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

async function getPublishedDecision(canonical, fallbackQ) {
  const lookup = canonical || fallbackQ;
  if (!lookup) return null;
  const { data } = await supabase
    .schema("ccc")
    .from("w_decision_public_v1")
    .select("canonical_entity,final_decision,final_priority,final_instruction,action_mode,action_level,risk_boundary,decision_score,pushed_at")
    .or(`canonical_entity.eq.${lookup},q.eq.${lookup}`)
    .order("pushed_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  return data ?? null;
}

async function logMiss({ query_text, mode, source, result_count, user_agent }) {
  try {
    await supabase
      .from("w_search_miss_log")
      .insert({
        query_text,
        route:          "/api/search",
        mode,
        source,
        result_count,
        decision_found: false,
        reason:         "NO_SEARCH_RESULTS_AND_NO_DECISION",
        user_agent:     user_agent ?? null,
      });
  } catch (e) {
    console.error("miss log failed:", e);
  }
}

export async function GET(req) {
  try {
    const { searchParams } = new URL(req.url);
    const q          = searchParams.get("q");
    const mode       = searchParams.get("mode") ?? "auto";
    const user_agent = req.headers.get("user-agent") ?? null;

    if (!q) return Response.json({ ok: false, error: "missing query" });

    const wData = await searchW(q);
    if (!wData) {
      await logMiss({ query_text: q, mode, source: "EMPTY", result_count: 0, user_agent });
      return Response.json({
        ok: true, mode, source: "EMPTY",
        query: q, count: 0, results: [],
        resolved_entities: [], decision: null,
      });
    }

    const { results, resolvedEntities } = formatWResults(wData);
    const topEntity = resolvedEntities[0]?.canonical ?? null;
    const decision  = await getPublishedDecision(topEntity, q);

    if (results.length === 0 && !decision) {
      await logMiss({ query_text: q, mode, source: "W", result_count: 0, user_agent });
    }

    return Response.json({
      ok:                true,
      mode,
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
