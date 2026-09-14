///| One contiguous counter interval requested from a peer, inclusive at both

///|
/// ends. Replica logs naturally map this range to dots.
pub(all) struct SyncRange {
  replica : String
  from_counter : Int
  to_counter : Int
} derive(Eq, Debug)

///|
/// Summary exchanged before anti-entropy transfer.
pub(all) struct ReplicaDigest {
  replica : String
  frontier : VersionVector
} derive(Eq, Debug)

///|
/// Validation failures for anti-entropy metadata.
pub(all) enum SyncError {
  EmptyDigestReplica
  InvalidSyncRange(String, Int, Int)
} derive(Eq, Debug)

///|
/// Construct a digest for one replica.
pub fn ReplicaDigest::new(
  replica : String,
  frontier : VersionVector,
) -> Result[ReplicaDigest, SyncError] {
  if replica.length() == 0 {
    Err(EmptyDigestReplica)
  } else {
    Ok({ replica, frontier })
  }
}

///|
/// Compute ranges present at the sender and missing at the receiver.
pub fn plan_sync(
  sender : VersionVector,
  receiver : VersionVector,
) -> Array[SyncRange] {
  let output : Array[SyncRange] = []
  for entry in sender.entries() {
    let known = receiver.counter(entry.replica)
    if entry.counter > known {
      output.push({
        replica: entry.replica,
        from_counter: known + 1,
        to_counter: entry.counter,
      })
    }
  }
  output
}

///|
/// Validate a range received from an untrusted peer.
pub fn SyncRange::new(
  replica : String,
  from_counter : Int,
  to_counter : Int,
) -> Result[SyncRange, SyncError] {
  if replica.length() == 0 {
    Err(EmptyDigestReplica)
  } else if from_counter <= 0 || to_counter < from_counter {
    Err(InvalidSyncRange(replica, from_counter, to_counter))
  } else {
    Ok({ replica, from_counter, to_counter })
  }
}

///|
/// Number of dots represented by a range.
pub fn SyncRange::length(self : SyncRange) -> Int {
  self.to_counter - self.from_counter + 1
}

///|
/// Test whether a dot belongs to a requested range.
pub fn SyncRange::contains(self : SyncRange, dot : Dot) -> Bool {
  dot.replica == self.replica &&
  dot.counter >= self.from_counter &&
  dot.counter <= self.to_counter
}

///| Select log entries requested by anti-entropy ranges while preserving the

///|
/// original causal release order.
pub fn select_sync_entries(
  log : OperationLog,
  ranges : Array[SyncRange],
) -> Array[LoggedOperation] {
  let output : Array[LoggedOperation] = []
  for entry in log.entries() {
    let dot = Dot::new(entry.operation.replica, entry.operation.counter).unwrap()
    for range in ranges {
      if range.contains(dot) {
        output.push(entry)
        break
      }
    }
  }
  output
}

///|
/// Summarize a batch as a frontier. Useful after applying a complete response.
pub fn sync_batch_frontier(entries : Array[LoggedOperation]) -> VersionVector {
  let vectors : Array[VectorEntry] = []
  for entry in entries {
    vectors.push({
      replica: entry.operation.replica,
      counter: entry.operation.counter,
    })
  }
  VersionVector::from_entries(vectors).unwrap()
}

///|
/// Report gaps in a transferred batch relative to the requested ranges.
pub fn missing_sync_dots(
  entries : Array[LoggedOperation],
  ranges : Array[SyncRange],
) -> DotSet {
  let mut missing = DotSet::new()
  for range in ranges {
    for counter in range.from_counter..<=range.to_counter {
      let expected = Dot::new(range.replica, counter).unwrap()
      let mut found = false
      for entry in entries {
        if entry.operation.replica == range.replica &&
          entry.operation.counter == counter {
          found = true
          break
        }
      }
      if !found {
        missing = missing.add(expected)
      }
    }
  }
  missing
}

///|
/// Estimate transfer size as number of operations, without reading the log.
pub fn sync_operation_count(ranges : Array[SyncRange]) -> Int {
  let mut total = 0
  for range in ranges {
    total = total + range.length()
  }
  total
}
