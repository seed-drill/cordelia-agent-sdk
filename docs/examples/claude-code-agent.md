# Example: Claude Code Agent Lifecycle

This example demonstrates the full lifecycle of a Claude Code agent from registration through memory operations to deactivation.

## 1. Registration

Russell starts a Claude Code session. The session hook calls `agent_register`:

```json
// Request
{
  "tool": "agent_register",
  "args": {
    "parent_entity_id": "russell_wing",
    "agent_type": "claude-code",
    "display_name": "Russell's Claude Code - Session 45",
    "capabilities": {
      "memory_read": {
        "layers": ["l1", "l2"],
        "groups": ["seed-drill"],
        "visibility": ["private", "group"]
      },
      "memory_write": {
        "layers": ["l1", "l2"],
        "groups": ["seed-drill"],
        "visibility": ["private", "group"]
      },
      "tools": [
        "memory_read_hot", "memory_write_hot", "memory_search",
        "memory_read_warm", "memory_write_warm", "memory_delete_warm",
        "memory_share", "memory_analyze_novelty"
      ],
      "max_parallel_ops": 5,
      "ttl_seconds": 0,
      "autonomous": false
    }
  }
}

// Response
{
  "agent_id": "7a3f9c1e2b...",
  "public_key": "MCowBQYDK2VwAyEA...",
  "private_key_encrypted": "..."
}
```

## 2. L1 Context Loaded

The agent's L1 is loaded (or created fresh):

```json
{
  "version": 1,
  "updated_at": "2026-01-31T16:34:00Z",
  "identity": {
    "id": "7a3f9c1e2b...",
    "name": "Russell's Claude Code - Session 45",
    "roles": ["agent"],
    "orgs": [{"id": "seed_drill", "name": "Seed Drill", "role": "agent"}],
    "key_refs": [],
    "style": []
  },
  "active": {
    "project": "cordelia",
    "sprint": 8,
    "focus": "R2 hardening",
    "blockers": [],
    "next": [],
    "context_refs": []
  },
  "prefs": {
    "planning_mode": "important",
    "feedback_style": "continuous",
    "verbosity": "concise",
    "emoji": false,
    "proactive_suggestions": true,
    "auto_commit": false
  },
  "delegation": {
    "allowed": false,
    "max_parallel": 1,
    "require_approval": [],
    "autonomous": []
  },
  "agent": {
    "parent_entity_id": "russell_wing",
    "agent_type": "claude-code",
    "capabilities": { "..." },
    "task": null,
    "working_memory": {},
    "event_queue": []
  }
}
```

## 3. Memory Operations

### Reading L2 (search for relevant memories)

```json
// Tool call
{ "tool": "memory_search", "args": { "query": "SQLite storage", "limit": 5 } }

// Results filtered by agent capabilities (only seed-drill group + private)
{ "results": ["entity-sqlite-provider", "learning-wal-mode", ...] }
```

### Writing L2 (persist a new learning)

```json
{
  "tool": "memory_write_warm",
  "args": {
    "type": "learning",
    "data": {
      "type": "insight",
      "content": "NodeStorageProvider needs health check caching to avoid hammering the node API",
      "confidence": 0.8,
      "tags": ["architecture", "performance", "cordelia"]
    }
  }
}
```

### Sharing to group

```json
{
  "tool": "memory_share",
  "args": {
    "item_id": "learning-health-check-cache",
    "target_group": "seed-drill",
    "entity_id": "7a3f9c1e2b..."
  }
}
// COW copy created, original unchanged
```

## 4. Session End

Session hook fires `session-end.mjs 7a3f9c1e2b...`:

- L1 updated with session summary
- Chain hash computed
- Session count incremented

## 5. Deactivation

When the Claude Code session ends:

```json
{
  "tool": "agent_deactivate",
  "args": { "agent_id": "7a3f9c1e2b..." }
}
```

- Agent status -> `deactivated`
- L1 archived as L2 session record
- Grace period starts (7 days)
- After grace: agent removed, L1 deleted
