.PHONY: demo demo-full clean preflight

CLUSTER_NAME := mgmt
KIND_CONFIG := scripts/kind-config.yaml
ARGOCD_NAMESPACE := argocd
ARGOCD_MANIFEST := https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
CATALOG_OCI := oci://ghcr.io/knodex/charts/knodex-demo-catalog
CATALOG_RELEASE := knodex-demo-catalog
KNODEX_OCI := oci://ghcr.io/knodex/charts/knodex
KNODEX_VERSION := 0.1.0
KNODEX_RELEASE := knodex
NAMESPACE := knodex
CAPI_WAIT_TIMEOUT := 300
ARGOCD_WAIT_TIMEOUT := 300
KRO_WAIT_TIMEOUT := 120
KNODEX_WAIT_TIMEOUT := 120
WORKLOAD_CLUSTER_NAME := my-cluster

## preflight: Check all prerequisites are installed
preflight:
	@./scripts/check-prerequisites.sh

## demo: Bootstrap management cluster with Knodex UI + RGDs ready for live demo
demo: preflight
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
	@echo "==> Installing Knodex UI..."
	@if helm status $(KNODEX_RELEASE) -n $(NAMESPACE) >/dev/null 2>&1; then \
		helm upgrade $(KNODEX_RELEASE) $(KNODEX_OCI) \
			--version $(KNODEX_VERSION) \
			--namespace $(NAMESPACE) \
			--set-json 'global.imagePullSecrets=[]' \
			--set server.config.cookie.secure=false \
			--set kro.enabled=false 2>&1 | grep -v 'unrecognized format'; \
	else \
		helm install $(KNODEX_RELEASE) $(KNODEX_OCI) \
			--version $(KNODEX_VERSION) \
			--namespace $(NAMESPACE) \
			--create-namespace \
			--set-json 'global.imagePullSecrets=[]' \
			--set server.config.cookie.secure=false \
			--set kro.enabled=false 2>&1 | grep -v 'unrecognized format'; \
	fi
	@echo "==> Waiting for Knodex to become ready..."
	@kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=knodex -n $(NAMESPACE) --timeout=$(KNODEX_WAIT_TIMEOUT)s
	@echo "==> Knodex UI is ready."

	@echo ""
	@echo "==> Installing Knodex demo catalog..."
	@if helm status $(CATALOG_RELEASE) -n $(NAMESPACE) >/dev/null 2>&1; then \
		helm upgrade $(CATALOG_RELEASE) $(CATALOG_OCI) \
			--namespace $(NAMESPACE) \
			--set kro.enabled=true 2>&1 | grep -v 'unrecognized format'; \
	else \
		helm install $(CATALOG_RELEASE) $(CATALOG_OCI) \
			--namespace $(NAMESPACE) \
			--create-namespace \
			--set kro.enabled=true 2>&1 | grep -v 'unrecognized format'; \
	fi
	@echo "==> Waiting for Kro to become ready..."
	@kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=kro -n $(NAMESPACE) --timeout=$(KRO_WAIT_TIMEOUT)s
	@echo "==> Kro is ready."
	@echo "==> Waiting for RGDs to become active..."
	@sleep 5
	@ACTIVE=$$(kubectl get rgd --no-headers 2>/dev/null | grep -c "Active"); \
		TOTAL=$$(kubectl get rgd --no-headers 2>/dev/null | wc -l | tr -d ' '); \
		echo "    RGDs active: $$ACTIVE/$$TOTAL"; \
		if [ "$$ACTIVE" -ne "$$TOTAL" ]; then \
			echo "    WARNING: Not all RGDs are active. Check: kubectl describe rgd"; \
		fi
	@echo "==> Demo catalog installed."

	@echo ""
	@helm get notes $(CATALOG_RELEASE) -n $(NAMESPACE)

## demo-full: Full end-to-end — bootstrap + create workload cluster + register with ArgoCD + deploy podinfo
demo-full: demo
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

	@echo "==> Deploying sample application (guestbook)..."
	@kubectl apply -f - <<< '{ \
		"apiVersion": "kro.run/v1alpha1", \
		"kind": "ApplicationDeployment", \
		"metadata": { "name": "guestbook" }, \
		"spec": { "appName": "guestbook", "externalRef": { "targetCluster": { "name": "$(WORKLOAD_CLUSTER_NAME)", "namespace": "default" } } } \
	}'

	@echo "==> Waiting for application to sync..."
	@./scripts/wait-for-app.sh guestbook $(ARGOCD_WAIT_TIMEOUT)
	@echo ""
	@echo "==> Demo complete!"
	@echo "    Workload cluster: $(WORKLOAD_CLUSTER_NAME)"
	@echo "    Application:      guestbook (Synced + Healthy)"

## clean: Delete the Kind management cluster
clean:
	@echo "==> Deleting Kind cluster '$(CLUSTER_NAME)'..."
	@kind delete cluster --name $(CLUSTER_NAME)
	@echo "==> Cluster '$(CLUSTER_NAME)' deleted."
