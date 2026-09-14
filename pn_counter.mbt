///|
/// One replica's monotonic positive and negative components.
pub(all) struct CounterComponent {
  replica : String
  positive : Int
  negative : Int
} derive(Eq, Debug)

///| A state-based PN counter. Each component only grows, making merge a

///|
/// component-wise maximum and therefore associative, commutative, idempotent.
pub struct PnCounter {
  components : Array[CounterComponent]
} derive(Eq, Debug)

///|
/// Counter validation errors.
pub(all) enum CounterError {
  EmptyCounterReplica
  NegativeCounterComponent(String, Int, Int)
  NegativeCounterAmount(Int)
} derive(Eq, Debug)

///|
/// Create a zero counter.
pub fn PnCounter::new() -> PnCounter {
  { components: [] }
}

///|
/// Restore validated components, merging duplicates by component-wise max.
pub fn PnCounter::from_components(
  components : Array[CounterComponent],
) -> Result[PnCounter, CounterError] {
  let mut output = PnCounter::new()
  for component in components {
    if component.replica.length() == 0 {
      return Err(EmptyCounterReplica)
    }
    if component.positive < 0 || component.negative < 0 {
      return Err(
        NegativeCounterComponent(
          component.replica,
          component.positive,
          component.negative,
        ),
      )
    }
    output = output.merge({ components: [component] })
  }
  Ok(output)
}

///|
/// Inspect normalized components.
pub fn PnCounter::components(self : PnCounter) -> Array[CounterComponent] {
  let output : Array[CounterComponent] = []
  for component in self.components {
    output.push(component)
  }
  output
}

///|
/// Current signed value.
pub fn PnCounter::value(self : PnCounter) -> Int {
  let mut result = 0
  for component in self.components {
    result = result + component.positive - component.negative
  }
  result
}

///|
/// Positive contribution made by one replica.
pub fn PnCounter::positive_of(self : PnCounter, replica : String) -> Int {
  for component in self.components {
    if component.replica == replica {
      return component.positive
    }
  }
  0
}

///|
/// Negative contribution made by one replica.
pub fn PnCounter::negative_of(self : PnCounter, replica : String) -> Int {
  for component in self.components {
    if component.replica == replica {
      return component.negative
    }
  }
  0
}

///|
/// Add a non-negative amount at one replica.
pub fn PnCounter::increment_by(
  self : PnCounter,
  replica : String,
  amount : Int,
) -> Result[PnCounter, CounterError] {
  if replica.length() == 0 {
    return Err(EmptyCounterReplica)
  }
  if amount < 0 {
    return Err(NegativeCounterAmount(amount))
  }
  Ok(
    self.set_component(
      replica,
      self.positive_of(replica) + amount,
      self.negative_of(replica),
    ),
  )
}

///|
/// Subtract a non-negative amount at one replica.
pub fn PnCounter::decrement_by(
  self : PnCounter,
  replica : String,
  amount : Int,
) -> Result[PnCounter, CounterError] {
  if replica.length() == 0 {
    return Err(EmptyCounterReplica)
  }
  if amount < 0 {
    return Err(NegativeCounterAmount(amount))
  }
  Ok(
    self.set_component(
      replica,
      self.positive_of(replica),
      self.negative_of(replica) + amount,
    ),
  )
}

///|
/// Increment by one.
pub fn PnCounter::increment(
  self : PnCounter,
  replica : String,
) -> Result[PnCounter, CounterError] {
  self.increment_by(replica, 1)
}

///|
/// Decrement by one.
pub fn PnCounter::decrement(
  self : PnCounter,
  replica : String,
) -> Result[PnCounter, CounterError] {
  self.decrement_by(replica, 1)
}

///|
/// Merge state using a component-wise maximum.
pub fn PnCounter::merge(self : PnCounter, other : PnCounter) -> PnCounter {
  let mut output = self
  for component in other.components {
    let positive = if component.positive > output.positive_of(component.replica) {
      component.positive
    } else {
      output.positive_of(component.replica)
    }
    let negative = if component.negative > output.negative_of(component.replica) {
      component.negative
    } else {
      output.negative_of(component.replica)
    }
    output = output.set_component(component.replica, positive, negative)
  }
  output
}

///|
/// True when every local component is less than or equal to the other state.
pub fn PnCounter::is_included_in(self : PnCounter, other : PnCounter) -> Bool {
  for component in self.components {
    if component.positive > other.positive_of(component.replica) ||
      component.negative > other.negative_of(component.replica) {
      return false
    }
  }
  true
}

///|
/// Components that contain information newer than a peer's state.
pub fn PnCounter::delta_since(self : PnCounter, peer : PnCounter) -> PnCounter {
  let output : Array[CounterComponent] = []
  for component in self.components {
    if component.positive > peer.positive_of(component.replica) ||
      component.negative > peer.negative_of(component.replica) {
      output.push(component)
    }
  }
  { components: output }
}

///|
fn PnCounter::set_component(
  self : PnCounter,
  replica : String,
  positive : Int,
  negative : Int,
) -> PnCounter {
  let output : Array[CounterComponent] = []
  let mut found = false
  for component in self.components {
    if component.replica == replica {
      output.push({ replica, positive, negative })
      found = true
    } else {
      output.push(component)
    }
  }
  if !found {
    output.push({ replica, positive, negative })
  }
  { components: output }
}
