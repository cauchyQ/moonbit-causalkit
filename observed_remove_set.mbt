///|
/// One visible value and the add dots that currently support it.
pub(all) struct ObservedValue {
  value : String
  additions : DotSet
} derive(Eq, Debug)

///| An observed-remove set. Concurrent add wins over a remove that did not

///|
/// observe it; a remove records only dots visible in its local state.
pub struct ObservedRemoveSet {
  values : Array[ObservedValue]
  removals : DotSet
  context : VersionVector
} derive(Eq, Debug)

///|
/// Mutation errors at the OR-Set boundary.
pub(all) enum ObservedRemoveError {
  EmptySetReplica
} derive(Eq, Debug)

///|
/// Create an empty OR-Set.
pub fn ObservedRemoveSet::new() -> ObservedRemoveSet {
  { values: [], removals: DotSet::new(), context: VersionVector::new() }
}

///|
/// Current causal context.
pub fn ObservedRemoveSet::context(self : ObservedRemoveSet) -> VersionVector {
  self.context
}

///|
/// Tombstones retained for state-based merge safety.
pub fn ObservedRemoveSet::removals(self : ObservedRemoveSet) -> DotSet {
  self.removals
}

///|
/// Visible value records and their live add dots.
pub fn ObservedRemoveSet::entries(
  self : ObservedRemoveSet,
) -> Array[ObservedValue] {
  let output : Array[ObservedValue] = []
  for entry in self.values {
    output.push(entry)
  }
  output
}

///|
/// Render the set as distinct values.
pub fn ObservedRemoveSet::values(self : ObservedRemoveSet) -> Array[String] {
  let output : Array[String] = []
  for entry in self.values {
    if entry.additions.length() > 0 {
      output.push(entry.value)
    }
  }
  output
}

///|
/// Test visible membership.
pub fn ObservedRemoveSet::contains(
  self : ObservedRemoveSet,
  value : String,
) -> Bool {
  for entry in self.values {
    if entry.value == value && entry.additions.length() > 0 {
      return true
    }
  }
  false
}

///|
/// Add a value with a fresh local dot.
pub fn ObservedRemoveSet::add(
  self : ObservedRemoveSet,
  replica : String,
  value : String,
) -> Result[ObservedRemoveSet, ObservedRemoveError] {
  if replica.length() == 0 {
    return Err(EmptySetReplica)
  }
  let context = self.context.increment(replica).unwrap()
  let dot = Dot::new(replica, context.counter(replica)).unwrap()
  let values : Array[ObservedValue] = []
  let mut found = false
  for entry in self.values {
    if entry.value == value {
      values.push({ value, additions: entry.additions.add(dot) })
      found = true
    } else {
      values.push(entry)
    }
  }
  if !found {
    values.push({ value, additions: DotSet::new().add(dot) })
  }
  Ok({ values, removals: self.removals, context })
}

///|
/// Remove all add dots for a value that this replica has observed.
pub fn ObservedRemoveSet::remove(
  self : ObservedRemoveSet,
  value : String,
) -> ObservedRemoveSet {
  let values : Array[ObservedValue] = []
  let mut removals = self.removals
  for entry in self.values {
    if entry.value == value {
      removals = removals.union(entry.additions)
    } else {
      values.push(entry)
    }
  }
  { values, removals, context: self.context }
}

///| Merge two state replicas. Adds named by either tombstone are suppressed;

///|
/// unseen concurrent additions remain visible.
pub fn ObservedRemoveSet::merge(
  self : ObservedRemoveSet,
  other : ObservedRemoveSet,
) -> ObservedRemoveSet {
  let removals = self.removals.union(other.removals)
  let mut values : Array[ObservedValue] = []
  for entry in self.values {
    values = orset_merge_entry(values, entry)
  }
  for entry in other.values {
    values = orset_merge_entry(values, entry)
  }
  let visible : Array[ObservedValue] = []
  for entry in values {
    let additions = entry.additions.difference(removals)
    if additions.length() > 0 {
      visible.push({ value: entry.value, additions })
    }
  }
  { values: visible, removals, context: self.context.merge(other.context) }
}

///| Drop tombstones that every replica has acknowledged. Callers must supply a

///|
/// stable frontier from StabilityTracker; an arbitrary vector is unsafe.
pub fn ObservedRemoveSet::compact(
  self : ObservedRemoveSet,
  stable_frontier : VersionVector,
) -> ObservedRemoveSet {
  {
    values: self.values,
    removals: self.removals.after(stable_frontier),
    context: self.context,
  }
}

///|
fn orset_merge_entry(
  values : Array[ObservedValue],
  candidate : ObservedValue,
) -> Array[ObservedValue] {
  let output : Array[ObservedValue] = []
  let mut found = false
  for entry in values {
    if entry.value == candidate.value {
      output.push({
        value: entry.value,
        additions: entry.additions.union(candidate.additions),
      })
      found = true
    } else {
      output.push(entry)
    }
  }
  if !found {
    output.push(candidate)
  }
  output
}
