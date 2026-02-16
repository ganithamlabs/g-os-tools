#!/usr/bin/env bash
set -e

# ─── Output Helpers ──────────────────────────────────────────────────────────
info()    { echo -e "\033[0;34m[INFO]\033[0m $*"; }
success() { echo -e "\033[0;32m[OK]\033[0m $*"; }
warn()    { echo -e "\033[1;33m[WARN]\033[0m $*"; }
error()   { echo -e "\033[0;31m[ERROR]\033[0m $*" >&2; }

# ─── Usage ───────────────────────────────────────────────────────────────────
usage() {
    cat <<'EOF'
Usage: verify-files.sh [OPTIONS] [SOURCE_DIR]

Verify all required files are present before installation.

Arguments:
  SOURCE_DIR    Directory containing the scripts (default: script's directory)

Options:
  --help        Show this help message
EOF
    exit 0
}

# ─── Parse Arguments ─────────────────────────────────────────────────────────
SOURCE_DIR=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --help) usage ;;
        -*)     error "Unknown option: $1"; exit 1 ;;
        *)      SOURCE_DIR="$1"; shift ;;
    esac
done

if [ -z "$SOURCE_DIR" ]; then
    SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"
fi

if [ ! -d "$SOURCE_DIR" ]; then
    error "Source directory does not exist: $SOURCE_DIR"
    exit 1
fi

echo ""
echo "=== Claude Code Context Tools - File Verification ==="
echo ""
echo "  Source directory: $SOURCE_DIR"
echo ""

# ─── Required Files ─────────────────────────────────────────────────────────
REQUIRED_FILES=(
    "claude-context-manager.sh"
    "claude-context-loader.sh"
    "claude-context-switcher.sh"
    "claude-project-init.sh"
    "shell-config.sh"
    "setup.sh"
)

OPTIONAL_FILES=(
    "README.md"
    "REQUIREMENTS.md"
    "HighLevelDesign.md"
    "COMPLETE_GUIDE.md"
    "DEPLOYMENT_GUIDE.md"
    "QUICK_INSTALL.md"
    "FILE_MANIFEST.md"
)

# ─── Check Required Files ───────────────────────────────────────────────────
echo "  Required files:"
MISSING=0
for file in "${REQUIRED_FILES[@]}"; do
    if [ -f "$SOURCE_DIR/$file" ]; then
        echo -e "    \033[0;32m✓\033[0m $file"
    else
        echo -e "    \033[0;31m✗\033[0m $file [MISSING]"
        MISSING=$((MISSING + 1))
    fi
done
echo ""

# ─── Check Optional Files ───────────────────────────────────────────────────
echo "  Optional files:"
OPT_MISSING=0
for file in "${OPTIONAL_FILES[@]}"; do
    if [ -f "$SOURCE_DIR/$file" ]; then
        echo -e "    \033[0;32m✓\033[0m $file"
    else
        echo -e "    \033[1;33m-\033[0m $file [not found]"
        OPT_MISSING=$((OPT_MISSING + 1))
    fi
done
echo ""

# ─── Result ──────────────────────────────────────────────────────────────────
if [ "$MISSING" -gt 0 ]; then
    error "$MISSING required file(s) missing. Cannot proceed with installation."
    exit 1
fi

if [ "$OPT_MISSING" -gt 0 ]; then
    warn "$OPT_MISSING optional file(s) not found. Installation can proceed."
fi

success "All required files present. Ready to install."
echo ""
