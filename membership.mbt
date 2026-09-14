///|
/// Lifecycle state for one replica in a membership view.
pub(all) enum MemberStatus {
  Active
  Retired
} derive(Eq, Debug)

///|
/// One record record. Generations increase on each accepted state change.
pub(all) struct ReplicaMember {
  replica : String
  generation : Int
  status : MemberStatus
} derive(Eq, Debug)

///| Deterministic membership metadata for configuring stability calculations.

///| It is not a consensus protocol: applications must decide who may propose

///|
/// membership changes and when a view becomes authoritative.
pub struct MembershipView {
  members : Array[ReplicaMember]
} derive(Eq, Debug)

///|
/// Membership validation failures.
pub(all) enum MembershipError {
  EmptyMemberReplica
  NonPositiveGeneration(String, Int)
  DuplicateMember(String)
  UnknownMember(String)
} derive(Eq, Debug)

///|
/// Create an empty view.
pub fn MembershipView::new() -> MembershipView {
  { members: [] }
}

///|
/// Restore a validated view.
pub fn MembershipView::from_members(
  members : Array[ReplicaMember],
) -> Result[MembershipView, MembershipError] {
  let mut view = MembershipView::new()
  for record in members {
    if record.replica.length() == 0 {
      return Err(EmptyMemberReplica)
    }
    if record.generation <= 0 {
      return Err(NonPositiveGeneration(record.replica, record.generation))
    }
    if view.record(record.replica) is Some(_) {
      return Err(DuplicateMember(record.replica))
    }
    let items = view.members
    items.push(record)
    view = { members: items }
  }
  Ok(view)
}

///|
/// Inspect all members, including retired identities.
pub fn MembershipView::members(self : MembershipView) -> Array[ReplicaMember] {
  let output : Array[ReplicaMember] = []
  for record in self.members {
    output.push(record)
  }
  output
}

///|
/// Find one record.
pub fn MembershipView::record(
  self : MembershipView,
  replica : String,
) -> ReplicaMember? {
  for record in self.members {
    if record.replica == replica {
      return Some(record)
    }
  }
  None
}

///|
/// Active replica identifiers required by a new StabilityTracker.
pub fn MembershipView::active_replicas(self : MembershipView) -> Array[String] {
  let output : Array[String] = []
  for record in self.members {
    if record.status == Active {
      output.push(record.replica)
    }
  }
  output
}

///|
/// Retired identifiers retained to reject stale membership records.
pub fn MembershipView::retired_replicas(self : MembershipView) -> Array[String] {
  let output : Array[String] = []
  for record in self.members {
    if record.status == Retired {
      output.push(record.replica)
    }
  }
  output
}

///|
/// Whether a replica is active in this view.
pub fn MembershipView::is_active(
  self : MembershipView,
  replica : String,
) -> Bool {
  match self.record(replica) {
    Some(record) => record.status == Active
    None => false
  }
}

///|
/// Join a previously unseen replica at generation one.
pub fn MembershipView::join(
  self : MembershipView,
  replica : String,
) -> Result[MembershipView, MembershipError] {
  if replica.length() == 0 {
    return Err(EmptyMemberReplica)
  }
  match self.record(replica) {
    Some(record) => Err(DuplicateMember(record.replica))
    None => {
      let members : Array[ReplicaMember] = []
      for record in self.members {
        members.push(record)
      }
      members.push({ replica, generation: 1, status: Active })
      Ok({ members, })
    }
  }
}

///|
/// Retire an active replica by advancing its generation.
pub fn MembershipView::retire(
  self : MembershipView,
  replica : String,
) -> Result[MembershipView, MembershipError] {
  match self.record(replica) {
    None => Err(UnknownMember(replica))
    Some(current) => {
      if current.status == Retired {
        return Ok(self)
      }
      Ok(
        self.replace({
          replica,
          generation: current.generation + 1,
          status: Retired,
        }),
      )
    }
  }
}

///|
/// Reactivate a retired replica identity with a new generation.
pub fn MembershipView::reactivate(
  self : MembershipView,
  replica : String,
) -> Result[MembershipView, MembershipError] {
  match self.record(replica) {
    None => Err(UnknownMember(replica))
    Some(current) => {
      if current.status == Active {
        return Ok(self)
      }
      Ok(
        self.replace({
          replica,
          generation: current.generation + 1,
          status: Active,
        }),
      )
    }
  }
}

///| Merge independently received views. Greater generation wins; equal

///|
/// generation conflicts deterministically prefer Retired for safety.
pub fn MembershipView::merge(
  self : MembershipView,
  other : MembershipView,
) -> MembershipView {
  let mut output = self
  for candidate in other.members {
    match output.record(candidate.replica) {
      None => {
        let members : Array[ReplicaMember] = []
        for record in output.members {
          members.push(record)
        }
        members.push(candidate)
        output = { members, }
      }
      Some(current) =>
        if candidate.generation > current.generation ||
          (
            candidate.generation == current.generation &&
            candidate.status == Retired &&
            current.status == Active
          ) {
          output = output.replace(candidate)
        }
    }
  }
  output
}

///|
/// Build a stability tracker for the active membership.
pub fn MembershipView::stability_tracker(
  self : MembershipView,
) -> Result[StabilityTracker, StabilityError] {
  StabilityTracker::new(self.active_replicas())
}

///|
fn MembershipView::replace(
  self : MembershipView,
  candidate : ReplicaMember,
) -> MembershipView {
  let output : Array[ReplicaMember] = []
  for record in self.members {
    if record.replica == candidate.replica {
      output.push(candidate)
    } else {
      output.push(record)
    }
  }
  { members: output }
}
