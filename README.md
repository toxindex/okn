# okn

Hosting infrastructure for running ONAI's distributed software node on Insilica hardware.

## Background

ONAI (Guha Jayachandran, guha@onai.com) operates a network of nodes running their
software. Insilica is contributing a hosting node from its residential cluster.

The node process communicates over TCP (both incoming and outgoing). ONAI currently
assumes a **static IP**; DNS support may be added if needed.

## Target host

- A **DGX Spark** on a 10 Gbps network shared with ~5 other machines.

### ONAI preferred system requirements

| Requirement | Spec |
|-------------|------|
| OS | Linux |
| Network | 1 Gbps to public, no firewall blockage of outbound/inbound TCP to external nodes |
| GPU | Nvidia, 24–32 GB vRAM |
| System RAM | 8 GB+ |

## Networking

The node runs on **spark3**, a DGX Spark on the residential cluster — behind NAT
with no static public IP. ONAI assumes a static IP, so we bridge over Tailscale
to a small GCP relay that holds a reserved static IP:

```
external ONAI nodes  <--TCP-->  okn-relay (static IP)  <--Tailscale-->  spark3
                                 okn.toxindex.com
```

This matches the other toxindex relays (`yard-proxy`, `qdrant-relay`, `kg-proxy`).
The relay is defined as IaC in [`terraform/`](terraform/) under the GCP `toxindex`
project. `spark3` is already on the tailnet (`100.91.51.95`).

ONAI deploys/runs the node software; once running it needs little attention.
Next step on ONAI's side: a call with Volkmar (or another ONAI engineer) to help
deploy on the host.

## Status

- [x] Commit the host — **spark3** (DGX Spark), already on the tailnet
- [x] Design the static-IP path — GCP Tailscale relay (`terraform/`)
- [ ] Confirm ONAI TCP port(s) and whether outbound needs the static IP too
- [ ] `terraform apply` the relay + create `okn.toxindex.com` A record
- [ ] Coordinate deployment call with ONAI
- [ ] Deploy and run the ONAI node software
