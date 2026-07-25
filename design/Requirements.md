# Requirements: Claude Code Context Management System

## Project Overview

Create a complete context management system for Claude Code that allows users to save, load, and switch between project contexts seamlessly. This system enables developers to maintain separate conversation histories and project-specific instructions for each repository they work on.

## Problem Statement

When using Claude Code across multiple projects, conversation history and context from one project can interfere with another. Developers need a way to:

1. Save Claude Code's conversation history (transcripts) for each project
2. Load the appropriate context when switching between projects
3. Reset Claude's context when moving to a new project
4. Provide project-specific instructions that Claude reads automatically
5. Manage multiple projects efficiently

## Core Components Required

### 1. Context Manager Script (`claude-context-manager.sh`)

**Purpose:** Save the current project's context before switching to another project.

**Functionality:**
- Extract Claude Code transcripts from `~/.claude/transcripts/`
- Create a `claude_transcripts/` directory in the project root
- Copy relevant transcript files to the project directory
- Create a README.md in the transcripts directory with metadata
- Commit changes to git (if in a git repository)
- Optionally reset Claude's context by clearing `~/.claude/transcripts/`

**Usage:**
```bash
# Save context for current project
claude-context-manager.sh

# Save context for specific project
claude-context-manager.sh /path/to/project

# Save context for multiple projects
claude-context-manager.sh /path/to/project1 /path/to/project2
```

**Features:**
- Detect git repository root automatically
- Filter transcripts by project path (if possible)
- Create backup before clearing transcripts
- Show summary of transcripts saved

### 2. Context Loader Script (`claude-context-loader.sh`)

**Purpose:** Restore project context when resuming work.

**Functionality:**
- Find the project's `claude_transcripts/` directory
- Clear current transcripts in `~/.claude/transcripts/`
- Copy saved transcripts back to `~/.claude/transcripts/`
- Create/update a context summary file
- Display project information

**Usage:**
```bash
# Load context for current project
claude-context-loader.sh

# Called automatically when entering a project directory
```

**Features:**
- Detect project root (git repository or current directory)
- Show number of transcripts loaded
- Display last save date
- Create CONTEXT_SUMMARY.md with project overview

### 3. Multi-Project Switcher (`claude-context-switcher.sh`)

**Purpose:** Manage context for multiple projects at once.

**Functionality:**
- Maintain a configuration file with project paths (`~/.claude-projects.conf`)
- Process all configured projects in batch
- Save context for each project
- Reset Claude context after processing all projects

**Usage:**
```bash
# Initialize configuration
claude-context-switcher.sh --init

# Add projects to configuration
claude-context-switcher.sh --add /path/to/project

# List configured projects
claude-context-switcher.sh --list

# Process all projects
claude-context-switcher.sh --all

# Process single project
claude-context-switcher.sh --single /path/to/project

# Reset context only
claude-context-switcher.sh --reset
```

**Configuration File Format (`~/.claude-projects.conf`):**
```
# Claude Code Projects Configuration
# One project path per line
/home/user/projects/project1
/home/user/projects/project2
/home/user/work/api-service
```

### 4. Project Initializer (`claude-project-init.sh`)

**Purpose:** Set up a new project for Claude context management.

**Functionality:**
- Create `.claude/` directory in project root
- Generate `.claude/instructions.md` template
- Create `claude_transcripts/` directory
- Generate README.md for transcripts
- Create `.claude/PROJECT_CONTEXT.md` guide
- Generate `claude-resume.sh` quick-start script
- Optionally add `claude_transcripts/` to `.gitignore`

**Usage:**
```bash
# Initialize current directory
claude-project-init.sh

# Initialize specific directory
claude-project-init.sh /path/to/project
```

**Files Created:**
```
project-root/
├── .claude/
│   ├── instructions.md          # Project-specific instructions for Claude
│   └── PROJECT_CONTEXT.md       # Context management guide
├── claude_transcripts/
│   └── README.md                # Info about transcripts
└── claude-resume.sh             # Quick start script
```

### 5. Shell Integration (`shell-config.sh`)

**Purpose:** Provide shell integration for automatic context management.

**Functionality:**
- Define command aliases (claude-save, claude-load, etc.)
- Auto-detect when entering a project with saved context
- Provide project switcher function
- Add utility functions for status checks

**Features:**
- Compatible with bash and zsh
- Optional auto-load on directory change
- Project workspace switcher function
- Status display commands

**Aliases to Define:**
```bash
claude-save    -> claude-context-manager.sh
claude-load    -> claude-context-loader.sh
claude-init    -> claude-project-init.sh
claude-switch  -> claude-context-switcher.sh
```

**Shell Functions:**
```bash
work <project>     # Switch to project and load context
claude-status      # Show current context status
claude-projects    # List projects with saved context
```

## Critical Requirements

### Backward Compatibility

**IMPORTANT:** All scripts must work regardless of installation location.

The `claude-resume.sh` script generated by `claude-project-init.sh` must search for `claude-context-loader.sh` in ALL these locations (in order):

1. `claude-load` command (if in PATH)
2. `~/.local/bin/claude-load` (symlink)
3. `~/.local/bin/claude-tools/claude-context-loader.sh`
4. `~/bin/claude-tools/claude-context-loader.sh`
5. `~/claude-context-loader.sh` (home directory)
6. `/usr/local/bin/claude-context-loader.sh` (system-wide)
7. Same directory as the script itself

**Example Implementation:**
```bash
# Find loader script
LOADER_FOUND=false

if command -v claude-load &> /dev/null; then
    claude-load
    LOADER_FOUND=true
elif [ -f "$HOME/.local/bin/claude-tools/claude-context-loader.sh" ]; then
    "$HOME/.local/bin/claude-tools/claude-context-loader.sh"
    LOADER_FOUND=true
# ... check other locations ...
fi

if [ "$LOADER_FOUND" = false ]; then
    echo "Error: claude-context-loader.sh not found!"
    exit 1
fi
```

### Error Handling

All scripts must:
- Check if required directories exist before accessing them
- Provide clear error messages
- Exit gracefully on errors
- Verify git repository status before git operations
- Handle missing files/directories appropriately

### User Experience

- Provide colored output (green for success, yellow for warnings, red for errors)
- Show progress indicators for long operations
- Ask for confirmation before destructive operations
- Display helpful messages and next steps
- Include `--help` option for all scripts

## Installation System

### Automated Installer (`setup.sh`)

**Purpose:** One-command installation of all components.

**Functionality:**
- Check for presence of all required scripts
- Prompt for installation location
- Copy files to installation directory
- Create command symlinks
- Configure shell (add to ~/.bashrc or ~/.zshrc)
- Verify installation

**Installation Locations:**
- **Recommended:** `~/.local/bin/claude-tools/`
- **Alternative:** `~/bin/`
- **System-wide:** `/usr/local/bin/` (requires sudo)

**Post-Installation:**
- Create symlinks in `~/.local/bin/`: claude-save, claude-load, claude-init, claude-switch
- Add PATH configuration to shell
- Source shell integration

### File Verification (`verify-files.sh`)

**Purpose:** Verify all required files are present before installation.

**Functionality:**
- Check for all core scripts
- Check for optional files
- Display status of each file
- Exit with error if required files missing

## Templates

### Project Instructions Template (`.claude/instructions.md`)

**Purpose:** Provide a template for project-specific Claude instructions.

**Sections:**
- Project Overview (name, description, type, status)
- Tech Stack (languages, frameworks, dependencies)
- Project Structure (directory layout, key files)
- Development Workflow (setup, running, testing, building)
- Coding Conventions (style guide, naming, patterns)
- Architecture Decisions (design patterns, state management)
- Current Focus (active tasks, recently completed, next steps)
- Important Context for Claude (things to know, avoid, prefer)
- Common Tasks & Commands
- Known Issues & Gotchas
- Testing Guidelines
- Deployment info
- Team Conventions (commits, branches, PRs)

### Context Summary Template (`claude_transcripts/CONTEXT_SUMMARY.md`)

**Purpose:** Auto-generated summary when loading context.

**Content:**
- Repository name and path
- Last context save date
- Number of transcripts
- Quick project overview section (editable by user)
- Key information Claude should know
- Recent work summary
- Next steps
- Important files list
- Known issues

## File Structure

### Per-Project Structure
```
project-root/
├── .claude/
│   ├── instructions.md          # Claude's project guide (USER EDITS THIS)
│   └── PROJECT_CONTEXT.md       # Context management guide
├── claude_transcripts/
│   ├── README.md                # Transcript directory info
│   ├── CONTEXT_SUMMARY.md       # Auto-generated summary
│   ├── transcript_20240215_143022.json
│   └── transcript_20240215_151534.json
└── claude-resume.sh             # Quick start script
```

### System Installation Structure
```
~/.local/bin/claude-tools/       # Main installation directory
├── claude-context-manager.sh
├── claude-context-loader.sh
├── claude-context-switcher.sh
├── claude-project-init.sh
├── shell-config.sh
└── (documentation files)

~/.local/bin/                    # Symlinks for easy access
├── claude-save -> claude-tools/claude-context-manager.sh
├── claude-load -> claude-tools/claude-context-loader.sh
├── claude-init -> claude-tools/claude-project-init.sh
└── claude-switch -> claude-tools/claude-context-switcher.sh

~/.claude-projects.conf          # Multi-project configuration
```

## Workflow Examples

### Daily Workflow
```bash
# Morning - Resume work on project
cd ~/projects/my-project
claude-load
claudecode

# End of day - Save context
claude-save

# Or use quick script
./claude-resume.sh
```

### Switching Projects
```bash
# Finish project A
cd ~/projects/project-a
claude-save

# Start project B
cd ~/projects/project-b
claude-load
claudecode
```

### Batch Save All Projects
```bash
# Save context for all configured projects
claude-switch --all
```

### Initialize New Project
```bash
cd ~/projects/new-project
claude-init
# Edit .claude/instructions.md
./claude-resume.sh
```

## Technical Specifications

### Transcript Location
- **Active transcripts:** `~/.claude/transcripts/`
- **Saved transcripts:** `<project-root>/claude_transcripts/`

### File Naming
- Transcripts: `transcript_YYYYMMDD_HHMMSS.json`
- Backups: `transcripts_backup_YYYYMMDD_HHMMSS/`

### Environment Variables
```bash
CLAUDE_PROJECTS_DIR="$HOME/projects"  # Default projects directory
```

### Color Codes for Output
```bash
GREEN='\033[0;32m'   # Success messages
BLUE='\033[0;34m'    # Step indicators
YELLOW='\033[1;33m'  # Warnings
RED='\033[0;31m'     # Errors
NC='\033[0m'         # No color (reset)
```

### Git Integration
- Auto-detect git repository root
- Commit transcripts with message: `"chore: save Claude Code transcripts before context switch"`
- Check git status before committing
- Handle non-git directories gracefully

## Optional Features

### Git Hooks
- Pre-checkout hook to save context
- Post-checkout hook to load context

### Cron Jobs
- Daily auto-save of all projects

### Enhanced cd Command
- Auto-detect and prompt to load context when entering project

### Status Dashboard
- Show active transcripts count
- Show current project
- Show saved transcripts count
- Show last save date

## Documentation Requirements

### README.md
- Overview of the system
- Quick start guide
- Basic usage examples
- Links to detailed guides

### COMPLETE_GUIDE.md
- Comprehensive usage documentation
- All features explained
- Workflow examples
- Best practices
- Troubleshooting

### DEPLOYMENT_GUIDE.md
- Installation instructions for all methods
- Platform-specific instructions
- Directory structure
- Updating and uninstalling

### QUICK_INSTALL.md
- One-liner installation commands
- Quick reference
- Shell-specific instructions

### FILE_MANIFEST.md
- List of all files
- File descriptions
- Size reference
- Verification checklist

## Success Criteria

The system is complete when:

1. ✅ All four core scripts work independently
2. ✅ Installation via setup.sh works on bash and zsh
3. ✅ Scripts work from any installation location (backward compatible)
4. ✅ Context saves and loads correctly
5. ✅ Multi-project switching works
6. ✅ Project initialization creates all necessary files
7. ✅ claude-resume.sh finds loader script regardless of installation
8. ✅ Shell integration provides convenient aliases
9. ✅ Git operations work correctly
10. ✅ Error handling is robust
11. ✅ Documentation is complete and clear
12. ✅ User can switch between projects without context pollution

## Testing Checklist

- [ ] Install to `~/.local/bin/claude-tools/` and verify all commands work
- [ ] Install to `~/bin/` and verify all commands work
- [ ] Test claude-init on fresh project
- [ ] Test claude-save with actual transcripts
- [ ] Test claude-load restores transcripts correctly
- [ ] Test claude-resume.sh finds loader from all install locations
- [ ] Test multi-project workflow
- [ ] Test git commit functionality
- [ ] Test in bash shell
- [ ] Test in zsh shell
- [ ] Test error handling (missing files, no git, etc.)
- [ ] Verify .claude/instructions.md is read by Claude Code

## Priority Order

1. **High Priority:** Core scripts (manager, loader, init)
2. **High Priority:** Backward compatibility in claude-resume.sh
3. **Medium Priority:** Multi-project switcher
4. **Medium Priority:** Setup/installation script
5. **Medium Priority:** Shell integration
6. **Low Priority:** Documentation files
7. **Low Priority:** Advanced features (hooks, status commands)

## Notes for Implementation

- Keep scripts POSIX-compatible where possible
- Use `set -e` for error handling
- Provide verbose output for debugging
- Test with actual Claude Code installation
- Ensure transcript JSON files are handled correctly
- Handle edge cases (empty directories, missing git, etc.)
- Make all paths user-configurable where appropriate
