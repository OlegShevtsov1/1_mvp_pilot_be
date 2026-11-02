#!/usr/bin/env bash
# The release-watch job of Kamal Deploy (R-C9): after a prod deploy, watch it for a while and
# report ✅ or ❌. It never rolls back; a person decides that (README "Releases").
# Usage: deploy/release_watch.sh health sha-<40 hex>
#          polls https://<PROJECT_ZONE>/health every WATCH_INTERVAL (30) seconds for WATCH_SECONDS
#          (600, prod-srv 180); a check passes only when it reports status ok and that release. Prints
#          since=<epoch>, checks=<n> and failed=<n> for GITHUB_OUTPUT, progress on stderr.
#          WATCH_DESTINATION=prod-srv (with PROD_SRV_VPN_IP) polls the srv host's shared kamal-proxy
#          over the VPN instead.
#        deploy/release_watch.sh verdict
#          env TAG, VERSION, CHECKS, FAILED, ISSUES_FILE (deploy/glitchtip_issues.sh output),
#          GLITCHTIP_OUTCOME (that step's outcome), RUN_URL. Prints result=ok|fail and message=<one
#          line for Telegram>. Issue titles appear only in the message; in Actions they are masked.
#          WATCH_DESTINATION=prod-srv names the srv host and its rollback in the message.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
source deploy/_common.sh

load_project_env
# Set directly: select_destination requires the SSH host, and only the prod-srv health checks need
# a host address (the srv host's proxy); prod uses the public URL.
DESTINATION="${WATCH_DESTINATION:-prod}"
if [[ "$DESTINATION" != 'prod' && "$DESTINATION" != 'prod-srv' ]]; then
  echo "error: unknown WATCH_DESTINATION '${DESTINATION}' (supported: prod, prod-srv)" >&2
  exit 2
fi
# prod-srv holds the shared VPN lock for the whole watch, and every other job's vpn-up waits for it
# only 300 s (CI_VPN_WAIT in 1_mvp_infra scripts/ci-vpn.sh): 6 checks take at most 210 s.
if [[ "$DESTINATION" == 'prod-srv' ]]; then
  WATCH_SECONDS="${WATCH_SECONDS:-180}"
else
  WATCH_SECONDS="${WATCH_SECONDS:-600}"
fi

watch_health() {
  local version="$1" seconds="$WATCH_SECONDS" interval="${WATCH_INTERVAL:-30}" checks failed=0 body i url
  require_version "$version"
  [[ "$DESTINATION" != 'prod-srv' ]] || require_prod_srv_host
  url="$(base_url)/health"
  checks=$(( seconds / interval ))
  echo "since=$(date +%s)"
  for (( i = 1; i <= checks; i++ )); do
    body="$(app_curl -fsS --max-time 10 "$url" 2> /dev/null || true)"
    if [[ "$body" == *'"status":"ok"'* && "$body" == *"\"release\":\"${version#sha-}\""* ]]; then
      echo "check ${i}/${checks}: ok" >&2
    else
      failed=$(( failed + 1 ))
      echo "check ${i}/${checks}: FAILED (${body:-no answer})" >&2
    fi
    (( i == checks )) || sleep "$interval"
  done
  echo "checks=${checks}"
  echo "failed=${failed}"
}

verdict() {
  local project="${PROJECT_NAME}-be-prod" sha="${VERSION:-}" where='' rollback head count named='' problems=() short_id title joined
  sha="${sha#sha-}"
  rollback='gh workflow run "Kamal Manage" --ref main -f action=rollback -f confirm=ROLLBACK-prod, or CONFIRM=ROLLBACK-prod deploy/rollback.sh prod'
  if [[ "$DESTINATION" == 'prod-srv' ]]; then
    where=' on srv'
    rollback='gh workflow run "Kamal Manage" --ref main -f action=rollback -f target=srv -f confirm=ROLLBACK-prod, or CONFIRM=ROLLBACK-prod deploy/rollback.sh prod-srv'
  fi
  head="release-watch ${project}${where} ${TAG:-?}${sha:+ (${sha:0:7})}"

  if [[ ! "${CHECKS:-}" =~ ^[1-9][0-9]*$ || ! "${FAILED:-}" =~ ^[0-9]+$ ]]; then
    problems+=('the /health watch did not finish')
  elif (( FAILED > 0 )); then
    problems+=("${FAILED}/${CHECKS} health checks failed")
  fi

  if [[ "${GLITCHTIP_OUTCOME:-}" != 'success' ]]; then
    problems+=('GlitchTip check failed (see the log)')
  else
    count="$(grep -c . "${ISSUES_FILE}" 2> /dev/null || true)"
    if (( ${count:-0} > 0 )); then
      while IFS=$'\t' read -r short_id title; do
        title="${title:0:80}"
        mask "$title" >&2
        named+="${named:+; }${short_id} ${title}"
      done < <(head -3 "${ISSUES_FILE}" | jq -r '[.shortId, (.title | gsub("[\\t\\n\\r]"; " "))] | @tsv')
      problems+=("${count} new GlitchTip issues: ${named}")
    fi
  fi

  if (( ${#problems[@]} == 0 )); then
    echo 'result=ok'
    echo "message=✅ ${head}: clean for $(( WATCH_SECONDS / 60 )) minutes, ${CHECKS}/${CHECKS} health checks ok, 0 new GlitchTip issues ${RUN_URL:-}"
    return 0
  fi
  joined="$(printf '%s; ' "${problems[@]}")"
  echo 'result=fail'
  echo "message=❌ ${head}: ${joined%; }. Prod was not rolled back automatically; to roll back: ${rollback} ${RUN_URL:-}"
}

case "${1:-}" in
  health) watch_health "${2:-}" ;;
  verdict) verdict ;;
  *)
    echo "usage: $0 health sha-<40 hex> | verdict" >&2
    exit 2
    ;;
esac
