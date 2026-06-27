# ADR-118: CCC V6 Calibration Amendment v0.1

## Status

```
draft
```

## Date

```
2026-06-27
```

## Scope

```
CCC V6 Amendment — not V7, not a major version rewrite.
V6 canonical architecture (checkpoint-118, ADR-116, ADR-117 + Amendment 01) remains sealed.
```

---

## Context

CCC V6 was sealed at checkpoint-118 under ADR-116 (W Layer Re-definition) and ADR-117 + Amendment 01 (CCC V6 Chain Structure / CORE Epistemic Boundary).

At that point, V6 established:

1. CORE (not a layer; governs all layers)
2. Q / W Sovereignty Boundary
3. Source Hygiene
4. Claim / Event / Hypothesis / Edge Boundary
5. Prediction / Decision Separation
6. Action Boundary
7. Language Policy v0.1
8. Checkpoint / ADR / Commit Discipline

V6 upgraded CCC from an information system to a driver-recognition system.

After checkpoint-118, Reality Test Phase began. During architecture review and early batch preparation, three structural gaps were identified that V6 did not yet formally govern:

**Gap 1 — Hallucination Risk**
No formal protocol prevented Inference from being treated as Fact, or Prediction from being treated as Decision. The boundary existed in principle but was not operationally enforced across all layers.

**Gap 2 — Core Dissolution Risk (Onion-Peeling Paradox)**
The system correctly defined what CORE is not, but lacked a positive definition of what CCC must irreducibly preserve. Repeated negation without a positive anchor risked dissolving operational capacity.

**Gap 3 — Logical Shutdown Risk**
No explicit principle prevented the system from collapsing to zero output under uncertainty. High uncertainty + no action doctrine = system paralysis, which is a failure mode distinct from deliberate NO_GO decisions.

---

## Decision

Integrate three calibration mechanisms into CCC V6 CORE as a partial amendment.

This amendment does not replace or renumber any existing ADR.
This amendment extends V6 without triggering a major version increment.

The three mechanisms are:

### Mechanism 1: Four-Level Calibration Framework

All major events, judgments, disputes, predictions, and decisions must distinguish, as far as possible:

| Level              | Definition                                         |
| ------------------ | -------------------------------------------------- |
| Fact               | Directly supported by evidence                     |
| Inference          | Reasonably derived from facts                      |
| Not Established    | Currently neither proven nor disproven             |
| Operational Impact | Practical meaning for case, decision, or CCC       |

Core principle:

```
Rigor is not the pursuit of absolute correctness.
Rigor is the systematic reduction of false positives and false negatives.
```

Governs: all seven operational layers, all batch outputs, all public outputs.
Not a new layer. Not a replacement for Information Intake.

### Mechanism 2: Irreducible Core

CCC must preserve five non-negotiable operational elements regardless of conceptual refinement:

```
CCC Irreducible Core
├─ Source    — user as origin; without source, CCC loses direction
├─ Judgment  — capacity to form judgment; without it, CCC is only data
├─ Memory    — capacity to store replayable structure; without it, CCC cannot accumulate
├─ Boundary  — capacity to distinguish fact/inference/unknown/action; without it, CCC hallucinates
└─ Action    — capacity to support real-world action; without it, CCC enters logical shutdown
```

Positive definition:

```
CCC Core is not emptiness.
CCC Core is the operational capacity to preserve memory, calibrate judgment,
maintain boundaries, and support action around the user as source.
```

Governs: CORE identity; prevents core dissolution through endless negation.

### Mechanism 3: Non-Zero Action Doctrine

```
∞ ≠ 0

Infinite uncertainty does not justify zero operational output.
```

CCC must always produce a constrained operational state. Allowed states include:

```
Positive:  DO · DO_WITH_CAUTION · WAIT · WATCH · NO_GO · REVIEW_REQUIRED
           NEGOTIATE · BUILD · COOPERATE · REPAIR · PUBLISH · FILE · DOCUMENT · ESCALATE

Counter:   REFUSE · EXIT · DEFEND · HEDGE · RESIST · EXPOSE · CHALLENGE_LEGALLY · ISOLATE_RISK
```

Governs: all Decision outputs; prevents logical shutdown under uncertainty.

---

## Updated CORE Structure

```
CORE
├─ Mission
├─ Primary Driver Chain
├─ Core Principles          (updated: 26 items)
├─ Four-Level Calibration Framework   ← ADR-118
├─ Irreducible Core                   ← ADR-118
├─ Non-Zero Action Doctrine           ← ADR-118
└─ Forbidden Rules          (updated: 26 items)
```

> CORE is not a layer. CORE governs all layers.

---

## Anti-Failure Map

| Failure Risk           | Failure Mode                 | CCC Countermeasure          |
| ---------------------- | ---------------------------- | --------------------------- |
| Hallucination Risk     | Inference becomes fact       | Four-Level Calibration      |
| Core Dissolution Risk  | Core pursuit becomes void    | Irreducible Core            |
| Logical Shutdown Risk  | Uncertainty returns zero     | Non-Zero Action Doctrine    |
| Contamination Risk     | W feedback pollutes Q        | Q/W Sovereignty Boundary    |
| Overaction Risk        | Prediction becomes command   | Prediction / Decision Split |
| Fragility Risk         | Action exceeds survivability | Action Boundary             |

---

## Updated Core Principles (full list)

1. CORE governs all layers, but is not itself a layer.
2. CORE must remain operationally positive.
3. CCC Core is not emptiness.
4. CCC must preserve Source, Judgment, Memory, Boundary, and Action.
5. Power is the upstream of resource allocation.
6. Events are manifestations, not root causes.
7. Every major analysis must trace upward toward power and resource allocation.
8. Source is not truth.
9. Record is not reality.
10. Claim is not event.
11. Hypothesis is not edge.
12. Correlation is not causation.
13. Prediction is not decision.
14. Decision is not guaranteed truth.
15. Public feedback is not Q fact.
16. Calibration is required before judgment.
17. Rigor means reducing false positives and false negatives.
18. Incomplete information creates tolerable error, not false certainty.
19. Unknown risk must be survivable before action.
20. Caution must not become paralysis.
21. CCC must always preserve a non-zero operational output.
22. Conceptual purity must not destroy system viability.
23. High-leverage nodes must not become single-point dependency.
24. No inspection, no formal ID.
25. No confirmation, no write command.
26. No evidence, no canonical label.

---

## Updated Forbidden Rules (full list)

1. Do not call CORE a layer.
2. Do not number CORE as Layer 0.
3. Do not replace Information Intake with CORE.
4. Do not allow W to automatically write back to Q.
5. Do not let source automatically become truth.
6. Do not let record automatically become reality.
7. Do not let claim automatically become event.
8. Do not let hypothesis automatically become edge.
9. Do not let correlation automatically become causation.
10. Do not let prediction automatically become decision.
11. Do not treat public feedback as Q fact.
12. Do not directly modify locked core functions without checkpoint.
13. Do not replace clear boundaries with complex structures.
14. Do not present CCC decisions as guaranteed truth.
15. Do not act when unknown risks exceed survivable boundaries.
16. Do not allow any goal to depend on a single node.
17. Do not mix Fact, Inference, Not Established, and Operational Impact.
18. Do not dissolve CORE into pure negation or operational emptiness.
19. Do not confuse conceptual purity with system viability.
20. Do not let uncertainty collapse the system into inaction.
21. Do not confuse caution with paralysis.
22. Do not allow endless negation to erase operational agency.
23. Do not interpret every conceptual breakthrough as a major version jump.
24. Do not assign ADR numbers, checkpoint IDs, or formal labels without inspection.
25. Do not provide write commands before confirmation.
26. Do not create canonical labels without evidence.

---

## Downstream Impact

### Reality Test Batch Protocol
- Four-Level Calibration output (Fact / Inference / Not Established / Operational Impact) is now required at every step: Source → Claim → Event → Entity → Edge → Driver Chain → Prediction → Decision → Public Output.
- Every batch must produce a non-zero constrained operational state.

### Review Checklist
- Extended from 13 to 30 items.
- New items cover: calibration separation, false positive/negative identification, logical shutdown avoidance, non-zero output preservation.

### Reality Test Scorecard
- Extended from 10 items (/50) to 16 items (/80).
- New items: Fact/Inference Separation, Uncertainty Handling, Operational Impact Clarity, False Positive/Negative Control, Core Preservation, Non-Zero Action Output.
- Pass threshold: ≥ 60/80.

### Checkpoint Fields
New fields added to checkpoint records:
```
calibration_status
fact_count
inference_count
not_established_items
operational_impacts
false_positive_risks
false_negative_risks
core_preservation_notes
non_zero_action_output
logical_shutdown_risk
```

New checkpoint status value added:
```
calibrated
```

### Staging Flow
New step added:
```
... → calibration check → non-zero action check → manual review → ...
```

---

## Final System Formula

```
CORE                      = Constitution
Primary Driver Chain      = World-operation axis
Seven Layers              = Operational workflow
Q/W Boundary              = Sovereignty boundary
Four-Level Calibration    = Error-control system        ← ADR-118
Irreducible Core          = Anti-dissolution anchor     ← ADR-118
Non-Zero Action Doctrine  = Anti-paralysis output rule  ← ADR-118
Action Boundary           = Risk boundary
Checkpoint / ADR / Commit = Closure discipline
```

中文：

```
CORE                     = 宪法
Primary Driver Chain     = 世界运行主轴
Seven Layers             = 操作流程
Q/W Boundary             = 主权边界
Four-Level Calibration   = 误判控制系统        ← ADR-118
Irreducible Core         = 防核心溶解锚点      ← ADR-118
Non-Zero Action Doctrine = 防瘫痪行动输出规则  ← ADR-118
Action Boundary          = 行动风险边界
Checkpoint/ADR/Commit    = 封板纪律
```

---

## What This ADR Does Not Change

```
V6 version label              — unchanged (this is an amendment, not V7)
checkpoint-118 seal           — unchanged
ADR-116 W Layer definition    — unchanged
ADR-117 Chain Structure       — unchanged
ADR-117 Amendment 01          — unchanged
Seven-layer operational flow  — unchanged
Q/W sovereignty boundary      — unchanged
Naming Firewall               — unchanged
Language Policy v0.1          — unchanged
```

---

## Consequences

**Positive:**
- Hallucination risk reduced via mandatory four-level calibration at all output points.
- Core dissolution risk reduced via explicit irreducible core definition.
- Logical shutdown risk reduced and explicitly controlled via non-zero action doctrine.
- All six identified failure modes now have a named countermeasure.
- Reality Test Phase now has a complete calibration protocol.

**Accepted tradeoffs:**
- Every batch output requires additional calibration annotation work.
- Scorecard scoring ceiling raised to /80; existing batch benchmarks do not apply retroactively.

**Known gaps remaining:**
- Four-Level Calibration is not yet reflected in DB schema (no new columns in this amendment; schema changes deferred to a future batch-level implementation decision).
- `calibration_status` and related checkpoint fields are defined here but not yet inserted into production checkpoint records; first use will be at the next checkpoint after this ADR is committed.

---

## References

```
ADR-116: W Layer Re-definition v0.1
ADR-117: CCC V6 Chain Structure v0.1
ADR-117 Amendment 01: CORE Epistemic Boundary
checkpoint-118: CCC V6 canonical architecture sealed (2026-06-23)
```

Based on currently referenced architecture context.
Formal verification completed via repo inspection (2026-06-27) and DB checkpoint inspection (2026-06-27).

---

## Approval

```
ADR number:        ADR-118
ADR file:          docs/adr/ADR-118-V6-Calibration-Amendment-v0.1.md
Status:            draft
Checkpoint label:  ccc-v6-calibration-amendment-adr118-draft-recorded  (expected ID: 123)
Checkpoint ID:     pending actual insert verification (sequence-assigned, not hardcoded)
Commit label:      TBD — pending review of this ADR file and checkpoint SQL
Author:            Neo (source) · Claude (technical carrier)
Review date:       2026-06-27
```
