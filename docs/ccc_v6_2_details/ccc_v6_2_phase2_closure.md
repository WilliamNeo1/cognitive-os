# ccc_v6_2_phase2_closure.md
## CCC V6 Phase 2 Architecture Closure Record

Status: candidate / draft
Scope: Phase 2 收尾 — A→E full chain completion + architecture stabilisation
write_db: NO until owner confirmation
Checkpoint ID: TBD pending DB inspection

---

## 0. Phase 2 Completion Statement

CCC SQLV3 / V6 Phase 2 has completed its first full A→E data pipeline:

```
A-data Review  ✓  (checkpoint-119)
B-data Review  ✓  (checkpoint-122)
C-data Review  ✓  (confirmed in sequence)
D-data Review  ✓  (confirmed in sequence)
E-data Review  ✓  (checkpoint-147)
```

This is the first time CCC has run a complete A→E chain under:
- Source hygiene discipline
- Claim/event/entity/edge boundary rules
- Candidate edge HELD protocol
- Four-Level Calibration
- SCG (Statistical Calibration Gate)
- VDRA architecture

Before proceeding to F-data, three institutional records are
locked as Phase 2 architecture outputs.

---

## 1. Core Constitution Update — Three New Principles

### 1.1 Operational Knowledge Boundary (OKB)

```
CCC does not claim to know what it has not confirmed.
Every output must be bounded by what the evidence actually supports.
```

OKB levels (recorded in edge/claim notes):
```
OKB-1  CONFIRMED    — multiple independent sources, official record
OKB-2  SUPPORTED    — single reliable source, consistent with pattern
OKB-3  REPORTED     — source says this; not independently verified
OKB-4  INFERRED     — derived from pattern, no direct source
OKB-5  SPECULATIVE  — no source basis; hypothesis only
OKB-6  UNKNOWN      — cannot be assessed with current evidence
```

Rule: OKB level must not be upgraded without evidence upgrade.
OKB-5 and OKB-6 cannot enter cognitive_edges.
OKB-3 and OKB-4 enter staging as HELD pending corroboration.

### 1.2 Anti-Information Contamination Principle

```
Information that enters CCC must not contaminate judgment
before it has passed calibration.
```

Four contamination vectors to control:

```
1. Source contamination
   Source says X ≠ X is true.
   AI output ≠ primary evidence.
   Media narrative ≠ confirmed event.

2. Layer contamination
   W feedback must not automatically modify Q.
   Public reaction must not become Q fact.
   External AI framing must not replace owner judgment.

3. Statistical contamination
   Correlation ≠ causation.
   Trend ≠ causal order.
   Average ≠ individual time path.
   Outlier ≠ noise.

4. Promotion contamination
   Candidate edge ≠ clean_graph_edge until promoted.
   HELD edge ≠ accepted edge.
   REPORTED relation ≠ OFFICIAL relation.
```

### 1.3 Anti-Topology Contamination Principle

```
Topology exists only for graph reasoning, not for storing knowledge.
拓扑只为推理存在，而不是为了存储知识。

Graph is not a knowledge database.
Graph is only the minimum topology required for reasoning.
图不是知识库。图只是推理所需要的最小拓扑骨架。

Topology Minimalism: only information that changes graph traversal,
connectivity, or state propagation may become a topology edge.
Everything else — entity attributes, role labels, risk evidence,
compliance context, long-tail descriptions — belongs in claims,
evidence, documents, or notes. Not in cognitive_edges.

co_occurs is a weak edge by default (edge_strength = 'WEAK').
The graph solver must not perform causal or control-chain inference
over co_occurs edges.

triggers means graph-state-propagation trigger, not timeline
causality. Chronological precedence alone does not justify a
triggers edge.
```

### 1.4 Projection Principle

```
Topology Layer is a projection of Knowledge Layer, not the
Knowledge Layer itself.
拓扑层是知识层的投影，而不是知识层本身。

Every topology edge must be reproducible from underlying claims
and evidence:

  documents → claims → evidence → candidate_edges → graph_edges

This guarantees that the graph can at any time be:
  dropped
  rebuilt
  verified

without loss of ground truth, because ground truth lives in
documents and claims, not in cognitive_edges.

An edge that cannot be reproduced from claims and evidence is
not a topology edge — it is unmaintainable infrastructure.
```

### 1.5 Semantic Evolution Principle

```
Business semantics are expected to evolve; graph topology should
evolve only when graph reasoning requirements evolve.
业务语义允许持续演化；图拓扑只有在推理需求发生变化时才应演化。

The domain-specific relation_type vocabulary (REPORTED_*, OFFICIAL_*,
SOURCE_*) is a Current Confirmed Vocabulary, not a Canonical
Vocabulary — versioned, extensible, not immutable.

New labels from F-data and beyond extend the mapping table (spec
Section 11.1) without requiring changes to the 6 topology primitives.

When a new label is encountered, it does not automatically become
a new primitive. It first passes through:
  Topology-worthy classification (spec Section 11.1)
  → if qualified: map to an existing primitive
  → if ambiguous: SEMANTIC_MAPPING_REQUIRED gate
  → if excluded: stays in claims/evidence only
```

### 1.6 Final Output Principle

```
Every CCC output must know its own boundary.
```

Every output — claim, edge, prediction, decision, public article —
must carry:

```
output_type:    INTERNAL_Q / PUBLIC_W / ABSTRACTED_W
okb_level:      OKB-1 through OKB-6
calibration:    Fact / Inference / Not Established / Operational Impact
sensitivity:    LOW / MEDIUM / HIGH / CRITICAL
exposure_gate:  PASSED / REQUIRED / BLOCKED
```

No output may represent itself as more certain than its OKB level supports.
No output may move from Q to W without Exposure Gate.
No output may claim owner authority without owner review.

---

## 2. Architecture Stability Declaration

As of checkpoint-147, CCC V6 has stabilised the following
institutional rules:

```
Architecture layer:
  CORE (7 components including five defences)        ✓ locked at checkpoint-146
  Seven operational layers L1–L7                     ✓ locked
  VDRA embedded at L1/L2                            ✓ locked at checkpoint-144
  SCG (Statistical Calibration Gate) at L4          ✓ locked at checkpoint-145
  Q/W Exposure Governance                            ✓ locked
  AI Narrative Power Risk                            ✓ locked

Data governance:
  Source hygiene rules                               ✓ operational
  Claim/event/entity/edge boundary                  ✓ operational
  HELD-edge protocol                                 ✓ operational
  three_system_candidate_edges_staging schema        ✓ confirmed
  Candidate Edge Reconstruction Spec v1.0            ✓ this document

Backlog classification:
  Review Backlog                                     ✓ defined
  Reconstruction Backlog                             ✓ defined
  Source Backlog                                     ✓ defined
  Promotion Backlog                                  ✓ defined
```

F-data and all subsequent batches will operate under these
stabilised rules without needing to redefine them.

---

## 3. Known Open Items (not blocking F-data)

```
Reconstruction Backlog:
  B/C/D HELD edges (24 rows in staging)
  — pipeline defined in edge_reconstruction_spec.md
  — execute after Phase 2 closure checkpoint

Promotion Backlog:
  16 PROMOTION_CANDIDATE rows in staging
  — awaiting owner promotion decisions
  — entity ID resolution required for some

Source Backlog:
  CE-08, CE-12 (and others TBD)
  — need independent source corroboration

Promotion Backlog (entity-dependent):
  CE-09, CE-13
  — entity_id resolution pending
```

## 3.1 Phase 3 Engineering Decisions — Resolved 2026-06-30

Two items previously flagged as schema-level technical debt have been
decided, not deferred:

```
L4 calibration automation: DECIDED Option B (semi-manual).
  First F-data batch processed by hand under DBeaver SQL before any
  automation is encoded into ingest_v3.py. See edge_reconstruction_spec.md
  Section 15.1 for full reasoning.

cognitive_edges traceability: DECIDED Path A (schema addition).
  created_by_case_ids text[] added via
  migration_cognitive_edges_case_ids_staging.sql. This migration must
  be run and verified before the Phase 2 closure checkpoint is treated
  as final — the checkpoint note's claim of "locked" must match actual
  DB state at insert time. See edge_reconstruction_spec.md Section 15.2.
```

---

## 4. Phase 2 Architecture Output — Six Institutional Principles

Phase 2's permanent output is not data. It is six principles that
constrain all future work:

```
1. Anti-Information Contamination Principle
   Source / layer / statistical / promotion contamination controlled.

2. Final Output Principle
   Every output carries output_type / okb_level / calibration /
   sensitivity / exposure_gate. No output claims more certainty
   than its evidence supports.

3. Anti-Topology Contamination Principle
   Graph is only the minimum topology required for reasoning.
   Topology exists only for graph reasoning, not knowledge storage.

4. Topology Minimalism
   Only information that changes graph traversal, connectivity, or
   state propagation may become a topology edge.

5. Projection Principle
   Every topology edge must be reproducible from underlying claims
   and evidence. The graph can always be dropped, rebuilt, verified.

6. Semantic Evolution Principle
   Business semantics evolve continuously. Graph topology evolves
   only when graph reasoning requirements evolve.
```

## 5. Phase 2 → Phase 3 Transition Conditions

Phase 3 begins when:

```
1. migration_cognitive_edges_topology_v2_staging.sql run and verified
   — all 3 checks pass (staging weight, cognitive_edges columns,
     unique constraint)

2. checkpoint-148 (ccc-v6-phase2-topology-minimalism-closure-v01)
   inserted after migration verification, not before

3. Candidate Edge Reconstruction Spec v1.1 committed to repo

4. ccc_v6_2_phase2_closure.md committed to repo

5. F-data ingest begins under unified spec, Option B calibration,
   Path A traceability
```

Phase 3 goals:

```
- F-data using unified edge spec, weight column, topology classification
- B/C/D Reconstruction Backlog processed in parallel (24 HELD rows)
- Promotion decisions on 16 PROMOTION_CANDIDATE rows
  (weight must be set per evidence-level guidance before promotion)
- SEMANTIC_MAPPING_REQUIRED gate applied to 11 ambiguous labels —
  owner decisions collected as Phase 3 milestone 1
- Evidence Layer design begins: housing the 13 excluded labels
  currently stranded in staging
```

---

## Document Status

```
File:       ccc_v6_2_phase2_closure.md
Version:    candidate / draft
Checkpoint: TBD — pending owner confirmation
write_db:   NO
Based on:
  checkpoint-144 VDRA embedded
  checkpoint-145 SCG recorded
  checkpoint-146 V6.2 architecture closure
  checkpoint-147 e-data complete (latest)
  three_system_candidate_edges_staging confirmed schema
```
