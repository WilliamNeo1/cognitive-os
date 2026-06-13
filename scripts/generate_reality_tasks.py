import os
import json
import psycopg2
from datetime import datetime, timezone

LOCAL_DB = {
    "host": "localhost", "port": 5432,
    "dbname": "postgres", "user": "postgres",
    "password": os.environ.get("LOCAL_PG_PASSWORD", ""),
}

def main():
    conn = psycopg2.connect(**LOCAL_DB)
    cur = conn.cursor()

    cur.execute("""
        SELECT DISTINCT cs.outcome_type, cs.entity_name, cs.signal_type, cs.signal_value
        FROM ccc.candidate_signals cs
        WHERE cs.gap_engine_verdict = 'INSUFFICIENT_SAMPLE'
          AND cs.sample_mode = 'TIME_SERIES'
          AND cs.entity_name IS NOT NULL
        ORDER BY cs.outcome_type, cs.entity_name
    """)
    signals = cur.fetchall()

    tasks = []
    for outcome_type, entity_name, signal_type, signal_value in signals:
        cur.execute("""
            SELECT r.source_name, r.access_method, r.notes, o.rationale
            FROM ccc.outcome_source_routing o
            JOIN ccc.reality_source_registry r ON r.source_name = o.source_name
            WHERE o.outcome_type = %s AND o.priority = 1
        """, (outcome_type,))
        row = cur.fetchone()
        if not row:
            continue
        source_name, access_method, notes, rationale = row

        task = {
            "task_id": f"{outcome_type}_{entity_name}_{datetime.now(timezone.utc).strftime('%Y%m%d')}",
            "entity_name": entity_name,
            "outcome_type": outcome_type,
            "triggering_signal": signal_type,
            "signal_value": float(signal_value) if signal_value else None,
            "target_source": source_name,
            "access_method": access_method,
            "source_notes": notes,
            "routing_rationale": rationale,
            "suggested_query": f"{entity_name} latest news",
        }
        tasks.append(task)

    print(json.dumps(tasks, ensure_ascii=False, indent=2))

    cur.execute("""
        CREATE TABLE IF NOT EXISTS ccc.reality_tasks (
            id bigserial PRIMARY KEY,
            task_id text UNIQUE,
            entity_name text,
            outcome_type text,
            target_source text,
            suggested_query text,
            status text DEFAULT 'PENDING' CHECK (status IN ('PENDING','EXECUTED_MANUAL','EXECUTED_AUTO','INGESTED')),
            executed_manually boolean DEFAULT false,
            created_at timestamptz DEFAULT now()
        )
    """)

    for t in tasks:
        cur.execute("""
            INSERT INTO ccc.reality_tasks (task_id, entity_name, outcome_type, target_source, suggested_query)
            VALUES (%s, %s, %s, %s, %s)
            ON CONFLICT (task_id) DO NOTHING
        """, (t["task_id"], t["entity_name"], t["outcome_type"], t["target_source"], t["suggested_query"]))

    conn.commit()
    cur.close()
    conn.close()
    print(f"\n生成 {len(tasks)} 个任务，已写入 ccc.reality_tasks")

if __name__ == "__main__":
    main()
