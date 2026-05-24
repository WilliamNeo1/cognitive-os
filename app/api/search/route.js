import { createClient } from "@supabase/supabase-js";

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE_KEY
);

export async function GET(req) {
  try {
    const { searchParams } = new URL(req.url);
    const q = searchParams.get("q");

    if (!q) return Response.json({ ok: false, error: "missing query" });

    const { data, error } = await supabase
      .schema("ccc")
      .rpc("search_router_v3", { q });

    if (error) {
      return Response.json({ ok: false, error });
    }

    return Response.json({
      ok: true,
      query: q,
      count: data?.length ?? 0,
      results: (data ?? []).map((r) => ({
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
      })),
    });

  } catch (err) {
    console.error("Search error:", err);
    return Response.json({ ok: false, error: err.message });
  }
}
