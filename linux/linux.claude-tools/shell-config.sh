#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Claude Code Context Management - Shell Integration
#
# Source this file from your ~/.bashrc or ~/.zshrc:
#   source ~/.local/bin/claude-tools/shell-config.sh
#
# This provides aliases, functions, and optional auto-detection when
# changing directories into a project with saved Claude context.
# ─────────────────────────────────────────────────────────────────────────────

# ─── Determine install directory ─────────────────────────────────────────────
# shellcheck disable=SC2148
_CLAUDE_TOOLS_DIR="${CLAUDE_TOOLS_DIR:-}"

if [ -z "$_CLAUDE_TOOLS_DIR" ]; then
    # Try to detect from the path of this script
    if [ -n "${BASH_SOURCE[0]:-}" ]; then
        _CLAUDE_TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    elif [ -n "${(%):-%x}" ] 2>/dev/null; then
        # zsh
        _CLAUDE_TOOLS_DIR="$(cd "$(dirname "${(%):-%x}")" && pwd)"
    else
        _CLAUDE_TOOLS_DIR="$HOME/.local/bin/claude-tools"
    fi
fi

# ─── Aliases ─────────────────────────────────────────────────────────────────
if command -v claude-context-manager.sh &>/dev/null; then
    alias claude-save='claude-context-manager.sh'
elif [ -x "$_CLAUDE_TOOLS_DIR/claude-context-manager.sh" ]; then
    alias claude-save="$_CLAUDE_TOOLS_DIR/claude-context-manager.sh"
fi

if command -v claude-context-loader.sh &>/dev/null; then
    alias claude-load='claude-context-loader.sh'
elif [ -x "$_CLAUDE_TOOLS_DIR/claude-context-loader.sh" ]; then
    alias claude-load="$_CLAUDE_TOOLS_DIR/claude-context-loader.sh"
fi

if command -v claude-project-init.sh &>/dev/null; then
    alias claude-init='claude-project-init.sh'
elif [ -x "$_CLAUDE_TOOLS_DIR/claude-project-init.sh" ]; then
    alias claude-init="$_CLAUDE_TOOLS_DIR/claude-project-init.sh"
fi

if command -v claude-context-switcher.sh &>/dev/null; then
    alias claude-switch='claude-context-switcher.sh'
elif [ -x "$_CLAUDE_TOOLS_DIR/claude-context-switcher.sh" ]; then
    alias claude-switch="$_CLAUDE_TOOLS_DIR/claude-context-switcher.sh"
fi

# ─── Functions ───────────────────────────────────────────────────────────────

# Switch to a project directory and load its Claude context
work() {
    local project_path="$1"

    if [ -z "$project_path" ]; then
        echo "Usage: work <project-path>"
        echo "  Switch to a project and load its Claude context."
        return 1
    fi

    # Resolve path: if it's just a name, check common locations
    if [ ! -d "$project_path" ]; then
        local projects_dir="${CLAUDE_PROJECTS_DIR:-$HOME/projects}"
        if [ -d "$projects_dir/$project_path" ]; then
            project_path="$projects_dir/$project_path"
        else
            echo "Error: Directory not found: $project_path"
            echo "  Also checked: $projects_dir/$project_path"
            return 1
        fi
    fi

    cd "$project_path" || return 1

    # Load context if transcripts exist
    if [ -d "claude_transcripts" ]; then
        local count
        count=$(find claude_transcripts -name "*.json" -type f 2>/dev/null | wc -l)
        if [ "$count" -gt 0 ]; then
            echo "Found $count saved transcript(s). Loading context..."
            if type claude-load &>/dev/null; then
                claude-load
            elif [ -x "$_CLAUDE_TOOLS_DIR/claude-context-loader.sh" ]; then
                "$_CLAUDE_TOOLS_DIR/claude-context-loader.sh"
            else
                echo "Warning: claude-context-loader.sh not found. Context not loaded."
            fi
        fi
    fi
}

# Show current Claude context status
claude-status() {
    local global_dir="$HOME/.claude/transcripts"
    local global_count=0
    local project_count=0
    local project_name="(none)"
    local last_save="unknown"

    # Count global transcripts
    if [ -d "$global_dir" ]; then
        global_count=$(find "$global_dir" -name "*.json" -type f 2>/dev/null | wc -l)
    fi

    # Detect current project
    local project_root
    if git rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
        project_root="$(git rev-parse --show-toplevel)"
    else
        project_root="$(pwd)"
    fi

    if [ -d "$project_root/claude_transcripts" ]; then
        project_name="$(basename "$project_root")"
        project_count=$(find "$project_root/claude_transcripts" -name "*.json" -type f 2>/dev/null | wc -l)

        if [ -f "$project_root/claude_transcripts/README.md" ]; then
            last_save=$(grep -oP '(?<=\*\*Last saved:\*\* ).*' "$project_root/claude_transcripts/README.md" 2>/dev/null || echo "unknown")
        fi
    fi

    echo ""
    echo "=== Claude Code Context Status ==="
    echo ""
    echo "  Active transcripts: $global_count"
    echo "  Current project:    $project_name"
    echo "  Saved transcripts:  $project_count"
    echo "  Last saved:         $last_save"
    echo "  Project root:       $project_root"
    echo ""
}

# List all projects that have saved Claude context
claude-projects() {
    local config_file="$HOME/.claude-projects.conf"

    echo ""
    echo "=== Projects with Claude Context ==="
    echo ""

    local found=0

    # First show configured projects
    if [ -f "$config_file" ]; then
        echo "  Configured projects (~/.claude-projects.conf):"
        while IFS= read -r line; do
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            [[ -z "$line" ]] && continue
            if [ -d "$line" ]; then
                local name
                name="$(basename "$line")"
                local count=0
                if [ -d "$line/claude_transcripts" ]; then
                    count=$(find "$line/claude_transcripts" -name "*.json" -type f 2>/dev/null | wc -l)
                fi
                echo -e "    \033[0;32m✓\033[0m $name ($count transcripts) - $line"
                found=$((found + 1))
            else
                echo -e "    \033[0;31m✗\033[0m $line [missing]"
            fi
        done < "$config_file"
        echo ""
    fi

    # Also scan common project directories
    local projects_dir="${CLAUDE_PROJECTS_DIR:-$HOME/projects}"
    if [ -d "$projects_dir" ]; then
        echo "  Projects in $projects_dir:"
        local dir_found=0
        for dir in "$projects_dir"/*/; do
            [ -d "$dir" ] || continue
            if [ -d "${dir}claude_transcripts" ]; then
                local name
                name="$(basename "$dir")"
                local count
                count=$(find "${dir}claude_transcripts" -name "*.json" -type f 2>/dev/null | wc -l)
                echo -e "    \033[0;32m✓\033[0m $name ($count transcripts)"
                dir_found=$((dir_found + 1))
                found=$((found + 1))
            fi
        done
        if [ "$dir_found" -eq 0 ]; then
            echo "    (none found)"
        fi
        echo ""
    fi

    if [ "$found" -eq 0 ]; then
        echo "  No projects with saved context found."
        echo "  Use 'claude-init' in a project to set it up."
        echo ""
    fi
}

# ─── Optional: Auto-detect on directory change ──────────────────────────────
# Set CLAUDE_AUTO_DETECT=true in your shell rc to enable this.
# When you cd into a project with saved transcripts, it will notify you.

if [ "${CLAUDE_AUTO_DETECT:-false}" = true ]; then
    _claude_check_project() {
        if [ -d "claude_transcripts" ]; then
            local count
            count=$(find claude_transcripts -name "*.json" -type f 2>/dev/null | wc -l)
            if [ "$count" -gt 0 ]; then
                echo -e "\033[0;34m[Claude]\033[0m This project has $count saved transcript(s). Run 'claude-load' to restore."
            fi
        fi
    }

    # Bash: use PROMPT_COMMAND
    if [ -n "${BASH_VERSION:-}" ]; then
        _claude_prev_dir=""
        _claude_prompt_hook() {
            if [ "$PWD" != "$_claude_prev_dir" ]; then
                _claude_prev_dir="$PWD"
                _claude_check_project
            fi
        }
        if [[ "$PROMPT_COMMAND" != *"_claude_prompt_hook"* ]]; then
            PROMPT_COMMAND="_claude_prompt_hook;${PROMPT_COMMAND:-}"
        fi
    fi

    # Zsh: use chpwd hook
    if [ -n "${ZSH_VERSION:-}" ]; then
        _claude_chpwd_hook() {
            _claude_check_project
        }
        if [[ ! " ${chpwd_functions[*]} " =~ " _claude_chpwd_hook " ]]; then
            chpwd_functions+=(_claude_chpwd_hook)
        fi
    fi
fi
