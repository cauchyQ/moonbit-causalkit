///| The clock must stay monotonic when an OS or simulated physical clock moves

///|
/// backwards.
test "HLC tick keeps monotonic order across clock rollback" {
  let clock = HlcClock::new("alpha", 100).unwrap()
  let first = clock.tick(100)
  let second = clock.tick(90)
  assert_eq(first.to_string(), "100:1:alpha")
  assert_eq(second.to_string(), "100:2:alpha")
  assert_true(first.precedes_or_equals(second))
}

///|
/// Receiving a future timestamp must advance beyond the remote logical state.
test "HLC receive advances beyond equal physical remote timestamp" {
  let clock = HlcClock::new("beta", 10).unwrap()
  let remote = HlcTimestamp::new(25, 3, "alpha").unwrap()
  let received = clock.receive(remote, 20)
  assert_eq(received.to_string(), "25:4:beta")
  assert_true(remote.precedes_or_equals(received))
}

///| Independent local writes are concurrent; merging then incrementing creates

///|
/// a successor which is after both histories.
test "version vectors distinguish concurrency from causality" {
  let alpha = VersionVector::new().increment("alpha").unwrap()
  let beta = VersionVector::new().increment("beta").unwrap()
  assert_eq(alpha.compare(beta), Concurrent)
  let merged = alpha.merge(beta).increment("alpha").unwrap()
  assert_eq(alpha.compare(merged), Before)
  assert_eq(beta.compare(merged), Before)
}

///| Duplicate serialized entries should normalize to the greatest known

///|
/// counter instead of depending on decode order.
test "version vector normalizes duplicate replica counters" {
  let vector = VersionVector::from_entries([
    { replica: "alpha", counter: 2 },
    { replica: "alpha", counter: 7 },
    { replica: "beta", counter: 1 },
  ]).unwrap()
  assert_eq(vector.counter("alpha"), 7)
  assert_eq(vector.counter("beta"), 1)
}

///| A delayed message creates one send and one receive event and transfers the

///|
/// source's causal history to the target.
test "simulator delivers delayed messages with merged context" {
  let simulator = Simulator::new(["alpha", "beta"], 0).unwrap()
  ignore(simulator.local_event("alpha", "write").unwrap())
  ignore(simulator.send("alpha", "beta", "replicate", 5).unwrap())
  assert_eq(simulator.pending().length(), 1)
  let delivered = simulator.advance_to(5).unwrap()
  assert_eq(delivered.length(), 1)
  assert_eq(simulator.pending().length(), 0)
  assert_true(
    simulator
    .vector_of("alpha")
    .unwrap()
    .happens_before(simulator.vector_of("beta").unwrap()),
  )
}

///| A partitioned target holds due messages, then receives them when brought

///|
/// online without changing message order or delivery time.
test "simulator holds due message while target is offline" {
  let simulator = Simulator::new(["alpha", "beta"], 0).unwrap()
  ignore(simulator.set_online("beta", false).unwrap())
  ignore(simulator.send("alpha", "beta", "queued", 1).unwrap())
  assert_eq(simulator.advance_to(1).unwrap().length(), 0)
  assert_eq(simulator.pending().length(), 1)
  ignore(simulator.set_online("beta", true).unwrap())
  assert_eq(simulator.advance_to(1).unwrap().length(), 1)
  assert_eq(simulator.pending().length(), 0)
}

///|
/// Independent replicas keep both values instead of hiding a real conflict.
test "multi-value register preserves concurrent writes" {
  let alpha = MultiValueRegister::new().write("alpha", "blue").unwrap()
  let beta = MultiValueRegister::new().write("beta", "green").unwrap()
  let merged = alpha.merge(beta)
  assert_eq(merged.values().length(), 2)
  assert_eq(merged.resolved(), None)
}

///| A write based on merged conflict context is after both alternatives and

///|
/// therefore resolves them to a single successor value.
test "multi-value register newer write resolves observed conflict" {
  let alpha = MultiValueRegister::new().write("alpha", "blue").unwrap()
  let beta = MultiValueRegister::new().write("beta", "green").unwrap()
  let resolved = alpha.merge(beta).write("alpha", "teal").unwrap()
  assert_eq(resolved.values().length(), 1)
  assert_eq(resolved.resolved().unwrap().value, "teal")
}

///|
/// Receiving the same remote state twice is idempotent.
test "multi-value register merge is idempotent" {
  let current = MultiValueRegister::new().write("alpha", "draft").unwrap()
  let remote = MultiValueRegister::new().write("beta", "review").unwrap()
  let once = current.merge(remote)
  let twice = once.merge(remote)
  assert_eq(once.values().length(), twice.values().length())
}

///|
/// A simulated send followed by delivery has one direct causal edge.
test "trace analysis finds direct send-to-receive predecessor" {
  let simulator = Simulator::new(["alpha", "beta"], 0).unwrap()
  ignore(simulator.send("alpha", "beta", "sync", 1).unwrap())
  ignore(simulator.advance_to(1).unwrap())
  let analysis = TraceAnalysis::new(simulator.trace()).unwrap()
  assert_eq(analysis.direct_edges().length(), 1)
  assert_eq(analysis.direct_edges()[0].earlier.replica, "alpha")
  assert_eq(analysis.direct_edges()[0].later.replica, "beta")
}

///|
/// Independent writes occupy the first layer and are reported as concurrent.
test "trace analysis reports concurrent local events" {
  let simulator = Simulator::new(["alpha", "beta"], 0).unwrap()
  ignore(simulator.local_event("alpha", "one").unwrap())
  ignore(simulator.local_event("beta", "two").unwrap())
  let analysis = TraceAnalysis::new(simulator.trace()).unwrap()
  assert_eq(analysis.concurrent_pairs().length(), 1)
  assert_eq(analysis.layers().length(), 1)
  assert_eq(analysis.layers()[0].events.length(), 2)
}

///|
/// A stable frontier is unavailable until every configured member reports.
test "stability tracker waits for every replica acknowledgement" {
  let tracker = StabilityTracker::new(["alpha", "beta"]).unwrap()
  let alpha = VersionVector::new().increment("alpha").unwrap()
  let partial = tracker.observe("alpha", alpha).unwrap()
  assert_eq(partial.stable_frontier(), None)
  let beta = alpha.increment("beta").unwrap()
  let complete = partial.observe("beta", beta).unwrap()
  assert_eq(complete.stable_frontier().unwrap().counter("alpha"), 1)
  assert_eq(complete.stable_frontier().unwrap().counter("beta"), 0)
}

///|
/// Later acknowledgements advance the stable component-wise minimum.
test "stability tracker computes a component-wise minimum" {
  let alpha = VersionVector::from_entries([
    { replica: "alpha", counter: 5 },
    { replica: "beta", counter: 2 },
  ]).unwrap()
  let beta = VersionVector::from_entries([
    { replica: "alpha", counter: 3 },
    { replica: "beta", counter: 7 },
  ]).unwrap()
  let tracker = StabilityTracker::new(["alpha", "beta"])
    .unwrap()
    .observe("alpha", alpha)
    .unwrap()
    .observe("beta", beta)
    .unwrap()
  let stable = tracker.stable_frontier().unwrap()
  assert_eq(stable.counter("alpha"), 3)
  assert_eq(stable.counter("beta"), 2)
}

///| An out-of-order operation remains queued until its predecessor arrives;

///|
/// the buffer then releases both operations in causal order.
test "causal buffer releases out-of-order replica operations" {
  let first = CausalOperation::new(
    "alpha-1",
    "alpha",
    1,
    VersionVector::new(),
    "first",
  ).unwrap()
  let prerequisite = VersionVector::new().increment("alpha").unwrap()
  let second = CausalOperation::new(
    "alpha-2", "alpha", 2, prerequisite, "second",
  ).unwrap()
  let buffer = CausalBuffer::new()
  let (queued, first_release) = buffer.offer(second)
  assert_eq(first_release.length(), 0)
  assert_eq(queued.pending().length(), 1)
  let (released, applied) = queued.offer(first)
  assert_eq(applied.length(), 2)
  assert_eq(applied[0].id, "alpha-1")
  assert_eq(applied[1].id, "alpha-2")
  assert_eq(released.applied().counter("alpha"), 2)
}

///|
/// Network retransmission must not leave a duplicate dot permanently queued.
test "causal buffer deduplicates pending operations" {
  let operation = CausalOperation::new(
    "alpha-2",
    "alpha",
    2,
    VersionVector::new().increment("alpha").unwrap(),
    "second",
  ).unwrap()
  let (queued, _) = CausalBuffer::new().offer(operation)
  let (deduplicated, released) = queued.offer(operation)
  assert_eq(released.length(), 0)
  assert_eq(deduplicated.pending().length(), 1)
}

///|
/// Compaction returns a checkpointable prefix and preserves the replay suffix.
test "operation log compacts only stable prefix" {
  let first = CausalOperation::new(
    "alpha-1",
    "alpha",
    1,
    VersionVector::new(),
    "first",
  ).unwrap()
  let second = CausalOperation::new(
    "alpha-2",
    "alpha",
    2,
    VersionVector::new().increment("alpha").unwrap(),
    "second",
  ).unwrap()
  let log = OperationLog::new().append([first, second], 10)
  let frontier = VersionVector::new().increment("alpha").unwrap()
  let (stable, remaining) = log.compact(frontier)
  assert_eq(stable.length(), 1)
  assert_eq(stable[0].operation.id, "alpha-1")
  assert_eq(remaining.length(), 1)
  assert_eq(remaining.entries()[0].operation.id, "alpha-2")
  assert_eq(log.length(), 2)
}
