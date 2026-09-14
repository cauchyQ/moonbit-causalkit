///|
/// An operation with an explicit causal prerequisite context and one dot.
pub(all) struct CausalOperation {
  id : String
  replica : String
  counter : Int
  prerequisites : VersionVector
  payload : String
} derive(Debug)

///| A deterministic buffer which applies operations only after their causal

///|
/// prerequisites and per-replica predecessor dot have arrived.
pub struct CausalBuffer {
  applied : VersionVector
  pending : Array[CausalOperation]
} derive(Debug)

///|
pub(all) enum BufferError {
  EmptyOperationId
  EmptyReplicaId
  NonPositiveCounter(Int)
} derive(Eq, Debug)

///|
pub fn CausalOperation::new(
  id : String,
  replica : String,
  counter : Int,
  prerequisites : VersionVector,
  payload : String,
) -> Result[CausalOperation, BufferError] {
  if id.length() == 0 {
    Err(EmptyOperationId)
  } else if replica.length() == 0 {
    Err(EmptyReplicaId)
  } else if counter <= 0 {
    Err(NonPositiveCounter(counter))
  } else {
    Ok({ id, replica, counter, prerequisites, payload })
  }
}

///|
pub fn CausalBuffer::new() -> CausalBuffer {
  { applied: VersionVector::new(), pending: [] }
}

///|
pub fn CausalBuffer::applied(self : CausalBuffer) -> VersionVector {
  self.applied
}

///|
pub fn CausalBuffer::pending(self : CausalBuffer) -> Array[CausalOperation] {
  let output : Array[CausalOperation] = []
  for operation in self.pending {
    output.push(operation)
  }
  output
}

///| Insert an operation, then repeatedly release any operation that became

///|
/// causally ready. The returned array is the exact application order.
pub fn CausalBuffer::offer(
  self : CausalBuffer,
  operation : CausalOperation,
) -> (CausalBuffer, Array[CausalOperation]) {
  if operation.counter <= self.applied.counter(operation.replica) {
    (self, [])
  } else if contains_dot(self.pending, operation) {
    // Retransmission is normal in replicated systems. Keep one copy per dot so
    // a duplicate cannot remain stuck forever after the first copy is applied.
    (self, [])
  } else {
    let pending : Array[CausalOperation] = []
    for item in self.pending {
      pending.push(item)
    }
    pending.push(operation)
    CausalBuffer::drain({ applied: self.applied, pending })
  }
}

///|
fn contains_dot(
  operations : Array[CausalOperation],
  candidate : CausalOperation,
) -> Bool {
  for operation in operations {
    if operation.replica == candidate.replica &&
      operation.counter == candidate.counter {
      return true
    }
  }
  false
}

///|
fn CausalBuffer::drain(
  self : CausalBuffer,
) -> (CausalBuffer, Array[CausalOperation]) {
  let mut current = self
  let released : Array[CausalOperation] = []
  let mut progressed = true
  while progressed {
    progressed = false
    let remaining : Array[CausalOperation] = []
    for operation in current.pending {
      if ready(current.applied, operation) {
        current = {
          applied: current.applied.increment(operation.replica).unwrap(),
          pending: remaining,
        }
        released.push(operation)
        progressed = true
      } else {
        remaining.push(operation)
      }
    }
    current = { applied: current.applied, pending: remaining }
  }
  (current, released)
}

///|
fn ready(applied : VersionVector, operation : CausalOperation) -> Bool {
  operation.prerequisites.happens_before(applied) &&
  applied.counter(operation.replica) + 1 == operation.counter
}
