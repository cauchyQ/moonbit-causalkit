///| One value held by a multi-value register together with its causal context.

///| Values are strings so this base package stays dependency-free; applications

///|
/// can encode domain records before passing them to the register.
pub(all) struct VersionedValue {
  value : String
  writer : String
  context : VersionVector
} derive(Eq, Debug)

///| A state-based multi-value register. Concurrent writes remain visible while

///|
/// a write that has observed them causally replaces them all.
pub struct MultiValueRegister {
  values : Array[VersionedValue]
} derive(Debug)

///|
/// Validation errors for register writes.
pub(all) enum RegisterError {
  EmptyWriter
} derive(Eq, Debug)

///|
/// Create an empty register.
pub fn MultiValueRegister::new() -> MultiValueRegister {
  { values: [] }
}

///| Inspect current values. More than one item represents an unresolved

///|
/// concurrent update, not an arbitrary last-writer-wins decision.
pub fn MultiValueRegister::values(
  self : MultiValueRegister,
) -> Array[VersionedValue] {
  let output : Array[VersionedValue] = []
  for value in self.values {
    output.push(value)
  }
  output
}

///|
/// Return the only value when the register has converged to one write.
pub fn MultiValueRegister::resolved(
  self : MultiValueRegister,
) -> VersionedValue? {
  if self.values.length() == 1 {
    Some(self.values[0])
  } else {
    None
  }
}

///| Join the contexts represented by currently visible values. A later local

///|
/// write based on this context will dominate all values it has observed.
pub fn MultiValueRegister::context(self : MultiValueRegister) -> VersionVector {
  let mut output = VersionVector::new()
  for value in self.values {
    output = output.merge(value.context)
  }
  output
}

///| Create a causally newer local value. This is a pure operation: persistence

///|
/// and replica transport remain responsibilities of the caller.
pub fn MultiValueRegister::write(
  self : MultiValueRegister,
  writer : String,
  value : String,
) -> Result[MultiValueRegister, RegisterError] {
  if writer.length() == 0 {
    return Err(EmptyWriter)
  }
  match self.context().increment(writer) {
    Ok(context) => Ok(self.apply({ value, writer, context }))
    Err(_) => Err(EmptyWriter)
  }
}

///| Merge a remote register state. Reapplying values is idempotent because

///|
/// equal causal contexts do not create duplicates.
pub fn MultiValueRegister::merge(
  self : MultiValueRegister,
  other : MultiValueRegister,
) -> MultiValueRegister {
  let mut output = self
  for value in other.values {
    output = output.apply(value)
  }
  output
}

///| Apply a remote versioned value. A candidate loses only when an existing

///|
/// value is causally equal or after it; concurrent values are both retained.
pub fn MultiValueRegister::apply(
  self : MultiValueRegister,
  candidate : VersionedValue,
) -> MultiValueRegister {
  let output : Array[VersionedValue] = []
  let mut candidate_is_obsolete = false
  for current in self.values {
    match candidate.context.compare(current.context) {
      Before | Equal => {
        output.push(current)
        candidate_is_obsolete = true
      }
      After => ()
      Concurrent => output.push(current)
    }
  }
  if !candidate_is_obsolete {
    output.push(candidate)
  }
  { values: output }
}

///| Explain whether a register is empty, converged, or needs application-level

///|
/// conflict resolution.
pub(all) enum RegisterState {
  Empty
  Resolved(VersionedValue)
  Conflict(Array[VersionedValue])
} derive(Debug)

///| Convert the register into a rendering-friendly state without forcing an

///|
/// application to inspect array lengths itself.
pub fn MultiValueRegister::state(self : MultiValueRegister) -> RegisterState {
  if self.values.length() == 0 {
    Empty
  } else if self.values.length() == 1 {
    Resolved(self.values[0])
  } else {
    Conflict(self.values)
  }
}
