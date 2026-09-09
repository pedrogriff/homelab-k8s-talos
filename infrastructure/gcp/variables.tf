# ==============================================================================
# Variables for GCP Hybrid Infrastructure, Workload Identity & DR Storage
# ==============================================================================

variable "gcp_project_id" {
  type        = string
  description = "The target Google Cloud Platform project ID."
  default     = "pedrogriff-cloud-production"
}

variable "gcp_project_number" {
  type        = string
  description = "The numeric GCP Project Number (used for Workload Identity audience formats)."
  default     = "1087429184512"
}

variable "gcp_region" {
  type        = string
  description = "Default GCP Region for regional storage and resources."
  default     = "us-central1"
}

variable "environment" {
  type        = string
  description = "Deployment environment identifier."
  default     = "production"
}

variable "k8s_cluster_name" {
  type        = string
  description = "Identifier of the on-premises Talos Kubernetes cluster."
  default     = "talos-baremetal"
}

variable "k8s_oidc_issuer_url" {
  type        = string
  description = "The OIDC Issuer URL of the on-prem Talos cluster (from /.well-known/openid-configuration)."
  default     = "https://10.0.0.170:6443"
}

variable "gcs_dr_bucket_name" {
  type        = string
  description = "Name of the Google Cloud Storage bucket for offsite disaster recovery."
  default     = "pedrogriff-talos-dr-coldline"
}

variable "gcs_storage_class" {
  type        = string
  description = "Initial storage class for backup archives (e.g. NEARLINE, COLDLINE)."
  default     = "NEARLINE"
}

variable "enable_required_apis" {
  type        = bool
  description = "Whether Terraform should automatically enable required GCP APIs."
  default     = true
}
