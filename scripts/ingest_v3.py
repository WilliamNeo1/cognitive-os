#!/usr/bin/env python3
"""
ingest_v3.py — 统一入库脚本 (Phase D.5.1: entity_upsert 接入版 / P2)
用法:
  方案A（手动）: python3 scripts/ingest_v3.py --json data.json
  方案B（自动）: python3 scripts/ingest_v3.py --image screenshot.png

============================================================
变更说明 (D.5.1 — Shared Entity Upsert Layer, P2)
============================================================
不再直接 SELECT/INSERT/UPDATE ccc.clean_entities。
所有实体写入改为调用 entity_upsert.upsert_entity()，统一路由：
  accept / accept_new -> 正常写入 clean_document_entities / person_aliases / 关系边
  review_queue        -> 类型冲突，跳过该实体的文档关联与关系边构建，仅打印 [SKIP]
  raw_staging         -> OCR噪音 / 低价值PERSON，跳过该实体

回归基准（来自 dump-postgres-202606150934.sql 的真实案例）：
  "英国" 在2026-06-09被ingest_v3先后创建为 PLACE(id=232,mention=1)
  和 GPE(id=339,mention=63) —— 这是同名不同type被当成两个独立实体的
  典型案例。本patch后，若重放产生"英国"+GPE且库中已有"英国"+PLACE，
  应进入 entity_review_queue (type_conflict)，不再创建新id。

5a/5b（关系边构建）调整：
  - 改为遍历 accepted_entities（已成功accept/accept_new的实体），
    src_id 直接使用 upsert_entity 返回的 entity_id，不再重复查询。
  - target(to_name) 的查找逻辑保持不变：按 canonical_name 模糊匹配
    已有实体（不限type），找不到则跳过并打印提示。
  - 被跳过(review_queue/raw_staging)的实体不会出现在
    clean_document_entities 中，因此自动不参与 5b co_occurrence 兜底。
============================================================
"""

import json, os, sys, hashlib, argparse
import psycopg2

from entity_upsert import upsert_entity, normalize_name

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

    # 3. entities — 改为 entity_upsert.upsert_entity()
    entities = data.get("entities", [])
    accepted_entities = []   # [{"name":..., "type":..., "entity_id":..., "raw":ent}]
    skipped_entities  = []   # [{"name":..., "type":..., "action":..., "reason":...}]

    for ent in entities:
        name  = ent.get("name", "").strip()
        etype = ent.get("type", "PERSON")
        if not name or len(name) < 2:
            continue

        result = upsert_entity(
            cur,
            {
                "canonical_name": name,
                "entity_type": etype,
                "mention_count": 1,
                "confidence": 0.9,
            },
            source="ingest_v3",
            # degree_hint: 本文档内"其他实体数量"，作为该实体潜在共现边数的
            # 下界估计——5b会给同文档内所有实体两两建co_occurrence边。
            # 不能传0：对任何"第一次出现"的新实体，创建瞬间mention必然=1、
            # 全图degree必然=0，若degree_hint硬编码0，门禁2(低价值PERSON)
            # 会拦截*所有*全新PERSON实体，无法进图。
            # 仅当本文档只提取出这1个实体时，degree_hint=0——此时"单实体
            # 孤立文档中的新PERSON"暂存待复查，符合D.5"分流不删除"原则。
            degree_hint=max(0, len(entities) - 1),
        )

        if result["action"] not in ("accept", "accept_new"):
            skipped_entities.append({
                "name": name, "type": etype,
                "action": result["action"], "reason": result["reason"],
            })
            print(f"   [SKIP] 实体: {name} ({etype}) -> {result['action']} ({result['reason']})")
            continue

        entity_id = result["entity_id"]
        accepted_entities.append({"name": name, "type": etype, "entity_id": entity_id, "raw": ent})

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

        tag = "新增" if result["action"] == "accept_new" else "已存在"
        print(f"   实体: {name} ({etype}) [{tag}]")

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

    # 5a. typed relations（从 accepted_entities 出发，被门禁跳过的实体不参与）
    for ent in accepted_entities:
        name   = ent["name"]
        src_id = ent["entity_id"]
        raw    = ent["raw"]

        # Phase 2.3: 每个实体只查一次 source_entity_uuid（不放进下面的
        # relations 循环，避免对同一个 src_id 重复查询）。
        # 查不到就跳过整个实体的关系构建，不允许写入 NULL endpoint uuid——
        # 这是 Phase 2.1 "endpoint anchor 不可漂移" 原则在写入路径上的落地。
        cur.execute("SELECT entity_uuid FROM ccc.clean_entities WHERE id = %s", (src_id,))
        src_uuid_row = cur.fetchone()
        if not src_uuid_row:
            print(f"   [SKIP] 关系源实体缺失 uuid: {name} source_entity_id={src_id}")
            continue
        src_uuid = src_uuid_row[0]

        for rel in raw.get("relations", []):
            to_name_raw = rel.get("to", "").strip()
            to_name = normalize_name(to_name_raw)
            rel_type = rel.get("type", "co_occurrence")
            direction = rel.get("direction", "source_to_target")
            if not to_name:
                continue

            # target 查找逻辑保持不变：按 canonical_name 模糊匹配已有实体
            # （不限type；找不到则跳过，不创建——target的创建/门禁判定
            #  应在它自己作为 entities[] 条目被 upsert_entity 处理时发生）
            cur.execute("SELECT id, entity_uuid FROM ccc.clean_entities WHERE lower(canonical_name) = lower(%s) LIMIT 1", (to_name,))
            tgt_row = cur.fetchone()
            if not tgt_row:
                print(f"   [SKIP] 关系: {name} --[{rel_type}]--> {to_name} (target未找到，可能在raw_staging/review_queue)")
                continue
            tgt_id, tgt_uuid = tgt_row
            if not tgt_uuid:
                print(f"   [SKIP] 关系目标实体缺失 uuid: {to_name} target_entity_id={tgt_id}")
                continue

            cur.execute("""
                SELECT id FROM ccc.clean_graph_edges
                WHERE source_entity_id = %s AND target_entity_id = %s
                  AND relation_type = %s
            """, (src_id, tgt_id, rel_type))
            if cur.fetchone():
                cur.execute("""
                    UPDATE ccc.clean_graph_edges
                    SET weight = weight + 1, document_count = document_count + 1
                    WHERE source_entity_id = %s AND target_entity_id = %s
                      AND relation_type = %s
                """, (src_id, tgt_id, rel_type))
            else:
                cur.execute("""
                    SELECT id, weight, document_count
                    FROM ccc.clean_graph_edges
                    WHERE source_entity_id = %s
                      AND target_entity_id = %s
                      AND relation_type = 'typed'
                      AND relation_label = %s
                """, (src_id, tgt_id, rel_type))
                existing = cur.fetchone()
                if existing:
                    edge_id, old_weight, old_doc_count = existing
                    cur.execute("""
                        UPDATE ccc.clean_graph_edges
                        SET weight = %s, document_count = %s
                        WHERE id = %s
                    """, (old_weight + 1, old_doc_count + 1, edge_id))
                else:
                    cur.execute("""
                        INSERT INTO ccc.clean_graph_edges
                            (source_entity_id, target_entity_id, source_entity_uuid, target_entity_uuid,
                             relation_type, relation_label, relation_direction, weight, document_count)
                        VALUES (%s, %s, %s, %s, 'typed', %s, %s, 1.0, 1)
                    """, (src_id, tgt_id, src_uuid, tgt_uuid, rel_type, direction))

            print(f"   关系: {name} --[{rel_type}]--> {to_name}")

    # 5b. co_occurrence（同文档内已accept的实体两两连接，作为兜底；
    #     被门禁跳过的实体不在 clean_document_entities 中，自动不参与）
    cur.execute("""
        SELECT entity_id FROM ccc.clean_document_entities
        WHERE document_id = %s
    """, (doc_id,))
    ent_ids = [r[0] for r in cur.fetchall()]

    # Phase 2.3: 批量取一次 id -> entity_uuid 映射，避免在下面 N^2 配对
    # 循环里对每一对都单独查询
    entity_uuid_map = {}
    if ent_ids:
        cur.execute("""
            SELECT id, entity_uuid FROM ccc.clean_entities
            WHERE id = ANY(%s)
        """, (ent_ids,))
        entity_uuid_map = {row[0]: row[1] for row in cur.fetchall()}

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
                src_uuid = entity_uuid_map.get(src)
                tgt_uuid = entity_uuid_map.get(tgt)
                if not src_uuid or not tgt_uuid:
                    print(f"   [SKIP] co_occurrence endpoint uuid missing: {src}->{tgt}")
                    continue
                cur.execute("""
                    INSERT INTO ccc.clean_graph_edges
                        (source_entity_id, target_entity_id, source_entity_uuid, target_entity_uuid,
                         relation_type, weight, document_count)
                    VALUES (%s, %s, %s, %s, 'co_occurrence', 1.0, 1)
                """, (src, tgt, src_uuid, tgt_uuid))

    conn.commit()
    cur.close()
    conn.close()

    print(f"\n✅ 入库完成 doc_id={doc_id}")
    print(f"   实体: {len(accepted_entities)} 个入图 / {len(skipped_entities)} 个分流(raw_staging/review_queue) / 共 {len(entities)} 个")
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
    if os.environ.get("SKIP_AUTO_SYNC"):
        print("\n⏭️  SKIP_AUTO_SYNC=1，跳过 Q→W 同步（本次仅测试本地ingest门禁）")
        return
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
