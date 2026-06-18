# SQLV3 Graph Write Gate v0.1

checkpoint id=102 ✅ LOCKED

## 1. Purpose

Graph Write Gate is the L6 gatekeeper for writing into `clean_graph_edges`.

It does not decide absolute truth.
It decides whether a candidate relation is safe enough to become a graph edge.

In Chinese:

```text
Graph Write Gate 不裁定绝对真相。
它只决定一条候选关系是否足够安全，可以进入 clean_graph_edges。
```

Its primary purpose is to prevent claims, hypotheses, rumors, interpretations, and contaminated narratives from entering the accepted graph as facts.

---

## 2. Position in SQLV3

Graph Write Gate sits after:

```text
L0 Raw Intake
L1 Document Normalization
L2 Claim Extraction
L3 Event Anchoring
L4 Entity Governance
L5 Relation Candidate
```

and before:

```text
L7 Decision Consumption
P6 Prediction
P7 Final Decision
```

The flow is:

```text
raw_documents
→ documents
→ claims
→ events / event_candidates
→ entity governance
→ candidate_edges
→ graph_write_gate
→ clean_graph_edges
→ P6 / P7
```

---

## 3. Core Principle

```text
No relation enters clean_graph_edges merely because it appears in text.
```

A relation may be mentioned, asserted, rumored, interpreted, or hypothesized.
But only a relation that survives L6 can become a clean graph edge.

---

# 4. Candidate Edge Source Types

Each candidate edge must preserve its source object type.

```text
event_supported
claim_supported
hypothesis_based
rumor_based
interpretation_based
unknown_basis
```

## 4.1 event_supported

Definition:

```text
A candidate edge derived from an anchored event.
```

Example:

```text
X acquired Y.
A court issued notice against X.
Company A launched product B.
Entity X met Entity Y on date Z.
```

Possible result:

```text
may pass
```

But still requires entity stability and source traceability.

---

## 4.2 claim_supported

Definition:

```text
A candidate edge derived from a supported claim.
```

Example:

```text
A credible report claims Company A supplied components to Company B.
A direct_record-supported claim states Person X held position Y.
```

Possible result:

```text
conditional pass
```

A supported claim may propose a graph edge, but cannot bypass review.

---

## 4.3 hypothesis_based

Definition:

```text
A candidate edge derived from an explanatory model.
```

Example:

```text
2015股灾是某派系挑战习近平。
海外媒体报道是出口转内销。
某商业失败背后是政治清洗。
```

Result:

```text
forbidden as clean edge
```

Allowed destination:

```text
watch signal
behavioral model
entity profile note
decision context
```

---

## 4.4 rumor_based

Definition:

```text
A candidate edge derived from weak, circulating, unverified material.
```

Example:

```text
某人秘密逃亡海外。
某人拿到3亿分手费。
某人被秘密处决。
```

Result:

```text
forbidden as clean edge
```

Allowed destination:

```text
parked
watch
rumor log
claim layer
```

---

## 4.5 interpretation_based

Definition:

```text
A candidate edge derived from analytical judgment, commentary, value judgment, or narrative framing.
```

Example:

```text
雷军是不正经圈子里最正经的人。
工党背叛工人阶级。
Reform UK 抓住 common sense。
```

Result:

```text
forbidden as clean edge
```

Allowed destination:

```text
narrative layer
cognitive node
decision context
```

---

## 4.6 unknown_basis

Definition:

```text
A candidate edge whose source object type is unclear.
```

**Clarification (locked this round):**

`unknown_basis` is not a sixth cognitive object type alongside event/claim/hypothesis/rumor/interpretation.
The five types defined in SQLV3 Claims/Events/Hypothesis Boundary v0.1 remain exhaustive at the point of L2/L3 extraction.

`unknown_basis` exists purely as an **L6-side fault-tolerance label**: it fires when a candidate edge arrives at the gate without a correctly propagated `source_object_type` from upstream (L2/L3/L5) — i.e. upstream tagging was lost, missing, or malformed by the time the edge reaches L6.

```text
unknown_basis = upstream 没有正确传递认知对象类型标签，L6 无法判断这条候选边
                到底源自 event / claim / hypothesis / rumor / interpretation 中的哪一种。
                这不是第六种认知对象类型，而是 L6 用来接住"信息丢失"的容错机制。
```

Result:

```text
park
```

Rule:

```text
When uncertain, park rather than promote.
```

This also implies an upstream quality signal: a recurring high volume of `unknown_basis` edges indicates a tagging defect somewhere in L2–L5, not a property of the underlying material itself, and should be investigated as a pipeline issue rather than treated as a permanent edge category.

---

# 5. Gate Decisions

Graph Write Gate has five possible decisions:

```text
accepted
rejected
parked
watch
needs_review
```

## 5.1 accepted

Meaning:

```text
Safe enough to enter clean_graph_edges.
```

Requirements:

```text
source_object_type is event_supported or qualified claim_supported
entities are governed by L4
source chain is traceable
relation type is explicit
not hypothesis_based
not rumor_based
not interpretation_based
not contamination-confirmed
```

---

## 5.2 rejected

Meaning:

```text
Must not enter graph.
```

Use when:

```text
hypothesis presented as fact
rumor presented as fact
interpretation presented as event
fabricated citation
confirmed contamination
entity identity conflict unresolved
```

---

## 5.3 parked

Meaning:

```text
Not safe enough now, but may become useful later.
```

Use when:

```text
missing source chain
weak source
claim unresolved
time anchor missing
entity identity ambiguous
source is suspected but not confirmed contaminated
source_object_type is unknown_basis
```

---

## 5.4 watch

Meaning:

```text
Not graph fact, but useful warning signal.
```

Use when:

```text
hypothesis has strategic value
rumor is persistent
contamination pattern is recurring
claim appears repeatedly across sources
```

A watch item may influence P7 only as warning context, not accepted graph fact.

---

## 5.5 needs_review

Meaning:

```text
Requires human review before decision.
```

Use when:

```text
high-impact edge
politically sensitive edge
conflicting sources
direct_record content ambiguity
supported claim but not event-anchored
```

---

# 6. Minimum Admission Rules

A candidate edge may be accepted only if all of the following are true:

```text
1. subject_entity_id is governed
2. object_entity_id is governed
3. relation_type is explicit
4. source_object_type is allowed
5. source chain is traceable
6. no confirmed contamination
7. not rumor_based
8. not hypothesis_based
9. not interpretation_based
10. review_status permits promotion
```

Short rule:

```text
No governed entities, no graph.
No traceable source, no graph.
No allowed object type, no graph.
```

---

# 7. Hard Prohibitions

The following must never enter `clean_graph_edges` as accepted facts:

```text
hypothesis_based edge
rumor_based edge
interpretation_based edge
fabricated-source edge
confirmed-contamination edge
ungoverned-entity edge
unknown-basis edge
```

They may be stored elsewhere, but not in `clean_graph_edges`.

---

# 8. Claim-Supported Edge Rules

A claim-supported edge may be accepted only when:

```text
claim_status is supported
source_chain is traceable
at least one source is direct_record or strong reported_account
no source is fabricated
contamination_status is not confirmed
claim is concrete, not interpretive
entities are governed
human review or rule gate approves promotion
```

Claim-supported does not mean automatically accepted.

```text
supported claim → candidate edge
candidate edge → review gate
review gate → accepted / parked / watch / rejected
```

---

# 9. Event-Supported Edge Rules

An event-supported edge may be accepted when:

```text
event is anchored
event has time_anchor
event has actor / subject
event has action
event has traceable source
entities are governed
relation type is directly implied by the event
```

But an event does not automatically produce every possible relation.

Example:

```text
Court notice was published.
```

Allowed event:

```text
court published notice
```

Not automatically allowed:

```text
all claims inside notice are true
```

This preserves the Record vs Content boundary.

---

# 10. Source Hygiene Interaction

Graph Write Gate must read Source Hygiene outputs:

```text
source_layer
source_status
contamination_status
source_claim_links
source_chain
quoted_excerpt
```

Rules:

```text
source_layer alone never proves truth
direct_record does not bypass claim layer
reported_account requires chain review
narrative_layer cannot directly generate accepted edge
confirmed contamination blocks promotion
suspected contamination parks or sends to review
fabricated source rejects promotion
```

---

# 11. Claims / Events / Hypothesis Boundary Interaction

Graph Write Gate must preserve object type identity.

```text
event may produce candidate edge
supported claim may propose candidate edge
hypothesis may produce watch signal only
rumor may produce watch or parked item only
interpretation may produce narrative/cognitive context only
```

Boundary rule:

```text
No object may be promoted by changing its label.
```

For example:

```text
hypothesis_based edge
```

cannot be renamed as:

```text
claim_supported edge
```

just to pass the gate.

---

# 12. Suggested Future Tables

This document does not create DDL yet.

Future DDL may include:

```text
candidate_edges
graph_write_reviews
graph_write_rejections
graph_watch_signals
```

## 12.1 candidate_edges

Possible fields:

```text
id
subject_entity_id
object_entity_id
relation_type
source_object_type
source_object_id
basis_summary
candidate_status
created_from_layer
created_at
notes
```

Required field:

```text
source_object_type
```

Because L6 must know whether the edge came from:

```text
event
claim
hypothesis
rumor
interpretation
(or unknown_basis, if upstream tagging was lost — see Section 4.6)
```

Dependency note (locked this round):

```text
source_object_id will eventually need to reference claims.id or events.id
depending on source_object_type. The claims table does not exist yet
(SQLV3 Claims/Events/Hypothesis Boundary v0.1 is principle-only, no DDL).
This document remains principle-only for the same reason: candidate_edges
cannot be meaningfully built until claims table DDL exists.

When candidate_edges DDL is eventually created, source_object_id may
temporarily follow the same dependency-staging pattern used by Source
Hygiene's source_claim_links.claim_id: a bare field first, with foreign
key constraints added later via ALTER TABLE after claims/events
structures are stable. This document itself does not create
candidate_edges — it does not decide or pre-commit to that staging
pattern, only notes it as a precedent already established elsewhere
in SQLV3.
```

---

## 12.2 graph_write_reviews

Possible fields:

```text
id
candidate_edge_id
review_decision
review_reason
reviewed_by
reviewed_at
notes
```

---

## 12.3 graph_write_rejections

Possible fields:

```text
id
candidate_edge_id
rejection_reason
source_object_type
created_at
notes
```

---

## 12.4 graph_watch_signals

Possible fields:

```text
id
source_object_type
source_object_id
signal_type
signal_text
related_entity_id
priority
created_at
notes
```

**Boundary with `source_observations` (locked this round):**

`ccc.source_observations` (Source Hygiene v0.1) and `graph_watch_signals` (this document) are deliberately kept separate, not merged, even though both are "observation/monitoring" tables and may overlap in subject matter.

```text
source_observations 只管信源本身：
  这个 source 的状态变化、污染嫌疑/确认、虚假引用等，对象是 sources 表的一行。

graph_watch_signals 只管候选边/认知对象：
  一个 hypothesis 因为有战略价值被持续监控、一个 rumor 反复出现、
  一个 claim 跨多个来源重复出现，对象是 candidate_edges（或更上游的
  claim/hypothesis/rumor）本身，不是某一条具体的 source。
```

When the same underlying phenomenon could justify an entry in both tables (e.g. "a reported_account source repeatedly shows contamination patterns, AND the hypothesis it keeps feeding has strategic watch value"), both tables may independently record their own observation. There is no deduplication requirement and no foreign key linking the two — they answer different questions (source cleanliness vs. cognitive-object significance) and are allowed to describe the same real-world situation from their own perspective without needing to reconcile.

---

# 13. Decision Matrix

```text
event_supported edge
→ accepted / needs_review / parked

supported claim edge
→ needs_review / accepted with conditions / parked

hypothesis edge
→ rejected as graph edge / watch signal

rumor edge
→ rejected as graph edge / parked / watch

interpretation edge
→ rejected as graph edge / narrative context only

unknown basis
→ parked
```

---

# 14. Final Lock Statement

Graph Write Gate v0.1 defines the boundary between relation candidates and clean graph facts.

Its core rules:

```text
No hypothesis edge.
No rumor edge.
No interpretation edge.
No unsupported claim edge.
No confirmed-contamination edge.
No ungoverned-entity edge.
No unknown-basis edge (parked, not promoted, and treated as an upstream tagging signal — see 4.6).
```

Only event-supported or qualified claim-supported relations may pass into `clean_graph_edges`, and only after source traceability, entity governance, and contamination checks.

When uncertain:

```text
park rather than promote
```

This document is principle-only. No DDL is created in this round (see Section 12.1 dependency note). DDL for `candidate_edges` and related tables should follow only after the `claims` table itself is designed and built, consistent with the same dependency already noted in Source Hygiene v0.1's `source_claim_links.claim_id`.

---

# 15. Checkpoint Lock

```sql
INSERT INTO ccc.rsal_checkpoints (checkpoint_label, module, note)
VALUES (
  'sqlv3_graph_write_gate_v01_locked',
  'SQLV3 / Graph Write Gate',
  $note$SQLV3 Graph Write Gate v0.1 LOCKED. L6 gatekeeper principles defined for candidate relation promotion into clean_graph_edges. Core rule: no relation enters clean_graph_edges merely because it appears in text. Allowed basis: event_supported and qualified claim_supported only. Forbidden as clean graph facts: hypothesis_based, rumor_based, interpretation_based, fabricated-source, confirmed-contamination, ungoverned-entity, unknown_basis. unknown_basis is defined as an L6 fault-tolerance label for missing/malformed upstream source_object_type, not a sixth cognitive object type. Source Hygiene interaction defined: source_layer alone never proves truth, confirmed contamination blocks promotion, suspected contamination parks or requires review. source_observations and future graph_watch_signals are kept separate: source_observations observes source cleanliness; graph_watch_signals observes candidate edges/cognitive-object risk. This round is principle-only; no candidate_edges DDL is created until claims and event_candidates structures are stable.$note$
);
```

Verification:

```sql
SELECT id, checkpoint_label, module, note, created_at
FROM ccc.rsal_checkpoints
WHERE checkpoint_label = 'sqlv3_graph_write_gate_v01_locked'
ORDER BY id DESC
LIMIT 1;
```

