#!/usr/bin/env bash
# Wait for an ArgoCD Application to reach Synced + Healthy
set -euo pipefail

APP_NAME="${1:?Usage: $0 <app-name> [timeout-seconds]}"
TIMEOUT="${2:-300}"
INTERVAL=10
ELAPSED=0

echo "Waiting for application '$APP_NAME' to sync (timeout: ${TIMEOUT}s)..."

while [ "$ELAPSED" -lt "$TIMEOUT" ]; do
  SYNC=$(kubectl get application "$APP_NAME" -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "")
  HEALTH=$(kubectl get application "$APP_NAME" -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null || echo "")

  if [ "$SYNC" = "Synced" ] && [ "$HEALTH" = "Healthy" ]; then
    echo "Application '$APP_NAME' is Synced and Healthy."
    return 0 2>/dev/null || exit 0
  fi

  echo "  Sync: ${SYNC:-Pending} / Health: ${HEALTH:-Pending} (${ELAPSED}s/${TIMEOUT}s)"
  sleep "$INTERVAL"
  ELAPSED=$((ELAPSED + INTERVAL))
done

echo "ERROR: Timed out waiting for application '$APP_NAME' after ${TIMEOUT}s"
exit 1
