# High-Level Design: Claude Code Context Management System

## 1. System Overview

The Claude Code Context Management System is a collection of shell scripts that manage Claude Code conversation transcripts on a per-project basis. It solves the problem of context pollution when developers switch between repositories by providing save, load, and switch operations on transcript files stored in `~/.claude/transcripts/`.

### Architecture Style

The system follows a **file-based, stateless CLI tool** pattern. Each script is a standalone executable that reads from and writes to well-known filesystem locations. There is no daemon, no database, and no background process. All state lives in:

- **Global state:** `~/.claude/transcripts/` (active Claude Code transcripts)
- **Per-project state:** `<project-root>/claude_transcripts/` (saved transcripts)
- **System config:** `~/.claude-projects.conf` (registered project list)

```
┌─────────────────────────────────────────────────────────────────┐
│                        User's Shell                             │
│  (aliases: claude-save, claude-load, claude-init, claude-switch)│
└──────────┬──────────────────────────────────────────────────────┘
           │ invokes
           ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Core Scripts                               │
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────────────────┐ │
│  │ context-     │  │ context-     │  │ context-              │ │
│  │ manager.sh   │  │ loader.sh    │  │ switcher.sh           │ │
│  │ (save)       │  │ (load)       │  │ (multi-project)       │ │
│  └──────┬───────┘  └──────┬───────┘  └───────────┬───────────┘ │
│         │                 │                       │             │
│  ┌──────┴─────────────────┴───────────────────────┴───────────┐ │
│  │              Shared Conventions                             │ │
│  │  - Color output helpers                                    │ │
│  │  - Git detection & operations                              │ │
│  │  - Path resolution (project root)                          │ │
│  │  - Error handling (set -e, checks)                         │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐                             │
│  │ project-     │  │ shell-       │                             │
│  │ init.sh      │  │ config.sh    │                             │
│  │ (bootstrap)  │  │ (aliases)    │                             │
│  └──────────────┘  └──────────────┘                             │
└─────────────────────────────────────────────────────────────────┘
           │                              │
           ▼                              ▼
┌─────────────────────┐     ┌──────────────────────────┐
│ ~/.claude/           │     │ <project-root>/           │
│   transcripts/       │     │   claude_transcripts/     │
│     *.json           │     │     *.json                │
│                      │     │     CONTEXT_SUMMARY.md    │
│                      │     │   .claude/                │
│                      │     │     instructions.md       │
└─────────────────────┘     └──────────────────────────┘
     (global active)              (per-project saved)
```

---

## 2. Data Flow

### 2.1 Save Operation (claude-save)

Copies transcripts from the global location into the project tree.

```
~/.claude/transcripts/*.json
        │
        │  1. Detect project root (git root or cwd)
        │  2. Create <project>/claude_transcripts/ if missing
        │  3. Copy transcript files
        │  4. Generate README.md with metadata
        │  5. (optional) git add + commit
        │  6. (optional) Clear ~/.claude/transcripts/
        │
        ▼
<project-root>/claude_transcripts/*.json
```

**Key decisions:**
- Transcripts are **copied**, not moved, unless the user explicitly requests a reset. This is the safe default.
- Before clearing global transcripts, a timestamped backup is created at `~/.claude/transcripts_backup_YYYYMMDD_HHMMSS/`.
- If a project path argument is given, only transcripts whose content references that path are copied (best-effort filtering). If no filtering is possible, all transcripts are copied.

### 2.2 Load Operation (claude-load)

Restores project transcripts back into the global location.

```
<project-root>/claude_transcripts/*.json
        │
        │  1. Detect project root
        │  2. Verify claude_transcripts/ exists
        │  3. Back up current ~/.claude/transcripts/
        │  4. Clear ~/.claude/transcripts/
        │  5. Copy saved transcripts into ~/.claude/transcripts/
        │  6. Generate/update CONTEXT_SUMMARY.md
        │  7. Display summary to user
        │
        ▼
~/.claude/transcripts/*.json  (now contains this project's history)
```

**Key decisions:**
- Load always **replaces** the global transcripts (after backup). This guarantees a clean context for the target project.
- The backup-then-replace approach means if the user forgot to save before loading, they can recover from the backup directory.

### 2.3 Switch Operation (claude-switch --all)

Orchestrates save across multiple projects, then resets.

```
~/.claude-projects.conf          ~/.claude/transcripts/
        │                                │
        │  1. Read project list          │
        │  2. For each project:          │
        │     a. Filter transcripts      │
        │        matching project path   │
        │     b. Copy to project's       │
        │        claude_transcripts/     │
        │  3. Back up global transcripts │
        │  4. Clear global transcripts   │
        │                                │
        ▼                                ▼
<project-N>/claude_transcripts/   (empty — clean slate)
```

### 2.4 Init Operation (claude-init)

Creates the scaffolding for a new project. Pure write operation — touches nothing in `~/.claude/`.

```
<project-root>/  (before)        <project-root>/  (after)
    ├── src/                         ├── src/
    ├── ...                          ├── ...
    │                                ├── .claude/
    │                                │   ├── instructions.md
    │                                │   └── PROJECT_CONTEXT.md
    │                                ├── claude_transcripts/
    │                                │   └── README.md
    │                                └── claude-resume.sh
```

---

## 3. Component Design

### 3.1 claude-context-manager.sh

| Aspect       | Detail |
|-------------|--------|
| **Input**   | Zero or more project paths as positional args. Defaults to current project root. |
| **Output**  | Transcript files copied into each project's `claude_transcripts/`. |
| **Flags**   | `--reset` clear global transcripts after save, `--no-git` skip git commit, `--help` usage info |
| **Exit codes** | 0 = success, 1 = error (no transcripts, invalid path) |

**Algorithm:**
1. Parse arguments and flags.
2. For each target project path:
   a. Resolve to absolute path. If git repo, use `git rev-parse --show-toplevel`.
   b. Create `claude_transcripts/` if it doesn't exist.
   c. Copy all `.json` files from `~/.claude/transcripts/` into `claude_transcripts/`.
   d. Generate/update `claude_transcripts/README.md` with timestamp, count, project name.
   e. If inside a git repo and `--no-git` not set: `git add claude_transcripts/ && git commit -m "chore: save Claude Code transcripts before context switch"`.
3. If `--reset` flag: back up `~/.claude/transcripts/` to `~/.claude/transcripts_backup_<timestamp>/`, then clear.
4. Print summary: number of transcripts saved, per project.

### 3.2 claude-context-loader.sh

| Aspect       | Detail |
|-------------|--------|
| **Input**   | Optional project path. Defaults to current project root. |
| **Output**  | Transcripts restored to `~/.claude/transcripts/`. CONTEXT_SUMMARY.md generated. |
| **Flags**   | `--no-clear` don't clear existing global transcripts first, `--help` |
| **Exit codes** | 0 = success, 1 = no saved transcripts found |

**Algorithm:**
1. Resolve project root.
2. Check `claude_transcripts/` exists and contains `.json` files. Exit with message if empty.
3. Back up current `~/.claude/transcripts/` (if non-empty) to timestamped backup dir.
4. Clear `~/.claude/transcripts/` (unless `--no-clear`).
5. Copy `claude_transcripts/*.json` into `~/.claude/transcripts/`.
6. Generate `claude_transcripts/CONTEXT_SUMMARY.md` with: repo name, path, date, transcript count, placeholder sections for user notes.
7. Print: project name, transcripts loaded count, last save date.

### 3.3 claude-context-switcher.sh

| Aspect       | Detail |
|-------------|--------|
| **Input**   | Subcommand flag + optional project path |
| **Output**  | Depends on subcommand |
| **Flags**   | `--init`, `--add <path>`, `--remove <path>`, `--list`, `--all`, `--single <path>`, `--reset`, `--help` |
| **Config**  | `~/.claude-projects.conf` — one absolute path per line, `#` comments allowed |

**Subcommand logic:**
- `--init`: Create `~/.claude-projects.conf` with header comment if it doesn't exist.
- `--add <path>`: Resolve path to absolute, append to config (skip if already present).
- `--remove <path>`: Remove matching line from config.
- `--list`: Read config, print each project with existence check (green if exists, red if missing).
- `--all`: For each project in config, invoke `claude-context-manager.sh <path>`, then clear global transcripts.
- `--single <path>`: Invoke `claude-context-manager.sh <path>` for just one project.
- `--reset`: Back up and clear `~/.claude/transcripts/` without saving anywhere.

**Dependency:** This script calls `claude-context-manager.sh` internally. It locates it using the same multi-location search strategy described in Section 5.

### 3.4 claude-project-init.sh

| Aspect       | Detail |
|-------------|--------|
| **Input**   | Optional project path. Defaults to cwd. |
| **Output**  | Scaffolding files created in project directory. |
| **Flags**   | `--gitignore` add `claude_transcripts/` to `.gitignore`, `--help` |

**Algorithm:**
1. Resolve project root.
2. Create `.claude/` directory (skip if exists, print note).
3. Write `.claude/instructions.md` from embedded template (skip if exists — never overwrite user content).
4. Write `.claude/PROJECT_CONTEXT.md` (overwrite OK — this is system-generated).
5. Create `claude_transcripts/` directory.
6. Write `claude_transcripts/README.md`.
7. Write `claude-resume.sh` with multi-location loader search logic. `chmod +x`.
8. If `--gitignore`: append `claude_transcripts/` to `.gitignore` (if not already present).
9. Print summary of files created and next steps.

**Template embedding:** All templates are defined as heredocs within the script itself. No external template files are needed. This keeps the tool self-contained.

### 3.5 shell-config.sh

This file is **sourced** (not executed) by the user's shell rc file. It defines:

```bash
# Aliases
alias claude-save='claude-context-manager.sh'
alias claude-load='claude-context-loader.sh'
alias claude-init='claude-project-init.sh'
alias claude-switch='claude-context-switcher.sh'

# Functions
work()        # cd to project, run claude-load
claude-status()   # show current transcript count, project detection
claude-projects() # list projects with saved transcripts

# Optional: chpwd hook (zsh) / PROMPT_COMMAND addition (bash)
# for auto-detection when entering a project directory
```

**Alias resolution:** Aliases point to script names (not full paths). This works because the installer adds the scripts directory to `$PATH`. If the user installed to a non-PATH location, the aliases use the full path determined at install time.

---

## 4. Installation Design

### 4.1 setup.sh

**Flow:**
1. Run `verify-files.sh` to confirm all scripts are present in the source directory.
2. Prompt user for install location (default: `~/.local/bin/claude-tools/`).
3. Create install directory. Copy all `.sh` scripts into it. `chmod +x` each.
4. Create `~/.local/bin/` symlinks: `claude-save`, `claude-load`, `claude-init`, `claude-switch`.
5. Detect shell (bash or zsh). Append `source <install-dir>/shell-config.sh` to the appropriate rc file (idempotent — check before appending).
6. Ensure `~/.local/bin` is in `$PATH` in the rc file.
7. Print success message with instructions to reload shell.

### 4.2 verify-files.sh

Checks for the presence of each required script in the current directory (or a given source directory). Prints a checklist with pass/fail per file. Exits non-zero if any required file is missing.

**Required files:**
- `claude-context-manager.sh`
- `claude-context-loader.sh`
- `claude-context-switcher.sh`
- `claude-project-init.sh`
- `shell-config.sh`
- `setup.sh`

**Optional files (warn if missing, don't fail):**
- `README.md`
- `COMPLETE_GUIDE.md`
- `DEPLOYMENT_GUIDE.md`
- `QUICK_INSTALL.md`
- `FILE_MANIFEST.md`

---

## 5. Backward Compatibility: Script Discovery

The `claude-resume.sh` script (generated per-project by `claude-project-init.sh`) and `claude-context-switcher.sh` (which invokes the manager) both need to locate sibling scripts at runtime. They use a **prioritized search** through these locations:

```
Priority  Location                                          Rationale
───────── ──────────────────────────────────────────────────  ─────────────────────────
1         command -v claude-load (on PATH)                   User installed properly
2         ~/.local/bin/claude-load (symlink)                 Standard install location
3         ~/.local/bin/claude-tools/claude-context-loader.sh Full path in standard loc
4         ~/bin/claude-tools/claude-context-loader.sh        Alternate install location
5         ~/claude-context-loader.sh                         Minimal manual install
6         /usr/local/bin/claude-context-loader.sh            System-wide install
7         $(dirname "$0")/claude-context-loader.sh           Same directory as caller
```

This is implemented as a helper function embedded in each script that needs it:

```bash
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
```

---

## 6. Error Handling Strategy

All scripts follow a consistent error handling approach:

1. **`set -e`** at the top — exit on any unhandled error.
2. **Pre-flight checks** before any destructive operation:
   - Directory existence: `[ -d "$dir" ]`
   - File existence: `[ -f "$file" ]`
   - Write permission: `[ -w "$dir" ]`
   - Git repo detection: `git rev-parse --is-inside-work-tree 2>/dev/null`
3. **Backup before destructive operations:** Any time global transcripts are cleared, a timestamped backup is created first.
4. **Confirmation prompts** for destructive actions (clearing transcripts, resetting context). These can be bypassed with a `--force` or `-y` flag for scripting use.
5. **Consistent exit codes:**
   - `0` — Success
   - `1` — General error (missing files, invalid arguments)
   - `2` — User cancelled (declined confirmation prompt)

---

## 7. Output and UX Conventions

All scripts share a common set of output helper functions (defined inline in each script to maintain standalone operation):

```bash
info()    { echo -e "\033[0;34m[INFO]\033[0m $*"; }
success() { echo -e "\033[0;32m[OK]\033[0m $*"; }
warn()    { echo -e "\033[1;33m[WARN]\033[0m $*"; }
error()   { echo -e "\033[0;31m[ERROR]\033[0m $*" >&2; }
step()    { echo -e "\033[0;34m→\033[0m $*"; }
```

**Conventions:**
- Step-by-step progress is printed as operations happen (`step "Copying transcripts..."`).
- Final result uses `success` or `error`.
- Warnings (non-fatal issues) use `warn`.
- All error output goes to stderr.
- Scripts support a `--quiet` flag to suppress info/step output (only errors and final result shown).
- `--help` flag prints usage synopsis and exits.

---

## 8. Template Content Design

### 8.1 instructions.md Template

The generated `.claude/instructions.md` is a comprehensive template with section headers and placeholder text. Each section is wrapped in HTML comments explaining what to fill in. This makes it easy for users to customize without needing to understand the system.

Key sections:
- **Project Overview** — Name, purpose, tech stack
- **Project Structure** — Directory layout
- **Development Workflow** — Build, test, run commands
- **Coding Conventions** — Style preferences
- **Current Focus** — Active work items
- **Important Context** — Things Claude should know, avoid, or prefer

### 8.2 CONTEXT_SUMMARY.md Template

Auto-generated each time `claude-context-loader.sh` runs. Contains machine-readable metadata at the top (timestamp, transcript count, project path) and human-editable sections below.

### 8.3 claude-resume.sh Template

A short, self-contained script that:
1. Searches for `claude-context-loader.sh` using the 7-location priority list.
2. Invokes the loader for the current project.
3. Prints instructions for starting Claude Code.
4. Is marked executable on creation.

---

## 9. Security Considerations

- **No secrets in transcripts:** Transcript files may contain sensitive information from Claude conversations. The system treats them as user data — it copies them but never transmits them externally.
- **No command injection:** All path variables are quoted. No `eval` is used. Arguments are never passed through unquoted expansion.
- **Git safety:** Git operations use explicit file paths (`git add claude_transcripts/`), never `git add -A` or `git add .`.
- **File permissions:** Scripts are installed with `755`. Transcript files retain their original permissions.
- **Gitignore option:** `claude-project-init.sh --gitignore` adds `claude_transcripts/` to `.gitignore` for users who don't want transcripts committed to version control.

---

## 10. Limitations and Non-Goals

- **No transcript filtering by project content:** Claude Code transcripts are JSON files that don't always contain project path information. The save operation copies all global transcripts, not just those related to the target project. Filtering is best-effort only.
- **No encryption:** Transcripts are stored as plain files. Encryption is out of scope.
- **No remote sync:** The system is local-only. Syncing transcripts across machines is left to the user's existing tools (git, rsync, etc.).
- **No transcript merging:** Loading replaces the global transcripts entirely. There is no merge of saved and existing transcripts (except via `--no-clear`).
- **Single user:** The system assumes a single user on the machine. There is no multi-user access control.

---

## 11. Implementation Order

The following order minimizes dependencies and allows incremental testing:

| Phase | Scripts | Rationale |
|-------|---------|-----------|
| 1     | `claude-project-init.sh` | No dependencies. Creates scaffolding. Testable immediately. |
| 2     | `claude-context-manager.sh` | Depends on transcript directory existing (created by init or manually). |
| 3     | `claude-context-loader.sh` | Depends on saved transcripts existing (created by manager). |
| 4     | `claude-context-switcher.sh` | Wraps manager. Requires manager to be working. |
| 5     | `shell-config.sh` | Depends on all core scripts existing. |
| 6     | `verify-files.sh`, `setup.sh` | Depends on all scripts being complete. |
| 7     | Documentation files | Written last, after behavior is finalized. |

---

## 12. Testing Approach

Each script will be tested in isolation and then as part of the full workflow:

**Unit testing (per script):**
- Run with `--help` — should print usage and exit 0.
- Run with invalid arguments — should print error and exit 1.
- Run in a directory without git — should handle gracefully.
- Run when `~/.claude/transcripts/` is empty — should warn, not crash.
- Run when target directories already exist — should be idempotent.

**Integration testing (workflow):**
1. `claude-init` on a fresh project — verify all files created.
2. Place dummy transcript files in `~/.claude/transcripts/`.
3. `claude-save` — verify transcripts copied to project.
4. Clear `~/.claude/transcripts/` manually.
5. `claude-load` — verify transcripts restored.
6. Set up two projects, `claude-switch --all` — verify both get transcripts.
7. Run `claude-resume.sh` from the project — verify it finds the loader.

**Shell compatibility:**
- All tests run under both `bash` and `zsh`.
- Verify `shell-config.sh` sources without errors in both shells.
