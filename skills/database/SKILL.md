---
name: database
description: >-
  Postgres for Ghostmind projects: create a database and role on the shared Postgres server (the db project),
  run Hasura on it, and manage migrations. Use when an app needs a database, a new DB/role/connection string,
  Hasura metadata or migrations, or when choosing how an app talks to Postgres.
---

# Database

Every product's data lives on **one shared Postgres server per environment**, run by the `db` project (`/Volumes/Projects/db`, read its `README.md` and `CLAUDE.md` first):

| | Dev | Prod |
|---|---|---|
| Cluster | the M1's (kube context `m1`), namespace `db` | ghostmind k3s (context `ghostmind`), namespace `db` |
| Address, from a pod | `db-postgres.db.svc.cluster.local:5432` | the same name |

The address is kept once, in Vault: `ghostmind/global/postgres#DB_HOST`. Each project gets its **own databases and its own role**, never the administrator's login. The API layer is a **Hasura** container per project. References: `/Volumes/Projects/format/db` (`scripts/create-db.sh`) and `/Volumes/Projects/tags/db` (migrations applied in the container); older: `potion/db`.

Both servers are shared infrastructure: ask before anything that creates, changes or removes a role or a database, and every time for prod. To look at what is on a server, use the `db` project's routines (`cd /Volumes/Projects/db/postgres && run routine list`, `run routine psql`; `DB_CONTEXT=ghostmind` in front for prod).

## Create a project database

1. **Names:** database `<project>_<app>_<env>` (underscores, e.g. `potion_db_dev`, `potion_db_prod`). Role `<project>_<env>`. A migrated project keeps its existing database names (tags: `tags-db-local`, `tags-db-prod`); don't move data to match the convention.
2. **Create the role and DB** with `scripts/create-db.sh`. Copy `/Volumes/Projects/format/db/scripts/create-db.sh` and change `PROJECT`. It handles three traps:
   - **The schema can't resolve yet.** The db schema needs `DB_USER`/`DB_PASSWORD`/`DB_NAME` from the Vault path this very script creates, so a plain `varlock run` refuses to start. Resolve only the Vault address and token, in the `create_db` routine:
     `varlock run --include-internal --filter APP_ENV,VAULT_ADDR,VAULT_TOKEN -- bash scripts/create-db.sh dev`
   - **No psql and no administrator password on the Mac.** The script runs psql inside the server's own pod, as its administrator, on the cluster that matches the environment:
     ```bash
     CONTEXT=$([ "$ENV" = prod ] && echo ghostmind || echo m1)
     psql() { kubectl --context "$CONTEXT" -n db exec -i deploy/postgres -- psql -U postgres "$@"; }
     ```
     A statement that carries a password goes in on stdin (`printf … | psql -q`), never on a command line.
   - **Re-runs are safe.** It creates the role and stores its password once. If the role exists but its Vault path doesn't (a previous run died in between), it sets a new password with `ALTER ROLE` and stores it.

   *Done when the new role connects to the new DB and `ghostmind/project/<project>/db/<env>` holds `DB_USER`, `DB_PASSWORD` and `DB_NAME`.*
3. **Point the apps at it.** The app/Hasura schema builds the URL from project credentials and the shared address:

   ```bash
   # @sensitive
   DB_USER=if(forEnv(prod), vaultSecret("ghostmind/project/<project>/db/prod"), vaultSecret("ghostmind/project/<project>/db/dev"))
   # @sensitive
   DB_PASSWORD=if(forEnv(prod), vaultSecret("ghostmind/project/<project>/db/prod"), vaultSecret("ghostmind/project/<project>/db/dev"))
   DB_NAME=if(forEnv(prod), vaultSecret("ghostmind/project/<project>/db/prod"), vaultSecret("ghostmind/project/<project>/db/dev"))
   DB_HOST=vaultSecret("ghostmind/global/postgres")
   # @sensitive
   HASURA_GRAPHQL_DATABASE_URL=concat("postgres://", $DB_USER, ":", $DB_PASSWORD, "@", $DB_HOST, ":5432/", $DB_NAME, "?sslmode=require")
   ```

   The product's Vault role needs `global/postgres` in its policy to read `DB_HOST`.

## Shape the schema around a workspace

Before the first migration, decide what the rows belong to. Strongly encouraged (`system` → *Workspaces*): a `workspaces` table (`id`, `user_id`, `name`, `is_default`, one default per person) and a `workspace_id` on every table that holds a person's data, with the foreign key cascading, so a second context, sharing or a team later needs no change to the tables. Reference: `/Volumes/Projects/potion/db`. A table that hangs off the user alone (their AI connection, their account settings) stays on `user_id`.

## Hasura

- **Hasura is a Deployment and Service like any app** (`/Volumes/Projects/tags/db/k8s/db.yaml`), reached by other apps at `http://<project>-db:<port>` and logging in to Vault with its service account. Its readiness and liveness probes hit `/healthz` on the app's real port; the image's built-in Docker healthcheck hardcodes 8080 and Kubernetes ignores it. To query prod from the Mac, use a read-only `kubectl --context ghostmind -n <project> port-forward`.
- **Pin the engine version that is already running.** For a migrated project, check first (`/v1/version` on the running server, or the `FROM` line of its Dockerfile): tags' prod ran `latest` = v2.49.4, and pinning an older tag would have downgraded the metadata catalog.
- Service `<project>-db`, image from `hasura/graphql-engine:<version>.cli-migrations-v3` (the variant that bundles `hasura-cli`), with the **glibc** varlock build installed (the image is Ubuntu; see `new-app` → docker.md).
- `HASURA_GRAPHQL_ADMIN_SECRET` and `HASURA_GRAPHQL_JWT_SECRET` live in `ghostmind/project/<project>/auth`. The JWT secret is shared with the web app and the MCP.
- The Hasura console gets **its own unique ports** from the registry (`hasura console --console-port <p> --api-port <p>`). The defaults, 9693/9695, belong to potion.
- **Prod applies migrations inside the container at start**, so the host never holds DB credentials. The official `cli-migrations-v3` entrypoint applies metadata *before* migrations, which breaks a commit that adds a table and tracks it. Use that image only for its `hasura-cli`, with this entrypoint order: a temporary server on a spare port → `hasura-cli migrate apply --all-databases` → `metadata apply` → `metadata ic list` → stop it → `graphql-engine serve`. Until the migrations succeed the real server never starts, the pod never becomes ready and the rollout times out. (The reference loops these steps so varlock stays PID 1, a habit from the Compose flow; on the cluster a failed start can simply exit and let Kubernetes restart the pod.) Copy `/Volumes/Projects/tags/db/docker/entrypoint.sh` and `Dockerfile` (`COPY app/state /hasura-project`). The console is enabled with `HASURA_GRAPHQL_ENABLE_CONSOLE`, not a `serve` flag.
- Dev migrations and metadata: `scripts/migrate.sh` runs `hasura migrate apply --database-name default && hasura metadata apply` against `HASURA_GRAPHQL_ENDPOINT`, as the routine `migrate` (`varlock run -- bash scripts/migrate.sh`). Create migrations with the Hasura console in dev and commit `app/state/`. Before merging, run the prod entrypoint's order against the dev DB.
- Apps that depend on new columns wait for the `db` job: `needs: db` in the project's `deploy.yaml` (see `deploy`).

## Dropping

Dropping a database is irreversible and the server hosts every other product. Always ask the user, name the exact database, and never touch a database outside the current project.
