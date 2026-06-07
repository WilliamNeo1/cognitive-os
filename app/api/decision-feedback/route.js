export async function POST(req) {
  try {
    const fd = await req.formData();
    const payload = {
      query_text:        fd.get('query_text'),
      canonical_entity:  fd.get('canonical_entity'),
      final_decision:    fd.get('final_decision'),
      final_priority:    fd.get('final_priority'),
      feedback_value:    fd.get('feedback_value'),
      feedback_reason:   fd.get('feedback_reason'),
    };
    console.log('Decision feedback received:', payload);
    return Response.json({ ok: true });
  } catch (err) {
    return Response.json({ ok: false, error: err.message });
  }
}
