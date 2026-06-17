import json
import pathlib
import psycopg2

DESKTOP = pathlib.Path.home() / "Desktop"

# 只导入这三个单篇 JSON，不导入 bundle
TARGET_FILES = [
    "li_zhaohui_haixin_enriched_v1.json",
    "lei_jun_xiaomi_su7_enriched_v1.json",
    "uk_labour_reform_ai_podcast_enriched_v1.json",
]

SOURCE_TAG = "phase_d_three_articles_json_v1"

conn = psycopg2.connect(
    host="localhost",
    port=5432,
    dbname="postgres",
    user="postgres"
)

cur = conn.cursor()

inserted = 0
skipped = 0

for filename in TARGET_FILES:
    path = DESKTOP / filename

    if not path.exists():
        print(f"MISS: {path}")
        continue

    data = json.loads(path.read_text(encoding="utf-8"))

    meta = data.get("document_meta", {})
    title = meta.get("title") or data.get("title") or filename
    source_file = meta.get("source_file") or filename
    protocol = meta.get("processing_stage") or meta.get("protocol") or "Phase D Source Hygiene Protocol v1"

    raw_content = (
        "PHASE_D_JSON_IMPORT_V1\n"
        f"TITLE: {title}\n"
        f"SOURCE_FILE: {source_file}\n"
        f"JSON_FILE: {filename}\n"
        f"PROTOCOL: {protocol}\n"
        "IMPORT_TARGET: raw_documents/documents candidate material only\n"
        "GRAPH_WRITE_POLICY: no clean_entities, no typed_edges in this batch\n\n"
        "JSON_PAYLOAD:\n"
        + json.dumps(data, ensure_ascii=False, indent=2)
    )

    cur.execute(
        """
        SELECT id
        FROM ccc.raw_documents
        WHERE source = %s
          AND raw_content ILIKE %s
        LIMIT 1;
        """,
        (SOURCE_TAG, f"%{filename}%")
    )

    existing = cur.fetchone()

    if existing:
        print(f"SKIP existing id={existing[0]} file={filename}")
        skipped += 1
        continue

    cur.execute(
        """
        INSERT INTO ccc.raw_documents (
            raw_content,
            source,
            created_at
        )
        VALUES (%s, %s, now())
        RETURNING id;
        """,
        (raw_content, SOURCE_TAG)
    )

    new_id = cur.fetchone()[0]
    print(f"INSERT id={new_id} file={filename} title={title}")
    inserted += 1

conn.commit()

cur.close()
conn.close()

print("\nDONE")
print(f"inserted={inserted}")
print(f"skipped={skipped}")
print(f"source_tag={SOURCE_TAG}")
