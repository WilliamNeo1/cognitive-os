import os
import json
import sys
import psycopg2

LOCAL_DB = {
    "host": "localhost", "port": 5432,
    "dbname": "postgres", "user": "postgres",
    "password": os.environ.get("LOCAL_PG_PASSWORD", ""),
}

def main(json_path):
    with open(json_path, 'r', encoding='utf-8') as f:
        obj = json.load(f)

    task_id = obj.get("task_id")
    entity_name = obj.get("entity_name")
    outcome_type = obj.get("outcome_type")
    source = f"REALITY_FETCH/{obj['sheet'].split('/')[1]}/{entity_name}"

    conn = psycopg2.connect(**LOCAL_DB)
    cur = conn.cursor()

    # 写入 raw_documents
    cur.execute("""
        INSERT INTO ccc.raw_documents (source, raw_content)
        VALUES (%s, %s)
        RETURNING id
    """, (source, json.dumps(obj, ensure_ascii=False)))
    raw_doc_id = cur.fetchone()[0]

    # 更新 reality_tasks 状态
    cur.execute("""
        UPDATE ccc.reality_tasks
        SET status = 'INGESTED', executed_manually = true
        WHERE task_id = %s
    """, (task_id,))

    conn.commit()
    print(f"写入 raw_documents id={raw_doc_id}, source={source}")
    print(f"reality_tasks task_id={task_id} 状态更新为 INGESTED")

    cur.close()
    conn.close()

if __name__ == "__main__":
    main(sys.argv[1])
