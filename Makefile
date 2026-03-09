.PHONY: bootstrap clean argocd-password verify preflight

CLUSTER_NAME := mgmt
KIND_CONFIG := scripts/kind-config.yaml
ARGOCD_NAMESPACE := argocd
ARGOCD_MANIFEST := https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
CAPI_WAIT_TIMEOUT := 300
ARGOCD_WAIT_TIMEOUT := 300

## preflight: Check all prerequisites are installed
preflight:
	@./scripts/check-prerequisites.sh

## bootstrap: Create Kind management cluster with CAPI (CAPD) and ArgoCD
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
		clusterctl init --infrastructure docker --wait-providers --wait-provider-timeout 300; \
	fi
	@echo "==> Waiting for CAPI components to become ready..."
	@./scripts/wait-for-pods.sh capi-system $(CAPI_WAIT_TIMEOUT)
	@./scripts/wait-for-pods.sh capd-system $(CAPI_WAIT_TIMEOUT)
	@./scripts/wait-for-pods.sh capi-kubeadm-bootstrap-system $(CAPI_WAIT_TIMEOUT)
	@./scripts/wait-for-pods.sh capi-kubeadm-control-plane-system $(CAPI_WAIT_TIMEOUT)
	@echo "==> CAPI components are ready."

	@echo "==> Installing ArgoCD..."
	@kubectl create namespace $(ARGOCD_NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	@kubectl apply -n $(ARGOCD_NAMESPACE) -f $(ARGOCD_MANIFEST) --server-side --force-conflicts
	@echo "==> Waiting for ArgoCD components to become ready..."
	@./scripts/wait-for-pods.sh $(ARGOCD_NAMESPACE) $(ARGOCD_WAIT_TIMEOUT)
	@echo "==> ArgoCD is ready."

	@echo ""
	@$(MAKE) --no-print-directory verify

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
