# Design: Event Model

## Motivation

Agents need to know when things happen: new memories written, members joining/leaving, trust changes. Without events, agents must poll -- wasteful and high-latency.

## Design

### Event Types

| Event | Payload | Trigger |
|-------|---------|---------|
| `memory.written` | item_id, type, group_id | L2 write |
| `group.member_joined` | group_id, entity_id, role | Member added |
| `group.member_left` | group_id, entity_id | Member removed |
| `swarm.task_complete` | swarm_id, agent_id, result | Agent finishes |
| `trust.score_changed` | agent_id, old, new | Trust updated |
| `agent.status_changed` | agent_id, old, new | Lifecycle transition |

### Delivery: Push vs Poll

**MCP Notification** (preferred):
- Server sends notification to client via MCP transport
- Real-time, no polling overhead
- Requires bidirectional MCP support

**L1 Event Queue** (fallback):
- Events appended to `agent.event_queue` in L1
- Agent reads queue at session start
- Queue cleared after read

### Subscriptions

Agents subscribe to event types at registration. Subscriptions respect capability scoping -- cannot subscribe to events from inaccessible groups.

```json
{
  "subscriptions": [
    { "event": "memory.written", "filter": { "group_id": "seed-drill" } },
    { "event": "swarm.task_complete", "filter": { "swarm_id": "swarm-*" } }
  ]
}
```

### Ordering

Events are ordered by timestamp. No global ordering guarantee across nodes -- eventual consistency applies.

## Security Considerations

- Event payloads contain metadata only, not memory content
- Subscription filtering prevents information leakage
- L1 event queue encrypted at rest (same as L1 context)
