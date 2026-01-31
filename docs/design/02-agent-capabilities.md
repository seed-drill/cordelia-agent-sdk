# Design: Agent Capabilities

## Motivation

Without formal capability scoping, agents either get full access (dangerous) or no access (useless). The capability model provides fine-grained, inheritable, revocable permissions.

## Design

### Least-Privilege Inheritance

```
C(agent) <= C(parent)
```

This is enforced at registration time AND at runtime. Even if a parent's capabilities are later reduced, existing children's effective capabilities shrink accordingly.

### Scope Dimensions

| Dimension | Controls | Example |
|-----------|----------|---------|
| memory_read.layers | Which memory layers | ["l1", "l2"] |
| memory_read.groups | Which groups | ["seed-drill", "swarm-*"] |
| memory_read.visibility | Which visibility levels | ["private", "group"] |
| memory_write | Same structure as read | |
| tools | Which MCP tools | ["memory_search", "memory_read_warm"] |
| max_parallel_ops | Concurrency limit | 5 |
| ttl_seconds | Agent lifetime | 3600 |
| autonomous | Unsupervised operation | false |

### Glob Patterns

Group IDs support glob patterns:
- `seed-drill` - exact match
- `swarm-*` - any group starting with "swarm-"
- `*` - all groups (only if parent has `*`)

### Runtime Enforcement

Every MCP tool call checks capabilities:
1. Is the tool in `capabilities.tools`?
2. Does the operation's target group match `capabilities.memory_*.groups`?
3. Is the visibility level in `capabilities.memory_*.visibility`?
4. Is the agent under `max_parallel_ops`?
5. Has `ttl_seconds` expired?

Failure returns `{ error: "capability_denied", detail: "..." }`.

### Revocation

```
parent -> agent_capabilities(agent_id, new_caps) -> Node
```

Revocation is immediate. In-flight operations that violate new caps are terminated.

## Security Considerations

- Capability checks happen at the storage layer (not just tool layer)
- Glob patterns cannot match groups the parent doesn't have access to
- TTL is wall-clock enforced by the node

## Open Questions

1. Should capabilities support time-of-day restrictions?
2. Rate limiting per capability dimension?
