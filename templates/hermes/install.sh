#!/usr/bin/env bash
# hermes bundle — runs INSIDE the guest (Ubuntu 24.04) on deploy.
# Hermes Agent: open-source multi-channel AI agent by Nous Research
# https://hermes-agent.nousresearch.com (MIT) — repo: github.com/NousResearch/hermes-agent
#
# The install URL comes from .env (HERMES_INSTALL_URL) so it's easy to change if the
# vendor link moves. Finish setup (API keys / channels) after, over SSH per Nous docs.
set -euo pipefail
: "${HERMES_INSTALL_URL:?HERMES_INSTALL_URL not set (add it to .env)}"

echo "[hermes] base packages…"
sudo apt-get update -y
sudo apt-get install -y curl ca-certificates

echo "[hermes] installing from $HERMES_INSTALL_URL …"
curl -fsSL "$HERMES_INSTALL_URL" | bash

echo "[hermes] done. Finish setup over SSH per Nous Research docs."
