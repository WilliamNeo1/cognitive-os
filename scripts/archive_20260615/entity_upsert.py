#!/usr/bin/env python3
"""
scripts/entity_upsert.py
=========================
Phase D.5.1 — Shared Entity Upsert Layer

唯一允许写 ccc.clean_entities 的入口。

============================================================
铁律（对应 RSAL 核心原则3：增强结构，不扩张结构）
============================================================
任何脚本不得直接 INSERT/UPDATE ccc.clean_entities。
必须调用本模块的 upsert_entity() 或 find_entity_only()。

ingest_v3.py / ingest_real_history.py / build_timeline.py
三个写入路径全部改为调用本模块（见文件末尾 "接入示例"）。

============================================================
路由表
============================================================
情况                                    动作                          写入位置
--------------------------------------------------------------------------
canonical_name(归一化后) + entity_type   增加 mention_count            clean_entities (UPDATE)
  完全匹配已存在实体
canonical_name 匹配但 entity_type 不同   类型冲突，人工裁决             entity_review_queue (INSERT)
OCR噪音 / 长度异常                       不入主图                       entity_raw_staging (INSERT)
PERSON且 mention=1 且 degree=0           暂存待复查                     entity_raw_staging (INSERT)
全新正常实体                             创建新实体                     clean_entities (INSERT)
build_timeline 引用但不存在的实体         不创建，记录为待定引用          entity_review_queue (INSERT)

============================================================
新增表（首次调用时自动 CREATE IF NOT EXISTS）
============================================================
ccc.entity_raw_staging   — 暂存：OCR噪音 / 低价值PERSON，不进主图
ccc.entity_review_queue  — 人工队列：类型冲突 / build_timeline的悬空引用

两张表都不删除任何数据，只是分流；处理后人工/脚本可将其转入
clean_entities 或标记 resolved=true / status='RESOLVED'。
"""

from __future__ import annotations

import json
import re
import unicodedata
from dataclasses import dataclass, field
from typing import Optional


# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

@dataclass
class GuardrailConfig:
    min_name_length: int = 2
    max_name_length: int = 40
    ocr_junk_pattern: str = r"[\x00-\x1f\ufffd]|(.)\1{4,}"

    low_value_mention_threshold: int = 1
    low_value_degree_threshold: int = 0

    # 类型冲突默认建议（仅供 review_queue 展示，不自动执行）
    type_conflict_hint: dict = field(default_factory=lambda: {
        frozenset({"GPE", "PLACE"}): "建议统一为 GPE，PLACE 仅用于非主权地理实体",
    })


# ---------------------------------------------------------------------------
# 归一化 / 噪音判定（纯函数，无DB依赖，可单独单元测试）
# ---------------------------------------------------------------------------

def normalize_name(name: str) -> str:
    """统一全半角、去首尾空格、压缩内部空格。"""
    name = unicodedata.normalize("NFKC", name or "")
    name = name.strip()
    name = re.sub(r"\s+", "", name)
    return name


def looks_like_ocr_noise(name: str, config: GuardrailConfig) -> bool:
    if len(name) < config.min_name_length:
        return True
    if len(name) > config.max_name_length:
        return True
    if re.search(config.ocr_junk_pattern, name):
        return True
    return False


def type_conflict_hint(etype_a: str, etype_b: str, config: GuardrailConfig) -> str:
    key = frozenset({etype_a, etype_b})
    return config.type_conflict_hint.get(key, "无默认建议，需人工判断")


# ---------------------------------------------------------------------------
# DDL — 首次调用时自动建表
# ---------------------------------------------------------------------------

_DDL = """
CREATE TABLE IF NOT EXISTS ccc.entity_raw_staging (
  id bigserial PRIMARY KEY,
  canonical_name text NOT NULL,
  entity_type text,
  reject_reason text NOT NULL,
  source text,
  raw_payload jsonb,
  created_at timestamptz DEFAULT now(),
  resolved boolean DEFAULT false
);

CREATE TABLE IF NOT EXISTS ccc.entity_review_queue (
  id bigserial PRIMARY KEY,
  canonical_name text NOT NULL,
  new_type text,
  existing_type text,
  existing_entity_id bigint,
  conflict_kind text NOT NULL DEFAULT 'type_conflict',
  hint text,
  source text,
  raw_payload jsonb,
  created_at timestamptz DEFAULT now(),
  status text DEFAULT 'PENDING' CHECK (status IN ('PENDING','RESOLVED','DISMISSED'))
);
"""

_tables_ensured = False


def _ensure_tables(cur):
    global _tables_ensured
    if _tables_ensured:
        return
    cur.execute(_DDL)
    _tables_ensured = True


# ---------------------------------------------------------------------------
# upsert_entity — 唯一允许写 clean_entities 的函数
# ---------------------------------------------------------------------------

def upsert_entity(
    cur,
    raw_entity: dict,
    source: str,
    config: Optional[GuardrailConfig] = None,
    degree_hint: int = 0,
) -> dict:
    """
    raw_entity 期望字段:
        canonical_name (str, 必填)
        entity_type    (str, 默认 'PERSON')
        mention_count  (int, 默认 1)  -- 本次贡献的mention增量
        confidence     (float, 默认 0.85)

    source: 调用方标识，写入 source 列，便于追溯（如 'ingest_v3', 'ingest_real_history'）

    degree_hint: 本批次内该实体已知的共现边数（用于低价值PERSON判定）。
                  调用方如果不知道，传 0（默认更保守，更容易暂存；
                  这是有意的——宁可暂存待复查，不宁可误判为低价值）。

    返回:
        {"action": "accept" | "accept_new" | "review_queue" | "raw_staging",
         "entity_id": int | None,
         "reason": str | None,
         "detail": dict | None}

        action 含义:
          accept       命中已存在实体 (同名同type)，mention_count+1，entity_id=已存在id
          accept_new   全新实体，已 INSERT，entity_id=新id
          review_queue 类型冲突，未写入 clean_entities，entity_id=None
          raw_staging  OCR噪音 / 低价值PERSON，未写入 clean_entities，entity_id=None
    """
    config = config or GuardrailConfig()
    _ensure_tables(cur)

    name_raw = (raw_entity.get("canonical_name") or "").strip()
    etype = raw_entity.get("entity_type", "PERSON")
    mention_count = raw_entity.get("mention_count", 1)
    confidence = raw_entity.get("confidence", 0.85)
    norm = normalize_name(name_raw)

    # ---- 门禁1: OCR / 抽取噪音 ----
    if not norm or looks_like_ocr_noise(norm, config):
        cur.execute(
            """
            INSERT INTO ccc.entity_raw_staging
                (canonical_name, entity_type, reject_reason, source, raw_payload)
            VALUES (%s, %s, 'ocr_noise', %s, %s::jsonb)
            RETURNING id
            """,
            (name_raw, etype, source, json.dumps(raw_entity, ensure_ascii=False)),
        )
        staging_id = cur.fetchone()[0]
        return {
            "action": "raw_staging", "entity_id": None,
            "reason": "ocr_noise", "detail": {"staging_id": staging_id},
        }

    # ---- 门禁3: 同名同type → 命中已存在实体 ----
    cur.execute(
        """
        SELECT id FROM ccc.clean_entities
        WHERE lower(canonical_name) = lower(%s) AND entity_type = %s
        LIMIT 1
        """,
        (norm, etype),
    )
    row = cur.fetchone()
    if row:
        entity_id = row[0]
        cur.execute(
            "UPDATE ccc.clean_entities SET mention_count = mention_count + %s WHERE id = %s",
            (mention_count, entity_id),
        )
        return {"action": "accept", "entity_id": entity_id, "reason": None, "detail": None}

    # ---- 门禁4: 同名不同type → 类型冲突 review_queue ----
    cur.execute(
        """
        SELECT id, entity_type FROM ccc.clean_entities
        WHERE lower(canonical_name) = lower(%s) AND entity_type != %s
        LIMIT 1
        """,
        (norm, etype),
    )
    conflict = cur.fetchone()
    if conflict:
        existing_id, existing_type = conflict
        hint = type_conflict_hint(etype, existing_type, config)
        cur.execute(
            """
            INSERT INTO ccc.entity_review_queue
                (canonical_name, new_type, existing_type, existing_entity_id,
                 conflict_kind, hint, source, raw_payload)
            VALUES (%s, %s, %s, %s, 'type_conflict', %s, %s, %s::jsonb)
            RETURNING id
            """,
            (norm, etype, existing_type, existing_id, hint, source,
             json.dumps(raw_entity, ensure_ascii=False)),
        )
        queue_id = cur.fetchone()[0]
        return {
            "action": "review_queue", "entity_id": None,
            "reason": "type_conflict",
            "detail": {
                "queue_id": queue_id, "existing_entity_id": existing_id,
                "existing_type": existing_type, "hint": hint,
            },
        }

    # ---- 门禁2: 低价值 PERSON ----
    if (
        etype == "PERSON"
        and mention_count <= config.low_value_mention_threshold
        and degree_hint <= config.low_value_degree_threshold
    ):
        cur.execute(
            """
            INSERT INTO ccc.entity_raw_staging
                (canonical_name, entity_type, reject_reason, source, raw_payload)
            VALUES (%s, %s, 'low_value_person_pending', %s, %s::jsonb)
            RETURNING id
            """,
            (norm, etype, source, json.dumps(raw_entity, ensure_ascii=False)),
        )
        staging_id = cur.fetchone()[0]
        return {
            "action": "raw_staging", "entity_id": None,
            "reason": "low_value_person_pending", "detail": {"staging_id": staging_id},
        }

    # ---- 全新正常实体 ----
    cur.execute(
        """
        INSERT INTO ccc.clean_entities
            (canonical_name, entity_type, source, confidence, mention_count)
        VALUES (%s, %s, %s, %s, %s)
        RETURNING id
        """,
        (norm, etype, source, confidence, mention_count),
    )
    entity_id = cur.fetchone()[0]
    return {"action": "accept_new", "entity_id": entity_id, "reason": None, "detail": None}


# ---------------------------------------------------------------------------
# find_entity_only — build_timeline.py 专用：只读，不创建
# ---------------------------------------------------------------------------

def find_entity_only(
    cur,
    name: str,
    source: str,
    config: Optional[GuardrailConfig] = None,
    expected_type: Optional[str] = None,
) -> dict:
    """
    只查找已存在实体，找不到时**不创建**，写入 entity_review_queue
    (conflict_kind='unresolved_reference')，返回 entity_id=None。

    expected_type: 调用方对该实体类型的猜测（用于关键词字典场景，如
                    build_timeline.ENTITY_KEYWORDS 中"日本"→GPE）。
                    仅用于记录，不用于创建。

    返回:
        {"action": "found" | "unresolved",
         "entity_id": int | None,
         "entity_type": str | None,
         "detail": dict | None}
    """
    config = config or GuardrailConfig()
    _ensure_tables(cur)

    norm = normalize_name(name)

    cur.execute(
        """
        SELECT id, entity_type FROM ccc.clean_entities
        WHERE lower(canonical_name) = lower(%s)
        ORDER BY mention_count DESC NULLS LAST
        LIMIT 1
        """,
        (norm,),
    )
    row = cur.fetchone()
    if row:
        entity_id, entity_type = row
        if expected_type and entity_type != expected_type:
            # 找到了，但类型和调用方预期不一致——记录但仍返回找到的实体
            # （不阻断timeline构建，但留痕供后续审查）
            cur.execute(
                """
                INSERT INTO ccc.entity_review_queue
                    (canonical_name, new_type, existing_type, existing_entity_id,
                     conflict_kind, hint, source, raw_payload)
                VALUES (%s, %s, %s, %s, 'reference_type_mismatch',
                        '调用方预期类型与clean_entities记录不一致，仅记录不阻断', %s, %s::jsonb)
                """,
                (norm, expected_type, entity_type, entity_id, source,
                 json.dumps({"name": name, "expected_type": expected_type}, ensure_ascii=False)),
            )
        return {"action": "found", "entity_id": entity_id, "entity_type": entity_type, "detail": None}

    # 找不到 -> 不创建，记录悬空引用
    cur.execute(
        """
        INSERT INTO ccc.entity_review_queue
            (canonical_name, new_type, existing_type, existing_entity_id,
             conflict_kind, hint, source, raw_payload)
        VALUES (%s, %s, NULL, NULL, 'unresolved_reference',
                '被引用但clean_entities中不存在，需人工确认是否应创建及其type', %s, %s::jsonb)
        RETURNING id
        """,
        (norm, expected_type, source,
         json.dumps({"name": name, "expected_type": expected_type}, ensure_ascii=False)),
    )
    queue_id = cur.fetchone()[0]
    return {
        "action": "unresolved", "entity_id": None, "entity_type": None,
        "detail": {"queue_id": queue_id},
    }


# ---------------------------------------------------------------------------
# 接入示例（不在此文件内执行，供 P2-P4 改造时参考，见 patches/ 目录）
# ---------------------------------------------------------------------------
"""
### ingest_v3.py / ingest_real_history.py (P2/P3)

替换原来的:
    cur.execute("SELECT id FROM ccc.clean_entities WHERE lower(canonical_name)=lower(%s) AND entity_type=%s", (name, etype))
    row = cur.fetchone()
    if row:
        entity_id = row[0]
        cur.execute("UPDATE ccc.clean_entities SET mention_count = mention_count + 1 WHERE id=%s", (entity_id,))
    else:
        cur.execute("INSERT INTO ccc.clean_entities (...) VALUES (...) RETURNING id")
        entity_id = cur.fetchone()[0]

为:
    from entity_upsert import upsert_entity
    result = upsert_entity(cur, {"canonical_name": name, "entity_type": etype, "mention_count": 1}, source="ingest_v3")
    if result["action"] in ("accept", "accept_new"):
        entity_id = result["entity_id"]
        # 继续走 clean_document_entities / person_aliases / 关系边逻辑
    else:
        # review_queue 或 raw_staging：不创建 clean_document_entities 关联，跳过该实体
        print(f"   [SKIP] {name} ({etype}) -> {result['action']} ({result['reason']})")
        continue


### build_timeline.py (P4) —— 最重要

替换:
    def find_or_create_entity(cur, name):
        ... INSERT ... entity_type='PERSON' ...

为:
    from entity_upsert import find_entity_only

    def get_entity_id(cur, entity_name):
        # PRESSURE_MAP/ENTITY_KEYWORDS 里已知该实体大致类型时可传 expected_type
        expected = {"日本":"GPE","美国":"GPE","俄罗斯":"GPE","乌克兰":"GPE",
                    "以色列":"GPE","香港":"GPE","中共":"ORG"}.get(entity_name, "PERSON")
        result = find_entity_only(cur, entity_name, source="build_timeline", expected_type=expected)
        return result["entity_id"]  # 可能是 None

    在 build() 主循环里:
        entity_id = get_entity_id(cur, entity_name)
        if entity_id is None:
            print(f"  ⚠️  {entity_name}: 未在clean_entities中找到，已记入review_queue，跳过本轮chain构建")
            continue
        # 原有 event_chains / event_nodes 逻辑不变，entity_id 改为引用而非创建
"""
