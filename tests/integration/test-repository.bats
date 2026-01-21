#!/usr/bin/env bats

# ============================================================================
# Integration Tests for End-to-End Workflows
# ============================================================================
# These tests validate the complete push workflow using real git operations

setup() {
    # Create temporary directories
    TEST_TEMP_DIR="$(mktemp -d)"
    export TEST_TEMP_DIR

    SOURCE_REPO="${TEST_TEMP_DIR}/source"
    TARGET_REPO="${TEST_TEMP_DIR}/target"
    export SOURCE_REPO TARGET_REPO

    # Get repository root
    REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
    export REPO_ROOT

    # Create source repository with folder structure
    mkdir -p "${SOURCE_REPO}"
    cd "${SOURCE_REPO}"
    git init . > /dev/null 2>&1
    git config user.name "Test User"
    git config user.email "test@example.com"

    # Create target repository (bare)
    git init --bare "${TARGET_REPO}" > /dev/null 2>&1

    # Create folder structure
    mkdir -p packages/frontend
    mkdir -p packages/backend
    mkdir -p docs

    # Add initial files
    echo "# Frontend" > packages/frontend/README.md
    echo "console.log('app');" > packages/frontend/app.js

    echo "# Backend" > packages/backend/README.md
    echo "const express = require('express');" > packages/backend/server.js

    echo "# Documentation" > docs/README.md

    git add .
    git commit -m "Initial commit" > /dev/null 2>&1
}

teardown() {
    # Clean up
    if [[ -n "${TEST_TEMP_DIR}" ]] && [[ -d "${TEST_TEMP_DIR}" ]]; then
        rm -rf "${TEST_TEMP_DIR}"
    fi
}

# ============================================================================
# End-to-End Workflow Tests
# ============================================================================

@test "integration: complete push workflow with changes" {
    cd "${SOURCE_REPO}"

    # Make a change in frontend folder
    echo "// New component" > packages/frontend/Component.tsx
    git add packages/frontend/Component.tsx
    git commit -m "Add new component" > /dev/null 2>&1

    # Set GitHub environment
    export GITHUB_REF="refs/heads/main"
    export GITHUB_EVENT_NAME="push"

    # Create temporary output file
    export GITHUB_OUTPUT="${TEST_TEMP_DIR}/output.txt"

    # Run the push script
    run "${REPO_ROOT}/scripts/push.sh" \
        "packages/frontend" \
        "${TARGET_REPO}" \
        --branch "main" \
        --token "fake-token" \
        --author "Test User <test@example.com>"

    # Verify success
    [[ "$status" -eq 0 ]]
    [[ "${output}" =~ "Changes detected in packages/frontend" ]]
    [[ "${output}" =~ "Subtree split completed successfully" ]]
    [[ "${output}" =~ "Successfully pushed to main" ]]
    [[ "${output}" =~ "Push operation completed successfully" ]]

    # Verify outputs
    [[ -f "${GITHUB_OUTPUT}" ]]
    local outputs=$(cat "${GITHUB_OUTPUT}")
    [[ "${outputs}" =~ "pushed=true" ]]
    [[ "${outputs}" =~ "skipped=false" ]]

    # Verify target repo has only frontend files
    cd "${TEST_TEMP_DIR}"
    git clone "${TARGET_REPO}" verify > /dev/null 2>&1
    cd verify

    # Should have frontend files
    [[ -f "README.md" ]]
    [[ -f "app.js" ]]
    [[ -f "Component.tsx" ]]

    # Should NOT have backend or docs files
    [[ ! -f "server.js" ]]
    [[ ! -d "packages" ]]
}

@test "integration: skip push when no changes detected" {
    cd "${SOURCE_REPO}"

    # Make a change in backend folder only (not frontend)
    echo "// New endpoint" > packages/backend/routes.js
    git add packages/backend/routes.js
    git commit -m "Add routes" > /dev/null 2>&1

    # Set GitHub environment
    export GITHUB_REF="refs/heads/main"
    export GITHUB_EVENT_NAME="push"
    export GITHUB_OUTPUT="${TEST_TEMP_DIR}/output.txt"

    # Run the push script for frontend (which has no changes)
    run "${REPO_ROOT}/scripts/push.sh" \
        "packages/frontend" \
        "${TARGET_REPO}" \
        --branch "main" \
        --token "fake-token" \
        --author "Test User <test@example.com>"

    # Verify it skipped
    [[ "$status" -eq 0 ]]
    [[ "${output}" =~ "No changes detected in packages/frontend" ]]
    [[ "${output}" =~ "Skipping push - no changes detected" ]]

    # Verify outputs
    local outputs=$(cat "${GITHUB_OUTPUT}")
    [[ "${outputs}" =~ "pushed=false" ]]
    [[ "${outputs}" =~ "skipped=true" ]]
}

@test "integration: first commit workflow" {
    # Create a new source repo with first commit
    cd "${TEST_TEMP_DIR}"
    mkdir new-source
    cd new-source
    git init . > /dev/null 2>&1
    git config user.name "Test User"
    git config user.email "test@example.com"

    # Create folder with files
    mkdir -p app
    echo "# App" > app/README.md
    echo "index.js" > app/index.js

    git add .
    git commit -m "First commit" > /dev/null 2>&1

    # Set GitHub environment
    export GITHUB_REF="refs/heads/main"
    export GITHUB_EVENT_NAME="push"
    export GITHUB_OUTPUT="${TEST_TEMP_DIR}/output.txt"

    # Run the push script
    run "${REPO_ROOT}/scripts/push.sh" \
        "app" \
        "${TARGET_REPO}" \
        --branch "main" \
        --token "fake-token" \
        --author "Test User <test@example.com>"

    # Verify success
    [[ "$status" -eq 0 ]]
    [[ "${output}" =~ "First commit detected" ]]
    [[ "${output}" =~ "Changes detected in app (first commit)" ]]
    [[ "${output}" =~ "Successfully pushed to main" ]]

    # Verify outputs
    local outputs=$(cat "${GITHUB_OUTPUT}")
    [[ "${outputs}" =~ "pushed=true" ]]
}

@test "integration: tag push workflow" {
    cd "${SOURCE_REPO}"

    # Create a tag
    git tag -a v1.0.0 -m "Release v1.0.0" > /dev/null 2>&1

    # Set GitHub environment for tag
    export GITHUB_REF="refs/tags/v1.0.0"
    export GITHUB_EVENT_NAME="push"
    export GITHUB_OUTPUT="${TEST_TEMP_DIR}/output.txt"

    # Run the push script
    run "${REPO_ROOT}/scripts/push.sh" \
        "packages/frontend" \
        "${TARGET_REPO}" \
        --branch "v1.0.0" \
        --token "fake-token" \
        --author "Test User <test@example.com>"

    # Verify success
    [[ "$status" -eq 0 ]]
    [[ "${output}" =~ "Tag push detected" ]]
    [[ "${output}" =~ "Changes detected in packages/frontend (tag push)" ]]
    [[ "${output}" =~ "Successfully pushed to v1.0.0" ]]
}

@test "integration: pull request workflow" {
    cd "${SOURCE_REPO}"

    # Create and checkout feature branch
    git checkout -b feature-branch > /dev/null 2>&1

    # Make changes in frontend
    echo "// PR change" > packages/frontend/feature.js
    git add packages/frontend/feature.js
    git commit -m "Add feature" > /dev/null 2>&1

    # Set GitHub environment for PR
    export GITHUB_REF="refs/pull/123/merge"
    export GITHUB_EVENT_NAME="pull_request"
    export GITHUB_HEAD_REF="feature-branch"
    export GITHUB_BASE_REF="main"
    export GITHUB_OUTPUT="${TEST_TEMP_DIR}/output.txt"

    # Run the push script
    run "${REPO_ROOT}/scripts/push.sh" \
        "packages/frontend" \
        "${TARGET_REPO}" \
        --branch "feature-branch" \
        --token "fake-token" \
        --author "Test User <test@example.com>"

    # Verify success
    [[ "$status" -eq 0 ]]
    [[ "${output}" =~ "Pull request detected" ]]
    [[ "${output}" =~ "Changes detected in packages/frontend" ]]
    [[ "${output}" =~ "Successfully pushed" ]]
}

# ============================================================================
# Error Handling Tests
# ============================================================================

@test "integration: fails with non-existent folder" {
    cd "${SOURCE_REPO}"

    export GITHUB_REF="refs/heads/main"
    export GITHUB_EVENT_NAME="push"
    export GITHUB_OUTPUT="${TEST_TEMP_DIR}/output.txt"

    # Run with non-existent folder
    run "${REPO_ROOT}/scripts/push.sh" \
        "non-existent-folder" \
        "${TARGET_REPO}" \
        --branch "main" \
        --token "fake-token" \
        --author "Test User <test@example.com>"

    # Verify failure
    [[ "$status" -ne 0 ]]
    [[ "${output}" =~ "Local folder 'non-existent-folder' does not exist" ]]

    # Verify outputs
    local outputs=$(cat "${GITHUB_OUTPUT}")
    [[ "${outputs}" =~ "pushed=false" ]]
    [[ "${outputs}" =~ "skipped=true" ]]
}

@test "integration: succeeds with local repository without token" {
    cd "${SOURCE_REPO}"

    # Make a change
    echo "test" > packages/frontend/test.txt
    git add packages/frontend/test.txt
    git commit -m "Test" > /dev/null 2>&1

    export GITHUB_REF="refs/heads/main"
    export GITHUB_EVENT_NAME="push"
    export GITHUB_OUTPUT="${TEST_TEMP_DIR}/output.txt"

    # Run without token (local repo doesn't need it)
    run "${REPO_ROOT}/scripts/push.sh" \
        "packages/frontend" \
        "${TARGET_REPO}" \
        --branch "main" \
        --author "Test User <test@example.com>"

    # Verify success (local repos don't need token)
    [[ "$status" -eq 0 ]]
    [[ "${output}" =~ "Successfully pushed to main" ]]
}

# ============================================================================
# Nested Folder Tests
# ============================================================================

@test "integration: handles deeply nested folders" {
    cd "${SOURCE_REPO}"

    # Create deeply nested structure
    mkdir -p apps/web/src/components
    echo "export const Button = () => {}" > apps/web/src/components/Button.tsx
    git add apps/web
    git commit -m "Add button component" > /dev/null 2>&1

    export GITHUB_REF="refs/heads/main"
    export GITHUB_EVENT_NAME="push"
    export GITHUB_OUTPUT="${TEST_TEMP_DIR}/output.txt"

    # Run the push script
    run "${REPO_ROOT}/scripts/push.sh" \
        "apps/web" \
        "${TARGET_REPO}" \
        --branch "main" \
        --token "fake-token" \
        --author "Test User <test@example.com>"

    # Verify success
    [[ "$status" -eq 0 ]]
    [[ "${output}" =~ "Changes detected in apps/web" ]]
    [[ "${output}" =~ "Successfully pushed to main" ]]

    # Verify target repo structure
    cd "${TEST_TEMP_DIR}"
    git clone "${TARGET_REPO}" verify-nested > /dev/null 2>&1
    cd verify-nested

    # Should have nested files at root level
    [[ -f "src/components/Button.tsx" ]]
    [[ ! -d "apps" ]]  # Parent folder should not exist
}

# ============================================================================
# Cleanup Tests
# ============================================================================

@test "integration: cleans up temporary branches after success" {
    cd "${SOURCE_REPO}"

    # Make a change
    echo "test" > packages/frontend/test.txt
    git add packages/frontend/test.txt
    git commit -m "Test" > /dev/null 2>&1

    export GITHUB_REF="refs/heads/main"
    export GITHUB_EVENT_NAME="push"
    export GITHUB_OUTPUT="${TEST_TEMP_DIR}/output.txt"

    # Run the push script
    "${REPO_ROOT}/scripts/push.sh" \
        "packages/frontend" \
        "${TARGET_REPO}" \
        --branch "main" \
        --token "fake-token" \
        --author "Test User <test@example.com>" > /dev/null 2>&1

    # Verify no temp branches remain
    local branches=$(git branch | grep "temp-split" || true)
    [[ -z "${branches}" ]]

    # Verify no temp remotes remain
    local remotes=$(git remote | grep "target-repo" || true)
    [[ -z "${remotes}" ]]
}
