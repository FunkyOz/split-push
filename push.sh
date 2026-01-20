#!/usr/bin/env bash

set -euo pipefail

FOLDER="${1:-}"
REPOSITORY="${2:-}"
BRANCH="${3:-}"
GITHUB_TOKEN="${4:-}"
GIT_USER_NAME="${5:-}"
GIT_USER_EMAIL="${6:-}"
BASE_REF="${7:-}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

validate_inputs() {
    local missing_params=()

    if [[ -z "${FOLDER}" ]]; then
        missing_params+=("folder")
    fi

    if [[ -z "${REPOSITORY}" ]]; then
        missing_params+=("repository")
    fi

    if [[ -z "${BRANCH}" ]]; then
        missing_params+=("branch")
    fi

    if [[ -z "${GITHUB_TOKEN}" ]]; then
        missing_params+=("token")
    fi

    if [[ -z "${GIT_USER_NAME}" ]]; then
        missing_params+=("user-name")
    fi

    if [[ -z "${GIT_USER_EMAIL}" ]]; then
        missing_params+=("user-email")
    fi

    if [[ ${#missing_params[@]} -gt 0 ]]; then
        log_error "Missing required parameters: ${missing_params[*]}"
        return 1
    fi

    if [[ ! -d "${FOLDER}" ]]; then
        log_error "Folder '${FOLDER}' does not exist"
        return 1
    fi

    log_info "Input validation passed"
    return 0
}

detect_changes() {
    local folder="$1"
    local base_ref="$2"
    local base_commit=""

    log_info "Detecting changes in folder: ${folder}"

    if [[ -n "${base_ref}" ]]; then
        log_info "Pull request detected - comparing with base branch: ${base_ref}"
        base_commit="origin/${base_ref}"

        if ! git fetch origin "${base_ref}" 2>/dev/null; then
            log_warning "Could not fetch base branch, falling back to HEAD^"
            base_commit="HEAD^"
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

configure_git() {
    local user_name="$1"
    local user_email="$2"

    log_info "Configuring git user"

    git config user.name "${user_name}"
    git config user.email "${user_email}"

    log_success "Git configured: ${user_name} <${user_email}>"
}

perform_subtree_split() {
    local folder="$1"
    local temp_branch="temp-split-${folder//\//-}"

    log_info "Performing subtree split for: ${folder}"
    log_info "Creating temporary branch: ${temp_branch}"

    if git rev-parse --verify "${temp_branch}" >/dev/null 2>&1; then
        log_warning "Temporary branch already exists, deleting it"
        git branch -D "${temp_branch}"
    fi

    if ! git subtree split --prefix="${folder}" -b "${temp_branch}"; then
        log_error "Failed to create subtree split for ${folder}"
        return 1
    fi

    log_success "Subtree split completed successfully"
    echo "${temp_branch}"
}

setup_remote() {
    local repository="$1"
    local token="$2"
    local remote_name="target-repo"

    log_info "Setting up remote: ${repository}"

    if git remote | grep -q "^${remote_name}$"; then
        log_warning "Remote '${remote_name}' already exists, removing it"
        git remote remove "${remote_name}"
    fi

    local remote_url="https://x-access-token:${token}@github.com/${repository}.git"

    if ! git remote add "${remote_name}" "${remote_url}"; then
        log_error "Failed to add remote: ${repository}"
        return 1
    fi

    log_success "Remote configured: ${repository}"
    echo "${remote_name}"
}

push_to_repository() {
    local remote_name="$1"
    local temp_branch="$2"
    local target_branch="$3"

    log_info "Pushing to remote: ${remote_name}"
    log_info "From branch: ${temp_branch} -> To branch: ${target_branch}"

    git fetch "${remote_name}" "${target_branch}" 2>/dev/null || {
        log_warning "Branch '${target_branch}' does not exist in remote, it will be created"
    }

    if ! git push "${remote_name}" "${temp_branch}:${target_branch}" --force-with-lease; then
        log_error "Failed to push to ${remote_name}"
        return 1
    fi

    log_success "Successfully pushed to ${target_branch}"
    return 0
}

cleanup() {
    local temp_branch="$1"
    local remote_name="$2"

    log_info "Performing cleanup"

    if git rev-parse --verify "${temp_branch}" >/dev/null 2>&1; then
        git branch -D "${temp_branch}" || log_warning "Could not delete temporary branch: ${temp_branch}"
    fi

    if git remote | grep -q "^${remote_name}$"; then
        git remote remove "${remote_name}" || log_warning "Could not remove remote: ${remote_name}"
    fi

    log_success "Cleanup completed"
}

set_output() {
    local key="$1"
    local value="$2"

    if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
        echo "${key}=${value}" >> "${GITHUB_OUTPUT}"
    else
        echo "::set-output name=${key}::${value}"
    fi
}

main() {
    log_info "================================="
    log_info "Push Monorepo Folder"
    log_info "================================="
    log_info "Folder: ${FOLDER}"
    log_info "Repository: ${REPOSITORY}"
    log_info "Branch: ${BRANCH}"
    log_info "Base Ref: ${BASE_REF:-<not set>}"
    log_info "================================="

    if ! validate_inputs; then
        log_error "Input validation failed"
        set_output "pushed" "false"
        set_output "skipped" "true"
        exit 1
    fi

    if ! detect_changes "${FOLDER}" "${BASE_REF}"; then
        log_info "Skipping push - no changes detected"
        set_output "pushed" "false"
        set_output "skipped" "true"
        exit 0
    fi

    configure_git "${GIT_USER_NAME}" "${GIT_USER_EMAIL}"

    local temp_branch
    temp_branch=$(perform_subtree_split "${FOLDER}")

    local remote_name
    remote_name=$(setup_remote "${REPOSITORY}" "${GITHUB_TOKEN}")

    local push_result=0

    if ! push_to_repository "${remote_name}" "${temp_branch}" "${BRANCH}"; then
        push_result=1
    fi

    cleanup "${temp_branch}" "${remote_name}"

    if [[ ${push_result} -eq 0 ]]; then
        log_success "Push operation completed successfully"
        set_output "pushed" "true"
        set_output "skipped" "false"
        exit 0
    else
        log_error "Push operation failed"
        set_output "pushed" "false"
        set_output "skipped" "false"
        exit 1
    fi
}

main
