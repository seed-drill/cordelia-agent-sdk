# Example: Minimal Agent

The absolute minimum to register and operate an agent.

## Registration

```json
{
  "tool": "agent_register",
  "args": {
    "parent_entity_id": "russell_wing",
    "agent_type": "custom",
    "display_name": "Minimal Agent",
    "capabilities": {
      "memory_read": { "layers": ["l2"], "groups": [], "visibility": ["public"] },
      "tools": ["memory_search", "memory_read_warm"],
      "max_parallel_ops": 1,
      "ttl_seconds": 300,
      "autonomous": false
    }
  }
}
```

This agent can:
- Search public L2 memories
- Read public L2 items
- Nothing else

It expires after 5 minutes.

## Operation

```json
// Search
{ "tool": "memory_search", "args": { "query": "deployment guide", "limit": 3 } }

// Read a result
{ "tool": "memory_read_warm", "args": { "id": "entity-deploy-guide" } }
```

## Deactivation

Automatic after `ttl_seconds` (300s). No manual intervention needed.
