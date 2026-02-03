# Cordelia E2E User Journey Test

End-to-end test of the full install-to-use journey on a clean machine.

## Prerequisites

- Fresh Ubuntu 24.04 VM (no Node.js, no Rust, no Claude Code)
- Outbound internet access (GitHub, npm, bootnodes on port 9474)
- SSH access from test runner
- For portal tests: access to test.portal.seeddrill.ai:3001

## Test Matrix

| Platform | Architecture | Test Target | Status |
|----------|-------------|-------------|--------|
| Ubuntu 24.04 | x86_64 | cordelia-e2e VM (192.168.3.103) on pdukvm20 | PASS |
| macOS 15 | aarch64 | cordeliatest user on Russell's MacBook | PASS |
| Ubuntu 24.04 | aarch64 | TBD (if available) | -- |

## Journey Steps

### Phase 1: Fresh Install

```bash
# On clean VM as non-root user:
curl -fsSL https://raw.githubusercontent.com/seed-drill/cordelia-agent-sdk/main/install.sh \
  | sh -s -- testuser --no-embeddings
```

**Expected outcome:**
- Node.js installed (if missing)
- cordelia-node binary downloaded to ~/.cordelia/bin/
- cordelia-proxy cloned and built in ~/.cordelia/proxy/
- Encryption key generated and stored (keychain or ~/.cordelia/key)
- Node identity key generated at ~/.cordelia/node.key
- config.toml created with bootnodes
- Claude Code MCP configured in ~/.claude.json
- Session hooks configured in ~/.claude/settings.json
- Skills installed (persist, remember, sprint)
- cordelia-node service started (systemd on Linux, launchd on macOS)
- L1 context seeded

**Verification:**
```bash
~/.cordelia/sdk/tests/verify-install.sh
```

All checks should PASS.

### Phase 2: Node Health

```bash
# Check service is running
systemctl --user status cordelia-node    # Linux
launchctl list | grep cordelia           # macOS

# Check node API responds
curl -s http://localhost:9473/api/health

# Check peer connections (may take 30-60s after first start)
curl -s http://localhost:9473/api/v1/peers | python3 -m json.tool

# Check logs for successful bootnode connections
journalctl --user -u cordelia-node --no-pager -n 20  # Linux
tail -20 ~/.cordelia/logs/node.stdout.log             # macOS
```

**Expected outcome:**
- Service running without errors
- Health endpoint returns `{"ok": true}`
- At least 1 peer connected (bootnode)
- Logs show successful handshake with boot1 or boot2

### Phase 3: Memory Operations (via proxy)

Start the HTTP sidecar to test memory tools directly:

```bash
# Start proxy HTTP server
cd ~/.cordelia/proxy
CORDELIA_STORAGE=sqlite \
  CORDELIA_MEMORY_ROOT=~/.cordelia/memory \
  CORDELIA_HTTP_PORT=3847 \
  node dist/http-server.js &
PROXY_PID=$!

# Wait for startup
sleep 2

# Read L1 hot context (should have seeded data)
curl -s http://localhost:3847/api/memory/hot/testuser | python3 -m json.tool

# Write a test L2 item
curl -s -X POST http://localhost:3847/api/memory/warm \
  -H "Content-Type: application/json" \
  -d '{
    "type": "learning",
    "data": {
      "type": "insight",
      "name": "e2e-test-item",
      "content": "This is an E2E test memory item.",
      "keywords": ["e2e", "test"]
    }
  }'

# Search for it
curl -s http://localhost:3847/api/memory/search?query=e2e+test | python3 -m json.tool

# Clean up
kill $PROXY_PID
```

**Expected outcome:**
- L1 read returns seeded user context
- L2 write returns success with item ID
- Search returns the test item

### Phase 4: Portal Enrollment

Requires portal running (VM: 192.168.3.206:3001 or production URL).

```bash
# 1. Start proxy HTTP sidecar with PORTAL_URL:
cd ~/.cordelia/proxy
CORDELIA_STORAGE=sqlite \
  CORDELIA_MEMORY_ROOT=~/.cordelia/memory \
  CORDELIA_HTTP_PORT=3847 \
  PORTAL_URL=http://192.168.3.206:3001 \
  node dist/http-server.js &

# 2. In portal UI: login, generate enrollment code (e.g. ABCD-EFGH)

# 3. Run enrollment script:
CORDELIA_PROXY_URL=http://localhost:3847 \
  cordelia-enroll.sh --code ABCD-EFGH

# 4. In portal UI: click Authorize

# 5. Verify device appears in portal dashboard with matching device ID
```

**Expected outcome:**
- Enrollment completes with device ID + entity ID
- Device appears in portal dashboard with same device ID
- Bearer token stored at ~/.cordelia/portal-token
- Device can be revoked from portal (detail page or dashboard)

### Phase 5: Claude Code Session (Manual)

This step requires interactive terminal (cannot be fully automated).

```bash
# Open new terminal (to pick up PATH changes)
claude
```

**Expected outcome:**
- Session hook fires, displays `[CORDELIA] Session 1 | Genesis +0d | Chain: VERIFIED`
- Memory tools available (try `/remember This is a test note`)
- `/persist` skill works
- Exit claude, start again -- session count increments, previous session summary shown

## Automated Test Script

`tests/e2e-user-journey.sh` should automate Phases 1-3 and verify Phase 4 if portal is available.

```bash
#!/bin/bash
# Usage: ./e2e-user-journey.sh <ssh_host> <test_user>
# Example: ./e2e-user-journey.sh rezi@e2e-test-vm testuser
#
# Runs on a fresh VM via SSH. Expects:
#   - Clean Ubuntu 24.04
#   - SSH key access configured
#   - Internet access
```

### Exit Criteria

| Check | Required | Notes |
|-------|----------|-------|
| install.sh completes without error | YES | |
| verify-install.sh all PASS | YES | |
| cordelia-node service running | YES | |
| Node health endpoint responds | YES | |
| At least 1 peer connected | YES | May need 60s warmup |
| L1 read returns seeded context | YES | |
| L2 write + search round-trip | YES | |
| Portal enrollment completes | NO | Requires portal access |
| Claude Code session hook fires | NO | Requires interactive terminal |

## Known Issues / Workarounds

1. **GitHub release binary may not exist yet** -- install.sh downloads from
   `github.com/seed-drill/cordelia-core/releases/latest`. If no release is
   published, the binary download will fail. Workaround: use `--skip-download`
   and pre-stage the binary from a Docker container:
   ```bash
   docker cp cordelia-e2e-boot1:/usr/local/bin/cordelia-node /tmp/cordelia-node
   scp /tmp/cordelia-node testuser@<vm-ip>:/tmp/cordelia-node
   mkdir -p ~/.cordelia/bin && cp /tmp/cordelia-node ~/.cordelia/bin/ && chmod +x ~/.cordelia/bin/cordelia-node
   ```

2. **Private repos** -- Until repos are public, clone SDK and proxy locally
   and rsync to the VM. Init git repos so installer detects them:
   ```bash
   rsync -az --exclude node_modules --exclude .git cordelia-agent-sdk/ testuser@<vm>:~/.cordelia/sdk/
   rsync -az --exclude node_modules --exclude .git cordelia-proxy/ testuser@<vm>:~/.cordelia/proxy/
   ssh testuser@<vm> 'cd ~/.cordelia/sdk && git init && git add -A && git commit -m init'
   ssh testuser@<vm> 'cd ~/.cordelia/proxy && git init && git add -A && git commit -m init'
   ```

3. **Claude Code install on Linux** -- install.sh runs `npm install -g @anthropic-ai/claude-code`.
   On a clean VM this may need sudo for global npm install, or the user needs
   to configure npm prefix. The installer handles this but may prompt.

4. **Keychain not available in headless VM** -- macOS Keychain and Linux
   secret-tool require a desktop session / D-Bus. On headless VMs, the
   installer falls back to ~/.cordelia/key file storage.

5. **Build tools for better-sqlite3** -- Native compilation needs
   `build-essential` (make, g++) and `python3`. Install before running:
   `sudo apt-get install -y build-essential python3`

6. **Proxy HTTP port** -- The HTTP sidecar reads `CORDELIA_HTTP_PORT`, not
   `PORT`. Default is 3847. If another proxy is on 3847, set
   `CORDELIA_HTTP_PORT=3848` and use `CORDELIA_PROXY_URL=http://localhost:3848`
   for enrollment.

7. **Bootnodes may be unreachable** -- If boot1/boot2 are down or
   firewalled, the node will start but have no peers. Check bootnode
   status first.

7. **Node identity key format** -- The installer's openssl fallback generates
   PEM format keys, but cordelia-node expects libp2p protobuf format.
   Fixed: installer now uses `cordelia-node identity generate` directly.
   If the binary is pre-staged, ensure config.toml exists first.

## VM Provisioning (pdukvm20)

VM: `cordelia-e2e` on pdukvm20 (192.168.3.103, static IP).

```bash
# Create VM (already done -- cloud image + cloud-init on br0 bridge)
sudo virt-install \
  --name cordelia-e2e --memory 2048 --vcpus 2 \
  --disk /var/lib/libvirt/images/cordelia-e2e.qcow2 \
  --disk /var/lib/libvirt/images/cidata-e2e.iso,device=cdrom \
  --os-variant ubuntu24.04 --network bridge=br0,model=virtio \
  --import --noautoconsole

# Snapshot workflow (fast iteration):
# Revert to clean state:
sudo virsh snapshot-revert cordelia-e2e base-clean
# base-clean = Ubuntu 24.04 + Node.js 22 + Claude Code + build-essential, no Cordelia

# After test changes, update snapshot:
sudo virsh snapshot-delete cordelia-e2e base-clean
sudo virsh snapshot-create-as cordelia-e2e base-clean "description"
```

## E2E Run Results

### Linux (Ubuntu 24.04 x86_64) -- 2026-02-03

VM: `cordelia-e2e` on pdukvm20 (192.168.3.103).
Pre-staged binary from Docker container, repos rsynced.

| Check | Result | Notes |
|-------|--------|-------|
| install.sh completes | PASS | With --skip-download, pre-staged binary+repos |
| All validations pass | PASS | 0 warnings on second run |
| cordelia-node service running | PASS | systemd user unit, active (running) |
| Node peers connected | PASS | 2 hot peers (boot1 + boot2), ~30ms RTT |
| L1 read returns seeded context | PASS | identity.id=testuser, version=1 |
| L2 write + search round-trip | PASS | Write returned id, search found 1 result |
| Portal enrollment | PASS | device-00ae43711da42553, entity russwing, ID matches portal |
| Claude Code session hook | NOT TESTED | Requires interactive terminal |

### macOS (15 Sequoia, aarch64) -- 2026-02-03

Machine: Russell's MacBook (M-series). Clean user profile `cordeliatest`.
Binary built locally via `cargo build --release -p cordelia-node` (15MB arm64).
SDK + proxy rsynced to ~/staging/, proxy built with npm + tsc.

| Check | Result | Notes |
|-------|--------|-------|
| install.sh completes | PASS | All phases, all validations green |
| Platform detection | PASS | aarch64-apple-darwin |
| Prerequisites | PASS | Node.js v25.4.0 (shared homebrew), Claude Code, git |
| Encryption key storage | PASS | Falls back to ~/.cordelia/key on fresh profile (no keychain) |
| Node identity key | PASS | Generated via cordelia-node identity generate |
| Config + L1 seed | PASS | config.toml generated, L1 seeded via seed-l1.mjs |
| MCP + hooks + skills | PASS | ~/.claude.json, settings.json, skills/ all configured |
| launchd service | REGISTERED | Cannot start from sudo context; needs real GUI login |
| Portal enrollment | PASS | device-ca73c2690998471c, entity russwing, ID matches portal |
| Claude Code session hook | NOT TESTED | Requires interactive terminal as cordeliatest |

### Bugs Found and Fixed

1. **Node identity key format** -- openssl ed25519 PEM != libp2p protobuf.
   Fixed: use `cordelia-node identity generate` directly. (f7b51df)
2. **L1 seed skipped with --skip-proxy** -- Installer skipped L1 seed even when
   proxy dist was available. Fixed: check for `dist/server.js` instead of flag. (f7b51df)
3. **Build tools missing** -- `better-sqlite3` native compilation needs
   `build-essential`. Added to cloud-init and documented.
4. **CORDELIA_CONFIG used before defined** -- Variable referenced in Phase 5
   (identity generate) but not defined until Phase 6. Fixed: early assignment. (f801328)
5. **Keychain dialog on fresh macOS profiles** -- `security add-generic-password`
   triggers interactive "keychain not found" dialog on new user profiles. Fixed:
   check `security default-keychain` before attempting keychain store. (f801328)
6. **Device ID mismatch** -- Portal generated device_id at authorization, proxy
   generated a different one locally. Fixed: proxy uses device_id from portal
   poll response. (ecfe346, 24a6e79)
