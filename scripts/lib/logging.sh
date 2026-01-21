#!/usr/bin/env bash

# Include guard - prevent multiple sourcing
[[ -n "${_LOGGING_SH_LOADED:-}" ]] && return 0
_LOGGING_SH_LOADED=1

# ============================================================================
# Logging Library
# ============================================================================
#
# Provides colored console logging functions for consistent output formatting.
#
# Functions:
#   - log_info()      Print informational messages in blue
#   - log_success()   Print success messages in green
#   - log_warning()   Print warning messages in yellow
#   - log_error()     Print error messages in red to stderr
#
# Dependencies: None
# ============================================================================

# Color codes for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'  # No Color

# Log informational message
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" >&2
}

# Log success message
log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

# Log warning message
log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" >&2
}

# Log error message to stderr
log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}
