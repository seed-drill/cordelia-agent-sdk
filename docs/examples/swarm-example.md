# Example: Research Swarm (3 Agents)

A swarm of 3 agents: 2 researchers + 1 synthesizer, using hierarchical coordination.

## 1. Create Swarm

```json
{
  "tool": "swarm_create",
  "args": {
    "swarm_id": "swarm-competitive-analysis-20260131",
    "goal": "Research competitive landscape for SME software platforms and synthesize findings",
    "group_id": "swarm-competitive-analysis-20260131",
    "strategy": "hierarchical",
    "agents": [
      {
        "slot": "researcher",
        "agent_type": "swarm-worker",
        "capabilities": {
          "memory_read": { "layers": ["l2"], "groups": ["swarm-competitive-analysis-20260131"], "visibility": ["group", "public"] },
          "memory_write": { "layers": ["l2"], "groups": ["swarm-competitive-analysis-20260131"], "visibility": ["group"] },
          "tools": ["memory_search", "memory_read_warm", "memory_write_warm"],
          "max_parallel_ops": 3,
          "ttl_seconds": 3600,
          "autonomous": true
        },
        "count": 2
      },
      {
        "slot": "synthesizer",
        "agent_type": "swarm-worker",
        "capabilities": {
          "memory_read": { "layers": ["l2"], "groups": ["swarm-competitive-analysis-20260131", "seed-drill"], "visibility": ["group", "public"] },
          "memory_write": { "layers": ["l2"], "groups": ["swarm-competitive-analysis-20260131"], "visibility": ["group"] },
          "tools": ["memory_search", "memory_read_warm", "memory_write_warm", "memory_share"],
          "max_parallel_ops": 1,
          "ttl_seconds": 3600,
          "autonomous": false
        },
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
}
```

## 2. Execution Phase

### Researcher A writes findings

```json
{
  "tool": "memory_write_warm",
  "args": {
    "type": "entity",
    "data": {
      "type": "concept",
      "name": "Salesforce SME Offering",
      "summary": "Salesforce Starter Suite targets 1-25 employees. GBP 25/user/month. CRM-first, limited customization.",
      "tags": ["competitor", "crm", "salesforce"]
    }
  }
}
// Written to swarm group -> chatty culture replicates to all members
```

### Researcher B writes findings

```json
{
  "tool": "memory_write_warm",
  "args": {
    "type": "entity",
    "data": {
      "type": "concept",
      "name": "Zoho One Platform",
      "summary": "Zoho One: 45+ apps for GBP 30/user/month. Broad but shallow. No UK-specific compliance.",
      "tags": ["competitor", "platform", "zoho"]
    }
  }
}
```

Both researchers can see each other's findings (chatty broadcast).

## 3. Synthesis Phase

Synthesizer reads all findings from the swarm group:

```json
{ "tool": "memory_search", "args": { "query": "competitor", "limit": 20, "group_id": "swarm-competitive-analysis-20260131" } }
```

Then writes a synthesis:

```json
{
  "tool": "memory_write_warm",
  "args": {
    "type": "learning",
    "data": {
      "type": "insight",
      "content": "UK SME software market has clear gap: platforms are either too expensive (Salesforce), too broad (Zoho), or US-focused. Seed Drill's AI-native, UK-first approach is differentiated.",
      "confidence": 0.85,
      "tags": ["competitive-analysis", "market-gap", "positioning"]
    }
  }
}
```

## 4. Disbandment

Parent reviews findings, then:

```json
{
  "tool": "swarm_disband",
  "args": { "swarm_id": "swarm-competitive-analysis-20260131" }
}
```

- Key findings shared to `seed-drill` group (COW copy)
- Swarm group archived as L2 session
- All 3 agents deactivated
- Memories expire after 24h TTL (unless shared to persistent group)
