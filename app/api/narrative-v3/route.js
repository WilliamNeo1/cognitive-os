import { createClient } from "@supabase/supabase-js";

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE_KEY
);

const GROQ_API_KEY = process.env.GROQ_API_KEY;

async function fetchDecision(entity) {
  if (!entity) return null;
  const { data } = await supabase
    .schema("ccc")
    .from("w_decision_public_v1")
    .select("final_decision,final_priority,final_instruction,decision_score,pushed_at")
    .or(`canonical_entity.eq.${entity},q.eq.${entity}`)
    .order("pushed_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  return data ?? null;
}

async function fetchActionLog(entity) {
  if (!entity) return [];
  const { data } = await supabase
    .schema("ccc")
    .from("action_log")
    .select("action_type,expected_outcome,observed_outcome,success_score,observation_date,observation_note")
    .eq("entity_name", entity)
    .order("created_at", { ascending: false })
    .limit(3);
  return data ?? [];
}

async function fetchPredictionAudit(entity) {
  if (!entity) return [];
  const { data } = await supabase
    .schema("ccc")
    .from("prediction_audit")
    .select("prediction_date,predicted_value,actual_value,error_score,audit_note")
    .eq("entity_name", entity)
    .order("prediction_date", { ascending: false })
    .limit(3);
  return data ?? [];
}

async function fetchInformationGaps(entity) {
  if (!entity) return [];
  const { data } = await supabase
    .schema("ccc")
    .from("information_gaps")
    .select("gap_type,missing_data,urgency,current_confidence,suggested_action")
    .eq("entity_name", entity)
    .eq("resolved", false)
    .order("urgency", { ascending: false })
    .limit(3);
  return data ?? [];
}

async function fetchSystemHealth() {
  const { data } = await supabase
    .schema("ccc")
    .from("system_health")
    .select("overall_health,prediction_accuracy,open_gaps,critical_gaps,snapshot_date")
    .order("snapshot_date", { ascending: false })
    .limit(1)
    .maybeSingle();
  return data ?? null;
}

async function fetchEntityProfile(entity) {
  if (!entity) return null;
  const { data } = await supabase
    .schema("ccc")
    .from("entity_profiles")
    .select("essence,survival_mode,power_logic,failure_mode,resource_dependency,decision_bias,confidence")
    .eq("entity_name", entity)
    .maybeSingle();
  return data ?? null;
}

async function generateNarrativeV3(query, entity, decision, profile, actionLog, predAudit, infoGaps, sysHealth, topDocs) {
  if (!GROQ_API_KEY) return null;

  const docContext = topDocs.slice(0, 3).map((r, i) =>
    `[文档${i+1}] ${r.content_preview}`
  ).join("\n\n");

  const decisionContext = decision
    ? `当前决策：${decision.final_decision} / ${decision.final_priority}\n指令：${decision.final_instruction}\n置信度：${decision.decision_score}`
    : "当前决策：无";

  const profileContext = profile
    ? `实体本质：${profile.essence}\n生存模式：${profile.survival_mode}\n决策偏差：${profile.decision_bias}\n资源依赖：${profile.resource_dependency}`
    : "";

  const actionContext = actionLog.length
    ? actionLog.map(a => `行动类型：${a.action_type} | 预期：${a.expected_outcome} | 观察：${a.observed_outcome ?? "待观察"} | 成功率：${a.success_score ?? "待评估"}`).join("\n")
    : "暂无行动记录";

  const auditContext = predAudit.length
    ? predAudit.map(a => `预测：${a.predicted_value} | 实际：${a.actual_value ?? "待观察"} | 误差：${a.error_score ?? "待评估"}`).join("\n")
    : "暂无审计记录";

  const gapContext = infoGaps.length
    ? infoGaps.map(g => `[${g.urgency}] ${g.missing_data}（建议：${g.suggested_action}）`).join("\n")
    : "无信息缺口";

  const healthContext = sysHealth
    ? `系统健康：${sysHealth.overall_health} | 开放缺口：${sysHealth.open_gaps} | 关键缺口：${sysHealth.critical_gaps}`
    : "";

  const prompt = `你是一个行动性认知情报系统（Enactive Cognitive-OS）。你的任务不是描述现在的判断，而是解释：为什么这个判断是现在这个样子，以及它可能如何改变。

查询实体：${entity ?? query}

${profileContext}

${decisionContext}

历史行动与结果：
${actionContext}

预测审计记录：
${auditContext}

当前信息缺口：
${gapContext}

${healthContext}

相关文档：
${docContext}

输出要求：
1. 解释当前判断的形成逻辑（为什么是这个决策）
2. 指出哪些已观察到的结果支持或挑战了这个判断
3. 指出最关键的信息缺口及其对判断可信度的影响
4. 给出一句话的修正方向建议
5. 语言简洁直接，不超过250字，不要标题或格式符号`;

  try {
    const response = await fetch("https://api.groq.com/openai/v1/chat/completions", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${GROQ_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: "llama-3.3-70b-versatile",
        temperature: 0.3,
        max_tokens: 400,
        messages: [
          { role: "system", content: "你是一个专注于政治和情报分析的行动性认知系统，解释判断的形成与修正逻辑。" },
          { role: "user", content: prompt }
        ],
      }),
    });
    if (!response.ok) return null;
    const data = await response.json();
    return data.choices?.[0]?.message?.content?.trim() || null;
  } catch {
    return null;
  }
}

export async function GET(req) {
  try {
    const { searchParams } = new URL(req.url);
    const q = searchParams.get("q");
    if (!q) return Response.json({ ok: false, error: "missing query" });

    const { data: searchData, error } = await supabase
      .schema("ccc")
      .rpc("search_router_v3", { q });

    if (error) return Response.json({ ok: false, error });

    const results     = searchData ?? [];
    const topEntity   = results[0]?.resolved_entities?.[0]?.canonical ?? q;

    const [decision, profile, actionLog, predAudit, infoGaps, sysHealth] = await Promise.all([
      fetchDecision(topEntity),
      fetchEntityProfile(topEntity),
      fetchActionLog(topEntity),
      fetchPredictionAudit(topEntity),
      fetchInformationGaps(topEntity),
      fetchSystemHealth(),
    ]);

    const narrative = await generateNarrativeV3(
      q, topEntity, decision, profile,
      actionLog, predAudit, infoGaps, sysHealth, results
    );

    return Response.json({
      ok:               true,
      version:          "narrative-v3",
      query:            q,
      entity:           topEntity,
      narrative,
      decision,
      profile,
      action_log:       actionLog,
      prediction_audit: predAudit,
      information_gaps: infoGaps,
      system_health:    sysHealth,
      result_count:     results.length,
    });

  } catch (err) {
    console.error("narrative-v3 error:", err);
    return Response.json({ ok: false, error: err.message });
  }
}
