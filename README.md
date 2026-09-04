# okn

Hosting infrastructure for running ONAI's distributed software node on Insilica
hardware. This repo is the project of record for that commitment: the host, the
network path, the deploy config, and the open items with ONAI.

## Background

ONAI (Guha Jayachandran, guha@onai.com; engineers Volkmar Frinken and Shriphani
Palakodety) operates a network of nodes running their software. Insilica is
contributing a hosting node from its residential DGX Spark cluster. Agreed by
email ("hosting support?", Apr 17 – Jul 7 2026).

What ONAI asked us to run (Shriphani's gist, 2026-07-01):

1. **vLLM** serving `Qwen/Qwen3-14B-AWQ` (16–19 GB quantized), reachable only by
   the gateway.
2. **Aardant `vllm-gateway`**, ONAI's process that joins their network and calls
   vLLM. After it starts we send ONAI the generated `resource_info.bin`.

ONAI's stated requirements: Linux; 1 Gbps to the public internet with no TCP
blocking; an NVIDIA GPU with 24–32 GB VRAM; 8 GB+ RAM; a static IP (DNS support
possible on request).

## Host: spark1

| | |
|---|---|
| Host | **spark1** (DGX Spark, GB10, aarch64, 128 GB unified memory), Tailscale `100.103.111.95` |
| Fallback | spark3 (`100.91.51.95`) — the box originally reserved; idle but not yet in the DCGM scrape |
| Why not spark0 | ~9 GB free: it carries the space-heater router, two embedding vLLMs, and seven kazu-inference containers |
| Why not spark0+spark1 for tensor parallelism | No ConnectX link between them (10 GbE only), and a 14B AWQ model fits on one GB10. TP stays at 1 |
| Memory budget | spark1 has ~64 GB available; vLLM is capped at 30% of GPU memory (~36 GB) so the kazu containers keep running |

Switching hosts is one variable: `spark_tailscale_ip` in `terraform/`, and the
`host=` label in the Prometheus `onai` job (ops repo).

## Layout

```
deploy/                 docker compose for the Spark (vLLM + gateway) + .env.example + runbook
terraform/              GCP relay giving the node a static IP over Tailscale (NOT yet applied)
```

## Networking

The Sparks sit behind residential NAT with no static public IP. ONAI assumed a
static IP, so the plan bridges over Tailscale to a small GCP relay:

```
external ONAI nodes  <--TCP-->  okn-relay (static IP)  <--Tailscale-->  spark1
                                 okn.toxindex.com
```

**Open question that may make the relay unnecessary:** ONAI's reference
compose publishes no inbound port for the gateway. If the gateway only dials
out to ONAI's network, the Spark's NAT is fine and the relay can be dropped.
Confirm with ONAI before `terraform apply`.

Current DNS: `okn.toxindex.com` has no record of its own. It resolves via the
Route53 wildcard to the main toxindex frontend LB (34.13.77.187), which is not
this service.

## Monitoring

Prometheus on ops.insilica.co scrapes vLLM's `/metrics` on `spark1:8600` (job
`onai`; host and GPU metrics come from the existing node_exporter and
dcgm-exporter targets). Grafana dashboard: **ONAI Node** at
<https://ops.insilica.co/grafana/d/onai-node>. Config lives in the ops repo
(`observability/prometheus/prometheus.yml`, `observability/grafana/dashboards/onai-node.json`).

## Status (2026-09-04)

- [x] Commit a host — spark1 (was spark3; see table above)
- [x] Design the static-IP path — GCP Tailscale relay (`terraform/`, validated)
- [x] Compose adapted for the Spark (`deploy/`; TP=1, arm64 vLLM image, 8600)
- [x] Monitoring wired — Prometheus job `onai` + Grafana "ONAI Node"
- [ ] **Blocked on ONAI:** gateway image is `linux/amd64` only; need an arm64 build (or run it under qemu, see `deploy/README.md`)
- [ ] **Blocked on ONAI:** does the gateway need inbound TCP? If yes, which port(s) (`terraform var.onai_ports`)?
- [ ] Bring up vLLM on spark1 (`deploy/README.md`)
- [ ] Bring up the gateway; send ONAI `resource_info.bin`
- [ ] If inbound is required: `terraform apply`, then A record `okn.toxindex.com -> relay_ip`

Correspondence gap: Tom's last message to ONAI was Jul 7 ("early next week").
The next message should carry the two blocked questions above.
