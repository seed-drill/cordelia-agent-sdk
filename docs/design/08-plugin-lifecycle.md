# Design: Plugin Lifecycle

## Motivation

Agents need clear lifecycle states for resource management, security, and operational clarity. The lifecycle mirrors standard service management patterns.

## Design

### State Machine

```
           +----------+
           |registered|
           +-----+----+
                 |  first operation
                 v
           +-----+----+
      +--->|  active   |<---+
      |    +-----+----+    |
      |          |         |
resume|   suspend|   reactivate
      |          v         |
      |    +-----+----+   |
      +----+ suspended +---+
           +-----+----+
                 |  TTL / parent / task complete
                 v
           +-----+------+
           |deactivated |
           +-----+------+
                 |  grace period expires
                 v
           +-----+---+
           | removed  |
           +---------+
```

### Grace Period

Default: 7 days. Configurable per agent at registration.

During grace period:
- L1 archived but preserved
- No operations allowed
- Parent can reactivate
- Group memberships retained (inactive)

After grace period:
- L1 deleted
- Group memberships removed
- Trust scores retained (historical record)

### Archival

On deactivation, the agent's final L1 state is written to L2 as a session summary. This preserves:
- What the agent was working on
- Accumulated findings
- Final working memory

## Security Considerations

- Suspended agents cannot make API calls
- Deactivated agents' keys are invalidated
- Grace period prevents accidental data loss
- Removal is permanent and irreversible
