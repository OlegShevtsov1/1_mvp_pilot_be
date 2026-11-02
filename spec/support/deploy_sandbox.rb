require 'open3'
require 'tmpdir'
require 'fileutils'

# deploy/*.sh are shell, so none of the project's Ruby gates look at them. They resolve the repo
# root from their own path, which lets the real scripts run inside a throwaway tree whose PATH
# shims stand in for kamal (bundle), curl, aws, crane, git, ssh, nc, getent and gh and record how
# they were called.
module DeploySandbox
  SHA = 'a' * 40
  # Built, not written out: the public-repo grep rejects any literal 12-digit number.
  ACCOUNT_ID = ('1' * 12).freeze

  SHIMS = {
    # Every call is logged; `kamal app containers` / `kamal app version` / `kamal app exec` answer
    # from fixtures, or fail like an unreachable host when a <name>.fail fixture exists. A
    # version-<config file name>.txt answers `kamal app version` for that config only.
    'bundle' => <<~'SH',
      #!/usr/bin/env bash
      echo "$*" >> "$SANDBOX/bundle.log"
      config="${!#}"
      case "$*" in
        *'kamal app containers'*) [[ -e "$SANDBOX/containers.fail" ]] && exit 1; cat "$SANDBOX/containers.txt" 2>/dev/null ;;
        *'kamal app version'*)
          [[ -e "$SANDBOX/version.fail" ]] && exit 1
          cat "$SANDBOX/version-${config##*/}.txt" 2>/dev/null || cat "$SANDBOX/version.txt" 2>/dev/null ;;
        *'kamal app exec'*) [[ -e "$SANDBOX/exec.fail" ]] && exit 1; cat "$SANDBOX/exec.txt" 2>/dev/null ;;
      esac
      exit 0
    SH
    # /health answers health.json. The GlitchTip API (/api/0/) answers glitchtip-page1.json, or
    # glitchtip-page2.json for a cursor URL, with headers from glitchtip-page<n>.headers and the
    # status from glitchtip-code; the headers curl reads from stdin (-H @-) go to curl.stdin.
    'curl' => <<~'SH',
      #!/usr/bin/env bash
      echo "$*" >> "$SANDBOX/curl.log"
      url="${!#}"
      if [[ "$url" == */api/0/* ]]; then
        cat >> "$SANDBOX/curl.stdin"
        page=1
        [[ "$url" == *cursor=* ]] && page=2
        out=/dev/stdout dump=/dev/null
        while (( $# )); do
          case "$1" in -o) out="$2"; shift ;; -D) dump="$2"; shift ;; esac
          shift
        done
        cat "$SANDBOX/glitchtip-page${page}.json" > "$out"
        cat "$SANDBOX/glitchtip-page${page}.headers" > "$dump" 2> /dev/null || printf 'HTTP/1.1 200 OK\r\n\r\n' > "$dump"
        cat "$SANDBOX/glitchtip-code" 2> /dev/null || printf 200
        exit 0
      fi
      [[ "$url" == */config.js ]] && { cat "$SANDBOX/config.js"; exit 0; }
      cat "$SANDBOX/health.json"
    SH
    'aws' => <<~SH,
      #!/usr/bin/env bash
      case "$*" in
        'sts get-caller-identity'*) echo "$AWS_SHIM_ACCOUNT" ;;
        'ecr get-login-password'*) echo 'ecr-password-from-shim' ;;
      esac
    SH
    # A registry of plain files: `digests` holds `<tag> <digest>` lines, manifest-<tag>.json and
    # config-<tag>.json the image documents. `mutate` copies the source with the new service label
    # and, like the real crane, without null config fields.
    'crane' => <<~'SH',
      #!/usr/bin/env bash
      set -euo pipefail
      if [[ "$1" == 'auth' ]]; then
        read -r _password
        echo "auth login $3" >> "$SANDBOX/crane.log"
        exit 0
      fi
      echo "$*" >> "$SANDBOX/crane.log"
      touch "$SANDBOX/digests"
      case "$1" in
        digest)
          line="$(grep "^${2##*:} " "$SANDBOX/digests")" || { echo 'MANIFEST_UNKNOWN' >&2; exit 1; }
          echo "${line#* }" ;;
        manifest) cat "$SANDBOX/manifest-${2##*:}.json" ;;
        config) cat "$SANDBOX/config-${2##*:}.json" ;;
        mutate)
          src="${2##*:}" dst="${6##*:}"
          echo "$dst sha256:prod${src}" >> "$SANDBOX/digests"
          jq -c '.config.digest = "sha256:cfgprod"' "$SANDBOX/manifest-${src}.json" > "$SANDBOX/manifest-${dst}.json"
          jq -c --arg service "${4#service=}" '.config.Labels.service = $service | .config |= with_entries(select(.value != null))' \
            "$SANDBOX/config-${src}.json" > "$SANDBOX/config-${dst}.json" ;;
        tag)
          grep -v "^$3 " "$SANDBOX/digests" > "$SANDBOX/digests.new" || true
          echo "$3 ${2#*@}" >> "$SANDBOX/digests.new"
          mv "$SANDBOX/digests.new" "$SANDBOX/digests" ;;
      esac
    SH
    # A published annotated release tag on main unless a fixture says otherwise: tag-fetch.fail
    # (not on origin), tag-type (e.g. commit for a lightweight tag), not-on-main. Anything else
    # (rev-parse) answers SHA.
    'git' => <<~SH,
      #!/usr/bin/env bash
      case "$*" in
        fetch*) echo "$*" >> "$SANDBOX/git.log"; [[ -e "$SANDBOX/tag-fetch.fail" ]] && exit 1; exit 0 ;;
        'cat-file -t '*) cat "$SANDBOX/tag-type" 2>/dev/null || echo tag ;;
        'merge-base --is-ancestor '*) [[ -e "$SANDBOX/not-on-main" ]] && exit 1; exit 0 ;;
        *) echo "#{SHA}" ;;
      esac
    SH
    # Logs the arguments and the size of stdin to ssh.log. Answers per host address (the part after
    # user@): pg_dump with dump.bin, psql with counts-<address>.txt, docker ps with fe-<address>.txt;
    # fails like an unreachable host when ssh-<address>.fail exists.
    'ssh' => <<~'SH',
      #!/usr/bin/env bash
      cmd="${!#}"
      host=''
      for arg in "$@"; do [[ "$arg" == *@* ]] && host="${arg#*@}"; done
      echo "$* stdin=$(wc -c | tr -d ' ')" >> "$SANDBOX/ssh.log"
      [[ -e "$SANDBOX/ssh-${host}.fail" ]] && exit 255
      case "$cmd" in
        *pg_dump*) cat "$SANDBOX/dump.bin" ;;
        *psql*) cat "$SANDBOX/counts-${host}.txt" ;;
        *'docker ps'*) cat "$SANDBOX/fe-${host}.txt" 2>/dev/null ;;
      esac
      exit 0
    SH
    # `nc -z -w 5 <address> 22` succeeds unless nc-<address>.fail exists.
    'nc' => <<~'SH',
      #!/usr/bin/env bash
      echo "$*" >> "$SANDBOX/nc.log"
      [[ ! -e "$SANDBOX/nc-${@: -2:1}.fail" ]]
    SH
    # Public DNS: hosts.txt holds `<name> <address>` lines; `getent ahostsv4 <name>` answers like
    # the real one, or exits 2 for a name it does not hold.
    'getent' => <<~'SH',
      #!/usr/bin/env bash
      found=2
      while read -r name addr; do
        [[ "$name" == "$2" ]] && { echo "$addr      STREAM $name"; echo "$addr      DGRAM"; found=0; }
      done < "$SANDBOX/hosts.txt"
      exit "$found"
    SH
    # Every call is logged. `workflow run` exits with gh-dispatch.code, `workflow view` answers
    # gh-workflow.yml (or fails without it), `run list` answers gh-runs.json, `run watch` exits with
    # gh-watch.code and `run view` answers gh-view.json. `api` answers gh-jobs.json for a .../jobs
    # path and gh-run.json otherwise, or fails when gh-api.fail exists.
    'gh' => <<~'SH',
      #!/usr/bin/env bash
      echo "$*" >> "$SANDBOX/gh.log"
      if [[ "$1" == 'api' ]]; then
        [[ -e "$SANDBOX/gh-api.fail" ]] && exit 1
        if [[ "${!#}" == */jobs ]]; then cat "$SANDBOX/gh-jobs.json"; else cat "$SANDBOX/gh-run.json"; fi
        exit 0
      fi
      case "$1 $2" in
        'workflow run') exit "$(cat "$SANDBOX/gh-dispatch.code" 2>/dev/null || echo 0)" ;;
        'workflow view') cat "$SANDBOX/gh-workflow.yml" 2>/dev/null || exit 1 ;;
        'run list') cat "$SANDBOX/gh-runs.json" ;;
        'run watch') exit "$(cat "$SANDBOX/gh-watch.code" 2>/dev/null || echo 0)" ;;
        'run view') cat "$SANDBOX/gh-view.json" ;;
      esac
    SH
    # Waiting is instant; a hosts-next.txt fixture becomes the public DNS after the first wait.
    'sleep' => <<~'SH'
      #!/usr/bin/env bash
      [[ -e "$SANDBOX/hosts-next.txt" ]] && mv "$SANDBOX/hosts-next.txt" "$SANDBOX/hosts.txt"
      exit 0
    SH
  }.freeze

  def write_executable(path, body)
    File.write(path, body)
    FileUtils.chmod(0o755, path)
  end

  def build_sandbox(root)
    %w[deploy .kamal].each { |dir| FileUtils.cp_r(Rails.root.join(dir).to_s, File.join(root, dir)) }
    FileUtils.mkdir_p([ File.join(root, 'config'), File.join(root, 'bin'), File.join(root, 'shim') ])
    %w[config/project.env config/deploy.dev.yml config/deploy.yml].each do |file|
      FileUtils.cp(Rails.root.join(file), File.join(root, file))
    end
    # The real scripts wait minutes for a healthy release; one second keeps the unhealthy paths fast.
    Dir[File.join(root, 'deploy', '*.sh')].each do |script|
      File.write(script, File.read(script).gsub(/HEALTH_TIMEOUT=\d+/, 'HEALTH_TIMEOUT=1'))
    end
    SHIMS.each { |name, body| write_executable(File.join(root, 'shim', name), body) }
    write_executable(File.join(root, 'bin', 'swagger_smoke'), <<~SH)
      #!/usr/bin/env bash
      echo "$* SMOKE_CONNECT_TO=${SMOKE_CONNECT_TO:-} SMOKE_FORWARDED_PROTO=${SMOKE_FORWARDED_PROTO:-} SMOKE_READ_ONLY=${SMOKE_READ_ONLY:-}" > "$SANDBOX/smoke.log"
      ${SMOKE_SHIM_FAILS:+exit 1}
      echo 'all passed'
    SH
  end

  # Public DNS with the AWS host live: the zone and app.<zone> resolve away from dev.<zone>, the
  # address of the public TLS terminator in front of the srv host.
  def public_dns(target)
    zone = project_env.fetch('PROJECT_ZONE')
    prod = target == 'srv' ? '192.0.2.20' : '192.0.2.10'
    "#{zone} #{prod}\napp.#{zone} #{prod}\ndev.#{zone} 192.0.2.20\n"
  end

  def project_env
    Rails.root.join('config/project.env').readlines(chomp: true)
      .grep(/\A[A-Z_]+=/).to_h { |line| line.split('=', 2) }
  end

  def secrets_env
    {
      'SECRET_KEY_BASE' => 'skb', 'POSTGRES_PASSWORD' => 'pgpass', 'SENTRY_DSN' => 'https://k@e.test/1',
      'SENTRY_ALLOWED_FE_DSN' => 'https://f@e.test/2', 'SMOKE_TOKEN' => 'smoke'
    }
  end

  # The registry state after Dev Deploy built sha-<sha>: one image, labelled for the dev service.
  def dev_image_files(sha = SHA)
    {
      'digests' => "sha-#{sha} sha256:dev#{sha}\n",
      "manifest-sha-#{sha}.json" => '{"config":{"digest":"sha256:cfgdev"},"layers":[{"digest":"sha256:L1"},{"digest":"sha256:L2"}]}',
      "config-sha-#{sha}.json" => %({"rootfs":{"type":"layers","diff_ids":["sha256:l1","sha256:l2"]},) +
        %("config":{"Labels":{"service":"#{project_env.fetch('PROJECT_NAME')}-dev"},"Env":["APP_RELEASE=#{sha}"],"OnBuild":null}})
    }
  end

  # Runs deploy/<script> with args inside a fresh sandbox and yields (output, status, sandbox).
  # `release` is what the stubbed /health reports; `files` are extra sandbox fixtures (name => content).
  def run_script(script, *args, env: {}, release: SHA, containers: nil, current_version: nil, files: {}, stdin: '')
    Dir.mktmpdir do |root|
      build_sandbox(root)
      File.write(File.join(root, 'health.json'), %({"status":"ok","release":"#{release}"}))
      File.write(File.join(root, 'hosts.txt'), public_dns('aws'))
      File.write(File.join(root, 'containers.txt'), containers) if containers
      File.write(File.join(root, 'version.txt'), current_version) if current_version
      files.each { |name, content| File.write(File.join(root, name), content) }
      full_env = {
        'PATH' => "#{File.join(root, 'shim')}:#{ENV.fetch('PATH')}",
        'SANDBOX' => root,
        'DEV_HOST' => '192.0.2.10',
        'AWS_SHIM_ACCOUNT' => ACCOUNT_ID,
        # nil unsets, so values exported in the caller's shell cannot make a spec pass vacuously.
        'SKIP_SMOKE' => nil, 'GITHUB_ACTIONS' => nil, 'PROJECT_NAME' => nil, 'PROJECT_ZONE' => nil,
        'KAMAL_REGISTRY_SERVER' => nil, 'KAMAL_REGISTRY_PASSWORD' => nil, 'PROD_VPN_IP' => nil, 'PROD_SRV_VPN_IP' => nil,
        'WATCH_DESTINATION' => nil, 'PROD_ACTIVE_TARGET' => nil, 'DRY_RUN' => nil, 'GH_TOKEN' => nil,
        'INFRA_PROD_REPO' => nil, 'RUNNER_TEMP' => nil, 'GITHUB_OUTPUT' => nil, 'GITHUB_REPOSITORY' => nil, 'GITHUB_RUN_ID' => nil,
        'AFTER_STANDBY' => nil, 'REQUIRE_READY' => nil,
        'GITHUB_STEP_SUMMARY' => nil, 'BACKUP_GATE' => nil, 'CONFIRM' => nil,
        'GLITCHTIP_API_TOKEN' => nil, 'GLITCHTIP_API_URL' => nil
      }.merge(secrets_env).merge(env)
      output, status = Open3.capture2e(full_env, File.join(root, 'deploy', script), *args, stdin_data: stdin)
      yield(output, status, root)
    end
  end

  def sandbox_log(root, name)
    path = File.join(root, name)
    File.exist?(path) ? File.read(path) : ''
  end
end

RSpec.configure do |config|
  config.include DeploySandbox, file_path: %r{spec/deploy/}
end
