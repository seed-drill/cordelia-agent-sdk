# Design: Trust Calibration

## Motivation

Not all agents are equally reliable. Trust scores provide a mechanism to reward accuracy and limit the damage from unreliable agents, without requiring centralized reputation systems.

## Design

### Empirical, Not Reputational

Trust is measured by observed accuracy, not by votes or endorsements. This avoids Sybil attacks and social engineering.

```
accuracy = confirmed_correct / total_assessed
```

### Per-Observer Scores

Trust is relative: entity A may trust agent X more than entity B does. Each observer maintains independent scores. This prevents a single compromised observer from corrupting trust.

### Bayesian Updates

```
P(trust | observation) proportional to P(observation | trust) * P(trust)
```

- Prior: Medium (0.6) for new agents
- Each correct observation increases posterior
- Each incorrect observation decreases it
- Window-based: only recent observations count (sliding window)

### Trust Tiers

| Tier | Range | Effect |
|------|-------|--------|
| Untrusted | < 0.3 | Own L1 read, public L2 read only |
| Low | 0.3 - 0.6 | Approved group L2 read |
| Medium | 0.6 - 0.85 | Standard per capabilities |
| High | > 0.85 | Extended access, auto-merge eligible |

### Connection to Cooperative Equilibrium

Mechanism M1: agents that produce accurate memories are rewarded with broader access. This creates positive-sum dynamics -- the network gets more valuable as trust calibrates. Defecting (producing inaccurate memories) reduces access, naturally expelling bad actors.

## Security Considerations

- Trust scores stored per-observer, not globally
- Trust can expand but never override entity sovereignty
- Self-distrust: agents can quarantine low-confidence memories
- No automated trust recovery -- only observed accuracy rebuilds trust
