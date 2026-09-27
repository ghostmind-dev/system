---
name: database
description: >-
  Postgres for Ghostmind projects: create a database and role on the shared AWS RDS, run Hasura on it,
  and manage migrations. Use when an app needs a database, a new DB/role/connection string, Hasura
  metadata or migrations, or when choosing how an app talks to Postgres.
---

# Database

Every product's data lives on **one shared AWS RDS Postgres** instance. The admin login is `ghostmind/global/postgres` (`PGHOST`, `PGUSER`, `PGPASSWORD`). Each project gets its **own databases and its own role**, never the admin login. The API layer is a **Hasura** container per project. Reference: `/Volumes/Projects/ghostmind/potion/db` (Hasura image + `app/state/{migrations,metadata}`).

For read-only exploration of any DB, use the `toolkits:postgres` skill.

## Create a project database

1. **Names:** database `<project>_<app>_<env>` (underscores, e.g. `potion_db_dev`, `potion_db_prod`). Role `<project>_<env>`.
2. **Create the role and DB** with `scripts/create-db.sh`, run as `varlock run -- bash scripts/create-db.sh <env>`. The schema points `PGHOST`/`PGUSER`/`PGPASSWORD` at `ghostmind/global/postgres`.

   ```bash
   set -euo pipefail
   PROJECT=<project>; ENV=$1; DB="${PROJECT}_db_${ENV}"; ROLE="${PROJECT}_${ENV}"
   export PGSSLMODE=require PGDATABASE=postgres
   if ! psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$ROLE'" | grep -q 1; then
     PASS=$(openssl rand -hex 24)
     psql -v ON_ERROR_STOP=1 -c "CREATE ROLE \"$ROLE\" LOGIN PASSWORD '$PASS'"
     # a role is created once, so its password is stored once
     vault kv put ghostmind/project/$PROJECT/db/$ENV DB_USER="$ROLE" DB_PASSWORD="$PASS" DB_NAME="$DB"
   fi
   psql -tAc "SELECT 1 FROM pg_database WHERE datname='$DB'" | grep -q 1 \
     || psql -v ON_ERROR_STOP=1 -c "CREATE DATABASE \"$DB\" OWNER \"$ROLE\""
   ```

   RDS admin users cannot always `CREATE DATABASE ... OWNER` a role they are not a member of. If that fails, run `GRANT "<role>" TO <admin>` first. *Done when `psql` as the new role connects to the new DB and the credentials are in Vault.*
3. **Point the apps at it.** The app/Hasura schema builds the URL from project credentials, never the admin ones:

   ```bash
   PGHOST=vaultSecret("ghostmind/global/postgres")
   # in .env.dev / .env.prod:
   DB_USER=vaultSecret("ghostmind/project/<project>/db/prod")
   DB_PASSWORD=vaultSecret("ghostmind/project/<project>/db/prod")
   DB_NAME=vaultSecret("ghostmind/project/<project>/db/prod")
   # @sensitive
   HASURA_GRAPHQL_DATABASE_URL=concat("postgres://", $DB_USER, ":", $DB_PASSWORD, "@", $PGHOST, ":5432/", $DB_NAME, "?sslmode=require")
   ```

## Hasura

- Container `<project>-db` from `hasura/graphql-engine:<pinned version>`, with varlock copied in like any other app. Override the healthcheck to the real port, as in potion's compose, because the image's built-in check hardcodes 8080.
- `HASURA_GRAPHQL_ADMIN_SECRET` and `HASURA_GRAPHQL_JWT_SECRET` live in `ghostmind/project/<project>/auth`. The JWT secret is shared with the web app and the MCP.
- Migrations and metadata: `scripts/migrate.sh` runs `hasura migrate apply --database-name default && hasura metadata apply` against `HASURA_GRAPHQL_ENDPOINT`, as the routine `migrate` (`varlock run -- bash scripts/migrate.sh`). Create migrations with the Hasura console in dev, commit `app/state/`, and prod applies them in the `db` workflow.
- Apps that depend on new columns wait for the `db` workflow (see `deploy`).

## Dropping

Dropping a database is irreversible and shared RDS hosts other products. Always ask the user, name the exact database, and never touch a database outside the current project.
