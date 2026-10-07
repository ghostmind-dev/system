#!/usr/bin/env bash
# Audit a Ghostmind project folder against the system's conventions.
#   check.sh <project-dir>
# Prints one finding per line:  LEVEL  RULE  path  message
#   FAIL = breaks a rule of the system (fix it)   WARN = likely drift (look at it)
# Exit code: 1 if any FAIL, else 0. Read-only: it never changes anything.
set -uo pipefail

ROOT=$(cd "${1:?usage: check.sh <project-dir>}" && pwd)
FAILS=0
say() { # level rule path message
  local rel=${3#"$ROOT"/}; [ "$3" = "$ROOT" ] && rel=.
  printf '%-4s  %-10s  %s  %s\n' "$1" "$2" "$rel" "$4"
  [ "$1" = FAIL ] && FAILS=$((FAILS + 1))
}
has() { grep -Eq -- "$1" "$2" 2>/dev/null; }

# ---------- root layout ----------
ALLOWED_ROOT='^(README\.md|Readme\.md|CLAUDE\.md|AGENTS\.md|meta\.json|\.gitignore|\.github|\.claude-plugin|\.claude|\.vscode|\.git|\.DS_Store|\.mcp\.json|plugin|k8s|shared|\.dockerignore|\.history|node_modules)$'
is_service() { [ -d "$1" ] && { [ -f "$1/meta.json" ] || [ -d "$1/docker" ] || [ -f "$1/.env.schema" ] || [ -d "$1/app" ]; }; }
SERVICES=()
for p in "$ROOT"/* "$ROOT"/.[!.]*; do
  [ -e "$p" ] || continue
  n=$(basename "$p")
  if is_service "$p"; then SERVICES+=("$p"); continue; fi
  echo "$n" | grep -Eq "$ALLOWED_ROOT" && continue
  say WARN root "$p" "not allowed at the root (only README, CLAUDE.md, meta.json, .gitignore, .github, .claude-plugin, plugin/, k8s/, shared/ with its .dockerignore, and service folders)"
done
[ ${#SERVICES[@]} -eq 0 ] && is_service "$ROOT" && SERVICES=("$ROOT")   # a single-service folder passed directly

# ---------- .gitignore ----------
GI="$ROOT/.gitignore"
if [ -f "$GI" ]; then
  grep -Enq '^\s*(\*\*/)?\.env\.(\*|prod|dev|schema)\s*$' "$GI" && \
    ! grep -Eq '^\s*!.*\.env\.schema' "$GI" && \
    say FAIL gitignore "$GI" "ignores .env.* / .env.prod / .env.schema: the committed pointer files would be left out of git"
  grep -Eq '^\s*\.env\.local\s*$|\.env\.\*\.local' "$GI" || say WARN gitignore "$GI" "should ignore .env, .env.local and .env.*.local (template in new-app/references/docker.md)"
else
  say WARN gitignore "$ROOT" "no .gitignore"
fi

# ---------- per service ----------
for S in "${SERVICES[@]}"; do
  # legacy env files
  for f in .env.base .env.template env.base; do
    [ -f "$S/$f" ] && say FAIL legacy-env "$S/$f" "legacy env file: move to .env.schema + Vault (migrate skill)"
  done
  [ -f "$S/.env.local" ] && say FAIL env-local "$S/.env.local" "varlock ALWAYS loads .env.local, whatever the environment: delete it"
  SCHEMA="$S/.env.schema"
  if [ ! -f "$SCHEMA" ]; then
    { [ -d "$S/docker" ] || [ -d "$S/scripts" ] || ls "$S"/.env.* >/dev/null 2>&1; } && \
      say FAIL no-schema "$S" "no .env.schema: config and secrets must come from varlock (secrets skill)"
  else
    has '@plugin\(' "$SCHEMA" && ! grep -Eq '@plugin\([^)]*@[0-9]+\.[0-9]+\.[0-9]+\)' "$SCHEMA" && say WARN schema "$SCHEMA" "pin the Vault plugin to an exact version (@plugin(@varlock/hashicorp-vault-plugin@x.y.z))"
    has 'enum\([^)]*\blocal\b' "$SCHEMA" && say FAIL schema "$SCHEMA" "APP_ENV must be dev/prod, never 'local' (varlock always loads .env.local)"
    has 'remap\(' "$SCHEMA" && say WARN schema "$SCHEMA" "remap() returns the env name, not the value: use if(forEnv(prod), …)"
    has 'ghostmind/projects/' "$SCHEMA" && say FAIL schema "$SCHEMA" "Vault path is ghostmind/project/ (singular)"
    grep -En '\.ts\.net' "$SCHEMA" 2>/dev/null | grep -Ev '^[0-9]+:\s*(#|VAULT_ADDR)' | grep -Eq . && \
      say WARN runtime-net "$SCHEMA" "a value points at a Tailscale name: between Hetzner servers running prod calls use the private network (10.0.0.x); fine if it's dev-only or a deliberate cross-provider link"
  fi
  # meta.json
  M="$S/meta.json"
  if [ -f "$M" ]; then
    for k in compose docker terraform custom secrets tmux template global tunnel mcp scope; do
      has "^\s*\"$k\"\s*:" "$M" && say WARN meta "$M" "deprecated key \"$k\""
    done
    has '"run (custom|vault|docker|terraform|tmux|meta|action)' "$M" && say FAIL routine "$M" "routine calls a deprecated run command (run custom/vault/docker/terraform/tmux…): use scripts/*.sh"
    has '--cible|--env=/run/secrets' "$M" && say FAIL routine "$M" "legacy env injection (--cible / --env): use varlock"
    has '"bash -c ' "$M" && say WARN routine "$M" "run routine has no shell: 'bash -c \"…\"' breaks; move it into scripts/*.sh"
    if has '"herdr"' "$M" && ! has '"prefix"\s*:\s*false' "$M"; then say WARN herdr "$M" "herdr tabs without \"prefix\": false get app-prefixed names (mcp-mcp)"; fi
    if [ -f "$S/docker/compose.dev.yaml" ] && has 'VAULT_TOKEN' "$S/docker/compose.dev.yaml" && has '"dev"\s*:\s*"varlock run -- ' "$M"; then
      say FAIL routine "$M" "dev passes VAULT_TOKEN to the container but the routine lacks --include-internal: the container gets it empty"
    fi
  fi
  # scripts
  for f in "$S"/scripts/*.ts; do
    [ -f "$f" ] || continue
    has 'jsr:@ghostmind/run' "$f" && say FAIL scripts "$f" "run custom script: rewrite as scripts/*.sh"
  done
  [ -f "$S/scripts/prod.sh" ] && ! has 'force-recreate' "$S/scripts/prod.sh" && \
    say WARN prod-sh "$S/scripts/prod.sh" "add --force-recreate, or the deploy's restart check fails on unchanged images"
  # docker
  D="$S/docker"
  if [ -d "$D" ]; then
    [ -f "$D/compose.local.yaml" ] && say WARN compose "$D/compose.local.yaml" "rename to compose.dev.yaml (environments are dev/prod)"
    for c in "$D"/compose*.yaml; do
      [ -f "$c" ] || continue
      has '^\s*env_file:' "$c" && say FAIL compose "$c" "env_file puts secrets in docker inspect: resolve them with varlock in the container"
      has '\$\{(SRC|LOCALHOST_SRC)\}' "$c" && say FAIL compose "$c" "\${SRC}/\${LOCALHOST_SRC} are legacy: use paths relative to the compose file"
      has '/run/secrets/[a-z]' "$c" && ! has '/run/ghostmind' "$c" && say FAIL compose "$c" "legacy /run/secrets/<project> files: use the single-use login flow (deploy skill)"
      has '"?(0\.0\.0\.0:)?(80|8080):(80|8080)"?' "$c" && say FAIL compose "$c" "Traefik publishes no host port (80/8080): the tunnel reaches it on the compose network"
      has '0\.0\.0\.0' "$c" && say FAIL compose "$c" "binds 0.0.0.0: use 127.0.0.1, the private address (10.0.0.x) or the Tailscale IP"
      has '^\s*platform:' "$c" && say WARN compose "$c" "platform: pin forces emulation on the Mac; images must build natively on arm64 and amd64"
      case "$c" in *prod*)
        grep -E '^\s*-\s*"?[0-9]+:[0-9]+"?\s*$' "$c" >/dev/null 2>&1 && \
          say FAIL compose "$c" "a prod port without a host address binds every interface: prefix 127.0.0.1:, \${PRIVATE_IP}: or \${TAILSCALE_IP}:"
      esac
    done
    DF="$D/Dockerfile"
    if [ -f "$DF" ]; then
      if has 'COPY --from=ghcr.io/dmno-dev/varlock' "$DF" && ! has '^FROM .*alpine' "$DF"; then
        say FAIL dockerfile "$DF" "the official varlock image is a musl binary: on Debian/Ubuntu bases install the glibc release (new-app docker.md)"
      fi
      grep -E 'https?://[^ ]*(x86_64|amd64|linux-x64)' "$DF" | grep -vq TARGETARCH && \
        say WARN dockerfile "$DF" "hardcoded architecture in a download URL: pick it from TARGETARCH (dev is arm64, prod amd64)"
      has '^FROM .*--platform' "$DF" && say WARN dockerfile "$DF" "--platform in FROM: build natively on each architecture"
      [ -f "$SCHEMA" ] && has 'vaultSecret\(' "$SCHEMA" && ! has 'ENTRYPOINT \["varlock"' "$DF" && \
        say WARN dockerfile "$DF" "entrypoint is not varlock: the container won't resolve its own secrets"
    fi
  fi
  # kubernetes (the default target)
  K="$S/k8s"; N=$(basename "$S")
  if [ -d "$K" ]; then
    PRODM=$(ls "$K"/*.yaml 2>/dev/null | grep -v '\.dev\.yaml$' | head -1)
    [ -n "$PRODM" ] || say FAIL k8s "$K" "no prod manifest (k8s/<app>.yaml)"
    [ -n "$PRODM" ] && ! has 'image:\s*IMAGE\s*$' "$PRODM" && say FAIL k8s "$PRODM" "prod manifest must use 'image: IMAGE' (CI replaces it with the built digest)"
    if [ -n "$PRODM" ] && [ -f "$SCHEMA" ] && has 'vaultSecret\(' "$SCHEMA"; then
      has 'VAULT_JWT_ROLE' "$PRODM" || say FAIL k8s "$PRODM" "the app reads Vault but the Deployment sets no VAULT_JWT_ROLE (login by service account)"
      has 'jwtAuthPath=k8s' "$SCHEMA" || say FAIL schema "$SCHEMA" "add jwtRole/jwtAuthPath=k8s/oidcToken to @initHcpVault and the VAULT_JWT line (secrets skill)"
      has 'ts\.net' "$PRODM" && say WARN k8s "$PRODM" "prod VAULT_ADDR should be Vault's private address (http://10.0.0.7:8200)"
    fi
    [ -f "$D/entrypoint.sh" ] && has 'while true' "$D/entrypoint.sh" && \
      say WARN k8s "$D/entrypoint.sh" "prod restart loop: that is for a Compose host's single-use login. On the cluster exec the app and let Kubernetes restart the pod (new-app docker.md)"
    [ -n "$PRODM" ] && has 'VAULT_TOKEN|secretKeyRef' "$PRODM" && say FAIL k8s "$PRODM" "no token or secret handed to a prod pod: it logs in to Vault with its service account"
    if ls "$K"/*.dev.yaml >/dev/null 2>&1; then
      SK="$S/skaffold.yaml"
      if [ ! -f "$SK" ]; then say FAIL skaffold "$S" "dev manifest without skaffold.yaml"
      else
        has '^\s*kubeContext:' "$SK" && say FAIL skaffold "$SK" "remove deploy.kubeContext: no file names a cluster; skaffold dev uses the current kube context (paired with the Docker context on the same machine)"
        has '^\s*sync:' "$SK" || say WARN skaffold "$SK" "no file sync: hot reload is required (sync: infer on the source folders), unless the app has no dev server"
        has 'push:\s*false' "$SK" || say WARN skaffold "$SK" "set build.local.push: false (the cluster on the Docker host uses the image directly)"
      fi
      # an app that builds from the repo root (skaffold context: .., for a shared/ folder) uses the root .dockerignore
      DI="$S/.dockerignore"; [ -f "$SK" ] && has 'context:\s*\.\.' "$SK" && DI="$ROOT/.dockerignore"
      # only an image that installs dependencies needs one (not cloudflared or Hasura)
      [ ! -f "$S/app/package.json" ] || { [ -f "$DI" ] && has 'node_modules' "$DI"; } || say FAIL docker "$S" "no .dockerignore excluding node_modules/.next/dist (at the repo root for an app that builds from it): the Mac's node_modules would hide the image's own"
      [ -f "$M" ] && ! has '"dev"\s*:\s*"skaffold dev' "$M" && say WARN routine "$M" "the dev routine of a Kubernetes app is \"skaffold dev\""
      ls "$K"/*.dev.yaml | while read -r dm; do
        grep -Eq '^kind:\s*(Namespace|PersistentVolumeClaim)' "$dm" && say WARN k8s "$dm" "shared things (namespace, volumes) belong in a pre-deploy hook, not in one app's dev manifest"
      done
    else
      [ -f "$D/compose.dev.yaml" ] || say WARN k8s "$K" "no dev manifest (k8s/<app>.dev.yaml + skaffold.yaml)"
      [ -f "$D/compose.dev.yaml" ] && say WARN k8s "$S" "prod is on Kubernetes but dev still uses Compose: move dev to Skaffold (reference: portal)"
    fi
  elif [ -f "$S/docker/Dockerfile" ] && ls "$D"/compose*.yaml >/dev/null 2>&1; then
    say WARN target "$S" "Compose only: fine for a non-cluster target (Cloud Run, standalone host); otherwise Kubernetes is the default (new-app kubernetes.md)"
  fi
  # a remote MCP on the cluster is stateless: several replicas, nothing pins a client to a pod
  if [ -d "$K" ] && [ -f "$S/app/package.json" ] && has '@modelcontextprotocol/' "$S/app/package.json"; then
    SRC="$S/app/src"; [ -d "$SRC" ] || SRC="$S/app"
    grep -rEq --exclude-dir=node_modules --exclude-dir=dist 'sessionIdGenerator\s*:\s*[^u[:space:]]|transports(\[|\.set\()' "$SRC" 2>/dev/null && \
      say FAIL mcp-state "$S" "the MCP keeps sessions in process memory: with 2 replicas the next request reaches a pod that never saw the session (404 Session not found). Make it stateless (new-app blocks.md)"
    has '"@modelcontextprotocol/sdk"' "$S/app/package.json" && \
      say WARN mcp-state "$S/app/package.json" "@modelcontextprotocol/sdk 1.x: move to v2 (@modelcontextprotocol/server + /node), which has no sessions (npx @modelcontextprotocol/codemod@latest v1-to-v2 .)"
    for dm in "$K"/*.dev.yaml; do
      [ -f "$dm" ] && grep -Eq '^kind:\s*Deployment' "$dm" && ! has '^\s*replicas:\s*[2-9]' "$dm" && \
        say WARN mcp-state "$dm" "an MCP's dev manifest runs replicas: 2, so a pod-bound request can't hide in dev"
    done
  fi
  [ "$N" = traefik ] && say WARN traefik "$S" "Traefik is no longer part of the pattern: the tunnel routes straight to each app's Service"
  # package.json dev port
  P="$S/app/package.json"
  [ -f "$P" ] && has '"dev"\s*:\s*"[^"]*--port[ =]?[0-9]+' "$P" && \
    say WARN port "$P" "dev script hardcodes the port: use --port \$PORT so the schema owns it"
done

# ---------- workflows ----------
for w in "$ROOT"/.github/workflows/*.y*ml; do
  [ -f "$w" ] || continue
  has 'kubectl .*(--context[ =]ghostmind|config use-context ghostmind)' "$w" && say FAIL workflow "$w" "a stored prod kube context in CI: log in with the run's OIDC token (_deploy-k8s.yaml)"
  has 'policy=admin' "$w" && say FAIL workflow "$w" "CI mints an admin Vault token: CI only mints single-use logins (deploy skill)"
  has 'VAULT_TOKEN:\s*\$\{\{\s*secrets\.' "$w" && say FAIL workflow "$w" "a Vault token in GitHub secrets: CI never needs one"
  has 'run vault kv export|/run/secrets/\$' "$w" && say FAIL workflow "$w" "legacy secret export to /run/secrets: use the single-use login flow"
  has 'play/actions/vault@' "$w" && ! has 'login:\s*"?false' "$w" && say WARN workflow "$w" "play/actions/vault logs in by default: pass login: \"false\""
  has 'group:\s*deploy-[a-z0-9]+\s*$' "$w" && say WARN workflow "$w" "concurrency group shared by all apps cancels sibling runs: use deploy-<project>-<app>"
  has 'StartedAt' "$w" && ! has 'RestartCount' "$w" && say WARN workflow "$w" "sleep-based verification: use the health-check loop from deploy/references/workflow.md"
done

# ---------- AI-operable ----------
for S in "${SERVICES[@]}"; do
  if [ "$(basename "$S")" = mcp ] && [ ! -f "$ROOT/plugin/.mcp.json" ]; then
    say WARN plugin "$ROOT" "the product has an MCP but no plugin/ (.mcp.json + skill): products are AI-operable by default"
  fi
done

# ---------- port collisions across projects ----------
# host side of "HOST:CONTAINER" / "IP:HOST:CONTAINER" port mappings in compose files
ports_of() { grep -hE '^\s*-\s*"?[^ #]*[0-9]+:[0-9]+"?\s*(#.*)?$|ports:\s*\[' "$@" 2>/dev/null \
  | grep -oE '[0-9]{2,5}:[0-9]{2,5}"?\s*(\]|,|$|#)' | cut -d: -f1 | sort -un; }
MINE=$(ports_of "$ROOT"/*/docker/compose*.yaml)
if [ -n "$MINE" ]; then
  for other in /Volumes/Projects/*/*/; do
    o=${other%/}; [ "$o" = "$ROOT" ] && continue
    for port in $(ports_of "$o"/*/docker/compose*.yaml); do
      echo "$MINE" | grep -qx "$port" && say WARN port "$ROOT" "host port $port is also published by $(basename "$(dirname "$o")")/$(basename "$o")"
    done
  done
fi

echo
echo "$FAILS failing check(s)."
[ "$FAILS" -eq 0 ]
