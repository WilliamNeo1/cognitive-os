# ccc_v6_2_edge_reconstruction_spec.md
## Candidate Edge Reconstruction Specification v1.0

Status: candidate / draft
Based on: checkpoint-146 (V6.2 architecture closure) · checkpoint-147 (e-data latest)
Scope: B/C/D three-batch reconstruction pipeline
write_db: NO until owner confirmation
Formal checkpoint ID: TBD pending inspection

---

## 0. Purpose

This specification defines the unified standard for reconstructing
candidate edges from B-data, C-data, and D-data batches into
`three_system_candidate_edges_staging`, and governing their
promotion path toward `cognitive_edges`.

It replaces ad-hoc per-batch rules with a single reusable template.

Current state in staging:
```
edge_status = HELD:                24 rows
edge_status = PROMOTION_CANDIDATE: 16 rows
Total:                             40 rows
```

All future B/C/D reconstruction follows this spec.
F-data and beyond will also follow this spec from the start.

---

## 1. Governing Principles

```
Candidate edge is not clean_graph_edge.
Hypothesis is not edge.
Correlation is not causation.
Narrative is not graph relation.
Source says X ≠ X is true.
REPORTED_ prefix = reported only, not confirmed.
OFFICIAL_ prefix = official record exists, not conviction.
```

**Anti-Topology Contamination Principle (added 2026-06-30):**
```
Topology exists only for graph reasoning, not for storing knowledge.
拓扑只为推理存在，而不是为了存储知识。

Topology Minimalism: only information that changes graph traversal,
connectivity, or state propagation may become a topology edge (the 6
relation_type primitives on cognitive_edges). Everything else —
entity attributes, risk evidence, role labels, long-tail descriptions
— belongs in claims / evidence / staging notes, not in cognitive_edges.

co_occurs is a weak edge by default (edge_strength = 'WEAK'). The
graph solver must not perform causal or control-chain inference over
co_occurs edges; they provide contextual weight only.

triggers means graph-state-propagation trigger, not timeline
causality. "X happened before Y" is not sufficient grounds for a
triggers edge — the edge must represent an actual state-propagation
relationship the solver can act on.
```

**Semantic Evolution Principle (added 2026-06-30):**
```
Business semantics are expected to evolve; graph topology should
evolve only when graph reasoning requirements evolve.
业务语义允许持续演化；图拓扑只有在推理需求发生变化时才应演化。

The 39-label vocabulary in Section 4 is a Current Confirmed Vocabulary,
not a Canonical Vocabulary — versioned and extensible, not immutable.
New labels from F-data and beyond extend the mapping table in Section
11.1 without requiring changes to the 6 topology primitives.
```

All edges must pass:
1. Four-Level Calibration (Fact / Inference / Not Established / Operational Impact)
2. Statistical Calibration Gate (SCG) — correlation ≠ causation check
3. Review Gate (owner review before promotion)
4. Exposure Gate (sensitivity check before any W output)

---

## 2. Staging Table: Actual Schema

Table: `ccc.three_system_candidate_edges_staging`

```
id                  bigint          — auto-assigned
case_id             text            — see naming convention below
source_subject      text            — source entity name/slug
target_subject      text            — target entity name/slug
relation_type       text            — from approved vocabulary below
edge_status         text            — HELD / PROMOTION_CANDIDATE / PROMOTED / REJECTED
source_status       text            — REPORTED / OFFICIAL / INFERRED / HELD
sensitivity_level   text            — LOW / MEDIUM / HIGH / CRITICAL
evidence_basis      text            — human-readable evidence summary
source_chain        text            — source document reference
source_checkpoints  ARRAY           — checkpoint IDs supporting this edge
legacy_event_id     integer         — if derived from legacy event
legacy_event_policy text            — archive policy for legacy anchor
notes               text            — calibration notes, SCG result, held reason
review_gate         text            — PENDING / PASS / FAIL / HOLD
promotion_path      text            — target table and conditions
review_note         text            — owner review decision notes
reviewed_by         text            — owner identifier
reviewed_at         timestamp
created_at          timestamp
updated_at          timestamp
```

Promotion target: `ccc.cognitive_edges`

```
id              bigint     — auto-assigned
source_node_id  bigint     — must resolve from clean_entities
target_node_id  bigint     — must resolve from clean_entities
relation_type   text
weight          double     — 0.0–1.0
created_at      timestamp
```

Note: `cognitive_edges` has no case_id, sensitivity, or evidence fields.
All traceability lives in `three_system_candidate_edges_staging`.
Promotion SQL must resolve entity IDs from `clean_entities` before insert.

### 2.1 Traceability debt — explicit decision required before Phase 3 high-volume ingest

The current asymmetric traceability (staging has case_id, cognitive_edges
does not) is acceptable at 40 rows. It is not acceptable at F-data volume
without an explicit owner decision, because the rollback cost is not
theoretical: if an upstream source is later confirmed to be a deliberately
seeded false narrative ("poisoned source"), reversing its effect requires
walking from `cognitive_edges` rows back to staging rows by
`(source_node_id, target_node_id, relation_type)` — and that match is
ambiguous whenever two different batches independently support the same
edge. A and C both asserting the same relation means a blind delete by
source-batch cannot distinguish which contribution to revoke.

Two paths, both deferred to Phase 3 engineering, not Phase 2 closure:

```
Path A — Minimal schema addition (recommended before F-data volume hits):
  ALTER TABLE ccc.cognitive_edges
    ADD COLUMN created_by_case_ids text[] DEFAULT '{}';
  Promotion SQL appends the promoting case_id to this array instead of
  overwriting. Multiple case_ids supporting the same edge accumulate
  here. A poisoned-source rollback becomes:
    UPDATE ... SET created_by_case_ids = array_remove(created_by_case_ids, '<bad_case_id>')
    WHERE '<bad_case_id>' = ANY(created_by_case_ids);
  followed by a weight-recalculation pass if created_by_case_ids becomes
  empty (full delete) or non-empty (re-weight from remaining sources).

Path B — Stay on reverse staging lookup (status quo):
  Acceptable only if batch volume stays low enough that manual
  cross-referencing in staging remains tractable, and only if owner
  explicitly accepts that multi-batch-supported edges will require
  manual disambiguation at rollback time.
```

This document does not select between Path A and Path B. That choice
belongs to the owner and is recorded as an open Phase 3 decision in
Section 15 below, not assumed silently.

---

## 3. case_id Naming Convention

Format:
```
{batch}-{sequence}-{relation_category}
```

Examples:
```
B-CE-01-OFFSHORE        — B-data, edge 01, offshore relation
C-CE-07-ENFORCEMENT     — C-data, edge 07, enforcement context
D-CE-03-OWNERSHIP       — D-data, edge 03, ownership relation
```

Rules:
- Batch prefix: B / C / D / E / F (matches data batch)
- CE = Candidate Edge
- Sequence: two-digit zero-padded
- Category: SHORT descriptor from relation_type family
  (OFFSHORE / OWNERSHIP / ENFORCEMENT / FAMILY / ROLE / FINANCIAL / SOURCE)
- No spaces, no special characters

---

## 4. Relation Type Vocabulary (current confirmed set)

### OFFICIAL_ prefix (official record exists)
```
OFFICIAL_ENFORCEMENT_ACTION_CONTEXT
OFFICIAL_INDICTMENT_CONTEXT
OFFICIAL_JUDICIAL_ACTION_CONTEXT
```

### REPORTED_ prefix (reported, not confirmed)
```
— Ownership / control
REPORTED_BENEFICIAL_OWNER_OR_SHAREHOLDER_LINK
REPORTED_BUSINESS_OWNERSHIP_CONTEXT
REPORTED_CONTROLLING_SHAREHOLDER_CONTEXT
REPORTED_SHAREHOLDING_CONTEXT
REPORTED_FOUNDER_OR_FAMILY_FUND_LINK
REPORTED_CENTRAL_FINANCIAL_ENTERPRISE_LISTING_CONTEXT

— Roles
REPORTED_CFO_ROLE
REPORTED_CHAIRPERSON_ROLE
REPORTED_PRESIDENT_ROLE
REPORTED_VP_ROLE

— Family / association
REPORTED_FAMILY_ASSOCIATION
REPORTED_FAMILY_FINANCIAL_ASSOCIATION
REPORTED_FAMILY_HOLDING_CONTEXT
REPORTED_SPOUSAL_OR_FAMILY_ASSOCIATION
REPORTED_ASSOCIATE_NETWORK

— Offshore / financial structure
REPORTED_OFFSHORE_INTERMEDIARY_LINK
REPORTED_OFFSHORE_JURISDICTION_ASSOCIATION
REPORTED_OFFSHORE_JURISDICTION_PATH
REPORTED_OFFSHORE_REGISTRATION
REPORTED_OFFSHORE_TAX_STRUCTURE
REPORTED_CROSS_BORDER_WEALTH_MANAGEMENT_CONTEXT
REPORTED_SERVICE_PROVIDER_FOR_OFFSHORE_ENTITIES
REPORTED_FINANCING_CHANNEL_CONTEXT

— Risk / crime context
REPORTED_ASSET_CONCEALMENT_CONTEXT
REPORTED_BRIBERY_OR_KICKBACK_CONTEXT
REPORTED_COMPLIANCE_FAILURE_CONTEXT
REPORTED_COMPLIANCE_RISK_CONTEXT
REPORTED_FINANCIAL_CRIME_CONTEXT
REPORTED_LONG_TAIL_ENFORCEMENT_CONTEXT
REPORTED_PROPERTY_LAUNDERING_RISK_CONTEXT
REPORTED_SAR_OR_FINANCIAL_INTELLIGENCE_CONTEXT
REPORTED_TAX_COMPLIANCE_CONTEXT
REPORTED_HISTORICAL_REORGANIZATION_CONTEXT

— Events / context
REPORTED_ATTENDEE_CONTEXT
REPORTED_REGULATORY_HIERARCHY_CONTEXT

— Source
SOURCE_DATASET_OR_LEAK_CONTEXT
```

Rules:
- REPORTED_ = source says this; not independently verified
- OFFICIAL_ = official document or legal record exists
- Do not promote REPORTED_ to OFFICIAL_ without evidence upgrade
- Do not create new relation_type without owner approval

---

## 5. Edge Status Lifecycle

```
HELD
  ↓ (evidence strengthened / SCG passed / review gate cleared)
PROMOTION_CANDIDATE
  ↓ (owner review PASS)
PROMOTED → insert into cognitive_edges
  OR
REJECTED → remains in staging, notes updated
```

Rules:
- HELD = insufficient evidence, SCG failed, or sensitivity too high
- PROMOTION_CANDIDATE = evidence sufficient, SCG passed, awaiting owner review
- PROMOTED = owner approved, inserted into cognitive_edges
- REJECTED = owner rejected, reason recorded in review_note

---

## 6. Source Status Values

```
REPORTED    — appears in source document, not independently verified
OFFICIAL    — appears in official legal/regulatory record
INFERRED    — derived from pattern, not direct source statement
HELD        — source exists but chain incomplete or contaminated
```

---

## 7. Sensitivity Level

```
LOW       — public record, no personal risk
MEDIUM    — named individual, reputational risk
HIGH      — legal risk, enforcement context, financial crime allegation
CRITICAL  — ongoing legal proceeding, direct personal jeopardy
```

Sensitivity governs:
- Whether edge can enter W output (HIGH/CRITICAL = Q-only by default)
- Whether owner review is required before promotion (always yes for HIGH/CRITICAL)
- Whether Exposure Gate must run before any publication

---

## 8. Evidence Level (recorded in evidence_basis field)

```
STRONG     — multiple independent sources, official record present
MODERATE   — single reliable source or multiple low-tier sources
WEAK       — single low-tier source, no corroboration
INSUFFICIENT — cannot support edge promotion
```

---

## 9. Review Gate Values

```
PENDING         — not yet reviewed
PASS            — owner approved for promotion
FAIL            — owner rejected
HOLD            — needs more evidence before review
SCG_REQUIRED    — Statistical Calibration Gate check needed first
```

---

## 10. Promotion Path Values

```
PROMOTE_TO_COGNITIVE_EDGES    — standard promotion
HOLD_PENDING_ENTITY_ID        — entity not yet in clean_entities
HOLD_PENDING_SOURCE_UPGRADE   — evidence needs upgrade
HOLD_PENDING_SCG              — SCG check not yet complete
REJECTED_INSUFFICIENT_EVIDENCE
REJECTED_SENSITIVITY_CRITICAL
```

---

## 11. Promotion SQL Template (Option A, Topology/Semantics Dual-Track)

Supersedes the earlier single-array template. Implements the
Anti-Topology Contamination Principle: `relation_type` stays locked to
the 6 graph-solver primitives; `semantic_relation_types` carries the
original domain label; `edge_strength` marks `co_occurs` edges as WEAK
by default so the solver excludes them from causal/control traversal.

**Prerequisite — must be run and verified before first use:**

```sql
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'ccc' AND table_name = 'cognitive_edges'
  AND column_name IN ('created_by_case_ids', 'semantic_relation_types', 'edge_strength');

SELECT conname FROM pg_constraint
WHERE conrelid = 'ccc.cognitive_edges'::regclass
  AND conname = 'cognitive_edges_topology_uniq';
```

If either check returns fewer rows than expected, run
`migration_cognitive_edges_topology_v2_staging.sql` first.

### 11.1 Topology-worthiness classification (doctrine-applied, not guessed)

This table is the actual judgment record, applying the test "does this
change graph traversal, connectivity, or state propagation" to each of
the 39 confirmed labels — not a prefix pattern match.

**Maps to a topology edge:**

| relation_type (staging)                          | → relation_type (cognitive_edges) | edge_strength |
|---------------------------------------------------|------------------------------------|----------------|
| OFFICIAL_ENFORCEMENT_ACTION_CONTEXT                | triggers                           | STRONG         |
| OFFICIAL_INDICTMENT_CONTEXT                        | triggers                           | STRONG         |
| OFFICIAL_JUDICIAL_ACTION_CONTEXT                   | triggers                           | STRONG         |
| REPORTED_BENEFICIAL_OWNER_OR_SHAREHOLDER_LINK      | supports                           | STRONG         |
| REPORTED_CONTROLLING_SHAREHOLDER_CONTEXT           | supports                           | STRONG         |
| REPORTED_SHAREHOLDING_CONTEXT                      | supports                           | STRONG         |
| REPORTED_BUSINESS_OWNERSHIP_CONTEXT                | supports                           | STRONG         |
| REPORTED_FOUNDER_OR_FAMILY_FUND_LINK               | supports                           | STRONG         |
| REPORTED_OFFSHORE_REGISTRATION                     | derives_from                       | STRONG         |
| REPORTED_OFFSHORE_INTERMEDIARY_LINK                | derives_from                       | STRONG         |
| SOURCE_DATASET_OR_LEAK_CONTEXT                     | derives_from                       | STRONG         |
| REPORTED_ASSOCIATE_NETWORK                         | co_occurs                          | WEAK           |
| REPORTED_FAMILY_ASSOCIATION                        | co_occurs                          | WEAK           |
| REPORTED_SPOUSAL_OR_FAMILY_ASSOCIATION             | co_occurs                          | WEAK           |
| REPORTED_ATTENDEE_CONTEXT                          | co_occurs                          | WEAK           |

**Explicitly NOT topology-worthy — must NOT be promoted to
cognitive_edges at all.** Per the doctrine's HSBC example, these are
evidence about an entity, not a structural relation between two
entities. They remain in `claims` / `evidence` / staging `notes`.
Attempting to promote these is a spec violation, not a missing-mapping
gap:

```
REPORTED_CFO_ROLE
REPORTED_CHAIRPERSON_ROLE
REPORTED_PRESIDENT_ROLE
REPORTED_VP_ROLE
REPORTED_COMPLIANCE_FAILURE_CONTEXT
REPORTED_COMPLIANCE_RISK_CONTEXT
REPORTED_FINANCIAL_CRIME_CONTEXT
REPORTED_BRIBERY_OR_KICKBACK_CONTEXT
REPORTED_ASSET_CONCEALMENT_CONTEXT
REPORTED_PROPERTY_LAUNDERING_RISK_CONTEXT
REPORTED_TAX_COMPLIANCE_CONTEXT
REPORTED_SAR_OR_FINANCIAL_INTELLIGENCE_CONTEXT
REPORTED_LONG_TAIL_ENFORCEMENT_CONTEXT
```

**Genuinely ambiguous — gated as `SEMANTIC_MAPPING_REQUIRED`, not
guessed.** These need an owner decision before they can be promoted;
the promotion template below routes them to a hold state rather than
silently defaulting:

```
REPORTED_FAMILY_FINANCIAL_ASSOCIATION
REPORTED_FAMILY_HOLDING_CONTEXT
REPORTED_CROSS_BORDER_WEALTH_MANAGEMENT_CONTEXT
REPORTED_SERVICE_PROVIDER_FOR_OFFSHORE_ENTITIES
REPORTED_FINANCING_CHANNEL_CONTEXT
REPORTED_OFFSHORE_JURISDICTION_ASSOCIATION
REPORTED_OFFSHORE_JURISDICTION_PATH
REPORTED_OFFSHORE_TAX_STRUCTURE
REPORTED_HISTORICAL_REORGANIZATION_CONTEXT
REPORTED_REGULATORY_HIERARCHY_CONTEXT
REPORTED_CENTRAL_FINANCIAL_ENTERPRISE_LISTING_CONTEXT
```

This mapping table is explicitly the **current confirmed version**, not
canonical — per the Semantic Evolution Principle, F-data will introduce
new labels that extend this table without requiring topology changes.

### 11.2 Promotion template

```sql
DO $$
DECLARE
  v_relation_type text;
  v_target_primitive text;
  v_target_strength text;
BEGIN
  SELECT relation_type INTO v_relation_type
  FROM ccc.three_system_candidate_edges_staging
  WHERE case_id = :target_case_id;

  v_target_primitive := CASE v_relation_type
    WHEN 'OFFICIAL_ENFORCEMENT_ACTION_CONTEXT' THEN 'triggers'
    WHEN 'OFFICIAL_INDICTMENT_CONTEXT' THEN 'triggers'
    WHEN 'OFFICIAL_JUDICIAL_ACTION_CONTEXT' THEN 'triggers'
    WHEN 'REPORTED_BENEFICIAL_OWNER_OR_SHAREHOLDER_LINK' THEN 'supports'
    WHEN 'REPORTED_CONTROLLING_SHAREHOLDER_CONTEXT' THEN 'supports'
    WHEN 'REPORTED_SHAREHOLDING_CONTEXT' THEN 'supports'
    WHEN 'REPORTED_BUSINESS_OWNERSHIP_CONTEXT' THEN 'supports'
    WHEN 'REPORTED_FOUNDER_OR_FAMILY_FUND_LINK' THEN 'supports'
    WHEN 'REPORTED_OFFSHORE_REGISTRATION' THEN 'derives_from'
    WHEN 'REPORTED_OFFSHORE_INTERMEDIARY_LINK' THEN 'derives_from'
    WHEN 'SOURCE_DATASET_OR_LEAK_CONTEXT' THEN 'derives_from'
    WHEN 'REPORTED_ASSOCIATE_NETWORK' THEN 'co_occurs'
    WHEN 'REPORTED_FAMILY_ASSOCIATION' THEN 'co_occurs'
    WHEN 'REPORTED_SPOUSAL_OR_FAMILY_ASSOCIATION' THEN 'co_occurs'
    WHEN 'REPORTED_ATTENDEE_CONTEXT' THEN 'co_occurs'
    ELSE NULL
  END;

  IF v_target_primitive IS NULL THEN
    UPDATE ccc.three_system_candidate_edges_staging
    SET review_gate = 'SEMANTIC_MAPPING_REQUIRED',
        promotion_path = 'BLOCKED_NOT_TOPOLOGY_WORTHY_OR_UNMAPPED',
        notes = COALESCE(notes, '') || E'\n[AUTO] relation_type ''' || v_relation_type ||
                ''' is not in the confirmed topology mapping. Either explicitly excluded ' ||
                'per Anti-Topology Contamination Principle, or genuinely ambiguous — ' ||
                'owner decision required before promotion.',
        updated_at = NOW()
    WHERE case_id = :target_case_id;

    RAISE NOTICE 'Case % blocked: relation_type % requires semantic mapping decision, not promoted.', :target_case_id, v_relation_type;
    RETURN;
  END IF;

  v_target_strength := CASE WHEN v_target_primitive = 'co_occurs' THEN 'WEAK' ELSE 'STRONG' END;

  INSERT INTO ccc.cognitive_edges (
      source_node_id, target_node_id, relation_type, weight,
      created_by_case_ids, semantic_relation_types, edge_strength
  )
  SELECT
      s.id, t.id, v_target_primitive, stg.weight,
      ARRAY[stg.case_id], ARRAY[stg.relation_type], v_target_strength
  FROM ccc.three_system_candidate_edges_staging stg
  JOIN ccc.clean_entities s ON s.canonical_slug = stg.source_subject
  JOIN ccc.clean_entities t ON t.canonical_slug = stg.target_subject
  WHERE stg.case_id = :target_case_id
  ON CONFLICT (source_node_id, target_node_id, relation_type)
  DO UPDATE SET
      created_by_case_ids =
        CASE WHEN EXCLUDED.created_by_case_ids[1] = ANY(ccc.cognitive_edges.created_by_case_ids)
             THEN ccc.cognitive_edges.created_by_case_ids
             ELSE ccc.cognitive_edges.created_by_case_ids || EXCLUDED.created_by_case_ids
        END,
      semantic_relation_types =
        CASE WHEN EXCLUDED.created_by_case_ids[1] = ANY(ccc.cognitive_edges.created_by_case_ids)
             THEN ccc.cognitive_edges.semantic_relation_types
             ELSE ccc.cognitive_edges.semantic_relation_types || EXCLUDED.semantic_relation_types
        END,
      weight = GREATEST(ccc.cognitive_edges.weight, EXCLUDED.weight);

  UPDATE ccc.three_system_candidate_edges_staging
  SET edge_status = 'PROMOTED',
      review_gate = 'PASS',
      promotion_path = 'PROMOTE_TO_COGNITIVE_EDGES',
      reviewed_by = 'owner',
      reviewed_at = NOW(),
      updated_at = NOW()
  WHERE case_id = :target_case_id
    AND EXISTS (SELECT 1 FROM ccc.clean_entities WHERE canonical_slug =
      (SELECT source_subject FROM ccc.three_system_candidate_edges_staging WHERE case_id = :target_case_id))
    AND EXISTS (SELECT 1 FROM ccc.clean_entities WHERE canonical_slug =
      (SELECT target_subject FROM ccc.three_system_candidate_edges_staging WHERE case_id = :target_case_id));

END $$;
```

**What changed from the previous draft, and why:**

```
- Removed invalid `DISTINCT(array_cat(...))` — not valid Postgres syntax.
- Replaced prefix-pattern LIKE matching with the explicit per-label
  table in 11.1 — prefix matching would silently misclassify labels
  like REPORTED_CFO_ROLE as if they were ordinary structural links,
  when the doctrine says role attributes are not topology-worthy.
- Replaced `ELSE 'supports'` with a hard fail to SEMANTIC_MAPPING_REQUIRED.
  No relation_type is silently assigned a primitive it wasn't
  explicitly classified into.
- Fixed column names against the actually-confirmed schema:
  clean_entities.canonical_slug (not .slug), staging's source_subject/
  target_subject (not source_slug/target_slug).
- Added an idempotency CASE guard so created_by_case_ids and
  semantic_relation_types cannot drift out of positional alignment
  on a repeated promotion attempt for the same case_id.
```

**Outstanding verification gap — stated directly, not assumed fixed:**
the confirmed staging schema dump does not show a `weight` column on
`three_system_candidate_edges_staging`. This template references
`stg.weight`, which has not been independently re-confirmed to exist.
Run this before first use:

```sql
SELECT column_name FROM information_schema.columns
WHERE table_schema = 'ccc' AND table_name = 'three_system_candidate_edges_staging'
  AND column_name ILIKE '%weight%';
```

If no such column exists, weight must be computed at promotion time
from `evidence_basis` and `source_status` using the weight-guidance
table in Section 11.3 below, not read from a non-existent column.

### 11.3 Weight guidance (unchanged from prior revision)

```
OFFICIAL_ + STRONG evidence:    0.85–0.95
REPORTED_ + STRONG evidence:    0.75–0.85
OFFICIAL_ + WEAK evidence:      0.40–0.55
REPORTED_ + MODERATE evidence:  0.60–0.79
REPORTED_ + WEAK evidence:      0.40–0.59
INFERRED:                       0.20–0.39
```

Conflict rule: evidence level governs over source_status prefix when
they diverge. State the divergence explicitly in `notes` when it
occurs.


---

## 12. Backlog Four-Category Classification

| Backlog Type           | Definition                                        | Current examples          |
|------------------------|---------------------------------------------------|---------------------------|
| Review Backlog         | Review gate PENDING, not yet owner-reviewed       | Any HELD without review   |
| Reconstruction Backlog | Candidate edge exists in notes/checkpoint         | B/C/D HELD edges (24 rows)|
|                        | but not yet entered into staging table            |                           |
| Source Backlog         | Edge in staging but missing independent           | CE-08, CE-12              |
|                        | source corroboration                              |                           |
| Promotion Backlog      | All conditions met, awaiting owner                | CE-09, CE-13              |
|                        | promotion decision                                | 16 PROMOTION_CANDIDATE rows|

---

## 13. B/C/D Reconstruction Pipeline

Current state:
```
In staging:
  HELD:                24 rows  → Reconstruction Backlog or Review Backlog
  PROMOTION_CANDIDATE: 16 rows  → Promotion Backlog

Not yet confirmed whether all B/C/D candidate edges are in staging.
Reconstruction means: verify staging coverage, fill gaps, then process.
```

Pipeline order:
```
Step 1: Verify staging coverage
  — Query staging for B-batch, C-batch, D-batch case_ids
  — Identify any checkpoint-noted edges not yet in staging

Step 2: Fill Reconstruction Backlog
  — Insert missing edges as HELD with evidence_basis and notes

Step 3: SCG check on all HELD rows
  — Correlation ≠ causation
  — Source independence
  — Statistical interpretation validity

Step 4: Review Gate
  — Owner reviews each PROMOTION_CANDIDATE
  — PASS → promotion SQL
  — FAIL → REJECTED with reason
  — HOLD → back to Source Backlog with required evidence noted

Step 5: Promotion
  — Entity ID resolution
  — cognitive_edges insert
  — Staging status update to PROMOTED
  — Checkpoint
```

---

## 14. Output Chain Position

All candidate edges in staging must record where they sit in the output chain:

```
output_chain_position (recorded in notes field until schema adds column):

INTERNAL_ONLY       — Q-layer only, never W
INTERNAL_ABSTRACTED — Q full, W abstract mechanism only
PUBLIC_OK           — W output permitted after Exposure Gate
```

Default for HIGH/CRITICAL sensitivity: INTERNAL_ONLY

---

## 15. Phase 3 Engineering Decisions — Resolved 2026-06-30

Both items below were open at Phase 2 closure draft time. Owner has
now decided both. Recorded as resolved, with the actual execution
status that was true at the moment the closure checkpoint was inserted
— not aspirational language.

### 15.1 L4 calibration automation level — DECIDED: Option B (semi-manual)

```
First F-data batch runs semi-manually: ingest_v3.py cleans and loads
to staging only. Four-Level Calibration and SCG checks remain owner-run
DBeaver SQL for this batch.

Reason: F-data is the first batch operating under OKB, Anti-Contamination,
and Final Output Principle. These rules must be stress-tested by hand
against real noise and narrative traps before being trusted to a code
operator. Automation review is scheduled after first F-data batch closes,
not before.
```

### 15.2 cognitive_edges traceability debt — DECIDED: Path A (schema addition)

```
ccc.cognitive_edges receives created_by_case_ids text[] DEFAULT '{}'.

Execution requirement: this migration must run and be verified BEFORE
the Phase 2 closure checkpoint is inserted — not promised in the
checkpoint note and executed later. A checkpoint note claiming a schema
change is "locked" while the column does not yet exist would itself be
a Final Output Principle violation (output certainty exceeding actual
state).

Migration file: migration_cognitive_edges_case_ids_staging.sql
Status at closure checkpoint insert time: see verification block in
that file — must show created_by_case_ids present in cognitive_edges
before this closure document is treated as final.

Reason for Path A over Path B: at F-data volume, multi-batch edge
overlap probability rises sharply; reverse staging lookup for rollback
becomes intractable once two batches independently support the same
edge. A microsecond-cost metadata column purchases precise surgical
rollback capability. Path B's manual cross-reference was only viable
at the current 40-row experimental scale.
```

---

## Document Status

```
File:       ccc_v6_2_edge_reconstruction_spec.md
Version:    v1.1 candidate / draft (Topology/Semantics dual-track)
Checkpoint: TBD — pending owner review and DB inspection
write_db:   NO

Migrations required before this spec's promotion template can run:
  1. migration_cognitive_edges_case_ids_staging.sql — RUN AND VERIFIED
     (created_by_case_ids confirmed present 2026-06-30)
  2. migration_cognitive_edges_topology_v2_staging.sql — NOT YET RUN
     (adds semantic_relation_types, edge_strength, unique constraint —
     must run and verify before Section 11.2 template is used)

Outstanding gap, not yet resolved:
  staging.weight column existence has not been confirmed — see
  Section 11.2 verification query. Template will fail at JOIN if
  absent and has not been corrected for that case.

Based on:
  three_system_candidate_edges_staging schema (confirmed)
  cognitive_edges schema (confirmed, pre-migration-2 state)
  checkpoint-144/145/146 architecture closure
  checkpoint-147 latest state
  Anti-Topology Contamination Principle (this revision)
  Semantic Evolution Principle (this revision)
```
