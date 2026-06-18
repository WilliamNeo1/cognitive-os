# SQLV3 Data Layer v0.1
checkpoint id=99

## Opening Statement
SQLV3 Data Layer is not a truth machine. It is an absorption and containment architecture for CCC as a sovereign think tank. Its purpose is to preserve raw material, prevent source pollution, separate records from reality, control graph entry, and feed actionable decisions without over-modeling.

## L0-L7 Absorption Protocol

### L0 Raw Intake
- Input: any raw material
- Output: raw_documents
- Rules: no truth judgment; preserve original; allow quarantine tags
- Status: raw_only / quarantine

### L1 Document Normalization
- Input: raw_documents
- Output: documents
- Rules: identify language, topic, time range, source_layer
- Status: normalized

### L2 Claim Extraction
- Input: documents
- Output: claims
- Rules: preserve claimant/source/original_quote; default status=unverified
- Status: extracted

### L3 Event Anchoring
- Input: claims with time_anchor+actor+action+source_trace
- Output: events
- Rules: anchor what happened, not the interpretation
- Status: anchored

### L4 Entity Governance
- Input: entity mentions from L3 events + L2 claims
- Output: entity_review_queue → clean_entities
- Rules: D.5.1 gate; entity_uuid generated here, immutable
- Status: governed

### L5 Relation Candidate
- Input: clean_entities + events + claims
- Output: candidate_edges
- Rules: must have source event or claim support
- Status: candidate

### L6 Graph Write Gate
- Input: candidate_edges
- Output: clean_graph_edges
- Rules: requires stable entities + source trace + accepted event/claim
- Status: accepted / rejected / parked / watch

### L7 Decision Consumption
- Input: L6 accepted + parked/watch as warning signals only
- Output: P6 Prediction + P7 Decision
- Rules: main judgment from accepted only; parked/watch are warning signals not facts

## Absorption Status Machine
raw_only / quarantine / normalized / extracted / anchored / governed / candidate / accepted / rejected / parked / watch / consumed
