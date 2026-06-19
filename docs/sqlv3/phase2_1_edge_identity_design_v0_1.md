# SQLV3 Phase 2.1 — Edge Identity Design v0.1

**Status:** design locked
**Depends on:** SQLV3 Phase 2 — Feedback Absorption v0.1 (checkpoint id=107)
**Scope:** principles + design-level analysis only. No tables altered. No SQL executed
against production schema beyond read-only inspection queries. No changes to
`sync_to_supabase.py`.

---

## 0. Core Pin

> Edge identity cannot be stable if its endpoints are unstable.

中文：
> 如果边的两端不稳定，边自身不可能真正稳定。

This single sentence governs every decision in this document. Giving an edge its
own UUID while its `source`/`target` still resolve through a locally-mutable
integer `id` would produce a stable label pointing at an unstable target — solving
the wrong layer of the problem.

---

## 1. Edge Identity 总纲

**核心问题：**
> `clean_graph_edges` 中的一条边，是否应被视为一个可被长期引用、同步、审核、
> 撤销和追踪的独立对象？

**设计目标声明：**
> Edge Identity 的设计目标不是为了让边更容易写入，而是为了让边在被引用、同步、
> 审核、撤销、追踪时不丢失身份。

如果是，它就需要一个跨同步、跨版本、跨环境稳定的身份层，且必须满足三条性质：

```
1. 不可变性   -- 一旦生成，不随边的属性变化而改变
2. 可同步性   -- Q→W sync 时可作为冲突解决 key（类比 entity_uuid 的 ON CONFLICT）
3. 可引用性   -- 可被 feedback object / review event / audit trail 稳定引用
```

边比实体更难，因为实体可以被显式赋予 `entity_uuid`，而边天然容易被误认为
`source + target + relation_type` 的派生结果，没有自己的"自我标识"。

**本阶段不做的事：**
```
不处理 dedup（同一实体对之间是否允许多条边并存，见第4点，但不执行实际合并）
不改 clean_graph_edges 现有字段（只设计，不 ALTER TABLE）
不影响 feedback_objects 既有设计（target_kind=EDGE 的开放时机见第5点，字段细化留待后续）
```

---

## 2. Endpoint Anchor Debt

实地检查 `clean_graph_edges` 字段结构后发现：

```
source_entity_id   bigint
target_entity_id   bigint
```

边目前锚定 source/target 实体的方式使用的是本地 `id`，而非 `entity_uuid`。这直接
违反了 SQLV2 Identity Layer 阶段已锁定的身份原则：

```
id          = local database implementation detail, never used as anchor
entity_uuid = stable identity layer across environments, syncs, and versions
```

**风险性质：静默错配，而非显式断裂。**
一旦发生本地重建、云端同步、实体合并、实体迁移、id 序列重排等情况，
`source_entity_id = 4` 在旧库里指向实体 A，在新库里可能指向实体 B —— 边不会报错，
但语义已经错误。这比连接断裂更危险，因为不会被任何机制自动发现。

**结论：本问题优先级高于"边自己要不要 UUID"，必须并入 Phase 2.1，作为前置条件。**
正确顺序是先设计、不立即实施：

```
Phase 2.1：设计原则，锁定字段方向
Phase 2.2 / 实际 DDL 阶段：执行 backfill + ALTER TABLE（不在本次范围）
```

**过渡式字段方向(设计稿，未执行)：**

| field | role |
|---|---|
| `id` | 本地行 id，保留，仅本地性能用途 |
| `edge_uuid` | 边自身稳定身份（新增，见第3点） |
| `source_entity_id` | 本地 join 优化字段，保留但降级为非权威 |
| `target_entity_id` | 同上 |
| `source_entity_uuid` | 稳定 endpoint anchor（新增） |
| `target_entity_uuid` | 稳定 endpoint anchor（新增） |
| `relation_type` | 关系属性，不作为身份 |
| `edge_fingerprint` | 辅助校验/去重签名（新增，不作为身份，见第3点） |

语义分工与 entity 的 `id` / `entity_uuid` 完全对称：
`*_entity_id` = local join optimization；`*_entity_uuid` = semantic identity anchor。

---

## 3. edge_uuid vs edge_fingerprint

**结论：`edge_uuid` 是主身份，`edge_fingerprint` 是辅助校验工具，二者不互相替代。**

| | edge_uuid（显式赋予） | edge_fingerprint（派生计算） |
|---|---|---|
| 角色 | 主身份 | 辅助校验/去重信号 |
| 依赖 | 不依赖任何可变字段 | 依赖 source/target/relation_type 等可变内容字段 |
| relation_type 改名 | 不受影响，历史引用安然无恙 | 断裂，被误判为全新边 |
| 适用场景 | 审计、反馈引用、版本演化、撤销追踪 | 检测重复、跨库完整性抽查 |

**relation_type 改名风险（已并入本节，不单独成节）：**
派生签名的输入字段恰好是边最容易变化的部分，这正是"主身份不应依赖会变的东西"
这条原则的反例。无论哈希算法如何包装，依赖可变内容的标识都不具备做主身份的资格。

**edge_fingerprint 的两层定位（v0.1 只锁原则，不设计算法）：**
```
raw_fingerprint        -- 严格内容比对（source_entity_uuid/target_entity_uuid/
                           relation_type/relation_label/relation_direction/
                           direction/pressure/valid_from/valid_to/event_time
                           全部一致 → 高度疑似重复写入）
normalized_fingerprint  -- 近重复检测（relation_label 规范化后比对，处理同义
                           表述、前缀差异等，用于发现"近似但不完全相同"的重复）
具体算法设计留待后续 phase，本节只记录角色定位。
```

---

## 4. 多边并存与 edge_uuid 粒度

### 4.1 实地数据验证

对 `ccc.clean_graph_edges` 按 `(source_entity_id, target_entity_id, relation_type)`
分组核查重复，发现 5 组重复，逐组比对其余字段后判定：

| 组 | 记录 | 判定 |
|---|---|---|
| 4→7 typed | marriage / romantic_relation（weight、document_count 均不同） | 合法语义多边 |
| 78→91 conspiracy_narrative | 文本仅差"民间"二字前缀，其余字段（weight/causal_weight/pressure/direction/document_count）完全一致 | 疑似近重复 |
| 378→376 typed | 企业 / organizational_dependency | relation_label 语义类别混乱（见4.3） |
| 385→382 typed | 合作 / organizational_dependency | 合法语义多边 |
| 386→385 typed | 社长 / organizational_dependency | relation_label 语义类别混乱（见4.3） |

### 4.2 结论：不采用三元组唯一约束

```
clean_graph_edges 当前同一 source/target/relation_type 三元组下存在多条记录，
这些记录混合了合法语义多边与疑似近重复。

因此 v0.1 不采用 UNIQUE(source_entity_uuid, target_entity_uuid, relation_type)。

edge_uuid 是唯一主身份，赋予每一条 clean_graph_edges 记录本身——
不由 source/target/relation_type 三元组推导，不在插入时按三元组自动复用。
（避免"插入前先按三元组查重、命中就复用 edge_uuid"这种策略，
 因为已证明三元组下可能存在多条语义不同的合法边。）

edge_fingerprint 仅用于疑似重复检测，不参与身份判定，不自动触发合并。
疑似重复边不在 Phase 2.1 处理，留给后续 dedup/review phase。
```

### 4.3 另行记录（已知问题，明确排除在 Phase 2.1 范围外）

```
relation_label 字段存在语义类别混乱：部分值是实体类型词或职位头衔词
（如"企业""社长"），而非关系描述本身，应该是 entity type 或 role/title，
不是 relationship label。

这不属于 edge identity 问题，属于 relation taxonomy / extraction normalization
问题，建议后续单独开 SQLV3 Relation Taxonomy Cleanup v0.1 处理，本次不做。
```

### 4.4 是否需要先修归并问题再设计身份层？

**结论：不需要。** 顺序应为先有身份层，再安全地处理归并/去重：
```
1. 先锁 edge identity 原则（本文档）
2. 再设计 fingerprint / duplicate detection 算法（后续 phase）
3. 再进入 dedup review（后续 phase）
4. 最后才考虑是否合并/清理历史边（后续 phase）
```
如果在没有稳定身份层的情况下先"修归并 bug"，容易在合法多边和近重复之间
判断失误，造成误删。

---

## 5. feedback target_kind=EDGE 何时开放

### 开放的两个硬性前提（缺一不可）

```
前提1 — 结构前提：
  clean_graph_edges 全表完成 backfill：
    edge_uuid（每行一个，不可变，按4.2节策略生成）
    source_entity_uuid（替代/补充 source_entity_id）
    target_entity_uuid（替代/补充 target_entity_id）
  规模参考：类比 SQLV2 Identity Layer 阶段对 ~1,190 个 entity 的回填工作量，
  这次是对全部 clean_graph_edges 行的回填。

前提2 — 同步前提：
  sync_to_supabase.py 支持把 edge_uuid 作为稳定冲突解决 key 传递到 W，
  类比现有 entity 的 ON CONFLICT (entity_uuid)，
  边需要等价的 ON CONFLICT (edge_uuid) 机制。
```

两个前提任一未满足，`target_kind=EDGE` 都不开放。

### relation_label 标签混乱不是阻塞条件

身份层稳定性（能否被引用）与内容质量（标得对不对）是两个独立维度。
事实上，开放后用户对"企业""社长"这类标签混乱的质疑，正好应该走 `CHALLENGE`
反馈路径进来——relation taxonomy 问题不是开放的前置条件，而是开放之后
feedback 机制可以帮助暴露和积累的内容。

### 开放前的过渡状态（维持 Feedback Absorption v0.1 原文不变）

```
target_kind = ENTITY 或 CHALLENGE
edge 相关反馈降级处理，proposed_payload 自由文本描述涉及的两个 entity_uuid
和 relation_type，不建立结构化 edge anchor。
```

### 开放后需要的后续工作（标记为已知待办，不在本次设计范围）

```
feedback_objects 的锚点字段需要从单一的 target_entity_uuid
扩展为能区分 ENTITY/EDGE 的结构（新增 target_edge_uuid，还是泛化为
target_object_uuid + target_kind 联合定位，留到实际开放时再设计）。
```

### 边界声明

```
开放 target_kind=EDGE 只解决"反馈能否稳定指向一条边"的问题，
不改变 Feedback Absorption v0.1 已锁定的核心红线：
accepted 仍然不等于自动写回 Q。
两件事完全独立，不因为开放了 EDGE 反馈通道而松动"不自动写回"的原则。
```

---

## 6. Summary of Locked Constraints

```
1. Edge identity cannot be stable if its endpoints are unstable.
   （边的两端必须先有 entity_uuid 锚定，边自身的身份才有意义）

2. edge_uuid 是边的唯一主身份，赋予每条 clean_graph_edges 记录本身，
   不由 source/target/relation_type 三元组推导或复用。

3. edge_fingerprint 仅作辅助校验/疑似重复检测，不参与身份判定，
   不自动触发合并。

4. 不对 (source_entity_uuid, target_entity_uuid, relation_type) 设唯一约束，
   因为已用实地数据证明该三元组下可能合法地存在多条边。

5. relation_label 语义类别混乱问题已记录，明确排除在本次范围外，
   留待独立的 Relation Taxonomy Cleanup 任务处理。

6. target_kind=EDGE 的开放有两个硬性前提（edge_uuid + endpoint uuid 全量
   backfill，且 Q→W sync 支持 edge_uuid 冲突解决），在满足之前，
   EDGE 相关反馈维持降级为 CHALLENGE 的处理方式。

7. 无论 target_kind=EDGE 是否开放，Feedback Absorption v0.1 的核心红线
   不变：accepted 不等于自动写回 Q。
```

---

## 7. Explicitly Out of Scope for This Document

```
- 不执行任何 ALTER TABLE / backfill 脚本
- 不设计 edge_fingerprint 的具体算法（raw/normalized 的实现细节）
- 不设计 relation taxonomy 规范化方案
- 不设计 feedback_objects 在 target_kind=EDGE 开放后的具体字段扩展方案
- 不修改 sync_to_supabase.py
```
