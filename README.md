<p><img src="docs/logo.svg" alt="Cordelia" width="48" height="42"></p>

# Cordelia Agent SDK

**The front door to Cordelia.** Install, configure, and extend persistent memory for AI agents.

## What This Is

This repo is where you start. It contains everything needed to install and run Cordelia:

- **Universal installer** (`install.sh`) -- one command to set up Cordelia on macOS or Linux
- **Session hooks** -- automatic memory load/save on every Claude Code session
- **Skills** -- `/persist`, `/remember`, `/sprint` for Claude Code
- **Agent specification** -- formal contract for agent identity, capabilities, and trust
- **Schemas** -- JSON Schema definitions for the agent model

## What This Is NOT

This is not the node software or the MCP server. Those live in:

- **[cordelia-core](https://github.com/seed-drill/cordelia-core)** -- Rust P2P node, protocol, replication, governor. For node operators and contributors.
- **[cordelia-proxy](https://github.com/seed-drill/cordelia-proxy)** -- TypeScript MCP server, dashboard, REST API. For developers extending the proxy.

## Quick Start

### One-line install

```bash
curl -fsSL https://seeddrill.ai/install.sh | sh -s -- <your_user_id>
```

### Or from a clone

```bash
git clone https://github.com/seed-drill/cordelia-agent-sdk.git
cd cordelia-agent-sdk
./install.sh <your_user_id>
```

### What the installer does

1. Detects platform (macOS/Linux, x86_64/aarch64)
2. Installs prerequisites (Node.js, Claude Code)
3. Downloads `cordelia-node` binary
4. Clones and builds the MCP proxy
5. Generates encryption key (stored in platform keychain)
6. Writes config and seeds initial memory
7. Configures Claude Code (MCP server, hooks, skills)
8. Starts the node service (launchd/systemd)

After install, open a new terminal and run `claude`. You should see:

```
[CORDELIA] Session 1 | Genesis +0d | Chain: VERIFIED
```

### Intel Mac / no embeddings

```bash
./install.sh <your_user_id> --no-embeddings
```

## Repository Layout

```
cordelia-agent-sdk/
  install.sh              # Universal installer
  setup.sh                # Manual setup (alternative)
  hooks/                  # Claude Code session lifecycle hooks
    lib.mjs               # Shared utilities (config, crypto, proxy resolution)
    session-start.mjs     # Load L1 context + verify integrity chain
    session-end.mjs       # Increment session, generate summary, update chain
    pre-compact.mjs       # Flush insights before context compaction
    server-manager.mjs    # Ensure HTTP server sidecar is running
    mcp-client.mjs        # MCP client for hook -> proxy communication
    novelty-lite.mjs      # Lightweight novelty detection
    recovery.mjs          # Notification utilities
  skills/                 # Claude Code skills
    persist/              # /persist - analyze + save high-novelty content
    remember/             # /remember - quick note to memory
    sprint/               # /sprint - show current sprint status
  setup/                  # Service templates
    ai.seeddrill.cordelia.plist   # macOS launchd
    cordelia-node.service         # Linux systemd
  scripts/                # Utilities
    seed-l1.mjs           # Seed initial L1 context for new user
    check-memory-health.mjs  # Pre/post-upgrade health check
    backup-memory-db.sh   # Backup to remote servers
    backup-cron-wrapper.sh # Cron wrapper for backup
  schemas/                # JSON Schema definitions (draft 2020-12)
  docs/                   # Design documents and examples
  tests/                  # Install test infrastructure
  SPEC.md                 # Formal agent specification
```

## Agent Specification

**Agents are entities.** An `agent_id` is an `entity_id`. Every Cordelia primitive -- groups, memory scoping, trust, sharing -- works identically with agents.

| Document | Description |
|----------|-------------|
| [SPEC.md](SPEC.md) | Formal specification |
| [docs/design/](docs/design/) | Design rationale |
| [schemas/](schemas/) | JSON Schema definitions |
| [docs/examples/](docs/examples/) | Worked examples |

## Testing

### Install test matrix (Docker)

```bash
npm run test:install
```

Runs the installer on Ubuntu 22.04, Ubuntu 24.04, Debian 12, and Fedora 39.

### Memory health check

```bash
npm run test:health
```

### Verify local install

```bash
npm run verify
```

## License

AGPL-3.0-only. See [LICENSE](LICENSE).

---

*Cordelia: persistent memory for AI agents.*
