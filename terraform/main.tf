# okn — GCP relay for the ONAI node running on a DGX Spark
#
# The ONAI node runs on a DGX Spark in Insilica's residential cluster (spark1 as
# of Sept 2026 — see var.spark_tailscale_ip) which sits behind residential NAT
# with no static public IP. ONAI's protocol speaks TCP (inbound + outbound) and
# assumes a static IP for us.
#
# This module provisions a small GCP VM with a reserved static external IP that
# joins the same Tailscale tailnet as the Spark and relays TCP between the public
# internet and the Spark over the tailnet. okn.toxindex.com -> this relay's IP.
#
#   external ONAI nodes  <--TCP-->  relay (static IP)  <--Tailscale-->  spark1
#
# Conventions match the other toxindex services (yard, sdag/flow): project
# "toxindex", region us-central1, GCS-backed state.
#
# Deploy:  terraform init && terraform apply
# Destroy: terraform destroy   (releases the static IP — DNS must be updated)

terraform {
  required_version = ">= 1.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  backend "gcs" {
    bucket = "toxindex-terraform-state"
    prefix = "okn"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

variable "project_id" {
  description = "GCP project ID"
  type        = string
  default     = "toxindex"
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP zone"
  type        = string
  default     = "us-central1-a"
}

variable "domain" {
  description = "Public domain that resolves to the relay (managed in Route53)"
  type        = string
  default     = "okn.toxindex.com"
}

variable "spark_tailscale_ip" {
  description = <<-EOT
    Tailscale IP of the DGX Spark that runs the ONAI node software.
    spark1 = 100.103.111.95 (current host). spark3 = 100.91.51.95 (fallback).
    Changing this re-templates the relay's startup script (VM is recreated).
  EOT
  type        = string
  default     = "100.103.111.95"
}

variable "onai_ports" {
  description = <<-EOT
    TCP ports the ONAI node listens on, relayed from the public internet to
    the Spark over Tailscale. ONAI has not yet specified the port(s) — confirm with
    Guha before apply. Placeholder kept narrow on purpose.
  EOT
  type        = list(number)
  default     = [] # TODO(guha): set the real ONAI TCP port(s)
}

variable "tailscale_auth_key" {
  description = <<-EOT
    Tailscale auth key used by the relay to join the tailnet unattended.
    Prefer a reusable, pre-approved, tagged ephemeral key (tag:relay). Provide
    via TF_VAR_tailscale_auth_key or a non-committed terraform.tfvars.
  EOT
  type        = string
  sensitive   = true
}

resource "google_project_service" "apis" {
  for_each = toset([
    "compute.googleapis.com",
    "secretmanager.googleapis.com",
  ])

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

output "relay_ip" {
  value       = google_compute_address.okn_relay.address
  description = "Static external IP for the relay — point okn.toxindex.com here"
}

output "dns_instructions" {
  value       = "Create A record: ${var.domain} -> ${google_compute_address.okn_relay.address} (Route53 zone Z01199351P9ECYL3NLKM0)"
  description = "Route53 record to create after apply"
}
