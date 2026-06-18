# SQLV3 Claims/Events/Hypothesis Boundary v0.1
checkpoint id=101

## Five Cognitive Object Types
- event = occurrence (发生)
- claim = assertion (主张)
- hypothesis = explanatory model (解释)
- rumor = unverified circulation (传闻)
- interpretation = analytical judgment (判断)

## Nine Core Boundary Rules
1. No claim becomes an event automatically.
2. No hypothesis becomes an edge.
3. No rumor enters clean_graph_edges.
4. No interpretation enters REALITY_EVENT.
5. An event records occurrence, not ultimate truth.
6. A record can be an event, but the content of the record may still be a claim.
7. Hypothesis may inform warning signals but not accepted graph facts.
8. CCC may use interpretations for judgment, but must preserve their layer identity.
9. When uncertain, park rather than promote.

## Event Minimum Requirements
time_anchor + actor/subject + action/occurrence + source_trace

## Upgrade Rules
- claim → event: requires concrete occurrence + time anchor + traceable source + not merely interpretation
- hypothesis → event: only the act of proposing may be recorded as record_event; hypothesis content cannot become reality_event
- rumor → event: must pass rumor → claim → supported claim → event candidate → review chain
- interpretation → event: never allowed

## Relationship with Source Hygiene
- Source Hygiene: where did it come from, is the chain clean?
- Boundary Rules: what kind of object is this?
- Meeting point: source_claim_links
