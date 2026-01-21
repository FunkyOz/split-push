#!/usr/bin/env bash

# Include guard - prevent multiple sourcing
[[ -n "${_DETECT_CHANGES_SH_LOADED:-}" ]] && return 0
_DETECT_CHANGES_SH_LOADED=1

set -euo pipefail

# ============================================================================
# Change Detection Library
# ============================================================================
#
# This module contains git change detection and branch detection logic.
#
# Dependencies:
#   - logging.sh (sourced automatically)
#
# Functions:
#   - detect_branch()        Auto-detect branch from GitHub context
#   - get_default_branch()   Query remote repository for default branch
#   - detect_changes()       Detect if folder has changes in current commit
# ============================================================================

# Get library directory for sourcing dependencies
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source dependencies
source "${LIB_DIR}/logging.sh"

detect_branch() {
    local branch="${1:-}"

    # If branch is provided, use it
    if [[ -n "${branch}" ]]; then
        log_info "Using provided branch: ${branch}"
        echo "${branch}"
        return 0
    fi

    log_info "Auto-detecting branch from GitHub context"

    # Check if tag
    if [[ "${GITHUB_REF:-}" =~ ^refs/tags/(.+)$ ]]; then
        local tag="${BASH_REMATCH[1]}"
        log_info "Tag detected: ${tag}"
        echo "${tag}"
        return 0
    fi

    # Check if PR
    if [[ "${GITHUB_EVENT_NAME:-}" == "pull_request" ]] && [[ -n "${GITHUB_HEAD_REF:-}" ]]; then
        log_info "Pull request detected, using head ref: ${GITHUB_HEAD_REF}"
        echo "${GITHUB_HEAD_REF}"
        return 0
    fi

    # Check if branch
    if [[ "${GITHUB_REF:-}" =~ ^refs/heads/(.+)$ ]]; then
        local branch_name="${BASH_REMATCH[1]}"
        log_info "Branch detected: ${branch_name}"
        echo "${branch_name}"
        return 0
    fi

    # Fallback to default branch query
    log_info "No GitHub context available, querying remote default branch"
    echo ""
    return 0
}

get_default_branch() {
    local remote_url="$1"

    log_info "Querying remote for default branch"

    local output
    if output=$(git ls-remote --symref "${remote_url}" HEAD 2>&1); then
        # Parse: ref: refs/heads/main	HEAD
        if [[ "${output}" =~ refs/heads/([^[:space:]]+) ]]; then
            local default_branch="${BASH_REMATCH[1]}"
            log_success "Default branch detected: ${default_branch}"
            echo "${default_branch}"
            return 0
        fi
    fi

    log_error "Could not determine default branch"
    return 1
}

detect_changes() {
    local folder="$1"
    local base_commit=""

    log_info "Detecting changes in folder: ${folder}"

    # Check if pull request event
    if [[ "${GITHUB_EVENT_NAME:-}" == "pull_request" ]] && [[ -n "${GITHUB_BASE_REF:-}" ]]; then
        log_info "Pull request detected - comparing with base branch: ${GITHUB_BASE_REF}"
        base_commit="origin/${GITHUB_BASE_REF}"

        if ! git fetch origin "${GITHUB_BASE_REF}" 2>/dev/null; then
            log_warning "Could not fetch base branch, falling back to HEAD^"
            base_commit="HEAD^"
        fi
    # Check if tag push
    elif [[ "${GITHUB_REF:-}" =~ ^refs/tags/ ]]; then
        log_info "Tag push detected - checking if folder has files"
        if git ls-tree -r HEAD --name-only | grep -q "^${folder}/"; then
            log_success "Changes detected in ${folder} (tag push)"
            return 0
        else
            log_info "No files found in ${folder}"
            return 1
        fi
    else
        log_info "Push event detected - comparing with previous commit"

        if git rev-parse HEAD^ >/dev/null 2>&1; then
            base_commit="HEAD^"
        else
            log_info "First commit detected - checking all files"
            if git ls-tree -r HEAD --name-only | grep -q "^${folder}/"; then
                log_success "Changes detected in ${folder} (first commit)"
                return 0
            else
                log_info "No files found in ${folder}"
                return 1
            fi
        fi
    fi

    log_info "Comparing: ${base_commit}...HEAD"

    if git diff "${base_commit}" HEAD --name-only | grep -q "^${folder}/"; then
        log_success "Changes detected in ${folder}"
        return 0
    else
        log_info "No changes detected in ${folder}"
        return 1
    fi
}
