# okn relay VM, static IP, Tailscale auth secret, firewall, and TCP forwarding.

# Reserved static external IP — this is the stable address ONAI connects to and
# that okn.toxindex.com resolves to. Survives VM recreation.
resource "google_compute_address" "okn_relay" {
  name   = "okn-relay"
  region = var.region
}

# Tailscale auth key stored in Secret Manager; the relay fetches it at boot.
resource "google_secret_manager_secret" "tailscale_auth_key" {
  secret_id = "okn-tailscale-auth-key"

  labels = {
    app        = "okn"
    managed_by = "terraform"
  }

  replication {
    auto {}
  }

  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret_version" "tailscale_auth_key" {
  secret      = google_secret_manager_secret.tailscale_auth_key.id
  secret_data = var.tailscale_auth_key
}

# Dedicated service account for the relay, allowed to read its auth key.
resource "google_service_account" "okn_relay" {
  account_id   = "okn-relay"
  display_name = "okn ONAI relay"
}

resource "google_secret_manager_secret_iam_member" "relay_reads_auth_key" {
  secret_id = google_secret_manager_secret.tailscale_auth_key.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.okn_relay.email}"
}

# Public ingress for the ONAI TCP port(s). source 0.0.0.0/0 because ONAI nodes
# are arbitrary internet hosts. Empty onai_ports => no rule (safe default).
resource "google_compute_firewall" "okn_onai_ingress" {
  count   = length(var.onai_ports) > 0 ? 1 : 0
  name    = "okn-allow-onai"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = [for p in var.onai_ports : tostring(p)]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["okn-relay"]
}

# SSH for setup/debug (kept open like the other toxindex relays).
resource "google_compute_firewall" "okn_ssh" {
  name    = "okn-allow-ssh"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["okn-relay"]
}

resource "google_compute_instance" "okn_relay" {
  name                      = "okn-relay"
  machine_type              = "e2-small" # relay only forwards bytes; cheap is fine
  zone                      = var.zone
  tags                      = ["okn-relay"]
  allow_stopping_for_update = true

  labels = {
    github-org = "toxindex"
    repo       = "okn"
    app        = "okn"
  }

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = 20
      type  = "pd-ssd"
    }
  }

  # Forwarding requires the kernel to route packets it didn't originate.
  can_ip_forward = true

  network_interface {
    network = "default"
    access_config {
      nat_ip = google_compute_address.okn_relay.address
    }
  }

  service_account {
    email  = google_service_account.okn_relay.email
    scopes = ["cloud-platform"]
  }

  metadata = {
    spark-ip   = var.spark_tailscale_ip
    onai-ports = join(",", [for p in var.onai_ports : tostring(p)])
  }

  metadata_startup_script = templatefile("${path.module}/startup.sh.tpl", {
    auth_key_secret = google_secret_manager_secret.tailscale_auth_key.secret_id
    spark_ip        = var.spark_tailscale_ip
    onai_ports      = join(" ", [for p in var.onai_ports : tostring(p)])
  })

  depends_on = [
    google_secret_manager_secret_version.tailscale_auth_key,
    google_secret_manager_secret_iam_member.relay_reads_auth_key,
  ]
}
