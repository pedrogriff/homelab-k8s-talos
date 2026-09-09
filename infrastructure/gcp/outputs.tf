# ==============================================================================
# Outputs for GCP Hybrid Infrastructure, Workload Identity & DR Storage
# ==============================================================================

output "gcs_dr_bucket_name" {
  description = "The name of the GCS 3-2-1 disaster recovery bucket."
  value       = google_storage_bucket.dr_bucket.name
}

output "gcs_dr_bucket_url" {
  description = "The gs:// URI of the GCS disaster recovery bucket."
  value       = google_storage_bucket.dr_bucket.url
}

output "workload_identity_pool_name" {
  description = "The full resource name of the Workload Identity Pool."
  value       = google_iam_workload_identity_pool.talos_pool.name
}

output "workload_identity_pool_id" {
  description = "The identifier of the Workload Identity Pool."
  value       = google_iam_workload_identity_pool.talos_pool.workload_identity_pool_id
}

output "workload_identity_provider_name" {
  description = "The full resource name of the Workload Identity Provider."
  value       = google_iam_workload_identity_pool_provider.talos_provider.name
}

output "workload_identity_provider_id" {
  description = "The identifier of the Workload Identity Provider."
  value       = google_iam_workload_identity_pool_provider.talos_provider.workload_identity_pool_provider_id
}

output "workload_identity_audience" {
  description = "The standard audience string required for Kubernetes projected service account tokens."
  value       = "//iam.googleapis.com/projects/${var.gcp_project_number}/locations/global/workloadIdentityPools/${google_iam_workload_identity_pool.talos_pool.workload_identity_pool_id}/providers/${google_iam_workload_identity_pool_provider.talos_provider.workload_identity_pool_provider_id}"
}

output "velero_service_account_email" {
  description = "The email address of the GCP service account for Velero offsite DR."
  value       = google_service_account.velero_sa.email
}

output "otel_collector_service_account_email" {
  description = "The email address of the GCP service account for OpenTelemetry Collector."
  value       = google_service_account.otel_sa.email
}

output "velero_credential_configuration" {
  description = "External account credential configuration JSON for Velero Workload Identity Federation."
  value = jsonencode({
    type               = "external_account"
    audience           = "//iam.googleapis.com/projects/${var.gcp_project_number}/locations/global/workloadIdentityPools/${google_iam_workload_identity_pool.talos_pool.workload_identity_pool_id}/providers/${google_iam_workload_identity_pool_provider.talos_provider.workload_identity_pool_provider_id}"
    subject_token_type = "urn:ietf:params:oauth:token-type:jwt"
    token_url          = "https://sts.googleapis.com/v1/token"
    credential_source = {
      file = "/var/run/secrets/tokens/gcp-token"
    }
    service_account_impersonation_url = "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/${google_service_account.velero_sa.email}:generateAccessToken"
  })
}

output "otel_credential_configuration" {
  description = "External account credential configuration JSON for OpenTelemetry Collector Workload Identity Federation."
  value = jsonencode({
    type               = "external_account"
    audience           = "//iam.googleapis.com/projects/${var.gcp_project_number}/locations/global/workloadIdentityPools/${google_iam_workload_identity_pool.talos_pool.workload_identity_pool_id}/providers/${google_iam_workload_identity_pool_provider.talos_provider.workload_identity_pool_provider_id}"
    subject_token_type = "urn:ietf:params:oauth:token-type:jwt"
    token_url          = "https://sts.googleapis.com/v1/token"
    credential_source = {
      file = "/var/run/secrets/tokens/gcp-token"
    }
    service_account_impersonation_url = "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/${google_service_account.otel_sa.email}:generateAccessToken"
  })
}
