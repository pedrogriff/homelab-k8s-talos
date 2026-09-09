# Hybrid GCP Cloud Integration & Keyless Disaster Recovery

Enterprise hybrid cloud architecture connecting on-premises bare-metal Talos Linux Kubernetes workloads to Google Cloud Platform using **Keyless Workload Identity Federation (WIF)**, **3-2-1 GCS Disaster Recovery with Velero**, and **Hybrid Cloud Trace Mirroring**.

---

## 🏛️ Architecture Overview

```
                      +-------------------------------------------------------------+
                      |                 Google Cloud Platform (GCP)                 |
                      |                                                             |
                      |  +---------------------------+  +------------------------+  |
                      |  |   Workload Identity Pool  |  | Cloud Storage (GCS) DR |  |
                      |  |   (talos-homelab-pool)    |  | (Tiered: Nearline ->   |  |
                      |  +-------------^-------------+  |  Coldline -> Archive)  |  |
                      |                |                +-----------^------------+  |
                      |                | OIDC STS Token             | 3-2-1 Offsite |
                      |                | Exchange                   | Backup Stream |
                      +----------------|----------------------------|---------------+
                                       |                            |
=======================================|============================|================
On-Premises Bare-Metal Talos Linux     |                            |
                                       |                            |
  +------------------------------------|----------------------------|---------------+
  |  Kubernetes Control Plane (OIDC)   |                            |               |
  |  Issuer: https://10.0.0.170:6443   |                            |               |
  +------------------------------------+                            |               |
                                                                    |               |
  +--------------------------+                         +------------+------------+  |
  | OpenTelemetry Collector  |                         |      Velero Server      |  |
  | (OTel Contrib 0.119.0)   |                         |   (velero-plugin-gcp)   |  |
  | - Projected ServiceToken |                         | - Projected Token       |  |
  | - Mirrors spans to GCP   |                         | - Offsite GCS BSL       |  |
  |   Cloud Trace            |                         +-------------------------+  |
  +--------------------------+                                                      |
=====================================================================================
```

---

## 🔒 Security & SRE Rationale

1. **Zero Static Service Account Keys (Zero-Trust Identity)**:
   - Traditional on-premises to cloud integrations often rely on long-lived static service account JSON keys. These are high-risk vectors for credential compromise, secret sprawl, and audit failures.
   - We utilize **GCP Workload Identity Federation (RFC 7523 / OIDC)**:
     - Talos Linux kubelet projects short-lived, cryptographically signed JSON Web Tokens (`ServiceAccountTokenProjection`) into pods.
     - Google STS (`sts.googleapis.com`) verifies the signature against the Talos Kubernetes OIDC discovery endpoint (`/.well-known/openid-configuration`).
     - Temporary access tokens are minted on-demand with automatic rotation every hour.

2. **Enterprise 3-2-1 Disaster Recovery Strategy**:
   - **3 Copies of Data**:
     1. Live Production NVMe PVCs (PostgreSQL, Redis, Vault, etc.).
     2. Local On-Premises Fast Backups (MinIO S3 via `velero-plugin-for-aws`).
     3. Offsite Geographically Redundant Cloud Archive (Google Cloud Storage via `velero-plugin-for-gcp`).
   - **2 Media Types**: High-speed local block/NVMe storage and remote cloud object storage.
   - **1 Offsite Location**: Google Cloud Storage in `us-central1` with automated lifecycle transitions:
     - **Day 0 - 90**: `NEARLINE` storage class (low-latency recovery for recent incidents).
     - **Day 90 - 180**: `COLDLINE` storage class (cost-effective retention).
     - **Day 180+**: `ARCHIVE` storage class (compliance & regulatory SOX archiving).

3. **Least-Privilege Role Bindings**:
   - `velero-talos-dr-sa`: Strictly bounded to `roles/storage.objectAdmin` on the DR bucket only. No project-level storage permissions.
   - `otel-collector-telemetry-sa`: Granted only `roles/cloudtrace.agent` and `roles/monitoring.metricWriter`. Cannot read customer data or alter cluster state.

---

## 🚀 Deployment Instructions

### Prerequisites
- OpenTofu >= 1.5.0 (or Terraform >= 1.5.0)
- Authenticated `gcloud` CLI with project owner or IAM admin rights

### 1. Initialize & Review Plan
```bash
cp terraform.tfvars.example terraform.tfvars
# Customize project_id, project_number, and bucket_name

tofu init
tofu plan -out=tfplan
```

### 2. Apply Infrastructure
```bash
tofu apply tfplan
```

### 3. Generated Artifacts
Applying the Terraform code produces two credential configuration files:
- `generated/velero-credentials.json`
- `generated/otel-credentials.json`

These files define the external account configuration pointing to the projected token path (`/var/run/secrets/tokens/gcp-token`) and the respective impersonated GCP service account.
