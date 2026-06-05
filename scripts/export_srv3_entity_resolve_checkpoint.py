#!/usr/bin/env python3
import os
import hashlib
from pathlib import Path
import psycopg2

OUT_DIR = Path("backups/search_router_local")
OUT_FILE = OUT_DIR / "srv3_entity_resolve_v3_local_stable.sql"

DB = {
    "host": os.environ.get("LOCAL_DB_HOST", "localhost"),
    "port": int(os.environ.get("LOCAL_DB_PORT", "5432")),
    "dbname": os.environ.get("LOCAL_DB_NAME", "postgres"),
    "user": os.environ.get("LOCAL_DB_USER", "postgres"),
    "password": os.environ.get("LOCAL_DB_PASSWORD", ""),
}

CHECKPOINT = "SRV3_entity_resolve_v3_local_stable"

CORE_CANONICALS = [
    "中共",
    "习近平",
    "特朗普",
    "美联储",
    "WEF",
    "比尔盖茨",
]

def lit(cur, value):
    return cur.mogrify("%s", (value,)).decode("utf-8")

def write_rows_as_conditional_alias_inserts(cur, f):
    cur.execute("""
        SELECT canonical, alias, alias_type
        FROM ccc.person_aliases
        WHERE canonical = ANY(%s)
        ORDER BY canonical, alias
    """, (CORE_CANONICALS,))
    rows = cur.fetchall()

    f.write("-- ============================================================\n")
    f.write("-- Core person_aliases used by entity_resolve_v3_local\n")
    f.write("-- ============================================================\n\n")

    for canonical, alias, alias_type in rows:
        f.write(
            "INSERT INTO ccc.person_aliases (canonical, alias, alias_type)\n"
            f"SELECT {lit(cur, canonical)}, {lit(cur, alias)}, {lit(cur, alias_type)}\n"
            "WHERE NOT EXISTS (\n"
            "  SELECT 1 FROM ccc.person_aliases\n"
            f"  WHERE canonical = {lit(cur, canonical)} AND alias = {lit(cur, alias)}\n"
            ");\n\n"
        )

def write_clean_entities(cur, f):
    cur.execute("""
        SELECT id, canonical_name, entity_type, source, mention_count, confidence, created_at
        FROM ccc.clean_entities
        WHERE canonical_name = ANY(%s)
        ORDER BY canonical_name
    """, (CORE_CANONICALS,))
    rows = cur.fetchall()

    f.write("-- ============================================================\n")
    f.write("-- Core clean_entities used by entity_resolve_v3_local\n")
    f.write("-- ============================================================\n\n")

    for row in rows:
        entity_id, canonical_name, entity_type, source, mention_count, confidence, created_at = row
        f.write(
            "INSERT INTO ccc.clean_entities (id, canonical_name, entity_type, source, mention_count, confidence, created_at)\n"
            f"SELECT {entity_id}, {lit(cur, canonical_name)}, {lit(cur, entity_type)}, "
            f"{lit(cur, source)}, {mention_count}, {confidence}, {lit(cur, created_at)}::timestamptz\n"
            "WHERE NOT EXISTS (\n"
            "  SELECT 1 FROM ccc.clean_entities\n"
            f"  WHERE canonical_name = {lit(cur, canonical_name)}\n"
            ");\n\n"
        )

def write_expectations(cur, f):
    cur.execute("""
        SELECT
          q,
          expected_canonical_name,
          expected_entity_id,
          expected_match_type,
          min_confidence,
          expected_entity_type,
          note
        FROM ccc.entity_resolve_v3_local_expectations
        ORDER BY q
    """)
    rows = cur.fetchall()

    f.write("-- ============================================================\n")
    f.write("-- Regression expectations\n")
    f.write("-- ============================================================\n\n")

    f.write("""
CREATE TABLE IF NOT EXISTS ccc.entity_resolve_v3_local_expectations (
  q text PRIMARY KEY,
  expected_canonical_name text NOT NULL,
  expected_entity_id bigint NOT NULL,
  expected_match_type text NOT NULL,
  min_confidence numeric NOT NULL,
  expected_entity_type text NOT NULL,
  note text,
  updated_at timestamp with time zone DEFAULT now()
);

""")

    for row in rows:
        q, expected_canonical_name, expected_entity_id, expected_match_type, min_confidence, expected_entity_type, note = row
        f.write(
            "INSERT INTO ccc.entity_resolve_v3_local_expectations "
            "(q, expected_canonical_name, expected_entity_id, expected_match_type, min_confidence, expected_entity_type, note)\n"
            f"VALUES ({lit(cur, q)}, {lit(cur, expected_canonical_name)}, {expected_entity_id}, "
            f"{lit(cur, expected_match_type)}, {min_confidence}, {lit(cur, expected_entity_type)}, {lit(cur, note)})\n"
            "ON CONFLICT (q) DO UPDATE SET\n"
            "  expected_canonical_name = EXCLUDED.expected_canonical_name,\n"
            "  expected_entity_id = EXCLUDED.expected_entity_id,\n"
            "  expected_match_type = EXCLUDED.expected_match_type,\n"
            "  min_confidence = EXCLUDED.min_confidence,\n"
            "  expected_entity_type = EXCLUDED.expected_entity_type,\n"
            "  note = EXCLUDED.note,\n"
            "  updated_at = now();\n\n"
        )

def write_wef_gates_edge(cur, f):
    cur.execute("""
        SELECT
          s.canonical_name AS source,
          t.canonical_name AS target,
          e.relation_type,
          e.weight,
          e.document_count,
          e.relation_label,
          e.relation_direction,
          e.causal_weight,
          e.pressure,
          e.direction
        FROM ccc.clean_graph_edges e
        JOIN ccc.clean_entities s ON s.id = e.source_entity_id
        JOIN ccc.clean_entities t ON t.id = e.target_entity_id
        WHERE s.canonical_name = 'WEF'
          AND t.canonical_name = '比尔盖茨'
          AND e.relation_type = 'elite_network_association'
        LIMIT 1
    """)
    row = cur.fetchone()

    f.write("-- ============================================================\n")
    f.write("-- WEF ↔ Bill Gates graph edge\n")
    f.write("-- ============================================================\n\n")

    if not row:
        f.write("-- WARNING: WEF ↔ 比尔盖茨 edge not found at export time.\n\n")
        return

    source, target, relation_type, weight, document_count, relation_label, relation_direction, causal_weight, pressure, direction = row

    f.write(f"""
WITH ids AS (
  SELECT
    (SELECT id FROM ccc.clean_entities WHERE canonical_name = {lit(cur, source)} LIMIT 1) AS source_id,
    (SELECT id FROM ccc.clean_entities WHERE canonical_name = {lit(cur, target)} LIMIT 1) AS target_id
)
INSERT INTO ccc.clean_graph_edges (
  source_entity_id,
  target_entity_id,
  relation_type,
  weight,
  document_count,
  created_at,
  relation_label,
  relation_direction,
  causal_weight,
  pressure,
  direction,
  updated_at
)
SELECT
  source_id,
  target_id,
  {lit(cur, relation_type)},
  {weight},
  {document_count},
  now(),
  {lit(cur, relation_label)},
  {lit(cur, relation_direction)},
  {causal_weight},
  {lit(cur, pressure)},
  {lit(cur, direction)},
  now()
FROM ids
WHERE source_id IS NOT NULL
  AND target_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1
    FROM ccc.clean_graph_edges e
    WHERE e.relation_type = {lit(cur, relation_type)}
      AND (
        (e.source_entity_id = ids.source_id AND e.target_entity_id = ids.target_id)
        OR
        (e.source_entity_id = ids.target_id AND e.target_entity_id = ids.source_id)
      )
  );

""")

def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    conn = psycopg2.connect(**DB)
    conn.autocommit = True
    cur = conn.cursor()

    with OUT_FILE.open("w", encoding="utf-8") as f:
        f.write("-- SRV3 Entity Resolve v3 Local Stable Checkpoint\n")
        f.write(f"-- checkpoint: {CHECKPOINT}\n")
        f.write("-- purpose: backup local multilingual entity resolver, aliases, regression, and WEF-Bill Gates graph edge\n\n")
        f.write("CREATE SCHEMA IF NOT EXISTS ccc;\n\n")

        f.write("-- ============================================================\n")
        f.write("-- Function: ccc.entity_resolve_v3_local(text)\n")
        f.write("-- ============================================================\n\n")
        cur.execute("SELECT pg_get_functiondef('ccc.entity_resolve_v3_local(text)'::regprocedure)")
        f.write(cur.fetchone()[0])
        f.write("\n\n")

        f.write("-- ============================================================\n")
        f.write("-- Regression view: ccc.entity_resolve_v3_local_regression\n")
        f.write("-- ============================================================\n\n")
        cur.execute("SELECT pg_get_viewdef('ccc.entity_resolve_v3_local_regression'::regclass, true)")
        viewdef = cur.fetchone()[0]
        f.write("CREATE OR REPLACE VIEW ccc.entity_resolve_v3_local_regression AS\n")
        f.write(viewdef.rstrip())
        f.write(";\n\n")

        write_clean_entities(cur, f)
        write_rows_as_conditional_alias_inserts(cur, f)
        write_expectations(cur, f)
        write_wef_gates_edge(cur, f)

        f.write("-- ============================================================\n")
        f.write("-- Checkpoint rows\n")
        f.write("-- ============================================================\n\n")
        f.write(f"""
INSERT INTO ccc.rsal_checkpoints (
  checkpoint_label,
  module,
  note
)
VALUES (
  {lit(cur, CHECKPOINT)},
  'Search Router v3 Local',
  'Stable checkpoint: multilingual entity resolution. RSAL rule: China/PRC/Chinese government/Beijing/State Council route to canonical 中共. Xi/Trump/Fed/WEF aliases verified. Bill Gates remains separate PERSON and links to WEF through graph edge. Regression PASS=53.'
)
ON CONFLICT (checkpoint_label) DO UPDATE SET
  module = EXCLUDED.module,
  note = EXCLUDED.note;

INSERT INTO ccc.function_snapshots (
  checkpoint_label,
  function_signature,
  function_definition,
  definition_hash
)
SELECT
  {lit(cur, CHECKPOINT)},
  'ccc.entity_resolve_v3_local(text)',
  pg_get_functiondef('ccc.entity_resolve_v3_local(text)'::regprocedure),
  md5(pg_get_functiondef('ccc.entity_resolve_v3_local(text)'::regprocedure))
ON CONFLICT (checkpoint_label, function_signature) DO UPDATE SET
  function_definition = EXCLUDED.function_definition,
  definition_hash = EXCLUDED.definition_hash,
  created_at = now();

COMMENT ON FUNCTION ccc.entity_resolve_v3_local(text)
IS 'Search Router v3 Local stable entity resolver. Multilingual aliases supported. RSAL rule: China/PRC/Chinese government/Beijing/State Council route to canonical 中共. Xi/Trump/Fed/WEF aliases verified. Bill Gates remains separate PERSON and links to WEF through graph edge. Exact/contained hits suppress fuzzy noise. Regression PASS=53.';

""")

        f.write("-- Verification:\n")
        f.write("-- SELECT regression_status, count(*) FROM ccc.entity_resolve_v3_local_regression GROUP BY regression_status;\n")

    digest = hashlib.md5(OUT_FILE.read_bytes()).hexdigest()
    print(f"✅ Exported: {OUT_FILE}")
    print(f"✅ MD5: {digest}")

if __name__ == "__main__":
    main()
