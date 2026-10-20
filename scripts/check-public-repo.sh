#!/usr/bin/env bash
# Fails when tracked files contain internal network details or private IDs
# that must never reach this public repository. Only file:line is printed,
# never the matching text, so CI logs do not repeat what was found.
# Patterns are written so they never match this file itself
# (escaped dots, bracketed single characters).
# Exceptions live only in the "Documented exceptions" section, each with its
# reason. The mirror publish runs this file before publishing the public mirror.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 2

status=0

# scan <label> <git grep args...> -- <pathspecs...>
scan() {
  local label=$1
  shift
  local out rc
  out=$(git grep -nI "$@")
  rc=$?
  case $rc in
    0)
      echo "::error::public-repo check failed: ${label}"
      printf '%s\n' "${out}" | cut -d: -f1,2
      status=1
      ;;
    1) ;;
    *) echo "git grep failed (${rc}) on rule: ${label}" >&2; exit 2 ;;
  esac
}

check() {
  local label=$1
  shift
  scan "${label}" "$@" -- .
}

ipv4='(^|[^0-9.])([0-9]{1,3}\.){3}[0-9]{1,3}([^0-9.]|$)'

# --- Documented exceptions -------------------------------------------------

# check_except <path>... -- <label> <git grep args...>: like check, but skips
# the given paths for this rule only.
check_except() {
  local excludes=()
  while [ "$1" != "--" ]; do
    excludes+=(":(exclude)$1")
    shift
  done
  shift
  local label=$1
  shift
  scan "${label}" "$@" -- . "${excludes[@]}"
}

# why: loopback, bind-all and the RFC 5737 documentation ranges can never be a
# real host (the deploy specs use them as sandbox hosts). They are removed per
# value, so a line that also holds a real address still fails.
allowed_ipv4='127\.0\.0\.1|0\.0\.0\.0|192\.0\.2\.[0-9]{1,3}|198\.51\.100\.[0-9]{1,3}|203\.0\.113\.[0-9]{1,3}'

# why: Gemfile, its lock and brakeman.ignore carry four-part gem versions and,
# being generated or JSON, cannot hold a comment.
check_ipv4() {
  local label="IPv4 literal (EIP or internal)"
  local hits rc out
  hits=$(git grep -nIE -e "${ipv4}" -- . \
    ':(exclude)Gemfile' ':(exclude)Gemfile.lock' ':(exclude)config/brakeman.ignore')
  rc=$?
  [ "${rc}" -le 1 ] || { echo "git grep failed (${rc}) on rule: ${label}" >&2; exit 2; }
  # One allowed value per pass, replaced by a non-digit marker, so the boundary
  # character next to it is still there for the following address.
  out=$(printf '%s\n' "${hits}" |
    sed -E -e ':a' -e "s/(^|[^0-9.])(${allowed_ipv4})([^0-9.]|$)/\\1X\\3/" -e 'ta' |
    grep -E "${ipv4}" | cut -d: -f1,2 | sort -u)
  if [ -n "${out}" ]; then
    echo "::error::public-repo check failed: ${label}"
    printf '%s\n' "${out}"
    status=1
  fi
}

# --- Rules ----------------------------------------------------------------

check "private LAN IP (192-168 range)"  -E  -e '192\.168\.'
check "internal VPN IP (10-18 range)"   -E  -e '(^|[^0-9])10\.18\.'
check_ipv4
check "internal hostname (vr8 prefix)"  -iE -e 'vr8[-]'
check "internal hostname srvN.local"   -iE -e 'srv[0-9]+\.local'
check "internal hostname (bonfir[e])"  -iE -e 'bonfir[e]'
check "AWS account ID (12 digits)"     -E  -e '(^|[^0-9])[0-9]{12}([^0-9]|$)'
check "Route53 hosted zone ID"         -E  -e '(^|[^A-Za-z0-9+/])Z[A-Z0-9]{12,}([^A-Za-z0-9+/=]|$)'
check "Trello link"                    -iE -e 'trello\.com'
check "Notion link or page ID"         -iE -e 'notion\.(so|site)' -e '(^|[^0-9a-f])[0-9a-f]{32}([^0-9a-f]|$)'
check "Telegram link or chat ID"       -iE -e 't\.me/' -e '-100[0-9]{9,}'
# why: the alert notifier steps must name the Bot API host (token and chat ID
# come from secrets) and the notifier spec asserts that URL.
check_except .github/workflows spec/deploy/infra_helpers_checkout_spec.rb -- \
  "Telegram Bot API host"              -iE -e 'api\.telegram\.org'
check "local home path"                -E  -e '/home/de[v]'

if [ "${status}" -eq 0 ]; then
  echo "public-repo check: clean"
fi
exit "${status}"
