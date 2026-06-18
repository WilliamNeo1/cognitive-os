-- ============================================================
-- SQLV3 claims 表 — DDL
-- 目标数据库：PostgreSQL，schema: ccc
-- ============================================================
--
-- Purpose:
--   Create ccc.claims, the L2 Claim Extraction layer table defined
--   in SQLV3 Claims/Events/Hypothesis Boundary v0.1.
--   建立 claims 表，承载"有人主张了什么"这一层认知对象，
--   填补 Source Hygiene v0.1 与 Graph Write Gate v0.1 都在等待的
--   结构依赖缺口。
--
-- Execution / 执行顺序：
--   1. 先在 DBeaver 中整体执行本文件。
--   2. 执行完毕后用文件末尾的验证查询确认表和外键都已生效。
--   3. 这次执行会同时修改 ccc.source_claim_links（补外键约束），
--      但不会修改 sources / source_observations 任何已有数据。
--
-- 范围声明（Scope）：
--   本次新增 ccc.claims 一张表，并对已存在的
--   ccc.source_claim_links.claim_id 补一条外键约束（之前在
--   Source Hygiene v0.1 DDL 里特意留空，注释写明"待 claims 表
--   建立后再补"，现在 claims 表建立，回补这条待办）。
--   不修改 ccc.documents / ccc.entities / ccc.events /
--   ccc.event_dashboard / ccc.sources / ccc.source_observations。
--
-- 边界声明（必须遵守，来自已锁定的四份协议）：
--
--   1. （Claims/Events/Hypothesis Boundary v0.1）claim_status 默认值
--      必须是 'unverified'，不是 'supported'。一条 claim 被记录下来
--      只代表"有人这样主张"，不代表这个主张为真。
--
--   2. （Claims/Events/Hypothesis Boundary v0.1 + Source Hygiene v0.1）
--      claims 表不存储 quoted_excerpt（原文引用片段）。引用片段属于
--      ccc.source_claim_links.quoted_excerpt，因为一条 claim 可能
--      关联多个 source，每个 source 可能引用不同段落，存在 claim
--      自身字段上会产生"哪一段才是真正引用"的歧义。同理也不存储
--      source_url / source_name，这些归 ccc.sources。
--
--   3. （Graph Write Gate v0.1）claims 表不存储
--      subject_entity_id / object_entity_id。如果在这一层就把
--      claim 和两个实体绑定成主语/宾语，等同于提前把 claim 当成了
--      候选边（candidate edge），违反"没有任何关系仅因为它出现在
--      文本里就能进图"的核心原则。实体关联应在 L4/L5 阶段处理。
--
--   4. （Feedback Absorption v0.1 第10节 Hard Prohibitions）
--      "W feedback written directly into claims" 是明确列出的硬性
--      禁止条款。因此本表不设置 input_origin 字段——这不是遗漏，
--      是因为 claims 表的存在前提就是只接收已经是 q_internal 的
--      数据：任何 w_feedback / unknown_origin 来源的内容，必须先
--      停留在 Feedback Absorption v0.1 设想的 feedback_candidates /
--      feedback_raw 表（本轮尚未建立），经过人工 re-curation 决策、
--      被重新归类为 q_internal 之后，才能作为一条新的 INSERT 进入
--      本表。本表里出现的每一行，在语义上都应被视为 q_internal。
--      若未来发现需要在 claims 表层面也做来源标记，应新增字段并
--      补充本表的边界声明，而不是放宽这条假设。
--
--   5. claim_type 字段本轮不创建。四份已锁定协议文档均未定义过
--      claim_type 的取值集合或语义，本轮不臆造一个新概念。如有
--      需要应作为未来独立的设计议题处理。
--
--   6. source_document_id 指向 ccc.documents(id)，表达"这条 claim
--      是从哪个已经进入 L1 Document Normalization 的文档中提取
--      出来的"，是物理出处。这与 ccc.source_claim_links 表达的
--      "哪些 source 在证据链路上支撑/转述/反驳这条 claim"是不同
--      维度的关联，两者并存，不互相替代。
-- ============================================================


-- ============================================================
-- 表：claims
-- ============================================================

CREATE TABLE IF NOT EXISTS ccc.claims (
    id                   bigserial PRIMARY KEY,

    -- claim 本身的内容
    claim_text           text        NOT NULL,    -- 这条主张的文本内容
    claimant             text,                      -- 谁提出了这个主张（不是谁记录的）

    -- 状态：默认 unverified，不是 supported（Boundary v0.1 核心要求）
    claim_status         text        NOT NULL DEFAULT 'unverified'
        CHECK (claim_status IN ('unverified', 'supported', 'refuted', 'disputed', 'parked')),

    -- 物理出处：这条claim是从哪个L1文档里提取出来的
    -- 注意：ccc.documents 是既有 legacy 表（bigint/bigserial），这里直接引用
    source_document_id   bigint      REFERENCES ccc.documents(id),

    -- 审计字段：记录这条claim是SQLV3哪一层处理产生的（自由文本，不加CHECK，
    -- 因为L0-L7的具体子阶段命名可能随实现演化，不在本轮固定枚举）
    created_from_layer   text,

    created_at           timestamptz DEFAULT now() NOT NULL,
    updated_at           timestamptz DEFAULT now() NOT NULL,

    notes                text                       -- 自由备注
);

CREATE INDEX IF NOT EXISTS idx_claims_status ON ccc.claims (claim_status);
CREATE INDEX IF NOT EXISTS idx_claims_source_document ON ccc.claims (source_document_id);

COMMENT ON TABLE ccc.claims IS
    'SQLV3 L2 Claim Extraction — claims 表只记录"有人主张了什么"，不记录证据摘录（归source_claim_links）、不绑定主宾实体（避免提前变成candidate edge）、不接收w_feedback（Feedback Absorption v0.1 Hard Prohibition，本表行语义上均为q_internal）。';
COMMENT ON COLUMN ccc.claims.claim_text IS
    '主张的文本内容。这是claim本身，不是证据原文引用——引用片段归 ccc.source_claim_links.quoted_excerpt。';
COMMENT ON COLUMN ccc.claims.claimant IS
    '提出这个主张的主体（人/媒体/机构），不是记录或转述这条claim的人。例如"某媒体称X"中claimant是该媒体。';
COMMENT ON COLUMN ccc.claims.claim_status IS
    '默认值为 unverified，不是 supported。一条claim被创建只代表"有人这样主张"，不代表为真。状态升级路径见 SQLV3 Claims/Events/Hypothesis Boundary v0.1 第5节。';
COMMENT ON COLUMN ccc.claims.source_document_id IS
    '指向 ccc.documents，表达这条claim从哪个L1文档提取而来（物理出处），与 source_claim_links 表达的证据链路是不同维度，两者并存。';
COMMENT ON COLUMN ccc.claims.created_from_layer IS
    '记录这条claim是SQLV3管线哪一层/哪个处理步骤产生的，自由文本，用于审计追溯，不做枚举约束。';


-- ============================================================
-- 外键回补：source_claim_links.claim_id → claims.id
-- （Source Hygiene v0.1 DDL 当时特意留空的待办，现在 claims 表
--  已建立，回补这条约束）
-- ============================================================

-- 先检查是否有任何现存的 source_claim_links 数据，其 claim_id 不为空
-- 但在新建的 claims 表中找不到对应记录（如果有，外键会直接报错失败，
-- 这里只是提前给出更清晰的提示而不是让原始外键错误信息含糊不清）
DO $$
DECLARE
    v_orphan_count integer;
BEGIN
    IF to_regclass('ccc.source_claim_links') IS NOT NULL THEN
        SELECT count(*) INTO v_orphan_count
        FROM ccc.source_claim_links scl
        WHERE NOT EXISTS (SELECT 1 FROM ccc.claims c WHERE c.id = scl.claim_id);

        IF v_orphan_count > 0 THEN
            RAISE EXCEPTION
                'source_claim_links 中存在 % 条记录的 claim_id 在新建的 claims 表中找不到对应行，外键约束无法添加。请先清理或修正这些孤儿记录（这些应该都是此前冒烟测试用的占位 claim_id=999999999 测试数据，若冒烟测试已正确清理则不应触发本检查）。',
                v_orphan_count;
        ELSE
            RAISE NOTICE '✅ 外键前置检查通过：source_claim_links 中没有孤儿 claim_id，可以安全添加外键约束';
        END IF;
    ELSE
        RAISE NOTICE '⚠ ccc.source_claim_links 表不存在，跳过外键回补（这不应该发生，Source Hygiene v0.1 DDL 应已建立此表）';
    END IF;
END;
$$;

ALTER TABLE ccc.source_claim_links
    DROP CONSTRAINT IF EXISTS fk_source_claim_links_claim;

ALTER TABLE ccc.source_claim_links
    ADD CONSTRAINT fk_source_claim_links_claim
    FOREIGN KEY (claim_id)
    REFERENCES ccc.claims(id);

COMMENT ON CONSTRAINT fk_source_claim_links_claim ON ccc.source_claim_links IS
    '外键回补：claim_id 必须指向真实存在的 ccc.claims 记录。此约束在 Source Hygiene v0.1 DDL 中曾被有意留空（claims表当时尚未建立），现于 claims 表 DDL 中补齐。';


-- ============================================================
-- 执行完毕后验证（仅查询，不产生数据）
-- ============================================================

/*
-- 确认 claims 表已建立：
SELECT table_name FROM information_schema.tables
WHERE table_schema = 'ccc' AND table_name = 'claims';

-- 确认 claims 表字段：
SELECT column_name, data_type, column_default, is_nullable
FROM information_schema.columns
WHERE table_schema = 'ccc' AND table_name = 'claims'
ORDER BY ordinal_position;

-- 确认外键回补已生效：
SELECT conname, conrelid::regclass AS table_name, confrelid::regclass AS references_table
FROM pg_constraint
WHERE conname = 'fk_source_claim_links_claim';
*/
