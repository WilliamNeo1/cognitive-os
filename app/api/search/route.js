import { createClient } from "@supabase/supabase-js";

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE_KEY
);

async function searchQ(q) {
  const url = `${process.env.NEXT_PUBLIC_SUPABASE_URL}/rest/v1/rpc/search_router_v3_local_forecast_trust_v3`;
  const res = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type":    "application/json",
      "apikey":          process.env.SUPABASE_SERVICE_ROLE_KEY,
      "Authorization":   `Bearer ${process.env.SUPABASE_SERVICE_ROLE_KEY}`,
      "Accept-Profile":  "ccc",
      "Content-Profile": "ccc",
    },
    body: JSON.stringify({ p_q: q }),
  });
  if (!res.ok) return null;
  const data = await res.json();
  return data ?? null;
}

async function searchW(q) {
  const { data, error } = await supabase
    .schema("ccc")
    .rpc("search_router_v3", { q });
  if (error) return null;
  return data ?? null;
}

function isQUsable(qData) {
  if (!qData) return false;
  if (!qData.ok) return false;
  const docs = qData.document_hits;
  if (!Array.isArray(docs) || docs.length === 0) return false;
  const topScore = docs[0]?.final_score ?? 0;
  return topScore >= 0.35;
}

function formatQResults(qData) {
  const docs = qData.document_hits ?? [];
  const resolvedEntities = (qData.resolved_entities ?? []).map(e => ({
    canonical:  e.canonical_name,
    type:       e.entity_type,
    confidence: e.confidence,
    match:      e.match_type,
  }));
  const results = docs.map(d => ({
    document_id:       d.document_id,
    content_preview:   d.content_preview,
    scores: {
      keyword:    d.keyword_score ?? 0,
      entity:     d.entity_score  ?? 0,
      graph:      d.graph_score   ?? 0,
      confidence: 0.5,
      final:      d.final_score   ?? 0,
    },
    resolved_entities: resolvedEntities,
    active_signals:    [],
    contradictions:    [],
    sources:           [],
  }));
  return { results, resolvedEntities };
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

export async function GET(req) {
  try {
    const { searchParams } = new URL(req.url);
    const q    = searchParams.get("q");
    const mode = searchParams.get("mode") ?? "auto";

    if (!q) return Response.json({ ok: false, error: "missing query" });

    if (mode === "all") {
      const [qData, wData] = await Promise.all([searchQ(q), searchW(q)]);
      const qFormatted = isQUsable(qData) ? formatQResults(qData) : null;
      const wFormatted = wData ? formatWResults(wData) : null;
      const qIds   = new Set((qFormatted?.results ?? []).map(r => r.document_id));
      const wExtra = (wFormatted?.results ?? []).filter(r => !qIds.has(r.document_id));
      const merged = [...(qFormatted?.results ?? []), ...wExtra];
      return Response.json({
        ok:                true,
        mode:              "all",
        source:            "Q+W",
        query:             q,
        count:             merged.length,
        results:           merged,
        resolved_entities: qFormatted?.resolvedEntities ?? wFormatted?.resolvedEntities ?? [],
        q_status:          qFormatted ? "HIT" : "EMPTY",
        w_status:          wFormatted ? "HIT" : "EMPTY",
        forecasts:         qData?.forecasts ?? [],
        panels:            qData?.panels    ?? [],
      });
    }

    const qData = await searchQ(q);

    if (isQUsable(qData)) {
      const { results, resolvedEntities } = formatQResults(qData);
      return Response.json({
        ok:                true,
        mode:              "auto",
        source:            "Q",
        query:             q,
        count:             results.length,
        results,
        resolved_entities: resolvedEntities,
        forecasts:         qData.forecasts ?? [],
        panels:            qData.panels    ?? [],
      });
    }

    const wData = await searchW(q);
    if (!wData) {
      return Response.json({
        ok: true, mode: "auto", source: "EMPTY",
        query: q, count: 0, results: [],
        resolved_entities: [], forecasts: [], panels: [],
      });
    }

    const { results, resolvedEntities } = formatWResults(wData);
    return Response.json({
      ok:                true,
      mode:              "auto",
      source:            "W_FALLBACK",
      query:             q,
      count:             results.length,
      results,
      resolved_entities: resolvedEntities,
      q_status:          "INSUFFICIENT",
      forecasts:         [],
      panels:            [],
    });

  } catch (err) {
    console.error("Search error:", err);
    return Response.json({ ok: false, error: err.message });
  }
}
