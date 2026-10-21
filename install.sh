#!/usr/bin/env bash
# Pegify installer — sets up Pegify in binary (user) or source (contributor) mode.
#
# Usage:
#   curl -fsSL https://pegify.dev/install.sh | bash          # binary mode (default)
#   bash install.sh                                            # binary mode (default)
#   bash install.sh --binary                                   # binary mode (explicit)
#   bash install.sh --source                                   # source/contributor mode
#   bash install.sh --help                                     # show this help
#
# Options:
#   --binary          Download pre-built release binary (default, recommended for users)
#   --source          Install from source in the current repo (for contributors)
#   --no-service      Skip daemon service installation
#   --version X.Y     Binary mode: install a specific release version (default: latest)
#   --help            Show this help message

set -euo pipefail

GITHUB_REPO="Pegify/Pegify"
PEGIFY_HOME="$HOME/.pegify"
PEGIFY_CONFIG="$PEGIFY_HOME/config.yaml"
INSTALL_DIR="$HOME/.local/bin"
PLUGIN_CACHE="$HOME/.claude/plugins/cache/pegify"
NO_SERVICE=false
TARGET_VERSION=""
INSTALL_MODE="binary"   # default: binary

# ── Parse arguments ──────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --binary)     INSTALL_MODE="binary"; shift ;;
        --source)     INSTALL_MODE="source"; shift ;;
        --no-service) NO_SERVICE=true; shift ;;
        --version)    TARGET_VERSION="$2"; shift 2 ;;
        --help|-h)
            cat <<'HELP'
Pegify Installer

USAGE
  bash install.sh [OPTIONS]

MODES
  --binary  (default) Download a pre-built native binary from GitHub Releases.
            Sets auth_mode: subscription so your Claude.ai plan powers the Pegis.
            Recommended for end-users.

  --source  Clone the repo and install from source using uv.
            Intended for contributors and developers.
            Requires Python 3.11+ and uv.

OPTIONS
  --no-service      Skip daemon service installation (useful in CI/containers)
  --version X.Y     Binary mode: pin to a specific release version
  --help            Show this help

EXAMPLES
  # End-user install (recommended)
  curl -fsSL https://pegify.dev/install.sh | bash

  # Contributor / source install
  git clone https://github.com/Pegify/pegify && cd pegify
  bash install.sh --source

  # Install specific version
  bash install.sh --version 0.9.2
HELP
            exit 0
            ;;
        *) shift ;;
    esac
done

# ── Colors ───────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${CYAN}[pegify]${NC} $*"; }
ok()    { echo -e "${GREEN}[  OK  ]${NC} $*"; }
warn()  { echo -e "${YELLOW}[ WARN ]${NC} $*"; }
fail()  { echo -e "${RED}[ FAIL ]${NC} $*"; exit 1; }

echo ""
echo -e "${BOLD}${CYAN}  ____            _  __       ${NC}"
echo -e "${BOLD}${CYAN} |  _ \\ ___  __ _(_)/ _|_   _ ${NC}"
echo -e "${BOLD}${CYAN} | |_) / _ \\/ _\` | | |_| | | |${NC}"
echo -e "${BOLD}${CYAN} |  __/  __/ (_| | |  _| |_| |${NC}"
echo -e "${BOLD}${CYAN} |_|   \\___|\\__, |_|_|  \\__, |${NC}"
echo -e "${BOLD}${CYAN}            |___/       |___/ ${NC}"
echo ""
echo -e "  ${BOLD}Pegi Operations Platform${NC}"
echo ""

if [ "$INSTALL_MODE" = "binary" ]; then
    echo -e "  Mode: ${BOLD}binary${NC} (user install)"
else
    echo -e "  Mode: ${BOLD}source${NC} (contributor install)"
fi
echo ""

# ── Detect platform (binary mode only) ───────────────────────────────
if [ "$INSTALL_MODE" = "binary" ]; then
    OS="$(uname -s)"
    ARCH="$(uname -m)"

    case "$OS" in
        Linux)  PLATFORM="linux" ;;
        Darwin) PLATFORM="macos" ;;
        *)      fail "Unsupported OS: $OS. Pegify supports Linux and macOS." ;;
    esac

    case "$ARCH" in
        x86_64|amd64)  ARCH="x86_64" ;;
        aarch64|arm64) ARCH="arm64" ;;
        *)             fail "Unsupported architecture: $ARCH" ;;
    esac

    BINARY_NAME="pegify-${PLATFORM}-${ARCH}"
    info "Platform: ${PLATFORM}/${ARCH}"
fi

PEGIFY_LOCAL_DB_NAME="${PEGIFY_LOCAL_DB_NAME:-pegify_local}"
PEGIFY_LOCAL_DB_URL="${PEGIFY_DB_URL:-postgresql://127.0.0.1:5432/${PEGIFY_LOCAL_DB_NAME}}"

ensure_postgres_ready() {
    if ! command -v psql &>/dev/null; then
        fail "PostgreSQL client not found. Install PostgreSQL, then rerun install.sh. See docs/deploy/postgres-setup.md"
    fi
    if ! command -v createdb &>/dev/null; then
        fail "createdb not found. Install PostgreSQL server tools, then rerun install.sh. See docs/deploy/postgres-setup.md"
    fi
    if psql "$PEGIFY_LOCAL_DB_URL" -c 'SELECT 1' &>/dev/null; then
        ok "PostgreSQL database ready: $PEGIFY_LOCAL_DB_NAME"
        return
    fi
    info "Creating local PostgreSQL database: $PEGIFY_LOCAL_DB_NAME"
    if createdb "$PEGIFY_LOCAL_DB_NAME" &>/dev/null && psql "$PEGIFY_LOCAL_DB_URL" -c 'SELECT 1' &>/dev/null; then
        ok "PostgreSQL database created: $PEGIFY_LOCAL_DB_NAME"
        return
    fi
    fail "Could not create/connect to local PostgreSQL database '$PEGIFY_LOCAL_DB_NAME'. Start PostgreSQL or set PEGIFY_DB_URL to a local/staging/test database URL."
}

ensure_postgres_ready

# ════════════════════════════════════════════════════════════════════
# BINARY MODE — download pre-built release binary
# ════════════════════════════════════════════════════════════════════
if [ "$INSTALL_MODE" = "binary" ]; then

    # ── Determine version ────────────────────────────────────────────
    if [ -n "$TARGET_VERSION" ]; then
        VERSION="$TARGET_VERSION"
    else
        info "Checking latest version..."
        RELEASE_JSON=$(curl -fsSL "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" 2>/dev/null) \
            || fail "Cannot reach GitHub. Check your internet connection."
        VERSION=$(echo "$RELEASE_JSON" | grep '"tag_name"' | head -1 | sed 's/.*"v\([^"]*\)".*/\1/')
    fi

    [ -z "$VERSION" ] && fail "Could not determine version."
    info "Version: ${VERSION}"

    DOWNLOAD_BASE="https://github.com/${GITHUB_REPO}/releases/download/v${VERSION}"
    DOWNLOAD_URL="${DOWNLOAD_BASE}/${BINARY_NAME}"
    CHECKSUMS_URL="${DOWNLOAD_BASE}/checksums.txt"

    # ── Check for local binary (offline mode) ────────────────────────
    LOCAL_BINARY=""
    if [ -f "./${BINARY_NAME}" ]; then
        LOCAL_BINARY="./${BINARY_NAME}"
        info "Found local binary: ${LOCAL_BINARY} (offline mode)"
    elif [ -f "./pegify" ]; then
        LOCAL_BINARY="./pegify"
        info "Found local binary: ${LOCAL_BINARY} (offline mode)"
    fi

    # ── Download binary ──────────────────────────────────────────────
    mkdir -p "$INSTALL_DIR"
    TARGET="${INSTALL_DIR}/pegify"

    if [ -n "$LOCAL_BINARY" ]; then
        cp "$LOCAL_BINARY" "$TARGET"
        ok "Copied local binary"
    else
        info "Downloading Pegify v${VERSION}..."
        # Show a progress bar when attached to a terminal; stay silent in piped installs.
        # In tty mode use curl's exit code (-f exits non-zero on HTTP error) rather
        # than parsing -w "%{http_code}" from a mixed stderr/stdout stream.
        if [ -t 1 ]; then
            if curl -f --progress-bar -L -o "$TARGET" "$DOWNLOAD_URL" 2>/dev/tty; then
                HTTP_CODE="200"
            else
                HTTP_CODE="000"
            fi
        else
            HTTP_CODE=$(curl -fsSL -w "%{http_code}" -o "$TARGET" "$DOWNLOAD_URL" 2>/dev/null) || true
        fi
        if [ ! -s "$TARGET" ] || [ "${HTTP_CODE:-0}" != "200" ]; then
            rm -f "$TARGET"
            fail "Download failed (HTTP ${HTTP_CODE:-unknown}). URL: $DOWNLOAD_URL"
        fi
        ok "Downloaded ${BINARY_NAME}"
    fi

    chmod +x "$TARGET"

    # ── Verify checksum ──────────────────────────────────────────────
    if [ -z "$LOCAL_BINARY" ]; then
        info "Verifying checksum..."
        CHECKSUMS=$(curl -fsSL "$CHECKSUMS_URL" 2>/dev/null) || true
        if [ -n "$CHECKSUMS" ]; then
            EXPECTED=$(echo "$CHECKSUMS" | grep "$BINARY_NAME" | awk '{print $1}')
            if [ -n "$EXPECTED" ]; then
                if command -v sha256sum &>/dev/null; then
                    ACTUAL=$(sha256sum "$TARGET" | awk '{print $1}')
                elif command -v shasum &>/dev/null; then
                    ACTUAL=$(shasum -a 256 "$TARGET" | awk '{print $1}')
                else
                    rm -f "$TARGET"
                    fail "Cannot verify checksum: install sha256sum or shasum first."
                fi
                if [ "$ACTUAL" != "$EXPECTED" ]; then
                    rm -f "$TARGET"
                    fail "Checksum mismatch! Expected: $EXPECTED Got: $ACTUAL"
                fi
                ok "Checksum verified"
            else
                warn "Binary not found in checksums.txt — skipping verification"
            fi
        else
            warn "Could not download checksums.txt — skipping verification"
        fi
    fi

    # ── Clear macOS quarantine ───────────────────────────────────────
    if [ "$PLATFORM" = "macos" ]; then
        xattr -d com.apple.quarantine "$TARGET" 2>/dev/null || true
    fi

    # ── Smoke test ───────────────────────────────────────────────────
    if "$TARGET" --version &>/dev/null; then
        ok "Pegify $("$TARGET" --version 2>&1)"
    else
        rm -f "$TARGET"
        fail "Binary downloaded but won't run. Architecture mismatch? Run: file $TARGET"
    fi

    # ── Ensure ~/.local/bin is in PATH ───────────────────────────────
    if ! echo "$PATH" | tr ':' '\n' | grep -qx "$INSTALL_DIR"; then
        SHELL_RC=""
        case "${SHELL:-/bin/bash}" in
            */zsh)  SHELL_RC="$HOME/.zshrc" ;;
            */bash) SHELL_RC="$HOME/.bashrc" ;;
            *)      SHELL_RC="$HOME/.profile" ;;
        esac
        if [ -n "$SHELL_RC" ] && ! grep -q "$INSTALL_DIR" "$SHELL_RC" 2>/dev/null; then
            echo "export PATH=\"${INSTALL_DIR}:\$PATH\"" >> "$SHELL_RC"
            ok "Added ${INSTALL_DIR} to PATH in ${SHELL_RC}"
        fi
        export PATH="${INSTALL_DIR}:$PATH"
    fi

# ════════════════════════════════════════════════════════════════════
# SOURCE MODE — install from repo using uv (contributor path)
# ════════════════════════════════════════════════════════════════════
else  # INSTALL_MODE = source

    # ── Check Python 3.11+ ───────────────────────────────────────────
    info "Checking Python 3.11+..."
    if command -v python3 &>/dev/null; then
        PY_VER=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
        PY_MAJOR=$(echo "$PY_VER" | cut -d. -f1)
        PY_MINOR=$(echo "$PY_VER" | cut -d. -f2)
        if [ "$PY_MAJOR" -ge 3 ] && [ "$PY_MINOR" -ge 11 ]; then
            ok "Python $PY_VER"
        else
            fail "Python $PY_VER found but 3.11+ required"
        fi
    else
        fail "Python 3 not found. Install Python 3.11+ first."
    fi

    # ── Check/install uv ─────────────────────────────────────────────
    info "Checking uv package manager..."
    if command -v uv &>/dev/null; then
        ok "uv $(uv --version 2>/dev/null | head -1)"
    else
        info "Installing uv..."
        curl -LsSf https://astral.sh/uv/install.sh | sh
        export PATH="$HOME/.local/bin:$PATH"
        ok "uv installed"
    fi

    # ── Install Pegify from source ───────────────────────────────────
    info "Installing Pegify from source..."
    if command -v pegify &>/dev/null; then
        ok "Pegify already installed ($(pegify --version 2>/dev/null || echo 'unknown version'))"
    else
        if [ -f "pyproject.toml" ] && grep -q "pegify" pyproject.toml 2>/dev/null; then
            uv pip install -e . 2>/dev/null || uv sync 2>/dev/null
            ok "Pegify installed from source"
        else
            fail "pyproject.toml not found or not a Pegify repo. Clone the repo first: git clone https://github.com/Pegify/pegify && cd pegify"
        fi
    fi

    TARGET="$(command -v pegify 2>/dev/null || echo 'uv run pegify')"

    # ── Source symlink — lets plugin sync find the repo ──────────────
    REPO_DIR="$(pwd)"
    SRC_LINK="$PEGIFY_HOME/src"
    mkdir -p "$PEGIFY_HOME"
    if [ ! -e "$SRC_LINK" ]; then
        ln -s "$REPO_DIR" "$SRC_LINK"
        ok "Created ~/.pegify/src → $REPO_DIR"
    else
        ok "~/.pegify/src already set"
    fi

fi  # end mode split

# ════════════════════════════════════════════════════════════════════
# SHARED SETUP — runs in both modes
# ════════════════════════════════════════════════════════════════════

# ── Create ~/.pegify ─────────────────────────────────────────────────
info "Setting up ~/.pegify..."
mkdir -p "$PEGIFY_HOME/logs"

# Capture first-install state before we create the config so we can run
# `pegify init` later. Checking the config file (not ~/.pegify itself, which
# we just created) correctly identifies a brand-new install regardless of
# which directory the user is running the installer from.
FIRST_INSTALL=false
if [ ! -f "$PEGIFY_CONFIG" ]; then
    FIRST_INSTALL=true
fi

if [ ! -f "$PEGIFY_CONFIG" ]; then
    if [ "$INSTALL_MODE" = "binary" ]; then
        cat > "$PEGIFY_CONFIG" << YAML
# Pegify configuration
daemon:
  host: 127.0.0.1
  port: 7654
  auto_restart: true

auth_mode: subscription

database:
  backend: postgres
  url: ${PEGIFY_LOCAL_DB_URL}

providers:
  anthropic:
    models:
      - id: claude-sonnet-4-6
        name: Claude Sonnet 4.6
        context_window: 200000
        max_tokens: 64000
      - id: claude-opus-4-6
        name: Claude Opus 4.6
        context_window: 1000000
        max_tokens: 64000
      - id: claude-haiku-4-5
        name: Claude Haiku 4.5
        context_window: 200000
        max_tokens: 8192

approval:
  mode: smart

auto_update:
  enabled: true
  check_interval: 86400
  mode: notify

channels:
  - name: dev
    description: Development channel

pegis: []
YAML
    else
        # Source mode: no auth_mode: subscription, no auto_update
        cat > "$PEGIFY_CONFIG" << YAML
# Pegify configuration
daemon:
  host: 127.0.0.1
  port: 7654
  auto_restart: true

database:
  backend: postgres
  url: ${PEGIFY_LOCAL_DB_URL}

providers:
  anthropic:
    models:
      - id: claude-sonnet-4-6
        name: Claude Sonnet 4.6
        context_window: 200000
        max_tokens: 64000
      - id: claude-opus-4-6
        name: Claude Opus 4.6
        context_window: 1000000
        max_tokens: 64000
      - id: claude-haiku-4-5
        name: Claude Haiku 4.5
        context_window: 200000
        max_tokens: 8192

approval:
  mode: smart

channels:
  - name: dev
    description: Development channel

pegis: []
YAML
    fi
    ok "Created config at $PEGIFY_CONFIG"
else
    ok "Config already exists"
fi

if ! grep -q '^database:' "$PEGIFY_CONFIG" 2>/dev/null; then
    cat >> "$PEGIFY_CONFIG" << YAML

database:
  backend: postgres
  url: ${PEGIFY_LOCAL_DB_URL}
YAML
    ok "Added PostgreSQL database config to $PEGIFY_CONFIG"
fi

# ── Auth setup ───────────────────────────────────────────────────────
if [ "$INSTALL_MODE" = "binary" ]; then
    # Binary mode: offer subscription (Claude.ai plan) or API key.
    # When stdin is not a tty (curl | bash), skip the prompt and default to
    # subscription — an interactive read would silently receive EOF and the
    # installer would exit or hang.
    AUTH_CHOICE=""
    if [ -t 0 ]; then
        echo ""
        echo -e "  ${BOLD}How do you want Pegify to access Claude?${NC}"
        echo "    1) Claude.ai plan / subscription (recommended — uses Claude Code login)"
        echo "    2) Anthropic API key"
        echo -n "  Choose [1/2] (default: 1): "
        read -r AUTH_CHOICE
        echo ""
    else
        info "Non-interactive install detected — defaulting to subscription auth (Claude.ai plan)"
        info "To switch later, pipe the key to: pegify config provider set anthropic --api anthropic --api-key-stdin"
    fi

    if [ "${AUTH_CHOICE:-1}" = "2" ]; then
        API_KEY="${ANTHROPIC_API_KEY:-}"
        if [ -z "$API_KEY" ]; then
            printf "  Enter your Anthropic API key (or press Enter to skip and set it later):\n"
            printf "  API key: "
            read -rs API_KEY
            echo ""
        fi
        if [ -n "$API_KEY" ]; then
            if ! printf '%s\n' "$API_KEY" | "$TARGET" config provider set anthropic \
                --api anthropic --api-key-stdin >/dev/null; then
                fail "Secure provider credential storage failed; API key was not saved"
            fi
            python3 - "$PEGIFY_CONFIG" <<'PYEOF'
import os
import sys
import tempfile

path = sys.argv[1]
with open(path) as handle:
    content = handle.read()
content = content.replace("auth_mode: subscription", "auth_mode: api", 1)
fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".config_", suffix=".tmp")
try:
    with os.fdopen(fd, "w") as handle:
        handle.write(content)
    os.replace(tmp_path, path)
except Exception:
    try:
        os.unlink(tmp_path)
    except OSError:
        pass
    raise
PYEOF
            ok "API key stored securely; config contains only an opaque reference"
        else
            warn "No API key entered — use 'pegify config provider set anthropic --api anthropic --api-key-stdin' later"
        fi
    else
        ok "Auth mode: subscription (Claude.ai plan via Claude Code OAuth)"
        info "Make sure you are logged in to Claude Code: run 'claude' and sign in if prompted"
    fi
else
    # Source mode: simple API key prompt
    ANTHROPIC_KEY="${ANTHROPIC_API_KEY:-}"
    if [ -z "$ANTHROPIC_KEY" ]; then
        echo ""
        info "No ANTHROPIC_API_KEY found in environment."
        printf "  Enter your Anthropic API key (or press Enter to skip): "
        read -rs ANTHROPIC_KEY
        echo ""
    fi

    if [ -n "$ANTHROPIC_KEY" ]; then
        if ! printf '%s\n' "$ANTHROPIC_KEY" | "$TARGET" config provider set anthropic \
            --api anthropic --api-key-stdin >/dev/null; then
            fail "Secure provider credential storage failed; API key was not saved"
        fi
        ok "API key stored securely; config contains only an opaque reference"
    else
        warn "No API key set. Use 'pegify config provider set anthropic --api anthropic --api-key-stdin' later"
    fi
fi

# ── Install system service ───────────────────────────────────────────
if [ "$NO_SERVICE" = "false" ]; then
    info "Installing system service..."
    if "$TARGET" daemon install 2>/dev/null; then
        ok "Service installed"
    else
        warn "Service install failed — you can start manually: pegify daemon start"
    fi

    # On Linux, enable linger so the user service survives logout
    if [ "${PLATFORM:-}" = "linux" ] && command -v loginctl &>/dev/null; then
        loginctl enable-linger "$(whoami)" 2>/dev/null \
            && ok "loginctl linger enabled — daemon persists after logout" \
            || warn "loginctl enable-linger failed — daemon may stop when you log out"
    fi

    info "Starting Pegify daemon..."
    DAEMON_STARTED=false
    # Poll /health every 500 ms (max 10 s) instead of two blind sleep 3 calls.
    _wait_for_daemon() {
        local deadline=$(( $(date +%s) + 10 ))
        while [ "$(date +%s)" -lt "$deadline" ]; do
            # --max-time 1 prevents a half-open TCP connection from hanging
            # a single poll past the 10 s deadline.
            if curl -s --max-time 1 http://127.0.0.1:7654/health &>/dev/null; then
                return 0
            fi
            sleep 0.5
        done
        return 1
    }
    if curl -s --max-time 1 http://127.0.0.1:7654/health &>/dev/null; then
        ok "Daemon already running"
        DAEMON_STARTED=true
    elif _wait_for_daemon; then
        ok "Daemon started via service"
        DAEMON_STARTED=true
    else
        "$TARGET" daemon start &>/dev/null &
        if _wait_for_daemon; then
            ok "Daemon started"
            DAEMON_STARTED=true
        else
            warn "Daemon didn't start. Run: pegify daemon start"
        fi
    fi
else
    info "Skipping service install (--no-service)"
fi

# ── Pegify MCP plugin for Claude Code ───────────────────────────────
if command -v claude &>/dev/null; then
    info "Installing Pegify MCP plugin for Claude Code..."
    if "$TARGET" plugin sync &>/dev/null; then
        ok "Pegify plugin synced (MCP + hooks active on next Claude Code session)"
    else
        warn "Plugin sync failed — run: pegify plugin sync"
    fi
else
    info "Claude Code not found — checking for Node.js to auto-install..."
    if command -v npm &>/dev/null; then
        # NOTE: npm install can take 60-180 s on a cold registry cache — this is a
        # UX-quality improvement (visible output + timeout) on a slow path, not a
        # root-cause fix. Real fixes (bundle a CC shim, background install, make CC
        # optional for first run) are tracked as follow-ups to M#49.
        info "Installing Claude Code via npm — this can take 1-3 minutes on first install..."
        # `timeout` is GNU coreutils — absent on stock macOS. Fall back to running
        # npm without a timeout rather than failing with "command not found".
        if command -v timeout >/dev/null 2>&1; then
            _npm_install() { timeout 90 npm install -g @anthropic-ai/claude-code; }
        else
            warn "timeout not available on this system — npm install may take longer than usual"
            _npm_install() { npm install -g @anthropic-ai/claude-code; }
        fi
        if _npm_install; then
            ok "Claude Code installed"
            info "Syncing Pegify MCP plugin..."
            if "$TARGET" plugin sync &>/dev/null; then
                ok "Pegify plugin synced (MCP + hooks active on next Claude Code session)"
            else
                warn "Plugin sync failed — run: pegify plugin sync"
            fi
        else
            warn "Claude Code install timed out or failed (npm took >90 s or errored)."
            warn "Install manually: npm install -g @anthropic-ai/claude-code"
            warn "Then run: pegify plugin sync"
        fi
    else
        warn "Node.js not found — install Claude Code manually: https://claude.ai/code"
        warn "Then run: pegify plugin sync"
    fi
fi

# ── Health check ─────────────────────────────────────────────────────
echo ""
info "Running health check..."
echo ""
"$TARGET" doctor 2>/dev/null || true

# ── First-time project init ───────────────────────────────────────────
# Run `pegify init` automatically for brand-new installs so the user can open
# the dashboard immediately without a manual follow-up step. Gated on
# FIRST_INSTALL (no config existed before we ran) and daemon being up — not
# on .pegify.yaml in cwd, which would re-run on every project checkout.
if [ "$FIRST_INSTALL" = "true" ] && [ "$DAEMON_STARTED" = "true" ]; then
    info "Initializing your first Pegify project..."
    if "$TARGET" init dev 2>/dev/null; then
        ok "Project initialized — channel 'dev' created"
    else
        warn "Auto-init skipped (run 'pegify init <channel>' to set up a project manually)"
    fi
fi

# ── Done ─────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
if [ "$INSTALL_MODE" = "binary" ]; then
    echo -e "${GREEN}  Pegify v${VERSION} is ready!${NC}"
else
    echo -e "${GREEN}  Pegify (source) is ready!${NC}"
fi
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  Quick start:"
echo "    pegify quickstart                    # Start daemon + open cockpit → follow /welcome"
echo "    pegify say dev \"Hello team!\"         # Send a message once Pegis are running"
echo "    pegify doctor                        # Check health"
echo ""
echo "  Upgrade:    pegify upgrade"
echo "  Uninstall:  pegify uninstall"
echo "  Docs:       https://github.com/${GITHUB_REPO}"
echo ""
if [ "$INSTALL_MODE" = "binary" ] && ! echo "$PATH" | tr ':' '\n' | grep -qx "$INSTALL_DIR"; then
    echo -e "  ${YELLOW}NOTE: Restart your terminal or run: source ~/.zshrc${NC}"
    echo ""
fi
