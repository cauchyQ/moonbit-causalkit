///|
/// One replica counter in a version vector.
pub(all) struct VectorEntry {
  replica : String
  counter : Int
} derive(Eq, Debug)

///| Version vectors represent causality, unlike an HLC's total ordering.

///|
/// Entries are kept in first-observed order to make traces deterministic.
pub struct VersionVector {
  entries : Array[VectorEntry]
} derive(Eq, Debug)

///|
/// The causal relation between two version vectors.
pub(all) enum CausalOrder {
  Before
  After
  Equal
  Concurrent
} derive(Eq, Debug)

///|
/// Create an empty vector.
pub fn VersionVector::new() -> VersionVector {
  { entries: [] }
}

///| Build a vector from counters, validating replica names and normalizing

///|
/// duplicate entries by keeping their greatest counter.
pub fn VersionVector::from_entries(
  entries : Array[VectorEntry],
) -> Result[VersionVector, VectorError] {
  let mut normalized : Array[VectorEntry] = []
  for entry in entries {
    if entry.replica.length() == 0 {
      return Err(EmptyReplicaId)
    }
    if entry.counter < 0 {
      return Err(NegativeCounter(entry.replica, entry.counter))
    }
    normalized = upsert_max(normalized, entry)
  }
  Ok({ entries: normalized })
}

///|
/// Read a replica counter. Missing replicas have counter zero.
pub fn VersionVector::counter(self : VersionVector, replica : String) -> Int {
  for entry in self.entries {
    if entry.replica == replica {
      return entry.counter
    }
  }
  0
}

///|
/// Return a successor vector for one local event at `replica`.
pub fn VersionVector::increment(
  self : VersionVector,
  replica : String,
) -> Result[VersionVector, VectorError] {
  if replica.length() == 0 {
    Err(EmptyReplicaId)
  } else {
    let next = self.counter(replica) + 1
    Ok({ entries: upsert_max(self.entries, { replica, counter: next }) })
  }
}

///| Merge all observed counters. This does not create an event by itself;

///|
/// callers that receive a message should merge and then increment locally.
pub fn VersionVector::merge(
  self : VersionVector,
  other : VersionVector,
) -> VersionVector {
  let mut output = self.entries
  for entry in other.entries {
    output = upsert_max(output, entry)
  }
  { entries: output }
}

///| Compare two vectors. `Concurrent` means neither vector dominates the

///|
/// other, so an application needs a merge policy instead of arbitrary ordering.
pub fn VersionVector::compare(
  self : VersionVector,
  other : VersionVector,
) -> CausalOrder {
  let mut self_greater = false
  let mut other_greater = false
  for entry in self.entries {
    let remote = other.counter(entry.replica)
    if entry.counter > remote {
      self_greater = true
    } else if entry.counter < remote {
      other_greater = true
    }
  }
  for entry in other.entries {
    let current = self.counter(entry.replica)
    if entry.counter > current {
      other_greater = true
    } else if entry.counter < current {
      self_greater = true
    }
  }
  if self_greater && other_greater {
    Concurrent
  } else if self_greater {
    After
  } else if other_greater {
    Before
  } else {
    Equal
  }
}

///|
/// True when this vector is less than or equal to the other vector.
pub fn VersionVector::happens_before(
  self : VersionVector,
  other : VersionVector,
) -> Bool {
  match self.compare(other) {
    Before | Equal => true
    After | Concurrent => false
  }
}

///|
/// Return a copy of the normalized entries for inspection or serialization.
pub fn VersionVector::entries(self : VersionVector) -> Array[VectorEntry] {
  let output : Array[VectorEntry] = []
  for entry in self.entries {
    output.push(entry)
  }
  output
}

///|
/// Errors at the version-vector trust boundary.
pub(all) enum VectorError {
  EmptyReplicaId
  NegativeCounter(String, Int)
} derive(Eq, Debug)

///|
fn upsert_max(
  values : Array[VectorEntry],
  candidate : VectorEntry,
) -> Array[VectorEntry] {
  let output : Array[VectorEntry] = []
  let mut found = false
  for value in values {
    if value.replica == candidate.replica {
      let counter = if value.counter > candidate.counter {
        value.counter
      } else {
        candidate.counter
      }
      output.push({ replica: value.replica, counter })
      found = true
    } else {
      output.push(value)
    }
  }
  if !found {
    output.push(candidate)
  }
  output
}
