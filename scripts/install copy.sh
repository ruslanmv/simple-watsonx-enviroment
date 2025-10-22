#!/usr/bin/env bash
# install.sh — Cross-platform installer dispatcher (Ubuntu, macOS, Windows/Git-Bash)
# - Detects OS and invokes the correct platform installers.
# - Resolves a usable Python ≥ 3.11 interpreter and exports PYTHON.
# - Allows overriding install dir with --install-dir/-d and interpreter with --python.
# - Prints the RuslanMV logo on start.

set -euo pipefail
IFS=$'\n\t'

# ── Blue runtime logo ────────────────────────────────────────────────────────
print_logo() {
  local BLUE="\033[1;34m"; local NC="\033[0m"
  echo -e "${BLUE}"
  cat <<'EOF'
                _
               | |
 _ __ _   _ ___| | __ _ _ __   _ __ _____   __
| '__| | | / __| |/ _` | '_ \| '_ ` _ \ \ / /
| |  | |_| \__ \ | (_| | | | | | | | | \ V /
|_|   \__,_|___/_|\__,_|_| |_|_| |_| |_|\_/

EOF
  echo -e "${NC}"
}

print_logo

# -----------------------------
# Arg parsing / config
# -----------------------------
INSTALL_ROOT="${INSTALL_ROOT:-$PWD}"
PYTHON="${PYTHON:-}"

usage() {
  cat <<'USAGE'
Usage: scripts/install.sh [--install-dir DIR] [--python /path/to/python]
  -d, --install-dir   Target directory to install/configure into (default: current directory)
      --python        Explicit Python interpreter to use (must be >= 3.11)
Environment overrides:
  INSTALL_ROOT=/path  PYTHON=/path/to/python  scripts/install.sh
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--install-dir)
      [[ $# -ge 2 ]] || { echo "Missing value for $1" >&2; exit 2; }
      INSTALL_ROOT="$2"; shift 2;;
    --python)
      [[ $# -ge 2 ]] || { echo "Missing value for $1" >&2; exit 2; }
      PYTHON="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *)
      echo "Unknown argument: $1" >&2; usage; exit 2;;
  esac
done

# -----------------------------
# Locate this script's directory (robust, handles symlinks)
# -----------------------------
SOURCE="${BASH_SOURCE[0]}"
while [[ -h "$SOURCE" ]]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"

echo "📂 Install root: ${INSTALL_ROOT}"
echo "📜 Script dir  : ${SCRIPT_DIR}"

# -----------------------------
# Helpers
# -----------------------------
is_wsl() {
  (grep -qi microsoft /proc/version 2>/dev/null) || \
  (grep -qiE 'microsoft|wsl' /proc/sys/kernel/osrelease 2>/dev/null)
}

# Resolve a Python >= 3.11 executable path
resolve_python_path() {
  # 1) Respect explicit override if valid
  if [[ -n "${PYTHON:-}" ]] && command -v "$PYTHON" >/dev/null 2>&1; then
    if "$PYTHON" - <<'PY' >/dev/null 2>&1; then
import sys; raise SystemExit(0 if sys.version_info[:2] >= (3,11) else 1)
PY
      command -v "$PYTHON"; return 0
    fi
  fi

  # 2) Preferred common names
  for cmd in python3.11 python3 python; do
    if command -v "$cmd" >/dev/null 2>&1; then
      if "$cmd" - <<'PY' >/dev/null 2>&1; then
import sys; raise SystemExit(0 if sys.version_info[:2] >= (3,11) else 1)
PY
        command -v "$cmd"; return 0
      fi
    fi
  done

  # 3) Windows launcher (resolve to actual path)
  if command -v py >/dev/null 2>&1 && py -3.11 -c "import sys" >/dev/null 2>&1; then
    py -3.11 -c "import sys; print(sys.executable)"; return 0
  fi

  return 1
}

# helper: run a script and exit if it fails
run_script() {
  local script_path="$1"
  local install_dir="$2" # Accept the installation directory as an argument

  echo "→ Running ${script_path}"
  if [[ ! -x "${script_path}" ]]; then
    echo "  (Making ${script_path} executable)"
    chmod +x "${script_path}"
  fi

  # Execute the sub-script, passing the target installation directory as its first argument.
  # The sub-script MUST be written to handle this argument.
  "${script_path}" "${install_dir}"
}

# -----------------------------
# Try to resolve Python now (ok if not found; platform installers may add it)
# -----------------------------
if PY_RESOLVED="$(resolve_python_path 2>/dev/null)"; then
  PYTHON="$PY_RESOLVED"
  export PYTHON
  echo "🐍 Using Python: ${PYTHON} ($("${PYTHON}" -c 'import sys; print(".".join(map(str,sys.version_info[:3])))'))"
else
  echo "ℹ️  Python ≥ 3.11 not currently available on PATH; platform installer will handle it."
fi

# -----------------------------
# OS detection and dispatch
# -----------------------------
OS_TYPE="$(uname -s)"

case "${OS_TYPE}" in
  Linux*)
    if is_wsl; then
      echo "🖥  Detected Linux (WSL)"
    else
      echo "🖥  Detected Linux"
    fi
    # Verify it's Ubuntu
    if grep -qi '^ID=ubuntu' /etc/os-release; then
      echo "✔  Ubuntu identified"
      run_script "${SCRIPT_DIR}/ubuntu/install_python311.sh" "${INSTALL_ROOT}"
      run_script "${SCRIPT_DIR}/ubuntu/install_docker.sh" "${INSTALL_ROOT}"
  
    else
      echo "❌  Unsupported Linux distro. This script currently supports Ubuntu only."
      exit 1
    fi
    ;;
  Darwin*)
    echo "🍎 Detected macOS"
    run_script "${SCRIPT_DIR}/mac/install_python311.sh" "${INSTALL_ROOT}"
    run_script "${SCRIPT_DIR}/mac/install_docker.sh" "${INSTALL_ROOT}"
  
    ;;
  MINGW*|MSYS*|CYGWIN*|Windows_NT)
    echo "🪟 Detected Windows (Git Bash/MSYS/Cygwin)"

    # Check if PowerShell is available
    if ! command -v pwsh &>/dev/null && ! command -v powershell &>/dev/null; then
      echo "❌ PowerShell not found. Please install PowerShell 7+ first: https://aka.ms/powershell" >&2
      exit 1
    fi
    POWERSHELL_CMD="$(command -v pwsh || command -v powershell)"

    echo "→ Using PowerShell: $POWERSHELL_CMD"
    "$POWERSHELL_CMD" -ExecutionPolicy Bypass -File "${SCRIPT_DIR}/windows/install_python_win.ps1" "${INSTALL_ROOT}"
    "$POWERSHELL_CMD" -ExecutionPolicy Bypass -File "${SCRIPT_DIR}/windows/install_docker.ps1" "${INSTALL_ROOT}"

    ;;
  *)
    echo "❓ Unknown OS: ${OS_TYPE}"
    echo "This script supports Ubuntu (Linux), macOS, and Windows (via Git Bash/MSYS/Cygwin)."
    exit 1
    ;;
esac

# Final hint for Makefiles that demand a 'python3.11' binary name
if [[ -n "${PYTHON:-}" ]]; then
  echo "💡 If a Makefile asks for python3.11 explicitly, pass the resolved interpreter:"
  echo "   make install PYTHON=\"${PYTHON}\""
fi

echo "✅ All done!"
