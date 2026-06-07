export async function GET(req) {
  try {
    const { searchParams } = new URL(req.url);
    const q = searchParams.get("q");
    if (!q) return Response.json({ ok: false, error: "missing query" });

    const url = `${process.env.NEXT_PUBLIC_SUPABASE_URL}/rest/v1/rpc/decision_engine_v1`;
    const res = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type":    "application/json",
        "apikey":          process.env.SUPABASE_SERVICE_ROLE_KEY,
        "Authorization":   `Bearer ${process.env.SUPABASE_SERVICE_ROLE_KEY}`,
        "Accept-Profile":  "ccc",
        "Content-Profile": "ccc",
      },
      body: JSON.stringify({ p_entity_name: q }),
    });

    if (!res.ok) {
      const err = await res.text();
      return Response.json({ ok: false, error: err });
    }

    const raw = await res.json();

    const decision = {
      final_decision:    raw.final_decision    ?? null,
      final_priority:    raw.final_priority    ?? null,
      final_instruction: raw.final_instruction ?? null,
      action_status:     raw.action_status     ?? null,
      action_level:      raw.action_level      ?? null,
      action_mode:       raw.action_mode       ?? null,
      risk_boundary:     raw.risk_boundary     ?? null,
      decision_score:    raw.decision_score    ?? null,
      forecast_status:   raw.p7_input_snapshot?.forecast_status ?? null,
      confidence:        raw.p7_input_snapshot?.confidence       ?? null,
      pressure:          raw.p7_input_snapshot?.pressure         ?? null,
      trajectory_code:   raw.p7_input_snapshot?.trajectory_code  ?? null,
    };

    return Response.json({
      ok:       true,
      version:  "decision-engine-v1",
      query:    q,
      decision,
      raw,
    });

  } catch (err) {
    return Response.json({ ok: false, error: err.message });
  }
}
