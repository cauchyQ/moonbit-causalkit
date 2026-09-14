///| The state of one simulated replica. The simulator is intentionally

///|
/// single-threaded and deterministic: callers control time with `advance_to`.
pub(all) struct ReplicaState {
  id : String
  clock : HlcClock
  vector : VersionVector
  online : Bool
} derive(Debug)

///|
/// A message that has been sent but not necessarily delivered.
pub(all) struct PendingMessage {
  source : String
  target : String
  payload : String
  sent_at : Int
  deliver_at : Int
  stamp : HlcTimestamp
  context : VersionVector
} derive(Debug)

///|
/// The kind of a trace event emitted by the deterministic simulator.
pub(all) enum TraceKind {
  Local(label~ : String)
  Sent(target~ : String, payload~ : String)
  Received(source~ : String, payload~ : String)
  AvailabilityChanged(online~ : Bool)
} derive(Eq, Debug)

///| A causally annotated event. `context` is the version vector after the

///|
/// event, while `stamp` is the HLC value used for stable total ordering.
pub(all) struct TraceEvent {
  sequence : Int
  time : Int
  replica : String
  stamp : HlcTimestamp
  context : VersionVector
  kind : TraceKind
} derive(Debug)

///| A deterministic in-memory transport and replica model. It is a test and

///|
/// teaching tool, not a production network stack.
pub(all) struct Simulator {
  mut time : Int
  mut replicas : Array[ReplicaState]
  mut pending : Array[PendingMessage]
  mut trace : Array[TraceEvent]
} derive(Debug)

///|
/// Create a network of replica IDs. IDs must be nonempty and unique.
pub fn Simulator::new(
  replica_ids : Array[String],
  start_time : Int,
) -> Result[Simulator, SimulatorError] {
  if start_time < 0 {
    return Err(NegativeSimulationTime(start_time))
  }
  let replicas : Array[ReplicaState] = []
  for id in replica_ids {
    if id.length() == 0 {
      return Err(EmptyReplicaId)
    }
    for replica in replicas {
      if replica.id == id {
        return Err(DuplicateReplica(id))
      }
    }
    match HlcClock::new(id, start_time) {
      Ok(clock) =>
        replicas.push({ id, clock, vector: VersionVector::new(), online: true })
      Err(_) => return Err(NegativeSimulationTime(start_time))
    }
  }
  Ok({ time: start_time, replicas, pending: [], trace: [] })
}

///|
/// Return the simulator's caller-controlled physical time.
pub fn Simulator::time(self : Simulator) -> Int {
  self.time
}

///|
/// Return a snapshot of replica state for display or assertions.
pub fn Simulator::replicas(self : Simulator) -> Array[ReplicaState] {
  self.replicas
}

///| Return queued messages which are waiting for their target to become online

///|
/// or for the controlled clock to reach their delivery time.
pub fn Simulator::pending(self : Simulator) -> Array[PendingMessage] {
  self.pending
}

///|
/// Return the append-only event trace.
pub fn Simulator::trace(self : Simulator) -> Array[TraceEvent] {
  self.trace
}

///| Emit one local event. Offline replicas reject events rather than silently

///|
/// accepting writes which could make a partition test misleading.
pub fn Simulator::local_event(
  self : Simulator,
  replica_id : String,
  label : String,
) -> Result[TraceEvent, SimulatorError] {
  let index = match self.replica_index(replica_id) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let replica = self.replicas[index]
  if !replica.online {
    return Err(ReplicaOffline(replica_id))
  }
  let stamp = replica.clock.tick(self.time)
  let context = match replica.vector.increment(replica.id) {
    Ok(vector) => vector
    Err(_) => return Err(EmptyReplicaId)
  }
  self.replicas[index] = {
    id: replica.id,
    clock: replica.clock,
    vector: context,
    online: replica.online,
  }
  Ok(self.record(replica.id, stamp, context, Local(label~)))
}

///| Send a causally annotated message. Sending is a local event; delivery is

///|
/// delayed until `advance_to` reaches `deliver_at`.
pub fn Simulator::send(
  self : Simulator,
  source : String,
  target : String,
  payload : String,
  delay : Int,
) -> Result[TraceEvent, SimulatorError] {
  if delay < 0 {
    return Err(NegativeDelay(delay))
  }
  let source_index = match self.replica_index(source) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  match self.replica_index(target) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let replica = self.replicas[source_index]
  if !replica.online {
    return Err(ReplicaOffline(source))
  }
  let stamp = replica.clock.tick(self.time)
  let context = match replica.vector.increment(replica.id) {
    Ok(vector) => vector
    Err(_) => return Err(EmptyReplicaId)
  }
  self.replicas[source_index] = {
    id: replica.id,
    clock: replica.clock,
    vector: context,
    online: replica.online,
  }
  self.pending.push({
    source: replica.id,
    target,
    payload,
    sent_at: self.time,
    deliver_at: self.time + delay,
    stamp,
    context,
  })
  Ok(self.record(replica.id, stamp, context, Sent(target~, payload~)))
}

///| Move simulated time forward and deliver every due message whose target is

///| online. Due messages for an offline target remain queued, modelling a

///|
/// recoverable network partition without inventing a separate transport API.
pub fn Simulator::advance_to(
  self : Simulator,
  next_time : Int,
) -> Result[Array[TraceEvent], SimulatorError] {
  if next_time < self.time {
    return Err(TimeWentBackwards(current=self.time, requested=next_time))
  }
  self.time = next_time
  let delivered : Array[TraceEvent] = []
  let remaining : Array[PendingMessage] = []
  for message in self.pending {
    let target_index = match self.replica_index(message.target) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let target = self.replicas[target_index]
    if message.deliver_at <= self.time && target.online {
      let stamp = target.clock.receive(message.stamp, self.time)
      let merged = target.vector.merge(message.context)
      let context = match merged.increment(target.id) {
        Ok(vector) => vector
        Err(_) => return Err(EmptyReplicaId)
      }
      self.replicas[target_index] = {
        id: target.id,
        clock: target.clock,
        vector: context,
        online: target.online,
      }
      let event = self.record(
        target.id,
        stamp,
        context,
        Received(source=message.source, payload=message.payload),
      )
      delivered.push(event)
    } else {
      remaining.push(message)
    }
  }
  self.pending = remaining
  Ok(delivered)
}

///| Change whether a replica accepts local events and delivered messages. The

///|
/// transition itself is traced so a replay explains why a message was held.
pub fn Simulator::set_online(
  self : Simulator,
  replica_id : String,
  online : Bool,
) -> Result[TraceEvent, SimulatorError] {
  let index = match self.replica_index(replica_id) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let replica = self.replicas[index]
  let stamp = replica.clock.tick(self.time)
  let context = match replica.vector.increment(replica.id) {
    Ok(vector) => vector
    Err(_) => return Err(EmptyReplicaId)
  }
  self.replicas[index] = {
    id: replica.id,
    clock: replica.clock,
    vector: context,
    online,
  }
  Ok(self.record(replica.id, stamp, context, AvailabilityChanged(online~)))
}

///|
/// Look up a replica's current causal vector.
pub fn Simulator::vector_of(
  self : Simulator,
  replica_id : String,
) -> Result[VersionVector, SimulatorError] {
  let index = match self.replica_index(replica_id) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  Ok(self.replicas[index].vector)
}

///|
/// Find a replica index once, keeping public APIs descriptive on bad IDs.
fn Simulator::replica_index(
  self : Simulator,
  replica_id : String,
) -> Result[Int, SimulatorError] {
  for index in 0..<self.replicas.length() {
    if self.replicas[index].id == replica_id {
      return Ok(index)
    }
  }
  Err(UnknownReplica(replica_id))
}

///|
/// Append an event to the trace and return the exact stored value.
fn Simulator::record(
  self : Simulator,
  replica : String,
  stamp : HlcTimestamp,
  context : VersionVector,
  kind : TraceKind,
) -> TraceEvent {
  let event = {
    sequence: self.trace.length() + 1,
    time: self.time,
    replica,
    stamp,
    context,
    kind,
  }
  self.trace.push(event)
  event
}

///|
/// Errors exposed by simulator operations.
pub(all) enum SimulatorError {
  EmptyReplicaId
  DuplicateReplica(String)
  UnknownReplica(String)
  ReplicaOffline(String)
  NegativeSimulationTime(Int)
  NegativeDelay(Int)
  TimeWentBackwards(current~ : Int, requested~ : Int)
} derive(Eq, Debug)
