# ADR-116

## W Layer Re-definition v0.1

**Status:** Candidate / Pending Phase 2.4 Closure
**Date:** 2026-06-20

---

## Previous Understanding

```text
W = Public Output Layer
```

W 被视为：
- 公共展示层
- 对外发布层
- Q → W 同步终点

---

## New Understanding

```text
W = Public Communication Layer
```

W 被重新定义为：
- 公共交流层（Public Communication Layer）
- 风险隔离层（Risk Isolation Layer）
- 认知缓冲层（Cognitive Buffer Layer）
- 自我保护层（Self-Protection Layer）

---

## Design Principle

Q 与 W 不追求完全对称。

```text
Q = Internal Truth & Decision Layer

W = Public Communication & Protection Layer
```

---

## Responsibilities

### Q Layer

负责：

```text
Reality
Evidence
Entity
Graph
Timeline
Assessment
Decision
```

特点：

```text
Truth First
```

Q 的定位是 **Reality Processing Layer**（内部认知工作区），处理对象包括：

- 公开资料
- 用户导入资料
- OCR 文本
- 实体（Entity）
- 关系（Graph）
- 时间线（Timeline）
- 评估（Assessment）
- 决策（Decision）

例如：人物 / 组织 / 国家 / 企业 / 事件 / 政策 / 技术路线 / 商业计划 / 历史事件 / 个人项目。

**Evidence** 指支撑一个判断的证据链，而非秘密情报或非法获取资料，例如：新闻、财报、法律文件、公开采访、研究报告、用户自己的观察记录。

### W Layer

负责：

```text
Communication
Explanation
Publication
Public Interaction
Feedback Collection
Risk Filtering
```

特点：

```text
Survivability First
```

**Public** 在 CCC 语境下定义为「Q 之外的人」，包括：网站访客、读者、用户、合作者、未来社区成员，甚至未来的自己。

W 之所以需要 Protection，保护的不是某个秘密，而是**系统长期生存能力**。Q 中可能存在原始 OCR、半成品判断、低可信度推测、未验证关系——这些内容直接公开会导致误导、噪音、错误传播。因此 Q → 审核 → W，本质上是内部工作区到对外发布区的标准产线划分，类似 Git Repository ≠ Production Website：草稿、实验分支、半成品代码不会直接上线，同理 CCC 不会把原始现实信号、未验证判断、中间推理过程直接作为公共交流内容。

---

## Feedback Rule

禁止：

```text
W → Q Direct Write
```

允许：

```text
W Feedback
  ↓
Audit
  ↓
Feedback Absorption
  ↓
Q
```

---

## Strategic Goal

目标不是：

```text
Publish Everything
```

目标是：

```text
Preserve Truth
While Preserving The System
```

---

## Design Insight

```text
Systems that maximize disclosure
without considering sustainability
often lose their ability to continue operating.

CCC therefore seeks:

Truth Preservation
+
System Survivability
```

---

## Closing Principle

```text
The purpose of W is not censorship.

The purpose of W is to convert internal cognition
into sustainable public communication.
```

中文：

```text
W 层的目的不是审查。

W 层的目的是将内部认知
转化为可持续的公共交流。
```

---

## SVG V6 Impact

SVG V6 中：

```text
Q Pool
```

标注：

```text
Internal Truth & Decision Layer
```

```text
W Layer
```

标注：

```text
Public Communication & Protection Layer
```

并明确：

```text
Q → W
```

以及：

```text
W Feedback
  ↓
Audit
  ↓
Feedback Absorption
  ↓
Q
```

---

## Revision Note (vs. Draft)

相对于初始草稿，本版本做出以下关键修改：

1. 删除 Assange 具名引用（历史人物的具体行为模式不适合作为系统架构应当效仿的原型，且独立于任何历史案例，原则本身依然自洽）
2. 保留 Truth Preservation + System Survivability 作为核心设计洞见
3. 明确 W 不是审查层，而是公共交流生产层（Closing Principle 新增）

这些修改使文档保持为 **Architecture Clarification**，而非滑向意识形态宣言。

---

## Pending Closure Conditions

本 ADR 状态正式转为 `Accepted` 前，需完成：

- [ ] W (Supabase) 端 `clean_graph_edges` 实际 schema 审计
- [ ] W (Supabase) 端 `claims` 实际 schema 审计
- [ ] `sync_to_supabase.py` 同步逻辑审计
- [ ] Phase 2.4 — W Schema & Sync Alignment v0.1 正式收尾

审计与对齐完成后，与 Phase 2.4 收尾说明一并封板为 checkpoint 116。
