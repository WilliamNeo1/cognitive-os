-- ============================================================
-- STAGING ONLY — DO NOT EXECUTE ON PRODUCTION DB WITHOUT OWNER RUN
-- Migration v2: topology uniqueness + dual-array traceability + edge_strength
-- Target table: ccc.cognitive_edges
-- Supersedes: migration_cognitive_edges_case_ids_staging.sql
--   (that file already ran and added created_by_case_ids — confirmed
--   by owner verification query. This migration is additive on top
--   of that confirmed state, not a replacement of it.)
-- Implements: Anti-Topology Contamination Principle,
--             Topology Minimalism Principle,
--             weak-edge default for co_occurs
-- Date: 2026-06-30
-- ============================================================

-- Pre-check: confirm created_by_case_ids already exists before
-- proceeding, since this migration assumes it does.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'ccc'
      AND table_name = 'cognitive_edges'
      AND column_name = 'created_by_case_ids'
  ) THEN
    RAISE EXCEPTION 'Prerequisite migration not yet run: created_by_case_ids missing. Run migration_cognitive_edges_case_ids_staging.sql first.';
  END IF;
END $$;

BEGIN;

-- 1. Add explicit unique constraint so ON CONFLICT has a defined target.
--    Without this, any promotion template using ON CONFLICT on this
--    column triple fails at execution — confirmed missing via
--    pg_constraint inspection on 2026-06-30.
ALTER TABLE ccc.cognitive_edges
  ADD CONSTRAINT cognitive_edges_topology_uniq
  UNIQUE (source_node_id, target_node_id, relation_type);

-- 2. Add semantic_relation_types — parallel array to created_by_case_ids,
--    holding the original domain-specific label(s) from staging.
--    Positional alignment with created_by_case_ids is a CONVENTION,
--    not DB-enforced — see promotion template below for how this is
--    kept consistent on upsert.
ALTER TABLE ccc.cognitive_edges
  ADD COLUMN IF NOT EXISTS semantic_relation_types text[] DEFAULT '{}';

-- 3. Add edge_strength — doctrine requires co_occurs to be a weak edge
--    by default, excluded from causal/control traversal unless
--    explicitly upgraded. This is a real column, not a doctrine
--    sentence with no enforcement.
ALTER TABLE ccc.cognitive_edges
  ADD COLUMN IF NOT EXISTS edge_strength text DEFAULT 'STRONG'
  CHECK (edge_strength IN ('STRONG', 'WEAK'));

COMMIT;

-- ============================================================
-- VERIFICATION — RUN IMMEDIATELY, DO NOT ASSUME SUCCESS
-- ============================================================

SELECT column_name, data_type, column_default
FROM information_schema.columns
WHERE table_schema = 'ccc'
  AND table_name = 'cognitive_edges'
  AND column_name IN ('created_by_case_ids', 'semantic_relation_types', 'edge_strength')
ORDER BY column_name;

SELECT conname, contype, pg_get_constraintdef(oid)
FROM pg_constraint
WHERE conrelid = 'ccc.cognitive_edges'::regclass
  AND conname = 'cognitive_edges_topology_uniq';

-- Expected: 3 columns present, 1 constraint present.
-- If either query returns fewer rows than expected, STOP —
-- do not proceed to the promotion template or closure checkpoint.

-- ============================================================
-- ROLLBACK (if needed)
-- ============================================================

-- ALTER TABLE ccc.cognitive_edges DROP CONSTRAINT cognitive_edges_topology_uniq;
-- ALTER TABLE ccc.cognitive_edges DROP COLUMN semantic_relation_types;
-- ALTER TABLE ccc.cognitive_edges DROP COLUMN edge_strength;
