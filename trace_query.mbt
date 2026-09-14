///|
/// Summary metrics for a causal trace.
pub(all) struct TraceSummary {
  event_count : Int
  direct_edge_count : Int
  concurrent_pair_count : Int
  layer_count : Int
  maximum_width : Int
  critical_path_length : Int
} derive(Eq, Debug)

///|
/// A path through causally ordered events.
pub(all) struct CausalPath {
  events : Array[TraceEvent]
} derive(Debug)

///|
/// Query facade for navigating a validated TraceAnalysis.
pub(all) struct TraceQuery {
  analysis : TraceAnalysis
} derive(Debug)

///|
/// Create queries from an already validated analysis.
pub fn TraceQuery::new(analysis : TraceAnalysis) -> TraceQuery {
  { analysis, }
}

///|
/// All strict causal ancestors of one event.
pub fn TraceQuery::ancestors(
  self : TraceQuery,
  sequence : Int,
) -> Array[TraceEvent] {
  let output : Array[TraceEvent] = []
  for candidate in self.analysis.events() {
    match self.analysis.relation(candidate.sequence, sequence) {
      Some(Before) => output.push(candidate)
      _ => ()
    }
  }
  output
}

///|
/// All strict causal descendants of one event.
pub fn TraceQuery::descendants(
  self : TraceQuery,
  sequence : Int,
) -> Array[TraceEvent] {
  let output : Array[TraceEvent] = []
  for candidate in self.analysis.events() {
    match self.analysis.relation(sequence, candidate.sequence) {
      Some(Before) => output.push(candidate)
      _ => ()
    }
  }
  output
}

///|
/// Events concurrent with one selected event.
pub fn TraceQuery::concurrent_with(
  self : TraceQuery,
  sequence : Int,
) -> Array[TraceEvent] {
  let output : Array[TraceEvent] = []
  for candidate in self.analysis.events() {
    match self.analysis.relation(sequence, candidate.sequence) {
      Some(Concurrent) => output.push(candidate)
      _ => ()
    }
  }
  output
}

///|
/// Events produced by one replica, preserving trace order.
pub fn TraceQuery::by_replica(
  self : TraceQuery,
  replica : String,
) -> Array[TraceEvent] {
  let output : Array[TraceEvent] = []
  for event in self.analysis.events() {
    if event.replica == replica {
      output.push(event)
    }
  }
  output
}

///|
/// Events whose HLC physical component lies in an inclusive interval.
pub fn TraceQuery::between_physical_times(
  self : TraceQuery,
  from_time : Int,
  to_time : Int,
) -> Array[TraceEvent] {
  let output : Array[TraceEvent] = []
  if to_time < from_time {
    return output
  }
  for event in self.analysis.events() {
    if event.stamp.physical >= from_time && event.stamp.physical <= to_time {
      output.push(event)
    }
  }
  output
}

///| Smallest useful causal slice containing an event, its ancestors, and its

///|
/// descendants. Concurrent events outside that cone are omitted.
pub fn TraceQuery::causal_slice(
  self : TraceQuery,
  sequence : Int,
) -> Array[TraceEvent] {
  let output : Array[TraceEvent] = []
  for event in self.analysis.events() {
    match self.analysis.relation(event.sequence, sequence) {
      Some(Before) | Some(After) | Some(Equal) => output.push(event)
      _ => ()
    }
  }
  output
}

///|
/// Longest direct-edge path ending at a selected event.
pub fn TraceQuery::longest_path_to(
  self : TraceQuery,
  sequence : Int,
) -> CausalPath {
  let mut best : Array[TraceEvent] = []
  for edge in self.analysis.direct_predecessors(sequence) {
    let candidate = self.longest_path_to(edge.earlier.sequence).events
    if candidate.length() > best.length() {
      best = candidate
    }
  }
  for event in self.analysis.events() {
    if event.sequence == sequence {
      best.push(event)
      break
    }
  }
  { events: best }
}

///|
/// Longest causal path anywhere in the trace.
pub fn TraceQuery::critical_path(self : TraceQuery) -> CausalPath {
  let mut best : Array[TraceEvent] = []
  for event in self.analysis.events() {
    let candidate = self.longest_path_to(event.sequence).events
    if candidate.length() > best.length() {
      best = candidate
    }
  }
  { events: best }
}

///|
/// Events with no causal predecessors.
pub fn TraceQuery::roots(self : TraceQuery) -> Array[TraceEvent] {
  let output : Array[TraceEvent] = []
  for event in self.analysis.events() {
    if self.analysis.direct_predecessors(event.sequence).length() == 0 {
      output.push(event)
    }
  }
  output
}

///|
/// Events with no causal successors.
pub fn TraceQuery::leaves(self : TraceQuery) -> Array[TraceEvent] {
  let output : Array[TraceEvent] = []
  for event in self.analysis.events() {
    if self.descendants(event.sequence).length() == 0 {
      output.push(event)
    }
  }
  output
}

///|
/// Aggregate metrics used by diagnostics and visualizers.
pub fn TraceQuery::summary(self : TraceQuery) -> TraceSummary {
  let layers = self.analysis.layers()
  let mut maximum_width = 0
  for layer in layers {
    if layer.events.length() > maximum_width {
      maximum_width = layer.events.length()
    }
  }
  {
    event_count: self.analysis.events().length(),
    direct_edge_count: self.analysis.direct_edges().length(),
    concurrent_pair_count: self.analysis.concurrent_pairs().length(),
    layer_count: layers.length(),
    maximum_width,
    critical_path_length: self.critical_path().events.length(),
  }
}
