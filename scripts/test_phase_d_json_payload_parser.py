import json
import re
import psycopg2

SOURCE_TAG = "phase_d_three_articles_json_v1"

conn = psycopg2.connect(
    host="localhost",
    port=5432,
    dbname="postgres",
    user="postgres"
)

cur = conn.cursor()

cur.execute("""
    SELECT id, raw_content, created_at
    FROM ccc.raw_documents
    WHERE source = %s
    ORDER BY id;
""", (SOURCE_TAG,))

rows = cur.fetchall()

print(f"raw_documents_found={len(rows)}")
print("=" * 80)

ok_count = 0
fail_count = 0

for doc_id, raw_content, created_at in rows:
    print(f"\nRAW_DOCUMENT id={doc_id}")
    print(f"created_at={created_at}")

    marker = "JSON_PAYLOAD:\n"
    if marker not in raw_content:
        print("FAIL: JSON_PAYLOAD marker not found")
        fail_count += 1
        continue

    payload_text = raw_content.split(marker, 1)[1].strip()

    try:
        data = json.loads(payload_text)
    except Exception as e:
        print(f"FAIL: json.loads error: {e}")
        fail_count += 1
        continue

    meta = data.get("document_meta", {})
    title = meta.get("title") or data.get("title")
    source_file = meta.get("source_file")
    processing_stage = meta.get("processing_stage") or meta.get("protocol")
    import_target = meta.get("import_target")

    candidate_entities = data.get("candidate_entities", [])
    candidate_events = data.get("candidate_events", [])
    candidate_claims = data.get("candidate_claims", [])
    source_enrichment = data.get("source_enrichment", [])
    correction_log = data.get("correction_log", [])

    print("PASS: JSON parsed")
    print(f"title={title}")
    print(f"source_file={source_file}")
    print(f"processing_stage={processing_stage}")
    print(f"import_target={import_target}")
    print(f"candidate_entities={len(candidate_entities)}")
    print(f"candidate_events={len(candidate_events)}")
    print(f"candidate_claims={len(candidate_claims)}")
    print(f"source_enrichment={len(source_enrichment)}")
    print(f"correction_log={len(correction_log)}")

    # light schema checks
    warnings = []

    if not title:
        warnings.append("missing document_meta.title")
    if not isinstance(candidate_entities, list):
        warnings.append("candidate_entities is not list")
    if not isinstance(candidate_events, list):
        warnings.append("candidate_events is not list")
    if not isinstance(candidate_claims, list):
        warnings.append("candidate_claims is not list")
    if not isinstance(source_enrichment, list):
        warnings.append("source_enrichment is not list")
    if not isinstance(correction_log, list):
        warnings.append("correction_log is not list")

    if warnings:
        print("WARNINGS:")
        for w in warnings:
            print(f"  - {w}")
    else:
        print("schema_check=OK")

    ok_count += 1

print("\n" + "=" * 80)
print("SUMMARY")
print(f"ok={ok_count}")
print(f"fail={fail_count}")

cur.close()
conn.close()
