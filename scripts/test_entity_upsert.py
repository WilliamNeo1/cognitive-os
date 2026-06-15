#!/usr/bin/env python3
"""
test_entity_upsert.py
======================
不需要真实 PostgreSQL —— 用 FakeCursor 模拟 ccc.clean_entities /
entity_raw_staging / entity_review_queue 三张表的内存状态，
验证 upsert_entity() / find_entity_only() 的路由逻辑。

跑法:
    python3 test_entity_upsert.py
"""

from entity_upsert import upsert_entity, find_entity_only, GuardrailConfig, normalize_name


class FakeCursor:
    """极简内存 DB，只支持本模块用到的 SQL 形态。"""

    def __init__(self, entities=None):
        # entities: list of dict {id, canonical_name, entity_type, mention_count}
        self.entities = {e["id"]: dict(e) for e in (entities or [])}
        self._next_id = max(self.entities.keys(), default=0) + 1
        self.raw_staging = []
        self.review_queue = []
        self._last_result = None

    def _new_id(self, table):
        nid = self._next_id
        self._next_id += 1
        return nid

    def execute(self, sql, params=None):
        sql_norm = " ".join(sql.split())
        params = params or ()

        # DDL — no-op
        if sql_norm.startswith("CREATE TABLE"):
            self._last_result = None
            return

        # --- upsert_entity: exact match (name+type) ---
        if "SELECT id FROM ccc.clean_entities" in sql_norm and "entity_type = %s" in sql_norm \
           and "!=" not in sql_norm:
            norm_name, etype = params
            for eid, e in self.entities.items():
                if e["canonical_name"].lower() == norm_name.lower() and e["entity_type"] == etype:
                    self._last_result = (eid,)
                    return
            self._last_result = None
            return

        # --- UPDATE mention_count ---
        if sql_norm.startswith("UPDATE ccc.clean_entities SET mention_count"):
            inc, eid = params
            self.entities[eid]["mention_count"] += inc
            self._last_result = None
            return

        # --- type conflict lookup ---
        if "SELECT id, entity_type FROM ccc.clean_entities" in sql_norm \
           and "entity_type != %s" in sql_norm:
            norm_name, etype = params
            for eid, e in self.entities.items():
                if e["canonical_name"].lower() == norm_name.lower() and e["entity_type"] != etype:
                    self._last_result = (eid, e["entity_type"])
                    return
            self._last_result = None
            return

        # --- find_entity_only lookup (no type filter) ---
        if "SELECT id, entity_type FROM ccc.clean_entities" in sql_norm \
           and "ORDER BY mention_count" in sql_norm:
            (norm_name,) = params
            best = None
            for eid, e in self.entities.items():
                if e["canonical_name"].lower() == norm_name.lower():
                    if best is None or e["mention_count"] > self.entities[best]["mention_count"]:
                        best = eid
            if best is not None:
                self._last_result = (best, self.entities[best]["entity_type"])
            else:
                self._last_result = None
            return

        # --- INSERT entity_raw_staging ---
        if sql_norm.startswith("INSERT INTO ccc.entity_raw_staging"):
            # params: (name, etype, source, json) -- order matches both ocr_noise and low_value
            name, etype, source, payload = params
            reason = "ocr_noise" if "'ocr_noise'" in sql_norm else "low_value_person_pending"
            sid = self._new_id("raw_staging")
            self.raw_staging.append({
                "id": sid, "canonical_name": name, "entity_type": etype,
                "reject_reason": reason, "source": source,
            })
            self._last_result = (sid,)
            return

        # --- INSERT entity_review_queue (type_conflict, with RETURNING) ---
        if sql_norm.startswith("INSERT INTO ccc.entity_review_queue") and "RETURNING id" in sql_norm \
           and "'type_conflict'" in sql_norm:
            norm_name, etype, existing_type, existing_id, hint, source, payload = params
            qid = self._new_id("review_queue")
            self.review_queue.append({
                "id": qid, "canonical_name": norm_name, "new_type": etype,
                "existing_type": existing_type, "existing_entity_id": existing_id,
                "conflict_kind": "type_conflict", "hint": hint, "source": source,
            })
            self._last_result = (qid,)
            return

        # --- INSERT entity_review_queue (reference_type_mismatch, no RETURNING) ---
        if sql_norm.startswith("INSERT INTO ccc.entity_review_queue") and "reference_type_mismatch" in sql_norm:
            norm_name, expected_type, existing_type, existing_id, source, payload = params
            self.review_queue.append({
                "canonical_name": norm_name, "new_type": expected_type,
                "existing_type": existing_type, "existing_entity_id": existing_id,
                "conflict_kind": "reference_type_mismatch", "source": source,
            })
            self._last_result = None
            return

        # --- INSERT entity_review_queue (unresolved_reference, with RETURNING) ---
        if sql_norm.startswith("INSERT INTO ccc.entity_review_queue") and "unresolved_reference" in sql_norm:
            norm_name, expected_type, source, payload = params
            qid = self._new_id("review_queue")
            self.review_queue.append({
                "id": qid, "canonical_name": norm_name, "new_type": expected_type,
                "conflict_kind": "unresolved_reference", "source": source,
            })
            self._last_result = (qid,)
            return

        # --- INSERT new clean_entity ---
        if sql_norm.startswith("INSERT INTO ccc.clean_entities"):
            norm_name, etype, source, confidence, mention_count = params
            eid = self._new_id("clean_entities")
            self.entities[eid] = {
                "id": eid, "canonical_name": norm_name, "entity_type": etype,
                "mention_count": mention_count, "source": source, "confidence": confidence,
            }
            self._last_result = (eid,)
            return

        raise NotImplementedError(f"Unhandled SQL: {sql_norm[:100]} params={params}")

    def fetchone(self):
        return self._last_result


# ---------------------------------------------------------------------------
# 测试用例
# ---------------------------------------------------------------------------

def run_tests():
    failures = []

    def check(name, cond, detail=""):
        status = "PASS" if cond else "FAIL"
        print(f"[{status}] {name}" + (f" -- {detail}" if detail and not cond else ""))
        if not cond:
            failures.append(name)

    # 初始库状态：模拟审计报告中的真实情况
    seed = [
        {"id": 232, "canonical_name": "英国", "entity_type": "PLACE", "mention_count": 5},
        {"id": 1,   "canonical_name": "习近平", "entity_type": "PERSON", "mention_count": 47},
        {"id": 9,   "canonical_name": "美国", "entity_type": "GPE", "mention_count": 222},
    ]

    # --- Case 1: 同名同type -> accept (mention_count递增) ---
    cur = FakeCursor(seed)
    r = upsert_entity(cur, {"canonical_name": "习近平", "entity_type": "PERSON", "mention_count": 3}, source="test")
    check("Case1 同名同type -> accept", r["action"] == "accept" and r["entity_id"] == 1)
    check("Case1 mention_count递增", cur.entities[1]["mention_count"] == 50, f"got {cur.entities[1]['mention_count']}")

    # --- Case 2: 同名不同type -> review_queue (英国 GPE vs 已存的 PLACE) ---
    cur = FakeCursor(seed)
    r = upsert_entity(cur, {"canonical_name": "英国", "entity_type": "GPE", "mention_count": 80}, source="test")
    check("Case2 类型冲突 -> review_queue", r["action"] == "review_queue")
    check("Case2 未写入clean_entities", 232 not in [e for e in cur.entities if cur.entities[e]["canonical_name"] == "英国" and cur.entities[e]["entity_type"] == "GPE"])
    check("Case2 hint正确", r["detail"]["hint"].startswith("建议统一为 GPE"), r["detail"]["hint"])

    # --- Case 3: OCR噪音 -> raw_staging ---
    cur = FakeCursor(seed)
    r = upsert_entity(cur, {"canonical_name": "一", "entity_type": "PERSON", "mention_count": 1}, source="test")
    check("Case3 单字符 -> raw_staging(ocr_noise)", r["action"] == "raw_staging" and r["reason"] == "ocr_noise")

    cur = FakeCursor(seed)
    r = upsert_entity(cur, {"canonical_name": "ーーーーー", "entity_type": "ORG", "mention_count": 1}, source="test")
    check("Case3b 重复符号 -> raw_staging(ocr_noise)", r["action"] == "raw_staging" and r["reason"] == "ocr_noise")

    # --- Case 4: 低价值PERSON (mention=1, degree=0) -> raw_staging ---
    cur = FakeCursor(seed)
    r = upsert_entity(cur, {"canonical_name": "山田次郎", "entity_type": "PERSON", "mention_count": 1}, source="test", degree_hint=0)
    check("Case4 低价值PERSON -> raw_staging", r["action"] == "raw_staging" and r["reason"] == "low_value_person_pending")

    # --- Case 4b: 同样mention=1但degree>0 -> 应正常创建 (不是低价值) ---
    cur = FakeCursor(seed)
    r = upsert_entity(cur, {"canonical_name": "薄瓜瓜", "entity_type": "PERSON", "mention_count": 2}, source="test", degree_hint=59)
    check("Case4b mention低但degree高 -> accept_new (非低价值)", r["action"] == "accept_new")

    # --- Case 5: 全新正常实体 ---
    cur = FakeCursor(seed)
    r = upsert_entity(cur, {"canonical_name": "石破茂", "entity_type": "PERSON", "mention_count": 3, "confidence": 0.9}, source="test")
    check("Case5 全新实体 -> accept_new", r["action"] == "accept_new" and r["entity_id"] is not None)
    check("Case5 写入clean_entities", cur.entities[r["entity_id"]]["canonical_name"] == "石破茂")

    # --- Case 6: 全半角/空格归一化后命中已有实体 ---
    cur = FakeCursor(seed)
    r = upsert_entity(cur, {"canonical_name": "  美国  ", "entity_type": "GPE", "mention_count": 1}, source="test")
    check("Case6 归一化命中已有实体 -> accept", r["action"] == "accept" and r["entity_id"] == 9)

    # --- Case 7: find_entity_only - 找到，类型一致 ---
    cur = FakeCursor(seed)
    r = find_entity_only(cur, "习近平", source="build_timeline", expected_type="PERSON")
    check("Case7 find_entity_only找到且类型一致", r["action"] == "found" and r["entity_id"] == 1)
    check("Case7 无review_queue记录", len(cur.review_queue) == 0)

    # --- Case 8: find_entity_only - 找到，但类型不一致（build_timeline误判场景）---
    cur = FakeCursor(seed)
    r = find_entity_only(cur, "英国", source="build_timeline", expected_type="PERSON")
    check("Case8 找到但类型不符 -> 仍返回found", r["action"] == "found" and r["entity_id"] == 232)
    check("Case8 记录reference_type_mismatch", any(q["conflict_kind"] == "reference_type_mismatch" for q in cur.review_queue))

    # --- Case 9: find_entity_only - 完全找不到 -> unresolved，不创建 ---
    cur = FakeCursor(seed)
    before_count = len(cur.entities)
    r = find_entity_only(cur, "某未知实体XYZ", source="build_timeline", expected_type="PERSON")
    check("Case9 找不到 -> unresolved", r["action"] == "unresolved" and r["entity_id"] is None)
    check("Case9 未创建新实体", len(cur.entities) == before_count)
    check("Case9 记入review_queue(unresolved_reference)", any(q["conflict_kind"] == "unresolved_reference" for q in cur.review_queue))

    # --- Case 10: normalize_name 基本行为 ---
    check("normalize_name 全角->半角+去空格", normalize_name("  美国  ") == "美国")
    check("normalize_name 不改变正常中文", normalize_name("习近平") == "习近平")

    print()
    if failures:
        print(f"❌ {len(failures)} 个测试失败: {failures}")
        raise SystemExit(1)
    else:
        print("✅ 全部测试通过")


if __name__ == "__main__":
    run_tests()
