///|
/// One replica's acknowledgement of the causal history it has durably seen.
pub(all) struct ReplicaAcknowledgement {
  replica : String
  context : VersionVector
} derive(Debug)

///| Tracks per-replica acknowledgements and computes a stable causal frontier.

///|
/// A counter is stable only after every configured replica has acknowledged it.
pub(all) struct StabilityTracker {
  replicas : Array[String]
  acknowledgements : Array[ReplicaAcknowledgement]
} derive(Debug)

///|
/// Construction and update errors for acknowledgement tracking.
pub(all) enum StabilityError {
  EmptyReplicaId
  DuplicateReplica(String)
  UnknownReplica(String)
} derive(Eq, Debug)

///|
/// Define the members whose acknowledgement is required for stability.
pub fn StabilityTracker::new(
  replicas : Array[String],
) -> Result[StabilityTracker, StabilityError] {
  for left in 0..<replicas.length() {
    if replicas[left].length() == 0 {
      return Err(EmptyReplicaId)
    }
    for right in (left + 1)..<replicas.length() {
      if replicas[left] == replicas[right] {
        return Err(DuplicateReplica(replicas[left]))
      }
    }
  }
  Ok({ replicas, acknowledgements: [] })
}

///|
/// Record or replace one replica's latest acknowledgement.
pub fn StabilityTracker::observe(
  self : StabilityTracker,
  replica : String,
  context : VersionVector,
) -> Result[StabilityTracker, StabilityError] {
  if !contains(self.replicas, replica) {
    return Err(UnknownReplica(replica))
  }
  let updated : Array[ReplicaAcknowledgement] = []
  let mut replaced = false
  for acknowledgement in self.acknowledgements {
    if acknowledgement.replica == replica {
      updated.push({ replica, context })
      replaced = true
    } else {
      updated.push(acknowledgement)
    }
  }
  if !replaced {
    updated.push({ replica, context })
  }
  Ok({ replicas: self.replicas, acknowledgements: updated })
}

///|
/// Return acknowledgements received so far.
pub fn StabilityTracker::acknowledgements(
  self : StabilityTracker,
) -> Array[ReplicaAcknowledgement] {
  self.acknowledgements
}

///| Compute the component-wise minimum acknowledged counter. `None` means at

///| least one configured replica has not reported yet, so pruning would be

///|
/// unsafe. Missing counters are treated as zero.
pub fn StabilityTracker::stable_frontier(
  self : StabilityTracker,
) -> VersionVector? {
  if self.acknowledgements.length() != self.replicas.length() {
    return None
  }
  let keys : Array[String] = []
  for acknowledgement in self.acknowledgements {
    for entry in acknowledgement.context.entries() {
      if !contains(keys, entry.replica) {
        keys.push(entry.replica)
      }
    }
  }
  let entries : Array[VectorEntry] = []
  for key in keys {
    let mut minimum = -1
    for acknowledgement in self.acknowledgements {
      let counter = acknowledgement.context.counter(key)
      if minimum < 0 || counter < minimum {
        minimum = counter
      }
    }
    entries.push({ replica: key, counter: minimum })
  }
  match VersionVector::from_entries(entries) {
    Ok(frontier) => Some(frontier)
    Err(_) => None
  }
}

///|
/// Check whether an event context is acknowledged by every member.
pub fn StabilityTracker::is_stable(
  self : StabilityTracker,
  context : VersionVector,
) -> Bool {
  match self.stable_frontier() {
    Some(frontier) => context.happens_before(frontier)
    None => false
  }
}

///|
fn contains(values : Array[String], candidate : String) -> Bool {
  for value in values {
    if value == candidate {
      return true
    }
  }
  false
}
