---
name: database
description: >-
  Postgres for Ghostmind projects: create a database and role on the shared AWS RDS, run Hasura on it,
  and manage migrations. Use when an app needs a database, a new DB/role/connection string, Hasura
  metadata or migrations, or when choosing how an app talks to Postgres.
---

# Database

Every product's data lives on **one shared AWS RDS Postgres** instance. The admin login is `ghostmind/global/postgres` (`PGHOST`, `PGUSER`, `PGPASSWORD`). Each project gets its **own databases and its own role**, never the admin login. The API layer is a **Hasura** container per project. Reference: `/Volumes/Projects/playground/format/db` (Hasura + varlock, `app/state/{migrations,metadata}`, `scripts/create-db.sh`); older: `potion/db`.

For read-only exploration of any DB, use the `toolkits:postgres` skill.

## Create a project database

1. **Names:** database `<project>_<app>_<env>` (underscores, e.g. `potion_db_dev`, `potion_db_prod`). Role `<project>_<env>`.
2. **Create the role and DB** with `scripts/create-db.sh`. Copy `/Volumes/Projects/playground/format/db/scripts/create-db.sh` and change `PROJECT`. It handles three traps:
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
   # in .env.dev / .env.prod:
   DB_USER=vaultSecret("ghostmind/project/<project>/db/prod")
   DB_PASSWORD=vaultSecret("ghostmind/project/<project>/db/prod")
   DB_NAME=vaultSecret("ghostmind/project/<project>/db/prod")
   # @sensitive
   HASURA_GRAPHQL_DATABASE_URL=concat("postgres://", $DB_USER, ":", $DB_PASSWORD, "@", $PGHOST, ":5432/", $DB_NAME, "?sslmode=require")
   ```

## Hasura

- Container `<project>-db` from `hasura/graphql-engine:<pinned version>`, with the **glibc** varlock build installed (the image is Ubuntu; see `new-app` → docker.md). Override the healthcheck to the real port, as in potion's compose, because the image's built-in check hardcodes 8080.
- `HASURA_GRAPHQL_ADMIN_SECRET` and `HASURA_GRAPHQL_JWT_SECRET` live in `ghostmind/project/<project>/auth`. The JWT secret is shared with the web app and the MCP.
- The Hasura console gets **its own unique ports** from the registry (`hasura console --console-port <p> --api-port <p>`). The defaults, 9693/9695, belong to potion.
- Migrations and metadata: `scripts/migrate.sh` runs `hasura migrate apply --database-name default && hasura metadata apply` against `HASURA_GRAPHQL_ENDPOINT`, as the routine `migrate` (`varlock run -- bash scripts/migrate.sh`). Create migrations with the Hasura console in dev, commit `app/state/`, and prod applies them in the `db` workflow.
- Apps that depend on new columns wait for the `db` workflow (see `deploy`).

## Dropping

Dropping a database is irreversible and shared RDS hosts other products. Always ask the user, name the exact database, and never touch a database outside the current project.
