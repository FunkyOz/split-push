#!/usr/bin/env bash

# ============================================================================
# BATS Test Helper
# ============================================================================
# Provides common test utilities and mock functions for unit testing

# Source bats-support and bats-assert if available
if [[ -d "${BATS_TEST_DIRNAME}/../../test_helper/bats-support" ]]; then
    load "../../test_helper/bats-support/load"
    load "../../test_helper/bats-assert/load"
fi

# ============================================================================
# Setup and Teardown
# ============================================================================

# Common setup for all tests
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
}

# Common teardown for all tests
teardown() {
    # Return to original directory
    if [[ -n "${ORIGINAL_DIR:-}" ]]; then
        cd "${ORIGINAL_DIR}"
    fi

    # Clean up temporary directory
    if [[ -n "${TEST_TEMP_DIR:-}" ]] && [[ -d "${TEST_TEMP_DIR}" ]]; then
        rm -rf "${TEST_TEMP_DIR}"
    fi
}

# ============================================================================
# Mock Functions
# ============================================================================

# Mock git diff command
mock_git_diff() {
    local should_find_changes="${1:-false}"

    git() {
        if [[ "$1" == "diff" ]]; then
            if [[ "${should_find_changes}" == "true" ]]; then
                # Output fake changed files
                echo "test-folder/file1.txt"
                echo "test-folder/file2.js"
                return 0
            else
                # No changes
                return 0
            fi
        else
            # Pass through to real git for other commands
            command git "$@"
        fi
    }
    export -f git
}

# Mock git ls-tree command
mock_git_ls_tree() {
    local has_files="${1:-false}"

    git() {
        if [[ "$1" == "ls-tree" ]]; then
            if [[ "${has_files}" == "true" ]]; then
                # Output fake files
                echo "test-folder/file1.txt"
                echo "test-folder/file2.js"
                return 0
            else
                # No files
                return 0
            fi
        else
            # Pass through to real git for other commands
            command git "$@"
        fi
    }
    export -f git
}

# Mock git fetch command
mock_git_fetch() {
    local should_succeed="${1:-true}"

    git() {
        if [[ "$1" == "fetch" ]]; then
            if [[ "${should_succeed}" == "true" ]]; then
                return 0
            else
                return 1
            fi
        else
            # Pass through to real git for other commands
            command git "$@"
        fi
    }
    export -f git
}

# Mock git rev-parse command
mock_git_rev_parse() {
    local ref_exists="${1:-true}"

    git() {
        if [[ "$1" == "rev-parse" ]]; then
            if [[ "${ref_exists}" == "true" ]]; then
                echo "abc123def456"
                return 0
            else
                echo "fatal: Needed a single revision"
                return 128
            fi
        else
            # Pass through to real git for other commands
            command git "$@"
        fi
    }
    export -f git
}

# Mock git ls-remote command
mock_git_ls_remote() {
    local default_branch="${1:-main}"
    local should_succeed="${2:-true}"

    git() {
        if [[ "$1" == "ls-remote" ]]; then
            if [[ "${should_succeed}" == "true" ]]; then
                echo "ref: refs/heads/${default_branch}	HEAD"
                echo "abc123def456	HEAD"
                echo "abc123def456	refs/heads/${default_branch}"
                return 0
            else
                echo "fatal: could not read from remote repository"
                return 128
            fi
        else
            # Pass through to real git for other commands
            command git "$@"
        fi
    }
    export -f git
}

# Mock git config command
mock_git_config() {
    local name="${1:-}"
    local email="${2:-}"

    git() {
        if [[ "$1" == "config" ]]; then
            if [[ "$2" == "user.name" ]]; then
                if [[ -n "${name}" ]]; then
                    echo "${name}"
                    return 0
                else
                    return 1
                fi
            elif [[ "$2" == "user.email" ]]; then
                if [[ -n "${email}" ]]; then
                    echo "${email}"
                    return 0
                else
                    return 1
                fi
            fi
        else
            # Pass through to real git for other commands
            command git "$@"
        fi
    }
    export -f git
}

# ============================================================================
# Environment Setup Helpers
# ============================================================================

# Set GitHub environment variables for push event
set_github_env_push() {
    local branch="${1:-main}"
    export GITHUB_REF="refs/heads/${branch}"
    export GITHUB_EVENT_NAME="push"
}

# Set GitHub environment variables for PR event
set_github_env_pr() {
    local head_ref="${1:-feature-branch}"
    local base_ref="${2:-main}"
    export GITHUB_REF="refs/pull/123/merge"
    export GITHUB_EVENT_NAME="pull_request"
    export GITHUB_HEAD_REF="${head_ref}"
    export GITHUB_BASE_REF="${base_ref}"
}

# Set GitHub environment variables for tag event
set_github_env_tag() {
    local tag="${1:-v1.0.0}"
    export GITHUB_REF="refs/tags/${tag}"
    export GITHUB_EVENT_NAME="push"
}

# ============================================================================
# Assertion Helpers
# ============================================================================

# Assert command succeeded
assert_success_custom() {
    if [[ "$status" -ne 0 ]]; then
        echo "Expected success but got status ${status}"
        echo "Output: ${output}"
        return 1
    fi
}

# Assert command failed
assert_failure_custom() {
    if [[ "$status" -eq 0 ]]; then
        echo "Expected failure but command succeeded"
        echo "Output: ${output}"
        return 1
    fi
}

# Assert output contains string
assert_output_contains() {
    local expected="$1"
    if [[ ! "${output}" =~ ${expected} ]]; then
        echo "Expected output to contain: ${expected}"
        echo "Actual output: ${output}"
        return 1
    fi
}

# Assert output does not contain string
assert_output_not_contains() {
    local unexpected="$1"
    if [[ "${output}" =~ ${unexpected} ]]; then
        echo "Expected output to NOT contain: ${unexpected}"
        echo "Actual output: ${output}"
        return 1
    fi
}

# ============================================================================
# Source Script Helpers
# ============================================================================

# Source the main script for testing
source_push_script() {
    # Get the repository root
    local repo_root="${BATS_TEST_DIRNAME}/../.."

    # Source logging functions first
    source "${repo_root}/scripts/push.sh" 2>/dev/null || true
}

# Source detection library for testing
source_detect_changes() {
    # Get the repository root
    local repo_root="${BATS_TEST_DIRNAME}/../.."

    # Source the detection library (which sources logging.sh automatically)
    source "${repo_root}/scripts/lib/detect-changes.sh"
}
