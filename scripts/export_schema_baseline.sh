#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="${1:-schema}"

if [[ -n "${DATABASE_URL:-}" ]]; then
  CONN_ARGS=("$DATABASE_URL")
elif [[ -n "${DB_HOST:-}" && -n "${DB_PORT:-}" && -n "${DB_NAME:-}" && -n "${DB_USER:-}" ]]; then
  CONN_ARGS=(-h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME")
  export PGPASSWORD="${DB_PASSWORD:-}"
else
  echo "Set DATABASE_URL or DB_HOST, DB_PORT, DB_NAME, DB_USER, and DB_PASSWORD." >&2
  exit 2
fi

mkdir -p "$OUT_DIR"

pg_dump \
  --schema=public \
  --schema-only \
  --no-owner \
  --no-privileges \
  --file "$OUT_DIR/current_schema.sql" \
  "${CONN_ARGS[@]}"

psql "${CONN_ARGS[@]}" -v ON_ERROR_STOP=1 -At -o "$OUT_DIR/current_views.sql" <<'SQL'
SELECT format(
  E'-- View: %I.%I\nCREATE OR REPLACE VIEW %I.%I AS\n%s;\n',
  schemaname,
  viewname,
  schemaname,
  viewname,
  pg_get_viewdef(format('%I.%I', schemaname, viewname)::regclass, true)
)
FROM pg_views
WHERE schemaname = 'public'
ORDER BY viewname;
SQL

psql "${CONN_ARGS[@]}" -v ON_ERROR_STOP=1 -At -o "$OUT_DIR/current_indexes.sql" <<'SQL'
SELECT indexdef || ';'
FROM pg_indexes
WHERE schemaname = 'public'
ORDER BY tablename, indexname;
SQL

psql "${CONN_ARGS[@]}" -v ON_ERROR_STOP=1 -At -o "$OUT_DIR/current_constraints.sql" <<'SQL'
SELECT format(
  'ALTER TABLE %I.%I ADD CONSTRAINT %I %s;',
  n.nspname,
  c.relname,
  con.conname,
  pg_get_constraintdef(con.oid, true)
)
FROM pg_constraint con
JOIN pg_class c ON c.oid = con.conrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
ORDER BY c.relname, con.conname;
SQL

echo "Wrote schema baseline files to $OUT_DIR"

