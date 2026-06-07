import { createClient } from "@supabase/supabase-js";

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE_KEY
);

export async function POST(req) {
  try {
    const fd = await req.formData();

    const query_text       = fd.get('query_text')       ?? '';
    const canonical_entity = fd.get('canonical_entity') ?? '';
    const final_decision   = fd.get('final_decision')   ?? '';
    const final_priority   = fd.get('final_priority')   ?? '';
    const final_instruction= fd.get('final_instruction')?? '';
    const feedback_value   = fd.get('feedback_value')   ?? '';
    const feedback_reason  = fd.get('feedback_reason')  ?? '';
    const page_path        = fd.get('page_path')        ?? '';
    const user_agent       = req.headers.get('user-agent') ?? '';

    if (!feedback_value || !['AGREE','DISAGREE'].includes(feedback_value)) {
      return Response.json({ ok: false, error: 'invalid feedback_value' });
    }

    // 写入反馈主表
    const { data: feedback, error: fbError } = await supabase
      .schema("ccc")
      .from("w_decision_feedback")
      .insert({
        query_text,
        canonical_entity,
        final_decision,
        final_priority,
        final_instruction,
        feedback_value,
        feedback_reason,
        page_path,
        user_agent,
      })
      .select("id")
      .single();

    if (fbError) return Response.json({ ok: false, error: fbError });

    const feedback_id = feedback.id;

    // 处理附件
    const files = fd.getAll('files').filter(f => f && f.size > 0);
    const attachments = [];

    for (const file of files.slice(0, 5)) {
      if (file.size > 20 * 1024 * 1024) continue; // 跳过超过 20MB 的文件

      const ext          = file.name.split('.').pop() ?? 'bin';
      const storage_path = `${feedback_id}/${Date.now()}_${file.name}`;
      const buffer       = await file.arrayBuffer();

      const { error: uploadError } = await supabase
        .storage
        .from("decision-feedback")
        .upload(storage_path, buffer, {
          contentType: file.type || 'application/octet-stream',
          upsert: false,
        });

      if (uploadError) {
        console.error('Upload error:', uploadError);
        continue;
      }

      const { error: attError } = await supabase
        .schema("ccc")
        .from("w_feedback_attachments")
        .insert({
          feedback_id,
          file_name:    file.name,
          file_size:    file.size,
          storage_path,
        });

      if (!attError) {
        attachments.push({ file_name: file.name, storage_path });
      }
    }

    return Response.json({
      ok:          true,
      feedback_id,
      attachments_saved: attachments.length,
    });

  } catch (err) {
    console.error('decision-feedback error:', err);
    return Response.json({ ok: false, error: err.message });
  }
}
