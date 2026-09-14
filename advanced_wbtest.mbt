///|
test "dot validates identity and ordering" {
  let first = Dot::new("alpha", 1).unwrap()
  let second = Dot::new("alpha", 2).unwrap()
  let remote = Dot::new("beta", 1).unwrap()
  assert_true(first.compare(second) < 0)
  assert_true(second.compare(remote) > 0)
  assert_eq(Dot::new("", 1), Err(EmptyDotReplica))
  assert_eq(Dot::new("alpha", 0), Err(NonPositiveDotCounter(0)))
}

///|
test "dot coverage follows version vector counters" {
  let dot = Dot::new("alpha", 2).unwrap()
  let one = VersionVector::new().increment("alpha").unwrap()
  let two = one.increment("alpha").unwrap()
  assert_true(!dot.is_covered_by(one))
  assert_true(dot.is_covered_by(two))
  assert_eq(dot.context().counter("alpha"), 2)
}

///|
test "dot set normalizes union intersection and difference" {
  let a1 = Dot::new("alpha", 1).unwrap()
  let a2 = Dot::new("alpha", 2).unwrap()
  let b1 = Dot::new("beta", 1).unwrap()
  let left = DotSet::from_array([a2, a1, a1]).unwrap()
  let right = DotSet::from_array([a2, b1]).unwrap()
  assert_eq(left.length(), 2)
  assert_eq(left.union(right).length(), 3)
  assert_eq(left.intersection(right).dots(), [a2])
  assert_eq(left.difference(right).dots(), [a1])
}

///|
test "dot set partitions at a causal frontier" {
  let dots = DotSet::from_array([
    Dot::new("alpha", 1).unwrap(),
    Dot::new("alpha", 2).unwrap(),
    Dot::new("beta", 1).unwrap(),
  ]).unwrap()
  let frontier = VersionVector::from_entries([{ replica: "alpha", counter: 1 }]).unwrap()
  assert_eq(dots.covered(frontier).length(), 1)
  assert_eq(dots.after(frontier).length(), 2)
  assert_eq(dots.frontier().counter("alpha"), 2)
  assert_eq(dots.frontier().counter("beta"), 1)
}

///|
test "dot set reports subset and next replica counter" {
  let first = Dot::new("alpha", 1).unwrap()
  let third = Dot::new("alpha", 3).unwrap()
  let small = DotSet::new().add(first)
  let large = small.add(third)
  assert_true(small.is_subset_of(large))
  assert_true(!large.is_subset_of(small))
  assert_eq(large.next_counter("alpha"), 4)
  assert_eq(large.next_counter("beta"), 1)
}

///|
test "observed remove set keeps concurrent add" {
  let base = ObservedRemoveSet::new().add("alpha", "note").unwrap()
  let removed = base.remove("note")
  let concurrent = ObservedRemoveSet::new().add("beta", "note").unwrap()
  let merged = removed.merge(concurrent)
  assert_true(merged.contains("note"))
  assert_eq(merged.values(), ["note"])
}

///|
test "observed remove set suppresses observed add" {
  let state = ObservedRemoveSet::new().add("alpha", "draft").unwrap()
  let removed = state.remove("draft")
  let merged = state.merge(removed)
  assert_true(!merged.contains("draft"))
  assert_eq(merged.removals().length(), 1)
}

///|
test "observed remove set merge is idempotent" {
  let state = ObservedRemoveSet::new()
    .add("alpha", "one")
    .unwrap()
    .add("alpha", "two")
    .unwrap()
  let merged = state.merge(state)
  assert_eq(merged.values().length(), 2)
  assert_eq(merged.context().counter("alpha"), 2)
}

///|
test "observed remove tombstones compact at stable frontier" {
  let state = ObservedRemoveSet::new().add("alpha", "gone").unwrap()
  let removed = state.remove("gone")
  assert_eq(removed.removals().length(), 1)
  let compacted = removed.compact(state.context())
  assert_eq(compacted.removals().length(), 0)
}

///|
test "pn counter merges independent increments and decrements" {
  let alpha = PnCounter::new().increment_by("alpha", 5).unwrap()
  let beta = PnCounter::new().decrement_by("beta", 2).unwrap()
  let merged = alpha.merge(beta)
  assert_eq(merged.value(), 3)
  assert_eq(merged.positive_of("alpha"), 5)
  assert_eq(merged.negative_of("beta"), 2)
}

///|
test "pn counter merge is idempotent and monotonic" {
  let first = PnCounter::new().increment("alpha").unwrap()
  let second = first.increment("alpha").unwrap()
  assert_true(first.is_included_in(second))
  assert_true(!second.is_included_in(first))
  assert_eq(second.merge(second), second)
}

///|
test "pn counter delta carries newer components" {
  let peer = PnCounter::new().increment_by("alpha", 2).unwrap()
  let current = peer
    .increment_by("alpha", 3)
    .unwrap()
    .decrement("beta")
    .unwrap()
  let delta = current.delta_since(peer)
  assert_eq(delta.components().length(), 2)
  assert_eq(peer.merge(delta), current)
}

///|
test "pn counter validates restored components" {
  let restored = PnCounter::from_components([
    { replica: "alpha", positive: 2, negative: 1 },
    { replica: "alpha", positive: 5, negative: 0 },
  ]).unwrap()
  assert_eq(restored.positive_of("alpha"), 5)
  assert_eq(restored.negative_of("alpha"), 1)
  assert_eq(
    PnCounter::new().increment_by("alpha", -1),
    Err(NegativeCounterAmount(-1)),
  )
}

///|
test "lww register selects later hybrid timestamp" {
  let early_stamp = HlcTimestamp::new(10, 0, "alpha").unwrap()
  let late_stamp = HlcTimestamp::new(11, 0, "beta").unwrap()
  let early = LastWriterWinsRegister::new("draft", "alpha", early_stamp).unwrap()
  let late = LastWriterWinsRegister::new("final", "beta", late_stamp).unwrap()
  assert_eq(early.merge(late).value(), "final")
  assert_true(late.dominates(early))
}

///|
test "lww register tie breaker converges" {
  let stamp = HlcTimestamp::new(10, 0, "clock").unwrap()
  let alpha = LastWriterWinsRegister::new("one", "alpha", stamp).unwrap()
  let beta = LastWriterWinsRegister::new("two", "beta", stamp).unwrap()
  assert_eq(alpha.merge(beta), beta.merge(alpha))
  assert_eq(alpha.merge(beta).writer(), "alpha")
}

///|
test "anti entropy plans only missing suffixes" {
  let sender = VersionVector::from_entries([
    { replica: "alpha", counter: 5 },
    { replica: "beta", counter: 2 },
  ]).unwrap()
  let receiver = VersionVector::from_entries([{ replica: "alpha", counter: 3 }]).unwrap()
  let ranges = plan_sync(sender, receiver)
  assert_eq(ranges.length(), 2)
  assert_eq(ranges[0].from_counter, 4)
  assert_eq(ranges[0].to_counter, 5)
  assert_eq(sync_operation_count(ranges), 4)
}

///|
test "anti entropy selects requested operation entries" {
  let first = CausalOperation::new(
    "a1",
    "alpha",
    1,
    VersionVector::new(),
    "one",
  ).unwrap()
  let second = CausalOperation::new(
    "a2",
    "alpha",
    2,
    VersionVector::new().increment("alpha").unwrap(),
    "two",
  ).unwrap()
  let log = OperationLog::new().append([first, second], 10)
  let range = SyncRange::new("alpha", 2, 2).unwrap()
  let selected = select_sync_entries(log, [range])
  assert_eq(selected.length(), 1)
  assert_eq(selected[0].operation.id, "a2")
}

///|
test "anti entropy detects incomplete transfer" {
  let first = CausalOperation::new(
    "a1",
    "alpha",
    1,
    VersionVector::new(),
    "one",
  ).unwrap()
  let log = OperationLog::new().append([first], 10)
  let range = SyncRange::new("alpha", 1, 3).unwrap()
  let missing = missing_sync_dots(log.entries(), [range])
  assert_eq(missing.length(), 2)
  assert_true(missing.contains(Dot::new("alpha", 2).unwrap()))
}

///|
test "checkpoint plan separates replay suffix" {
  let first = CausalOperation::new(
    "a1",
    "alpha",
    1,
    VersionVector::new(),
    "one",
  ).unwrap()
  let second = CausalOperation::new(
    "a2",
    "alpha",
    2,
    VersionVector::new().increment("alpha").unwrap(),
    "two",
  ).unwrap()
  let log = OperationLog::new().append([first, second], 10)
  let frontier = VersionVector::new().increment("alpha").unwrap()
  let plan = plan_checkpoint(log, frontier, "snapshot", 20).unwrap()
  assert_eq(plan.checkpoint.operation_count(), 1)
  assert_eq(plan.replay_log.length(), 1)
  assert_eq(plan.checkpoint.state(), "snapshot")
}

///|
test "checkpoint replay validation advances frontier" {
  let checkpoint = CausalCheckpoint::new(
    VersionVector::new().increment("alpha").unwrap(),
    "state",
    1,
    10,
  ).unwrap()
  let operation = CausalOperation::new(
    "a2",
    "alpha",
    2,
    checkpoint.frontier(),
    "two",
  ).unwrap()
  let entries = OperationLog::new().append([operation], 11).entries()
  let result = validate_replay(checkpoint, entries).unwrap()
  assert_eq(result.counter("alpha"), 2)
}

///|
test "checkpoint replay rejects a per replica gap" {
  let checkpoint = CausalCheckpoint::new(VersionVector::new(), "state", 0, 10).unwrap()
  let operation = CausalOperation::new(
    "a2",
    "alpha",
    2,
    VersionVector::new(),
    "two",
  ).unwrap()
  let entries = OperationLog::new().append([operation], 11).entries()
  assert_eq(validate_replay(checkpoint, entries), Err(ReplayGap("alpha", 1, 2)))
}

///|
test "membership lifecycle updates active replica set" {
  let view = MembershipView::new().join("alpha").unwrap().join("beta").unwrap()
  assert_eq(view.active_replicas().length(), 2)
  let retired = view.retire("beta").unwrap()
  assert_eq(retired.active_replicas(), ["alpha"])
  assert_eq(retired.retired_replicas(), ["beta"])
  let active = retired.reactivate("beta").unwrap()
  assert_true(active.is_active("beta"))
}

///|
test "membership merge prefers later generation" {
  let base = MembershipView::new().join("alpha").unwrap()
  let retired = base.retire("alpha").unwrap()
  assert_eq(base.merge(retired), retired)
  assert_true(!base.merge(retired).is_active("alpha"))
}

///|
test "membership creates stability tracker for active replicas" {
  let view = MembershipView::new()
    .join("alpha")
    .unwrap()
    .join("beta")
    .unwrap()
    .retire("beta")
    .unwrap()
  let tracker = view.stability_tracker().unwrap()
  assert_eq(
    tracker
    .observe("alpha", VersionVector::new().increment("alpha").unwrap())
    .unwrap()
    .stable_frontier()
    .unwrap()
    .counter("alpha"),
    1,
  )
}

///|
test "replication batch validates duplicate identity" {
  let operation = CausalOperation::new(
    "a1",
    "alpha",
    1,
    VersionVector::new(),
    "one",
  ).unwrap()
  let frontier = VersionVector::new().increment("alpha").unwrap()
  assert_true(
    ReplicationBatch::new("alpha", "batch", [operation, operation], frontier)
    is Err(DuplicateBatchOperation("a1")),
  )
}

///|
test "replication batch releases operations in causal order" {
  let first = CausalOperation::new(
    "a1",
    "alpha",
    1,
    VersionVector::new(),
    "one",
  ).unwrap()
  let first_context = VersionVector::new().increment("alpha").unwrap()
  let second = CausalOperation::new("a2", "alpha", 2, first_context, "two").unwrap()
  let frontier = first_context.increment("alpha").unwrap()
  let batch = ReplicationBatch::new("alpha", "batch", [second, first], frontier).unwrap()
  let delivered = batch.deliver(CausalBuffer::new())
  assert_eq(delivered.released.length(), 2)
  assert_eq(delivered.released[0].id, "a1")
  assert_eq(delivered.released[1].id, "a2")
}

///|
test "causal map preserves concurrent values" {
  let alpha = CausalMap::new().put("title", "alpha", "one").unwrap()
  let beta = CausalMap::new().put("title", "beta", "two").unwrap()
  let merged = alpha.merge(beta)
  assert_eq(merged.get("title").unwrap().values().length(), 2)
}

///|
test "causal map observed remove hides old values" {
  let state = CausalMap::new().put("title", "alpha", "one").unwrap()
  let removed = state.remove("title").unwrap()
  assert_true(!state.merge(removed).contains_key("title"))
  assert_eq(removed.tombstones().length(), 1)
}

///|
test "causal map concurrent put survives remove" {
  let alpha = CausalMap::new().put("title", "alpha", "one").unwrap()
  let removed = alpha.remove("title").unwrap()
  let concurrent = CausalMap::new().put("title", "beta", "two").unwrap()
  let merged = removed.merge(concurrent)
  assert_true(merged.contains_key("title"))
  assert_eq(merged.get("title").unwrap().resolved().unwrap().value, "two")
}

///|
test "trace query finds causal roots leaves and path" {
  let simulator = Simulator::new(["alpha", "beta"], 0).unwrap()
  ignore(simulator.local_event("alpha", "start").unwrap())
  ignore(simulator.send("alpha", "beta", "sync", 1).unwrap())
  ignore(simulator.advance_to(1).unwrap())
  let analysis = TraceAnalysis::new(simulator.trace()).unwrap()
  let query = TraceQuery::new(analysis)
  assert_true(query.roots().length() > 0)
  assert_true(query.leaves().length() > 0)
  assert_true(query.critical_path().events.length() >= 2)
}

///|
test "trace query filters replica and physical time" {
  let simulator = Simulator::new(["alpha", "beta"], 10).unwrap()
  ignore(simulator.local_event("alpha", "one").unwrap())
  ignore(simulator.local_event("beta", "two").unwrap())
  let query = TraceQuery::new(TraceAnalysis::new(simulator.trace()).unwrap())
  assert_eq(query.by_replica("alpha").length(), 1)
  assert_eq(query.between_physical_times(10, 10).length(), 2)
  assert_eq(query.between_physical_times(11, 10).length(), 0)
}

///|
test "trace export creates portable rows and graph lines" {
  let simulator = Simulator::new(["alpha"], 0).unwrap()
  ignore(simulator.local_event("alpha", "write").unwrap())
  let analysis = TraceAnalysis::new(simulator.trace()).unwrap()
  let rows = trace_rows(simulator.trace())
  assert_eq(rows.length(), 1)
  assert_eq(rows[0].kind, "local")
  assert_eq(rows[0].detail, "write")
  assert_eq(trace_dot_lines(analysis)[0], "digraph causality {")
  assert_eq(trace_mermaid_lines(analysis)[0], "flowchart LR")
}

///|
test "clock diagnostics accepts readings within thresholds" {
  let policy = ClockDiagnosticPolicy::new(5, 20).unwrap()
  let diagnostics = ClockDiagnostics::new(policy, 100)
    .unwrap()
    .observe(97)
    .unwrap()
    .observe(110)
    .unwrap()
  assert_true(!diagnostics.has_anomaly())
  assert_eq(diagnostics.samples().length(), 2)
  assert_eq(diagnostics.last_reading(), 110)
}

///|
test "clock diagnostics records rollback and forward jump" {
  let policy = ClockDiagnosticPolicy::new(2, 10).unwrap()
  let diagnostics = ClockDiagnostics::new(policy, 100)
    .unwrap()
    .observe(90)
    .unwrap()
    .observe(120)
    .unwrap()
  assert_true(diagnostics.has_anomaly())
  assert_eq(diagnostics.rollback_count(), 1)
  assert_eq(diagnostics.forward_jump_count(), 1)
  assert_eq(diagnostics.anomalies().length(), 2)
  assert_true(diagnostics.samples()[0].status is ClockRollback(10))
  assert_true(diagnostics.samples()[1].status is ClockForwardJump(30))
}

///|
test "clock diagnostics reset keeps comparison baseline" {
  let policy = ClockDiagnosticPolicy::new(0, 5).unwrap()
  let diagnostics = ClockDiagnostics::new(policy, 10)
    .unwrap()
    .observe(20)
    .unwrap()
    .reset()
  assert_eq(diagnostics.samples().length(), 0)
  assert_eq(diagnostics.forward_jump_count(), 0)
  assert_eq(diagnostics.last_reading(), 20)
  let next = diagnostics.observe(19).unwrap()
  assert_eq(next.rollback_count(), 1)
}

///|
test "clock diagnostics rejects invalid policy and reading" {
  assert_eq(
    ClockDiagnosticPolicy::new(-1, 5),
    Err(NegativeRollbackThreshold(-1)),
  )
  let policy = ClockDiagnosticPolicy::new(1, 5).unwrap()
  assert_true(
    ClockDiagnostics::new(policy, -1) is Err(NegativeClockReading(-1)),
  )
}

///|
test "vector metrics find common history and distance" {
  let left = VersionVector::from_entries([
    { replica: "alpha", counter: 5 },
    { replica: "beta", counter: 2 },
  ]).unwrap()
  let right = VersionVector::from_entries([
    { replica: "alpha", counter: 3 },
    { replica: "gamma", counter: 4 },
  ]).unwrap()
  let common = common_frontier(left, right)
  assert_eq(common.counter("alpha"), 3)
  assert_eq(common.counter("beta"), 0)
  assert_eq(vector_distance(left, right), 8)
  assert_eq(events_missing_on_right(left, right), 4)
  assert_eq(replicas_ahead(left, right), ["alpha", "beta"])
}

///|
test "vector metrics report equality and component differences" {
  let first = VersionVector::new().increment("alpha").unwrap()
  let equal = VersionVector::from_entries([{ replica: "alpha", counter: 1 }]).unwrap()
  let later = equal.increment("beta").unwrap()
  assert_true(same_frontier(first, equal))
  assert_true(!same_frontier(first, later))
  let differences = vector_differences(first, later)
  assert_eq(differences.length(), 1)
  assert_eq(differences[0].replica, "beta")
}

///|
test "operation log append preserves previous value" {
  let empty = OperationLog::new()
  let operation = CausalOperation::new(
    "a1",
    "alpha",
    1,
    VersionVector::new(),
    "one",
  ).unwrap()
  let appended = empty.append([operation], 10)
  assert_eq(empty.length(), 0)
  assert_eq(appended.length(), 1)
}

///|
test "causal buffer offer preserves previous pending array" {
  let empty = CausalBuffer::new()
  let operation = CausalOperation::new(
    "a2",
    "alpha",
    2,
    VersionVector::new().increment("alpha").unwrap(),
    "two",
  ).unwrap()
  let (queued, _) = empty.offer(operation)
  assert_eq(empty.pending().length(), 0)
  assert_eq(queued.pending().length(), 1)
}

///|
test "membership join preserves previous view" {
  let empty = MembershipView::new()
  let joined = empty.join("alpha").unwrap()
  assert_eq(empty.members().length(), 0)
  assert_eq(joined.members().length(), 1)
}

///|
test "clock observation preserves previous diagnostics" {
  let policy = ClockDiagnosticPolicy::new(0, 5).unwrap()
  let empty = ClockDiagnostics::new(policy, 10).unwrap()
  let observed = empty.observe(20).unwrap()
  assert_eq(empty.samples().length(), 0)
  assert_eq(observed.samples().length(), 1)
}

///|
test "causal map supports remove then re-add by same replica" {
  let initial = CausalMap::new().put("title", "alpha", "one").unwrap()
  let removed = initial.remove("title").unwrap()
  let readded = removed.put("title", "alpha", "two").unwrap()
  let merged = removed.merge(readded)
  assert_true(merged.contains_key("title"))
  assert_eq(merged.get("title").unwrap().resolved().unwrap().value, "two")
  assert_eq(merged.context().counter("alpha"), 2)
}

///|
test "trace layers are independent of input order" {
  let simulator = Simulator::new(["alpha", "beta"], 0).unwrap()
  ignore(simulator.send("alpha", "beta", "sync", 1).unwrap())
  ignore(simulator.advance_to(1).unwrap())
  let events = simulator.trace()
  let forward = TraceAnalysis::new(events).unwrap().layers()
  let reversed = TraceAnalysis::new([events[1], events[0]]).unwrap().layers()
  assert_eq(forward.length(), reversed.length())
  assert_eq(forward.length(), 2)
  assert_eq(reversed[0].events[0].sequence, events[0].sequence)
  assert_eq(reversed[1].events[0].sequence, events[1].sequence)
}

///|
test "replication batch counts a duplicate pending dot" {
  let dependency = VersionVector::new().increment("alpha").unwrap()
  let operation = CausalOperation::new("a2", "alpha", 2, dependency, "two").unwrap()
  let (pending, _) = CausalBuffer::new().offer(operation)
  let frontier = dependency.increment("alpha").unwrap()
  let batch = ReplicationBatch::new("alpha", "retry", [operation], frontier).unwrap()
  let delivery = batch.deliver(pending)
  assert_eq(delivery.accepted_count, 0)
  assert_eq(delivery.duplicate_count, 1)
  assert_eq(delivery.buffer.pending().length(), 1)
}

///|
test "replay validation rejects missing causal dependency" {
  let checkpoint = CausalCheckpoint::new(VersionVector::new(), "state", 0, 10).unwrap()
  let dependency = VersionVector::new().increment("beta").unwrap()
  let operation = CausalOperation::new("a1", "alpha", 1, dependency, "one").unwrap()
  let entries = OperationLog::new().append([operation], 11).entries()
  assert_eq(
    validate_replay(checkpoint, entries),
    Err(ReplayDependencyMissing("a1")),
  )
}

///|
test "public collection accessors return defensive arrays" {
  let vector = VersionVector::new().increment("alpha").unwrap()
  let entries = vector.entries()
  entries.push({ replica: "beta", counter: 9 })
  assert_eq(vector.counter("beta"), 0)
  let dots = DotSet::new().add(Dot::new("alpha", 1).unwrap())
  let exposed = dots.dots()
  exposed.push(Dot::new("beta", 1).unwrap())
  assert_eq(dots.length(), 1)
}
