import { createClient } from "@supabase/supabase-js";

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE_KEY
);

async function searchW(q) {
  const { data, error } = await supabase
    .schema("ccc")
    .rpc("search_router_v3", { q });
  if (error) return null;
  return data ?? null;
}

function formatWResults(wData) {
  const rows = Array.isArray(wData) ? wData : [];
  const results = rows.map(r => ({
    document_id:       r.document_id,
    content_preview:   r.content_preview,
    scores: {
      keyword:    r.keyword_score    ?? 0,
      entity:     r.entity_score     ?? 0,
      graph:      r.graph_score      ?? 0,
      confidence: r.confidence_score ?? 0.5,
      final:      r.final_score      ?? 0,
    },
    resolved_entities: r.resolved_entities ?? [],
    active_signals:    r.active_signals    ?? [],
    contradictions:    r.contradictions    ?? [],
    sources:           r.sources           ?? [],
  }));
  const resolvedEntities = rows[0]?.resolved_entities ?? [];
  return { results, resolvedEntities };
}

async function getPublishedDecision(canonical) {
  if (!canonical) return null;
  const { data } = await supabase
    .schema("ccc")
    .from("w_decision_public_v1")
    .select("canonical_entity,final_decision,final_priority,final_instruction,action_mode,action_level,risk_boundary,decision_score,pushed_at")
    .or(`canonical_entity.eq.${canonical},q.eq.${canonical}`)
    .order("pushed_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  return data ?? null;
}

export async function GET(req) {
  try {
    const { searchParams } = new URL(req.url);
    const q    = searchParams.get("q");
    const mode = searchParams.get("mode") ?? "auto";

    if (!q) return Response.json({ ok: false, error: "missing query" });

    const wData = await searchW(q);
    if (!wData) {
      return Response.json({
        ok: true, mode, source: "EMPTY",
        query: q, count: 0, results: [],
        resolved_entities: [], decision: null,
      });
    }

    const { results, resolvedEntities } = formatWResults(wData);

    const topEntity = resolvedEntities[0]?.canonical ?? null;
    const decision  = await getPublishedDecision(topEntity);

    return Response.json({
      ok:                true,
      mode:              mode,
      source:            "W",
      query:             q,
      count:             results.length,
      results,
      resolved_entities: resolvedEntities,
      decision,
    });

  } catch (err) {
    console.error("Search error:", err);
    return Response.json({ ok: false, error: err.message });
  }
}
