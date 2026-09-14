///| A hybrid logical timestamp. `physical` is supplied by the caller so the

///|
/// algorithm remains deterministic in tests, simulations, and WASM runtimes.
pub(all) struct HlcTimestamp {
  physical : Int
  logical : Int
  node : String
} derive(Eq, Debug)

///| Create a timestamp. Negative physical time and logical counters are not

///| valid HLC values, so this returns an error instead of silently accepting

///|
/// malformed decoded data.
pub fn HlcTimestamp::new(
  physical : Int,
  logical : Int,
  node : String,
) -> Result[HlcTimestamp, TimestampError] {
  if physical < 0 {
    Err(NegativePhysicalTime(physical))
  } else if logical < 0 {
    Err(NegativeLogicalCounter(logical))
  } else if node.length() == 0 {
    Err(EmptyNodeId)
  } else {
    Ok({ physical, logical, node })
  }
}

///| Return a stable human-readable representation suitable for traces. This is

///| deliberately not a wire format: consumers should choose their own storage

///|
/// format and validate it at the boundary.
pub fn HlcTimestamp::to_string(self : HlcTimestamp) -> String {
  self.physical.to_string() + ":" + self.logical.to_string() + ":" + self.node
}

///| Total-order two timestamps by physical time, logical counter, then node.

///|
/// A negative value means `self` comes before `other`.
pub fn HlcTimestamp::compare(self : HlcTimestamp, other : HlcTimestamp) -> Int {
  if self.physical < other.physical {
    -1
  } else if self.physical > other.physical {
    1
  } else if self.logical < other.logical {
    -1
  } else if self.logical > other.logical {
    1
  } else if self.node < other.node {
    -1
  } else if self.node > other.node {
    1
  } else {
    0
  }
}

///|
/// True when `self` is no later than `other` in HLC total order.
pub fn HlcTimestamp::precedes_or_equals(
  self : HlcTimestamp,
  other : HlcTimestamp,
) -> Bool {
  self.compare(other) <= 0
}

///|
/// Timestamp construction and decoding errors.
pub(all) enum TimestampError {
  NegativePhysicalTime(Int)
  NegativeLogicalCounter(Int)
  EmptyNodeId
} derive(Eq, Debug)
