# Knodex Demo Catalog

A demo Helm chart showcasing [Kro](https://kro.run) Resource Graph Definitions (RGDs) for provisioning Kubernetes clusters and deploying applications — all from a local Kind management cluster.

**What you'll accomplish:** Bootstrap a local management cluster with Cluster API, ArgoCD, and Kro RGD templates — then create workload clusters and deploy applications using declarative Kubernetes manifests.

```
┌──────────────────────────────────────────────────────────┐
│                 Management Cluster (mgmt)                │
│                                                          │
│  ┌──────────┐  ┌──────────┐  ┌─────────────────────────┐│
│  │ Cluster  │  │  ArgoCD  │  │   Kro + RGDs            ││
│  │   API    │  │ (GitOps) │  │ - KindCluster           ││
│  │  (CAPD)  │  │          │  │ - ArgocdClusterReg.     ││
│  └────┬─────┘  └────┬─────┘  │ - ApplicationDeployment ││
│       │              │        └─────────────────────────┘│
│       │              │                                    │
└───────┼──────────────┼────────────────────────────────────┘
        │              │
        │ provisions   │ deploys app via GitOps
        ▼              ▼
┌──────────────────────────────────────────────────────────┐
│               Workload Cluster (my-cluster)              │
│                                                          │
│  ┌──────────────────────────────────────────────────┐    │
│  │         Sample App (podinfo)                     │    │
│  └──────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────┘
```

## Quick Start

### Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| [Docker Desktop](https://www.docker.com/products/docker-desktop/) | Latest | Container runtime for Kind clusters |
| [Kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation) | Latest | Local Kubernetes clusters in Docker |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | v1.30+ | Kubernetes CLI |
| [clusterctl](https://cluster-api.sigs.k8s.io/user/quick-start#install-clusterctl) | v1.x | Cluster API management tool |
| [Helm](https://helm.sh/docs/intro/install/) | v3.x | Kubernetes package manager |

> **Note:** Docker must be running with at least **4 GB of RAM** allocated.

### Option A: Bootstrap for Live Demo (default)

Sets up the management cluster with all RGDs ready — create workload clusters and deploy apps from the UI.

```bash
make bootstrap
```

This creates the `mgmt` Kind cluster and installs:
- **Cluster API** with the Docker infrastructure provider (CAPD)
- **ArgoCD** for GitOps-based application deployment
- **Knodex demo catalog** Helm chart with Kro + three RGDs
- **ClusterResourceSet** for automatic CNI (kindnet) installation on workload clusters

Once complete, open the ArgoCD UI to create resources interactively:

```bash
# Get the admin password
make argocd-password

# Port-forward to ArgoCD
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Open https://localhost:8080 — **Username:** `admin`, **Password:** from above.

### Option B: Full End-to-End Demo

Runs everything automatically — bootstrap + workload cluster + sample app:

```bash
make demo
```

This does everything in Option A, plus:
- Creates a workload cluster (`my-cluster`) via the KindCluster RGD
- Registers it with ArgoCD via the ArgocdClusterRegistration RGD
- Deploys [podinfo](https://github.com/stefanprodan/podinfo) via the ApplicationDeployment RGD

## RGDs Included

The chart installs three Resource Graph Definitions:

| RGD | Kind | Purpose |
|-----|------|---------|
| `kind-cluster` | `KindCluster` | Provision workload clusters via CAPD |
| `argocd-cluster-register` | `ArgocdClusterRegistration` | Register clusters with the local ArgoCD |
| `deploy-application` | `ApplicationDeployment` | Deploy apps via ArgoCD GitOps |

Verify they're active:

```bash
kubectl get rgd
```

Expected output:

```
NAME                      APIVERSION   KIND                        STATE
argocd-cluster-register   v1alpha1     ArgocdClusterRegistration   Active
deploy-application        v1alpha1     ApplicationDeployment       Active
kind-cluster              v1alpha1     KindCluster                 Active
```

## Step-by-Step Usage

If you used `make bootstrap` (Option A), follow these steps to create resources manually or from the UI.

### 1. Create a Workload Cluster

```yaml
# my-cluster.yaml
apiVersion: kro.run/v1alpha1
kind: KindCluster
metadata:
  name: my-cluster
spec:
  clusterName: my-cluster
  kubernetesVersion: v1.31.0
  workerCount: 1
```

```bash
kubectl apply -f my-cluster.yaml
```

Monitor progress:

```bash
kubectl get kindcluster my-cluster -w
kubectl get cluster my-cluster -o jsonpath='{.status.phase}'
```

The CNI (kindnet) is automatically installed via a ClusterResourceSet — no manual step needed.

### 2. Register the Cluster with ArgoCD

```yaml
# my-cluster-argocd.yaml
apiVersion: kro.run/v1alpha1
kind: ArgocdClusterRegistration
metadata:
  name: my-cluster
spec:
  clusterName: my-cluster
  externalRef:
    targetCluster:
      name: my-cluster
      namespace: default
```

```bash
kubectl apply -f my-cluster-argocd.yaml
```

This runs a one-shot Job that extracts CAPI kubeconfig credentials and creates an ArgoCD cluster secret.

```bash
kubectl get argocdclusterregistration my-cluster
```

### 3. Deploy an Application

```yaml
# my-app.yaml
apiVersion: kro.run/v1alpha1
kind: ApplicationDeployment
metadata:
  name: podinfo
spec:
  appName: podinfo
  repoURL: https://github.com/stefanprodan/podinfo
  path: kustomize
  targetRevision: master
  externalRef:
    targetCluster:
      name: my-cluster
      namespace: default
```

> **Note:** The `externalRef.targetCluster` references the `ArgocdClusterRegistration` (not the KindCluster), ensuring the cluster is registered before deployment.

```bash
kubectl apply -f my-app.yaml
```

Verify:

```bash
kubectl get applicationdeployment podinfo
kubectl get application podinfo -n argocd
```

## What's Running Where

### Management Cluster (`mgmt`)

| Component | Namespace | Purpose |
|-----------|-----------|---------|
| Cluster API controllers | `capi-system` | Cluster lifecycle management |
| CAPD provider | `capd-system` | Docker-based infrastructure provider |
| KubeAdm bootstrap | `capi-kubeadm-bootstrap-system` | Node bootstrap configuration |
| KubeAdm control plane | `capi-kubeadm-control-plane-system` | Control plane management |
| ArgoCD | `argocd` | GitOps application delivery |
| Kro | `default` | RGD controller |
| RGDs | `default` | KindCluster, ArgocdClusterRegistration, ApplicationDeployment |
| ClusterResourceSet | `default` | Auto-installs kindnet CNI on workload clusters |

### Workload Cluster (`my-cluster`)

| Component | Namespace | Purpose |
|-----------|-----------|---------|
| kindnet CNI | `kube-system` | Pod networking (auto-installed via ClusterResourceSet) |
| Sample app (podinfo) | `default` | Deployed by ArgoCD via the ApplicationDeployment RGD |

## Useful Commands

```bash
# Management cluster
make verify                                     # Health check
make argocd-password                            # Get ArgoCD password
kubectl get rgd                                 # List all RGDs
kubectl get kindcluster                         # List KindCluster instances
kubectl get argocdclusterregistration           # List ArgoCD registrations
kubectl get applicationdeployment               # List app deployments
kubectl get clusters                            # List CAPI clusters
kubectl get machines                            # List CAPI machines
kubectl get applications -n argocd              # List ArgoCD apps
kubectl get clusterresourceset                  # List ClusterResourceSets

# ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

## Cleanup

Delete everything:

```bash
make clean
```

This deletes the Kind management cluster (`mgmt`), which also removes all workload clusters running inside it.

### Manual Cleanup

If `make clean` fails or you need to clean up partially:

```bash
# Delete individual resources first (in order)
kubectl delete applicationdeployment podinfo
kubectl delete argocdclusterregistration my-cluster
kubectl delete kindcluster my-cluster

# Wait for resources to be fully deleted, then tear down the cluster
kind delete cluster --name mgmt
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| `make bootstrap` hangs | Ensure Docker is running with 4GB+ RAM |
| CAPI pods not starting | Check `kubectl get pods -A` for crash loops; `make clean && make bootstrap` |
| Workload cluster stuck in `Provisioning` | Check `kubectl describe cluster my-cluster`; ensure Docker has resources |
| Nodes stuck in `NotReady` | Verify kindnet is running: `kubectl get clusterresourcesetbinding` |
| ArgoCD app not syncing | Verify cluster is registered: `kubectl get argocdclusterregistration` |
| `make argocd-password` fails | ArgoCD may not be fully ready; wait and retry |

## Development

### Install from Local Source

```bash
make install-catalog-local
```

Or manually:

```bash
helm dependency update charts/knodex-demo-catalog
helm install knodex-demo-catalog charts/knodex-demo-catalog \
  --namespace knodex --create-namespace --set kro.enabled=true
```

### Upgrade After Changes

```bash
helm upgrade knodex-demo-catalog charts/knodex-demo-catalog \
  --namespace knodex --set kro.enabled=true
```
