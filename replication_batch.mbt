///|
/// A transport-neutral batch of causal operations.
pub(all) struct ReplicationBatch {
  source : String
  batch_id : String
  operations : Array[CausalOperation]
  advertised_frontier : VersionVector
} derive(Debug)

///|
/// Batch validation failures.
pub(all) enum BatchError {
  EmptyBatchSource
  EmptyBatchId
  DuplicateBatchOperation(String)
  DuplicateBatchDot(String, Int)
  BatchCounterBeyondFrontier(String, Int, Int)
  BatchDependencyBeyondFrontier(String, String, Int, Int)
} derive(Eq, Debug)

///|
/// Result of feeding a batch through a causal buffer.
pub(all) struct BatchDelivery {
  buffer : CausalBuffer
  released : Array[CausalOperation]
  accepted_count : Int
  duplicate_count : Int
} derive(Debug)

///|
/// Construct and validate a replication batch.
pub fn ReplicationBatch::new(
  source : String,
  batch_id : String,
  operations : Array[CausalOperation],
  advertised_frontier : VersionVector,
) -> Result[ReplicationBatch, BatchError] {
  if source.length() == 0 {
    return Err(EmptyBatchSource)
  }
  if batch_id.length() == 0 {
    return Err(EmptyBatchId)
  }
  for left in 0..<operations.length() {
    let operation = operations[left]
    if operation.counter > advertised_frontier.counter(operation.replica) {
      return Err(
        BatchCounterBeyondFrontier(
          operation.replica,
          operation.counter,
          advertised_frontier.counter(operation.replica),
        ),
      )
    }
    for dependency in operation.prerequisites.entries() {
      let advertised = advertised_frontier.counter(dependency.replica)
      if dependency.counter > advertised {
        return Err(
          BatchDependencyBeyondFrontier(
            operation.id,
            dependency.replica,
            dependency.counter,
            advertised,
          ),
        )
      }
    }
    for right in (left + 1)..<operations.length() {
      if operation.id == operations[right].id {
        return Err(DuplicateBatchOperation(operation.id))
      }
      if operation.replica == operations[right].replica &&
        operation.counter == operations[right].counter {
        return Err(DuplicateBatchDot(operation.replica, operation.counter))
      }
    }
  }
  Ok({ source, batch_id, operations, advertised_frontier })
}

///|
/// Number of operations carried by the batch.
pub fn ReplicationBatch::length(self : ReplicationBatch) -> Int {
  self.operations.length()
}

///|
/// Return operations in transport order.
pub fn ReplicationBatch::operations(
  self : ReplicationBatch,
) -> Array[CausalOperation] {
  self.operations
}

///|
/// Whether the batch contains a given operation identity.
pub fn ReplicationBatch::contains_id(
  self : ReplicationBatch,
  operation_id : String,
) -> Bool {
  for operation in self.operations {
    if operation.id == operation_id {
      return true
    }
  }
  false
}

///|
/// Restrict the batch to operations not covered by a receiver frontier.
pub fn ReplicationBatch::after(
  self : ReplicationBatch,
  receiver : VersionVector,
) -> ReplicationBatch {
  let operations : Array[CausalOperation] = []
  for operation in self.operations {
    if operation.counter > receiver.counter(operation.replica) {
      operations.push(operation)
    }
  }
  {
    source: self.source,
    batch_id: self.batch_id,
    operations,
    advertised_frontier: self.advertised_frontier,
  }
}

///| Feed all operations through a buffer. Transport order may be arbitrary;

///|
/// released order is always causally valid.
pub fn ReplicationBatch::deliver(
  self : ReplicationBatch,
  initial : CausalBuffer,
) -> BatchDelivery {
  let mut buffer = initial
  let released : Array[CausalOperation] = []
  let mut accepted_count = 0
  let mut duplicate_count = 0
  for operation in self.operations {
    let before_pending = buffer.pending().length()
    let (next, ready) = buffer.offer(operation)
    if ready.length() == 0 && next.pending().length() == before_pending {
      duplicate_count = duplicate_count + 1
    } else {
      accepted_count = accepted_count + 1
    }
    for item in ready {
      released.push(item)
    }
    buffer = next
  }
  { buffer, released, accepted_count, duplicate_count }
}

///|
/// Append released operations to an existing log with one application time.
pub fn BatchDelivery::append_to_log(
  self : BatchDelivery,
  log : OperationLog,
  applied_at : Int,
) -> OperationLog {
  log.append(self.released, applied_at)
}

///|
/// Causal frontier after delivery.
pub fn BatchDelivery::frontier(self : BatchDelivery) -> VersionVector {
  self.buffer.applied()
}
