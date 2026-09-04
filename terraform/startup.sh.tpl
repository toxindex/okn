#!/bin/bash
# okn relay startup: join Tailscale and forward each ONAI TCP port to the Spark.
set -euxo pipefail

SPARK_IP="${spark_ip}"
ONAI_PORTS="${onai_ports}"

# --- Tailscale -------------------------------------------------------------
curl -fsSL https://tailscale.com/install.sh | sh

# Fetch the auth key from Secret Manager via the VM's service account.
apt-get update
apt-get install -y socat jq
AUTH_KEY="$(curl -s -H "Metadata-Flavor: Google" \
  "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token" \
  | jq -r .access_token \
  | xargs -I{} curl -s -H "Authorization: Bearer {}" \
    "https://secretmanager.googleapis.com/v1/projects/$(curl -s -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/project/project-id)/secrets/${auth_key_secret}/versions/latest:access" \
  | jq -r .payload.data | base64 -d)"

tailscale up --auth-key="$AUTH_KEY" --hostname=okn-relay --accept-routes

# --- TCP forwarding: public:PORT -> spark:PORT over the tailnet -------------
# One systemd unit per port using socat. Restarts on failure / reboot.
for PORT in $ONAI_PORTS; do
  cat >/etc/systemd/system/okn-relay@$PORT.service <<UNIT
[Unit]
Description=okn relay TCP :$PORT -> DGX Spark over Tailscale
After=tailscaled.service network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/bin/socat TCP4-LISTEN:$PORT,reuseaddr,fork TCP4:$SPARK_IP:$PORT
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
UNIT
  systemctl enable --now okn-relay@$PORT.service
done

echo "okn relay up: forwarding [$ONAI_PORTS] -> $SPARK_IP"
