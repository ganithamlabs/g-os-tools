#!/usr/bin/env bash
set -e

# ─── Output Helpers ──────────────────────────────────────────────────────────
info()    { echo -e "\033[0;34m[INFO]\033[0m $*"; }
success() { echo -e "\033[0;32m[OK]\033[0m $*"; }
warn()    { echo -e "\033[1;33m[WARN]\033[0m $*"; }
error()   { echo -e "\033[0;31m[ERROR]\033[0m $*" >&2; }
step()    { echo -e "\033[0;34m→\033[0m $*"; }

# ─── Constants ───────────────────────────────────────────────────────────────
CONFIG_FILE="$HOME/.claude-projects.conf"
CLAUDE_TRANSCRIPTS_DIR="$HOME/.claude/transcripts"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

# ─── Script Discovery ───────────────────────────────────────────────────────
find_script() {
    local script_name="$1"
    local alias_name="$2"

    if command -v "$alias_name" &>/dev/null; then
        command -v "$alias_name"
    elif [ -x "$HOME/.local/bin/$alias_name" ]; then
        echo "$HOME/.local/bin/$alias_name"
    elif [ -x "$HOME/.local/bin/claude-tools/$script_name" ]; then
        echo "$HOME/.local/bin/claude-tools/$script_name"
    elif [ -x "$HOME/bin/claude-tools/$script_name" ]; then
        echo "$HOME/bin/claude-tools/$script_name"
    elif [ -x "$HOME/$script_name" ]; then
        echo "$HOME/$script_name"
    elif [ -x "/usr/local/bin/$script_name" ]; then
        echo "/usr/local/bin/$script_name"
    elif [ -x "$(dirname "$0")/$script_name" ]; then
        echo "$(dirname "$0")/$script_name"
    else
        return 1
    fi
}

# ─── Usage ───────────────────────────────────────────────────────────────────
usage() {
    cat <<'EOF'
Usage: claude-context-switcher.sh [COMMAND] [ARGS]

Manage Claude Code context across multiple projects.

Commands:
  --init                  Create the projects configuration file
  --add <path>            Add a project to the configuration
  --remove <path>         Remove a project from the configuration
  --list                  List all configured projects
  --all                   Save context for all configured projects and reset
  --single <path>         Save context for a single project
  --reset                 Back up and clear global transcripts
  --help                  Show this help message

Configuration:
  Projects are stored in ~/.claude-projects.conf (one path per line).

Examples:
  claude-context-switcher.sh --init
  claude-context-switcher.sh --add ~/projects/my-app
  claude-context-switcher.sh --all
  claude-context-switcher.sh --single ~/projects/my-app
EOF
    exit 0
}

# ─── Read Config ─────────────────────────────────────────────────────────────
read_projects() {
    if [ ! -f "$CONFIG_FILE" ]; then
        error "Configuration file not found: $CONFIG_FILE"
        error "Run '--init' first to create it."
        exit 1
    fi
    # Read non-empty, non-comment lines
    grep -v '^\s*#' "$CONFIG_FILE" | grep -v '^\s*$' || true
}

# ─── Commands ────────────────────────────────────────────────────────────────
cmd_init() {
    if [ -f "$CONFIG_FILE" ]; then
        warn "Configuration file already exists: $CONFIG_FILE"
        echo "  Current contents:"
        while IFS= read -r line; do
            echo "    $line"
        done < <(read_projects)
        return
    fi

    step "Creating configuration file: $CONFIG_FILE"
    cat > "$CONFIG_FILE" << 'CONF_EOF'
# Claude Code Projects Configuration
# Add one project path per line.
# Lines starting with # are comments.
#
# Example:
# /home/user/projects/my-app
# /home/user/work/api-service
CONF_EOF

    success "Configuration file created: $CONFIG_FILE"
    echo "  Add projects with: claude-context-switcher.sh --add /path/to/project"
}

cmd_add() {
    local project_path="$1"

    if [ -z "$project_path" ]; then
        error "No project path specified."
        error "Usage: claude-context-switcher.sh --add /path/to/project"
        exit 1
    fi

    # Resolve to absolute path
    if [ ! -d "$project_path" ]; then
        error "Directory does not exist: $project_path"
        exit 1
    fi
    local abs_path
    abs_path="$(cd "$project_path" && pwd)"

    # Create config if it doesn't exist
    if [ ! -f "$CONFIG_FILE" ]; then
        cmd_init
    fi

    # Check if already present
    if grep -qF "$abs_path" "$CONFIG_FILE" 2>/dev/null; then
        warn "Project already in configuration: $abs_path"
        return
    fi

    echo "$abs_path" >> "$CONFIG_FILE"
    success "Added project: $abs_path"
}

cmd_remove() {
    local project_path="$1"

    if [ -z "$project_path" ]; then
        error "No project path specified."
        exit 1
    fi

    if [ ! -f "$CONFIG_FILE" ]; then
        error "Configuration file not found: $CONFIG_FILE"
        exit 1
    fi

    # Resolve to absolute path if directory exists
    local abs_path
    if [ -d "$project_path" ]; then
        abs_path="$(cd "$project_path" && pwd)"
    else
        abs_path="$project_path"
    fi

    if ! grep -qF "$abs_path" "$CONFIG_FILE" 2>/dev/null; then
        warn "Project not found in configuration: $abs_path"
        return
    fi

    # Remove the line (create temp file to be safe)
    local tmp_file
    tmp_file="$(mktemp)"
    grep -vF "$abs_path" "$CONFIG_FILE" > "$tmp_file" || true
    mv "$tmp_file" "$CONFIG_FILE"
    success "Removed project: $abs_path"
}

cmd_list() {
    if [ ! -f "$CONFIG_FILE" ]; then
        error "Configuration file not found: $CONFIG_FILE"
        error "Run '--init' first."
        exit 1
    fi

    local projects
    projects="$(read_projects)"

    if [ -z "$projects" ]; then
        info "No projects configured."
        echo "  Add projects with: claude-context-switcher.sh --add /path/to/project"
        return
    fi

    echo ""
    echo "Configured projects:"
    echo ""
    while IFS= read -r project; do
        if [ -d "$project" ]; then
            local name
            name="$(basename "$project")"
            local has_transcripts="no"
            if [ -d "$project/claude_transcripts" ]; then
                local count
                count=$(find "$project/claude_transcripts" -name "*.json" -type f 2>/dev/null | wc -l)
                if [ "$count" -gt 0 ]; then
                    has_transcripts="$count file(s)"
                fi
            fi
            echo -e "  \033[0;32m✓\033[0m $name ($project) [transcripts: $has_transcripts]"
        else
            echo -e "  \033[0;31m✗\033[0m $project [directory missing]"
        fi
    done <<< "$projects"
    echo ""
}

cmd_all() {
    local projects
    projects="$(read_projects)"

    if [ -z "$projects" ]; then
        error "No projects configured."
        exit 1
    fi

    # Find the manager script
    local manager
    manager="$(find_script "claude-context-manager.sh" "claude-save")" || {
        error "claude-context-manager.sh not found!"
        error "Ensure the Claude context tools are installed."
        exit 1
    }

    info "Processing all configured projects..."
    echo ""

    local processed=0
    local failed=0

    while IFS= read -r project; do
        if [ ! -d "$project" ]; then
            warn "Skipping missing directory: $project"
            failed=$((failed + 1))
            continue
        fi

        info "Processing: $(basename "$project")"
        if "$manager" --no-git --quiet "$project"; then
            processed=$((processed + 1))
        else
            warn "Failed to save context for: $project"
            failed=$((failed + 1))
        fi
    done <<< "$projects"

    echo ""

    # Reset global transcripts
    if [ "$processed" -gt 0 ]; then
        step "Resetting global transcripts..."
        BACKUP_DIR="$HOME/.claude/transcripts_backup_$TIMESTAMP"
        if [ -d "$CLAUDE_TRANSCRIPTS_DIR" ]; then
            cp -r "$CLAUDE_TRANSCRIPTS_DIR" "$BACKUP_DIR"
            find "$CLAUDE_TRANSCRIPTS_DIR" -name "*.json" -type f -delete 2>/dev/null || true
            step "Backup saved to: $BACKUP_DIR"
        fi
    fi

    echo ""
    success "Done! Processed $processed project(s)."
    if [ "$failed" -gt 0 ]; then
        warn "$failed project(s) failed or skipped."
    fi
}

cmd_single() {
    local project_path="$1"

    if [ -z "$project_path" ]; then
        error "No project path specified."
        exit 1
    fi

    if [ ! -d "$project_path" ]; then
        error "Directory does not exist: $project_path"
        exit 1
    fi

    local manager
    manager="$(find_script "claude-context-manager.sh" "claude-save")" || {
        error "claude-context-manager.sh not found!"
        exit 1
    }

    "$manager" "$project_path"
}

cmd_reset() {
    if [ ! -d "$CLAUDE_TRANSCRIPTS_DIR" ]; then
        info "No global transcripts directory found. Nothing to reset."
        return
    fi

    local count
    count=$(find "$CLAUDE_TRANSCRIPTS_DIR" -name "*.json" -type f 2>/dev/null | wc -l)

    if [ "$count" -eq 0 ]; then
        info "No transcript files found. Nothing to reset."
        return
    fi

    echo -n "Back up and clear $count global transcript(s)? [y/N] "
    read -r CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        info "Cancelled."
        exit 2
    fi

    BACKUP_DIR="$HOME/.claude/transcripts_backup_$TIMESTAMP"
    step "Backing up to: $BACKUP_DIR"
    cp -r "$CLAUDE_TRANSCRIPTS_DIR" "$BACKUP_DIR"

    step "Clearing global transcripts..."
    find "$CLAUDE_TRANSCRIPTS_DIR" -name "*.json" -type f -delete 2>/dev/null || true

    success "Global transcripts cleared. Backup at: $BACKUP_DIR"
}

# ─── Main ────────────────────────────────────────────────────────────────────
if [ $# -eq 0 ]; then
    usage
fi

case "$1" in
    --init)    cmd_init ;;
    --add)     cmd_add "$2" ;;
    --remove)  cmd_remove "$2" ;;
    --list)    cmd_list ;;
    --all)     cmd_all ;;
    --single)  cmd_single "$2" ;;
    --reset)   cmd_reset ;;
    --help)    usage ;;
    *)         error "Unknown command: $1"; echo ""; usage ;;
esac
