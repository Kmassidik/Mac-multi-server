#!/usr/bin/env bash
# openclaw bundle — runs INSIDE the guest (Ubuntu 24.04) on first deploy.
# deploy pipes this over SSH: ssh admin@<vps> 'bash -s' < this file.
#
# ⚠️  PLACEHOLDER: fill in the real OpenClaw install steps below.
#     Keep it idempotent (safe to re-run). When it exposes an HTTP port,
#     put that port number in templates/openclaw/port so the panel routes it.
set -euo pipefail

echo "[openclaw] preparing base…"
sudo apt-get update -y
sudo apt-get install -y curl ca-certificates

# ── TODO: real OpenClaw install ──────────────────────────────
# e.g.:
#   curl -fsSL https://get.openclaw.example/install.sh | sh
#   sudo systemctl enable --now openclaw
# and set its listen port in ../port  (default assumed 3000)
echo "[openclaw] TODO: add the real OpenClaw install command in templates/openclaw/install.sh"

echo "[openclaw] done."
