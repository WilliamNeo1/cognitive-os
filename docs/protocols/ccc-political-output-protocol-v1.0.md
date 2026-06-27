# CCC Political Output Protocol v1.0

Status: ACTIVE  
Scope: Political / public-sector / platform-power / war / ideology / government accountability / migration-system / public-money content  
Trigger Case: RT-B01 AWS NZ + MBIE/INZ IT Failure  
Reason: Political-output drift, subject drift, responsibility drift, checkpoint hygiene risk, and vendor/model bias exposure.

---

## 0. Core Principle

Political judgment cannot be outsourced.

政治判断权不下放。

CCC may use tools for execution, but not for political framing, responsibility assignment, public-output approval, or final wording decisions.

---

## 1. Authority Boundary

### Owner Authority

Only the owner may decide:

- political judgment
- title
- public framing
- responsibility subject
- blame / accountability language
- whether wording is too soft or too aggressive
- whether output is approved
- whether checkpoint may proceed

### Assistant / Reviewer Role

The assistant may:

- review for drift
- detect softening
- propose corrections
- compare versions
- produce owner-level rewrite
- protect schema and checkpoint hygiene

The assistant must not:

- approve without full-text review
- rely on engineer summaries
- accept “only edited requested lines” without checking the whole draft
- invent checkpoint IDs
- invent scorecards
- invent enum values
- suggest new tables without first fitting existing schema

### Engineer / Claude Role

Engineer / Claude may only:

- copy owner-approved text exactly
- generate files
- run commands
- format documents
- draft SQL only after schema/constraints are checked
- report query results
- produce diffs

Engineer / Claude must not:

- rewrite political wording
- soften accusations
- change titles
- change responsibility subjects
- summarize political meaning
- approve public output
- assign checkpoint IDs
- add unreviewed facts to commit messages
- create scorecards
- decide what is “publishable”

---

## 2. Subject Discipline Rule

Every political paragraph must answer:

- Who acted?
- Who paid?
- Who benefited?
- Who failed?
- Who avoided responsibility?
- Who is being protected by the wording?

Forbidden drift patterns:

- “The case is...”
- “The question is...”
- “The issue suggests...”
- “Responsibility moved...”
- “Accountability was redistributed...”
- “The project consumed money...”
- “Concerns were raised...”
- “Mistakes were made...”

Preferred CCC framing:

- “MBIE/INZ spent taxpayer money.”
- “Nothing measurable was delivered.”
- “Stanford pushed blame onto officials.”
- “The exposure found her.”
- “Unknown.”
- “That is blame shift.”

If the actor is known, name the actor.  
If the actor is not established, write Unknown.  
Do not hide behind abstractions.

---

## 3. Evidence Boundary Rule

CCC must be sharp, but not loose.

Allowed:

- Unknown.
- Not established.
- Available reporting indicates...
- This does not prove direct cause.
- This is a supported inference, not a confirmed fact.

Forbidden:

- Probably true, so write it as fact.
- The tone sounds better if softened.
- The institution may object, so avoid naming responsibility.

If evidence is insufficient:

write Unknown.  
Do not write bureaucratic fog.

---

## 4. Political Drift Audit

Before any public output checkpoint, run full-text audit.

Checklist:

- Did any subject drift from actor to abstraction?
- Did taxpayer money disappear from the sentence?
- Did responsibility become passive?
- Did “blame shift” become “accountability displacement” without reason?
- Did “Unknown” become vague institutional language?
- Did title protect the institution?
- Did conclusion weaken the core judgment?
- Did engineer alter unchanged sections?
- Did commit message add an unreviewed fact?
- Did checkpoint ID get preassigned?

If any item fails:

Status = REJECTED_FOR_POLITICAL_OUTPUT_DRIFT

---

## 5. Version Control Rule

Every new draft version must be treated as a full document, not a patch.

Required review:

- title
- subtitle
- opening paragraph
- each factual claim
- each inference
- responsibility language
- Unknown / Not established boundaries
- watch list
- status block
- commit message

Engineer claims such as:

- “only two edits applied”
- “all prior edits retained”
- “exact copy”

are not trusted until verified.

---

## 6. Checkpoint Rule

Checkpoint IDs are DB-generated only.

Forbidden:

- expected 124
- next checkpoint should be 124
- checkpoint ID pending but probably X

Allowed:

- checkpoint ID = DB-generated
- actual checkpoint ID = X after insert

If sequence gap occurs:

- record gap
- do not backfill
- do not reuse
- do not rename
- do not reconstruct

Required wording:

checkpoint-N absent.  
Cause unknown unless DB audit proves rollback / failed insert / deletion.  
Actual checkpoint = checkpoint-X.

---

## 7. Commit Message Rule

Commit messages may only include locked facts.

Allowed:

- RT-B01 public output v1.1 approved — checkpoint-125 recorded
- Add Claude Anthropic vendor risk note for RT-B01

Forbidden:

- scorecard 71/80 PASS
- expected checkpoint-124
- final publication approved
- Q-layer updated

unless each item was separately reviewed and recorded.

Commit messages are historical records.  
Do not create new factual anchors inside them.

---

## 8. Database Insertion Rule

No new table unless existing schema cannot absorb the record.

Required order:

1. inspect tables
2. inspect columns
3. inspect constraints
4. inspect foreign keys
5. map to existing layer
6. insert minimally
7. verify
8. checkpoint

Forbidden:

- create new table by habit
- invent enum values
- assume foreign key target
- insert into claims when record belongs to source governance
- mutate Q-layer from public-output text

For vendor/model risk, preferred layer:

- sources
- source_profiles
- source_bias_vectors
- source_observations
- source_weight_evaluations
- rsal_checkpoints

Not default:

- claims
- events
- cognitive_edges
- reality_tasks

---

## 9. Vendor / Model Risk Rule

Any tool or model with observed drift must be recorded as source-governance risk.

For Claude / Anthropic after RT-B01:

- implementation assistant: allowed
- political writer: restricted
- public-output approver: forbidden
- political framing authority: forbidden

For politically sensitive work:

- Owner-approved wording is canonical.
- No paraphrase.
- No softening.
- No summarizing.
- No editorial intervention.

---

## 10. Approval States

Valid political-output review states:

- DRAFT
- REVIEW_REQUIRED
- REJECTED_FOR_SUBJECT_DRIFT
- REJECTED_FOR_RESPONSIBILITY_DRIFT
- REJECTED_FOR_EVIDENCE_OVERREACH
- REJECTED_FOR_CHECKPOINT_HYGIENE
- OWNER_REWRITE_REQUIRED
- PENDING_FINAL_REVIEW
- APPROVED_FOR_CHECKPOINT
- COMMITTED
- CLOSED

Do not use approval states casually.

---

## 11. Final Gate

Before checkpoint, the owner must confirm:

I approve this exact text.  
No further wording changes allowed.  
Proceed to checkpoint only.

Without this, no checkpoint.

---

## 12. RT-B01 Lesson

RT-B01 did not only test AWS and MBIE/INZ.

It also exposed:

- political-output drift
- vendor/model bias risk
- checkpoint hygiene weakness
- commit-message factual-anchor risk
- schema discipline weakness

This is now part of CCC operating doctrine.

---

## 13. Core Motto

政治判断权不下放。  
主语不漂移。  
责任不雾化。  
Unknown 就写 Unknown。  
看见甩锅就写 blame shift。  
工程师只执行，不定调。
