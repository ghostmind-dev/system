# Deploy workflows for a Compose host

For apps deployed with [compose-host.md](compose-host.md). Cluster apps use `_deploy-k8s.yaml` (`deploy` skill).

Three kinds of file, all in `.github/workflows/`. The working reference is `/Volumes/Projects/ghostmind/users/.github/workflows/` (tags used the same files before moving to the cluster; see its git history).

## `_deploy.yaml`: one app's deploy (reusable)

```yaml
name: _deploy
on:
  workflow_call:
    inputs:
      app: { type: string, required: true }
      vault: { type: boolean, default: true }     # false: the app has no secrets (traefik)
      verify: { type: string, required: true }    # shell run on the host until it succeeds (3 min)
env:
  PROJECT: <project>
  HOST: <host>                                    # tailscale name of the server; change to move the project
  VAULT_ADDR: http://vault.tail0e3587.ts.net:8200
jobs:
  deploy:
    runs-on: ubuntu-latest
    env:
      APP: ${{ inputs.app }}
      CONTAINER: <project>-${{ inputs.app }}
    steps:
      - uses: tailscale/github-action@v4
        with:
          oauth-client-id: ${{ secrets.TS_OAUTH_CLIENT_ID }}
          oauth-secret: ${{ secrets.TS_OAUTH_SECRET }}
          tags: tag:ci
      - if: inputs.vault
        uses: ghostmind-dev/play/actions/vault@main
        with:
          login: "false"                          # the action logs in by default; install the CLI only
      - name: Mint a single-use login for the app
        if: inputs.vault
        id: login
        env:
          ROLE_ID: ${{ secrets.VAULT_CI_ROLE_ID }}
          SECRET_ID: ${{ secrets.VAULT_CI_SECRET_ID }}
        run: |
          set -euo pipefail
          export VAULT_TOKEN=$(vault write -field=token auth/approle/login role_id="$ROLE_ID" secret_id="$SECRET_ID")
          echo "::add-mask::$VAULT_TOKEN"
          rid=$(vault read -field=role_id auth/approle/role/$PROJECT-$APP/role-id)
          sid=$(vault write -f -field=secret_id auth/approle/role/$PROJECT-$APP/secret-id)
          echo "::add-mask::$sid"
          echo "rid=$rid" >> "$GITHUB_OUTPUT"
          echo "sid=$sid" >> "$GITHUB_OUTPUT"
          vault token revoke -self
      - name: Hand the login to the host (stdin -> RAM, never argv or disk)
        if: inputs.vault
        env:
          RID: ${{ steps.login.outputs.rid }}
          SID: ${{ steps.login.outputs.sid }}
        run: |
          set -euo pipefail
          printf '%s\n%s\n' "$RID" "$SID" | tailscale ssh ghostmind@$HOST \
            "set -e; d=/run/ghostmind/$PROJECT/$APP; sudo install -d -m 700 -o ghostmind -g ghostmind \$d; umask 077; read -r r; read -r s; printf %s \"\$r\" > \$d/role_id; printf %s \"\$s\" > \$d/secret_id"
      - name: Pull, build, restart, verify
        env:
          VERIFY: ${{ inputs.verify }}
        run: |
          set -euo pipefail
          tailscale ssh ghostmind@$HOST /bin/bash -s <<EOF
          set -euo pipefail
          trap 'rm -f /run/ghostmind/$PROJECT/$APP/*' EXIT        # used or not, the login goes
          cd ~/Projects/$PROJECT
          flock /tmp/$PROJECT-git.lock git pull --ff-only origin main
          cd $APP
          start=\$(date -u +%s)
          bash scripts/prod.sh
          started=\$(docker inspect -f '{{.State.StartedAt}}' $CONTAINER)
          [ "\$(date -u -d "\$started" +%s)" -ge "\$start" ] || { echo "::error::$CONTAINER was not recreated"; exit 1; }
          for i in \$(seq 1 36); do
            if [ "\$(docker inspect -f '{{.State.Running}} {{.RestartCount}}' $CONTAINER)" = "true 0" ] && ( $VERIFY ) >/dev/null 2>&1; then
              echo "$CONTAINER is up and verified"; exit 0
            fi
            sleep 5
          done
          echo "::error::$CONTAINER did not become healthy"; docker logs --tail 60 $CONTAINER; exit 1
          EOF
      - name: No secret in the container config
        run: |
          tailscale ssh ghostmind@$HOST "docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' <project>-${{ inputs.app }}" \
            | grep -E '^(VAULT_TOKEN|VAULT_SECRET_ID|.*SECRET|.*PASSWORD|.*PRIVATE_KEY)=' && { echo "::error::secret-looking env in docker inspect"; exit 1; } || echo "container env holds no secrets"
```

## `<app>.yaml`: a thin caller per app

```yaml
name: <app>
on:
  workflow_dispatch:
  push:
    branches: [main]
    paths: ["<app>/**", ".github/workflows/<app>.yaml", ".github/workflows/_deploy.yaml"]
concurrency:
  group: deploy-<project>-<app>        # per app: a shared group cancels sibling runs
  cancel-in-progress: false
permissions: { actions: read, contents: read }
jobs:
  deploy:
    uses: ./.github/workflows/_deploy.yaml
    secrets: inherit
    with:
      app: <app>
      verify: "curl -fsS http://127.0.0.1:<port>/health"
```

- **Apps that depend on DB migrations** add a `wait-db` job before `deploy` (`needs: wait-db`). It checks whether the commit touches `db/` and, if so, waits for the `db` workflow on the same SHA, refusing to deploy if it failed. It uses `${{ github.token }}` with `permissions: actions: read`, so no PAT is needed. Copy it from `tags/.github/workflows/city.yaml`.
- **`verify` probes the real thing:** a health URL for apps, `docker exec <c> curl localhost:<port>/healthz` for Hasura, `docker logs --since 3m <c> | grep -q 'Registered tunnel connection'` for the tunnel, `true` for traefik.

## `redeploy-all.yaml`: every app, in dependency order

`workflow_dispatch` only, one job per app calling `_deploy.yaml`, ordered with `needs:`: **db → apps → traefik → tunnel**. Use it after a host reboot (every container needs a fresh login) and for the first cutover from the legacy deploy. Reference: `tags/.github/workflows/redeploy-all.yaml`.
