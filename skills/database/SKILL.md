---
name: database
description: >-
  Postgres for Ghostmind projects: create a database and role on the shared AWS RDS, run Hasura on it,
  and manage migrations. Use when an app needs a database, a new DB/role/connection string, Hasura
  metadata or migrations, or when choosing how an app talks to Postgres.
---

# Database

Every product's data lives on **one shared AWS RDS Postgres** instance. The admin login is `ghostmind/global/postgres` (`PGHOST`, `PGUSER`, `PGPASSWORD`). Each project gets its **own databases and its own role**, never the admin login. The API layer is a **Hasura** container per project. References: `/Volumes/Projects/ghostmind/format/db` (dev, `scripts/create-db.sh`) and `/Volumes/Projects/ghostmind/tags/db` (dev + prod, migrations applied in the container); older: `potion/db`.

For read-only exploration of any DB, use the `toolkits:postgres` skill.

## Create a project database

1. **Names:** database `<project>_<app>_<env>` (underscores, e.g. `potion_db_dev`, `potion_db_prod`). Role `<project>_<env>`. A migrated project keeps its existing database names (tags: `tags-db-local`, `tags-db-prod`); don't move data to match the convention.
2. **Create the role and DB** with `scripts/create-db.sh`. Copy `/Volumes/Projects/ghostmind/format/db/scripts/create-db.sh` and change `PROJECT`. It handles three traps:
   - **The schema can't resolve yet.** The db schema needs `DB_USER`/`DB_PASSWORD`/`DB_NAME` from the Vault path this very script creates, so a plain `varlock run` refuses to start. Resolve only the admin login and the Vault token, in the `create_db` routine:
     `varlock run --include-internal --filter PGHOST,PGUSER,PGPASSWORD,APP_ENV,VAULT_ADDR,VAULT_TOKEN -- bash scripts/create-db.sh dev`
   - **No psql on the Mac.** The script runs psql in a throwaway container:
     ```bash
     psql() {
       docker run --rm -i -e PGHOST -e PGUSER -e PGPASSWORD -e PGSSLMODE=require -e PGDATABASE=postgres \
         postgres:17-alpine psql "$@"
     }
     ```
   - **Re-runs are safe.** It creates the role and stores its password once. If the role exists but its Vault path doesn't (a previous run died in between), it sets a new password with `ALTER ROLE` and stores it. It runs `GRANT "<role>" TO CURRENT_USER` before `CREATE DATABASE ... OWNER`, which RDS admins need.

   *Done when `psql` as the new role connects to the new DB and `ghostmind/project/<project>/db/<env>` holds `DB_USER`, `DB_PASSWORD` and `DB_NAME`.*
3. **Point the apps at it.** The app/Hasura schema builds the URL from project credentials, never the admin ones:

   ```bash
   PGHOST=vaultSecret("ghostmind/global/postgres")
   DB_USER=if(forEnv(prod), vaultSecret("ghostmind/project/<project>/db/prod"), vaultSecret("ghostmind/project/<project>/db/dev"))
   # @sensitive
   DB_PASSWORD=if(forEnv(prod), vaultSecret("ghostmind/project/<project>/db/prod"), vaultSecret("ghostmind/project/<project>/db/dev"))
   DB_NAME=if(forEnv(prod), vaultSecret("ghostmind/project/<project>/db/prod"), vaultSecret("ghostmind/project/<project>/db/dev"))
   # @sensitive
   HASURA_GRAPHQL_DATABASE_URL=concat("postgres://", $DB_USER, ":", $DB_PASSWORD, "@", $PGHOST, ":5432/", $DB_NAME, "?sslmode=require")
   ```

## Hasura

- **Hasura is a Deployment and Service like any app** (`/Volumes/Projects/ghostmind/tags/db/k8s/db.yaml`), reached by other apps at `http://<project>-db:<port>` and logging in to Vault with its service account. Its readiness and liveness probes hit `/healthz` on the app's real port; the image's built-in Docker healthcheck hardcodes 8080 and Kubernetes ignores it. To query prod from the Mac, use a read-only `kubectl --context ghostmind -n <project> port-forward`.
- **Pin the engine version that is already running.** For a migrated project, check first (`/v1/version` on the running server, or the `FROM` line of its Dockerfile): tags' prod ran `latest` = v2.49.4, and pinning an older tag would have downgraded the metadata catalog.
- Service `<project>-db`, image from `hasura/graphql-engine:<version>.cli-migrations-v3` (the variant that bundles `hasura-cli`), with the **glibc** varlock build installed (the image is Ubuntu; see `new-app` → docker.md).
- `HASURA_GRAPHQL_ADMIN_SECRET` and `HASURA_GRAPHQL_JWT_SECRET` live in `ghostmind/project/<project>/auth`. The JWT secret is shared with the web app and the MCP.
- The Hasura console gets **its own unique ports** from the registry (`hasura console --console-port <p> --api-port <p>`). The defaults, 9693/9695, belong to potion.
- **Prod applies migrations inside the container at start**, so the host never holds DB credentials. The official `cli-migrations-v3` entrypoint applies metadata *before* migrations, which breaks a commit that adds a table and tracks it. Use that image only for its `hasura-cli`, with this entrypoint order: a temporary server on a spare port → `hasura-cli migrate apply --all-databases` → `metadata apply` → `metadata ic list` → stop it → `graphql-engine serve`. Until the migrations succeed the real server never starts, the pod never becomes ready and the rollout times out. (The reference loops these steps so varlock stays PID 1, a habit from the Compose flow; on the cluster a failed start can simply exit and let Kubernetes restart the pod.) Copy `/Volumes/Projects/ghostmind/tags/db/docker/entrypoint.sh` and `Dockerfile` (`COPY app/state /hasura-project`). The console is enabled with `HASURA_GRAPHQL_ENABLE_CONSOLE`, not a `serve` flag.
- Dev migrations and metadata: `scripts/migrate.sh` runs `hasura migrate apply --database-name default && hasura metadata apply` against `HASURA_GRAPHQL_ENDPOINT`, as the routine `migrate` (`varlock run -- bash scripts/migrate.sh`). Create migrations with the Hasura console in dev and commit `app/state/`. Before merging, run the prod entrypoint's order against the dev DB.
- Apps that depend on new columns wait for the `db` job: `needs: db` in the project's `deploy.yaml` (see `deploy`).

## Dropping

Dropping a database is irreversible and shared RDS hosts other products. Always ask the user, name the exact database, and never touch a database outside the current project.
