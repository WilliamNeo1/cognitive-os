import { createClient } from "@supabase/supabase-js";

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE_KEY
);

const GROQ_API_KEY = process.env.GROQ_API_KEY;

async function generateNarrative(query, results, resolvedEntities) {
  if (!GROQ_API_KEY) return null;

  const entityNames = resolvedEntities
    .map(e => e.canonical)
    .filter(Boolean)
    .slice(0, 3)
    .join("、");

  const topDocs = results.slice(0, 5).map((r, i) =>
    `[文档${i+1}] ${r.content_preview}`
  ).join("\n\n");

  const prompt = `你是一个情报分析系统。根据以下搜索结果，为查询"${query}"生成简洁的认知叙事分析。

核心实体：${entityNames || query}

相关文档摘要：
${topDocs}

要求：
1. 用3-5句话概括核心发现
2. 识别主要模式或趋势
3. 指出关键矛盾或不确定性
4. 语言简洁，直接，不废话
5. 只输出分析内容，不要标题或格式

输出格式：直接输出分析文字，200字以内。`;

  try {
    const response = await fetch(
      "https://api.groq.com/openai/v1/chat/completions",
      {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${GROQ_API_KEY}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          model: "llama-3.3-70b-versatile",
          temperature: 0.3,
          max_tokens: 300,
          messages: [
            { role: "system", content: "你是一个专注于政治和情报分析的认知系统，输出简洁精准的分析。" },
            { role: "user", content: prompt }
          ],
        }),
      }
    );

    if (!response.ok) return null;
    const data = await response.json();
    return data.choices?.[0]?.message?.content?.trim() || null;
  } catch {
    return null;
  }
}

async function getEntityIntelligence(entityName) {
  if (!entityName) return null;
  const { data } = await supabase
    .schema("ccc")
    .rpc("entity_intelligence", { p_entity_name: entityName });
  return data;
}

export async function GET(req) {
  try {
    const { searchParams } = new URL(req.url);
    const q = searchParams.get("q");

    if (!q) return Response.json({ ok: false, error: "missing query" });

    const { data, error } = await supabase
      .schema("ccc")
      .rpc("search_router_v3", { q });

    if (error) return Response.json({ ok: false, error });

    const results = data ?? [];
    const resolvedEntities = results[0]?.resolved_entities ?? [];

    // 并行获取叙事和实体情报
    const topEntity = resolvedEntities[0]?.canonical;
    const [narrative, entityIntel] = await Promise.all([
      generateNarrative(q, results, resolvedEntities),
      getEntityIntelligence(topEntity),
    ]);

    return Response.json({
      ok: true,
      query: q,
      count: results.length,
      narrative: narrative || null,
      entity_intelligence: entityIntel || null,
      results: results.map(r => ({
        document_id:       r.document_id,
        content_preview:   r.content_preview,
        scores: {
          keyword:    r.keyword_score    ?? 0,
          entity:     r.entity_score     ?? 0,
          graph:      r.graph_score      ?? 0,
          confidence: r.confidence_score ?? 0.5,
          signal:     r.signal_boost     ?? 0,
          final:      r.final_score      ?? 0,
        },
        resolved_entities: r.resolved_entities ?? [],
        active_signals:    r.active_signals    ?? [],
        contradictions:    r.contradictions    ?? [],
        sources:           r.sources           ?? [],
      })),
    });

  } catch (err) {
    return Response.json({ ok: false, error: err.message });
  }
}
