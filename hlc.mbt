///|
/// Mutable Hybrid Logical Clock state for one replica.
pub(all) struct HlcClock {
  node : String
  mut last : HlcTimestamp
} derive(Debug)

///| Create a clock with an initial physical time. The first generated event at

///|
/// the same physical time receives logical counter one.
pub fn HlcClock::new(
  node : String,
  initial_physical : Int,
) -> Result[HlcClock, TimestampError] {
  match HlcTimestamp::new(initial_physical, 0, node) {
    Ok(last) => Ok({ node: last.node, last })
    Err(error) => Err(error)
  }
}

///|
/// Return the last generated timestamp without advancing the clock.
pub fn HlcClock::last(self : HlcClock) -> HlcTimestamp {
  self.last
}

///| Advance for a local event. A physical clock moving backwards is safe: the

///|
/// clock keeps the known physical component and advances its logical counter.
pub fn HlcClock::tick(self : HlcClock, physical_now : Int) -> HlcTimestamp {
  let physical = max_int(self.last.physical, physical_now)
  let logical = if physical_now > self.last.physical {
    0
  } else {
    self.last.logical + 1
  }
  let next = { physical, logical, node: self.node }
  self.last = next
  next
}

///| Merge a remote HLC timestamp and advance for the receive event. This is the

///| standard HLC receive rule: the resulting timestamp is strictly later than

///|
/// both the local state and the received timestamp.
pub fn HlcClock::receive(
  self : HlcClock,
  remote : HlcTimestamp,
  physical_now : Int,
) -> HlcTimestamp {
  let current = self.last
  let physical = max_int(
    max_int(current.physical, remote.physical),
    physical_now,
  )
  let logical = if physical == current.physical && physical == remote.physical {
    max_int(current.logical, remote.logical) + 1
  } else if physical == current.physical {
    current.logical + 1
  } else if physical == remote.physical {
    remote.logical + 1
  } else {
    0
  }
  let next = { physical, logical, node: self.node }
  self.last = next
  next
}

///| Restore a persisted state after validating that the timestamp belongs to

///| the same replica. This prevents accidentally continuing another node's

///|
/// sequence under a new identity.
pub fn HlcClock::restore(
  node : String,
  last : HlcTimestamp,
) -> Result[HlcClock, ClockError] {
  if node == last.node {
    Ok({ node, last })
  } else {
    Err(NodeMismatch(expected=node, found=last.node))
  }
}

///|
/// Clock-specific domain errors.
pub(all) enum ClockError {
  NodeMismatch(expected~ : String, found~ : String)
} derive(Eq, Debug)

///|
/// Keep arithmetic local instead of adding a dependency for one operation.
fn max_int(left : Int, right : Int) -> Int {
  if left > right {
    left
  } else {
    right
  }
}
