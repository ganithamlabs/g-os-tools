#!/usr/bin/env bash
set -e

# ─── Output Helpers ──────────────────────────────────────────────────────────
info()    { echo -e "\033[0;34m[INFO]\033[0m $*"; }
success() { echo -e "\033[0;32m[OK]\033[0m $*"; }
warn()    { echo -e "\033[1;33m[WARN]\033[0m $*"; }
error()   { echo -e "\033[0;31m[ERROR]\033[0m $*" >&2; }
step()    { echo -e "\033[0;34m→\033[0m $*"; }

# ─── Usage ───────────────────────────────────────────────────────────────────
usage() {
    cat <<'EOF'
Usage: claude-project-init.sh [OPTIONS] [PROJECT_PATH]

Initialize a project for Claude Code context management.

Arguments:
  PROJECT_PATH    Path to project directory (default: current directory)

Options:
  --gitignore     Add claude_transcripts/ to .gitignore
  --help          Show this help message

Files created:
  .claude/instructions.md          Project-specific instructions for Claude
  .claude/PROJECT_CONTEXT.md       Context management guide
  claude_transcripts/README.md     Transcript directory info
  claude-resume.sh                 Quick-start script
EOF
    exit 0
}

# ─── Parse Arguments ─────────────────────────────────────────────────────────
ADD_GITIGNORE=false
PROJECT_PATH=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --gitignore) ADD_GITIGNORE=true; shift ;;
        --help)      usage ;;
        -*)          error "Unknown option: $1"; exit 1 ;;
        *)           PROJECT_PATH="$1"; shift ;;
    esac
done

# ─── Resolve Project Root ────────────────────────────────────────────────────
if [ -n "$PROJECT_PATH" ]; then
    PROJECT_ROOT="$(cd "$PROJECT_PATH" 2>/dev/null && pwd)" || {
        error "Directory does not exist: $PROJECT_PATH"
        exit 1
    }
else
    PROJECT_ROOT="$(pwd)"
fi

# Try to use git root if inside a repo
if git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree &>/dev/null; then
    GIT_ROOT="$(git -C "$PROJECT_ROOT" rev-parse --show-toplevel)"
    PROJECT_ROOT="$GIT_ROOT"
    IS_GIT=true
else
    IS_GIT=false
fi

PROJECT_NAME="$(basename "$PROJECT_ROOT")"

info "Initializing Claude context management for: $PROJECT_NAME"
info "Project root: $PROJECT_ROOT"
echo ""

# ─── Create .claude/ Directory ───────────────────────────────────────────────
CLAUDE_DIR="$PROJECT_ROOT/.claude"
if [ -d "$CLAUDE_DIR" ]; then
    step ".claude/ directory already exists — skipping creation"
else
    step "Creating .claude/ directory"
    mkdir -p "$CLAUDE_DIR"
fi

# ─── Create .claude/instructions.md ─────────────────────────────────────────
INSTRUCTIONS_FILE="$CLAUDE_DIR/instructions.md"
if [ -f "$INSTRUCTIONS_FILE" ]; then
    warn ".claude/instructions.md already exists — not overwriting"
else
    step "Creating .claude/instructions.md template"
    cat > "$INSTRUCTIONS_FILE" << 'INSTRUCTIONS_EOF'
# Project Instructions for Claude

<!-- Edit this file to give Claude project-specific context and instructions. -->
<!-- Claude Code reads this file automatically when working in this project. -->

## Project Overview

- **Name:** <!-- project name -->
- **Description:** <!-- brief description -->
- **Type:** <!-- web app, CLI tool, library, API, etc. -->
- **Status:** <!-- active development, maintenance, etc. -->

## Tech Stack

- **Language(s):** <!-- e.g., Python 3.11, TypeScript 5.x -->
- **Framework(s):** <!-- e.g., FastAPI, React, Express -->
- **Key Dependencies:** <!-- list important packages -->

## Project Structure

```
<!-- Describe or paste your directory layout here -->
```

## Development Workflow

- **Setup:** <!-- how to set up the dev environment -->
- **Run:** <!-- how to run the project -->
- **Test:** <!-- how to run tests -->
- **Build:** <!-- how to build for production -->

## Coding Conventions

- **Style Guide:** <!-- e.g., PEP 8, Airbnb JS -->
- **Naming:** <!-- conventions for variables, functions, files -->
- **Patterns:** <!-- preferred patterns, e.g., functional vs OOP -->

## Architecture Decisions

<!-- Key design decisions and their rationale -->

## Current Focus

- **Active Tasks:**
  - <!-- current work item -->
- **Recently Completed:**
  - <!-- recent completion -->
- **Next Steps:**
  - <!-- upcoming work -->

## Important Context for Claude

- **Things to Know:**
  - <!-- important project-specific knowledge -->
- **Things to Avoid:**
  - <!-- patterns, approaches, or files to avoid -->
- **Things to Prefer:**
  - <!-- preferred approaches or patterns -->

## Common Tasks & Commands

```bash
# Add your frequently used commands here
```

## Known Issues & Gotchas

- <!-- list known issues or tricky areas -->

## Testing Guidelines

- <!-- test framework, coverage expectations, how to write tests -->

## Deployment

- <!-- deployment process, environments, CI/CD -->

## Team Conventions

- **Commits:** <!-- commit message format -->
- **Branches:** <!-- branching strategy -->
- **PRs:** <!-- PR process -->
INSTRUCTIONS_EOF
fi

# ─── Create .claude/PROJECT_CONTEXT.md ───────────────────────────────────────
step "Creating .claude/PROJECT_CONTEXT.md"
cat > "$CLAUDE_DIR/PROJECT_CONTEXT.md" << CONTEXT_EOF
# Claude Code Context Management

This project uses the Claude Code Context Management System to save and
restore conversation history between sessions.

## How It Works

- **Save context:** Run \`claude-save\` (or \`claude-context-manager.sh\`)
  to copy your Claude Code transcripts into this project's
  \`claude_transcripts/\` directory.

- **Load context:** Run \`claude-load\` (or \`claude-context-loader.sh\`)
  to restore saved transcripts back into Claude Code's active directory.

- **Quick resume:** Run \`./claude-resume.sh\` from the project root to
  load context and get ready to work.

## Directory Layout

\`\`\`
.claude/
├── instructions.md       ← Edit this! Claude reads it automatically.
└── PROJECT_CONTEXT.md    ← This file (context management guide).

claude_transcripts/
├── README.md             ← Info about the transcripts directory.
├── CONTEXT_SUMMARY.md    ← Auto-generated when context is loaded.
└── *.json                ← Saved transcript files.

claude-resume.sh          ← Quick-start script.
\`\`\`

## Tips

1. Edit \`.claude/instructions.md\` to give Claude project-specific knowledge.
2. Run \`claude-save\` before switching to another project.
3. Run \`claude-load\` (or \`./claude-resume.sh\`) when resuming work.
4. Transcripts are JSON files — you can inspect them if needed.

## More Information

See the Claude Code Context Management System documentation for the full
guide on multi-project workflows, shell integration, and advanced features.
CONTEXT_EOF

# ─── Create claude_transcripts/ Directory ────────────────────────────────────
TRANSCRIPTS_DIR="$PROJECT_ROOT/claude_transcripts"
if [ -d "$TRANSCRIPTS_DIR" ]; then
    step "claude_transcripts/ directory already exists — skipping creation"
else
    step "Creating claude_transcripts/ directory"
    mkdir -p "$TRANSCRIPTS_DIR"
fi

# ─── Create claude_transcripts/README.md ─────────────────────────────────────
step "Creating claude_transcripts/README.md"
cat > "$TRANSCRIPTS_DIR/README.md" << README_EOF
# Claude Code Transcripts

This directory contains saved Claude Code conversation transcripts for
the **$(basename "$PROJECT_ROOT")** project.

## Purpose

These transcript files allow you to restore Claude Code's conversation
context when resuming work on this project after working on a different one.

## Usage

- **Save transcripts here:** \`claude-save\`
- **Load transcripts from here:** \`claude-load\`

## File Format

Transcript files are JSON files named \`transcript_YYYYMMDD_HHMMSS.json\`.
They are copied from \`~/.claude/transcripts/\` by the context manager.

## Notes

- Do not edit transcript files manually.
- You can safely delete old transcripts to save space.
- If you don't want these committed to git, add \`claude_transcripts/\`
  to your \`.gitignore\`.
README_EOF

# ─── Create claude-resume.sh ────────────────────────────────────────────────
step "Creating claude-resume.sh"
cat > "$PROJECT_ROOT/claude-resume.sh" << 'RESUME_EOF'
#!/usr/bin/env bash
set -e

# Claude Code Context Resume Script
# Generated by claude-project-init.sh
# Loads saved transcripts for this project and prepares for a Claude session.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"

echo ""
echo "=== Claude Code Context Resume ==="
echo "Project: $(basename "$PROJECT_ROOT")"
echo ""

# ─── Find the loader script ─────────────────────────────────────────────────
LOADER=""

if command -v claude-load &>/dev/null; then
    LOADER="$(command -v claude-load)"
elif [ -x "$HOME/.local/bin/claude-load" ]; then
    LOADER="$HOME/.local/bin/claude-load"
elif [ -x "$HOME/.local/bin/claude-tools/claude-context-loader.sh" ]; then
    LOADER="$HOME/.local/bin/claude-tools/claude-context-loader.sh"
elif [ -x "$HOME/bin/claude-tools/claude-context-loader.sh" ]; then
    LOADER="$HOME/bin/claude-tools/claude-context-loader.sh"
elif [ -x "$HOME/claude-context-loader.sh" ]; then
    LOADER="$HOME/claude-context-loader.sh"
elif [ -x "/usr/local/bin/claude-context-loader.sh" ]; then
    LOADER="/usr/local/bin/claude-context-loader.sh"
elif [ -x "$SCRIPT_DIR/claude-context-loader.sh" ]; then
    LOADER="$SCRIPT_DIR/claude-context-loader.sh"
fi

if [ -z "$LOADER" ]; then
    echo -e "\033[0;31m[ERROR]\033[0m claude-context-loader.sh not found!"
    echo ""
    echo "Please install the Claude Code Context Management tools."
    echo "See: https://github.com/your-repo/claude-context-tools"
    exit 1
fi

echo "Using loader: $LOADER"
echo ""

# ─── Load context ───────────────────────────────────────────────────────────
"$LOADER" "$PROJECT_ROOT"

echo ""
echo "Ready! You can now start Claude Code:"
echo "  claude"
echo ""
RESUME_EOF
chmod +x "$PROJECT_ROOT/claude-resume.sh"

# ─── Optionally add to .gitignore ───────────────────────────────────────────
if [ "$ADD_GITIGNORE" = true ]; then
    GITIGNORE="$PROJECT_ROOT/.gitignore"
    if [ -f "$GITIGNORE" ] && grep -qF "claude_transcripts/" "$GITIGNORE"; then
        step "claude_transcripts/ already in .gitignore"
    else
        step "Adding claude_transcripts/ to .gitignore"
        echo "" >> "$GITIGNORE"
        echo "# Claude Code transcripts" >> "$GITIGNORE"
        echo "claude_transcripts/" >> "$GITIGNORE"
    fi
fi

# ─── Summary ────────────────────────────────────────────────────────────────
echo ""
success "Project initialized for Claude Code context management!"
echo ""
echo "  Files created:"
echo "    .claude/instructions.md        ← Edit this with project details"
echo "    .claude/PROJECT_CONTEXT.md     ← Context management guide"
echo "    claude_transcripts/README.md   ← Transcript directory info"
echo "    claude-resume.sh               ← Quick-start script"
echo ""
echo "  Next steps:"
echo "    1. Edit .claude/instructions.md with your project details"
echo "    2. Run 'claude-save' to save transcripts after a session"
echo "    3. Run './claude-resume.sh' to load context and start working"
echo ""
