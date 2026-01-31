# Design: Reintegration

## Motivation

Autonomous agents may operate disconnected for hours or days. When they return, their memory may have diverged from the current state. We need a safe merge protocol.

## Design

### Three-Phase Protocol

**Phase 1: Verification**
- Agent authenticates via Ed25519 signature
- Node compares agent L1 chain_hash with last known hash
- Divergence detected if hashes differ

**Phase 2: Staging**
- Node creates temporary staging group: `staging-{agent_id}-{timestamp}`
- Agent's new memories written to staging group
- Agent gets viewer access to current group state (can see but not write)

**Phase 3: Merge**
- Parent reviews staged memories
- Approve: memories copied to target groups (standard COW share)
- Reject: staging group deleted
- Partial: some memories approved, others rejected

### Divergence Detection

```
Agent chain_hash != Node's last_known_chain_hash

Divergence score = number of sessions since last sync
High divergence (>5 sessions) = mandatory review
Low divergence (1-2 sessions) = auto-merge eligible (if high trust)
```

### Auto-Merge

For agents with trust > 0.85 AND divergence <= 2 sessions, parent MAY pre-authorize automatic merge. This is opt-in per agent and can be revoked at any time.

## Security Considerations

- Staging group isolates incoming memories from production
- Viewer access prevents the agent from overwriting current state
- Parent approval is the final gate (entity sovereignty)
- Auto-merge requires explicit opt-in, never defaults
