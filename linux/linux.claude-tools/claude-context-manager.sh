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
Usage: claude-context-manager.sh [OPTIONS] [PROJECT_PATH...]

Save Claude Code transcripts into project directories.

Arguments:
  PROJECT_PATH    One or more project paths (default: current directory)

Options:
  --reset         Clear global transcripts after saving
  --no-git        Skip git add/commit
  --force, -y     Skip confirmation prompts
  --quiet         Suppress informational output
  --help          Show this help message

Examples:
  claude-context-manager.sh                     # Save for current project
  claude-context-manager.sh /path/to/project    # Save for specific project
  claude-context-manager.sh --reset             # Save and clear global
EOF
    exit 0
}

# ─── Parse Arguments ─────────────────────────────────────────────────────────
DO_RESET=false
NO_GIT=false
FORCE=false
QUIET=false
PROJECT_PATHS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --reset)   DO_RESET=true; shift ;;
        --no-git)  NO_GIT=true; shift ;;
        --force|-y) FORCE=true; shift ;;
        --quiet)   QUIET=true; shift ;;
        --help)    usage ;;
        -*)        error "Unknown option: $1"; exit 1 ;;
        *)         PROJECT_PATHS+=("$1"); shift ;;
    esac
done

# Default to current directory if no paths given
if [ ${#PROJECT_PATHS[@]} -eq 0 ]; then
    PROJECT_PATHS=("$(pwd)")
fi

# ─── Quiet-aware output ─────────────────────────────────────────────────────
_info()    { [ "$QUIET" = true ] || info "$@"; }
_step()    { [ "$QUIET" = true ] || step "$@"; }

# ─── Check Global Transcripts ───────────────────────────────────────────────
if [ ! -d "$CLAUDE_TRANSCRIPTS_DIR" ]; then
    warn "Claude transcripts directory does not exist: $CLAUDE_TRANSCRIPTS_DIR"
    warn "No transcripts to save."
    exit 0
fi

# Count transcript files (json files and subdirectories with json files)
TRANSCRIPT_COUNT=0
if [ -d "$CLAUDE_TRANSCRIPTS_DIR" ]; then
    TRANSCRIPT_COUNT=$(find "$CLAUDE_TRANSCRIPTS_DIR" -name "*.json" -type f 2>/dev/null | wc -l)
fi

if [ "$TRANSCRIPT_COUNT" -eq 0 ]; then
    warn "No transcript files found in $CLAUDE_TRANSCRIPTS_DIR"
    warn "Nothing to save."
    exit 0
fi

_info "Found $TRANSCRIPT_COUNT transcript file(s) to save"
echo ""

# ─── Process Each Project ───────────────────────────────────────────────────
SAVED_COUNT=0

for PROJECT_PATH in "${PROJECT_PATHS[@]}"; do
    # Resolve to absolute path
    if [ ! -d "$PROJECT_PATH" ]; then
        error "Directory does not exist: $PROJECT_PATH"
        continue
    fi
    PROJECT_ROOT="$(cd "$PROJECT_PATH" && pwd)"

    # Try git root
    IS_GIT=false
    if git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree &>/dev/null; then
        PROJECT_ROOT="$(git -C "$PROJECT_ROOT" rev-parse --show-toplevel)"
        IS_GIT=true
    fi

    PROJECT_NAME="$(basename "$PROJECT_ROOT")"
    _info "Saving transcripts for: $PROJECT_NAME ($PROJECT_ROOT)"

    # Create transcripts directory
    DEST_DIR="$PROJECT_ROOT/claude_transcripts"
    if [ ! -d "$DEST_DIR" ]; then
        _step "Creating claude_transcripts/ directory"
        mkdir -p "$DEST_DIR"
    fi

    # Copy transcript files (preserve directory structure)
    _step "Copying transcript files..."
    COPIED=0
    while IFS= read -r -d '' file; do
        REL_PATH="${file#"$CLAUDE_TRANSCRIPTS_DIR"/}"
        DEST_FILE="$DEST_DIR/$REL_PATH"
        mkdir -p "$(dirname "$DEST_FILE")"
        cp "$file" "$DEST_FILE"
        COPIED=$((COPIED + 1))
    done < <(find "$CLAUDE_TRANSCRIPTS_DIR" -name "*.json" -type f -print0 2>/dev/null)

    _step "Copied $COPIED transcript file(s)"

    # Generate/update README.md with metadata
    _step "Updating claude_transcripts/README.md"
    cat > "$DEST_DIR/README.md" << README_EOF
# Claude Code Transcripts

**Project:** $PROJECT_NAME
**Path:** $PROJECT_ROOT
**Last saved:** $(date '+%Y-%m-%d %H:%M:%S')
**Transcript count:** $COPIED

## Purpose

These transcript files allow you to restore Claude Code's conversation
context when resuming work on this project.

## Usage

- **Save transcripts here:** \`claude-save\`
- **Load transcripts from here:** \`claude-load\`

## Notes

- Do not edit transcript files manually.
- You can safely delete old transcripts to save space.
README_EOF

    # Git operations
    if [ "$IS_GIT" = true ] && [ "$NO_GIT" = false ]; then
        _step "Adding transcripts to git..."
        if git -C "$PROJECT_ROOT" add claude_transcripts/; then
            # Check if there are staged changes
            if git -C "$PROJECT_ROOT" diff --cached --quiet -- claude_transcripts/ 2>/dev/null; then
                _step "No new changes to commit"
            else
                git -C "$PROJECT_ROOT" commit -m "chore: save Claude Code transcripts before context switch" -- claude_transcripts/ || {
                    warn "Git commit failed — transcripts are saved but not committed"
                }
            fi
        else
            warn "Git add failed — transcripts are saved but not staged"
        fi
    elif [ "$IS_GIT" = false ]; then
        _step "Not a git repository — skipping git operations"
    fi

    SAVED_COUNT=$((SAVED_COUNT + 1))
    success "Saved $COPIED transcript(s) for $PROJECT_NAME"
    echo ""
done

# ─── Reset Global Transcripts ───────────────────────────────────────────────
if [ "$DO_RESET" = true ]; then
    if [ "$FORCE" = false ]; then
        echo -n "Clear global transcripts in $CLAUDE_TRANSCRIPTS_DIR? [y/N] "
        read -r CONFIRM
        if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
            info "Skipping reset."
            echo ""
            success "Done! Saved transcripts for $SAVED_COUNT project(s)."
            exit 0
        fi
    fi

    # Backup before clearing
    BACKUP_DIR="$HOME/.claude/transcripts_backup_$TIMESTAMP"
    _step "Backing up transcripts to: $BACKUP_DIR"
    cp -r "$CLAUDE_TRANSCRIPTS_DIR" "$BACKUP_DIR"

    _step "Clearing global transcripts..."
    find "$CLAUDE_TRANSCRIPTS_DIR" -name "*.json" -type f -delete 2>/dev/null || true

    success "Global transcripts cleared (backup at $BACKUP_DIR)"
fi

# ─── Summary ────────────────────────────────────────────────────────────────
echo ""
success "Done! Saved transcripts for $SAVED_COUNT project(s)."
