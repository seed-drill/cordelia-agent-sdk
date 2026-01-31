# Claude Configuration - Cordelia Agent SDK

## Project Context

This repository contains the formal specification for the Cordelia Agent SDK -- defining how AI agents participate in Cordelia's memory network with first-class identity, capabilities, trust, and swarm coordination.

## Related Projects

- **cordelia-core**: Rust implementation (node, protocol, storage, crypto, API)
- **cordelia-proxy**: TypeScript MCP server, hooks, skills, dashboard

## Key Principles

1. Agents ARE entities (agent_id = entity_id)
2. Least-privilege capability inheritance from parent
3. Entity sovereignty: compromised groups cannot force content into agent memory
4. Trust is empirical (accuracy over time), not reputational
5. Swarms map to groups with chatty culture

## License

AGPL-3.0-only

## Organization

Seed Drill - https://github.com/seed-drill
