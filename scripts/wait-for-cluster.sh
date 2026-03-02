#!/usr/bin/env bash
# Wait for a CAPI cluster to reach Provisioned phase
set -euo pipefail

CLUSTER_NAME="${1:?Usage: $0 <cluster-name> [timeout-seconds]}"
TIMEOUT="${2:-300}"
INTERVAL=10
ELAPSED=0

echo "Waiting for cluster '$CLUSTER_NAME' to be provisioned (timeout: ${TIMEOUT}s)..."

while [ "$ELAPSED" -lt "$TIMEOUT" ]; do
  PHASE=$(kubectl get cluster "$CLUSTER_NAME" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
  JOB_DONE=$(kubectl get job "${CLUSTER_NAME}-argocd-register" -o jsonpath='{.status.succeeded}' 2>/dev/null || echo "0")

  if [ "$PHASE" = "Provisioned" ] && [ "$JOB_DONE" = "1" ]; then
    echo "Cluster '$CLUSTER_NAME' is provisioned and registered with ArgoCD."
    return 0 2>/dev/null || exit 0
  fi

  echo "  Phase: ${PHASE:-Pending} | ArgoCD registered: $([ "$JOB_DONE" = "1" ] && echo "yes" || echo "no") (${ELAPSED}s/${TIMEOUT}s)"
  sleep "$INTERVAL"
  ELAPSED=$((ELAPSED + INTERVAL))
done

echo "ERROR: Timed out waiting for cluster '$CLUSTER_NAME' after ${TIMEOUT}s"
exit 1
