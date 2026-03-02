#!/usr/bin/env bash
# Check that all required tools are installed before bootstrap
set -euo pipefail

MISSING=0

check_tool() {
  if ! command -v "$1" &>/dev/null; then
    echo "ERROR: '$1' is not installed or not in PATH"
    MISSING=$((MISSING + 1))
  else
    echo "  OK: $1 ($(command -v "$1"))"
  fi
}

echo "Checking prerequisites..."
check_tool docker
check_tool kind
check_tool kubectl
check_tool clusterctl
check_tool helm

# Check Docker is running
if command -v docker &>/dev/null; then
  if ! docker info &>/dev/null; then
    echo "ERROR: Docker is installed but not running"
    MISSING=$((MISSING + 1))
  else
    echo "  OK: Docker daemon is running"
  fi
fi

if [ "${MISSING}" -gt 0 ]; then
  echo ""
  echo "ERROR: ${MISSING} prerequisite(s) missing. Install them before running bootstrap."
  exit 1
fi

echo "All prerequisites met."
