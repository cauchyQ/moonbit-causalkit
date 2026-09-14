///|
/// Per-replica difference between two causal frontiers.
pub(all) struct VectorDifference {
  replica : String
  left_counter : Int
  right_counter : Int
} derive(Eq, Debug)

///|
/// Component differences, including replicas present on only one side.
pub fn vector_differences(
  left : VersionVector,
  right : VersionVector,
) -> Array[VectorDifference] {
  let output : Array[VectorDifference] = []
  for entry in left.entries() {
    let remote = right.counter(entry.replica)
    if entry.counter != remote {
      output.push({
        replica: entry.replica,
        left_counter: entry.counter,
        right_counter: remote,
      })
    }
  }
  for entry in right.entries() {
    if left.counter(entry.replica) == 0 && entry.counter != 0 {
      output.push({
        replica: entry.replica,
        left_counter: 0,
        right_counter: entry.counter,
      })
    }
  }
  output
}

///|
/// Component-wise minimum, representing history known by both sides.
pub fn common_frontier(
  left : VersionVector,
  right : VersionVector,
) -> VersionVector {
  let entries : Array[VectorEntry] = []
  for entry in left.entries() {
    let remote = right.counter(entry.replica)
    let minimum = if entry.counter < remote { entry.counter } else { remote }
    if minimum > 0 {
      entries.push({ replica: entry.replica, counter: minimum })
    }
  }
  VersionVector::from_entries(entries).unwrap()
}

///|
/// Number of events present on the left but absent on the right.
pub fn events_missing_on_right(
  left : VersionVector,
  right : VersionVector,
) -> Int {
  let mut total = 0
  for entry in left.entries() {
    let remote = right.counter(entry.replica)
    if entry.counter > remote {
      total = total + entry.counter - remote
    }
  }
  total
}

///|
/// Symmetric Manhattan distance between causal frontiers.
pub fn vector_distance(left : VersionVector, right : VersionVector) -> Int {
  events_missing_on_right(left, right) + events_missing_on_right(right, left)
}

///|
/// Whether two frontiers have exactly the same replica counters.
pub fn same_frontier(left : VersionVector, right : VersionVector) -> Bool {
  left.compare(right) == Equal
}

///|
/// Replicas on which the left frontier is ahead.
pub fn replicas_ahead(
  left : VersionVector,
  right : VersionVector,
) -> Array[String] {
  let output : Array[String] = []
  for entry in left.entries() {
    if entry.counter > right.counter(entry.replica) {
      output.push(entry.replica)
    }
  }
  output
}
