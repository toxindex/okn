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
| Memory budget | spark1's seven `kazu-chemical-v1-*` containers were **stopped on 2026-09-04** (`docker stop`, not removed; `docker start` brings them back). vLLM takes 60% of GPU memory (~73 GB) |

Switching hosts is one variable: `spark_tailscale_ip` in `terraform/`, and the
`host=` label in the Prometheus `onai` job (ops repo).

## Layout

```
deploy/                 docker compose for the Spark (vLLM + gateway) + .env.example + runbook
gateway/                submodule toxindex/aardant-vllm-gateway: arm64 rebuild of ONAI's gateway image
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
compose publishes no inbound port for the gateway, but inside the container
the `aardant` daemon is configured to listen on `0.0.0.0:9000`
(`aardant.toml`). If the daemon only dials out to ONAI's relays, the Spark's
NAT is fine and the relay can be dropped; if 9000 must be reachable, set
`terraform var.onai_ports = [9000]` and publish it in the compose. Confirm
with ONAI before `terraform apply`.

Current DNS: `okn.toxindex.com` has no record of its own. It resolves via the
Route53 wildcard to the main toxindex frontend LB (34.13.77.187), which is not
this service.

## Monitoring

Prometheus on ops.insilica.co scrapes vLLM's `/metrics` on `spark1:8600` (job
`onai`; host and GPU metrics come from the existing node_exporter and
dcgm-exporter targets). Grafana: an **ONAI** row on the fleet
[Quick Health](https://ops.insilica.co/grafana/d/insilica-fleet) dashboard
(vLLM up, tok/s, queue, KV cache) and the detail dashboard **ONAI Node** at
<https://ops.insilica.co/grafana/d/onai-node>. Config lives in the ops repo
(`observability/prometheus/prometheus.yml`, `observability/grafana/dashboards/`).

## The gateway on aarch64

ONAI's gateway image is amd64-only and closed source (two ELF binaries plus
scripts and bootstrap files; nothing to fork). Two paths, both in place:

- **Now:** run ONAI's amd64 image under qemu user emulation on spark1
  (`tonistiigi/binfmt` installed 2026-09-04; `platform: linux/amd64` in the
  compose). Adequate for a proxy; the GPU work is native in vLLM.
- **Native:** `gateway/` (submodule [toxindex/aardant-vllm-gateway](https://github.com/toxindex/aardant-vllm-gateway))
  rebuilds ONAI's image layout for arm64. It takes every
  architecture-independent file from ONAI's published image at build time and
  needs only two arm64 binaries from ONAI (`aardant`, `app`). The amd64 build
  of the same Dockerfile is the validation that the packaging matches upstream.

## Status (2026-09-04)

- [x] Commit a host — spark1 (was spark3; see table above)
- [x] Design the static-IP path — GCP Tailscale relay (`terraform/`, validated)
- [x] Compose adapted for the Spark (`deploy/`; TP=1, arm64 vLLM image, 8600)
- [x] Monitoring wired — Prometheus job `onai`, fleet Quick Health row, "ONAI Node" dashboard
- [x] kazu-inference stopped on spark1; **vLLM up** on spark1:8600 serving `qwen3-14b-awq` (AWQ Marlin kernel, FlashAttention 2)
- [x] Gateway **ready** on spark1 under qemu emulation (2026-09-04, ~13 min to the wire socket; needs `AARDANT_READY_TIMEOUT_SECONDS=7200`). `app` is running against `http://vllm:8600`.
- [x] `resource_info.bin` written (322 bytes). Canonical copy on spark1 at `~/okn/gateway-state/.config/aardant_vllm_gateway/resource_info.bin`; a copy sits in `deploy/resource_info.bin` on Tom's dev box (gitignored).
- [ ] **Send ONAI** `resource_info.bin` (Shriphani, cc Guha + Volkmar)
- [ ] **Ask ONAI:** arm64 builds of `aardant` and `app` (for `gateway/build.sh arm64`); `gateway/` submodule is ready for them
- [ ] **Ask ONAI:** must the daemon's port 9000 be reachable from the internet? If yes: `terraform var.onai_ports=[9000]`, publish in compose, `terraform apply`, A record `okn.toxindex.com -> relay_ip`
- [ ] **Tell ONAI what we observe:** after ready, the daemon holds no TCP/UDP sockets to the relays (`107.193.138.245:59090-93`; two of four ports answer from spark1) and nothing listens on 9000 inside the container. Either it connects lazily once ONAI registers the node, or something is still missing on our side. No vLLM requests have arrived yet.

Correspondence gap: Tom's last message to ONAI was Jul 7 ("early next week").
The next message should carry `resource_info.bin` and the items above.
