# ADR-117

## CCC V6 Chain Structure v0.1

**Status:** Accepted
**Date:** 2026-06-22
**Scope:** Architecture / naming / causality structure
**Implementation status:** Design accepted; DDL and code implementation pending future checkpoints

---

## Sealed Notes (Three Required Confirmations)

1. Driver Rank uses **D0-D5** from ADR-117 onward. Old P-prefixed references in prior checkpoints and ADRs remain historical and are not backfilled.

2. Action Priority **A0-A4** is accepted as the future-facing V6 naming standard. Existing P0-P4 code, enums, and database fields are not migrated in this phase. A naming cleanup checkpoint will be opened separately when R7 migration is scheduled.

3. **L0-L7 Operational Workflow** is accepted as architecture and design intent only. It is not implemented DDL or production-ready code. Future checkpoints are required for each L-stage implementation.

---

## Naming Firewall

Four prefix namespaces, non-overlapping:

| Prefix | Domain | Example |
|--------|--------|---------|
| `CORE` | Supreme constraint / world model | CORE Mission, CORE Principles |
| `L0–L7` | Data absorption workflow | L0 Raw Intake, L6 Graph Write Gate |
| `R0–R7` | Reasoning / RSAL functional layer | R5 Trust Topology, R7 Decision Engine |
| `D0–D5` | Driver Rank / causal height | D0 Root Power, D5 Event Symptom |
| `A0–A4` | Action Priority (R7 output) | A0 Critical, A4 No-Go |

Old records using `P0–P7` for Reasoning Layer and `P0–P4` for action priority remain valid as historical labels. They are not extended or reused for new concepts.

---

## CCC Language Policy v0.1

**Core rule:**

```
English for structure.
Chinese for explanation.
Bilingual for transmission.
```

**Three-layer language structure:**

| Layer | Language | Scope |
|-------|----------|-------|
| Canonical / Core | English only | ADR titles, DDL, SQL, API, enums, table names, field names, checkpoint titles, SVG canonical labels |
| Explanation | Chinese + English (paired) | ADR body, comments, maintenance docs, design notes |
| Public Transmission | Chinese-first or bilingual | Public-facing content, Chinese audience materials |

**Rules:**

1. Canonical system terms use English.
2. Chinese explanations are allowed and encouraged.
3. Database names, enum names, ADR titles, checkpoints use English first.
4. Public-facing explanations may use Chinese first.
5. Every important Chinese term must be bound to an English canonical term.
6. No uncontrolled mixed naming inside the same layer.
7. Public transmission layer must not reverse-pollute Core naming.

**Key bindings (canonical ↔ Chinese):**

```
CORE              — 核心宪法区，不是一层
Driver Chain      — 主驱动链
Claim             — 声称，不等于事实
Event             — 已锚定发生
Edge              — 图谱边
Source Hygiene    — 信源卫生
Feedback          — 反馈，不自动成为事实
Q Layer           — 主权判断核心
W Layer           — 公开展示与反馈界面
```

---

## Part 1 — CORE

### Definition

```
CORE is not a layer.
CORE governs all layers.
```

中文：CORE 不是一层。CORE 是整套系统的上位约束、世界模型和宪法核心。

CORE consists of four components only:

```
CORE
├─ Mission
├─ Primary Driver Chain
├─ Core Principles
└─ Forbidden Rules
```

### Mission

```
CCC exists to improve judgment, prediction, and action.
```

中文：CCC 的目标是提升判断、预测和行动，而不是堆积资料。

CCC is a cognitive exoskeleton, judgment organ, memory system, evidence review system, and action support system. The user is the source; CCC is the technical carrier.

### Primary Driver Chain

```
Power
↓
Resources
↓
Economy
↓
Technology
↓
Society
↓
Events
```

中文：权力决定资源配置；资源决定经济结构；经济决定科技能力；科技塑造社会形态；社会最终表现为事件。

**Core interpretive rule:**

```
Event is not the cause.
Event is the manifestation.
Driver is the cause.
```

Do not start from events as causes. Start from drivers.

### Core Principles

```
1.  CORE governs all layers, but is not itself a layer.
2.  Power is the upstream of resource allocation.
3.  Events are manifestations, not root causes.
4.  Every major analysis must trace upward toward power and resource allocation.
5.  Source is not truth.
6.  Record is not reality.
7.  Claim is not event.
8.  Hypothesis is not edge.
9.  W feedback is not Q fact.
10. CCC outputs decisions, not just records.
```

### Forbidden Rules

```
1.  Do not call CORE a layer.
2.  Do not number CORE as Layer 0.
3.  Do not allow W to automatically write back to Q.
4.  Do not let source automatically become truth.
5.  Do not let claim automatically upgrade to event.
6.  Do not let hypothesis automatically write into graph edge.
7.  Do not directly modify locked P5 / P6 / P7 core functions without a checkpoint.
8.  Do not replicate Q core judgment functions on the W side.
9.  Do not open unaudited graph write paths.
10. Do not use complex structures to replace clear boundaries.
```

---

## Part 2 — Global Architecture

```
CORE
↓ governs all
Q / W Sovereignty Boundary
↓
Operational Workflow (L0–L7)
↓
Reasoning / Decision Core (R0–R7)
↓
Q → W Publication Gate
↓
Feedback Absorption Gate
↓
Q Review Queue (human-approved only)
```

---

## Part 3 — Q / W Sovereignty Boundary

### Q Layer

```
Q = local PostgreSQL / ccc schema / sovereign judgment core
```

Q is the sole source of truth, judgment, and decision.

Q owns: `raw_documents`, `documents`, `sources`, `claims`, `events`, `entities`, `clean_graph_edges`, trust topology, prediction, decision, checkpoints.

```
Q sovereign. Q decides. Q owns judgment.
```

### W Layer

```
W = Supabase + Vercel / public search, display, feedback, public API
```

W is not the judgment core. W does not decide.

```
W exposed. W displays. W collects feedback. W does not decide.
```

### Data Flow Rules

Allowed:
```
Q → W
```

Forbidden:
```
W → Q automatic write-back
```

Correct feedback path:
```
W feedback
↓
feedback_raw / feedback_queue
↓
review
↓
candidate
↓
human-approved absorption
↓
Q
```

Forbidden path (permanent prohibition):
```
W feedback → Q fact
```

---

## Part 4 — Operational Workflow (L0–L7)

**Status: Design intent. Not implemented DDL. Future checkpoints required.**

```
L0 Raw Intake
↓
L1 Document Normalization
↓
L2 Claim Extraction
↓
L3 Event Anchoring
↓
L4 Entity Governance
↓
L5 Relation Candidate
↓
L6 Graph Write Gate
↓
L7 Decision Consumption
```

### Key boundaries per stage

**L0 Raw Intake** — accepts all input; does not generate entities, events, or edges; preserves source trace only.

**L1 Document Normalization** — format cleaning only. `Normalization is not verification.`

**L2 Claim Extraction** — all claims default `unverified`; claim ≠ event; claim ≠ fact; claim ≠ edge.

**L3 Event Anchoring** — records occurrence only; does not record interpretation or causation.

**L4 Entity Governance** — `entity_uuid` is immutable; source does not directly generate `entity_uuid`; mention ≠ clean entity.

**L5 Relation Candidate** — candidate relation ≠ graph edge; all relations enter candidate zone first.

**L6 Graph Write Gate** — `Absorption is a gate, not a pipeline.` Determines edge type, evidence grade, source chain, reversibility.

**L7 Decision Consumption** — outputs: decision, alert, forecast, action recommendation, risk boundary.

---

## Part 5 — Reasoning Layer (R0–R7)

Corresponds to old RSAL P0–P7. Renamed R0–R7 from ADR-117 onward for new documents.

| New | Old | Name |
|-----|-----|------|
| R0 | P0 | Clean Ontology |
| R1 | P1 | Typed Graph |
| R2 | P2/P2.5 | Timeline Reasoning |
| R3 | P3 | Essence Layer |
| R3.5 | P3.5 | Behavioral Model |
| R4 | P4 | Contradiction & Signal Layer |
| R5 | P5 | Rule / Trust Topology |
| R6 | P6 | Prediction Output |
| R7 | P7 | Decision Engine |

Old P-labels in historical checkpoints remain valid. They are not backfilled.

### R7 Decision Engine — Output Standard

```
final_status: DO | DO_WITH_CAUTION | WAIT | NO_GO
action_level: A0 | A1 | A2 | A3 | A4
```

Action Priority (A0–A4):

| Label | Meaning |
|-------|---------|
| A0 | Critical / Immediate |
| A1 | High |
| A2 | Caution |
| A3 | Wait |
| A4 | No-Go / Avoid |

Old P0–P4 action priority labels in existing code/enums are not renamed in this phase.

---

## Part 6 — Driver Rank (D0–D5)

Causal height classification. Not to be confused with Reasoning Layer (R) or Action Priority (A).

| Label | Name | 中文 |
|-------|------|------|
| D0 | Root Power | 根驱动力：权力结构、统治集团、制度安排 |
| D1 | Resource Allocator | 配置机制：财政、税收、土地、能源、信贷 |
| D2 | Economic Structure | 生产系统：产业、贸易、劳动力、市场规模 |
| D3 | Technology / Capability System | 能力系统：科技、工程、教育、军工 |
| D4 | Social Mechanism | 社会机制：舆论、文化、人口、社会运动 |
| D5 | Event / Symptom | 表现层：新闻事件、社会问题、价格变化 |

**Causality Trace Rule:**

For every major event, CCC must trace causality upward through at least three layers and identify the resource allocation mechanism and the power structure behind it.

```
If analysis stops at D5, it is incomplete.
If analysis avoids D0, it is structurally incomplete.
```

Analysis template:
```
D5 Event Layer:        What happened on the surface?
D4 Society Layer:      What social phenomenon does it reflect?
D3 Capability Layer:   What technology / organization / capability is involved?
D2 Economy Layer:      What economic structure / cost structure underlies it?
D1 Resource Layer:     Who gets resources? Who loses them?
D0 Power Layer:        Who decides the allocation? Who benefits? Who maintains the structure?
```

---

## Part 7 — Source Hygiene

Source Hygiene prevents contamination from entering Q. It does not determine world truth.

### source_layer (replaces source_type to avoid collision)

```
direct_record    — 直接记录层
reported_account — 转述报道层
narrative_layer  — 叙事加工层
```

`source_layer` describes distance from reality only. It does not directly equal trustworthiness.

### Contamination status machine

```
clean → suspected → confirmed → rejected
```

`confirmed` requires a `confirmed_observation`. Timestamp or source name alone is insufficient.

### Claim / Event / Hypothesis boundary

| Object | Definition | Can become event? |
|--------|-----------|-------------------|
| `event` | Anchored occurrence | — (is already event) |
| `claim` | Someone says something | Yes, with: direct record + cross-source + time/location anchoring + entity verification + source hygiene pass |
| `hypothesis` | Possible explanation | No, unless contains verifiable occurrence |
| `rumor` | Unverified circulating claim | Must be claim-ified first |
| `interpretation` | Meaning assigned to event | Forbidden — cannot replace event |

---

## Part 8 — Feedback Absorption

```
Disagreement is not noise.
Disagreement is diagnostic input.
```

中文：分歧不是噪音。分歧是诊断输入。

This principle is placed in footer / side note, not in CORE body. It is an operational principle, not a Primary Driver Chain item.

### Feedback path

```
W feedback
↓
feedback_raw → feedback_classification
↓
review_queue
↓
candidate_update
↓
human approval
↓
Q absorption
```

### Forbidden feedback paths

```
feedback → Q fact                  FORBIDDEN
feedback → clean_graph_edges       FORBIDDEN
feedback → decision overwrite      FORBIDDEN
feedback → source truth            FORBIDDEN
```

---

## Part 9 — Sealed Checkpoint Reference

Modules locked prior to ADR-117:

```
id=98   Constitution v1                    LOCKED
id=99   Data Layer v0.1                    LOCKED
id=100  Source Hygiene v0.1                LOCKED
id=107  Feedback Absorption v0.1           LOCKED  (checkpoint-107)
id=110  Edge Identity Design v0.1          LOCKED  (checkpoint-110)
id=113  Edge Identity DDL & Backfill v0.1  LOCKED  (checkpoint-113)
id=115  Edge Endpoint Ingest Write Path    LOCKED  (checkpoint-115, commit cc07d9d)
id=116  W Schema & Sync Alignment v0.1     LOCKED  (checkpoint-116, commit 8a3413b)
ADR-116 W Layer Re-definition v0.1         ACCEPTED
```

---

## Closing Statement

```
CORE governs all layers.
Information Intake remains the operational starting point.
Q remains the sovereign judgment core.
W remains the exposed public interface.
Feedback is diagnostic input, not automatic truth.
Decision is the final output, not data storage.
```

中文：
```
CORE 统摄全局，但不是一层。
信息搜集仍然是操作流程的起点。
Q 仍然是主权判断核心。
W 仍然是公开展示与反馈界面。
反馈是诊断输入，不是自动事实。
决策才是最终输出，而不是资料堆积。
```

One-line summary:

```
CCC V6 = CORE-governed, Q-sovereign, driver-centered strategic causality system.
```
