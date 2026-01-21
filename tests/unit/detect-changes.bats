#!/usr/bin/env bats

# ============================================================================
# Unit Tests for Change Detection Functions
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

    # Source the library
    source_detect_changes
}

# ============================================================================
# detect_branch() Tests
# ============================================================================

@test "detect_branch: uses provided branch" {
    run detect_branch "custom-branch"
    [[ "$status" -eq 0 ]]
    [[ "${output}" =~ "custom-branch" ]]
    [[ "${output}" =~ "Using provided branch: custom-branch" ]]
}

@test "detect_branch: detects tag from GITHUB_REF" {
    export GITHUB_REF="refs/tags/v1.0.0"
    run detect_branch ""
    [[ "$status" -eq 0 ]]
    [[ "${output}" =~ "v1.0.0" ]]
    [[ "${output}" =~ "Tag detected: v1.0.0" ]]
}

@test "detect_branch: detects PR head ref" {
    set_github_env_pr "feature-branch" "main"
    run detect_branch ""
    [[ "$status" -eq 0 ]]
    [[ "${output}" =~ "feature-branch" ]]
    [[ "${output}" =~ "Pull request detected" ]]
}

@test "detect_branch: detects branch from GITHUB_REF" {
    export GITHUB_REF="refs/heads/develop"
    run detect_branch ""
    [[ "$status" -eq 0 ]]
    [[ "${output}" =~ "develop" ]]
    [[ "${output}" =~ "Branch detected: develop" ]]
}

@test "detect_branch: returns empty when no context available" {
    # Ensure no GitHub environment variables are set
    unset GITHUB_REF
    unset GITHUB_EVENT_NAME
    unset GITHUB_HEAD_REF

    # Capture the return value (last stdout line before stderr mixing)
    local branch=$(detect_branch "")
    [[ -z "${branch}" ]]
}

# ============================================================================
# get_default_branch() Tests
# ============================================================================

@test "get_default_branch: successfully queries default branch (main)" {
    git() {
        if [[ "$1" == "ls-remote" ]]; then
            echo "ref: refs/heads/main	HEAD"
            echo "abc123def456	HEAD"
            echo "abc123def456	refs/heads/main"
            return 0
        else
            command git "$@"
        fi
    }
    export -f git

    run get_default_branch "https://github.com/org/repo.git"
    [[ "$status" -eq 0 ]]
    [[ "${output}" =~ "main" ]]
}

@test "get_default_branch: successfully queries default branch (master)" {
    git() {
        if [[ "$1" == "ls-remote" ]]; then
            echo "ref: refs/heads/master	HEAD"
            echo "abc123def456	HEAD"
            echo "abc123def456	refs/heads/master"
            return 0
        else
            command git "$@"
        fi
    }
    export -f git

    run get_default_branch "https://github.com/org/repo.git"
    [[ "$status" -eq 0 ]]
    [[ "${output}" =~ "master" ]]
}

@test "get_default_branch: fails when remote query fails" {
    mock_git_ls_remote "main" "false"

    run get_default_branch "https://github.com/org/repo.git"
    [[ "$status" -ne 0 ]]
    [[ "${output}" =~ "Could not determine default branch" ]]
}

# ============================================================================
# detect_changes() Tests - Push Events
# ============================================================================

@test "detect_changes: detects changes in push event" {
    # Mock git diff to return changes
    git() {
        if [[ "$1" == "diff" ]]; then
            echo "test-folder/file1.txt"
            return 0
        elif [[ "$1" == "rev-parse" ]]; then
            echo "abc123"
            return 0
        else
            command git "$@"
        fi
    }
    export -f git

    run detect_changes "test-folder"
    [[ "$status" -eq 0 ]]
    [[ "${output}" =~ "Changes detected in test-folder" ]]
}

@test "detect_changes: no changes in push event" {
    # Mock git diff to return no changes
    git() {
        if [[ "$1" == "diff" ]]; then
            # No output = no changes
            return 0
        elif [[ "$1" == "rev-parse" ]]; then
            echo "abc123"
            return 0
        else
            command git "$@"
        fi
    }
    export -f git

    run detect_changes "test-folder"
    [[ "$status" -ne 0 ]]
    [[ "${output}" =~ "No changes detected in test-folder" ]]
}

@test "detect_changes: first commit with files" {
    # Mock no HEAD^ (first commit) but folder has files
    git() {
        if [[ "$1" == "rev-parse" ]]; then
            echo "fatal: Needed a single revision" >&2
            return 128
        elif [[ "$1" == "ls-tree" ]]; then
            echo "test-folder/file1.txt"
            return 0
        else
            command git "$@"
        fi
    }
    export -f git

    run detect_changes "test-folder"
    [[ "$status" -eq 0 ]]
    [[ "${output}" =~ "Changes detected in test-folder (first commit)" ]]
}

@test "detect_changes: first commit without files in folder" {
    # Mock no HEAD^ (first commit) and folder has no files
    git() {
        if [[ "$1" == "rev-parse" ]]; then
            echo "fatal: Needed a single revision" >&2
            return 128
        elif [[ "$1" == "ls-tree" ]]; then
            # No output = no files in folder
            return 0
        else
            command git "$@"
        fi
    }
    export -f git

    run detect_changes "test-folder"
    [[ "$status" -ne 0 ]]
    [[ "${output}" =~ "No files found in test-folder" ]]
}

# ============================================================================
# detect_changes() Tests - Pull Request Events
# ============================================================================

@test "detect_changes: PR with changes in folder" {
    set_github_env_pr "feature" "main"

    git() {
        if [[ "$1" == "fetch" ]]; then
            return 0
        elif [[ "$1" == "diff" ]]; then
            echo "test-folder/file1.txt"
            return 0
        else
            command git "$@"
        fi
    }
    export -f git

    run detect_changes "test-folder"
    [[ "$status" -eq 0 ]]
    [[ "${output}" =~ "Pull request detected" ]]
    [[ "${output}" =~ "Changes detected in test-folder" ]]
}

@test "detect_changes: PR without changes in folder" {
    set_github_env_pr "feature" "main"

    git() {
        if [[ "$1" == "fetch" ]]; then
            return 0
        elif [[ "$1" == "diff" ]]; then
            # No output = no changes
            return 0
        else
            command git "$@"
        fi
    }
    export -f git

    run detect_changes "test-folder"
    [[ "$status" -ne 0 ]]
    [[ "${output}" =~ "No changes detected in test-folder" ]]
}

@test "detect_changes: PR with fetch failure falls back to HEAD^" {
    set_github_env_pr "feature" "main"

    git() {
        if [[ "$1" == "fetch" ]]; then
            return 1  # Fetch fails
        elif [[ "$1" == "diff" ]]; then
            echo "test-folder/file1.txt"
            return 0
        else
            command git "$@"
        fi
    }
    export -f git

    run detect_changes "test-folder"
    [[ "$status" -eq 0 ]]
    [[ "${output}" =~ "Could not fetch base branch, falling back to HEAD^" ]]
    [[ "${output}" =~ "Changes detected in test-folder" ]]
}

# ============================================================================
# detect_changes() Tests - Tag Events
# ============================================================================

@test "detect_changes: tag push with files in folder" {
    set_github_env_tag "v1.0.0"

    git() {
        if [[ "$1" == "ls-tree" ]]; then
            echo "test-folder/file1.txt"
            return 0
        else
            command git "$@"
        fi
    }
    export -f git

    run detect_changes "test-folder"
    [[ "$status" -eq 0 ]]
    [[ "${output}" =~ "Tag push detected" ]]
    [[ "${output}" =~ "Changes detected in test-folder (tag push)" ]]
}

@test "detect_changes: tag push without files in folder" {
    set_github_env_tag "v1.0.0"

    git() {
        if [[ "$1" == "ls-tree" ]]; then
            # No output = no files
            return 0
        else
            command git "$@"
        fi
    }
    export -f git

    run detect_changes "test-folder"
    [[ "$status" -ne 0 ]]
    [[ "${output}" =~ "No files found in test-folder" ]]
}

# ============================================================================
# detect_changes() Tests - Edge Cases
# ============================================================================

@test "detect_changes: handles nested folder paths" {
    git() {
        if [[ "$1" == "diff" ]]; then
            echo "packages/frontend/src/App.tsx"
            return 0
        elif [[ "$1" == "rev-parse" ]]; then
            echo "abc123"
            return 0
        else
            command git "$@"
        fi
    }
    export -f git

    run detect_changes "packages/frontend"
    [[ "$status" -eq 0 ]]
    [[ "${output}" =~ "Changes detected in packages/frontend" ]]
}

@test "detect_changes: ignores changes outside folder" {
    git() {
        if [[ "$1" == "diff" ]]; then
            echo "other-folder/file.txt"
            echo "different/path/file.js"
            return 0
        elif [[ "$1" == "rev-parse" ]]; then
            echo "abc123"
            return 0
        else
            command git "$@"
        fi
    }
    export -f git

    run detect_changes "test-folder"
    [[ "$status" -ne 0 ]]
    [[ "${output}" =~ "No changes detected in test-folder" ]]
}
