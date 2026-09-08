#!/bin/bash
# okn relay startup: join Tailscale and forward each ONAI TCP port to the Spark.
set -euxo pipefail

SPARK_IP="${spark_ip}"
ONAI_PORTS="${onai_ports}"

# --- Tailscale -------------------------------------------------------------
curl -fsSL https://tailscale.com/install.sh | sh

# Fetch the auth key from Secret Manager via the VM's service account. Disable
# shell tracing while the key is in scope so it never reaches the serial log.
apt-get update
apt-get install -y socat jq
set +x
AUTH_KEY="$(curl -s -H "Metadata-Flavor: Google" \
  "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token" \
  | jq -r .access_token \
  | xargs -I{} curl -s -H "Authorization: Bearer {}" \
    "https://secretmanager.googleapis.com/v1/projects/$(curl -s -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/project/project-id)/secrets/${auth_key_secret}/versions/latest:access" \
  | jq -r .payload.data | base64 -d)"

tailscale up --auth-key="$AUTH_KEY" --hostname=okn-relay --accept-routes
unset AUTH_KEY
set -x

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

# --- Health endpoint -------------------------------------------------------
# Report the real downstream state rather than merely proving that this VM is
# running. No ONAI or vLLM data is exposed.
cat >/usr/local/bin/okn-health.py <<'PY'
#!/usr/bin/env python3
import json
import socket
from http.server import BaseHTTPRequestHandler, HTTPServer

SPARK_IP = "${spark_ip}"
ONAI_PORTS = [int(port) for port in "${onai_ports}".split()]


def tcp_ready(host, port):
    try:
        with socket.create_connection((host, port), timeout=2):
            return True
    except OSError:
        return False


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path not in ("/", "/healthz"):
            self.send_error(404)
            return
        ports = {str(port): tcp_ready(SPARK_IP, port) for port in ONAI_PORTS}
        healthy = bool(ports) and all(ports.values())
        body = json.dumps({
            "service": "okn-relay",
            "healthy": healthy,
            "upstream": "spark1",
            "tcp": ports,
        }, sort_keys=True).encode() + b"\n"
        self.send_response(200 if healthy else 503)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        pass


HTTPServer(("0.0.0.0", 80), Handler).serve_forever()
PY
chmod 755 /usr/local/bin/okn-health.py

cat >/etc/systemd/system/okn-health.service <<'UNIT'
[Unit]
Description=OKN relay downstream health endpoint
After=network-online.target tailscaled.service
Wants=network-online.target

[Service]
ExecStart=/usr/local/bin/okn-health.py
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
UNIT
systemctl enable --now okn-health.service

echo "okn relay up: forwarding [$ONAI_PORTS] -> $SPARK_IP"
