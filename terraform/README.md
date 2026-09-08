# okn relay — Terraform

Provisions a GCP relay that exposes the ONAI node (running on a DGX Spark,
`spark1` as of Sept 2026) to the public internet at a **static IP**, bridging
over Tailscale.

```
external ONAI nodes  <--TCP-->  okn-relay (static IP)  <--Tailscale-->  spark1
                                  okn.toxindex.com
```

## Why a relay

The Sparks live on Insilica's residential cluster — behind NAT, no static
public IP. ONAI's protocol speaks TCP and assumes a static IP for us.
The relay is a cheap `e2-small` GCP VM with a reserved external IP that joins
the same tailnet as the Spark and `socat`-forwards each ONAI port to it. The
Spark is selected by `var.spark_tailscale_ip` (spark1 by default; spark3 is the
documented fallback).

This mirrors the existing toxindex relays (`yard-proxy`, `qdrant-relay`,
`kg-proxy`, `searxng-mcp`) — same project (`toxindex`), region (`us-central1`),
and GCS-backed state.

## Prerequisites

1. **Tailscale auth key** — generate a reusable, ephemeral-node, pre-approved
   key carrying `tag:okn-relay`. Pass it through `TF_VAR_tailscale_auth_key`;
   do not write it to a committed file. The reusable key allows Terraform to
   replace the VM, while ephemeral nodes disappear after removal. Tailscale
   keys expire after at most 90 days, so rotate the Secret Manager value before
   a later replacement. The tailnet policy permits this tag to reach only
   `tag:dgx:9000`.
2. **ONAI port** — TCP `9000` is the committed default.
3. The target Spark already on the tailnet — `spark1` at `100.103.111.95`
   (`spark3` at `100.91.51.95` if you switch `var.spark_tailscale_ip`).

## Deploy

```bash
cd terraform
terraform init
TF_VAR_tailscale_auth_key="$KEY" terraform apply
```

Terraform also manages the Route 53 A record in zone
`Z01199351P9ECYL3NLKM0`. Use an AWS profile with access to that zone:

```bash
AWS_PROFILE=iam_tom TF_VAR_tailscale_auth_key="$KEY" terraform apply
```

## Health

The relay serves a dependency-aware health response on port 80:

```bash
curl -i http://okn.toxindex.com/healthz
```

It returns HTTP 200 only if the relay can connect to `spark1:9000`. A 503
response distinguishes a healthy relay from an unavailable Aardant listener.

## Open item (pending ONAI)

- **Symmetric static IP:** does ONAI identify us by source IP on our *outbound*
  connections too? If so, the Spark must route ONAI-bound traffic out through
  the relay (the VM already sets `can_ip_forward`; add a Tailscale subnet route
  + MASQUERADE and a policy route on the Spark). Inbound-only is provisioned now.

## Status (2026-09-08)

Deployed in GCP project `toxindex`, zone `us-central1-a`, with state in
`gs://toxindex-terraform-state/okn`. The `e2-small` VM `okn-relay` uses reserved
IP `35.232.167.66`. Route 53 zone `Z01199351P9ECYL3NLKM0` maps
`okn.toxindex.com` to that address. Public firewall rules expose TCP `9000`
for ONAI and TCP `80` for the health response.
