#!/usr/bin/env python3
"""
本地 ccc -> Supabase ccc 同步脚本
每次 ingest 后自动调用
"""

import psycopg2, os
from datetime import datetime

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

INCREMENTAL_TABLES = [
    "person_aliases",
    "clean_entities",
    "raw_documents",
    "documents",
    "clean_document_entities",
    "clean_graph_edges",
    "events",
    "claims",
    "cognitive_nodes",
    "cognitive_edges",
    "contradictions",
    "signals",
]

def get_max_id(cur, table):
    cur.execute(f"SELECT MAX(id) FROM ccc.{table}")
    return cur.fetchone()[0] or 0

def sync_incremental(local_cur, remote_cur, remote_conn, table):
    remote_max = get_max_id(remote_cur, table)
    local_max  = get_max_id(local_cur, table)

    if local_max <= remote_max:
        print(f"  {table}: 无新数据")
        return 0

    local_cur.execute(
        f"SELECT * FROM ccc.{table} WHERE id > %s ORDER BY id",
        (remote_max,)
    )
    rows = local_cur.fetchall()
    cols = [desc[0] for desc in local_cur.description]
    if not rows:
        return 0

    placeholders = ", ".join(["%s"] * len(cols))
    col_names    = ", ".join(cols)
    remote_cur.executemany(
        f"INSERT INTO ccc.{table} ({col_names}) VALUES ({placeholders}) ON CONFLICT (id) DO NOTHING",
        rows
    )
    remote_conn.commit()
    print(f"  {table}: 同步 {len(rows)} 条")
    return len(rows)

def sync_noise_library(local_cur, remote_cur, remote_conn):
    local_cur.execute("SELECT word FROM ccc.person_noise_library")
    local_words = {r[0] for r in local_cur.fetchall()}

    remote_cur.execute("SELECT word FROM ccc.person_noise_library")
    remote_words = {r[0] for r in remote_cur.fetchall()}

    new_words = local_words - remote_words
    if not new_words:
        print(f"  person_noise_library: 无新数据")
        return 0

    remote_cur.executemany(
        "INSERT INTO ccc.person_noise_library (word) VALUES (%s) ON CONFLICT DO NOTHING",
        [(w,) for w in new_words]
    )
    remote_conn.commit()
    print(f"  person_noise_library: 同步 {len(new_words)} 条")
    return len(new_words)

def main():
    print(f"\n{'='*50}")
    print(f"同步开始: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"{'='*50}")

    local_conn  = psycopg2.connect(**LOCAL_DB)
    remote_conn = psycopg2.connect(**SUPABASE_DB)
    local_cur   = local_conn.cursor()
    remote_cur  = remote_conn.cursor()

    total = 0

    for table in INCREMENTAL_TABLES:
        try:
            total += sync_incremental(local_cur, remote_cur, remote_conn, table)
        except Exception as e:
            print(f"  {table}: 错误 - {e}")
            remote_conn.rollback()

    try:
        total += sync_noise_library(local_cur, remote_cur, remote_conn)
    except Exception as e:
        print(f"  person_noise_library: 错误 - {e}")
        remote_conn.rollback()

    local_cur.close()
    remote_cur.close()
    local_conn.close()
    remote_conn.close()

    print(f"\n同步完成，共推送 {total} 条")
    print(f"{'='*50}\n")

if __name__ == "__main__":
    main()
