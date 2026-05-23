#!/usr/bin/env python3
"""
本地 ccc -> Supabase ccc 增量同步脚本
用法: python3 scripts/sync_to_supabase.py
"""

import psycopg2
import os
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

TABLES = [
    "entities",
    "documents",
    "document_entities",
    "graph_edges",
    "person_aliases",
    "events",
    "cognitive_nodes",
    "contradictions",
    "revision_log",
    "signals",
    "cognitive_edges",
]

def get_max_id(cur, table):
    cur.execute(f"SELECT MAX(id) FROM ccc.{table}")
    result = cur.fetchone()[0]
    return result or 0

def sync_table(local_cur, remote_cur, remote_conn, table):
    remote_max = get_max_id(remote_cur, table)
    local_max  = get_max_id(local_cur, table)

    if local_max <= remote_max:
        print(f"  {table}: 无新数据 (remote={remote_max}, local={local_max})")
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
    sql = f"""
        INSERT INTO ccc.{table} ({col_names})
        VALUES ({placeholders})
        ON CONFLICT (id) DO NOTHING
    """

    remote_cur.executemany(sql, rows)
    remote_conn.commit()
    print(f"  {table}: 同步 {len(rows)} 条 (id {remote_max+1} ~ {local_max})")
    return len(rows)

def main():
    print(f"\n{'='*50}")
    print(f"同步开始: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"{'='*50}")

    local_conn  = psycopg2.connect(**LOCAL_DB)
    remote_conn = psycopg2.connect(**SUPABASE_DB)
    local_cur   = local_conn.cursor()
    remote_cur  = remote_conn.cursor()

    total = 0
    for table in TABLES:
        try:
            count = sync_table(local_cur, remote_cur, remote_conn, table)
            total += count
        except Exception as e:
            print(f"  {table}: 错误 - {e}")
            remote_conn.rollback()

    local_cur.close()
    remote_cur.close()
    local_conn.close()
    remote_conn.close()

    print(f"\n{'='*50}")
    print(f"同步完成，共推送 {total} 条记录")
    print(f"{'='*50}\n")

if __name__ == "__main__":
    main()
