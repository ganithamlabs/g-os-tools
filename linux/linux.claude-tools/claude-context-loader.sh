#!/usr/bin/env bash
set -e

# ─── Output Helpers ──────────────────────────────────────────────────────────
info()    { echo -e "\033[0;34m[INFO]\033[0m $*"; }
success() { echo -e "\033[0;32m[OK]\033[0m $*"; }
warn()    { echo -e "\033[1;33m[WARN]\033[0m $*"; }
error()   { echo -e "\033[0;31m[ERROR]\033[0m $*" >&2; }
step()    { echo -e "\033[0;34m→\033[0m $*"; }

# ─── Constants ───────────────────────────────────────────────────────────────
CLAUDE_TRANSCRIPTS_DIR="$HOME/.claude/transcripts"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

# ─── Usage ───────────────────────────────────────────────────────────────────
usage() {
    cat <<'EOF'
Usage: claude-context-loader.sh [OPTIONS] [PROJECT_PATH]

Load saved Claude Code transcripts for a project.

Arguments:
  PROJECT_PATH    Path to project directory (default: current directory)

Options:
  --no-clear      Don't clear existing global transcripts first (merge)
  --force, -y     Skip confirmation prompts
  --quiet         Suppress informational output
  --help          Show this help message

Examples:
  claude-context-loader.sh                     # Load for current project
  claude-context-loader.sh /path/to/project    # Load for specific project
  claude-context-loader.sh --no-clear          # Merge with existing
EOF
    exit 0
}

# ─── Parse Arguments ─────────────────────────────────────────────────────────
NO_CLEAR=false
FORCE=false
QUIET=false
PROJECT_PATH=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-clear) NO_CLEAR=true; shift ;;
        --force|-y) FORCE=true; shift ;;
        --quiet)    QUIET=true; shift ;;
        --help)     usage ;;
        -*)         error "Unknown option: $1"; exit 1 ;;
        *)          PROJECT_PATH="$1"; shift ;;
    esac
done

# ─── Quiet-aware output ─────────────────────────────────────────────────────
_info()    { [ "$QUIET" = true ] || info "$@"; }
_step()    { [ "$QUIET" = true ] || step "$@"; }

# ─── Resolve Project Root ────────────────────────────────────────────────────
if [ -n "$PROJECT_PATH" ]; then
    if [ ! -d "$PROJECT_PATH" ]; then
        error "Directory does not exist: $PROJECT_PATH"
        exit 1
    fi
    PROJECT_ROOT="$(cd "$PROJECT_PATH" && pwd)"
else
    PROJECT_ROOT="$(pwd)"
fi

# Try git root
if git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree &>/dev/null; then
    PROJECT_ROOT="$(git -C "$PROJECT_ROOT" rev-parse --show-toplevel)"
fi

PROJECT_NAME="$(basename "$PROJECT_ROOT")"
SOURCE_DIR="$PROJECT_ROOT/claude_transcripts"

# ─── Check Saved Transcripts ────────────────────────────────────────────────
if [ ! -d "$SOURCE_DIR" ]; then
    error "No claude_transcripts/ directory found in $PROJECT_ROOT"
    error "Run 'claude-init' to set up this project, or 'claude-save' to save transcripts first."
    exit 1
fi

SOURCE_COUNT=$(find "$SOURCE_DIR" -name "*.json" -type f 2>/dev/null | wc -l)

if [ "$SOURCE_COUNT" -eq 0 ]; then
    warn "No transcript files found in $SOURCE_DIR"
    warn "Run 'claude-save' to save transcripts first."
    exit 0
fi

_info "Loading context for: $PROJECT_NAME"
_info "Found $SOURCE_COUNT saved transcript file(s)"
echo ""

# ─── Ensure Global Transcripts Directory Exists ─────────────────────────────
mkdir -p "$CLAUDE_TRANSCRIPTS_DIR"

# ─── Back Up and Clear Existing Global Transcripts ───────────────────────────
EXISTING_COUNT=$(find "$CLAUDE_TRANSCRIPTS_DIR" -name "*.json" -type f 2>/dev/null | wc -l)

if [ "$NO_CLEAR" = false ] && [ "$EXISTING_COUNT" -gt 0 ]; then
    _step "Found $EXISTING_COUNT existing transcript(s) in global directory"

    # Backup
    BACKUP_DIR="$HOME/.claude/transcripts_backup_$TIMESTAMP"
    _step "Backing up to: $BACKUP_DIR"
    cp -r "$CLAUDE_TRANSCRIPTS_DIR" "$BACKUP_DIR"

    # Clear
    _step "Clearing global transcripts..."
    find "$CLAUDE_TRANSCRIPTS_DIR" -name "*.json" -type f -delete 2>/dev/null || true
elif [ "$NO_CLEAR" = true ] && [ "$EXISTING_COUNT" -gt 0 ]; then
    _step "Keeping $EXISTING_COUNT existing transcript(s) (--no-clear mode)"
fi

# ─── Copy Saved Transcripts to Global ───────────────────────────────────────
_step "Restoring transcripts to $CLAUDE_TRANSCRIPTS_DIR..."
LOADED=0
while IFS= read -r -d '' file; do
    REL_PATH="${file#"$SOURCE_DIR"/}"
    DEST_FILE="$CLAUDE_TRANSCRIPTS_DIR/$REL_PATH"
    mkdir -p "$(dirname "$DEST_FILE")"
    cp "$file" "$DEST_FILE"
    LOADED=$((LOADED + 1))
done < <(find "$SOURCE_DIR" -name "*.json" -type f -print0 2>/dev/null)

_step "Restored $LOADED transcript file(s)"

# ─── Generate CONTEXT_SUMMARY.md ────────────────────────────────────────────
_step "Generating CONTEXT_SUMMARY.md"

# Try to detect last save date from README.md
LAST_SAVE="unknown"
if [ -f "$SOURCE_DIR/README.md" ]; then
    SAVED_LINE=$(grep -oP '(?<=\*\*Last saved:\*\* ).*' "$SOURCE_DIR/README.md" 2>/dev/null || true)
    if [ -n "$SAVED_LINE" ]; then
        LAST_SAVE="$SAVED_LINE"
    fi
fi

cat > "$SOURCE_DIR/CONTEXT_SUMMARY.md" << SUMMARY_EOF
# Context Summary: $PROJECT_NAME

**Repository:** $PROJECT_NAME
**Path:** $PROJECT_ROOT
**Last context save:** $LAST_SAVE
**Context loaded:** $(date '+%Y-%m-%d %H:%M:%S')
**Transcripts loaded:** $LOADED

---

## Quick Project Overview

<!-- Add a brief overview of what this project is about -->

## Key Information Claude Should Know

<!-- What context does Claude need to be effective on this project? -->

## Recent Work Summary

<!-- What was done in the last session? -->

## Next Steps

<!-- What should be worked on next? -->

## Important Files

<!-- List key files Claude should be aware of -->

## Known Issues

<!-- Any current bugs or problems? -->
SUMMARY_EOF

# ─── Display Summary ────────────────────────────────────────────────────────
echo ""
success "Context loaded for $PROJECT_NAME!"
echo ""
echo "  Project:     $PROJECT_NAME"
echo "  Path:        $PROJECT_ROOT"
echo "  Transcripts: $LOADED loaded"
echo "  Last saved:  $LAST_SAVE"
echo ""
echo "  You can now start Claude Code:"
echo "    claude"
echo ""
