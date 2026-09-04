#!/usr/bin/env bash
# openclaw bundle — runs INSIDE the guest (Ubuntu 24.04) on deploy.
# OpenClaw: open-source personal AI assistant — https://openclaw.ai (MIT).
#
# The install URL comes from .env (OPENCLAW_INSTALL_URL) so it's easy to change
# if the vendor link ever moves — no code edit needed.
# Interactive onboarding (API keys, chat channels) is done after, over SSH: `openclaw onboard`.
set -euo pipefail
: "${OPENCLAW_INSTALL_URL:?OPENCLAW_INSTALL_URL not set (add it to .env)}"

echo "[openclaw] base packages…"
sudo apt-get update -y
sudo apt-get install -y curl ca-certificates

echo "[openclaw] installing from $OPENCLAW_INSTALL_URL …"
curl -fsSL "$OPENCLAW_INSTALL_URL" | bash

echo "[openclaw] done. Finish setup over SSH:  openclaw onboard"
