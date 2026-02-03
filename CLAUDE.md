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
