# SQLV3 Phase 2.2 — Edge Identity DDL & Backfill v0.1

**Status:** executed and locked
**Depends on:** SQLV3 Phase 2.1 — Edge Identity Design v0.1 (checkpoint id=110)
**Scope:** structural backfill only. No feedback tables, no taxonomy cleanup,
no sync_to_supabase.py changes.

---

## 0. Scope (as agreed before execution)

```
In scope:
  1. clean_graph_edges 增加 edge_uuid
  2. 增加 source_entity_uuid / target_entity_uuid
  3. 回填现有边的 endpoint uuid
  4. 为每条现有 edge 生成 edge_uuid
  5. 增加必要索引

Explicitly out of scope:
  6. 不对 (source_entity_uuid, target_entity_uuid, relation_type) 三元组做唯一约束
  7. 不做 dedup
  8. 不改 relation_label
  9. 不开放 target_kind=EDGE
  10. 不改 feedback_objects 设计
  （另：不改 sync_to_supabase.py）
```

`edge_uuid` 本身设 UNIQUE 不属于第6条的范围 — 第6条针对的是三元组组合,不是
`edge_uuid` 自身。`edge_uuid` 加 UNIQUE 是落实 Phase 2.1 "edge_uuid 是唯一主
身份" 这条已锁定原则,不是范围扩张。

---

## 1. Pre-flight Verification (执行前体检)

```sql
SELECT COUNT(*) FROM ccc.clean_graph_edges;                 -- 10,965
-- source_entity_id 在 clean_entities 中找不到对应行的边数:  0
-- target_entity_id 在 clean_entities 中找不到对应行的边数:  0
```

零悬空引用，迁移可以安全进行，无需先处理 `anchor_unresolved` 类的边缘情况。

---

## 2. Executed Migration (实际执行的 SQL，按执行顺序)

### 2.1 加列 + 回填(事务内执行，验证通过后 COMMIT)

```sql
BEGIN;

ALTER TABLE ccc.clean_graph_edges ADD COLUMN edge_uuid uuid;
ALTER TABLE ccc.clean_graph_edges ADD COLUMN source_entity_uuid uuid;
ALTER TABLE ccc.clean_graph_edges ADD COLUMN target_entity_uuid uuid;

UPDATE ccc.clean_graph_edges e
SET source_entity_uuid = ce.entity_uuid
FROM ccc.clean_entities ce
WHERE e.source_entity_id = ce.id;

UPDATE ccc.clean_graph_edges e
SET target_entity_uuid = ce.entity_uuid
FROM ccc.clean_entities ce
WHERE e.target_entity_id = ce.id;

UPDATE ccc.clean_graph_edges
SET edge_uuid = gen_random_uuid()
WHERE edge_uuid IS NULL;

-- 验证(全部通过后 COMMIT):
-- total_rows = 10965, null_edge_uuid = 0, null_source_uuid = 0,
-- null_target_uuid = 0, distinct_edge_uuid = 10965

COMMIT;
```

### 2.2 身份层约束(edge_uuid 作为唯一主身份，数据库层自动生成)

```sql
ALTER TABLE ccc.clean_graph_edges
ALTER COLUMN edge_uuid SET DEFAULT gen_random_uuid();

ALTER TABLE ccc.clean_graph_edges
ALTER COLUMN edge_uuid SET NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS clean_graph_edges_edge_uuid_uidx
ON ccc.clean_graph_edges(edge_uuid);

CREATE INDEX IF NOT EXISTS idx_clean_graph_edges_source_entity_uuid
ON ccc.clean_graph_edges (source_entity_uuid);

CREATE INDEX IF NOT EXISTS idx_clean_graph_edges_target_entity_uuid
ON ccc.clean_graph_edges (target_entity_uuid);
```

### 2.3 清理(早期版本误建了一个与唯一索引重复的非唯一索引)

```sql
DROP INDEX ccc.idx_clean_graph_edges_edge_uuid;
```

---

## 3. Final Verified State

**列结构：**

| column | data_type | is_nullable | column_default |
|---|---|---|---|
| `edge_uuid` | uuid | NO | `gen_random_uuid()` |
| `source_entity_uuid` | uuid | YES | (none) |
| `target_entity_uuid` | uuid | YES | (none) |

**索引：**

```
clean_graph_edges_edge_uuid_uidx           -- UNIQUE btree (edge_uuid)
idx_clean_graph_edges_source_entity_uuid   -- btree (source_entity_uuid)
idx_clean_graph_edges_target_entity_uuid   -- btree (target_entity_uuid)
```

---

## 4. Design Decisions Made During Execution

```
edge_uuid:
  数据库层自动生成(DEFAULT gen_random_uuid())、NOT NULL、UNIQUE。
  决定立即落地，不等待 ingest 脚本改造完成。
  理由：edge_uuid 是身份层字段，不应该依赖应用层"记得赋值"——
  如果遗漏赋值会产生 NULL 身份边，直接违反 Phase 2.1 已锁定的核心原则。

source_entity_uuid / target_entity_uuid:
  不设默认值，保持可空。
  理由：它们的值来自外部权威(clean_entities.entity_uuid)，
  不应由数据库自行生成一个不指向任何实体的 uuid。
  回填/赋值方式留给后续 ingest 逻辑或 trigger 决定，本阶段不实现。
```

---

## 5. ⚠️ Known Gap — Needs Follow-up Before Next Ingest Run

```
现状：edge_uuid 有数据库默认值，新插入的边会自动获得 edge_uuid。
但 source_entity_uuid / target_entity_uuid 没有默认值，
现有的 ingest_batch.py（或任何写入 clean_graph_edges 的脚本）
如果没有显式赋值这两个字段，新插入的边会产生:
  edge_uuid 非空(自动生成)
  source_entity_uuid / target_entity_uuid 为 NULL

这意味着：在 ingest 脚本被更新之前，新写入的边会处于
"自身有身份、但 endpoint 锚定缺失"的状态——这正是 Phase 2.1
第0条核心判断("边的身份不可能比它的两端更稳定")试图避免的情况。

建议：在下一次跑 ingest_batch.py 写入新边之前，
先更新写入逻辑，让它在写入时一并填入 source_entity_uuid / target_entity_uuid
（从 clean_entities 按 id 查出对应 entity_uuid），
否则这次回填工作只覆盖历史数据，新数据会继续产生缺口。
这个改造任务本身不在 Phase 2.2 范围内，但需要在制度上记录为优先待办。
```

---

## 6. Explicitly Not Done (per locked scope)

```
- 未对 (source_entity_uuid, target_entity_uuid, relation_type) 三元组加唯一约束
- 未执行任何 dedup / 合并操作
- 未修改 relation_label 内容
- 未开放 feedback target_kind=EDGE
- 未修改 feedback_objects 设计
- 未修改 sync_to_supabase.py
```
