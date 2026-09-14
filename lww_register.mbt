///| A register value timestamped by an HLC. This CRDT deliberately provides a

///| deterministic last-writer policy for domains that prefer one value over

///|
/// preserving conflicts with MultiValueRegister.
pub(all) struct LastWriterWinsRegister {
  value : String
  writer : String
  timestamp : HlcTimestamp
} derive(Eq, Debug)

///|
/// LWW register validation errors.
pub(all) enum LastWriterWinsError {
  EmptyLastWriter
} derive(Eq, Debug)

///|
/// Construct a validated register state.
pub fn LastWriterWinsRegister::new(
  value : String,
  writer : String,
  timestamp : HlcTimestamp,
) -> Result[LastWriterWinsRegister, LastWriterWinsError] {
  if writer.length() == 0 {
    Err(EmptyLastWriter)
  } else {
    Ok({ value, writer, timestamp })
  }
}

///|
/// Current value.
pub fn LastWriterWinsRegister::value(self : LastWriterWinsRegister) -> String {
  self.value
}

///|
/// Writer of the current value.
pub fn LastWriterWinsRegister::writer(self : LastWriterWinsRegister) -> String {
  self.writer
}

///|
/// Timestamp of the current value.
pub fn LastWriterWinsRegister::timestamp(
  self : LastWriterWinsRegister,
) -> HlcTimestamp {
  self.timestamp
}

///| Replace the local state when the supplied timestamp wins. Equal timestamps

///| use writer then value as stable tie-breakers, protecting convergence even

///|
/// after corrupted or manually restored clocks produce a collision.
pub fn LastWriterWinsRegister::write(
  self : LastWriterWinsRegister,
  value : String,
  writer : String,
  timestamp : HlcTimestamp,
) -> Result[LastWriterWinsRegister, LastWriterWinsError] {
  match LastWriterWinsRegister::new(value, writer, timestamp) {
    Ok(candidate) => Ok(self.merge(candidate))
    Err(error) => Err(error)
  }
}

///|
/// Deterministic state merge.
pub fn LastWriterWinsRegister::merge(
  self : LastWriterWinsRegister,
  other : LastWriterWinsRegister,
) -> LastWriterWinsRegister {
  let timestamp_order = self.timestamp.compare(other.timestamp)
  if timestamp_order < 0 {
    other
  } else if timestamp_order > 0 {
    self
  } else if self.writer < other.writer {
    other
  } else if self.writer > other.writer {
    self
  } else if self.value < other.value {
    other
  } else {
    self
  }
}

///|
/// Whether this state would win or tie during merge.
pub fn LastWriterWinsRegister::dominates(
  self : LastWriterWinsRegister,
  other : LastWriterWinsRegister,
) -> Bool {
  self.merge(other) == self
}
