-- ============================================================
-- SQLV3 claims 表 — Smoke Test
-- 目标数据库：PostgreSQL，schema: ccc
-- ============================================================
--
-- Purpose:
--   Verify ccc.claims table constraints and the newly-added
--   foreign key from ccc.source_claim_links.claim_id behave as
--   designed.
--   验证 claims 表的约束（claim_status 默认值/CHECK），以及
--   source_claim_links.claim_id 外键回补后是否真的生效。
--
-- Execution / 执行顺序：
--   1. 必须先执行 sqlv3_claims_v01_ddl.sql。
--   2. 再执行本文件。
--   3. 全部 NOTICE 显示 ✅ 即为通过。
--   4. 本文件结尾会清理所有 TEST_ 前缀的测试数据。
--
-- Important / 重要：
--   若整个测试块中途失败，TEST_ 前缀的数据可能残留，请用文件末尾
--   的查询确认并手动清理（参考 sqlv3_source_hygiene_v01_smoke_test.sql
--   中已有的同类应急清理说明）。
-- ============================================================


DO $$
DECLARE
    v_claim_a   bigint;
    v_source_a  bigint;
    v_status    text;
BEGIN
    -- 前置检查：确认 claims 表和外键约束都已建立
    IF to_regclass('ccc.claims') IS NULL THEN
        RAISE EXCEPTION '冒烟测试前置检查失败：ccc.claims 表尚未建立，请先执行 sqlv3_claims_v01_ddl.sql';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_source_claim_links_claim') THEN
        RAISE EXCEPTION '冒烟测试前置检查失败：source_claim_links.claim_id 的外键约束尚未建立，请先执行 sqlv3_claims_v01_ddl.sql';
    END IF;
    RAISE NOTICE '✅ 前置检查通过：claims 表与外键约束均已存在';

    -- 验证：claim_status 默认值是 unverified，不是 supported
    INSERT INTO ccc.claims (claim_text, claimant)
    VALUES ('TEST_某媒体称海鑫钢铁负债约X', 'TEST_某媒体')
    RETURNING id, claim_status INTO v_claim_a, v_status;

    ASSERT v_status = 'unverified', 'claim_status 默认值应为 unverified，实际为: ' || v_status;
    RAISE NOTICE '✅ claim_status 默认值正确：%', v_status;

    -- 验证：非法 claim_status 被拒绝
    BEGIN
        INSERT INTO ccc.claims (claim_text, claim_status) VALUES ('TEST_非法状态测试', 'invalid_status');
        RAISE EXCEPTION '应该被 CHECK 约束拒绝，但没有报错';
    EXCEPTION WHEN check_violation THEN
        RAISE NOTICE '✅ claim_status 非法值被正确拒绝';
    END;

    -- 验证：claim_text 为必填（NOT NULL），缺失应被拒绝
    BEGIN
        INSERT INTO ccc.claims (claimant) VALUES ('TEST_缺少claim_text');
        RAISE EXCEPTION '应该因 claim_text NOT NULL 被拒绝，但没有报错';
    EXCEPTION WHEN not_null_violation THEN
        RAISE NOTICE '✅ claim_text 缺失被正确拒绝（NOT NULL约束生效）';
    END;

    -- 验证：source_document_id 外键 — 引用一个不存在的document应被拒绝
    BEGIN
        INSERT INTO ccc.claims (claim_text, source_document_id) VALUES ('TEST_引用不存在的文档', 999999998);
        RAISE EXCEPTION '应该因外键约束被拒绝，但没有报错';
    EXCEPTION WHEN foreign_key_violation THEN
        RAISE NOTICE '✅ source_document_id 外键约束正确拒绝不存在的document引用';
    END;

    -- 核心验证：source_claim_links.claim_id 外键回补是否真的生效
    -- 插入一个真实的 source 用于关联测试
    INSERT INTO ccc.sources (source_name, source_layer, source_status)
    VALUES ('TEST_claims外键测试用source', 'direct_record', 'traceable')
    RETURNING id INTO v_source_a;

    -- 用真实存在的 claim_id (v_claim_a) 建立 link，应该成功
    INSERT INTO ccc.source_claim_links (claim_id, source_id, source_role, chain_position)
    VALUES (v_claim_a, v_source_a, 'primary_source', 0);
    RAISE NOTICE '✅ source_claim_links 使用真实存在的 claim_id 插入成功';

    -- 用不存在的 claim_id 建立 link，现在应该被外键拒绝
    -- （在外键回补之前，这种插入是会成功的——这正是回补外键要堵住的漏洞）
    BEGIN
        INSERT INTO ccc.source_claim_links (claim_id, source_id, source_role, chain_position)
        VALUES (888888888, v_source_a, 'cited_by', 0);
        RAISE EXCEPTION '应该被外键约束拒绝（claim_id=888888888不存在），但没有报错——说明外键回补未生效！';
    EXCEPTION WHEN foreign_key_violation THEN
        RAISE NOTICE '✅ 外键回补已生效：source_claim_links 拒绝了不存在的 claim_id';
    END;

    -- 清理测试数据
    DELETE FROM ccc.source_claim_links WHERE claim_id = v_claim_a;
    DELETE FROM ccc.sources WHERE id = v_source_a;
    DELETE FROM ccc.claims WHERE id = v_claim_a;

    RAISE NOTICE '✅✅✅ claims 表冒烟测试全部通过，测试数据已清理 ✅✅✅';
END;
$$;


-- ============================================================
-- 收尾确认（仅查询）：确认测试数据确实没有残留
-- ============================================================

SELECT count(*) AS residual_test_claims
FROM ccc.claims
WHERE claim_text LIKE 'TEST_%';
-- 期望结果：0

SELECT count(*) AS residual_test_links_888
FROM ccc.source_claim_links
WHERE claim_id = 888888888;
-- 期望结果：0（这条本来就应该插入失败，不会真正存在）
