# Cordelia Agent SDK

Formal specification for agent identity, capabilities, trust, and swarm coordination in Cordelia.

## What is Cordelia?

[Cordelia](https://github.com/seed-drill/cordelia-core) is a distributed persistent memory system for autonomous AI agents. It provides end-to-end encrypted, sovereign memory that agents control -- solving the session amnesia problem where every conversation starts from zero. Read the [whitepaper](https://github.com/seed-drill/cordelia-core/blob/main/WHITEPAPER.md) for the full design.

## Why This Exists

MCP provides transport -- but no formal model for agent identity, capabilities, trust, swarm coordination, or memory scoping. This spec defines the contract that agents implement to participate in the Cordelia memory network.

## Core Principle

**Agents are entities.** An `agent_id` is an `entity_id`. Every Cordelia primitive -- groups, memory scoping, trust, sharing -- works identically with agents. No special cases.

## Documents

| Document | Description |
|----------|-------------|
| [SPEC.md](SPEC.md) | Formal specification (primary deliverable) |
| [docs/design/](docs/design/) | Design documents with rationale |
| [schemas/](schemas/) | JSON Schema definitions (draft 2020-12) |
| [docs/examples/](docs/examples/) | Worked examples |

## Quick Start

1. Read [SPEC.md](SPEC.md) for the full specification
2. Browse [schemas/](schemas/) for machine-readable type definitions
3. See [docs/examples/claude-code-agent.md](docs/examples/claude-code-agent.md) for a lifecycle walkthrough

## Related Repositories

- [cordelia-core](https://github.com/seed-drill/cordelia-core) - Rust node, protocol, storage, crypto, API
- [cordelia-proxy](https://github.com/seed-drill/cordelia-proxy) - TypeScript MCP server, dashboard, hooks

## Release Targets

| Sections | Target |
|----------|--------|
| 1-3, 7-8 (Identity, Capabilities, L1, Scoping, Lifecycle) | R3 |
| 4, 9 (Swarm, Events) | R3/R4 |
| 5-6 (Trust, Reintegration) | R4 |

## License

AGPL-3.0-only. See [LICENSE](LICENSE).

---

*Cordelia: persistent memory for AI agents.*
