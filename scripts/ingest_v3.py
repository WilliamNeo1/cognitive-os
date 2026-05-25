#!/usr/bin/env python3
"""
ingest_v3.py — 统一入库脚本
用法:
  方案A（手动）: python3 scripts/ingest_v3.py --json data.json
  方案B（自动）: python3 scripts/ingest_v3.py --image screenshot.png
"""

import json, os, sys, hashlib, argparse
import psycopg2

LOCAL_DB = {
    "host":   "localhost",
    "port":   5432,
    "dbname": "postgres",
    "user":   "postgres",
    "password": os.environ.get("LOCAL_PG_PASSWORD", ""),
}

def get_conn():
    return psycopg2.connect(**LOCAL_DB)

def hash_content(text):
    return hashlib.md5(text.encode()).hexdigest()

def ingest_json(data: dict):
    conn = get_conn()
    cur  = conn.cursor()

    raw_content  = data.get("raw_content", json.dumps(data, ensure_ascii=False))
    full_content = json.dumps(data, ensure_ascii=False)
    content_hash = hash_content(full_content)

    # 1. raw_documents
    cur.execute("""
        INSERT INTO ccc.raw_documents (raw_content, source, created_at)
        VALUES (%s, %s, now())
        RETURNING id
    """, (raw_content, data.get("source_type", "xmind")))
    raw_doc_id = cur.fetchone()[0]

    # 2. documents
    cur.execute("""
        INSERT INTO ccc.documents (raw_document_id, content, content_hash, created_at)
        VALUES (%s, %s, %s, now())
        ON CONFLICT (content_hash) DO NOTHING
        RETURNING id
    """, (raw_doc_id, full_content, content_hash))
    row = cur.fetchone()
    if row:
        doc_id = row[0]
        print(f"✅ 新文档 doc_id={doc_id}")
    else:
        cur.execute("SELECT id FROM ccc.documents WHERE content_hash = %s", (content_hash,))
        doc_id = cur.fetchone()[0]
        print(f"⚠️  文档已存在 doc_id={doc_id}")

    # 3. entities
    entities = data.get("entities", [])
    for ent in entities:
        name  = ent.get("name", "").strip()
        etype = ent.get("type", "PERSON")
        if not name or len(name) < 2:
            continue

        # 查是否已存在
        cur.execute("""
            SELECT id FROM ccc.clean_entities
            WHERE lower(canonical_name) = lower(%s) AND entity_type = %s
        """, (name, etype))
        row = cur.fetchone()
        if row:
            entity_id = row[0]
            cur.execute("""
                UPDATE ccc.clean_entities
                SET mention_count = mention_count + 1
                WHERE id = %s
            """, (entity_id,))
        else:
            cur.execute("""
                INSERT INTO ccc.clean_entities
                    (canonical_name, entity_type, source, confidence, mention_count)
                VALUES (%s, %s, 'ingest_v3', 0.9, 1)
                RETURNING id
            """, (name, etype))
            entity_id = cur.fetchone()[0]

        # clean_document_entities
        cur.execute("""
            SELECT id FROM ccc.clean_document_entities
            WHERE document_id = %s AND entity_id = %s
        """, (doc_id, entity_id))
        if cur.fetchone():
            cur.execute("""
                UPDATE ccc.clean_document_entities
                SET frequency = frequency + 1
                WHERE document_id = %s AND entity_id = %s
            """, (doc_id, entity_id))
        else:
            cur.execute("""
                INSERT INTO ccc.clean_document_entities
                    (document_id, entity_id, canonical_name, entity_type, frequency)
                VALUES (%s, %s, %s, %s, 1)
            """, (doc_id, entity_id, name, etype))

        # person_aliases
        for alias in ent.get("aliases", []):
            if alias and len(alias) >= 2:
                cur.execute("""
                    INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
                    VALUES (%s, %s, 'auto')
                    ON CONFLICT DO NOTHING
                """, (name, alias))

        print(f"   实体: {name} ({etype})")

    # 4. events
    events = data.get("events", [])
    for ev in events:
        summary  = ev.get("summary", "").strip()
        if not summary:
            continue
        date_raw = str(ev.get("date", "") or "")
        if len(date_raw) == 4 and date_raw.isdigit():
            date_sql = f"{date_raw}-01-01"
        elif len(date_raw) >= 8:
            date_sql = date_raw[:10]
        else:
            date_sql = None
        year = int(date_raw[:4]) if len(date_raw) >= 4 and date_raw[:4].isdigit() else None

        cur.execute("""
            INSERT INTO ccc.events
                (document_id, event_summary, event_date, event_year, event_time_raw, created_at)
            VALUES (%s, %s, %s, %s, %s, now())
            ON CONFLICT DO NOTHING
        """, (doc_id, summary, date_sql, year, date_raw))
        print(f"   事件: {date_raw} — {summary[:50]}")

    # 5. clean_graph_edges（同文档内实体两两连接）
    cur.execute("""
        SELECT entity_id FROM ccc.clean_document_entities
        WHERE document_id = %s
    """, (doc_id,))
    ent_ids = [r[0] for r in cur.fetchall()]

    for i, eid1 in enumerate(ent_ids):
        for eid2 in ent_ids[i+1:]:
            src, tgt = min(eid1, eid2), max(eid1, eid2)
            cur.execute("""
                SELECT id FROM ccc.clean_graph_edges
                WHERE source_entity_id = %s AND target_entity_id = %s
                  AND relation_type = 'co_occurrence'
            """, (src, tgt))
            if cur.fetchone():
                cur.execute("""
                    UPDATE ccc.clean_graph_edges
                    SET weight = weight + 1, document_count = document_count + 1
                    WHERE source_entity_id = %s AND target_entity_id = %s
                      AND relation_type = 'co_occurrence'
                """, (src, tgt))
            else:
                cur.execute("""
                    INSERT INTO ccc.clean_graph_edges
                        (source_entity_id, target_entity_id, relation_type, weight, document_count)
                    VALUES (%s, %s, 'co_occurrence', 1.0, 1)
                """, (src, tgt))

    conn.commit()
    cur.close()
    conn.close()

    print(f"\n✅ 入库完成 doc_id={doc_id}")
    print(f"   实体: {len(entities)} 个")
    print(f"   事件: {len(events)} 个")
    return doc_id

def ingest_image(image_path: str):
    import base64
    from openai import OpenAI

    api_key = os.environ.get("OPENAI_API_KEY")
    if not api_key:
        print("❌ 未设置 OPENAI_API_KEY")
        print("   运行: export OPENAI_API_KEY='sk-...'")
        sys.exit(1)

    client = OpenAI(api_key=api_key)
    with open(image_path, "rb") as f:
        img_b64 = base64.b64encode(f.read()).decode()
    ext  = image_path.split(".")[-1].lower()
    mime = {"jpg":"image/jpeg","jpeg":"image/jpeg","png":"image/png"}.get(ext,"image/png")

    print(f"📸 正在用 GPT-4o 分析: {image_path}")
    response = client.chat.completions.create(
        model="gpt-4o",
        messages=[{"role":"user","content":[
            {"type":"text","text":"""分析这张思维导图或笔记截图，提取所有信息，只返回JSON不要解释：
{
  "title": "主题",
  "category": "PERSON|ORG|EVENT|PLACE|CLAIM",
  "language": "zh|en|mixed",
  "source_type": "xmind",
  "source_url": null,
  "verified": false,
  "entities": [{"name":"","type":"PERSON|ORG|GPE|EVENT","role":"","aliases":[],"notes":""}],
  "events": [{"date":"YYYY或YYYY-MM-DD","location":"","summary":"","persons":[]}],
  "claims": [{"text":"","confidence":0.8,"source":null}],
  "raw_content": "图片主要内容描述"
}"""},
            {"type":"image_url","image_url":{"url":f"data:{mime};base64,{img_b64}","detail":"high"}}
        ]}],
        max_tokens=3000
    )

    raw = response.choices[0].message.content.strip()
    if raw.startswith("```"):
        raw = raw.split("```")[1]
        if raw.startswith("json"):
            raw = raw[4:]
    data = json.loads(raw.strip())
    print(f"✅ GPT-4o 提取 {len(data.get('entities',[]))} 个实体")
    return ingest_json(data)

def auto_sync():
    import subprocess
    print("\n🔄 自动同步到 Supabase...")
    subprocess.run(["python3", "scripts/sync_to_supabase.py"])

def main():
    parser = argparse.ArgumentParser(description="CCC 入库脚本 v3")
    parser.add_argument("--json",  help="JSON 文件路径（方案A）")
    parser.add_argument("--image", help="图片路径（方案B）")
    parser.add_argument("--stdin", action="store_true", help="从 stdin 读取 JSON")
    args = parser.parse_args()

    if args.json:
        with open(args.json, "r", encoding="utf-8") as f:
            ingest_json(json.load(f))
        auto_sync()
    elif args.image:
        ingest_image(args.image)
        auto_sync()
    elif args.stdin:
        ingest_json(json.load(sys.stdin))
        auto_sync()
    else:
        parser.print_help()

if __name__ == "__main__":
    main()

