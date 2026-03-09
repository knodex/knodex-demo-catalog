# Demo Catalog Azure

Demo Helm chart showcasing Azure Landing Zone Resource Graph Definitions (RGDs) for [Kro](https://kro.run).

## What's Included

| RGD | Kind | Description |
|-----|------|-------------|
| `aso-credential` | `ASOCredential` | Foundation credential for Azure Service Operator (Service Principal / Workload Identity) |
| `alz-hub` | `ALZHub` | Hub VNet with subnets for Firewall, Bastion, Gateway, and DNS Resolver |
| `alz-spoke-vnet` | `ALZSpokeVNet` | Spoke VNet peered to hub with NSG and firewall routing |

## Prerequisites

- Kubernetes 1.34+
- [Knodex](https://github.com/knodex/knodex) installed
- [Azure Service Operator](https://azure.github.io/azure-service-operator/) v2.13+

### Install Knodex

```bash
helm install knodex oci://ghcr.io/knodex/charts/knodex \
  --namespace knodex --create-namespace
```

Access the Knodex UI:
```bash
kubectl port-forward svc/knodex-server 8080:8080 -n knodex
```

## Installation

**From OCI registry:**
```bash
helm install knodex-demo-catalog oci://ghcr.io/knodex/charts/knodex-demo-catalog
```

## Usage

Once installed, the RGDs register new custom resource types in your cluster. Create instances to provision Azure infrastructure:

```yaml
apiVersion: kro.run/v1alpha1
kind: ASOCredential
metadata:
  name: my-credential
spec:
  name: my-credential
  subscriptionId: "<subscription-id>"
  tenantId: "<tenant-id>"
  clientId: "<client-id>"
  clientSecret: "<client-secret>"
```

```yaml
apiVersion: kro.run/v1alpha1
kind: ALZHub
metadata:
  name: my-hub
spec:
  name: my-hub
  location: canadacentral
```

```yaml
apiVersion: kro.run/v1alpha1
kind: ALZSpokeVNet
metadata:
  name: my-spoke
spec:
  name: my-spoke
  addressSpace: "10.1.0.0/16"
  externalRef:
    hubVnetRef:
      name: my-hub
      namespace: default
```
