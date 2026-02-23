# Cordelia -- Persistent Memory for AI Agents

**cordelia-agent-sdk** -- Installer, hooks, skills, agent integration.

Push back when something is wrong. Flag technical debt, architectural concerns, and safety issues before implementing.

## Team

| Name | Role | GitHub |
|------|------|--------|
| Russell Wing | Co-Founder | @russwing |
| Martin Stevens | Co-Founder | @budgester |

## Cross-Repo Architecture

| Repo | Purpose | Language | Visibility |
|------|---------|----------|------------|
| cordelia-core | Rust P2P node, storage, replication | Rust | public |
| cordelia-proxy | MCP server, HTTP sidecar, dashboard | TypeScript | public |
| cordelia-agent-sdk | Installer, hooks, skills | Shell/JS | public |
| cordelia-portal | OAuth portal, device enrollment, vault | JS/Express | private |

## Current Status

R3 near-complete (S10 remaining: MCP proxy package). Portal PS8-9 next. GTM-002 blocked on polish sprint completion.

**Delivery Board:** https://github.com/orgs/seed-drill/projects/1

**Priority items:**

1. [P2P replication e2e test](https://github.com/seed-drill/cordelia-core/issues/4) -- prove propagation across local + Fly nodes
2. [Group invites](https://github.com/seed-drill/cordelia-portal/issues/2) -- invite-by-link, user directory, entity discovery
3. [Vault + device polish](https://github.com/seed-drill/cordelia-portal/issues/3) -- passphrase strength, device removal
4. [MCP proxy package](https://github.com/seed-drill/cordelia-proxy/issues/10) -- thin stdio proxy for multi-agent support
5. [E2E test harness](https://github.com/seed-drill/cordelia-core/issues/5) -- Docker orchestrator for CI

## Shared Conventions

- Commit format: `type: description` (feat/fix/docs/refactor/chore), under 72 chars
- Co-author line: `Co-Authored-By: Claude <model> <noreply@anthropic.com>`
- Never commit secrets (.env, credentials, keys)
- Never force push to main
- No emojis unless requested

## What Goes Where

- P2P protocol, storage, replication -> cordelia-core
- MCP tools, search, encryption, dashboard -> cordelia-proxy
- Install scripts, hooks, agent integration -> cordelia-agent-sdk
- Web UI, OAuth, enrollment, vault -> cordelia-portal
- Strategy, roadmap, actions, backlog -> seed-drill/strategy-and-planning

---

# Claude Configuration - Cordelia Agent SDK

## Project Context

This is the **front door** to Cordelia -- the repo end users install from. It contains:

- **install.sh** -- universal installer (macOS + Linux)
- **hooks/** -- Claude Code session lifecycle hooks (session-start, session-end, pre-compact)
- **skills/** -- Claude Code skills (persist, remember, sprint)
- **setup/** -- launchd/systemd service templates
- **scripts/** -- utility scripts (seed-l1, health check, backup)
- **schemas/** -- JSON Schema definitions for the agent model
- **SPEC.md** -- formal agent specification

## Architecture

Hooks in this repo need the proxy's `dist/` to spawn the HTTP server sidecar. The proxy directory is resolved via `getProxyDir()` in `hooks/lib.mjs`:

1. `CORDELIA_PROXY_DIR` env var
2. `config.toml` `[paths] proxy_dir`
3. Default: `~/.cordelia/proxy`

The installer writes `proxy_dir` into config.toml during setup.

## Related Projects

- **cordelia-core**: Rust node (P2P, replication, governor, API)
- **cordelia-proxy**: TypeScript MCP server, dashboard, REST API

## Key Principles

1. Agents ARE entities (agent_id = entity_id)
2. Memory is sovereign -- install NEVER overwrites existing memory
3. Hooks resolve proxy via config, not relative paths
4. Install is idempotent and fail-safe

## Memory Safety Rules

- NEVER overwrite config.toml -- merge new fields only
- NEVER overwrite node.key -- identity is permanent
- NEVER overwrite memory/ -- only code changes, not data
- NEVER overwrite encryption key (keychain or ~/.cordelia/key)
- Pre-migration backup is MANDATORY before touching existing installs
- If backup verification fails, ABORT -- leave everything untouched

## Testing

```bash
npm run test:install    # Docker distro matrix
npm run test:health     # Memory health check
npm run verify          # Verify local install
```

## Organization

Seed Drill - https://github.com/seed-drill

## License

AGPL-3.0-only
