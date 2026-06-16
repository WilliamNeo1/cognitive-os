#!/usr/bin/env python3
"""
ingest_real_history.py — Phase D.5.1 entity_upsert 接入版 (P3)
从 ccc.raw_documents WHERE source LIKE 'REAL_HISTORY/%'
→ 写入 ccc.documents
→ 提取实体 → ccc.clean_entities + ccc.clean_document_entities

用法：
    export LOCAL_PG_PASSWORD=""
    python3 ingest_real_history.py [--dry-run] [--batch 100] [--limit 500]

说明：
    - 不依赖 ingest_v3.py，直接复用相同表结构
    - 实体提取：基于已知实体名单 + 简单规则（不用 NLP，不联网）
    - 已存在的 content_hash 跳过（幂等）
    - dry-run 模式只打印，不写库

============================================================
变更说明 (D.5.1 — Shared Entity Upsert Layer, P3)
============================================================
不再直接 SELECT/INSERT/UPDATE ccc.clean_entities。
实体写入改为调用 entity_upsert.upsert_entity()：
  accept / accept_new -> 正常写入 clean_document_entities
  review_queue        -> 类型冲突（本脚本的 KNOWN_ENTITIES 类型与已有
                          clean_entities 记录不一致），跳过该实体的
                          文档关联，仅计入 skipped_ents
  raw_staging         -> OCR噪音 / 低价值PERSON，跳过

degree_hint = max(0, len(entities) - 1) —— 同 P2，避免单文档内
"第一次出现的新PERSON"被门禁2误判为低价值（理由见 ingest_v3.py 注释）。

dry-run 路径不变：仍只调用 extract_entities() 打印，不调用
upsert_entity()，不连DB写操作。
============================================================
"""

import os, sys, json, hashlib, argparse, re
import psycopg2
from psycopg2.extras import execute_values

from entity_upsert import upsert_entity

LOCAL_DB = {
    "host":     "localhost",
    "port":     5432,
    "dbname":   "postgres",
    "user":     "postgres",
    "password": os.environ.get("LOCAL_PG_PASSWORD", ""),
}

# ── 已知实体名单（基于 Q 侧 entity_profiles + 常见历史人物）──
KNOWN_ENTITIES = {
    # PERSON
    "习近平": "PERSON", "毛泽东": "PERSON", "邓小平": "PERSON",
    "江泽民": "PERSON", "胡锦涛": "PERSON", "李克强": "PERSON",
    "普京":   "PERSON", "特朗普": "PERSON", "拜登":   "PERSON",
    "马云":   "PERSON", "马化腾": "PERSON", "任正非": "PERSON",
    "薄熙来": "PERSON", "周永康": "PERSON", "林彪":   "PERSON",
    "刘少奇": "PERSON", "彭德怀": "PERSON", "赵紫阳": "PERSON",
    "希特勒": "PERSON", "斯大林": "PERSON", "列宁":   "PERSON",
    "罗斯福": "PERSON", "丘吉尔": "PERSON", "戈尔巴乔夫": "PERSON",
    "蒋介石": "PERSON", "孙中山": "PERSON", "袁世凯": "PERSON",
    "石正丽": "PERSON", "李文亮": "PERSON", "艾未未": "PERSON",
    "柯文哲": "PERSON", "于品海": "PERSON",
    # ORG
    "中共":   "ORG", "中国共产党": "ORG", "国民党": "ORG",
    "美联储": "ORG", "WEF": "ORG", "联合国": "ORG",
    "CIA":    "ORG", "FBI": "ORG", "WHO": "ORG",
    "解放军": "ORG", "公安部": "ORG", "国安部": "ORG",
    "美军":   "ORG", "北约": "ORG", "华约": "ORG",
    "纳粹":   "ORG", "法西斯": "ORG",
    # GPE
    "中国":   "GPE", "美国": "GPE", "俄罗斯": "GPE",
    "苏联":   "GPE", "台湾": "GPE", "香港":   "GPE",
    "日本":   "GPE", "德国": "GPE", "英国":   "GPE",
    "法国":   "GPE", "以色列": "GPE", "乌克兰": "GPE",
    "朝鲜":   "GPE", "韩国": "GPE", "越南":   "GPE",
    "新疆":   "GPE", "西藏": "GPE",
}

# 从文本中匹配已知实体
def extract_entities(text):
    found = {}
    for name, etype in KNOWN_ENTITIES.items():
        if name in text:
            found[name] = etype
    return [{"name": k, "type": v} for k, v in found.items()]

def hash_content(text):
    return hashlib.md5(text.encode()).hexdigest()

def get_conn():
    return psycopg2.connect(**LOCAL_DB)

def process_batch(cur, conn, rows, dry_run):
    inserted_docs = 0
    skipped_docs  = 0
    inserted_ents = 0
    skipped_ents  = 0   # 新增：被 upsert_entity 分流(raw_staging/review_queue)的实体数

    for raw_doc_id, source, raw_content in rows:
        try:
            obj = json.loads(raw_content)
        except json.JSONDecodeError:
            obj = {"text": raw_content}

        text = obj.get("text", raw_content)
        if not text or len(text.strip()) < 4:
            continue

        # 构建 documents.content（完整 JSON，和 ingest_v3 格式一致）
        full_content = json.dumps({
            "raw_content": text,
            "source_type": source,
            "sheet":       obj.get("sheet"),
            "era":         obj.get("era"),
            "extracted_year": obj.get("extracted_year"),
            "doc_type":    obj.get("doc_type"),
            "language":    obj.get("language"),
            "tags":        obj.get("tags", []),
            "entities":    [],
        }, ensure_ascii=False)

        content_hash = hash_content(full_content)

        if dry_run:
            entities = extract_entities(text)
            print(f"  [DRY] raw_doc={raw_doc_id} | {text[:50]}... | entities={[e['name'] for e in entities]}")
            inserted_docs += 1
            continue

        # INSERT documents（幂等）
        cur.execute("""
            INSERT INTO ccc.documents (raw_document_id, content, content_hash, created_at)
            VALUES (%s, %s, %s, now())
            ON CONFLICT (content_hash) DO NOTHING
            RETURNING id
        """, (raw_doc_id, full_content, content_hash))
        row = cur.fetchone()
        if row:
            doc_id = row[0]
            inserted_docs += 1
        else:
            cur.execute("SELECT id FROM ccc.documents WHERE content_hash = %s", (content_hash,))
            doc_id = cur.fetchone()[0]
            skipped_docs += 1

        # 实体提取 — 改为 entity_upsert.upsert_entity()
        entities = extract_entities(text)
        for ent in entities:
            name  = ent["name"]
            etype = ent["type"]

            result = upsert_entity(
                cur,
                {
                    "canonical_name": name,
                    "entity_type": etype,
                    "mention_count": 1,
                    "confidence": 0.85,
                },
                source="ingest_real_history",
                # 同 ingest_v3 P2：避免"单文档内首次出现的新PERSON"被门禁2
                # (低价值PERSON, mention=1且degree=0)误判而无法入图。
                degree_hint=max(0, len(entities) - 1),
            )

            if result["action"] not in ("accept", "accept_new"):
                skipped_ents += 1
                continue

            entity_id = result["entity_id"]
            if result["action"] == "accept_new":
                inserted_ents += 1

            # upsert clean_document_entities
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

        conn.commit()

    return inserted_docs, skipped_docs, inserted_ents, skipped_ents

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true", help="只打印，不写库")
    parser.add_argument("--batch",   type=int, default=200,  help="每批处理条数")
    parser.add_argument("--limit",   type=int, default=0,    help="最多处理条数（0=全部）")
    parser.add_argument("--sheet",   type=str, default="",   help="只处理某个 sheet，如 '2019～'")
    args = parser.parse_args()

    conn = get_conn()
    cur  = conn.cursor()

    # 查询待处理记录
    where = "WHERE rd.source LIKE 'REAL_HISTORY/%'"
    if args.sheet:
        where += f" AND rd.source = 'REAL_HISTORY/{args.sheet}'"

    # 跳过已经在 documents 里的（通过 raw_document_id 关联）
    query = f"""
        SELECT rd.id, rd.source, rd.raw_content
        FROM ccc.raw_documents rd
        LEFT JOIN ccc.documents d ON d.raw_document_id = rd.id
        {where}
        AND d.id IS NULL
        ORDER BY rd.id
    """
    if args.limit > 0:
        query += f" LIMIT {args.limit}"

    cur.execute(query)
    all_rows = cur.fetchall()
    total = len(all_rows)

    print(f"\ningest_real_history.py {'[DRY RUN]' if args.dry_run else '[APPLY]'}")
    print(f"待处理：{total} 条（已跳过已处理记录）")
    if args.sheet:
        print(f"只处理：{args.sheet}")
    print()

    total_docs = total_skip = total_ents = total_skip_ents = 0
    batch_size = args.batch

    for i in range(0, total, batch_size):
        batch = all_rows[i:i+batch_size]
        d, s, e, se = process_batch(cur, conn, batch, args.dry_run)
        total_docs += d
        total_skip += s
        total_ents += e
        total_skip_ents += se
        done = min(i + batch_size, total)
        print(f"  [{done}/{total}] 新增文档={d} 跳过={s} 新增实体={e} 分流实体={se}")

    print(f"\n完成：")
    print(f"  新增 documents:      {total_docs}")
    print(f"  跳过（已存在）:       {total_skip}")
    print(f"  新增 clean_entities: {total_ents}")
    print(f"  分流(raw_staging/review_queue): {total_skip_ents}")

    cur.close()
    conn.close()

if __name__ == "__main__":
    main()
