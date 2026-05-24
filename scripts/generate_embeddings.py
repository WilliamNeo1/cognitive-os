#!/usr/bin/env python3
"""
本地生成 bge-m3 embedding 并写入本地 + Supabase
用法: python3 scripts/generate_embeddings.py
"""

import psycopg2
import os
import json
from sentence_transformers import SentenceTransformer

LOCAL_DB = {
    "host":     "localhost",
    "port":     5432,
    "dbname":   "postgres",
    "user":     "postgres",
    "password": os.environ.get("LOCAL_PG_PASSWORD", ""),
}

SUPABASE_DB = {
    "host":     "aws-1-ap-southeast-2.pooler.supabase.com",
    "port":     5432,
    "dbname":   "postgres",
    "user":     "postgres.mgigbiblwqywcegkhjpu",
    "password": os.environ.get("SUPABASE_DB_PASSWORD", ""),
}

BATCH_SIZE = 32

def main():
    print("加载模型 BAAI/bge-m3 ...")
    model = SentenceTransformer("BAAI/bge-m3")
    print("模型加载完成")

    local_conn  = psycopg2.connect(**LOCAL_DB)
    remote_conn = psycopg2.connect(**SUPABASE_DB)
    local_cur   = local_conn.cursor()
    remote_cur  = remote_conn.cursor()

    # 先修改本地 embedding 列维度
    print("检查本地 embedding 列维度...")
    try:
        local_cur.execute("UPDATE ccc.documents SET embedding = NULL WHERE embedding IS NOT NULL")
        local_cur.execute("ALTER TABLE ccc.documents ALTER COLUMN embedding TYPE vector(1024) USING NULL")
        local_conn.commit()
        print("本地 embedding 列已更新为 1024 维")
    except Exception as e:
        local_conn.rollback()
        print(f"列维度已正确或跳过: {e}")

    # 拿所有没有 embedding 的文档
    local_cur.execute("""
        SELECT id, content FROM ccc.documents
        WHERE embedding IS NULL
        ORDER BY id
    """)
    rows = local_cur.fetchall()
    total = len(rows)
    print(f"需要生成 embedding 的文档: {total} 条")

    done = 0
    for i in range(0, total, BATCH_SIZE):
        batch = rows[i:i+BATCH_SIZE]
        ids     = [r[0] for r in batch]
        texts   = [r[1][:2000] for r in batch]  # 截断超长文本

        # 生成 embedding
        embeddings = model.encode(texts, normalize_embeddings=True, show_progress_bar=False)

        # 写入本地
        for doc_id, emb in zip(ids, embeddings):
            vec_str = "[" + ",".join(map(str, emb.tolist())) + "]"
            local_cur.execute(
                "UPDATE ccc.documents SET embedding = %s::vector, embedding_model = 'bge-m3', embedding_created_at = now() WHERE id = %s",
                (vec_str, doc_id)
            )
        local_conn.commit()

        # 写入 Supabase
        for doc_id, emb in zip(ids, embeddings):
            vec_str = "[" + ",".join(map(str, emb.tolist())) + "]"
            try:
                remote_cur.execute(
                    "UPDATE ccc.documents SET embedding = %s::vector, embedding_model = 'bge-m3', embedding_created_at = now() WHERE id = %s",
                    (vec_str, doc_id)
                )
            except Exception as e:
                print(f"  Supabase 写入失败 doc_id={doc_id}: {e}")
                remote_conn.rollback()
        remote_conn.commit()

        done += len(batch)
        print(f"  进度: {done}/{total} ({done*100//total}%)")

    local_cur.close()
    remote_cur.close()
    local_conn.close()
    remote_conn.close()
    print("\n全部完成！")

if __name__ == "__main__":
    main()
