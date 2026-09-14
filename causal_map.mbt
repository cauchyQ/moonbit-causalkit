///|
/// One key and its conflict-preserving register.
pub(all) struct CausalMapEntry {
  key : String
  register : MultiValueRegister
} derive(Debug)

///|
/// A removed key and the context observed by the removal.
pub(all) struct CausalMapTombstone {
  key : String
  context : VersionVector
} derive(Eq, Debug)

///| A string map whose values preserve concurrent writes. Removing a key only

///|
/// suppresses writes observed by that removal; a concurrent put survives.
pub struct CausalMap {
  entries : Array[CausalMapEntry]
  tombstones : Array[CausalMapTombstone]
  context : VersionVector
} derive(Debug)

///|
/// Causal-map validation failures.
pub(all) enum CausalMapError {
  EmptyMapKey
  EmptyMapWriter
} derive(Eq, Debug)

///|
/// Create an empty map.
pub fn CausalMap::new() -> CausalMap {
  { entries: [], tombstones: [], context: VersionVector::new() }
}

///|
/// Visible entries.
pub fn CausalMap::entries(self : CausalMap) -> Array[CausalMapEntry] {
  let output : Array[CausalMapEntry] = []
  for entry in self.entries {
    output.push(entry)
  }
  output
}

///|
/// Retained removal contexts.
pub fn CausalMap::tombstones(self : CausalMap) -> Array[CausalMapTombstone] {
  let output : Array[CausalMapTombstone] = []
  for tombstone in self.tombstones {
    output.push(tombstone)
  }
  output
}

///|
/// Causal history observed by this map, including removed values.
pub fn CausalMap::context(self : CausalMap) -> VersionVector {
  self.context
}

///|
/// Visible keys.
pub fn CausalMap::keys(self : CausalMap) -> Array[String] {
  let output : Array[String] = []
  for entry in self.entries {
    output.push(entry.key)
  }
  output
}

///|
/// Find a visible register by key.
pub fn CausalMap::get(self : CausalMap, key : String) -> MultiValueRegister? {
  for entry in self.entries {
    if entry.key == key {
      return Some(entry.register)
    }
  }
  None
}

///|
/// Whether a key is visible.
pub fn CausalMap::contains_key(self : CausalMap, key : String) -> Bool {
  self.get(key) is Some(_)
}

///|
/// Put a new value using the register's current causal context.
pub fn CausalMap::put(
  self : CausalMap,
  key : String,
  writer : String,
  value : String,
) -> Result[CausalMap, CausalMapError] {
  if key.length() == 0 {
    return Err(EmptyMapKey)
  }
  if writer.length() == 0 {
    return Err(EmptyMapWriter)
  }
  let context = self.context.increment(writer).unwrap()
  let current = match self.get(key) {
    Some(register) => register
    None => MultiValueRegister::new()
  }
  let register = current.apply({ value, writer, context })
  Ok(self.set_entry({ key, register }, context))
}

///|
/// Remove the currently observed versions of a key.
pub fn CausalMap::remove(
  self : CausalMap,
  key : String,
) -> Result[CausalMap, CausalMapError] {
  if key.length() == 0 {
    return Err(EmptyMapKey)
  }
  match self.get(key) {
    None => Ok(self)
    Some(register) => {
      let entries : Array[CausalMapEntry] = []
      for entry in self.entries {
        if entry.key != key {
          entries.push(entry)
        }
      }
      Ok({
        entries,
        tombstones: cmap_upsert_tombstone(self.tombstones, {
          key,
          context: register.context(),
        }),
        context: self.context,
      })
    }
  }
}

///|
/// Merge independently updated map states.
pub fn CausalMap::merge(self : CausalMap, other : CausalMap) -> CausalMap {
  let mut tombstones = self.tombstones
  for tombstone in other.tombstones {
    tombstones = cmap_upsert_tombstone(tombstones, tombstone)
  }
  let mut entries : Array[CausalMapEntry] = []
  for entry in self.entries {
    entries = cmap_merge_entry(entries, entry)
  }
  for entry in other.entries {
    entries = cmap_merge_entry(entries, entry)
  }
  let visible : Array[CausalMapEntry] = []
  for entry in entries {
    let filtered = cmap_filter_removed(
      entry.register,
      cmap_tombstone_context(tombstones, entry.key),
    )
    if filtered.values().length() > 0 {
      visible.push({ key: entry.key, register: filtered })
    }
  }
  { entries: visible, tombstones, context: self.context.merge(other.context) }
}

///|
/// Compact removal contexts already covered by a stable frontier.
pub fn CausalMap::compact(
  self : CausalMap,
  stable_frontier : VersionVector,
) -> CausalMap {
  let tombstones : Array[CausalMapTombstone] = []
  for tombstone in self.tombstones {
    if !tombstone.context.happens_before(stable_frontier) {
      tombstones.push(tombstone)
    }
  }
  { entries: self.entries, tombstones, context: self.context }
}

///|
fn CausalMap::set_entry(
  self : CausalMap,
  candidate : CausalMapEntry,
  context : VersionVector,
) -> CausalMap {
  let entries : Array[CausalMapEntry] = []
  let mut found = false
  for entry in self.entries {
    if entry.key == candidate.key {
      entries.push(candidate)
      found = true
    } else {
      entries.push(entry)
    }
  }
  if !found {
    entries.push(candidate)
  }
  { entries, tombstones: self.tombstones, context }
}

///|
fn cmap_merge_entry(
  entries : Array[CausalMapEntry],
  candidate : CausalMapEntry,
) -> Array[CausalMapEntry] {
  let output : Array[CausalMapEntry] = []
  let mut found = false
  for entry in entries {
    if entry.key == candidate.key {
      output.push({
        key: entry.key,
        register: entry.register.merge(candidate.register),
      })
      found = true
    } else {
      output.push(entry)
    }
  }
  if !found {
    output.push(candidate)
  }
  output
}

///|
fn cmap_upsert_tombstone(
  tombstones : Array[CausalMapTombstone],
  candidate : CausalMapTombstone,
) -> Array[CausalMapTombstone] {
  let output : Array[CausalMapTombstone] = []
  let mut found = false
  for tombstone in tombstones {
    if tombstone.key == candidate.key {
      output.push({
        key: tombstone.key,
        context: tombstone.context.merge(candidate.context),
      })
      found = true
    } else {
      output.push(tombstone)
    }
  }
  if !found {
    output.push(candidate)
  }
  output
}

///|
fn cmap_tombstone_context(
  tombstones : Array[CausalMapTombstone],
  key : String,
) -> VersionVector {
  for tombstone in tombstones {
    if tombstone.key == key {
      return tombstone.context
    }
  }
  VersionVector::new()
}

///|
fn cmap_filter_removed(
  register : MultiValueRegister,
  removed : VersionVector,
) -> MultiValueRegister {
  let mut output = MultiValueRegister::new()
  for value in register.values() {
    if !value.context.happens_before(removed) {
      output = output.apply(value)
    }
  }
  output
}
