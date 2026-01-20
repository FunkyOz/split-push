# Push Monorepo Folder Action

A custom GitHub Action that intelligently syncs monorepo folders to dedicated repositories using git subtree split. This action detects changes in specific folders and pushes only when changes are detected, preserving git history.

## Features

- Smart change detection for both push and pull request events
- Git history preservation using subtree split
- Parallel execution support via matrix strategy
- Comprehensive error handling
- No external dependencies (uses only raw git commands)
- Reusable across multiple repositories

## Usage

### Basic Example

```yaml
- name: Push to dedicated repository
  uses: ./.github/actions/push-monorepo
  with:
    folder: "api.twiper"
    repository: "api.twiper"
    branch: "main"
    organization: "Twiper-app"
    token: ${{ secrets.ACCESS_TOKEN }}
    user-name: "Lorenzo Dessimoni"
    user-email: "lorenzo.dessimoni@gmail.com"
```

### Matrix Strategy Example

```yaml
jobs:
  push-changes:
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        service:
          - folder: "api.twiper"
            repository: "api.twiper"
          - folder: "rag.twiper"
            repository: "rag.twiper"

    steps:
      - name: Checkout with full history
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Push to dedicated repository
        uses: ./.github/actions/push-monorepo
        with:
          folder: ${{ matrix.service.folder }}
          repository: ${{ matrix.service.repository }}
          branch: ${{ github.ref_name }}
          organization: "Twiper-app"
          token: ${{ secrets.ACCESS_TOKEN }}
          user-name: "Your Name"
          user-email: "your@email.com"
```

### Pull Request Support

```yaml
- name: Push to dedicated repository
  uses: ./.github/actions/push-monorepo
  with:
    folder: "api.twiper"
    repository: "api.twiper"
    branch: ${{ github.head_ref || github.ref_name }}
    organization: "Twiper-app"
    token: ${{ secrets.ACCESS_TOKEN }}
    user-name: "Your Name"
    user-email: "your@email.com"
    base-ref: ${{ github.base_ref }}
```

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `folder` | Folder name to sync (e.g., "api.twiper") | Yes | - |
| `repository` | Target repository name (e.g., "api.twiper") | Yes | - |
| `branch` | Branch name to push to (e.g., "main", "staging") | Yes | - |
| `organization` | GitHub organization name (e.g., "Twiper-app") | Yes | - |
| `token` | GitHub authentication token with push access | Yes | - |
| `user-name` | Git committer name | Yes | - |
| `user-email` | Git committer email | Yes | - |
| `base-ref` | Base branch for comparison (used for pull requests) | No | `""` |

## Outputs

| Output | Description | Example |
|--------|-------------|---------|
| `pushed` | Boolean indicating if push occurred | `"true"` or `"false"` |
| `skipped` | Boolean indicating if skipped due to no changes | `"true"` or `"false"` |

## How It Works

1. **Input Validation**: Verifies all required parameters are provided and folder exists
2. **Change Detection**:
   - For **push events**: Compares current commit with previous commit (`HEAD^`)
   - For **pull requests**: Compares PR head with base branch
   - For **first commit**: Checks if any files exist in the folder
3. **Git Configuration**: Sets up git user name and email
4. **Subtree Split**: Extracts folder history using `git subtree split --prefix=<folder>`
5. **Remote Setup**: Adds target repository as remote with token authentication
6. **Push**: Pushes split branch to target repository using `--force-with-lease`
7. **Cleanup**: Removes temporary branches and remotes

## Change Detection Logic

### Push Events
```bash
# Compares current commit with previous commit
git diff HEAD^ HEAD --name-only | grep "^api.twiper/"
```

### Pull Request Events
```bash
# Compares PR head with base branch
git diff origin/main...HEAD --name-only | grep "^api.twiper/"
```

### First Commit
```bash
# Lists all files in the commit
git ls-tree -r HEAD --name-only | grep "^api.twiper/"
```

## Error Handling

The action handles various error scenarios:

- **No Changes Detected**: Skips push and completes successfully
- **Authentication Failure**: Exits with error and clear message
- **Branch Doesn't Exist**: Creates new branch in target repository
- **Merge Conflict**: `--force-with-lease` prevents overwriting unexpected changes
- **Network Issues**: Git operations timeout and fail gracefully
- **Invalid Folder**: Validates folder exists before proceeding

## Requirements

- **Git Repository**: Must be run in a git repository context
- **Full History**: Requires `fetch-depth: 0` in checkout action for subtree split
- **Permissions**: Token must have push access to target repositories

## Security

- Uses `x-access-token` format to prevent token exposure in git URLs
- Never logs sensitive information (tokens)
- Uses `--force-with-lease` instead of `--force` for safer pushes
- Validates all inputs to prevent injection attacks

## Reusability

### Option 1: Copy to Another Repository
Copy the entire `.github/actions/push-monorepo/` folder to another repository and use it in workflows.

### Option 2: Reference from This Repository
```yaml
- uses: Twiper-app/twiper-b2b/.github/actions/push-monorepo@main
  with:
    folder: "my-folder"
    repository: "my-repo"
    # ... other inputs
```

### Option 3: Publish to GitHub Marketplace
Create a dedicated repository and publish as a standalone action for maximum reusability.

## Example Workflow

See `.github/workflows/push-repo.yml` for a complete example using matrix strategy with multiple services.

## Troubleshooting

### Changes not detected
- Ensure `fetch-depth: 0` is set in checkout action
- Verify folder path is correct (must match exactly)
- Check if changes actually exist in the folder

### Authentication errors
- Verify token has push access to target repository
- Ensure token is not expired
- Check organization and repository names are correct

### Push failures
- Check if branch protection rules are blocking the push
- Verify remote state hasn't changed (use `--force-with-lease`)
- Ensure network connectivity to GitHub

## License

This action is part of the Twiper B2B monorepo and follows the same license.

## Author

Twiper Development Team
