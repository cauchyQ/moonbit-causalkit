///|
/// An append-only record of operations released by a causal buffer.
pub(all) struct LoggedOperation {
  operation : CausalOperation
  applied_at : Int
} derive(Debug)

///| A deterministic replay log. It deliberately stores the original causal

///| operation rather than a callback, so the trace remains serializable by a

///|
/// host application and reproducible in tests.
pub struct OperationLog {
  entries : Array[LoggedOperation]
} derive(Debug)

///|
pub fn OperationLog::new() -> OperationLog {
  { entries: [] }
}

///|
pub fn OperationLog::entries(self : OperationLog) -> Array[LoggedOperation] {
  let output : Array[LoggedOperation] = []
  for entry in self.entries {
    output.push(entry)
  }
  output
}

///|
pub fn OperationLog::length(self : OperationLog) -> Int {
  self.entries.length()
}

///|
/// Append operations in their already-validated causal release order.
pub fn OperationLog::append(
  self : OperationLog,
  operations : Array[CausalOperation],
  applied_at : Int,
) -> OperationLog {
  let entries : Array[LoggedOperation] = []
  for entry in self.entries {
    entries.push(entry)
  }
  for operation in operations {
    entries.push({ operation, applied_at })
  }
  { entries, }
}

///|
/// Return a checkpointable prefix whose operations are covered by `frontier`.
pub fn OperationLog::stable_prefix(
  self : OperationLog,
  frontier : VersionVector,
) -> Array[LoggedOperation] {
  let output : Array[LoggedOperation] = []
  for entry in self.entries {
    if entry.operation.counter <= frontier.counter(entry.operation.replica) {
      output.push(entry)
    } else {
      return output
    }
  }
  output
}

///| Split the log at the stable frontier. The returned prefix may be folded

///| into a durable checkpoint; the returned log contains exactly the entries

///|
/// that still need replay. The original log is unchanged.
pub fn OperationLog::compact(
  self : OperationLog,
  frontier : VersionVector,
) -> (Array[LoggedOperation], OperationLog) {
  let stable = self.stable_prefix(frontier)
  let remaining : Array[LoggedOperation] = []
  for index in stable.length()..<self.entries.length() {
    remaining.push(self.entries[index])
  }
  (stable, { entries: remaining })
}
