# okn — ONAI hosting node

Project of record for hosting ONAI's network node (Guha Jayachandran) on an
Insilica DGX Spark. Do not create a parallel repo or workspace for this; add
here.

- Host of record: **spark1** (`dev@spark1`, Tailscale 100.103.111.95). Fallback spark3.
  Change hosts by editing `terraform/main.tf` `spark_tailscale_ip` and the
  `host=` label of the `onai` job in the ops repo's `prometheus.yml`.
- `deploy/` is what runs on the Spark. Validate with
  `docker compose --env-file deploy/.env.example -f deploy/docker-compose.yml config -q`
  (run it on the Spark; dev boxes may lack the compose plugin).
- `terraform/` is the GCP relay. It has never been applied and is gated on ONAI
  confirming ports. `terraform validate` before committing.
- Monitoring config does not live here: Prometheus job `onai` and the Grafana
  dashboard `onai-node` are in the ops repo (`insilica/ops`, `observability/`),
  deployed with `observability/deploy.sh`.
- Keep the Status section of `README.md` current when anything changes;
  it is what the next person reads first.
- ONAI thread: Gmail "hosting support?" (thread 19d9c90290003889 in Cortex).
  Setup gist: https://gist.github.com/shriphani/6630e92183a1fadc508249ce952c26aa
