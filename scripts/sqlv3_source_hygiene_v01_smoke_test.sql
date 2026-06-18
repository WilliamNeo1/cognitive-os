-- ============================================================
-- SQLV3 Source Hygiene Protocol v0.1 — Smoke Test
-- 目标数据库：PostgreSQL，schema: ccc
-- ============================================================
--
-- Purpose:
--   Verify sources / source_observations / source_claim_links tables,
--   constraints, and the two-layer contamination-confirmation triggers
--   all behave as designed.
--   验证 sources / source_observations / source_claim_links 三张表的
--   约束、两层污染确认触发器、confirmed_contamination_observation_id
--   指针机制是否按设计生效。
--
-- Execution / 执行顺序：
--   1. 必须先执行 sqlv3_source_hygiene_v01_ddl.sql，确认三张表已建立。
--   2. 再执行本文件。
--   3. 全部 NOTICE 显示 ✅ 即为通过；任何 EXCEPTION 未被捕获则说明设计有问题。
--   4. 本文件结尾会自动清理所有 TEST_ 前缀的测试数据，执行完毕后
--      表中不会残留任何测试痕迹。
--
-- Important / 重要：
--   本文件只做验证，不修改表结构。如果三张表不存在，本文件会直接报错，
--   这是预期行为（提示你忘了先跑 DDL）。
--
--   若整个测试块（DO $$ ... $$）在中途失败（例如某条 ASSERT 没通过，
--   或某个 PostgreSQL 版本对 RAISE EXCEPTION 文本的 LIKE 匹配行为有差异），
--   PostgreSQL 会在失败的那一行直接中断，不会继续往后执行文件末尾的
--   清理语句 —— 也就是说 TEST_ 前缀的测试数据有可能残留在
--   ccc.sources / ccc.source_observations / ccc.source_claim_links 中。
--   遇到这种情况：
--     1. 不必惊慌，先看报错信息定位具体是哪一步失败（这正是冒烟测试的目的）。
--     2. 用本文件末尾的两条查询确认是否有残留：
--          SELECT count(*) FROM ccc.sources WHERE source_name LIKE 'TEST_%';
--          SELECT count(*) FROM ccc.source_claim_links WHERE claim_id = 999999999;
--     3. 若有残留，手动清理（注意：必须把 contamination_status 与指针
--          一起改，不能只清指针——否则会产生"confirmed但指针为NULL"的
--          非法中间状态，被触发器(b)正确拦截，这是设计预期行为）：
--          UPDATE ccc.sources SET contamination_status = 'unknown',
--                                  confirmed_contamination_observation_id = NULL
--            WHERE source_name LIKE 'TEST_%';
--          DELETE FROM ccc.source_claim_links WHERE claim_id = 999999999;
--          DELETE FROM ccc.source_observations
--            WHERE source_id IN (SELECT id FROM ccc.sources WHERE source_name LIKE 'TEST_%');
--          DELETE FROM ccc.sources WHERE source_name LIKE 'TEST_%';
--     4. 清理完毕、确认两条查询都返回 0 后，再重新跑本文件。
-- ============================================================


DO $$
DECLARE
    v_source_a bigint;
    v_source_b bigint;
    v_obs_id   bigint;
    v_status   text;
    v_ptr      bigint;
BEGIN
    -- 前置检查：确认三张表存在，否则提前给出清晰报错而不是裸 SQL 错误
    IF to_regclass('ccc.sources') IS NULL
       OR to_regclass('ccc.source_observations') IS NULL
       OR to_regclass('ccc.source_claim_links') IS NULL THEN
        RAISE EXCEPTION '冒烟测试前置检查失败：三张表尚未建立，请先执行 sqlv3_source_hygiene_v01_ddl.sql';
    END IF;
    RAISE NOTICE '✅ 前置检查通过：三张表均已存在';

    -- 插入一条 direct_record
    INSERT INTO ccc.sources (source_name, source_layer, source_status, domain, title)
    VALUES ('TEST_直接记录', 'direct_record', 'traceable', 'court.example.gov', 'TEST法院公告标题')
    RETURNING id INTO v_source_a;

    -- 插入一条 reported_account，转述自上面那条
    INSERT INTO ccc.sources (source_name, source_layer, source_status, derived_from_source_id, domain)
    VALUES ('TEST_转述报道', 'reported_account', 'unverified', v_source_a, 'news.example.com')
    RETURNING id INTO v_source_b;

    -- 验证非法 source_layer 会被拒绝
    BEGIN
        INSERT INTO ccc.sources (source_name, source_layer) VALUES ('TEST_非法类型', 'invalid_layer');
        RAISE EXCEPTION '应该被 CHECK 约束拒绝，但没有报错';
    EXCEPTION WHEN check_violation THEN
        RAISE NOTICE '✅ source_layer 非法值被正确拒绝';
    END;

    -- 验证：规则初筛只能写 suspected
    INSERT INTO ccc.source_observations
        (source_id, observation_type, flagged_by_rule, rule_name, proposed_contamination_status, observation_text)
    VALUES
        (v_source_b, 'contamination_suspected', true, 'outlet_loop_keyword', 'suspected', 'TEST规则初筛命中');

    SELECT contamination_status INTO v_status FROM ccc.sources WHERE id = v_source_b;
    ASSERT v_status = 'suspected', 'contamination_status 应被规则推进到 suspected';
    RAISE NOTICE '✅ 规则初筛成功写入 suspected，当前状态: %', v_status;

    -- 验证：规则尝试通过 observation 直接写 confirmed（无人工确认）应被触发器(a)拒绝
    BEGIN
        INSERT INTO ccc.source_observations
            (source_id, observation_type, flagged_by_rule, rule_name, proposed_contamination_status, observation_text)
        VALUES
            (v_source_b, 'contamination_confirmation', true, 'outlet_loop_keyword', 'confirmed', 'TEST规则试图越权定罪');
        RAISE EXCEPTION '应该被触发器(a)拒绝，但没有报错';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%不能由规则直接定为 confirmed%' THEN
            RAISE NOTICE '✅ 触发器(a) 正确拒绝：规则越权写 confirmed';
        ELSE
            RAISE;
        END IF;
    END;

    -- 验证：有人绕过 observation，直接 UPDATE sources 改成 confirmed 但不给指针，应被触发器(b)拒绝
    BEGIN
        UPDATE ccc.sources SET contamination_status = 'confirmed' WHERE id = v_source_b;
        RAISE EXCEPTION '应该被触发器(b)拒绝（缺指针），但没有报错';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%没有指定 confirmed_contamination_observation_id%' THEN
            RAISE NOTICE '✅ 触发器(b) 正确拒绝：直接 UPDATE 缺少指针';
        ELSE
            RAISE;
        END IF;
    END;

    -- 验证：伪造一个不满足条件的指针（指向 suspected 那条记录，不是 contamination_confirmation 类型）应被拒绝
    SELECT id INTO v_obs_id FROM ccc.source_observations
        WHERE source_id = v_source_b AND observation_type = 'contamination_suspected' LIMIT 1;
    BEGIN
        UPDATE ccc.sources
        SET contamination_status = 'confirmed', confirmed_contamination_observation_id = v_obs_id
        WHERE id = v_source_b;
        RAISE EXCEPTION '应该被触发器(b)拒绝（指针指向无效记录），但没有报错';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%指向的记录不满足条件%' THEN
            RAISE NOTICE '✅ 触发器(b) 正确拒绝：指针指向不满足条件的记录';
        ELSE
            RAISE;
        END IF;
    END;

    -- 验证：正常人工确认流程（一次 INSERT 自动完成回填）
    INSERT INTO ccc.source_observations
        (source_id, observation_type, flagged_by_rule, rule_name,
         confirmed_by_human, confirmed_by, confirmed_at, proposed_contamination_status, observation_text)
    VALUES
        (v_source_b, 'contamination_confirmation', true, 'outlet_loop_keyword',
         true, 'TEST_reviewer', now(), 'confirmed', 'TEST人工确认通过')
    RETURNING id INTO v_obs_id;

    SELECT contamination_status, confirmed_contamination_observation_id
        INTO v_status, v_ptr FROM ccc.sources WHERE id = v_source_b;
    ASSERT v_status = 'confirmed', 'contamination_status 应在人工确认后推进到 confirmed';
    ASSERT v_ptr = v_obs_id, 'confirmed_contamination_observation_id 应指向刚插入的那条 observation';
    RAISE NOTICE '✅ 人工确认后自动回填成功：status=%, 指针指向 observation id=%', v_status, v_ptr;

    -- 验证：现在用真实有效的指针重复 UPDATE 应该被允许
    UPDATE ccc.sources
    SET contamination_status = 'confirmed', confirmed_contamination_observation_id = v_obs_id
    WHERE id = v_source_b;
    RAISE NOTICE '✅ 使用真实有效指针的 UPDATE 被正确允许';

    -- 验证 claim link 写入：chain_position / source_role / quoted_excerpt / link_note / source_layer_at_link
    INSERT INTO ccc.source_claim_links
        (claim_id, source_id, source_role, chain_position, source_layer_at_link, quoted_excerpt, link_note)
    VALUES
        (999999999, v_source_a, 'primary_source', 0, 'direct_record', 'TEST原文片段A', 'TEST备注A');
    INSERT INTO ccc.source_claim_links
        (claim_id, source_id, source_role, chain_position, source_layer_at_link, quoted_excerpt, link_note)
    VALUES
        (999999999, v_source_b, 'reported_by', 1, 'reported_account', 'TEST原文片段B', 'TEST备注B');
    RAISE NOTICE '✅ source_claim_links 多对多+引用链写入成功';

    -- 清理测试数据（先清 sources 上的指针引用，再删 observations，避免外键冲突）
    -- 注意：必须把 contamination_status 一起降级，不能只清指针 —— 否则会产生
    -- "contamination_status=confirmed 但 confirmed_contamination_observation_id=NULL"
    -- 这种非法中间状态，被触发器(b)正确拦截（这恰好证明触发器(b)在按设计工作）。
    UPDATE ccc.sources
    SET contamination_status = 'unknown',
        confirmed_contamination_observation_id = NULL
    WHERE id IN (v_source_a, v_source_b);
    DELETE FROM ccc.source_claim_links WHERE claim_id = 999999999;
    DELETE FROM ccc.source_observations WHERE source_id IN (v_source_a, v_source_b);
    DELETE FROM ccc.sources WHERE id IN (v_source_a, v_source_b);

    RAISE NOTICE '✅✅✅ Source Hygiene v0.1 冒烟测试全部通过，测试数据已清理 ✅✅✅';
END;
$$;


-- ============================================================
-- 收尾确认（仅查询）：确认测试数据确实没有残留
-- ============================================================

SELECT count(*) AS residual_test_sources
FROM ccc.sources
WHERE source_name LIKE 'TEST_%';
-- 期望结果：0

SELECT count(*) AS residual_test_links
FROM ccc.source_claim_links
WHERE claim_id = 999999999;
-- 期望结果：0
