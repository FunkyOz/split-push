# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a GitHub Action (composite action) that syncs specific folders from a monorepo to dedicated repositories using git subtree split. The action preserves git history and only pushes when changes are detected in the target folder.

## Architecture

### Core Components

**action.yml**
- GitHub Action definition file (composite action type)
- Defines inputs:
  - Required: `local` (folder path), `remote` (repository URL)
  - Optional: `branch`, `token`, `author`
- Defines outputs (pushed, skipped - both boolean strings)
- Invokes scripts/push.sh with flag-based arguments (--branch/-b, --token/-t, --author/-a)

**scripts/lib/logging.sh**
- Logging library providing colored console output functions
- Foundation dependency for all other scripts
- Include guard: `_LOGGING_SH_LOADED` (prevents multiple sourcing)
- Functions:
  - `log_info()`: Print informational messages in blue
  - `log_success()`: Print success messages in green
  - `log_warning()`: Print warning messages in yellow
  - `log_error()`: Print error messages in red to stderr
- No external dependencies

**scripts/push.sh**
- Main bash script that implements the sync logic
- Sources libraries: logging.sh and detect-changes.sh
- **Usage**: `push.sh LOCAL REMOTE [OPTIONS]`
  - Positional arguments: LOCAL (folder path), REMOTE (repository URL)
  - Optional flags: --branch/-b, --token/-t, --author/-a, --help/-h
  - Run `push.sh --help` for comprehensive usage information
- Structured into discrete functions with single responsibilities:
  - `parse_arguments()`: Parses command-line arguments (positional and optional flags)
  - `validate_inputs()`: Ensures required parameters (local, remote) exist and folder is present
  - `configure_git()`: Sets git user.name and user.email
  - `perform_subtree_split()`: Creates temporary branch with folder history using git subtree split
  - `setup_remote()`: Adds target repository as remote with optional token authentication
  - `push_to_repository()`: Pushes split branch using --force-with-lease
  - `cleanup()`: Removes temporary branches and remotes
  - `set_output()`: Sets GitHub Actions outputs (supports both modern and legacy formats)
  - `parse_remote_url()`: Parses and formats remote repository URLs (handles local paths, SSH, HTTPS with/without tokens)
  - `parse_author()`: Parses author information from various formats
  - `main()`: Orchestrates the entire workflow

**scripts/lib/detect-changes.sh**
- Change detection library (sourced by push.sh)
- Include guard: `_DETECT_CHANGES_SH_LOADED` (prevents multiple sourcing)
- Sources logging.sh for console output
- Contains git context and change detection logic:
  - `detect_changes()`: Handles change detection for push events, PRs, and first commits
  - `detect_branch()`: Auto-detects branch from GitHub context (GITHUB_REF, etc.)
  - `get_default_branch()`: Queries remote repository for default branch

### Key Technical Details

**Git Operations Flow:**
1. Change detection compares commits/branches to find folder-specific changes
2. `git subtree split --prefix=<folder>` extracts folder history into temporary branch
3. Remote added with appropriate URL format:
   - HTTPS with token: `https://x-access-token:{token}@github.com/{repo}.git`
   - HTTPS without token: `https://github.com/{repo}.git` (relies on git credentials)
   - SSH: `git@github.com:{org}/{repo}.git`
   - Local path: `/path/to/repo` (for testing)
4. Push uses `--force-with-lease` to prevent overwriting unexpected changes
5. Temporary branches and remotes cleaned up regardless of success/failure

**Change Detection Logic:**
- **Push events**: Compare `HEAD^` with `HEAD` using `git diff`
- **Pull requests**: Compare `origin/{base-ref}...HEAD` using `git diff`
- **First commit**: Use `git ls-tree -r HEAD --name-only` to check if folder has files
- All comparisons filter for changes in the specific folder using grep

**Error Handling:**
- Bash strict mode enabled: `set -euo pipefail`
- All git operations check exit codes
- Missing base branch falls back to `HEAD^`
- Non-existent target branch triggers creation warning but continues
- Cleanup runs even on failure (not in trap, but called before exits)

**Library Design:**
- **Include Guards**: All library files use include guards to prevent multiple sourcing
  - Pattern: `[[ -n "${_LIBRARY_NAME_LOADED:-}" ]] && return 0`
  - Each library sets its guard variable on first load
  - Subsequent source attempts return immediately without re-executing
  - Benefits: Performance optimization, prevents variable redefinition, safe for complex dependency chains
- **Dependency Chain**: Libraries source their dependencies automatically
  - `logging.sh`: No dependencies (foundation)
  - `detect-changes.sh`: Sources `logging.sh`
  - `push.sh`: Sources both `logging.sh` and `detect-changes.sh`
  - Include guards ensure `logging.sh` is only loaded once even when sourced multiple times

## Testing

This project uses BATS (Bash Automated Testing System) for comprehensive test coverage.

### Running Tests Locally

**Install BATS:**
```bash
# macOS
brew install bats-core

# Linux
sudo npm install -g bats

# Install support libraries (required for tests)
git clone https://github.com/bats-core/bats-support.git test_helper/bats-support
git clone https://github.com/bats-core/bats-assert.git test_helper/bats-assert
```

**Run all tests:**
```bash
./tests/run-tests.sh
```

**Run specific test suite:**
```bash
# Unit tests only
bats tests/unit/*.bats

# Integration tests only
bats tests/integration/*.bats

# Specific test file
bats tests/unit/detect-changes.bats
```

### Test Structure

- **`tests/unit/`** - Unit tests for individual functions
  - `detect-changes.bats` - Tests for change detection logic
  - `parse-functions.bats` - Tests for URL and author parsing
  - `git-operations.bats` - Tests for git operations and validation
  - `test_helper.bash` - Shared test utilities and mock functions

- **`tests/integration/`** - End-to-end workflow tests
  - `test-repository.bats` - Complete push workflows with real git operations

- **`tests/run-tests.sh`** - Local test runner script

### CI/CD Testing

Tests run automatically in GitHub Actions on push and pull requests:
- Unit tests validate individual function behavior
- Integration tests verify end-to-end workflows
- Shellcheck linting ensures code quality

See `.github/workflows/test.yml` for CI configuration.

### Manual Testing

To test the bash script manually (outside GitHub Actions):

```bash
# Display help
./scripts/push.sh --help

# Test with all options
./scripts/push.sh \
  "path/to/folder" \
  "org/repo-name" \
  --branch "branch-name" \
  --token "github_token" \
  --author "Your Name <your@email.com>"

# Test with minimal arguments (branch auto-detected, author from git config)
./scripts/push.sh "path/to/folder" "org/repo-name"

# Test with SSH URL (no token needed)
./scripts/push.sh "path/to/folder" "git@github.com:org/repo.git" --branch "main"

# Using short flags
./scripts/push.sh "path/to/folder" "org/repo-name" -b "main" -t "token" -a "Name <email>"
```

Note: Manual testing requires being in a git repository with the target folder present.

## Common Development Commands

**Validate action.yml syntax:**
```bash
# Install actionlint
brew install actionlint  # macOS
# OR: https://github.com/rhysd/actionlint

# Run validation
actionlint action.yml
```

**Test bash script syntax:**
```bash
# Check for syntax errors
bash -n scripts/push.sh
bash -n scripts/lib/detect-changes.sh

# Run with shellcheck for best practices
shellcheck scripts/push.sh
shellcheck scripts/lib/detect-changes.sh
```

**Run tests:**
```bash
# Run all tests
./tests/run-tests.sh

# Run specific test suite
bats tests/unit/detect-changes.bats
bats tests/integration/test-repository.bats
```

## Usage in GitHub Workflows

The action expects `fetch-depth: 0` in the checkout step to ensure full git history for subtree split:

```yaml
steps:
  - uses: actions/checkout@v4
    with:
      fetch-depth: 0  # Required for git subtree split

  - uses: ./.github/actions/push-monorepo
    with:
      folder: "my-folder"
      # ... other inputs
```

For matrix strategies with multiple folders, use `fail-fast: false` to prevent one failure from stopping all jobs.

## Important Constraints

- **Full git history required**: Action fails without `fetch-depth: 0`
- **Folder must exist**: Script validates folder presence before proceeding
- **Authentication**: Token is optional but required for HTTPS URLs without existing git credentials
  - SSH URLs (`git@github.com:...`) don't require a token
  - HTTPS URLs can use a token or rely on git credential helpers
  - Token (when provided) must have write permissions to target repository
- **Branch protection**: May block pushes even with valid token
- **Composite action limitation**: Cannot use Docker or JavaScript, only shell steps
