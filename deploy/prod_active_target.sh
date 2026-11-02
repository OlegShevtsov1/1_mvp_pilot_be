#!/usr/bin/env bash
# Prints active_target=aws|srv, the live prod host as public DNS shows it (deploy/_common.sh
# detect_active_target), ready for GITHUB_OUTPUT. Fails while DNS is unresolvable or mid-change.
# Run it outside the VPN: vpn-up resolves the VPN zones through the VPN's own DNS.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
source deploy/_common.sh

load_project_env
if ! target="$(detect_active_target)"; then
  echo "::error::the live prod host is unknown: public DNS for ${PROJECT_ZONE} is unresolvable or mid-change; nothing touched prod" >&2
  exit 1
fi
echo "active_target=${target}"
