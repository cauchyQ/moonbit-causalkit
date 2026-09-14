///| A reproducible two-replica example. It creates a write at alpha, sends the

///|
/// write while beta is offline, then shows delivery after beta recovers.
fn main {
  let simulator = @causal.Simulator::new(["alpha", "beta"], 1_000).unwrap()
  ignore(simulator.local_event("alpha", "create note").unwrap())
  ignore(simulator.set_online("beta", false).unwrap())
  ignore(simulator.send("alpha", "beta", "note:v1", 20).unwrap())
  ignore(simulator.advance_to(1_020).unwrap())
  println(
    "while beta is offline, queued=" + simulator.pending().length().to_string(),
  )
  ignore(simulator.set_online("beta", true).unwrap())
  let delivered = simulator.advance_to(1_020).unwrap()
  println("after recovery, delivered=" + delivered.length().to_string())
  let analysis = @causal.TraceAnalysis::new(simulator.trace()).unwrap()
  println("direct causal edges=" + analysis.direct_edges().length().to_string())
  println(
    "concurrent event pairs=" + analysis.concurrent_pairs().length().to_string(),
  )
  for event in simulator.trace() {
    println(
      event.sequence.to_string() +
      " " +
      event.replica +
      " " +
      event.stamp.to_string(),
    )
  }
}
