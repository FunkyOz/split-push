#!/usr/bin/env bash

set -euo pipefail

# Get script directory for sourcing lib files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source library functions
source "${SCRIPT_DIR}/lib/logging.sh"
source "${SCRIPT_DIR}/lib/detect-changes.sh"

# Display help message
show_help() {
    cat << 'EOF'
Push Monorepo Folder - Sync folders to dedicated repositories

USAGE:
    push.sh LOCAL REMOTE [OPTIONS]

ARGUMENTS:
    LOCAL       Local folder path (e.g., "packages/api")
    REMOTE      Target repository URL
                Formats: https://github.com/org/repo.git | git@github.com:org/repo.git
                         org/repo | /path/to/local/repo

OPTIONS:
    -b, --branch BRANCH    Target branch (default: auto-detect from git context)
    -t, --token TOKEN      GitHub token (optional for SSH/local repos)
    -a, --author AUTHOR    Git author "Name <email>" (default: git config)
    -h, --help             Show this help

EXAMPLES:
    # Basic usage
    push.sh "packages/api" "https://github.com/org/api.git" -b "main" -t "ghp_xxx"

    # Minimal (auto-detect branch and author)
    push.sh "packages/api" "org/api"

    # SSH (no token needed)
    push.sh "packages/api" "git@github.com:org/api.git" -b "main"

    # Short flags
    push.sh "packages/api" "org/api" -b "main" -t "token" -a "Bot <bot@example.com>"

WORKFLOW:
    1. Validate inputs and detect changes in folder
    2. Skip if no changes (exit 0)
    3. Extract folder history via git subtree split
    4. Push to target with --force-with-lease
    5. Cleanup temporary branches/remotes

CHANGE DETECTION:
    Push events → Compares HEAD with HEAD^
    Pull requests → Compares HEAD with base branch
    First commit → Checks if folder has files
    Tags → Checks if folder exists at tag

BRANCH AUTO-DETECTION (priority order):
    1. --branch parameter
    2. GITHUB_HEAD_REF (PR head)
    3. GITHUB_REF (push/tag)
    4. Remote default branch

AUTHENTICATION:
    SSH:   Uses ~/.ssh/ keys or SSH agent (no token needed)
    HTTPS: Requires --token or git credential helpers
    Local: No authentication needed

EXIT CODES:
    0 = Success (pushed or skipped - no changes)
    1 = Failure (validation/git/push error)

OUTPUTS (GitHub Actions when GITHUB_OUTPUT set):
    pushed=true/false    skipped=true/false

REQUIREMENTS:
    Git 2.0+ with full history (fetch-depth: 0), write permissions to target repo

For full documentation, see README.md

EOF
}

# Parse command line arguments
parse_arguments() {
    # Show help if no arguments or help flag provided
    if [[ $# -eq 0 ]]; then
        show_help
        exit 0
    fi

    # Check for help flag as first argument
    if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
        show_help
        exit 0
    fi

    # Positional arguments
    LOCAL=""
    REMOTE=""

    # Optional arguments
    BRANCH=""
    GITHUB_TOKEN=""
    AUTHOR=""

    # Parse positional arguments first
    if [[ $# -ge 1 ]] && [[ ! "$1" =~ ^- ]]; then
        LOCAL="$1"
        shift
    fi

    if [[ $# -ge 1 ]] && [[ ! "$1" =~ ^- ]]; then
        REMOTE="$1"
        shift
    fi

    # Parse optional arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -b|--branch)
                BRANCH="${2:-}"
                shift 2
                ;;
            -t|--token)
                GITHUB_TOKEN="${2:-}"
                shift 2
                ;;
            -a|--author)
                AUTHOR="${2:-}"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                echo "" >&2
                echo "Usage: $0 LOCAL REMOTE [OPTIONS]" >&2
                echo "Try '$0 --help' for more information." >&2
                return 1
                ;;
        esac
    done

    # Export variables for use in other functions
    export LOCAL REMOTE BRANCH GITHUB_TOKEN AUTHOR
}

# Parse arguments
parse_arguments "$@"

parse_remote_url() {
    local remote="$1"
    local token="${2:-}"

    # Local path (starts with / or ./ or ../)
    if [[ "${remote}" =~ ^/ ]] || [[ "${remote}" =~ ^\.\. ]] || [[ "${remote}" =~ ^\. ]]; then
        log_info "Local path detected, using as-is"
        echo "${remote}"
        return 0
    fi

    # SSH format (git@github.com:org/repo.git)
    if [[ "${remote}" =~ ^git@ ]]; then
        log_info "SSH URL detected, using as-is"
        echo "${remote}"
        return 0
    fi

    # HTTPS with existing credentials (https://token@github.com/org/repo.git)
    if [[ "${remote}" =~ ^https://[^@]+@.* ]]; then
        log_info "HTTPS URL with credentials detected, using as-is"
        echo "${remote}"
        return 0
    fi

    # HTTPS without credentials (https://github.com/log/repo.git)
    if [[ "${remote}" =~ ^https:// ]]; then
        if [[ -n "${token}" ]]; then
            log_info "HTTPS URL detected, injecting token"
            local url_with_token="${remote/https:\/\//https://x-access-token:${token}@}"
            echo "${url_with_token}"
        else
            log_info "HTTPS URL detected, no token provided"
            echo "${remote}"
        fi
        return 0
    fi

    # Fallback - treat as HTTPS and inject token if available
    if [[ -n "${token}" ]]; then
        log_warning "Unknown URL format, treating as HTTPS with token"
        echo "https://x-access-token:${token}@${remote}"
    else
        log_warning "Unknown URL format, treating as HTTPS without token"
        echo "https://${remote}"
    fi
    return 0
}

parse_author() {
    local author="$1"
    local name=""
    local email=""

    if [[ -z "${author}" ]]; then
        # Try git config
        name=$(git config user.name 2>/dev/null || echo "")
        email=$(git config user.email 2>/dev/null || echo "")

        if [[ -z "${name}" ]] || [[ -z "${email}" ]]; then
            # Use default
            name="GitHub Action"
            email="action@github.com"
            log_info "Using default author: ${name} <${email}>"
        else
            log_info "Using git config author: ${name} <${email}>"
        fi
    else
        # Parse author string
        # Format: "John Doe <john@example.com>" or "John Doe john@example.com"
        if [[ "${author}" =~ ^(.+)\<(.+)\>$ ]]; then
            name="${BASH_REMATCH[1]}"
            email="${BASH_REMATCH[2]}"
            # Trim whitespace
            name="${name%"${name##*[![:space:]]}"}"
            email="${email%"${email##*[![:space:]]}"}"
        elif [[ "${author}" =~ ^(.+)[[:space:]]([^[:space:]]+@[^[:space:]]+)$ ]]; then
            name="${BASH_REMATCH[1]}"
            email="${BASH_REMATCH[2]}"
        else
            log_warning "Could not parse author format, using as name only"
            name="${author}"
            email="action@github.com"
        fi
        log_info "Using provided author: ${name} <${email}>"
    fi

    echo "${name}|${email}"
    return 0
}

validate_inputs() {
    local missing_params=()

    if [[ -z "${LOCAL}" ]]; then
        missing_params+=("local")
    fi

    if [[ -z "${REMOTE}" ]]; then
        missing_params+=("remote")
    fi

    if [[ ${#missing_params[@]} -gt 0 ]]; then
        log_error "Missing required parameters: ${missing_params[*]}"
        return 1
    fi

    if [[ ! -d "${LOCAL}" ]]; then
        log_error "Local folder '${LOCAL}' does not exist"
        return 1
    fi

    log_info "Input validation passed"
    return 0
}

configure_git() {
    local author="$1"
    local author_parsed
    local user_name
    local user_email

    log_info "Configuring git user"

    author_parsed=$(parse_author "${author}")
    IFS='|' read -r user_name user_email <<< "${author_parsed}"

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
        git branch -D "${temp_branch}" >&2
    fi

    if ! git subtree split --prefix="${folder}" -b "${temp_branch}" >&2; then
        log_error "Failed to create subtree split for ${folder}"
        return 1
    fi

    log_success "Subtree split completed successfully"
    echo "${temp_branch}"
}

setup_remote() {
    local remote="$1"
    local token="$2"
    local remote_name="target-repo"
    local remote_url

    log_info "Setting up remote: ${remote}"

    if git remote | grep -q "^${remote_name}$"; then
        log_warning "Remote '${remote_name}' already exists, removing it"
        git remote remove "${remote_name}"
    fi

    remote_url=$(parse_remote_url "${remote}" "${token}")

    if ! git remote add "${remote_name}" "${remote_url}"; then
        log_error "Failed to add remote: ${remote}"
        return 1
    fi

    log_success "Remote configured: ${remote}"
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
    log_info "Local: ${LOCAL}"
    log_info "Remote: ${REMOTE}"
    log_info "Branch: ${BRANCH:-<auto-detect>}"
    log_info "================================="

    if ! validate_inputs; then
        log_error "Input validation failed"
        set_output "pushed" "false"
        set_output "skipped" "true"
        exit 1
    fi

    # Detect branch if not provided
    local target_branch
    target_branch=$(detect_branch "${BRANCH}")

    # If still empty, query remote for default branch
    if [[ -z "${target_branch}" ]]; then
        local remote_url
        remote_url=$(parse_remote_url "${REMOTE}" "${GITHUB_TOKEN}")

        if ! target_branch=$(get_default_branch "${remote_url}"); then
            log_error "Could not determine target branch"
            set_output "pushed" "false"
            set_output "skipped" "true"
            exit 1
        fi
    fi

    log_info "Target branch: ${target_branch}"

    if ! detect_changes "${LOCAL}"; then
        log_info "Skipping push - no changes detected"
        set_output "pushed" "false"
        set_output "skipped" "true"
        exit 0
    fi

    configure_git "${AUTHOR}"

    local temp_branch
    temp_branch=$(perform_subtree_split "${LOCAL}")

    local remote_name
    remote_name=$(setup_remote "${REMOTE}" "${GITHUB_TOKEN}")

    local push_result=0

    if ! push_to_repository "${remote_name}" "${temp_branch}" "${target_branch}"; then
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

# Only run main if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
