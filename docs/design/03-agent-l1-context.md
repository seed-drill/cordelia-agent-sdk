# Design: Agent L1 Context

## Motivation

Each agent needs persistent state across sessions: working memory, task progress, event queue. Reusing the existing L1 infrastructure (user_id-keyed hot context) gives this for free.

## Design

### Storage Key

```
L1 key: user_id = agent_id
```

Standard L1 read/write operations work unchanged. The agent's L1 is just another entry in the `l1_hot` table.

### Extended Schema

The `agent` field extends the standard L1:

```json
{
  "version": 1,
  "identity": { "id": "agent_id", "name": "Agent Display Name", ... },
  "active": { ... },
  "prefs": { ... },
  "delegation": { ... },
  "ephemeral": { ... },
  "agent": {
    "parent_entity_id": "russell_wing",
    "agent_type": "swarm-worker",
    "capabilities": { ... },
    "task": { "goal": "...", "progress": 0.4, "findings": [...] },
    "working_memory": { ... },
    "event_queue": [...]
  }
}
```

### Session Hooks

Session hooks fire per-agent:
```bash
session-start.mjs <agent_id>
session-end.mjs <agent_id>
```

This gives each agent independent:
- Session count and chain hash
- Session summaries (L2 archival)
- Integrity verification

### Archival on Deactivation

When an agent is deactivated, its L1 context is persisted as an L2 session record before deletion. This preserves the agent's final state for future reference.

## Security Considerations

- Agents can only read/write their own L1
- Parent can read (but not write) child L1 for supervision
- L1 encryption uses the same key as the parent's context (derived from CORDELIA_ENCRYPTION_KEY)
