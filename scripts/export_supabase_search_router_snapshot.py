#!/usr/bin/env python3
import os
from pathlib import Path
import hashlib
import psycopg2

OUT_DIR = Path("backups/search_router_cloud")
OUT_FILE = OUT_DIR / "supabase_search_router_snapshot.sql"

DB = {
    "host": "aws-1-ap-southeast-2.pooler.supabase.com",
    "port": 5432,
    "dbname": "postgres",
    "user": "postgres.mgigbiblwqywcegkhjpu",
    "password": os.environ.get("SUPABASE_DB_PASSWORD", ""),
    "sslmode": "require",
    "connect_timeout": 30,
}

FUNCTIONS = [
    "ccc.entity_resolve(text)",
    "ccc.entity_graph_expand(bigint,integer,double precision)",
    "ccc.entity_intelligence(text)",
    "ccc.search_router(text)",
    "ccc.search_router_v2(text)",
    "ccc.search_router_v3(text)",
]

OPTIONAL_FUNCTION_NAMES = [
    "effective_confidence",
    "signal_boost",
    "vector_search",
    "search_vector",
    "search_keyword",
    "search_ai",
]

def main():
    if not DB["password"]:
        raise SystemExit("Missing SUPABASE_DB_PASSWORD env var")

    OUT_DIR.mkdir(parents=True, exist_ok=True)

    conn = psycopg2.connect(**DB)
    conn.autocommit = True
    cur = conn.cursor()

    with OUT_FILE.open("w", encoding="utf-8") as f:
        f.write("-- Supabase Search Router Cloud Snapshot\n")
        f.write("-- Source: Supabase ccc schema\n")
        f.write("-- Purpose: backup production search RPC definitions\n\n")
        f.write("CREATE SCHEMA IF NOT EXISTS ccc;\n\n")

        f.write("-- ============================================================\n")
        f.write("-- Explicit RPC functions\n")
        f.write("-- ============================================================\n\n")

        for sig in FUNCTIONS:
            cur.execute("SELECT to_regprocedure(%s)", (sig,))
            exists = cur.fetchone()[0]
            if not exists:
                f.write(f"-- MISSING: {sig}\n\n")
                continue

            cur.execute("SELECT pg_get_functiondef(%s::regprocedure)", (sig,))
            definition = cur.fetchone()[0]
            f.write(f"-- Function: {sig}\n")
            f.write(definition)
            if not definition.rstrip().endswith(";"):
                f.write(";")
            f.write("\n\n")

        f.write("-- ============================================================\n")
        f.write("-- Optional dependency functions by name\n")
        f.write("-- ============================================================\n\n")

        cur.execute("""
            SELECT p.oid::regprocedure::text, pg_get_functiondef(p.oid)
            FROM pg_proc p
            JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'ccc'
              AND p.proname = ANY(%s)
            ORDER BY p.proname, p.oid::regprocedure::text
        """, (OPTIONAL_FUNCTION_NAMES,))

        for signature, definition in cur.fetchall():
            f.write(f"-- Function: {signature}\n")
            f.write(definition)
            if not definition.rstrip().endswith(";"):
                f.write(";")
            f.write("\n\n")

        f.write("-- ============================================================\n")
        f.write("-- Related views\n")
        f.write("-- ============================================================\n\n")

        cur.execute("""
            SELECT viewname, definition
            FROM pg_views
            WHERE schemaname = 'ccc'
              AND viewname IN ('aliases_safe', 'doc_entity_mentions')
            ORDER BY viewname
        """)
        for viewname, definition in cur.fetchall():
            f.write(f"CREATE OR REPLACE VIEW ccc.{viewname} AS\n")
            f.write(definition.rstrip())
            f.write(";\n\n")

    digest = hashlib.md5(OUT_FILE.read_bytes()).hexdigest()
    print(f"✅ Exported: {OUT_FILE}")
    print(f"✅ MD5: {digest}")

if __name__ == "__main__":
    main()
