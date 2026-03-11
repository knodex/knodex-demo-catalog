# Knodex Demo Catalog

A demo Helm chart showcasing [Kro](https://kro.run) Resource Graph Definitions (RGDs) for provisioning Kubernetes clusters and deploying applications — all from a local Kind management cluster.

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
│  │       Sample App (guestbook)                     │    │
│  └──────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────┘
```

## Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| [Docker Desktop](https://www.docker.com/products/docker-desktop/) | Latest | Container runtime for Kind clusters |
| [Kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation) | Latest | Local Kubernetes clusters in Docker |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | v1.30+ | Kubernetes CLI |
| [clusterctl](https://cluster-api.sigs.k8s.io/user/quick-start#install-clusterctl) | v1.x | Cluster API management tool |
| [Helm](https://helm.sh/docs/intro/install/) | v3.x | Kubernetes package manager |

> **Note:** Docker must be running with at least **4 GB of RAM** allocated.

## Quick Start

```bash
make demo
```

This creates the `mgmt` Kind cluster and installs:
- **Cluster API** with the Docker infrastructure provider (CAPD)
- **ArgoCD** for GitOps-based application deployment
- **Knodex UI** for browsing and deploying Kro RGDs
- **Knodex demo catalog** Helm chart with Kro + three RGDs
- **ClusterResourceSet** for automatic CNI (kindnet) installation on workload clusters

Once complete, access the Knodex UI:

```bash
kubectl port-forward svc/knodex-server -n knodex 3000:8080
```

Open http://localhost:3000 — **Username:** `admin`, **Password:**

```bash
kubectl -n knodex get secret knodex-initial-admin-password -o jsonpath="{.data.password}" | base64 -d
```

ArgoCD is also available:

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Open https://localhost:8080 — **Username:** `admin`, **Password:**

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

> **Note:** This demo catalog exposes credentials in resource status fields for convenience. This is intended for **local development and demonstration only** — do not use this pattern in production.

## Using the UI

After `make demo`, use the Knodex UI to walk through the demo:

1. **Create a workload cluster** — Create a `KindCluster` resource. This provisions a new Kubernetes cluster via CAPD. The CNI (kindnet) is automatically installed via a ClusterResourceSet.

2. **Register the cluster with ArgoCD** — Create an `ArgocdClusterRegistration` resource pointing to your new cluster. This extracts CAPI credentials and registers the cluster with ArgoCD.

3. **Deploy an application** — Create an `ApplicationDeployment` resource. This creates an ArgoCD Application that deploys to the registered workload cluster via GitOps.

## Full Automated Demo

To run all three steps automatically (bootstrap + workload cluster + sample app):

```bash
make demo-full
```

## Cleanup

```bash
make clean
```

This deletes the Kind management cluster (`mgmt`), which also removes all workload clusters running inside it.
