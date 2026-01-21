#!/usr/bin/env bats

# ============================================================================
# Unit Tests for Git Operations Functions
# ============================================================================

load test_helper

setup() {
    # Create temporary directory for test isolation
    TEST_TEMP_DIR="$(mktemp -d)"
    export TEST_TEMP_DIR

    # Save original directory
    ORIGINAL_DIR="$(pwd)"
    export ORIGINAL_DIR

    # Clear GitHub environment variables
    unset GITHUB_REF
    unset GITHUB_EVENT_NAME
    unset GITHUB_HEAD_REF
    unset GITHUB_BASE_REF
    unset GITHUB_OUTPUT

    # Source the main push script to get git operation functions
    REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
    export REPO_ROOT

    # Source the script (which sources logging.sh automatically)
    source "${REPO_ROOT}/scripts/push.sh"

    # Create test folder
    mkdir -p "${TEST_TEMP_DIR}/test-folder"
}

# ============================================================================
# validate_inputs() Tests
# ============================================================================

@test "validate_inputs: succeeds with all required parameters" {
    LOCAL="${TEST_TEMP_DIR}/test-folder"
    REMOTE="https://github.com/org/repo.git"
    GITHUB_TOKEN="test-token"
    export LOCAL REMOTE GITHUB_TOKEN

    run validate_inputs
    [[ "$status" -eq 0 ]]
    [[ "${output}" =~ "Input validation passed" ]]
}

@test "validate_inputs: fails when LOCAL is missing" {
    LOCAL=""
    REMOTE="https://github.com/org/repo.git"
    GITHUB_TOKEN="test-token"
    export LOCAL REMOTE GITHUB_TOKEN

    run validate_inputs
    [[ "$status" -ne 0 ]]
    [[ "${output}" =~ "Missing required parameters: local" ]]
}

@test "validate_inputs: fails when REMOTE is missing" {
    LOCAL="${TEST_TEMP_DIR}/test-folder"
    REMOTE=""
    GITHUB_TOKEN="test-token"
    export LOCAL REMOTE GITHUB_TOKEN

    run validate_inputs
    [[ "$status" -ne 0 ]]
    [[ "${output}" =~ "Missing required parameters: remote" ]]
}

@test "validate_inputs: succeeds when GITHUB_TOKEN is missing" {
    LOCAL="${TEST_TEMP_DIR}/test-folder"
    REMOTE="https://github.com/org/repo.git"
    GITHUB_TOKEN=""
    export LOCAL REMOTE GITHUB_TOKEN

    run validate_inputs
    [[ "$status" -eq 0 ]]
    [[ "${output}" =~ "Input validation passed" ]]
}

@test "validate_inputs: fails when multiple parameters missing" {
    LOCAL=""
    REMOTE=""
    GITHUB_TOKEN="test-token"
    export LOCAL REMOTE GITHUB_TOKEN

    run validate_inputs
    [[ "$status" -ne 0 ]]
    [[ "${output}" =~ "Missing required parameters:" ]]
    [[ "${output}" =~ "local" ]]
    [[ "${output}" =~ "remote" ]]
}

@test "validate_inputs: fails when folder does not exist" {
    LOCAL="${TEST_TEMP_DIR}/non-existent-folder"
    REMOTE="https://github.com/org/repo.git"
    GITHUB_TOKEN="test-token"
    export LOCAL REMOTE GITHUB_TOKEN

    run validate_inputs
    [[ "$status" -ne 0 ]]
    [[ "${output}" =~ "Local folder '${LOCAL}' does not exist" ]]
}

# ============================================================================
# configure_git() Tests
# ============================================================================

@test "configure_git: sets git user from provided author" {
    # Initialize a git repo in temp dir
    cd "${TEST_TEMP_DIR}"
    git init . > /dev/null 2>&1

    run configure_git "Test User <test@example.com>"
    [[ "$status" -eq 0 ]]
    [[ "${output}" =~ "Git configured: Test User <test@example.com>" ]]

    # Verify git config was set
    local actual_name=$(git config user.name)
    local actual_email=$(git config user.email)
    [[ "${actual_name}" == "Test User" ]]
    [[ "${actual_email}" == "test@example.com" ]]
}

@test "configure_git: uses default author when empty" {
    # Initialize a git repo in temp dir
    cd "${TEST_TEMP_DIR}"
    git init . > /dev/null 2>&1

    # Mock git config to return empty (no global config)
    git() {
        if [[ "$1" == "config" ]] && [[ "$2" == "user.name" ]]; then
            if [[ "${3:-}" == "GitHub Action" ]]; then
                # Setting the value
                command git "$@"
            else
                # Getting the value - return empty
                return 1
            fi
        elif [[ "$1" == "config" ]] && [[ "$2" == "user.email" ]]; then
            if [[ "${3:-}" == "action@github.com" ]]; then
                # Setting the value
                command git "$@"
            else
                # Getting the value - return empty
                return 1
            fi
        else
            command git "$@"
        fi
    }
    export -f git

    run configure_git ""
    [[ "$status" -eq 0 ]]
    [[ "${output}" =~ "GitHub Action <action@github.com>" ]]

    # Unset the mock to use real git for verification
    unset -f git

    # Verify git config was set
    local actual_name=$(git config user.name)
    local actual_email=$(git config user.email)
    [[ "${actual_name}" == "GitHub Action" ]]
    [[ "${actual_email}" == "action@github.com" ]]
}

# ============================================================================
# cleanup() Tests
# ============================================================================

@test "cleanup: removes temporary branch" {
    # Initialize a git repo
    cd "${TEST_TEMP_DIR}"
    git init . > /dev/null 2>&1
    git config user.name "Test"
    git config user.email "test@example.com"

    # Create a test file and commit
    echo "test" > test.txt
    git add test.txt
    git commit -m "Initial commit" > /dev/null 2>&1

    # Create a temporary branch
    git branch temp-split-test > /dev/null 2>&1

    # Verify branch exists
    git rev-parse --verify temp-split-test > /dev/null 2>&1

    # Run cleanup
    run cleanup "temp-split-test" "fake-remote"
    [[ "$status" -eq 0 ]]
    [[ "${output}" =~ "Cleanup completed" ]]

    # Verify branch was deleted
    run git rev-parse --verify temp-split-test
    [[ "$status" -ne 0 ]]
}

@test "cleanup: handles non-existent branch gracefully" {
    cd "${TEST_TEMP_DIR}"
    git init . > /dev/null 2>&1

    run cleanup "non-existent-branch" "fake-remote"
    [[ "$status" -eq 0 ]]
    [[ "${output}" =~ "Cleanup completed" ]]
}

@test "cleanup: removes remote" {
    cd "${TEST_TEMP_DIR}"
    git init . > /dev/null 2>&1

    # Add a test remote
    git remote add test-remote "https://github.com/test/repo.git" > /dev/null 2>&1

    # Verify remote exists
    git remote | grep -q "test-remote"

    # Run cleanup
    run cleanup "fake-branch" "test-remote"
    [[ "$status" -eq 0 ]]

    # Verify remote was removed
    run git remote
    [[ ! "${output}" =~ "test-remote" ]]
}

# ============================================================================
# set_output() Tests
# ============================================================================

@test "set_output: writes to GITHUB_OUTPUT file" {
    # Create a temporary GITHUB_OUTPUT file
    export GITHUB_OUTPUT="${TEST_TEMP_DIR}/github_output.txt"

    run set_output "pushed" "true"
    [[ "$status" -eq 0 ]]

    # Verify content was written
    [[ -f "${GITHUB_OUTPUT}" ]]
    local content=$(cat "${GITHUB_OUTPUT}")
    [[ "${content}" == "pushed=true" ]]
}

@test "set_output: uses legacy format when GITHUB_OUTPUT not set" {
    unset GITHUB_OUTPUT

    run set_output "skipped" "false"
    [[ "$status" -eq 0 ]]
    [[ "${output}" == "::set-output name=skipped::false" ]]
}

@test "set_output: appends multiple outputs" {
    export GITHUB_OUTPUT="${TEST_TEMP_DIR}/github_output.txt"

    set_output "pushed" "true"
    set_output "skipped" "false"

    local content=$(cat "${GITHUB_OUTPUT}")
    [[ "${content}" =~ "pushed=true" ]]
    [[ "${content}" =~ "skipped=false" ]]
}

# ============================================================================
# setup_remote() Tests
# ============================================================================

@test "setup_remote: adds new remote successfully" {
    cd "${TEST_TEMP_DIR}"
    git init . > /dev/null 2>&1

    run setup_remote "https://github.com/org/repo.git" "test-token"
    [[ "$status" -eq 0 ]]
    [[ "${output}" =~ "Remote configured" ]]
    [[ "${output}" =~ "target-repo" ]]

    # Verify remote was added
    local remotes=$(git remote)
    [[ "${remotes}" =~ "target-repo" ]]
}

@test "setup_remote: replaces existing remote" {
    cd "${TEST_TEMP_DIR}"
    git init . > /dev/null 2>&1

    # Add existing remote
    git remote add target-repo "https://github.com/old/repo.git" > /dev/null 2>&1

    run setup_remote "https://github.com/new/repo.git" "test-token"
    [[ "$status" -eq 0 ]]
    [[ "${output}" =~ "Remote 'target-repo' already exists, removing it" ]]
    [[ "${output}" =~ "Remote configured" ]]

    # Verify remote was updated
    local remote_url=$(git remote get-url target-repo)
    [[ "${remote_url}" =~ "new/repo.git" ]]
}

@test "setup_remote: handles SSH URLs" {
    cd "${TEST_TEMP_DIR}"
    git init . > /dev/null 2>&1

    run setup_remote "git@github.com:org/repo.git" "test-token"
    [[ "$status" -eq 0 ]]
    [[ "${output}" =~ "SSH URL detected" ]]

    # Verify remote was added with SSH URL
    local remote_url=$(git remote get-url target-repo)
    [[ "${remote_url}" == "git@github.com:org/repo.git" ]]
}

# ============================================================================
# Edge Cases and Error Handling
# ============================================================================

@test "validate_inputs: handles folder with spaces in name" {
    mkdir -p "${TEST_TEMP_DIR}/folder with spaces"
    LOCAL="${TEST_TEMP_DIR}/folder with spaces"
    REMOTE="https://github.com/org/repo.git"
    GITHUB_TOKEN="test-token"
    export LOCAL REMOTE GITHUB_TOKEN

    run validate_inputs
    [[ "$status" -eq 0 ]]
    [[ "${output}" =~ "Input validation passed" ]]
}

@test "validate_inputs: handles special characters in paths" {
    mkdir -p "${TEST_TEMP_DIR}/test-folder_123"
    LOCAL="${TEST_TEMP_DIR}/test-folder_123"
    REMOTE="https://github.com/org/repo.git"
    GITHUB_TOKEN="test-token"
    export LOCAL REMOTE GITHUB_TOKEN

    run validate_inputs
    [[ "$status" -eq 0 ]]
    [[ "${output}" =~ "Input validation passed" ]]
}
