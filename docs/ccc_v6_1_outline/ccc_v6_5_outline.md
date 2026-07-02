# CCC / Cognitive-OS V6.5
## Master Outline

Status: candidate / draft
Based on: checkpoint-148 · ADR-118 · Phase 2 sealed
File: docs/ccc_v6_1_outline/ccc_v6_5_outline.md

> CCC is a governed cognitive architecture.
> Not a knowledge management system.
> Not merely a cognitive system.
> A system that forms reliable judgment under constraint.

```
Decision Flow (invariant):

Reality
↓
Define
↓
Explore
↓
Evaluate
↓
Judge
↓
Execute
↓
Reality

L1–L7 = Governance of each step, not the steps themselves.
```

---

# Part I — CORE Constitution

> The constitution. Changes almost never.
> Defines why CCC exists, why it is designed this way,
> and what must never be done.

---

## I.1 Mission

```
CCC exists to improve timely action under uncertainty.
Not to accumulate data. Not to accumulate knowledge.

Cognition exists to improve action.
Action changes reality.
Reality determines survival.
```

The final output of CCC is not knowledge, not judgment.
It is timely action that improves the subject's probability of
survival and long-term development.

**Goal chain (top-down):**

```
Survival & Development
        ↑
Effective Action
        ↑
Correct Decision
        ↑
Calibrated Prediction
        ↑
Understanding Reality
```

Architecture, calibration, knowledge, prediction — all are means.
Survival and development is the end.

**Contrast with IPT (Incident / Investigation Project):**

```
IPT goal:  Win the case.
           Evidence precedes action.
           Procedure protects credibility.
           Slow and correct beats fast and wrong.

CCC goal:  Improve survival and long-term development.
           Protection can precede explanation.
           When survival is at stake, delay is also a decision.
```

Same methods may be shared (timeline, evidence, calibration).
Different architectural priorities — because different ultimate goals.
Architecture must always be derived from the system's ultimate goal.
架构不是先验存在的，它必须由系统的最终目标推导出来。

```
User        = source
Think tank  = externalized structure
CCC         = technical carrier
```

## I.2 Primary Driver Chain

```
D0 Power
↓
D1 Resources
↓
D2 Economy
↓
D3 Technology
↓
D4 Society
↓
D5 Events

Event is not the cause. Event is the manifestation. Driver is the cause.
事件不是原因。事件是显化。驱动力才是原因。
```

## I.3 Core Principles

1. CORE governs all layers, but is not itself a layer.
2. CORE must remain operationally positive.
3. Power is the upstream of resource allocation.
4. Events are manifestations, not root causes.
5. Every major analysis must trace upward toward power and resource allocation.
6. Source is not truth. Record is not reality. Claim is not event.
7. Hypothesis is not edge. Correlation is not causation.
8. Prediction is not decision. Decision is not guaranteed truth.
9. Public feedback is not Q fact.
10. Calibration is required before judgment.
11. Rigor means reducing false positives and false negatives.
12. Incomplete information creates tolerable error, not false certainty.
13. Unknown risk must be survivable before commitment. Withdrawal, pause, and observation are actions.
14. Caution must not become paralysis. CCC must always preserve non-zero output.
15. Truth belongs in Q. Exposure is governed in W. AI may assist but must not rule.
16. Automatic acquisition is not automatic absorption.
17. Graph is not a knowledge database. Graph is only the minimum topology required for reasoning.
18. Every topology edge must be reproducible from underlying claims and evidence.
19. Business semantics evolve; graph topology evolves only when reasoning requirements evolve.
20. Reality is upstream of architecture. Architecture serves reality. Reality never bends to architecture.
21. No inspection, no formal ID. No confirmation, no write command. No evidence, no canonical label.
22. Architecture must always be derived from the system's ultimate goal. Goal precedes architecture. Architecture must never override goal.

## I.4 Irreducible Core

```
CCC Core is not emptiness.
CCC must always preserve:

Source    — user as origin; without source, CCC loses direction
Judgment  — capacity to form calibrated judgment
Memory    — capacity to store replayable structure
Boundary  — capacity to distinguish fact/inference/unknown/action
Action    — capacity to support real-world constrained action
```

## I.5 Forbidden Rules

```
Do not call CORE a layer.
Do not let source automatically become truth.
Do not let claim automatically become event.
Do not let hypothesis automatically become edge.
Do not let prediction automatically become decision.
Do not mix Fact / Inference / Not Established / Operational Impact.
Do not dissolve CORE into pure negation or operational emptiness.
Do not let uncertainty collapse the system to zero.
Do not allow W feedback to automatically modify Q.
Do not delegate sovereign judgment to any AI system.
Do not publish sensitive Q content without Exposure Gate review.
Do not assign formal IDs without inspection.
Do not promote topology edges that cannot be reproduced from claims.
Do not treat co_occurs as a causal inference edge.
Do not add a layer when a doctrine or module would suffice.
Do not interpret every conceptual breakthrough as a major version jump.
```

## I.6 Language Policy

```
English for structure and naming.
Chinese for explanation.
Bilingual for transmission.

Core = English-first (ADR, DDL, SQL, API, enums, checkpoints, labels)
Explanation = paired English / Chinese
Transmission = Chinese-first or bilingual
```

## I.7 Naming Firewall

```
CORE     = supreme constraint (not a layer)
D0–D5    = driver rank
L1–L7    = governance layer (stable, ordered, not numbered inside CORE)
Doctrine = cross-layer principle (governs all layers, belongs to Part III)
Module   = operational mechanism inside a layer (belongs to Part II)
```

## I.8 Evolution Rules

```
Five permitted upgrade types:

① Add Doctrine       → Part III only
② Deepen Module      → Part II only
③ Enhance Calibration → Part III or Part II
④ Add Engineering    → Part IV
⑤ Add Maps           → Part IV

Five prohibited changes:

✗ Add a Layer
✗ Change Layer order
✗ Override CORE
✗ Modify Driver Chain
✗ Rename existing Canonical objects

Stable architecture. Evolving intelligence.
稳定的架构。无限演化的智能。
```

---

# Part II — Cognitive Pipeline

> The seven governance layers.
> Not a workflow — a governance framework for each step of cognition.
> Each layer has one job. One template. One boundary.

```
Template (every layer):

Purpose
Input
Output
Boundary Rules
Tables
Active Modules
Future Extension
```

---

## L1 — Reality Intake & Source Hygiene

**Purpose:** Maintain contact with reality. All external material enters here.

**Input:** Public data · OCR · Owner import · News · Filings · Observations · VDRA fetch

**Output:** `raw_documents` with source labels attached

**Boundary Rules:**
```
Input is not absorption.
Source is not truth.
Record is not reality.
CCC can automatically acquire reality samples — must not automatically believe them.
```

**Mandatory labels on every intake row:**
```
source · source_layer · source_status · contamination_status
ai_source_risk · exposure_risk · access_mode
```

**Tables:** `raw_documents · reality_source_registry · reality_tasks · outcome_source_routing`

**Active Modules:** VDRA

**Future Extension:** Scheduler / recurring fetch runner / source freshness monitor

---

## L2 — Source & Claim Registration

**Purpose:** Convert raw material into auditable, typed objects.

**Input:** `raw_documents`

**Output:** Registered sources, candidate claims, candidate events, review queue items

**Boundary Rules:**
```
Source says X ≠ X is true.
Claim exists ≠ Claim is valid.
AI summary is not evidence.
Nothing passes to L3 without a source anchor.
```

**Tables:** `documents · claims · sources · source_profiles · review_queue`

**Active Modules:** Source hygiene pipeline

**Future Extension:** Auto-dedup log · source freshness scoring

---

## L3 — Entity / Claim / Event Structuring

**Purpose:** Decompose registered material into typed structural objects.

**Input:** Candidate claims and events from L2

**Output:** Typed Claim · Event · Entity · Hypothesis · Rumor · Interpretation

**Boundary Rules:**
```
Claim is not event.
Commentary is not event.
Hypothesis is not edge.
Rumor does not enter clean_graph_edges.
Interpretation does not become REALITY_EVENT.
```

**Claim kinds:** factual · interpretive · predictive · normative · propaganda · user_analysis

**Tables:** `claims · events · clean_entities · hypotheses · context_facts`

**Active Modules:** Entity upsert pipeline

**Future Extension:** NER v2 · automated claim-type classifier

---

## L4 — Evidence & Calibration

**Purpose:** Calibrate every object before it can advance.
Evidence is confirmed here. Topology projection happens in L5.

**Input:** Typed objects from L3

**Output:** Calibrated objects with Four-Level tag + SCG result + exposure status

**Boundary Rules:**
```
Fact / Inference / Not Established / Operational Impact must be separated.
SCG must pass before any candidate edge is promoted.
Exposure calibration must run before any W output is considered.
AI output is not primary evidence.
```

**Calibration dimensions:**
```
Four-Level Calibration:  Fact / Inference / Not Established / Operational Impact
SCG (6 checks):          dimension curse · shrinkage · random trend
                         time-path vs ensemble · fat tail · causal inference
Exposure Calibration:    public risk before any W output
AI Bias Calibration:     subject drift · responsibility drift · softening
```

**Tables:** `calibration_records · validation_notes · scorecards · statistical_calibration_gate_registry`

**Active Modules:** Statistical Calibration Gate (SCG) · Candidate Edge Pipeline

**Future Extension:** Evidence Layer (houses 13 non-topology relation types currently in staging)

---

## L5 — Knowledge Integration & Topology Projection

**Purpose:** Project calibrated knowledge into graph topology.
Knowledge Layer (claims/evidence) is ground truth.
Topology Layer is a projection — not the Knowledge Layer itself.

**Input:** Calibrated objects from L4

**Output:** `clean_entities · cognitive_edges · timelines · driver_chain_map`

**Boundary Rules:**
```
No entity without identity anchor.
No edge without traceable source in claims/evidence.
No driver chain without calibrated basis.
Topology Layer is a projection of Knowledge Layer — not the source of truth.
Topology classification governs what becomes an edge:
  Topology-worthy (15 types) → triggers / supports / derives_from / co_occurs
  Non-topology (13 types)    → stays in claims/evidence/L4
  Ambiguous (11 types)       → SEMANTIC_MAPPING_REQUIRED gate
```

**Tables:** `clean_entities · cognitive_edges · timelines · driver_chain_map · three_system_candidate_edges_staging`

**Active Modules:** Candidate Edge Pipeline · Driver Chain Mapper

**Future Extension:** Semantic Mapping Module (resolves 11 SEMANTIC_MAPPING_REQUIRED labels)

---

## L6 — Prediction & Decision

**Purpose:** Generate constrained operational output from calibrated, projected knowledge.

**Input:** Calibrated evidence + topology from L5

**Output:** Prediction + Decision + public_status

**Boundary Rules:**
```
Prediction is not decision.
Decision is not guaranteed truth.
Every decision output carries a public_status.
∞ ≠ 0 — uncertainty must produce a constrained state, not paralysis.
```

**Prediction format:**
```
Prediction · Confidence (0.15–0.95) · Conditions · Warning Signals · Revision Triggers
```

**Decision values:**
```
DO · DO_WITH_CAUTION · WAIT · WATCH · NO_GO · REVIEW_REQUIRED
NEGOTIATE · BUILD · REFUSE · EXIT · DEFEND · HEDGE
DOCUMENT · ESCALATE · REPAIR · PUBLISH · FILE
```

**Public status (attached to every decision):**
```
PUBLIC_OK · PUBLIC_ABSTRACT_ONLY · OWNER_REVIEW_REQUIRED · Q_ONLY · DO_NOT_PUBLISH
```

**Tables:** `decision_records · prediction_outputs · prediction_audit · audit_logs`

**Active Modules:** Assessment Pipeline (R0–R7) · Prediction Engine

**Future Extension:** Automated confidence calibration

---

## L7 — Public Output, Feedback, Memory & Checkpoint

**Purpose:** Close the loop. Govern exposure. Record memory. Enable succession.

**Input:** Decisions + public_status from L6; W feedback from public

**Output:** W public output · Checkpoint records · Memory / succession entries

**Boundary Rules:**
```
W feedback is not Q fact.
No direct W → Q write.
Public output does not modify internal judgment.
Checkpoint closes the loop — no batch proceeds without it.
```

**Sub-components:**
```
L7A  Exposure Gate        Q→W 8-question check before any sensitive content enters W
L7B  W Public Output      Fact / Inference / Not Established / Watch / Operational meaning
L7C  Feedback Loop        W → feedback_queue → Audit → Absorption → Return to Q
L7D  Scorecard / Review   /80 · PASS ≥ 60 · REVIEW 48–59 · FAIL < 48
L7E  Checkpoint           rsal_checkpoints · latest: checkpoint-148
L7F  Memory & Succession  Platform risk · AI risk · owner corrections · Classics
```

**Tables:** `public_outputs · w_feedback · absorption_log · rsal_checkpoints`

**Active Modules:** Exposure Gate · Feedback Queue · Audit & Absorption · Checkpoint Discipline

**Future Extension:** Automated succession indexing

---

# Part III — Cross-layer Doctrines

> Everything that governs all layers simultaneously.
> Not a step in the pipeline. Not a module inside one layer.
> A doctrine applies from L1 to L7 without exception.
>
> Adding a doctrine does not change Part II.
> Adding a doctrine does not change Part I.
> Only Part III changes.

---

## III.1 Four-Level Calibration Framework

```
Every major claim, edge, prediction, decision, and public output
must distinguish:

Fact               Directly supported by evidence
Inference          Reasonably derived from facts
Not Established    Currently neither proven nor disproven
Operational Impact Practical meaning for case, decision, or CCC

Rigor is not the pursuit of absolute correctness.
Rigor is the systematic reduction of false positives and false negatives.
```

## III.2 Q / W Sovereignty Boundary

```
Q Layer — Internal Truth & Decision (Owner/Q-direct only)
  Contains: raw_documents · claims · events · clean_entities
  cognitive_edges · prediction_audit · rsal_checkpoints

Q → Exposure Gate (8 questions) → W

W Layer — Public Survival Interface (all non-owner actors)
  Mechanism > accusation · Structure > emotion
  Low attack surface > high-exposure collision

W → Feedback Queue → Audit → Absorption → Return to Q

Owner = Q.  Others = W.  No trusted middle layer by default.
```

## III.3 VDRA — Validation-driven Reality Acquisition

```
CCC can automatically acquire reality samples.
CCC must not automatically believe them.

Trigger path:
L7 gap detection → information_gaps → reality_tasks
→ outcome_source_routing → reality fetch
→ raw_documents → L1 intake → L2 registration → calibration

VDRA cannot:
  auto-confirm facts · auto-generate accepted events
  auto-write cognitive_edges · auto-output W
  bypass owner review · process political content automatically
```

## III.4 Statistical Calibration Gate (SCG)

```
Six checks — applied at L4 before any promotion:

1. Dimension restraint    More features ≠ better judgment
2. Shrinkage estimation   Single entity judgment must compare against peer baseline
3. Random trend alert     Long-term trend ≠ causal order
4. Time-path priority     Ensemble averages ≠ individual survival paths; prevent ruin first
5. Tail risk priority     Low-probability catastrophic events modelled separately
6. Causation priority     Correlation / co-occurrence cannot be promoted to formal edge
```

## III.5 Exposure Governance

```
Exposure Gate questions (must pass before Q content enters W):
1. Must this be published now?
2. Can it be delayed?
3. Can it be abstracted?
4. Can the subject be de-identified?
5. Can it be reframed as mechanism analysis?
6. Will it expose CCC's judgment chain?
7. Will it trigger platform, legal, identity, or partner risk?
8. Has owner reviewed it?
```

## III.6 AI Narrative Power Risk

```
No AI is neutral.
AI may assist: retrieval · parsing · translation · summarisation
              mechanical execution · analysis support

AI must not: form sovereign judgment · determine political framing
             approve public exposure · hold core principle authority

Calibration signals — check all AI-assisted outputs for:
subject drift · responsibility drift · softening
unauthorized framing · politically biased paraphrase
sensitivity replacement · owner intent dilution
```

## III.7 Topology Minimalism & Projection

```
Graph is not a knowledge database.
Graph is only the minimum topology required for reasoning.
拓扑只为推理存在，而不是为了存储知识。

Topology Layer is a projection of Knowledge Layer — not the source of truth.
Every topology edge must be reproducible from underlying claims and evidence.
Graph can be dropped, rebuilt, verified at any time.

Topology primitives (6 only):
supports · contradicts · derives_from · revises · triggers · co_occurs

co_occurs = WEAK edge by default. No causal inference permitted.
triggers  = graph state propagation, not timeline causality.

Classification at L5:
  Topology-worthy (15) → map to a primitive
  Non-topology (13)    → claims/evidence only
  Ambiguous (11)       → SEMANTIC_MAPPING_REQUIRED gate
```

## III.8 Semantic Evolution

```
Business semantics evolve continuously.
Graph topology evolves only when reasoning requirements evolve.
业务语义允许持续演化；图拓扑只有在推理需求发生变化时才应演化。

Vocabulary is Current Confirmed Version — not canonical, not immutable.
New labels extend the mapping table (spec Section 11.1).
New labels do not automatically become new topology primitives.
New labels first pass: topology-worthy classification → existing primitive
                       or: SEMANTIC_MAPPING_REQUIRED gate
```

## III.9 Intelligence Cycle

```
7-step closed loop:

1. Direction      Define question before collecting material
2. Collection     Acquire from official records / OSINT / VDRA / owner import
3. Processing     Transcribe · denoise · extract entity / timeline / causal chain
4. Analysis       Fact · Assessment · Inference · Speculation · Narrative · Propaganda
5. Production     Conclusion · confidence · key evidence · counter-evidence · unknowns
6. Dissemination  Q full / W filtered — no W contamination of Q
7. Feedback       All judgments subject to post-hoc fact-checking and revision

Three information traps to avoid:
  Information overload  · Source illusion  · Conclusion-first
```

## III.10 Non-Zero Action Doctrine

```
∞ ≠ 0
Infinite uncertainty does not justify zero operational output.
Calibration must not end in paralysis.

Fact sufficient      → DO
Inference reasonable → DO_WITH_CAUTION
Not Established      → WATCH / WAIT / HEDGE / DOCUMENT
Risk exceeds limit   → NO_GO / REFUSE / EXIT / DEFEND
```

## III.11 Owner / Public Binary Access

```
Owner / Q-direct:    Full truth · full evidence · full judgment · full risk
Public / W-mediated: All non-owner actors — engineers, external AI,
                     platform tools, collaborators — see W only

No trusted middle layer by default.
```

## III.12 Schema Governance

```
All migrations tracked and versioned.
DDL changes require owner confirmation before execution.
Confirmed cognitive_edges schema (post checkpoint-148):
  id · source_node_id · target_node_id · relation_type · weight
  created_at · created_by_case_ids · semantic_relation_types · edge_strength
  Constraint: cognitive_edges_topology_uniq
    UNIQUE (source_node_id, target_node_id, relation_type)

Confirmed staging schema:
  three_system_candidate_edges_staging
  Key columns: case_id · relation_type · edge_status · source_status
  sensitivity_level · evidence_basis · review_gate · promotion_path
  weight (DEFAULT 1.0 — placeholder, not calibrated)
```

## III.13 Anti-Information Contamination

```
Four contamination vectors — must be controlled at every layer:

1. Source contamination     Source says X ≠ X is true
2. Layer contamination      W feedback must not auto-modify Q
3. Statistical contamination Correlation ≠ causation · average ≠ individual path
4. Promotion contamination  Candidate edge ≠ accepted edge until promoted
```

## III.14 Survival Priority Doctrine

```
When reality changes faster than cognition,
protection precedes explanation.

Reaction precedes interpretation.
When survival is at stake, delay is also a decision.
```

**Action flow (when survival pressure is high):**

```
Reality
↓
Threat Detection
↓
Immediate Action / Protection
↓
Evidence
↓
Analysis
↓
Knowledge
```

Evidence comes after action — not because evidence is unimportant,
but because survival is the precondition for everything else.
If the subject does not survive, evidence becomes irrelevant.

**Standard flow (when survival pressure is low):**

```
Reality → Define → Explore → Evaluate → Judge → Execute → Reality
```

L1–L7 governs both flows. The flow selected depends on threat level,
not on architectural preference.

**Core rules:**

```
Unknown risk must be survivable before commitment.
  Withdrawal, pause, and observation are themselves actions.

Time-path priority over ensemble averages.
  Ensemble average = 0 does not mean individual ruin probability = 0.
  Prevent ruin before maximising expected value.

Tail risks modelled separately — not averaged away.
  Low-probability catastrophic events get their own model.
  They are not noise. They are the most important signals.

Delay is a decision.
  Inaction under threat is a choice with consequences.
  Not acting is not the same as not deciding.
```

---

# Part IV — Evolution

> Architecture does not grow here.
> Intelligence grows here.
> Reality Tests, Checkpoints, Regression Corpus, Roadmap.

---

## IV.1 Checkpoint Discipline

```
Format:  ccc.rsal_checkpoints
Fields:  checkpoint_label · module · note · created_at (sequence-assigned ID)

Rules:
- Checkpoint ID is never hardcoded — always DB-sequence-assigned
- Checkpoint note must match actual DB state at insert time
  (Final Output Principle applies to checkpoints)
- No batch proceeds without a closed checkpoint
- Formal IDs require repo + DB inspection before assignment

Latest: checkpoint-148
  ccc-v6-phase2-topology-minimalism-closure-v01
  2026-07-01 · architecture-closure
```

## IV.2 ADR Discipline

```
ADR files: docs/ccc_v6_4_archive/drafts/adr_legacy/
Current:
  ADR-116  W Layer Redefinition v0.1
  ADR-117  CCC V6 Chain Structure v0.1
  ADR-117  Amendment 01 CORE Epistemic Boundary
  ADR-118  V6 Calibration Amendment v0.1
           (Four-Level Calibration · Irreducible Core · Non-Zero Action)
Next ADR:  TBD — pending inspection
```

## IV.3 Reality Test Protocol

```
Standard pipeline:
Reality → Source → Claim → Event → Entity → Edge →
Driver Chain → Four-Level Calibration → SCG →
Prediction → Decision → Public Output → Review → Checkpoint

Scorecard: /80 · PASS ≥ 60 · REVIEW 48–59 · FAIL < 48

Batch status:
RT-B01  AWS NZ + MBIE/INZ        COMPLETE
        checkpoint-125 · public output v1.1 · 71/80 PASS
RT-B02  NZ energy-water          SCOPE DEFINED · not started
RT-B03  Continuous Knowledge     Phase 3 first milestone (F-data)
        Evolution Test           Goal: prove Pipeline works without
                                 modification on new data
```

## IV.4 Regression Corpus

```
24 HELD rows in three_system_candidate_edges_staging = Regression Corpus
Not a backlog to clear. A test dataset to rerun.

Rerun after each upgrade to: VDRA / SCG / Topology / Evidence Layer

If previously HELD → now promotes:   upgrade is effective
If previously promoted → now HELD:   upgrade has side effects

This is CCC's long-term regression test standard.
```

## IV.5 Phase Status

```
Phase 1  knowledge base                    complete
Phase 2  cognitive pipeline + sealed       complete (checkpoint-148)

         Six sealed principles:
         Anti-Information Contamination · Final Output Principle
         Anti-Topology Contamination · Topology Minimalism
         Projection Principle · Semantic Evolution Principle

Phase 3  continuous evolution              starting
         Order:
         ① F-data as RT-B03 (verify Pipeline runs without modification)
         ② Collect new relation labels from F-data
         ③ Apply topology classification
         ④ Close full pipeline to checkpoint
         ⑤ Rerun 24 HELD rows as Regression Test
```

## IV.6 Open Items

```
Promotion Backlog:
  16 PROMOTION_CANDIDATE rows — weight must be set per evidence-level
  guidance before promotion (DEFAULT 1.0 is not calibrated)

Semantic Mapping Required:
  11 ambiguous relation types awaiting owner classification decision
  (SEMANTIC_MAPPING_REQUIRED gate in staging)

Evidence Layer design:
  13 non-topology relation types currently in staging
  Must be housed in a proper Evidence Layer structure (Phase 3)

Future Modules:
  Evidence Layer · Semantic Mapping Module
  Automated confidence calibration · Automated succession indexing
```

## IV.7 Engineering State

```
Python:   ingest_v3.py · entity_upsert.py · sync_to_supabase.py
API:      Groq (llama-3.3-70b-versatile) primary
          OpenAI gpt-4o-mini secondary · Gemini tertiary
Supabase: W-side · ccc-lab.vercel.app
Git:      WilliamNeo1/cognitive-os · latest commits e04784c · a1c61bc
DB:       PostgreSQL 18 via Postgres.app (Q-side) · DBeaver 18
          Supabase SQL Editor (W-side)
```

---

# Final Statement

```
CCC V6.5 =
  Part I   CORE Constitution   (invariant)
  Part II  Cognitive Pipeline  (seven governance layers, stable)
  Part III Cross-layer Doctrines (evolving independently)
  Part IV  Evolution           (how the system grows)

CCC is a governed cognitive architecture.

It forms reliable judgment under constraint.
It does not claim certainty it does not have.
It does not collapse to zero under uncertainty.
It does not let architecture outrun reality.
It does not let cognition delay survival-critical action.

Cognition exists to improve action.
Action changes reality.
Reality determines survival.

稳定的架构。无限演化的智能。
Stable architecture. Evolving intelligence.

∞ ≠ 0
去伪存真，而不是去形存空。
```

---

## Document Status

```
File:       ccc_v6_5_outline.md
Replaces:   ccc_v6_1_outline.md · ccc_v6_1_outline_v2.md
Version:    V6.5 candidate / draft
Scope:      Four-part governed cognitive architecture
Based on:   checkpoint-148 · ADR-118 · commits e04784c · a1c61bc
Destination: docs/ccc_v6_1_outline/ccc_v6_5_outline.md
write_db:   NO
Checkpoint: TBD pending owner review
```
