# ==============================================================================
# Main Terraform Architecture: GCS 3-2-1 DR Bucket & Workload Identity Pool
# ==============================================================================

locals {
  apis = var.enable_required_apis ? [
    "iam.googleapis.com",
    "storage.googleapis.com",
    "sts.googleapis.com",
    "iamcredentials.googleapis.com",
    "cloudtrace.googleapis.com",
    "monitoring.googleapis.com",
  ] : []
}

# 1. Enable Required GCP Service APIs
resource "google_project_service" "required_apis" {
  for_each           = toset(local.apis)
  project            = var.gcp_project_id
  service            = each.key
  disable_on_destroy = false
}

# 2. Enterprise 3-2-1 GCS Disaster Recovery Bucket (CIS GCP Hardened)
resource "google_storage_bucket" "dr_bucket" {
  name          = var.gcs_dr_bucket_name
  location      = var.gcp_region
  storage_class = var.gcs_storage_class

  # Enforce uniform bucket-level access (disables legacy ACLs for security)
  uniform_bucket_level_access = true

  # Protect against accidental deletion or ransomware corruption
  versioning {
    enabled = true
  }

  # Automated Tiered Storage Lifecycle Policy
  lifecycle_rule {
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
    condition {
      age = 90
    }
  }

  lifecycle_rule {
    action {
      type          = "SetStorageClass"
      storage_class = "ARCHIVE"
    }
    condition {
      age = 180
    }
  }

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      num_newer_versions = 5
      days_since_noncurrent_time = 365
    }
  }

  labels = {
    environment = var.environment
    managed_by  = "terraform"
    cluster     = var.k8s_cluster_name
    tier        = "disaster-recovery"
  }

  depends_on = [google_project_service.required_apis]
}

# 3. IAM Workload Identity Pool for On-Premises Talos Cluster
resource "google_iam_workload_identity_pool" "talos_pool" {
  workload_identity_pool_id = "talos-homelab-pool"
  display_name              = "Talos Homelab Workload Identity Pool"
  description               = "Keyless OIDC federation for bare-metal Talos Linux Kubernetes workloads"
  disabled                  = false

  depends_on = [google_project_service.required_apis]
}

# 4. Workload Identity Pool Provider (OIDC Trust Configuration)
resource "google_iam_workload_identity_pool_provider" "talos_provider" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.talos_pool.workload_identity_pool_id
  workload_identity_pool_provider_id = "talos-k8s-provider"
  display_name                       = "Talos K8s OIDC Provider"
  description                        = "Trusts Talos Kubernetes ServiceAccount projected tokens"

  attribute_mapping = {
    "google.subject"           = "assertion.sub"
    "attribute.namespace"      = "assertion['kubernetes.io']['namespace']"
    "attribute.serviceaccount" = "assertion['kubernetes.io']['serviceaccount']['name']"
    "attribute.pod"            = "assertion['kubernetes.io']['pod']['name']"
  }

  oidc {
    issuer_uri        = var.k8s_oidc_issuer_url
    allowed_audiences = [
      "//iam.googleapis.com/projects/${var.gcp_project_number}/locations/global/workloadIdentityPools/${google_iam_workload_identity_pool.talos_pool.workload_identity_pool_id}/providers/talos-k8s-provider"
    ]
  }
}

# 5. Service Account for Velero Offsite DR
resource "google_service_account" "velero_sa" {
  account_id   = "velero-talos-dr-sa"
  display_name = "Velero Offsite Backup Service Account"
  description  = "Impersonated by Velero server pod in Talos to store offsite backups in GCS"
}

# Grant Velero SA ObjectAdmin privileges on the DR Bucket ONLY (Principle of Least Privilege)
resource "google_storage_bucket_iam_member" "velero_bucket_admin" {
  bucket = google_storage_bucket.dr_bucket.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.velero_sa.email}"
}

# Allow Velero Kubernetes ServiceAccount to impersonate the GCP Service Account keylessly
resource "google_service_account_iam_member" "velero_workload_identity_user" {
  service_account_id = google_service_account.velero_sa.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principal://iam.googleapis.com/${google_iam_workload_identity_pool.talos_pool.name}/subject/system:serviceaccount:velero:velero-server"
}

# 6. Service Account for OpenTelemetry Collector (Hybrid Cloud Trace)
resource "google_service_account" "otel_sa" {
  account_id   = "otel-collector-telemetry-sa"
  display_name = "OpenTelemetry Collector Cloud Trace SA"
  description  = "Impersonated by OpenTelemetry Collector in Talos to mirror traces to GCP Cloud Trace"
}

# Grant Cloud Trace Agent role to write distributed trace spans to Google Cloud Trace
resource "google_project_iam_member" "otel_trace_agent" {
  project = var.gcp_project_id
  role    = "roles/cloudtrace.agent"
  member  = "serviceAccount:${google_service_account.otel_sa.email}"
}

# Grant Monitoring Metric Writer role for custom SLO metric export
resource "google_project_iam_member" "otel_metric_writer" {
  project = var.gcp_project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.otel_sa.email}"
}

# Allow OpenTelemetry Collector Kubernetes ServiceAccount to impersonate the GCP Service Account
resource "google_service_account_iam_member" "otel_workload_identity_user" {
  service_account_id = google_service_account.otel_sa.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principal://iam.googleapis.com/${google_iam_workload_identity_pool.talos_pool.name}/subject/system:serviceaccount:monitoring:otel-collector"
}

# 7. Local WIF Credential Configuration Files (Ready to mount as K8s ConfigMaps/Secrets)
resource "local_file" "velero_wif_config" {
  content = jsonencode({
    type                              = "external_account"
    audience                          = "//iam.googleapis.com/projects/${var.gcp_project_number}/locations/global/workloadIdentityPools/${google_iam_workload_identity_pool.talos_pool.workload_identity_pool_id}/providers/${google_iam_workload_identity_pool_provider.talos_provider.workload_identity_pool_provider_id}"
    subject_token_type                = "urn:ietf:params:oauth:token-type:jwt"
    token_url                         = "https://sts.googleapis.com/v1/token"
    credential_source = {
      file = "/var/run/secrets/tokens/gcp-token"
    }
    service_account_impersonation_url = "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/${google_service_account.velero_sa.email}:generateAccessToken"
  })
  filename = "${path.module}/generated/velero-credentials.json"
}

resource "local_file" "otel_wif_config" {
  content = jsonencode({
    type                              = "external_account"
    audience                          = "//iam.googleapis.com/projects/${var.gcp_project_number}/locations/global/workloadIdentityPools/${google_iam_workload_identity_pool.talos_pool.workload_identity_pool_id}/providers/${google_iam_workload_identity_pool_provider.talos_provider.workload_identity_pool_provider_id}"
    subject_token_type                = "urn:ietf:params:oauth:token-type:jwt"
    token_url                         = "https://sts.googleapis.com/v1/token"
    credential_source = {
      file = "/var/run/secrets/tokens/gcp-token"
    }
    service_account_impersonation_url = "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/${google_service_account.otel_sa.email}:generateAccessToken"
  })
  filename = "${path.module}/generated/otel-credentials.json"
}
