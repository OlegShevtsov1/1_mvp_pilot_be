#!/usr/bin/env bash
# Prod Switch: moves prod between the AWS host (destination prod) and the srv host (prod-srv), in
# either direction; .github/workflows/prod-switch.yml runs the subcommands in this order. See README
# "Prod Switch (aws <-> srv)".
#
# Usage: deploy/prod_switch.sh guard
#          env TO (aws|srv) and ACTIVE_TARGET (deploy/prod_active_target.sh); refuses a switch to
#          the host that is already live. Prints to=, from=, to_destination=, from_destination=.
#        deploy/prod_switch.sh plan
#          the step selection of prepare (select_steps) from observations in the environment.
#        deploy/prod_switch.sh prepare <to-dest> vX.Y.Z [<source_sha>]
#          step 1: refuses unless the target is reachable (or, for aws, needs the standby), fe runs
#          there and the live prod runs the release; resumes the target's service and writes
#          steps= (standby, live, deploy) to GITHUB_OUTPUT. AFTER_STANDBY=1 refuses an AWS instance
#          that is still down; REQUIRE_READY=1 refuses a target that still needs a deploy.
#        deploy/prod_switch.sh standby
#          step 1 for to=aws while the AWS instance is down: dispatches Project Terraform Prod
#          (prod_target=aws-standby: instance running, records stay on srv) like dns, or prints it
#          for the operator; writes dispatched=yes|no to GITHUB_OUTPUT.
#        deploy/prod_switch.sh wait-host <dest> <minutes>
#          waits for SSH on the host (every STANDBY_POLL_SECONDS).
#        deploy/prod_switch.sh deploy-target aws|srv vX.Y.Z [<source_sha>]
#          step 1: dispatches Kamal Deploy target=<to> with prod_switch_run=GITHUB_RUN_ID and
#          watches that run.
#        deploy/prod_switch.sh switch-run-check <run-id>
#          Kamal Deploy's guard for prod_switch_run: refuses unless the run is an in-progress Prod
#          Switch on main to TARGET, and TARGET is not ACTIVE_TARGET (the live host).
#        deploy/prod_switch.sh freeze <from-dest>
#          step 2: Kamal maintenance (kamal-proxy answers 503) and every app container stopped; the
#          service stays registered and paused in kamal-proxy.
#        deploy/prod_switch.sh move-data <from-dest> <to-dest> sha-<sha>
#          step 2: a final dump of the live database, restored into the target's recreated one,
#          the row counts of every public table compared, then the target's app booted.
#        deploy/prod_switch.sh compare-counts <source counts> <target counts>
#        deploy/prod_switch.sh abort-check <from-dest>
#          refuses an abort unless public DNS shows the source and this run's prod-dns job never
#          began (GITHUB_RUN_ID).
#        deploy/prod_switch.sh abort <from-dest> sha-<sha>
#          before DNS only: starts the live prod's app on the release again and ends maintenance.
#        deploy/prod_switch.sh dns aws|srv
#          step 3: dispatches Project Terraform Prod (prod_target=<to>) in INFRA_PROD_REPO@env/prod
#          with GH_TOKEN, or prints the exact command and record changes for the operator; then
#          waits for public DNS to show <to> (DNS_WAIT_MINUTES, every DNS_POLL_SECONDS).
#        deploy/prod_switch.sh finalize-public <to-dest> sha-<sha>
#          step 4: /health, the read-only smoke and fe's config.js on the public URLs, pinned to
#          the addresses DNS now gives; then prod-current/prod-previous follow the target.
#        deploy/prod_switch.sh stop-old <from-dest>
#          step 5: stops, never removes, the old host's app containers; accessories and volumes stay,
#          and its service stays paused in kamal-proxy, so a switch back resumes it.
#        deploy/prod_switch.sh infra-options | dns-began
#          stdin: the infra workflow YAML, printing the options of its prod_target input; the jobs
#          API pages of a run, printing whether its prod-dns job began (yes|no).
#
# Env: PROD_ACTIVE_TARGET (aws|srv: the live prod host before the switch; read from public DNS
# when unset), PROD_VPN_IP, PROD_SRV_VPN_IP and the deploy/deploy.sh environment for every command
# that reaches a host. DRY_RUN=1 prints each command that would touch a host, ECR, DNS or infra as
# "[dry-run] ..." on stderr and runs none of them.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
source deploy/_common.sh

PUBLIC_HEALTH_TIMEOUT=600
MAINTENANCE_MESSAGE='Prod is moving to another host and is back in a few minutes.'
# One "table|count" line per table in public, exact counts.
COUNT_SQL="SELECT format('SELECT %L || ''|'' || count(*) FROM public.%I', tablename, tablename) FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename \\gexec"
# The name of the prod-dns job in .github/workflows/prod-switch.yml, as the jobs API lists it.
DNS_JOB_NAME='Switch DNS (operator approval)'
WORK_DIR=''
trap '[[ -z "$WORK_DIR" ]] || rm -rf "$WORK_DIR"' EXIT

fail() {
  echo "::error::$1" >&2
  exit 1
}

usage() {
  sed -n '/^# Usage/,/^# Env/p' "${BASH_SOURCE[0]}" | sed '$d' >&2
  exit 2
}

dry_run() {
  [[ "${DRY_RUN:-}" == '1' ]]
}

run() {
  if dry_run; then
    echo "[dry-run] $*" >&2
  else
    "$@"
  fi
}

destination_of() {
  case "$1" in
    aws) echo prod ;;
    srv) echo prod-srv ;;
    *) fail "a prod host must be aws or srv (got '$1')" ;;
  esac
}

target_of() {
  case "$1" in
    prod) echo aws ;;
    prod-srv) echo srv ;;
    *) fail "unknown destination '$1' (supported: prod, prod-srv)" ;;
  esac
}

host_role() {
  if [[ "$1" == 'prod' ]]; then echo 'the AWS host'; else echo 'the srv host'; fi
}

host_address() {
  if [[ "$1" == 'prod' ]]; then
    require_prod_host
    echo "$PROD_VPN_IP"
  else
    require_prod_srv_host
    echo "$PROD_SRV_VPN_IP"
  fi
}

# kamal_on <dest> <kamal args...>: Kamal with that destination's config.
kamal_on() {
  local dest="$1"
  shift
  (
    select_destination "$dest"
    run bundle exec kamal "$@" -c "$CONFIG"
  )
}

# remote <dest> <command>: runs command on the host over SSH with the SSH users of
# config/deploy.yml and config/deploy.prod-srv.yml; stdin goes through. accept-new is the same
# trust Kamal's own SSH gives these hosts on a fresh runner (net-ssh accepts a new key), over the
# authenticated VPN; a pinned key would refuse an AWS instance infra re-created.
remote() {
  local dest="$1" cmd="$2" user=ubuntu host
  if dry_run; then
    echo "[dry-run] on $(host_role "$dest"): ${cmd}" >&2
    return 0
  fi
  [[ "$dest" == 'prod' ]] || user="${PROJECT_NAME}-prod"
  host="$(host_address "$dest")"
  ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new "${user}@${host}" "$cmd"
}

# stop_app <dest>: stops every running app container (web and cron) of the service. Not
# `kamal app stop`: that also removes the service from kamal-proxy, which ends maintenance and
# leaves nothing for a later `kamal app live` to resume.
stop_app() {
  remote "$1" "docker ps -q --filter label=service=${PROJECT_NAME} | xargs -r docker stop" < /dev/null
}

host_reachable() {
  local host attempt
  host="$(host_address "$1")"
  for attempt in 1 2 3; do
    if nc -z -w 5 "$host" 22; then
      return 0
    fi
    echo "attempt ${attempt}: SSH on $(host_role "$1") is not reachable yet" >&2
    sleep 5
  done
  return 1
}

running_version() {
  kamal_on "$1" app version -q 2> /dev/null | tr -d '[:space:]' || true
}

# Both prod configs read .kamal/secrets.prod.
setup_kamal_env() {
  load_project_env
  if dry_run; then
    return 0
  fi
  resolve_registry
  SECRETS_FILE='.kamal/secrets.prod'
  require_secrets
}

# wait_healthy <dest> sha-<sha>: the destination's own health check (deploy/_common.sh wait_release).
wait_healthy() {
  if dry_run; then
    echo "[dry-run] wait until /health on $(host_role "$1") reports release ${2#sha-}" >&2
    return 0
  fi
  (
    select_destination "$1"
    wait_release "$2" "$HEALTH_TIMEOUT"
  )
}

require_two_hosts() {
  target_of "$1" > /dev/null
  target_of "$2" > /dev/null
  [[ "$1" != "$2" ]] || fail "the source and the target are both ${1}"
}

cmd_guard() {
  local to="${TO:-}" from="${ACTIVE_TARGET:-}"
  [[ "$to" == 'aws' || "$to" == 'srv' ]] || fail "to must be aws or srv (got '${to}')"
  [[ "$from" == 'aws' || "$from" == 'srv' ]] || fail "the live prod host must be aws or srv (got '${from}')"
  [[ "$to" != "$from" ]] || fail "prod already runs on ${to} (public DNS points there): nothing to switch"
  echo "to=${to}"
  echo "from=${from}"
  echo "to_destination=$(destination_of "$to")"
  echo "from_destination=$(destination_of "$from")"
}

# select_steps: prints steps=standby (an unreachable AWS instance), or steps=<live and/or deploy,
# in order>, from TO, RELEASE (prod-sha-<sha>), AFTER_STANDBY and the observations REACHABLE and
# FE_RUNNING (yes|no), SOURCE_VERSION and TARGET_VERSION (the running Kamal versions, empty for
# none), TARGET_CONTAINERS (yes|no: the service has containers on the target, maybe paused by an
# earlier switch). Refuses when the switch cannot start.
select_steps() {
  local steps=()
  if [[ "${REACHABLE:-}" != 'yes' ]]; then
    [[ "${TO:-}" == 'aws' ]] ||
      fail 'the srv host is not reachable over the VPN: check the VPN and the host; nothing touched prod'
    [[ "${AFTER_STANDBY:-}" != '1' ]] ||
      fail "the AWS instance did not come up after the standby (infra prod_target=aws-standby): check the infra run and the instance; nothing touched prod"
    echo 'steps=standby'
    return 0
  fi
  [[ "${SOURCE_VERSION:-}" == "${RELEASE:-}" ]] ||
    fail "the live prod runs ${SOURCE_VERSION:-no version}, not ${RELEASE:-}: switch with the release prod runs; nothing touched prod"
  [[ "${FE_RUNNING:-}" == 'yes' ]] ||
    fail "fe does not run on the ${TO:-} host: deploy it there first with fe's Kamal Deploy target=${TO:-} (same version and confirm); nothing touched prod"
  [[ "${TARGET_CONTAINERS:-}" != 'yes' ]] || steps+=(live)
  [[ "${TARGET_VERSION:-}" == "${RELEASE:-}" ]] || steps+=(deploy)
  echo "steps=${steps[*]}"
}

cmd_prepare() {
  local to_dest="$1" from_dest containers steps
  shift
  require_active_target
  from_dest="$(destination_of "$PROD_ACTIVE_TARGET")"
  require_two_hosts "$from_dest" "$to_dest"
  setup_kamal_env
  TO="$(target_of "$to_dest")"
  RELEASE="prod-$(resolve_prod_release "$@")"

  if dry_run; then
    REACHABLE=yes FE_RUNNING=yes SOURCE_VERSION="$RELEASE" TARGET_CONTAINERS=yes TARGET_VERSION=''
    if [[ "${REQUIRE_READY:-}" == '1' ]]; then
      TARGET_VERSION="$RELEASE"
    elif [[ "$TO" == 'aws' && "${AFTER_STANDBY:-}" != '1' ]]; then
      REACHABLE=no
    fi
    echo "[dry-run] check SSH on $(host_role "$to_dest"), fe's containers there and the running version on both hosts; a dry run assumes $(dry_assumption)" >&2
  else
    REACHABLE=no
    if host_reachable "$to_dest"; then
      REACHABLE=yes
      SOURCE_VERSION="$(running_version "$from_dest")"
      FE_RUNNING=no
      if [[ -n "$(remote "$to_dest" "docker ps --filter name=^${PROJECT_NAME}-fe-web- --filter status=running -q" < /dev/null)" ]]; then
        FE_RUNNING=yes
      fi
      containers="$(kamal_on "$to_dest" app containers -q)" ||
        fail "could not list the containers on $(host_role "$to_dest"); nothing touched prod"
      TARGET_CONTAINERS=no
      if grep -q "${PROJECT_NAME}-web-" <<< "$containers"; then TARGET_CONTAINERS=yes; fi
      TARGET_VERSION="$(running_version "$to_dest")"
    fi
  fi

  steps="$(select_steps)" || exit 1
  steps="${steps#steps=}"
  echo "==> $(host_role "$to_dest"): ${steps:-already runs ${RELEASE}}"
  if [[ "${REQUIRE_READY:-}" == '1' && ( " ${steps} " == *' deploy '* || "$steps" == 'standby' ) ]]; then
    fail "the target does not run ${RELEASE} ($(host_role "$to_dest"): ${steps}); nothing touched prod"
  fi
  if [[ " ${steps} " == *' live '* ]]; then
    echo "==> Resuming ${PROJECT_NAME} in kamal-proxy on $(host_role "$to_dest") (paused by an earlier switch)"
    kamal_on "$to_dest" app live
  fi
  echo "steps=${steps}" >> "${GITHUB_OUTPUT:-/dev/null}"
}

dry_assumption() {
  if [[ "${REQUIRE_READY:-}" == '1' ]]; then
    echo 'the target job brought the target to the release'
  elif [[ "$REACHABLE" != 'yes' ]]; then
    echo 'the AWS instance is down'
  else
    echo 'the target needs a deploy'
  fi
}

cmd_freeze() {
  local dest="$1"
  target_of "$dest" > /dev/null
  setup_kamal_env
  echo "==> Maintenance on $(host_role "$dest"): kamal-proxy answers 503 for ${PROJECT_NAME}"
  kamal_on "$dest" app maintenance --roles=web --message "$MAINTENANCE_MESSAGE"
  echo "==> Stopping every ${PROJECT_NAME} app container on $(host_role "$dest"); the accessories keep running"
  stop_app "$dest"
}

compare_counts() {
  local source="$1" target="$2" diff table on_source on_target
  if [[ ! -s "$source" || ! -s "$target" ]]; then
    echo 'error: a row count list is empty' >&2
    return 1
  fi
  diff="$(LC_ALL=C join -t '|' -a 1 -a 2 -e missing -o 0,1.2,2.2 \
    <(LC_ALL=C sort -t '|' -k 1,1 "$source") <(LC_ALL=C sort -t '|' -k 1,1 "$target") | awk -F '|' '$2 != $3')"
  if [[ -n "$diff" ]]; then
    while IFS='|' read -r table on_source on_target; do
      echo "error: table ${table}: ${on_source} rows on the live prod, ${on_target} on the target" >&2
    done <<< "$diff"
    return 1
  fi
  echo "==> $(grep -c . "$source") tables, every row count matches"
}

cmd_move_data() {
  local from_dest="$1" to_dest="$2" version="$3" db container
  require_two_hosts "$from_dest" "$to_dest"
  require_version "$version"
  setup_kamal_env
  db="${PROJECT_NAME}_prod"
  container="${PROJECT_NAME}-db"
  # The dump is prod data: owner-only, never uploaded, deleted on exit.
  WORK_DIR="$(umask 077 && mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/prod-switch.XXXXXX")"

  echo "==> Final dump of ${db} on $(host_role "$from_dest")"
  remote "$from_dest" "docker exec ${container} pg_dump -U postgres -d ${db} -Fc" < /dev/null > "${WORK_DIR}/dump"
  if ! dry_run && [[ "$(head -c 5 "${WORK_DIR}/dump")" != 'PGDMP' ]]; then
    fail "the dump of ${db} is not a pg_dump archive; $(host_role "$to_dest") was not touched"
  fi

  echo "==> Restoring it into a recreated ${db} on $(host_role "$to_dest")"
  stop_app "$to_dest"
  remote "$to_dest" "docker exec ${container} dropdb -U postgres --if-exists --force ${db}" < /dev/null
  remote "$to_dest" "docker exec ${container} createdb -U postgres ${db}" < /dev/null
  remote "$to_dest" "docker exec -i ${container} pg_restore -U postgres -d ${db} --no-owner --exit-on-error" < "${WORK_DIR}/dump"

  echo '==> Comparing the row counts of every public table'
  local count_cmd="docker exec -i ${container} psql -U postgres -d ${db} -At -v ON_ERROR_STOP=1"
  remote "$from_dest" "$count_cmd" <<< "$COUNT_SQL" > "${WORK_DIR}/source.counts"
  remote "$to_dest" "$count_cmd" <<< "$COUNT_SQL" > "${WORK_DIR}/target.counts"
  if ! dry_run && ! compare_counts "${WORK_DIR}/source.counts" "${WORK_DIR}/target.counts"; then
    fail "the restored database differs from the live one; DNS was not touched"
  fi

  echo "==> Booting prod-${version} on $(host_role "$to_dest")"
  kamal_on "$to_dest" app boot --version "prod-${version}"
  wait_healthy "$to_dest" "$version"
  echo "==> The data is on $(host_role "$to_dest"); the live prod stays in maintenance until DNS moves"
}

cmd_abort() {
  local dest="$1" version="$2"
  target_of "$dest" > /dev/null
  require_version "$version"
  setup_kamal_env
  echo "==> Abort: starting prod-${version} on $(host_role "$dest") again and ending maintenance"
  kamal_on "$dest" app start --version "prod-${version}"
  kamal_on "$dest" app live
  wait_healthy "$dest" "$version"
  echo "==> Prod is back on $(host_role "$dest"); DNS was not touched"
}

# print_manual_switch <prod_target> <minutes>: the dispatch (DISPATCH) and what it changes, for the
# operator to apply through infra.
print_manual_switch() {
  local to="$1" minutes="$2" address
  if [[ "$to" == 'aws-standby' ]]; then
    echo "::warning::the AWS standby is up to the operator: apply it through infra; the target job waits for the AWS instance to answer"
    echo "  ${DISPATCH[*]}"
    echo "What it does: AWS instance running (re-created if absent); records stay on srv, DNS does not move."
    return 0
  fi
  if [[ "$to" == 'srv' ]]; then
    address="the addresses of dev.${PROJECT_ZONE} (the public TLS terminator in front of the srv host)"
  else
    address="the aws_eip.prod address (terraform output in infra/projects/${PROJECT_NAME}-prod)"
  fi
  echo "::warning::the DNS switch is up to the operator: apply it through infra; this job waits ${minutes} min for public DNS to show ${to}"
  echo "  ${DISPATCH[*]}"
  echo "Record changes, applied by infra only, never in the Route53 console (the next ${PROJECT_NAME}-prod apply would revert them):"
  echo "  ${PROJECT_ZONE} A -> ${address}"
  echo "  app.${PROJECT_ZONE} A -> ${address}"
}

# infra_target_options: the options of the prod_target input in the workflow YAML on stdin, one per
# line, from a block (- aws) or an inline ([aws, srv]) list.
infra_target_options() {
  awk '
    function indent(line) { match(line, /^ */); return RLENGTH }
    /^[[:space:]]*(#.*)?$/ { next }
    !input && /^ *prod_target:[[:space:]]*$/ { input = indent($0); next }
    input && indent($0) <= input { exit }
    input && !list && /^ *options:/ {
      list = indent($0)
      if (sub(/^ *options:[[:space:]]*\[/, "")) {
        sub(/\].*/, "")
        n = split($0, items, ",")
        for (i = 1; i <= n; i++) { gsub(/[[:space:]\047"]/, "", items[i]); if (items[i] != "") print items[i] }
        exit
      }
      next
    }
    list && indent($0) <= list { exit }
    list && /^ *- / { sub(/^ *- */, ""); gsub(/[[:space:]\047"]/, ""); print }
  '
}

# infra_supports_target <value>: false only when the infra workflow is readable and its
# prod_target does not offer the value. Unreadable (the token may not read contents), the dispatch
# goes ahead: GitHub refuses inputs a workflow does not declare, and that refusal falls back too.
infra_supports_target() {
  local yaml offered
  if ! yaml="$(gh workflow view project-terraform-prod.yml -R "$INFRA_PROD_REPO" --ref env/prod --yaml 2> /dev/null)"; then
    echo "::notice::could not read Project Terraform Prod in ${INFRA_PROD_REPO}@env/prod; dispatching prod_target=$1 unchecked"
    return 0
  fi
  offered="$(infra_target_options <<< "$yaml")"
  grep -qxF -- "$1" <<< "$offered" && return 0
  echo "::warning::Project Terraform Prod in ${INFRA_PROD_REPO}@env/prod offers no prod_target=$1 (it offers: $(tr '\n' ' ' <<< "${offered:-nothing}"))"
  return 1
}

# set_dispatch <prod_target>: DISPATCH, the Project Terraform Prod apply in INFRA_PROD_REPO@env/prod.
set_dispatch() {
  INFRA_PROD_REPO="${INFRA_PROD_REPO:-${GITHUB_REPOSITORY_OWNER:-<owner>}/1_mvp_infra}"
  DISPATCH=(gh workflow run project-terraform-prod.yml -R "$INFRA_PROD_REPO" --ref env/prod
    -f "project=${PROJECT_NAME}" -f action=apply -f "confirm=APPLY-PROD-${PROJECT_NAME}" -f "prod_target=$1")
}

# try_dispatch <prod_target>: the checked infra dispatch with GH_TOKEN, false whenever the operator
# has to apply it instead.
try_dispatch() {
  if [[ -z "${GH_TOKEN:-}" ]]; then
    echo '::warning::INFRA_PROD_DISPATCH_TOKEN is not set in the environment prod-dns'
    return 1
  fi
  infra_supports_target "$1" && dispatch_infra "$1"
}

# dispatch_infra <prod_target>: the dispatched infra run must succeed with at least one job not
# skipped: outside its repository's env/prod branch every job of that workflow is skipped.
dispatch_infra() {
  local since id='' attempt
  since="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "==> Dispatching Project Terraform Prod in ${INFRA_PROD_REPO}@env/prod with prod_target=$1"
  if ! "${DISPATCH[@]}"; then
    echo '::warning::the infra dispatch failed (INFRA_PROD_DISPATCH_TOKEN cannot run that workflow, or it has no prod_target input)'
    return 1
  fi
  for attempt in $(seq 12); do
    id="$(gh run list -R "$INFRA_PROD_REPO" --workflow project-terraform-prod.yml --event workflow_dispatch \
      --json databaseId,createdAt --limit 20 \
      | jq -r --arg since "$since" '[.[] | select(.createdAt >= $since)] | sort_by(.createdAt) | last | .databaseId // empty')" || id=''
    [[ -z "$id" ]] || break
    echo "attempt ${attempt}: the dispatched infra run is not listed yet" >&2
    sleep 10
  done
  if [[ -z "$id" ]]; then
    echo '::warning::the dispatched infra run did not appear within 2 minutes'
    return 1
  fi
  echo "==> Watching infra run ${id}"
  if ! gh run watch "$id" -R "$INFRA_PROD_REPO" --exit-status; then
    echo "::warning::infra run ${id} failed"
    return 1
  fi
  if ! gh run view "$id" -R "$INFRA_PROD_REPO" --json jobs | jq -e '[.jobs[].conclusion] | any(. != "skipped")' > /dev/null; then
    echo "::warning::every job of infra run ${id} was skipped: it applies only on ${INFRA_PROD_REPO}@env/prod"
    return 1
  fi
}

wait_dns() {
  local to="$1" minutes="$2" interval="${DNS_POLL_SECONDS:-30}" attempts i now='unknown'
  attempts=$(( minutes * 60 / interval ))
  echo "==> Waiting up to ${minutes} min for public DNS to show ${to}"
  for (( i = 1; i <= attempts; i++ )); do
    now="$(detect_active_target 2> /dev/null || echo mid-change)"
    if [[ "$now" == "$to" ]]; then
      echo "==> Public DNS for ${PROJECT_ZONE} and app.${PROJECT_ZONE} points at ${to}"
      return 0
    fi
    sleep "$interval"
  done
  fail "public DNS did not show ${to} within ${minutes} min (it shows ${now}); DNS may have moved partly: follow README \"Prod Switch\", after DNS"
}

cmd_dns() {
  local to="$1" minutes
  destination_of "$to" > /dev/null
  load_project_env
  set_dispatch "$to"
  if dry_run; then
    run "${DISPATCH[@]}"
    print_manual_switch "$to" "${DNS_WAIT_MINUTES:-20}"
    echo "[dry-run] wait for public DNS to show ${to}" >&2
    return 0
  fi
  if try_dispatch "$to"; then
    minutes="${DNS_WAIT_MINUTES:-20}"
  else
    minutes="${DNS_WAIT_MINUTES:-60}"
    print_manual_switch "$to" "$minutes"
  fi
  wait_dns "$to" "$minutes"
}

cmd_standby() {
  local dispatched=no
  load_project_env
  set_dispatch aws-standby
  if dry_run; then
    run "${DISPATCH[@]}"
    print_manual_switch aws-standby 0
  elif try_dispatch aws-standby; then
    dispatched=yes
  else
    print_manual_switch aws-standby 0
  fi
  echo "dispatched=${dispatched}" >> "${GITHUB_OUTPUT:-/dev/null}"
}

cmd_wait_host() {
  local dest="$1" minutes="$2" interval="${STANDBY_POLL_SECONDS:-30}" host attempts i
  target_of "$dest" > /dev/null
  if dry_run; then
    echo "[dry-run] wait up to ${minutes} min for SSH on $(host_role "$dest")" >&2
    return 0
  fi
  host="$(host_address "$dest")"
  attempts=$(( minutes * 60 / interval ))
  echo "==> Waiting up to ${minutes} min for SSH on $(host_role "$dest")"
  for (( i = 1; i <= attempts; i++ )); do
    if nc -z -w 5 "$host" 22; then
      echo "==> SSH on $(host_role "$dest") answers"
      return 0
    fi
    sleep "$interval"
  done
  fail "SSH on $(host_role "$dest") did not answer within ${minutes} min; nothing touched prod: once the instance answers, run Prod Switch again"
}

cmd_deploy_target() {
  local to="$1" tag="$2" id='' attempt dispatch
  destination_of "$to" > /dev/null
  [[ -n "${GITHUB_REPOSITORY:-}" && -n "${GITHUB_RUN_ID:-}" ]] || fail 'GITHUB_REPOSITORY and GITHUB_RUN_ID must be set (the Prod Switch run)'
  dispatch=(gh workflow run kamal-deploy.yml -R "$GITHUB_REPOSITORY" --ref main -f environment=prod -f "target=${to}" -f "version=${tag}")
  [[ -z "${3:-}" ]] || dispatch+=(-f "source_sha=$3")
  dispatch+=(-f confirm=prod -f "prod_switch_run=${GITHUB_RUN_ID}")
  if dry_run; then
    run "${dispatch[@]}"
    echo "[dry-run] watch that Kamal Deploy run until it ends" >&2
    return 0
  fi
  echo "==> Dispatching Kamal Deploy target=${to} ${tag} for this Prod Switch"
  "${dispatch[@]}" || fail "could not dispatch Kamal Deploy target=${to}; nothing touched prod"
  for attempt in $(seq 12); do
    id="$(gh run list -R "$GITHUB_REPOSITORY" --workflow kamal-deploy.yml --event workflow_dispatch \
      --json databaseId,displayTitle --limit 20 \
      | jq -r --arg suffix " for Prod Switch ${GITHUB_RUN_ID}" '[.[] | select(.displayTitle | endswith($suffix))] | first | .databaseId // empty')" || id=''
    [[ -z "$id" ]] || break
    echo "attempt ${attempt}: the dispatched Kamal Deploy run is not listed yet" >&2
    sleep 10
  done
  [[ -n "$id" ]] || fail 'the dispatched Kamal Deploy run did not appear within 2 minutes; nothing touched prod'
  echo "==> Watching Kamal Deploy run ${id}"
  gh run watch "$id" -R "$GITHUB_REPOSITORY" --exit-status ||
    fail "the target deploy (Kamal Deploy run ${id}) failed; nothing touched prod"
}

# check_switch_run: the run JSON (GET /repos/.../actions/runs/<id>) on stdin, RUN_ID, TARGET and
# ACTIVE_TARGET in the environment.
check_switch_run() {
  local path event status branch title
  : "${TARGET:?}" "${ACTIVE_TARGET:?}"
  { read -r path; read -r event; read -r status; read -r branch; read -r title; } < <(jq -r '.path, .event, .status, .head_branch, .display_title')
  [[ "$path" == '.github/workflows/prod-switch.yml' ]] || fail "Prod Switch run ${RUN_ID} is not a Prod Switch run (${path})"
  [[ "$event" == 'workflow_dispatch' ]] || fail "Prod Switch run ${RUN_ID} is not dispatched (${event})"
  [[ "$status" == 'in_progress' ]] || fail "Prod Switch run ${RUN_ID} is not in progress (${status})"
  [[ "$branch" == 'main' ]] || fail "Prod Switch run ${RUN_ID} is not on main (${branch})"
  [[ "$title" == "Prod Switch to ${TARGET}" ]] || fail "Prod Switch run ${RUN_ID} is not titled 'Prod Switch to ${TARGET}' (${title})"
  [[ "$TARGET" != "$ACTIVE_TARGET" ]] || fail "${TARGET} is the live prod host: Prod Switch deploys only the other host"
  echo "==> Prod Switch run ${RUN_ID} to ${TARGET} is in progress on main; deploying outside kamal-prod"
}

cmd_switch_run_check() {
  local json
  RUN_ID="$1"
  [[ "$RUN_ID" =~ ^[0-9]+$ ]] || fail "prod_switch_run must be a run id (got '${RUN_ID}')"
  json="$(gh api "repos/${GITHUB_REPOSITORY}/actions/runs/${RUN_ID}")" || fail "could not read Prod Switch run ${RUN_ID}"
  check_switch_run <<< "$json"
}

# dns_job_began: the jobs API pages of a run on stdin; a job began once it had a runner or a step.
# started_at is set even for a job cancelled while it waited for its approval.
dns_job_began() {
  jq -rs --arg name "$DNS_JOB_NAME" \
    '[.[].jobs[] | select(.name == $name)] | if any(.runner_name != null or ((.steps // []) | length) > 0) then "yes" else "no" end'
}

cmd_abort_check() {
  local from now jobs began refused
  from="$(target_of "$1")"
  load_project_env
  if dry_run; then
    echo "[dry-run] check that public DNS shows ${from} and that the prod-dns job of run ${GITHUB_RUN_ID:-} never began" >&2
    return 0
  fi
  refused="prod stays in maintenance on $(host_role "$1"): follow README \"Prod Switch\", after DNS"
  now="$(detect_active_target)" || fail "public DNS shows no single host; ${refused}"
  [[ "$now" == "$from" ]] || fail "public DNS shows ${now}, not ${from}: DNS moved; ${refused}"
  jobs="$(gh api --paginate "repos/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}/jobs")" ||
    fail "could not read the jobs of this run; ${refused}"
  began="$(dns_job_began <<< "$jobs")" || fail "could not read the jobs of this run; ${refused}"
  [[ "$began" == 'no' ]] || fail "the prod-dns job began, so DNS may have moved; ${refused}"
  echo "==> Public DNS shows ${from} and the prod-dns job never began: the abort may bring ${from} back"
}

# The old host's service is paused and its app stopped, so only the target can answer on these
# addresses; the health body alone cannot tell the hosts apart (both run the same release).
cmd_finalize_public() {
  local to_dest="$1" version="$2" to addr app_addr body deadline config
  require_version "$version"
  to="$(target_of "$to_dest")"
  load_project_env
  if dry_run; then
    echo "[dry-run] check that public DNS shows ${to}, then /health (release ${version#sha-}), the read-only smoke on https://${PROJECT_ZONE} and https://app.${PROJECT_ZONE}/config.js, pinned to those addresses" >&2
    echo "[dry-run] prod-previous <- prod-current, prod-current <- prod-${version}" >&2
    return 0
  fi
  [[ "$(detect_active_target)" == "$to" ]] || fail "public DNS does not show ${to}"
  addr="$(resolve_a "$PROJECT_ZONE" | head -n 1)"
  app_addr="$(resolve_a "app.${PROJECT_ZONE}" | head -n 1)"

  echo "==> Waiting up to ${PUBLIC_HEALTH_TIMEOUT}s for https://${PROJECT_ZONE}/health on ${to} to report release ${version#sha-}"
  deadline=$(( SECONDS + PUBLIC_HEALTH_TIMEOUT ))
  body=''
  until [[ "$body" == *'"status":"ok"'* && "$body" == *"\"release\":\"${version#sha-}\""* ]]; do
    (( SECONDS < deadline )) ||
      fail "https://${PROJECT_ZONE}/health on ${to} did not report release ${version#sha-} (last answer: ${body:-none}); follow README \"Prod Switch\", after DNS"
    sleep 5
    body="$(curl -fsS --max-time 5 --resolve "${PROJECT_ZONE}:443:${addr}" "https://${PROJECT_ZONE}/health" 2> /dev/null || true)"
  done
  echo "==> Healthy: ${body}"

  SMOKE_READ_ONLY=1 SMOKE_CONNECT_TO="${PROJECT_ZONE}:443:${addr}:443" bin/swagger_smoke "https://${PROJECT_ZONE}" ||
    fail "the read-only smoke failed on https://${PROJECT_ZONE} (${to}); follow README \"Prod Switch\", after DNS"

  config="$(curl -fsS --max-time 10 --resolve "app.${PROJECT_ZONE}:443:${app_addr}" "https://app.${PROJECT_ZONE}/config.js" 2> /dev/null | tr -d ' "' || true)"
  if ! grep -Eq "[{,]API_URL:https://${PROJECT_ZONE//./\\.}[,}]" <<< "$config" || ! grep -Eq '[{,]ENV_NAME:prod[,}]' <<< "$config"; then
    fail "https://app.${PROJECT_ZONE}/config.js does not set API_URL https://${PROJECT_ZONE} and ENV_NAME prod; follow README \"Prod Switch\", after DNS"
  fi
  echo "==> fe's config.js points at https://${PROJECT_ZONE}"

  resolve_registry
  crane_login
  DESTINATION="$to_dest"
  PROD_ACTIVE_TARGET="$to"
  rotate_prod_tags "prod-${version}"
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    echo "Prod runs on **${to}**: public DNS for ${PROJECT_ZONE} and app.${PROJECT_ZONE} points there, prod-current is prod-${version}." >> "$GITHUB_STEP_SUMMARY"
  fi
}

cmd_stop_old() {
  local dest="$1"
  target_of "$dest" > /dev/null
  load_project_env
  if ! dry_run && ! host_reachable "$dest"; then
    [[ "$dest" == 'prod' ]] || fail 'the srv host is not reachable over the VPN: its app containers may still run; stop them from a console'
    echo '==> Nothing to stop: the AWS instance is stopped by infra (prod_target=srv), and the freeze stopped its app containers'
    return 0
  fi
  echo "==> Stopping the app containers on $(host_role "$dest"); they, the accessories and the volumes stay, the service stays paused"
  stop_app "$dest"
}

SUBCOMMAND="${1:-}"
shift || true
case "$SUBCOMMAND:$#" in
  guard:0) cmd_guard ;;
  plan:0) load_project_env && select_steps ;;
  prepare:2 | prepare:3) cmd_prepare "$@" ;;
  standby:0) cmd_standby ;;
  wait-host:2) cmd_wait_host "$@" ;;
  deploy-target:2 | deploy-target:3) cmd_deploy_target "$@" ;;
  switch-run-check:1) cmd_switch_run_check "$@" ;;
  abort-check:1) cmd_abort_check "$@" ;;
  infra-options:0) infra_target_options ;;
  dns-began:0) dns_job_began ;;
  freeze:1) cmd_freeze "$@" ;;
  move-data:3) cmd_move_data "$@" ;;
  compare-counts:2) compare_counts "$@" ;;
  abort:2) cmd_abort "$@" ;;
  dns:1) cmd_dns "$@" ;;
  finalize-public:2) cmd_finalize_public "$@" ;;
  stop-old:1) cmd_stop_old "$@" ;;
  *) usage ;;
esac
