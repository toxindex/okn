# Bring-up on spark1

Run as `dev@spark1` (Tailscale SSH). Everything is Docker; no sudo needed after
the one-time state directory setup.

## 0. Preconditions

- The seven `kazu-chemical-v1-*` containers on spark1 were stopped on
  2026-09-04 (they are still present; `docker start` revives them). With them
  down spark1 has ~114 GB free and `VLLM_GPU_MEM_UTIL=0.60` is safe. If they
  ever come back, drop it to 0.30.
- Port 8600 is free (`ss -tln | grep 8600`). 8000 stays reserved for
  space-heater's router-facing vLLM.
- The gateway image is amd64-only. qemu user emulation is already installed on
  spark1 (`docker run --privileged --rm tonistiigi/binfmt --install amd64`,
  2026-09-04; re-run after a reboot if `ls /proc/sys/fs/binfmt_misc` shows no
  `qemu-x86_64`). For a native image see `../gateway/`.

## 1. Files

```bash
mkdir -p ~/okn && cd ~/okn
# copy deploy/ from this repo (rsync from a dev box, or git clone)
cp .env.example .env && $EDITOR .env        # HF_TOKEN; paths default to spark1
mkdir -p ~/okn/gateway-state
sudo chown -R 999:999 ~/okn/gateway-state && sudo chmod 700 ~/okn/gateway-state
```

## 2. vLLM first

```bash
docker compose up -d vllm
docker logs -f onai-vllm            # first start downloads ~9 GB and compiles kernels; allow 10 min
curl -s localhost:8600/v1/models    # expect "qwen3-14b-awq"
curl -s localhost:8600/metrics | grep -c '^vllm:'
```

Within a minute the Prometheus target `onai / 100.103.111.95:8600` on
<https://ops.insilica.co/prometheus/targets?search=onai> flips to UP and the
**ONAI Node** Grafana dashboard fills in.

If the AWQ kernels fail to load on GB10, fall back to the upstream arm64 image
(`vllm/vllm-openai:nightly` publishes arm64) and report which one worked here.

## 3. Gateway

```bash
docker compose up -d vllm-gateway
docker logs -f onai-gateway
ls -la ~/okn/gateway-state/.config/aardant_vllm_gateway/resource_info.bin
```

Send `resource_info.bin` to Shriphani (spalakod@onai.com), cc Guha and Volkmar.

## 4. Verify from outside

- Ask ONAI whether their side sees the node.
- If the gateway needs inbound TCP, that is the moment to `terraform apply`
  the relay (`../terraform/`) with the confirmed port(s) and create the
  `okn.toxindex.com` A record.

## Rollback

```bash
docker compose down        # keeps gateway-state and the model cache
```
