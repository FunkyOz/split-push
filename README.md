# Split and Push from a Monorepo to Dedicated Repositories

A GitHub Action and standalone CLI tool that syncs monorepo folders to dedicated repositories using git subtree split. Detects changes in specific folders and pushes only when changes are found, preserving complete git history.

[![Tests](https://img.shields.io/badge/tests-63%20passed-success)](./tests)
[![Coverage](https://img.shields.io/badge/coverage-100%25-success)](./tests)
[![Bash](https://img.shields.io/badge/bash-4.0+-blue)](./scripts)
[![License](https://img.shields.io/badge/license-MIT-blue)](./LICENSE)

## At a Glance

```bash
# GitHub Action
- uses: FunkyOz/split-push@v1
  with:
    local: "packages/api"
    remote: "https://github.com/org/api-repo.git"
    token: ${{ secrets.GITHUB_TOKEN }}

# CLI
./scripts/push.sh "packages/api" "org/api-repo" --branch "main"
```

## Quick Start

### GitHub Action

```yaml
steps:
  - uses: actions/checkout@v4
    with:
      fetch-depth: 0  # Required for git history

  - name: Push to dedicated repository
    uses: FunkyOz/split-push@v1
    with:
      local: "packages/api"
      remote: "https://github.com/org/api-repo.git"
      branch: "main"
      token: ${{ secrets.GITHUB_TOKEN }}
      author: "GitHub Actions <actions@github.com>"
```

### CLI

```bash
./scripts/push.sh --help

# HTTPS with token
./scripts/push.sh "packages/api" "https://github.com/org/api-repo.git" \
  --branch "main" --token "ghp_xxxxxxxxxxxx"

# SSH (no token needed)
./scripts/push.sh "packages/api" "git@github.com:org/api-repo.git" --branch "main"

# Minimal (auto-detect branch and author)
./scripts/push.sh "packages/api" "https://github.com/org/api-repo.git"
```

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `local` | Local folder path to sync (e.g., "packages/api") | Yes | - |
| `remote` | Target repository URL (HTTPS, SSH, or local path) | Yes | - |
| `branch` | Branch name to push to (auto-detected if not provided) | No | `""` |
| `token` | GitHub authentication token (optional for SSH URLs) | No | `""` |
| `author` | Git author in format "Name \<email\>" (uses git config if not provided) | No | `""` |

## Outputs

| Output | Description | Example |
|--------|-------------|---------|
| `pushed` | Boolean indicating if push occurred | `"true"` or `"false"` |
| `skipped` | Boolean indicating if skipped due to no changes | `"true"` or `"false"` |

## Usage Examples

### Matrix Strategy - Multiple Folders in Parallel

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
      fail-fast: false
      matrix:
        folder:
          - local: "packages/api"
            remote: "https://github.com/my-org/api.git"
          - local: "packages/frontend"
            remote: "https://github.com/my-org/frontend.git"
          - local: "packages/shared"
            remote: "git@github.com:my-org/shared.git"

    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Sync ${{ matrix.folder.local }}
        uses: FunkyOz/split-push@v1
        with:
          local: ${{ matrix.folder.local }}
          remote: ${{ matrix.folder.remote }}
          branch: ${{ github.head_ref || github.ref_name }}
          token: ${{ secrets.GITHUB_TOKEN }}
```

### Conditional Execution Based on Output

```yaml
- name: Sync folder
  id: sync
  uses: FunkyOz/split-push@v1
  with:
    local: "packages/api"
    remote: "https://github.com/org/api.git"
    token: ${{ secrets.GITHUB_TOKEN }}

- name: Notify on push
  if: steps.sync.outputs.pushed == 'true'
  run: echo "Changes were pushed to api repository"

- name: Notify on skip
  if: steps.sync.outputs.skipped == 'true'
  run: echo "No changes detected, push was skipped"
```

### Custom Branch Strategies

```yaml
# Push to environment-specific branches
- name: Sync to staging
  uses: FunkyOz/split-push@v1
  with:
    local: "packages/api"
    remote: "https://github.com/org/api.git"
    branch: "staging"
    token: ${{ secrets.GITHUB_TOKEN }}

# Mirror branch structure
- name: Sync to matching branch
  uses: FunkyOz/split-push@v1
  with:
    local: "packages/api"
    remote: "https://github.com/org/api.git"
    branch: ${{ github.ref_name }}
    token: ${{ secrets.GITHUB_TOKEN }}
```

### Multiple Remotes

```yaml
- name: Sync to GitHub
  uses: FunkyOz/split-push@v1
  with:
    local: "packages/api"
    remote: "https://github.com/org/api.git"
    token: ${{ secrets.GITHUB_TOKEN }}

- name: Sync to GitLab
  uses: FunkyOz/split-push@v1
  with:
    local: "packages/api"
    remote: "https://gitlab.com/org/api.git"
    token: ${{ secrets.GITLAB_TOKEN }}
```

## How It Works

### 1. Argument Parsing & Validation
Parses positional arguments (`LOCAL`, `REMOTE`) and optional flags (`--branch`, `--token`, `--author`). Validates the folder exists locally.

### 2. Branch Detection
Auto-detects the target branch (priority order):
1. `--branch` parameter
2. `GITHUB_REF` tag detection (for tag pushes)
3. `GITHUB_HEAD_REF` (for pull requests)
4. `GITHUB_REF` branch extraction (for push events)
5. Remote repository default branch (fallback)

### 3. Change Detection
Checks if the folder has changes before proceeding:
- **Push events**: `git diff HEAD^ HEAD --name-only | grep "^folder/"`
- **Pull requests**: `git diff origin/base...HEAD --name-only | grep "^folder/"`
- **First commit / Tags**: `git ls-tree -r HEAD --name-only | grep "^folder/"`

Skips the push if no changes are detected (exits successfully).

### 4. Git Configuration
Uses the provided `--author` or falls back to git config, then to `"GitHub Action <action@github.com>"`.

### 5. Subtree Split
Extracts folder history into a temporary branch:
```bash
git subtree split --prefix=<folder> -b temp-split-<folder>
```

### 6. Remote Setup
Adds the target repository with appropriate authentication:
- **HTTPS with token**: `https://x-access-token:TOKEN@github.com/org/repo.git`
- **HTTPS without token**: `https://github.com/org/repo.git`
- **SSH**: `git@github.com:org/repo.git`
- **Local**: `/path/to/repo`

### 7. Push
```bash
git push target-repo temp-split-folder:branch --force-with-lease
```
Uses `--force-with-lease` to prevent overwriting unexpected remote changes.

### 8. Cleanup
Removes temporary branches and remotes regardless of success or failure.

## Requirements

- **Git 2.0+** with subtree split support
- **Bash 4.0+**
- **Full git history**: Requires `fetch-depth: 0` in GitHub Actions
- **Target folder** must exist in the repository
- **Write access** to the target repository

### Authentication

| Method | Setup | Token needed? |
|--------|-------|---------------|
| HTTPS with token | Provide `token` input with `repo` scope | Yes |
| HTTPS with git credentials | Configure git credential helpers | No |
| SSH | SSH keys in `~/.ssh/` or SSH agent | No |
| Local path | Direct filesystem access | No |

## Error Handling

### Successful Scenarios
- **No changes detected**: Skips push, sets `skipped=true`, exits with code 0
- **Branch doesn't exist**: Creates new branch in target repository automatically
- **Empty token for SSH**: Continues without token

### Error Scenarios

| Scenario | Behavior | Exit Code |
|----------|----------|-----------|
| Missing required arguments | Error message and usage hint | 1 |
| Folder doesn't exist | Validation error | 1 |
| Authentication failure | Git push fails | 1 |
| Remote state changed | `--force-with-lease` prevents push | 1 |
| Branch protection rules | Push rejected by remote | 1 |
| Subtree split failure | Error message | 1 |

### Safety Features
- **Bash strict mode**: `set -euo pipefail`
- **Safe force push**: `--force-with-lease` instead of `--force`
- **Token security**: Tokens never logged or exposed in output
- **Cleanup guarantee**: Temporary branches/remotes removed even on failure
- **Non-destructive**: Original repository never modified

## Security

### Token Protection
- Uses `x-access-token:TOKEN` format (GitHub recommended)
- Tokens never appear in logs or stderr
- Token only used during push, stored in shell variables (not on disk)

### Safe Push Strategy
- `--force-with-lease` fails if remote has been updated unexpectedly
- Temporary local branches are auto-cleaned
- Source repository is read-only (never modified)

### Best Practices
1. Use fine-grained PATs limited to specific repositories
2. Store tokens in GitHub Secrets, never hardcode
3. Prefer SSH URLs when possible
4. Enable branch protection on target repositories

## Troubleshooting

### Changes Not Detected

1. Ensure `fetch-depth: 0` in checkout step
2. Verify folder path is exact (case-sensitive, no leading/trailing slashes)
3. Confirm commits actually touch the folder: `git diff HEAD^ HEAD --name-only | grep "^packages/api/"`

### Authentication Errors

**HTTPS**: Verify `token` secret exists and has `repo` scope with write permissions.

**SSH**: Test with `ssh -T git@github.com` and ensure deploy keys have write access.

### Push Failures

- **Branch protection**: Check repository settings or add bypass rules
- **Force-with-lease rejection**: Someone pushed to the target repo; re-run the action
- **Network issues**: Test with `git ls-remote <url>`

### Common Mistakes

```yaml
# Wrong
local: "/packages/api"     # No leading slash
local: "packages/api/"     # No trailing slash

# Correct
local: "packages/api"
```

```yaml
# Wrong - token embedded in URL
remote: "https://TOKEN@github.com/org/repo.git"

# Correct - token as separate input
remote: "https://github.com/org/repo.git"
token: ${{ secrets.GITHUB_TOKEN }}
```

Note: `GITHUB_TOKEN` only works within the same organization. Use a PAT for cross-organization pushes.

### Debug Mode

Add these repository secrets and re-run:
- `ACTIONS_STEP_DEBUG` = `true`
- `ACTIONS_RUNNER_DEBUG` = `true`

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, testing, and code quality guidelines.

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Author

**Lorenzo Dessimoni**
