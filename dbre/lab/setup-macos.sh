#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# DBRE Lab — macOS developer setup
#
# Installs everything needed to run the lab and follow the DBRE guide:
#   Docker Desktop, MySQL client tools, Percona Toolkit, gh-ost,
#   sysbench, fio, and supporting utilities.
#
# Usage:
#   chmod +x setup-macos.sh && ./setup-macos.sh
#
# Idempotent — safe to run multiple times.
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; RESET='\033[0m'

ok()   { echo -e "${GREEN}✓${RESET} $1"; }
warn() { echo -e "${YELLOW}⚠${RESET}  $1"; }
info() { echo -e "${BLUE}→${RESET} $1"; }
fail() { echo -e "${RED}✗${RESET} $1"; }
header() { echo; echo -e "${BOLD}━━━ $1 ━━━${RESET}"; }

# ── Helpers ───────────────────────────────────────────────────────────────────
check_cmd() {
  if command -v "$1" &>/dev/null; then
    ok "$1 $(command -v $1)"
    return 0
  else
    return 1
  fi
}

brew_install() {
  local pkg=$1
  local check_cmd=${2:-$1}   # optional: the binary name if different from package
  if command -v "$check_cmd" &>/dev/null; then
    ok "$pkg already installed ($(command -v $check_cmd))"
  else
    info "Installing $pkg..."
    brew install "$pkg"
    ok "$pkg installed"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
header "1. Homebrew"
# ─────────────────────────────────────────────────────────────────────────────
if ! command -v brew &>/dev/null; then
  info "Homebrew not found — installing..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  # Apple Silicon: add brew to PATH for this session
  if [[ "$(uname -m)" == "arm64" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
  ok "Homebrew installed"
else
  ok "Homebrew $(brew --version | head -1)"
fi

#brew update --quiet

# ─────────────────────────────────────────────────────────────────────────────
header "2. Docker Desktop"
# ─────────────────────────────────────────────────────────────────────────────
if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
  ok "Docker $(docker --version)"
  ok "Docker Compose $(docker compose version --short 2>/dev/null || echo 'v2')"
else
  if command -v docker &>/dev/null; then
    warn "Docker CLI found but daemon is not running."
    warn "Start Docker Desktop from Applications, then re-run this script."
  else
    info "Docker Desktop not found — installing via Homebrew Cask..."
    brew install --cask docker
    warn "Docker Desktop installed. Open it from Applications to start the daemon,"
    warn "then re-run this script to verify."
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
header "3. MySQL client tools"
# mysql, mysqladmin, mysqldump, mysqlbinlog, mysqlslap — all in mysql-client
# ─────────────────────────────────────────────────────────────────────────────
if ! command -v mysql &>/dev/null; then
  info "Installing mysql-client (provides mysql, mysqldump, mysqlbinlog, mysqlslap)..."
  brew install mysql-client

  # mysql-client is keg-only — add to PATH
  MYSQL_PREFIX="$(brew --prefix mysql-client)"
  SHELL_RC=""
  case "$SHELL" in
    */zsh)  SHELL_RC="$HOME/.zshrc" ;;
    */bash) SHELL_RC="$HOME/.bash_profile" ;;
  esac

  if [[ -n "$SHELL_RC" ]] && ! grep -q "mysql-client" "$SHELL_RC" 2>/dev/null; then
    echo "" >> "$SHELL_RC"
    echo "# MySQL client tools (added by DBRE lab setup)" >> "$SHELL_RC"
    echo 'export PATH="'"$MYSQL_PREFIX/bin"':$PATH"' >> "$SHELL_RC"
    warn "Added mysql-client to PATH in $SHELL_RC"
    warn "Run: source $SHELL_RC  (or open a new terminal)"
  fi

  export PATH="$MYSQL_PREFIX/bin:$PATH"
  ok "mysql-client installed"
else
  ok "mysql $(mysql --version)"
fi

# Verify individual tools
for tool in mysql mysqladmin mysqldump mysqlbinlog mysqlslap; do
  check_cmd "$tool" || warn "$tool not in PATH — run: source ~/.zshrc"
done

# ─────────────────────────────────────────────────────────────────────────────
header "4. Percona Toolkit"
# pt-online-schema-change, pt-table-checksum, pt-table-sync,
# pt-query-digest, pt-duplicate-key-checker, pt-mysql-summary
# ─────────────────────────────────────────────────────────────────────────────
brew_install percona-toolkit pt-online-schema-change

# Verify the key pt-* tools are present
PT_TOOLS=(
  pt-online-schema-change
  pt-table-checksum
  pt-table-sync
  pt-query-digest
  pt-duplicate-key-checker
  pt-mysql-summary
  pt-heartbeat
  pt-slave-delay
  pt-show-grants
  pt-variable-advisor
  pt-index-usage
)

echo
info "Verifying pt-* tools:"
missing_pt=0
for tool in "${PT_TOOLS[@]}"; do
  if command -v "$tool" &>/dev/null; then
    echo -e "   ${GREEN}✓${RESET} $tool"
  else
    echo -e "   ${RED}✗${RESET} $tool — missing"
    ((missing_pt++)) || true
  fi
done

if [[ $missing_pt -gt 0 ]]; then
  warn "$missing_pt pt-* tools not found in PATH. Try: brew reinstall percona-toolkit"
fi

# ─────────────────────────────────────────────────────────────────────────────
header "5. gh-ost — Online Schema Change (binlog-based, no triggers)"
# ─────────────────────────────────────────────────────────────────────────────
brew_install gh-ost gh-ost

# ─────────────────────────────────────────────────────────────────────────────
header "6. sysbench — MySQL load testing"
# ─────────────────────────────────────────────────────────────────────────────
brew_install sysbench sysbench

# ─────────────────────────────────────────────────────────────────────────────
header "7. fio — disk IOPS measurement (innodb_io_capacity tuning)"
# ─────────────────────────────────────────────────────────────────────────────
brew_install fio fio

# ─────────────────────────────────────────────────────────────────────────────
header "8. Supporting utilities"
# ─────────────────────────────────────────────────────────────────────────────
brew_install netcat nc          # nc — gh-ost socket control (echo throttle | nc -U ...)
brew_install pv pv              # pipe viewer — progress bar for mysqldump restores
brew_install jq jq              # JSON processing — docker API, gh-ost output
brew_install redis redis-cli    # redis-cli — host-side Valkey benchmark (scripts/13, 14)

# moreutils provides ts (timestamp), sponge, etc. — useful for log monitoring
brew install moreutils 2>/dev/null && ok "moreutils installed" || true

# ─────────────────────────────────────────────────────────────────────────────
header "9. Percona XtraBackup"
# ─────────────────────────────────────────────────────────────────────────────
# xtrabackup has no official macOS binary — runs inside Docker in this lab.
# For local install on Linux or in CI: https://www.percona.com/downloads/XtraBackup/
if command -v xtrabackup &>/dev/null; then
  ok "xtrabackup $(xtrabackup --version 2>&1 | head -1)"
else
  info "xtrabackup — not available as native macOS binary."
  info "In this lab it runs inside the 'toolkit' Docker container:"
  echo "  docker exec toolkit xtrabackup --version"
  info "For Linux install: https://docs.percona.com/percona-xtrabackup/8.0/installation.html"
fi

# ─────────────────────────────────────────────────────────────────────────────
header "10. Apple Silicon (M1/M2/M3) notes"
# ─────────────────────────────────────────────────────────────────────────────
if [[ "$(uname -m)" == "arm64" ]]; then
  info "Apple Silicon detected."
  info "Docker Desktop runs ARM64 images natively (mysql:8.0 supports arm64)."
  info "All lab containers use linux/amd64 emulation via Rosetta when needed."
  info "Performance is slightly lower than native — acceptable for lab use."
  warn "If containers fail to start with 'exec format error': open Docker Desktop"
  warn "→ Settings → Features in Development → enable 'Use Rosetta for x86/amd64'"
fi

# ─────────────────────────────────────────────────────────────────────────────
header "Summary"
# ─────────────────────────────────────────────────────────────────────────────
echo
printf "%-30s %s\n" "Tool" "Version / Status"
printf "%-30s %s\n" "──────────────────────────────" "────────────────────────────────"

print_version() {
  local name=$1
  local cmd=$2
  if command -v "$cmd" &>/dev/null; then
    local ver
    ver=$($2 --version 2>&1 | head -1 | sed 's/.*version //' | sed 's/ .*//' | cut -c1-30)
    printf "%-30s ${GREEN}%s${RESET}\n" "$name" "$ver"
  else
    printf "%-30s ${RED}%s${RESET}\n" "$name" "NOT FOUND"
  fi
}

print_version "docker"                  "docker"
print_version "docker compose"          "docker"
print_version "mysql (client)"          "mysql"
print_version "mysqldump"               "mysqldump"
print_version "pt-online-schema-change" "pt-online-schema-change"
print_version "pt-query-digest"         "pt-query-digest"
print_version "pt-table-checksum"       "pt-table-checksum"
print_version "gh-ost"                  "gh-ost"
print_version "sysbench"                "sysbench"
print_version "fio"                     "fio"
print_version "nc (netcat)"             "nc"
print_version "pv"                      "pv"
print_version "jq"                      "jq"
print_version "redis-cli"               "redis-cli"

echo
info "xtrabackup: runs in 'toolkit' Docker container (no macOS binary)"
echo
echo -e "${BOLD}Next steps:${RESET}"
echo "  1. Make sure Docker Desktop is running"
echo "  2. cd dbre/lab"
echo "  3. docker compose up -d"
echo "  4. ./scripts/01-setup-replication.sh"
echo "  5. Open http://localhost:3000  (Grafana — admin/admin)"
echo "     Open http://localhost:8080  (Adminer — root/rootpass)"
echo "     Open http://localhost:8404  (HAProxy stats)"
