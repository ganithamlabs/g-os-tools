#!/usr/bin/env bash
set -e

# ─── Output Helpers ──────────────────────────────────────────────────────────
info()    { echo -e "\033[0;34m[INFO]\033[0m $*"; }
success() { echo -e "\033[0;32m[OK]\033[0m $*"; }
warn()    { echo -e "\033[1;33m[WARN]\033[0m $*"; }
error()   { echo -e "\033[0;31m[ERROR]\033[0m $*" >&2; }
step()    { echo -e "\033[0;34m→\033[0m $*"; }

SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"

# ─── Usage ───────────────────────────────────────────────────────────────────
usage() {
    cat <<'EOF'
Usage: setup.sh [OPTIONS]

Install Claude Code Context Management tools.

Options:
  --install-dir <path>   Installation directory (default: ~/.local/bin/claude-tools)
  --no-shell-config      Don't add shell integration to rc file
  --uninstall            Remove installed files and shell configuration
  --help                 Show this help message

Installation locations:
  Scripts:   <install-dir>/
  Symlinks:  ~/.local/bin/claude-save, claude-load, claude-init, claude-switch
  Shell:     source line added to ~/.bashrc or ~/.zshrc
EOF
    exit 0
}

# ─── Parse Arguments ─────────────────────────────────────────────────────────
INSTALL_DIR="$HOME/.local/bin/claude-tools"
NO_SHELL_CONFIG=false
UNINSTALL=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --install-dir)     INSTALL_DIR="$2"; shift 2 ;;
        --no-shell-config) NO_SHELL_CONFIG=true; shift ;;
        --uninstall)       UNINSTALL=true; shift ;;
        --help)            usage ;;
        -*)                error "Unknown option: $1"; exit 1 ;;
        *)                 error "Unexpected argument: $1"; exit 1 ;;
    esac
done

# ─── Detect Shell ────────────────────────────────────────────────────────────
detect_shell_rc() {
    if [ -n "${ZSH_VERSION:-}" ] || [ "$(basename "$SHELL")" = "zsh" ]; then
        echo "$HOME/.zshrc"
    else
        echo "$HOME/.bashrc"
    fi
}

SHELL_RC="$(detect_shell_rc)"

# ─── Uninstall ───────────────────────────────────────────────────────────────
if [ "$UNINSTALL" = true ]; then
    echo ""
    echo "=== Uninstalling Claude Code Context Tools ==="
    echo ""

    # Remove symlinks
    for link in claude-save claude-load claude-init claude-switch; do
        if [ -L "$HOME/.local/bin/$link" ]; then
            step "Removing symlink: ~/.local/bin/$link"
            rm "$HOME/.local/bin/$link"
        fi
    done

    # Remove install directory
    if [ -d "$INSTALL_DIR" ]; then
        step "Removing install directory: $INSTALL_DIR"
        rm -rf "$INSTALL_DIR"
    fi

    # Remove shell config line
    if [ -f "$SHELL_RC" ]; then
        if grep -qF "claude-tools/shell-config.sh" "$SHELL_RC"; then
            step "Removing shell integration from $SHELL_RC"
            local tmp_file
            tmp_file="$(mktemp)"
            grep -vF "claude-tools/shell-config.sh" "$SHELL_RC" > "$tmp_file"
            mv "$tmp_file" "$SHELL_RC"
        fi
    fi

    echo ""
    success "Uninstall complete."
    echo "  Note: Per-project files (.claude/, claude_transcripts/, claude-resume.sh)"
    echo "  were not removed. Delete them manually if desired."
    echo ""
    exit 0
fi

# ─── Install ─────────────────────────────────────────────────────────────────
echo ""
echo "=== Claude Code Context Tools - Installer ==="
echo ""
echo "  Source:      $SOURCE_DIR"
echo "  Install to:  $INSTALL_DIR"
echo "  Shell rc:    $SHELL_RC"
echo ""

# Step 1: Verify files
step "Verifying source files..."
if [ -x "$SOURCE_DIR/verify-files.sh" ]; then
    "$SOURCE_DIR/verify-files.sh" "$SOURCE_DIR" || exit 1
else
    # Inline check if verify script not executable
    for f in claude-context-manager.sh claude-context-loader.sh claude-context-switcher.sh claude-project-init.sh shell-config.sh; do
        if [ ! -f "$SOURCE_DIR/$f" ]; then
            error "Missing required file: $f"
            exit 1
        fi
    done
    success "All required files present."
fi
echo ""

# Step 2: Create install directory
step "Creating install directory: $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"

# Step 3: Copy scripts
SCRIPTS=(
    "claude-context-manager.sh"
    "claude-context-loader.sh"
    "claude-context-switcher.sh"
    "claude-project-init.sh"
    "shell-config.sh"
)

step "Copying scripts..."
for script in "${SCRIPTS[@]}"; do
    cp "$SOURCE_DIR/$script" "$INSTALL_DIR/$script"
    chmod +x "$INSTALL_DIR/$script"
    echo "    $script"
done

# Copy documentation files if present
DOC_FILES=(
    "README.md"
    "REQUIREMENTS.md"
    "HighLevelDesign.md"
    "COMPLETE_GUIDE.md"
    "DEPLOYMENT_GUIDE.md"
    "QUICK_INSTALL.md"
    "FILE_MANIFEST.md"
)

DOC_COPIED=0
for doc in "${DOC_FILES[@]}"; do
    if [ -f "$SOURCE_DIR/$doc" ]; then
        cp "$SOURCE_DIR/$doc" "$INSTALL_DIR/$doc"
        DOC_COPIED=$((DOC_COPIED + 1))
    fi
done
if [ "$DOC_COPIED" -gt 0 ]; then
    step "Copied $DOC_COPIED documentation file(s)"
fi

# Step 4: Create symlinks
step "Creating command symlinks in ~/.local/bin/"
mkdir -p "$HOME/.local/bin"

declare -A SYMLINKS=(
    ["claude-save"]="claude-context-manager.sh"
    ["claude-load"]="claude-context-loader.sh"
    ["claude-init"]="claude-project-init.sh"
    ["claude-switch"]="claude-context-switcher.sh"
)

for link_name in "${!SYMLINKS[@]}"; do
    target="$INSTALL_DIR/${SYMLINKS[$link_name]}"
    link_path="$HOME/.local/bin/$link_name"
    # Remove existing symlink if it points somewhere else
    if [ -L "$link_path" ]; then
        rm "$link_path"
    fi
    ln -s "$target" "$link_path"
    echo "    $link_name -> ${SYMLINKS[$link_name]}"
done

# Step 5: Ensure ~/.local/bin is in PATH
if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    step "Adding ~/.local/bin to PATH in $SHELL_RC"
    if [ -f "$SHELL_RC" ] && grep -qF '$HOME/.local/bin' "$SHELL_RC"; then
        info "PATH entry already in $SHELL_RC (may need shell restart)"
    else
        echo '' >> "$SHELL_RC"
        echo '# Claude Code Context Tools - PATH' >> "$SHELL_RC"
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$SHELL_RC"
    fi
else
    step "~/.local/bin already in PATH"
fi

# Step 6: Shell integration
if [ "$NO_SHELL_CONFIG" = false ]; then
    SOURCE_LINE="source \"$INSTALL_DIR/shell-config.sh\""
    if [ -f "$SHELL_RC" ] && grep -qF "claude-tools/shell-config.sh" "$SHELL_RC"; then
        step "Shell integration already configured in $SHELL_RC"
    else
        step "Adding shell integration to $SHELL_RC"
        echo '' >> "$SHELL_RC"
        echo '# Claude Code Context Tools - Shell Integration' >> "$SHELL_RC"
        echo "$SOURCE_LINE" >> "$SHELL_RC"
    fi
else
    step "Skipping shell integration (--no-shell-config)"
fi

# ─── Summary ────────────────────────────────────────────────────────────────
echo ""
success "Installation complete!"
echo ""
echo "  Commands available (after restarting your shell):"
echo "    claude-save     Save current project's Claude context"
echo "    claude-load     Load a project's saved Claude context"
echo "    claude-init     Initialize a project for context management"
echo "    claude-switch   Manage multiple projects"
echo ""
echo "  Shell functions:"
echo "    work <project>     Switch to project and load context"
echo "    claude-status      Show current context status"
echo "    claude-projects    List projects with saved context"
echo ""
echo "  To activate now (without restarting shell):"
echo "    source $SHELL_RC"
echo ""
