#!/usr/bin/env python3
"""
Q->W Promotion Gate v1
Pushes validated local P7 decision outputs to Supabase w_decision_public_v1.
Direction: Q (local) -> W (cloud). One-way only.
Trigger: Manual. Always dry-run first.
"""

import os, sys, psycopg2, argparse
from datetime import datetime, timezone

REQUIRED_SCHEMA_VERSION = 'decision_engine_output_v1'
VALID_FINAL_DECISIONS   = {'DO', 'DO_WITH_CAUTION', 'MONITOR_ONLY', 'WAIT', 'NO_GO'}
VALID_FINAL_PRIORITIES  = {'P0', 'P1', 'P2', 'P3', 'P4'}
MIN_CHECKPOINT_ID       = 15
SOURCE_COMMIT           = '2b14405'

LOCAL_DB = {
    "host":     "localhost",
    "port":     5432,
    "dbname":   "postgres",
    "user":     "postgres",
    "password": os.environ.get("LOCAL_PG_PASSWORD", ""),
}

SUPABASE_DB = {
    "host":            "aws-1-ap-southeast-2.pooler.supabase.com",
    "port":            5432,
    "dbname":          "postgres",
    "user":            "postgres.mgigbiblwqywcegkhjpu",
    "password":        os.environ.get("SUPABASE_DB_PASSWORD", ""),
    "sslmode":         "require",
    "connect_timeout": 30,
    "keepalives":      1,
    "keepalives_idle": 30,
}

ENTITIES = ['习近平', '普京', '特朗普', '中共', '美联储', 'WEF']

def fetch_local(entities):
    conn = psycopg2.connect(**LOCAL_DB)
    cur  = conn.cursor()
    rows = []
    for entity in entities:
        cur.execute("SELECT ccc.decision_engine_v1(%s)", (entity,))
        result = cur.fetchone()[0]
        rows.append((entity, result))
    cur.close(); conn.close()
    return rows

def gate_check(entity, r):
    errors = []
    if r.get('schema_version') != REQUIRED_SCHEMA_VERSION:
        errors.append(f"schema_version mismatch: {r.get('schema_version')}")
    if r.get('final_decision') not in VALID_FINAL_DECISIONS:
        errors.append(f"invalid final_decision: {r.get('final_decision')}")
    if r.get('final_priority') not in VALID_FINAL_PRIORITIES:
        errors.append(f"invalid final_priority: {r.get('final_priority')}")
    if not r.get('final_instruction'):
        errors.append("final_instruction is null")
    score = r.get('decision_score', -1)
    if not (0 <= float(score) <= 1):
        errors.append(f"decision_score out of range: {score}")
    return errors

def build_payload(entity, r):
    return {
        'q':                       entity,
        'canonical_entity':        r.get('entity', entity),
        'final_decision':          r['final_decision'],
        'final_priority':          r['final_priority'],
        'decision_score':          float(r['decision_score']),
        'final_instruction':       r['final_instruction'],
        'action_status':           r.get('action_status'),
        'action_level':            r.get('action_level'),
        'action_mode':             r.get('action_mode'),
        'risk_boundary':           r.get('risk_boundary'),
        'review_trigger':          r.get('review_trigger'),
        'primary_rule':            r.get('decision_reason', {}).get('primary_rule'),
        'schema_version':          r.get('schema_version'),
        'source_checkpoint_label': 'SQLV1_locked',
        'source_checkpoint_id':    MIN_CHECKPOINT_ID,
        'source_commit':           SOURCE_COMMIT,
        'source_generated_at':     r.get('generated_at'),
        'search_text':             f"{entity} {r['final_decision']} {r['final_priority']}",
        'tags':                    [r['final_decision'], r['final_priority'], r.get('action_mode', '')],
    }

def push_payload(cur, conn, p):
    cur.execute("""
        INSERT INTO ccc.w_decision_public_v1 (
            q, canonical_entity, final_decision, final_priority,
            decision_score, final_instruction, action_status, action_level,
            action_mode, risk_boundary, review_trigger, primary_rule,
            schema_version, source_checkpoint_label, source_checkpoint_id,
            source_commit, source_generated_at, search_text, tags
        ) VALUES (
            %(q)s, %(canonical_entity)s, %(final_decision)s, %(final_priority)s,
            %(decision_score)s, %(final_instruction)s, %(action_status)s, %(action_level)s,
            %(action_mode)s, %(risk_boundary)s, %(review_trigger)s, %(primary_rule)s,
            %(schema_version)s, %(source_checkpoint_label)s, %(source_checkpoint_id)s,
            %(source_commit)s, %(source_generated_at)s, %(search_text)s, %(tags)s
        )
        ON CONFLICT (canonical_entity)
        DO UPDATE SET
            final_decision          = EXCLUDED.final_decision,
            final_priority          = EXCLUDED.final_priority,
            decision_score          = EXCLUDED.decision_score,
            final_instruction       = EXCLUDED.final_instruction,
            action_status           = EXCLUDED.action_status,
            action_level            = EXCLUDED.action_level,
            action_mode             = EXCLUDED.action_mode,
            risk_boundary           = EXCLUDED.risk_boundary,
            review_trigger          = EXCLUDED.review_trigger,
            primary_rule            = EXCLUDED.primary_rule,
            schema_version          = EXCLUDED.schema_version,
            source_checkpoint_label = EXCLUDED.source_checkpoint_label,
            source_checkpoint_id    = EXCLUDED.source_checkpoint_id,
            source_commit           = EXCLUDED.source_commit,
            source_generated_at     = EXCLUDED.source_generated_at,
            search_text             = EXCLUDED.search_text,
            tags                    = EXCLUDED.tags,
            pushed_at               = now()
    """, p)
    conn.commit()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--apply',   action='store_true')
    args = parser.parse_args()

    if not args.dry_run and not args.apply:
        print("Usage: q_to_w_sync.py [--dry-run | --apply]"); sys.exit(1)

    rows = fetch_local(ENTITIES)

    passed, blocked, payloads = [], [], []
    for entity, r in rows:
        if not r.get('ok'):
            blocked.append((entity, [f"p6 error: {r.get('error')}"]))
            continue
        errors = gate_check(entity, r)
        if errors:
            blocked.append((entity, errors))
        else:
            payloads.append(build_payload(entity, r))
            passed.append(entity)

    print(f"\nQ->W Promotion Gate v1 -- {'DRY RUN' if args.dry_run else 'APPLY'}")
    print(f"  通过准入: {len(passed)}  ->  {passed}")
    print(f"  阻断:     {len(blocked)}")
    for e, errs in blocked:
        print(f"    x {e}: {errs}")

    if args.dry_run:
        print("\n[DRY RUN] 未写入任何数据。确认无误后跑 --apply")
        return

    remote_conn = psycopg2.connect(**SUPABASE_DB)
    remote_cur  = remote_conn.cursor()
    pushed = 0
    for p in payloads:
        try:
            push_payload(remote_cur, remote_conn, p)
            print(f"  pushed: {p['canonical_entity']} -> {p['final_decision']} / {p['final_priority']}")
            pushed += 1
        except Exception as e:
            remote_conn.rollback()
            print(f"  FAILED: {p['canonical_entity']} -> {e}")
    remote_cur.close(); remote_conn.close()

    print(f"\nDone: {pushed}/{len(payloads)} pushed at {datetime.now(timezone.utc).isoformat()}")

if __name__ == '__main__':
    main()
