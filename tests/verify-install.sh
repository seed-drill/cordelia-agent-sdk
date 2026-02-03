#!/bin/bash
#
# Cordelia Install Verification
#
# Assertions:
#   1. ~/.cordelia/config.toml exists
#   2. ~/.cordelia/bin/cordelia-node is executable
#   3. ~/.cordelia/proxy/dist/server.js exists
#   4. ~/.claude.json has cordelia MCP entry
#   5. ~/.claude/settings.json has hooks pointing to SDK paths
#   6. Skills installed
#   7. If CORDELIA_BOOT_ADDR set: node peers successfully
#   8. Migration safety checks (if CORDELIA_TEST_MIGRATION=1)
#
# Exit 0 = all pass, Exit 1 = any fail

set -uo pipefail

CORDELIA_HOME="$HOME/.cordelia"
ERRORS=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}PASS${NC}  $1"; }
fail() { echo -e "  ${RED}FAIL${NC}  $1"; ERRORS=$((ERRORS+1)); }

echo ""
echo "=== Cordelia Install Verification ==="
echo ""

# 1. config.toml exists
if [[ -f "$CORDELIA_HOME/config.toml" ]]; then
    pass "config.toml exists"
else
    fail "config.toml missing"
fi

# 2. cordelia-node binary is executable
if [[ -x "$CORDELIA_HOME/bin/cordelia-node" ]]; then
    pass "cordelia-node binary executable"
else
    fail "cordelia-node binary missing or not executable"
fi

# 3. proxy dist/server.js exists
if [[ -f "$CORDELIA_HOME/proxy/dist/server.js" ]]; then
    pass "proxy dist/server.js exists"
else
    fail "proxy dist/server.js missing"
fi

# 4. ~/.claude.json has cordelia MCP entry
if [[ -f "$HOME/.claude.json" ]]; then
    if node -e "
        const config = JSON.parse(require('fs').readFileSync('$HOME/.claude.json', 'utf-8'));
        process.exit(config.mcpServers?.cordelia ? 0 : 1);
    " 2>/dev/null; then
        pass "MCP config has cordelia entry"
    else
        fail "MCP config missing cordelia entry"
    fi
else
    fail "~/.claude.json missing"
fi

# 5. hooks point to SDK paths
if [[ -f "$HOME/.claude/settings.json" ]]; then
    if grep -q 'cordelia-agent-sdk\|cordelia/sdk' "$HOME/.claude/settings.json" 2>/dev/null; then
        pass "hooks point to SDK paths"
    elif grep -q 'cordelia.*hooks.*session' "$HOME/.claude/settings.json" 2>/dev/null; then
        # Hooks exist but point to proxy (acceptable for existing installs)
        pass "hooks configured (proxy paths -- pre-migration)"
    else
        fail "hooks not configured"
    fi
else
    fail "~/.claude/settings.json missing"
fi

# 6. Skills installed
SKILLS_OK=true
for skill in persist remember sprint; do
    if [[ ! -d "$HOME/.claude/skills/$skill" ]]; then
        SKILLS_OK=false
    fi
done
if [[ "$SKILLS_OK" = true ]]; then
    pass "skills installed (persist, remember, sprint)"
else
    fail "one or more skills missing"
fi

# 7. proxy_dir in config.toml
if grep -q 'proxy_dir' "$CORDELIA_HOME/config.toml" 2>/dev/null; then
    pass "config.toml has proxy_dir"
else
    fail "config.toml missing proxy_dir"
fi

# 8. Memory DB exists and is non-empty (skip if proxy was mocked -- no real storage available)
CORDELIA_DB="$CORDELIA_HOME/memory/cordelia.db"
PROXY_SERVER="$CORDELIA_HOME/proxy/dist/server.js"
if [[ -f "$PROXY_SERVER" ]] && [[ $(wc -c < "$PROXY_SERVER") -lt 100 ]]; then
    echo "  SKIP  memory DB (proxy dist is mocked)"
elif [[ -f "$CORDELIA_DB" ]] && [[ -s "$CORDELIA_DB" ]]; then
    pass "memory DB exists and non-empty"
else
    fail "memory DB missing or empty"
fi

# 9. Node identity key exists
if [[ -f "$CORDELIA_HOME/node.key" ]]; then
    pass "node identity key exists"
else
    fail "node identity key missing"
fi

# 10. Peering test (conditional)
if [[ -n "${CORDELIA_BOOT_ADDR:-}" ]]; then
    echo ""
    echo "--- Peering Test ---"
    if "$CORDELIA_HOME/bin/cordelia-node" --config "$CORDELIA_HOME/config.toml" peer-check 2>/dev/null; then
        pass "node peers with $CORDELIA_BOOT_ADDR"
    else
        fail "node failed to peer with $CORDELIA_BOOT_ADDR"
    fi
else
    echo "  SKIP  peering test (CORDELIA_BOOT_ADDR not set)"
fi

# --- Migration safety tests ---
if [[ "${CORDELIA_TEST_MIGRATION:-}" = "1" ]]; then
    echo ""
    echo "--- Migration Safety Tests ---"

    # Check backup was created
    BACKUP_COUNT=$(ls -d "$CORDELIA_HOME/backups/pre-migrate-"* 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$BACKUP_COUNT" -gt 0 ]]; then
        pass "pre-migration backup created ($BACKUP_COUNT backups)"
    else
        fail "no pre-migration backup found"
    fi

    # Check backup has manifest
    LATEST_BACKUP=$(ls -d "$CORDELIA_HOME/backups/pre-migrate-"* 2>/dev/null | sort | tail -1)
    if [[ -n "$LATEST_BACKUP" ]] && [[ -f "$LATEST_BACKUP/manifest.sha256" ]]; then
        pass "backup has SHA-256 manifest"
    else
        fail "backup missing SHA-256 manifest"
    fi

    # Check backup has memory data
    if [[ -n "$LATEST_BACKUP" ]] && [[ -d "$LATEST_BACKUP/memory" ]]; then
        pass "backup includes memory directory"
    else
        fail "backup missing memory directory"
    fi

    # Check config.toml was NOT overwritten (should have proxy_dir added, not replaced)
    if [[ -n "$LATEST_BACKUP" ]] && [[ -f "$LATEST_BACKUP/config.toml" ]]; then
        ORIGINAL_USER=$(grep 'user_id' "$LATEST_BACKUP/config.toml" 2>/dev/null | head -1)
        CURRENT_USER=$(grep 'user_id' "$CORDELIA_HOME/config.toml" 2>/dev/null | head -1)
        if [[ "$ORIGINAL_USER" = "$CURRENT_USER" ]]; then
            pass "config.toml user_id preserved (not overwritten)"
        else
            fail "config.toml user_id changed during migration"
        fi
    fi
fi

# --- Results ---
echo ""
if [[ $ERRORS -gt 0 ]]; then
    echo -e "${RED}=== VERIFICATION FAILED: $ERRORS errors ===${NC}"
    exit 1
else
    echo -e "${GREEN}=== VERIFICATION PASSED ===${NC}"
    exit 0
fi
