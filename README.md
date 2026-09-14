# MoonBit CausalKit

MoonBit CausalKit is a deterministic, pure-MoonBit toolkit for modelling
causal time in distributed systems. It provides Hybrid Logical Clocks (HLC),
version-vector comparison, and a caller-controlled simulator for delayed or
partitioned message delivery.

## Why it exists

Physical timestamps cannot explain whether two writes are causally related,
especially when device clocks drift or messages arrive out of order. CausalKit
keeps that logic as a reusable algorithm library: applications keep control of
networking, persistence, authentication, and wall-clock acquisition.

## Current capabilities

- Validated HLC timestamps and rollback-safe local/remote clock transitions.
- Version vectors with merge, causal comparison, and concurrency detection.
- A deterministic simulator with local events, delayed messages, offline
  replicas, recovery, and append-only causal traces.
- A state-based multi-value register that preserves concurrent values and
  resolves them only after a causally newer write.
- Trace analysis with direct causal edges, concurrent-event pairs, and causal
  layers for debuggers or visualizers.
- Replica acknowledgement tracking and stable-frontier calculation for safe
  event-log compaction decisions.
- A causal operation buffer that holds out-of-order replicated operations until
  their prerequisites and per-replica sequence are present, while deduplicating
  retransmitted dots.
- An immutable operation-log split that turns a stable prefix into a checkpoint
  and preserves the exact replay suffix.
- Dot and DotSet primitives, anti-entropy range planning, replication batches,
  checkpoint validation, and replay-gap detection.
- Observed-remove sets, PN counters, LWW registers, and conflict-preserving
  causal maps as reusable CRDT building blocks.
- Dynamic membership views, clock anomaly diagnostics, vector-distance metrics,
  advanced causal graph queries, and Graphviz/Mermaid-friendly trace export.

## Run locally

Add the package to a MoonBit project:

```text
moon add cauchyQ/moonbit-causalkit
```

Check this repository and run its example:

```text
moon check --deny-warn
moon test --deny-warn
moon run cmd/main
```

The command-line example simulates a message held during a replica outage and
delivered after recovery. The example and all core algorithms run without
network, storage, or runtime dependencies.

## Minimal use

```moonbit
let local = @causal.VersionVector::new().increment("device-a").unwrap()
let remote = @causal.VersionVector::new().increment("device-b").unwrap()
assert_eq(local.compare(remote), @causal.Concurrent)
```

Add `cauchyQ/moonbit-causalkit` to your package imports as `@causal`. Public
types and functions are listed in `pkg.generated.mbti`.

## Scope

This is an algorithm, CRDT-building-block, and simulation library, not a
production replication protocol, database, network transport, cryptographic
identity system, or consensus implementation. The narrow boundary keeps its
behavior reproducible across native, JavaScript, and WebAssembly targets.

The implementation is original and AI-assisted. It does not copy or port an
upstream codebase and uses no runtime dependencies or third-party test data.

## License

Apache-2.0. See `LICENSE`.
