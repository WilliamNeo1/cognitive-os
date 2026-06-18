# SQLV3 Feedback Absorption Protocol v0.1

checkpoint id=103 ✅ LOCKED

## 1. Purpose

Feedback Absorption Protocol defines the W → Q boundary: it governs whether and how external feedback, uploads, comments, corrections, or submissions may enter Q's truth layers.

It does not decide what feedback is correct or useful.
It decides whether feedback may enter at all, and if so, where it must land.

In Chinese:

```text
Feedback Absorption Protocol 不裁定反馈内容是否正确或有价值。
它只决定外部反馈能否进入 Q，以及如果可以进入，必须落在哪一层。
```

Its primary purpose is to prevent W-side feedback — regardless of source, intent, or apparent credibility — from automatically writing into Q's truth layers (claims, events, entities, clean_graph_edges).

---

## 2. Position in SQLV3

This protocol sits conceptually upstream of L0 Raw Intake, as a gate that decides what is even allowed to become `raw_documents` in the first place — or whether it must be quarantined in a separate feedback-only staging area before ever touching Q's absorption pipeline.

```text
external input
→ Feedback Absorption Gate  ← this document
→ (if Q-internal)    raw_documents → L0–L7 as normal
→ (if W feedback)     feedback_candidates / feedback_raw / review_queue
                       (never directly into raw_documents, claims, events,
                       entities, or clean_graph_edges)
```

This is distinct from Source Hygiene and Graph Write Gate. Source Hygiene governs the cleanliness of a source once it is already inside Q's pipeline. Graph Write Gate governs promotion from candidate relation to clean graph edge. Feedback Absorption governs something earlier and more fundamental: whether external input is permitted to enter the pipeline at all, and under what label.

```text
Feedback Absorption:
  外部输入能不能进来？进来后必须标记什么来源？

Source Hygiene:
  已经在管线里的信源，链路干不干净？

Graph Write Gate:
  候选关系能不能写入 clean_graph_edges？
```

---

## 3. Core Principle

```text
W cannot write Q.
```

More precisely:

```text
External feedback may be observed, recorded, and considered.
External feedback may never automatically become Q truth.
```

This is a direct extension of the sovereignty principle already locked in SQLV3 Constitution v1: CCC is a sovereign think tank, and Q's truth layers must not be contaminated by W-side rewriting.

---

## 4. What Counts as "W Feedback"

This protocol does not distinguish between feedback channels by mechanism. All of the following are treated identically under this protocol, regardless of how they technically arrive:

```text
human-submitted corrections or comments (typed or pasted by a person
  other than the Q operator, or even by the Q operator on behalf of
  a third party)
automated scraping or API ingestion of external commentary
  (forum posts, social media replies, etc.)
future W-side submission forms or portals (not yet built, but must
  be assumed in scope)
```

```text
不区分渠道。人工输入的纠错评论、脚本/API自动抓取的外部评论、
未来可能出现的W端提交表单——这三种在本协议下一视同仁，
只要数据来源不是 Q 自身控制下产生的原始材料，就属于 W feedback。
```

The distinguishing question is not "how did this arrive technically" but:

```text
Was this content produced or selected by Q's own controlled process
(Q operator curating primary sources, Q's own ingestion of court
records / financial filings / direct_record material), or did it
originate from outside that controlled process and merely arrive
through some technical channel?
```

If the latter, it is W feedback, regardless of channel.

---

## 5. Input Origin Classification

Every piece of input entering the system must be classifiable as one of:

```text
q_internal        — Q operator's own curated primary material
                     (e.g. direct_record documents Q chose to ingest,
                     Q's own research notes, Q's own structured data)
w_feedback         — any content originating outside Q's controlled
                     curation process: corrections, comments, external
                     submissions, scraped reactions, third-party
                     annotations
unknown_origin     — input whose origin cannot currently be determined
                     because the ingestion path does not preserve it
```

```text
Rule: when input_origin cannot be determined, it must be treated as
w_feedback, not as q_internal. Defaulting to the more permissive
category when uncertain is the exact failure mode this protocol exists
to prevent.
```

不确定时默认归为 w_feedback，绝不默认归为 q_internal。这是本协议存在的核心理由：宁可保守地多隔离一些，也不能因为"看起来像Q自己的材料"就放行。

---

## 6. Absorption Destinations

```text
q_internal    → may proceed through normal L0 Raw Intake and onward
                (still subject to Source Hygiene, Claims/Events/Hypothesis
                Boundary, and Graph Write Gate as already locked)

w_feedback    → must land in a feedback-only staging area, never directly
                in raw_documents, claims, events, entities, or
                clean_graph_edges. Possible destinations:
                  feedback_candidates
                  feedback_raw
                  review_queue (existing concept, reused from
                  Entity Governance — type_conflict/unresolved_reference
                  already use this pattern)

unknown_origin → must be treated as w_feedback (see Section 5) and
                routed identically
```

```text
Short rule:
No w_feedback enters Q truth layers directly.
No unknown_origin enters Q truth layers directly.
Only q_internal may proceed through the normal pipeline.
```

---

## 7. Promotion Path (W Feedback → Q, If Ever)

W feedback is not permanently barred from ever influencing Q. But promotion must go through explicit, human-reviewed steps — it cannot happen automatically, and it cannot skip layers.

```text
w_feedback
→ feedback_candidates (or feedback_raw)
→ human review
→ (if approved) re-classified as q_internal-equivalent material,
   then enters L0 Raw Intake as if it were freshly curated by Q
→ from there it is subject to all normal layers: Source Hygiene,
  Claims/Events/Hypothesis Boundary, Graph Write Gate
```

```text
Rule: promotion requires a human decision to re-curate, not an automatic
pipeline transition. The act of "Q choosing to treat this external
material as worth ingesting" is itself the q_internal-making event —
W feedback does not become Q truth by sitting in a queue long enough
or by accumulating volume.
```

This mirrors a rule already locked in Source Hygiene v0.1: contamination_status can only move to confirmed via explicit human confirmation, never automatically. The same discipline applies here: w_feedback → q_internal reclassification requires the same kind of explicit, attributable human action, not silent pipeline drift.

---

## 8. Interaction with Existing Ingest Scripts

This is the most operationally important section of this document.

```text
scripts/ingest_v3.py
scripts/ingest_real_history.py
scripts/ingest_batch.py
```

were inspected as part of locking this protocol. None of them currently carry an explicit `input_origin` field, parameter, or routing mechanism that distinguishes Q-controlled material from W feedback.

```text
ingest_v3.py:        accepts --json or --image, no origin parameter
ingest_real_history.py:  reads from ccc.raw_documents WHERE source LIKE
                      'REAL_HISTORY/%' — this is a source-string filter
                      specific to this script's own use case, not a
                      general-purpose origin classification mechanism
ingest_batch.py:      pure batch wrapper around ingest_v3.py, inherits
                      the same gap
```

This is not evidence that W feedback has already contaminated Q. It is evidence that the architecture currently has no mechanism to prevent it, should W feedback ever be passed through these scripts.

```text
Locked judgment:

No existing ingest script is W-feedback-safe by default.

These scripts may continue to be used for q_internal input (Q operator
curating and feeding in primary material they have personally selected).

These scripts must NOT be used to ingest:
  external user-submitted material
  scraped external commentary
  any future W-side submission form output
unless and until they are modified to carry an explicit input_origin
tag and route non-q_internal input to feedback_candidates / review_queue
instead of raw_documents.
```

This document does not modify these scripts in this round. It records the current gap as a known risk and a precondition for any future use of these scripts with non-Q-curated input.

---

## 9. Relationship to Entity Governance's review_queue

SQLV3's existing Entity Governance layer (D.5.1) already has a `entity_review_queue` for type_conflict and unresolved_reference cases. This protocol does not replace or duplicate that table.

```text
entity_review_queue:  already-governed entities whose CLAIMED identity
                       conflicts with existing records (a Q-internal
                       data quality problem)

feedback_candidates / feedback_raw (this protocol):
                       content whose ORIGIN is external to Q's
                       controlled curation (a provenance/sovereignty
                       problem)
```

These are different problems that happen to use a similar "park for human review" pattern. They are not merged into one table. An entity mention inside a piece of w_feedback content, if that feedback is ever promoted, would still go through normal entity_review_queue logic at that point — the two layers operate independently and in sequence, not as substitutes for each other.

---

## 10. Hard Prohibitions

The following must never happen:

```text
W feedback written directly into raw_documents
W feedback written directly into claims
W feedback written directly into events
W feedback written directly into clean_entities / entity_uuid
W feedback written directly into clean_graph_edges
unknown_origin input defaulting to q_internal treatment
automatic promotion from feedback_candidates to Q truth layers
  without an explicit human re-curation decision
```

---

## 11. Minimum Admission Rules for Future feedback_candidates / feedback_raw Tables

This document does not create DDL in this round. If and when such tables are designed, they must satisfy:

```text
1. input_origin is recorded and immutable once set
2. raw content is preserved unmodified (same principle as L0 Raw Intake:
   no judgment, no interpretation, but quarantine/flagging permitted)
3. no automatic write path exists from these tables into claims,
   events, entities, or clean_graph_edges
4. promotion to q_internal-equivalent status requires a recorded human
   decision (who, when, why) — same discipline as Source Hygiene's
   confirmed_contamination_observation_id pointer pattern
5. these tables may reference entities for context, but must not
   create or mutate entity_uuid directly (same boundary already
   locked in Source Hygiene v0.1 Section 2 of its boundary declarations)
```

---

## 12. Final Lock Statement

Feedback Absorption Protocol v0.1 defines the W → Q sovereignty boundary.

Its core rules:

```text
W cannot write Q.
No w_feedback enters Q truth layers directly.
No unknown_origin defaults to q_internal.
Promotion from feedback to Q truth requires explicit human re-curation,
  never automatic pipeline transition.
No existing ingest script is W-feedback-safe by default.
```

This document is principle-only. No DDL is created in this round. No existing ingest scripts are modified in this round — the gap identified in Section 8 is recorded as a known risk, not yet remediated.

When in doubt about origin:

```text
treat as w_feedback, not q_internal
```

---

## 13. Checkpoint Lock

```sql
INSERT INTO ccc.rsal_checkpoints (checkpoint_label, module, note)
VALUES (
  'sqlv3_feedback_absorption_v01_locked',
  'SQLV3 / Feedback Absorption',
  $note$SQLV3 Feedback Absorption Protocol v0.1 LOCKED. Defines the W to Q sovereignty boundary: external feedback, uploads, comments, corrections, or submissions must not automatically write into Q truth layers (raw_documents, claims, events, entities, clean_graph_edges), regardless of channel (manual input, automated scraping, future submission forms - all treated identically). Input origin classified as q_internal, w_feedback, or unknown_origin, with unknown_origin defaulting to w_feedback treatment, never q_internal. W feedback may only land in feedback_candidates/feedback_raw/review_queue staging areas. Promotion to Q truth requires explicit recorded human re-curation decision, never automatic pipeline transition, mirroring the human-confirmation discipline already locked in Source Hygiene v0.1's contamination_status mechanism. Inspected existing ingest scripts (ingest_v3.py, ingest_real_history.py, ingest_batch.py) and found none carry explicit input_origin tagging; locked judgment is that no existing ingest script is W-feedback-safe by default and must not be used for non-Q-curated input until modified. This round is principle-only; no DDL created, no existing scripts modified.$note$
);
```

Verification:

```sql
SELECT id, checkpoint_label, module, note, created_at
FROM ccc.rsal_checkpoints
WHERE checkpoint_label = 'sqlv3_feedback_absorption_v01_locked'
ORDER BY id DESC
LIMIT 1;
```
