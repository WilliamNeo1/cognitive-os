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

    // 先精确匹配 canonical_entity，再 fallback 模糊匹配 search_text
    const { data, error } = await supabase
      .from("w_decision_public_v1")
      .select("*")
      .or(`canonical_entity.eq.${q},q.eq.${q}`)
      .order("pushed_at", { ascending: false })
      .limit(1)
      .maybeSingle();

    if (error) return Response.json({ ok: false, error });

    if (!data) {
      return Response.json({
        ok:      false,
        status:  "NOT_FOUND",
        query:   q,
        message: "No decision published for this entity.",
      });
    }

    return Response.json({
      ok:      true,
      version: "decision-engine-v1",
      query:   q,
      source:  "w_decision_public_v1",
      decision: {
        final_decision:    data.final_decision,
        final_priority:    data.final_priority,
        final_instruction: data.final_instruction,
        action_status:     data.action_status,
        action_level:      data.action_level,
        action_mode:       data.action_mode,
        risk_boundary:     data.risk_boundary,
        decision_score:    data.decision_score,
        review_trigger:    data.review_trigger,
        primary_rule:      data.primary_rule,
        pushed_at:         data.pushed_at,
      },
    });

  } catch (err) {
    return Response.json({ ok: false, error: err.message });
  }
}
