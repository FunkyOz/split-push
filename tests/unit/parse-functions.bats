#!/usr/bin/env bats

# ============================================================================
# Unit Tests for Parsing Functions
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

    # Source the main push script to get parse functions
    REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
    export REPO_ROOT

    # Source parse functions (which sources logging.sh automatically)
    source "${REPO_ROOT}/scripts/push.sh"
}

# ============================================================================
# parse_remote_url() Tests
# ============================================================================

@test "parse_remote_url: SSH format returns as-is" {
    run parse_remote_url "git@github.com:org/repo.git" "fake-token"
    [[ "$status" -eq 0 ]]
    [[ "${output}" =~ "SSH URL detected" ]]
    [[ "${output}" =~ "git@github.com:org/repo.git" ]]
}

@test "parse_remote_url: HTTPS with credentials returns as-is" {
    run parse_remote_url "https://token@github.com/org/repo.git" "fake-token"
    [[ "$status" -eq 0 ]]
    [[ "${output}" =~ "HTTPS URL with credentials detected" ]]
    [[ "${output}" =~ "https://token@github.com/org/repo.git" ]]
}

@test "parse_remote_url: HTTPS without credentials injects token" {
    run parse_remote_url "https://github.com/org/repo.git" "my-secret-token"
    [[ "$status" -eq 0 ]]
    [[ "${output}" =~ "HTTPS URL detected, injecting token" ]]
    [[ "${output}" =~ "https://x-access-token:my-secret-token@github.com/org/repo.git" ]]
}

@test "parse_remote_url: unknown format treated as HTTPS" {
    run parse_remote_url "github.com/org/repo.git" "test-token"
    [[ "$status" -eq 0 ]]
    [[ "${output}" =~ "Unknown URL format, treating as HTTPS" ]]
    [[ "${output}" =~ "https://x-access-token:test-token@github.com/org/repo.git" ]]
}

@test "parse_remote_url: handles HTTP (upgrades to HTTPS with token)" {
    run parse_remote_url "https://github.com/org/repo" "token123"
    [[ "$status" -eq 0 ]]
    [[ "${output}" =~ "https://x-access-token:token123@github.com/org/repo" ]]
}

# ============================================================================
# parse_author() Tests
# ============================================================================

@test "parse_author: parses format 'Name <email>'" {
    run parse_author "John Doe <john@example.com>"
    [[ "$status" -eq 0 ]]
    [[ "${output}" =~ "Using provided author: John Doe <john@example.com>" ]]
    [[ "${output}" =~ "John Doe|john@example.com" ]]
}

@test "parse_author: parses format 'Name email'" {
    run parse_author "Jane Smith jane@example.com"
    [[ "$status" -eq 0 ]]
    [[ "${output}" =~ "Using provided author: Jane Smith <jane@example.com>" ]]
    [[ "${output}" =~ "Jane Smith|jane@example.com" ]]
}

@test "parse_author: handles format with extra spaces 'Name  <  email  >'" {
    run parse_author "Bob Johnson  <  bob@example.com  >"
    [[ "$status" -eq 0 ]]
    # Should trim whitespace
    local last_line=$(echo "${output}" | tail -n 1)
    [[ "${last_line}" =~ "Bob Johnson" ]]
}

@test "parse_author: uses default when empty and no git config" {
    # Mock git config to return nothing
    git() {
        if [[ "$1" == "config" ]]; then
            return 1
        else
            command git "$@"
        fi
    }
    export -f git

    run parse_author ""
    [[ "$status" -eq 0 ]]
    [[ "${output}" =~ "Using default author: GitHub Action <action@github.com>" ]]
    [[ "${output}" =~ "GitHub Action|action@github.com" ]]
}

@test "parse_author: uses git config when empty and available" {
    # Mock git config
    git() {
        if [[ "$1" == "config" ]] && [[ "$2" == "user.name" ]]; then
            echo "Git User"
            return 0
        elif [[ "$1" == "config" ]] && [[ "$2" == "user.email" ]]; then
            echo "git@user.com"
            return 0
        else
            command git "$@"
        fi
    }
    export -f git

    run parse_author ""
    [[ "$status" -eq 0 ]]
    [[ "${output}" =~ "Using git config author: Git User <git@user.com>" ]]
    [[ "${output}" =~ "Git User|git@user.com" ]]
}

@test "parse_author: handles partial git config (name only)" {
    # Mock git config with only name
    git() {
        if [[ "$1" == "config" ]] && [[ "$2" == "user.name" ]]; then
            echo "Partial User"
            return 0
        elif [[ "$1" == "config" ]] && [[ "$2" == "user.email" ]]; then
            return 1  # No email
        else
            command git "$@"
        fi
    }
    export -f git

    run parse_author ""
    [[ "$status" -eq 0 ]]
    # Should fall back to default when git config is incomplete
    [[ "${output}" =~ "GitHub Action|action@github.com" ]]
}

@test "parse_author: handles invalid format (name only)" {
    run parse_author "Just A Name"
    [[ "$status" -eq 0 ]]
    [[ "${output}" =~ "Could not parse author format" ]]
    [[ "${output}" =~ "Just A Name|action@github.com" ]]
}

@test "parse_author: handles empty string parts" {
    run parse_author " <>"
    [[ "$status" -eq 0 ]]
    # Should handle gracefully
    [[ "$status" -eq 0 ]]
}

@test "parse_author: handles special characters in name" {
    run parse_author "O'Brien-Smith <obrien@example.com>"
    [[ "$status" -eq 0 ]]
    [[ "${output}" =~ "O'Brien-Smith" ]]
    [[ "${output}" =~ "obrien@example.com" ]]
}

# ============================================================================
# parse_author() Output Format Tests
# ============================================================================

@test "parse_author: output format is 'name|email'" {
    run parse_author "Test User <test@example.com>"
    [[ "$status" -eq 0 ]]

    # Get last line (the actual output)
    local last_line=$(echo "${output}" | tail -n 1)

    # Should contain a pipe separator
    [[ "${last_line}" =~ \| ]]

    # Should be able to split on pipe
    IFS='|' read -r name email <<< "${last_line}"
    [[ "${name}" == "Test User" ]]
    [[ "${email}" == "test@example.com" ]]
}

@test "parse_author: handles unicode characters" {
    run parse_author "José García <jose@example.com>"
    [[ "$status" -eq 0 ]]
    [[ "${output}" =~ "José García" ]]
}
