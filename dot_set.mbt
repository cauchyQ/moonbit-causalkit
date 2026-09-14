///|
/// A dot identifies exactly one event in one replica's monotonic sequence.
pub(all) struct Dot {
  replica : String
  counter : Int
} derive(Eq, Debug)

///|
/// Validation errors for dots and dot collections.
pub(all) enum DotError {
  EmptyDotReplica
  NonPositiveDotCounter(Int)
} derive(Eq, Debug)

///|
/// Construct a validated causal dot.
pub fn Dot::new(replica : String, counter : Int) -> Result[Dot, DotError] {
  if replica.length() == 0 {
    Err(EmptyDotReplica)
  } else if counter <= 0 {
    Err(NonPositiveDotCounter(counter))
  } else {
    Ok({ replica, counter })
  }
}

///|
/// Convert a dot to the version vector that covers only its own sequence.
pub fn Dot::context(self : Dot) -> VersionVector {
  VersionVector::from_entries([{ replica: self.replica, counter: self.counter }]).unwrap()
}

///|
/// Test whether a version vector has observed this dot.
pub fn Dot::is_covered_by(self : Dot, context : VersionVector) -> Bool {
  context.counter(self.replica) >= self.counter
}

///|
/// Deterministic MoonBit string ordering by replica and then counter.
pub fn Dot::compare(self : Dot, other : Dot) -> Int {
  if self.replica < other.replica {
    -1
  } else if self.replica > other.replica {
    1
  } else if self.counter < other.counter {
    -1
  } else if self.counter > other.counter {
    1
  } else {
    0
  }
}

///| A normalized set of unique dots. Ordering is deterministic and does not

///|
/// depend on message arrival order.
pub struct DotSet {
  dots : Array[Dot]
} derive(Eq, Debug)

///|
/// Create an empty dot set.
pub fn DotSet::new() -> DotSet {
  { dots: [] }
}

///|
/// Validate, deduplicate, and sort a collection of dots.
pub fn DotSet::from_array(dots : Array[Dot]) -> Result[DotSet, DotError] {
  let mut output = DotSet::new()
  for dot in dots {
    match Dot::new(dot.replica, dot.counter) {
      Err(error) => return Err(error)
      Ok(valid) => output = output.add(valid)
    }
  }
  Ok(output)
}

///|
/// Return normalized dots for inspection or host serialization.
pub fn DotSet::dots(self : DotSet) -> Array[Dot] {
  let output : Array[Dot] = []
  for dot in self.dots {
    output.push(dot)
  }
  output
}

///|
/// Number of distinct dots.
pub fn DotSet::length(self : DotSet) -> Int {
  self.dots.length()
}

///|
/// Test exact dot membership.
pub fn DotSet::contains(self : DotSet, candidate : Dot) -> Bool {
  for dot in self.dots {
    if dot == candidate {
      return true
    }
  }
  false
}

///|
/// Add one dot, retaining deterministic order.
pub fn DotSet::add(self : DotSet, candidate : Dot) -> DotSet {
  if self.contains(candidate) {
    return self
  }
  let output : Array[Dot] = []
  let mut inserted = false
  for dot in self.dots {
    if !inserted && candidate.compare(dot) < 0 {
      output.push(candidate)
      inserted = true
    }
    output.push(dot)
  }
  if !inserted {
    output.push(candidate)
  }
  { dots: output }
}

///|
/// Remove one exact dot.
pub fn DotSet::remove(self : DotSet, candidate : Dot) -> DotSet {
  let output : Array[Dot] = []
  for dot in self.dots {
    if dot != candidate {
      output.push(dot)
    }
  }
  { dots: output }
}

///|
/// Set union.
pub fn DotSet::union(self : DotSet, other : DotSet) -> DotSet {
  let mut output = self
  for dot in other.dots {
    output = output.add(dot)
  }
  output
}

///|
/// Set intersection.
pub fn DotSet::intersection(self : DotSet, other : DotSet) -> DotSet {
  let output : Array[Dot] = []
  for dot in self.dots {
    if other.contains(dot) {
      output.push(dot)
    }
  }
  { dots: output }
}

///|
/// Set difference.
pub fn DotSet::difference(self : DotSet, other : DotSet) -> DotSet {
  let output : Array[Dot] = []
  for dot in self.dots {
    if !other.contains(dot) {
      output.push(dot)
    }
  }
  { dots: output }
}

///|
/// Keep only dots not already covered by a version vector.
pub fn DotSet::after(self : DotSet, context : VersionVector) -> DotSet {
  let output : Array[Dot] = []
  for dot in self.dots {
    if !dot.is_covered_by(context) {
      output.push(dot)
    }
  }
  { dots: output }
}

///|
/// Keep only dots covered by a version vector.
pub fn DotSet::covered(self : DotSet, context : VersionVector) -> DotSet {
  let output : Array[Dot] = []
  for dot in self.dots {
    if dot.is_covered_by(context) {
      output.push(dot)
    }
  }
  { dots: output }
}

///|
/// Build the component-wise maximum context represented by these dots.
pub fn DotSet::frontier(self : DotSet) -> VersionVector {
  let entries : Array[VectorEntry] = []
  for dot in self.dots {
    entries.push({ replica: dot.replica, counter: dot.counter })
  }
  VersionVector::from_entries(entries).unwrap()
}

///|
/// Return true when every dot in this set occurs in the other set.
pub fn DotSet::is_subset_of(self : DotSet, other : DotSet) -> Bool {
  for dot in self.dots {
    if !other.contains(dot) {
      return false
    }
  }
  true
}

///|
/// Return the next counter after the greatest dot for a replica.
pub fn DotSet::next_counter(self : DotSet, replica : String) -> Int {
  let mut greatest = 0
  for dot in self.dots {
    if dot.replica == replica && dot.counter > greatest {
      greatest = dot.counter
    }
  }
  greatest + 1
}
