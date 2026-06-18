# SQLV3 Source Hygiene Protocol v0.1
checkpoint id=100

## Purpose
Not a truth-ranking system. A containment layer for source identity, traceability, and contamination risk.

## Three Source Layers (source_layer)
- direct_record: original documents, filings, official speeches, court records, financial reports
- reported_account: media reports, interviews, third-party summaries, investigation reports
- narrative_layer: commentary, analysis, propaganda, podcasts, self-media, secondary retelling

**source_layer is distance from original event, NOT credibility ranking.**

## Source Status
unverified / traceable / supported / disputed / refuted / fabricated / parked / quarantine

## Contamination Status (separate field)
unknown / suspected / confirmed / dismissed
- Rules can only mark suspected
- confirmed requires human confirmation
- fabricated = fake citation, no original found
- contaminated = source laundering, propaganda injection, export-reimport loop

## Three Concept Tables
- sources: source node identity
- source_observations: observations, status changes, contamination confirmations
- source_claim_links: many-to-many between claims and sources

## 10 Core Rules
1. Source is not truth
2. Overseas source is not automatically independent
3. Direct record is not reality
4. Reported account is not verified fact
5. Narrative layer may contain signals but cannot directly produce events or edges
6. Fabricated citation must be removed or quarantined
7. Source laundering must be marked as contamination risk
8. Claims must preserve their source chain
9. No claim may be upgraded only because a prestigious source name is attached
10. W-side feedback or uploads can only create candidate sources, never direct Q facts
