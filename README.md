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
terraform/              deployed GCP relay giving the node a static IP over Tailscale
```

## Networking

The Sparks sit behind residential NAT with no static public IP. ONAI assumed a
static IP, so the plan bridges over Tailscale to a small GCP relay:

```
external ONAI nodes  <--TCP-->  okn-relay (static IP)  <--Tailscale-->  spark1
                                 okn.toxindex.com
```

The deployed GCP relay has reserved IP `35.232.167.66`. Route 53 maps
`okn.toxindex.com` directly to it, and public TCP `9000` is forwarded to
`spark1:9000` over Tailscale. The tailnet ACL permits `tag:okn-relay` to reach
only TCP `9000` on DGX nodes.

Visit <http://okn.toxindex.com/healthz> or run
`curl -i http://okn.toxindex.com/healthz`. HTTP 200 means the relay can connect
to the Spark gateway. HTTP 503 means the relay is up but Aardant is not
accepting the forwarded connection.

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

## Status (2026-09-08)

- [x] Commit a host — spark1 (was spark3; see table above)
- [x] Deploy the static-IP path: `okn.toxindex.com` → `35.232.167.66` → Tailscale → `spark1:9000`
- [x] Compose adapted for the Spark (`deploy/`; TP=1, arm64 vLLM image, 8600)
- [x] Monitoring wired — Prometheus job `onai`, fleet Quick Health row, "ONAI Node" dashboard
- [x] kazu-inference stopped on spark1; **vLLM up** on spark1:8600 serving `qwen3-14b-awq` (AWQ Marlin kernel, FlashAttention 2)
- [x] Gateway **ready** on spark1 under qemu emulation (2026-09-04, ~13 min to the wire socket; needs `AARDANT_READY_TIMEOUT_SECONDS=7200`). `app` is running against `http://vllm:8600`.
- [x] `resource_info.bin` written (322 bytes). Canonical copy on spark1 at `~/okn/gateway-state/.config/aardant_vllm_gateway/resource_info.bin`; a copy sits in `deploy/resource_info.bin` on Tom's dev box (gitignored).
- [ ] **Send ONAI** `resource_info.bin` (Shriphani, cc Guha + Volkmar)
- [ ] **Ask ONAI:** arm64 builds of `aardant` and `app` (for `gateway/build.sh arm64`); `gateway/` submodule is ready for them
- [ ] **Tell ONAI what we observe:** the gateway and vLLM processes are running, but Aardant has no TCP listener. Its persisted config says port `51927`, while the expected public endpoint is `9000`. Logs repeatedly report neighbor connection refusals, aborted handshakes, `No exit nodes available`, and an unavailable SURB deposit. The public relay therefore reports HTTP 503 until ONAI resolves registration/bootstrap connectivity.

Correspondence gap: Tom's last message to ONAI was Jul 7 ("early next week").
The next message should carry `resource_info.bin` and the items above.
