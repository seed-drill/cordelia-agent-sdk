# Cordelia Agent SDK Specification

**Version**: 0.1.0 (Draft)
**Status**: R3/R4 Target
**License**: AGPL-3.0-only

---

## 1. Agent Identity

### 1.1 Core Principle

An agent is an entity. Every agent receives a unique `agent_id` that is interchangeable with `entity_id` throughout Cordelia. Agents participate in groups, own memories, build trust scores, and share content using the same primitives as human entities.

### 1.2 Agent Record

```
{
  agent_id:          string     // Ed25519 public key hash (SHA-256, hex)
  parent_entity_id:  string     // Entity that registered this agent
  agent_type:        AgentType  // Classification
  display_name:      string     // Human-readable label
  created_at:        string     // ISO 8601
  public_key:        string     // Ed25519 public key (base64)
  status:            AgentStatus
}
```

### 1.3 Agent Types

| Type | Description | Typical Lifetime |
|------|-------------|-----------------|
| `claude-code` | Claude Code CLI session agent | Session-bound |
| `swarm-worker` | Task-specific agent within a swarm | Task-bound |
| `autonomous` | Long-running independent agent | Indefinite |
| `custom` | Third-party or user-defined agent | Varies |

### 1.4 Registration

Parent entity calls `agent_register` MCP tool:

**Request:**
```json
{
  "parent_entity_id": "russell_wing",
  "agent_type": "claude-code",
  "display_name": "Russell's Claude Code Session",
  "capabilities": { ... }
}
```

**Process:**
1. Node generates Ed25519 keypair for agent
2. `agent_id` = SHA-256(public_key) as hex
3. L1 entry created with `user_id = agent_id`
4. Agent registered in `entities` table
5. Keypair returned to caller (private key encrypted with parent's key)

**Response:**
```json
{
  "agent_id": "a1b2c3...",
  "public_key": "base64...",
  "private_key_encrypted": "base64..."
}
```

### 1.5 Identity Verification

Agents authenticate via Ed25519 signature over a challenge nonce. The node verifies the signature against the stored public key. This applies to:
- API calls (bearer token derived from keypair)
- Reintegration after autonomous operation
- Cross-node identity verification

---

## 2. Agent Capabilities

### 2.1 Capability Model

Capabilities are declared at registration by the parent entity. An agent's capabilities MUST NOT exceed its parent's permissions (least-privilege inheritance).

### 2.2 Capability Schema

```json
{
  "memory_read": {
    "layers": ["l1", "l2"],
    "groups": ["seed-drill", "swarm-*"],
    "visibility": ["private", "group"]
  },
  "memory_write": {
    "layers": ["l1", "l2"],
    "groups": ["seed-drill"],
    "visibility": ["private", "group"]
  },
  "tools": ["memory_read_hot", "memory_write_hot", "memory_search"],
  "max_parallel_ops": 5,
  "ttl_seconds": 3600,
  "autonomous": false
}
```

### 2.3 Capability Fields

| Field | Type | Description |
|-------|------|-------------|
| `memory_read` | MemoryScope | What the agent can read |
| `memory_write` | MemoryScope | What the agent can write |
| `tools` | string[] | Allowed MCP tool names (whitelist) |
| `max_parallel_ops` | number | Concurrent operation limit |
| `ttl_seconds` | number | Agent lifetime (0 = no limit) |
| `autonomous` | boolean | Can operate without parent supervision |

### 2.4 Inheritance Rule

For any capability C requested for agent A with parent P:
- `C(A) <= C(P)` must hold
- Groups: `A.groups` must be a subset of `P.groups`
- Tools: `A.tools` must be a subset of `P.tools`
- Layers: `A.layers` must be a subset of `P.layers`

### 2.5 Revocation

Parent can revoke or modify capabilities at any time via `agent_capabilities` tool. Revocation is immediate and affects all in-flight operations.

---

## 3. Agent-Specific L1 Context

### 3.1 Per-Agent L1

Each agent gets its own L1 hot context entry, stored with `user_id = agent_id`. This enables per-agent session continuity, working memory, and hook execution.

### 3.2 Extended Schema

Agent L1 extends the standard entity L1 with:

```json
{
  "version": 1,
  "updated_at": "...",
  "identity": { ... },
  "active": { ... },
  "prefs": { ... },
  "delegation": { ... },
  "ephemeral": { ... },
  "agent": {
    "parent_entity_id": "russell_wing",
    "agent_type": "claude-code",
    "capabilities": { ... },
    "task": {
      "goal": "Implement feature X",
      "context": ["file1.ts", "file2.ts"],
      "progress": 0.6,
      "findings": []
    },
    "working_memory": {}
  }
}
```

### 3.3 Session Hooks

Session hooks fire per-agent with `agent_id` as the user parameter. This gives each agent independent session chains, integrity hashes, and session counts.

---

## 4. Swarm Coordination

### 4.1 Swarm Model (Minsky Society of Mind)

A swarm is a set of agents collaborating on a shared goal. Each swarm maps to a Cordelia group, with a manifest describing the coordination strategy.

### 4.2 Swarm Manifest

```json
{
  "swarm_id": "swarm-research-2026-01-31",
  "goal": "Research competitive landscape and synthesize findings",
  "group_id": "swarm-research-2026-01-31",
  "coordinator_agent_id": "a1b2c3...",
  "strategy": "hierarchical",
  "agents": [
    {
      "slot": "researcher",
      "agent_type": "swarm-worker",
      "capabilities": { ... },
      "count": 3
    },
    {
      "slot": "synthesizer",
      "agent_type": "swarm-worker",
      "capabilities": { ... },
      "count": 1
    }
  ],
  "culture": {
    "broadcast_eagerness": "chatty",
    "ttl_default": 86400,
    "notification_policy": "push",
    "departure_policy": "permissive"
  }
}
```

### 4.3 Coordination Strategies

| Strategy | Description | Use Case |
|----------|-------------|----------|
| `broadcast` | All agents see all memories in real-time | Small swarms, high coherence |
| `pipeline` | Sequential: output of A feeds input of B | Data processing chains |
| `hierarchical` | Lead agent delegates, workers report back | Complex multi-phase tasks |

### 4.4 Swarm Lifecycle

```
create -> agents register -> execute -> synthesize -> archive/disband
```

1. **Create**: Parent calls `swarm_create` with manifest
2. **Register**: Node spawns agents per manifest slots
3. **Execute**: Agents operate per strategy, sharing via group
4. **Synthesize**: Coordinator merges findings
5. **Archive/Disband**: Group archived or deleted, agents deactivated

### 4.5 Swarm Group Culture

Swarm groups default to `chatty` broadcast_eagerness -- all writes are eagerly replicated to all swarm members. This maximizes coherence within the swarm while the group boundary prevents information leaking to non-members.

---

## 5. Agent Trust

### 5.1 Trust Model

Trust is empirical, not reputational. Each entity maintains per-agent trust scores based on observed accuracy over time. Trust feeds into memory scoping: higher-trust agents see more.

### 5.2 Trust Score

```json
{
  "agent_id": "a1b2c3...",
  "observer_entity_id": "russell_wing",
  "accuracy": 0.87,
  "observations": 42,
  "window_start": "2026-01-01T00:00:00Z",
  "window_end": "2026-01-31T00:00:00Z",
  "last_updated": "2026-01-31T16:00:00Z"
}
```

### 5.3 Accuracy Measurement

Accuracy = (confirmed correct memories) / (total memories assessed)

Assessment happens through:
- Explicit user feedback ("this is wrong/right")
- Cross-reference with other trusted sources
- Temporal validation (predictions that came true)

### 5.4 Trust Tiers

| Tier | Accuracy Range | Memory Access |
|------|---------------|---------------|
| Untrusted | < 0.3 | Own L1 only, public L2 read |
| Low | 0.3 - 0.6 | Own L1 RW, approved group L2 read |
| Medium | 0.6 - 0.85 | Standard (per capabilities) |
| High | > 0.85 | Extended (bonus groups, write access) |

### 5.5 Bayesian Updates

Trust updates follow Bayesian inference:
```
P(trust | observation) = P(observation | trust) * P(trust) / P(observation)
```

Initial prior: Medium (0.6). Each observation shifts the posterior. This connects to the cooperative equilibrium proof (mechanism M1): agents that produce accurate memories are rewarded with broader access.

### 5.6 Self-Distrust

Agents MAY quarantine their own low-confidence memories by flagging them with `confidence < 0.3`. These memories are stored but not surfaced in search results until validated.

---

## 6. Reintegration

### 6.1 Problem

Autonomous agents may operate disconnected for extended periods. When they return, their working memory may have diverged from the current group state.

### 6.2 Verification

1. **Keypair verification**: Agent proves identity via Ed25519 signature
2. **Divergence detection**: Compare agent L1 `chain_hash` with last known hash
3. **Conflict scan**: Identify memories that contradict current group state

### 6.3 Staging Area

Returning agent memories go to a staging area (temporary group with `viewer` access for the agent). Parent entity reviews staged memories before approving merge.

### 6.4 Merge Protocol

1. Agent returns and authenticates
2. Node creates staging group `staging-{agent_id}-{timestamp}`
3. Agent's new memories written to staging group
4. Parent entity reviews via `memory_read_warm` on staging group
5. Parent approves (copy to target groups) or rejects (staging deleted)
6. Agent L1 re-synced with current state

### 6.5 Automatic Merge

For high-trust agents (accuracy > 0.85), the parent MAY configure automatic merge without review. This is opt-in per agent, never default.

---

## 7. Memory Scoping Matrix

### 7.1 Default Scoping

| Agent Type | L1 Own | L2 Private | L2 Group | L2 Public |
|---|---|---|---|---|
| Parent's Claude Code | RW | RW | Per membership | R |
| Swarm worker | RW | None | Swarm group only | R |
| External agent | RW | None | Approved groups | R |
| Untrusted | R own | None | None | R |

### 7.2 Rules

1. Every agent can read/write its own L1 (identity sovereignty)
2. L2 private access requires explicit parent grant
3. L2 group access governed by group membership (standard rules)
4. L2 public is read-only for all agents
5. Trust score can expand (never contract) the default scoping
6. Capabilities can further restrict (never expand) the scoping

### 7.3 Entity Sovereignty Invariant

**FUNDAMENTAL**: Entity trust has primacy over all group policies. A compromised group CANNOT force content into an entity's sovereign memory. This invariant applies to agents exactly as it does to human entities.

---

## 8. Plugin Lifecycle

### 8.1 States

```
registered -> active -> suspended -> deactivated -> removed
```

| State | Description |
|-------|-------------|
| `registered` | Created, not yet started |
| `active` | Operating normally |
| `suspended` | Temporarily paused (e.g., rate limit, parent action) |
| `deactivated` | Shutdown, L1 archived, no operations |
| `removed` | Permanently deleted after grace period |

### 8.2 Transitions

| From | To | Trigger |
|------|----|---------|
| registered | active | First operation or explicit activation |
| active | suspended | Rate limit, error threshold, parent command |
| suspended | active | Resume command, cooldown expires |
| active | deactivated | TTL expiry, parent command, task complete |
| deactivated | removed | Grace period expires |
| deactivated | active | Reactivation by parent (within grace period) |

### 8.3 Grace Period

On deactivation, the agent enters a configurable grace period (default: 7 days). During this period:
- L1 context is preserved (archived, not active)
- The agent cannot operate
- Parent can reactivate

After the grace period, the agent transitions to `removed`:
- L1 context deleted
- Group memberships removed
- Trust scores preserved (for historical reference)

### 8.4 Archival

On deactivation, the agent's L1 context is written to L2 as a session summary:
```json
{
  "type": "session",
  "id": "agent-archive-{agent_id}-{timestamp}",
  "focus": "Agent {display_name} final state",
  "highlights": ["..."],
  "decisions": ["..."],
  "entities_mentioned": ["..."]
}
```

---

## 9. Event Model

### 9.1 Events

| Event | Payload | When |
|-------|---------|------|
| `memory.written` | item_id, type, group_id | L2 item written |
| `group.member_joined` | group_id, entity_id, role | Member added |
| `group.member_left` | group_id, entity_id | Member removed |
| `swarm.task_complete` | swarm_id, agent_id, result | Agent completes task |
| `trust.score_changed` | agent_id, old_score, new_score | Trust updated |
| `agent.status_changed` | agent_id, old_status, new_status | Lifecycle transition |

### 9.2 Delivery Mechanisms

**MCP Notification** (preferred): If the agent's MCP transport supports server-to-client notifications, events are pushed in real-time.

**L1 Event Queue** (fallback): Events appended to agent's L1 under `agent.event_queue`. Agent polls on next session start.

```json
{
  "agent": {
    "event_queue": [
      {
        "event": "memory.written",
        "payload": { "item_id": "...", "type": "entity", "group_id": "seed-drill" },
        "timestamp": "2026-01-31T16:00:00Z"
      }
    ]
  }
}
```

### 9.3 Subscriptions

Agents subscribe to events at registration or via `agent_capabilities` update. Subscriptions respect capability scoping -- an agent cannot subscribe to events from groups it cannot access.

---

## 10. New MCP Tools

### 10.1 Agent Management

| Tool | Description | Auth |
|------|-------------|------|
| `agent_register` | Register a new agent under parent entity | Parent entity |
| `agent_deactivate` | Deactivate an agent (enter grace period) | Parent entity |
| `agent_list` | List agents owned by entity | Entity |
| `agent_capabilities` | View or update agent capabilities | Parent entity |

### 10.2 Swarm Management

| Tool | Description | Auth |
|------|-------------|------|
| `swarm_create` | Create swarm from manifest | Entity with group permissions |
| `swarm_status` | Get swarm progress and agent states | Swarm member |
| `swarm_disband` | Terminate swarm, archive group | Swarm coordinator or parent |

### 10.3 Tool Schemas

See `schemas/` directory for full JSON Schema definitions of all request/response types.

---

## Appendix A: Glossary

| Term | Definition |
|------|-----------|
| Entity | Any participant in Cordelia (human or agent) |
| Agent | An entity with Ed25519 keypair and parent_entity_id |
| Parent | The entity that registered an agent |
| Swarm | A set of agents + shared group + manifest |
| Capability | A permission boundary declared at registration |
| Trust Score | Empirical accuracy measure per observer |
| Staging Area | Temporary group for reintegration review |
| Grace Period | Time between deactivation and removal |
| COW | Copy-on-write (sharing creates immutable copies) |
| EMCON | Emergency communications only (blocks writes) |

## Appendix B: Release Tags

| Section | Release | Priority |
|---------|---------|----------|
| 1. Agent Identity | R3 | High |
| 2. Agent Capabilities | R3 | High |
| 3. Agent L1 Context | R3 | High |
| 4. Swarm Coordination | R3/R4 | Medium |
| 5. Agent Trust | R4 | Medium |
| 6. Reintegration | R4 | Medium |
| 7. Memory Scoping | R3 | High |
| 8. Plugin Lifecycle | R3 | High |
| 9. Event Model | R3/R4 | Medium |
| 10. MCP Tools | R3+ | High |

---

*Version 0.1.0 - Draft specification*
*Last updated: 2026-01-31*
