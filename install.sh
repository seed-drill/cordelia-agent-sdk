#!/bin/bash
#
# Cordelia Universal Installer (SDK)
# Usage: curl -fsSL https://seeddrill.ai/install.sh | bash -s -- <user_id>
#    or: ./install.sh <user_id> [--no-embeddings]
#
# Phases:
#   0. Existing install detection + pre-migration backup
#   1. Platform detection
#   2. Prerequisites (Node.js, Claude Code)
#   3. Download cordelia-node binary
#   4. Clone + build proxy / detect SDK repo
#   5. Generate credentials (encryption key, node identity)
#   6. Write config + seed L1
#   7. Configure Claude Code (MCP, hooks, skills)
#   8. Shell environment (~/.cordelia/bin to PATH)
#   9. Start node service (launchd / systemd)
#  10. Post-migration verification
#

set -e

# --- Constants ---

CORDELIA_HOME="$HOME/.cordelia"
CORDELIA_BIN="$CORDELIA_HOME/bin"
CORDELIA_LOGS="$CORDELIA_HOME/logs"
MEMORY_ROOT="$CORDELIA_HOME/memory"
GITHUB_REPO="seed-drill/cordelia-core"
PROXY_REPO="https://github.com/seed-drill/cordelia-proxy.git"
SDK_REPO="https://github.com/seed-drill/cordelia-agent-sdk.git"

USER_ID=""
NO_EMBEDDINGS=false
SKIP_DOWNLOAD=false
SKIP_PROXY=false
IS_MIGRATION=false
BACKUP_DIR=""
PRE_MIGRATION_L2_COUNT=""

# --- Colors ---

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
phase() {
    local num="$1"
    local label="$2"
    echo ""
    echo -e "${BLUE}--- Phase ${num}: ${label} ---${NC}"
    return 0
}

# --- Parse arguments ---

for arg in "$@"; do
    case $arg in
        --no-embeddings) NO_EMBEDDINGS=true ;;
        --skip-download) SKIP_DOWNLOAD=true ;;
        --skip-proxy) SKIP_PROXY=true ;;
        --help|-h)
            echo "Cordelia Universal Installer"
            echo ""
            echo "Usage: ./install.sh <user_id> [--no-embeddings]"
            echo "   or: curl -fsSL https://seeddrill.ai/install.sh | bash -s -- <user_id>"
            echo ""
            echo "Options:"
            echo "  --no-embeddings    Skip Ollama (Intel Macs, simpler setup)"
            echo "  --skip-download    Skip binary download (use existing cordelia-node)"
            echo "  --skip-proxy       Skip proxy clone+build (use existing proxy dist)"
            exit 0
            ;;
        *)
            if [[ -z "$USER_ID" ]]; then
                USER_ID="$arg"
            fi
            ;;
    esac
done

if [[ -z "$USER_ID" ]]; then
    echo "Cordelia Universal Installer"
    echo ""
    echo "Usage: ./install.sh <user_id>"
    echo "   or: curl -fsSL https://seeddrill.ai/install.sh | bash -s -- <user_id>"
    exit 1
fi

echo ""
echo "========================================"
echo "   Cordelia Universal Installer"
echo "========================================"
echo ""
echo "Installing for user: $USER_ID"
[[ "$NO_EMBEDDINGS" = true ]] && echo "Mode: No embeddings (Intel Mac compatible)"
echo ""

# ============================================
# Phase 0: Existing install detection + backup
# ============================================
phase 0 "Existing install detection"

if [[ -d "$CORDELIA_HOME" ]]; then
    if [[ -d "$MEMORY_ROOT" ]]; then
        IS_MIGRATION=true
        echo "Existing Cordelia installation detected. Memory will be backed up before any changes."
        echo ""

        BACKUP_TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
        BACKUP_DIR="$CORDELIA_HOME/backups/pre-migrate-${BACKUP_TIMESTAMP}"
        mkdir -p "$BACKUP_DIR"

        # --- Pre-migration backup ---
        echo "Creating pre-migration backup at $BACKUP_DIR..."

        # Try cordelia-node backup first (if binary exists and DB is accessible)
        if [[ -x "$CORDELIA_BIN/cordelia-node" ]]; then
            "$CORDELIA_BIN/cordelia-node" backup --output "$BACKUP_DIR/cordelia.db" 2>/dev/null || true
        fi

        # Direct SQLite backup (if cordelia-node backup didn't produce a file)
        if [[ ! -f "$BACKUP_DIR/cordelia.db" ]] && command -v sqlite3 &>/dev/null; then
            CORDELIA_DB="$MEMORY_ROOT/cordelia.db"
            if [[ -f "$CORDELIA_DB" ]]; then
                sqlite3 "$CORDELIA_DB" ".backup '$BACKUP_DIR/cordelia.db'" 2>/dev/null || {
                    error "Failed to backup SQLite database. Aborting -- no changes made."
                }
            fi
        fi

        # Copy memory directory (preserving structure)
        if [[ -d "$MEMORY_ROOT" ]]; then
            cp -a "$MEMORY_ROOT" "$BACKUP_DIR/memory" 2>/dev/null || {
                error "Failed to backup memory directory. Aborting -- no changes made."
            }
        fi

        # Copy config.toml
        if [[ -f "$CORDELIA_HOME/config.toml" ]]; then
            cp "$CORDELIA_HOME/config.toml" "$BACKUP_DIR/config.toml" || {
                error "Failed to backup config.toml. Aborting -- no changes made."
            }
        fi

        # Copy node.key
        if [[ -f "$CORDELIA_HOME/node.key" ]]; then
            cp "$CORDELIA_HOME/node.key" "$BACKUP_DIR/node.key" || {
                error "Failed to backup node.key. Aborting -- no changes made."
            }
        fi

        # Copy encryption key file (if exists)
        if [[ -f "$CORDELIA_HOME/key" ]]; then
            cp "$CORDELIA_HOME/key" "$BACKUP_DIR/key" || true
        fi

        # Generate SHA-256 manifest
        echo "Generating backup manifest..."
        MANIFEST_FILE="$BACKUP_DIR/manifest.sha256"
        cd "$BACKUP_DIR"
        find . -type f ! -name 'manifest.sha256' -exec shasum -a 256 {} \; > "$MANIFEST_FILE" 2>/dev/null || \
        find . -type f ! -name 'manifest.sha256' -exec sha256sum {} \; > "$MANIFEST_FILE" 2>/dev/null || {
            error "Failed to generate backup manifest. Aborting -- no changes made."
        }
        cd - > /dev/null

        # Verify backup integrity
        echo "Verifying backup integrity..."
        cd "$BACKUP_DIR"
        if command -v shasum &>/dev/null; then
            shasum -a 256 -c "$MANIFEST_FILE" --quiet 2>/dev/null || {
                error "Backup verification failed. Aborting -- no changes made."
            }
        else
            sha256sum -c "$MANIFEST_FILE" --quiet 2>/dev/null || {
                error "Backup verification failed. Aborting -- no changes made."
            }
        fi
        cd - > /dev/null

        # Capture pre-migration L2 item count (for post-migration verification)
        CORDELIA_DB="$MEMORY_ROOT/cordelia.db"
        if [[ -f "$CORDELIA_DB" ]] && command -v sqlite3 &>/dev/null; then
            PRE_MIGRATION_L2_COUNT=$(sqlite3 "$CORDELIA_DB" "SELECT COUNT(*) FROM l2_items;" 2>/dev/null || echo "")
        fi

        info "Pre-migration backup complete: $BACKUP_DIR"
        info "Backup manifest verified (SHA-256)"
    else
        info "Existing ~/.cordelia/ found but no memory -- treating as fresh install"
    fi
else
    info "Fresh installation"
fi

# ============================================
# Phase 1: Platform detection
# ============================================
phase 1 "Platform detection"

OS="$(uname -s)"
ARCH="$(uname -m)"

case "$OS" in
    Darwin) OS_NAME="macos" ;;
    Linux)  OS_NAME="linux" ;;
    *)      error "Unsupported OS: $OS. Supported: macOS, Linux." ;;
esac

# Normalise arch
case "$ARCH" in
    x86_64|amd64)   ARCH_NAME="x86_64" ;;
    aarch64|arm64)   ARCH_NAME="aarch64" ;;
    *)               error "Unsupported architecture: $ARCH. Supported: x86_64, aarch64/arm64." ;;
esac

# Build target triple
case "${OS_NAME}-${ARCH_NAME}" in
    macos-x86_64)   TARGET="x86_64-apple-darwin" ;;
    macos-aarch64)  TARGET="aarch64-apple-darwin" ;;
    linux-x86_64)   TARGET="x86_64-unknown-linux-gnu" ;;
    linux-aarch64)  TARGET="aarch64-unknown-linux-gnu" ;;
    *)              error "Unsupported platform: ${OS_NAME}-${ARCH_NAME}" ;;
esac

# Map TARGET to binary name (GitHub release naming convention)
case "${OS_NAME}-${ARCH_NAME}" in
    macos-x86_64)   BINARY_SUFFIX="x86_64-darwin" ;;
    macos-aarch64)  BINARY_SUFFIX="aarch64-darwin" ;;
    linux-x86_64)   BINARY_SUFFIX="x86_64-linux" ;;
    linux-aarch64)  BINARY_SUFFIX="aarch64-linux" ;;
    *)              error "Unsupported platform: ${OS_NAME}-${ARCH_NAME}" ;;
esac

info "Platform: $OS_NAME $ARCH_NAME -> $TARGET"

# ============================================
# Phase 2: Prerequisites
# ============================================
phase 2 "Prerequisites"

# Node.js
if ! command -v node &> /dev/null; then
    warn "Node.js not found. Installing..."
    if [[ "$OS_NAME" = "macos" ]]; then
        if ! command -v brew &> /dev/null; then
            warn "Homebrew not found. Required for Node.js on macOS."
            echo ""
            read -p "Install Homebrew now? [y/N] " -n 1 -r
            echo ""
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
                info "Homebrew installed"
            else
                error "Homebrew required. Install from https://brew.sh or install Node.js manually."
            fi
        fi
        brew install node
    elif [[ "$OS_NAME" = "linux" ]]; then
        curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
        sudo apt-get install -y nodejs
    fi
    info "Node.js installed"
else
    info "Node.js $(node --version)"
fi

# Claude Code
if ! command -v claude &> /dev/null; then
    if [[ "$OS_NAME" = "linux" ]]; then
        warn "Claude Code not found. Installing via npm..."
        sudo npm install -g @anthropic-ai/claude-code
        command -v claude &> /dev/null || error "Claude Code install failed. Install manually: npm install -g @anthropic-ai/claude-code"
        info "Claude Code installed via npm"
    else
        error "Claude Code not found. Install from: https://claude.ai/download"
    fi
else
    info "Claude Code found"
fi

# Git (needed for proxy clone)
command -v git &> /dev/null || error "git not found. Install git first."
info "git found"

# ============================================
# Phase 3: Download cordelia-node binary
# ============================================
phase 3 "Download cordelia-node binary"

mkdir -p "$CORDELIA_BIN" "$CORDELIA_LOGS"

BINARY_PATH="${CORDELIA_BIN}/cordelia-node"

if [[ "$SKIP_DOWNLOAD" = true ]]; then
    if [[ -x "$BINARY_PATH" ]]; then
        info "Skipping download (--skip-download). Using existing: $BINARY_PATH"
    else
        error "--skip-download specified but no binary found at $BINARY_PATH"
    fi
else
    BINARY_NAME="cordelia-node-${BINARY_SUFFIX}"
    BINARY_URL="https://github.com/${GITHUB_REPO}/releases/latest/download/${BINARY_NAME}"
    CHECKSUM_URL="${BINARY_URL}.sha256"

    if [[ -f "$BINARY_PATH" ]]; then
        info "cordelia-node already installed at $BINARY_PATH"
        info "Re-downloading to check for updates..."
    fi

    echo "Downloading cordelia-node for $TARGET..."
    curl -fsSL -o "${CORDELIA_BIN}/${BINARY_NAME}" "$BINARY_URL" || error "Failed to download binary. Check https://github.com/${GITHUB_REPO}/releases"
    
    # Try to download checksum (optional - may not exist)
    if curl -fsSL -o "${CORDELIA_BIN}/${BINARY_NAME}.sha256" "$CHECKSUM_URL" 2>/dev/null; then
        # Verify SHA256 if checksum file was downloaded
        echo "Verifying checksum..."
        cd "$CORDELIA_BIN"
        if [[ "$OS_NAME" = "macos" ]]; then
            shasum -a 256 -c "${BINARY_NAME}.sha256" || error "Checksum verification failed. Binary may be corrupt."
        else
            sha256sum -c "${BINARY_NAME}.sha256" || error "Checksum verification failed. Binary may be corrupt."
        fi
        cd - > /dev/null
        rm -f "${CORDELIA_BIN}/${BINARY_NAME}.sha256"
    else
        warn "Checksum file not available. Skipping verification."
    fi

    cp "${CORDELIA_BIN}/${BINARY_NAME}" "$BINARY_PATH"
    chmod +x "$BINARY_PATH"
    rm -f "${CORDELIA_BIN}/${BINARY_NAME}" "${BINARY_NAME}.sha256"

    info "cordelia-node installed: $BINARY_PATH"
fi

# ============================================
# Phase 4: SDK + proxy setup
# ============================================
phase 4 "SDK + proxy setup"

# --- Detect SDK directory ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
SDK_DIR=""

if [[ -f "$SCRIPT_DIR/package.json" ]] && grep -q '"cordelia-agent-sdk"' "$SCRIPT_DIR/package.json" 2>/dev/null; then
    SDK_DIR="$SCRIPT_DIR"
    info "Running from SDK repo at $SDK_DIR"
elif [[ -d "$CORDELIA_HOME/sdk/.git" ]]; then
    SDK_DIR="$CORDELIA_HOME/sdk"
    info "SDK already cloned at $SDK_DIR"
    cd "$SDK_DIR"
    git pull --ff-only 2>/dev/null || warn "Could not fast-forward SDK. Continuing with existing version."
else
    echo "Cloning cordelia-agent-sdk..."
    git clone "$SDK_REPO" "$CORDELIA_HOME/sdk" || error "Failed to clone cordelia-agent-sdk."
    SDK_DIR="$CORDELIA_HOME/sdk"
fi

# Install SDK dependencies (for MCP SDK used by hooks)
cd "$SDK_DIR"
if [[ ! -d "node_modules" ]]; then
    npm install --silent 2>/dev/null || npm install
fi
info "SDK dependencies installed"

# --- Clone + build proxy ---
PROXY_DIR="$CORDELIA_HOME/proxy"

if [[ "$SKIP_PROXY" = true ]]; then
    if [[ -d "$PROXY_DIR/dist" ]]; then
        info "Skipping proxy clone+build (--skip-proxy). Using existing: $PROXY_DIR"
    else
        mkdir -p "$PROXY_DIR/dist"
        info "Skipping proxy clone+build (--skip-proxy). Created stub: $PROXY_DIR/dist"
    fi
else
    if [[ -d "$PROXY_DIR/.git" ]]; then
        info "Proxy already cloned at $PROXY_DIR"
        cd "$PROXY_DIR"
        git pull --ff-only 2>/dev/null || warn "Could not fast-forward proxy. Continuing with existing version."
    else
        echo "Cloning cordelia-proxy..."
        git clone "$PROXY_REPO" "$PROXY_DIR" || error "Failed to clone cordelia-proxy."
    fi

    cd "$PROXY_DIR"

    if [[ ! -d "node_modules" ]]; then
        npm install --silent
    fi
    info "Proxy dependencies installed"

    npm run build --silent 2>/dev/null || npm run build
    info "Proxy built"
fi

# ============================================
# Phase 5: Generate credentials
# ============================================
phase 5 "Generate credentials"

# --- Encryption key ---
# On migration: preserve existing key. On fresh install: generate new one.
if [[ "$IS_MIGRATION" = true ]]; then
    # Try to retrieve existing key from keychain
    ENCRYPTION_KEY=""
    if [[ "$OS_NAME" = "macos" ]]; then
        ENCRYPTION_KEY=$(security find-generic-password -a cordelia -s cordelia-encryption-key -w 2>/dev/null || true)
    elif [[ "$OS_NAME" = "linux" ]]; then
        ENCRYPTION_KEY=$(secret-tool lookup service cordelia type encryption-key 2>/dev/null || true)
    fi
    # Fallback: key file
    if [[ -z "$ENCRYPTION_KEY" ]] && [[ -f "$CORDELIA_HOME/key" ]]; then
        ENCRYPTION_KEY=$(cat "$CORDELIA_HOME/key")
    fi
    if [[ -n "$ENCRYPTION_KEY" ]]; then
        info "Using existing encryption key (migration)"
        KEY_STORED=true
    else
        warn "Could not find existing encryption key -- generating new one"
        ENCRYPTION_KEY=$(openssl rand -hex 32)
        KEY_STORED=false
    fi
else
    ENCRYPTION_KEY=$(openssl rand -hex 32)
    info "Generated 64-character hex encryption key"
    KEY_STORED=false
fi

# Store in platform keychain (no plaintext in shell profile)
if [[ "$KEY_STORED" = false ]]; then
    if [[ "$OS_NAME" = "macos" ]]; then
        # macOS Keychain -- check default keychain exists first to avoid
        # interactive dialog on fresh user profiles with no keychain
        if security default-keychain 2>/dev/null | grep -q 'login.keychain'; then
            if security add-generic-password -a cordelia -s cordelia-encryption-key -w "$ENCRYPTION_KEY" -U 2>/dev/null; then
                KEY_STORED=true
                info "Encryption key stored in macOS Keychain"
            else
                warn "Could not store key in Keychain"
            fi
        else
            warn "No default keychain found (fresh user profile?) -- skipping keychain storage"
        fi
    elif [[ "$OS_NAME" = "linux" ]]; then
        # Linux: GNOME Keyring via secret-tool
        if command -v secret-tool &> /dev/null; then
            echo -n "$ENCRYPTION_KEY" | secret-tool store --label='Cordelia Encryption Key' service cordelia type encryption-key 2>/dev/null
            if [[ $? -eq 0 ]]; then
                KEY_STORED=true
                info "Encryption key stored in GNOME Keyring"
            else
                warn "Could not store key in GNOME Keyring"
            fi
        else
            warn "secret-tool not found (install libsecret-tools for keyring support)"
        fi
    fi
fi

# Fallback: file with restrictive permissions
if [[ "$KEY_STORED" = false ]]; then
    KEY_FILE="$CORDELIA_HOME/key"
    echo -n "$ENCRYPTION_KEY" > "$KEY_FILE"
    chmod 0600 "$KEY_FILE"
    info "Encryption key stored in $KEY_FILE (chmod 0600)"
fi

# --- Node identity key ---
CORDELIA_CONFIG="$CORDELIA_HOME/config.toml"
if [[ -f "$CORDELIA_HOME/node.key" ]]; then
    info "Node identity key already exists"
else
    "$BINARY_PATH" --config "$CORDELIA_CONFIG" identity generate 2>/dev/null || true
    if [[ -f "$CORDELIA_HOME/node.key" ]]; then
        info "Node identity key generated via cordelia-node"
    else
        error "Failed to generate node identity key. Run: cordelia-node --config ~/.cordelia/config.toml identity generate"
    fi
fi

# ============================================
# Phase 6: Write config + seed L1
# ============================================
phase 6 "Write config + seed L1"

CORDELIA_CONFIG="$CORDELIA_HOME/config.toml"

if [[ ! -f "$CORDELIA_CONFIG" ]]; then
    cat > "$CORDELIA_CONFIG" << NODEEOF
# Cordelia configuration
# Generated by install.sh for user: ${USER_ID}

[identity]
user_id = "${USER_ID}"

[paths]
memory_root = "${MEMORY_ROOT}"
proxy_dir = "${PROXY_DIR}"

[node]
identity_key = "${CORDELIA_HOME}/node.key"
api_transport = "http"
api_addr = "127.0.0.1:9473"
database = "${CORDELIA_HOME}/cordelia.db"
entity_id = "${USER_ID}"

[network]
listen_addr = "0.0.0.0:9474"

[[network.bootnodes]]
addr = "boot1.cordelia.seeddrill.ai:9474"

[[network.bootnodes]]
addr = "boot2.cordelia.seeddrill.ai:9474"

[governor]
hot_min = 2
hot_max = 20
warm_min = 10
warm_max = 50

[replication]
sync_interval_moderate_secs = 300
tombstone_retention_days = 7
max_batch_size = 100
NODEEOF
    info "Generated config: $CORDELIA_CONFIG"
else
    info "Config already exists: $CORDELIA_CONFIG"

    # NEVER overwrite config.toml -- merge new fields only

    # Add [paths] proxy_dir if missing
    if ! grep -q 'proxy_dir' "$CORDELIA_CONFIG" 2>/dev/null; then
        if grep -q '^\[paths\]' "$CORDELIA_CONFIG" 2>/dev/null; then
            # [paths] section exists, add proxy_dir after it
            sed -i.bak '/^\[paths\]/a\
proxy_dir = "'"$PROXY_DIR"'"' "$CORDELIA_CONFIG"
            rm -f "${CORDELIA_CONFIG}.bak"
        else
            # No [paths] section -- append it
            echo "" >> "$CORDELIA_CONFIG"
            echo "[paths]" >> "$CORDELIA_CONFIG"
            echo "proxy_dir = \"${PROXY_DIR}\"" >> "$CORDELIA_CONFIG"
        fi
        info "Added proxy_dir to config.toml"
    fi

    # Fix stale bootnode addresses if present
    if grep -q 'seeddrill\.io' "$CORDELIA_CONFIG" 2>/dev/null; then
        sed -i.bak 's/seeddrill\.io/seeddrill.ai/g' "$CORDELIA_CONFIG"
        rm -f "${CORDELIA_CONFIG}.bak"
        info "Fixed bootnode addresses (.io -> .ai)"
    fi
    if grep -q 'moltbot' "$CORDELIA_CONFIG" 2>/dev/null; then
        sed -i.bak '/moltbot/d' "$CORDELIA_CONFIG"
        rm -f "${CORDELIA_CONFIG}.bak"
        info "Removed stale moltbot bootnode"
    fi
fi

# Ensure salt directory and file
SALT_DIR="$MEMORY_ROOT/L2-warm/.salt"
SALT_FILE="$SALT_DIR/global.salt"
mkdir -p "$SALT_DIR"
if [[ ! -f "$SALT_FILE" ]]; then
    openssl rand -out "$SALT_FILE" 32
    info "Generated encryption salt"
fi

# Seed L1 context (seed-l1.mjs is idempotent -- skips if L1 already exists)
# Requires proxy dist for storage/crypto imports -- skip if proxy not built
export CORDELIA_ENCRYPTION_KEY="$ENCRYPTION_KEY"
export CORDELIA_MEMORY_ROOT="$MEMORY_ROOT"
export CORDELIA_PROXY_DIR="$PROXY_DIR"
export CORDELIA_STORAGE=node
[[ "$NO_EMBEDDINGS" = true ]] && export CORDELIA_EMBEDDING_PROVIDER=none

if [[ -f "$PROXY_DIR/dist/server.js" ]]; then
    echo "Seeding L1 memory for $USER_ID..."
    node "$SDK_DIR/scripts/seed-l1.mjs" "$USER_ID"
    info "L1 context seeded"
else
    warn "Skipping L1 seed (proxy dist not built)"
fi

# ============================================
# Phase 7: Configure Claude Code
# ============================================
phase 7 "Configure Claude Code"

GLOBAL_MCP="$HOME/.claude.json"
CLAUDE_DIR="$HOME/.claude"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"

mkdir -p "$CLAUDE_DIR"

# --- MCP server config (NO encryption key in env -- retrieved at runtime) ---
ENV_STORAGE="{\"CORDELIA_STORAGE\": \"node\", \"CORDELIA_MEMORY_ROOT\": \"$MEMORY_ROOT\"}"
if [[ "$NO_EMBEDDINGS" = true ]]; then
    ENV_STORAGE="{\"CORDELIA_EMBEDDING_PROVIDER\": \"none\", \"CORDELIA_STORAGE\": \"node\", \"CORDELIA_MEMORY_ROOT\": \"$MEMORY_ROOT\"}"
fi

node -e "
const fs = require('fs');
const globalMcp = '$GLOBAL_MCP';
const proxyDir = '$PROXY_DIR';
const envJson = $ENV_STORAGE;

let config = {};
try { config = JSON.parse(fs.readFileSync(globalMcp, 'utf-8')); } catch {}

if (!config.mcpServers) config.mcpServers = {};
config.mcpServers.cordelia = {
    command: 'node',
    args: [proxyDir + '/dist/server.js'],
    env: envJson
};

fs.writeFileSync(globalMcp, JSON.stringify(config, null, 2));
"
info "MCP server configured: $GLOBAL_MCP"

# --- Session hooks (point at SDK, not proxy) ---
node -e "
const fs = require('fs');
const settingsFile = '$SETTINGS_FILE';
const sdkDir = '$SDK_DIR';

let settings = {};
try { settings = JSON.parse(fs.readFileSync(settingsFile, 'utf-8')); } catch {}

if (!settings.hooks) settings.hooks = {};
if (!settings.hooks.SessionStart) settings.hooks.SessionStart = [];
if (!settings.hooks.SessionEnd) settings.hooks.SessionEnd = [];

const startHook = {
    matcher: '',
    hooks: [{ type: 'command', command: sdkDir + '/hooks/session-start.mjs', timeout: 10 }]
};
const endHook = {
    matcher: '',
    hooks: [{ type: 'command', command: sdkDir + '/hooks/session-end.mjs', timeout: 10 }]
};

// Remove any existing cordelia hooks (migration: proxy -> SDK paths)
settings.hooks.SessionStart = settings.hooks.SessionStart.filter(h =>
    !(h.hooks && h.hooks.some(hh => hh.command && hh.command.includes('cordelia')))
);
settings.hooks.SessionEnd = settings.hooks.SessionEnd.filter(h =>
    !(h.hooks && h.hooks.some(hh => hh.command && hh.command.includes('cordelia')))
);

settings.hooks.SessionStart.push(startHook);
settings.hooks.SessionEnd.push(endHook);

fs.writeFileSync(settingsFile, JSON.stringify(settings, null, 2));
"
info "Session hooks configured (SDK paths)"

# --- Skills (from SDK) ---
SKILLS_SRC="$SDK_DIR/skills"
SKILLS_DEST="$CLAUDE_DIR/skills"
mkdir -p "$SKILLS_DEST"

for skill_dir in "$SKILLS_SRC"/*; do
    if [[ -d "$skill_dir" ]]; then
        skill_name=$(basename "$skill_dir")
        dest_dir="$SKILLS_DEST/$skill_name"
        mkdir -p "$dest_dir"
        for file in "$skill_dir"/*; do
            if [[ -f "$file" ]]; then
                sed "s/__USER_ID__/$USER_ID/g" "$file" > "$dest_dir/$(basename "$file")"
            fi
        done
    fi
done
info "Skills installed: persist, sprint, remember"

# ============================================
# Phase 8: Shell environment
# ============================================
phase 8 "Shell environment"

# Add ~/.cordelia/bin to PATH (but NOT the encryption key)
if [[ "$OS_NAME" = "linux" ]]; then
    if [[ -f "$HOME/.bashrc" ]]; then
        SHELL_PROFILE="$HOME/.bashrc"
    elif [[ -f "$HOME/.zshrc" ]]; then
        SHELL_PROFILE="$HOME/.zshrc"
    else
        SHELL_PROFILE="$HOME/.bashrc"
        touch "$SHELL_PROFILE"
    fi
else
    if [[ -f "$HOME/.zshrc" ]]; then
        SHELL_PROFILE="$HOME/.zshrc"
    elif [[ -f "$HOME/.bashrc" ]]; then
        SHELL_PROFILE="$HOME/.bashrc"
    else
        SHELL_PROFILE="$HOME/.zshrc"
        touch "$SHELL_PROFILE"
    fi
fi

# Remove any existing CORDELIA_ENCRYPTION_KEY export (cleanup from old installs)
if grep -q "CORDELIA_ENCRYPTION_KEY" "$SHELL_PROFILE" 2>/dev/null; then
    # Remove the key line (no longer storing in shell profile)
    sed -i.bak '/CORDELIA_ENCRYPTION_KEY/d' "$SHELL_PROFILE"
    rm -f "${SHELL_PROFILE}.bak"
    warn "Removed plaintext encryption key from $SHELL_PROFILE (now stored in keychain)"
fi

# Add PATH entry for cordelia binaries
if ! grep -q 'cordelia/bin' "$SHELL_PROFILE" 2>/dev/null; then
    echo "" >> "$SHELL_PROFILE"
    echo "# Cordelia" >> "$SHELL_PROFILE"
    echo 'export PATH="$HOME/.cordelia/bin:$PATH"' >> "$SHELL_PROFILE"
    info "Added ~/.cordelia/bin to PATH in $SHELL_PROFILE"
else
    info "~/.cordelia/bin already in PATH"
fi

# Export for current session
export PATH="$CORDELIA_BIN:$PATH"

# ============================================
# Phase 9: Start node service
# ============================================
phase 9 "Start node service"

if [[ "$OS_NAME" = "macos" ]]; then
    # launchd
    PLIST_LABEL="ai.seeddrill.cordelia"
    PLIST_SRC="$SDK_DIR/setup/ai.seeddrill.cordelia.plist"
    PLIST_DEST="$HOME/Library/LaunchAgents/${PLIST_LABEL}.plist"

    if [[ -f "$PLIST_SRC" ]]; then
        mkdir -p "$HOME/Library/LaunchAgents"
        # Substitute home directory in plist
        sed "s|__HOME__|$HOME|g" "$PLIST_SRC" > "$PLIST_DEST"

        # Unload if already loaded (ignore errors)
        launchctl bootout "gui/$(id -u)/${PLIST_LABEL}" 2>/dev/null || true

        launchctl bootstrap "gui/$(id -u)" "$PLIST_DEST" 2>/dev/null || launchctl load "$PLIST_DEST" 2>/dev/null
        info "cordelia-node registered with launchd ($PLIST_LABEL)"
        info "Logs: $CORDELIA_LOGS/"
    else
        warn "launchd plist not found at $PLIST_SRC -- skipping service install"
        echo "Start manually: cordelia-node --config $CORDELIA_HOME/config.toml"
    fi

elif [[ "$OS_NAME" = "linux" ]]; then
    # systemd user unit
    UNIT_SRC="$SDK_DIR/setup/cordelia-node.service"
    UNIT_DIR="$HOME/.config/systemd/user"
    UNIT_DEST="$UNIT_DIR/cordelia-node.service"

    if [[ -f "$UNIT_SRC" ]]; then
        mkdir -p "$UNIT_DIR"
        sed "s|__HOME__|$HOME|g" "$UNIT_SRC" > "$UNIT_DEST"

        if systemctl --user daemon-reload 2>/dev/null; then
            systemctl --user enable cordelia-node.service
            systemctl --user start cordelia-node.service
            info "cordelia-node enabled and started (systemd user unit)"
            info "Check status: systemctl --user status cordelia-node"
            info "Logs: journalctl --user -u cordelia-node -f"
        else
            warn "systemd not available (container/WSL?) -- service unit installed but not started"
            info "Start manually: cordelia-node --config $CORDELIA_HOME/config.toml"
        fi
    else
        warn "systemd unit not found at $UNIT_SRC -- skipping service install"
        echo "Start manually: cordelia-node --config $CORDELIA_HOME/config.toml"
    fi
fi

# ============================================
# Phase 10: Post-migration verification
# ============================================
if [[ "$IS_MIGRATION" = true ]]; then
    phase 10 "Post-migration verification"
    MIGRATION_ERRORS=0

    # Verify memory DB exists and is accessible
    CORDELIA_DB="$MEMORY_ROOT/cordelia.db"
    if [[ -f "$CORDELIA_DB" ]] && [[ -s "$CORDELIA_DB" ]]; then
        info "Memory DB exists"
    else
        warn "Memory DB missing or empty"
        MIGRATION_ERRORS=$((MIGRATION_ERRORS+1))
    fi

    # Verify L2 item count matches pre-migration
    if [[ -n "$PRE_MIGRATION_L2_COUNT" ]] && command -v sqlite3 &>/dev/null; then
        POST_L2_COUNT=$(sqlite3 "$CORDELIA_DB" "SELECT COUNT(*) FROM l2_items;" 2>/dev/null || echo "")
        if [[ -n "$POST_L2_COUNT" ]] && [[ "$POST_L2_COUNT" -eq "$PRE_MIGRATION_L2_COUNT" ]]; then
            info "L2 item count preserved: $POST_L2_COUNT items"
        elif [[ -n "$POST_L2_COUNT" ]]; then
            warn "L2 item count changed: $PRE_MIGRATION_L2_COUNT -> $POST_L2_COUNT"
            MIGRATION_ERRORS=$((MIGRATION_ERRORS+1))
        fi
    fi

    # Verify config.toml has proxy_dir
    if grep -q 'proxy_dir' "$CORDELIA_CONFIG" 2>/dev/null; then
        info "config.toml has proxy_dir"
    else
        warn "config.toml missing proxy_dir"
        MIGRATION_ERRORS=$((MIGRATION_ERRORS+1))
    fi

    # Verify hooks point to SDK
    if grep -q 'cordelia-agent-sdk\|cordelia/sdk' "$SETTINGS_FILE" 2>/dev/null; then
        info "Hooks point to SDK paths"
    else
        warn "Hooks may still point to proxy paths"
        MIGRATION_ERRORS=$((MIGRATION_ERRORS+1))
    fi

    # Verify node.key preserved
    if [[ -f "$CORDELIA_HOME/node.key" ]]; then
        info "Node identity key preserved"
    else
        warn "Node identity key missing"
        MIGRATION_ERRORS=$((MIGRATION_ERRORS+1))
    fi

    if [[ $MIGRATION_ERRORS -gt 0 ]]; then
        echo ""
        warn "Migration completed with $MIGRATION_ERRORS warnings."
        echo "Backup available at: $BACKUP_DIR"
        echo ""
        echo "To rollback:"
        echo "  cp $BACKUP_DIR/config.toml $CORDELIA_HOME/config.toml"
        echo "  # Restore hooks to proxy paths in ~/.claude/settings.json"
    else
        info "Migration verification passed -- all checks OK"
    fi
fi

# ============================================
# Validate
# ============================================
echo ""
echo "--- Validation ---"
ERRORS=0

[[ -x "$BINARY_PATH" ]] && info "cordelia-node binary" || { warn "cordelia-node binary missing"; ERRORS=$((ERRORS+1)); }
[[ -f "$PROXY_DIR/dist/server.js" ]] && info "MCP proxy built" || { warn "MCP proxy missing"; ERRORS=$((ERRORS+1)); }
[[ -f "$GLOBAL_MCP" ]] && info "MCP config (~/.claude.json)" || { warn "MCP config missing"; ERRORS=$((ERRORS+1)); }
[[ -f "$SETTINGS_FILE" ]] && info "Claude hooks" || { warn "Claude hooks missing"; ERRORS=$((ERRORS+1)); }
[[ -d "$SKILLS_DEST/persist" ]] && info "Skills installed" || { warn "Skills missing"; ERRORS=$((ERRORS+1)); }
[[ -f "$CORDELIA_CONFIG" ]] && info "Node config" || { warn "Node config missing"; ERRORS=$((ERRORS+1)); }

CORDELIA_DB="$MEMORY_ROOT/cordelia.db"
[[ -f "$CORDELIA_DB" ]] && [[ -s "$CORDELIA_DB" ]] && info "L1 memory seeded" || { warn "L1 memory missing"; ERRORS=$((ERRORS+1)); }

KEY_LEN=${#ENCRYPTION_KEY}
[[ "$KEY_LEN" -eq 64 ]] && info "Encryption key valid (64 chars)" || { warn "Encryption key wrong length: $KEY_LEN"; ERRORS=$((ERRORS+1)); }

# Verify key NOT in shell profile
if grep -q "CORDELIA_ENCRYPTION_KEY" "$SHELL_PROFILE" 2>/dev/null; then
    warn "Encryption key still in shell profile -- remove manually"
    ERRORS=$((ERRORS+1))
else
    info "No plaintext key in shell profile"
fi

if [[ $ERRORS -gt 0 ]]; then
    warn "Completed with $ERRORS warnings"
else
    info "All validations passed"
fi

# ============================================
# Done
# ============================================
echo ""
echo "========================================"
echo "      Installation Complete!"
echo "========================================"
echo ""
echo "Cordelia is ready for: $USER_ID"
echo ""
echo "Layout:"
echo "  Binary:    ~/.cordelia/bin/cordelia-node"
echo "  SDK:       $SDK_DIR"
echo "  Proxy:     $PROXY_DIR"
echo "  Config:    ~/.cordelia/config.toml"
echo "  Memory:    ~/.cordelia/memory/cordelia.db"
echo "  MCP:       ~/.claude.json"
echo "  Hooks:     ~/.claude/settings.json (SDK paths)"
echo "  Skills:    ~/.claude/skills/ (persist, sprint, remember)"
echo ""
echo "Next steps:"
echo "  1. Open a NEW terminal (to pick up PATH changes)"
echo "  2. Run 'claude' from any directory"
echo "  3. You should see: [CORDELIA] Session 1 | Genesis..."
echo ""

if [[ "$KEY_STORED" = true ]]; then
    echo "Your encryption key is stored securely in the platform keychain."
else
    echo "IMPORTANT: Your encryption key is stored in ~/.cordelia/key"
    echo "Back it up somewhere safe. If you lose it, your memory cannot be recovered."
fi

echo ""
echo "Encryption key (save this):"
echo ""
echo "  $ENCRYPTION_KEY"
echo ""
