# SQLV3 Phase 2 — Feedback Absorption v0.1

**Status:** design locked
**Depends on:** CCC Foundation Architecture v1 (checkpoint id=106)
**Scope:** principles + field-level draft only. No tables created. No SQL executed. No changes to `sync_to_supabase.py`.

---

## 0. Core Definition

> Feedback Absorption v0.1 does not let W modify Q. It only preserves W-generated
> modification intent as traceable, isolated, non-auto-accepted claims for later
> Q-side human or explicitly approved script review.

中文：
> Feedback Absorption v0.1 的目标不是让 W 修改 Q，而是让 W 产生的所有修改意图，
> 以可追溯、可隔离、不可自动采纳的 claim 形式安全落地，等待 Q 侧人工审核或
> 显式批准脚本处理。

---

## 1. Q/W Authority Boundary

```
Q = source of truth
W = read-only mirror + feedback collection endpoint

Q → W = sync          (existing sync_to_supabase.py)
W → Q = feedback collection  (this design; NOT a reverse sync)
```

These two directions are semantically different, use different scripts, and have
different permissions. They must never be merged into a single bidirectional sync.

---

## 2. Identity Anchor: entity_uuid

```
entity_uuid     -- stable identity layer across environments, syncs, and versions
id              -- local database implementation detail only; never used as anchor
canonical_slug  -- renameable, unreliable; never used as anchor
```

Edge identity is a known gap (see Section 7) and is explicitly out of scope for v0.1.

---

## 3. Ontology of Feedback

```
Feedback is not a mutation. Feedback is a claim about a possible mutation.

反馈 ≠ 变更
反馈 = 带来源、带置信度、带目标对象的候选声明
```

`feedback_confidence` (confidence in the feedback itself) and
`target_claim_confidence` (confidence of the thing being targeted, lives in Q)
are strictly separate and never share a field.

---

## 4. Immutability Principle

```
feedback object content      -- write-once, never UPDATEd
review event stream           -- append-only, represents state transitions
```

A feedback object's "current status" is derived by querying its review_event
history ordered by time — never stored as a directly-overwritable status field
on the feedback object itself.

---

## 5. Explicitly Out of Scope for v0.1

```
- No automatic write-back to Q
- No entity dedup / merge logic
- No confidence_score back-propagation algorithm
- No review UI / automated review rules
```

---

## 6. Field-Level Draft

### 6.1 feedback object (candidate claim layer)

| field | notes |
|---|---|
| `feedback_id` | immutable UUID |
| `target_kind` | v0.1 default `ENTITY`; reserved for future `EDGE` / `CLAIM` / `SOURCE` |
| `target_entity_uuid` | required when `target_kind = ENTITY`; NULL for `ADDITION` |
| `anchor_status` | `resolved` / `unresolved` / `not_applicable` |
| `feedback_type` | `CORRECTION` / `ADDITION` / `CHALLENGE` / `DUPLICATE` |
| `proposed_payload` | JSON/JSONB; claim content container, NOT a patch/diff/mutation instruction |
| `feedback_confidence` | 0.15–0.95; confidence of the feedback itself |
| `source_type` | origin classification (human_annotation / model_inference / external_signal, TBD) |
| `submitted_by` | submitting actor identifier |
| `submitted_from` | v0.1: always `W` |
| `created_at` | timestamp; also serves as the implicit "created" event (no separate `created` review_event) |

Explicitly excluded fields (would push v0.1 toward write-back):
`apply_to_q`, `auto_update`, `merged_entity_id`, `new_confidence_score`.

### 6.2 review event (review event layer)

| field | notes |
|---|---|
| `review_event_id` | event identifier |
| `feedback_id` | read-only reference to the immutable feedback object |
| `event_type` | `under_review` / `accepted` / `rejected` / `deferred` / `revoked` |
| `actor` | human reviewer or explicit approval script identifier |
| `note` | uses existing `$note$...$note$` dollar-quoting convention; no raw single quotes |
| `created_at` | event timestamp |

`accepted` marks a review conclusion only — it never triggers automatic write-back
to Q. `revoked` exists to record that an accepted conclusion was later withdrawn;
it does not undo any change in Q, since v0.1 never wrote one in the first place.

---

## 7. Target Anchor Rules

**CORRECTION / CHALLENGE**
`target_entity_uuid` required, must reference an existing `entity_uuid` in
`clean_entities` at write time when possible. If unresolved at write time, the
object is still written, with `anchor_status = unresolved`.

> Anchor resolution failure does not invalidate the feedback object. It only
> means the feedback cannot currently be stably bound to an existing object in Q.

**ADDITION**
`target_entity_uuid = NULL`, `anchor_status = not_applicable`. The proposed
entity description lives entirely in `proposed_payload`. No UUID is fabricated.

**DUPLICATE**
`target_entity_uuid` is the flagged primary target only.

> DUPLICATE is a suspicion marker, not a merge instruction.

The suspected-duplicate counterpart entity is described inside `proposed_payload`.
No merge direction, no designation of which entity is retained or removed, is
implied or recorded in v0.1.

---

## 8. feedback_type — Minimal Enum

```
CORRECTION   -- proposed correction to an existing entity's attributes
ADDITION     -- proposed new entity (target_entity_uuid = NULL)
CHALLENGE    -- challenge to an existing claim/source's credibility
DUPLICATE    -- suspected duplicate entity flag (flag only, no merge)
```

No `OTHER` catch-all. New feedback types may only be introduced via an explicit
version upgrade of this design (e.g. v0.2), never added ad hoc.

---

## 9. Edge Identity Gap

```
Current state: clean_graph_edges has no entity_uuid-equivalent immutable identity field.
Impact:        edges cannot be referenced by a stable anchor.
v0.1 handling: edge-related feedback is downgraded to CHALLENGE;
               proposed_payload free-text describes the two entity_uuids
               and relation_type involved. No structured edge anchor is created.

Deferred (not in scope):
  edge_uuid or edge_fingerprint design.
  A naive fingerprint of (source_entity_uuid + target_entity_uuid + relation_type)
  is risky if relation_type is later renamed/normalized/split — this risk is
  recorded here for future phases to resolve, not decided now.
```

---

## 10. Summary of Locked Constraints

```
1. proposed_payload is a claim content container, not an executable mutation instruction.
2. Anchor resolution failure does not invalidate the feedback object.
3. DUPLICATE is a suspicion marker, not a merge instruction.
4. New feedback_type values require an explicit version upgrade; no OTHER fallback.
5. accepted != automatic write-back to Q. Write-back, if it ever happens, is a
   separate, later-phase, human or explicitly-approved-script action.
6. Q→W sync and W→Q feedback collection are permanently distinct pipelines.
```
