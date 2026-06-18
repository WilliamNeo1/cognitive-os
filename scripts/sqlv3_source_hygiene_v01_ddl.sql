-- ============================================================
-- SQLV3 Source Hygiene Protocol v0.1 — DDL
-- 目标数据库：PostgreSQL，schema: ccc
-- ============================================================
--
-- Purpose:
--   Create Source Hygiene tables for L1-L2 source governance.
--   建立信源治理三张表：sources / source_observations / source_claim_links。
--
-- Execution / 执行顺序：
--   1. 先在 DBeaver 中整体执行本文件（建表、约束、trigger、注释）。
--   2. 执行完毕后，确认无报错，检查表、约束、触发器、注释均已生效：
--        SELECT table_name FROM information_schema.tables
--        WHERE table_schema = 'ccc' AND table_name IN
--              ('sources', 'source_observations', 'source_claim_links');
--   3. 确认无误后，再单独执行 sqlv3_source_hygiene_v01_smoke_test.sql
--      （冒烟测试会插入并清理少量 TEST_ 前缀数据，验证触发器行为）。
--   4. 冒烟测试全部通过后，git commit + push。
--
-- Important / 重要：
--   本 DDL 文件不插入任何业务行级数据，只做结构迁移。
--   冒烟测试已拆分到独立文件，不在本文件内执行。
--   本文件可重复执行（CREATE TABLE IF NOT EXISTS / CREATE OR REPLACE / DROP+CREATE TRIGGER），
--   重复跑不会报错，也不会产生重复数据。
--
-- 范围声明（Scope）：
--   本次只新增三张表，不修改、不引用任何现有表
--   （ccc.documents / ccc.entities / ccc.events / ccc.event_dashboard 等保持原样不动）。
--
-- 边界声明（Boundary — 必须遵守）：
--   1. 字段命名：本协议使用 source_layer，不使用 source_type，
--      避免与 ccc.event_dashboard.source_type（取值 'rule'/'rule_entity_document'，
--      表示"由哪个规则生成"）发生语义冲突。两套字段互不引用，
--      ccc.event_dashboard.source_type 维持现状不动。
--   2. 实体边界：本协议产生的 source 记录可以承载实体提及/别名，
--      但绝不直接生成或修改 entity_uuid / clean_entities。
--      实体身份解析仍完全由 L4 Entity Governance（entity_upsert.py）负责。
--      若未来需要打通，路径必须是 source → entity_mention → entity_review_queue
--      → L4 entity_upsert，而不是 source 直接写 clean_entities。
--   3. claim 边界：claims 表本次不创建（留待未来 L2 Claim Extraction 模块单独设计）。
--      source_claim_links.claim_id 暂为裸字段，待 claims 表建立后再补外键约束。
--   4. 污染判定边界（指针绑定）：contamination_status 推进到 confirmed，
--      不用"是否存在历史人工确认记录"这种宽松检查（会被时间错位/数据未清理绕过），
--      改为强制绑定一个明确指针 sources.confirmed_contamination_observation_id，
--      该指针必须指向一条真实满足条件的 source_observations 记录：
--        source_id 匹配本条 source、observation_type = 'contamination_confirmation'、
--        confirmed_by_human = true。
--      三个触发器（拆分原因见下方触发器(a)定义处的"修复记录"注释）：
--        (a-1) source_observations 的 BEFORE INSERT：若 proposed_contamination_status
--              ='confirmed' 但 confirmed_by_human 不是 true，拒绝插入。只做检查，不查表。
--        (a-2) source_observations 的 AFTER INSERT：这一行已真正提交后，
--              回填 sources.contamination_status 与 confirmed_contamination_observation_id。
--              （必须在 AFTER 而不是 BEFORE 阶段做，否则触发(b)校验时这一行
--              在 source_observations 表中还查不到，会被误判为"指针无效"。）
--        (b) sources 的 BEFORE UPDATE：若试图把 contamination_status 改为 confirmed，
--            强制校验 confirmed_contamination_observation_id 指向的那条记录
--            是否真实满足上述三个条件，不满足则拒绝，无论是谁发起这次 UPDATE。
--   5. 运维提示：若要删除一条已被 sources 指向的 confirmation observation，
--      必须先解除指针（UPDATE ccc.sources SET confirmed_contamination_observation_id = NULL
--      WHERE confirmed_contamination_observation_id = <observation_id>），再删 observation。
--      这是外键保护的正常行为，不是 bug，目的是防止"source 显示 confirmed 但确认依据已被删除"。
--   6. 与 SQLV3 Claims / Events / Hypothesis Boundary v0.1 的关系：
--      该协议管"这句话算什么认知对象"（event/claim/hypothesis/rumor/interpretation），
--      Source Hygiene 管"这句话从哪来、链路干不干净"，两者不互相覆盖，交汇于
--      source_claim_links。该协议提到的 source_chain 概念，即指本设计中
--      source_claim_links（chain_position / source_role / source_layer_at_link）与
--      sources.derived_from_source_id（信源节点固定衍生关系）共同还原的逻辑链路，
--      并非另一张独立表，本版不新建 source_chain 表。未来若出现以下需求，
--      可再考虑单独建表：链路需要独立编号、多条claim共享同一条完整链路、
--      链路本身需要审核/版本管理/污染评分、需要保存链路快照防止
--      derived_from_source_id 变化影响历史审计。v0.1 暂不需要。
--      另外，该协议中 claim 的 quoted_excerpt 字段，最终以本设计的
--      source_claim_links.quoted_excerpt 为准：一条 claim 通过多条 link
--      可关联多段不同信源的引用片段，claim 自身（未来建表时）不单独存
--      quoted_excerpt，避免出现"哪一段才是 claim 的真正引用"这类歧义。
--   7. Record vs Content 边界（来自该协议第7节，仅供未来 L3 Event Anchoring /
--      L2 Claim Extraction 设计参考，本版不因此调整表结构）：
--      一份 direct_record 信源"存在并被发布"这件事可以支撑一个 event
--      （例：法院公告发布），但该记录"说了什么内容"不会因为信源层级是
--      direct_record 就自动被当作事实，内容本身仍需经由 source_claim_links
--      挂为 claim，与其它来源的 claim 一样接受同等的引用链与确认流程。
--      也就是说，source_layer='direct_record' 只影响信源距离原始事件的层级，
--      绝不在数据库层面触发"内容自动判真"的任何捷径。
-- ============================================================


-- ============================================================
-- 表一：sources — 信源节点登记表
-- ============================================================

CREATE TABLE IF NOT EXISTS ccc.sources (
    id                      bigserial PRIMARY KEY,

    -- 信源基本标识
    source_name             text        NOT NULL,           -- 显示名，如 "BBC中文网"、"@某自媒体账号"
    source_url              text,                            -- 原文链接，可空（口述/截图类信源可能没有）
    source_identifier       text,                            -- 补充标识：账号ID/刊物名/案号等，便于去重
    title                   text,                            -- 该信源对应文章/文档的标题
    published_at            timestamptz,                     -- 该信源原始发布时间（不是入库时间），用于判断时间链/出口转内销
    domain                  text,                            -- 域名，便于按域名聚合统计/识别同源矩阵账号

    -- 三层分类：信源距离原始事件的层级，不表示可信度（Protocol 核心原则1）
    source_layer            text        NOT NULL
        CHECK (source_layer IN ('direct_record', 'reported_account', 'narrative_layer')),

    -- 当前整体状态
    source_status           text        NOT NULL DEFAULT 'unverified'
        CHECK (source_status IN (
            'unverified', 'traceable', 'supported', 'disputed',
            'refuted', 'fabricated', 'parked', 'quarantine'
        )),
    -- 注：污染判定独立用 contamination_status 表达，不在本状态机中（两者是不同维度）

    -- 污染判定：独立状态机
    contamination_status    text        NOT NULL DEFAULT 'unknown'
        CHECK (contamination_status IN ('unknown', 'suspected', 'confirmed', 'dismissed')),

    -- confirmed 状态的证据指针：必须指向一条真实的人工确认 observation 记录
    -- 不允许 contamination_status='confirmed' 而此字段为 NULL（由触发器(b)强制）
    confirmed_contamination_observation_id  bigint,
    -- 此处不写 REFERENCES，因为 source_observations 表在下方才定义；
    -- 待两表都建立后，在文件末尾用 ALTER TABLE 补外键约束

    -- 转述链：本信源固定的衍生关系（自引用）
    -- 例：自媒体A转述BBC，则 derived_from_source_id 指向 BBC 这条 source 记录
    -- 这是信源节点本身的"出身"属性，不等同于它在某条具体 claim 链路里的位置
    derived_from_source_id  bigint      REFERENCES ccc.sources(id),

    first_seen_at           timestamptz DEFAULT now() NOT NULL,
    created_at              timestamptz DEFAULT now() NOT NULL,
    updated_at              timestamptz DEFAULT now() NOT NULL,

    notes                   text                              -- 自由备注
);

CREATE INDEX IF NOT EXISTS idx_sources_layer   ON ccc.sources (source_layer);
CREATE INDEX IF NOT EXISTS idx_sources_status  ON ccc.sources (source_status);
CREATE INDEX IF NOT EXISTS idx_sources_contamination ON ccc.sources (contamination_status);
CREATE INDEX IF NOT EXISTS idx_sources_derived_from   ON ccc.sources (derived_from_source_id);
CREATE INDEX IF NOT EXISTS idx_sources_domain  ON ccc.sources (domain);

COMMENT ON TABLE  ccc.sources IS
    'Source Hygiene Protocol v0.1 — 信源节点登记表。source_layer 只表示距离原始事件的层级，不表示真假。本表绝不直接生成或修改 entity_uuid/clean_entities，实体身份解析归 L4 Entity Governance 管。';
COMMENT ON COLUMN ccc.sources.source_layer IS
    '三层分类：direct_record(原始记录) / reported_account(转述报道) / narrative_layer(叙事评论层)。命名为 source_layer 以避免与 ccc.event_dashboard.source_type 冲突。';
COMMENT ON COLUMN ccc.sources.contamination_status IS
    '出口转内销污染判定，独立状态机：unknown / suspected(规则初筛) / confirmed(人工确认) / dismissed(人工排除)。confirmed 必须有 confirmed_contamination_observation_id 指向真实人工确认记录，由触发器强制。';
COMMENT ON COLUMN ccc.sources.confirmed_contamination_observation_id IS
    '指向 ccc.source_observations 中那条真实满足条件的人工确认记录（observation_type=contamination_confirmation 且 confirmed_by_human=true）。这是 confirmed 状态的唯一合法证据来源，不用时间戳判断，用明确指针绑定。';
COMMENT ON COLUMN ccc.sources.derived_from_source_id IS
    '信源节点固定的衍生关系：若本信源是从另一信源转述而来，指向那条信源记录。不等同于该信源在某条具体 claim 引用链中的位置（那个由 source_claim_links.chain_position 表达）。';
COMMENT ON COLUMN ccc.sources.domain IS
    '信源所在域名，便于按域名聚合统计、识别同源矩阵账号或重复信源集群，也用于判断时间链（reported_account 是否晚于 direct_record）。';


-- ============================================================
-- 表二：source_observations — 对信源的观察与风险记录
-- ============================================================

CREATE TABLE IF NOT EXISTS ccc.source_observations (
    id                      bigserial PRIMARY KEY,
    source_id               bigint      NOT NULL REFERENCES ccc.sources(id) ON DELETE CASCADE,

    observation_type        text        NOT NULL
        CHECK (observation_type IN (
            'status_change',
            'contamination_suspected',
            'contamination_confirmation',
            'contamination_dismissed',
            'fabricated_citation',
            'source_chain_note',
            'manual_review'
        )),

    -- 规则初筛 + 人工确认 两步走（核心：规则只能 suspect，人工才能 confirm）
    flagged_by_rule         boolean     DEFAULT false NOT NULL,   -- 是否由关键词/规则初筛命中
    rule_name               text,                                 -- 命中的规则名称，例如 'outlet_loop_keyword'
    confirmed_by_human      boolean,                               -- NULL=未审，true=人工确认成立，false=人工否定
    confirmed_by            text,                                  -- 审核人标识
    confirmed_at            timestamptz,

    -- 本次观察建议把 contamination_status 推进到什么值
    -- 触发器校验：若为 'confirmed'，confirmed_by_human 必须为 true，否则拒绝写入
    proposed_contamination_status  text
        CHECK (proposed_contamination_status IN ('unknown', 'suspected', 'confirmed', 'dismissed')),

    old_status               text,        -- 状态变更前的 source_status（observation_type = status_change 时使用）
    new_status               text,        -- 状态变更后的 source_status
    old_contamination_status text,        -- 污染状态变更前快照（审计回溯用，不驱动逻辑）
    new_contamination_status text,        -- 污染状态变更后快照

    observed_by              text,        -- 记录这条观察的人/脚本标识
    observation_text         text,        -- 观察详情说明

    created_at               timestamptz DEFAULT now() NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_source_obs_source ON ccc.source_observations (source_id);
CREATE INDEX IF NOT EXISTS idx_source_obs_type   ON ccc.source_observations (observation_type);
CREATE INDEX IF NOT EXISTS idx_source_obs_pending_review
    ON ccc.source_observations (source_id) WHERE confirmed_by_human IS NULL AND flagged_by_rule = true;

COMMENT ON TABLE ccc.source_observations IS
    'Source Hygiene Protocol v0.1 — 信源观察记录表。承载 contamination_status 等判定的"规则初筛+人工确认"过程留痕，是 sources.confirmed_contamination_observation_id 指针的唯一合法指向目标。';
COMMENT ON COLUMN ccc.source_observations.proposed_contamination_status IS
    '本条观察建议把对应 source 的 contamination_status 推进到的值。若为 confirmed，则 confirmed_by_human 必须为 true，否则触发器拒绝写入。';


-- ============================================================
-- 触发器 (a)：source_observations 写入时强制 confirmed 必须人工确认
-- 拆成两阶段，避免与触发器(b)产生时序冲突：
--   (a-1) BEFORE INSERT：只做拒绝检查（检查 NEW 自身字段，不查表，无时序问题）
--   (a-2) AFTER INSERT：这一行已真正落入表中，此时再回填 sources，
--         这样触发器(b)对 source_observations 的 SELECT 才能查到这一行
-- 修复记录：最初版本把回填动作也放在 BEFORE INSERT，导致触发器(b)
-- 校验时这一行还未真正写入表（仍处于"已分配id但未提交"状态），
-- SELECT 查询返回0行，触发器(b)误判为"指针无效"而拒绝，详见冒烟测试报错。
-- ============================================================

CREATE OR REPLACE FUNCTION ccc.trg_enforce_contamination_confirmation()
RETURNS trigger
    LANGUAGE plpgsql
AS $$
BEGIN
    -- (a-1) 拒绝检查：只看 NEW 自身字段，BEFORE INSERT 阶段执行即可，无时序问题
    IF NEW.proposed_contamination_status = 'confirmed' AND NEW.confirmed_by_human IS NOT TRUE THEN
        RAISE EXCEPTION
            'contamination_status 不能由规则直接定为 confirmed：observation source_id=% 缺少 confirmed_by_human=true',
            NEW.source_id;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS enforce_contamination_confirmation ON ccc.source_observations;

CREATE TRIGGER enforce_contamination_confirmation
    BEFORE INSERT ON ccc.source_observations
    FOR EACH ROW
    EXECUTE FUNCTION ccc.trg_enforce_contamination_confirmation();

COMMENT ON TRIGGER enforce_contamination_confirmation ON ccc.source_observations IS
    'BEFORE INSERT 阶段：若 proposed_contamination_status=confirmed 但无人工确认，拒绝插入。只做检查，不回填 sources（回填动作在 AFTER INSERT 阶段的 sync_sources_after_observation 触发器中完成，避免时序冲突）。';


CREATE OR REPLACE FUNCTION ccc.trg_sync_sources_after_observation()
RETURNS trigger
    LANGUAGE plpgsql
AS $$
BEGIN
    -- (a-2) 回填动作：此刻 NEW 这一行已真正落入 source_observations 表，
    -- 触发器(b)对该表的 SELECT 能查到它，不会出现"指针指向尚未提交的行"的误判
    IF NEW.proposed_contamination_status IS NOT NULL THEN
        IF NEW.proposed_contamination_status = 'confirmed' THEN
            -- confirmed 情形：同时回填状态与指针，指针指向这条记录自己
            UPDATE ccc.sources
            SET contamination_status = 'confirmed',
                confirmed_contamination_observation_id = NEW.id,
                updated_at = now()
            WHERE id = NEW.source_id;
        ELSE
            -- 非 confirmed 情形（suspected/dismissed/unknown）：正常推进，不动指针
            UPDATE ccc.sources
            SET contamination_status = NEW.proposed_contamination_status,
                updated_at = now()
            WHERE id = NEW.source_id;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS sync_sources_after_observation ON ccc.source_observations;

CREATE TRIGGER sync_sources_after_observation
    AFTER INSERT ON ccc.source_observations
    FOR EACH ROW
    EXECUTE FUNCTION ccc.trg_sync_sources_after_observation();

COMMENT ON TRIGGER sync_sources_after_observation ON ccc.source_observations IS
    'AFTER INSERT 阶段：此时这条 observation 已真正提交到表中，安全回填 sources.contamination_status 与 confirmed_contamination_observation_id 指针，触发器(b)校验时能查到这条记录，不会出现时序误判。';


-- ============================================================
-- 触发器 (b)：sources 表防绕过 — 校验指针指向的记录是否真实满足条件
-- ============================================================

CREATE OR REPLACE FUNCTION ccc.trg_guard_sources_contamination_confirmed()
RETURNS trigger
    LANGUAGE plpgsql
AS $$
DECLARE
    v_obs_valid boolean;
BEGIN
    IF NEW.contamination_status = 'confirmed' THEN

        IF NEW.confirmed_contamination_observation_id IS NULL THEN
            RAISE EXCEPTION
                'sources.contamination_status 不能改为 confirmed：source id=% 没有指定 confirmed_contamination_observation_id。',
                NEW.id;
        END IF;

        -- 校验指针指向的那条记录是否真实满足：source_id匹配、type正确、人工确认为真
        SELECT EXISTS (
            SELECT 1 FROM ccc.source_observations so
            WHERE so.id = NEW.confirmed_contamination_observation_id
              AND so.source_id = NEW.id
              AND so.observation_type = 'contamination_confirmation'
              AND so.confirmed_by_human IS TRUE
        ) INTO v_obs_valid;

        IF NOT v_obs_valid THEN
            RAISE EXCEPTION
                'sources.contamination_status 不能改为 confirmed：confirmed_contamination_observation_id=% 指向的记录不满足条件（source_id需匹配、observation_type需为contamination_confirmation、confirmed_by_human需为true）。source id=%',
                NEW.confirmed_contamination_observation_id, NEW.id;
        END IF;

    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS guard_sources_contamination_confirmed ON ccc.sources;

CREATE TRIGGER guard_sources_contamination_confirmed
    BEFORE UPDATE ON ccc.sources
    FOR EACH ROW
    EXECUTE FUNCTION ccc.trg_guard_sources_contamination_confirmed();

COMMENT ON TRIGGER guard_sources_contamination_confirmed ON ccc.sources IS
    '防绕过：任何把 contamination_status 改为 confirmed 的 UPDATE（无论谁发起、是否通过应用层），都必须指定一个真实有效的 confirmed_contamination_observation_id，并校验该记录确实满足人工确认条件。不检查"历史上是否存在"，只检查"这次绑定的指针是否有效"。';


-- ============================================================
-- 表三：source_claim_links — claim 与 source 的关联（多对多 + 引用链角色）
-- ============================================================

CREATE TABLE IF NOT EXISTS ccc.source_claim_links (
    id                      bigserial PRIMARY KEY,

    -- claim_id 暂不加外键约束：L2 claims 表尚未建立（本次确认不创建）
    claim_id                bigint      NOT NULL,
    source_id               bigint      NOT NULL REFERENCES ccc.sources(id) ON DELETE CASCADE,

    -- 这个 source 在这条 claim 的引用链里扮演什么角色
    source_role             text        NOT NULL
        CHECK (source_role IN (
            'primary_source', 'reported_by', 'cited_by',
            'repeated_by', 'disputed_by', 'refuted_by', 'contaminated_by'
        )),

    -- 该信源在引用链中的位置（0=最初/直接信源，1=转述第一层，2=转述第二层…）
    -- 配合 sources.derived_from_source_id 可重建完整链路，
    -- 但 chain_position 允许同一 source 在不同 claim 里取不同值，
    -- 解决"同一篇文章在这条claim里是转述者、在那条claim里是被转述者"的场景
    chain_position           integer     DEFAULT 0 NOT NULL CHECK (chain_position >= 0),

    -- 冗余快照：该 source 在被链接的当下，其 source_layer 是什么
    -- 不作为独立真相来源，只是为了不必每次 join sources 表即可审计链路层级分布
    source_layer_at_link     text
        CHECK (source_layer_at_link IN ('direct_record', 'reported_account', 'narrative_layer')),

    -- 原文引用片段：证据本身，保持简短，遵循版权与可追溯性，不做大段摘录
    quoted_excerpt           text,

    -- 人工备注/说明：评注性文字，与 quoted_excerpt（原文）分开存放，避免证据与判断混在一起
    link_note                text,

    created_at               timestamptz DEFAULT now() NOT NULL,

    UNIQUE (claim_id, source_id, source_role)
);

CREATE INDEX IF NOT EXISTS idx_source_claim_links_claim  ON ccc.source_claim_links (claim_id);
CREATE INDEX IF NOT EXISTS idx_source_claim_links_source ON ccc.source_claim_links (source_id);
CREATE INDEX IF NOT EXISTS idx_source_claim_links_role   ON ccc.source_claim_links (source_role);

COMMENT ON TABLE ccc.source_claim_links IS
    'Source Hygiene Protocol v0.1 — claim 与 source 多对多关联表，claim_id 暂为裸字段（claims 表未建立，待建后补外键）。一条 claim 可挂多个 source，保留完整引用链而非只留最后可见信源。';
COMMENT ON COLUMN ccc.source_claim_links.source_role IS
    '信源在该条claim引用链中的角色：primary_source / reported_by / cited_by / repeated_by / disputed_by / refuted_by / contaminated_by。';
COMMENT ON COLUMN ccc.source_claim_links.chain_position IS
    '0=直接/最初信源，1=第一层转述，2=第二层转述... 用于重建链路与识别出口转内销模式。同一 source 在不同 claim 中的 chain_position 可以不同。';
COMMENT ON COLUMN ccc.source_claim_links.source_layer_at_link IS
    'source_layer_at_link is a denormalized snapshot of sources.source_layer at the time of linking. 链接建立时对 sources.source_layer 的冗余快照，用于审计引用链，不作为独立真相来源。';
COMMENT ON COLUMN ccc.source_claim_links.quoted_excerpt IS
    '该信源在本条claim中被引用的原文片段（证据本身），保持简短。';
COMMENT ON COLUMN ccc.source_claim_links.link_note IS
    '人工对这条link的评注/说明（判断性文字），与 quoted_excerpt（原文证据）分开存放。';


-- ============================================================
-- 补充外键约束：sources.confirmed_contamination_observation_id → source_observations.id
-- （必须在两表都建立后才能加，故放在文件末尾）
-- ============================================================

ALTER TABLE ccc.sources
    DROP CONSTRAINT IF EXISTS fk_sources_confirmed_observation;

ALTER TABLE ccc.sources
    ADD CONSTRAINT fk_sources_confirmed_observation
    FOREIGN KEY (confirmed_contamination_observation_id)
    REFERENCES ccc.source_observations(id);

COMMENT ON CONSTRAINT fk_sources_confirmed_observation ON ccc.sources IS
    '补充外键：confirmed_contamination_observation_id 必须指向真实存在的 source_observations 记录。延后到文件末尾添加，因为两表存在相互引用关系。';


-- ============================================================
-- 执行完毕后验证（仅查询，不产生数据）
-- ============================================================

/*
-- 确认三张表都已建立：
SELECT table_name FROM information_schema.tables
WHERE table_schema = 'ccc' AND table_name IN
      ('sources', 'source_observations', 'source_claim_links');

-- 确认三个触发器都已挂载（原"两个"已拆分为三个，见上方修复记录）：
SELECT trigger_name, event_object_table FROM information_schema.triggers
WHERE trigger_schema = 'ccc' AND trigger_name IN
      ('enforce_contamination_confirmation', 'sync_sources_after_observation',
       'guard_sources_contamination_confirmed');

-- 确认外键约束已生效：
SELECT conname FROM pg_constraint WHERE conname = 'fk_sources_confirmed_observation';
*/
