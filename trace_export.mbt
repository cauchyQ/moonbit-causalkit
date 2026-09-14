///|
/// A dependency-free, serialization-friendly trace row.
pub(all) struct TraceRow {
  sequence : Int
  replica : String
  physical : Int
  logical : Int
  kind : String
  detail : String
} derive(Eq, Debug)

///|
/// A serialization-friendly direct edge.
pub(all) struct EdgeRow {
  from_sequence : Int
  to_sequence : Int
} derive(Eq, Debug)

///|
/// Convert trace events into flat rows suitable for CSV/JSON adapters.
pub fn trace_rows(events : Array[TraceEvent]) -> Array[TraceRow] {
  let output : Array[TraceRow] = []
  for event in events {
    output.push({
      sequence: event.sequence,
      replica: event.replica,
      physical: event.stamp.physical,
      logical: event.stamp.logical,
      kind: trace_kind_name(event.kind),
      detail: trace_kind_detail(event.kind),
    })
  }
  output
}

///|
/// Flatten direct causal edges for host serializers.
pub fn edge_rows(analysis : TraceAnalysis) -> Array[EdgeRow] {
  let output : Array[EdgeRow] = []
  for edge in analysis.direct_edges() {
    output.push({
      from_sequence: edge.earlier.sequence,
      to_sequence: edge.later.sequence,
    })
  }
  output
}

///|
/// Stable name for a trace event kind.
pub fn trace_kind_name(kind : TraceKind) -> String {
  match kind {
    Local(_) => "local"
    Sent(..) => "send"
    Received(..) => "receive"
    AvailabilityChanged(online~) => if online { "online" } else { "offline" }
  }
}

///|
/// Human-readable payload carried by a trace kind.
pub fn trace_kind_detail(kind : TraceKind) -> String {
  match kind {
    Local(label~) => label
    Sent(target~, payload~) => target + ":" + payload
    Received(source~, payload~) => source + ":" + payload
    AvailabilityChanged(online~) => if online { "online" } else { "offline" }
  }
}

///| Graphviz DOT lines. Returning lines avoids forcing a particular newline or

///|
/// filesystem API on browser, native, and Wasm callers.
pub fn trace_dot_lines(analysis : TraceAnalysis) -> Array[String] {
  let output : Array[String] = ["digraph causality {"]
  output.push("  rankdir=LR;")
  for event in analysis.events() {
    output.push(
      "  e" +
      event.sequence.to_string() +
      " [label=\"" +
      event.sequence.to_string() +
      " " +
      event.replica +
      " " +
      trace_kind_name(event.kind) +
      "\"];",
    )
  }
  for edge in analysis.direct_edges() {
    output.push(
      "  e" +
      edge.earlier.sequence.to_string() +
      " -> e" +
      edge.later.sequence.to_string() +
      ";",
    )
  }
  output.push("}")
  output
}

///|
/// Mermaid flowchart lines for Markdown documentation and issue reports.
pub fn trace_mermaid_lines(analysis : TraceAnalysis) -> Array[String] {
  let output : Array[String] = ["flowchart LR"]
  for event in analysis.events() {
    output.push(
      "  e" +
      event.sequence.to_string() +
      "[\"" +
      event.sequence.to_string() +
      " " +
      event.replica +
      " " +
      trace_kind_name(event.kind) +
      "\"]",
    )
  }
  for edge in analysis.direct_edges() {
    output.push(
      "  e" +
      edge.earlier.sequence.to_string() +
      " --> e" +
      edge.later.sequence.to_string(),
    )
  }
  output
}

///| One line per concurrency conflict, useful in diagnostics without a graph

///|
/// rendering dependency.
pub fn concurrency_report_lines(analysis : TraceAnalysis) -> Array[String] {
  let output : Array[String] = []
  for pair in analysis.concurrent_pairs() {
    output.push(
      pair.first.sequence.to_string() +
      " (" +
      pair.first.replica +
      ") concurrent with " +
      pair.second.sequence.to_string() +
      " (" +
      pair.second.replica +
      ")",
    )
  }
  output
}

///|
/// One line per topological layer.
pub fn layer_report_lines(analysis : TraceAnalysis) -> Array[String] {
  let output : Array[String] = []
  for layer in analysis.layers() {
    let mut line = "layer " + layer.index.to_string() + ":"
    for event in layer.events {
      line = line + " " + event.sequence.to_string()
    }
    output.push(line)
  }
  output
}
