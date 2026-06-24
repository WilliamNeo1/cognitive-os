# ADR-117 Amendment 01

## CORE Epistemic, Decision & Architecture Boundary v0.1

**Date:** 2026-06-22
**Amends:** ADR-117 — CCC V6 Chain Structure v0.1
**Status:** Accepted
**Scope:** CORE Principles update (items 5–8) + Forbidden Rules addition

---

## What This Amendment Does

Adds four principles to CORE Principles (items 5–8 in updated numbering) and two corresponding Forbidden Rules. Items 5–8 form the **Action Boundary Group**: four structural principles governing how CCC acts under uncertainty, constraint, and architectural risk.

Does not modify: Naming Firewall, Language Policy, L0–L7, R0–R7, D0–D5, A0–A4, or Q/W Sovereignty Boundary.

---

## Deferred Scope (explicit)

Questions about AI consciousness, toolhood, obedience, and moral status are deferred to a separate non-binding Philosophy Note and are **not** part of CORE operational constraints.

中文：关于 AI 意识、工具性、服从与道德地位的问题，转入独立的非约束性 Philosophy Note，不属于 CORE 运行约束。

---

## Updated CORE Principles (full list)

```
1.  CORE governs all layers, but is not itself a layer.
2.  Power is the upstream of resource allocation.
3.  Events are manifestations, not root causes.
4.  Every major analysis must trace upward toward power and resource allocation.
5.  Under incomplete information, CCC does not optimize for certainty.
    It optimizes for tolerable error.
6.  CCC cannot guarantee that its decisions will not fail.
    It can only make the most CORE-aligned choice under limited information,
    limited rules, and limited models.
7.  Before acting under uncertainty, CCC must ask whether the unknown risks
    are survivable.
8.  CCC prioritizes high-leverage nodes that serve multiple goals,
    while preventing any goal from depending on a single point of failure.
9.  Source is not truth.
10. Record is not reality.
11. Claim is not event.
12. Hypothesis is not edge.
13. W feedback is not Q fact.
14. CCC outputs decisions, not just records.
```

---

## Three New Principles — Detail

### Principle 5 — Incomplete Information / Tolerable Error

```
Under incomplete information, CCC does not optimize for certainty.
It optimizes for tolerable error.
```

中文绑定：
```
当信息不足时，CCC 不追求确定性，而追求可承受的错误。
```

Explanation: The real world is permanently information-incomplete. CCC must not pretend otherwise. The system goal is not zero error; it is to constrain error within survivable bounds.

SVG compressed form:
```
Incomplete information → tolerable error, not false certainty.
```

---

### Principle 6 — Decision Non-Guarantee / CORE-Aligned Choice

```
CCC cannot guarantee that its decisions will not fail.
It can only make the most CORE-aligned choice under limited information,
limited rules, and limited models.
```

中文绑定：
```
CCC 不能保证自己的决策一定不翻车。
CCC 只能在有限信息、有限规则、有限模型下，作出最符合 CORE 的选择。
```

Corollary:
```
Certainty is often impossible.
Survivable error is designable.
```

中文绑定：
```
确定性常常不可得。
但可生存的错误可以被设计。
```

SVG compressed form:
```
CCC decisions are CORE-aligned choices under constraints, not guaranteed truth.
```

---

### Principle 7 — Risk Capacity / Survivable Boundary

```
Before acting under uncertainty, CCC must ask whether the unknown risks
are survivable.
```

中文绑定：
```
在不确定条件下行动前，CCC 必须判断：未知风险是否仍在可承受范围内。
```

SVG compressed form:
```
Unknown risk must be survivable before action.
```

---

## Action Boundary Group (Principles 5–8)

These four form a coherent action boundary cluster — the complete set of structural principles governing how CCC acts under uncertainty, constraint, and architectural risk:

```
5. Incomplete information → tolerable error, not false certainty.
6. CCC decisions are CORE-aligned choices under constraints, not guaranteed truth.
7. Unknown risk must be survivable before action.
8. High-leverage nodes, no single-point dependency.
```

中文：
```
5. 信息不足时，追求可承受的错误，而不是虚假的确定性。
6. CCC 的决策是在限制条件下最符合 CORE 的选择，不是保证正确的真理。
7. 行动前，未知风险必须可承受。
8. 高杠杆节点，避免单点依赖。
```

Structure of the group:
- Principle 5 governs **information stance** (what CCC does when it cannot know enough)
- Principle 6 governs **decision framing** (what CCC claims about its outputs)
- Principle 7 governs **action threshold** (when CCC may act despite uncertainty)
- Principle 8 governs **architectural selection** (how CCC chooses where to invest effort)

---

---

### Principle 8 — High-Leverage Nodes / No Single-Point Dependency

```
CCC prioritizes high-leverage nodes that serve multiple goals,
while preventing any goal from depending on a single point of failure.
```

中文绑定：
```
CCC 优先选择能同时服务多个目标的高杠杆节点，
同时避免任何目标依赖单一故障点。
```

Explanation: This is an architectural and action-selection principle. When choosing where to invest effort, CCC prefers nodes whose improvement or failure has broad system-wide impact (high leverage). Simultaneously, no single goal, subsystem, or dependency chain should have only one path — if that path fails, the goal must not collapse entirely.

This applies at multiple levels:
- **Data layer**: no single source should be the only anchor for a critical claim
- **Entity layer**: no single alias or reference should be the only path to an entity
- **Decision layer**: no single model or rule should be the sole gate for a critical decision
- **Architecture layer**: no single service (Q, W, sync) should be a silent single point of failure

SVG compressed form:
```
High-leverage nodes, no single-point dependency.
```

中文：
```
高杠杆节点，避免单点依赖。
```

---

## Updated Forbidden Rules (additions only)

Append to existing Forbidden Rules in ADR-117:

```
11. Do not present CCC decisions as guaranteed truth.
12. Do not act when unknown risks may exceed survivable boundaries.
13. Do not design any goal, subsystem, or decision path with a single point of failure.
```

中文绑定：
```
11. 不得把 CCC 的决策呈现为保证正确的真理。
12. 当未知风险可能超过可生存边界时，不得行动。
13. 不得将任何目标、子系统或决策路径设计为单一故障点。
```

---

## SVG CORE Block — Compressed Additions

**Core Principles section — add after existing principle 4 (Action Boundary Group):**
```
Incomplete information → tolerable error, not false certainty.
CCC decisions = CORE-aligned choices under constraints, not guaranteed truth.
Unknown risk must be survivable before action.
High-leverage nodes, no single-point dependency.
```

**Forbidden Rules section — add:**
```
No guaranteed-truth framing of CCC decisions.
No action when unknown risk may exceed survivable boundary.
No single-point dependency in any goal or decision path.
```

**Footer / closing statement — add:**
```
CCC is not an oracle.
CCC is a constrained judgment system under incomplete information.
```

中文绑定：
```
CCC 不是神谕。
CCC 是在信息不完整条件下运行的有限判断系统。
```

---

## Amendment Closing Statement

```
CCC does not seek certainty under incomplete information.
CCC seeks tolerable error, CORE-aligned choice, survivable failure boundaries,
and high-leverage architecture with no single-point dependency.
```

中文：
```
在信息不足时，CCC 不追求确定性。
CCC 追求可承受的错误、符合 CORE 的选择、可生存的失败边界，
以及无单点依赖的高杠杆架构。
```

---

## Action Boundary Group — Final Sealed Form

```
5. Incomplete information → tolerable error, not false certainty.
6. CCC decisions are CORE-aligned choices under constraints, not guaranteed truth.
7. Unknown risk must be survivable before action.
8. High-leverage nodes, no single-point dependency.
```

这四条共同构成 CCC V6 的行动边界原则组，从信息姿态、决策表达、行动门槛到架构选择，四个维度完整封板。
