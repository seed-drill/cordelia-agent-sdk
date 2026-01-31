# Design: Memory Scoping

## Motivation

Different agent types need different levels of memory access. A swarm worker researching a topic should not be able to read the parent's private memories. The scoping matrix provides clear defaults.

## Design

### Default Matrix

| Agent Type | L1 Own | L2 Private | L2 Group | L2 Public |
|---|---|---|---|---|
| Parent's Claude Code | RW | RW | Per membership | R |
| Swarm worker | RW | None | Swarm group only | R |
| External agent | RW | None | Approved groups | R |
| Untrusted | R own | None | None | R |

### Rule Precedence

1. Entity sovereignty (always enforced, cannot be overridden)
2. Capabilities (declared at registration, may restrict)
3. Trust tier (may expand within capability bounds)
4. Group membership (standard group rules apply)

### Key Invariant

Trust can EXPAND access (within capability bounds). Capabilities can RESTRICT access (below parent level). Neither can violate entity sovereignty.

```
effective_access = min(capabilities, max(trust_tier_default, explicit_grants))
```

But always: entity sovereignty > everything else.

### Context Bindings

Memory scoping interacts with context bindings (directory -> group mapping). When an agent operates in a bound directory, it sees the bound group's memories. This is additive to the agent's existing scoping.

## Security Considerations

- Swarm workers cannot escape their swarm group boundary
- External agents start with minimal access
- L2 private access is never default for non-parent agents
- Every access decision is logged to access_log
