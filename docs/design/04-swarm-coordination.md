# Design: Swarm Coordination (Minsky Society of Mind)

## Motivation

Complex tasks benefit from multiple specialized agents working together. Minsky's Society of Mind insight: intelligence emerges from the interaction of simple, specialized agents.

## Design

### Swarm = Group + Manifest + Agents

A swarm is not a new primitive. It is a group (existing primitive) with a manifest (metadata) and registered agents (existing entities). The power comes from the coordination strategy, not new infrastructure.

### Coordination Strategies

**Broadcast** (all see all):
```
Agent A writes -> group replicates to B, C, D
Agent B writes -> group replicates to A, C, D
```
Best for: small swarms, brainstorming, consensus-building.

**Pipeline** (sequential):
```
Agent A writes -> B reads -> B writes -> C reads -> C writes -> output
```
Best for: data processing, transformation chains, refinement.

**Hierarchical** (lead delegates):
```
Coordinator assigns tasks to workers
Workers report results to coordinator
Coordinator synthesizes
```
Best for: complex multi-phase tasks, research + analysis + synthesis.

### Culture Defaults

Swarm groups default to:
- `broadcast_eagerness: "chatty"` - maximize coherence
- `notification_policy: "push"` - immediate awareness
- `departure_policy: "permissive"` - easy cleanup
- `ttl_default: 86400` - auto-expire after 24h

### Lifecycle

```
swarm_create(manifest) -> Node
  Node: createGroup(swarm_id, ...)
  Node: for each agent slot: agent_register(...)
  Node: add all agents as members
  Node: coordinator begins execution

... execution ...

swarm_disband(swarm_id) -> Node
  Node: archive group (L2 session summary)
  Node: deactivate all swarm agents
  Node: coordinator synthesizes findings
```

## Security Considerations

- Swarm group boundary prevents information leaking to non-members
- Worker agents cannot access groups outside the swarm
- Coordinator has same capabilities as parent (cannot escalate)
- Swarm memory expires via TTL (natural selection)

## Open Questions

1. Dynamic scaling: add/remove agents during execution?
2. Fault tolerance: agent crashes mid-task?
3. Inter-swarm communication: two swarms collaborating?
