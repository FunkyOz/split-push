#!/usr/bin/env bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=================================${NC}"
echo -e "${BLUE}Running Test Suite${NC}"
echo -e "${BLUE}=================================${NC}"
echo ""

# Check if bats is installed
if ! command -v bats &> /dev/null; then
    echo -e "${RED}Error: bats not found${NC}"
    echo ""
    echo "Please install BATS:"
    echo "  macOS:  brew install bats-core"
    echo "  Linux:  sudo npm install -g bats"
    echo ""
    echo "Also install support libraries:"
    echo "  git clone https://github.com/bats-core/bats-support.git test_helper/bats-support"
    echo "  git clone https://github.com/bats-core/bats-assert.git test_helper/bats-assert"
    exit 1
fi

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}/.."

# Track test results
FAILED=0

# Run unit tests
echo -e "${BLUE}Running unit tests...${NC}"
echo ""

if bats tests/unit/*.bats; then
    echo ""
    echo -e "${GREEN}✓ Unit tests passed${NC}"
else
    FAILED=1
    echo ""
    echo -e "${RED}✗ Unit tests failed${NC}"
fi

echo ""
echo -e "${BLUE}=================================${NC}"
echo ""

# Run integration tests
echo -e "${BLUE}Running integration tests...${NC}"
echo ""

if bats tests/integration/*.bats; then
    echo ""
    echo -e "${GREEN}✓ Integration tests passed${NC}"
else
    FAILED=1
    echo ""
    echo -e "${RED}✗ Integration tests failed${NC}"
fi

echo ""
echo -e "${BLUE}=================================${NC}"
echo ""

# Print summary
if [[ ${FAILED} -eq 0 ]]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed${NC}"
    exit 1
fi
