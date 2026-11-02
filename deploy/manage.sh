#!/usr/bin/env bash
# Operate a prod deployment: deploy/manage.sh status|logs|restart|remove [prod|prod-srv]
# The destination defaults to prod (the AWS host); prod-srv is prod on the on-prem srv host.
# Needs the same environment as deploy/deploy.sh <destination>. Rollback is deploy/rollback.sh.
#
# remove deletes the app, the accessories and their data volumes, so it only runs with
# BACKUP_GATE=passed, which the Kamal Manage workflow sets after the prod DB backup gate. From a
# console, take and check a backup of the prod database first.
# dev is never managed with this script: its kamal-proxy is shared with another deployment. For
# the same reason prod-srv refuses remove: kamal remove also removes the kamal-proxy.
# On prod-srv restart boots the running version by name: the image tag latest on that host is
# shared with dev, whose deploys move it to unreleased develop code.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
source deploy/_common.sh

ACTION="${1:-}"
case "$ACTION" in
  status|logs|restart) ;;
  remove)
    if [[ "${BACKUP_GATE:-}" != 'passed' ]]; then
      echo 'error: remove needs BACKUP_GATE=passed (a checked backup of the prod database); nothing was removed' >&2
      exit 1
    fi
    ;;
  *)
    echo "error: unknown action '${ACTION}' (supported: status, logs, restart, remove)" >&2
    exit 2
    ;;
esac

DESTINATION_ARG="${2:-prod}"
case "$DESTINATION_ARG" in
  prod|prod-srv) ;;
  *)
    echo "error: unknown destination '${DESTINATION_ARG}' (supported: prod, prod-srv)" >&2
    exit 2
    ;;
esac
if [[ "$ACTION" == 'remove' && "$DESTINATION_ARG" == 'prod-srv' ]]; then
  echo 'error: remove is refused on prod-srv: kamal remove would also remove the kamal-proxy shared with dev and another deployment; nothing was removed' >&2
  exit 1
fi

select_destination "$DESTINATION_ARG"
load_project_env
resolve_registry
require_secrets

case "$ACTION" in
  status)
    kamal details
    kamal app version
    ;;
  logs) kamal app logs --lines 200 ;;
  restart)
    if [[ "$DESTINATION" == 'prod-srv' ]]; then
      if ! current="$(kamal app version -q | tr -d '[:space:]')" || [[ -z "$current" ]]; then
        echo "error: could not determine the running version; nothing was restarted. Inspect 'bundle exec kamal app containers -c $CONFIG'." >&2
        exit 1
      fi
      kamal app boot --version "$current"
    else
      kamal app boot
    fi
    ;;
  remove) kamal remove -y ;;
esac
