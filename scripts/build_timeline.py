#!/usr/bin/env python3
"""
build_timeline.py v2 — 时序因果链构建
包含: P2.5 temporal fields + trajectory scoring + previous/next linking
"""

import psycopg2, os
from datetime import datetime, timezone

LOCAL_DB = {
    "host": "localhost", "port": 5432,
    "dbname": "postgres", "user": "postgres",
    "password": os.environ.get("LOCAL_PG_PASSWORD", ""),
}

ENTITY_KEYWORDS = {
    "习近平": ["习近平","包子","xjp","枞阳帮","张红文","曹建国","林宗棠","安徽视察"],
    "特朗普": ["特朗普","川普","Trump","国会山"],
    "马云":   ["马云","阿里巴巴","潘多拉"],
    "哈马斯": ["哈马斯","Hamas","加沙"],
    "ISIS":   ["ISIS","伊斯兰国","Khorasan"],
    "美联储": ["美联储","QE","量化宽松","UAW","罢工"],
    "中共":   ["中共","中国政府","上海封城","新冠","COVID","胡锦涛","周正毅","北京","水淹"],
    "乌克兰": ["乌克兰","俄罗斯入侵","Nord Stream"],
    "俄罗斯": ["俄罗斯","普京","Shiplyuk","哈巴罗夫斯克"],
    "以色列": ["以色列","伊斯坦堡"],
    "薄熙来": ["薄熙来","薄一波","胡耀邦","李丹宇"],
    "香港":   ["香港","元朗","福建帮","洗钱","长江换汇"],
    "蔡英文": ["蔡英文","民进党"],
    "Pavel Dourov": ["Dourov","Telegram","Pavel"],
    "日本":   ["日本","深圳日本"],
    "中国社会": ["田文华","三鹿","张新伟","连云港"],
}

PRESSURE_MAP = {
    "习近平": "political", "特朗普": "political",
    "马云": "financial",   "哈马斯": "military",
    "ISIS": "military",    "美联储": "financial",
    "中共": "political",   "乌克兰": "military",
    "俄罗斯": "military",  "以色列": "military",
    "薄熙来": "political", "香港": "political",
    "蔡英文": "political", "Pavel Dourov": "media",
    "日本": "social",      "中国社会": "social",
}

def get_conn():
    return psycopg2.connect(**LOCAL_DB)

def find_or_create_entity(cur, name):
    cur.execute("""
        SELECT id FROM ccc.clean_entities
        WHERE lower(canonical_name) = lower(%s) LIMIT 1
    """, (name,))
    row = cur.fetchone()
    if row:
        return row[0]
    cur.execute("""
        INSERT INTO ccc.clean_entities
            (canonical_name, entity_type, source, confidence)
        VALUES (%s, 'PERSON', 'timeline_auto', 0.8)
        RETURNING id
    """, (name,))
    return cur.fetchone()[0]

def match_entity(summary):
    s = summary.lower()
    for entity, keywords in ENTITY_KEYWORDS.items():
        if any(kw.lower() in s for kw in keywords):
            return entity
    return None

def infer_essence(summary):
    s = summary.lower()
    if any(w in s for w in ["被捕","逮捕","判刑","调查","拘留","被抓","架走","覆灭"]):
        return "法律压制"
    if any(w in s for w in ["攻击","袭击","爆炸","战争","轰炸","冲突","导弹"]):
        return "军事冲突"
    if any(w in s for w in ["量化宽松","利率","股市","经济","金融","洗钱","资产","罢工"]):
        return "金融压力"
    if any(w in s for w in ["当选","上任","就任","选举","连任"]):
        return "权力更迭"
    if any(w in s for w in ["抗议","示威","革命","游行","暴乱","袭击市民","封城"]):
        return "社会压力"
    if any(w in s for w in ["病毒","疫情","感染","死亡","核辐射","水淹","地震"]):
        return "灾难事件"
    if any(w in s for w in ["泄密","间谍","情报","文件","泄露"]):
        return "情报行动"
    if any(w in s for w in ["离婚","婚外","家族","出狱","寿宴"]):
        return "个人事件"
    return "待分类"

def infer_mechanism(summary):
    s = summary.lower()
    mechs = []
    if any(w in s for w in ["制裁","封锁","限制","罢工"]):
        mechs.append("经济制裁")
    if any(w in s for w in ["媒体","舆论","叙事","文件","泄露"]):
        mechs.append("叙事控制")
    if any(w in s for w in ["军事","武力","导弹","轰炸","攻击","袭击"]):
        mechs.append("武力威慑")
    if any(w in s for w in ["法律","判决","起诉","逮捕","调查","拘留"]):
        mechs.append("法律手段")
    if any(w in s for w in ["金融","资本","融资","洗钱","资产"]):
        mechs.append("金融手段")
    if any(w in s for w in ["选举","民主","投票","就任"]):
        mechs.append("政治手段")
    return mechs if mechs else ["待分析"]

def infer_direction(evs):
    if not evs:
        return "unknown"
    essences = [infer_essence(ev[1]) for ev in evs]
    escalating = sum(1 for e in essences if e in ["军事冲突","法律压制","社会压力"])
    deescalating = sum(1 for e in essences if e in ["权力更迭","个人事件"])
    if escalating > deescalating * 1.5:
        return "escalating"
    if deescalating > escalating:
        return "de-escalating"
    if len(evs) >= 3:
        return "volatile"
    return "stabilizing"

def calc_escalation_score(seq, total, essence):
    base = seq / max(total - 1, 1)
    boost = {"军事冲突": 0.3, "法律压制": 0.2, "社会压力": 0.15,
             "灾难事件": 0.1, "权力更迭": -0.1}.get(essence, 0)
    return min(1.0, max(0.0, base + boost))

def build():
    conn = get_conn()
    cur  = conn.cursor()

    # 清空旧数据
    cur.execute("DELETE FROM ccc.causal_edges")
    cur.execute("DELETE FROM ccc.event_nodes")
    cur.execute("DELETE FROM ccc.event_chains")
    conn.commit()
    print("🗑  清空旧数据")

    # 拿有时间的事件
    cur.execute("""
        SELECT id, event_summary, event_date, event_year, document_id
        FROM ccc.events
        WHERE event_date IS NOT NULL OR event_year IS NOT NULL
        ORDER BY event_date NULLS LAST, event_year
    """)
    events = cur.fetchall()

    # 去重
    seen = set()
    unique = []
    for ev in events:
        if ev[1] not in seen:
            seen.add(ev[1])
            unique.append(ev)
    print(f"📅 有时间事件: {len(events)} → 去重后: {len(unique)}")

    # 按实体分组
    entity_events = {}
    unmatched = []
    for ev in unique:
        entity = match_entity(ev[1])
        if entity:
            entity_events.setdefault(entity, []).append(ev)
        else:
            unmatched.append(ev[1][:60])

    matched_count = sum(len(v) for v in entity_events.items() if isinstance(v, list))
    print(f"🔗 匹配: {sum(len(v) for v in entity_events.values())} 条")
    if unmatched:
        print(f"❓ 未匹配: {len(unmatched)} 条")
        for s in unmatched:
            print(f"   - {s}")
    print()

    total_chains = 0
    total_nodes  = 0

    for entity_name, evs in entity_events.items():
        entity_id = find_or_create_entity(cur, entity_name)
        pressure  = PRESSURE_MAP.get(entity_name, "political")
        direction = infer_direction(evs)

        # 计算链的时间范围
        dates = [ev[2] for ev in evs if ev[2]]
        start_time = min(dates) if dates else None
        end_time   = max(dates) if dates else None
        duration   = (end_time - start_time).days if start_time and end_time else None

        # trajectory_score：节点数 × 平均escalation
        traj_score = round(len(evs) * 0.1, 2)

        cur.execute("""
            INSERT INTO ccc.event_chains
                (chain_name, entity_id, description, pressure_type, direction,
                 start_time, end_time, duration_days, trajectory_score)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
            RETURNING id
        """, (
            f"{entity_name}时间线", entity_id,
            f"{entity_name}相关事件因果链，共{len(evs)}个节点",
            pressure, direction,
            start_time, end_time, duration, traj_score
        ))
        chain_id = cur.fetchone()[0]
        total_chains += 1

        # 建节点
        node_ids = []
        for seq, ev in enumerate(evs):
            ev_id, summary, ev_date, ev_year, doc_id = ev
            essence   = infer_essence(summary)
            mechanism = infer_mechanism(summary)
            esc_score = calc_escalation_score(seq, len(evs), essence)

            ev_time = None
            if ev_date:
                ev_time = f"{ev_date} 00:00:00+00"
            elif ev_year:
                ev_time = f"{ev_year}-01-01 00:00:00+00"

            cur.execute("""
                INSERT INTO ccc.event_nodes
                    (chain_id, event_id, entity_id, event_time,
                     sequence_order, essence, mechanism, pressure,
                     signal_strength, causal_weight, escalation_score, decay_factor)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                RETURNING id
            """, (
                chain_id, ev_id, entity_id, ev_time,
                seq, essence, mechanism, pressure,
                0.7, 1.0, esc_score, 1.0
            ))
            node_ids.append(cur.fetchone()[0])
            total_nodes += 1

        # 更新 previous/next 链接
        for i, node_id in enumerate(node_ids):
            prev_id = node_ids[i-1] if i > 0 else None
            next_id = node_ids[i+1] if i < len(node_ids)-1 else None
            cur.execute("""
                UPDATE ccc.event_nodes
                SET previous_event_id = %s, next_event_id = %s
                WHERE id = %s
            """, (prev_id, next_id, node_id))

        # 建因果边
        for i in range(1, len(node_ids)):
            ev_cur = evs[i]
            ev_prv = evs[i-1]
            time_delta = 30
            if ev_cur[2] and ev_prv[2]:
                time_delta = (ev_cur[2] - ev_prv[2]).days
            esc_cur = calc_escalation_score(i, len(evs), infer_essence(ev_cur[1]))
            esc_prv = calc_escalation_score(i-1, len(evs), infer_essence(ev_prv[1]))
            strength = round(0.5 + (esc_cur - esc_prv) * 0.5, 3)
            bias = "escalating" if esc_cur > esc_prv else "de-escalating"

            cur.execute("""
                INSERT INTO ccc.causal_edges
                    (source_event_id, target_event_id, causal_type,
                     confidence, time_delta_days,
                     temporal_distance, causality_strength, directional_bias)
                VALUES (%s, %s, 'follows', 0.6, %s, %s, %s, %s)
                ON CONFLICT DO NOTHING
            """, (node_ids[i-1], node_ids[i], time_delta,
                  time_delta, strength, bias))

        print(f"  ✅ {entity_name}: {len(evs)}节点 "
              f"方向={direction} 压力={pressure} "
              f"时间={start_time}~{end_time}")

    conn.commit()
    cur.close()
    conn.close()

    print(f"\n{'='*50}")
    print(f"完成: {total_chains}条因果链，{total_nodes}个事件节点")
    print(f"{'='*50}")

if __name__ == "__main__":
    build()
