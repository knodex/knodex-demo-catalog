#!/usr/bin/env bash
# Wait for all deployments and statefulsets in a namespace to be ready
# Usage: wait-for-pods.sh <namespace> [timeout_seconds]
#
# Uses kubectl wait for proper readiness checks instead of parsing pod status text.
# Detects CrashLoopBackOff and other permanent failures early.

set -euo pipefail

NAMESPACE="${1:?Usage: wait-for-pods.sh <namespace> [timeout_seconds]}"
TIMEOUT="${2:-300}"
INTERVAL=10
ELAPSED=0

echo "Waiting for workloads in namespace '${NAMESPACE}' to be ready (timeout: ${TIMEOUT}s)..."

# Wait for namespace to have workloads scheduled
while [ "${ELAPSED}" -lt "${TIMEOUT}" ]; do
  DEPLOY_COUNT=$(kubectl get deployments -n "${NAMESPACE}" --no-headers 2>/dev/null | wc -l | tr -d ' ')
  STS_COUNT=$(kubectl get statefulsets -n "${NAMESPACE}" --no-headers 2>/dev/null | wc -l | tr -d ' ')
  if [ "$((DEPLOY_COUNT + STS_COUNT))" -gt 0 ]; then
    break
  fi
  echo "  No workloads found yet in '${NAMESPACE}', waiting..."
  sleep "${INTERVAL}"
  ELAPSED=$((ELAPSED + INTERVAL))
done

if [ "$((DEPLOY_COUNT + STS_COUNT))" -eq 0 ]; then
  echo "ERROR: No deployments or statefulsets found in '${NAMESPACE}' after ${TIMEOUT}s"
  exit 1
fi

# Check for CrashLoopBackOff or other permanent failures during the wait
check_for_failures() {
  local crashes
  crashes=$(kubectl get pods -n "${NAMESPACE}" --no-headers 2>/dev/null | grep -c 'CrashLoopBackOff\|ImagePullBackOff\|ErrImagePull\|InvalidImageName' || true)
  if [ "${crashes}" -gt 0 ]; then
    echo ""
    echo "WARNING: ${crashes} pod(s) in permanent failure state:"
    kubectl get pods -n "${NAMESPACE}" --no-headers 2>/dev/null | grep 'CrashLoopBackOff\|ImagePullBackOff\|ErrImagePull\|InvalidImageName' || true
    return 1
  fi
  return 0
}

# Wait for deployments
if [ "${DEPLOY_COUNT}" -gt 0 ]; then
  echo "  Waiting for ${DEPLOY_COUNT} deployment(s)..."
  REMAINING=$((TIMEOUT - ELAPSED))
  if [ "${REMAINING}" -le 0 ]; then REMAINING=10; fi
  SECONDS=0
  if ! kubectl wait --for=condition=Available deployment --all -n "${NAMESPACE}" --timeout="${REMAINING}s" 2>&1; then
    echo ""
    echo "ERROR: Deployments did not become ready in time."
    check_for_failures || true
    kubectl get pods -n "${NAMESPACE}"
    exit 1
  fi
  ELAPSED=$((ELAPSED + SECONDS))
fi

# Wait for statefulsets
if [ "${STS_COUNT}" -gt 0 ]; then
  echo "  Waiting for ${STS_COUNT} statefulset(s)..."
  REMAINING=$((TIMEOUT - ELAPSED))
  if [ "${REMAINING}" -le 0 ]; then REMAINING=10; fi
  if ! kubectl rollout status statefulset --namespace "${NAMESPACE}" --timeout="${REMAINING}s" 2>&1; then
    echo ""
    echo "ERROR: StatefulSets did not become ready in time."
    check_for_failures || true
    kubectl get pods -n "${NAMESPACE}"
    exit 1
  fi
fi

# Final crash check — pods may have started but then crashed
if ! check_for_failures; then
  echo ""
  echo "ERROR: Some pods are in a failure state despite workloads reporting ready."
  kubectl get pods -n "${NAMESPACE}"
  exit 1
fi

echo "All workloads in '${NAMESPACE}' are ready."
