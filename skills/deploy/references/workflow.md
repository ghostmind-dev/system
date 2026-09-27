# Deploy workflow template

`.github/workflows/<app>.yaml`, one per deployable app:

```yaml
name: <app>
on:
  workflow_dispatch:
  push:
    branches: [main]
    paths:
      - "<app>/**"
      - ".github/workflows/<app>.yaml"
concurrency:
  group: deploy-<project>
  cancel-in-progress: false
env:
  PROJECT: <project>
  APP: <app>
  CONTAINER: <project>-<app>
  HOST: <host>          # tailscale name of the server; change this line to move the app
  VAULT_ADDR: http://vault.tail0e3587.ts.net:8200
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: tailscale/github-action@v4
        with:
          oauth-client-id: ${{ secrets.TS_OAUTH_CLIENT_ID }}
          oauth-secret: ${{ secrets.TS_OAUTH_SECRET }}
          tags: tag:ci
      - uses: ghostmind-dev/play/actions/vault@main      # installs the vault CLI only (no login)
      - name: Mint a single-use login for the app
        id: login
        env:
          ROLE_ID: ${{ secrets.VAULT_CI_ROLE_ID }}
          SECRET_ID: ${{ secrets.VAULT_CI_SECRET_ID }}
        run: |
          export VAULT_TOKEN=$(vault write -field=token auth/approle/login role_id="$ROLE_ID" secret_id="$SECRET_ID")
          rid=$(vault read -field=role_id auth/approle/role/$PROJECT-$APP/role-id)
          sid=$(vault write -f -field=secret_id auth/approle/role/$PROJECT-$APP/secret-id)
          echo "::add-mask::$sid"
          echo "rid=$rid" >> "$GITHUB_OUTPUT"
          echo "sid=$sid" >> "$GITHUB_OUTPUT"
          vault token revoke -self
      - name: Deploy
        env:
          RID: ${{ steps.login.outputs.rid }}
          SID: ${{ steps.login.outputs.sid }}
        run: |
          # the login travels over stdin into RAM on the host, never in argv or on disk
          printf '%s\n%s\n' "$RID" "$SID" | tailscale ssh ghostmind@$HOST \
            "sudo install -d -m 700 /run/ghostmind/$PROJECT/$APP && \
             { read r; read s; umask 077; printf %s \"\$r\" | sudo tee /run/ghostmind/$PROJECT/$APP/role_id >/dev/null; \
               printf %s \"\$s\" | sudo tee /run/ghostmind/$PROJECT/$APP/secret_id >/dev/null; }"
          tailscale ssh ghostmind@$HOST /bin/bash <<EOF
          set -euo pipefail
          trap 'sudo rm -f /run/ghostmind/$PROJECT/$APP/*' EXIT   # used or not, the login goes
          cd ~/Projects/$PROJECT
          flock /tmp/$PROJECT-git.lock git pull --ff-only origin main
          cd $APP
          start=\$(date -u +%s)
          bash scripts/prod.sh
          sleep 5   # let varlock resolve and the app boot
          [ "\$(docker inspect -f '{{.State.Running}}' $CONTAINER)" = true ]
          started=\$(docker inspect -f '{{.State.StartedAt}}' $CONTAINER)
          [ "\$(date -u -d "\$started" +%s)" -ge "\$start" ] || { echo "not restarted: build failed"; exit 1; }
          EOF
```

Notes:
- `/run` on the host is tmpfs (RAM). `compose.prod.yaml` mounts `/run/ghostmind/<project>/<app>/{role_id,secret_id}` as compose `secrets:`. After startup the secret_id is spent (`num_uses=1`), and the trap deletes the files anyway.
- If varlock fails at container start (a missing secret or a denied policy), the container exits, the check goes red, and `docker logs <container>` says why, with `@sensitive` values redacted.
- Add `"shared/**"` to `paths` when the image copies shared code from the repo root.
- The quoting of the stdin hand-off and the `sleep` are first drafts; tighten them in the pilot.
