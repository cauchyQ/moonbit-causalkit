///| Immutable state captured after applying a stable operation-log prefix.

///|
/// `state` is application-defined so the causal core remains storage-neutral.
pub(all) struct CausalCheckpoint {
  frontier : VersionVector
  state : String
  operation_count : Int
  created_at : Int
} derive(Eq, Debug)

///|
/// A checkpoint and the unstable suffix still required for replay.
pub(all) struct CheckpointPlan {
  checkpoint : CausalCheckpoint
  stable_entries : Array[LoggedOperation]
  replay_log : OperationLog
} derive(Debug)

///|
/// Validation failures for restored checkpoints.
pub(all) enum CheckpointError {
  NegativeCheckpointOperationCount(Int)
  NegativeCheckpointTime(Int)
  CheckpointAheadOfLog(String, Int, Int)
  ReplayGap(String, Int, Int)
  ReplayDependencyMissing(String)
} derive(Eq, Debug)

///|
/// Construct a checkpoint supplied by a persistence adapter.
pub fn CausalCheckpoint::new(
  frontier : VersionVector,
  state : String,
  operation_count : Int,
  created_at : Int,
) -> Result[CausalCheckpoint, CheckpointError] {
  if operation_count < 0 {
    Err(NegativeCheckpointOperationCount(operation_count))
  } else if created_at < 0 {
    Err(NegativeCheckpointTime(created_at))
  } else {
    Ok({ frontier, state, operation_count, created_at })
  }
}

///|
/// Captured causal frontier.
pub fn CausalCheckpoint::frontier(self : CausalCheckpoint) -> VersionVector {
  self.frontier
}

///|
/// Opaque application snapshot.
pub fn CausalCheckpoint::state(self : CausalCheckpoint) -> String {
  self.state
}

///|
/// Number of operations folded into the snapshot.
pub fn CausalCheckpoint::operation_count(self : CausalCheckpoint) -> Int {
  self.operation_count
}

///|
/// Logical or physical host time recorded for observability.
pub fn CausalCheckpoint::created_at(self : CausalCheckpoint) -> Int {
  self.created_at
}

///|
/// Build a checkpoint plan from a frontier already proven stable.
pub fn plan_checkpoint(
  log : OperationLog,
  stable_frontier : VersionVector,
  state : String,
  created_at : Int,
) -> Result[CheckpointPlan, CheckpointError] {
  if created_at < 0 {
    return Err(NegativeCheckpointTime(created_at))
  }
  let (stable_entries, replay_log) = log.compact(stable_frontier)
  match
    CausalCheckpoint::new(
      stable_frontier,
      state,
      stable_entries.length(),
      created_at,
    ) {
    Ok(checkpoint) => Ok({ checkpoint, stable_entries, replay_log })
    Err(error) => Err(error)
  }
}

///|
/// Check that a checkpoint does not claim counters beyond the combined log.
pub fn validate_checkpoint_against(
  checkpoint : CausalCheckpoint,
  log : OperationLog,
) -> Result[Unit, CheckpointError] {
  let log_frontier = operation_log_frontier(log)
  for entry in checkpoint.frontier.entries() {
    let available = log_frontier.counter(entry.replica)
    if entry.counter > available {
      return Err(CheckpointAheadOfLog(entry.replica, entry.counter, available))
    }
  }
  Ok(())
}

///|
/// Compute the greatest counters represented in a log.
pub fn operation_log_frontier(log : OperationLog) -> VersionVector {
  let entries : Array[VectorEntry] = []
  for logged in log.entries() {
    entries.push({
      replica: logged.operation.replica,
      counter: logged.operation.counter,
    })
  }
  VersionVector::from_entries(entries).unwrap()
}

///|
/// Select entries strictly after a checkpoint frontier.
pub fn replay_after(
  checkpoint : CausalCheckpoint,
  log : OperationLog,
) -> Array[LoggedOperation] {
  let output : Array[LoggedOperation] = []
  for entry in log.entries() {
    if entry.operation.counter >
      checkpoint.frontier.counter(entry.operation.replica) {
      output.push(entry)
    }
  }
  output
}

///|
/// Validate that replay contains no per-replica gaps after the checkpoint.
pub fn validate_replay(
  checkpoint : CausalCheckpoint,
  entries : Array[LoggedOperation],
) -> Result[VersionVector, CheckpointError] {
  let mut frontier = checkpoint.frontier
  for entry in entries {
    if !entry.operation.prerequisites.happens_before(frontier) {
      return Err(ReplayDependencyMissing(entry.operation.id))
    }
    let expected = frontier.counter(entry.operation.replica) + 1
    if entry.operation.counter != expected {
      return Err(
        ReplayGap(entry.operation.replica, expected, entry.operation.counter),
      )
    }
    frontier = frontier.increment(entry.operation.replica).unwrap()
  }
  Ok(frontier)
}

///|
/// Combine a previous checkpoint with an additional stable plan.
pub fn advance_checkpoint(
  previous : CausalCheckpoint,
  plan : CheckpointPlan,
) -> CausalCheckpoint {
  {
    frontier: previous.frontier.merge(plan.checkpoint.frontier),
    state: plan.checkpoint.state,
    operation_count: previous.operation_count + plan.checkpoint.operation_count,
    created_at: plan.checkpoint.created_at,
  }
}
