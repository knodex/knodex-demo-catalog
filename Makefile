.PHONY: bootstrap demo clean argocd-password verify preflight install-catalog install-catalog-local _wait-for-catalog

CLUSTER_NAME := mgmt
KIND_CONFIG := scripts/kind-config.yaml
ARGOCD_NAMESPACE := argocd
ARGOCD_MANIFEST := https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
CHART_OCI := oci://ghcr.io/knodex/charts/knodex-demo-catalog
CHART_LOCAL := charts/knodex-demo-catalog
RELEASE_NAME := knodex-demo-catalog
CHART_NAMESPACE := knodex
CAPI_WAIT_TIMEOUT := 300
ARGOCD_WAIT_TIMEOUT := 300
KRO_WAIT_TIMEOUT := 120
WORKLOAD_CLUSTER_NAME := my-cluster

## preflight: Check all prerequisites are installed
preflight:
	@./scripts/check-prerequisites.sh

## bootstrap: Create management cluster, install CAPI + ArgoCD + Knodex catalog (RGDs ready for UI demo)
bootstrap: preflight
	@if kind get clusters 2>/dev/null | grep -qx '$(CLUSTER_NAME)'; then \
		echo "==> Kind cluster '$(CLUSTER_NAME)' already exists, skipping creation."; \
	else \
		echo "==> Creating Kind cluster '$(CLUSTER_NAME)'..."; \
		kind create cluster --name $(CLUSTER_NAME) --config $(KIND_CONFIG) --wait 60s; \
		echo "==> Kind cluster '$(CLUSTER_NAME)' created."; \
	fi

	@echo "==> Initializing Cluster API with Docker infrastructure provider..."
	@if kubectl get providers -A 2>/dev/null | grep -q infrastructure-docker; then \
		echo "    CAPI already initialized, skipping."; \
	else \
		clusterctl init --infrastructure docker --wait-providers --wait-provider-timeout 300 2>&1 | grep -v 'unrecognized format'; \
	fi
	@echo "==> Waiting for CAPI components to become ready..."
	@./scripts/wait-for-pods.sh capi-system $(CAPI_WAIT_TIMEOUT)
	@./scripts/wait-for-pods.sh capd-system $(CAPI_WAIT_TIMEOUT)
	@./scripts/wait-for-pods.sh capi-kubeadm-bootstrap-system $(CAPI_WAIT_TIMEOUT)
	@./scripts/wait-for-pods.sh capi-kubeadm-control-plane-system $(CAPI_WAIT_TIMEOUT)
	@echo "==> CAPI components are ready."

	@echo "==> Installing ArgoCD..."
	@kubectl create namespace $(ARGOCD_NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	@kubectl apply -n $(ARGOCD_NAMESPACE) -f $(ARGOCD_MANIFEST) --server-side --force-conflicts 2>&1 | grep -v 'unrecognized format'
	@echo "==> Waiting for ArgoCD components to become ready..."
	@./scripts/wait-for-pods.sh $(ARGOCD_NAMESPACE) $(ARGOCD_WAIT_TIMEOUT)
	@echo "==> ArgoCD is ready."

	@echo ""
	@$(MAKE) --no-print-directory install-catalog
	@echo ""
	@$(MAKE) --no-print-directory verify
	@echo ""
	@helm get notes $(RELEASE_NAME) -n $(CHART_NAMESPACE)

## install-catalog: Install the Knodex demo catalog from OCI registry
install-catalog:
	@echo "==> Installing Knodex demo catalog from OCI registry..."
	@if helm status $(RELEASE_NAME) -n $(CHART_NAMESPACE) >/dev/null 2>&1; then \
		echo "    Chart already installed, upgrading..."; \
		helm upgrade $(RELEASE_NAME) $(CHART_OCI) \
			--namespace $(CHART_NAMESPACE) \
			--set kro.enabled=true 2>&1 | grep -v 'unrecognized format'; \
	else \
		helm install $(RELEASE_NAME) $(CHART_OCI) \
			--namespace $(CHART_NAMESPACE) \
			--create-namespace \
			--set kro.enabled=true 2>&1 | grep -v 'unrecognized format'; \
	fi
	@$(MAKE) --no-print-directory _wait-for-catalog

## install-catalog-local: Install the Knodex demo catalog from local source (for development)
install-catalog-local:
	@echo "==> Installing Knodex demo catalog from local source..."
	@helm dependency update $(CHART_LOCAL) --skip-refresh 2>/dev/null || helm dependency update $(CHART_LOCAL)
	@if helm status $(RELEASE_NAME) -n $(CHART_NAMESPACE) >/dev/null 2>&1; then \
		echo "    Chart already installed, upgrading..."; \
		helm upgrade $(RELEASE_NAME) $(CHART_LOCAL) \
			--namespace $(CHART_NAMESPACE) \
			--set kro.enabled=true 2>&1 | grep -v 'unrecognized format'; \
	else \
		helm install $(RELEASE_NAME) $(CHART_LOCAL) \
			--namespace $(CHART_NAMESPACE) \
			--create-namespace \
			--set kro.enabled=true 2>&1 | grep -v 'unrecognized format'; \
	fi
	@$(MAKE) --no-print-directory _wait-for-catalog

## _wait-for-catalog: Internal target to wait for Kro and RGDs
_wait-for-catalog:
	@echo "==> Waiting for Kro to become ready..."
	@kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=kro -n $(CHART_NAMESPACE) --timeout=$(KRO_WAIT_TIMEOUT)s
	@echo "==> Kro is ready."
	@echo "==> Waiting for RGDs to become active..."
	@sleep 5
	@ACTIVE=$$(kubectl get rgd --no-headers 2>/dev/null | grep -c "Active"); \
		TOTAL=$$(kubectl get rgd --no-headers 2>/dev/null | wc -l | tr -d ' '); \
		echo "    RGDs active: $$ACTIVE/$$TOTAL"; \
		if [ "$$ACTIVE" -ne "$$TOTAL" ]; then \
			echo "    WARNING: Not all RGDs are active. Check: kubectl describe rgd"; \
		fi
	@echo "==> Knodex demo catalog installed."

## demo: Full end-to-end demo — bootstrap + create workload cluster + register with ArgoCD + deploy podinfo
demo: bootstrap
	@echo ""
	@echo "==> Creating workload cluster '$(WORKLOAD_CLUSTER_NAME)'..."
	@kubectl apply -f - <<< '{ \
		"apiVersion": "kro.run/v1alpha1", \
		"kind": "KindCluster", \
		"metadata": { "name": "$(WORKLOAD_CLUSTER_NAME)" }, \
		"spec": { "clusterName": "$(WORKLOAD_CLUSTER_NAME)", "kubernetesVersion": "v1.31.0", "workerCount": 1 } \
	}'

	@echo "==> Registering cluster with ArgoCD..."
	@kubectl apply -f - <<< '{ \
		"apiVersion": "kro.run/v1alpha1", \
		"kind": "ArgocdClusterRegistration", \
		"metadata": { "name": "$(WORKLOAD_CLUSTER_NAME)" }, \
		"spec": { "clusterName": "$(WORKLOAD_CLUSTER_NAME)", "externalRef": { "targetCluster": { "name": "$(WORKLOAD_CLUSTER_NAME)", "namespace": "default" } } } \
	}'

	@echo "==> Waiting for cluster to be provisioned..."
	@./scripts/wait-for-cluster.sh $(WORKLOAD_CLUSTER_NAME) $(CAPI_WAIT_TIMEOUT)

	@echo "==> Deploying sample application (podinfo)..."
	@kubectl apply -f - <<< '{ \
		"apiVersion": "kro.run/v1alpha1", \
		"kind": "ApplicationDeployment", \
		"metadata": { "name": "podinfo" }, \
		"spec": { "appName": "podinfo", "repoURL": "https://github.com/stefanprodan/podinfo", "path": "kustomize", "targetRevision": "master", "externalRef": { "targetCluster": { "name": "$(WORKLOAD_CLUSTER_NAME)", "namespace": "default" } } } \
	}'

	@echo "==> Waiting for application to sync..."
	@./scripts/wait-for-app.sh podinfo $(ARGOCD_WAIT_TIMEOUT)
	@echo ""
	@echo "==> Demo complete!"
	@echo "    Workload cluster: $(WORKLOAD_CLUSTER_NAME)"
	@echo "    Application:      podinfo (Synced + Healthy)"
	@echo ""
	@echo "    ArgoCD UI:  kubectl port-forward svc/argocd-server -n argocd 8080:443"
	@echo "    Password:   make argocd-password"

## verify: Verify the management cluster is healthy
verify:
	@echo "==> Verifying management cluster..."
	@echo ""
	@echo "--- Kind cluster ---"
	@kind get clusters 2>/dev/null | grep -qx '$(CLUSTER_NAME)' && echo "  OK: Cluster '$(CLUSTER_NAME)' exists" || (echo "  FAIL: Cluster '$(CLUSTER_NAME)' not found" && exit 1)
	@echo ""
	@echo "--- CAPI providers ---"
	@if ! kubectl get providers -A --no-headers 2>/dev/null | grep -q .; then \
		echo "  FAIL: No CAPI providers found (CRDs may not be installed)"; exit 1; \
	fi
	@kubectl get providers -A --no-headers 2>/dev/null | while read -r ns name rest; do echo "  OK: $$name ($$ns)"; done
	@kubectl get providers -A --no-headers 2>/dev/null | grep -q infrastructure-docker || (echo "  FAIL: infrastructure-docker provider not found" && exit 1)
	@echo ""
	@echo "--- ArgoCD ---"
	@kubectl get pods -n $(ARGOCD_NAMESPACE) --no-headers 2>/dev/null | while read -r name ready status rest; do echo "  $$status: $$name ($$ready)"; done
	@HEALTHY=$$(kubectl get deployments -n $(ARGOCD_NAMESPACE) --no-headers 2>/dev/null | awk '{split($$2,a,"/"); if(a[1]==a[2]) c++} END{print c+0}'); \
		TOTAL=$$(kubectl get deployments -n $(ARGOCD_NAMESPACE) --no-headers 2>/dev/null | wc -l | tr -d ' '); \
		echo ""; \
		echo "  Deployments ready: $$HEALTHY/$$TOTAL"; \
		if [ "$$HEALTHY" -ne "$$TOTAL" ]; then echo "  WARNING: Not all ArgoCD deployments are ready"; fi
	@echo ""
	@echo "--- ArgoCD API health ---"
	@kubectl -n $(ARGOCD_NAMESPACE) get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" >/dev/null 2>&1 \
		&& echo "  OK: Admin credentials accessible" \
		|| (echo "  FAIL: Cannot retrieve admin credentials" && exit 1)
	@echo ""
	@echo "--- Knodex catalog ---"
	@if helm status $(RELEASE_NAME) -n $(CHART_NAMESPACE) >/dev/null 2>&1; then \
		echo "  OK: Helm release '$(RELEASE_NAME)' installed"; \
		kubectl get rgd --no-headers 2>/dev/null | while read -r name apiver kind state rest; do echo "  $$state: $$name ($$kind)"; done; \
	else \
		echo "  FAIL: Helm release '$(RELEASE_NAME)' not found"; \
	fi
	@echo ""
	@echo "==> Verification complete."
	@echo "    To access ArgoCD UI: kubectl port-forward svc/argocd-server -n $(ARGOCD_NAMESPACE) 8080:443"
	@echo "    To get admin password: make argocd-password"

## clean: Delete the Kind management cluster
clean:
	@echo "==> Deleting Kind cluster '$(CLUSTER_NAME)'..."
	@kind delete cluster --name $(CLUSTER_NAME)
	@echo "==> Cluster '$(CLUSTER_NAME)' deleted."

## argocd-password: Retrieve the ArgoCD admin password
argocd-password:
	@kubectl -n $(ARGOCD_NAMESPACE) get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 --decode && echo
