import { createClient } from "@supabase/supabase-js";

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE_KEY
);

export async function GET(req) {
  try {
    const { searchParams } = new URL(req.url);
    const q = searchParams.get("q");

    if (!q) {
      return Response.json({ ok: false, error: "missing q" });
    }

    const { data: resolved, error } = await supabase
      .schema("ccc")
      .rpc("entity_resolve", { query_text: q });

    if (error) {
      return Response.json({ ok: false, error });
    }

    const top = resolved?.[0];
    let graph = [];

    if (top?.entity_id) {
      const { data: graphData } = await supabase
        .schema("ccc")
        .rpc("entity_graph_expand", {
          seed_entity_id: top.entity_id,
          max_hops: 1,
          min_weight: 1.0,
        });
      graph = graphData ?? [];
    }

    return Response.json({
      ok: true,
      query: q,
      resolved: resolved ?? [],
      graph_neighbors: graph.map((g) => ({
        name:     g.canonical_name,
        relation: g.relation,
        weight:   g.weight,
      })),
    });

  } catch (err) {
    return Response.json({ ok: false, error: err.message });
  }
}
