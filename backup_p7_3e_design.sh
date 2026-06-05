#!/usr/bin/env bash
set -euo pipefail

# RSAL P7.3e Final Decision Gate Design Backup
# Purpose:
#   Create a local backup package for the P7.3e design.
#   This script DOES NOT modify PostgreSQL, Supabase, Next.js, or any forecast functions.
#
# Usage:
#   bash scripts/backup_p7_3e_design.sh
#
# Outputs:
#   backups/p7_design/p7_3e_final_decision_gate_design.md
#   backups/p7_design/p7_3e_final_decision_gate_manifest.json
#   backups/p7_design/p7_3e_final_decision_gate_design.sha256
#   backups/p7_design/p7_3e_final_decision_gate_backup.tar.gz

ROOT_DIR="$(pwd)"
OUT_DIR="backups/p7_design"
DESIGN_MD="$OUT_DIR/p7_3e_final_decision_gate_design.md"
MANIFEST_JSON="$OUT_DIR/p7_3e_final_decision_gate_manifest.json"
HASH_FILE="$OUT_DIR/p7_3e_final_decision_gate_design.sha256"
ARCHIVE="$OUT_DIR/p7_3e_final_decision_gate_backup.tar.gz"

mkdir -p "$OUT_DIR"

cat > "$DESIGN_MD" <<'ENDOFFILE'
# RSAL P7.3e Final Decision Gate — Design Backup

Status: DESIGN ONLY / NOT IMPLEMENTED / NOT ACTIVE  
Stable baseline: `P7.3d_forecast_v1_1_confidence_gate_stable`  
Date: 2026-06-05  
Scope: P7 Survival Forecast / Final Decision Gate

---

## 0. Freeze Boundary

The following P7.3d components are locked and must not be modified during P7.3e design backup:

- `ccc.forecast_v1_1(text)`
- `ccc.forecast_v1_1_core(text)`
- `ccc.forecast_confidence_gate_v1(double precision, double precision, double precision)`
- `ccc.forecast_v1_1_regression`
- `ccc.forecast_regression_expectations`

Do not modify:

- P7.4 rigidity multiplier
- route-specific keyword logic
- entity profile schema
- Supabase
- Next.js frontend
- active `contradiction_engine` data

---

## 1. Problem Definition

P7.3d solved the statistical confidence problem:

> How much should we trust the signal?

P7.3e solves a different physical/dynamical problem:

> What is the final emergent state when internal behavioral inertia collides with external field pressure?

This is not a replacement for confidence. It is a decision interpretation layer placed after confidence gate.

---

## 2. Core Model: Rotation vs Orbit

### 2.1 `base_decision`

Internal behavioral inertia.

Source:

- `forecast_v1_1(...)->>'decision'`
- Usually determined by `prob_a` vs `prob_b`
- Represents the entity's internal survival path

Meaning:

- Entity self-rotation
- Institutional inertia
- Historical path dependency
- Power survival logic

### 2.2 `field_decision`

External stress direction.

Source:

- `panel_4_signal_alignment.resonance_score`
- `panel_4_signal_alignment.friction_score`
- `panel_4_signal_alignment.neutral_score`
- `panel_4_signal_alignment.direction_balance`
- `panel_4_signal_alignment.evidence_score`

Meaning:

- Macro field pressure
- Friction against base path
- External confirmation or obstruction

### 2.3 `final_status`

Emergent state after base inertia and field pressure collide.

Meaning:

- Not simply A or B
- A dynamic status token
- Explains whether the base path is reinforced, blocked, drifting, or under counter-pressure

---

## 3. Field Decision Rule

Proposed minimal rule:

```text
IF evidence_score < 0.20:
    field_decision = NEUTRAL

ELSE IF direction_balance >= 0.25:
    field_decision = A

ELSE IF direction_balance <= -0.25:
    field_decision = B

ELSE:
    field_decision = MIXED
```

Interpretation:

- `A`: external field supports Option A / resonance
- `B`: external field supports Option B / friction
- `MIXED`: external field is conflicted
- `NEUTRAL`: insufficient evidence

---

## 4. Generic Interference Matrix

| base_decision | field_decision | final_status | Meaning |
|---|---|---|---|
| A | A | A_RESONANCE_AMPLIFIED | Internal inertia and external field reinforce each other |
| A | B | A_UNDER_FIELD_CONSTRAINT | Base path continues but faces strong external friction |
| A | MIXED | A_CONTESTED | Base path remains dominant but field is unstable |
| A | NEUTRAL | A_INERTIAL_DRIFT | Base path continues by inertia; insufficient field evidence |
| B | B | B_RESONANCE_AMPLIFIED | Option B is internally and externally reinforced |
| B | A | B_UNDER_COUNTERPRESSURE | B path exists but is pressured by A-side field |
| B | MIXED | B_CONTESTED | B path exists but field is unstable |
| B | NEUTRAL | B_INERTIAL_DRIFT | B path continues by inertia; insufficient field evidence |

---

## 5. Route-Specific Status Mapping

### 5.1 Authoritarian

Route profiles:

- `authoritarian`

Examples:

- 习近平
- 中共
- 普京

Status mapping:

| base | field | status_token | Narrative |
|---|---|---|---|
| A | A | CONTROL_RESONANCE_AMPLIFIED | Internal control logic is reinforced by external disorder |
| A | B | CONTROL_UNDER_MATERIAL_FRICTION | Control path continues but material pressure forces tactical concessions |
| A | MIXED | CONTROL_CONTESTED | Control remains dominant, but field is unstable |
| A | NEUTRAL | CONTROL_INERTIAL_DRIFT | Control path continues by inertia |

### 5.2 Governance

Route profiles:

- `governance`

Examples:

- WEF

Status mapping:

| base | field | status_token | Narrative |
|---|---|---|---|
| A | A | ELITE_GOVERNANCE_RESONANCE | Elite coordination agenda is externally reinforced |
| A | B | A_UNDER_SOVEREIGN_BACKLASH | Agenda continues but is blocked by sovereignty / nationalism / de-globalization |
| A | MIXED | GOVERNANCE_CONTESTED | Agenda survives but field is fragmented |
| A | NEUTRAL | GOVERNANCE_INERTIAL_DRIFT | Agenda moves by institutional inertia |

### 5.3 Financial

Route profiles:

- `financial`

Examples:

- 美联储

Status mapping:

| base | field | status_token | Narrative |
|---|---|---|---|
| A | A | LIQUIDITY_RESCUE_REINFORCED | Liquidity rescue path is externally supported |
| A | B | LIQUIDITY_PATH_CONSTRAINED_BY_INFLATION | Liquidity rescue is constrained by inflation / discipline pressure |
| B | B | DISCIPLINE_TIGHTENING_REINFORCED | Tightening path is externally supported |
| B | A | TIGHTENING_UNDER_LIQUIDITY_STRESS | Tightening path is constrained by liquidity stress |
| any | NEUTRAL | CENTRAL_BANK_INERTIAL_DRIFT | Institution moves through technical inertia |

### 5.4 Transactional

Route profiles:

- `transactional`

Examples:

- 特朗普 / Donald John Trump

Status mapping:

| base | field | status_token | Narrative |
|---|---|---|---|
| A | A | EXTREME_PRESSURE_REINFORCED | Destructive pressure is reinforced by external field |
| A | B | PRESSURE_TO_DEAL_CONVERSION | Extreme pressure is likely converting into deal extraction |
| A | MIXED | VOLATILE_BALANCED | Pressure and deal paths are balanced |
| A | NEUTRAL | TRANSACTIONAL_INERTIAL_DRIFT | Moves by short-cycle bargaining inertia |
| B | B | DEAL_CASHOUT_REINFORCED | Deal cashout is externally reinforced |
| B | A | DEAL_UNDER_ESCALATION_PRESSURE | Deal path faces renewed escalation pressure |

---

## 6. Proposed JSON Output Extension

P7.3e should not overwrite P7.3d outputs. It should add a new panel:

```json
{
  "panel_5_final_decision_gate": {
    "model": "final_decision_gate_v1",
    "base_decision": "A",
    "field_decision": "B",
    "final_status": "A_UNDER_SOVEREIGN_BACKLASH",
    "friction_index": 0.42,
    "resultant_vector": -0.42,
    "evidence_score": 0.42,
    "direction_balance": -1.0,
    "status_narrative": "Base agenda continues, but external sovereign backlash blocks acceleration."
  }
}
```

---

## 7. Minimal Computation Draft

### 7.1 Input

From `forecast_v1_1(p_entity_name)`:

```text
base_decision = f->>'decision'
route_profile = f->>'route_profile'
confidence = f->panel_3_forecast.confidence
resonance = f->panel_4_signal_alignment.resonance_score
friction = f->panel_4_signal_alignment.friction_score
neutral = f->panel_4_signal_alignment.neutral_score
evidence_score = f->panel_4_signal_alignment.evidence_score
direction_balance = f->panel_4_signal_alignment.direction_balance
```

### 7.2 Field Decision

```text
IF evidence_score < 0.20:
    field_decision = NEUTRAL
ELSE IF direction_balance >= 0.25:
    field_decision = A
ELSE IF direction_balance <= -0.25:
    field_decision = B
ELSE:
    field_decision = MIXED
```

### 7.3 Friction Index

```text
friction_index =
  CASE
    WHEN field_decision = NEUTRAL THEN 0
    WHEN base_decision = field_decision THEN 0
    ELSE ABS(direction_balance) * evidence_score
  END
```

### 7.4 Resultant Vector

```text
resultant_vector = direction_balance * evidence_score
```

Positive means A-side field pressure.  
Negative means B-side field pressure.  
Near zero means mixed or insufficient field pressure.

---

## 8. Current Expected Examples

### 8.1 WEF

Current P7.3d:

```text
base_decision = A
route_profile = governance
direction_balance = -1
evidence_score = 0.42
field_decision = B
```

Expected P7.3e:

```text
final_status = A_UNDER_SOVEREIGN_BACKLASH
friction_index = 0.42
```

Meaning:

> Elite governance agenda continues internally, but sovereign backlash is already blocking acceleration.

### 8.2 习近平

Current P7.3d:

```text
base_decision = A
route_profile = authoritarian
direction_balance = 1
evidence_score = 1
field_decision = A
```

Expected P7.3e:

```text
final_status = CONTROL_RESONANCE_AMPLIFIED
friction_index = 0
```

Meaning:

> Internal control logic and external disorder reinforce each other.

### 8.3 中共

Current P7.3d:

```text
base_decision = A
route_profile = authoritarian
direction_balance = 1
evidence_score = 1
field_decision = A
```

Expected P7.3e baseline:

```text
final_status = CONTROL_RESONANCE_AMPLIFIED
```

Stress-test possibility:

```text
field_decision = MIXED or B
final_status = CONTROL_UNDER_MATERIAL_FRICTION
```

### 8.4 美联储

Current P7.3d:

```text
base_decision = A
route_profile = financial
direction_balance = 1
evidence_score = 0.33
field_decision = A
```

Expected P7.3e:

```text
final_status = LIQUIDITY_RESCUE_REINFORCED
```

But low evidence should keep the narrative cautious.

### 8.5 特朗普

Current P7.3d:

```text
evidence_score = 0
field_decision = NEUTRAL
```

Expected P7.3e:

```text
final_status = TRANSACTIONAL_INERTIAL_DRIFT
```

---

## 9. Implementation Boundary

P7.3e should be implemented as a wrapper around `forecast_v1_1`.

Recommended function name:

```sql
ccc.forecast_v1_1_final_gate(text)
```

Do not modify:

```sql
ccc.forecast_v1_1(text)
ccc.forecast_v1_1_core(text)
ccc.forecast_confidence_gate_v1(...)
```

Reason:

- P7.3d is locked
- P7.3e should be reversible
- Final decision gate is an interpretation layer, not a confidence layer

---

## 10. Backlog Status

Current status:

```text
P7.3e = DESIGN BACKUP ONLY
```

Next step, when approved:

```text
Implement ccc.forecast_v1_1_final_gate(text)
Add regression view for final gate
Do not touch stable P7.3d baseline
```

ENDOFFILE

cat > "$MANIFEST_JSON" <<'ENDOFFILE'
{
  "backup_name": "RSAL P7.3e Final Decision Gate Design Backup",
  "status": "DESIGN_ONLY_NOT_IMPLEMENTED",
  "stable_baseline": "P7.3d_forecast_v1_1_confidence_gate_stable",
  "created_for": "cognitive-os",
  "files": [
    "p7_3e_final_decision_gate_design.md",
    "p7_3e_final_decision_gate_manifest.json",
    "p7_3e_final_decision_gate_design.sha256",
    "p7_3e_final_decision_gate_backup.tar.gz"
  ],
  "do_not_modify": [
    "ccc.forecast_v1_1(text)",
    "ccc.forecast_v1_1_core(text)",
    "ccc.forecast_confidence_gate_v1(double precision, double precision, double precision)",
    "ccc.forecast_v1_1_regression",
    "active contradiction_engine data",
    "Supabase",
    "Next.js frontend"
  ],
  "recommended_next_function": "ccc.forecast_v1_1_final_gate(text)"
}
ENDOFFILE

if command -v sha256sum >/dev/null 2>&1; then
  sha256sum "$DESIGN_MD" > "$HASH_FILE"
else
  shasum -a 256 "$DESIGN_MD" > "$HASH_FILE"
fi

tar -czf "$ARCHIVE" -C "$OUT_DIR" \
  p7_3e_final_decision_gate_design.md \
  p7_3e_final_decision_gate_manifest.json \
  p7_3e_final_decision_gate_design.sha256

echo "✅ P7.3e design backup created"
echo "Design:   $DESIGN_MD"
echo "Manifest: $MANIFEST_JSON"
echo "Hash:     $HASH_FILE"
echo "Archive:  $ARCHIVE"
echo
echo "Preview:"
ls -lh "$OUT_DIR"
