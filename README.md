# Split and push from a Monorepo to dedicated repositories

A GitHub Action and standalone CLI tool that intelligently syncs monorepo folders to dedicated repositories using git subtree split. This tool detects changes in specific folders and pushes only when changes are detected, preserving complete git history.

[![Tests](https://img.shields.io/badge/tests-63%20passed-success)](./tests)
[![Coverage](https://img.shields.io/badge/coverage-100%25-success)](./tests)
[![Bash](https://img.shields.io/badge/bash-4.0+-blue)](./scripts)
[![License](https://img.shields.io/badge/license-MIT-blue)](./LICENSE)

## At a Glance

```bash
# GitHub Action - Sync monorepo folder to dedicated repo
- uses: ./.github/actions/push-monorepo
  with:
    local: "packages/api"
    remote: "https://github.com/org/api-repo.git"
    token: ${{ secrets.GITHUB_TOKEN }}

# CLI - Direct command line usage
./scripts/push.sh "packages/api" "org/api-repo" --branch "main"

# Result - Dedicated repo with full git history
✓ Folder history preserved
✓ Only pushes when changes detected
✓ Supports HTTPS, SSH, and local repos
✓ Zero external dependencies
```

**What it does**: Extracts a folder from your monorepo and pushes it to a separate repository with complete git history, only when changes are detected.

**Why use it**: Split monorepo packages into individual repos for independent versioning, deployment, or distribution while maintaining full git history.

## Table of Contents

- [Features](#features)
- [Quick Start](#quick-start)
- [Usage Examples](#usage-examples)
- [Inputs](#inputs)
- [Outputs](#outputs)
- [How It Works](#how-it-works)
- [Change Detection Logic](#change-detection-logic)
- [Requirements](#requirements)
- [Error Handling](#error-handling)
- [Security](#security)
- [Performance](#performance)
- [Reusability](#reusability)
- [Advanced Usage](#advanced-usage)
- [Example Workflows](#example-workflows)
- [Troubleshooting](#troubleshooting)
- [Development](#development)
- [Comparison with Alternatives](#comparison-with-alternatives)
- [Contributing](#contributing)

## Features

- **Smart Change Detection** - Detects changes in push events, pull requests, tags, and first commits
- **History Preservation** - Uses git subtree split to maintain complete commit history
- **Flexible Authentication** - Supports HTTPS (with/without tokens), SSH, and local repositories
- **Parallel Execution** - Compatible with GitHub Actions matrix strategies
- **Comprehensive CLI** - Can be used as a standalone command-line tool with `--help`
- **Zero Dependencies** - Pure bash implementation using only git commands
- **Fully Tested** - 63 automated tests (54 unit + 9 integration) with 100% pass rate
- **Optional Token** - Token only required when needed (HTTPS without git credentials)
- **Multiple URL Formats** - HTTPS, SSH, short form (org/repo), local paths

## Quick Start

### GitHub Action Usage

```yaml
steps:
  - uses: actions/checkout@v4
    with:
      fetch-depth: 0  # Required for git history

  - name: Push to dedicated repository
    uses: ./.github/actions/push-monorepo
    with:
      local: "packages/api"
      remote: "https://github.com/org/api-repo.git"
      branch: "main"
      token: ${{ secrets.GITHUB_TOKEN }}
      author: "GitHub Actions <actions@github.com>"
```

### Command Line Usage

```bash
# Show help
./scripts/push.sh --help

# Basic usage with token
./scripts/push.sh "packages/api" "https://github.com/org/api-repo.git" \
  --branch "main" \
  --token "ghp_xxxxxxxxxxxx"

# SSH (no token needed)
./scripts/push.sh "packages/api" "git@github.com:org/api-repo.git" \
  --branch "main"

# Minimal (auto-detect branch and author)
./scripts/push.sh "packages/api" "https://github.com/org/api-repo.git"
```

## Usage Examples

### Basic Example - HTTPS with Token

```yaml
- name: Push to dedicated repository
  uses: ./.github/actions/push-monorepo
  with:
    local: "packages/api"
    remote: "https://github.com/org/api-repo.git"
    branch: "main"
    token: ${{ secrets.GITHUB_TOKEN }}
    author: "Your Name <your@email.com>"
```

### Minimal Example - Auto-detect Branch and Author

The action can auto-detect the branch and use git config for author:

```yaml
- name: Push to dedicated repository
  uses: ./.github/actions/push-monorepo
  with:
    local: "packages/api"
    remote: "https://github.com/org/api-repo.git"
    token: ${{ secrets.GITHUB_TOKEN }}
```

Branch detection sources (in order):
1. `branch` input parameter
2. `GITHUB_HEAD_REF` (for pull requests)
3. `GITHUB_REF` (for pushes and tags)
4. Remote repository default branch

### SSH Example - No Token Required

```yaml
- name: Push to dedicated repository
  uses: ./.github/actions/push-monorepo
  with:
    local: "packages/api"
    remote: "git@github.com:org/api-repo.git"
    branch: "main"
```

### Matrix Strategy - Multiple Folders in Parallel

Sync multiple folders simultaneously using GitHub Actions matrix:

```yaml
name: Sync Monorepo Folders

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  sync-folders:
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false  # Continue even if one folder fails
      matrix:
        folder:
          - local: "packages/api"
            remote: "https://github.com/my-org/api.git"
          - local: "packages/frontend"
            remote: "https://github.com/my-org/frontend.git"
          - local: "packages/shared"
            remote: "git@github.com:my-org/shared.git"  # SSH
          - local: "services/auth"
            remote: "https://github.com/my-org/auth-service.git"

    steps:
      - name: Checkout with full history
        uses: actions/checkout@v4
        with:
          fetch-depth: 0  # Required for git subtree split

      - name: Sync ${{ matrix.folder.local }} to dedicated repo
        uses: ./.github/actions/push-monorepo
        with:
          local: ${{ matrix.folder.local }}
          remote: ${{ matrix.folder.remote }}
          branch: ${{ github.head_ref || github.ref_name }}
          token: ${{ secrets.GITHUB_TOKEN }}
          author: "Monorepo Bot <bot@example.com>"
```

### Pull Request Support

```yaml
- name: Push to dedicated repository
  uses: ./.github/actions/push-monorepo
  with:
    local: "packages/api"
    remote: "https://github.com/org/api-repo.git"
    branch: ${{ github.head_ref || github.ref_name }}
    token: ${{ secrets.GITHUB_TOKEN }}
    author: "Your Name <your@email.com>"
```

### Command Line Usage

The script can also be run directly from the command line:

```bash
# Show help and all options
./scripts/push.sh --help

# Basic usage
./scripts/push.sh "packages/api" "https://github.com/org/repo.git"

# With all options
./scripts/push.sh "packages/api" "org/repo" \
  --branch "main" \
  --token "ghp_xxxx" \
  --author "Name <email>"

# Using short flags
./scripts/push.sh "packages/api" "org/repo" -b "main" -t "ghp_xxxx" -a "Name <email>"
```

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `local` | Local folder path to sync (e.g., "packages/api") | Yes | - |
| `remote` | Target repository URL (HTTPS, SSH, or local path) | Yes | - |
| `branch` | Branch name to push to (auto-detected if not provided) | No | `""` |
| `token` | GitHub authentication token (optional for SSH URLs) | No | `""` |
| `author` | Git author in format "Name <email>" (uses git config if not provided) | No | `""` |

## Outputs

| Output | Description | Example |
|--------|-------------|---------|
| `pushed` | Boolean indicating if push occurred | `"true"` or `"false"` |
| `skipped` | Boolean indicating if skipped due to no changes | `"true"` or `"false"` |

## How It Works

The action performs an intelligent sync in 8 steps:

### 1. Argument Parsing & Validation
   - Parses positional arguments (LOCAL, REMOTE)
   - Processes optional flags (--branch, --token, --author)
   - Validates folder exists locally
   - Verifies required parameters are present

### 2. Branch Detection
   Auto-detects target branch from multiple sources:
   - Provided `--branch` parameter (highest priority)
   - `GITHUB_HEAD_REF` for pull requests
   - `GITHUB_REF` for pushes and tags
   - Remote repository default branch (fallback)

### 3. Change Detection
   Intelligently detects if folder has changes:
   - **Push events**: `git diff HEAD^ HEAD --name-only | grep "^folder/"`
   - **Pull requests**: `git diff origin/base...HEAD --name-only | grep "^folder/"`
   - **First commit**: `git ls-tree -r HEAD --name-only | grep "^folder/"`
   - **Tag push**: `git ls-tree -r HEAD --name-only | grep "^folder/"`
   - **Skips** if no changes detected (exits successfully)

### 4. Git Configuration
   - Uses provided author or falls back to git config
   - Sets `user.name` and `user.email` for commits
   - Default: "GitHub Action <action@github.com>"

### 5. Subtree Split
   Extracts folder history into temporary branch:
   ```bash
   git subtree split --prefix=<folder> -b temp-split-<folder>
   ```
   This creates a new branch containing only the folder's commits

### 6. Remote Setup
   Adds target repository with appropriate authentication:
   - **HTTPS with token**: `https://x-access-token:TOKEN@github.com/org/repo.git`
   - **HTTPS without token**: `https://github.com/org/repo.git` (uses git credentials)
   - **SSH**: `git@github.com:org/repo.git` (uses SSH keys)
   - **Local**: `/path/to/repo` (direct path)

### 7. Push
   Pushes split branch using safe force:
   ```bash
   git push target-repo temp-split-folder:branch --force-with-lease
   ```
   `--force-with-lease` prevents overwriting unexpected remote changes

### 8. Cleanup
   Removes temporary resources:
   - Deletes temporary split branch
   - Removes temporary remote
   - Always executes, even on failure

## Change Detection Logic

### Push Events
```bash
# Compares current commit with previous commit
git diff HEAD^ HEAD --name-only | grep "^packages/api/"
```

### Pull Request Events
```bash
# Compares PR head with base branch
git diff origin/main...HEAD --name-only | grep "^packages/api/"
```

### First Commit
```bash
# Lists all files in the commit
git ls-tree -r HEAD --name-only | grep "^packages/api/"
```

### Tag Push
```bash
# Checks if folder has any files at the tagged commit
git ls-tree -r HEAD --name-only | grep "^packages/api/"
```

## Error Handling

The tool handles various scenarios gracefully:

### Successful Scenarios
- **No Changes Detected**: Skips push, sets `skipped=true`, exits with code 0
- **Branch Doesn't Exist**: Creates new branch in target repository automatically
- **Empty Token for SSH**: Continues without token (SSH doesn't need it)

### Error Scenarios

| Scenario | Behavior | Exit Code |
|----------|----------|-----------|
| Missing required arguments | Shows error and usage hint | 1 |
| Folder doesn't exist | Validation error with clear message | 1 |
| Authentication failure | Git push fails with auth error | 1 |
| Network issues | Git operation timeout/failure | 1 |
| Remote state changed | `--force-with-lease` prevents push | 1 |
| Branch protection rules | Push rejected by remote | 1 |
| Invalid git operation | Git error with stderr output | 1 |
| Subtree split failure | Clear error message | 1 |

### Safety Features
- **Bash Strict Mode**: `set -euo pipefail` catches errors immediately
- **Input Validation**: All parameters validated before operations
- **Safe Force Push**: Uses `--force-with-lease` instead of `--force`
- **Token Security**: Tokens never logged or exposed in output
- **Cleanup Guarantee**: Temporary branches/remotes removed even on failure
- **No Destructive Changes**: Original repository never modified

## Requirements

### Mandatory
- **Git Repository**: Must be run within a git repository
- **Full History**: Requires `fetch-depth: 0` for subtree split to work
- **Git 2.0+**: Git version 2.0 or higher with subtree split support
- **Bash 4.0+**: Bash shell with support for arrays and associative arrays
- **Target Folder**: Folder must exist in the repository

### Authentication (choose one)

#### HTTPS with Token
- Provide `token` parameter with a GitHub personal access token
- Token must have `repo` scope and push access to target repository
- Used in GitHub Actions: `${{ secrets.GITHUB_TOKEN }}`

#### HTTPS with Git Credentials
- Configure git credential helpers
- No token parameter needed
- Example: `git config credential.helper store`

#### SSH
- SSH keys configured in `~/.ssh/` or SSH agent
- No token parameter needed
- GitHub SSH key must be added to account/deploy keys

#### Local Repositories
- Direct file system access
- No authentication needed
- Useful for testing

### Permissions
- **Source repository**: Read access (to clone/fetch)
- **Target repository**: Write access (to push)
- **Branch protection**: May require additional permissions or bypass rules

## Security

### Token Protection
- **URL Format**: Uses `x-access-token:TOKEN` format (GitHub recommended)
- **No Logging**: Tokens never appear in logs or stderr
- **Ephemeral**: Token only used during push operation
- **Git Config**: Token never stored in git config
- **Memory Only**: Token stored in shell variables, not on disk

### Safe Push Strategy
- **Force with Lease**: Uses `--force-with-lease` instead of `--force`
  - Prevents overwriting unexpected remote changes
  - Fails if remote has been updated by someone else
  - Safer than blind force push
- **Temporary Branches**: Uses temporary local branches (auto-cleaned)
- **Read-Only Source**: Source repository never modified

### Input Validation
- **Path Sanitization**: Validates folder paths to prevent traversal
- **URL Validation**: Checks remote URL format
- **Parameter Validation**: Ensures required parameters present
- **No Code Injection**: All inputs passed as parameters, not evaluated

### Best Practices
1. **Use Fine-Grained PATs**: Limit token scope to specific repositories
2. **Store in Secrets**: Never hardcode tokens in workflow files
3. **Rotate Regularly**: Update tokens periodically
4. **SSH Preferred**: Use SSH URLs when possible (more secure)
5. **Branch Protection**: Enable branch protection on target repositories
6. **Audit Logs**: Monitor GitHub audit logs for push activity

### Compliance
- **OWASP Top 10**: Validates inputs to prevent injection attacks
- **Least Privilege**: Token only needs push access, nothing more
- **No External Dependencies**: Pure bash, no third-party code
- **Open Source**: Full source code available for audit

## Performance

### Execution Time

Typical execution times (depends on repository size and network):

| Operation | Time | Notes |
|-----------|------|-------|
| Change detection | 0.1-0.5s | Fast - only diffs specific folder |
| No changes (skip) | 0.5-1s | Minimal overhead |
| Subtree split | 1-30s | Depends on folder history size |
| Push to remote | 1-10s | Depends on network and commit count |
| Full workflow | 5-45s | End-to-end with changes |

### Optimization Tips

1. **Matrix Strategy**: Run multiple folders in parallel
   ```yaml
   strategy:
     matrix:
       folder: [api, frontend, backend]
   ```

2. **Conditional Execution**: Only run on specific paths
   ```yaml
   on:
     push:
       paths:
         - 'packages/**'
   ```

3. **Shallow Clone for Detection**: Use shallow for detection, full for push
   ```yaml
   # First job: detect changes (fast)
   - uses: actions/checkout@v4
     with:
       fetch-depth: 1

   # Second job: full clone and push (only if needed)
   - uses: actions/checkout@v4
     with:
       fetch-depth: 0
   ```

4. **Reuse Checkout**: One checkout for multiple syncs
   ```yaml
   - uses: actions/checkout@v4
     with:
       fetch-depth: 0

   - name: Sync API
     uses: ./.github/actions/push-monorepo
     with:
       local: "packages/api"
       # ...

   - name: Sync Frontend
     uses: ./.github/actions/push-monorepo
     with:
       local: "packages/frontend"
       # ...
   ```

### Scaling

- **Small folders** (< 100 commits): ~5 seconds
- **Medium folders** (100-1000 commits): ~15 seconds
- **Large folders** (1000+ commits): ~30-45 seconds
- **Parallel jobs**: Near-linear scaling with matrix strategy

## Reusability

### Option 1: Local Action (Recommended for Single Repo)

Copy the action into your repository:

```bash
# In your monorepo
mkdir -p .github/actions
cp -r /path/to/split-push .github/actions/push-monorepo

# Use in workflow
- uses: ./.github/actions/push-monorepo
  with:
    local: "packages/api"
    remote: "https://github.com/org/api.git"
    token: ${{ secrets.GITHUB_TOKEN }}
```

**Pros**: Easy to customize, no external dependencies, works offline
**Cons**: Need to update each repository separately

### Option 2: Composite Action in Another Repo

Reference from another repository:

```yaml
- uses: your-org/monorepo-tools/.github/actions/push-monorepo@v1
  with:
    local: "packages/api"
    remote: "https://github.com/org/api.git"
    token: ${{ secrets.GITHUB_TOKEN }}
```

**Pros**: Centralized updates, version control
**Cons**: Requires public repo or GitHub Enterprise

### Option 3: Published GitHub Action

Publish to GitHub Marketplace:

```yaml
- uses: your-org/push-monorepo-folder@v1
  with:
    local: "packages/api"
    remote: "https://github.com/org/api.git"
    token: ${{ secrets.GITHUB_TOKEN }}
```

**Pros**: Discoverable, semantic versioning, public reuse
**Cons**: Requires dedicated repository

### Option 4: CLI Script Only

Use the bash script directly (no GitHub Actions):

```bash
# Install
curl -o push.sh https://raw.githubusercontent.com/org/split-push/main/scripts/push.sh
chmod +x push.sh

# Use in any CI/CD
./push.sh "packages/api" "https://github.com/org/api.git" \
  --branch "main" \
  --token "$GITHUB_TOKEN"
```

**Pros**: Works in any CI/CD (GitLab, CircleCI, Jenkins)
**Cons**: No GitHub Actions integration

## Advanced Usage

### Conditional Execution Based on Output

Use the action's outputs to trigger subsequent steps:

```yaml
- name: Sync folder
  id: sync
  uses: ./.github/actions/push-monorepo
  with:
    local: "packages/api"
    remote: "https://github.com/org/api.git"
    token: ${{ secrets.GITHUB_TOKEN }}

- name: Notify on push
  if: steps.sync.outputs.pushed == 'true'
  run: |
    echo "Changes were pushed to api repository"
    # Send notification, trigger deployment, etc.

- name: Notify on skip
  if: steps.sync.outputs.skipped == 'true'
  run: |
    echo "No changes detected, push was skipped"
```

### Custom Branch Strategies

```yaml
# Push to environment-specific branches
- name: Sync to staging
  uses: ./.github/actions/push-monorepo
  with:
    local: "packages/api"
    remote: "https://github.com/org/api.git"
    branch: "staging"
    token: ${{ secrets.GITHUB_TOKEN }}

# Use PR number in branch name
- name: Sync to PR branch
  uses: ./.github/actions/push-monorepo
  with:
    local: "packages/api"
    remote: "https://github.com/org/api.git"
    branch: "pr-${{ github.event.pull_request.number }}"
    token: ${{ secrets.GITHUB_TOKEN }}

# Mirror branch structure
- name: Sync to matching branch
  uses: ./.github/actions/push-monorepo
  with:
    local: "packages/api"
    remote: "https://github.com/org/api.git"
    branch: ${{ github.ref_name }}
    token: ${{ secrets.GITHUB_TOKEN }}
```

### Multiple Remotes

Sync same folder to multiple destinations:

```yaml
- name: Sync to GitHub
  uses: ./.github/actions/push-monorepo
  with:
    local: "packages/api"
    remote: "https://github.com/org/api.git"
    token: ${{ secrets.GITHUB_TOKEN }}

- name: Sync to GitLab
  uses: ./.github/actions/push-monorepo
  with:
    local: "packages/api"
    remote: "https://gitlab.com/org/api.git"
    token: ${{ secrets.GITLAB_TOKEN }}

- name: Sync to Bitbucket
  uses: ./.github/actions/push-monorepo
  with:
    local: "packages/api"
    remote: "https://bitbucket.org/org/api.git"
    token: ${{ secrets.BITBUCKET_TOKEN }}
```

### Integration with Other Actions

```yaml
- name: Sync folder
  id: sync
  uses: ./.github/actions/push-monorepo
  with:
    local: "packages/api"
    remote: "https://github.com/org/api.git"
    token: ${{ secrets.GITHUB_TOKEN }}

- name: Trigger deployment
  if: steps.sync.outputs.pushed == 'true'
  uses: peter-evans/repository-dispatch@v2
  with:
    token: ${{ secrets.PAT }}
    repository: org/api
    event-type: deploy
    client-payload: |
      {
        "ref": "${{ github.ref }}",
        "sha": "${{ github.sha }}"
      }

- name: Create release
  if: startsWith(github.ref, 'refs/tags/')
  uses: softprops/action-gh-release@v1
  with:
    repository: org/api
    token: ${{ secrets.PAT }}
```

### Debugging and Testing

```yaml
# Test mode - push to test repository
- name: Test sync
  if: github.event_name == 'pull_request'
  uses: ./.github/actions/push-monorepo
  with:
    local: "packages/api"
    remote: "https://github.com/org/api-test.git"  # Test repo
    branch: "test-${{ github.event.pull_request.number }}"
    token: ${{ secrets.GITHUB_TOKEN }}

# Dry run - detect changes without pushing
- name: Check for changes
  run: |
    if git diff HEAD^ HEAD --name-only | grep "^packages/api/"; then
      echo "Changes detected in packages/api"
      echo "would_push=true" >> $GITHUB_OUTPUT
    fi
  id: check

# Real push only on main
- name: Sync to production
  if: github.ref == 'refs/heads/main' && steps.check.outputs.would_push == 'true'
  uses: ./.github/actions/push-monorepo
  with:
    local: "packages/api"
    remote: "https://github.com/org/api.git"
    token: ${{ secrets.GITHUB_TOKEN }}
```

## Example Workflows

Complete workflow examples for common scenarios:

### Single Folder Sync

```yaml
name: Sync API Package

on:
  push:
    branches: [main]
    paths:
      - 'packages/api/**'

jobs:
  sync:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Sync API to dedicated repo
        uses: ./.github/actions/push-monorepo
        with:
          local: "packages/api"
          remote: "https://github.com/my-org/api.git"
          branch: "main"
          token: ${{ secrets.GITHUB_TOKEN }}
          author: "API Bot <bot@example.com>"
```

### Multi-Folder Matrix

```yaml
name: Sync All Packages

on:
  push:
    branches: [main, develop]

jobs:
  sync:
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        package:
          - { local: "packages/api", remote: "api" }
          - { local: "packages/web", remote: "web" }
          - { local: "packages/mobile", remote: "mobile" }
          - { local: "packages/shared", remote: "shared" }

    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Sync ${{ matrix.package.local }}
        uses: ./.github/actions/push-monorepo
        with:
          local: ${{ matrix.package.local }}
          remote: "https://github.com/my-org/${{ matrix.package.remote }}.git"
          branch: ${{ github.ref_name }}
          token: ${{ secrets.GITHUB_TOKEN }}
```

### PR Preview

```yaml
name: PR Preview Sync

on:
  pull_request:
    types: [opened, synchronize]

jobs:
  preview:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Sync to preview branch
        uses: ./.github/actions/push-monorepo
        with:
          local: "packages/api"
          remote: "https://github.com/my-org/api.git"
          branch: "preview-pr-${{ github.event.pull_request.number }}"
          token: ${{ secrets.GITHUB_TOKEN }}
          author: "Preview Bot <preview@example.com>"

      - name: Comment PR
        uses: actions/github-script@v7
        with:
          script: |
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: '🚀 Preview deployed to branch `preview-pr-${{ github.event.pull_request.number }}`'
            })
```

## Troubleshooting

### Changes Not Detected

**Symptom**: Action runs but skips push with "No changes detected"

**Solutions**:
1. **Check fetch-depth**: Ensure `fetch-depth: 0` in checkout step
   ```yaml
   - uses: actions/checkout@v4
     with:
       fetch-depth: 0  # This is required!
   ```

2. **Verify folder path**: Path must match exactly (case-sensitive)
   ```bash
   # Check folder exists
   ls -la packages/api

   # Verify path in action
   local: "packages/api"  # Must match exactly
   ```

3. **Check for actual changes**: Verify commits touch the folder
   ```bash
   git diff HEAD^ HEAD --name-only | grep "^packages/api/"
   ```

4. **First commit issue**: For first commit in monorepo, ensure folder has files
   ```bash
   git ls-tree -r HEAD --name-only | grep "^packages/api/"
   ```

### Authentication Errors

**Symptom**: `fatal: Authentication failed` or `Permission denied`

**For HTTPS URLs**:
1. **Verify token is set**:
   ```yaml
   token: ${{ secrets.GITHUB_TOKEN }}  # Check secret exists
   ```

2. **Check token permissions**:
   - Go to Settings → Actions → General → Workflow permissions
   - Ensure "Read and write permissions" is enabled
   - Or use a Personal Access Token with `repo` scope

3. **Token expiration**: PATs expire, GITHUB_TOKEN is per-workflow
   ```bash
   # Test token manually
   curl -H "Authorization: token $TOKEN" https://api.github.com/user
   ```

**For SSH URLs**:
1. **Check SSH keys**:
   ```bash
   ssh -T git@github.com  # Should show authentication success
   ```

2. **Deploy keys**: Ensure deploy key has write access
   - Repository → Settings → Deploy keys
   - Check "Allow write access"

3. **SSH agent**: For local testing
   ```bash
   eval "$(ssh-agent -s)"
   ssh-add ~/.ssh/id_rsa
   ```

### Push Failures

**Symptom**: `error: failed to push some refs`

**Common causes**:

1. **Branch protection rules**:
   - Check repository → Settings → Branches
   - Bypass protection rules or add exception
   - Use a bot account with bypass permissions

2. **Force-with-lease rejection**:
   ```
   error: failed to push some refs to 'https://github.com/org/repo.git'
   hint: Updates were rejected because the remote contains work that you do
   hint: not have locally.
   ```
   - Someone pushed to target repo between fetch and push
   - Run action again (it will fetch latest)
   - Consider using a dedicated sync branch

3. **Network issues**:
   ```bash
   # Test connectivity
   curl -I https://github.com

   # Check git connectivity
   git ls-remote https://github.com/org/repo.git
   ```

### Git Subtree Split Errors

**Symptom**: `fatal: ambiguous argument 'HEAD^': unknown revision`

**Solution**: This is the first commit, which is handled automatically
- The action detects this and uses `git ls-tree` instead
- Ensure folder has files: `git ls-tree -r HEAD --name-only | grep "^folder/"`

**Symptom**: `fatal: Could not get sha1 for prefix 'packages/api'`

**Solution**: Folder doesn't exist or path is wrong
```bash
# Check folder exists
ls -la packages/api

# Verify git knows about it
git ls-tree HEAD packages/api
```

### Common Mistakes

1. **Missing fetch-depth: 0**
   - Most common issue
   - Shallow clone breaks subtree split
   - Always use `fetch-depth: 0`

2. **Wrong folder path**
   ```yaml
   # ❌ Wrong
   local: "/packages/api"     # Don't use leading slash
   local: "packages/api/"     # Don't use trailing slash

   # ✓ Correct
   local: "packages/api"
   ```

3. **Token in wrong place**
   ```yaml
   # ❌ Wrong
   remote: "https://TOKEN@github.com/org/repo.git"

   # ✓ Correct
   remote: "https://github.com/org/repo.git"
   token: ${{ secrets.GITHUB_TOKEN }}
   ```

4. **Using GITHUB_TOKEN for different org**
   - GITHUB_TOKEN only works for same organization
   - Use PAT for cross-organization pushes

### Debug Mode

Enable debug logging in GitHub Actions:

1. **Repository secrets**:
   - Add secret: `ACTIONS_STEP_DEBUG` = `true`
   - Add secret: `ACTIONS_RUNNER_DEBUG` = `true`

2. **Re-run workflow** to see detailed logs

3. **Check logs** for:
   - Exact git commands executed
   - URL formats (token will be redacted)
   - Change detection output
   - Branch detection logic

### Getting Help

If you're still stuck:

1. **Check the logs**: Read the full action output
2. **Run locally**: Test with `./scripts/push.sh --help`
3. **Verify git**: Ensure git 2.0+ is installed
4. **Test manually**: Try git commands manually
5. **Open an issue**: Include logs and minimal reproduction

## Development

### Project Structure

```
split-push/
├── action.yml                           # GitHub Action definition
├── CLAUDE.md                            # Development documentation
├── README.md                            # User documentation
├── scripts/
│   ├── push.sh                         # Main CLI script (370+ lines)
│   │                                   # - Argument parsing with --help
│   │                                   # - Main workflow orchestration
│   │                                   # - All core functions
│   └── lib/
│       ├── logging.sh                  # Logging library
│       │                               # - Colored output (info/success/warning/error)
│       │                               # - All output to stderr (preserves stdout)
│       └── detect-changes.sh           # Change detection library
│                                       # - Branch auto-detection
│                                       # - Change detection (push/PR/tag/first commit)
│                                       # - Remote default branch query
├── tests/
│   ├── unit/                           # Unit tests (54 tests)
│   │   ├── test_helper.bash           # Test utilities and mock functions
│   │   ├── detect-changes.bats        # Change detection tests (19 tests)
│   │   ├── parse-functions.bats       # URL/author parsing tests (15 tests)
│   │   └── git-operations.bats        # Git operations tests (20 tests)
│   ├── integration/                    # Integration tests (9 tests)
│   │   └── test-repository.bats       # End-to-end workflow tests
│   └── run-tests.sh                    # Test runner script
└── .github/workflows/
    └── test.yml                        # CI/CD test workflow
```

### Test Coverage

**63 Total Tests** - 100% Pass Rate ✓

- **54 Unit Tests** - Individual function testing
  - Argument parsing and validation
  - Change detection logic
  - URL and author parsing
  - Git operations (split, push, cleanup)
  - Remote setup and configuration
  - Output generation

- **9 Integration Tests** - End-to-end workflows
  - Complete push workflow with changes
  - Skip when no changes detected
  - First commit workflow
  - Tag push workflow
  - Pull request workflow
  - Error handling (missing folder, no token needed)
  - Deeply nested folders
  - Cleanup verification

### Running Tests

Comprehensive test coverage using BATS (Bash Automated Testing System).

#### Install Dependencies

```bash
# macOS
brew install bats-core

# Linux (Debian/Ubuntu)
sudo apt-get install bats

# Linux (via npm)
sudo npm install -g bats

# Install BATS support libraries (required)
git clone https://github.com/bats-core/bats-support.git test_helper/bats-support
git clone https://github.com/bats-core/bats-assert.git test_helper/bats-assert
```

#### Run Tests

```bash
# Run all tests (recommended)
./tests/run-tests.sh

# Output:
# ✓ Unit tests passed (54 tests)
# ✓ Integration tests passed (9 tests)
# All tests passed!

# Run specific test suite
bats tests/unit/*.bats                    # All unit tests
bats tests/integration/*.bats             # All integration tests

# Run individual test file
bats tests/unit/detect-changes.bats       # Change detection tests
bats tests/unit/parse-functions.bats      # Parsing tests
bats tests/unit/git-operations.bats       # Git operation tests
bats tests/integration/test-repository.bats  # Integration tests

# Run with filter
bats tests/unit/detect-changes.bats --filter "pull request"

# Show output even for passing tests
bats tests/unit/detect-changes.bats --show-output-of-passing-tests
```

#### Test Structure

**Unit Tests** (`tests/unit/`)
- Mock git commands to isolate function behavior
- Test individual functions in isolation
- Fast execution (~2 seconds)
- No actual git operations

**Integration Tests** (`tests/integration/`)
- Create real git repositories
- Perform actual git operations
- Test end-to-end workflows
- Slower execution (~5 seconds)
- Verify actual push results

**Test Helper** (`tests/unit/test_helper.bash`)
- Common setup/teardown functions
- Mock function generators
- GitHub environment simulators
- Assertion helpers

### Code Quality

**Shellcheck linting:**
```bash
# Install shellcheck
brew install shellcheck  # macOS
sudo apt-get install shellcheck  # Linux

# Run linter
shellcheck scripts/push.sh
shellcheck scripts/lib/detect-changes.sh
```

**Action validation:**
```bash
# Install actionlint
brew install actionlint

# Validate action.yml
actionlint action.yml
```

### Testing Locally

Test the script manually with a local repository:

```bash
# Display help and see all options
./scripts/push.sh --help

# Full options
./scripts/push.sh \
  "path/to/folder" \
  "https://github.com/org/repo.git" \
  --branch "main" \
  --token "github_token" \
  --author "Your Name <your@email.com>"

# Minimal (auto-detect branch, use git config for author)
./scripts/push.sh "path/to/folder" "https://github.com/org/repo.git"

# SSH URL (no token needed)
./scripts/push.sh "path/to/folder" "git@github.com:org/repo.git" --branch "main"

# Using short flags
./scripts/push.sh "packages/api" "org/repo" -b "main" -t "token" -a "Name <email>"
```

### CI/CD

Tests run automatically on every push and pull request:
- Unit tests validate individual functions
- Integration tests verify end-to-end workflows
- Shellcheck ensures code quality

See `.github/workflows/test.yml` for CI configuration.

## Comparison with Alternatives

### vs. Git Submodules
- **Submodules**: Reference external repos, don't preserve history independently
- **This tool**: Extracts folder with full history, creates independent repos
- **Use this when**: You want to split a monorepo into separate repos

### vs. Git Filter-Branch
- **Filter-branch**: Rewrites entire repository history (dangerous, slow)
- **This tool**: Non-destructive, only creates new branch, preserves original
- **Use this when**: You need safe, repeatable syncing

### vs. Manual git subtree split
- **Manual**: Requires multiple git commands, error-prone, hard to maintain
- **This tool**: Automated, tested, handles edge cases
- **Use this when**: You want reliable, automated syncing in CI/CD

### vs. Monorepo Tools (Nx, Turborepo)
- **Monorepo tools**: Build systems, don't sync to external repos
- **This tool**: Complements them, syncs outputs to dedicated repos
- **Use both when**: You want monorepo benefits + independent package repos

## Limitations

- **Requires full git history**: `fetch-depth: 0` needed (can slow down checkout)
- **Force push required**: Uses `--force-with-lease` (generally safe but force nonetheless)
- **GitHub Actions only**: Action wrapper only works in GitHub Actions (script works anywhere)
- **No merge commits**: Subtree split creates linear history
- **One-way sync**: Pushes from monorepo to dedicated repos (not bidirectional)

## Roadmap

Future improvements under consideration:

- [ ] Bidirectional sync support
- [ ] Dry-run mode with detailed change preview
- [ ] Webhook integration for external CI/CD
- [ ] Custom commit message templates
- [ ] Tag synchronization options
- [ ] Branch cleanup automation
- [ ] Performance metrics and reporting
- [ ] Docker container action (faster startup)
- [ ] More authentication methods (App tokens, OIDC)

## Contributing

Contributions are welcome! This project uses:

- **Bash 4.0+** for scripting
- **BATS** for testing
- **Shellcheck** for linting
- **GitHub Actions** for CI/CD

### Development Workflow

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Run test suite: `./tests/run-tests.sh`
6. Run shellcheck: `shellcheck scripts/push.sh`
7. Submit a pull request

### Reporting Issues

When reporting issues, please include:

- Operating system and version
- Git version (`git --version`)
- Bash version (`bash --version`)
- Full error message and logs
- Minimal reproduction steps
- Expected vs actual behavior

## License

MIT License - see LICENSE file for details

## Author

**Lorenzo Dessimoni**

## Acknowledgments

- Git subtree split documentation
- BATS testing framework
- GitHub Actions community
- All contributors

## Support

- 📖 **Documentation**: Read this README and CLAUDE.md
- 🐛 **Bug Reports**: Open an issue on GitHub
- 💡 **Feature Requests**: Open an issue with [Feature Request] prefix
- 💬 **Questions**: Open a discussion on GitHub
- ⭐ **Show Support**: Star the repository if you find it useful
