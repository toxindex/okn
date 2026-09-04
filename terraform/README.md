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

1. **Tailscale auth key** — generate a reusable, ephemeral, pre-approved key
   (tag `tag:relay`) at <https://login.tailscale.com/admin/settings/keys>.
2. **ONAI port(s)** — `var.onai_ports` is empty until ONAI confirms the TCP
   port(s). With it empty, no public firewall rule is created (safe to apply
   the rest, but the relay won't forward anything yet).
3. The target Spark already on the tailnet — `spark1` at `100.103.111.95`
   (`spark3` at `100.91.51.95` if you switch `var.spark_tailscale_ip`).

## Deploy

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # fill in auth key + ports
terraform init
terraform apply
```

Then point DNS at the output IP (Route53 zone `Z01199351P9ECYL3NLKM0`):

```bash
terraform output relay_ip
# create A record okn.toxindex.com -> <relay_ip>
```

## Open items (pending ONAI)

- **Port(s):** which TCP port(s) the node listens on → `var.onai_ports`.
- **Symmetric static IP:** does ONAI identify us by source IP on our *outbound*
  connections too? If so, the Spark must route ONAI-bound traffic out through
  the relay (the VM already sets `can_ip_forward`; add a Tailscale subnet route
  + MASQUERADE and a policy route on the Spark). Inbound-only is provisioned now.

## Status (2026-09-04)

**Never applied.** There is no `okn-relay` VM or address in the `toxindex`
project and no `okn.toxindex.com` record; the name currently resolves only via
the Route53 wildcard to the main toxindex frontend LB (34.13.77.187). Apply is
gated on ONAI's port list.
