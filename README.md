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

- Planned: expose this node via the subdomain **okn.toxindex.com**.
- ONAI deploys/runs the software; once running it needs little attention.
- Next step on ONAI side: a call with Volkmar (or another ONAI engineer) to help
  deploy the software on the host.

## Status

- [ ] Select / commit the DGX Spark host
- [ ] Set up `okn.toxindex.com` subdomain
- [ ] Coordinate deployment call with ONAI
- [ ] Deploy and run the ONAI node software
