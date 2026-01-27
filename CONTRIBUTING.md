# Contributing

Contributions are welcome! This project uses Bash 4.0+, BATS for testing, Shellcheck for linting, and GitHub Actions for CI/CD.

## Project Structure

```
split-push/
├── action.yml                           # GitHub Action definition
├── scripts/
│   ├── push.sh                         # Main CLI script (450+ lines)
│   └── lib/
│       ├── logging.sh                  # Colored console output functions
│       └── detect-changes.sh           # Change detection and branch resolution
├── tests/
│   ├── unit/                           # Unit tests (54 tests)
│   │   ├── test_helper.bash           # Test utilities and mock functions
│   │   ├── detect-changes.bats        # Change detection tests (19 tests)
│   │   ├── parse-functions.bats       # URL/author parsing tests (15 tests)
│   │   └── git-operations.bats        # Git operations tests (20 tests)
│   ├── integration/                    # Integration tests (9 tests)
│   │   └── test-repository.bats       # End-to-end workflow tests
│   └── run-tests.sh                    # Test runner script
├── .github/workflows/
│   └── test.yml                        # CI/CD test workflow
├── CLAUDE.md                           # AI development documentation
├── CHANGELOG.md                        # Version history
└── README.md                           # User documentation
```

## Running Tests

This project uses [BATS](https://github.com/bats-core/bats-core) (Bash Automated Testing System) with **63 tests** (54 unit + 9 integration), 100% pass rate.

### Install Dependencies

```bash
# macOS
brew install bats-core

# Linux (via npm)
sudo npm install -g bats

# Install BATS support libraries (required)
git clone https://github.com/bats-core/bats-support.git test_helper/bats-support
git clone https://github.com/bats-core/bats-assert.git test_helper/bats-assert
```

### Run Tests

```bash
# Run all tests
./tests/run-tests.sh

# Run specific test suite
bats tests/unit/*.bats                    # All unit tests
bats tests/integration/*.bats             # All integration tests

# Run individual test file
bats tests/unit/detect-changes.bats
bats tests/unit/parse-functions.bats
bats tests/unit/git-operations.bats
bats tests/integration/test-repository.bats

# Run with filter
bats tests/unit/detect-changes.bats --filter "pull request"
```

**Unit tests** mock git commands and test individual functions in isolation (~2s).
**Integration tests** create real git repositories and test end-to-end workflows (~5s).

## Code Quality

```bash
# Shellcheck linting
shellcheck -x scripts/push.sh scripts/lib/detect-changes.sh scripts/lib/logging.sh

# Syntax check
bash -n scripts/push.sh
bash -n scripts/lib/detect-changes.sh

# Action validation (requires actionlint)
actionlint action.yml
```

## Testing Locally

```bash
# Display help
./scripts/push.sh --help

# Full options
./scripts/push.sh "path/to/folder" "https://github.com/org/repo.git" \
  --branch "main" --token "github_token" --author "Your Name <your@email.com>"

# Minimal (auto-detect branch, use git config for author)
./scripts/push.sh "path/to/folder" "https://github.com/org/repo.git"

# SSH URL (no token needed)
./scripts/push.sh "path/to/folder" "git@github.com:org/repo.git" --branch "main"
```

Note: Must be run inside a git repository with the target folder present.

## Development Workflow

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Run test suite: `./tests/run-tests.sh`
6. Run shellcheck: `shellcheck -x scripts/push.sh`
7. Submit a pull request

## Reporting Issues

When reporting issues, please include:

- Operating system and version
- Git version (`git --version`)
- Bash version (`bash --version`)
- Full error message and logs
- Minimal reproduction steps
