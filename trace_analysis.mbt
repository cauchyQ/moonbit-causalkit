///| A direct causal edge inferred from version-vector contexts. Direct edges

///|
/// omit transitive predecessors so a rendered graph stays useful to people.
pub(all) struct CausalEdge {
  earlier : TraceEvent
  later : TraceEvent
} derive(Debug)

///|
/// Two trace events whose contexts are genuinely concurrent.
pub(all) struct ConcurrentPair {
  first : TraceEvent
  second : TraceEvent
} derive(Debug)

///| One topological layer of a causal trace. Events in the same layer have no

///|
/// causal dependency on an earlier event in that layer.
pub(all) struct CausalLayer {
  index : Int
  events : Array[TraceEvent]
} derive(Debug)

///|
/// Validated, queryable causal trace analysis.
pub struct TraceAnalysis {
  events : Array[TraceEvent]
} derive(Debug)

///|
/// Trace construction errors.
pub(all) enum TraceError {
  DuplicateSequence(Int)
  NonPositiveSequence(Int)
} derive(Eq, Debug)

///| Validate trace identity. Timestamps need not be sorted: causality is read

///|
/// from version vectors, not assumed from their wall-clock representation.
pub fn TraceAnalysis::new(
  events : Array[TraceEvent],
) -> Result[TraceAnalysis, TraceError] {
  for left in 0..<events.length() {
    if events[left].sequence <= 0 {
      return Err(NonPositiveSequence(events[left].sequence))
    }
    for right in (left + 1)..<events.length() {
      if events[left].sequence == events[right].sequence {
        return Err(DuplicateSequence(events[left].sequence))
      }
    }
  }
  Ok({ events, })
}

///|
/// Return the source events used to build this analysis.
pub fn TraceAnalysis::events(self : TraceAnalysis) -> Array[TraceEvent] {
  let output : Array[TraceEvent] = []
  for event in self.events {
    output.push(event)
  }
  output
}

///|
/// Read the causal relation between two event sequence numbers.
pub fn TraceAnalysis::relation(
  self : TraceAnalysis,
  first_sequence : Int,
  second_sequence : Int,
) -> CausalOrder? {
  match self.find(first_sequence) {
    Some(first) =>
      match self.find(second_sequence) {
        Some(second) => Some(first.context.compare(second.context))
        None => None
      }
    None => None
  }
}

///| Return transitive-reduced incoming edges for one event. An edge `a -> c`

///|
/// is omitted when another event `b` already proves `a -> b -> c`.
pub fn TraceAnalysis::direct_predecessors(
  self : TraceAnalysis,
  sequence : Int,
) -> Array[CausalEdge] {
  match self.find(sequence) {
    None => []
    Some(target) => {
      let output : Array[CausalEdge] = []
      for candidate in self.events {
        if candidate.context.compare(target.context) == Before &&
          !self.has_intermediate(candidate, target) {
          output.push({ earlier: candidate, later: target })
        }
      }
      output
    }
  }
}

///|
/// Return every directly inferred edge in deterministic trace order.
pub fn TraceAnalysis::direct_edges(self : TraceAnalysis) -> Array[CausalEdge] {
  let output : Array[CausalEdge] = []
  for event in self.events {
    for edge in self.direct_predecessors(event.sequence) {
      output.push(edge)
    }
  }
  output
}

///| Find pairs that need an application conflict policy instead of temporal

///|
/// sorting. Each pair appears once with the earlier trace position first.
pub fn TraceAnalysis::concurrent_pairs(
  self : TraceAnalysis,
) -> Array[ConcurrentPair] {
  let output : Array[ConcurrentPair] = []
  for left in 0..<self.events.length() {
    for right in (left + 1)..<self.events.length() {
      if self.events[left].context.compare(self.events[right].context) ==
        Concurrent {
        output.push({ first: self.events[left], second: self.events[right] })
      }
    }
  }
  output
}

///| Assign each event its longest-predecessor depth. The function uses causal

///| comparison rather than trace array order, so delayed deliveries are placed

///|
/// after their actual send even if a physical clock is skewed.
pub fn TraceAnalysis::layers(self : TraceAnalysis) -> Array[CausalLayer] {
  let depths : Array[Int] = []
  for _ in self.events {
    depths.push(0)
  }
  for _ in 0..<self.events.length() {
    for target in 0..<self.events.length() {
      for predecessor in 0..<self.events.length() {
        if self.events[predecessor].context.compare(self.events[target].context) ==
          Before &&
          depths[predecessor] + 1 > depths[target] {
          depths[target] = depths[predecessor] + 1
        }
      }
    }
  }
  let layers : Array[CausalLayer] = []
  for index in 0..<self.events.length() {
    while layers.length() <= depths[index] {
      layers.push({ index: layers.length(), events: [] })
    }
    let layer = layers[depths[index]]
    let items = layer.events
    items.push(self.events[index])
    layers[depths[index]] = { index: layer.index, events: items }
  }
  layers
}

///|
/// Locate an event by its stable trace sequence.
fn TraceAnalysis::find(self : TraceAnalysis, sequence : Int) -> TraceEvent? {
  for event in self.events {
    if event.sequence == sequence {
      return Some(event)
    }
  }
  None
}

///|
/// Check whether candidate is only a transitive predecessor of target.
fn TraceAnalysis::has_intermediate(
  self : TraceAnalysis,
  candidate : TraceEvent,
  target : TraceEvent,
) -> Bool {
  for middle in self.events {
    if middle.sequence != candidate.sequence &&
      middle.sequence != target.sequence &&
      candidate.context.compare(middle.context) == Before &&
      middle.context.compare(target.context) == Before {
      return true
    }
  }
  false
}
