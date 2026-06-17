#!/usr/bin/env python3
"""
本地 ccc -> Supabase ccc 同步脚本
用时间戳做增量判断，解决 id 不对齐问题
"""

import psycopg2, os
from datetime import datetime

LOCAL_DB = {
    "host":     "localhost",
    "port": 5432,
    "dbname":   "postgres",
    "user":     "postgres",
    "password": os.environ.get("LOCAL_PG_PASSWORD", ""),
}

SUPABASE_DB = {
    "host": "aws-1-ap-southeast-2.pooler.supabase.com",
    "port": 6543,
    "dbname": "postgres",
    "user": "postgres.mgigbiblwqywcegkhjpu",
    "password": os.environ.get("SUPABASE_DB_PASSWORD", ""),
    "sslmode": "require",
    "connect_timeout": 30,
    "gssencmode": "disable",
    "keepalives": 1,
    "keepalives_idle": 30,
}

# 有 created_at 的表用时间戳，没有的用全量对比
TIMESTAMP_TABLES = [
    "person_aliases",
    "clean_entities",
    "raw_documents",
    "documents",
    "clean_document_entities",
    "clean_graph_edges",
    "events",
    "wenziyu_cases",
    "claims",
    "event_chains",
    "event_nodes",
    "causal_edges",
    "entity_profiles",
    "entity_trajectories",
    "behavioral_models",
    "contradiction_engine",
    "source_profiles",
    "cognitive_nodes",
    "cognitive_edges",
    "contradictions",
    "signals",
]

def get_remote_max_time(cur, table):
    try:
        cur.execute(f"SELECT MAX(created_at) FROM ccc.{table}")
        result = cur.fetchone()[0]
        return result
    except Exception:
        return None


def sync_clean_entities(local_cur, remote_cur, remote_conn):
    """sync clean_entities using entity_uuid as conflict key."""
    remote_max_time = get_remote_max_time(remote_cur, "clean_entities")
    if remote_max_time:
        local_cur.execute(
            "SELECT * FROM ccc.clean_entities WHERE created_at > %s ORDER BY created_at, id",
            (remote_max_time,)
        )
    else:
        local_cur.execute("SELECT * FROM ccc.clean_entities ORDER BY created_at, id")

    rows = local_cur.fetchall()
    if not rows:
        print("  clean_entities: 无新数据")
        return 0

    cols = [desc[0] for desc in local_cur.description]
    col_names = ", ".join(cols)
    placeholders = ", ".join(["%s"] * len(cols))
    update_cols = ", ".join([f"{c}=EXCLUDED.{c}" for c in cols if c not in ("id","entity_uuid","created_at")])

    inserted = skipped = 0
    for row in rows:
        try:
            remote_cur.execute(f"""
                INSERT INTO ccc.clean_entities ({col_names})
                VALUES ({placeholders})
                ON CONFLICT (entity_uuid) DO UPDATE SET {update_cols}
            """, row)
            if remote_cur.rowcount > 0:
                inserted += 1
            else:
                skipped += 1
        except Exception as e:
            remote_conn.rollback()
            skipped += 1
    remote_conn.commit()
    print(f"  clean_entities: 新增 {inserted} 条，跳过 {skipped} 条")
    return inserted

def sync_table(local_cur, remote_cur, remote_conn, table):
    remote_max_time = get_remote_max_time(remote_cur, table)

    if remote_max_time:
        local_cur.execute(
            f"SELECT * FROM ccc.{table} WHERE created_at > %s ORDER BY created_at, id",
            (remote_max_time,)
        )
    else:
        local_cur.execute(
            f"SELECT * FROM ccc.{table} ORDER BY created_at, id"
        )

    rows = local_cur.fetchall()
    if not rows:
        print(f"  {table}: 无新数据")
        return 0

    cols = [desc[0] for desc in local_cur.description]
    placeholders = ", ".join(["%s"] * len(cols))
    col_names = ", ".join(cols)

    inserted = 0
    skipped  = 0
    for row in rows:
        try:
            remote_cur.execute(f"""
                INSERT INTO ccc.{table} ({col_names})
                VALUES ({placeholders})
                ON CONFLICT (id) DO NOTHING
            """, row)
            if remote_cur.rowcount > 0:
                inserted += 1
            else:
                skipped += 1
        except Exception as e:
            remote_conn.rollback()
            print(f"  {table}: 行插入失败 - {e}")
            continue

    remote_conn.commit()
    if inserted > 0:
        print(f"  {table}: 新增 {inserted} 条" + (f"，跳过 {skipped} 条" if skipped else ""))
    else:
        print(f"  {table}: 无新数据")
    return inserted


def sync_documents(local_cur, remote_cur, remote_conn):
    """sync documents using content_hash as conflict key."""
    remote_max_time = get_remote_max_time(remote_cur, "documents")
    if remote_max_time:
        local_cur.execute(
            "SELECT * FROM ccc.documents WHERE created_at > %s ORDER BY created_at, id",
            (remote_max_time,)
        )
    else:
        local_cur.execute("SELECT * FROM ccc.documents ORDER BY created_at, id")
    rows = local_cur.fetchall()
    if not rows:
        print("  documents: 无新数据")
        return 0
    cols = [desc[0] for desc in local_cur.description]
    col_names = ", ".join(cols)
    placeholders = ", ".join(["%s"] * len(cols))
    inserted = skipped = 0
    for row in rows:
        try:
            remote_cur.execute(f"""
                INSERT INTO ccc.documents ({col_names})
                VALUES ({placeholders})
                ON CONFLICT (content_hash) DO NOTHING
            """, row)
            if remote_cur.rowcount > 0:
                inserted += 1
            else:
                skipped += 1
        except Exception as e:
            remote_conn.rollback()
            skipped += 1
    remote_conn.commit()
    if inserted > 0:
        print(f"  documents: 新增 {inserted} 条，跳过 {skipped} 条")
    else:
        print("  documents: 无新数据")
    return inserted


def sync_person_aliases(local_cur, remote_cur, remote_conn):
    """sync person_aliases using alias as conflict key."""
    remote_max_time = get_remote_max_time(remote_cur, "person_aliases")
    if remote_max_time:
        local_cur.execute(
            "SELECT * FROM ccc.person_aliases WHERE created_at > %s ORDER BY created_at, id",
            (remote_max_time,)
        )
    else:
        local_cur.execute("SELECT * FROM ccc.person_aliases ORDER BY created_at, id")
    rows = local_cur.fetchall()
    if not rows:
        print("  person_aliases: 无新数据")
        return 0
    cols = [desc[0] for desc in local_cur.description]
    col_names = ", ".join(cols)
    placeholders = ", ".join(["%s"] * len(cols))
    inserted = skipped = 0
    for row in rows:
        try:
            remote_cur.execute(f"""
                INSERT INTO ccc.person_aliases ({col_names})
                VALUES ({placeholders})
                ON CONFLICT (alias) DO NOTHING
            """, row)
            if remote_cur.rowcount > 0:
                inserted += 1
            else:
                skipped += 1
        except Exception as e:
            remote_conn.rollback()
            skipped += 1
    remote_conn.commit()
    if inserted > 0:
        print(f"  person_aliases: 新增 {inserted} 条，跳过 {skipped} 条")
    else:
        print("  person_aliases: 无新数据")
    return inserted

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
    for table in TIMESTAMP_TABLES:
        try:
            total += sync_table(local_cur, remote_cur, remote_conn, table)
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
