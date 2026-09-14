///|
/// Classification of a physical clock reading relative to the prior sample.
pub(all) enum ClockReadingStatus {
  ClockReadingAccepted
  ClockRollback(Int)
  ClockForwardJump(Int)
} derive(Eq, Debug)

///| Thresholds for diagnosing host-clock behavior. HLC remains monotonic even

///|
/// when a reading is suspicious; this policy is observability, not rejection.
pub(all) struct ClockDiagnosticPolicy {
  maximum_rollback : Int
  maximum_forward_jump : Int
} derive(Eq, Debug)

///|
/// One classified host-clock sample.
pub(all) struct ClockSample {
  reading : Int
  previous : Int
  status : ClockReadingStatus
} derive(Eq, Debug)

///|
/// Immutable diagnostics accumulated for one clock source.
pub struct ClockDiagnostics {
  policy : ClockDiagnosticPolicy
  last_reading : Int
  samples : Array[ClockSample]
  rollback_count : Int
  forward_jump_count : Int
} derive(Debug)

///|
/// Policy and sample validation failures.
pub(all) enum ClockDiagnosticError {
  NegativeRollbackThreshold(Int)
  NegativeForwardJumpThreshold(Int)
  NegativeClockReading(Int)
} derive(Eq, Debug)

///|
/// Construct diagnostic thresholds.
pub fn ClockDiagnosticPolicy::new(
  maximum_rollback : Int,
  maximum_forward_jump : Int,
) -> Result[ClockDiagnosticPolicy, ClockDiagnosticError] {
  if maximum_rollback < 0 {
    Err(NegativeRollbackThreshold(maximum_rollback))
  } else if maximum_forward_jump < 0 {
    Err(NegativeForwardJumpThreshold(maximum_forward_jump))
  } else {
    Ok({ maximum_rollback, maximum_forward_jump })
  }
}

///|
/// Start diagnostics at a known physical reading.
pub fn ClockDiagnostics::new(
  policy : ClockDiagnosticPolicy,
  initial_reading : Int,
) -> Result[ClockDiagnostics, ClockDiagnosticError] {
  if initial_reading < 0 {
    Err(NegativeClockReading(initial_reading))
  } else {
    Ok({
      policy,
      last_reading: initial_reading,
      samples: [],
      rollback_count: 0,
      forward_jump_count: 0,
    })
  }
}

///|
/// Classify and append one reading.
pub fn ClockDiagnostics::observe(
  self : ClockDiagnostics,
  reading : Int,
) -> Result[ClockDiagnostics, ClockDiagnosticError] {
  if reading < 0 {
    return Err(NegativeClockReading(reading))
  }
  let difference = reading - self.last_reading
  let status = if difference < 0 &&
    0 - difference > self.policy.maximum_rollback {
    ClockRollback(0 - difference)
  } else if difference > self.policy.maximum_forward_jump {
    ClockForwardJump(difference)
  } else {
    ClockReadingAccepted
  }
  let samples : Array[ClockSample] = []
  for sample in self.samples {
    samples.push(sample)
  }
  samples.push({ reading, previous: self.last_reading, status })
  let rollback_increment = match status {
    ClockRollback(_) => 1
    _ => 0
  }
  let forward_increment = match status {
    ClockForwardJump(_) => 1
    _ => 0
  }
  Ok({
    policy: self.policy,
    last_reading: reading,
    samples,
    rollback_count: self.rollback_count + rollback_increment,
    forward_jump_count: self.forward_jump_count + forward_increment,
  })
}

///|
/// Recorded samples in observation order.
pub fn ClockDiagnostics::samples(self : ClockDiagnostics) -> Array[ClockSample] {
  let output : Array[ClockSample] = []
  for sample in self.samples {
    output.push(sample)
  }
  output
}

///|
/// Most recent physical reading.
pub fn ClockDiagnostics::last_reading(self : ClockDiagnostics) -> Int {
  self.last_reading
}

///|
/// Number of excessive rollbacks.
pub fn ClockDiagnostics::rollback_count(self : ClockDiagnostics) -> Int {
  self.rollback_count
}

///|
/// Number of excessive forward jumps.
pub fn ClockDiagnostics::forward_jump_count(self : ClockDiagnostics) -> Int {
  self.forward_jump_count
}

///|
/// Whether any suspicious sample has been observed.
pub fn ClockDiagnostics::has_anomaly(self : ClockDiagnostics) -> Bool {
  self.rollback_count > 0 || self.forward_jump_count > 0
}

///|
/// Only anomalous samples, suitable for telemetry emission.
pub fn ClockDiagnostics::anomalies(
  self : ClockDiagnostics,
) -> Array[ClockSample] {
  let output : Array[ClockSample] = []
  for sample in self.samples {
    match sample.status {
      ClockReadingAccepted => ()
      ClockRollback(_) | ClockForwardJump(_) => output.push(sample)
    }
  }
  output
}

///| Clear accumulated samples and counters while retaining policy and the last

///|
/// reading as the next comparison baseline.
pub fn ClockDiagnostics::reset(self : ClockDiagnostics) -> ClockDiagnostics {
  {
    policy: self.policy,
    last_reading: self.last_reading,
    samples: [],
    rollback_count: 0,
    forward_jump_count: 0,
  }
}
