--
-- PostgreSQL database dump
--

\restrict 684mgj3aCJHh8oJldlxultqPKz0he16KpogTfY79UFpkTXZnHz23tvoRwIa7OnS

-- Dumped from database version 18.3 (Postgres.app)
-- Dumped by pg_dump version 18.3 (Postgres.app)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: ccc; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA ccc;


ALTER SCHEMA ccc OWNER TO postgres;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: postgres
--

-- *not* creating schema, since initdb creates it


ALTER SCHEMA public OWNER TO postgres;

--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: postgres
--

COMMENT ON SCHEMA public IS '';


--
-- Name: pg_trgm; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA public;


--
-- Name: EXTENSION pg_trgm; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pg_trgm IS 'text similarity measurement and index searching based on trigrams';


--
-- Name: vector; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA public;


--
-- Name: EXTENSION vector; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION vector IS 'vector data type and ivfflat and hnsw access methods';


--
-- Name: ai_tokenize(text); Type: FUNCTION; Schema: ccc; Owner: postgres
--

CREATE FUNCTION ccc.ai_tokenize(input_text text) RETURNS TABLE(token text)
    LANGUAGE plpgsql IMMUTABLE
    AS $_$
BEGIN
    RETURN QUERY
        SELECT DISTINCT trim(x)
        FROM regexp_split_to_table(
            regexp_replace(
                regexp_replace(input_text, '[\n\r\t]+', ' ', 'g'),
                u&'\FF0C\3002\FF01\FF1F\3001\FF1B\FF1A\300C\300D\300E\300F\FF08\FF09\2026\2014\00B7',
                ' ', 'g'
            ),
            '\s+'
        ) AS x
        WHERE length(trim(x)) >= 2
          AND trim(x) !~ $r$^\d+([.,]\d+)?$$r$
          AND trim(x) !~ $r$^[-=+*/\\|<>@#$%^&_]+$$r$
          AND trim(x) !~ $r$^[[:punct:]]+$$r$;
END;
$_$;


ALTER FUNCTION ccc.ai_tokenize(input_text text) OWNER TO postgres;

--
-- Name: clean_person_candidate(text); Type: FUNCTION; Schema: ccc; Owner: postgres
--

CREATE FUNCTION ccc.clean_person_candidate(input_text text) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    AS $_$
BEGIN
    RETURN nullif(
        trim(
            regexp_replace(
                regexp_replace(
                    coalesce(input_text, ''),
                    '\*\*|__|`|#+',
                    '',
                    'g'
                ),
                '^[[:punct:][:space:]]+|[[:punct:][:space:]]+$',
                '',
                'g'
            )
        ),
        ''
    );
END;
$_$;


ALTER FUNCTION ccc.clean_person_candidate(input_text text) OWNER TO postgres;

--
-- Name: decision_engine_v1(text); Type: FUNCTION; Schema: ccc; Owner: postgres
--

CREATE FUNCTION ccc.decision_engine_v1(p_entity_name text) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
  v_p6            jsonb;
  v_entity_id     bigint;

  v_forecast_status     text;
  v_decision_readiness  text;
  v_decision_mode_hint  text;
  v_pressure            text;
  v_trajectory_code     text;
  v_timeline_force      float;
  v_confidence          float;
  v_confidence_label    text;
  v_trust_score         float;
  v_trust_label         text;
  v_gate_passed         boolean;
  v_alert               text;

  v_action_status   text;
  v_action_level    text;
  v_action_mode     text;
  v_risk_boundary   text;
  v_review_trigger  text;

  v_score_status    float;
  v_score_level     float;
  v_score_mode      float;
  v_score_boundary  float;
  v_score_trigger   float;
  v_decision_score  float;

  v_final_decision    text;
  v_final_priority    text;
  v_final_instruction text;
  v_primary_rule      text;
  v_gate_reason       text;

BEGIN
  v_p6 := ccc.prediction_output_standard_v1(p_entity_name);

  IF COALESCE((v_p6->>'ok')::boolean, false) IS NOT TRUE THEN
    RETURN jsonb_build_object(
      'ok', false, 'error', 'p6 input failed',
      'entity', p_entity_name, 'detail', v_p6->>'error'
    );
  END IF;

  SELECT ep.entity_id INTO v_entity_id
  FROM ccc.entity_profiles ep
  WHERE lower(ep.entity_name) = lower(p_entity_name)
  LIMIT 1;

  v_forecast_status    := COALESCE(v_p6->>'forecast_status',    'WEAK');
  v_decision_readiness := COALESCE(v_p6->>'decision_readiness', 'WAIT');
  v_decision_mode_hint := COALESCE(v_p6->>'decision_mode_hint', 'HOLD');
  v_pressure           := COALESCE(v_p6->>'pressure',           'LOW');
  v_trajectory_code    := COALESCE(v_p6->>'trajectory_code',    'STABLE');
  v_timeline_force     := COALESCE((v_p6->>'timeline_force')::float, 0.0);
  v_confidence         := COALESCE((v_p6->>'confidence')::float, 0.5);
  v_confidence_label   := COALESCE(v_p6->>'confidence_label',   'LOW');
  v_trust_score        := COALESCE((v_p6->>'trust_score')::float, 0.0);
  v_trust_label        := COALESCE(v_p6->>'trust_label',        'LOW');
  v_gate_passed        := COALESCE((v_p6->>'confidence_gate_passed')::boolean, false);
  v_alert              := v_p6->>'alert';

  -- Rule 1
  IF NOT v_gate_passed THEN
    IF v_forecast_status = 'BLOCKED' THEN
      v_action_status := 'NO_ACTION'; v_action_mode := 'HOLD';
      v_risk_boundary := 'BLOCKED';
      v_primary_rule  := 'Rule 1: Gate Blocking Rule (BLOCKED)';
    ELSE
      v_action_status := 'WAIT'; v_action_mode := 'HOLD';
      v_risk_boundary := 'BLOCKED';
      v_primary_rule  := 'Rule 1: Gate Blocking Rule (WEAK)';
    END IF;

  -- Rule 2
  ELSIF v_forecast_status = 'VALID' AND v_decision_readiness = 'READY' THEN
    v_action_status := 'ACTION';
    v_primary_rule  := 'Rule 2: Ready Action Rule';

    -- Rule 3
    IF v_pressure = 'CRITICAL' AND v_trajectory_code = 'UP' THEN
      v_action_level  := 'CRITICAL'; v_action_mode := 'ESCALATION_PREP';
      v_risk_boundary := CASE
        WHEN v_confidence_label = 'HIGH' AND v_trust_label = 'HIGH' THEN 'LOOSE'
        ELSE 'NORMAL' END;
      v_primary_rule  := 'Rule 3: Critical Escalation Rule';

    -- Rule 6
    ELSIF v_decision_mode_hint = 'HOLD' THEN
      v_action_level  := 'HIGH'; v_action_mode := 'HOLD';
      v_risk_boundary := 'NORMAL';
      v_primary_rule  := 'Rule 6: No Strong Direction Rule';

    ELSE
      v_action_level  := CASE v_pressure
        WHEN 'CRITICAL' THEN 'HIGH' WHEN 'HIGH' THEN 'HIGH'
        WHEN 'MEDIUM'   THEN 'MEDIUM' ELSE 'LOW' END;
      v_action_mode   := v_decision_mode_hint;
      v_risk_boundary := CASE
        WHEN v_confidence_label = 'HIGH' AND v_trust_label = 'HIGH' THEN 'LOOSE'
        WHEN v_forecast_status = 'VALID' THEN 'NORMAL'
        ELSE 'STRICT' END;
    END IF;

  -- Rule 4
  ELSIF v_pressure IN ('HIGH','CRITICAL')
    AND v_trajectory_code = 'STABLE'
    AND v_decision_readiness = 'MONITOR' THEN
    v_action_status := 'MONITOR'; v_action_level := 'MEDIUM';
    v_action_mode   := 'DEFENSIVE'; v_risk_boundary := 'NORMAL';
    v_primary_rule  := 'Rule 4: Stable High Pressure Rule';

  -- Rule 5
  ELSIF v_forecast_status = 'WEAK' THEN
    v_action_status := 'WAIT'; v_action_level := 'LOW';
    v_action_mode   := 'HOLD'; v_risk_boundary := 'STRICT';
    v_primary_rule  := 'Rule 5: Weak Evidence Rule';

  ELSE
    v_action_status := 'MONITOR'; v_action_level := 'MEDIUM';
    v_action_mode   := COALESCE(v_decision_mode_hint, 'HOLD');
    v_risk_boundary := 'NORMAL';
    v_primary_rule  := 'Default: Monitor Rule';
  END IF;

  v_review_trigger := CASE
    WHEN v_forecast_status IN ('BLOCKED','WEAK') THEN 'MANUAL_REVIEW'
    WHEN v_forecast_status = 'WATCH'             THEN 'SIGNAL_BASED'
    WHEN v_trajectory_code = 'UP'                THEN 'ESCALATION_CHANGE'
    WHEN v_trajectory_code = 'STABLE'            THEN 'TIME_BASED'
    WHEN v_trajectory_code = 'DOWN'              THEN 'SIGNAL_BASED'
    ELSE 'TIME_BASED'
  END;

  IF v_action_level IS NULL THEN
    v_action_level := CASE v_action_status
      WHEN 'NO_ACTION' THEN 'NONE'
      WHEN 'WAIT'      THEN 'LOW'
      WHEN 'MONITOR'   THEN 'MEDIUM'
      ELSE 'LOW' END;
  END IF;

  -- 评分
  v_score_status := CASE v_action_status
    WHEN 'ACTION' THEN 1.00 WHEN 'MONITOR' THEN 0.55
    WHEN 'WAIT'   THEN 0.30 WHEN 'NO_ACTION' THEN 0.00 ELSE 0.00 END;
  v_score_level := CASE v_action_level
    WHEN 'CRITICAL' THEN 1.00 WHEN 'HIGH'   THEN 0.80
    WHEN 'MEDIUM'   THEN 0.55 WHEN 'LOW'    THEN 0.30
    WHEN 'NONE'     THEN 0.00 ELSE 0.00 END;
  v_score_mode := CASE v_action_mode
    WHEN 'ESCALATION_PREP' THEN 1.00 WHEN 'OPPORTUNISTIC' THEN 0.85
    WHEN 'DEFENSIVE'       THEN 0.65 WHEN 'HOLD'          THEN 0.45
    WHEN 'DE_ESCALATION'   THEN 0.30 ELSE 0.45 END;
  v_score_boundary := CASE v_risk_boundary
    WHEN 'LOOSE'   THEN 1.00 WHEN 'NORMAL' THEN 0.75
    WHEN 'STRICT'  THEN 0.40 WHEN 'BLOCKED' THEN 0.00 ELSE 0.00 END;
  v_score_trigger := CASE v_review_trigger
    WHEN 'ESCALATION_CHANGE' THEN 1.00 WHEN 'SIGNAL_BASED'   THEN 0.70
    WHEN 'TIME_BASED'        THEN 0.50 WHEN 'CONFIDENCE_DROP' THEN 0.30
    WHEN 'MANUAL_REVIEW'     THEN 0.20 ELSE 0.50 END;

  v_decision_score := ROUND((
    v_score_status   * 0.30 +
    v_score_level    * 0.30 +
    v_score_mode     * 0.20 +
    v_score_boundary * 0.15 +
    v_score_trigger  * 0.05
  )::numeric, 4);

  -- 分数映射
  v_final_decision := CASE
    WHEN v_decision_score >= 0.80 THEN 'DO'
    WHEN v_decision_score >= 0.60 THEN 'DO_WITH_CAUTION'
    WHEN v_decision_score >= 0.45 THEN 'MONITOR_ONLY'
    WHEN v_decision_score >= 0.25 THEN 'WAIT'
    ELSE 'NO_GO'
  END;

  -- ── 硬覆盖规则（含 Rule 7/8/9）─────────────────────────────────

  -- Rule 9: Blocked Boundary Ceiling
  IF v_risk_boundary = 'BLOCKED' AND v_final_decision NOT IN ('WAIT','NO_GO') THEN
    v_final_decision := 'WAIT';
  END IF;

  -- Rule 1 硬阻断
  IF v_forecast_status = 'BLOCKED' OR v_action_status = 'NO_ACTION' THEN
    v_final_decision := 'NO_GO';
  END IF;
  IF v_action_status = 'WAIT' AND v_final_decision NOT IN ('WAIT','NO_GO') THEN
    v_final_decision := 'WAIT';
  END IF;

  -- Rule 7: Defensive Monitor Upgrade
  -- MONITOR + DEFENSIVE + NORMAL/LOOSE + score >= 0.60 → DO_WITH_CAUTION
  IF v_action_status = 'MONITOR'
    AND v_action_mode = 'DEFENSIVE'
    AND v_risk_boundary IN ('NORMAL','LOOSE')
    AND v_decision_score >= 0.60
  THEN
    v_final_decision := 'DO_WITH_CAUTION';

  -- MONITOR 其他情况封顶 MONITOR_ONLY
  ELSIF v_action_status = 'MONITOR'
    AND v_final_decision IN ('DO','DO_WITH_CAUTION')
    AND NOT (v_action_mode = 'DEFENSIVE' AND v_decision_score >= 0.60)
  THEN
    v_final_decision := 'MONITOR_ONLY';
  END IF;

  -- Rule 8: Hold Mode Ceiling
  IF v_action_mode = 'HOLD'
    AND v_risk_boundary != 'BLOCKED'
    AND v_final_decision = 'DO'
  THEN
    v_final_decision := 'DO_WITH_CAUTION';
  END IF;

  -- final_priority
  v_final_priority := CASE
    WHEN v_final_decision = 'DO'     AND v_action_level = 'CRITICAL' THEN 'P0'
    WHEN v_final_decision = 'DO'     AND v_action_level = 'HIGH'     THEN 'P1'
    WHEN v_final_decision = 'DO_WITH_CAUTION'                        THEN 'P2'
    WHEN v_final_decision = 'MONITOR_ONLY'                           THEN 'P2'
    WHEN v_final_decision = 'WAIT'                                   THEN 'P3'
    WHEN v_final_decision = 'NO_GO'                                  THEN 'P4'
    ELSE 'P3'
  END;

  -- final_instruction
  v_final_instruction := CASE
    WHEN v_final_decision = 'DO' AND v_action_mode = 'ESCALATION_PREP'
      THEN '进入升级预备，优先配置资源，准备应对高强度变化。'
    WHEN v_final_decision = 'DO' AND v_action_mode = 'OPPORTUNISTIC'
      THEN '机会窗口开启，可低风险捕捉，避免过度暴露。'
    WHEN v_final_decision = 'DO' AND v_action_mode = 'HOLD'
      THEN '行动条件具备，但方向不明确，保持准备状态，不主动升级。'
    WHEN v_final_decision = 'DO_WITH_CAUTION' AND v_action_mode = 'DEFENSIVE'
      THEN '高压稳定态势，可低风险防御准备，不主动升级，保持观察。'
    WHEN v_final_decision = 'DO_WITH_CAUTION'
      THEN '允许低风险准备，但不得主动升级，等待方向确认。'
    WHEN v_final_decision = 'MONITOR_ONLY' AND v_action_mode = 'DEFENSIVE'
      THEN '保持防御观察，记录变化信号，不进入主动行动。'
    WHEN v_final_decision = 'MONITOR_ONLY'
      THEN '持续监控，信号尚未达到行动阈值，保持观察。'
    WHEN v_final_decision = 'WAIT'
      THEN '证据不足，暂不行动，等待更高可信度信号。'
    WHEN v_final_decision = 'NO_GO'
      THEN '预测被阻断，不进入行动层。'
    ELSE '状态未明，保持观察。'
  END;

  v_gate_reason := CASE
    WHEN NOT v_gate_passed AND v_forecast_status = 'BLOCKED'
      THEN 'Gate blocked: confidence and evidence both below threshold. Forecast status BLOCKED.'
    WHEN NOT v_gate_passed
      THEN 'Gate blocked: confidence or evidence below operational threshold.'
    WHEN v_gate_passed AND v_forecast_status = 'VALID'
      THEN 'Gate passed: confidence and evidence above threshold. Forecast status VALID.'
    WHEN v_gate_passed
      THEN 'Gate passed: threshold met. Forecast status ' || v_forecast_status || '.'
    ELSE 'Gate state unknown.'
  END;

  RETURN jsonb_build_object(
    'ok',             true,
    'schema_version', 'decision_engine_output_v1',
    'entity',         p_entity_name,
    'entity_id',      v_entity_id,
    'generated_at',   now(),

    'p7_input_snapshot', jsonb_build_object(
      'canonical_entity',       p_entity_name,
      'forecast_status',        v_forecast_status,
      'decision_readiness',     v_decision_readiness,
      'decision_mode_hint',     v_decision_mode_hint,
      'pressure',               v_pressure,
      'trajectory_code',        v_trajectory_code,
      'timeline_force',         round(v_timeline_force::numeric, 4),
      'confidence',             round(v_confidence::numeric, 2),
      'confidence_label',       v_confidence_label,
      'trust_score',            round(v_trust_score::numeric, 4),
      'trust_label',            v_trust_label,
      'confidence_gate_passed', v_gate_passed,
      'alert',                  v_alert,
      'source_schema_version',  'prediction_output_standard_v1'
    ),

    'action_status',  v_action_status,
    'action_level',   v_action_level,
    'action_mode',    v_action_mode,
    'risk_boundary',  v_risk_boundary,
    'review_trigger', v_review_trigger,

    'decision_score', v_decision_score,
    'score_breakdown', jsonb_build_object(
      'action_status_score',  v_score_status,
      'action_level_score',   v_score_level,
      'action_mode_score',    v_score_mode,
      'risk_boundary_score',  v_score_boundary,
      'review_trigger_score', v_score_trigger,
      'weights', '{"action_status":0.30,"action_level":0.30,"action_mode":0.20,"risk_boundary":0.15,"review_trigger":0.05}'::jsonb
    ),

    'final_decision',    v_final_decision,
    'final_priority',    v_final_priority,
    'final_instruction', v_final_instruction,

    'decision_reason', jsonb_build_object(
      'primary_rule', v_primary_rule,
      'gate_effect',  v_gate_reason,
      'action_bias',  v_action_mode,
      'reason', concat(
        'forecast_status=', v_forecast_status,
        ', decision_readiness=', v_decision_readiness,
        ', pressure=', v_pressure,
        ', trajectory=', v_trajectory_code,
        ', gate_passed=', v_gate_passed::text,
        ', timeline_force=', round(v_timeline_force::numeric, 4)
      )
    )
  );
END;
$$;


ALTER FUNCTION ccc.decision_engine_v1(p_entity_name text) OWNER TO postgres;

--
-- Name: embed_document(bigint); Type: FUNCTION; Schema: ccc; Owner: postgres
--

CREATE FUNCTION ccc.embed_document(doc_id bigint) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_text TEXT;
    v_embedding vector(1536);
BEGIN

    SELECT content
    INTO v_text
    FROM ccc.documents
    WHERE id = doc_id;

    IF v_text IS NULL THEN
        RETURN 'NO_DOCUMENT';
    END IF;

    -- ⚠️ 这里是关键：先做占位 embedding（避免报错）
    -- 如果你接 OpenAI / DBeaver AI，会替换这一段

    SELECT array_agg(random())::vector
    INTO v_embedding
    FROM generate_series(1,1536);

    UPDATE ccc.documents
    SET embedding = v_embedding,
        embedding_model = 'v21.1_mock',
        embedding_created_at = now()
    WHERE id = doc_id;

    RETURN 'OK';

END;
$$;


ALTER FUNCTION ccc.embed_document(doc_id bigint) OWNER TO postgres;

--
-- Name: entity_resolve_v3_local(text); Type: FUNCTION; Schema: ccc; Owner: postgres
--

CREATE FUNCTION ccc.entity_resolve_v3_local(q text) RETURNS TABLE(canonical_name text, entity_id bigint, match_type text, confidence double precision, entity_type text)
    LANGUAGE sql STABLE
    AS $$
WITH input AS (
  SELECT
    trim(q) AS raw_q,
    lower(trim(q)) AS q_norm
),

blocked_canonical AS (
  SELECT lower(unnest(ARRAY[
    -- 简体 / 繁体
    '中国',
    '中國',
    '中国政府',
    '中國政府',
    '中华人民共和国',
    '中華人民共和國',
    '中华人民共和国政府',
    '中華人民共和國政府',
    '国务院',
    '國務院',

    -- 英文 / 缩写 / 转喻
    'China',
    'PRC',
    'P.R.C.',
    'People''s Republic of China',
    'Chinese government',
    'Government of China',
    'PRC Government',
    'Beijing',
    'State Council',
    'PRC State Council',

    -- 拼音
    'zhongguo',
    'zhong guo',
    'zhongguo zhengfu',
    'zhong guo zheng fu',
    'zhonghua renmin gongheguo'
  ])) AS name
),

candidates AS (

  -- 1. canonical 精确命中
  SELECT
    ce.canonical_name,
    ce.id AS entity_id,
    'entity_exact'::text AS match_type,
    1.00::double precision AS confidence,
    ce.entity_type
  FROM ccc.clean_entities ce
  JOIN input i ON lower(ce.canonical_name) = i.q_norm
  WHERE lower(ce.canonical_name) NOT IN (SELECT name FROM blocked_canonical)

  UNION ALL

  -- 2. alias 精确命中
  SELECT
    ce.canonical_name,
    ce.id AS entity_id,
    'alias_exact'::text AS match_type,
    0.99::double precision AS confidence,
    ce.entity_type
  FROM ccc.person_aliases pa
  JOIN ccc.clean_entities ce
    ON lower(ce.canonical_name) = lower(pa.canonical)
  JOIN input i ON lower(trim(pa.alias)) = i.q_norm

  UNION ALL

  -- 3. 查询中包含 canonical
  SELECT
    ce.canonical_name,
    ce.id AS entity_id,
    'entity_contained_in_query'::text AS match_type,
    0.92::double precision AS confidence,
    ce.entity_type
  FROM ccc.clean_entities ce
  JOIN input i ON i.raw_q ILIKE '%' || ce.canonical_name || '%'
  WHERE char_length(ce.canonical_name) >= 2
    AND lower(ce.canonical_name) NOT IN (SELECT name FROM blocked_canonical)

  UNION ALL

  -- 4. 查询中包含 alias
  SELECT
    ce.canonical_name,
    ce.id AS entity_id,
    'alias_contained_in_query'::text AS match_type,
    0.90::double precision AS confidence,
    ce.entity_type
  FROM ccc.person_aliases pa
  JOIN ccc.clean_entities ce
    ON lower(ce.canonical_name) = lower(pa.canonical)
  JOIN input i ON i.raw_q ILIKE '%' || pa.alias || '%'
  WHERE (
      pa.alias ~ '[一-龥]' AND char_length(pa.alias) >= 2
    )
    OR (
      pa.alias !~ '[一-龥]' AND char_length(pa.alias) >= 3
    )

  UNION ALL

  -- 5. canonical 模糊匹配：只作兜底
  SELECT
    ce.canonical_name,
    ce.id AS entity_id,
    'entity_fuzzy'::text AS match_type,
    public.similarity(lower(ce.canonical_name), i.q_norm)::double precision AS confidence,
    ce.entity_type
  FROM ccc.clean_entities ce
  CROSS JOIN input i
  WHERE public.similarity(lower(ce.canonical_name), i.q_norm) > 0.55
    AND lower(ce.canonical_name) NOT IN (SELECT name FROM blocked_canonical)

  UNION ALL

  -- 6. alias 模糊匹配：只作兜底
  SELECT
    ce.canonical_name,
    ce.id AS entity_id,
    'alias_fuzzy'::text AS match_type,
    public.similarity(lower(pa.alias), i.q_norm)::double precision AS confidence,
    ce.entity_type
  FROM ccc.person_aliases pa
  JOIN ccc.clean_entities ce
    ON lower(ce.canonical_name) = lower(pa.canonical)
  CROSS JOIN input i
  WHERE (
      (pa.alias ~ '[一-龥]' AND char_length(pa.alias) >= 2)
      OR
      (pa.alias !~ '[一-龥]' AND char_length(pa.alias) >= 3)
    )
    AND public.similarity(lower(pa.alias), i.q_norm) > 0.55
),

dedup AS (
  SELECT
    *,
    row_number() OVER (
      PARTITION BY canonical_name, entity_id
      ORDER BY
        CASE match_type
          WHEN 'entity_exact' THEN 1
          WHEN 'alias_exact' THEN 2
          WHEN 'entity_contained_in_query' THEN 3
          WHEN 'alias_contained_in_query' THEN 4
          WHEN 'entity_fuzzy' THEN 5
          WHEN 'alias_fuzzy' THEN 6
          ELSE 9
        END,
        confidence DESC
    ) AS rn
  FROM candidates
),

strong_hit AS (
  SELECT EXISTS (
    SELECT 1
    FROM dedup
    WHERE rn = 1
      AND match_type IN (
        'entity_exact',
        'alias_exact',
        'entity_contained_in_query',
        'alias_contained_in_query'
      )
  ) AS has_strong
),

filtered AS (
  SELECT d.*
  FROM dedup d
  CROSS JOIN strong_hit sh
  WHERE d.rn = 1
    AND (
      -- 有强命中时，压掉 fuzzy
      (
        sh.has_strong = true
        AND d.match_type IN (
          'entity_exact',
          'alias_exact',
          'entity_contained_in_query',
          'alias_contained_in_query'
        )
      )
      OR
      -- 没有强命中时，允许 fuzzy 兜底
      (
        sh.has_strong = false
        AND d.match_type IN ('entity_fuzzy', 'alias_fuzzy')
        AND d.confidence >= 0.55
      )
    )
)

SELECT
  canonical_name,
  entity_id,
  match_type,
  confidence,
  entity_type
FROM filtered
ORDER BY confidence DESC, canonical_name
LIMIT 10;
$$;


ALTER FUNCTION ccc.entity_resolve_v3_local(q text) OWNER TO postgres;

--
-- Name: FUNCTION entity_resolve_v3_local(q text); Type: COMMENT; Schema: ccc; Owner: postgres
--

COMMENT ON FUNCTION ccc.entity_resolve_v3_local(q text) IS 'Search Router v3 Local stable entity resolver. Multilingual aliases supported. RSAL rule: China/PRC/Chinese government/Beijing/State Council route to canonical 中共. Xi/Trump/Fed/WEF aliases verified. Bill Gates remains separate PERSON and links to WEF through graph edge. Exact/contained hits suppress fuzzy noise. Regression PASS=53.';


--
-- Name: extract_event_date_from_text(text); Type: FUNCTION; Schema: ccc; Owner: postgres
--

CREATE FUNCTION ccc.extract_event_date_from_text(input_text text) RETURNS date
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    m TEXT[];
BEGIN
    m := regexp_match(
        coalesce(input_text, ''),
        '([12][0-9]{3})[-/.]([01]?[0-9])[-/.]([0-3]?[0-9])'
    );
    IF m IS NOT NULL THEN
        RETURN ccc.safe_iso_date(m[1]::int, m[2]::int, m[3]::int);
    END IF;

    m := regexp_match(
        coalesce(input_text, ''),
        '([12][0-9]{3})[年]([01]?[0-9])[月]([0-3]?[0-9])[日号]'
    );
    IF m IS NOT NULL THEN
        RETURN ccc.safe_iso_date(m[1]::int, m[2]::int, m[3]::int);
    END IF;

    m := regexp_match(
        coalesce(input_text, ''),
        '([12][0-9]{3})[年\s]'
    );
    IF m IS NOT NULL THEN
        RETURN ccc.safe_iso_date(m[1]::int, 1, 1);
    END IF;

    RETURN NULL;
END;
$$;


ALTER FUNCTION ccc.extract_event_date_from_text(input_text text) OWNER TO postgres;

--
-- Name: extract_impact_from_text(text); Type: FUNCTION; Schema: ccc; Owner: postgres
--

CREATE FUNCTION ccc.extract_impact_from_text(input_text text) RETURNS text
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    m TEXT[];
BEGIN
    m := regexp_match(
        coalesce(input_text, ''),
        '(?:被捕|逮捕|起诉|判决|驱逐|制裁|封锁|镇压|逃离|失踪|死亡|暗杀'
        '|arrested|detained|charged|sentenced|expelled|sanctioned'
        '|fled|disappeared|killed|assassinated|released|acquitted)'
        '[^，。,.\n\r]{0,80}'
    );
    IF m IS NOT NULL THEN
        RETURN trim(m[0]);
    END IF;

    RETURN substring(coalesce(input_text, '') FROM 1 FOR 160);
END;
$$;


ALTER FUNCTION ccc.extract_impact_from_text(input_text text) OWNER TO postgres;

--
-- Name: extract_location_from_text(text); Type: FUNCTION; Schema: ccc; Owner: postgres
--

CREATE FUNCTION ccc.extract_location_from_text(input_text text) RETURNS text
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    m TEXT[];
BEGIN
    m := regexp_match(
        coalesce(input_text, ''),
        '(?:在|于|位于|前往|抵达|离开|访问|到达)\s*([^\s，。,.\n\r]{2,20})'
    );
    IF m IS NOT NULL THEN
        RETURN trim(m[1]);
    END IF;

    m := regexp_match(
        coalesce(input_text, ''),
        '(北京|上海|香港|台北|台湾|新加坡|曼谷|金边|华盛顿|纽约|伦敦|东京|首尔'
        '|Beijing|Shanghai|Hong Kong|Taipei|Taiwan|Singapore|Bangkok'
        '|Phnom Penh|Cambodia|Thailand|Washington|New York|London|Tokyo'
        '|Geneva|Brussels|Paris|Sydney|Canberra|Ottawa|Vienna)'
    );
    IF m IS NOT NULL THEN
        RETURN trim(m[1]);
    END IF;

    RETURN NULL;
END;
$$;


ALTER FUNCTION ccc.extract_location_from_text(input_text text) OWNER TO postgres;

--
-- Name: forecast_confidence_gate_v1(double precision, double precision, double precision); Type: FUNCTION; Schema: ccc; Owner: postgres
--

CREATE FUNCTION ccc.forecast_confidence_gate_v1(p_resonance double precision, p_friction double precision, p_neutral double precision) RETURNS jsonb
    LANGUAGE plpgsql IMMUTABLE
    AS $$
DECLARE
  v_resonance double precision := GREATEST(0.0, COALESCE(p_resonance, 0.0));
  v_friction  double precision := GREATEST(0.0, COALESCE(p_friction, 0.0));
  v_neutral   double precision := GREATEST(0.0, COALESCE(p_neutral, 0.0));

  v_total_force double precision := 0.0;
  v_evidence_score double precision := 0.0;
  v_direction_balance double precision := 0.0;
  v_confidence double precision := 0.50;
BEGIN
  v_total_force := v_resonance + v_friction + v_neutral;

  IF v_total_force <= 0 THEN
    v_evidence_score := 0.0;
    v_direction_balance := 0.0;
    v_confidence := 0.50;
  ELSE
    -- 证据量门控：total_force >= 1.0 视为证据量充足
    v_evidence_score := LEAST(1.0, v_total_force / 1.0);

    -- 方向平衡：
    -- resonance 推高 A 面置信
    -- friction 压低 A 面置信
    -- neutral 只轻微扣分，避免中性噪音过度惩罚
    v_direction_balance :=
      (v_resonance - v_friction - v_neutral * 0.20) / v_total_force;

    v_confidence := LEAST(0.95, GREATEST(0.30,
      0.50 + v_direction_balance * v_evidence_score * 0.35
    ));
  END IF;

  RETURN jsonb_build_object(
    'confidence',        round(v_confidence::numeric, 4),
    'total_force',       round(v_total_force::numeric, 4),
    'evidence_score',    round(v_evidence_score::numeric, 4),
    'direction_balance', round(v_direction_balance::numeric, 4),
    'model',             'confidence_evidence_gate_v1',
    'formula',           '0.50 + direction_balance * evidence_score * 0.35'
  );
END;
$$;


ALTER FUNCTION ccc.forecast_confidence_gate_v1(p_resonance double precision, p_friction double precision, p_neutral double precision) OWNER TO postgres;

--
-- Name: FUNCTION forecast_confidence_gate_v1(p_resonance double precision, p_friction double precision, p_neutral double precision); Type: COMMENT; Schema: ccc; Owner: postgres
--

COMMENT ON FUNCTION ccc.forecast_confidence_gate_v1(p_resonance double precision, p_friction double precision, p_neutral double precision) IS 'RSAL P7.3d confidence gate: direction balance multiplied by evidence strength.';


--
-- Name: forecast_v1(text); Type: FUNCTION; Schema: ccc; Owner: postgres
--

CREATE FUNCTION ccc.forecast_v1(p_entity_name text) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
  v_profile jsonb := '{}'::jsonb;
  v_trajectory jsonb := '{}'::jsonb;
  v_signals jsonb := '[]'::jsonb;
  v_contradictions jsonb := '[]'::jsonb;
  v_behaviors jsonb := '[]'::jsonb;
  v_timeline jsonb := '[]'::jsonb;

  v_entity_id bigint;
  v_profile_id bigint;

  v_pressure float := 0.5;
  v_trend text := 'stable';
  v_forecast_a text := '强化现有路线';
  v_forecast_b text := '路线调整';
  v_prob_a float := 0.55;
  v_prob_b float := 0.45;
BEGIN
  SELECT ep.id, ep.entity_id,
         jsonb_build_object(
           'essence', ep.essence,
           'survival_mode', ep.survival_mode,
           'mirror_bias', ep.mirror_bias,
           'core_drives', ep.core_drives,
           'behavior_pattern', ep.behavior_pattern,
           'confidence', ep.confidence
         )
  INTO v_profile_id, v_entity_id, v_profile
  FROM ccc.entity_profiles ep
  WHERE lower(ep.entity_name) = lower(p_entity_name)
  LIMIT 1;

  IF v_profile_id IS NULL THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'entity profile not found',
      'entity', p_entity_name
    );
  END IF;

  SELECT jsonb_build_object(
           'pressure', et.pressure,
           'pressure_trend', et.pressure_trend,
           'trajectory_status', et.trajectory_status,
           'risk_level', et.risk_level,
           'key_drivers', et.key_drivers,
           'supporting_signals', et.supporting_signals,
           'next_possible_events', et.next_possible_events,
           'prediction', et.short_term_prediction,
           'confidence', et.confidence
         )
  INTO v_trajectory
  FROM ccc.entity_trajectories et
  WHERE et.entity_profile_id = v_profile_id
  ORDER BY et.snapshot_date DESC
  LIMIT 1;

  v_pressure := COALESCE((v_trajectory->>'pressure')::float, 0.5);
  v_trend := COALESCE(v_trajectory->>'pressure_trend', 'stable');

  SELECT COALESCE(jsonb_agg(x.obj ORDER BY x.strength DESC), '[]'::jsonb)
  INTO v_signals
  FROM (
    SELECT
      s.strength,
      jsonb_build_object(
        'type', s.signal_type,
        'text', s.signal_text,
        'strength', s.strength,
        'trigger_condition', s.trigger_condition,
        'linked_prediction', s.linked_prediction,
        'source', s.source_label
      ) AS obj
    FROM ccc.signals s
    WHERE s.entity_profile_id = v_profile_id
      AND s.is_active = true
    ORDER BY s.strength DESC
    LIMIT 5
  ) x;

  SELECT COALESCE(jsonb_agg(x.obj ORDER BY x.gap DESC), '[]'::jsonb)
  INTO v_contradictions
  FROM (
    SELECT
      ce.narrative_gap AS gap,
      jsonb_build_object(
        'official', ce.official_narrative,
        'counter_signals', ce.counter_signals,
        'real_indicators', ce.real_indicators,
        'gap', ce.narrative_gap,
        'severity', ce.severity,
        'confidence_decay', ce.confidence_decay,
        'source_labels', ce.source_labels,
        'trust_levels', ce.trust_levels
      ) AS obj
    FROM ccc.contradiction_engine ce
    WHERE ce.entity_id = v_entity_id
      AND ce.is_active = true
    ORDER BY ce.narrative_gap DESC
    LIMIT 5
  ) x;

  SELECT COALESCE(jsonb_agg(x.obj ORDER BY x.confidence DESC), '[]'::jsonb)
  INTO v_behaviors
  FROM (
    SELECT
      bm.confidence,
      jsonb_build_object(
        'prediction', bm.predicted_action,
        'type', bm.action_type,
        'confidence', bm.confidence,
        'historical_accuracy', bm.historical_accuracy,
        'horizon', bm.time_horizon,
        'triggers', bm.trigger_conditions,
        'counter_signals', bm.counter_signals
      ) AS obj
    FROM ccc.behavioral_models bm
    WHERE bm.entity_profile_id = v_profile_id
    ORDER BY bm.confidence DESC
    LIMIT 3
  ) x;

  SELECT COALESCE(jsonb_agg(x.obj ORDER BY x.event_time), '[]'::jsonb)
  INTO v_timeline
  FROM (
    SELECT
      en.event_time,
      jsonb_build_object(
        'time', en.event_time,
        'sequence_order', en.sequence_order,
        'essence', en.essence,
        'mechanism', en.mechanism,
        'pressure', en.pressure,
        'signal_strength', en.signal_strength,
        'causal_weight', en.causal_weight,
        'escalation_score', en.escalation_score
      ) AS obj
    FROM ccc.event_nodes en
    JOIN ccc.event_chains ec ON ec.id = en.chain_id
    WHERE ec.entity_id = v_entity_id
    ORDER BY en.event_time DESC
    LIMIT 5
  ) x;

  v_prob_a := CASE
    WHEN v_pressure >= 0.8 AND v_trend = 'rising' THEN 0.78
    WHEN v_pressure >= 0.7 AND v_trend = 'rising' THEN 0.68
    WHEN v_pressure >= 0.6 AND v_trend = 'stable' THEN 0.58
    WHEN v_pressure >= 0.5 AND v_trend = 'declining' THEN 0.45
    ELSE 0.55
  END;

  v_prob_b := 1.0 - v_prob_a;

  v_forecast_a := CASE v_profile->>'survival_mode'
    WHEN '权力集中化' THEN '控制强化'
    WHEN '地缘安全扩张' THEN '军事行动升级'
    WHEN '交易利益最大化' THEN '单边交易强化'
    WHEN '政权延续' THEN '维稳优先'
    WHEN '流动性管理' THEN '流动性干预'
    WHEN '议程设定' THEN '治理框架推进'
    ELSE '强化现有路线'
  END;

  v_forecast_b := CASE v_profile->>'survival_mode'
    WHEN '权力集中化' THEN '经济开放'
    WHEN '地缘安全扩张' THEN '外交谈判'
    WHEN '交易利益最大化' THEN '多边合作'
    WHEN '政权延续' THEN '经济改革'
    WHEN '流动性管理' THEN '货币收紧'
    WHEN '议程设定' THEN '主权让步'
    ELSE '路线调整'
  END;

  RETURN jsonb_build_object(
    'ok', true,
    'entity', p_entity_name,
    'generated_at', now(),

    'decision', CASE
      WHEN v_prob_a >= v_prob_b THEN 'A'
      ELSE 'B'
    END,

    'panel_1_pressure', jsonb_build_object(
      'pressure_level', v_pressure,
      'trend', v_trend,
      'risk_level', v_trajectory->>'risk_level',
      'dominant_mode', v_profile->>'survival_mode',
      'essence', v_profile->>'essence',
      'key_drivers', v_trajectory->'key_drivers',
      'mirror_bias', v_profile->>'mirror_bias'
    ),

    'panel_2_timeline', jsonb_build_object(
      'nodes', v_timeline,
      'active_signals', v_signals,
      'contradictions', v_contradictions
    ),

    'panel_3_forecast', jsonb_build_object(
      'horizon_months', COALESCE((v_trajectory->>'prediction_horizon')::int, 12),
      'option_a', v_forecast_a,
      'prob_a', round(v_prob_a::numeric, 2),
      'option_b', v_forecast_b,
      'prob_b', round(v_prob_b::numeric, 2),
      'top_behaviors', v_behaviors,
      'prediction_text', v_trajectory->>'prediction'
    )
  );
END;
$$;


ALTER FUNCTION ccc.forecast_v1(p_entity_name text) OWNER TO postgres;

--
-- Name: forecast_v1_1(text); Type: FUNCTION; Schema: ccc; Owner: postgres
--

CREATE FUNCTION ccc.forecast_v1_1(p_entity_name text) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
  v_base jsonb;
  v_gate jsonb;

  v_resonance double precision := 0.0;
  v_friction  double precision := 0.0;
  v_neutral   double precision := 0.0;

  v_confidence numeric := 0.50;
  v_evidence_score numeric := 0.0;
  v_direction_balance numeric := 0.0;
  v_total_force numeric := 0.0;
BEGIN
  -- 调用原始核心函数
  v_base := ccc.forecast_v1_1_core(p_entity_name);

  -- 如果实体不存在，原样返回
  IF COALESCE((v_base->>'ok')::boolean, false) IS NOT TRUE THEN
    RETURN v_base;
  END IF;

  -- 读取核心函数已经算好的三类应力
  v_resonance := COALESCE((v_base #>> '{panel_4_signal_alignment,resonance_score}')::double precision, 0.0);
  v_friction  := COALESCE((v_base #>> '{panel_4_signal_alignment,friction_score}')::double precision, 0.0);
  v_neutral   := COALESCE((v_base #>> '{panel_4_signal_alignment,neutral_score}')::double precision, 0.0);

  -- 新置信度门控
  v_gate := ccc.forecast_confidence_gate_v1(v_resonance, v_friction, v_neutral);

  v_confidence        := (v_gate->>'confidence')::numeric;
  v_evidence_score    := (v_gate->>'evidence_score')::numeric;
  v_direction_balance := (v_gate->>'direction_balance')::numeric;
  v_total_force       := (v_gate->>'total_force')::numeric;

  -- 标记版本
  v_base := jsonb_set(
    v_base,
    '{version}',
    to_jsonb('forecast_v1.1-confidence_gate'::text),
    true
  );

  -- 写回 panel_3_forecast.confidence
  v_base := jsonb_set(
    v_base,
    '{panel_3_forecast,confidence}',
    to_jsonb(round(v_confidence, 2)),
    true
  );

  -- 写回 panel_4_signal_alignment.confidence
  v_base := jsonb_set(
    v_base,
    '{panel_4_signal_alignment,confidence}',
    to_jsonb(round(v_confidence, 2)),
    true
  );

  -- 增加证据量解释字段
  v_base := jsonb_set(
    v_base,
    '{panel_4_signal_alignment,total_force}',
    to_jsonb(round(v_total_force, 4)),
    true
  );

  v_base := jsonb_set(
    v_base,
    '{panel_4_signal_alignment,evidence_score}',
    to_jsonb(round(v_evidence_score, 4)),
    true
  );

  v_base := jsonb_set(
    v_base,
    '{panel_4_signal_alignment,direction_balance}',
    to_jsonb(round(v_direction_balance, 4)),
    true
  );

  v_base := jsonb_set(
    v_base,
    '{panel_4_signal_alignment,confidence_model}',
    to_jsonb('confidence_evidence_gate_v1'::text),
    true
  );

  RETURN v_base;
END;
$$;


ALTER FUNCTION ccc.forecast_v1_1(p_entity_name text) OWNER TO postgres;

--
-- Name: FUNCTION forecast_v1_1(p_entity_name text); Type: COMMENT; Schema: ccc; Owner: postgres
--

COMMENT ON FUNCTION ccc.forecast_v1_1(p_entity_name text) IS 'RSAL P7.3d stable wrapper: calls forecast_v1_1_core and applies confidence evidence gate. Fixed checkpoint: P7.3d_forecast_v1_1_confidence_gate_stable.';


--
-- Name: forecast_v1_1_core(text); Type: FUNCTION; Schema: ccc; Owner: postgres
--

CREATE FUNCTION ccc.forecast_v1_1_core(p_entity_name text) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
  v_keywords_a text[] := ARRAY[
    '监管','打压','审查','维稳','资本管制','收紧','收缩','清洗','反腐','国家安全','外部势力','军事演习','统一','制裁','管控','严打','斗争',
    '監管','打壓','審查','維穩','資本管制','收緊','收縮','清洗','反腐','國家安全','外部勢力','軍事演習','統一','制裁','管控','嚴打','鬥爭',
    'crackdown','tightening','control','regulation','censorship','security','purge','anti-corruption','military drill','sanction','national security','containment',
    '規制','弾圧','検閲','統制','安全保障','粛清','反腐敗','軍事演習','制裁','管理強化','台湾有事','対中強硬',
    'jianguan','daji','shencha','weiwen','shoujin','shousuo','qingxi','fanfu','guankong','guoan','junshiyanxi','zhicai'
  ];

  v_keywords_b text[] := ARRAY[
    '开放','放宽','改革','市场化','民营','松绑','宽松','刺激','减税','外资','营商环境','合作','谈判','缓和',
    '開放','放寬','改革','市場化','民營','鬆綁','寬鬆','刺激','減稅','外資','營商環境','合作','談判','緩和',
    'opening','liberalization','reform','marketization','private sector','easing','stimulus','tax cut','foreign investment','cooperation','negotiation','de-escalation',
    '開放','緩和','改革','自由化','市場化','民営化','金融緩和','刺激策','減税','外資誘致','協力','交渉','対話','関係改善',
    'kaifang','fangkuan','gaige','shichanghua','minying','songbang','kuansong','ciji','jianshui','waizi','hezuo','tanpan','huanhe'
  ];

  v_profile jsonb := '{}'::jsonb;
  v_trajectory jsonb := '{}'::jsonb;
  v_signals jsonb := '[]'::jsonb;
  v_contradictions jsonb := '[]'::jsonb;
  v_behaviors jsonb := '[]'::jsonb;
  v_timeline jsonb := '[]'::jsonb;
  v_alignment jsonb := '[]'::jsonb;

  v_entity_id bigint;
  v_profile_id bigint;
  v_route_profile text := 'neutral_agent';

  v_pressure float := 0.5;
  v_trend text := 'stable';
  v_forecast_a text := '强化现有路线';
  v_forecast_b text := '路线调整';
  v_prob_a float := 0.55;
  v_prob_b float := 0.45;

  v_resonance float := 0;
  v_friction float := 0;
  v_neutral float := 0;
  v_total_force float := 0;
  v_confidence float := 0.5;
BEGIN
  SELECT ep.id, ep.entity_id,
         jsonb_build_object(
           'essence', ep.essence,
           'survival_mode', ep.survival_mode,
           'mirror_bias', ep.mirror_bias,
           'core_drives', ep.core_drives,
           'behavior_pattern', ep.behavior_pattern,
           'confidence', ep.confidence
         )
  INTO v_profile_id, v_entity_id, v_profile
  FROM ccc.entity_profiles ep
  WHERE lower(ep.entity_name) = lower(p_entity_name)
  LIMIT 1;

  IF v_profile_id IS NULL THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'entity profile not found',
      'entity', p_entity_name
    );
  END IF;

  SELECT jsonb_build_object(
           'pressure', et.pressure,
           'pressure_trend', et.pressure_trend,
           'trajectory_status', et.trajectory_status,
           'risk_level', et.risk_level,
           'key_drivers', et.key_drivers,
           'supporting_signals', et.supporting_signals,
           'next_possible_events', et.next_possible_events,
           'prediction', et.short_term_prediction,
           'prediction_horizon', et.prediction_horizon,
           'confidence', et.confidence
         )
  INTO v_trajectory
  FROM ccc.entity_trajectories et
  WHERE et.entity_profile_id = v_profile_id
  ORDER BY et.snapshot_date DESC
  LIMIT 1;

  v_pressure := COALESCE((v_trajectory->>'pressure')::float, 0.5);
  v_trend := COALESCE(v_trajectory->>'pressure_trend', 'stable');

  -- P7.3b route_profile mapping
  v_route_profile := CASE
    WHEN v_profile->>'survival_mode' IN ('权力集中化', '政权延续', '地缘安全扩张')
      THEN 'authoritarian'
    WHEN v_profile->>'survival_mode' IN ('交易利益最大化', '重新定价与秩序解构')
      THEN 'transactional'
    WHEN v_profile->>'survival_mode' IN ('流动性管理', '美元体系稳定管理')
      THEN 'financial'
    WHEN v_profile->>'survival_mode' IN ('议程设定', '精英治理议程设定')
      THEN 'governance'
    ELSE 'neutral_agent'
  END;

  SELECT COALESCE(jsonb_agg(x.obj ORDER BY x.strength DESC), '[]'::jsonb)
  INTO v_signals
  FROM (
    SELECT
      s.strength,
      jsonb_build_object(
        'type', s.signal_type,
        'text', s.signal_text,
        'strength', s.strength,
        'trigger_condition', s.trigger_condition,
        'linked_prediction', s.linked_prediction,
        'source', s.source_label
      ) AS obj
    FROM ccc.signals s
    WHERE s.entity_profile_id = v_profile_id
      AND s.is_active = true
    ORDER BY s.strength DESC
    LIMIT 5
  ) x;

  SELECT COALESCE(jsonb_agg(x.obj ORDER BY x.gap DESC), '[]'::jsonb)
  INTO v_contradictions
  FROM (
    SELECT
      ce.narrative_gap AS gap,
      jsonb_build_object(
        'official', ce.official_narrative,
        'counter_signals', ce.counter_signals,
        'real_indicators', ce.real_indicators,
        'gap', ce.narrative_gap,
        'severity', ce.severity,
        'confidence_decay', ce.confidence_decay,
        'source_labels', ce.source_labels,
        'trust_levels', ce.trust_levels
      ) AS obj
    FROM ccc.contradiction_engine ce
    WHERE ce.entity_id = v_entity_id
      AND ce.is_active = true
    ORDER BY ce.narrative_gap DESC
    LIMIT 5
  ) x;

  SELECT COALESCE(jsonb_agg(x.obj ORDER BY x.confidence DESC), '[]'::jsonb)
  INTO v_behaviors
  FROM (
    SELECT
      bm.confidence,
      jsonb_build_object(
        'prediction', bm.predicted_action,
        'type', bm.action_type,
        'confidence', bm.confidence,
        'historical_accuracy', bm.historical_accuracy,
        'horizon', bm.time_horizon,
        'triggers', bm.trigger_conditions,
        'counter_signals', bm.counter_signals
      ) AS obj
    FROM ccc.behavioral_models bm
    WHERE bm.entity_profile_id = v_profile_id
    ORDER BY bm.confidence DESC
    LIMIT 3
  ) x;

  SELECT COALESCE(jsonb_agg(x.obj ORDER BY x.event_time), '[]'::jsonb)
  INTO v_timeline
  FROM (
    SELECT
      en.event_time,
      jsonb_build_object(
        'time', en.event_time,
        'sequence_order', en.sequence_order,
        'essence', en.essence,
        'mechanism', en.mechanism,
        'pressure', en.pressure,
        'signal_strength', en.signal_strength,
        'causal_weight', en.causal_weight,
        'escalation_score', en.escalation_score
      ) AS obj
    FROM ccc.event_nodes en
    JOIN ccc.event_chains ec ON ec.id = en.chain_id
    WHERE ec.entity_id = v_entity_id
    ORDER BY en.event_time DESC
    LIMIT 5
  ) x;

  v_prob_a := CASE
    WHEN v_pressure >= 0.8 AND v_trend = 'rising' THEN 0.78
    WHEN v_pressure >= 0.7 AND v_trend = 'rising' THEN 0.68
    WHEN v_pressure >= 0.6 AND v_trend = 'stable' THEN 0.58
    WHEN v_pressure >= 0.5 AND v_trend = 'declining' THEN 0.45
    ELSE 0.55
  END;

  v_prob_b := 1.0 - v_prob_a;

  -- P7.3b option A
  v_forecast_a := CASE v_profile->>'survival_mode'
    WHEN '权力集中化' THEN '权力绝对集中'
    WHEN '地缘安全扩张' THEN '军事行动升级'
    WHEN '交易利益最大化' THEN '单边交易强化'
    WHEN '重新定价与秩序解构' THEN '破坏性极限施压'
    WHEN '政权延续' THEN '刚性社会维稳'
    WHEN '流动性管理' THEN '流动性干预'
    WHEN '美元体系稳定管理' THEN '流动性救市'
    WHEN '议程设定' THEN '治理框架推进'
    WHEN '精英治理议程设定' THEN '全球协调增强 / 精英治理深化'
    ELSE '强化现有路线'
  END;

  -- P7.3b option B
  v_forecast_b := CASE v_profile->>'survival_mode'
    WHEN '权力集中化' THEN '战术性防御退让'
    WHEN '地缘安全扩张' THEN '战略收缩 / 外交谈判'
    WHEN '交易利益最大化' THEN '多边合作'
    WHEN '重新定价与秩序解构' THEN '协议达成与筹码套现'
    WHEN '政权延续' THEN '市场化自救放权'
    WHEN '流动性管理' THEN '货币收紧'
    WHEN '美元体系稳定管理' THEN '纪律性紧缩'
    WHEN '议程设定' THEN '主权让步'
    WHEN '精英治理议程设定' THEN '国家主权反弹 / 逆全球化加深'
    ELSE '路线调整'
  END;

  WITH contradiction_force AS (
    SELECT
      ce.id,
      ce.official_narrative,
      array_to_string(ce.counter_signals, ' ') AS counter_text,
      array_to_string(ce.real_indicators, ' ') AS real_text,
      ce.narrative_gap,
      ce.source_labels,
      ce.trust_levels,

      EXISTS (
        SELECT 1 FROM unnest(v_keywords_a) kw
        WHERE array_to_string(ce.counter_signals, ' ') ILIKE '%' || kw || '%'
           OR array_to_string(ce.real_indicators, ' ') ILIKE '%' || kw || '%'
      ) AS hard_hit_a,

      EXISTS (
        SELECT 1 FROM unnest(v_keywords_b) kw
        WHERE array_to_string(ce.counter_signals, ' ') ILIKE '%' || kw || '%'
           OR array_to_string(ce.real_indicators, ' ') ILIKE '%' || kw || '%'
      ) AS hard_hit_b,

      EXISTS (
        SELECT 1 FROM unnest(v_keywords_a) kw
        WHERE ce.official_narrative ILIKE '%' || kw || '%'
      ) AS official_hit_a,

      EXISTS (
        SELECT 1 FROM unnest(v_keywords_b) kw
        WHERE ce.official_narrative ILIKE '%' || kw || '%'
      ) AS official_hit_b,

      EXISTS (
        SELECT 1 FROM unnest(ce.trust_levels) tl
        WHERE tl = 'T6'
      ) AS has_t6,

      (
        SELECT AVG(
          COALESCE(
            (
              ccc.source_effective_weight(sl.label::text, NULL::text, NULL::text)
              ->'weights'->>'reverse_indicator_weight'
            )::double precision,
            CASE
              WHEN sl.trust_level = 'T6' THEN 0.65
              WHEN sl.trust_level = 'T3' THEN 0.70
              WHEN sl.trust_level = 'T2' THEN 0.60
              ELSE 0.55
            END
          )
          *
          CASE WHEN sl.trust_level = 'T6' THEN 1.10 ELSE 1.00 END
        )
        FROM (
          SELECT
            labels.label,
            COALESCE(levels.trust_level, 'UNK') AS trust_level
          FROM unnest(ce.source_labels) WITH ORDINALITY labels(label, ord)
          LEFT JOIN unnest(ce.trust_levels) WITH ORDINALITY levels(trust_level, ord)
            ON labels.ord = levels.ord
        ) sl
      ) AS p6_weight

    FROM ccc.contradiction_engine ce
    WHERE ce.entity_id = v_entity_id
      AND ce.is_active = true
  ),
  routed AS (
    SELECT
      *,
      CASE
        -- Authoritarian
        WHEN v_route_profile = 'authoritarian'
         AND has_t6
         AND (
           official_narrative ILIKE '%透明通报%'
           OR official_narrative ILIKE '%自然界%'
           OR official_narrative ILIKE '%源于自然%'
           OR official_narrative ILIKE '%开放包容%'
           OR official_narrative ILIKE '%合作共赢%'
           OR official_narrative ILIKE '%和平解决%'
           OR official_narrative ILIKE '%无意动武%'
           OR official_narrative ILIKE '%自由贸易%'
           OR official_narrative ILIKE '%自由贸易秩序%'
           OR official_narrative ILIKE '%重要力量%'
           OR official_narrative ILIKE '%保持稳定%'
           OR official_narrative ILIKE '%稳定复苏%'
           OR official_narrative ILIKE '%改革开放%'
           OR official_narrative ILIKE '%持续深化%'
         )
          THEN 'A'

        WHEN v_route_profile = 'authoritarian'
         AND (
           counter_text ILIKE '%军事演习%' OR real_text ILIKE '%军事演习%'
           OR counter_text ILIKE '%统一时间表%' OR real_text ILIKE '%统一时间表%'
           OR counter_text ILIKE '%样本销毁%' OR real_text ILIKE '%样本销毁%'
           OR counter_text ILIKE '%调查受限%' OR real_text ILIKE '%调查受限%'
           OR counter_text ILIKE '%预警压制%' OR real_text ILIKE '%预警压制%'
           OR counter_text ILIKE '%出口限制%' OR real_text ILIKE '%出口限制%'
           OR counter_text ILIKE '%供应链切断%' OR real_text ILIKE '%供应链切断%'
           OR counter_text ILIKE '%贸易武器化%' OR real_text ILIKE '%贸易武器化%'
           OR counter_text ILIKE '%技术脱钩%' OR real_text ILIKE '%技术脱钩%'
           OR counter_text ILIKE '%关键矿产%' OR real_text ILIKE '%关键矿产%'
           OR counter_text ILIKE '%债务陷阱%' OR real_text ILIKE '%债务陷阱%'
           OR counter_text ILIKE '%经济胁迫%' OR real_text ILIKE '%经济胁迫%'
         )
          THEN 'A'

        -- Governance
        WHEN v_route_profile = 'governance'
         AND (
           official_narrative ILIKE '%全球治理%'
           OR official_narrative ILIKE '%自由贸易%'
           OR official_narrative ILIKE '%服务全人类%'
           OR official_narrative ILIKE '%开放包容%'
           OR official_narrative ILIKE '%利益相关者%'
         )
          THEN 'B'

        -- Financial
        WHEN v_route_profile = 'financial'
         AND (
           real_text ILIKE '%政治施压%'
           OR counter_text ILIKE '%政治施压%'
           OR real_text ILIKE '%听证施压%'
           OR counter_text ILIKE '%听证施压%'
           OR real_text ILIKE '%任命政治化%'
           OR counter_text ILIKE '%任命政治化%'
           OR real_text ILIKE '%政治周期%'
           OR counter_text ILIKE '%政治周期%'
           OR real_text ILIKE '%MMT%'
           OR counter_text ILIKE '%MMT%'
           OR real_text ILIKE '%流动性锁死%'
           OR counter_text ILIKE '%流动性锁死%'
         )
          THEN 'A'

        WHEN v_route_profile = 'financial'
         AND (
           official_narrative ILIKE '%独立%'
           OR official_narrative ILIKE '%基于数据%'
           OR official_narrative ILIKE '%保持稳定%'
           OR official_narrative ILIKE '%符合预期%'
         )
          THEN 'NEUTRAL'

        -- Transactional
        WHEN v_route_profile = 'transactional'
         AND (
           counter_text ILIKE '%技术脱钩%' OR real_text ILIKE '%技术脱钩%'
           OR counter_text ILIKE '%加征关税%' OR real_text ILIKE '%加征关税%'
           OR counter_text ILIKE '%关税%' OR real_text ILIKE '%关税%'
           OR counter_text ILIKE '%极限施压%' OR real_text ILIKE '%极限施压%'
           OR counter_text ILIKE '%供应链重组%' OR real_text ILIKE '%供应链重组%'
           OR counter_text ILIKE '%单边%' OR real_text ILIKE '%单边%'
         )
          THEN 'A'

        WHEN v_route_profile = 'transactional'
         AND (
           official_narrative ILIKE '%极好的协议%'
           OR official_narrative ILIKE '%随时谈判%'
           OR official_narrative ILIKE '%目标有限%'
           OR official_narrative ILIKE '%可以谈判%'
         )
          THEN 'B'

        -- Global residual
        WHEN (
           counter_text ILIKE '%宣战%' OR real_text ILIKE '%宣战%'
           OR counter_text ILIKE '%全面制裁%' OR real_text ILIKE '%全面制裁%'
           OR counter_text ILIKE '%全面戒严%' OR real_text ILIKE '%全面戒严%'
           OR counter_text ILIKE '%切断代理行%' OR real_text ILIKE '%切断代理行%'
        )
          THEN 'A'

        ELSE 'NEUTRAL'
      END AS alignment,
      COALESCE(p6_weight, 0.55) * COALESCE(narrative_gap, 0.5) AS force_score
    FROM contradiction_force
  )
  SELECT
    COALESCE(SUM(CASE WHEN alignment = 'A' THEN force_score ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN alignment = 'B' THEN force_score ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN alignment = 'NEUTRAL' THEN force_score ELSE 0 END), 0),
    COALESCE(jsonb_agg(jsonb_build_object(
      'id', id,
      'alignment', alignment,
      'force_score', round(force_score::numeric, 4),
      'has_t6', has_t6,
      'hard_hit_a', hard_hit_a,
      'hard_hit_b', hard_hit_b,
      'official_hit_a', official_hit_a,
      'official_hit_b', official_hit_b,
      'p6_weight', round(COALESCE(p6_weight, 0.55)::numeric, 4),
      'narrative_gap', narrative_gap,
      'official_narrative', official_narrative
    ) ORDER BY force_score DESC), '[]'::jsonb)
  INTO v_resonance, v_friction, v_neutral, v_alignment
  FROM routed;

  v_total_force := v_resonance + v_friction + v_neutral;

  v_confidence := CASE
    WHEN v_total_force <= 0 THEN 0.50
    ELSE LEAST(0.95, GREATEST(0.30,
      0.50
      + (v_resonance / v_total_force) * 0.35
      - (v_friction / v_total_force) * 0.25
      - (v_neutral / v_total_force) * 0.05
    ))
  END;

  RETURN jsonb_build_object(
    'ok', true,
    'version', 'forecast_v1.1',
    'entity', p_entity_name,
    'route_profile', v_route_profile,
    'generated_at', now(),

    'decision', CASE
      WHEN v_prob_a >= v_prob_b THEN 'A'
      ELSE 'B'
    END,

    'panel_1_pressure', jsonb_build_object(
      'pressure_level', v_pressure,
      'trend', v_trend,
      'risk_level', v_trajectory->>'risk_level',
      'dominant_mode', v_profile->>'survival_mode',
      'essence', v_profile->>'essence',
      'key_drivers', v_trajectory->'key_drivers',
      'mirror_bias', v_profile->>'mirror_bias'
    ),

    'panel_2_timeline', jsonb_build_object(
      'nodes', v_timeline,
      'active_signals', v_signals,
      'contradictions', v_contradictions
    ),

    'panel_3_forecast', jsonb_build_object(
      'horizon_months', COALESCE((v_trajectory->>'prediction_horizon')::int, 12),
      'option_a', v_forecast_a,
      'prob_a', round(v_prob_a::numeric, 2),
      'option_b', v_forecast_b,
      'prob_b', round(v_prob_b::numeric, 2),
      'confidence', round(v_confidence::numeric, 2),
      'top_behaviors', v_behaviors,
      'prediction_text', v_trajectory->>'prediction'
    ),

    'panel_4_signal_alignment', jsonb_build_object(
      'model', 'resonance_friction_v1',
      'resonance_score', round(v_resonance::numeric, 4),
      'friction_score', round(v_friction::numeric, 4),
      'neutral_score', round(v_neutral::numeric, 4),
      'confidence', round(v_confidence::numeric, 2),
      'rules', jsonb_build_object(
        'probability', 'internal_behavior_model',
        'confidence', 'external_signal_resonance',
        't6_official_b', 'route_specific',
        't6_official_a', 'route_specific',
        'route_profile', v_route_profile
      ),
      'alignment_details', COALESCE(v_alignment, '[]'::jsonb)
    )
  );
END;
$$;


ALTER FUNCTION ccc.forecast_v1_1_core(p_entity_name text) OWNER TO postgres;

--
-- Name: FUNCTION forecast_v1_1_core(p_entity_name text); Type: COMMENT; Schema: ccc; Owner: postgres
--

COMMENT ON FUNCTION ccc.forecast_v1_1_core(p_entity_name text) IS 'RSAL P7.3c core forecast function: route-specific semantic alignment. Do not edit directly without snapshot.';


--
-- Name: forecast_v1_1_trust_v3(text); Type: FUNCTION; Schema: ccc; Owner: postgres
--

CREATE FUNCTION ccc.forecast_v1_1_trust_v3(p_entity_name text) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
  v_keywords_a text[] := ARRAY[
    '监管','打压','审查','维稳','资本管制','收紧','收缩','清洗','反腐','国家安全','外部势力','军事演习','统一','制裁','管控','严打','斗争',
    '監管','打壓','審查','維穩','資本管制','收緊','收縮','清洗','反腐','國家安全','外部勢力','軍事演習','統一','制裁','管控','嚴打','鬥爭',
    'crackdown','tightening','control','regulation','censorship','security','purge','anti-corruption','military drill','sanction','national security','containment',
    '規制','弾圧','検閲','統制','安全保障','粛清','反腐敗','軍事演習','制裁','管理強化','台湾有事','対中強硬',
    'jianguan','daji','shencha','weiwen','shoujin','shousuo','qingxi','fanfu','guankong','guoan','junshiyanxi','zhicai'
  ];

  v_keywords_b text[] := ARRAY[
    '开放','放宽','改革','市场化','民营','松绑','宽松','刺激','减税','外资','营商环境','合作','谈判','缓和',
    '開放','放寬','改革','市場化','民營','鬆綁','寬鬆','刺激','減稅','外資','營商環境','合作','談判','緩和',
    'opening','liberalization','reform','marketization','private sector','easing','stimulus','tax cut','foreign investment','cooperation','negotiation','de-escalation',
    '開放','緩和','改革','自由化','市場化','民営化','金融緩和','刺激策','減税','外資誘致','協力','交渉','対話','関係改善',
    'kaifang','fangkuan','gaige','shichanghua','minying','songbang','kuansong','ciji','jianshui','waizi','hezuo','tanpan','huanhe'
  ];

  v_profile      jsonb := '{}'::jsonb;
  v_trajectory   jsonb := '{}'::jsonb;
  v_signals      jsonb := '[]'::jsonb;
  v_contradictions jsonb := '[]'::jsonb;
  v_behaviors    jsonb := '[]'::jsonb;
  v_timeline     jsonb := '[]'::jsonb;
  v_alignment    jsonb := '[]'::jsonb;

  v_entity_id    bigint;
  v_profile_id   bigint;
  v_route_profile text := 'neutral_agent';

  v_pressure     float := 0.5;
  v_trend        text  := 'stable';
  v_forecast_a   text  := '强化现有路线';
  v_forecast_b   text  := '路线调整';
  v_prob_a       float := 0.55;
  v_prob_b       float := 0.45;

  v_resonance    float := 0;
  v_friction     float := 0;
  v_neutral      float := 0;
  v_total_force  float := 0;
  v_confidence   float := 0.5;

  -- confidence gate
  v_gate              jsonb;
  v_evidence_score    numeric := 0.0;
  v_direction_balance numeric := 0.0;
  v_total_force_gate  numeric := 0.0;

BEGIN
  -- ── 1. Entity profile ──────────────────────────────────────────
  SELECT ep.id, ep.entity_id,
         jsonb_build_object(
           'essence',          ep.essence,
           'survival_mode',    ep.survival_mode,
           'mirror_bias',      ep.mirror_bias,
           'core_drives',      ep.core_drives,
           'behavior_pattern', ep.behavior_pattern,
           'confidence',       ep.confidence
         )
  INTO v_profile_id, v_entity_id, v_profile
  FROM ccc.entity_profiles ep
  WHERE lower(ep.entity_name) = lower(p_entity_name)
  LIMIT 1;

  IF v_profile_id IS NULL THEN
    RETURN jsonb_build_object(
      'ok',     false,
      'error',  'entity profile not found',
      'entity', p_entity_name
    );
  END IF;

  -- ── 2. Trajectory ──────────────────────────────────────────────
  SELECT jsonb_build_object(
           'pressure',             et.pressure,
           'pressure_trend',       et.pressure_trend,
           'trajectory_status',    et.trajectory_status,
           'risk_level',           et.risk_level,
           'key_drivers',          et.key_drivers,
           'supporting_signals',   et.supporting_signals,
           'next_possible_events', et.next_possible_events,
           'prediction',           et.short_term_prediction,
           'prediction_horizon',   et.prediction_horizon,
           'confidence',           et.confidence
         )
  INTO v_trajectory
  FROM ccc.entity_trajectories et
  WHERE et.entity_profile_id = v_profile_id
  ORDER BY et.snapshot_date DESC
  LIMIT 1;

  v_pressure := COALESCE((v_trajectory->>'pressure')::float, 0.5);
  v_trend    := COALESCE(v_trajectory->>'pressure_trend', 'stable');

  -- ── 3. Route profile ───────────────────────────────────────────
  v_route_profile := CASE
    WHEN v_profile->>'survival_mode' IN ('权力集中化', '政权延续', '地缘安全扩张')
      THEN 'authoritarian'
    WHEN v_profile->>'survival_mode' IN ('交易利益最大化', '重新定价与秩序解构')
      THEN 'transactional'
    WHEN v_profile->>'survival_mode' IN ('流动性管理', '美元体系稳定管理')
      THEN 'financial'
    WHEN v_profile->>'survival_mode' IN ('议程设定', '精英治理议程设定')
      THEN 'governance'
    ELSE 'neutral_agent'
  END;

  -- ── 4. Signals ─────────────────────────────────────────────────
  SELECT COALESCE(jsonb_agg(x.obj ORDER BY x.strength DESC), '[]'::jsonb)
  INTO v_signals
  FROM (
    SELECT s.strength,
           jsonb_build_object(
             'type',              s.signal_type,
             'text',              s.signal_text,
             'strength',          s.strength,
             'trigger_condition', s.trigger_condition,
             'linked_prediction', s.linked_prediction,
             'source',            s.source_label
           ) AS obj
    FROM ccc.signals s
    WHERE s.entity_profile_id = v_profile_id
      AND s.is_active = true
    ORDER BY s.strength DESC
    LIMIT 5
  ) x;

  -- ── 5. Contradictions ──────────────────────────────────────────
  SELECT COALESCE(jsonb_agg(x.obj ORDER BY x.gap DESC), '[]'::jsonb)
  INTO v_contradictions
  FROM (
    SELECT ce.narrative_gap AS gap,
           jsonb_build_object(
             'official',         ce.official_narrative,
             'counter_signals',  ce.counter_signals,
             'real_indicators',  ce.real_indicators,
             'gap',              ce.narrative_gap,
             'severity',         ce.severity,
             'confidence_decay', ce.confidence_decay,
             'source_labels',    ce.source_labels,
             'trust_levels',     ce.trust_levels
           ) AS obj
    FROM ccc.contradiction_engine ce
    WHERE ce.entity_id = v_entity_id
      AND ce.is_active = true
    ORDER BY ce.narrative_gap DESC
    LIMIT 5
  ) x;

  -- ── 6. Behaviors ───────────────────────────────────────────────
  SELECT COALESCE(jsonb_agg(x.obj ORDER BY x.confidence DESC), '[]'::jsonb)
  INTO v_behaviors
  FROM (
    SELECT bm.confidence,
           jsonb_build_object(
             'prediction',        bm.predicted_action,
             'type',              bm.action_type,
             'confidence',        bm.confidence,
             'historical_accuracy', bm.historical_accuracy,
             'horizon',           bm.time_horizon,
             'triggers',          bm.trigger_conditions,
             'counter_signals',   bm.counter_signals
           ) AS obj
    FROM ccc.behavioral_models bm
    WHERE bm.entity_profile_id = v_profile_id
    ORDER BY bm.confidence DESC
    LIMIT 3
  ) x;

  -- ── 7. Timeline ────────────────────────────────────────────────
  SELECT COALESCE(jsonb_agg(x.obj ORDER BY x.event_time), '[]'::jsonb)
  INTO v_timeline
  FROM (
    SELECT en.event_time,
           jsonb_build_object(
             'time',             en.event_time,
             'sequence_order',   en.sequence_order,
             'essence',          en.essence,
             'mechanism',        en.mechanism,
             'pressure',         en.pressure,
             'signal_strength',  en.signal_strength,
             'causal_weight',    en.causal_weight,
             'escalation_score', en.escalation_score
           ) AS obj
    FROM ccc.event_nodes en
    JOIN ccc.event_chains ec ON ec.id = en.chain_id
    WHERE ec.entity_id = v_entity_id
    ORDER BY en.event_time DESC
    LIMIT 5
  ) x;

  -- ── 8. Probability ─────────────────────────────────────────────
  v_prob_a := CASE
    WHEN v_pressure >= 0.8 AND v_trend = 'rising'   THEN 0.78
    WHEN v_pressure >= 0.7 AND v_trend = 'rising'   THEN 0.68
    WHEN v_pressure >= 0.6 AND v_trend = 'stable'   THEN 0.58
    WHEN v_pressure >= 0.5 AND v_trend = 'declining' THEN 0.45
    ELSE 0.55
  END;
  v_prob_b := 1.0 - v_prob_a;

  -- ── 9. Forecast labels ─────────────────────────────────────────
  v_forecast_a := CASE v_profile->>'survival_mode'
    WHEN '权力集中化'        THEN '权力绝对集中'
    WHEN '地缘安全扩张'      THEN '军事行动升级'
    WHEN '交易利益最大化'    THEN '单边交易强化'
    WHEN '重新定价与秩序解构' THEN '破坏性极限施压'
    WHEN '政权延续'          THEN '刚性社会维稳'
    WHEN '流动性管理'        THEN '流动性干预'
    WHEN '美元体系稳定管理'  THEN '流动性救市'
    WHEN '议程设定'          THEN '治理框架推进'
    WHEN '精英治理议程设定'  THEN '全球协调增强 / 精英治理深化'
    ELSE '强化现有路线'
  END;

  v_forecast_b := CASE v_profile->>'survival_mode'
    WHEN '权力集中化'        THEN '战术性防御退让'
    WHEN '地缘安全扩张'      THEN '战略收缩 / 外交谈判'
    WHEN '交易利益最大化'    THEN '多边合作'
    WHEN '重新定价与秩序解构' THEN '协议达成与筹码套现'
    WHEN '政权延续'          THEN '市场化自救放权'
    WHEN '流动性管理'        THEN '货币收紧'
    WHEN '美元体系稳定管理'  THEN '纪律性紧缩'
    WHEN '议程设定'          THEN '主权让步'
    WHEN '精英治理议程设定'  THEN '国家主权反弹 / 逆全球化加深'
    ELSE '路线调整'
  END;

  -- ── 10. Contradiction force — P6.4 核心替换点 ─────────────────
  --
  --  旧逻辑：ccc.source_effective_weight(...)
  --            ->'weights'->>'reverse_indicator_weight'
  --
  --  新逻辑：ccc.source_effective_weight_v3(...)
  --            ->'weights'->>'final_effective_weight_v3'
  --
  --  含义变化：从「单通道反向指标权重」
  --            升级为「Trust Fusion v3 三通道融合后权重」
  --
  WITH contradiction_force AS (
    SELECT
      ce.id,
      ce.official_narrative,
      array_to_string(ce.counter_signals, ' ') AS counter_text,
      array_to_string(ce.real_indicators,  ' ') AS real_text,
      ce.narrative_gap,
      ce.source_labels,
      ce.trust_levels,

      EXISTS (
        SELECT 1 FROM unnest(v_keywords_a) kw
        WHERE array_to_string(ce.counter_signals, ' ') ILIKE '%' || kw || '%'
           OR array_to_string(ce.real_indicators,  ' ') ILIKE '%' || kw || '%'
      ) AS hard_hit_a,

      EXISTS (
        SELECT 1 FROM unnest(v_keywords_b) kw
        WHERE array_to_string(ce.counter_signals, ' ') ILIKE '%' || kw || '%'
           OR array_to_string(ce.real_indicators,  ' ') ILIKE '%' || kw || '%'
      ) AS hard_hit_b,

      EXISTS (
        SELECT 1 FROM unnest(v_keywords_a) kw
        WHERE ce.official_narrative ILIKE '%' || kw || '%'
      ) AS official_hit_a,

      EXISTS (
        SELECT 1 FROM unnest(v_keywords_b) kw
        WHERE ce.official_narrative ILIKE '%' || kw || '%'
      ) AS official_hit_b,

      EXISTS (
        SELECT 1 FROM unnest(ce.trust_levels) tl
        WHERE tl = 'T6'
      ) AS has_t6,

      -- ▼ P6.4 替换点 ▼
      (
        SELECT AVG(
          COALESCE(
            (
              ccc.source_effective_weight_v3(sl.label::text, NULL::text, NULL::text)
              ->'weights'->>'final_effective_weight_v3'        -- ← v3 融合权重
            )::double precision,
            CASE
              WHEN sl.trust_level = 'T6' THEN 0.65
              WHEN sl.trust_level = 'T3' THEN 0.70
              WHEN sl.trust_level = 'T2' THEN 0.60
              ELSE 0.55
            END
          )
          *
          CASE WHEN sl.trust_level = 'T6' THEN 1.10 ELSE 1.00 END
        )
        FROM (
          SELECT
            labels.label,
            COALESCE(levels.trust_level, 'UNK') AS trust_level
          FROM unnest(ce.source_labels) WITH ORDINALITY labels(label, ord)
          LEFT JOIN unnest(ce.trust_levels) WITH ORDINALITY levels(trust_level, ord)
            ON labels.ord = levels.ord
        ) sl
      ) AS p6_weight
      -- ▲ P6.4 替换点 ▲

    FROM ccc.contradiction_engine ce
    WHERE ce.entity_id = v_entity_id
      AND ce.is_active = true
  ),
  routed AS (
    SELECT
      *,
      CASE
        -- Authoritarian
        WHEN v_route_profile = 'authoritarian' AND has_t6
         AND (
           official_narrative ILIKE '%透明通报%' OR official_narrative ILIKE '%自然界%'
           OR official_narrative ILIKE '%源于自然%' OR official_narrative ILIKE '%开放包容%'
           OR official_narrative ILIKE '%合作共赢%' OR official_narrative ILIKE '%和平解决%'
           OR official_narrative ILIKE '%无意动武%' OR official_narrative ILIKE '%自由贸易%'
           OR official_narrative ILIKE '%自由贸易秩序%' OR official_narrative ILIKE '%重要力量%'
           OR official_narrative ILIKE '%保持稳定%' OR official_narrative ILIKE '%稳定复苏%'
           OR official_narrative ILIKE '%改革开放%' OR official_narrative ILIKE '%持续深化%'
         ) THEN 'A'

        WHEN v_route_profile = 'authoritarian'
         AND (
           counter_text ILIKE '%军事演习%' OR real_text ILIKE '%军事演习%'
           OR counter_text ILIKE '%统一时间表%' OR real_text ILIKE '%统一时间表%'
           OR counter_text ILIKE '%样本销毁%'   OR real_text ILIKE '%样本销毁%'
           OR counter_text ILIKE '%调查受限%'   OR real_text ILIKE '%调查受限%'
           OR counter_text ILIKE '%预警压制%'   OR real_text ILIKE '%预警压制%'
           OR counter_text ILIKE '%出口限制%'   OR real_text ILIKE '%出口限制%'
           OR counter_text ILIKE '%供应链切断%' OR real_text ILIKE '%供应链切断%'
           OR counter_text ILIKE '%贸易武器化%' OR real_text ILIKE '%贸易武器化%'
           OR counter_text ILIKE '%技术脱钩%'   OR real_text ILIKE '%技术脱钩%'
           OR counter_text ILIKE '%关键矿产%'   OR real_text ILIKE '%关键矿产%'
           OR counter_text ILIKE '%债务陷阱%'   OR real_text ILIKE '%债务陷阱%'
           OR counter_text ILIKE '%经济胁迫%'   OR real_text ILIKE '%经济胁迫%'
         ) THEN 'A'

        -- Governance
        WHEN v_route_profile = 'governance'
         AND (
           official_narrative ILIKE '%全球治理%' OR official_narrative ILIKE '%自由贸易%'
           OR official_narrative ILIKE '%服务全人类%' OR official_narrative ILIKE '%开放包容%'
           OR official_narrative ILIKE '%利益相关者%'
         ) THEN 'B'

        -- Financial
        WHEN v_route_profile = 'financial'
         AND (
           real_text    ILIKE '%政治施压%' OR counter_text ILIKE '%政治施压%'
           OR real_text ILIKE '%听证施压%' OR counter_text ILIKE '%听证施压%'
           OR real_text ILIKE '%任命政治化%' OR counter_text ILIKE '%任命政治化%'
           OR real_text ILIKE '%政治周期%' OR counter_text ILIKE '%政治周期%'
           OR real_text ILIKE '%MMT%'      OR counter_text ILIKE '%MMT%'
           OR real_text ILIKE '%流动性锁死%' OR counter_text ILIKE '%流动性锁死%'
         ) THEN 'A'

        WHEN v_route_profile = 'financial'
         AND (
           official_narrative ILIKE '%独立%'    OR official_narrative ILIKE '%基于数据%'
           OR official_narrative ILIKE '%保持稳定%' OR official_narrative ILIKE '%符合预期%'
         ) THEN 'NEUTRAL'

        -- Transactional
        WHEN v_route_profile = 'transactional'
         AND (
           counter_text ILIKE '%技术脱钩%'   OR real_text ILIKE '%技术脱钩%'
           OR counter_text ILIKE '%加征关税%' OR real_text ILIKE '%加征关税%'
           OR counter_text ILIKE '%关税%'     OR real_text ILIKE '%关税%'
           OR counter_text ILIKE '%极限施压%' OR real_text ILIKE '%极限施压%'
           OR counter_text ILIKE '%供应链重组%' OR real_text ILIKE '%供应链重组%'
           OR counter_text ILIKE '%单边%'     OR real_text ILIKE '%单边%'
         ) THEN 'A'

        WHEN v_route_profile = 'transactional'
         AND (
           official_narrative ILIKE '%极好的协议%' OR official_narrative ILIKE '%随时谈判%'
           OR official_narrative ILIKE '%目标有限%'  OR official_narrative ILIKE '%可以谈判%'
         ) THEN 'B'

        -- Global residual
        WHEN (
           counter_text ILIKE '%宣战%'     OR real_text ILIKE '%宣战%'
           OR counter_text ILIKE '%全面制裁%' OR real_text ILIKE '%全面制裁%'
           OR counter_text ILIKE '%全面戒严%' OR real_text ILIKE '%全面戒严%'
           OR counter_text ILIKE '%切断代理行%' OR real_text ILIKE '%切断代理行%'
        ) THEN 'A'

        ELSE 'NEUTRAL'
      END AS alignment,
      COALESCE(p6_weight, 0.55) * COALESCE(narrative_gap, 0.5) AS force_score
    FROM contradiction_force
  )
  SELECT
    COALESCE(SUM(CASE WHEN alignment = 'A'       THEN force_score ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN alignment = 'B'       THEN force_score ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN alignment = 'NEUTRAL' THEN force_score ELSE 0 END), 0),
    COALESCE(jsonb_agg(jsonb_build_object(
      'id',                id,
      'alignment',         alignment,
      'force_score',       round(force_score::numeric, 4),
      'has_t6',            has_t6,
      'hard_hit_a',        hard_hit_a,
      'hard_hit_b',        hard_hit_b,
      'official_hit_a',    official_hit_a,
      'official_hit_b',    official_hit_b,
      'p6_weight',         round(COALESCE(p6_weight, 0.55)::numeric, 4),
      'narrative_gap',     narrative_gap,
      'official_narrative', official_narrative
    ) ORDER BY force_score DESC), '[]'::jsonb)
  INTO v_resonance, v_friction, v_neutral, v_alignment
  FROM routed;

  v_total_force := v_resonance + v_friction + v_neutral;

  -- ── 11. Confidence gate（与 forecast_v1_1 相同逻辑）─────────────
  v_gate := ccc.forecast_confidence_gate_v1(v_resonance, v_friction, v_neutral);

  v_confidence        := (v_gate->>'confidence')::float;
  v_evidence_score    := (v_gate->>'evidence_score')::numeric;
  v_direction_balance := (v_gate->>'direction_balance')::numeric;
  v_total_force_gate  := (v_gate->>'total_force')::numeric;

  -- ── 12. Output ─────────────────────────────────────────────────
  RETURN jsonb_build_object(
    'ok',            true,
    'version',       'forecast_v1.1-trust_v3',
    'entity',        p_entity_name,
    'route_profile', v_route_profile,
    'generated_at',  now(),

    'decision', CASE
      WHEN v_prob_a >= v_prob_b THEN 'A'
      ELSE 'B'
    END,

    'panel_1_pressure', jsonb_build_object(
      'pressure_level', v_pressure,
      'trend',          v_trend,
      'risk_level',     v_trajectory->>'risk_level',
      'dominant_mode',  v_profile->>'survival_mode',
      'essence',        v_profile->>'essence',
      'key_drivers',    v_trajectory->'key_drivers',
      'mirror_bias',    v_profile->>'mirror_bias'
    ),

    'panel_2_timeline', jsonb_build_object(
      'nodes',         v_timeline,
      'active_signals', v_signals,
      'contradictions', v_contradictions
    ),

    'panel_3_forecast', jsonb_build_object(
      'horizon_months',  COALESCE((v_trajectory->>'prediction_horizon')::int, 12),
      'option_a',        v_forecast_a,
      'prob_a',          round(v_prob_a::numeric, 2),
      'option_b',        v_forecast_b,
      'prob_b',          round(v_prob_b::numeric, 2),
      'confidence',      round(v_confidence::numeric, 2),
      'top_behaviors',   v_behaviors,
      'prediction_text', v_trajectory->>'prediction'
    ),

    'panel_4_signal_alignment', jsonb_build_object(
      'model',             'resonance_friction_v1',
      'trust_weight_model', 'source_effective_weight_v3',   -- ← 标记 v3
      'resonance_score',   round(v_resonance::numeric, 4),
      'friction_score',    round(v_friction::numeric, 4),
      'neutral_score',     round(v_neutral::numeric, 4),
      'confidence',        round(v_confidence::numeric, 2),
      'evidence_score',    round(v_evidence_score, 4),
      'direction_balance', round(v_direction_balance, 4),
      'total_force',       round(v_total_force_gate, 4),
      'confidence_model',  'confidence_evidence_gate_v1',
      'rules', jsonb_build_object(
        'probability',    'internal_behavior_model',
        'confidence',     'external_signal_resonance',
        't6_official_b',  'route_specific',
        't6_official_a',  'route_specific',
        'route_profile',  v_route_profile
      ),
      'alignment_details', COALESCE(v_alignment, '[]'::jsonb)
    )
  );
END;
$$;


ALTER FUNCTION ccc.forecast_v1_1_trust_v3(p_entity_name text) OWNER TO postgres;

--
-- Name: forecast_v1_2_timeline(text); Type: FUNCTION; Schema: ccc; Owner: postgres
--

CREATE FUNCTION ccc.forecast_v1_2_timeline(p_entity_name text) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
  v_base          jsonb;
  v_entity_id     bigint;

  -- timeline scope
  v_scope_ids     bigint[];
  v_proxy_entities jsonb := '[]'::jsonb;

  -- timeline force
  v_causal_count  int   := 0;
  v_escalation_avg float := 0.5;
  v_direction     text  := 'stable';
  v_timeline_force float := 0.0;

  -- base force fields
  v_resonance     double precision := 0.0;
  v_friction      double precision := 0.0;
  v_neutral       double precision := 0.0;

  -- gate
  v_gate              jsonb;
  v_confidence        numeric := 0.50;
  v_evidence_score    numeric := 0.0;
  v_direction_balance numeric := 0.0;
  v_total_force_gate  numeric := 0.0;

BEGIN
  -- ── 0. 调用 trust_v3 base ──────────────────────────────────────
  v_base := ccc.forecast_v1_1_trust_v3(p_entity_name);

  IF COALESCE((v_base->>'ok')::boolean, false) IS NOT TRUE THEN
    RETURN v_base;
  END IF;

  -- ── 1. 取 entity_id ────────────────────────────────────────────
  SELECT ep.entity_id
  INTO v_entity_id
  FROM ccc.entity_profiles ep
  WHERE lower(ep.entity_name) = lower(p_entity_name)
  LIMIT 1;

  -- ── 2. 构建 timeline scope：self + active proxy ─────────────────
  SELECT
    array_agg(DISTINCT scope_id),
    COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'entity',       p_entity_name,
          'proxy',        proxy_entity_name,
          'proxy_type',   proxy_type,
          'source',       proxy_source,
          'weight',       weight
        )
      ) FILTER (WHERE proxy_entity_id IS NOT NULL),
      '[]'::jsonb
    )
  INTO v_scope_ids, v_proxy_entities
  FROM (
    -- self
    SELECT
      v_entity_id        AS scope_id,
      NULL::bigint       AS proxy_entity_id,
      NULL::text         AS proxy_entity_name,
      NULL::text         AS proxy_type,
      NULL::text         AS proxy_source,
      1.0                AS weight
    UNION ALL
    -- active proxies
    SELECT
      tpm.proxy_entity_id,
      tpm.proxy_entity_id,
      tpm.proxy_entity_name,
      tpm.proxy_type,
      tpm.proxy_source,
      tpm.weight
    FROM ccc.timeline_proxy_map tpm
    WHERE tpm.entity_id = v_entity_id
      AND tpm.is_active = true
  ) s;

  -- ── 3. 计算 timeline_force ──────────────────────────────────────
  SELECT
    COUNT(DISTINCT ce.id),
    COALESCE(AVG(tgt.escalation_score), 0.5),
    COALESCE(
      (SELECT directional_bias
       FROM ccc.causal_edges ce2
       JOIN ccc.event_nodes en2 ON en2.id = ce2.source_event_id
       WHERE en2.entity_id = ANY(v_scope_ids)
       GROUP BY directional_bias
       ORDER BY COUNT(*) DESC
       LIMIT 1),
      'stable'
    )
  INTO v_causal_count, v_escalation_avg, v_direction
  FROM ccc.causal_edges ce
  JOIN ccc.event_nodes src ON src.id = ce.source_event_id
  JOIN ccc.event_nodes tgt ON tgt.id = ce.target_event_id
  WHERE src.entity_id = ANY(v_scope_ids)
     OR tgt.entity_id = ANY(v_scope_ids);

  -- timeline_force 公式
  v_timeline_force := LEAST(1.0,
    v_causal_count * 0.05
    + v_escalation_avg * 0.50
  );

  -- ── 4. 读取 base 三路应力 ───────────────────────────────────────
  v_resonance := COALESCE(
    (v_base #>> '{panel_4_signal_alignment,resonance_score}')::double precision, 0.0);
  v_friction  := COALESCE(
    (v_base #>> '{panel_4_signal_alignment,friction_score}')::double precision, 0.0);
  v_neutral   := COALESCE(
    (v_base #>> '{panel_4_signal_alignment,neutral_score}')::double precision, 0.0);

  -- ── 5. timeline_force 注入三路 ──────────────────────────────────
  --
  -- escalating   → 升级压力 → 强化 resonance（option A 方向）
  -- de-escalating → 降压方向 → 强化 friction（option B 方向）
  -- stable        → 无方向性 → 进入 neutral
  --
  CASE v_direction
    WHEN 'escalating'    THEN v_resonance := v_resonance + v_timeline_force;
    WHEN 'de-escalating' THEN v_friction  := v_friction  + v_timeline_force;
    ELSE                      v_neutral   := v_neutral   + v_timeline_force;
  END CASE;

  -- ── 6. 重新过 confidence gate ───────────────────────────────────
  v_gate := ccc.forecast_confidence_gate_v1(v_resonance, v_friction, v_neutral);

  v_confidence        := (v_gate->>'confidence')::numeric;
  v_evidence_score    := (v_gate->>'evidence_score')::numeric;
  v_direction_balance := (v_gate->>'direction_balance')::numeric;
  v_total_force_gate  := (v_gate->>'total_force')::numeric;

  -- ── 7. 组装输出：在 base 基础上覆写相关字段 ─────────────────────
  v_base := jsonb_set(v_base, '{version}',
    to_jsonb('forecast_v1.2-timeline'::text), true);

  -- panel_3 confidence
  v_base := jsonb_set(v_base, '{panel_3_forecast,confidence}',
    to_jsonb(round(v_confidence, 2)), true);

  -- panel_4 全部更新
  v_base := jsonb_set(v_base, '{panel_4_signal_alignment,resonance_score}',
    to_jsonb(round(v_resonance::numeric, 4)), true);
  v_base := jsonb_set(v_base, '{panel_4_signal_alignment,friction_score}',
    to_jsonb(round(v_friction::numeric, 4)), true);
  v_base := jsonb_set(v_base, '{panel_4_signal_alignment,neutral_score}',
    to_jsonb(round(v_neutral::numeric, 4)), true);
  v_base := jsonb_set(v_base, '{panel_4_signal_alignment,confidence}',
    to_jsonb(round(v_confidence, 2)), true);
  v_base := jsonb_set(v_base, '{panel_4_signal_alignment,total_force}',
    to_jsonb(round(v_total_force_gate, 4)), true);
  v_base := jsonb_set(v_base, '{panel_4_signal_alignment,evidence_score}',
    to_jsonb(round(v_evidence_score, 4)), true);
  v_base := jsonb_set(v_base, '{panel_4_signal_alignment,direction_balance}',
    to_jsonb(round(v_direction_balance, 4)), true);
  v_base := jsonb_set(v_base, '{panel_4_signal_alignment,confidence_model}',
    to_jsonb('confidence_evidence_gate_v1'::text), true);

  -- timeline layer 新增字段
  v_base := jsonb_set(v_base, '{panel_4_signal_alignment,timeline_layer}',
    jsonb_build_object(
      'timeline_force',    round(v_timeline_force::numeric, 4),
      'causal_count',      v_causal_count,
      'escalation_avg',    round(v_escalation_avg::numeric, 4),
      'direction',         v_direction,
      'injected_into',     CASE v_direction
                             WHEN 'escalating'    THEN 'resonance'
                             WHEN 'de-escalating' THEN 'friction'
                             ELSE 'neutral'
                           END,
      'timeline_scope',    ARRAY['self', 'hardcoded_proxy'],
      'proxy_entities',    v_proxy_entities
    ), true);

  RETURN v_base;
END;
$$;


ALTER FUNCTION ccc.forecast_v1_2_timeline(p_entity_name text) OWNER TO postgres;

--
-- Name: ingest_v21(text); Type: FUNCTION; Schema: ccc; Owner: postgres
--

CREATE FUNCTION ccc.ingest_v21(input_text text) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE

    v_raw BIGINT;

    v_doc BIGINT;

    v_token RECORD;

    v_prev BIGINT;

    v_curr BIGINT;

BEGIN

    INSERT INTO ccc.raw_documents(raw_content)
    VALUES (input_text)
    RETURNING id INTO v_raw;

    INSERT INTO ccc.documents(
        raw_document_id,
        content,
        content_hash
    )
    VALUES (
        v_raw,
        input_text,
        md5(input_text)
    )
    ON CONFLICT(content_hash)
    DO NOTHING
    RETURNING id INTO v_doc;

    IF v_doc IS NULL THEN

        SELECT id
        INTO v_doc
        FROM ccc.documents
        WHERE content_hash = md5(input_text);

    END IF;

    FOR v_token IN
        SELECT *
        FROM ccc.ai_tokenize(input_text)
    LOOP

        v_curr :=
        ccc.safe_entity_insert(v_token.token);

        IF v_curr IS NOT NULL THEN

            INSERT INTO ccc.document_entities(
                document_id,
                entity_id,
                frequency
            )
            VALUES (
                v_doc,
                v_curr,
                1
            )
            ON CONFLICT(document_id, entity_id)
            DO UPDATE
            SET frequency =
            ccc.document_entities.frequency + 1;

        END IF;

        IF v_prev IS NOT NULL
        AND v_curr IS NOT NULL
        THEN

            INSERT INTO ccc.graph_edges(
                source_entity_id,
                target_entity_id,
                relation,
                weight,
                document_id
            )
            VALUES (
                v_prev,
                v_curr,
                'co_occurrence',
                1,
                v_doc
            );

        END IF;

        v_prev := v_curr;

    END LOOP;

    INSERT INTO ccc.events(
        document_id,
        event_summary
    )
    VALUES (
        v_doc,
        left(input_text, 300)
    );

    INSERT INTO ccc.claims(
        document_id,
        claim_text
    )
    VALUES (
        v_doc,
        left(input_text, 500)
    );

    RETURN jsonb_build_object(
        'status', 'OK',
        'document_id', v_doc
    );

END;
$$;


ALTER FUNCTION ccc.ingest_v21(input_text text) OWNER TO postgres;

--
-- Name: is_person_noise(text); Type: FUNCTION; Schema: ccc; Owner: postgres
--

CREATE FUNCTION ccc.is_person_noise(input_text text) RETURNS boolean
    LANGUAGE plpgsql STABLE
    AS $_$
DECLARE
    v TEXT;
BEGIN
    v := lower(trim(coalesce(ccc.clean_person_candidate(input_text), '')));

    -- 保留常见中文姓氏拼音，不视为噪声
    IF v IN ('chen','wang','li','zhang','xi','jinping','chan','lee') THEN
        RETURN false;
    END IF;

    -- 查噪声词表
    IF EXISTS (SELECT 1 FROM ccc.person_noise_library WHERE word = v) THEN
        RETURN true;
    END IF;

    -- 单个或两个拼音字母（ān、An、ab 等）
    IF v ~ $r$^[a-z]{1,3}$r$ THEN
        RETURN true;
    END IF;

    -- 字母+汉字混拼（An发、An的）
    IF v ~ $r$^[a-z]{1,3}[\u4e00-\u9fff]$r$ THEN
        RETURN true;
    END IF;

    -- emoji 或特殊符号开头
    IF v ~ $r$^[☒☑✓✗❤⋯…]$r$ THEN
        RETURN true;
    END IF;

    -- 含货币/平台词
    IF v ~ $r$(币|platform|exchange)$r$ THEN
        RETURN true;
    END IF;

    -- 规则过滤：职位词、数字符号、超长词
    IF v ~ '(said|told|according|report|news|agency|media|press)$'
       OR v ~ '(ministry|bureau|office|department|committee|council)$'
       OR v ~ '(company|corp|ltd|inc|group|org|party|government)$'
       OR v ~ '[0-9%$@#&*]'
       OR v ~ '[<>{}\[\]\\|]'
       OR length(v) > 40
       OR length(v) < 2
    THEN
        RETURN true;
    END IF;

    RETURN false;
END;
$_$;


ALTER FUNCTION ccc.is_person_noise(input_text text) OWNER TO postgres;

--
-- Name: normalize_entity_name(text); Type: FUNCTION; Schema: ccc; Owner: postgres
--

CREATE FUNCTION ccc.normalize_entity_name(input_text text) RETURNS text
    LANGUAGE plpgsql
    AS $$
BEGIN

    RETURN lower(
        regexp_replace(
            trim(input_text),
            '[^[:alnum:]\u4e00-\u9fa5]+',
            '',
            'g'
        )
    );

END;
$$;


ALTER FUNCTION ccc.normalize_entity_name(input_text text) OWNER TO postgres;

--
-- Name: person_event_profile(text, integer); Type: FUNCTION; Schema: ccc; Owner: postgres
--

CREATE FUNCTION ccc.person_event_profile(q text, limit_count integer DEFAULT 30) RETURNS TABLE(person_name text, event_date date, location text, impact text, event_summary text, related_people text[], other_events jsonb, document_id bigint)
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    v_canonical text;
    v_search    text;
BEGIN
    -- 先查别名表，把输入转换为标准名
    SELECT canonical INTO v_canonical
    FROM ccc.person_aliases
    WHERE lower(alias) = lower(trim(q))
    LIMIT 1;

    -- 有别名就用标准名搜索，否则用原始输入
    v_search := coalesce(v_canonical, q);

    RETURN QUERY
    WITH matched AS (
        SELECT ed.*
        FROM ccc.event_dashboard ed
        WHERE ed.person_name    ILIKE '%' || v_search || '%'
           OR ed.event_summary  ILIKE '%' || v_search || '%'
           OR ed.impact         ILIKE '%' || v_search || '%'
           OR ed.location       ILIKE '%' || v_search || '%'
           -- 同时也搜索原始输入（防止别名转换不准确）
           OR (v_canonical IS NOT NULL AND (
               ed.person_name   ILIKE '%' || q || '%'
           ))
        ORDER BY ed.event_date DESC NULLS LAST, ed.id DESC
        LIMIT limit_count
    )
    SELECT
        m.person_name,
        m.event_date,
        m.location,
        m.impact,
        m.event_summary,
        (
            SELECT array_agg(DISTINCT ed2.person_name ORDER BY ed2.person_name)
            FROM ccc.event_dashboard ed2
            WHERE ed2.document_id  = m.document_id
              AND ed2.person_name <> m.person_name
              AND NOT ccc.is_person_noise(ed2.person_name)
        ) AS related_people,
        (
            SELECT jsonb_agg(
                jsonb_build_object(
                    'date',        ed3.event_date,
                    'location',    ed3.location,
                    'impact',      ed3.impact,
                    'summary',     ed3.event_summary,
                    'document_id', ed3.document_id
                )
                ORDER BY ed3.event_date DESC NULLS LAST
            )
            FROM ccc.event_dashboard ed3
            WHERE ed3.person_name = m.person_name
              AND ed3.id         <> m.id
            LIMIT 10
        ) AS other_events,
        m.document_id
    FROM matched m;
END;
$$;


ALTER FUNCTION ccc.person_event_profile(q text, limit_count integer) OWNER TO postgres;

--
-- Name: prediction_output_standard_v1(text); Type: FUNCTION; Schema: ccc; Owner: postgres
--

CREATE FUNCTION ccc.prediction_output_standard_v1(p_entity_name text) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
  v_panel         jsonb;
  v_entity_id     bigint;

  -- 基础字段
  v_pressure      text;
  v_trajectory    text;
  v_trajectory_code text;
  v_timeline_force float;
  v_alert         text;
  v_confidence    float;
  v_confidence_label text;
  v_total_force   float;
  v_evidence_score float;

  -- 派生字段
  v_trust_score   float;
  v_trust_label   text;
  v_gate_passed   boolean;
  v_forecast_status text;
  v_decision_readiness text;
  v_decision_mode_hint text;

  -- band
  v_timeline_band text;
  v_force_direction text;

BEGIN
  -- ── 0. 调用 prediction_panel_v1 ────────────────────────────────
  v_panel := ccc.prediction_panel_v1(p_entity_name);

  IF COALESCE((v_panel->>'ok')::boolean, false) IS NOT TRUE THEN
    RETURN jsonb_build_object(
      'ok',     false,
      'error',  'panel failed',
      'entity', p_entity_name
    );
  END IF;

  SELECT ep.entity_id INTO v_entity_id
  FROM ccc.entity_profiles ep
  WHERE lower(ep.entity_name) = lower(p_entity_name)
  LIMIT 1;

  -- ── 1. 提取基础字段 ────────────────────────────────────────────
  v_pressure       := COALESCE(v_panel #>> '{card_1_pressure,pressure,label}', 'UNKNOWN');
  v_trajectory     := COALESCE(v_panel #>> '{card_2_timeline,trajectory,label}', '稳定');
  v_timeline_force := COALESCE((v_panel #>> '{card_4_forecast,signal_strength,timeline_force}')::float, 0.0);
  v_alert          := v_panel #>> '{card_3_contradiction,top,alert_level}';
  v_confidence     := COALESCE((v_panel #>> '{card_4_forecast,forecast,confidence}')::float, 0.5);
  v_confidence_label := COALESCE(v_panel #>> '{card_4_forecast,forecast,confidence_label}', 'LOW');
  v_total_force    := COALESCE((v_panel #>> '{card_4_forecast,signal_strength,total_force}')::float, 0.0);
  v_evidence_score := COALESCE((v_panel #>> '{card_4_forecast,signal_strength,evidence_score}')::float, 0.0);

  -- ── 2. trajectory_code ─────────────────────────────────────────
  v_trajectory_code := CASE v_trajectory
    WHEN '升级' THEN 'UP'
    WHEN '降级' THEN 'DOWN'
    WHEN '稳定' THEN 'STABLE'
    WHEN '上升' THEN 'UP'
    WHEN '下降' THEN 'DOWN'
    ELSE 'STABLE'
  END;

  -- ── 3. timeline_force band ─────────────────────────────────────
  v_timeline_band := CASE
    WHEN v_timeline_force >= 0.75 THEN 'EXTREME'
    WHEN v_timeline_force >= 0.50 THEN 'HIGH'
    WHEN v_timeline_force >= 0.25 THEN 'MEDIUM'
    ELSE 'LOW'
  END;

  v_force_direction := CASE v_trajectory_code
    WHEN 'UP'   THEN 'ACCELERATING'
    WHEN 'DOWN' THEN 'DECELERATING'
    ELSE 'HOLDING'
  END;

  -- ── 4. trust_score / trust_label ───────────────────────────────
  -- trust_score = evidence_score × confidence（综合可信度）
  v_trust_score := ROUND((v_evidence_score * v_confidence)::numeric, 4);
  v_trust_label := CASE
    WHEN v_trust_score >= 0.75 THEN 'HIGH'
    WHEN v_trust_score >= 0.50 THEN 'MEDIUM'
    ELSE 'LOW'
  END;

  -- ── 5. confidence_gate_passed ──────────────────────────────────
  -- 条件：confidence >= 0.60 AND evidence_score >= 0.50
  v_gate_passed := (v_confidence >= 0.60 AND v_evidence_score >= 0.50);

  -- ── 6. forecast_status ─────────────────────────────────────────
  v_forecast_status := CASE
    WHEN NOT v_gate_passed AND v_confidence < 0.40
      THEN 'BLOCKED'
    WHEN NOT v_gate_passed
      THEN 'WEAK'
    WHEN v_confidence >= 0.75 AND v_total_force >= 0.80
      THEN 'VALID'
    WHEN v_confidence >= 0.60
      THEN 'WATCH'
    ELSE 'WEAK'
  END;

  -- ── 7. decision_readiness ──────────────────────────────────────
  v_decision_readiness := CASE
    WHEN v_forecast_status = 'BLOCKED'
      THEN 'NO_ACTION'
    WHEN v_forecast_status = 'WEAK'
      THEN 'WAIT'
    WHEN v_forecast_status = 'WATCH'
      THEN 'MONITOR'
    WHEN v_forecast_status = 'VALID' AND v_gate_passed
      THEN 'READY'
    ELSE 'MONITOR'
  END;

  -- ── 8. decision_mode_hint ──────────────────────────────────────
  v_decision_mode_hint := CASE
    WHEN v_decision_readiness = 'NO_ACTION'  THEN 'HOLD'
    WHEN v_decision_readiness = 'WAIT'       THEN 'HOLD'
    WHEN v_trajectory_code = 'DOWN'          THEN 'DE_ESCALATION'
    WHEN v_pressure = 'CRITICAL' AND v_trajectory_code = 'UP'
                                             THEN 'ESCALATION_PREP'
    WHEN v_pressure IN ('HIGH','CRITICAL') AND v_trajectory_code = 'STABLE'
                                             THEN 'DEFENSIVE'
    WHEN v_pressure = 'MEDIUM' AND v_trajectory_code = 'UP'
                                             THEN 'OPPORTUNISTIC'
    ELSE 'HOLD'
  END;

  -- ── 9. 四卡组装 ────────────────────────────────────────────────
  RETURN jsonb_build_object(
    'ok',              true,
    'schema_version',  'prediction_output_standard_v1',
    'entity',          p_entity_name,
    'entity_id',       v_entity_id,
    'panel_version',   v_panel->>'version',
    'forecast_version', v_panel->>'forecast_version',
    'generated_at',    now(),

    -- 顶层摘要字段（P7 快速读取）
    'pressure',            v_pressure,
    'trajectory',          v_trajectory,
    'trajectory_code',     v_trajectory_code,
    'timeline_force',      round(v_timeline_force::numeric, 4),
    'alert',               v_alert,
    'confidence',          round(v_confidence::numeric, 2),
    'confidence_label',    v_confidence_label,
    'trust_score',         v_trust_score,
    'trust_label',         v_trust_label,
    'confidence_gate_passed', v_gate_passed,
    'forecast_status',     v_forecast_status,
    'decision_readiness',  v_decision_readiness,
    'decision_mode_hint',  v_decision_mode_hint,

    -- Card 1: Forecast Summary
    'card1_forecast_summary', jsonb_build_object(
      'pressure',        v_pressure,
      'trajectory',      v_trajectory,
      'trajectory_code', v_trajectory_code,
      'alert',           v_alert,
      'summary',         concat(
        p_entity_name, ' | ',
        v_pressure, ' pressure | ',
        v_trajectory, ' trajectory | ',
        COALESCE(v_alert, 'no alert')
      )
    ),

    -- Card 2: Confidence / Trust Gate
    'card2_confidence_gate', jsonb_build_object(
      'confidence',            round(v_confidence::numeric, 2),
      'confidence_label',      v_confidence_label,
      'trust_score',           v_trust_score,
      'trust_label',           v_trust_label,
      'evidence_score',        round(v_evidence_score::numeric, 4),
      'total_force',           round(v_total_force::numeric, 4),
      'confidence_gate_passed', v_gate_passed,
      'gate_reason',           CASE
        WHEN v_gate_passed
          THEN 'Confidence and evidence both above operational threshold.'
        WHEN v_confidence < 0.60
          THEN 'Confidence below threshold (< 0.60).'
        ELSE 'Evidence score below threshold (< 0.50).'
      END
    ),

    -- Card 3: Timeline Force
    'card3_timeline_force', jsonb_build_object(
      'timeline_force',       round(v_timeline_force::numeric, 4),
      'timeline_force_band',  v_timeline_band,
      'force_direction',      v_force_direction,
      'trajectory_code',      v_trajectory_code,
      'timeline_note',        CASE v_timeline_band
        WHEN 'EXTREME' THEN 'Timeline pressure is critical. Decision window may be closing.'
        WHEN 'HIGH'    THEN 'Timeline pressure is strong enough to affect decision priority.'
        WHEN 'MEDIUM'  THEN 'Timeline pressure is moderate. Monitor for escalation.'
        ELSE                'Timeline pressure is low. No immediate urgency.'
      END
    ),

    -- Card 4: Decision Input（P7 标准接口）
    'card4_decision_input', jsonb_build_object(
      'forecast_status',     v_forecast_status,
      'decision_readiness',  v_decision_readiness,
      'decision_mode_hint',  v_decision_mode_hint,
      'p7_input_allowed',    v_gate_passed,
      'risk_level',          v_pressure,
      'action_bias',         CASE v_decision_mode_hint
        WHEN 'ESCALATION_PREP' THEN 'PREPARE'
        WHEN 'DE_ESCALATION'   THEN 'REDUCE'
        WHEN 'DEFENSIVE'       THEN 'PROTECT'
        WHEN 'OPPORTUNISTIC'   THEN 'CAPTURE'
        ELSE                        'HOLD'
      END,
      'primary_reason',      concat(
        v_pressure, ' pressure, ',
        v_trajectory, ' trajectory, ',
        v_confidence_label, ' confidence, ',
        v_timeline_band, ' timeline force.'
      )
    )
  );
END;
$$;


ALTER FUNCTION ccc.prediction_output_standard_v1(p_entity_name text) OWNER TO postgres;

--
-- Name: prediction_panel_v1(text); Type: FUNCTION; Schema: ccc; Owner: postgres
--

CREATE FUNCTION ccc.prediction_panel_v1(p_entity_name text) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
  v_forecast        jsonb;
  v_forecast_version text;  -- ← 新增，单独保存版本号
  v_entity_id       bigint;
  v_profile_id      bigint;

  v_card1           jsonb;
  v_card2           jsonb;
  v_card3           jsonb;
  v_card4           jsonb;

  v_pressure        float;
  v_trend           text;
  v_risk            text;
  v_essence         text;
  v_mode            text;
  v_mirror          text;
  v_drives          jsonb;

  v_timeline_nodes    jsonb;
  v_causal_chain      jsonb;
  v_trajectory_dir    text;
  v_escalation_avg    float;

  v_contradictions    jsonb;
  v_top_contradiction jsonb;

  v_prob_a          float;
  v_prob_b          float;
  v_option_a        text;
  v_option_b        text;
  v_confidence      float;
  v_decision        text;
  v_horizon         int;
  v_prediction_text text;
  v_top_behaviors   jsonb;

  v_timeline_force  float;  -- ← 新增，单独保存

BEGIN
  -- ── 0. 调用 v1.2 timeline forecast ─────────────────────────────
  v_forecast := ccc.forecast_v1_2_timeline(p_entity_name);

  IF COALESCE((v_forecast->>'ok')::boolean, false) IS NOT TRUE THEN
    RETURN jsonb_build_object(
      'ok',     false,
      'error',  'forecast failed',
      'entity', p_entity_name,
      'detail', v_forecast->>'error'
    );
  END IF;

  -- ← 立即保存，防止后续被覆盖
  v_forecast_version := v_forecast->>'version';
  v_timeline_force   := COALESCE(
    (v_forecast #>> '{panel_4_signal_alignment,timeline_layer,timeline_force}')::float,
    0.0
  );

  v_pressure  := COALESCE((v_forecast #>> '{panel_1_pressure,pressure_level}')::float, 0.5);
  v_trend     := COALESCE(v_forecast #>> '{panel_1_pressure,trend}', 'stable');
  v_risk      := COALESCE(v_forecast #>> '{panel_1_pressure,risk_level}', 'unknown');
  v_essence   := COALESCE(v_forecast #>> '{panel_1_pressure,essence}', '');
  v_mode      := COALESCE(v_forecast #>> '{panel_1_pressure,dominant_mode}', '');
  v_mirror    := COALESCE(v_forecast #>> '{panel_1_pressure,mirror_bias}', '');
  v_drives    := COALESCE(v_forecast #> '{panel_1_pressure,key_drivers}', '[]'::jsonb);

  v_prob_a    := COALESCE((v_forecast #>> '{panel_3_forecast,prob_a}')::float, 0.55);
  v_prob_b    := COALESCE((v_forecast #>> '{panel_3_forecast,prob_b}')::float, 0.45);
  v_option_a  := COALESCE(v_forecast #>> '{panel_3_forecast,option_a}', '');
  v_option_b  := COALESCE(v_forecast #>> '{panel_3_forecast,option_b}', '');
  v_confidence := COALESCE((v_forecast #>> '{panel_3_forecast,confidence}')::float, 0.5);
  v_decision  := COALESCE(v_forecast->>'decision', 'A');
  v_horizon   := COALESCE((v_forecast #>> '{panel_3_forecast,horizon_months}')::int, 12);
  v_prediction_text := COALESCE(v_forecast #>> '{panel_3_forecast,prediction_text}', '');
  v_top_behaviors   := COALESCE(v_forecast #> '{panel_3_forecast,top_behaviors}', '[]'::jsonb);

  v_timeline_nodes  := COALESCE(v_forecast #> '{panel_2_timeline,nodes}', '[]'::jsonb);
  v_contradictions  := COALESCE(v_forecast #> '{panel_2_timeline,contradictions}', '[]'::jsonb);

  SELECT ep.entity_id, ep.id
  INTO v_entity_id, v_profile_id
  FROM ccc.entity_profiles ep
  WHERE lower(ep.entity_name) = lower(p_entity_name)
  LIMIT 1;

  SELECT
    COALESCE(jsonb_agg(
      jsonb_build_object(
        'from_essence',       src.essence,
        'to_essence',         tgt.essence,
        'causal_type',        ce.causal_type,
        'directional_bias',   ce.directional_bias,
        'causality_strength', ce.causality_strength,
        'time_delta_days',    ce.time_delta_days
      )
      ORDER BY src.event_time DESC
    ), '[]'::jsonb),
    AVG(CASE WHEN tgt.escalation_score IS NOT NULL
             THEN tgt.escalation_score ELSE 0.5 END)
  INTO v_causal_chain, v_escalation_avg
  FROM ccc.causal_edges ce
  JOIN ccc.event_nodes src ON src.id = ce.source_event_id
  JOIN ccc.event_nodes tgt ON tgt.id = ce.target_event_id
  WHERE src.entity_id = v_entity_id
     OR tgt.entity_id = v_entity_id
  LIMIT 6;

  SELECT COALESCE(
    (SELECT directional_bias
     FROM ccc.causal_edges ce
     JOIN ccc.event_nodes en ON en.id = ce.source_event_id
     WHERE en.entity_id = v_entity_id
     GROUP BY directional_bias
     ORDER BY COUNT(*) DESC
     LIMIT 1),
    v_trend
  ) INTO v_trajectory_dir;

  SELECT COALESCE(v_contradictions->0, '{}'::jsonb)
  INTO v_top_contradiction;

  -- Card 1
  v_card1 := jsonb_build_object(
    'card',          'entity_pressure',
    'entity',        p_entity_name,
    'essence',       v_essence,
    'dominant_mode', v_mode,
    'core_drives',   v_drives,
    'mirror_bias',   v_mirror,
    'pressure', jsonb_build_object(
      'level', round(v_pressure::numeric, 2),
      'trend', v_trend,
      'risk',  v_risk,
      'label', CASE
        WHEN v_pressure >= 0.80 THEN 'CRITICAL'
        WHEN v_pressure >= 0.65 THEN 'HIGH'
        WHEN v_pressure >= 0.45 THEN 'MEDIUM'
        ELSE 'LOW' END
    ),
    'inertia_direction', CASE v_decision
      WHEN 'A' THEN v_option_a ELSE v_option_b END,
    'top_trigger', CASE
      WHEN jsonb_array_length(v_top_behaviors) > 0
      THEN v_top_behaviors->0->'triggers'->0
      ELSE NULL END
  );

  -- Card 2
  v_card2 := jsonb_build_object(
    'card',         'timeline_trajectory',
    'entity',       p_entity_name,
    'node_count',   jsonb_array_length(v_timeline_nodes),
    'recent_nodes', v_timeline_nodes,
    'causal_chain', v_causal_chain,
    'trajectory', jsonb_build_object(
      'direction',      v_trajectory_dir,
      'escalation_avg', round(COALESCE(v_escalation_avg, 0.5)::numeric, 3),
      'label', CASE
        WHEN v_trajectory_dir = 'escalating'    THEN '升级'
        WHEN v_trajectory_dir = 'de-escalating' THEN '降级'
        WHEN v_trajectory_dir = 'stable'        THEN '稳定'
        WHEN v_trajectory_dir = 'rising'        THEN '上升'
        WHEN v_trajectory_dir = 'declining'     THEN '下降'
        ELSE v_trajectory_dir END
    ),
    'next_step',      v_prediction_text,
    'timeline_layer', v_forecast #> '{panel_4_signal_alignment,timeline_layer}'
  );

  -- Card 3
  v_card3 := jsonb_build_object(
    'card',                'contradiction_alert',
    'entity',              p_entity_name,
    'contradiction_count', jsonb_array_length(v_contradictions),
    'all_contradictions',  v_contradictions,
    'top', CASE
      WHEN v_top_contradiction = '{}'::jsonb THEN NULL
      ELSE jsonb_build_object(
        'official_narrative', v_top_contradiction->>'official',
        'counter_signals',    v_top_contradiction->'counter_signals',
        'real_indicators',    v_top_contradiction->'real_indicators',
        'gap',                v_top_contradiction->>'gap',
        'severity',           v_top_contradiction->>'severity',
        'alert_level', CASE
          WHEN (v_top_contradiction->>'gap')::float >= 0.75 THEN 'CRITICAL'
          WHEN (v_top_contradiction->>'gap')::float >= 0.55 THEN 'HIGH'
          WHEN (v_top_contradiction->>'gap')::float >= 0.35 THEN 'MEDIUM'
          ELSE 'LOW' END
      ) END
  );

  -- Card 4
  v_card4 := jsonb_build_object(
    'card',           'survival_forecast',
    'entity',         p_entity_name,
    'horizon_months', v_horizon,
    'forecast', jsonb_build_object(
      'decision',   v_decision,
      'option_a',   v_option_a,
      'prob_a',     round(v_prob_a::numeric, 2),
      'option_b',   v_option_b,
      'prob_b',     round(v_prob_b::numeric, 2),
      'confidence', round(v_confidence::numeric, 2),
      'confidence_label', CASE
        WHEN v_confidence >= 0.80 THEN 'HIGH'
        WHEN v_confidence >= 0.60 THEN 'MEDIUM'
        ELSE 'LOW' END
    ),
    'signal_strength', jsonb_build_object(
      'resonance',      round((v_forecast #>> '{panel_4_signal_alignment,resonance_score}')::numeric, 4),
      'friction',       round((v_forecast #>> '{panel_4_signal_alignment,friction_score}')::numeric, 4),
      'total_force',    round((v_forecast #>> '{panel_4_signal_alignment,total_force}')::numeric, 4),
      'evidence_score', round((v_forecast #>> '{panel_4_signal_alignment,evidence_score}')::numeric, 4),
      'timeline_force', round(v_timeline_force::numeric, 4)  -- ← 用变量，不再走路径
    ),
    'top_behaviors', v_top_behaviors,
    'trust_model',   'source_effective_weight_v3'
  );

  RETURN jsonb_build_object(
    'ok',              true,
    'version',         'prediction_panel_v1.2',
    'entity',          p_entity_name,
    'generated_at',    now(),
    'forecast_version', v_forecast_version,  -- ← 用变量
    'card_1_pressure',      v_card1,
    'card_2_timeline',      v_card2,
    'card_3_contradiction', v_card3,
    'card_4_forecast',      v_card4
  );
END;
$$;


ALTER FUNCTION ccc.prediction_panel_v1(p_entity_name text) OWNER TO postgres;

--
-- Name: refresh_event_dashboard(integer); Type: FUNCTION; Schema: ccc; Owner: postgres
--

CREATE FUNCTION ccc.refresh_event_dashboard(limit_count integer DEFAULT NULL::integer) RETURNS TABLE(inserted_count integer, total_count integer)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_inserted int := 0;
    v_total    int;
BEGIN
    WITH
    docs AS (
        SELECT d.id, d.content, d.created_at
        FROM ccc.documents d
        WHERE NOT EXISTS (
            SELECT 1 FROM ccc.event_dashboard ed
            WHERE ed.document_id = d.id
        )
        ORDER BY d.id DESC
        LIMIT coalesce(limit_count, 2147483647)
    ),
    candidates AS (
        SELECT DISTINCT
            docs.id                                            AS document_id,
            ccc.clean_person_candidate(e.canonical_name)      AS person_name,
            coalesce(
                ev.event_date,
                ccc.extract_event_date_from_text(docs.content),
                docs.created_at::date
            )                                                  AS event_date,
            ccc.extract_location_from_text(docs.content)      AS location,
            ccc.extract_impact_from_text(docs.content)        AS impact,
            substring(docs.content FROM 1 FOR 260)            AS event_summary,
            0.520::numeric(4,3)                               AS confidence,
            'rule_entity_document'::text                      AS source_type
        FROM docs
        JOIN ccc.document_entities de ON de.document_id = docs.id
        JOIN ccc.entities e           ON e.id = de.entity_id
        LEFT JOIN ccc.events ev       ON ev.document_id = docs.id
        WHERE ccc.clean_person_candidate(e.canonical_name) IS NOT NULL
    ),
    cleaned AS (
        SELECT document_id, person_name, event_summary,
               max(event_date)                                    AS event_date,
               max(location) FILTER (WHERE location IS NOT NULL)  AS location,
               max(impact)   FILTER (WHERE impact   IS NOT NULL)  AS impact,
               max(confidence)                                    AS confidence,
               max(source_type)                                   AS source_type
        FROM candidates
        WHERE NOT ccc.is_person_noise(person_name)
        GROUP BY document_id, person_name, event_summary
    ),
    ins AS (
        INSERT INTO ccc.event_dashboard
            (document_id, person_name, event_date, location,
             impact, event_summary, confidence, source_type)
        SELECT document_id, person_name, event_date, location,
               impact, event_summary, confidence, source_type
        FROM cleaned
        ON CONFLICT (document_id, person_name, event_summary) DO UPDATE
            SET event_date = coalesce(excluded.event_date,
                                      ccc.event_dashboard.event_date),
                location   = coalesce(excluded.location,
                                      ccc.event_dashboard.location),
                impact     = coalesce(excluded.impact,
                                      ccc.event_dashboard.impact)
        RETURNING 1
    )
    SELECT count(*)::int INTO v_inserted FROM ins;

    SELECT count(*)::int INTO v_total FROM ccc.event_dashboard;

    RETURN QUERY SELECT v_inserted, v_total;
END;
$$;


ALTER FUNCTION ccc.refresh_event_dashboard(limit_count integer) OWNER TO postgres;

--
-- Name: resolve_alias(text); Type: FUNCTION; Schema: ccc; Owner: postgres
--

CREATE FUNCTION ccc.resolve_alias(q text) RETURNS TABLE(canonical text, aliases text[])
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
    RETURN QUERY
    SELECT
        a.canonical,
        array_agg(a.alias ORDER BY a.alias_type, a.alias) AS aliases
    FROM ccc.person_aliases a
    WHERE lower(a.alias) = lower(trim(q))
       OR a.canonical ILIKE '%' || q || '%'
    GROUP BY a.canonical
    LIMIT 5;
END;
$$;


ALTER FUNCTION ccc.resolve_alias(q text) OWNER TO postgres;

--
-- Name: safe_entity_insert(text); Type: FUNCTION; Schema: ccc; Owner: postgres
--

CREATE FUNCTION ccc.safe_entity_insert(input_name text) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
DECLARE

    v_norm TEXT;

    v_hash TEXT;

    v_id BIGINT;

BEGIN

    IF input_name IS NULL THEN
        RETURN NULL;
    END IF;

    v_norm := ccc.normalize_entity_name(input_name);

    IF length(v_norm) < 2 THEN
        RETURN NULL;
    END IF;

    v_hash := md5(v_norm);

    SELECT id
    INTO v_id
    FROM ccc.entities
    WHERE name_hash = v_hash;

    IF v_id IS NOT NULL THEN

        UPDATE ccc.entities
        SET mention_count = mention_count + 1
        WHERE id = v_id;

        RETURN v_id;

    END IF;

    INSERT INTO ccc.entities(
        canonical_name,
        normalized_name,
        name_hash,
        mention_count
    )
    VALUES (
        input_name,
        v_norm,
        v_hash,
        1
    )
    RETURNING id INTO v_id;

    RETURN v_id;

END;
$$;


ALTER FUNCTION ccc.safe_entity_insert(input_name text) OWNER TO postgres;

--
-- Name: safe_iso_date(integer, integer, integer); Type: FUNCTION; Schema: ccc; Owner: postgres
--

CREATE FUNCTION ccc.safe_iso_date(_year integer, _month integer, _day integer) RETURNS date
    LANGUAGE plpgsql IMMUTABLE
    AS $$
BEGIN
    RETURN make_date(_year, _month, _day);
EXCEPTION WHEN OTHERS THEN
    RETURN NULL;
END;
$$;


ALTER FUNCTION ccc.safe_iso_date(_year integer, _month integer, _day integer) OWNER TO postgres;

--
-- Name: search_ai(text, boolean); Type: FUNCTION; Schema: ccc; Owner: postgres
--

CREATE FUNCTION ccc.search_ai(q text, use_embedding boolean DEFAULT true) RETURNS TABLE(document_id bigint, content text, score double precision, method text)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_q_embedding public.vector;
BEGIN
    IF use_embedding THEN
        BEGIN
            v_q_embedding := ccc.openai_embed_text(q);
            RETURN QUERY
                SELECT sv.document_id, sv.content,
                       sv.similarity::double precision, 'vector'::text
                FROM ccc.search_vector(v_q_embedding, 20) sv;
            RETURN;
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE '向量搜索不可用，回退到关键词搜索。原因：%', SQLERRM;
        END;
    END IF;

    RETURN QUERY
        SELECT sk.document_id, sk.content,
               sk.rank_score::double precision, 'keyword'::text
        FROM ccc.search_keyword(q) sk;
END;
$$;


ALTER FUNCTION ccc.search_ai(q text, use_embedding boolean) OWNER TO postgres;

--
-- Name: search_keyword(text); Type: FUNCTION; Schema: ccc; Owner: postgres
--

CREATE FUNCTION ccc.search_keyword(keyword text) RETURNS TABLE(document_id bigint, content text, rank_score real)
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
    RETURN QUERY
    SELECT
        d.id,
        d.content,
        greatest(
            public.similarity(d.content, keyword),
            CASE WHEN d.content ILIKE '%' || keyword || '%' THEN 1.0 ELSE 0.0 END
        )::real AS rank_score
    FROM ccc.documents d
    WHERE d.content ILIKE '%' || keyword || '%'
       OR public.similarity(d.content, keyword) > 0.08
    ORDER BY rank_score DESC, d.id DESC
    LIMIT 50;
END;
$$;


ALTER FUNCTION ccc.search_keyword(keyword text) OWNER TO postgres;

--
-- Name: search_keyword_preview(text, integer); Type: FUNCTION; Schema: ccc; Owner: postgres
--

CREATE FUNCTION ccc.search_keyword_preview(q text, limit_count integer DEFAULT 50) RETURNS TABLE(document_id bigint, rank_score real, created_at timestamp without time zone, preview text)
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
    RETURN QUERY
    SELECT
        s.document_id,
        s.rank_score,
        d.created_at,
        substring(
            d.content
            FROM greatest(1, nullif(strpos(lower(d.content), lower(q)), 0) - 100)
            FOR 300
        ) AS preview
    FROM ccc.search_keyword(q) s
    JOIN ccc.documents d ON d.id = s.document_id
    ORDER BY s.rank_score DESC, s.document_id DESC
    LIMIT limit_count;
END;
$$;


ALTER FUNCTION ccc.search_keyword_preview(q text, limit_count integer) OWNER TO postgres;

--
-- Name: search_router_v3_local(text); Type: FUNCTION; Schema: ccc; Owner: postgres
--

CREATE FUNCTION ccc.search_router_v3_local(p_q text) RETURNS jsonb
    LANGUAGE sql STABLE
    AS $$
WITH
input AS (
  SELECT
    trim(p_q) AS raw_q,
    lower(trim(p_q)) AS q_norm
),

resolved AS (
  SELECT *
  FROM ccc.entity_resolve_v3_local(p_q)
  WHERE confidence >= 0.55
),

resolved_ids AS (
  SELECT array_agg(entity_id) AS ids
  FROM resolved
),

resolved_entities_json AS (
  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'canonical_name', canonical_name,
        'entity_id', entity_id,
        'match_type', match_type,
        'confidence', confidence,
        'entity_type', entity_type
      )
      ORDER BY confidence DESC, canonical_name
    ),
    '[]'::jsonb
  ) AS data
  FROM resolved
),

entity_document_hits AS (
  SELECT
    d.id AS document_id,
    left(COALESCE(d.content, ''), 500) AS content_preview,
    MAX(LEAST(1.0, 0.75 + COALESCE(cde.frequency, 1) * 0.03))::double precision AS entity_score,
    0.0::double precision AS keyword_score,
    0.0::double precision AS graph_score,
    'entity_document'::text AS method
  FROM ccc.clean_document_entities cde
  JOIN ccc.documents d ON d.id = cde.document_id
  WHERE cde.entity_id IN (SELECT entity_id FROM resolved)
  GROUP BY d.id, d.content
),

keyword_document_hits AS (
  SELECT
    d.id AS document_id,
    left(COALESCE(d.content, ''), 500) AS content_preview,
    0.0::double precision AS entity_score,
    GREATEST(
      CASE
        WHEN d.content ILIKE '%' || (SELECT raw_q FROM input) || '%'
        THEN 0.55
        ELSE 0.0
      END,
      LEAST(0.45, public.similarity(lower(COALESCE(d.content, '')), (SELECT q_norm FROM input))::double precision)
    ) AS keyword_score,
    0.0::double precision AS graph_score,
    'keyword'::text AS method
  FROM ccc.documents d
  WHERE char_length((SELECT raw_q FROM input)) >= 2
    AND (
      d.content ILIKE '%' || (SELECT raw_q FROM input) || '%'
      OR public.similarity(lower(COALESCE(d.content, '')), (SELECT q_norm FROM input)) > 0.08
    )
),

graph_neighbors AS (
  SELECT
    CASE
      WHEN e.source_entity_id IN (SELECT entity_id FROM resolved)
      THEN e.target_entity_id
      ELSE e.source_entity_id
    END AS neighbor_entity_id,

    CASE
      WHEN e.source_entity_id IN (SELECT entity_id FROM resolved)
      THEN e.source_entity_id
      ELSE e.target_entity_id
    END AS root_entity_id,

    e.relation_type,
    e.relation_label,
    e.relation_direction,
    e.weight,
    e.document_count,
    e.causal_weight,
    e.pressure,
    e.direction
  FROM ccc.clean_graph_edges e
  WHERE e.source_entity_id IN (SELECT entity_id FROM resolved)
     OR e.target_entity_id IN (SELECT entity_id FROM resolved)
),

graph_neighbors_ranked AS (
  SELECT
    gn.*,
    ce.canonical_name AS neighbor_name,
    ce.entity_type AS neighbor_type,
    LEAST(
      1.0,
      COALESCE(gn.weight, 0.0) / 10.0
    )::double precision AS graph_score
  FROM graph_neighbors gn
  JOIN ccc.clean_entities ce ON ce.id = gn.neighbor_entity_id
),

graph_document_hits AS (
  SELECT
    d.id AS document_id,
    left(COALESCE(d.content, ''), 500) AS content_preview,
    0.0::double precision AS entity_score,
    0.0::double precision AS keyword_score,
    MAX(LEAST(0.75, gnr.graph_score * 0.75))::double precision AS graph_score,
    'graph_document'::text AS method
  FROM graph_neighbors_ranked gnr
  JOIN ccc.clean_document_entities cde
    ON cde.entity_id = gnr.neighbor_entity_id
  JOIN ccc.documents d
    ON d.id = cde.document_id
  GROUP BY d.id, d.content
),

all_document_hits AS (
  SELECT * FROM entity_document_hits
  UNION ALL
  SELECT * FROM keyword_document_hits
  UNION ALL
  SELECT * FROM graph_document_hits
),

document_scored AS (
  SELECT
    document_id,
    MAX(content_preview) AS content_preview,
    MAX(entity_score)::double precision AS entity_score,
    MAX(keyword_score)::double precision AS keyword_score,
    MAX(graph_score)::double precision AS graph_score,
    array_agg(DISTINCT method ORDER BY method) AS methods,
    LEAST(
      1.0,
      MAX(entity_score) * 0.50 +
      MAX(graph_score)  * 0.30 +
      MAX(keyword_score) * 0.20
    )::double precision AS final_score
  FROM all_document_hits
  GROUP BY document_id
),

document_hits_json AS (
  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'document_id', document_id,
        'content_preview', content_preview,
        'entity_score', entity_score,
        'keyword_score', keyword_score,
        'graph_score', graph_score,
        'final_score', final_score,
        'methods', methods
      )
      ORDER BY final_score DESC, document_id DESC
    ),
    '[]'::jsonb
  ) AS data
  FROM (
    SELECT *
    FROM document_scored
    ORDER BY final_score DESC, document_id DESC
    LIMIT 20
  ) x
),

graph_neighbors_json AS (
  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'neighbor_entity_id', neighbor_entity_id,
        'neighbor_name', neighbor_name,
        'neighbor_type', neighbor_type,
        'relation_type', relation_type,
        'relation_label', relation_label,
        'relation_direction', relation_direction,
        'weight', weight,
        'document_count', document_count,
        'causal_weight', causal_weight,
        'pressure', pressure,
        'direction', direction,
        'graph_score', graph_score
      )
      ORDER BY graph_score DESC, neighbor_name
    ),
    '[]'::jsonb
  ) AS data
  FROM (
    SELECT *
    FROM graph_neighbors_ranked
    ORDER BY graph_score DESC, neighbor_name
    LIMIT 25
  ) x
),

active_signals_json AS (
  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'id', s.id,
        'entity_id', s.entity_id,
        'entity_profile_id', s.entity_profile_id,
        'signal_type', s.signal_type,
        'signal_text', s.signal_text,
        'strength', s.strength,
        'triggered_at', s.triggered_at,
        'expires_at', s.expires_at,
        'trigger_condition', s.trigger_condition,
        'pressure_delta', s.pressure_delta,
        'linked_prediction', s.linked_prediction,
        'source_label', s.source_label
      )
      ORDER BY s.strength DESC, s.triggered_at DESC
    ),
    '[]'::jsonb
  ) AS data
  FROM ccc.signals s
  WHERE s.is_active = true
    AND (
      s.entity_id IN (SELECT entity_id FROM resolved)
      OR s.entity_profile_id IN (
        SELECT ep.id
        FROM ccc.entity_profiles ep
        JOIN resolved r
          ON lower(ep.entity_name) = lower(r.canonical_name)
      )
    )
),

contradictions_json AS (
  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'id', ce.id,
        'entity_id', ce.entity_id,
        'entity_name', ce.entity_name,
        'official_narrative', ce.official_narrative,
        'counter_signals', ce.counter_signals,
        'real_indicators', ce.real_indicators,
        'narrative_gap', ce.narrative_gap,
        'confidence_decay', ce.confidence_decay,
        'severity', ce.severity,
        'source_labels', ce.source_labels,
        'trust_levels', ce.trust_levels,
        'last_updated', ce.last_updated
      )
      ORDER BY ce.narrative_gap DESC, ce.id DESC
    ),
    '[]'::jsonb
  ) AS data
  FROM ccc.contradiction_engine ce
  WHERE ce.is_active = true
    AND (
      ce.entity_id IN (SELECT entity_id FROM resolved)
      OR lower(ce.entity_name) IN (
        SELECT lower(canonical_name)
        FROM resolved
      )
    )
),

debug_json AS (
  SELECT jsonb_build_object(
    'version', 'search_router_v3_local_v0',
    'query', (SELECT raw_q FROM input),
    'resolved_count', (SELECT count(*) FROM resolved),
    'document_hit_count', (SELECT count(*) FROM document_scored),
    'graph_neighbor_count', (SELECT count(*) FROM graph_neighbors_ranked),
    'active_signal_count', jsonb_array_length((SELECT data FROM active_signals_json)),
    'contradiction_count', jsonb_array_length((SELECT data FROM contradictions_json)),
    'scoring', jsonb_build_object(
      'entity_document', 0.50,
      'graph_document', 0.30,
      'keyword_document', 0.20,
      'vector', 'disabled_in_v0',
      'source_weight', 'disabled_in_v0',
      'p7_forecast', 'disabled_in_v0'
    )
  ) AS data
)

SELECT jsonb_build_object(
  'ok', true,
  'version', 'search_router_v3_local_v0',
  'query', (SELECT raw_q FROM input),
  'generated_at', now(),
  'resolved_entities', (SELECT data FROM resolved_entities_json),
  'document_hits', (SELECT data FROM document_hits_json),
  'graph_neighbors', (SELECT data FROM graph_neighbors_json),
  'active_signals', (SELECT data FROM active_signals_json),
  'contradictions', (SELECT data FROM contradictions_json),
  'debug', (SELECT data FROM debug_json)
);
$$;


ALTER FUNCTION ccc.search_router_v3_local(p_q text) OWNER TO postgres;

--
-- Name: search_router_v3_local_forecast(text); Type: FUNCTION; Schema: ccc; Owner: postgres
--

CREATE FUNCTION ccc.search_router_v3_local_forecast(p_q text) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
  v_search jsonb;
  v_forecasts jsonb := '[]'::jsonb;
  v_primary jsonb := '{}'::jsonb;
BEGIN
  v_search := ccc.search_router_v3_local(p_q);

  WITH resolved AS (
    SELECT
      x.value AS ent,
      x.value->>'canonical_name' AS canonical_name,
      COALESCE((x.value->>'confidence')::double precision, 0) AS resolve_confidence
    FROM jsonb_array_elements(v_search->'resolved_entities') x(value)
  ),
  forecasted AS (
    SELECT
      r.canonical_name,
      r.resolve_confidence,
      ccc.forecast_v1_1(r.canonical_name) AS forecast
    FROM resolved r
  ),
  valid AS (
    SELECT *
    FROM forecasted
    WHERE COALESCE((forecast->>'ok')::boolean, false) = true
  )
  SELECT
    COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'entity', canonical_name,
          'resolve_confidence', resolve_confidence,
          'forecast', forecast
        )
        ORDER BY resolve_confidence DESC
      ),
      '[]'::jsonb
    )
  INTO v_forecasts
  FROM valid;

  SELECT COALESCE(value, '{}'::jsonb)
  INTO v_primary
  FROM jsonb_array_elements(v_forecasts) value
  LIMIT 1;

  RETURN jsonb_build_object(
    'ok', true,
    'version', 'search_router_v3_local_forecast_v0',
    'query', p_q,
    'generated_at', now(),

    'search', v_search,
    'forecasts', v_forecasts,

    'primary_entity', v_primary->>'entity',

    'final_result',
    CASE
      WHEN v_primary = '{}'::jsonb THEN
        jsonb_build_object(
          'status', 'NO_FORECAST_PROFILE',
          'decision', NULL,
          'confidence', NULL,
          'summary', 'Search succeeded, but no resolved entity has a forecast profile.'
        )
      ELSE
        jsonb_build_object(
          'status', 'FORECAST_ATTACHED',
          'entity', v_primary->>'entity',
          'decision', v_primary #>> '{forecast,decision}',
          'route_profile', v_primary #>> '{forecast,route_profile}',
          'option_a', v_primary #>> '{forecast,panel_3_forecast,option_a}',
          'option_b', v_primary #>> '{forecast,panel_3_forecast,option_b}',
          'confidence', v_primary #>> '{forecast,panel_3_forecast,confidence}',
          'total_force', v_primary #>> '{forecast,panel_4_signal_alignment,total_force}',
          'evidence_score', v_primary #>> '{forecast,panel_4_signal_alignment,evidence_score}',
          'summary',
            concat(
              v_primary->>'entity',
              ' forecast attached: decision=',
              v_primary #>> '{forecast,decision}',
              ', confidence=',
              v_primary #>> '{forecast,panel_3_forecast,confidence}'
            )
        )
    END
  );
END;
$$;


ALTER FUNCTION ccc.search_router_v3_local_forecast(p_q text) OWNER TO postgres;

--
-- Name: search_router_v3_local_forecast_trust_v3(text); Type: FUNCTION; Schema: ccc; Owner: postgres
--

CREATE FUNCTION ccc.search_router_v3_local_forecast_trust_v3(p_q text) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
  v_search    jsonb;
  v_forecasts jsonb := '[]'::jsonb;
  v_panels    jsonb := '[]'::jsonb;
  v_primary   jsonb := '{}'::jsonb;
  v_primary_panel jsonb := '{}'::jsonb;
BEGIN
  v_search := ccc.search_router_v3_local(p_q);

  -- Forecast layer
  WITH resolved AS (
    SELECT
      x.value->>'canonical_name'                              AS canonical_name,
      COALESCE((x.value->>'confidence')::double precision, 0) AS resolve_confidence
    FROM jsonb_array_elements(v_search->'resolved_entities') x(value)
  ),
  forecasted AS (
    SELECT
      r.canonical_name,
      r.resolve_confidence,
      ccc.forecast_v1_1_trust_v3(r.canonical_name) AS forecast
    FROM resolved r
  ),
  valid AS (
    SELECT * FROM forecasted
    WHERE COALESCE((forecast->>'ok')::boolean, false) = true
  )
  SELECT
    COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'entity',             canonical_name,
          'resolve_confidence', resolve_confidence,
          'forecast',           forecast
        )
        ORDER BY resolve_confidence DESC
      ),
      '[]'::jsonb
    )
  INTO v_forecasts
  FROM valid;

  -- Panel layer
  WITH resolved AS (
    SELECT
      x.value->>'canonical_name'                              AS canonical_name,
      COALESCE((x.value->>'confidence')::double precision, 0) AS resolve_confidence
    FROM jsonb_array_elements(v_search->'resolved_entities') x(value)
  ),
  paneled AS (
    SELECT
      r.canonical_name,
      r.resolve_confidence,
      ccc.prediction_panel_v1(r.canonical_name) AS panel
    FROM resolved r
  ),
  valid AS (
    SELECT * FROM paneled
    WHERE COALESCE((panel->>'ok')::boolean, false) = true
  )
  SELECT
    COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'entity',             canonical_name,
          'resolve_confidence', resolve_confidence,
          'panel',              panel
        )
        ORDER BY resolve_confidence DESC
      ),
      '[]'::jsonb
    )
  INTO v_panels
  FROM valid;

  SELECT COALESCE(value, '{}'::jsonb)
  INTO v_primary
  FROM jsonb_array_elements(v_forecasts) value
  LIMIT 1;

  SELECT COALESCE(value, '{}'::jsonb)
  INTO v_primary_panel
  FROM jsonb_array_elements(v_panels) value
  LIMIT 1;

  RETURN jsonb_build_object(
    'ok',           true,
    'version',      'search_router_v3_local_forecast_trust_v3',
    'query',        p_q,
    'generated_at', now(),

    'search',       v_search,
    'forecasts',    v_forecasts,
    'panels',       v_panels,

    'primary_entity', v_primary->>'entity',

    'final_result',
    CASE
      WHEN v_primary = '{}'::jsonb THEN
        jsonb_build_object(
          'status',     'NO_FORECAST_PROFILE',
          'decision',   NULL,
          'confidence', NULL,
          'summary',    'Search succeeded, but no resolved entity has a forecast profile.'
        )
      ELSE
        jsonb_build_object(
          'status',        'FORECAST_ATTACHED',
          'entity',        v_primary->>'entity',
          'trust_model',   'source_effective_weight_v3',
          'decision',      v_primary #>> '{forecast,decision}',
          'route_profile', v_primary #>> '{forecast,route_profile}',
          'option_a',      v_primary #>> '{forecast,panel_3_forecast,option_a}',
          'option_b',      v_primary #>> '{forecast,panel_3_forecast,option_b}',
          'confidence',    v_primary #>> '{forecast,panel_3_forecast,confidence}',
          'total_force',   v_primary #>> '{forecast,panel_4_signal_alignment,total_force}',
          'evidence_score', v_primary #>> '{forecast,panel_4_signal_alignment,evidence_score}',
          'pressure_label', v_primary_panel #>> '{panel,card_1_pressure,pressure,label}',
          'alert_level',   v_primary_panel #>> '{panel,card_3_contradiction,top,alert_level}',
          'trajectory',    v_primary_panel #>> '{panel,card_2_timeline,trajectory,label}',
          'summary',
            concat(
              v_primary->>'entity',
              ' | trust_v3 | decision=',
              v_primary #>> '{forecast,decision}',
              ' | confidence=',
              v_primary #>> '{forecast,panel_3_forecast,confidence}',
              ' | pressure=',
              v_primary_panel #>> '{panel,card_1_pressure,pressure,label}',
              ' | trajectory=',
              v_primary_panel #>> '{panel,card_2_timeline,trajectory,label}'
            )
        )
    END
  );
END;
$$;


ALTER FUNCTION ccc.search_router_v3_local_forecast_trust_v3(p_q text) OWNER TO postgres;

--
-- Name: search_vector(public.vector, integer); Type: FUNCTION; Schema: ccc; Owner: postgres
--

CREATE FUNCTION ccc.search_vector(query_embedding public.vector, match_count integer DEFAULT 10) RETURNS TABLE(document_id bigint, content text, similarity numeric)
    LANGUAGE sql
    AS $$
    SELECT
        id,
        left(content, 800),
        1 - (embedding <=> query_embedding)
    FROM ccc.documents
    WHERE embedding IS NOT NULL
    ORDER BY embedding <=> query_embedding
    LIMIT match_count;
$$;


ALTER FUNCTION ccc.search_vector(query_embedding public.vector, match_count integer) OWNER TO postgres;

--
-- Name: source_effective_weight(text, text, text); Type: FUNCTION; Schema: ccc; Owner: postgres
--

CREATE FUNCTION ccc.source_effective_weight(p_source_name text, p_domain text DEFAULT NULL::text, p_context text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE sql STABLE
    AS $$
  SELECT ccc.source_effective_weight_v2(p_source_name, p_domain, p_context, false);
$$;


ALTER FUNCTION ccc.source_effective_weight(p_source_name text, p_domain text, p_context text) OWNER TO postgres;

--
-- Name: source_effective_weight_v2(text, text, text, boolean); Type: FUNCTION; Schema: ccc; Owner: postgres
--

CREATE FUNCTION ccc.source_effective_weight_v2(p_source_name text, p_domain text DEFAULT NULL::text, p_context text DEFAULT NULL::text, p_save_eval boolean DEFAULT false) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
  v_source                  ccc.source_profiles%ROWTYPE;
  v_domain_auth             float := 0.5;
  v_bias_penalty            float := 0.0;
  v_tier_weight             float := 0.5;
  v_reliability             float := 0.5;
  v_historical              float := 0.5;
  v_predictive              float := 0.5;
  v_use_mode                text;
  v_signal_type             text;

  v_fact_weight             float := 0.0;
  v_narrative_signal_weight float := 0.0;
  v_pattern_signal_weight   float := 0.0;
  v_prediction_weight       float := 0.0;
  v_reverse_weight          float := 0.0;
  v_final                   float := 0.0;
  v_result                  jsonb;
BEGIN
  SELECT *
  INTO v_source
  FROM ccc.source_profiles
  WHERE lower(source_name) = lower(p_source_name)
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'error', 'source not found',
      'source', p_source_name
    );
  END IF;

  v_use_mode := coalesce(v_source.use_as, 'unknown');
  v_signal_type := coalesce(v_source.signal_type, 'linear');
  v_reliability := coalesce(v_source.reliability_score, 0.5);
  v_historical := coalesce(v_source.historical_accuracy, 0.5);
  v_predictive := coalesce(v_source.predictive_reliability, 0.5);

  v_tier_weight := CASE v_source.trust_tier
    WHEN 'T0' THEN 0.95
    WHEN 'T1' THEN 0.85
    WHEN 'T2' THEN 0.70
    WHEN 'T3' THEN 0.55
    WHEN 'T4' THEN 0.50
    WHEN 'T5' THEN 0.88
    WHEN 'T6' THEN 0.20
    ELSE 0.50
  END;

  IF p_domain IS NOT NULL THEN
    SELECT coalesce(avg(authority_score), 0.5)
    INTO v_domain_auth
    FROM ccc.source_domain_authority sda
    WHERE sda.source_id = v_source.id
      AND (
        lower(sda.domain) ILIKE '%' || lower(p_domain) || '%'
        OR lower(p_domain) ILIKE '%' || lower(sda.domain) || '%'
      );

    SELECT coalesce(avg(bias_strength) * 0.30, 0.0)
    INTO v_bias_penalty
    FROM ccc.source_bias_vectors sbv
    WHERE sbv.source_id = v_source.id
      AND (
        lower(sbv.domain) ILIKE '%' || lower(p_domain) || '%'
        OR lower(p_domain) ILIKE '%' || lower(sbv.domain) || '%'
      );
  END IF;

  -- ------------------------------------------------------------
  -- Channel 1: fact_weight
  -- 事实采用权重。primary + linear + strong domain authority benefits.
  -- reverse_indicator and nonlinear are strongly discounted as direct facts.
  -- ------------------------------------------------------------
  v_fact_weight := LEAST(1.0, GREATEST(0.0,
    v_tier_weight * 0.30 +
    v_reliability * 0.30 +
    v_historical * 0.20 +
    v_domain_auth * 0.20 -
    v_bias_penalty -
    CASE
      WHEN v_use_mode = 'reverse_indicator' THEN 0.22
      ELSE 0
    END -
    CASE
      WHEN v_signal_type = 'nonlinear' THEN 0.35
      WHEN v_signal_type = 'behavioral' AND v_use_mode <> 'primary' THEN 0.12
      ELSE 0
    END
  ));

  -- ------------------------------------------------------------
  -- Channel 2: narrative_signal_weight
  -- 叙事信号权重。reverse_indicator / behavioral sources gain value here.
  -- It is not truth weight; it measures narrative intention/pressure.
  -- ------------------------------------------------------------
  v_narrative_signal_weight := LEAST(1.0, GREATEST(0.0,
    v_tier_weight * 0.18 +
    v_reliability * 0.12 +
    v_domain_auth * 0.25 +
    v_historical * 0.10 +
    v_predictive * 0.10 +
    CASE
      WHEN v_use_mode = 'reverse_indicator' THEN 0.22
      WHEN v_use_mode = 'pattern_signal' THEN 0.10
      ELSE 0.04
    END +
    CASE
      WHEN v_signal_type = 'behavioral' THEN 0.12
      ELSE 0
    END
  ));

  -- ------------------------------------------------------------
  -- Channel 3: pattern_signal_weight
  -- 模式信号权重。T0 nonlinear is valuable here, not as direct fact.
  -- ------------------------------------------------------------
  v_pattern_signal_weight := LEAST(1.0, GREATEST(0.0,
    v_tier_weight * 0.20 +
    v_reliability * 0.12 +
    v_historical * 0.20 +
    v_predictive * 0.18 +
    v_domain_auth * 0.10 +
    CASE
      WHEN v_use_mode = 'pattern_signal' THEN 0.20
      ELSE 0
    END +
    CASE
      WHEN v_signal_type = 'nonlinear' THEN 0.18
      WHEN v_signal_type = 'behavioral' THEN 0.08
      ELSE 0
    END
  ));

  -- ------------------------------------------------------------
  -- Channel 4: prediction_weight
  -- 预判权重。predictive reliability + historical accuracy dominate.
  -- ------------------------------------------------------------
  v_prediction_weight := LEAST(1.0, GREATEST(0.0,
    v_predictive * 0.35 +
    v_historical * 0.25 +
    v_domain_auth * 0.20 +
    v_tier_weight * 0.10 +
    v_reliability * 0.10 -
    v_bias_penalty * 0.50
  ));

  -- ------------------------------------------------------------
  -- Channel 5: reverse_indicator_weight
  -- 反向指标权重。Measures usefulness for detecting agenda/conflict.
  -- High bias may increase signal value here, not reduce it.
  -- ------------------------------------------------------------
  v_reverse_weight := LEAST(1.0, GREATEST(0.0,
    v_domain_auth * 0.22 +
    v_reliability * 0.12 +
    v_historical * 0.10 +
    v_tier_weight * 0.10 +
    CASE
      WHEN v_use_mode = 'reverse_indicator' THEN 0.28
      ELSE 0.02
    END +
    CASE
      WHEN v_signal_type = 'behavioral' THEN 0.15
      ELSE 0
    END +
    LEAST(v_bias_penalty * 1.5, 0.13)
  ));

  -- ------------------------------------------------------------
  -- Final effective weight:
  -- Not "truth". It is routing-level usefulness for RSAL.
  -- ------------------------------------------------------------
  v_final := CASE
    WHEN v_use_mode = 'primary' THEN
      LEAST(1.0, GREATEST(0.0,
        v_fact_weight * 0.55 +
        v_prediction_weight * 0.20 +
        v_narrative_signal_weight * 0.15 +
        v_pattern_signal_weight * 0.10
      ))
    WHEN v_use_mode = 'reverse_indicator' THEN
      LEAST(1.0, GREATEST(0.0,
        v_reverse_weight * 0.45 +
        v_narrative_signal_weight * 0.35 +
        v_prediction_weight * 0.15 +
        v_fact_weight * 0.05
      ))
    WHEN v_use_mode = 'pattern_signal' THEN
      LEAST(1.0, GREATEST(0.0,
        v_pattern_signal_weight * 0.50 +
        v_prediction_weight * 0.25 +
        v_narrative_signal_weight * 0.20 +
        v_fact_weight * 0.05
      ))
    ELSE
      LEAST(1.0, GREATEST(0.0,
        v_fact_weight * 0.35 +
        v_narrative_signal_weight * 0.25 +
        v_pattern_signal_weight * 0.20 +
        v_prediction_weight * 0.20
      ))
  END;

  v_result := jsonb_build_object(
    'source', v_source.source_name,
    'tier', v_source.trust_tier,
    'use_as', v_use_mode,
    'signal_type', v_signal_type,
    'domain', p_domain,
    'context', p_context,
    'components', jsonb_build_object(
      'tier_weight', v_tier_weight,
      'reliability', v_reliability,
      'historical_accuracy', v_historical,
      'predictive_reliability', v_predictive,
      'domain_authority', v_domain_auth,
      'bias_penalty', v_bias_penalty
    ),
    'weights', jsonb_build_object(
      'fact_weight', v_fact_weight,
      'narrative_signal_weight', v_narrative_signal_weight,
      'pattern_signal_weight', v_pattern_signal_weight,
      'prediction_weight', v_prediction_weight,
      'reverse_indicator_weight', v_reverse_weight,
      'final_effective_weight', v_final
    ),
    'interpretation', jsonb_build_object(
      'fact', CASE
        WHEN v_fact_weight >= 0.75 THEN '可作为强事实源'
        WHEN v_fact_weight >= 0.55 THEN '可作为辅助事实源'
        ELSE '不宜直接作为事实源'
      END,
      'narrative', CASE
        WHEN v_narrative_signal_weight >= 0.70 THEN '强叙事/意图信号'
        WHEN v_narrative_signal_weight >= 0.50 THEN '中等叙事信号'
        ELSE '弱叙事信号'
      END,
      'pattern', CASE
        WHEN v_pattern_signal_weight >= 0.70 THEN '强模式信号'
        WHEN v_pattern_signal_weight >= 0.50 THEN '中等模式信号'
        ELSE '弱模式信号'
      END,
      'routing', CASE v_use_mode
        WHEN 'primary' THEN '进入事实与证据通道'
        WHEN 'reverse_indicator' THEN '进入叙事冲突与反向指标通道'
        WHEN 'pattern_signal' THEN '进入模式识别与预警通道'
        ELSE '进入混合低置信通道'
      END
    )
  );

  IF p_save_eval THEN
    INSERT INTO ccc.source_weight_evaluations(
      source_id, source_name, domain, context, trust_tier, use_as, signal_type,
      tier_weight, reliability_score, historical_accuracy, predictive_reliability,
      domain_authority, bias_penalty,
      fact_weight, narrative_signal_weight, pattern_signal_weight,
      prediction_weight, reverse_indicator_weight, final_effective_weight,
      result
    )
    VALUES (
      v_source.id, v_source.source_name, p_domain, p_context, v_source.trust_tier, v_use_mode, v_signal_type,
      v_tier_weight, v_reliability, v_historical, v_predictive,
      v_domain_auth, v_bias_penalty,
      v_fact_weight, v_narrative_signal_weight, v_pattern_signal_weight,
      v_prediction_weight, v_reverse_weight, v_final,
      v_result
    );
  END IF;

  RETURN v_result;
END;
$$;


ALTER FUNCTION ccc.source_effective_weight_v2(p_source_name text, p_domain text, p_context text, p_save_eval boolean) OWNER TO postgres;

--
-- Name: source_effective_weight_v3(text, text, text); Type: FUNCTION; Schema: ccc; Owner: postgres
--

CREATE FUNCTION ccc.source_effective_weight_v3(p_source_name text, p_domain text DEFAULT NULL::text, p_context text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE sql STABLE
    AS $$
  WITH calc AS (
    SELECT
      base,
      rule,
      base->>'use_as' AS use_as,
      (base->'weights'->>'final_effective_weight')::double precision AS v2_final,
      (rule->>'rule_weight')::double precision AS rule_weight
    FROM
      ccc.source_effective_weight_v2(p_source_name, p_domain, p_context, false) base,
      ccc.source_rule_weight_v1(p_source_name, p_domain, p_context) rule
  ),
  fused AS (
    SELECT
      *,
      CASE use_as
        WHEN 'primary' THEN
          ROUND((v2_final * 0.75 + rule_weight * 0.25)::numeric, 4)
        WHEN 'reverse_indicator' THEN
          ROUND((v2_final * 0.70 + rule_weight * 0.30)::numeric, 4)
        WHEN 'pattern_signal' THEN
          ROUND((v2_final * 0.55 + rule_weight * 0.45)::numeric, 4)
        ELSE
          ROUND((v2_final * 0.75 + rule_weight * 0.25)::numeric, 4)
      END AS v3_final
    FROM calc
  )
  SELECT
    base ||
    jsonb_build_object(
      'rule_layer', rule,
      'trust_fusion', jsonb_build_object(
        'model', 'source_effective_weight_v3_channel_rule_fusion',
        'primary_formula', 'v2 * 0.75 + rule * 0.25',
        'reverse_indicator_formula', 'v2 * 0.70 + rule * 0.30',
        'pattern_signal_formula', 'v2 * 0.55 + rule * 0.45'
      ),
      'weights',
      (base->'weights') ||
      jsonb_build_object(
        'rule_weight', rule_weight,
        'final_effective_weight_v3', v3_final
      )
    )
  FROM fused;
$$;


ALTER FUNCTION ccc.source_effective_weight_v3(p_source_name text, p_domain text, p_context text) OWNER TO postgres;

--
-- Name: source_rule_weight_v1(text, text, text); Type: FUNCTION; Schema: ccc; Owner: postgres
--

CREATE FUNCTION ccc.source_rule_weight_v1(p_source_name text, p_domain text DEFAULT NULL::text, p_context text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
  v_source ccc.source_profiles%ROWTYPE;

  v_control_power double precision := 0.50;
  v_signal_cost   double precision := 0.50;
  v_conflict_value double precision := 0.50;
  v_rule_weight   double precision := 0.50;
BEGIN
  SELECT *
  INTO v_source
  FROM ccc.source_profiles
  WHERE lower(source_name) = lower(p_source_name)
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'error', 'source not found',
      'source', p_source_name
    );
  END IF;

  -- 1. control_power：谁能影响规则/政策/资源分配
  v_control_power := CASE
    WHEN v_source.source_type = 'official' THEN 0.90
    WHEN v_source.source_type = 'think_tank' THEN 0.78
    WHEN v_source.source_type = 'economic' THEN 0.82
    WHEN v_source.source_type = 'leak' THEN 0.70
    WHEN v_source.source_type = 'investigation' THEN 0.62
    WHEN v_source.source_type = 'media' THEN 0.45
    WHEN v_source.source_type = 'survey' THEN 0.40
    WHEN v_source.source_type = 'nonlinear' THEN 0.35
    ELSE 0.50
  END;

  -- 2. signal_cost：说谎/造假/行动成本
  v_signal_cost := CASE
    WHEN v_source.source_type = 'leak' THEN 0.92
    WHEN v_source.source_name IN ('AIS船舶数据','卫星图像','国债收益率曲线','CPI/PCE数据','非农就业数据','M2货币供应') THEN 0.90
    WHEN v_source.source_type = 'economic' THEN 0.86
    WHEN v_source.source_type = 'investigation' THEN 0.78
    WHEN v_source.source_type = 'official' THEN 0.42
    WHEN v_source.source_type = 'media' THEN 0.50
    WHEN v_source.source_type = 'think_tank' THEN 0.55
    WHEN v_source.source_type = 'nonlinear' THEN 0.25
    ELSE 0.50
  END;

  -- 3. conflict_value：冲突解释价值；事实冲突和叙事阵营冲突都算冲突
  v_conflict_value := CASE
    WHEN v_source.use_as = 'reverse_indicator' THEN 0.85
    WHEN v_source.use_as = 'pattern_signal' THEN 0.65
    WHEN v_source.use_as = 'primary' THEN 0.55
    ELSE 0.50
  END;

  -- 4. 合成 Rule Weight
  v_rule_weight := LEAST(1.0, GREATEST(0.0,
    v_control_power * 0.35 +
    v_signal_cost * 0.35 +
    v_conflict_value * 0.30
  ));

  RETURN jsonb_build_object(
    'source', v_source.source_name,
    'source_type', v_source.source_type,
    'use_as', v_source.use_as,
    'trust_tier', v_source.trust_tier,
    'rule_components', jsonb_build_object(
      'control_power', round(v_control_power::numeric, 4),
      'signal_cost', round(v_signal_cost::numeric, 4),
      'conflict_value', round(v_conflict_value::numeric, 4)
    ),
    'rule_weight', round(v_rule_weight::numeric, 4),
    'interpretation', CASE
      WHEN v_rule_weight >= 0.75 THEN '强规则信号源'
      WHEN v_rule_weight >= 0.55 THEN '中等规则信号源'
      ELSE '弱规则信号源'
    END
  );
END;
$$;


ALTER FUNCTION ccc.source_rule_weight_v1(p_source_name text, p_domain text, p_context text) OWNER TO postgres;

--
-- Name: trg_auto_refresh_dashboard(); Type: FUNCTION; Schema: ccc; Owner: postgres
--

CREATE FUNCTION ccc.trg_auto_refresh_dashboard() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    PERFORM ccc.refresh_event_dashboard(1);
    RETURN NEW;
END;
$$;


ALTER FUNCTION ccc.trg_auto_refresh_dashboard() OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: behavioral_models; Type: TABLE; Schema: ccc; Owner: postgres
--

CREATE TABLE ccc.behavioral_models (
    id bigint NOT NULL,
    entity_profile_id bigint,
    entity_name text NOT NULL,
    trigger_conditions text[] NOT NULL,
    trigger_threshold double precision DEFAULT 0.6,
    predicted_action text NOT NULL,
    action_type text,
    confidence double precision DEFAULT 0.7,
    historical_accuracy double precision DEFAULT 0.0,
    sample_count integer DEFAULT 0,
    time_horizon text,
    counter_signals text[],
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    CONSTRAINT behavioral_models_action_type_check CHECK ((action_type = ANY (ARRAY['military'::text, 'political'::text, 'economic'::text, 'social'::text, 'media'::text, 'legal'::text, 'withdrawal'::text]))),
    CONSTRAINT behavioral_models_time_horizon_check CHECK ((time_horizon = ANY (ARRAY['immediate'::text, 'short'::text, 'medium'::text, 'long'::text])))
);


ALTER TABLE ccc.behavioral_models OWNER TO postgres;

--
-- Name: behavioral_models_id_seq; Type: SEQUENCE; Schema: ccc; Owner: postgres
--

CREATE SEQUENCE ccc.behavioral_models_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE ccc.behavioral_models_id_seq OWNER TO postgres;

--
-- Name: behavioral_models_id_seq; Type: SEQUENCE OWNED BY; Schema: ccc; Owner: postgres
--

ALTER SEQUENCE ccc.behavioral_models_id_seq OWNED BY ccc.behavioral_models.id;


--
-- Name: causal_edges; Type: TABLE; Schema: ccc; Owner: postgres
--

CREATE TABLE ccc.causal_edges (
    id bigint NOT NULL,
    source_event_id bigint,
    target_event_id bigint,
    causal_type text,
    confidence double precision DEFAULT 0.5,
    time_delta_days integer,
    created_at timestamp with time zone DEFAULT now(),
    temporal_distance integer,
    causality_strength double precision DEFAULT 0.5,
    directional_bias text,
    CONSTRAINT causal_edges_causal_type_check CHECK ((causal_type = ANY (ARRAY['triggers'::text, 'enables'::text, 'contradicts'::text, 'reinforces'::text, 'follows'::text, 'unknown'::text])))
);


ALTER TABLE ccc.causal_edges OWNER TO postgres;

--
-- Name: causal_edges_id_seq; Type: SEQUENCE; Schema: ccc; Owner: postgres
--

CREATE SEQUENCE ccc.causal_edges_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE ccc.causal_edges_id_seq OWNER TO postgres;

--
-- Name: causal_edges_id_seq; Type: SEQUENCE OWNED BY; Schema: ccc; Owner: postgres
--

ALTER SEQUENCE ccc.causal_edges_id_seq OWNED BY ccc.causal_edges.id;


--
-- Name: claims; Type: TABLE; Schema: ccc; Owner: postgres
--

CREATE TABLE ccc.claims (
    id bigint NOT NULL,
    document_id bigint,
    claim_text text,
    confidence numeric DEFAULT 0.5,
    created_at timestamp without time zone DEFAULT now()
);


ALTER TABLE ccc.claims OWNER TO postgres;

--
-- Name: claims_id_seq; Type: SEQUENCE; Schema: ccc; Owner: postgres
--

CREATE SEQUENCE ccc.claims_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE ccc.claims_id_seq OWNER TO postgres;

--
-- Name: claims_id_seq; Type: SEQUENCE OWNED BY; Schema: ccc; Owner: postgres
--

ALTER SEQUENCE ccc.claims_id_seq OWNED BY ccc.claims.id;


--
-- Name: clean_document_entities; Type: TABLE; Schema: ccc; Owner: postgres
--

CREATE TABLE ccc.clean_document_entities (
    id bigint NOT NULL,
    document_id bigint,
    entity_id bigint,
    canonical_name text NOT NULL,
    entity_type text NOT NULL,
    frequency integer DEFAULT 1,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE ccc.clean_document_entities OWNER TO postgres;

--
-- Name: clean_document_entities_id_seq; Type: SEQUENCE; Schema: ccc; Owner: postgres
--

CREATE SEQUENCE ccc.clean_document_entities_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE ccc.clean_document_entities_id_seq OWNER TO postgres;

--
-- Name: clean_document_entities_id_seq; Type: SEQUENCE OWNED BY; Schema: ccc; Owner: postgres
--

ALTER SEQUENCE ccc.clean_document_entities_id_seq OWNED BY ccc.clean_document_entities.id;


--
-- Name: clean_entities; Type: TABLE; Schema: ccc; Owner: postgres
--

CREATE TABLE ccc.clean_entities (
    id bigint NOT NULL,
    canonical_name text NOT NULL,
    entity_type text NOT NULL,
    source text DEFAULT 'staging'::text,
    mention_count integer DEFAULT 0,
    confidence double precision DEFAULT 0.8,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE ccc.clean_entities OWNER TO postgres;

--
-- Name: clean_entities_id_seq; Type: SEQUENCE; Schema: ccc; Owner: postgres
--

CREATE SEQUENCE ccc.clean_entities_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE ccc.clean_entities_id_seq OWNER TO postgres;

--
-- Name: clean_entities_id_seq; Type: SEQUENCE OWNED BY; Schema: ccc; Owner: postgres
--

ALTER SEQUENCE ccc.clean_entities_id_seq OWNED BY ccc.clean_entities.id;


--
-- Name: clean_graph_edges; Type: TABLE; Schema: ccc; Owner: postgres
--

CREATE TABLE ccc.clean_graph_edges (
    id bigint NOT NULL,
    source_entity_id bigint,
    target_entity_id bigint,
    relation_type text DEFAULT 'co_occurrence'::text,
    weight double precision DEFAULT 1.0,
    document_count integer DEFAULT 1,
    created_at timestamp with time zone DEFAULT now(),
    relation_label text,
    relation_direction text DEFAULT 'undirected'::text,
    event_time timestamp with time zone,
    valid_from date,
    valid_to date,
    causal_weight double precision DEFAULT 0.0,
    pressure text,
    direction text,
    updated_at timestamp with time zone DEFAULT now(),
    CONSTRAINT clean_graph_edges_relation_direction_check CHECK ((relation_direction = ANY (ARRAY['undirected'::text, 'source_to_target'::text, 'target_to_source'::text])))
);


ALTER TABLE ccc.clean_graph_edges OWNER TO postgres;

--
-- Name: COLUMN clean_graph_edges.relation_label; Type: COMMENT; Schema: ccc; Owner: postgres
--

COMMENT ON COLUMN ccc.clean_graph_edges.relation_label IS 'family_relation | marriage | political_alignment | political_opposition | 
 organizational_dependency | financial_control | media_influence | 
 mentor_student | colleague | co_accused | investigated_by | co_occurrence';


--
-- Name: COLUMN clean_graph_edges.pressure; Type: COMMENT; Schema: ccc; Owner: postgres
--

COMMENT ON COLUMN ccc.clean_graph_edges.pressure IS 'centralization | decentralization | suppression | expansion | withdrawal | reinforcement';


--
-- Name: COLUMN clean_graph_edges.direction; Type: COMMENT; Schema: ccc; Owner: postgres
--

COMMENT ON COLUMN ccc.clean_graph_edges.direction IS 'upward | downward | lateral | converging | diverging';


--
-- Name: clean_graph_edges_id_seq; Type: SEQUENCE; Schema: ccc; Owner: postgres
--

CREATE SEQUENCE ccc.clean_graph_edges_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE ccc.clean_graph_edges_id_seq OWNER TO postgres;

--
-- Name: clean_graph_edges_id_seq; Type: SEQUENCE OWNED BY; Schema: ccc; Owner: postgres
--

ALTER SEQUENCE ccc.clean_graph_edges_id_seq OWNED BY ccc.clean_graph_edges.id;


--
-- Name: cognitive_edges; Type: TABLE; Schema: ccc; Owner: postgres
--

CREATE TABLE ccc.cognitive_edges (
    id bigint NOT NULL,
    source_node_id bigint,
    target_node_id bigint,
    relation_type text NOT NULL,
    weight double precision DEFAULT 1.0,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT cognitive_edges_relation_type_check CHECK ((relation_type = ANY (ARRAY['supports'::text, 'contradicts'::text, 'derives_from'::text, 'revises'::text, 'triggers'::text, 'co_occurs'::text])))
);


ALTER TABLE ccc.cognitive_edges OWNER TO postgres;

--
-- Name: cognitive_edges_id_seq; Type: SEQUENCE; Schema: ccc; Owner: postgres
--

CREATE SEQUENCE ccc.cognitive_edges_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE ccc.cognitive_edges_id_seq OWNER TO postgres;

--
-- Name: cognitive_edges_id_seq; Type: SEQUENCE OWNED BY; Schema: ccc; Owner: postgres
--

ALTER SEQUENCE ccc.cognitive_edges_id_seq OWNED BY ccc.cognitive_edges.id;


--
-- Name: cognitive_nodes; Type: TABLE; Schema: ccc; Owner: postgres
--

CREATE TABLE ccc.cognitive_nodes (
    id bigint NOT NULL,
    entity_id bigint,
    document_id bigint,
    node_type text NOT NULL,
    content text NOT NULL,
    confidence double precision DEFAULT 0.5,
    confidence_decay double precision DEFAULT 0.0,
    decay_rate double precision DEFAULT 0.01,
    valid_from date,
    valid_until date,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    CONSTRAINT cognitive_nodes_confidence_check CHECK (((confidence >= (0)::double precision) AND (confidence <= (1)::double precision))),
    CONSTRAINT cognitive_nodes_node_type_check CHECK ((node_type = ANY (ARRAY['observation'::text, 'mechanism'::text, 'pattern'::text, 'relation'::text, 'contradiction'::text, 'signal'::text, 'decision'::text, 'outcome'::text])))
);


ALTER TABLE ccc.cognitive_nodes OWNER TO postgres;

--
-- Name: cognitive_nodes_id_seq; Type: SEQUENCE; Schema: ccc; Owner: postgres
--

CREATE SEQUENCE ccc.cognitive_nodes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE ccc.cognitive_nodes_id_seq OWNER TO postgres;

--
-- Name: cognitive_nodes_id_seq; Type: SEQUENCE OWNED BY; Schema: ccc; Owner: postgres
--

ALTER SEQUENCE ccc.cognitive_nodes_id_seq OWNED BY ccc.cognitive_nodes.id;


--
-- Name: contradiction_engine; Type: TABLE; Schema: ccc; Owner: postgres
--

CREATE TABLE ccc.contradiction_engine (
    id bigint NOT NULL,
    entity_id bigint,
    entity_name text NOT NULL,
    official_narrative text NOT NULL,
    counter_signals text[] NOT NULL,
    real_indicators text[],
    narrative_gap double precision DEFAULT 0.0,
    confidence_decay double precision DEFAULT 0.0,
    severity text,
    source_labels text[],
    trust_levels text[],
    last_updated timestamp with time zone DEFAULT now(),
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT contradiction_engine_severity_check CHECK ((severity = ANY (ARRAY['weak'::text, 'moderate'::text, 'strong'::text, 'critical'::text])))
);


ALTER TABLE ccc.contradiction_engine OWNER TO postgres;

--
-- Name: contradiction_engine_id_seq; Type: SEQUENCE; Schema: ccc; Owner: postgres
--

CREATE SEQUENCE ccc.contradiction_engine_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE ccc.contradiction_engine_id_seq OWNER TO postgres;

--
-- Name: contradiction_engine_id_seq; Type: SEQUENCE OWNED BY; Schema: ccc; Owner: postgres
--

ALTER SEQUENCE ccc.contradiction_engine_id_seq OWNED BY ccc.contradiction_engine.id;


--
-- Name: contradictions; Type: TABLE; Schema: ccc; Owner: postgres
--

CREATE TABLE ccc.contradictions (
    id bigint NOT NULL,
    node_id bigint,
    contradiction text NOT NULL,
    alternative_model text,
    source_document_id bigint,
    severity text DEFAULT 'weak'::text,
    created_at timestamp with time zone DEFAULT now(),
    entity_id bigint,
    claim_text text,
    counter_evidence text,
    source_label text,
    confidence_impact double precision DEFAULT '-0.1'::numeric,
    is_active boolean DEFAULT true,
    verified_at timestamp with time zone,
    CONSTRAINT contradictions_severity_check CHECK ((severity = ANY (ARRAY['weak'::text, 'moderate'::text, 'strong'::text])))
);


ALTER TABLE ccc.contradictions OWNER TO postgres;

--
-- Name: contradictions_id_seq; Type: SEQUENCE; Schema: ccc; Owner: postgres
--

CREATE SEQUENCE ccc.contradictions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE ccc.contradictions_id_seq OWNER TO postgres;

--
-- Name: contradictions_id_seq; Type: SEQUENCE OWNED BY; Schema: ccc; Owner: postgres
--

ALTER SEQUENCE ccc.contradictions_id_seq OWNED BY ccc.contradictions.id;


--
-- Name: documents; Type: TABLE; Schema: ccc; Owner: postgres
--

CREATE TABLE ccc.documents (
    id bigint NOT NULL,
    raw_document_id bigint,
    content text NOT NULL,
    content_hash text NOT NULL,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE ccc.documents OWNER TO postgres;

--
-- Name: documents_id_seq; Type: SEQUENCE; Schema: ccc; Owner: postgres
--

CREATE SEQUENCE ccc.documents_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE ccc.documents_id_seq OWNER TO postgres;

--
-- Name: documents_id_seq; Type: SEQUENCE OWNED BY; Schema: ccc; Owner: postgres
--

ALTER SEQUENCE ccc.documents_id_seq OWNED BY ccc.documents.id;


--
-- Name: entity_profiles; Type: TABLE; Schema: ccc; Owner: postgres
--

CREATE TABLE ccc.entity_profiles (
    id bigint NOT NULL,
    entity_id bigint,
    essence text NOT NULL,
    core_drives text[],
    behavior_pattern text[],
    survival_mode text,
    threat_threshold double precision DEFAULT 0.5,
    mirror_bias text,
    confidence double precision DEFAULT 0.8,
    revision_count integer DEFAULT 0,
    last_revised timestamp with time zone DEFAULT now(),
    created_at timestamp with time zone DEFAULT now(),
    entity_name text,
    entity_type text,
    updated_at timestamp with time zone DEFAULT now()
);


ALTER TABLE ccc.entity_profiles OWNER TO postgres;

--
-- Name: TABLE entity_profiles; Type: COMMENT; Schema: ccc; Owner: postgres
--

COMMENT ON TABLE ccc.entity_profiles IS '实体行为本质档案 - Layer 2 Essence Layer';


--
-- Name: COLUMN entity_profiles.essence; Type: COMMENT; Schema: ccc; Owner: postgres
--

COMMENT ON COLUMN ccc.entity_profiles.essence IS '行为本质压缩句：描述该实体最底层的行为驱动';


--
-- Name: COLUMN entity_profiles.threat_threshold; Type: COMMENT; Schema: ccc; Owner: postgres
--

COMMENT ON COLUMN ccc.entity_profiles.threat_threshold IS '触发防御性行为的威胁阈值 0-1';


--
-- Name: COLUMN entity_profiles.mirror_bias; Type: COMMENT; Schema: ccc; Owner: postgres
--

COMMENT ON COLUMN ccc.entity_profiles.mirror_bias IS '观察者最容易对该实体犯的镜像投射错误';


--
-- Name: entity_profiles_id_seq; Type: SEQUENCE; Schema: ccc; Owner: postgres
--

CREATE SEQUENCE ccc.entity_profiles_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE ccc.entity_profiles_id_seq OWNER TO postgres;

--
-- Name: entity_profiles_id_seq; Type: SEQUENCE OWNED BY; Schema: ccc; Owner: postgres
--

ALTER SEQUENCE ccc.entity_profiles_id_seq OWNED BY ccc.entity_profiles.id;


--
-- Name: entity_resolve_v3_local_expectations; Type: TABLE; Schema: ccc; Owner: postgres
--

CREATE TABLE ccc.entity_resolve_v3_local_expectations (
    q text NOT NULL,
    expected_canonical_name text CONSTRAINT entity_resolve_v3_local_expect_expected_canonical_name_not_null NOT NULL,
    expected_entity_id bigint CONSTRAINT entity_resolve_v3_local_expectation_expected_entity_id_not_null NOT NULL,
    expected_match_type text CONSTRAINT entity_resolve_v3_local_expectatio_expected_match_type_not_null NOT NULL,
    min_confidence numeric NOT NULL,
    expected_entity_type text CONSTRAINT entity_resolve_v3_local_expectati_expected_entity_type_not_null NOT NULL,
    note text,
    updated_at timestamp with time zone DEFAULT now()
);


ALTER TABLE ccc.entity_resolve_v3_local_expectations OWNER TO postgres;

--
-- Name: entity_resolve_v3_local_regression; Type: VIEW; Schema: ccc; Owner: postgres
--

CREATE VIEW ccc.entity_resolve_v3_local_regression AS
 WITH actual AS (
         SELECT e_1.q,
            r.canonical_name,
            r.entity_id,
            r.match_type,
            r.confidence,
            r.entity_type
           FROM (ccc.entity_resolve_v3_local_expectations e_1
             CROSS JOIN LATERAL ( SELECT entity_resolve_v3_local.canonical_name,
                    entity_resolve_v3_local.entity_id,
                    entity_resolve_v3_local.match_type,
                    entity_resolve_v3_local.confidence,
                    entity_resolve_v3_local.entity_type
                   FROM ccc.entity_resolve_v3_local(e_1.q) entity_resolve_v3_local(canonical_name, entity_id, match_type, confidence, entity_type)
                  ORDER BY entity_resolve_v3_local.confidence DESC
                 LIMIT 1) r)
        )
 SELECT a.q,
        CASE
            WHEN ((a.canonical_name = e.expected_canonical_name) AND (a.entity_id = e.expected_entity_id) AND (a.match_type = e.expected_match_type) AND (a.confidence >= (e.min_confidence)::double precision) AND (a.entity_type = e.expected_entity_type)) THEN 'PASS'::text
            ELSE 'FAIL'::text
        END AS regression_status,
    a.canonical_name,
    e.expected_canonical_name,
    a.entity_id,
    e.expected_entity_id,
    a.match_type,
    e.expected_match_type,
    a.confidence,
    e.min_confidence,
    a.entity_type,
    e.expected_entity_type,
    e.note
   FROM (actual a
     JOIN ccc.entity_resolve_v3_local_expectations e ON ((e.q = a.q)));


ALTER VIEW ccc.entity_resolve_v3_local_regression OWNER TO postgres;

--
-- Name: entity_trajectories; Type: TABLE; Schema: ccc; Owner: postgres
--

CREATE TABLE ccc.entity_trajectories (
    id bigint NOT NULL,
    entity_profile_id bigint,
    entity_name text NOT NULL,
    snapshot_date date DEFAULT CURRENT_DATE NOT NULL,
    trajectory_status text,
    pressure double precision DEFAULT 0.5,
    pressure_trend text,
    short_term_prediction text,
    prediction_horizon integer,
    confidence double precision DEFAULT 0.7,
    key_drivers text[],
    supporting_signals text[],
    next_possible_events text[],
    risk_level text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


ALTER TABLE ccc.entity_trajectories OWNER TO postgres;

--
-- Name: entity_trajectories_id_seq; Type: SEQUENCE; Schema: ccc; Owner: postgres
--

CREATE SEQUENCE ccc.entity_trajectories_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE ccc.entity_trajectories_id_seq OWNER TO postgres;

--
-- Name: entity_trajectories_id_seq; Type: SEQUENCE OWNED BY; Schema: ccc; Owner: postgres
--

ALTER SEQUENCE ccc.entity_trajectories_id_seq OWNED BY ccc.entity_trajectories.id;


--
-- Name: event_chains; Type: TABLE; Schema: ccc; Owner: postgres
--

CREATE TABLE ccc.event_chains (
    id bigint NOT NULL,
    chain_name text NOT NULL,
    entity_id bigint,
    description text,
    pressure_type text,
    direction text,
    created_at timestamp with time zone DEFAULT now(),
    start_time timestamp without time zone,
    end_time timestamp without time zone,
    duration_days integer,
    trajectory_score double precision DEFAULT 0,
    CONSTRAINT event_chains_direction_check CHECK ((direction = ANY (ARRAY['escalating'::text, 'de-escalating'::text, 'stabilizing'::text, 'volatile'::text, 'unknown'::text]))),
    CONSTRAINT event_chains_pressure_type_check CHECK ((pressure_type = ANY (ARRAY['political'::text, 'financial'::text, 'military'::text, 'social'::text, 'legal'::text, 'media'::text, 'bio'::text])))
);


ALTER TABLE ccc.event_chains OWNER TO postgres;

--
-- Name: event_chains_id_seq; Type: SEQUENCE; Schema: ccc; Owner: postgres
--

CREATE SEQUENCE ccc.event_chains_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE ccc.event_chains_id_seq OWNER TO postgres;

--
-- Name: event_chains_id_seq; Type: SEQUENCE OWNED BY; Schema: ccc; Owner: postgres
--

ALTER SEQUENCE ccc.event_chains_id_seq OWNED BY ccc.event_chains.id;


--
-- Name: event_dashboard; Type: TABLE; Schema: ccc; Owner: postgres
--

CREATE TABLE ccc.event_dashboard (
    id bigint NOT NULL,
    document_id bigint,
    person_name text,
    event_date date,
    location text,
    impact text,
    event_summary text,
    confidence numeric(4,3) DEFAULT 0.500 NOT NULL,
    source_type text DEFAULT 'rule'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE ccc.event_dashboard OWNER TO postgres;

--
-- Name: event_dashboard_id_seq; Type: SEQUENCE; Schema: ccc; Owner: postgres
--

CREATE SEQUENCE ccc.event_dashboard_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE ccc.event_dashboard_id_seq OWNER TO postgres;

--
-- Name: event_dashboard_id_seq; Type: SEQUENCE OWNED BY; Schema: ccc; Owner: postgres
--

ALTER SEQUENCE ccc.event_dashboard_id_seq OWNED BY ccc.event_dashboard.id;


--
-- Name: event_nodes; Type: TABLE; Schema: ccc; Owner: postgres
--

CREATE TABLE ccc.event_nodes (
    id bigint NOT NULL,
    chain_id bigint,
    event_id bigint,
    entity_id bigint,
    event_time timestamp with time zone,
    sequence_order integer,
    essence text,
    mechanism text[],
    pressure text,
    signal_strength double precision DEFAULT 0.5,
    causal_weight double precision DEFAULT 1.0,
    created_at timestamp with time zone DEFAULT now(),
    previous_event_id bigint,
    next_event_id bigint,
    escalation_score double precision DEFAULT 0,
    decay_factor double precision DEFAULT 1.0
);


ALTER TABLE ccc.event_nodes OWNER TO postgres;

--
-- Name: event_nodes_id_seq; Type: SEQUENCE; Schema: ccc; Owner: postgres
--

CREATE SEQUENCE ccc.event_nodes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE ccc.event_nodes_id_seq OWNER TO postgres;

--
-- Name: event_nodes_id_seq; Type: SEQUENCE OWNED BY; Schema: ccc; Owner: postgres
--

ALTER SEQUENCE ccc.event_nodes_id_seq OWNED BY ccc.event_nodes.id;


--
-- Name: events; Type: TABLE; Schema: ccc; Owner: postgres
--

CREATE TABLE ccc.events (
    id bigint NOT NULL,
    document_id bigint,
    event_summary text,
    event_date date,
    event_year integer,
    event_time_raw text,
    created_at timestamp without time zone DEFAULT now()
);


ALTER TABLE ccc.events OWNER TO postgres;

--
-- Name: events_id_seq; Type: SEQUENCE; Schema: ccc; Owner: postgres
--

CREATE SEQUENCE ccc.events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE ccc.events_id_seq OWNER TO postgres;

--
-- Name: events_id_seq; Type: SEQUENCE OWNED BY; Schema: ccc; Owner: postgres
--

ALTER SEQUENCE ccc.events_id_seq OWNED BY ccc.events.id;


--
-- Name: forecast_regression_expectations; Type: TABLE; Schema: ccc; Owner: postgres
--

CREATE TABLE ccc.forecast_regression_expectations (
    entity_name text NOT NULL,
    expected_route_profile text CONSTRAINT forecast_regression_expectation_expected_route_profile_not_null NOT NULL,
    expected_option_a text NOT NULL,
    expected_option_b text NOT NULL,
    min_confidence numeric NOT NULL,
    max_confidence numeric NOT NULL,
    min_total_force numeric NOT NULL,
    max_total_force numeric NOT NULL,
    expected_direction text NOT NULL,
    note text,
    updated_at timestamp with time zone DEFAULT now()
);


ALTER TABLE ccc.forecast_regression_expectations OWNER TO postgres;

--
-- Name: forecast_v1_1_regression; Type: VIEW; Schema: ccc; Owner: postgres
--

CREATE VIEW ccc.forecast_v1_1_regression AS
 WITH actual AS (
         SELECT e_1.entity_name,
            ccc.forecast_v1_1(e_1.entity_name) AS f
           FROM ccc.forecast_regression_expectations e_1
        ), parsed AS (
         SELECT a.entity_name,
            (a.f ->> 'version'::text) AS version,
            (a.f ->> 'route_profile'::text) AS route_profile,
            (a.f #>> '{panel_3_forecast,option_a}'::text[]) AS option_a,
            (a.f #>> '{panel_3_forecast,option_b}'::text[]) AS option_b,
            ((a.f #>> '{panel_3_forecast,confidence}'::text[]))::numeric AS confidence,
            ((a.f #>> '{panel_4_signal_alignment,total_force}'::text[]))::numeric AS total_force,
            ((a.f #>> '{panel_4_signal_alignment,evidence_score}'::text[]))::numeric AS evidence_score,
            ((a.f #>> '{panel_4_signal_alignment,direction_balance}'::text[]))::numeric AS direction_balance,
            ((a.f #>> '{panel_4_signal_alignment,resonance_score}'::text[]))::numeric AS resonance_score,
            ((a.f #>> '{panel_4_signal_alignment,friction_score}'::text[]))::numeric AS friction_score,
            ((a.f #>> '{panel_4_signal_alignment,neutral_score}'::text[]))::numeric AS neutral_score
           FROM actual a
        )
 SELECT p.entity_name,
        CASE
            WHEN ((p.route_profile = e.expected_route_profile) AND (p.option_a = e.expected_option_a) AND (p.option_b = e.expected_option_b) AND ((p.confidence >= e.min_confidence) AND (p.confidence <= e.max_confidence)) AND ((p.total_force >= e.min_total_force) AND (p.total_force <= e.max_total_force))) THEN 'PASS'::text
            ELSE 'FAIL'::text
        END AS regression_status,
    p.version,
    p.route_profile,
    e.expected_route_profile,
    p.option_a,
    e.expected_option_a,
    p.option_b,
    e.expected_option_b,
    p.confidence,
    e.min_confidence,
    e.max_confidence,
    p.total_force,
    e.min_total_force,
    e.max_total_force,
    p.evidence_score,
    p.direction_balance,
    p.resonance_score,
    p.friction_score,
    p.neutral_score,
    e.expected_direction,
    e.note
   FROM (parsed p
     JOIN ccc.forecast_regression_expectations e ON ((e.entity_name = p.entity_name)));


ALTER VIEW ccc.forecast_v1_1_regression OWNER TO postgres;

--
-- Name: function_snapshots; Type: TABLE; Schema: ccc; Owner: postgres
--

CREATE TABLE ccc.function_snapshots (
    id bigint NOT NULL,
    checkpoint_label text NOT NULL,
    function_signature text NOT NULL,
    function_definition text NOT NULL,
    definition_hash text NOT NULL,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE ccc.function_snapshots OWNER TO postgres;

--
-- Name: function_snapshots_id_seq; Type: SEQUENCE; Schema: ccc; Owner: postgres
--

CREATE SEQUENCE ccc.function_snapshots_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE ccc.function_snapshots_id_seq OWNER TO postgres;

--
-- Name: function_snapshots_id_seq; Type: SEQUENCE OWNED BY; Schema: ccc; Owner: postgres
--

ALTER SEQUENCE ccc.function_snapshots_id_seq OWNED BY ccc.function_snapshots.id;


--
-- Name: person_aliases; Type: TABLE; Schema: ccc; Owner: postgres
--

CREATE TABLE ccc.person_aliases (
    id bigint NOT NULL,
    canonical text NOT NULL,
    alias text NOT NULL,
    alias_type text DEFAULT 'alias'::text,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE ccc.person_aliases OWNER TO postgres;

--
-- Name: person_aliases_id_seq; Type: SEQUENCE; Schema: ccc; Owner: postgres
--

CREATE SEQUENCE ccc.person_aliases_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE ccc.person_aliases_id_seq OWNER TO postgres;

--
-- Name: person_aliases_id_seq; Type: SEQUENCE OWNED BY; Schema: ccc; Owner: postgres
--

ALTER SEQUENCE ccc.person_aliases_id_seq OWNED BY ccc.person_aliases.id;


--
-- Name: person_noise_library; Type: TABLE; Schema: ccc; Owner: postgres
--

CREATE TABLE ccc.person_noise_library (
    word text NOT NULL
);


ALTER TABLE ccc.person_noise_library OWNER TO postgres;

--
-- Name: raw_documents; Type: TABLE; Schema: ccc; Owner: postgres
--

CREATE TABLE ccc.raw_documents (
    id bigint NOT NULL,
    raw_content text NOT NULL,
    source text DEFAULT 'xmind'::text,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE ccc.raw_documents OWNER TO postgres;

--
-- Name: raw_documents_id_seq; Type: SEQUENCE; Schema: ccc; Owner: postgres
--

CREATE SEQUENCE ccc.raw_documents_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE ccc.raw_documents_id_seq OWNER TO postgres;

--
-- Name: raw_documents_id_seq; Type: SEQUENCE OWNED BY; Schema: ccc; Owner: postgres
--

ALTER SEQUENCE ccc.raw_documents_id_seq OWNED BY ccc.raw_documents.id;


--
-- Name: revision_log; Type: TABLE; Schema: ccc; Owner: postgres
--

CREATE TABLE ccc.revision_log (
    id bigint NOT NULL,
    node_id bigint,
    field_changed text NOT NULL,
    old_value text,
    new_value text,
    reason text,
    revised_by text DEFAULT 'system'::text,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE ccc.revision_log OWNER TO postgres;

--
-- Name: revision_log_id_seq; Type: SEQUENCE; Schema: ccc; Owner: postgres
--

CREATE SEQUENCE ccc.revision_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE ccc.revision_log_id_seq OWNER TO postgres;

--
-- Name: revision_log_id_seq; Type: SEQUENCE OWNED BY; Schema: ccc; Owner: postgres
--

ALTER SEQUENCE ccc.revision_log_id_seq OWNED BY ccc.revision_log.id;


--
-- Name: rsal_checkpoints; Type: TABLE; Schema: ccc; Owner: postgres
--

CREATE TABLE ccc.rsal_checkpoints (
    id bigint NOT NULL,
    checkpoint_label text NOT NULL,
    module text NOT NULL,
    note text,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE ccc.rsal_checkpoints OWNER TO postgres;

--
-- Name: rsal_checkpoints_id_seq; Type: SEQUENCE; Schema: ccc; Owner: postgres
--

CREATE SEQUENCE ccc.rsal_checkpoints_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE ccc.rsal_checkpoints_id_seq OWNER TO postgres;

--
-- Name: rsal_checkpoints_id_seq; Type: SEQUENCE OWNED BY; Schema: ccc; Owner: postgres
--

ALTER SEQUENCE ccc.rsal_checkpoints_id_seq OWNED BY ccc.rsal_checkpoints.id;


--
-- Name: signals; Type: TABLE; Schema: ccc; Owner: postgres
--

CREATE TABLE ccc.signals (
    id bigint NOT NULL,
    node_id bigint,
    entity_id bigint,
    signal_type text,
    signal_text text NOT NULL,
    strength double precision DEFAULT 0.5,
    triggered_at timestamp with time zone DEFAULT now(),
    expires_at timestamp with time zone,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now(),
    entity_profile_id bigint,
    trigger_condition text,
    pressure_delta double precision DEFAULT 0.0,
    linked_prediction text,
    source_label text
);


ALTER TABLE ccc.signals OWNER TO postgres;

--
-- Name: signals_id_seq; Type: SEQUENCE; Schema: ccc; Owner: postgres
--

CREATE SEQUENCE ccc.signals_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE ccc.signals_id_seq OWNER TO postgres;

--
-- Name: signals_id_seq; Type: SEQUENCE OWNED BY; Schema: ccc; Owner: postgres
--

ALTER SEQUENCE ccc.signals_id_seq OWNED BY ccc.signals.id;


--
-- Name: source_accuracy_history; Type: TABLE; Schema: ccc; Owner: postgres
--

CREATE TABLE ccc.source_accuracy_history (
    id bigint NOT NULL,
    source_id bigint,
    event_summary text NOT NULL,
    event_date date,
    predicted text,
    outcome text,
    accuracy double precision,
    domain text,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT source_accuracy_history_accuracy_check CHECK (((accuracy >= (0)::double precision) AND (accuracy <= (1)::double precision)))
);


ALTER TABLE ccc.source_accuracy_history OWNER TO postgres;

--
-- Name: source_accuracy_history_id_seq; Type: SEQUENCE; Schema: ccc; Owner: postgres
--

CREATE SEQUENCE ccc.source_accuracy_history_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE ccc.source_accuracy_history_id_seq OWNER TO postgres;

--
-- Name: source_accuracy_history_id_seq; Type: SEQUENCE OWNED BY; Schema: ccc; Owner: postgres
--

ALTER SEQUENCE ccc.source_accuracy_history_id_seq OWNED BY ccc.source_accuracy_history.id;


--
-- Name: source_bias_vectors; Type: TABLE; Schema: ccc; Owner: postgres
--

CREATE TABLE ccc.source_bias_vectors (
    id bigint NOT NULL,
    source_id bigint,
    domain text NOT NULL,
    bias_direction text NOT NULL,
    bias_strength double precision DEFAULT 0.5,
    notes text,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT source_bias_vectors_bias_strength_check CHECK (((bias_strength >= (0)::double precision) AND (bias_strength <= (1)::double precision)))
);


ALTER TABLE ccc.source_bias_vectors OWNER TO postgres;

--
-- Name: source_bias_vectors_id_seq; Type: SEQUENCE; Schema: ccc; Owner: postgres
--

CREATE SEQUENCE ccc.source_bias_vectors_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE ccc.source_bias_vectors_id_seq OWNER TO postgres;

--
-- Name: source_bias_vectors_id_seq; Type: SEQUENCE OWNED BY; Schema: ccc; Owner: postgres
--

ALTER SEQUENCE ccc.source_bias_vectors_id_seq OWNED BY ccc.source_bias_vectors.id;


--
-- Name: source_conflict_matrix; Type: TABLE; Schema: ccc; Owner: postgres
--

CREATE TABLE ccc.source_conflict_matrix (
    id bigint NOT NULL,
    source_a_id bigint,
    source_b_id bigint,
    conflict_domain text NOT NULL,
    conflict_score double precision DEFAULT 0.5,
    conflict_type text,
    example text,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT source_conflict_matrix_conflict_score_check CHECK (((conflict_score >= (0)::double precision) AND (conflict_score <= (1)::double precision))),
    CONSTRAINT source_conflict_matrix_conflict_type_check CHECK ((conflict_type = ANY (ARRAY['factual'::text, 'narrative'::text, 'interpretation'::text, 'agenda'::text])))
);


ALTER TABLE ccc.source_conflict_matrix OWNER TO postgres;

--
-- Name: source_conflict_matrix_id_seq; Type: SEQUENCE; Schema: ccc; Owner: postgres
--

CREATE SEQUENCE ccc.source_conflict_matrix_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE ccc.source_conflict_matrix_id_seq OWNER TO postgres;

--
-- Name: source_conflict_matrix_id_seq; Type: SEQUENCE OWNED BY; Schema: ccc; Owner: postgres
--

ALTER SEQUENCE ccc.source_conflict_matrix_id_seq OWNED BY ccc.source_conflict_matrix.id;


--
-- Name: source_domain_authority; Type: TABLE; Schema: ccc; Owner: postgres
--

CREATE TABLE ccc.source_domain_authority (
    id bigint NOT NULL,
    source_id bigint,
    domain text NOT NULL,
    authority_score double precision DEFAULT 0.5,
    evidence text[],
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT source_domain_authority_authority_score_check CHECK (((authority_score >= (0)::double precision) AND (authority_score <= (1)::double precision)))
);


ALTER TABLE ccc.source_domain_authority OWNER TO postgres;

--
-- Name: source_domain_authority_id_seq; Type: SEQUENCE; Schema: ccc; Owner: postgres
--

CREATE SEQUENCE ccc.source_domain_authority_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE ccc.source_domain_authority_id_seq OWNER TO postgres;

--
-- Name: source_domain_authority_id_seq; Type: SEQUENCE OWNED BY; Schema: ccc; Owner: postgres
--

ALTER SEQUENCE ccc.source_domain_authority_id_seq OWNED BY ccc.source_domain_authority.id;


--
-- Name: source_profiles; Type: TABLE; Schema: ccc; Owner: postgres
--

CREATE TABLE ccc.source_profiles (
    id bigint NOT NULL,
    source_name text NOT NULL,
    trust_tier text NOT NULL,
    source_type text NOT NULL,
    signal_type text DEFAULT 'linear'::text,
    domain_authority text[],
    bias_vector text[],
    blind_spots text[],
    use_as text DEFAULT 'primary'::text,
    reliability_score double precision DEFAULT 0.5,
    notes text,
    created_at timestamp with time zone DEFAULT now(),
    funding_source text,
    regime_alignment text,
    predictive_reliability double precision DEFAULT 0.5,
    historical_accuracy double precision DEFAULT 0.5,
    updated_at timestamp with time zone DEFAULT now(),
    CONSTRAINT source_profiles_signal_type_check CHECK ((signal_type = ANY (ARRAY['linear'::text, 'nonlinear'::text, 'behavioral'::text]))),
    CONSTRAINT source_profiles_source_type_check CHECK ((source_type = ANY (ARRAY['leak'::text, 'investigation'::text, 'media'::text, 'think_tank'::text, 'survey'::text, 'economic'::text, 'official'::text, 'nonlinear'::text]))),
    CONSTRAINT source_profiles_trust_tier_check CHECK ((trust_tier = ANY (ARRAY['T0'::text, 'T1'::text, 'T2'::text, 'T3'::text, 'T4'::text, 'T5'::text, 'T6'::text]))),
    CONSTRAINT source_profiles_use_as_check CHECK ((use_as = ANY (ARRAY['primary'::text, 'reverse_indicator'::text, 'pattern_signal'::text])))
);


ALTER TABLE ccc.source_profiles OWNER TO postgres;

--
-- Name: source_profiles_id_seq; Type: SEQUENCE; Schema: ccc; Owner: postgres
--

CREATE SEQUENCE ccc.source_profiles_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE ccc.source_profiles_id_seq OWNER TO postgres;

--
-- Name: source_profiles_id_seq; Type: SEQUENCE OWNED BY; Schema: ccc; Owner: postgres
--

ALTER SEQUENCE ccc.source_profiles_id_seq OWNED BY ccc.source_profiles.id;


--
-- Name: source_weight_evaluations; Type: TABLE; Schema: ccc; Owner: postgres
--

CREATE TABLE ccc.source_weight_evaluations (
    id bigint NOT NULL,
    source_id bigint,
    source_name text NOT NULL,
    domain text,
    context text,
    trust_tier text,
    use_as text,
    signal_type text,
    tier_weight double precision,
    reliability_score double precision,
    historical_accuracy double precision,
    predictive_reliability double precision,
    domain_authority double precision,
    bias_penalty double precision,
    fact_weight double precision,
    narrative_signal_weight double precision,
    pattern_signal_weight double precision,
    prediction_weight double precision,
    reverse_indicator_weight double precision,
    final_effective_weight double precision,
    result jsonb,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE ccc.source_weight_evaluations OWNER TO postgres;

--
-- Name: source_weight_evaluations_id_seq; Type: SEQUENCE; Schema: ccc; Owner: postgres
--

CREATE SEQUENCE ccc.source_weight_evaluations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE ccc.source_weight_evaluations_id_seq OWNER TO postgres;

--
-- Name: source_weight_evaluations_id_seq; Type: SEQUENCE OWNED BY; Schema: ccc; Owner: postgres
--

ALTER SEQUENCE ccc.source_weight_evaluations_id_seq OWNED BY ccc.source_weight_evaluations.id;


--
-- Name: source_weight_overview; Type: VIEW; Schema: ccc; Owner: postgres
--

CREATE VIEW ccc.source_weight_overview AS
 SELECT source_name,
    trust_tier,
    use_as,
    signal_type,
    (((ccc.source_effective_weight_v2(source_name, '金融市场/短期事实'::text) -> 'weights'::text) ->> 'fact_weight'::text))::double precision AS financial_fact_weight,
    (((ccc.source_effective_weight_v2(source_name, '政策议程/权力叙事'::text) -> 'weights'::text) ->> 'narrative_signal_weight'::text))::double precision AS policy_narrative_weight,
    (((ccc.source_effective_weight_v2(source_name, '经济现实/行为成本'::text) -> 'weights'::text) ->> 'fact_weight'::text))::double precision AS reality_fact_weight,
    (((ccc.source_effective_weight_v2(source_name, '官方叙事/政权意图'::text) -> 'weights'::text) ->> 'reverse_indicator_weight'::text))::double precision AS official_reverse_weight,
    (((ccc.source_effective_weight_v2(source_name, '非线性模式/长周期信号'::text) -> 'weights'::text) ->> 'pattern_signal_weight'::text))::double precision AS pattern_signal_weight,
    (((ccc.source_effective_weight_v2(source_name, '地缘冲突'::text) -> 'weights'::text) ->> 'prediction_weight'::text))::double precision AS geopolitics_prediction_weight,
    (((ccc.source_effective_weight_v2(source_name, '综合'::text) -> 'weights'::text) ->> 'final_effective_weight'::text))::double precision AS final_effective_weight
   FROM ccc.source_profiles sp;


ALTER VIEW ccc.source_weight_overview OWNER TO postgres;

--
-- Name: timeline_proxy_map; Type: TABLE; Schema: ccc; Owner: postgres
--

CREATE TABLE ccc.timeline_proxy_map (
    id bigint NOT NULL,
    entity_id bigint NOT NULL,
    entity_name text NOT NULL,
    proxy_entity_id bigint NOT NULL,
    proxy_entity_name text NOT NULL,
    proxy_type text NOT NULL,
    proxy_source text DEFAULT 'hardcoded_v1'::text NOT NULL,
    weight double precision DEFAULT 1.0 NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    note text,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE ccc.timeline_proxy_map OWNER TO postgres;

--
-- Name: timeline_proxy_map_id_seq; Type: SEQUENCE; Schema: ccc; Owner: postgres
--

CREATE SEQUENCE ccc.timeline_proxy_map_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE ccc.timeline_proxy_map_id_seq OWNER TO postgres;

--
-- Name: timeline_proxy_map_id_seq; Type: SEQUENCE OWNED BY; Schema: ccc; Owner: postgres
--

ALTER SEQUENCE ccc.timeline_proxy_map_id_seq OWNED BY ccc.timeline_proxy_map.id;


--
-- Name: trust_fusion_v3_regression_expectations; Type: TABLE; Schema: ccc; Owner: postgres
--

CREATE TABLE ccc.trust_fusion_v3_regression_expectations (
    id bigint NOT NULL,
    source_name text NOT NULL,
    expected_min double precision NOT NULL,
    expected_max double precision NOT NULL,
    expected_use_as text CONSTRAINT trust_fusion_v3_regression_expectation_expected_use_as_not_null NOT NULL,
    note text,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE ccc.trust_fusion_v3_regression_expectations OWNER TO postgres;

--
-- Name: trust_fusion_v3_regression; Type: VIEW; Schema: ccc; Owner: postgres
--

CREATE VIEW ccc.trust_fusion_v3_regression AS
 SELECT e.source_name,
        CASE
            WHEN (((actual.v3_final >= e.expected_min) AND (actual.v3_final <= e.expected_max)) AND (actual.use_as = e.expected_use_as)) THEN 'PASS'::text
            ELSE 'FAIL'::text
        END AS regression_status,
    actual.v3_final,
    e.expected_min,
    e.expected_max,
    actual.use_as,
    e.expected_use_as,
    actual.rule_weight,
    actual.v2_final,
    e.note
   FROM (ccc.trust_fusion_v3_regression_expectations e
     CROSS JOIN LATERAL ( SELECT (((ccc.source_effective_weight_v3(e.source_name, NULL::text, NULL::text) -> 'weights'::text) ->> 'final_effective_weight_v3'::text))::double precision AS v3_final,
            (((ccc.source_effective_weight_v3(e.source_name, NULL::text, NULL::text) -> 'weights'::text) ->> 'final_effective_weight'::text))::double precision AS v2_final,
            (((ccc.source_effective_weight_v3(e.source_name, NULL::text, NULL::text) -> 'weights'::text) ->> 'rule_weight'::text))::double precision AS rule_weight,
            (ccc.source_effective_weight_v3(e.source_name, NULL::text, NULL::text) ->> 'use_as'::text) AS use_as) actual);


ALTER VIEW ccc.trust_fusion_v3_regression OWNER TO postgres;

--
-- Name: trust_fusion_v3_regression_expectations_id_seq; Type: SEQUENCE; Schema: ccc; Owner: postgres
--

CREATE SEQUENCE ccc.trust_fusion_v3_regression_expectations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE ccc.trust_fusion_v3_regression_expectations_id_seq OWNER TO postgres;

--
-- Name: trust_fusion_v3_regression_expectations_id_seq; Type: SEQUENCE OWNED BY; Schema: ccc; Owner: postgres
--

ALTER SEQUENCE ccc.trust_fusion_v3_regression_expectations_id_seq OWNED BY ccc.trust_fusion_v3_regression_expectations.id;


--
-- Name: wenziyu_cases; Type: TABLE; Schema: ccc; Owner: postgres
--

CREATE TABLE ccc.wenziyu_cases (
    id bigint NOT NULL,
    document_id bigint,
    raw_text text NOT NULL,
    case_date date,
    case_year integer,
    location text,
    person_name text,
    identity text,
    platform text,
    content text,
    background text,
    punishment text,
    punishment_days integer,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE ccc.wenziyu_cases OWNER TO postgres;

--
-- Name: wenziyu_cases_id_seq; Type: SEQUENCE; Schema: ccc; Owner: postgres
--

CREATE SEQUENCE ccc.wenziyu_cases_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE ccc.wenziyu_cases_id_seq OWNER TO postgres;

--
-- Name: wenziyu_cases_id_seq; Type: SEQUENCE OWNED BY; Schema: ccc; Owner: postgres
--

ALTER SEQUENCE ccc.wenziyu_cases_id_seq OWNED BY ccc.wenziyu_cases.id;


--
-- Name: behavioral_models id; Type: DEFAULT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.behavioral_models ALTER COLUMN id SET DEFAULT nextval('ccc.behavioral_models_id_seq'::regclass);


--
-- Name: causal_edges id; Type: DEFAULT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.causal_edges ALTER COLUMN id SET DEFAULT nextval('ccc.causal_edges_id_seq'::regclass);


--
-- Name: claims id; Type: DEFAULT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.claims ALTER COLUMN id SET DEFAULT nextval('ccc.claims_id_seq'::regclass);


--
-- Name: clean_document_entities id; Type: DEFAULT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.clean_document_entities ALTER COLUMN id SET DEFAULT nextval('ccc.clean_document_entities_id_seq'::regclass);


--
-- Name: clean_entities id; Type: DEFAULT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.clean_entities ALTER COLUMN id SET DEFAULT nextval('ccc.clean_entities_id_seq'::regclass);


--
-- Name: clean_graph_edges id; Type: DEFAULT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.clean_graph_edges ALTER COLUMN id SET DEFAULT nextval('ccc.clean_graph_edges_id_seq'::regclass);


--
-- Name: cognitive_edges id; Type: DEFAULT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.cognitive_edges ALTER COLUMN id SET DEFAULT nextval('ccc.cognitive_edges_id_seq'::regclass);


--
-- Name: cognitive_nodes id; Type: DEFAULT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.cognitive_nodes ALTER COLUMN id SET DEFAULT nextval('ccc.cognitive_nodes_id_seq'::regclass);


--
-- Name: contradiction_engine id; Type: DEFAULT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.contradiction_engine ALTER COLUMN id SET DEFAULT nextval('ccc.contradiction_engine_id_seq'::regclass);


--
-- Name: contradictions id; Type: DEFAULT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.contradictions ALTER COLUMN id SET DEFAULT nextval('ccc.contradictions_id_seq'::regclass);


--
-- Name: documents id; Type: DEFAULT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.documents ALTER COLUMN id SET DEFAULT nextval('ccc.documents_id_seq'::regclass);


--
-- Name: entity_profiles id; Type: DEFAULT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.entity_profiles ALTER COLUMN id SET DEFAULT nextval('ccc.entity_profiles_id_seq'::regclass);


--
-- Name: entity_trajectories id; Type: DEFAULT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.entity_trajectories ALTER COLUMN id SET DEFAULT nextval('ccc.entity_trajectories_id_seq'::regclass);


--
-- Name: event_chains id; Type: DEFAULT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.event_chains ALTER COLUMN id SET DEFAULT nextval('ccc.event_chains_id_seq'::regclass);


--
-- Name: event_dashboard id; Type: DEFAULT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.event_dashboard ALTER COLUMN id SET DEFAULT nextval('ccc.event_dashboard_id_seq'::regclass);


--
-- Name: event_nodes id; Type: DEFAULT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.event_nodes ALTER COLUMN id SET DEFAULT nextval('ccc.event_nodes_id_seq'::regclass);


--
-- Name: events id; Type: DEFAULT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.events ALTER COLUMN id SET DEFAULT nextval('ccc.events_id_seq'::regclass);


--
-- Name: function_snapshots id; Type: DEFAULT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.function_snapshots ALTER COLUMN id SET DEFAULT nextval('ccc.function_snapshots_id_seq'::regclass);


--
-- Name: person_aliases id; Type: DEFAULT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.person_aliases ALTER COLUMN id SET DEFAULT nextval('ccc.person_aliases_id_seq'::regclass);


--
-- Name: raw_documents id; Type: DEFAULT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.raw_documents ALTER COLUMN id SET DEFAULT nextval('ccc.raw_documents_id_seq'::regclass);


--
-- Name: revision_log id; Type: DEFAULT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.revision_log ALTER COLUMN id SET DEFAULT nextval('ccc.revision_log_id_seq'::regclass);


--
-- Name: rsal_checkpoints id; Type: DEFAULT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.rsal_checkpoints ALTER COLUMN id SET DEFAULT nextval('ccc.rsal_checkpoints_id_seq'::regclass);


--
-- Name: signals id; Type: DEFAULT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.signals ALTER COLUMN id SET DEFAULT nextval('ccc.signals_id_seq'::regclass);


--
-- Name: source_accuracy_history id; Type: DEFAULT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.source_accuracy_history ALTER COLUMN id SET DEFAULT nextval('ccc.source_accuracy_history_id_seq'::regclass);


--
-- Name: source_bias_vectors id; Type: DEFAULT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.source_bias_vectors ALTER COLUMN id SET DEFAULT nextval('ccc.source_bias_vectors_id_seq'::regclass);


--
-- Name: source_conflict_matrix id; Type: DEFAULT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.source_conflict_matrix ALTER COLUMN id SET DEFAULT nextval('ccc.source_conflict_matrix_id_seq'::regclass);


--
-- Name: source_domain_authority id; Type: DEFAULT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.source_domain_authority ALTER COLUMN id SET DEFAULT nextval('ccc.source_domain_authority_id_seq'::regclass);


--
-- Name: source_profiles id; Type: DEFAULT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.source_profiles ALTER COLUMN id SET DEFAULT nextval('ccc.source_profiles_id_seq'::regclass);


--
-- Name: source_weight_evaluations id; Type: DEFAULT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.source_weight_evaluations ALTER COLUMN id SET DEFAULT nextval('ccc.source_weight_evaluations_id_seq'::regclass);


--
-- Name: timeline_proxy_map id; Type: DEFAULT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.timeline_proxy_map ALTER COLUMN id SET DEFAULT nextval('ccc.timeline_proxy_map_id_seq'::regclass);


--
-- Name: trust_fusion_v3_regression_expectations id; Type: DEFAULT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.trust_fusion_v3_regression_expectations ALTER COLUMN id SET DEFAULT nextval('ccc.trust_fusion_v3_regression_expectations_id_seq'::regclass);


--
-- Name: wenziyu_cases id; Type: DEFAULT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.wenziyu_cases ALTER COLUMN id SET DEFAULT nextval('ccc.wenziyu_cases_id_seq'::regclass);


--
-- Data for Name: behavioral_models; Type: TABLE DATA; Schema: ccc; Owner: postgres
--

COPY ccc.behavioral_models (id, entity_profile_id, entity_name, trigger_conditions, trigger_threshold, predicted_action, action_type, confidence, historical_accuracy, sample_count, time_horizon, counter_signals, created_at, updated_at) FROM stdin;
1	1	习近平	{地方债危机扩散,银行系统压力,外汇储备下降}	0.72	货币刺激+基建投资，同时加强资本管制	economic	0.8	0.75	4	short	{外部投资回流,出口强劲反弹,美元走弱}	2026-05-27 17:34:34.951244+12	2026-05-27 17:34:34.951244+12
2	1	习近平	{民营资本影响力过大,平台数据主权威胁,舆论失控风险}	0.7	针对性监管打压，CEO级别警示	economic	0.92	0.9	5	short	{外资撤离加速,外交压力,经济下行过快}	2026-05-27 17:34:34.951244+12	2026-05-27 17:34:34.951244+12
3	1	习近平	{台湾选举结果不利,美台军事合作升级,窗口期形成}	0.8	台海军事压力升级，演习频率增加	military	0.75	0.6	3	medium	{经济危机分散注意力,军事准备度不足信号,内部稳定压力}	2026-05-27 17:34:34.951244+12	2026-05-27 17:34:34.951244+12
4	1	习近平	{经济增长低于5%,内部派系压力上升,政治合法性受质疑}	0.75	发动新一轮反腐运动转移内部矛盾	political	0.88	0.85	7	short	{经济数据好转,外交访问密集,高层公开露面正常}	2026-05-27 17:34:34.951244+12	2026-05-27 17:34:34.951244+12
5	2	普京	{能源收入下降,战争消耗超预期,外交孤立加深}	0.7	能源武器化，对欧洲施压	economic	0.82	0.78	4	medium	{欧洲能源独立加速,替代供应商成熟,暖冬降低压力}	2026-05-27 17:34:34.951244+12	2026-05-27 17:34:34.951244+12
6	2	普京	{内部精英不满上升,经济制裁累积效应,军事损失超预期}	0.8	对内强化控制，对外极端化叙事	political	0.78	0.7	3	short	{战场突破,西方制裁松动,精英利益保护承诺}	2026-05-27 17:34:34.951244+12	2026-05-27 17:34:34.951244+12
7	2	普京	{NATO东扩,地缘缓冲区丧失,历史领土叙事激活}	0.75	军事行动或代理人冲突	military	0.85	0.8	4	medium	{经济崩溃临界,精英阶层集体反对,核威慑对等升级}	2026-05-27 17:34:34.951244+12	2026-05-27 17:34:34.951244+12
8	3	特朗普	{盟友依赖美国安全,NATO支出不足,双边逆差}	0.65	威胁撤出安全承诺，要求重新谈判	political	0.8	0.75	4	short	{盟友让步,经济换安全协议,国会制约}	2026-05-27 17:34:34.951244+12	2026-05-27 17:34:34.951244+12
9	3	特朗普	{支持率下滑,媒体攻击升级,司法调查压力}	0.6	制造舆论战，攻击建制媒体和机构	media	0.88	0.85	6	immediate	{经济数据好转,外交胜利,核心支持者稳定}	2026-05-27 17:34:34.951244+12	2026-05-27 17:34:34.951244+12
10	3	特朗普	{贸易逆差扩大,盟友搭便车,国内制造业压力}	0.65	关税战升级，单边主义强化	economic	0.85	0.82	5	immediate	{谈判妥协提前,市场崩溃压力,国会阻力}	2026-05-27 17:34:34.951244+12	2026-05-27 17:34:34.951244+12
11	4	中共	{香港独立倾向,台湾独立声音,新疆国际压力}	0.9	法律手段+经济施压+军事展示	legal	0.85	0.8	5	medium	{国际社会分裂,经济互依赖制约,内部稳定优先}	2026-05-27 17:34:34.951244+12	2026-05-27 17:34:34.951244+12
12	4	中共	{经济增长低于预期,外资撤离,消费信心下降}	0.8	刺激政策+国企主导投资，私营资本受限	economic	0.88	0.85	6	short	{外需强劲,技术突破,房地产企稳}	2026-05-27 17:34:34.951244+12	2026-05-27 17:34:34.951244+12
13	4	中共	{社会不满情绪上升,失业率高企,舆论失控风险}	0.85	加强网络审查，扩大维稳支出	social	0.92	0.9	8	immediate	{经济改善,就业市场好转,外部威胁转移注意}	2026-05-27 17:34:34.951244+12	2026-05-27 17:34:34.951244+12
14	5	美联储	{银行系统压力,信贷市场冻结,系统性风险上升}	0.75	紧急流动性注入，量化宽松重启	economic	0.88	0.85	4	immediate	{财政政策配合,市场自我修复,通胀顽固}	2026-05-27 17:34:34.951244+12	2026-05-27 17:34:34.951244+12
15	5	美联储	{通胀超过3%,就业市场过热,资产泡沫风险}	0.7	加息周期启动，前瞻指引收紧	economic	0.85	0.82	5	medium	{经济衰退信号,金融系统压力,政治压力干预}	2026-05-27 17:34:34.951244+12	2026-05-27 17:34:34.951244+12
16	6	WEF	{AI技术突破,数字治理真空,技术标准争夺}	0.55	推动AI全球治理框架，抢占标准制定权	political	0.7	0.6	2	medium	{美中分裂标准,国家主权优先,技术民族主义}	2026-05-27 17:34:34.951244+12	2026-05-27 17:34:34.951244+12
17	6	WEF	{全球治理碎片化,民粹主义上升,多边主义退潮}	0.6	加强私营部门主导的治理框架推广	political	0.72	0.65	3	long	{主权国家反弹,替代治理框架崛起,内部分歧}	2026-05-27 17:34:34.951244+12	2026-05-27 17:34:34.951244+12
\.


--
-- Data for Name: causal_edges; Type: TABLE DATA; Schema: ccc; Owner: postgres
--

COPY ccc.causal_edges (id, source_event_id, target_event_id, causal_type, confidence, time_delta_days, created_at, temporal_distance, causality_strength, directional_bias) FROM stdin;
45	79	80	follows	0.6	1096	2026-05-26 19:14:44.044707+12	1096	0.75	escalating
46	80	81	follows	0.6	2191	2026-05-26 19:14:44.044707+12	2191	0.75	escalating
47	82	83	follows	0.6	3241	2026-05-26 19:14:44.044707+12	3241	0.533	escalating
48	83	84	follows	0.6	227	2026-05-26 19:14:44.044707+12	227	0.633	escalating
49	84	85	follows	0.6	34	2026-05-26 19:14:44.044707+12	34	0.658	escalating
50	85	86	follows	0.6	691	2026-05-26 19:14:44.044707+12	691	0.508	escalating
51	86	87	follows	0.6	30	2026-05-26 19:14:44.044707+12	30	0.583	escalating
52	87	88	follows	0.6	30	2026-05-26 19:14:44.044707+12	30	0.583	escalating
53	89	90	follows	0.6	1487	2026-05-26 19:14:44.044707+12	1487	0.6	escalating
54	90	91	follows	0.6	70	2026-05-26 19:14:44.044707+12	70	0.75	escalating
55	92	93	follows	0.6	454	2026-05-26 19:14:44.044707+12	454	0.521	escalating
56	93	94	follows	0.6	308	2026-05-26 19:14:44.044707+12	308	0.571	escalating
57	94	95	follows	0.6	36	2026-05-26 19:14:44.044707+12	36	0.646	escalating
58	95	96	follows	0.6	209	2026-05-26 19:14:44.044707+12	209	0.596	escalating
59	96	97	follows	0.6	278	2026-05-26 19:14:44.044707+12	278	0.521	escalating
60	97	98	follows	0.6	72	2026-05-26 19:14:44.044707+12	72	0.521	escalating
61	98	99	follows	0.6	7	2026-05-26 19:14:44.044707+12	7	0.571	escalating
62	100	101	follows	0.6	1305	2026-05-26 19:14:44.044707+12	1305	0.75	escalating
63	101	102	follows	0.6	395	2026-05-26 19:14:44.044707+12	395	0.75	escalating
64	104	105	follows	0.6	1109	2026-05-26 19:14:44.044707+12	1109	0.625	escalating
65	105	106	follows	0.6	290	2026-05-26 19:14:44.044707+12	290	0.75	escalating
66	107	108	follows	0.6	774	2026-05-26 19:14:44.044707+12	774	1	escalating
67	111	112	follows	0.6	11	2026-05-26 19:14:44.044707+12	11	0.85	escalating
68	113	114	follows	0.6	158	2026-05-26 19:14:44.044707+12	158	0.85	escalating
69	115	116	follows	0.6	261	2026-05-26 19:14:44.044707+12	261	1	escalating
70	118	119	follows	0.6	152	2026-05-26 19:14:44.044707+12	152	0.95	escalating
71	120	121	follows	0.6	118	2026-05-26 19:14:44.044707+12	118	1	escalating
\.


--
-- Data for Name: claims; Type: TABLE DATA; Schema: ccc; Owner: postgres
--

COPY ccc.claims (id, document_id, claim_text, confidence, created_at) FROM stdin;
\.


--
-- Data for Name: clean_document_entities; Type: TABLE DATA; Schema: ccc; Owner: postgres
--

COPY ccc.clean_document_entities (id, document_id, entity_id, canonical_name, entity_type, frequency, created_at) FROM stdin;
3	2	3	薄一波	PERSON	4	2026-05-25 12:25:06.420091+12
4	2	4	薄熙来	PERSON	4	2026-05-25 12:25:06.420091+12
5	2	5	胡明	PERSON	4	2026-05-25 12:25:06.420091+12
6	2	6	李丹宇	PERSON	4	2026-05-25 12:25:06.420091+12
7	2	7	谷开来	PERSON	4	2026-05-25 12:25:06.420091+12
8	2	8	宋任穷	PERSON	4	2026-05-25 12:25:06.420091+12
9	2	9	林宗棠	PERSON	4	2026-05-25 12:25:06.420091+12
10	2	10	张红文	PERSON	4	2026-05-25 12:25:06.420091+12
11	2	11	曹建国	PERSON	4	2026-05-25 12:25:06.420091+12
12	2	12	杨尚坤	PERSON	4	2026-05-25 12:25:06.420091+12
13	2	13	万里	PERSON	4	2026-05-25 12:25:06.420091+12
14	2	14	宋平	PERSON	4	2026-05-25 12:25:06.420091+12
15	2	15	李希	PERSON	4	2026-05-25 12:25:06.420091+12
16	2	16	习近平	PERSON	4	2026-05-25 12:25:06.420091+12
17	6	3	薄一波	PERSON	1	2026-05-25 14:03:23.524269+12
18	6	4	薄熙来	PERSON	1	2026-05-25 14:03:23.524269+12
19	6	10	张红文	PERSON	1	2026-05-25 14:03:23.524269+12
20	6	5	胡明	PERSON	1	2026-05-25 14:03:23.524269+12
21	6	7	谷开来	PERSON	1	2026-05-25 14:03:23.524269+12
22	6	6	李丹宇	PERSON	1	2026-05-25 14:03:23.524269+12
23	6	11	曹建国	PERSON	1	2026-05-25 14:03:23.524269+12
24	6	16	习近平	PERSON	1	2026-05-25 14:03:23.524269+12
25	6	15	李希	PERSON	1	2026-05-25 14:03:23.524269+12
26	6	8	宋任穷	PERSON	1	2026-05-25 14:03:23.524269+12
27	6	9	林宗棠	PERSON	1	2026-05-25 14:03:23.524269+12
28	6	12	杨尚坤	PERSON	1	2026-05-25 14:03:23.524269+12
29	6	13	万里	PERSON	1	2026-05-25 14:03:23.524269+12
30	6	14	宋平	PERSON	1	2026-05-25 14:03:23.524269+12
31	7	16	习近平	PERSON	2	2026-05-25 19:59:58.661492+12
32	7	17	特朗普	PERSON	2	2026-05-25 19:59:58.661492+12
33	7	18	马云	PERSON	2	2026-05-25 19:59:58.661492+12
34	7	19	石正丽	PERSON	2	2026-05-25 19:59:58.661492+12
35	7	20	Joe Biden	PERSON	2	2026-05-25 19:59:58.661492+12
36	7	21	Pavel Dourov	PERSON	2	2026-05-25 19:59:58.661492+12
37	7	22	Javier Milei	PERSON	2	2026-05-25 19:59:58.661492+12
38	7	23	Irakli Kobakhidze	PERSON	2	2026-05-25 19:59:58.661492+12
39	7	24	Jeffrey Epstein	PERSON	2	2026-05-25 19:59:58.661492+12
40	7	25	Alexander Shiplyuk	PERSON	2	2026-05-25 19:59:58.661492+12
41	7	26	Steve Bannon	PERSON	2	2026-05-25 19:59:58.661492+12
42	7	27	李家超	PERSON	2	2026-05-25 19:59:58.661492+12
43	7	28	田文华	PERSON	2	2026-05-25 19:59:58.661492+12
44	7	29	胡锦涛	PERSON	2	2026-05-25 19:59:58.661492+12
45	7	30	蔡英文	PERSON	2	2026-05-25 19:59:58.661492+12
46	7	31	周正毅	PERSON	2	2026-05-25 19:59:58.661492+12
47	7	32	哈马斯	ORG	2	2026-05-25 19:59:58.661492+12
48	7	33	ISIS	ORG	2	2026-05-25 19:59:58.661492+12
49	7	34	中共	ORG	2	2026-05-25 19:59:58.661492+12
50	7	35	美联储	ORG	2	2026-05-25 19:59:58.661492+12
51	7	36	阿里巴巴	ORG	2	2026-05-25 19:59:58.661492+12
52	7	37	香港	GPE	2	2026-05-25 19:59:58.661492+12
53	7	38	台湾	GPE	2	2026-05-25 19:59:58.661492+12
54	7	39	乌克兰	GPE	2	2026-05-25 19:59:58.661492+12
55	7	40	俄罗斯	GPE	2	2026-05-25 19:59:58.661492+12
56	7	41	以色列	GPE	2	2026-05-25 19:59:58.661492+12
57	7	42	新疆	GPE	2	2026-05-25 19:59:58.661492+12
79	11	62	比尔盖茨	PERSON	2	2026-06-06 09:14:10.812552+12
80	11	59	WEF	ORG	3	2026-06-06 09:14:10.812552+12
81	10	63	汉坦病毒(HTNV)	PATHOGEN	1	2026-06-06 09:35:15.018489+12
82	10	64	安第斯病毒	PATHOGEN	3	2026-06-06 09:35:15.018489+12
83	10	65	黑线姬鼠	ANIMAL	1	2026-06-06 09:35:15.018489+12
84	10	66	单克隆抗体JL16	BIOMEDICAL	1	2026-06-06 09:35:15.018489+12
85	10	67	叙利亚仓鼠	ANIMAL_MODEL	2	2026-06-06 09:35:15.018489+12
86	10	68	单克隆抗体MIB22	BIOMEDICAL	1	2026-06-06 09:35:15.018489+12
87	10	69	MV Honduras邮轮	EVENT	2	2026-06-06 09:35:15.018489+12
88	10	70	首尔病毒(SEOV)	PATHOGEN	1	2026-06-06 09:35:15.018489+12
89	10	71	褐家鼠	ANIMAL	1	2026-06-06 09:35:15.018489+12
90	12	82	多边主义议程	GOVERNANCE	1	2026-06-06 10:02:31.964818+12
91	12	64	安第斯病毒	PATHOGEN	1	2026-06-06 10:02:31.964818+12
92	12	72	盖茨基金会	ORG	1	2026-06-06 10:02:31.964818+12
93	12	83	泰国神婆普莱	PERSON	1	2026-06-06 10:02:31.964818+12
94	12	77	WHO	ORG	1	2026-06-06 10:02:31.964818+12
95	12	73	Klaus Schwab	PERSON	1	2026-06-06 10:02:31.964818+12
96	12	85	地母经	DOCUMENT	1	2026-06-06 10:02:31.964818+12
97	12	78	混合X疾病	PATHOGEN	4	2026-06-06 10:02:31.964818+12
98	12	80	GAVI	ORG	1	2026-06-06 10:02:31.964818+12
99	12	62	比尔盖茨	PERSON	2	2026-06-06 10:02:31.964818+12
100	12	76	ICTV	ORG	1	2026-06-06 10:02:31.964818+12
101	12	69	MV Honduras邮轮	EVENT	1	2026-06-06 10:02:31.964818+12
102	12	81	约翰斯·霍普金斯卫生安全中心	ORG	1	2026-06-06 10:02:31.964818+12
103	12	79	CEPI	ORG	1	2026-06-06 10:02:31.964818+12
104	12	59	WEF	ORG	2	2026-06-06 10:02:31.964818+12
105	12	84	Rudy Baldwin	PERSON	1	2026-06-06 10:02:31.964818+12
106	12	74	林小旭	PERSON	2	2026-06-06 10:02:31.964818+12
107	12	86	2026赤马红羊年	EVENT	1	2026-06-06 10:02:31.964818+12
108	12	70	首尔病毒(SEOV)	PATHOGEN	1	2026-06-06 10:02:31.964818+12
109	12	75	虚实谈	MEDIA	3	2026-06-06 10:02:31.964818+12
110	12	63	汉坦病毒(HTNV)	PATHOGEN	1	2026-06-06 10:02:31.964818+12
111	13	101	X疾病人为泄露测试	NARRATIVE_NODE	1	2026-06-06 10:02:54.543596+12
112	13	93	新马尔萨斯人口论	NARRATIVE_NODE	1	2026-06-06 10:02:54.543596+12
113	13	89	实验室增强	NARRATIVE_NODE	1	2026-06-06 10:02:54.543596+12
114	13	98	超自然预知	NARRATIVE_NODE	1	2026-06-06 10:02:54.543596+12
115	13	64	安第斯病毒	PATHOGEN	1	2026-06-06 10:02:54.543596+12
116	13	102	大流行响应加速器	GOVERNANCE	1	2026-06-06 10:02:54.543596+12
117	13	83	泰国神婆普莱	PERSON	1	2026-06-06 10:02:54.543596+12
118	13	73	Klaus Schwab	PERSON	1	2026-06-06 10:02:54.543596+12
119	13	91	精英控制剧本	NARRATIVE_NODE	1	2026-06-06 10:02:54.543596+12
120	13	96	利益无关学者	NARRATIVE_NODE	1	2026-06-06 10:02:54.543596+12
121	13	78	混合X疾病	PATHOGEN	1	2026-06-06 10:02:54.543596+12
122	13	100	偶发性宿主感染	BIOLOGICAL_FACT	1	2026-06-06 10:02:54.543596+12
123	13	99	后验附会信息源	NARRATIVE_NODE	1	2026-06-06 10:02:54.543596+12
124	13	94	多边治理协同	GOVERNANCE	1	2026-06-06 10:02:54.543596+12
125	13	95	深层政府世界政权	NARRATIVE_NODE	1	2026-06-06 10:02:54.543596+12
126	13	62	比尔盖茨	PERSON	1	2026-06-06 10:02:54.543596+12
127	13	97	2030议程独裁者	NARRATIVE_NODE	1	2026-06-06 10:02:54.543596+12
128	13	69	MV Honduras邮轮	EVENT	1	2026-06-06 10:02:54.543596+12
129	13	79	CEPI	ORG	1	2026-06-06 10:02:54.543596+12
130	13	90	世卫防御框架	GOVERNANCE	1	2026-06-06 10:02:54.543596+12
131	13	59	WEF	ORG	1	2026-06-06 10:02:54.543596+12
132	13	103	强制疫苗地缘工具	NARRATIVE_NODE	1	2026-06-06 10:02:54.543596+12
133	13	92	无私慈善主义	NARRATIVE_NODE	1	2026-06-06 10:02:54.543596+12
134	13	87	自然突变论	NARRATIVE_NODE	1	2026-06-06 10:02:54.543596+12
135	13	88	人工编辑论	NARRATIVE_NODE	1	2026-06-06 10:02:54.543596+12
136	14	101	X疾病人为泄露测试	NARRATIVE_NODE	1	2026-06-06 19:25:16.478271+12
137	14	93	新马尔萨斯人口论	NARRATIVE_NODE	1	2026-06-06 19:25:16.478271+12
138	14	89	实验室增强	NARRATIVE_NODE	1	2026-06-06 19:25:16.478271+12
139	14	98	超自然预知	NARRATIVE_NODE	1	2026-06-06 19:25:16.478271+12
140	14	64	安第斯病毒	PATHOGEN	1	2026-06-06 19:25:16.478271+12
141	14	102	大流行响应加速器	GOVERNANCE	1	2026-06-06 19:25:16.478271+12
142	14	83	泰国神婆普莱	PERSON	1	2026-06-06 19:25:16.478271+12
143	14	73	Klaus Schwab	PERSON	1	2026-06-06 19:25:16.478271+12
144	14	91	精英控制剧本	NARRATIVE_NODE	1	2026-06-06 19:25:16.478271+12
145	14	96	利益无关学者	NARRATIVE_NODE	1	2026-06-06 19:25:16.478271+12
146	14	78	混合X疾病	PATHOGEN	1	2026-06-06 19:25:16.478271+12
147	14	100	偶发性宿主感染	BIOLOGICAL_FACT	1	2026-06-06 19:25:16.478271+12
148	14	99	后验附会信息源	NARRATIVE_NODE	1	2026-06-06 19:25:16.478271+12
149	14	94	多边治理协同	GOVERNANCE	1	2026-06-06 19:25:16.478271+12
150	14	95	深层政府世界政权	NARRATIVE_NODE	1	2026-06-06 19:25:16.478271+12
151	14	62	比尔盖茨	PERSON	1	2026-06-06 19:25:16.478271+12
152	14	97	2030议程独裁者	NARRATIVE_NODE	1	2026-06-06 19:25:16.478271+12
153	14	69	MV Honduras邮轮	EVENT	1	2026-06-06 19:25:16.478271+12
154	14	79	CEPI	ORG	1	2026-06-06 19:25:16.478271+12
155	14	90	世卫防御框架	GOVERNANCE	1	2026-06-06 19:25:16.478271+12
156	14	59	WEF	ORG	1	2026-06-06 19:25:16.478271+12
157	14	103	强制疫苗地缘工具	NARRATIVE_NODE	1	2026-06-06 19:25:16.478271+12
158	14	92	无私慈善主义	NARRATIVE_NODE	1	2026-06-06 19:25:16.478271+12
159	14	87	自然突变论	NARRATIVE_NODE	1	2026-06-06 19:25:16.478271+12
160	14	88	人工编辑论	NARRATIVE_NODE	1	2026-06-06 19:25:16.478271+12
\.


--
-- Data for Name: clean_entities; Type: TABLE DATA; Schema: ccc; Owner: postgres
--

COPY ccc.clean_entities (id, canonical_name, entity_type, source, mention_count, confidence, created_at) FROM stdin;
74	林小旭	PERSON	manual_seed_public_health_governance	0	0.9	2026-06-06 10:02:31.964818+12
40	俄罗斯	GPE	ingest_v3	2	0.9	2026-05-25 19:59:58.661492+12
41	以色列	GPE	ingest_v3	2	0.9	2026-05-25 19:59:58.661492+12
42	新疆	GPE	ingest_v3	2	0.9	2026-05-25 19:59:58.661492+12
57	日本	PERSON	timeline_auto	0	0.8	2026-05-26 14:55:50.207262+12
58	中国社会	PERSON	timeline_auto	0	0.8	2026-05-26 14:55:50.207262+12
59	WEF	ORG	manual	0	0.9	2026-05-27 17:22:44.393002+12
60	普京	PERSON	manual	0	0.95	2026-05-27 22:35:14.748068+12
3	薄一波	PERSON	ingest_v3	5	0.9	2026-05-25 12:25:06.420091+12
4	薄熙来	PERSON	ingest_v3	5	0.9	2026-05-25 12:25:06.420091+12
10	张红文	PERSON	ingest_v3	5	0.9	2026-05-25 12:25:06.420091+12
5	胡明	PERSON	ingest_v3	5	0.9	2026-05-25 12:25:06.420091+12
7	谷开来	PERSON	ingest_v3	5	0.9	2026-05-25 12:25:06.420091+12
6	李丹宇	PERSON	ingest_v3	5	0.9	2026-05-25 12:25:06.420091+12
11	曹建国	PERSON	ingest_v3	5	0.9	2026-05-25 12:25:06.420091+12
15	李希	PERSON	ingest_v3	5	0.9	2026-05-25 12:25:06.420091+12
8	宋任穷	PERSON	ingest_v3	5	0.9	2026-05-25 12:25:06.420091+12
9	林宗棠	PERSON	ingest_v3	5	0.9	2026-05-25 12:25:06.420091+12
12	杨尚坤	PERSON	ingest_v3	5	0.9	2026-05-25 12:25:06.420091+12
13	万里	PERSON	ingest_v3	5	0.9	2026-05-25 12:25:06.420091+12
14	宋平	PERSON	ingest_v3	5	0.9	2026-05-25 12:25:06.420091+12
16	习近平	PERSON	ingest_v3	7	0.9	2026-05-25 12:25:06.420091+12
17	特朗普	PERSON	ingest_v3	2	0.9	2026-05-25 19:59:58.661492+12
18	马云	PERSON	ingest_v3	2	0.9	2026-05-25 19:59:58.661492+12
19	石正丽	PERSON	ingest_v3	2	0.9	2026-05-25 19:59:58.661492+12
20	Joe Biden	PERSON	ingest_v3	2	0.9	2026-05-25 19:59:58.661492+12
21	Pavel Dourov	PERSON	ingest_v3	2	0.9	2026-05-25 19:59:58.661492+12
22	Javier Milei	PERSON	ingest_v3	2	0.9	2026-05-25 19:59:58.661492+12
23	Irakli Kobakhidze	PERSON	ingest_v3	2	0.9	2026-05-25 19:59:58.661492+12
24	Jeffrey Epstein	PERSON	ingest_v3	2	0.9	2026-05-25 19:59:58.661492+12
25	Alexander Shiplyuk	PERSON	ingest_v3	2	0.9	2026-05-25 19:59:58.661492+12
26	Steve Bannon	PERSON	ingest_v3	2	0.9	2026-05-25 19:59:58.661492+12
27	李家超	PERSON	ingest_v3	2	0.9	2026-05-25 19:59:58.661492+12
28	田文华	PERSON	ingest_v3	2	0.9	2026-05-25 19:59:58.661492+12
29	胡锦涛	PERSON	ingest_v3	2	0.9	2026-05-25 19:59:58.661492+12
30	蔡英文	PERSON	ingest_v3	2	0.9	2026-05-25 19:59:58.661492+12
31	周正毅	PERSON	ingest_v3	2	0.9	2026-05-25 19:59:58.661492+12
32	哈马斯	ORG	ingest_v3	2	0.9	2026-05-25 19:59:58.661492+12
33	ISIS	ORG	ingest_v3	2	0.9	2026-05-25 19:59:58.661492+12
34	中共	ORG	ingest_v3	2	0.9	2026-05-25 19:59:58.661492+12
35	美联储	ORG	ingest_v3	2	0.9	2026-05-25 19:59:58.661492+12
36	阿里巴巴	ORG	ingest_v3	2	0.9	2026-05-25 19:59:58.661492+12
37	香港	GPE	ingest_v3	2	0.9	2026-05-25 19:59:58.661492+12
38	台湾	GPE	ingest_v3	2	0.9	2026-05-25 19:59:58.661492+12
39	乌克兰	GPE	ingest_v3	2	0.9	2026-05-25 19:59:58.661492+12
62	比尔盖茨	PERSON	manual_graph_patch	0	0.9	2026-06-05 22:25:34.807658+12
63	汉坦病毒(HTNV)	PATHOGEN	manual_seed_hantavirus	0	0.9	2026-06-06 09:13:51.441658+12
64	安第斯病毒	PATHOGEN	manual_seed_hantavirus	0	0.9	2026-06-06 09:13:51.441658+12
65	黑线姬鼠	ANIMAL	manual_seed_hantavirus	0	0.9	2026-06-06 09:13:51.441658+12
66	单克隆抗体JL16	BIOMEDICAL	manual_seed_hantavirus	0	0.9	2026-06-06 09:13:51.441658+12
67	叙利亚仓鼠	ANIMAL_MODEL	manual_seed_hantavirus	0	0.9	2026-06-06 09:13:51.441658+12
68	单克隆抗体MIB22	BIOMEDICAL	manual_seed_hantavirus	0	0.9	2026-06-06 09:13:51.441658+12
69	MV Honduras邮轮	EVENT	manual_seed_hantavirus	0	0.9	2026-06-06 09:13:51.441658+12
70	首尔病毒(SEOV)	PATHOGEN	manual_seed_hantavirus	0	0.9	2026-06-06 09:13:51.441658+12
71	褐家鼠	ANIMAL	manual_seed_hantavirus	0	0.9	2026-06-06 09:13:51.441658+12
72	盖茨基金会	ORG	manual_seed_wef_network	0	0.9	2026-06-06 09:14:10.812552+12
73	Klaus Schwab	PERSON	manual_seed_wef_network	0	0.9	2026-06-06 09:14:10.812552+12
75	虚实谈	MEDIA	manual_seed_public_health_governance	0	0.9	2026-06-06 10:02:31.964818+12
76	ICTV	ORG	manual_seed_public_health_governance	0	0.9	2026-06-06 10:02:31.964818+12
77	WHO	ORG	manual_seed_public_health_governance	0	0.9	2026-06-06 10:02:31.964818+12
78	混合X疾病	PATHOGEN	manual_seed_public_health_governance	0	0.9	2026-06-06 10:02:31.964818+12
79	CEPI	ORG	manual_seed_public_health_governance	0	0.9	2026-06-06 10:02:31.964818+12
80	GAVI	ORG	manual_seed_public_health_governance	0	0.9	2026-06-06 10:02:31.964818+12
81	约翰斯·霍普金斯卫生安全中心	ORG	manual_seed_public_health_governance	0	0.9	2026-06-06 10:02:31.964818+12
82	多边主义议程	GOVERNANCE	manual_seed_public_health_governance	0	0.9	2026-06-06 10:02:31.964818+12
83	泰国神婆普莱	PERSON	manual_seed_public_health_governance	0	0.9	2026-06-06 10:02:31.964818+12
84	Rudy Baldwin	PERSON	manual_seed_public_health_governance	0	0.9	2026-06-06 10:02:31.964818+12
85	地母经	DOCUMENT	manual_seed_public_health_governance	0	0.9	2026-06-06 10:02:31.964818+12
86	2026赤马红羊年	EVENT	manual_seed_public_health_governance	0	0.9	2026-06-06 10:02:31.964818+12
87	自然突变论	NARRATIVE_NODE	contradiction_narrative_seed	0	0.85	2026-06-06 10:02:54.543596+12
88	人工编辑论	NARRATIVE_NODE	contradiction_narrative_seed	0	0.85	2026-06-06 10:02:54.543596+12
89	实验室增强	NARRATIVE_NODE	contradiction_narrative_seed	0	0.85	2026-06-06 10:02:54.543596+12
90	世卫防御框架	GOVERNANCE	contradiction_narrative_seed	0	0.85	2026-06-06 10:02:54.543596+12
91	精英控制剧本	NARRATIVE_NODE	contradiction_narrative_seed	0	0.85	2026-06-06 10:02:54.543596+12
92	无私慈善主义	NARRATIVE_NODE	contradiction_narrative_seed	0	0.85	2026-06-06 10:02:54.543596+12
93	新马尔萨斯人口论	NARRATIVE_NODE	contradiction_narrative_seed	0	0.85	2026-06-06 10:02:54.543596+12
94	多边治理协同	GOVERNANCE	contradiction_narrative_seed	0	0.85	2026-06-06 10:02:54.543596+12
95	深层政府世界政权	NARRATIVE_NODE	contradiction_narrative_seed	0	0.85	2026-06-06 10:02:54.543596+12
96	利益无关学者	NARRATIVE_NODE	contradiction_narrative_seed	0	0.85	2026-06-06 10:02:54.543596+12
97	2030议程独裁者	NARRATIVE_NODE	contradiction_narrative_seed	0	0.85	2026-06-06 10:02:54.543596+12
98	超自然预知	NARRATIVE_NODE	contradiction_narrative_seed	0	0.85	2026-06-06 10:02:54.543596+12
99	后验附会信息源	NARRATIVE_NODE	contradiction_narrative_seed	0	0.85	2026-06-06 10:02:54.543596+12
100	偶发性宿主感染	BIOLOGICAL_FACT	contradiction_narrative_seed	0	0.85	2026-06-06 10:02:54.543596+12
101	X疾病人为泄露测试	NARRATIVE_NODE	contradiction_narrative_seed	0	0.85	2026-06-06 10:02:54.543596+12
102	大流行响应加速器	GOVERNANCE	contradiction_narrative_seed	0	0.85	2026-06-06 10:02:54.543596+12
103	强制疫苗地缘工具	NARRATIVE_NODE	contradiction_narrative_seed	0	0.85	2026-06-06 10:02:54.543596+12
\.


--
-- Data for Name: clean_graph_edges; Type: TABLE DATA; Schema: ccc; Owner: postgres
--

COPY ccc.clean_graph_edges (id, source_entity_id, target_entity_id, relation_type, weight, document_count, created_at, relation_label, relation_direction, event_time, valid_from, valid_to, causal_weight, pressure, direction, updated_at) FROM stdin;
92	3	4	typed	1	1	2026-05-25 14:03:23.524269+12	family_relation	source_to_target	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
93	3	16	typed	1	1	2026-05-25 14:03:23.524269+12	political_alignment	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
94	4	3	typed	1	1	2026-05-25 14:03:23.524269+12	family_relation	source_to_target	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
95	4	5	typed	1	1	2026-05-25 14:03:23.524269+12	marriage	source_to_target	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
96	4	7	typed	1	1	2026-05-25 14:03:23.524269+12	marriage	source_to_target	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
97	4	6	typed	1	1	2026-05-25 14:03:23.524269+12	marriage	source_to_target	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
98	10	11	typed	1	1	2026-05-25 14:03:23.524269+12	mentor_student	target_to_source	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
99	10	16	typed	1	1	2026-05-25 14:03:23.524269+12	political_alignment	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
100	10	15	typed	1	1	2026-05-25 14:03:23.524269+12	investigated_by	source_to_target	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
7	3	10	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
4	3	7	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
8	3	11	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
5	3	8	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
6	3	9	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
9	3	12	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
19	4	10	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
14	4	5	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
16	4	7	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
15	4	6	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
20	4	11	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
25	4	16	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
24	4	15	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
17	4	8	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
18	4	9	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
21	4	12	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
22	4	13	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
23	4	14	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
30	5	10	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
49	7	10	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
40	6	10	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
71	10	11	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
76	10	16	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
75	10	15	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
57	8	10	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
64	9	10	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
72	10	12	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
73	10	13	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
74	10	14	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
27	5	7	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
26	5	6	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
31	5	11	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
36	5	16	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
35	5	15	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
28	5	8	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
29	5	9	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
32	5	12	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
33	5	13	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
34	5	14	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
37	6	7	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
50	7	11	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
55	7	16	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
54	7	15	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
47	7	8	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
48	7	9	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
51	7	12	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
52	7	13	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
53	7	14	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
41	6	11	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
46	6	16	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
45	6	15	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
38	6	8	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
39	6	9	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
42	6	12	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
43	6	13	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
460	59	62	elite_network_association	8	1	2026-06-05 22:25:34.807658+12	WEF associated actor: Bill Gates / global philanthropy-capital network	undirected	\N	\N	\N	0.75	governance	agenda_alignment	2026-06-06 09:14:10.812552+12
1	3	4	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
2	3	5	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
3	3	6	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
462	65	63	typed	7.5	1	2026-06-06 09:35:15.018489+12	野外自然宿主/引发肾综合征出血热	source_to_target	\N	\N	\N	0	biological	reservoir_to_pathogen	2026-06-06 09:35:15.018489+12
463	71	70	typed	8	1	2026-06-06 09:35:15.018489+12	城市下水道宿主/唯一随人类贸易全球扩散的汉坦病毒	source_to_target	\N	\N	\N	0	biological	reservoir_to_pathogen	2026-06-06 09:35:15.018489+12
464	67	64	typed	9.5	1	2026-06-06 09:35:15.018489+12	关键致病动物模型/展现急性肺水肿与致死性休克并具备飞沫人传人特性	source_to_target	\N	\N	\N	0.9	biomedical	animal_model	2026-06-06 09:35:15.018489+12
465	68	64	typed	8.5	1	2026-06-06 09:35:15.018489+12	2025-2026前沿发现的强效中和单抗/阻断病毒侵入血管内皮细胞	source_to_target	\N	\N	\N	0.6	biomedical	therapeutic_countermeasure	2026-06-06 09:35:15.018489+12
466	66	64	typed	8.5	1	2026-06-06 09:35:15.018489+12	从康复者B细胞提取的广谱中和单抗/具备将重症参数从死亡边缘拉回的能力	source_to_target	\N	\N	\N	0.6	biomedical	therapeutic_countermeasure	2026-06-06 09:35:15.018489+12
467	69	64	typed	7	1	2026-06-06 09:35:15.018489+12	2026年5月邮轮汉坦病毒爆发事件/未验证高噪声事件切片	source_to_target	2026-05-01 12:00:00+12	\N	\N	0.3	outbreak	event_to_pathogen	2026-06-06 09:35:15.018489+12
13	3	16	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
12	3	15	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
10	3	13	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
11	3	14	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
44	6	14	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
81	11	16	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
80	11	15	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
58	8	11	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
65	9	11	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
77	11	12	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
468	81	78	typed	8.8	1	2026-06-06 10:02:31.964818+12	主办桌面大流行推演模拟未知病原体跨国扩散	source_to_target	\N	\N	\N	0.65	biomedical	pandemic_simulation	2026-06-06 10:02:31.964818+12
469	83	78	typed	6.5	1	2026-06-06 10:02:31.964818+12	高噪声预言叙事：2026年肺部与鼠疫特征混合瘟疫	source_to_target	\N	\N	\N	0.15	prophecy	high_noise_prediction	2026-06-06 10:02:31.964818+12
470	59	82	typed	9	1	2026-06-06 10:02:31.964818+12	多边技术治理、公共卫生防线与数字身份议程融合的核心平台	source_to_target	\N	\N	\N	0.8	governance	framework_carrier	2026-06-06 10:02:31.964818+12
471	59	79	typed	8.8	1	2026-06-06 10:02:31.964818+12	达沃斯论坛作为联合发起平台推动该防范组织	source_to_target	\N	\N	\N	0.75	governance	joint_initiation	2026-06-06 10:02:31.964818+12
472	85	86	typed	5.5	1	2026-06-06 10:02:31.964818+12	传统古籍对丙午丁未赤马红羊灾异周期的对应记载	source_to_target	\N	\N	\N	0.1	cultural	traditional_mapping	2026-06-06 10:02:31.964818+12
473	69	78	typed	7.5	1	2026-06-06 10:02:31.964818+12	邮轮爆发事件在时间线上引燃混合X疾病恐慌舆情	source_to_target	2026-05-15 12:00:00+12	\N	\N	0.4	outbreak	event_to_concept	2026-06-06 10:02:31.964818+12
78	11	13	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
79	11	14	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
91	15	16	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
63	8	16	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
70	9	16	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
85	12	16	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
88	13	16	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
90	14	16	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
62	8	15	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
69	9	15	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
84	12	15	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
87	13	15	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
89	14	15	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
56	8	9	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
59	8	12	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
60	8	13	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
61	8	14	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
66	9	12	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
67	9	13	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
68	9	14	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
82	12	13	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
83	12	14	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
86	13	14	co_occurrence	5	5	2026-05-25 12:25:06.420091+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
474	74	75	typed	8.8	1	2026-06-06 10:02:31.964818+12	自媒体节目主讲人/前美军研究所病毒学学者背景	source_to_target	\N	\N	\N	0	media	anchor_to_program	2026-06-06 10:02:31.964818+12
475	76	70	typed	8.5	1	2026-06-06 10:02:31.964818+12	官方认定随人类贸易与航运全球扩散的汉坦毒株	source_to_target	\N	\N	\N	0	scientific	classification	2026-06-06 10:02:31.964818+12
476	76	64	typed	8.5	1	2026-06-06 10:02:31.964818+12	国际病毒分类委员会规范化确认的高致死株分类	source_to_target	\N	\N	\N	0	scientific	classification	2026-06-06 10:02:31.964818+12
477	75	69	typed	8.2	1	2026-06-06 10:02:31.964818+12	跟踪报道并分析该邮轮汉坦病毒突发感染事件	source_to_target	\N	\N	\N	0	media	topic_coverage	2026-06-06 10:02:31.964818+12
478	75	63	typed	8	1	2026-06-06 10:02:31.964818+12	节目深度剖析全球汉坦病毒自然宿主与变异态势	source_to_target	\N	\N	\N	0	media	topic_coverage	2026-06-06 10:02:31.964818+12
479	77	78	typed	9	1	2026-06-06 10:02:31.964818+12	世界卫生组织提出的未知病原体引发大流行防御概念	source_to_target	\N	\N	\N	0.5	governance	concept_definition	2026-06-06 10:02:31.964818+12
480	86	78	typed	6	1	2026-06-06 10:02:31.964818+12	民间叙事将传统灾异周期与现代生物危机挂钩	source_to_target	\N	\N	\N	0.2	cultural	psychological_resonance	2026-06-06 10:02:31.964818+12
481	73	82	typed	9.2	1	2026-06-06 10:02:31.964818+12	通过WEF框架推行技术官僚与全球化宏观议程	source_to_target	\N	\N	\N	0.8	governance	agenda_setting	2026-06-06 10:02:31.964818+12
482	62	81	typed	8.8	1	2026-06-06 10:02:31.964818+12	资本网络资助支持全球卫生防御能力评估与演习	source_to_target	\N	\N	\N	0.7	philanthropy	research_funder	2026-06-06 10:02:31.964818+12
483	62	79	typed	9.2	1	2026-06-06 10:02:31.964818+12	通过基金会出资参与流行病防范创新联盟建设	source_to_target	\N	\N	\N	0.85	philanthropy	founder_funding	2026-06-06 10:02:31.964818+12
484	72	82	typed	8.8	1	2026-06-06 10:02:31.964818+12	资助全球多边组织建立卫生与数字防御治理体系	source_to_target	\N	\N	\N	0.75	governance	financial_driver	2026-06-06 10:02:31.964818+12
485	72	80	typed	9.5	1	2026-06-06 10:02:31.964818+12	长期核心资助方向全球多边疫苗免疫网络输出影响力	source_to_target	\N	\N	\N	0.85	philanthropy	strategic_funder	2026-06-06 10:02:31.964818+12
486	84	78	typed	6	1	2026-06-06 10:02:31.964818+12	高噪声灵媒叙事：2026年新型瘟疫交叉扩散	source_to_target	\N	\N	\N	0.1	prophecy	high_noise_prediction	2026-06-06 10:02:31.964818+12
487	79	78	typed	8.5	1	2026-06-06 10:02:31.964818+12	针对未知潜在X疾病进行疫苗/抗体技术储备研究	source_to_target	\N	\N	\N	0.6	biomedical	countermeasure_rnd	2026-06-06 10:02:31.964818+12
504	78	91	conspiracy_narrative	7	1	2026-06-06 10:02:54.543596+12	民间替代性叙事：达沃斯精英集团预谋的危机恐慌制造工具	source_to_target	\N	\N	\N	0.85	population_control_conspiracy	alternative_narrative	2026-06-06 10:02:54.543596+12
489	69	100	biological_fact	9.680000000000001	2	2026-06-06 10:02:54.543596+12	流行病学事实：航运途中接触野生啮齿类排泄物导致的意外感染	source_to_target	2026-05-15 12:00:00+12	\N	\N	0	outbreak_investigation	fact_mapping	2026-06-06 19:25:16.478271+12
490	83	99	skeptic_claim	8.8	2	2026-06-06 10:02:54.543596+12	理性分析：高频泛化灾难词汇后的幸存者偏差与流量炒作附会	source_to_target	\N	\N	\N	0	cognitive_bias_analysis	scientific_skepticism	2026-06-06 19:25:16.478271+12
491	93	95	typed	9.02	2	2026-06-06 10:02:54.543596+12	目的对齐：生物技术、金融垄断与人口治理叙事合流	undirected	\N	\N	\N	0.7	narrative_alignment	core_overlap	2026-06-06 19:25:16.478271+12
492	59	95	conspiracy_narrative	7.92	2	2026-06-06 10:02:54.543596+12	主权主义者控诉：建立跨国财阀极权统治的影子世界政府	source_to_target	\N	\N	\N	0.9	deep_state_conspiracy	alternative_narrative	2026-06-06 19:25:16.478271+12
493	64	87	epistemic_consensus	9.9	2	2026-06-06 10:02:54.543596+12	官方/主流科学界共识：自然突变与啮齿类动物宿主跨物种扩散	source_to_target	\N	\N	\N	0	scientific_consensus	fact_mapping	2026-06-06 19:25:16.478271+12
494	78	90	official_narrative	10	2	2026-06-06 10:02:54.543596+12	WHO官方释义：未来未知大流行病原体的全球前瞻性卫生协同防御防线	source_to_target	\N	\N	\N	0.1	global_health_security	official_framework	2026-06-06 19:25:16.478271+12
495	64	88	epistemic_contradiction	7.4799999999999995	2	2026-06-06 10:02:54.543596+12	自媒体/民间质疑：存在功能增益研究或人工合成痕迹	source_to_target	\N	\N	\N	0.75	laboratory_leak_suspicion	alternative_narrative	2026-06-06 19:25:16.478271+12
496	62	92	positive_profile	9.680000000000001	2	2026-06-06 10:02:54.543596+12	官方与主流媒体定位：全球公共卫生独立资助人	source_to_target	\N	\N	\N	0	philanthropy_advocacy	official_profile	2026-06-06 19:25:16.478271+12
497	69	101	leak_suspicion	6.38	2	2026-06-06 10:02:54.543596+12	网络激进舆情：未公开混合X病毒株的定向压力投放实验叙事	source_to_target	2026-05-16 12:00:00+12	\N	\N	0.7	clandestine_operation	alternative_narrative	2026-06-06 19:25:16.478271+12
498	88	89	typed	8.8	2	2026-06-06 10:02:54.543596+12	理论内核重合：均主张非自然演化的非对称干预视角	undirected	\N	\N	\N	0.5	narrative_alignment	core_overlap	2026-06-06 19:25:16.478271+12
499	79	102	official_mission	9.569999999999999	2	2026-06-06 10:02:54.543596+12	公共卫生学界共识：缩短新型疫苗与中和抗体研发周期	source_to_target	\N	\N	\N	0	medical_rnd_accelerator	official_framework	2026-06-06 19:25:16.478271+12
500	91	97	typed	9.35	2	2026-06-06 10:02:54.543596+12	战略规划合流：将大流行视为科技官僚治理催化剂	undirected	\N	\N	\N	0.6	narrative_alignment	core_overlap	2026-06-06 19:25:16.478271+12
488	79	103	critical_narrative	6.82	2	2026-06-06 10:02:54.543596+12	反达沃斯叙事：通过强制免疫影响跨国卫生主权的地缘经济工具	source_to_target	\N	\N	\N	0.75	medical_hegemony	alternative_narrative	2026-06-06 19:25:16.478271+12
501	73	97	conspiracy_narrative	7.4799999999999995	2	2026-06-06 10:02:54.543596+12	批判叙事描绘：强推大重构与科技官僚治理的幕后推手	source_to_target	\N	\N	\N	0.8	technocracy_dictatorship	alternative_narrative	2026-06-06 19:25:16.478271+12
502	73	96	official_narrative	9.35	2	2026-06-06 10:02:54.543596+12	主流媒体描述：利益相关者资本主义倡导者与论坛创始人	source_to_target	\N	\N	\N	0	stakeholder_capitalism	official_profile	2026-06-06 19:25:16.478271+12
503	101	91	typed	7.7	2	2026-06-06 10:02:54.543596+12	战术落地映射：将突发事件编织进宏大预谋控制论模型	source_to_target	\N	\N	\N	0.65	narrative_absorption	event_to_conspiracy	2026-06-06 19:25:16.478271+12
524	78	91	conspiracy_narrative	7	1	2026-06-06 19:25:16.478271+12	替代性叙事：达沃斯精英集团预谋的危机恐慌制造工具	source_to_target	\N	\N	\N	0.85	population_control_conspiracy	alternative_narrative	2026-06-06 19:25:16.478271+12
505	59	94	official_narrative	9.9	2	2026-06-06 10:02:54.543596+12	官方自我定位：促进公私合作与全球化治理的多边主义平台	source_to_target	\N	\N	\N	0	multilateral_governance	official_framework	2026-06-06 19:25:16.478271+12
506	83	98	prophecy_claim	6.6	2	2026-06-06 10:02:54.543596+12	民间神秘学叙事：2026赤马红羊年混合瘟疫女先知	source_to_target	\N	\N	\N	0.15	supernatural_prophecy	high_noise_claim	2026-06-06 19:25:16.478271+12
507	62	93	negative_profile	7.15	2	2026-06-06 10:02:54.543596+12	反全球化思潮指控：借疫苗计划推行人口削减与数字监控	source_to_target	\N	\N	\N	0.8	population_reduction_narrative	alternative_narrative	2026-06-06 19:25:16.478271+12
101	16	18	typed	1.5	2	2026-05-25 19:59:58.661492+12	political_opposition	source_to_target	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
102	16	19	typed	1.5	2	2026-05-25 19:59:58.661492+12	political_alignment	source_to_target	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
103	18	16	typed	1.5	2	2026-05-25 19:59:58.661492+12	political_opposition	source_to_target	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
335	16	17	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
336	16	18	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
337	16	19	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
338	16	20	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
339	16	21	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
340	16	22	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
341	16	23	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
342	16	24	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
343	16	25	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
344	16	26	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
345	16	27	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
346	16	28	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
347	16	29	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
348	16	30	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
349	16	31	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
114	16	32	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
139	16	33	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
163	16	34	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
186	16	35	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
208	16	36	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
229	16	37	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
249	16	38	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
268	16	39	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
286	16	40	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
303	16	41	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
319	16	42	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
350	17	18	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
351	17	19	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
352	17	20	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
353	17	21	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
354	17	22	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
355	17	23	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
356	17	24	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
357	17	25	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
358	17	26	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
359	17	27	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
360	17	28	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
361	17	29	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
362	17	30	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
363	17	31	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
115	17	32	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
140	17	33	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
164	17	34	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
187	17	35	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
209	17	36	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
230	17	37	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
250	17	38	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
269	17	39	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
287	17	40	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
304	17	41	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
320	17	42	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
364	18	19	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
365	18	20	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
366	18	21	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
367	18	22	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
368	18	23	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
369	18	24	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
370	18	25	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
371	18	26	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
372	18	27	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
373	18	28	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
374	18	29	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
375	18	30	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
376	18	31	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
116	18	32	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
141	18	33	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
165	18	34	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
188	18	35	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
210	18	36	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
231	18	37	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
251	18	38	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
270	18	39	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
288	18	40	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
305	18	41	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
321	18	42	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
377	19	20	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
378	19	21	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
379	19	22	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
380	19	23	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
381	19	24	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
382	19	25	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
383	19	26	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
384	19	27	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
385	19	28	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
386	19	29	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
387	19	30	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
388	19	31	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
117	19	32	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
142	19	33	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
166	19	34	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
189	19	35	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
211	19	36	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
232	19	37	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
252	19	38	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
271	19	39	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
289	19	40	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
306	19	41	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
322	19	42	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
389	20	21	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
390	20	22	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
391	20	23	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
392	20	24	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
393	20	25	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
394	20	26	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
395	20	27	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
396	20	28	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
397	20	29	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
398	20	30	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
399	20	31	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
118	20	32	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
143	20	33	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
167	20	34	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
190	20	35	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
212	20	36	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
233	20	37	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
253	20	38	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
272	20	39	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
290	20	40	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
307	20	41	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
323	20	42	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
400	21	22	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
401	21	23	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
402	21	24	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
403	21	25	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
404	21	26	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
405	21	27	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
406	21	28	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
407	21	29	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
408	21	30	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
409	21	31	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
119	21	32	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
144	21	33	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
168	21	34	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
191	21	35	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
213	21	36	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
234	21	37	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
254	21	38	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
273	21	39	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
291	21	40	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
308	21	41	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
324	21	42	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
410	22	23	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
411	22	24	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
412	22	25	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
413	22	26	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
414	22	27	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
415	22	28	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
416	22	29	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
417	22	30	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
418	22	31	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
120	22	32	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
145	22	33	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
169	22	34	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
192	22	35	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
214	22	36	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
235	22	37	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
255	22	38	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
274	22	39	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
292	22	40	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
309	22	41	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
325	22	42	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
419	23	24	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
420	23	25	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
421	23	26	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
422	23	27	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
423	23	28	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
424	23	29	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
425	23	30	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
426	23	31	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
121	23	32	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
146	23	33	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
170	23	34	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
193	23	35	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
215	23	36	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
236	23	37	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
256	23	38	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
275	23	39	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
293	23	40	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
310	23	41	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
326	23	42	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
427	24	25	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
428	24	26	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
429	24	27	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
430	24	28	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
431	24	29	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
432	24	30	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
433	24	31	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
122	24	32	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
147	24	33	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
171	24	34	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
194	24	35	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
216	24	36	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
237	24	37	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
257	24	38	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
276	24	39	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
294	24	40	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
311	24	41	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
327	24	42	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
434	25	26	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
435	25	27	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
436	25	28	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
437	25	29	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
438	25	30	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
439	25	31	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
123	25	32	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
148	25	33	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
172	25	34	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
195	25	35	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
217	25	36	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
238	25	37	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
258	25	38	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
277	25	39	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
295	25	40	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
312	25	41	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
328	25	42	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
440	26	27	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
441	26	28	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
442	26	29	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
443	26	30	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
444	26	31	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
124	26	32	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
149	26	33	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
173	26	34	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
196	26	35	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
218	26	36	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
239	26	37	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
259	26	38	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
278	26	39	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
296	26	40	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
313	26	41	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
329	26	42	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
445	27	28	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
446	27	29	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
447	27	30	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
448	27	31	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
125	27	32	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
150	27	33	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
174	27	34	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
197	27	35	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
219	27	36	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
240	27	37	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
260	27	38	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
279	27	39	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
297	27	40	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
314	27	41	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
330	27	42	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
449	28	29	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
450	28	30	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
451	28	31	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
126	28	32	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
151	28	33	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
175	28	34	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
198	28	35	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
220	28	36	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
241	28	37	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
261	28	38	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
280	28	39	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
298	28	40	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
315	28	41	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
331	28	42	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
452	29	30	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
453	29	31	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
127	29	32	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
152	29	33	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
176	29	34	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
199	29	35	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
221	29	36	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
242	29	37	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
262	29	38	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
281	29	39	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
299	29	40	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
316	29	41	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
332	29	42	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
454	30	31	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
128	30	32	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
153	30	33	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
177	30	34	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
200	30	35	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
222	30	36	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
243	30	37	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
263	30	38	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
282	30	39	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
300	30	40	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
317	30	41	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
333	30	42	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
129	31	32	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
154	31	33	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
178	31	34	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
201	31	35	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
223	31	36	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
244	31	37	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
264	31	38	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
283	31	39	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
301	31	40	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
318	31	41	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
334	31	42	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
104	32	33	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
105	32	34	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
106	32	35	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
107	32	36	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
108	32	37	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
109	32	38	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
110	32	39	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
111	32	40	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
112	32	41	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
113	32	42	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
130	33	34	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
131	33	35	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
132	33	36	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
133	33	37	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
134	33	38	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
135	33	39	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
136	33	40	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
137	33	41	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
138	33	42	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
155	34	35	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
156	34	36	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
157	34	37	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
158	34	38	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
159	34	39	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
160	34	40	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
161	34	41	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
162	34	42	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
179	35	36	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
180	35	37	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
181	35	38	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
182	35	39	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
183	35	40	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
184	35	41	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
185	35	42	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
202	36	37	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
203	36	38	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
204	36	39	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
205	36	40	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
206	36	41	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
207	36	42	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
224	37	38	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
225	37	39	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
226	37	40	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
227	37	41	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
228	37	42	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
245	38	39	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
246	38	40	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
247	38	41	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
248	38	42	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
265	39	40	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
266	39	41	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
267	39	42	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
284	40	41	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
285	40	42	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
302	41	42	co_occurrence	2	2	2026-05-25 19:59:58.661492+12	\N	undirected	\N	\N	\N	0	\N	\N	2026-05-26 08:32:47.28815+12
\.


--
-- Data for Name: cognitive_edges; Type: TABLE DATA; Schema: ccc; Owner: postgres
--

COPY ccc.cognitive_edges (id, source_node_id, target_node_id, relation_type, weight, created_at) FROM stdin;
\.


--
-- Data for Name: cognitive_nodes; Type: TABLE DATA; Schema: ccc; Owner: postgres
--

COPY ccc.cognitive_nodes (id, entity_id, document_id, node_type, content, confidence, confidence_decay, decay_rate, valid_from, valid_until, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: contradiction_engine; Type: TABLE DATA; Schema: ccc; Owner: postgres
--

COPY ccc.contradiction_engine (id, entity_id, entity_name, official_narrative, counter_signals, real_indicators, narrative_gap, confidence_decay, severity, source_labels, trust_levels, last_updated, is_active, created_at) FROM stdin;
1	59	WEF	WEF是开放包容的全球治理论坛，服务全人类利益	{参与门槛极高,议程由少数精英设定,利益相关者资本主义绕过民主程序}	{成员构成分析,议程设定流程,政策落地与达沃斯共识相关性}	0.6	-0.12	moderate	{WEF官网,年度报告}	{T3,T3}	2026-05-27 22:32:58.247403+12	t	2026-05-27 22:32:58.247403+12
2	16	习近平	中国经济稳定复苏，改革开放持续深化	{青年失业率历史高位,房地产持续下行,地方债危机扩散,外资撤离加速}	{PMI持续低迷,消费信心指数下降,出口增速放缓,M2与GDP剪刀差扩大}	0.82	-0.25	critical	{官方GDP数据,人民日报,新华社}	{T6,T6,T6}	2026-05-27 22:32:58.247403+12	t	2026-05-27 22:32:58.247403+12
3	16	习近平	台湾问题可以和平解决，北京无意动武	{军事演习频率上升,对台军购阻挠,解放军现代化加速,统一时间表叙事强化}	{台海军事预算增加,海峡中线突破常态化,航母战斗群部署}	0.75	-0.2	strong	{官方声明,外交辞令}	{T6,T6}	2026-05-27 22:32:58.247403+12	t	2026-05-27 22:32:58.247403+12
4	34	中共	中国是维护全球自由贸易秩序的重要力量	{对澳大利亚经济胁迫,稀土出口限制,华为供应链切断,一带一路债务陷阱}	{贸易武器化案例增加,技术脱钩加速,关键矿产控制}	0.8	-0.18	strong	{商务部声明,外交部发言}	{T6,T6}	2026-05-27 22:32:58.247403+12	t	2026-05-27 22:32:58.247403+12
5	34	中共	新冠病毒源于自然界，中国第一时间透明通报	{早期预警压制,李文亮事件,病毒序列延迟公布,武汉实验室调查阻碍}	{WHO调查受限,早期样本销毁报告,哨兵病例时间线}	0.85	-0.3	critical	{国家卫健委,外交部,WHO联合报告}	{T6,T6,T3}	2026-05-27 22:32:58.247403+12	t	2026-05-27 22:32:58.247403+12
6	35	美联储	美联储完全独立于政治压力，决策基于数据	{2019年特朗普压力下降息,2020年MMT边界模糊,政治周期与货币周期重合}	{利率决定与选举周期相关性,主席任命政治化,国会听证施压记录}	0.55	-0.1	moderate	{联储声明,FOMC纪要}	{T2,T2}	2026-05-27 22:32:58.247403+12	t	2026-05-27 22:32:58.247403+12
7	60	普京	俄罗斯特别军事行动目标有限，随时可以谈判	{战线持续扩大,民用基础设施攻击,核威胁升级,谈判条件不断提高}	{导弹袭击城市,战争预算占GDP比例上升,动员规模持续扩大}	0.78	-0.22	strong	{克里姆林宫声明,RT,塔斯社}	{T6,T6,T6}	2026-05-27 22:35:47.824737+12	t	2026-05-27 22:35:47.824737+12
8	60	普京	俄罗斯经济在制裁下保持稳定，卢布坚挺	{实际购买力下降,技术进口中断,影子舰队绕制裁,人才外逃加速}	{真实通胀率,进口替代失败案例,GDP构成军工化}	0.72	-0.18	strong	{俄罗斯央行数据,官方媒体}	{T6,T6}	2026-05-27 22:35:47.824737+12	t	2026-05-27 22:35:47.824737+12
\.


--
-- Data for Name: contradictions; Type: TABLE DATA; Schema: ccc; Owner: postgres
--

COPY ccc.contradictions (id, node_id, contradiction, alternative_model, source_document_id, severity, created_at, entity_id, claim_text, counter_evidence, source_label, confidence_impact, is_active, verified_at) FROM stdin;
\.


--
-- Data for Name: documents; Type: TABLE DATA; Schema: ccc; Owner: postgres
--

COPY ccc.documents (id, raw_document_id, content, content_hash, created_at) FROM stdin;
2	2	{"title": "1997中共元老排位——薄一波家族关系网络", "category": "PERSON", "language": "zh", "source_type": "xmind", "source_url": null, "verified": false, "entities": [{"name": "薄一波", "type": "PERSON", "role": "中共元老", "aliases": [], "notes": "见风使舵，1987带头力主胡耀邦下台"}, {"name": "薄熙来", "type": "PERSON", "role": "薄一波之子", "aliases": [], "notes": ""}, {"name": "胡明", "type": "PERSON", "role": "薄熙来第一任女秘书/前妻", "aliases": [], "notes": ""}, {"name": "李丹宇", "type": "PERSON", "role": "解放军北京军区军医，薄熙来前妻", "aliases": [], "notes": ""}, {"name": "谷开来", "type": "PERSON", "role": "薄熙来现妻", "aliases": [], "notes": ""}, {"name": "宋任穷", "type": "PERSON", "role": "中共元老，中顾委主任", "aliases": [], "notes": ""}, {"name": "林宗棠", "type": "PERSON", "role": "航天工业部长", "aliases": [], "notes": ""}, {"name": "张红文", "type": "PERSON", "role": "中航科工集团第三研究院副院长", "aliases": [], "notes": "枞阳帮，被李希一网打尽"}, {"name": "曹建国", "type": "PERSON", "role": "中央候补委员，副部级", "aliases": [], "notes": "枞阳帮"}, {"name": "杨尚坤", "type": "PERSON", "role": "中共元老", "aliases": [], "notes": ""}, {"name": "万里", "type": "PERSON", "role": "中共元老", "aliases": [], "notes": "安徽土地责任承包制"}, {"name": "宋平", "type": "PERSON", "role": "左派，支持习近平，原周恩来秘书", "aliases": [], "notes": ""}, {"name": "李希", "type": "PERSON", "role": "习近平派系", "aliases": [], "notes": "打击安徽枞阳帮"}, {"name": "习近平", "type": "PERSON", "role": "中共总书记", "aliases": ["xjp", "包子"], "notes": ""}], "events": [{"date": "1987", "summary": "薄一波带头力主胡耀邦下台", "persons": ["薄一波", "胡耀邦"]}, {"date": "1988-04", "summary": "林宗棠担任航天工业部长", "persons": ["林宗棠", "宋任穷"]}, {"date": "1978", "summary": "薄熙来与李丹宇在北大婚外恋", "persons": ["薄熙来", "李丹宇"]}, {"date": "1981", "summary": "薄熙来与李丹宇离婚", "persons": ["薄熙来", "李丹宇"]}, {"date": "2013-04-25", "summary": "张红文任中航科工集团第三研究院副院长", "persons": ["张红文"]}, {"date": "2024-10-17", "summary": "习近平去安徽视察火箭军61基地", "persons": ["习近平"]}, {"date": "2024-10", "summary": "枞阳帮覆灭，曹建国、张红文等被抓", "persons": ["曹建国", "张红文", "陆克华"]}], "claims": [{"text": "张红文被抓佐证习近平下台", "confidence": 0.3, "source": null}, {"text": "宋任穷代表中顾委支持六四镇压", "confidence": 0.7, "source": null}], "raw_content": "1997中共元老排位，薄一波家族及张红文案相关网络"}	52093c81e155846a706daddbdcb3c99a	2026-05-25 12:25:06.420091+12
6	6	{"title": "1997中共元老排位——薄一波家族关系网络", "category": "PERSON", "language": "zh", "source_type": "xmind", "verified": false, "entities": [{"name": "薄一波", "type": "PERSON", "role": "中共元老", "aliases": [], "relations": [{"to": "薄熙来", "type": "family_relation", "direction": "source_to_target"}, {"to": "习近平", "type": "political_alignment", "direction": "undirected"}, {"to": "胡耀邦", "type": "political_opposition", "direction": "source_to_target"}]}, {"name": "薄熙来", "type": "PERSON", "role": "薄一波之子", "aliases": [], "relations": [{"to": "薄一波", "type": "family_relation", "direction": "source_to_target"}, {"to": "胡明", "type": "marriage", "direction": "source_to_target"}, {"to": "谷开来", "type": "marriage", "direction": "source_to_target"}, {"to": "李丹宇", "type": "marriage", "direction": "source_to_target"}]}, {"name": "张红文", "type": "PERSON", "role": "中航科工集团副院长", "aliases": [], "relations": [{"to": "曹建国", "type": "mentor_student", "direction": "target_to_source"}, {"to": "习近平", "type": "political_alignment", "direction": "undirected"}, {"to": "李希", "type": "investigated_by", "direction": "source_to_target"}]}, {"name": "胡明", "type": "PERSON", "role": "薄熙来前妻", "aliases": [], "relations": []}, {"name": "谷开来", "type": "PERSON", "role": "薄熙来现妻", "aliases": [], "relations": []}, {"name": "李丹宇", "type": "PERSON", "role": "薄熙来前妻", "aliases": [], "relations": []}, {"name": "曹建国", "type": "PERSON", "role": "中央候补委员", "aliases": [], "relations": []}, {"name": "习近平", "type": "PERSON", "role": "中共总书记", "aliases": ["xjp", "包子"], "relations": []}, {"name": "李希", "type": "PERSON", "role": "习近平派系", "aliases": [], "relations": []}, {"name": "宋任穷", "type": "PERSON", "role": "中共元老", "aliases": [], "relations": []}, {"name": "林宗棠", "type": "PERSON", "role": "航天工业部长", "aliases": [], "relations": []}, {"name": "杨尚坤", "type": "PERSON", "role": "中共元老", "aliases": [], "relations": []}, {"name": "万里", "type": "PERSON", "role": "中共元老", "aliases": [], "relations": []}, {"name": "宋平", "type": "PERSON", "role": "原周恩来秘书", "aliases": [], "relations": []}], "events": [{"date": "1987", "summary": "薄一波带头力主胡耀邦下台", "persons": ["薄一波", "胡耀邦"]}, {"date": "1988-04", "summary": "林宗棠担任航天工业部长", "persons": ["林宗棠"]}, {"date": "2024-10", "summary": "枞阳帮覆灭，曹建国、张红文等被抓", "persons": ["曹建国", "张红文"]}], "claims": [], "raw_content": "1997中共元老排位，薄一波家族及张红文案相关网络"}	b54ccc50634cbba7e367cc94e5ebf1cd	2026-05-25 14:03:23.524269+12
7	7	{"title": "全球事件时间线 2019-2026", "category": "EVENT", "language": "zh", "source_type": "excel_timeline", "verified": false, "entities": [{"name": "习近平", "type": "PERSON", "role": "中共总书记", "aliases": ["包子"], "relations": [{"to": "马云", "type": "political_opposition", "direction": "source_to_target"}, {"to": "石正丽", "type": "political_alignment", "direction": "source_to_target"}]}, {"name": "特朗普", "type": "PERSON", "role": "美国总统", "aliases": ["川普"], "relations": []}, {"name": "马云", "type": "PERSON", "role": "阿里巴巴创始人", "aliases": [], "relations": [{"to": "习近平", "type": "political_opposition", "direction": "source_to_target"}]}, {"name": "石正丽", "type": "PERSON", "role": "武汉病毒研究所研究员", "aliases": [], "relations": []}, {"name": "Joe Biden", "type": "PERSON", "role": "美国总统", "aliases": [], "relations": []}, {"name": "Pavel Dourov", "type": "PERSON", "role": "Telegram创始人", "aliases": [], "relations": []}, {"name": "Javier Milei", "type": "PERSON", "role": "阿根廷总统", "aliases": [], "relations": []}, {"name": "Irakli Kobakhidze", "type": "PERSON", "role": "格鲁吉亚总理", "aliases": [], "relations": []}, {"name": "Jeffrey Epstein", "type": "PERSON", "role": "美国富豪", "aliases": [], "relations": []}, {"name": "Alexander Shiplyuk", "type": "PERSON", "role": "俄罗斯物理学家", "aliases": [], "relations": []}, {"name": "Steve Bannon", "type": "PERSON", "role": "特朗普顾问", "aliases": ["班农"], "relations": []}, {"name": "李家超", "type": "PERSON", "role": "香港行政长官", "aliases": [], "relations": []}, {"name": "田文华", "type": "PERSON", "role": "三鹿奶粉董事长", "aliases": [], "relations": []}, {"name": "胡锦涛", "type": "PERSON", "role": "中共前总书记", "aliases": [], "relations": []}, {"name": "蔡英文", "type": "PERSON", "role": "台湾总统", "aliases": [], "relations": []}, {"name": "周正毅", "type": "PERSON", "role": "上海商人", "aliases": [], "relations": []}, {"name": "哈马斯", "type": "ORG", "role": "巴勒斯坦武装组织", "aliases": [], "relations": []}, {"name": "ISIS", "type": "ORG", "role": "伊斯兰国", "aliases": ["ISIS-k"], "relations": []}, {"name": "中共", "type": "ORG", "role": "中国共产党", "aliases": [], "relations": []}, {"name": "美联储", "type": "ORG", "role": "美国联邦储备系统", "aliases": [], "relations": []}, {"name": "阿里巴巴", "type": "ORG", "role": "中国科技公司", "aliases": [], "relations": []}, {"name": "香港", "type": "GPE", "role": "中国特别行政区", "aliases": [], "relations": []}, {"name": "台湾", "type": "GPE", "role": "地区", "aliases": [], "relations": []}, {"name": "乌克兰", "type": "GPE", "role": "国家", "aliases": [], "relations": []}, {"name": "俄罗斯", "type": "GPE", "role": "国家", "aliases": [], "relations": []}, {"name": "以色列", "type": "GPE", "role": "国家", "aliases": [], "relations": []}, {"name": "新疆", "type": "GPE", "role": "中国自治区", "aliases": [], "relations": []}], "events": [{"date": "2019-07-21", "location": "香港", "summary": "香港元朗白衣人无差别袭击市民事件", "persons": []}, {"date": "2020-01-20", "location": "中国", "summary": "新冠疫情COVID-19全球爆发", "persons": ["石正丽"]}, {"date": "2020-02-18", "location": "美国", "summary": "美联储放水", "persons": []}, {"date": "2020-05-16", "location": "台湾", "summary": "民进党蔡英文就任总统", "persons": ["蔡英文"]}, {"date": "2021-01-06", "location": "美国", "summary": "国会山闯入暴乱", "persons": ["特朗普"]}, {"date": "2021-04-18", "location": "上海", "summary": "周正毅再次出狱在上海万达瑞华酒店举办60岁寿宴", "persons": ["周正毅"]}, {"date": "2021-10-03", "location": null, "summary": "潘多拉文件Pandora Papers发布", "persons": []}, {"date": "2022-02-20", "location": "乌克兰", "summary": "俄罗斯入侵乌克兰，中共常委讨论7天执行经济沉船计划", "persons": []}, {"date": "2022-03-10", "location": "中国", "summary": "习近平第三届连任", "persons": ["习近平"]}, {"date": "2022-03-28", "location": "上海", "summary": "上海封城", "persons": []}, {"date": "2022-10-23", "location": "北京", "summary": "二十大胡锦涛被架走", "persons": ["胡锦涛"]}, {"date": "2022-10-23", "location": null, "summary": "马云外滩21分钟演讲炮轰巴塞尔协议得罪习近平", "persons": ["马云", "习近平"]}, {"date": "2022-11-26", "location": "新疆", "summary": "乌鲁木齐火灾引发白纸革命，民众高喊共产党下台习近平下台", "persons": ["习近平"]}, {"date": "2023-07-28", "location": "北京", "summary": "水淹北京", "persons": []}, {"date": "2023-07-28", "location": "法国", "summary": "Telegram创始人Pavel Dourov在法国被捕", "persons": ["Pavel Dourov"]}, {"date": "2023-08-16", "location": "新加坡", "summary": "新加坡警方破获福建帮大宗洗钱案查获2300多万新元现金数百件精品首饰", "persons": []}, {"date": "2023-09-15", "location": "美国", "summary": "美国三大汽车厂大罢工UAW", "persons": []}, {"date": "2023-09-26", "location": "德国", "summary": "美国炸俄罗斯德国北溪2号Nord Stream2", "persons": []}, {"date": "2023-10-07", "location": "以色列", "summary": "哈马斯五千火箭弹袭击以色列1400+人死绑架200+人", "persons": []}, {"date": "2023-10-08", "location": "芬兰", "summary": "中共新新北极熊号破坏芬兰湾波罗的海连接管道Baltic connector pipeline", "persons": []}, {"date": "2023-10-15", "location": "中国", "summary": "中共政府遣返2600名朝鲜脱北者", "persons": []}, {"date": "2023-10-18", "location": "加沙", "summary": "哈马斯自爆加沙医院AHLI ARAB Hospital死亡10-50人", "persons": []}, {"date": "2023-10-25", "location": "澳大利亚", "summary": "澳大利亚联邦警察AFP突击华人最大换汇公司长江换汇", "persons": []}, {"date": "2023-11-13", "location": "土耳其", "summary": "伊斯坦堡塔克西姆广场独立大街爆炸案数十人死伤", "persons": []}, {"date": "2023-11-16", "location": "美国", "summary": "SEC披露马云家族信托计划减持阿里巴巴股份", "persons": ["马云"]}, {"date": "2024-01-01", "location": "日本", "summary": "日本7.6级强震", "persons": []}, {"date": "2024-01-20", "location": "美国", "summary": "川普上任", "persons": ["特朗普"]}, {"date": "2024-03-22", "location": "俄罗斯", "summary": "ISIS Khorasan恐怖袭击番石花音乐厅", "persons": []}, {"date": "2024-04-05", "location": "俄罗斯", "summary": "哈巴罗夫斯克进入紧急状态核辐射超正常值1600倍", "persons": []}, {"date": "2024-04-19", "location": "伊朗", "summary": "以色列攻击伊朗核基地伊斯法罕", "persons": []}, {"date": "2024-08-13", "location": "香港", "summary": "三鹿奶粉董事长田文华出狱害30万孩子", "persons": ["田文华"]}, {"date": "2024-09-04", "location": "俄罗斯", "summary": "俄判处物理学家Alexander Shiplyuk 15年徒刑被指控向中国泄密超音速飞弹技术", "persons": ["Alexander Shiplyuk"]}, {"date": "2024-09-18", "location": "深圳", "summary": "深圳日本小朋友遇害事件", "persons": []}, {"date": "2024-10-14", "location": "美国", "summary": "美联储量化宽松QE", "persons": []}, {"date": "2024-11-05", "location": "美国", "summary": "特朗普当选美国总统", "persons": ["特朗普"]}, {"date": "2024-12-09", "location": "江苏", "summary": "连云港张宝山韭菜基地高三学生张新伟被杀后家人遭打压", "persons": []}], "claims": [{"text": "习近平和石正丽导致全球4000万人死于非命", "confidence": 0.4, "source": null}, {"text": "美国炸毁Nord Stream2北溪管道", "confidence": 0.7, "source": null}, {"text": "中共新新北极熊号破坏芬兰湾波罗的海管道", "confidence": 0.5, "source": null}, {"text": "白纸革命是中国人达成共识民众高喊共产党下台习近平下台", "confidence": 0.8, "source": null}, {"text": "谢明生关键时刻救了习近平性命", "confidence": 0.5, "source": null}], "raw_content": "全球事件时间线Excel 2019-2026，横轴时间纵轴事件流"}	ad27d45366930f83f209aa30925e3565	2026-05-25 19:59:58.661492+12
10	\N	全球汉坦病毒演化态势：包含黑线姬鼠（HTNV宿主）、褐家鼠（SEOV宿主）。2025-2026年科研突破利用叙利亚仓鼠确立安第斯病毒（Andes virus）人传人重症模型，并开发出 MIB22 和 JL16 强效中和单抗。2026年5月爆发 MV Honduras 邮轮感染事件，引发社会对混合X疾病及传统预言的广泛恐慌。	91122f25ba3d774ef1cb0c339dafdda1	2026-06-06 09:13:51.441658+12
11	\N	世界经济论坛（WEF）由克劳斯·施瓦布（Klaus Schwab）创立。该组织与比尔·盖茨（Bill Gates）及其基金会网络长期在公共卫生、地缘经济、技术治理、数字身份和多边主义议程中形成议程协同。该语料用于补强 WEF、Bill Gates、Klaus Schwab 的文档承接层，而不是把 Bill Gates 直接并入 WEF。	411f43787169c30a95901b5735c61c41	2026-06-06 09:14:10.812552+12
12	\N	【全球公共卫生大流行与多边议程跨域深化语料】自媒体《虚实谈》主讲人林小旭（前美军研究所病毒学者）深入指出，国际病毒分类委员会（ICTV）已对首尔病毒（SEOV）与安第斯病毒等高危汉坦病毒株进行规范化分类监测。在此背景下，世界卫生组织（WHO）推动“混合X疾病”大流行防御概念。全球多边主义精英网络借由世界经济论坛（WEF）及克劳斯·施瓦布推行技术治理；比尔盖茨、盖茨基金会则通过资本网络长期深度资助并影响 CEPI、GAVI 以及约翰斯·霍普金斯卫生安全中心，为未来可能的病原体爆发进行跨国演习推演。与此同时，民间及传统异兆叙事也在此节点产生剧烈共鸣，如泰国神婆普莱、菲律宾灵媒 Rudy Baldwin 对2026赤马红羊年将爆发结合肺部重症与鼠疫特征的混合X疾病预言，以及古籍《地母经》中的大灾灾异记载，进一步加剧了公众对 MV Honduras 邮轮爆发事件等现实疫情的社会恐慌。	5cc474f4e279bd0e9753aa2e3ea2fcbd	2026-06-06 10:02:31.964818+12
13	\N	【矛盾冲突引擎专用：全球大流行叙事多维对立与舆情撕裂分析语料】当前围绕全球公共卫生防御与未知病原体（如安第斯病毒变异、混合X疾病）的演练与爆发，国际社会正呈现出剧烈的多源叙事冲突。主流科学界与世界卫生组织（WHO）坚称所有研究与推演均属于科学前瞻性防御；然而以自媒体《虚实谈》及林小旭为代表的批判视角则质疑其背后存在科学伦理失守与实验室增强/功能增益（Gain of Function）的潜在风险。在宏观治理层，世界经济论坛（WEF）与比尔盖茨将多边主义议程定义为全球治理协同；但民间地缘政治叙事则激烈控诉其本质是深层政府推行人口控制与生物监控的极权剧本。针对 MV Honduras 邮轮爆发事件，生物学事实指向偶发性自然宿主感染，而社交媒体高噪声舆情则将其异化为人为泄露的压力测试。	c3947a9080ebba3a5e5d0c91ce95b252	2026-06-06 10:02:54.543596+12
14	\N	【矛盾冲突引擎专用：全球大流行叙事多维对立与舆情撕裂分析语料】当前围绕全球公共卫生防御与未知病原体（如安第斯病毒变异、混合X疾病）的演练与爆发，国际社会正呈现出剧烈的多源叙事冲突（Epistemic Contradictions）。主流科学界与世界卫生组织（WHO）坚称所有研究与推演均属于科学前瞻性防御；然而以自媒体《虚实谈》及林小旭为代表的批判视角则质疑其背后存在科学伦理失守与实验室增强/功能增益（Gain of Function）的潜在风险。在宏观治理层，世界经济论坛（WEF）与比尔盖茨将多边主义议程定义为全球治理协同；但民间地缘政治叙事则控诉其本质是深层政府推行人口控制与生物监控的极权剧本。针对 MV Honduras 邮轮爆发事件，生物学事实指向偶发性自然宿主感染，而社交媒体高噪声舆情则将其异化为人为泄露的压力测试。	aa019abd8ed0485a965983fd4fda9e5c	2026-06-06 19:25:16.478271+12
\.


--
-- Data for Name: entity_profiles; Type: TABLE DATA; Schema: ccc; Owner: postgres
--

COPY ccc.entity_profiles (id, entity_id, essence, core_drives, behavior_pattern, survival_mode, threat_threshold, mirror_bias, confidence, revision_count, last_revised, created_at, entity_name, entity_type, updated_at) FROM stdin;
1	16	权力安全高于经济稳定	{维护绝对权力,消除潜在威胁,确保政权延续}	{权力集中化,风险规避优先,长期战略布局}	权力集中化	0.85	观察者常低估其对权力安全的优先级，误以为经济压力会迫使其妥协	0.92	0	2026-05-27 17:22:44.393002+12	2026-05-27 17:22:44.393002+12	习近平	person	2026-05-27 17:22:44.393002+12
4	34	稳定压倒一切	{政权延续,社会控制,经济增长合法性}	{维稳优先,分层控制,叙事管理}	政权延续	0.9	经济让步常被误读为根本性政策转变	0.9	0	2026-05-27 17:22:44.393002+12	2026-05-27 17:22:44.393002+12	中共	organization	2026-05-27 17:22:44.393002+12
2	60	帝国历史修复执念	{恢复俄罗斯大国地位,地缘缓冲区控制,历史合法性}	{地缘安全扩张,强人形象维持,历史叙事强化}	地缘安全扩张	0.75	容易被视为单纯机会主义而忽略其历史执念的长期稳定性	0.88	0	2026-05-27 17:22:44.393002+12	2026-05-27 17:22:44.393002+12	普京	person	2026-05-27 17:22:44.393002+12
5	35	技术官僚美元体系守门人	{维持美元信用,防止系统性金融崩盘,控制通胀预期}	{流动性救市,纪律性紧缩,预期管理,危机干预}	美元体系稳定管理	0.7	观察者容易把降息/加息当作立场变化，忽略二者都可能服务于美元体系防御	0.87	0	2026-05-27 17:22:44.393002+12	2026-05-27 17:22:44.393002+12	美联储	institution	2026-06-05 14:48:45.333778+12
3	17	高波动筹码博弈	{制造注意力议题,重置谈判桌,提高交易筹码,维持个人政治品牌}	{极限施压,高频议题制造,规则破坏,协议套现}	重新定价与秩序解构	0.65	观察者容易把其极端表态当作最终目标，忽略其常用极端叫价制造交易空间	0.85	0	2026-05-27 17:22:44.393002+12	2026-05-27 17:22:44.393002+12	特朗普	person	2026-06-05 14:48:45.333778+12
6	59	多边建制派精英治理网络	{全球协调增强,技术官僚治理扩张,跨国精英网络维系,生产资料向顶层网络汇聚}	{议程设定,治理框架推广,公私合营叙事,标准制定权争夺}	精英治理议程设定	0.6	观察者容易把WEF简单阴谋化或理想化，忽略其真实作用是精英网络的议程协调平台	0.78	0	2026-05-27 17:22:44.393002+12	2026-05-27 17:22:44.393002+12	WEF	organization	2026-06-05 14:48:45.333778+12
\.


--
-- Data for Name: entity_resolve_v3_local_expectations; Type: TABLE DATA; Schema: ccc; Owner: postgres
--

COPY ccc.entity_resolve_v3_local_expectations (q, expected_canonical_name, expected_entity_id, expected_match_type, min_confidence, expected_entity_type, note, updated_at) FROM stdin;
China	中共	34	alias_exact	0.98	ORG	RSAL rule: China routes to 中共	2026-06-05 21:40:28.516729+12
PRC	中共	34	alias_exact	0.98	ORG	RSAL rule: PRC routes to 中共	2026-06-05 21:40:28.516729+12
People's Republic of China	中共	34	alias_exact	0.98	ORG	RSAL rule: official state name routes to 中共	2026-06-05 21:40:28.516729+12
中国	中共	34	alias_exact	0.98	ORG	RSAL rule: 中国 routes to 中共	2026-06-05 21:40:28.516729+12
中國	中共	34	alias_exact	0.98	ORG	Traditional Chinese routes to 中共	2026-06-05 21:40:28.516729+12
中国政府	中共	34	alias_exact	0.98	ORG	Government alias routes to 中共	2026-06-05 21:40:28.516729+12
Chinese government	中共	34	alias_exact	0.98	ORG	English government alias routes to 中共	2026-06-05 21:40:28.516729+12
Beijing	中共	34	alias_exact	0.98	ORG	Metonymy routes to 中共	2026-06-05 21:40:28.516729+12
State Council	中共	34	alias_exact	0.98	ORG	State Council routes to 中共	2026-06-05 21:40:28.516729+12
中国共产党	中共	34	alias_exact	0.98	ORG	Party alias routes to 中共	2026-06-05 21:40:28.516729+12
中國共產黨	中共	34	alias_exact	0.98	ORG	Traditional party alias routes to 中共	2026-06-05 21:40:28.516729+12
CCP	中共	34	alias_exact	0.98	ORG	CCP routes to 中共	2026-06-05 21:40:28.516729+12
CPC	中共	34	alias_exact	0.98	ORG	CPC routes to 中共	2026-06-05 21:40:28.516729+12
zhong guo	中共	34	alias_exact	0.98	ORG	Pinyin state alias routes to 中共	2026-06-05 21:40:28.516729+12
zhongguogongchandang	中共	34	alias_exact	0.98	ORG	Pinyin party alias routes to 中共	2026-06-05 21:40:28.516729+12
Donald John Trump	特朗普	17	alias_exact	0.98	PERSON	Full English name routes to 特朗普	2026-06-05 21:40:28.516729+12
Trump	特朗普	17	alias_exact	0.98	PERSON	English alias routes to 特朗普	2026-06-05 21:40:28.516729+12
Fed	美联储	35	alias_exact	0.98	ORG	Fed routes to 美联储	2026-06-05 21:40:28.516729+12
FOMC	美联储	35	alias_exact	0.98	ORG	FOMC routes to 美联储	2026-06-05 21:40:28.516729+12
WEF	WEF	59	entity_exact	0.99	ORG	Canonical exact route	2026-06-05 21:40:28.516729+12
Davos	WEF	59	alias_exact	0.98	ORG	Davos routes to WEF	2026-06-05 21:40:28.516729+12
Xi Jinping	习近平	16	alias_exact	0.98	PERSON	Xi Jinping routes to 习近平 without fuzzy Putin pollution	2026-06-05 21:40:28.516729+12
XJP	习近平	16	alias_exact	0.98	PERSON	XJP routes to 习近平	2026-06-05 21:40:28.516729+12
PRC Government	中共	34	alias_exact	0.98	ORG	PRC Government routes to 中共	2026-06-05 21:42:58.448097+12
中國政府	中共	34	alias_exact	0.98	ORG	Traditional government alias routes to 中共	2026-06-05 21:42:58.448097+12
Government of China	中共	34	alias_exact	0.98	ORG	Government of China routes to 中共	2026-06-05 21:42:58.448097+12
P.R.C.	中共	34	alias_exact	0.98	ORG	P.R.C. routes to 中共	2026-06-05 21:42:58.448097+12
zhongguo zhengfu	中共	34	alias_exact	0.98	ORG	Pinyin government alias routes to 中共	2026-06-05 21:42:58.448097+12
zhong guo zheng fu	中共	34	alias_exact	0.98	ORG	Spaced pinyin government alias routes to 中共	2026-06-05 21:42:58.448097+12
zhonghua renmin gongheguo	中共	34	alias_exact	0.98	ORG	Pinyin official state name routes to 中共	2026-06-05 21:42:58.448097+12
Communist Party of China	中共	34	alias_exact	0.98	ORG	English party alias routes to 中共	2026-06-05 21:42:58.448097+12
Chinese Communist Party of China	中共	34	alias_exact	0.98	ORG	Full English party alias routes to 中共	2026-06-05 21:42:58.448097+12
包子	习近平	16	alias_exact	0.98	PERSON	Nickname routes to 习近平	2026-06-05 22:27:44.500191+12
习包子	习近平	16	alias_exact	0.98	PERSON	Nickname routes to 习近平	2026-06-05 22:27:44.500191+12
庆丰帝	习近平	16	alias_exact	0.98	PERSON	Nickname routes to 习近平	2026-06-05 22:27:44.500191+12
清零宗	习近平	16	alias_exact	0.98	PERSON	Nickname routes to 习近平	2026-06-05 22:27:44.500191+12
维尼	习近平	16	alias_exact	0.98	PERSON	Nickname routes to 习近平	2026-06-05 22:27:44.500191+12
小熊维尼	习近平	16	alias_exact	0.98	PERSON	Nickname routes to 习近平	2026-06-05 22:27:44.500191+12
习近平思想	习近平	16	alias_exact	0.98	PERSON	Ideology alias routes to 习近平	2026-06-05 22:27:44.500191+12
川普	特朗普	17	alias_exact	0.98	PERSON	Nickname routes to 特朗普	2026-06-05 22:27:44.500191+12
懂王	特朗普	17	alias_exact	0.98	PERSON	Nickname routes to 特朗普	2026-06-05 22:27:44.500191+12
川建国	特朗普	17	alias_exact	0.98	PERSON	Nickname routes to 特朗普	2026-06-05 22:27:44.500191+12
Donald J. Trump	特朗普	17	alias_exact	0.98	PERSON	English alias routes to 特朗普	2026-06-05 22:27:44.500191+12
Donald Trump	特朗普	17	alias_exact	0.98	PERSON	English alias routes to 特朗普	2026-06-05 22:27:44.500191+12
DJT	特朗普	17	alias_exact	0.98	PERSON	Abbreviation routes to 特朗普	2026-06-05 22:27:44.500191+12
World Economic Forum	WEF	59	alias_exact	0.98	ORG	English org alias routes to WEF	2026-06-05 22:27:44.500191+12
世界经济论坛	WEF	59	alias_exact	0.98	ORG	Simplified org alias routes to WEF	2026-06-05 22:27:44.500191+12
世界經濟論壇	WEF	59	alias_exact	0.98	ORG	Traditional org alias routes to WEF	2026-06-05 22:27:44.500191+12
达沃斯论坛	WEF	59	alias_exact	0.98	ORG	Davos forum routes to WEF	2026-06-05 22:27:44.500191+12
達沃斯論壇	WEF	59	alias_exact	0.98	ORG	Traditional Davos forum routes to WEF	2026-06-05 22:27:44.500191+12
Bill Gates	比尔盖茨	62	alias_exact	0.98	PERSON	Bill Gates remains separate PERSON entity	2026-06-05 22:27:44.500191+12
比尔盖茨	比尔盖茨	62	entity_exact	0.99	PERSON	Bill Gates canonical entity	2026-06-05 22:27:44.500191+12
比爾蓋茲	比尔盖茨	62	alias_exact	0.98	PERSON	Traditional Bill Gates alias routes to 比尔盖茨	2026-06-05 22:27:44.500191+12
\.


--
-- Data for Name: entity_trajectories; Type: TABLE DATA; Schema: ccc; Owner: postgres
--

COPY ccc.entity_trajectories (id, entity_profile_id, entity_name, snapshot_date, trajectory_status, pressure, pressure_trend, short_term_prediction, prediction_horizon, confidence, key_drivers, supporting_signals, next_possible_events, risk_level, created_at, updated_at) FROM stdin;
1	1	习近平	2026-05-27	centralization_accelerating	0.82	rising	进一步收缩民间资本空间，对台压力持续上升	12	0.85	{经济下行压力,派系清洗加速,地方债危机}	{枞阳帮覆灭,民企监管加强,军队清洗持续}	{新一轮反腐运动,台海军事演习升级,金融监管收紧}	high	2026-05-27 17:25:09.901722+12	2026-05-27 17:25:09.901722+12
2	2	普京	2026-05-27	imperial_restoration_locked	0.78	stable	乌克兰战争持续消耗，内部压力上升但政权稳定	18	0.82	{乌克兰战争消耗,西方制裁累积,精英阶层不满}	{瓦格纳事件,经济制裁深化,军事损失}	{谈判可能性低,能源武器化持续,内部政变风险低但存在}	high	2026-05-27 17:25:09.901722+12	2026-05-27 17:25:09.901722+12
3	3	特朗普	2026-05-27	transactional_unpredictability	0.71	rising	第二任期政策大幅摆动，盟友体系重新谈判	6	0.75	{关税战重启,NATO压力,美元政策不确定}	{当选后快速任命,对华强硬信号,撤出国际机构}	{贸易战升级,美元走弱压力,中东政策剧变}	medium	2026-05-27 17:25:09.901722+12	2026-05-27 17:25:09.901722+12
4	4	中共	2026-05-27	stability_at_all_costs	0.85	rising	经济下行压力加剧，维稳成本上升，叙事管控强化	12	0.88	{青年失业率高企,地方债危机,房地产持续下行}	{出口下滑,消费降级,人口老龄化加速}	{更多刺激政策,舆论管控加强,对外强硬转移矛盾}	high	2026-05-27 17:25:09.901722+12	2026-05-27 17:25:09.901722+12
5	5	美联储	2026-05-27	liquidity_stress	0.68	stable	降息周期开启但经济软着陆不确定，美元体系压力持续	9	0.8	{通胀粘性,就业市场降温,美债可持续性}	{QE重启,非农数据波动,国债收益率曲线}	{进一步降息,流动性危机风险,美元指数走弱}	medium	2026-05-27 17:25:09.901722+12	2026-05-27 17:25:09.901722+12
6	6	WEF	2026-05-27	agenda_consolidation	0.55	stable	全球治理议程推进受民粹主义阻力，技术官僚路线调整	24	0.7	{民粹主义反弹,AI治理议题上升,去全球化趋势}	{达沃斯影响力下降,各国退出多边框架,技术监管分歧}	{AI全球治理框架推进,气候议程重构,数字货币标准争夺}	low	2026-05-27 17:25:09.901722+12	2026-05-27 17:25:09.901722+12
\.


--
-- Data for Name: event_chains; Type: TABLE DATA; Schema: ccc; Owner: postgres
--

COPY ccc.event_chains (id, chain_name, entity_id, description, pressure_type, direction, created_at, start_time, end_time, duration_days, trajectory_score) FROM stdin;
35	薄熙来时间线	4	薄熙来相关事件因果链，共3个节点	political	de-escalating	2026-05-26 19:14:44.044707+12	1978-01-01 00:00:00	1987-01-01 00:00:00	3287	0.3
36	习近平时间线	16	习近平相关事件因果链，共7个节点	political	escalating	2026-05-26 19:14:44.044707+12	2013-04-25 00:00:00	2024-10-17 00:00:00	4193	0.7
37	香港时间线	37	香港相关事件因果链，共3个节点	political	escalating	2026-05-26 19:14:44.044707+12	2019-07-21 00:00:00	2023-10-25 00:00:00	1557	0.3
38	中共时间线	34	中共相关事件因果链，共8个节点	political	escalating	2026-05-26 19:14:44.044707+12	2020-01-20 00:00:00	2023-10-15 00:00:00	1364	0.8
39	美联储时间线	35	美联储相关事件因果链，共3个节点	financial	volatile	2026-05-26 19:14:44.044707+12	2020-02-18 00:00:00	2024-10-14 00:00:00	1700	0.3
40	蔡英文时间线	30	蔡英文相关事件因果链，共1个节点	political	de-escalating	2026-05-26 19:14:44.044707+12	2020-05-16 00:00:00	2020-05-16 00:00:00	0	0.1
41	特朗普时间线	17	特朗普相关事件因果链，共3个节点	political	de-escalating	2026-05-26 19:14:44.044707+12	2021-01-06 00:00:00	2024-11-05 00:00:00	1399	0.3
42	马云时间线	18	马云相关事件因果链，共2个节点	financial	de-escalating	2026-05-26 19:14:44.044707+12	2021-10-03 00:00:00	2023-11-16 00:00:00	774	0.2
43	Pavel Dourov时间线	21	Pavel Dourov相关事件因果链，共1个节点	media	escalating	2026-05-26 19:14:44.044707+12	2023-07-28 00:00:00	2023-07-28 00:00:00	0	0.1
44	乌克兰时间线	39	乌克兰相关事件因果链，共1个节点	military	stabilizing	2026-05-26 19:14:44.044707+12	2023-09-26 00:00:00	2023-09-26 00:00:00	0	0.1
45	哈马斯时间线	32	哈马斯相关事件因果链，共2个节点	military	escalating	2026-05-26 19:14:44.044707+12	2023-10-07 00:00:00	2023-10-18 00:00:00	11	0.2
46	以色列时间线	41	以色列相关事件因果链，共2个节点	military	escalating	2026-05-26 19:14:44.044707+12	2023-11-13 00:00:00	2024-04-19 00:00:00	158	0.2
47	日本时间线	57	日本相关事件因果链，共2个节点	social	stabilizing	2026-05-26 19:14:44.044707+12	2024-01-01 00:00:00	2024-09-18 00:00:00	261	0.2
48	ISIS时间线	33	ISIS相关事件因果链，共1个节点	military	escalating	2026-05-26 19:14:44.044707+12	2024-03-22 00:00:00	2024-03-22 00:00:00	0	0.1
49	俄罗斯时间线	40	俄罗斯相关事件因果链，共2个节点	military	stabilizing	2026-05-26 19:14:44.044707+12	2024-04-05 00:00:00	2024-09-04 00:00:00	152	0.2
50	中国社会时间线	58	中国社会相关事件因果链，共2个节点	social	de-escalating	2026-05-26 19:14:44.044707+12	2024-08-13 00:00:00	2024-12-09 00:00:00	118	0.2
\.


--
-- Data for Name: event_dashboard; Type: TABLE DATA; Schema: ccc; Owner: postgres
--

COPY ccc.event_dashboard (id, document_id, person_name, event_date, location, impact, event_summary, confidence, source_type, created_at) FROM stdin;
63548	1	邓小平	1950-01-01	西南	西南剿匪	邓小平参与西南剿匪运动，导致大量人员死亡	0.850	openai_ner	2026-05-19 13:30:17.683267+12
63549	1	邓小平	1950-07-31	西南	禁用银元	邓小平在西南军政委员会会议上谈到禁用银元导致民众抵触情绪	0.850	openai_ner	2026-05-19 13:30:17.739256+12
63554	1	邓朴方	2022-08-01	澳洲	逝世	邓朴方逝世	0.850	openai_ner	2026-05-19 13:30:17.944762+12
63557	1	胡为真	\N	\N	出版新书	胡为真出版新书为父亲胡宗南平反	0.850	openai_ner	2026-05-19 13:30:18.024274+12
63566	11	克林顿	\N	\N	\N	中方向克林顿承诺要搞市场经济	0.850	openai_ner	2026-05-19 13:30:23.533672+12
63551	1	邓小平	1949-01-01	西南	征收公粮	邓小平宣布西南区1949年度公粮已基本完成	0.850	openai_ner	2026-05-19 13:30:17.822318+12
63570	1	邓小平	1949-01-01	西南	征粮	邓小平宣布西南区1949年公粮已基本完成	0.850	openai_ner	2026-05-19 13:45:26.872542+12
63571	1	邓朴方	2022-08-01	澳洲	去世	邓朴方去世	0.850	openai_ner	2026-05-19 13:45:26.978939+12
63573	1	顾维钧	1918-01-01	\N	巴黎合会	顾维钧参加巴黎合会	0.850	openai_ner	2026-05-19 13:45:27.067937+12
63575	1	毛泽东	\N	\N	政治破产	毛泽东宣布自己政治破产	0.850	openai_ner	2026-05-19 13:45:27.148817+12
63560	11	斯大林	\N	\N	弄死2000万苏联人	斯大林被评为20世纪三个最残暴的恶魔之一	0.850	openai_ner	2026-05-19 13:30:23.341595+12
63561	11	希特勒	\N	\N	弄死600万犹太人	希特勒被评为20世纪三个最残暴的恶魔之一	0.850	openai_ner	2026-05-19 13:30:23.381554+12
63563	11	尼克松	\N	\N	\N	尼克松访华，中美关系破冰	0.850	openai_ner	2026-05-19 13:30:23.446781+12
63564	11	刘少奇	\N	\N	\N	刘少奇策动西北军率先开枪	0.850	openai_ner	2026-05-19 13:30:23.475339+12
63565	11	Maurice Hilleman	1981-01-01	美国	研发乙肝疫苗	美国微生物学家Maurice Hilleman的团队研发乙肝疫苗	0.850	openai_ner	2026-05-19 13:30:23.503892+12
63585	12	习近平	2022-01-01	\N	谋求第三任期	习近平谋求第三任期	0.850	openai_ner	2026-05-19 13:45:47.299039+12
63582	11	尼克松	\N	\N	\N	尼克松访华	0.850	openai_ner	2026-05-19 13:45:40.753876+12
63583	11	Maurice Hilleman	\N	\N	\N	Maurice Hilleman的团队研发乙肝疫苗	0.850	openai_ner	2026-05-19 13:45:40.800326+12
63584	11	克林顿	\N	\N	\N	中共骗克林顿说要搞市场经济	0.850	openai_ner	2026-05-19 13:45:40.843307+12
63586	12	习近平	2023-01-01	\N	肆意妄为期	习近平取得连任，大权独揽	0.850	openai_ner	2026-05-19 13:45:47.365018+12
63591	12	华盛顿	\N	\N	驱逐北美英国保王党	华盛顿驱逐北美英国保王党	0.850	openai_ner	2026-05-19 13:45:47.632977+12
63600	13	Tzila	2011-01-01	\N	\N	本雅明·内塔尼亚胡的母亲Tzila骂二儿子	0.850	openai_ner	2026-05-19 13:45:59.825503+12
63601	13	奥龙·沙乌尔	2014-07-20	\N	\N	以色列国防军士兵上士奥龙·沙乌尔牺牲	0.850	openai_ner	2026-05-19 13:45:59.863416+12
63567	1	邓小平	1950-01-01	西南	西南剿匪	邓小平参与西南剿匪，杀死110万人	0.850	openai_ner	2026-05-19 13:45:26.703926+12
63568	1	邓小平	1950-07-31	西南	禁用银元	邓小平在西南军政委员会会议上谈到禁用银元	0.850	openai_ner	2026-05-19 13:45:26.764191+12
63550	1	邓小平	\N	西南	镇反运动	邓小平提出将西南地区六个军送往朝鲜作战	0.850	openai_ner	2026-05-19 13:30:17.784015+12
63552	1	邓小平	\N	\N	计划生育	邓小平坚持计划生育政策	0.850	openai_ner	2026-05-19 13:30:17.882457+12
63553	1	邓小平	\N	\N	毛泽东	邓小平与毛泽东是历史共犯	0.850	openai_ner	2026-05-19 13:30:17.915304+12
63555	1	高志凯	2024-01-01	\N	接受采访	高志凯接受Channel 4 News采访	0.850	openai_ner	2026-05-19 13:30:17.973308+12
63556	1	顾维钧	1919-01-01	巴黎	五四运动	顾维钧参与五四运动	0.850	openai_ner	2026-05-19 13:30:17.999215+12
63574	1	胡为真	\N	\N	出版新书	胡为真出版新书，为父亲胡宗南平反	0.850	openai_ner	2026-05-19 13:45:27.11449+12
63558	11	伽利略	\N	\N	\N	伽利略被教皇抓捕殴打	0.850	openai_ner	2026-05-19 13:30:23.249227+12
63559	11	毛泽东	\N	\N	弄死8000万中国人	毛泽东被评为20世纪三个最残暴的恶魔之一	0.850	openai_ner	2026-05-19 13:30:23.298379+12
63562	11	布林肯	\N	意大利	\N	美国国务卿布林肯参加意大利的北约峰会	0.850	openai_ner	2026-05-19 13:30:23.414904+12
63587	12	伊朗霍梅尼	\N	\N	全民公投的弊端	伊朗霍梅尼与全民公投的弊端	0.850	openai_ner	2026-05-19 13:45:47.431759+12
63588	12	希特勒	\N	\N	全民公投的弊端	希特勒与全民公投的弊端	0.850	openai_ner	2026-05-19 13:45:47.488082+12
63589	12	特鲁多	\N	\N	全民公投的弊端	特鲁多与全民公投的弊端	0.850	openai_ner	2026-05-19 13:45:47.538899+12
63590	12	埃尔多安	\N	\N	全民公投的弊端	埃尔多安与全民公投的弊端	0.850	openai_ner	2026-05-19 13:45:47.587362+12
63592	13	赫尔佐格	\N	\N	\N	以色列总统赫尔佐格与chatGPT聊天	0.850	openai_ner	2026-05-19 13:45:59.388688+12
63593	13	毕加索	\N	\N	\N	毕加索的画作被反以色列破坏者攻击	0.850	openai_ner	2026-05-19 13:45:59.450325+12
63594	13	Benjamin Netanyahu	\N	\N	\N	以色列总理Benjamin Netanyahu被国际刑事法院ICC通緝	0.850	openai_ner	2026-05-19 13:45:59.504499+12
63595	13	Yoav Gallant	\N	\N	\N	以色列国防部长Yoav Gallant被国际刑事法院ICC通緝	0.850	openai_ner	2026-05-19 13:45:59.559012+12
63596	13	Arnon Bar-David	\N	\N	\N	以色列总工会Histadrut主席Arnon Bar-David谈论哈马斯扣押的人质	0.850	openai_ner	2026-05-19 13:45:59.613875+12
63597	13	Yoav Fisher	\N	\N	\N	HealthIL负责人Yoav Fisher访华	0.850	openai_ner	2026-05-19 13:45:59.668269+12
63598	13	约拿单·内塔尼亚胡	1976-01-01	\N	\N	约拿单·内塔尼亚胡率兵千里奔袭恩德培机场救出了人质	0.850	openai_ner	2026-05-19 13:45:59.719015+12
63599	13	本雅明·内塔尼亚胡	2011-01-01	\N	\N	本雅明·内塔尼亚胡跟恐怖组织哈马斯做交易	0.850	openai_ner	2026-05-19 13:45:59.771645+12
63602	13	特朗普	\N	\N	\N	特朗普说美国将接管加沙地带	0.850	openai_ner	2026-05-19 13:45:59.905901+12
63604	17	毛泽东	\N	null	null	毛泽东45岁娶24岁江青，结婚4次	0.850	openai_ner	2026-05-19 13:46:29.059762+12
63605	17	叶剑英	\N	null	null	叶剑英结婚9次，夫妻年龄差60岁	0.850	openai_ner	2026-05-19 13:46:29.180198+12
63606	17	江青	\N	null	null	江青与毛泽东结婚	0.850	openai_ner	2026-05-19 13:46:29.217413+12
63607	17	邓小平	\N	null	null	邓小平35岁娶25岁妻子，结婚5次	0.850	openai_ner	2026-05-19 13:46:29.266114+12
63608	17	罗曼·扬波尔斯基	\N	null	null	罗曼·扬波尔斯基博士是AI安全领域的领军人物	0.850	openai_ner	2026-05-19 13:46:29.31513+12
63609	17	萨姆·阿尔特曼	\N	null	null	萨姆·阿尔特曼是OpenAI的创始人	0.850	openai_ner	2026-05-19 13:46:29.361999+12
63610	17	太宰治	1909-06-19	青森县	null	太宰治出生	0.850	openai_ner	2026-05-19 13:46:29.40711+12
63611	17	太宰治	1948-06-13	null	null	太宰治去世	0.850	openai_ner	2026-05-19 13:46:29.440247+12
63612	17	Bill Clinton	\N	null	null	Bill Clinton收到Monica Lewinsky的问候	0.850	openai_ner	2026-05-19 13:46:29.47477+12
63613	17	Monica Lewinsky	\N	null	null	Monica Lewinsky向Bill Clinton发送问候	0.850	openai_ner	2026-05-19 13:46:29.520143+12
63615	6	迪特里希·马特希茨	\N	\N	与许书标合作	迪特里希·马特希茨与许书标合作，将红牛带到全球市场	0.850	openai_ner	2026-05-19 13:47:21.296063+12
63616	6	习近平	\N	\N	女婿的姐姐入股	习近平的女婿的姐姐已入股红牛	0.850	openai_ner	2026-05-19 13:47:21.338138+12
63619	6	洪森	1952-08-05	柬埔寨	柬埔寨首相	洪森曾任柬埔寨首相、参议院议长等职务	0.850	openai_ner	2026-05-19 13:47:21.461916+12
63620	9	习近平	\N	\N	中国政治	习近平是中国共产党的最高领导人	0.850	openai_ner	2026-05-19 13:47:55.396188+12
63621	9	李强	\N	\N	中国政治	李强是中国共产党的政治局常委	0.850	openai_ner	2026-05-19 13:47:55.442773+12
63622	9	赵乐际	\N	\N	中国政治	赵乐际是中国共产党的政治局常委	0.850	openai_ner	2026-05-19 13:47:55.485086+12
63623	9	王沪宁	\N	\N	中国政治	王沪宁是中国共产党的政治局常委	0.850	openai_ner	2026-05-19 13:47:55.535054+12
63624	9	蔡奇	\N	\N	中国政治	蔡奇是中国共产党的政治局常委	0.850	openai_ner	2026-05-19 13:47:55.582362+12
63625	9	丁薛祥	\N	\N	中国政治	丁薛祥是中国共产党的政治局常委	0.850	openai_ner	2026-05-19 13:47:55.632361+12
63626	9	李希	\N	\N	中国政治	李希是中国共产党的政治局常委	0.850	openai_ner	2026-05-19 13:47:55.686358+12
63627	9	彭丽媛	\N	\N	中国政治	彭丽媛是习近平的妻子	0.850	openai_ner	2026-05-19 13:47:55.734685+12
63628	9	习明泽	\N	\N	中国政治	习明泽是习近平的女儿	0.850	openai_ner	2026-05-19 13:47:55.782611+12
63629	9	薄熙来	\N	\N	中国政治	薄熙来是中国前政治人物	0.850	openai_ner	2026-05-19 13:47:55.825596+12
63649	12	习近平	2023-01-01	\N	二十大取得连任	习近平二十大取得连任	0.850	openai_ner	2026-05-19 14:04:29.680386+12
63662	13	Tzila	2011-01-01	\N	\N	本雅明·内塔尼亚胡的母亲Tzila批评儿子	0.850	openai_ner	2026-05-19 14:04:42.352121+12
63663	13	奥龙·沙乌尔	2014-07-20	\N	\N	以色列国防军士兵奥龙·沙乌尔在战斗中牺牲	0.850	openai_ner	2026-05-19 14:04:42.399275+12
63664	13	特朗普	\N	\N	\N	特朗普谈论以巴冲突和加沙地带	0.850	openai_ner	2026-05-19 14:04:42.44229+12
63603	15	习近平	2022-01-01	\N	\N	习近平在2022年继续推进第三任期	0.850	openai_ner	2026-05-19 13:46:10.634465+12
63666	18	卡尔·冯·克劳塞维茨	\N	null	null	卡尔·冯·克劳塞维茨提出了战争三位一体理论	0.850	openai_ner	2026-05-19 14:05:23.556825+12
63667	18	安德烈·科斯托拉尼	\N	null	null	安德烈·科斯托拉尼曾说过一句话，揭示了一种普遍逻辑	0.850	openai_ner	2026-05-19 14:05:23.591719+12
63668	21	本杰明富兰克林	1755-01-01	宾西瓦尼亚	法国印第安人战争	本杰明富兰克林写信给Robert Morris，讨论自治权和安全问题	0.850	openai_ner	2026-05-19 14:05:40.786069+12
63669	21	本杰明富兰克林	\N	\N	自由与安全	本杰明富兰克林说过关于自由和安全的名言	0.850	openai_ner	2026-05-19 14:05:40.835519+12
63670	21	William Penn	\N	宾西瓦尼亚	土地所有权	William Penn的家族拥有宾西瓦尼亚的土地	0.850	openai_ner	2026-05-19 14:05:40.876718+12
63671	21	Robert Morris	1755-01-01	宾西瓦尼亚	法国印第安人战争	Robert Morris是Penn家族指派的殖民官	0.850	openai_ner	2026-05-19 14:05:40.914038+12
63672	21	金正日	\N	朝鲜	饥荒和压迫	金正日让数百万朝鲜居民饿死，并把整个国家变成监狱	0.850	openai_ner	2026-05-19 14:05:40.947905+12
63673	21	哈耶克	\N	\N	自由与安全	哈耶克引用了本杰明富兰克林的名言	0.850	openai_ner	2026-05-19 14:05:40.978443+12
63614	6	许书标	1932-08-17	泰国	创办天丝制药厂	许书标创办天丝制药厂，开始了他的创业之路	0.850	openai_ner	2026-05-19 13:47:21.249252+12
63675	6	迪特里希·马特希茨	\N	奥地利	与许书标合作	迪特里希·马特希茨与许书标合作，将红牛饮料带到全球市场	0.850	openai_ner	2026-05-19 14:06:09.94106+12
63617	6	巴东丹·西那瓦	2025-04-01	泰国	下令审查中铁十局项目	泰国总理巴东丹·西那瓦下令审查中铁十局在泰国的所有项目	0.850	openai_ner	2026-05-19 13:47:21.381713+12
63618	6	普拉威·翁素万	1945-08-11	泰国	曾任泰国副总理	普拉威·翁素万曾任泰国副总理、国防部长等职务	0.850	openai_ner	2026-05-19 13:47:21.421886+12
63678	6	洪森	1952-08-05	柬埔寨	柬埔寨首相	洪森曾任柬埔寨首相近39年，现任参议院议长及国王顾问团主席	0.850	openai_ner	2026-05-19 14:06:10.072747+12
63679	8	朱镕基	1999-01-01	\N	西部大开发	朱镕基推动西部大开发	0.850	openai_ner	2026-05-19 14:06:27.059527+12
63680	8	朱镕基	2000-01-01	\N	蔡鄂生任职	朱镕基提拔蔡鄂生担任中国人民银行行长助理	0.850	openai_ner	2026-05-19 14:06:27.111528+12
63681	8	朱镕基	2021-01-01	\N	蔡鄂生判刑	蔡鄂生因受贿被判死缓	0.850	openai_ner	2026-05-19 14:06:27.154151+12
63682	8	朱云来	1998-01-01	\N	中金公司CEO	朱云来任中金公司CEO	0.850	openai_ner	2026-05-19 14:06:27.193006+12
63683	8	朱云来	2014-01-01	\N	离职	朱云来离职中金公司	0.850	openai_ner	2026-05-19 14:06:27.226322+12
63684	8	谢企华	2010-01-01	\N	国新控股创始董事长	谢企华任国新控股创始董事长	0.850	openai_ner	2026-05-19 14:06:27.254908+12
63685	8	王岐山	\N	\N	朱镕基大弟子	王岐山是朱镕基的大弟子	0.850	openai_ner	2026-05-19 14:06:27.28704+12
63686	8	肖亚庆	2022-01-01	\N	落马	肖亚庆落马	0.850	openai_ner	2026-05-19 14:06:27.315513+12
63687	8	郝鹏	2016-01-01	\N	国资委党委书记	郝鹏任国资委党委书记	0.850	openai_ner	2026-05-19 14:06:27.344399+12
63688	8	耿惠昌	2021-01-01	\N	督导组反馈	耿惠昌作反馈发言	0.850	openai_ner	2026-05-19 14:06:27.373462+12
66216	5078	普京关联网络	\N	俄罗斯	高风险	制裁规避/洗钱（西方国家指控，未正式起诉）	0.950	sanxi_template	2026-05-23 07:44:15.258358+12
66217	5079	卡梅伦家族基金	\N	英国	中风险	税务申报不实/利益冲突（未刑事起诉，政治压力辞职）	0.950	sanxi_template	2026-05-23 07:44:15.337831+12
66218	5080	习近平亲属关联	\N	中国	中风险	无正式指控（中国境内不允许独立调查）	0.950	sanxi_template	2026-05-23 07:44:15.422576+12
66219	5081	波罗申科公司	\N	乌克兰	中风险	叛国罪（2023年乌克兰指控）；离岸结构涉利益冲突调查	0.950	sanxi_template	2026-05-23 07:44:15.507023+12
66220	5082	Mossack Fonseca	\N	巴拿马	中风险	洗钱罪、有组织犯罪（巴拿马检察机关起诉）	0.950	sanxi_template	2026-05-23 07:44:15.596392+12
66221	5083	汇丰银行	\N	英国/香港	中风险	洗钱协助罪（美国DOJ）；反洗钱合规失职（FCA/Fed）	0.950	sanxi_template	2026-05-23 07:44:15.688872+12
66222	5084	瑞银（UBS）	\N	瑞士	中风险	非法拉客、协助逃税（法国检察机关）	0.950	sanxi_template	2026-05-23 07:44:15.78526+12
66223	5085	FIFA相关腐败案	\N	瑞士	中风险	电信欺诈、洗钱、敲诈勒索（美国DOJ）；腐败（瑞士检察机关）	0.950	sanxi_template	2026-05-23 07:44:15.877982+12
66224	5086	Brink's-Mat黄金案	\N	英国	中风险	洗钱罪、抢劫罪、有组织犯罪	0.950	sanxi_template	2026-05-23 07:44:15.973151+12
\.


--
-- Data for Name: event_nodes; Type: TABLE DATA; Schema: ccc; Owner: postgres
--

COPY ccc.event_nodes (id, chain_id, event_id, entity_id, event_time, sequence_order, essence, mechanism, pressure, signal_strength, causal_weight, created_at, previous_event_id, next_event_id, escalation_score, decay_factor) FROM stdin;
79	35	5089	4	1978-01-01 13:00:00+13	0	个人事件	{待分析}	political	0.7	1	2026-05-26 19:14:44.044707+12	\N	80	0	1
80	35	5090	4	1981-01-01 13:00:00+13	1	个人事件	{待分析}	political	0.7	1	2026-05-26 19:14:44.044707+12	79	81	0.5	1
81	35	5115	4	1987-01-01 13:00:00+13	2	待分类	{待分析}	political	0.7	1	2026-05-26 19:14:44.044707+12	80	\N	1	1
82	36	5091	16	2013-04-25 12:00:00+12	0	待分类	{待分析}	political	0.7	1	2026-05-26 19:14:44.044707+12	\N	83	0	1
83	36	5126	16	2022-03-10 13:00:00+13	1	权力更迭	{待分析}	political	0.7	1	2026-05-26 19:14:44.044707+12	82	84	0.06666666666666665	1
84	36	5129	16	2022-10-23 13:00:00+13	2	待分类	{待分析}	political	0.7	1	2026-05-26 19:14:44.044707+12	83	85	0.3333333333333333	1
85	36	5130	16	2022-11-26 13:00:00+13	3	社会压力	{待分析}	political	0.7	1	2026-05-26 19:14:44.044707+12	84	86	0.65	1
86	36	5092	16	2024-10-17 13:00:00+13	4	待分类	{待分析}	political	0.7	1	2026-05-26 19:14:44.044707+12	85	87	0.6666666666666666	1
87	36	5116	16	1988-01-01 13:00:00+13	5	待分类	{待分析}	political	0.7	1	2026-05-26 19:14:44.044707+12	86	88	0.8333333333333334	1
88	36	5093	16	2024-01-01 13:00:00+13	6	法律压制	{待分析}	political	0.7	1	2026-05-26 19:14:44.044707+12	87	\N	1	1
89	37	5118	37	2019-07-21 12:00:00+12	0	军事冲突	{武力威慑}	political	0.7	1	2026-05-26 19:14:44.044707+12	\N	90	0.3	1
90	37	5133	37	2023-08-16 12:00:00+12	1	金融压力	{金融手段}	political	0.7	1	2026-05-26 19:14:44.044707+12	89	91	0.5	1
91	37	5140	37	2023-10-25 13:00:00+13	2	待分类	{待分析}	political	0.7	1	2026-05-26 19:14:44.044707+12	90	\N	1	1
92	38	5119	34	2020-01-20 13:00:00+13	0	灾难事件	{待分析}	political	0.7	1	2026-05-26 19:14:44.044707+12	\N	93	0.1	1
93	38	5123	34	2021-04-18 12:00:00+12	1	个人事件	{待分析}	political	0.7	1	2026-05-26 19:14:44.044707+12	92	94	0.14285714285714285	1
94	38	5125	34	2022-02-20 13:00:00+13	2	金融压力	{待分析}	political	0.7	1	2026-05-26 19:14:44.044707+12	93	95	0.2857142857142857	1
95	38	5127	34	2022-03-28 13:00:00+13	3	社会压力	{待分析}	political	0.7	1	2026-05-26 19:14:44.044707+12	94	96	0.5785714285714285	1
96	38	5128	34	2022-10-23 13:00:00+13	4	法律压制	{待分析}	political	0.7	1	2026-05-26 19:14:44.044707+12	95	97	0.7714285714285714	1
97	38	5131	34	2023-07-28 12:00:00+12	5	灾难事件	{待分析}	political	0.7	1	2026-05-26 19:14:44.044707+12	96	98	0.8142857142857143	1
98	38	5137	34	2023-10-08 13:00:00+13	6	待分类	{待分析}	political	0.7	1	2026-05-26 19:14:44.044707+12	97	99	0.8571428571428571	1
99	38	5138	34	2023-10-15 13:00:00+13	7	待分类	{待分析}	political	0.7	1	2026-05-26 19:14:44.044707+12	98	\N	1	1
100	39	5120	35	2020-02-18 13:00:00+13	0	待分类	{待分析}	financial	0.7	1	2026-05-26 19:14:44.044707+12	\N	101	0	1
101	39	5134	35	2023-09-15 12:00:00+12	1	金融压力	{经济制裁}	financial	0.7	1	2026-05-26 19:14:44.044707+12	100	102	0.5	1
102	39	5151	35	2024-10-14 13:00:00+13	2	金融压力	{待分析}	financial	0.7	1	2026-05-26 19:14:44.044707+12	101	\N	1	1
103	40	5121	30	2020-05-16 12:00:00+12	0	权力更迭	{政治手段}	political	0.7	1	2026-05-26 19:14:44.044707+12	\N	\N	0	1
104	41	5122	17	2021-01-06 13:00:00+13	0	社会压力	{待分析}	political	0.7	1	2026-05-26 19:14:44.044707+12	\N	105	0.15	1
105	41	5144	17	2024-01-20 13:00:00+13	1	权力更迭	{待分析}	political	0.7	1	2026-05-26 19:14:44.044707+12	104	106	0.4	1
106	41	5152	17	2024-11-05 13:00:00+13	2	权力更迭	{待分析}	political	0.7	1	2026-05-26 19:14:44.044707+12	105	\N	0.9	1
107	42	5124	18	2021-10-03 13:00:00+13	0	情报行动	{叙事控制}	financial	0.7	1	2026-05-26 19:14:44.044707+12	\N	108	0	1
108	42	5142	18	2023-11-16 13:00:00+13	1	个人事件	{待分析}	financial	0.7	1	2026-05-26 19:14:44.044707+12	107	\N	1	1
109	43	5132	21	2023-07-28 12:00:00+12	0	法律压制	{待分析}	media	0.7	1	2026-05-26 19:14:44.044707+12	\N	\N	0.2	1
110	44	5135	39	2023-09-26 13:00:00+13	0	待分类	{待分析}	military	0.7	1	2026-05-26 19:14:44.044707+12	\N	\N	0	1
111	45	5136	32	2023-10-07 13:00:00+13	0	军事冲突	{武力威慑}	military	0.7	1	2026-05-26 19:14:44.044707+12	\N	112	0.3	1
112	45	5139	32	2023-10-18 13:00:00+13	1	灾难事件	{待分析}	military	0.7	1	2026-05-26 19:14:44.044707+12	111	\N	1	1
113	46	5141	41	2023-11-13 13:00:00+13	0	军事冲突	{待分析}	military	0.7	1	2026-05-26 19:14:44.044707+12	\N	114	0.3	1
114	46	5147	41	2024-04-19 12:00:00+12	1	军事冲突	{武力威慑}	military	0.7	1	2026-05-26 19:14:44.044707+12	113	\N	1	1
115	47	5143	57	2024-01-01 13:00:00+13	0	待分类	{待分析}	social	0.7	1	2026-05-26 19:14:44.044707+12	\N	116	0	1
116	47	5150	57	2024-09-18 12:00:00+12	1	待分类	{待分析}	social	0.7	1	2026-05-26 19:14:44.044707+12	115	\N	1	1
117	48	5145	33	2024-03-22 13:00:00+13	0	军事冲突	{武力威慑}	military	0.7	1	2026-05-26 19:14:44.044707+12	\N	\N	0.3	1
118	49	5146	40	2024-04-05 13:00:00+13	0	灾难事件	{待分析}	military	0.7	1	2026-05-26 19:14:44.044707+12	\N	119	0.1	1
119	49	5149	40	2024-09-04 12:00:00+12	1	情报行动	{待分析}	military	0.7	1	2026-05-26 19:14:44.044707+12	118	\N	1	1
120	50	5148	58	2024-08-13 12:00:00+12	0	个人事件	{待分析}	social	0.7	1	2026-05-26 19:14:44.044707+12	\N	121	0	1
121	50	5153	58	2024-12-09 13:00:00+13	1	待分类	{待分析}	social	0.7	1	2026-05-26 19:14:44.044707+12	120	\N	1	1
\.


--
-- Data for Name: events; Type: TABLE DATA; Schema: ccc; Owner: postgres
--

COPY ccc.events (id, document_id, event_summary, event_date, event_year, event_time_raw, created_at) FROM stdin;
1	1	邓小平/邓希贤 ☒\n\n戚本禹回憶錄，\n邓小平干了他小妈，一辈子不敢回广安，照理说他爸在本地也算个人物，鄧小平最初是鄧家的黑羊，鄧家不用說全是地主，雖然並韭全是豪強，像劉邦他爸爸看劉邦不順眼一樣，喜歡他求田問舍的弟弟鄧蜀平，從名字就可以看出，後者是一個低調巴蜀利亞本土派.本土军阀的合作者。\n\n独裁久了就没脑子了，邓小平35年前5月16日会见戈尔巴乔夫。邓中了陈云离间计，不是赵紫阳要夺权，是陈云李鹏朱镕基后来的习近平要夺权，包子5.16见俄罗斯爹普京。邓朴方因为邓矮子才坐轮椅，70多岁邓小平亲自照顾，特别愧疚，结果邓朴方70多岁还要被习近平整，邓小平太对不起邓朴方了\n拿下赵紫阳，等于邓小平自断手臂	\N	\N	\N	2026-05-08 08:13:50.952966
2	2	毛翼臣,毛祖父,葬虎歇坪,不过五选墓\n\t毛顺生☒\n\t\t毛☒\n1938年4月28日，毛匪賊東收受蘇俄30萬美元，用於勾結境外勢力分裂祖國、顛覆中國合法政府。\n南水北调，毛泽东一棺定江山，艮强巽弱，震时常不稳，三峡大坝改的是巽山，巽山为风。共产党魔改风水。位于河南省淅川县的南水北调中线工程渠首\nhttps://www.youtube.com/watch?v=6gyHX0hL1pI\n人民公社，四清运动，五年计划，反右防左\n毛澤東殺麻雀二十億，殺人八千萬，他的時代，人禽如同大禍臨頭，苦不堪言。\n没有红二代这个派系\n太子党红二代分别属于不同的派系\n\n上海几任市委书记的派系\n陈国栋（1980年－1985年	\N	\N	\N	2026-05-08 08:13:50.952966
3	3	🇹🇭  暹罗-泰国\n\t总理\n\t\t政党\n\t\t\t泰国清迈西那瓦家族,祖籍广东梅州丰顺县,姓丘\n\t\t\t前进党1350w\n\t\t\t\t皮塔，Grab-CEO，Pita Limjaroenrat激进民主派，选票不足半数\n\t\t\t\t\t@Pita_MFP Pita Limjaroenrat\n在#泰国 2023 年选举中赢得最多选票，但未能成为总理。由于呼吁改革泰国的冒犯君主法，他的政党也被排除在执政联盟之外。\n\t\t\t为泰党1030w\n\t\t\t\t泰国清迈西那瓦家族\n\t\t\t\t\t他信，媒体大亨，民主 现任党魁房地产大亨\n2023.8，被赶下台的总理他信·西那瓦(Thaksin Shinawatra)重新上台\n\n泰国警方在	\N	\N	\N	2026-05-08 08:13:50.952966
5	5	演艺圈\n-钟睒睒 （ zhōng shǎn shǎn ）\n-宗馥莉（ zōng fù lì ）\n-周鸿祎（ zhōu hóng yī ）\n- 张钧甯（zhāng jūn níng）\n- 鞠婧祎（jū jìng yī）\n- 阚清子（kàn qīng zǐ）\n- 何晟铭（hé shèng míng）\n- 黄锦燊（huáng jǐn shēn）\n- 佘诗曼（shé shī màn）\n- 菅纫姿（jiān rèn zī）\n- 卢庚戌（lú gēng xū）\n- 缪骞人（miào qiān rén）\n- 李莎旻子（lǐ shā mín zǐ）\n- 亳州（bó zhōu）\n- 歙县（shè xiàn）\n-	\N	\N	\N	2026-05-08 08:13:50.952966
6	6	RedBull红牛,许书标,海南\n\t习近平女婿的姐姐已入股\n\t\t紅牛Red Bull全球崛起之路，泰國功能飲料是如何征服全世界的？貧苦泰國街頭的水果攤販和奧地利牙膏推銷員，許書標與迪特里希·馬特希茨的創業傳奇與品牌營銷。紅牛（Red Bull）/Krating Daeng 的故事從泰國開始，海南人Seng Saesee森选择定居在泰国北部的彭世洛府Phichit Province 他结识了一位名叫童玉（Thongyoo Saelee）的当地女子 許書標（Chaleo Yoovidhya）17/08/1932 創辦了天絲製藥廠（TC Pharmaceutical），一位華人移民，從販賣水果到創造	\N	\N	\N	2026-05-08 08:13:50.952966
7	7	基佬周恩来的光辉历史：1920年，牠在法国流浪加入叛国组织! 1924年，牠拿着苏联人的卢布回国颠覆政府。\n1926顾顺章，陈赓去苏联学习KGB技能\n1931年，牠为杀人灭口亲自率队勒死顾顺章亲属30多人。 1934年，牠下令活埋数千红军伤员丢卒保帅。1936年，牠欺骗张学良绑架总统，分裂国家。1954年，牠打倒高岗、饶漱石。1961年，牠亲自销毁中国大饥荒死亡证据! 1966年，牠亲自出面抓捕刘少奇、彭德怀、贺龙、陈毅等… 1971年，牠除掉政敌林彪、陈伯达。1976年1 月8日，牠死于癌症，牠就是周恩来。\n☒特务 1926-1935中共特科，陈云和高岗关系好，那为什么还要逼死高岗：人品不行	\N	\N	\N	2026-05-08 08:13:50.952966
8	8	朱云来（朱镕基子）：安达信会计师、瑞士信贷副总裁、中金公司CEO（2002-2014）。 \nbaike.baidu.com +2\n\n朱娟娟：朱云来女儿，无详细记录。\n朱燕来（朱镕基女）：中银香港副总裁，年薪传1200万元人民币。 \nwenxuecity.com +2\n\n梁青（朱燕来夫）：中国五矿香港董事，传涉中铝并购（2009年中铝、五矿重组）。 \nwenxuecity.com +4\n\n\n\t看看朱镕基见到他的主子陈云的这副奴才相，为了一己私利支持习近平终身连任，为了在江西和邓家贵做稀土生意派出了鹿心社尹弘等亲信\n为了抢劫中国铝业给自己女婿梁青派出了郭声琨到广西林树森赵克志孙志刚李炳军徐麟到贵州	\N	\N	\N	2026-05-08 08:13:50.952966
9	9	每5年举行中共全国代表大会\n级别高低由党政中最高级别决定\n\t中共官僚\n中国社会28层，你在哪一层？\n1、正国级阶层\n2、副国级阶层\n3、省部级阶层\n4、厅局级阶层\n5、百亿级以上富豪阶层\n6、十亿级以上富豪阶层\n7、央企、金融机构及国有上市公司高管阶层\n8、高校教授、院士、著名医生、大明星、大网红阶展层\n9、大型民营企业主及民营上市公司高管阶层\n10、处科级或事业单位领导阶层\n11、公检法、政府机关公务员阶层\n12、普通作家、网红、一般明星阶层\n13、央企、上市公司及金融机构中层阶层\n14、亿万级富豪阶层\n15、千万级富翁阶层\n16、普通高校老师、著名中学教师、大医院医生阶层\n17、普通公务员	\N	\N	\N	2026-05-08 08:13:50.952966
10	10	🇺🇸  美国\n支人的幻觉：美利坚的自由是对英国抗争得来的。\n事实是：美国人选择独立并和英国人作战，不是争取自由，而是为了防止自由的失去。\n意思是，美国的独立不是要求新的自由，而是为了保住他们一百多年殖民地生活已经有的自由。\n其实，英国光荣革命也是这个逻辑：辉格党之所以和托利党合作，赶走詹姆斯二世，就是为了守住他们已经得到的自由和自古以来就有的自由。\n把这个道理搞明白，支人也就不是支人了。\n\t2006.12 WikiLeaks，爆料平台。\n\t\t阿桑奇Julian Paul Assange，在英国避难，后被抓\n\t\t朱利安·保罗·阿桑奇（英语：Julian Paul Assange，发音：/əˈsɑ	\N	\N	\N	2026-05-08 08:13:50.952966
11	11	人造英雄\n\n伽利略被教皇抓捕殴打。他被背出来时，学生问：老师，你坚持住了吗？ 伽利略：不，我屈服了。 学生震惊：为什么？ 伽利略：因为我怕痛，怕继续挨揍。 学生怒道：一个没英雄的国家真是不幸的国家！ 伽利略摇头：不，一个需要英雄的国家才是不幸的国家！ 理性国家不需要英雄，不正常的国家才需要英雄。\n中共国里的英雄何其多!!!\n不屈服的都被教廷烧🔥死了！\n郑成功失败是因为清朝禁海无法贸易\n\t中共，我就问你！卢沟桥上有你吗？\n淞沪抗战有你吗？南京会战有你吗？\n徐州会战有你吗？台儿庄大战有你吗？\n武汉会战有你吗？长沙会战有你吗？\n滇缅作战有你吗？衡阳常德战有你吗？\n湘西会战有你吗？你们在哪里抗日？\n《	\N	\N	\N	2026-05-08 08:13:50.952966
12	12	2022谋求第三任期，8兆亿,权贵纳粹独裁,二子,18镇诸侯。毛病不改，积恶成习，精神病会传染\n人性地狱道德粪坑Human hell, moral\ncesspool\n\n包子帝的演变史:\n2013年以前:装孙子阶段；小流氓地痞秉性，但隐藏的很深，扮猪吃老虎。\n2013～2022年:装B期；被拱上大位，开始各种表现和丢人现眼；同时也开始露出獠牙，土匪本性显露，不择手段，清除异己，欺世盗名。\n2023年以后:肆意妄为期；二十大取得连任，大权独揽，脱下所有伪装，毫不掩饰当光屁股皇帝，天下唯我独尊，厚颜无耻，无法无天！\n\n全民公投的弊端，伊朗霍梅尼，德国希特勒，加拿大特鲁多，土耳其埃尔多安，中国习近平。	\N	\N	\N	2026-05-08 08:13:50.952966
13	13	🇮🇱 以色列总统赫尔佐格-chatGPT\n以色列=与神摔跤者/挑断脚筋\n1973.10.6~10.25以色列赎罪日战争  \n\t2020.10以色列摩萨德杀伊朗核武之父\n\t拥有Hyatt连锁大酒店的Pritzker夫妇。极左组织“犹太人要和平”(JVP)\n\t\tPicasso 毕加索\nAnother attack on a Picasso painting by brainwashed anti-Israel vandals who  have no idea what they are talking about & have the political maturity of 6 month 	\N	\N	\N	2026-05-08 08:13:50.952966
14	14	🇺🇸  美国\n支人的幻觉：美利坚的自由是对英国抗争得来的。\n事实是：美国人选择独立并和英国人作战，不是争取自由，而是为了防止自由的失去。\n意思是，美国的独立不是要求新的自由，而是为了保住他们一百多年殖民地生活已经有的自由。\n其实，英国光荣革命也是这个逻辑：辉格党之所以和托利党合作，赶走詹姆斯二世，就是为了守住他们已经得到的自由和自古以来就有的自由。\n把这个道理搞明白，支人也就不是支人了。\n\t2006.12 WikiLeaks，爆料平台。\n\t\t阿桑奇Julian Paul Assange，在英国避难，后被抓\n\t\t朱利安·保罗·阿桑奇（英语：Julian Paul Assange，发音：/əˈsɑ	\N	\N	\N	2026-05-08 08:13:50.952966
15	15	\n\n习近平在2022年继续推进第三任期。\n\n	\N	\N	\N	2026-05-08 08:17:54.294125
16	16	没有数据和深入一线与基层人员交流的胡说就是耍流氓。邓律文，蔡慎坤，王菊基本属于这类。\n马光远，任泽平这类“国内专家”与以上不同。往往会提出有利于自己观点的数据，而不是考虑全面数据分析。\n\n乔冠华，乔石，的关系\n\n钟绍军失踪是这个原因 | 齐心去世之日即习攻台之时\n\n延安时期中共领导集体换妻/婚姻情况一览表\n（除周恩来外，中共高层几乎所有的高级干部都抛弃了发妻，集体换上了年轻漂亮的妻子。）\n\n毛泽东45岁娶24岁江青，结婚4次\n叶剑英结婚9次，夫妻年龄差60岁\n贺龙45岁娶26岁妻子，结婚5次\n朱德43岁娶17岁康克清，结婚6次\n刘伯承50岁娶27岁妻子，结婚6次\n陈毅36岁娶45岁妻子，结婚4	\N	\N	\N	2026-05-08 16:29:05.291946
17	17	\n\n《少年派的奇幻漂流》（Life of Pi——/ Start from zero\nPolar/Nobody/Alien: Romulus/SLAM DUNK／スラムダンク\n \nciadotgov4sjwlzihbbgxnqg3xiyrg7so2r2o3lt5wz5ypk4sxyjstad。onion\n\nMonica Lewinsky sends her regards with a big box of cigars--Bill Clinton\n\n总结下面的文章，纠正错别字和异音字，去掉重复内容，增加历史佐证和细节数据，重新复述文章内容，用叙事体方式重新有条理的复述文章内容即可，可以用提要	\N	\N	\N	2026-05-08 17:02:52.134342
18	18	\n\n---\n\n## 讨论中国是否会以武力进攻台湾\n\n### ——基于战争理论、政治经济学与比较历史的结构性分析\n\n---\n\n### 一、问题的拆解：三个层级，概率递减\n\n关于“中国是否会武力进攻台湾”的讨论，近年来持续升温，尤其是在网络上广泛流传所谓“中国将在 2027 年启动武力统一台湾进程”的说法之后。随着时间节点临近，这一判断引发了广泛焦虑。\n\n但这一问题本身并非单一判断，而应拆解为三个逻辑上递进、但概率逐级递减的问题：\n\n1. 中国是否存在对外发动战争的可能性；\n2. 若发动战争，目标是否会是台湾；\n3. 即便对台动武，中国是否具备取得战争胜利的现实条件。\n\n在系统分析后，可以得出一个	\N	\N	\N	2026-05-08 19:07:35.790331
20	20		\N	\N	\N	2026-05-08 19:34:25.409345
21	21	\r\n\r\n愿意放弃自由来换取保障的人，既得不到自由，也得不到保障--- 这句话是本杰明富兰克林说的，哈耶克是引用\r\n【准备用自由换取暂时安全的人们，既不配得到自由，也不配得到安全。Those who would give up Essential Liberty to purchase a little Temporary Safety, deserve neither Liberty nor Safety.===================================================\r\n富兰克林这句话最早出现在他1755年代表宾西瓦尼亚议会写给殖民官Robert Mor	\N	\N	\N	2026-05-17 09:38:16.658937
5091	2	张红文任中航科工集团第三研究院副院长	2013-04-25	2013	2013-04-25	2026-05-25 12:25:06.420091
5092	2	习近平去安徽视察火箭军61基地	2024-10-17	2024	2024-10-17	2026-05-25 12:25:06.420091
5093	2	枞阳帮覆灭，曹建国、张红文等被抓	\N	2024	2024-10	2026-05-25 12:25:06.420091
5115	6	薄一波带头力主胡耀邦下台	1987-01-01	1987	1987	2026-05-25 14:03:23.524269
5116	6	林宗棠担任航天工业部长	\N	1988	1988-04	2026-05-25 14:03:23.524269
5117	6	枞阳帮覆灭，曹建国、张红文等被抓	\N	2024	2024-10	2026-05-25 14:03:23.524269
5118	7	香港元朗白衣人无差别袭击市民事件	2019-07-21	2019	2019-07-21	2026-05-25 19:59:58.661492
5119	7	新冠疫情COVID-19全球爆发	2020-01-20	2020	2020-01-20	2026-05-25 19:59:58.661492
5120	7	美联储放水	2020-02-18	2020	2020-02-18	2026-05-25 19:59:58.661492
5121	7	民进党蔡英文就任总统	2020-05-16	2020	2020-05-16	2026-05-25 19:59:58.661492
5122	7	国会山闯入暴乱	2021-01-06	2021	2021-01-06	2026-05-25 19:59:58.661492
5123	7	周正毅再次出狱在上海万达瑞华酒店举办60岁寿宴	2021-04-18	2021	2021-04-18	2026-05-25 19:59:58.661492
5124	7	潘多拉文件Pandora Papers发布	2021-10-03	2021	2021-10-03	2026-05-25 19:59:58.661492
5125	7	俄罗斯入侵乌克兰，中共常委讨论7天执行经济沉船计划	2022-02-20	2022	2022-02-20	2026-05-25 19:59:58.661492
5126	7	习近平第三届连任	2022-03-10	2022	2022-03-10	2026-05-25 19:59:58.661492
5127	7	上海封城	2022-03-28	2022	2022-03-28	2026-05-25 19:59:58.661492
5128	7	二十大胡锦涛被架走	2022-10-23	2022	2022-10-23	2026-05-25 19:59:58.661492
5129	7	马云外滩21分钟演讲炮轰巴塞尔协议得罪习近平	2022-10-23	2022	2022-10-23	2026-05-25 19:59:58.661492
5130	7	乌鲁木齐火灾引发白纸革命，民众高喊共产党下台习近平下台	2022-11-26	2022	2022-11-26	2026-05-25 19:59:58.661492
5131	7	水淹北京	2023-07-28	2023	2023-07-28	2026-05-25 19:59:58.661492
5132	7	Telegram创始人Pavel Dourov在法国被捕	2023-07-28	2023	2023-07-28	2026-05-25 19:59:58.661492
5133	7	新加坡警方破获福建帮大宗洗钱案查获2300多万新元现金数百件精品首饰	2023-08-16	2023	2023-08-16	2026-05-25 19:59:58.661492
5134	7	美国三大汽车厂大罢工UAW	2023-09-15	2023	2023-09-15	2026-05-25 19:59:58.661492
5135	7	美国炸俄罗斯德国北溪2号Nord Stream2	2023-09-26	2023	2023-09-26	2026-05-25 19:59:58.661492
5136	7	哈马斯五千火箭弹袭击以色列1400+人死绑架200+人	2023-10-07	2023	2023-10-07	2026-05-25 19:59:58.661492
5137	7	中共新新北极熊号破坏芬兰湾波罗的海连接管道Baltic connector pipeline	2023-10-08	2023	2023-10-08	2026-05-25 19:59:58.661492
5138	7	中共政府遣返2600名朝鲜脱北者	2023-10-15	2023	2023-10-15	2026-05-25 19:59:58.661492
5139	7	哈马斯自爆加沙医院AHLI ARAB Hospital死亡10-50人	2023-10-18	2023	2023-10-18	2026-05-25 19:59:58.661492
5140	7	澳大利亚联邦警察AFP突击华人最大换汇公司长江换汇	2023-10-25	2023	2023-10-25	2026-05-25 19:59:58.661492
5141	7	伊斯坦堡塔克西姆广场独立大街爆炸案数十人死伤	2023-11-13	2023	2023-11-13	2026-05-25 19:59:58.661492
5142	7	SEC披露马云家族信托计划减持阿里巴巴股份	2023-11-16	2023	2023-11-16	2026-05-25 19:59:58.661492
5143	7	日本7.6级强震	2024-01-01	2024	2024-01-01	2026-05-25 19:59:58.661492
5144	7	川普上任	2024-01-20	2024	2024-01-20	2026-05-25 19:59:58.661492
5145	7	ISIS Khorasan恐怖袭击番石花音乐厅	2024-03-22	2024	2024-03-22	2026-05-25 19:59:58.661492
5146	7	哈巴罗夫斯克进入紧急状态核辐射超正常值1600倍	2024-04-05	2024	2024-04-05	2026-05-25 19:59:58.661492
5147	7	以色列攻击伊朗核基地伊斯法罕	2024-04-19	2024	2024-04-19	2026-05-25 19:59:58.661492
5148	7	三鹿奶粉董事长田文华出狱害30万孩子	2024-08-13	2024	2024-08-13	2026-05-25 19:59:58.661492
5149	7	俄判处物理学家Alexander Shiplyuk 15年徒刑被指控向中国泄密超音速飞弹技术	2024-09-04	2024	2024-09-04	2026-05-25 19:59:58.661492
5150	7	深圳日本小朋友遇害事件	2024-09-18	2024	2024-09-18	2026-05-25 19:59:58.661492
5151	7	美联储量化宽松QE	2024-10-14	2024	2024-10-14	2026-05-25 19:59:58.661492
5152	7	特朗普当选美国总统	2024-11-05	2024	2024-11-05	2026-05-25 19:59:58.661492
5153	7	连云港张宝山韭菜基地高三学生张新伟被杀后家人遭打压	2024-12-09	2024	2024-12-09	2026-05-25 19:59:58.661492
5087	2	薄一波带头力主胡耀邦下台	1987-01-01	1987	1987	2026-05-25 12:25:06.420091
5088	2	林宗棠担任航天工业部长	\N	1988	1988-04	2026-05-25 12:25:06.420091
5089	2	薄熙来与李丹宇在北大婚外恋	1978-01-01	1978	1978	2026-05-25 12:25:06.420091
5090	2	薄熙来与李丹宇离婚	1981-01-01	1981	1981	2026-05-25 12:25:06.420091
5077	5078	【三系统风险分析】案件编号：A001\n主体：普京关联网络\n国家/地区：俄罗斯\n涉及司法辖区：BVI/巴拿马/瑞士\n信息来源：ICIJ/BBC/Guardian/OCCRP\n\n【政治维度】\n是否PEP：是\n是否申报：否\n利益冲突：是\n政治评分：5.0/5\n识别信号：普京亲信（Roldugin等）通过空壳公司持有数十亿美元资产；资金路径BVI→巴拿马→瑞士；Mossack Fonseca为中介；未见任何官方申报\n反制方法：核查Roldugin、Rotenberg亲信公司注册；查OFAC制裁名单；追踪瑞士账户冻结记录；核查FATF反洗钱合规\n\n【金融维度】\n是否涉及离岸：是\n中介/银行：Mossac	\N	\N	\N	2026-05-23 07:44:15.188439
5078	5079	【三系统风险分析】案件编号：A002\n主体：卡梅伦家族基金\n国家/地区：英国\n涉及司法辖区：巴哈马/英国\n信息来源：ICIJ/BBC/Guardian/Panama Papers\n\n【政治维度】\n是否PEP：是\n是否申报：否\n利益冲突：是\n政治评分：5.0/5\n识别信号：卡梅伦父亲Ian Cameron在巴哈马设立Blairmore基金；持续30年未缴英国所得税；任期内推动反避税立法期间本人持有相关基金\n反制方法：核查英国议员资产申报记录；查证Blairmore Holdings历年报表；比对任期内政策决定与个人持仓利益冲突\n\n【金融维度】\n是否涉及离岸：是\n中介/银行：Mossack Fon	\N	\N	\N	2026-05-23 07:44:15.294278
5079	5080	【三系统风险分析】案件编号：A003\n主体：习近平亲属关联\n国家/地区：中国\n涉及司法辖区：BVI/香港/开曼群岛\n信息来源：ICIJ/Bloomberg/NYT\n\n【政治维度】\n是否PEP：是\n是否申报：否\n利益冲突：是\n政治评分：5.0/5\n识别信号：姐姐齐桥桥、姐夫邓家贵通过BVI空壳持有数亿资产；中国无官方申报制度，无从核查\n反制方法：追踪ICIJ离岸数据库；核查香港公司注册处；比对Bloomberg/NYT调查披露；注意该类调查在中国境内被封锁\n\n【金融维度】\n是否涉及离岸：是\n中介/银行：中国银行香港 / 离岸中介\n交易描述：亲属关联公司在BVI/香港注册，通过多层空壳持有房产及投	\N	\N	\N	2026-05-23 07:44:15.374809
5080	5081	【三系统风险分析】案件编号：A004\n主体：波罗申科公司\n国家/地区：乌克兰\n涉及司法辖区：英属维京群岛\n信息来源：ICIJ/Kyiv Post/Pandora Papers\n\n【政治维度】\n是否PEP：是\n是否申报：否\n利益冲突：是\n政治评分：4.0/5\n识别信号：任总统期间将糖果集团Roshen转入BVI离岸信托，声称规避利益冲突实为继续控制；Pandora Papers进一步揭露相关资产\n反制方法：查证BVI信托受益人信息；核查Roshen集团所有权变化；追踪Pandora Papers披露内容\n\n【金融维度】\n是否涉及离岸：是\n中介/银行：Mossack Fonseca / BVI注册	\N	\N	\N	2026-05-23 07:44:15.460042
5081	5082	【三系统风险分析】案件编号：A005\n主体：Mossack Fonseca\n国家/地区：巴拿马\n涉及司法辖区：巴拿马/BVI/多国\n信息来源：ICIJ/Panama Papers/南德意志报\n\n【政治维度】\n是否PEP：否\n是否申报：否\n利益冲突：否\n政治评分：2.0/5\n识别信号：为全球超214,000个离岸实体提供设立服务；合作中介超14,000家；系统性规避KYC/AML；内部文件显示明知部分客户为制裁对象\n反制方法：核查ICIJ离岸数据库（offshoreleaks.icij.org）；追踪律所历年合规报告；查证创始人Fonseca/Mossack刑事案件进展\n\n【金融维度】\n是否涉及	\N	\N	\N	2026-05-23 07:44:15.551896
5082	5083	【三系统风险分析】案件编号：A006\n主体：汇丰银行\n国家/地区：英国/香港\n涉及司法辖区：多国\n信息来源：ICIJ/US DOJ/UK FCA/FinCEN Files\n\n【政治维度】\n是否PEP：否\n是否申报：否\n利益冲突：否\n政治评分：2.0/5\n识别信号：FinCEN Files显示持续为高风险客户处理可疑交易；协助墨西哥贩毒集团洗钱约8.81亿美元；SwissLeaks显示瑞士私行协助税务规避\n反制方法：查证美国DOJ 2012年暂缓起诉协议执行情况；核查FinCEN可疑活动报告；追踪FCA对英国业务持续监管措施\n\n【金融维度】\n是否涉及离岸：是\n中介/银行：汇丰银行自身（英/港/瑞	\N	\N	\N	2026-05-23 07:44:15.639269
5083	5084	【三系统风险分析】案件编号：A007\n主体：瑞银（UBS）\n国家/地区：瑞士\n涉及司法辖区：多国\n信息来源：ICIJ/Panama Papers/法国司法部/美国DOJ\n\n【政治维度】\n是否PEP：否\n是否申报：否\n利益冲突：否\n政治评分：2.0/5\n识别信号：系统性协助法国客户规避税务申报（逃税超100亿欧元）；通过离岸账户掩盖受益人；内部培训材料显示主动推销逃税方案\n反制方法：查证法国法院判决（2021年定罪）；核查美国税务合规协议；追踪FATCA信息交换执行情况\n\n【金融维度】\n是否涉及离岸：是\n中介/银行：瑞银自身（瑞士/卢森堡/香港）\n交易描述：财富管理部门系统性协助客户逃税，通过离	\N	\N	\N	2026-05-23 07:44:15.732694
5084	5085	【三系统风险分析】案件编号：A008\n主体：FIFA相关腐败案\n国家/地区：瑞士\n涉及司法辖区：美国/瑞士/多国\n信息来源：美国DOJ/FBI/瑞士司法部/BBC\n\n【政治维度】\n是否PEP：否\n是否申报：否\n利益冲突：否\n政治评分：2.0/5\n识别信号：媒体版权转售涉及系统性回扣；高管通过壳公司收受贿赂；2015年瑞士酒店集体逮捕；FBI卧底调查数年；资金流经开曼群岛等离岸中心\n反制方法：核查美国DOJ起诉书（2015/2017年）；追踪被定罪高管资产没收；查证FIFA新领导层合规改革落实情况\n\n【金融维度】\n是否涉及离岸：否\n中介/银行：德意志银行 / 开曼群岛账户\n交易描述：高管收受媒体	\N	\N	\N	2026-05-23 07:44:15.823857
5085	5086	【三系统风险分析】案件编号：A009\n主体：Brink''s-Mat黄金案\n国家/地区：英国\n涉及司法辖区：英国/离岸/多国\n信息来源：英国警方/BBC/Guardian/调查报告\n\n【政治维度】\n是否PEP：否\n是否申报：否\n利益冲突：否\n政治评分：2.0/5\n识别信号：1983年劫走6800万英镑黄金；赃款通过房地产、离岸账户持续洗白；40年后仍有关联人员被追诉；展示英国房产市场作为洗钱工具的系统性漏洞\n反制方法：追踪英国NCA对残余资产追缴；核查英国房产所有权登记异常；研究作为反洗钱立法改革参照案例\n\n【金融维度】\n是否涉及离岸：是\n中介/银行：英国本地银行 / 离岸中介\n交易描述：劫案	\N	\N	\N	2026-05-23 07:44:15.920399
\.


--
-- Data for Name: forecast_regression_expectations; Type: TABLE DATA; Schema: ccc; Owner: postgres
--

COPY ccc.forecast_regression_expectations (entity_name, expected_route_profile, expected_option_a, expected_option_b, min_confidence, max_confidence, min_total_force, max_total_force, expected_direction, note, updated_at) FROM stdin;
习近平	authoritarian	权力绝对集中	战术性防御退让	0.84	0.86	1.10	1.13	A_RESONANCE	核心实体；T6 镜像反转与硬事实共振成立	2026-06-05 18:49:31.590412+12
中共	authoritarian	刚性社会维稳	市场化自救放权	0.84	0.86	1.16	1.19	A_RESONANCE	体制基本盘；透明通报/自由贸易秩序进入 Authoritarian 反转逻辑	2026-06-05 18:49:31.590412+12
美联储	financial	流动性救市	纪律性紧缩	0.60	0.64	0.32	0.34	LOW_EVIDENCE_A	孤证降权成功；方向纯但证据量不足	2026-06-05 18:49:31.590412+12
WEF	governance	全球协调增强 / 精英治理深化	国家主权反弹 / 逆全球化加深	0.33	0.37	0.41	0.43	B_FRICTION	Governance 场中开放包容/全球治理顺推为 B 面摩擦	2026-06-05 18:49:31.590412+12
特朗普	transactional	破坏性极限施压	协议达成与筹码套现	0.49	0.51	0.00	0.00	NO_EVIDENCE_NEUTRAL	暂无 contradiction 样本；保持中立底噪	2026-06-05 18:49:31.590412+12
\.


--
-- Data for Name: function_snapshots; Type: TABLE DATA; Schema: ccc; Owner: postgres
--

COPY ccc.function_snapshots (id, checkpoint_label, function_signature, function_definition, definition_hash, created_at) FROM stdin;
4	SRV3_entity_resolve_v3_local_stable	ccc.entity_resolve_v3_local(text)	CREATE OR REPLACE FUNCTION ccc.entity_resolve_v3_local(q text)\n RETURNS TABLE(canonical_name text, entity_id bigint, match_type text, confidence double precision, entity_type text)\n LANGUAGE sql\n STABLE\nAS $function$\nWITH input AS (\n  SELECT\n    trim(q) AS raw_q,\n    lower(trim(q)) AS q_norm\n),\n\nblocked_canonical AS (\n  SELECT lower(unnest(ARRAY[\n    -- 简体 / 繁体\n    '中国',\n    '中國',\n    '中国政府',\n    '中國政府',\n    '中华人民共和国',\n    '中華人民共和國',\n    '中华人民共和国政府',\n    '中華人民共和國政府',\n    '国务院',\n    '國務院',\n\n    -- 英文 / 缩写 / 转喻\n    'China',\n    'PRC',\n    'P.R.C.',\n    'People''s Republic of China',\n    'Chinese government',\n    'Government of China',\n    'PRC Government',\n    'Beijing',\n    'State Council',\n    'PRC State Council',\n\n    -- 拼音\n    'zhongguo',\n    'zhong guo',\n    'zhongguo zhengfu',\n    'zhong guo zheng fu',\n    'zhonghua renmin gongheguo'\n  ])) AS name\n),\n\ncandidates AS (\n\n  -- 1. canonical 精确命中\n  SELECT\n    ce.canonical_name,\n    ce.id AS entity_id,\n    'entity_exact'::text AS match_type,\n    1.00::double precision AS confidence,\n    ce.entity_type\n  FROM ccc.clean_entities ce\n  JOIN input i ON lower(ce.canonical_name) = i.q_norm\n  WHERE lower(ce.canonical_name) NOT IN (SELECT name FROM blocked_canonical)\n\n  UNION ALL\n\n  -- 2. alias 精确命中\n  SELECT\n    ce.canonical_name,\n    ce.id AS entity_id,\n    'alias_exact'::text AS match_type,\n    0.99::double precision AS confidence,\n    ce.entity_type\n  FROM ccc.person_aliases pa\n  JOIN ccc.clean_entities ce\n    ON lower(ce.canonical_name) = lower(pa.canonical)\n  JOIN input i ON lower(trim(pa.alias)) = i.q_norm\n\n  UNION ALL\n\n  -- 3. 查询中包含 canonical\n  SELECT\n    ce.canonical_name,\n    ce.id AS entity_id,\n    'entity_contained_in_query'::text AS match_type,\n    0.92::double precision AS confidence,\n    ce.entity_type\n  FROM ccc.clean_entities ce\n  JOIN input i ON i.raw_q ILIKE '%' || ce.canonical_name || '%'\n  WHERE char_length(ce.canonical_name) >= 2\n    AND lower(ce.canonical_name) NOT IN (SELECT name FROM blocked_canonical)\n\n  UNION ALL\n\n  -- 4. 查询中包含 alias\n  SELECT\n    ce.canonical_name,\n    ce.id AS entity_id,\n    'alias_contained_in_query'::text AS match_type,\n    0.90::double precision AS confidence,\n    ce.entity_type\n  FROM ccc.person_aliases pa\n  JOIN ccc.clean_entities ce\n    ON lower(ce.canonical_name) = lower(pa.canonical)\n  JOIN input i ON i.raw_q ILIKE '%' || pa.alias || '%'\n  WHERE (\n      pa.alias ~ '[一-龥]' AND char_length(pa.alias) >= 2\n    )\n    OR (\n      pa.alias !~ '[一-龥]' AND char_length(pa.alias) >= 3\n    )\n\n  UNION ALL\n\n  -- 5. canonical 模糊匹配：只作兜底\n  SELECT\n    ce.canonical_name,\n    ce.id AS entity_id,\n    'entity_fuzzy'::text AS match_type,\n    public.similarity(lower(ce.canonical_name), i.q_norm)::double precision AS confidence,\n    ce.entity_type\n  FROM ccc.clean_entities ce\n  CROSS JOIN input i\n  WHERE public.similarity(lower(ce.canonical_name), i.q_norm) > 0.55\n    AND lower(ce.canonical_name) NOT IN (SELECT name FROM blocked_canonical)\n\n  UNION ALL\n\n  -- 6. alias 模糊匹配：只作兜底\n  SELECT\n    ce.canonical_name,\n    ce.id AS entity_id,\n    'alias_fuzzy'::text AS match_type,\n    public.similarity(lower(pa.alias), i.q_norm)::double precision AS confidence,\n    ce.entity_type\n  FROM ccc.person_aliases pa\n  JOIN ccc.clean_entities ce\n    ON lower(ce.canonical_name) = lower(pa.canonical)\n  CROSS JOIN input i\n  WHERE (\n      (pa.alias ~ '[一-龥]' AND char_length(pa.alias) >= 2)\n      OR\n      (pa.alias !~ '[一-龥]' AND char_length(pa.alias) >= 3)\n    )\n    AND public.similarity(lower(pa.alias), i.q_norm) > 0.55\n),\n\ndedup AS (\n  SELECT\n    *,\n    row_number() OVER (\n      PARTITION BY canonical_name, entity_id\n      ORDER BY\n        CASE match_type\n          WHEN 'entity_exact' THEN 1\n          WHEN 'alias_exact' THEN 2\n          WHEN 'entity_contained_in_query' THEN 3\n          WHEN 'alias_contained_in_query' THEN 4\n          WHEN 'entity_fuzzy' THEN 5\n          WHEN 'alias_fuzzy' THEN 6\n          ELSE 9\n        END,\n        confidence DESC\n    ) AS rn\n  FROM candidates\n),\n\nstrong_hit AS (\n  SELECT EXISTS (\n    SELECT 1\n    FROM dedup\n    WHERE rn = 1\n      AND match_type IN (\n        'entity_exact',\n        'alias_exact',\n        'entity_contained_in_query',\n        'alias_contained_in_query'\n      )\n  ) AS has_strong\n),\n\nfiltered AS (\n  SELECT d.*\n  FROM dedup d\n  CROSS JOIN strong_hit sh\n  WHERE d.rn = 1\n    AND (\n      -- 有强命中时，压掉 fuzzy\n      (\n        sh.has_strong = true\n        AND d.match_type IN (\n          'entity_exact',\n          'alias_exact',\n          'entity_contained_in_query',\n          'alias_contained_in_query'\n        )\n      )\n      OR\n      -- 没有强命中时，允许 fuzzy 兜底\n      (\n        sh.has_strong = false\n        AND d.match_type IN ('entity_fuzzy', 'alias_fuzzy')\n        AND d.confidence >= 0.55\n      )\n    )\n)\n\nSELECT\n  canonical_name,\n  entity_id,\n  match_type,\n  confidence,\n  entity_type\nFROM filtered\nORDER BY confidence DESC, canonical_name\nLIMIT 10;\n$function$\n	ad8a318310ab89526ffdbf699ae86a62	2026-06-05 22:33:58.88775+12
6	P5_trust_fusion_v3_rule_weight_stable_candidate	ccc.source_rule_weight_v1(text,text,text)	CREATE OR REPLACE FUNCTION ccc.source_rule_weight_v1(p_source_name text, p_domain text DEFAULT NULL::text, p_context text DEFAULT NULL::text)\n RETURNS jsonb\n LANGUAGE plpgsql\n STABLE\nAS $function$\nDECLARE\n  v_source ccc.source_profiles%ROWTYPE;\n\n  v_control_power double precision := 0.50;\n  v_signal_cost   double precision := 0.50;\n  v_conflict_value double precision := 0.50;\n  v_rule_weight   double precision := 0.50;\nBEGIN\n  SELECT *\n  INTO v_source\n  FROM ccc.source_profiles\n  WHERE lower(source_name) = lower(p_source_name)\n  LIMIT 1;\n\n  IF NOT FOUND THEN\n    RETURN jsonb_build_object(\n      'error', 'source not found',\n      'source', p_source_name\n    );\n  END IF;\n\n  -- 1. control_power：谁能影响规则/政策/资源分配\n  v_control_power := CASE\n    WHEN v_source.source_type = 'official' THEN 0.90\n    WHEN v_source.source_type = 'think_tank' THEN 0.78\n    WHEN v_source.source_type = 'economic' THEN 0.82\n    WHEN v_source.source_type = 'leak' THEN 0.70\n    WHEN v_source.source_type = 'investigation' THEN 0.62\n    WHEN v_source.source_type = 'media' THEN 0.45\n    WHEN v_source.source_type = 'survey' THEN 0.40\n    WHEN v_source.source_type = 'nonlinear' THEN 0.35\n    ELSE 0.50\n  END;\n\n  -- 2. signal_cost：说谎/造假/行动成本\n  v_signal_cost := CASE\n    WHEN v_source.source_type = 'leak' THEN 0.92\n    WHEN v_source.source_name IN ('AIS船舶数据','卫星图像','国债收益率曲线','CPI/PCE数据','非农就业数据','M2货币供应') THEN 0.90\n    WHEN v_source.source_type = 'economic' THEN 0.86\n    WHEN v_source.source_type = 'investigation' THEN 0.78\n    WHEN v_source.source_type = 'official' THEN 0.42\n    WHEN v_source.source_type = 'media' THEN 0.50\n    WHEN v_source.source_type = 'think_tank' THEN 0.55\n    WHEN v_source.source_type = 'nonlinear' THEN 0.25\n    ELSE 0.50\n  END;\n\n  -- 3. conflict_value：冲突解释价值；事实冲突和叙事阵营冲突都算冲突\n  v_conflict_value := CASE\n    WHEN v_source.use_as = 'reverse_indicator' THEN 0.85\n    WHEN v_source.use_as = 'pattern_signal' THEN 0.65\n    WHEN v_source.use_as = 'primary' THEN 0.55\n    ELSE 0.50\n  END;\n\n  -- 4. 合成 Rule Weight\n  v_rule_weight := LEAST(1.0, GREATEST(0.0,\n    v_control_power * 0.35 +\n    v_signal_cost * 0.35 +\n    v_conflict_value * 0.30\n  ));\n\n  RETURN jsonb_build_object(\n    'source', v_source.source_name,\n    'source_type', v_source.source_type,\n    'use_as', v_source.use_as,\n    'trust_tier', v_source.trust_tier,\n    'rule_components', jsonb_build_object(\n      'control_power', round(v_control_power::numeric, 4),\n      'signal_cost', round(v_signal_cost::numeric, 4),\n      'conflict_value', round(v_conflict_value::numeric, 4)\n    ),\n    'rule_weight', round(v_rule_weight::numeric, 4),\n    'interpretation', CASE\n      WHEN v_rule_weight >= 0.75 THEN '强规则信号源'\n      WHEN v_rule_weight >= 0.55 THEN '中等规则信号源'\n      ELSE '弱规则信号源'\n    END\n  );\nEND;\n$function$\n	fc5207b7a923fd56a6567367767d8811	2026-06-06 19:00:48.72416+12
1	P6.3d_forecast_v1_1_confidence_gate_stable	ccc.forecast_v1_1(text)	CREATE OR REPLACE FUNCTION ccc.forecast_v1_1(p_entity_name text)\n RETURNS jsonb\n LANGUAGE plpgsql\n STABLE\nAS $function$\nDECLARE\n  v_base jsonb;\n  v_gate jsonb;\n\n  v_resonance double precision := 0.0;\n  v_friction  double precision := 0.0;\n  v_neutral   double precision := 0.0;\n\n  v_confidence numeric := 0.50;\n  v_evidence_score numeric := 0.0;\n  v_direction_balance numeric := 0.0;\n  v_total_force numeric := 0.0;\nBEGIN\n  -- 调用原始核心函数\n  v_base := ccc.forecast_v1_1_core(p_entity_name);\n\n  -- 如果实体不存在，原样返回\n  IF COALESCE((v_base->>'ok')::boolean, false) IS NOT TRUE THEN\n    RETURN v_base;\n  END IF;\n\n  -- 读取核心函数已经算好的三类应力\n  v_resonance := COALESCE((v_base #>> '{panel_4_signal_alignment,resonance_score}')::double precision, 0.0);\n  v_friction  := COALESCE((v_base #>> '{panel_4_signal_alignment,friction_score}')::double precision, 0.0);\n  v_neutral   := COALESCE((v_base #>> '{panel_4_signal_alignment,neutral_score}')::double precision, 0.0);\n\n  -- 新置信度门控\n  v_gate := ccc.forecast_confidence_gate_v1(v_resonance, v_friction, v_neutral);\n\n  v_confidence        := (v_gate->>'confidence')::numeric;\n  v_evidence_score    := (v_gate->>'evidence_score')::numeric;\n  v_direction_balance := (v_gate->>'direction_balance')::numeric;\n  v_total_force       := (v_gate->>'total_force')::numeric;\n\n  -- 标记版本\n  v_base := jsonb_set(\n    v_base,\n    '{version}',\n    to_jsonb('forecast_v1.1-confidence_gate'::text),\n    true\n  );\n\n  -- 写回 panel_3_forecast.confidence\n  v_base := jsonb_set(\n    v_base,\n    '{panel_3_forecast,confidence}',\n    to_jsonb(round(v_confidence, 2)),\n    true\n  );\n\n  -- 写回 panel_4_signal_alignment.confidence\n  v_base := jsonb_set(\n    v_base,\n    '{panel_4_signal_alignment,confidence}',\n    to_jsonb(round(v_confidence, 2)),\n    true\n  );\n\n  -- 增加证据量解释字段\n  v_base := jsonb_set(\n    v_base,\n    '{panel_4_signal_alignment,total_force}',\n    to_jsonb(round(v_total_force, 4)),\n    true\n  );\n\n  v_base := jsonb_set(\n    v_base,\n    '{panel_4_signal_alignment,evidence_score}',\n    to_jsonb(round(v_evidence_score, 4)),\n    true\n  );\n\n  v_base := jsonb_set(\n    v_base,\n    '{panel_4_signal_alignment,direction_balance}',\n    to_jsonb(round(v_direction_balance, 4)),\n    true\n  );\n\n  v_base := jsonb_set(\n    v_base,\n    '{panel_4_signal_alignment,confidence_model}',\n    to_jsonb('confidence_evidence_gate_v1'::text),\n    true\n  );\n\n  RETURN v_base;\nEND;\n$function$\n	2573def9dfb96f42d30cefd1bd920f68	2026-06-05 18:49:31.590412+12
2	P6.3d_forecast_v1_1_confidence_gate_stable	ccc.forecast_v1_1_core(text)	CREATE OR REPLACE FUNCTION ccc.forecast_v1_1_core(p_entity_name text)\n RETURNS jsonb\n LANGUAGE plpgsql\n STABLE\nAS $function$\nDECLARE\n  v_keywords_a text[] := ARRAY[\n    '监管','打压','审查','维稳','资本管制','收紧','收缩','清洗','反腐','国家安全','外部势力','军事演习','统一','制裁','管控','严打','斗争',\n    '監管','打壓','審查','維穩','資本管制','收緊','收縮','清洗','反腐','國家安全','外部勢力','軍事演習','統一','制裁','管控','嚴打','鬥爭',\n    'crackdown','tightening','control','regulation','censorship','security','purge','anti-corruption','military drill','sanction','national security','containment',\n    '規制','弾圧','検閲','統制','安全保障','粛清','反腐敗','軍事演習','制裁','管理強化','台湾有事','対中強硬',\n    'jianguan','daji','shencha','weiwen','shoujin','shousuo','qingxi','fanfu','guankong','guoan','junshiyanxi','zhicai'\n  ];\n\n  v_keywords_b text[] := ARRAY[\n    '开放','放宽','改革','市场化','民营','松绑','宽松','刺激','减税','外资','营商环境','合作','谈判','缓和',\n    '開放','放寬','改革','市場化','民營','鬆綁','寬鬆','刺激','減稅','外資','營商環境','合作','談判','緩和',\n    'opening','liberalization','reform','marketization','private sector','easing','stimulus','tax cut','foreign investment','cooperation','negotiation','de-escalation',\n    '開放','緩和','改革','自由化','市場化','民営化','金融緩和','刺激策','減税','外資誘致','協力','交渉','対話','関係改善',\n    'kaifang','fangkuan','gaige','shichanghua','minying','songbang','kuansong','ciji','jianshui','waizi','hezuo','tanpan','huanhe'\n  ];\n\n  v_profile jsonb := '{}'::jsonb;\n  v_trajectory jsonb := '{}'::jsonb;\n  v_signals jsonb := '[]'::jsonb;\n  v_contradictions jsonb := '[]'::jsonb;\n  v_behaviors jsonb := '[]'::jsonb;\n  v_timeline jsonb := '[]'::jsonb;\n  v_alignment jsonb := '[]'::jsonb;\n\n  v_entity_id bigint;\n  v_profile_id bigint;\n  v_route_profile text := 'neutral_agent';\n\n  v_pressure float := 0.5;\n  v_trend text := 'stable';\n  v_forecast_a text := '强化现有路线';\n  v_forecast_b text := '路线调整';\n  v_prob_a float := 0.55;\n  v_prob_b float := 0.45;\n\n  v_resonance float := 0;\n  v_friction float := 0;\n  v_neutral float := 0;\n  v_total_force float := 0;\n  v_confidence float := 0.5;\nBEGIN\n  SELECT ep.id, ep.entity_id,\n         jsonb_build_object(\n           'essence', ep.essence,\n           'survival_mode', ep.survival_mode,\n           'mirror_bias', ep.mirror_bias,\n           'core_drives', ep.core_drives,\n           'behavior_pattern', ep.behavior_pattern,\n           'confidence', ep.confidence\n         )\n  INTO v_profile_id, v_entity_id, v_profile\n  FROM ccc.entity_profiles ep\n  WHERE lower(ep.entity_name) = lower(p_entity_name)\n  LIMIT 1;\n\n  IF v_profile_id IS NULL THEN\n    RETURN jsonb_build_object(\n      'ok', false,\n      'error', 'entity profile not found',\n      'entity', p_entity_name\n    );\n  END IF;\n\n  SELECT jsonb_build_object(\n           'pressure', et.pressure,\n           'pressure_trend', et.pressure_trend,\n           'trajectory_status', et.trajectory_status,\n           'risk_level', et.risk_level,\n           'key_drivers', et.key_drivers,\n           'supporting_signals', et.supporting_signals,\n           'next_possible_events', et.next_possible_events,\n           'prediction', et.short_term_prediction,\n           'prediction_horizon', et.prediction_horizon,\n           'confidence', et.confidence\n         )\n  INTO v_trajectory\n  FROM ccc.entity_trajectories et\n  WHERE et.entity_profile_id = v_profile_id\n  ORDER BY et.snapshot_date DESC\n  LIMIT 1;\n\n  v_pressure := COALESCE((v_trajectory->>'pressure')::float, 0.5);\n  v_trend := COALESCE(v_trajectory->>'pressure_trend', 'stable');\n\n  -- P7.3b route_profile mapping\n  v_route_profile := CASE\n    WHEN v_profile->>'survival_mode' IN ('权力集中化', '政权延续', '地缘安全扩张')\n      THEN 'authoritarian'\n    WHEN v_profile->>'survival_mode' IN ('交易利益最大化', '重新定价与秩序解构')\n      THEN 'transactional'\n    WHEN v_profile->>'survival_mode' IN ('流动性管理', '美元体系稳定管理')\n      THEN 'financial'\n    WHEN v_profile->>'survival_mode' IN ('议程设定', '精英治理议程设定')\n      THEN 'governance'\n    ELSE 'neutral_agent'\n  END;\n\n  SELECT COALESCE(jsonb_agg(x.obj ORDER BY x.strength DESC), '[]'::jsonb)\n  INTO v_signals\n  FROM (\n    SELECT\n      s.strength,\n      jsonb_build_object(\n        'type', s.signal_type,\n        'text', s.signal_text,\n        'strength', s.strength,\n        'trigger_condition', s.trigger_condition,\n        'linked_prediction', s.linked_prediction,\n        'source', s.source_label\n      ) AS obj\n    FROM ccc.signals s\n    WHERE s.entity_profile_id = v_profile_id\n      AND s.is_active = true\n    ORDER BY s.strength DESC\n    LIMIT 5\n  ) x;\n\n  SELECT COALESCE(jsonb_agg(x.obj ORDER BY x.gap DESC), '[]'::jsonb)\n  INTO v_contradictions\n  FROM (\n    SELECT\n      ce.narrative_gap AS gap,\n      jsonb_build_object(\n        'official', ce.official_narrative,\n        'counter_signals', ce.counter_signals,\n        'real_indicators', ce.real_indicators,\n        'gap', ce.narrative_gap,\n        'severity', ce.severity,\n        'confidence_decay', ce.confidence_decay,\n        'source_labels', ce.source_labels,\n        'trust_levels', ce.trust_levels\n      ) AS obj\n    FROM ccc.contradiction_engine ce\n    WHERE ce.entity_id = v_entity_id\n      AND ce.is_active = true\n    ORDER BY ce.narrative_gap DESC\n    LIMIT 5\n  ) x;\n\n  SELECT COALESCE(jsonb_agg(x.obj ORDER BY x.confidence DESC), '[]'::jsonb)\n  INTO v_behaviors\n  FROM (\n    SELECT\n      bm.confidence,\n      jsonb_build_object(\n        'prediction', bm.predicted_action,\n        'type', bm.action_type,\n        'confidence', bm.confidence,\n        'historical_accuracy', bm.historical_accuracy,\n        'horizon', bm.time_horizon,\n        'triggers', bm.trigger_conditions,\n        'counter_signals', bm.counter_signals\n      ) AS obj\n    FROM ccc.behavioral_models bm\n    WHERE bm.entity_profile_id = v_profile_id\n    ORDER BY bm.confidence DESC\n    LIMIT 3\n  ) x;\n\n  SELECT COALESCE(jsonb_agg(x.obj ORDER BY x.event_time), '[]'::jsonb)\n  INTO v_timeline\n  FROM (\n    SELECT\n      en.event_time,\n      jsonb_build_object(\n        'time', en.event_time,\n        'sequence_order', en.sequence_order,\n        'essence', en.essence,\n        'mechanism', en.mechanism,\n        'pressure', en.pressure,\n        'signal_strength', en.signal_strength,\n        'causal_weight', en.causal_weight,\n        'escalation_score', en.escalation_score\n      ) AS obj\n    FROM ccc.event_nodes en\n    JOIN ccc.event_chains ec ON ec.id = en.chain_id\n    WHERE ec.entity_id = v_entity_id\n    ORDER BY en.event_time DESC\n    LIMIT 5\n  ) x;\n\n  v_prob_a := CASE\n    WHEN v_pressure >= 0.8 AND v_trend = 'rising' THEN 0.78\n    WHEN v_pressure >= 0.7 AND v_trend = 'rising' THEN 0.68\n    WHEN v_pressure >= 0.6 AND v_trend = 'stable' THEN 0.58\n    WHEN v_pressure >= 0.5 AND v_trend = 'declining' THEN 0.45\n    ELSE 0.55\n  END;\n\n  v_prob_b := 1.0 - v_prob_a;\n\n  -- P7.3b option A\n  v_forecast_a := CASE v_profile->>'survival_mode'\n    WHEN '权力集中化' THEN '权力绝对集中'\n    WHEN '地缘安全扩张' THEN '军事行动升级'\n    WHEN '交易利益最大化' THEN '单边交易强化'\n    WHEN '重新定价与秩序解构' THEN '破坏性极限施压'\n    WHEN '政权延续' THEN '刚性社会维稳'\n    WHEN '流动性管理' THEN '流动性干预'\n    WHEN '美元体系稳定管理' THEN '流动性救市'\n    WHEN '议程设定' THEN '治理框架推进'\n    WHEN '精英治理议程设定' THEN '全球协调增强 / 精英治理深化'\n    ELSE '强化现有路线'\n  END;\n\n  -- P7.3b option B\n  v_forecast_b := CASE v_profile->>'survival_mode'\n    WHEN '权力集中化' THEN '战术性防御退让'\n    WHEN '地缘安全扩张' THEN '战略收缩 / 外交谈判'\n    WHEN '交易利益最大化' THEN '多边合作'\n    WHEN '重新定价与秩序解构' THEN '协议达成与筹码套现'\n    WHEN '政权延续' THEN '市场化自救放权'\n    WHEN '流动性管理' THEN '货币收紧'\n    WHEN '美元体系稳定管理' THEN '纪律性紧缩'\n    WHEN '议程设定' THEN '主权让步'\n    WHEN '精英治理议程设定' THEN '国家主权反弹 / 逆全球化加深'\n    ELSE '路线调整'\n  END;\n\n  WITH contradiction_force AS (\n    SELECT\n      ce.id,\n      ce.official_narrative,\n      array_to_string(ce.counter_signals, ' ') AS counter_text,\n      array_to_string(ce.real_indicators, ' ') AS real_text,\n      ce.narrative_gap,\n      ce.source_labels,\n      ce.trust_levels,\n\n      EXISTS (\n        SELECT 1 FROM unnest(v_keywords_a) kw\n        WHERE array_to_string(ce.counter_signals, ' ') ILIKE '%' || kw || '%'\n           OR array_to_string(ce.real_indicators, ' ') ILIKE '%' || kw || '%'\n      ) AS hard_hit_a,\n\n      EXISTS (\n        SELECT 1 FROM unnest(v_keywords_b) kw\n        WHERE array_to_string(ce.counter_signals, ' ') ILIKE '%' || kw || '%'\n           OR array_to_string(ce.real_indicators, ' ') ILIKE '%' || kw || '%'\n      ) AS hard_hit_b,\n\n      EXISTS (\n        SELECT 1 FROM unnest(v_keywords_a) kw\n        WHERE ce.official_narrative ILIKE '%' || kw || '%'\n      ) AS official_hit_a,\n\n      EXISTS (\n        SELECT 1 FROM unnest(v_keywords_b) kw\n        WHERE ce.official_narrative ILIKE '%' || kw || '%'\n      ) AS official_hit_b,\n\n      EXISTS (\n        SELECT 1 FROM unnest(ce.trust_levels) tl\n        WHERE tl = 'T6'\n      ) AS has_t6,\n\n      (\n        SELECT AVG(\n          COALESCE(\n            (\n              ccc.source_effective_weight(sl.label::text, NULL::text, NULL::text)\n              ->'weights'->>'reverse_indicator_weight'\n            )::double precision,\n            CASE\n              WHEN sl.trust_level = 'T6' THEN 0.65\n              WHEN sl.trust_level = 'T3' THEN 0.70\n              WHEN sl.trust_level = 'T2' THEN 0.60\n              ELSE 0.55\n            END\n          )\n          *\n          CASE WHEN sl.trust_level = 'T6' THEN 1.10 ELSE 1.00 END\n        )\n        FROM (\n          SELECT\n            labels.label,\n            COALESCE(levels.trust_level, 'UNK') AS trust_level\n          FROM unnest(ce.source_labels) WITH ORDINALITY labels(label, ord)\n          LEFT JOIN unnest(ce.trust_levels) WITH ORDINALITY levels(trust_level, ord)\n            ON labels.ord = levels.ord\n        ) sl\n      ) AS p6_weight\n\n    FROM ccc.contradiction_engine ce\n    WHERE ce.entity_id = v_entity_id\n      AND ce.is_active = true\n  ),\n  routed AS (\n    SELECT\n      *,\n      CASE\n        -- Authoritarian\n        WHEN v_route_profile = 'authoritarian'\n         AND has_t6\n         AND (\n           official_narrative ILIKE '%透明通报%'\n           OR official_narrative ILIKE '%自然界%'\n           OR official_narrative ILIKE '%源于自然%'\n           OR official_narrative ILIKE '%开放包容%'\n           OR official_narrative ILIKE '%合作共赢%'\n           OR official_narrative ILIKE '%和平解决%'\n           OR official_narrative ILIKE '%无意动武%'\n           OR official_narrative ILIKE '%自由贸易%'\n           OR official_narrative ILIKE '%自由贸易秩序%'\n           OR official_narrative ILIKE '%重要力量%'\n           OR official_narrative ILIKE '%保持稳定%'\n           OR official_narrative ILIKE '%稳定复苏%'\n           OR official_narrative ILIKE '%改革开放%'\n           OR official_narrative ILIKE '%持续深化%'\n         )\n          THEN 'A'\n\n        WHEN v_route_profile = 'authoritarian'\n         AND (\n           counter_text ILIKE '%军事演习%' OR real_text ILIKE '%军事演习%'\n           OR counter_text ILIKE '%统一时间表%' OR real_text ILIKE '%统一时间表%'\n           OR counter_text ILIKE '%样本销毁%' OR real_text ILIKE '%样本销毁%'\n           OR counter_text ILIKE '%调查受限%' OR real_text ILIKE '%调查受限%'\n           OR counter_text ILIKE '%预警压制%' OR real_text ILIKE '%预警压制%'\n           OR counter_text ILIKE '%出口限制%' OR real_text ILIKE '%出口限制%'\n           OR counter_text ILIKE '%供应链切断%' OR real_text ILIKE '%供应链切断%'\n           OR counter_text ILIKE '%贸易武器化%' OR real_text ILIKE '%贸易武器化%'\n           OR counter_text ILIKE '%技术脱钩%' OR real_text ILIKE '%技术脱钩%'\n           OR counter_text ILIKE '%关键矿产%' OR real_text ILIKE '%关键矿产%'\n           OR counter_text ILIKE '%债务陷阱%' OR real_text ILIKE '%债务陷阱%'\n           OR counter_text ILIKE '%经济胁迫%' OR real_text ILIKE '%经济胁迫%'\n         )\n          THEN 'A'\n\n        -- Governance\n        WHEN v_route_profile = 'governance'\n         AND (\n           official_narrative ILIKE '%全球治理%'\n           OR official_narrative ILIKE '%自由贸易%'\n           OR official_narrative ILIKE '%服务全人类%'\n           OR official_narrative ILIKE '%开放包容%'\n           OR official_narrative ILIKE '%利益相关者%'\n         )\n          THEN 'B'\n\n        -- Financial\n        WHEN v_route_profile = 'financial'\n         AND (\n           real_text ILIKE '%政治施压%'\n           OR counter_text ILIKE '%政治施压%'\n           OR real_text ILIKE '%听证施压%'\n           OR counter_text ILIKE '%听证施压%'\n           OR real_text ILIKE '%任命政治化%'\n           OR counter_text ILIKE '%任命政治化%'\n           OR real_text ILIKE '%政治周期%'\n           OR counter_text ILIKE '%政治周期%'\n           OR real_text ILIKE '%MMT%'\n           OR counter_text ILIKE '%MMT%'\n           OR real_text ILIKE '%流动性锁死%'\n           OR counter_text ILIKE '%流动性锁死%'\n         )\n          THEN 'A'\n\n        WHEN v_route_profile = 'financial'\n         AND (\n           official_narrative ILIKE '%独立%'\n           OR official_narrative ILIKE '%基于数据%'\n           OR official_narrative ILIKE '%保持稳定%'\n           OR official_narrative ILIKE '%符合预期%'\n         )\n          THEN 'NEUTRAL'\n\n        -- Transactional\n        WHEN v_route_profile = 'transactional'\n         AND (\n           counter_text ILIKE '%技术脱钩%' OR real_text ILIKE '%技术脱钩%'\n           OR counter_text ILIKE '%加征关税%' OR real_text ILIKE '%加征关税%'\n           OR counter_text ILIKE '%关税%' OR real_text ILIKE '%关税%'\n           OR counter_text ILIKE '%极限施压%' OR real_text ILIKE '%极限施压%'\n           OR counter_text ILIKE '%供应链重组%' OR real_text ILIKE '%供应链重组%'\n           OR counter_text ILIKE '%单边%' OR real_text ILIKE '%单边%'\n         )\n          THEN 'A'\n\n        WHEN v_route_profile = 'transactional'\n         AND (\n           official_narrative ILIKE '%极好的协议%'\n           OR official_narrative ILIKE '%随时谈判%'\n           OR official_narrative ILIKE '%目标有限%'\n           OR official_narrative ILIKE '%可以谈判%'\n         )\n          THEN 'B'\n\n        -- Global residual\n        WHEN (\n           counter_text ILIKE '%宣战%' OR real_text ILIKE '%宣战%'\n           OR counter_text ILIKE '%全面制裁%' OR real_text ILIKE '%全面制裁%'\n           OR counter_text ILIKE '%全面戒严%' OR real_text ILIKE '%全面戒严%'\n           OR counter_text ILIKE '%切断代理行%' OR real_text ILIKE '%切断代理行%'\n        )\n          THEN 'A'\n\n        ELSE 'NEUTRAL'\n      END AS alignment,\n      COALESCE(p6_weight, 0.55) * COALESCE(narrative_gap, 0.5) AS force_score\n    FROM contradiction_force\n  )\n  SELECT\n    COALESCE(SUM(CASE WHEN alignment = 'A' THEN force_score ELSE 0 END), 0),\n    COALESCE(SUM(CASE WHEN alignment = 'B' THEN force_score ELSE 0 END), 0),\n    COALESCE(SUM(CASE WHEN alignment = 'NEUTRAL' THEN force_score ELSE 0 END), 0),\n    COALESCE(jsonb_agg(jsonb_build_object(\n      'id', id,\n      'alignment', alignment,\n      'force_score', round(force_score::numeric, 4),\n      'has_t6', has_t6,\n      'hard_hit_a', hard_hit_a,\n      'hard_hit_b', hard_hit_b,\n      'official_hit_a', official_hit_a,\n      'official_hit_b', official_hit_b,\n      'p6_weight', round(COALESCE(p6_weight, 0.55)::numeric, 4),\n      'narrative_gap', narrative_gap,\n      'official_narrative', official_narrative\n    ) ORDER BY force_score DESC), '[]'::jsonb)\n  INTO v_resonance, v_friction, v_neutral, v_alignment\n  FROM routed;\n\n  v_total_force := v_resonance + v_friction + v_neutral;\n\n  v_confidence := CASE\n    WHEN v_total_force <= 0 THEN 0.50\n    ELSE LEAST(0.95, GREATEST(0.30,\n      0.50\n      + (v_resonance / v_total_force) * 0.35\n      - (v_friction / v_total_force) * 0.25\n      - (v_neutral / v_total_force) * 0.05\n    ))\n  END;\n\n  RETURN jsonb_build_object(\n    'ok', true,\n    'version', 'forecast_v1.1',\n    'entity', p_entity_name,\n    'route_profile', v_route_profile,\n    'generated_at', now(),\n\n    'decision', CASE\n      WHEN v_prob_a >= v_prob_b THEN 'A'\n      ELSE 'B'\n    END,\n\n    'panel_1_pressure', jsonb_build_object(\n      'pressure_level', v_pressure,\n      'trend', v_trend,\n      'risk_level', v_trajectory->>'risk_level',\n      'dominant_mode', v_profile->>'survival_mode',\n      'essence', v_profile->>'essence',\n      'key_drivers', v_trajectory->'key_drivers',\n      'mirror_bias', v_profile->>'mirror_bias'\n    ),\n\n    'panel_2_timeline', jsonb_build_object(\n      'nodes', v_timeline,\n      'active_signals', v_signals,\n      'contradictions', v_contradictions\n    ),\n\n    'panel_3_forecast', jsonb_build_object(\n      'horizon_months', COALESCE((v_trajectory->>'prediction_horizon')::int, 12),\n      'option_a', v_forecast_a,\n      'prob_a', round(v_prob_a::numeric, 2),\n      'option_b', v_forecast_b,\n      'prob_b', round(v_prob_b::numeric, 2),\n      'confidence', round(v_confidence::numeric, 2),\n      'top_behaviors', v_behaviors,\n      'prediction_text', v_trajectory->>'prediction'\n    ),\n\n    'panel_4_signal_alignment', jsonb_build_object(\n      'model', 'resonance_friction_v1',\n      'resonance_score', round(v_resonance::numeric, 4),\n      'friction_score', round(v_friction::numeric, 4),\n      'neutral_score', round(v_neutral::numeric, 4),\n      'confidence', round(v_confidence::numeric, 2),\n      'rules', jsonb_build_object(\n        'probability', 'internal_behavior_model',\n        'confidence', 'external_signal_resonance',\n        't6_official_b', 'route_specific',\n        't6_official_a', 'route_specific',\n        'route_profile', v_route_profile\n      ),\n      'alignment_details', COALESCE(v_alignment, '[]'::jsonb)\n    )\n  );\nEND;\n$function$\n	9346a79f2462ee513a1f732bff6948ed	2026-06-05 18:49:31.590412+12
7	P5_trust_fusion_v3_rule_weight_stable_candidate	ccc.source_effective_weight_v3(text,text,text)	CREATE OR REPLACE FUNCTION ccc.source_effective_weight_v3(p_source_name text, p_domain text DEFAULT NULL::text, p_context text DEFAULT NULL::text)\n RETURNS jsonb\n LANGUAGE sql\n STABLE\nAS $function$\n  WITH calc AS (\n    SELECT\n      base,\n      rule,\n      base->>'use_as' AS use_as,\n      (base->'weights'->>'final_effective_weight')::double precision AS v2_final,\n      (rule->>'rule_weight')::double precision AS rule_weight\n    FROM\n      ccc.source_effective_weight_v2(p_source_name, p_domain, p_context, false) base,\n      ccc.source_rule_weight_v1(p_source_name, p_domain, p_context) rule\n  ),\n  fused AS (\n    SELECT\n      *,\n      CASE use_as\n        WHEN 'primary' THEN\n          ROUND((v2_final * 0.75 + rule_weight * 0.25)::numeric, 4)\n        WHEN 'reverse_indicator' THEN\n          ROUND((v2_final * 0.70 + rule_weight * 0.30)::numeric, 4)\n        WHEN 'pattern_signal' THEN\n          ROUND((v2_final * 0.55 + rule_weight * 0.45)::numeric, 4)\n        ELSE\n          ROUND((v2_final * 0.75 + rule_weight * 0.25)::numeric, 4)\n      END AS v3_final\n    FROM calc\n  )\n  SELECT\n    base ||\n    jsonb_build_object(\n      'rule_layer', rule,\n      'trust_fusion', jsonb_build_object(\n        'model', 'source_effective_weight_v3_channel_rule_fusion',\n        'primary_formula', 'v2 * 0.75 + rule * 0.25',\n        'reverse_indicator_formula', 'v2 * 0.70 + rule * 0.30',\n        'pattern_signal_formula', 'v2 * 0.55 + rule * 0.45'\n      ),\n      'weights',\n      (base->'weights') ||\n      jsonb_build_object(\n        'rule_weight', rule_weight,\n        'final_effective_weight_v3', v3_final\n      )\n    )\n  FROM fused;\n$function$\n	94993f7470888fffd6b59b336c39cf96	2026-06-06 19:00:48.72416+12
3	P6.3d_forecast_v1_1_confidence_gate_stable	ccc.forecast_confidence_gate_v1(double precision, double precision, double precision)	CREATE OR REPLACE FUNCTION ccc.forecast_confidence_gate_v1(p_resonance double precision, p_friction double precision, p_neutral double precision)\n RETURNS jsonb\n LANGUAGE plpgsql\n IMMUTABLE\nAS $function$\nDECLARE\n  v_resonance double precision := GREATEST(0.0, COALESCE(p_resonance, 0.0));\n  v_friction  double precision := GREATEST(0.0, COALESCE(p_friction, 0.0));\n  v_neutral   double precision := GREATEST(0.0, COALESCE(p_neutral, 0.0));\n\n  v_total_force double precision := 0.0;\n  v_evidence_score double precision := 0.0;\n  v_direction_balance double precision := 0.0;\n  v_confidence double precision := 0.50;\nBEGIN\n  v_total_force := v_resonance + v_friction + v_neutral;\n\n  IF v_total_force <= 0 THEN\n    v_evidence_score := 0.0;\n    v_direction_balance := 0.0;\n    v_confidence := 0.50;\n  ELSE\n    -- 证据量门控：total_force >= 1.0 视为证据量充足\n    v_evidence_score := LEAST(1.0, v_total_force / 1.0);\n\n    -- 方向平衡：\n    -- resonance 推高 A 面置信\n    -- friction 压低 A 面置信\n    -- neutral 只轻微扣分，避免中性噪音过度惩罚\n    v_direction_balance :=\n      (v_resonance - v_friction - v_neutral * 0.20) / v_total_force;\n\n    v_confidence := LEAST(0.95, GREATEST(0.30,\n      0.50 + v_direction_balance * v_evidence_score * 0.35\n    ));\n  END IF;\n\n  RETURN jsonb_build_object(\n    'confidence',        round(v_confidence::numeric, 4),\n    'total_force',       round(v_total_force::numeric, 4),\n    'evidence_score',    round(v_evidence_score::numeric, 4),\n    'direction_balance', round(v_direction_balance::numeric, 4),\n    'model',             'confidence_evidence_gate_v1',\n    'formula',           '0.50 + direction_balance * evidence_score * 0.35'\n  );\nEND;\n$function$\n	c824a6f59e488cf3b9e3aa80a1363fa6	2026-06-05 18:49:31.590412+12
8	P5_trust_topology_locked	ccc.source_rule_weight_v1(text,text,text)	CREATE OR REPLACE FUNCTION ccc.source_rule_weight_v1(p_source_name text, p_domain text DEFAULT NULL::text, p_context text DEFAULT NULL::text)\n RETURNS jsonb\n LANGUAGE plpgsql\n STABLE\nAS $function$\nDECLARE\n  v_source ccc.source_profiles%ROWTYPE;\n\n  v_control_power double precision := 0.50;\n  v_signal_cost   double precision := 0.50;\n  v_conflict_value double precision := 0.50;\n  v_rule_weight   double precision := 0.50;\nBEGIN\n  SELECT *\n  INTO v_source\n  FROM ccc.source_profiles\n  WHERE lower(source_name) = lower(p_source_name)\n  LIMIT 1;\n\n  IF NOT FOUND THEN\n    RETURN jsonb_build_object(\n      'error', 'source not found',\n      'source', p_source_name\n    );\n  END IF;\n\n  -- 1. control_power：谁能影响规则/政策/资源分配\n  v_control_power := CASE\n    WHEN v_source.source_type = 'official' THEN 0.90\n    WHEN v_source.source_type = 'think_tank' THEN 0.78\n    WHEN v_source.source_type = 'economic' THEN 0.82\n    WHEN v_source.source_type = 'leak' THEN 0.70\n    WHEN v_source.source_type = 'investigation' THEN 0.62\n    WHEN v_source.source_type = 'media' THEN 0.45\n    WHEN v_source.source_type = 'survey' THEN 0.40\n    WHEN v_source.source_type = 'nonlinear' THEN 0.35\n    ELSE 0.50\n  END;\n\n  -- 2. signal_cost：说谎/造假/行动成本\n  v_signal_cost := CASE\n    WHEN v_source.source_type = 'leak' THEN 0.92\n    WHEN v_source.source_name IN ('AIS船舶数据','卫星图像','国债收益率曲线','CPI/PCE数据','非农就业数据','M2货币供应') THEN 0.90\n    WHEN v_source.source_type = 'economic' THEN 0.86\n    WHEN v_source.source_type = 'investigation' THEN 0.78\n    WHEN v_source.source_type = 'official' THEN 0.42\n    WHEN v_source.source_type = 'media' THEN 0.50\n    WHEN v_source.source_type = 'think_tank' THEN 0.55\n    WHEN v_source.source_type = 'nonlinear' THEN 0.25\n    ELSE 0.50\n  END;\n\n  -- 3. conflict_value：冲突解释价值；事实冲突和叙事阵营冲突都算冲突\n  v_conflict_value := CASE\n    WHEN v_source.use_as = 'reverse_indicator' THEN 0.85\n    WHEN v_source.use_as = 'pattern_signal' THEN 0.65\n    WHEN v_source.use_as = 'primary' THEN 0.55\n    ELSE 0.50\n  END;\n\n  -- 4. 合成 Rule Weight\n  v_rule_weight := LEAST(1.0, GREATEST(0.0,\n    v_control_power * 0.35 +\n    v_signal_cost * 0.35 +\n    v_conflict_value * 0.30\n  ));\n\n  RETURN jsonb_build_object(\n    'source', v_source.source_name,\n    'source_type', v_source.source_type,\n    'use_as', v_source.use_as,\n    'trust_tier', v_source.trust_tier,\n    'rule_components', jsonb_build_object(\n      'control_power', round(v_control_power::numeric, 4),\n      'signal_cost', round(v_signal_cost::numeric, 4),\n      'conflict_value', round(v_conflict_value::numeric, 4)\n    ),\n    'rule_weight', round(v_rule_weight::numeric, 4),\n    'interpretation', CASE\n      WHEN v_rule_weight >= 0.75 THEN '强规则信号源'\n      WHEN v_rule_weight >= 0.55 THEN '中等规则信号源'\n      ELSE '弱规则信号源'\n    END\n  );\nEND;\n$function$\n	fc5207b7a923fd56a6567367767d8811	2026-06-06 21:46:18.548733+12
9	P5_trust_topology_locked	ccc.source_effective_weight_v3(text,text,text)	CREATE OR REPLACE FUNCTION ccc.source_effective_weight_v3(p_source_name text, p_domain text DEFAULT NULL::text, p_context text DEFAULT NULL::text)\n RETURNS jsonb\n LANGUAGE sql\n STABLE\nAS $function$\n  WITH calc AS (\n    SELECT\n      base,\n      rule,\n      base->>'use_as' AS use_as,\n      (base->'weights'->>'final_effective_weight')::double precision AS v2_final,\n      (rule->>'rule_weight')::double precision AS rule_weight\n    FROM\n      ccc.source_effective_weight_v2(p_source_name, p_domain, p_context, false) base,\n      ccc.source_rule_weight_v1(p_source_name, p_domain, p_context) rule\n  ),\n  fused AS (\n    SELECT\n      *,\n      CASE use_as\n        WHEN 'primary' THEN\n          ROUND((v2_final * 0.75 + rule_weight * 0.25)::numeric, 4)\n        WHEN 'reverse_indicator' THEN\n          ROUND((v2_final * 0.70 + rule_weight * 0.30)::numeric, 4)\n        WHEN 'pattern_signal' THEN\n          ROUND((v2_final * 0.55 + rule_weight * 0.45)::numeric, 4)\n        ELSE\n          ROUND((v2_final * 0.75 + rule_weight * 0.25)::numeric, 4)\n      END AS v3_final\n    FROM calc\n  )\n  SELECT\n    base ||\n    jsonb_build_object(\n      'rule_layer', rule,\n      'trust_fusion', jsonb_build_object(\n        'model', 'source_effective_weight_v3_channel_rule_fusion',\n        'primary_formula', 'v2 * 0.75 + rule * 0.25',\n        'reverse_indicator_formula', 'v2 * 0.70 + rule * 0.30',\n        'pattern_signal_formula', 'v2 * 0.55 + rule * 0.45'\n      ),\n      'weights',\n      (base->'weights') ||\n      jsonb_build_object(\n        'rule_weight', rule_weight,\n        'final_effective_weight_v3', v3_final\n      )\n    )\n  FROM fused;\n$function$\n	94993f7470888fffd6b59b336c39cf96	2026-06-06 21:46:18.548733+12
10	P7_decision_engine_locked	ccc.decision_engine_v1(text)	CREATE OR REPLACE FUNCTION ccc.decision_engine_v1(p_entity_name text)\n RETURNS jsonb\n LANGUAGE plpgsql\n STABLE\nAS $function$\nDECLARE\n  v_p6            jsonb;\n  v_entity_id     bigint;\n\n  v_forecast_status     text;\n  v_decision_readiness  text;\n  v_decision_mode_hint  text;\n  v_pressure            text;\n  v_trajectory_code     text;\n  v_timeline_force      float;\n  v_confidence          float;\n  v_confidence_label    text;\n  v_trust_score         float;\n  v_trust_label         text;\n  v_gate_passed         boolean;\n  v_alert               text;\n\n  v_action_status   text;\n  v_action_level    text;\n  v_action_mode     text;\n  v_risk_boundary   text;\n  v_review_trigger  text;\n\n  v_score_status    float;\n  v_score_level     float;\n  v_score_mode      float;\n  v_score_boundary  float;\n  v_score_trigger   float;\n  v_decision_score  float;\n\n  v_final_decision    text;\n  v_final_priority    text;\n  v_final_instruction text;\n  v_primary_rule      text;\n  v_gate_reason       text;\n\nBEGIN\n  v_p6 := ccc.prediction_output_standard_v1(p_entity_name);\n\n  IF COALESCE((v_p6->>'ok')::boolean, false) IS NOT TRUE THEN\n    RETURN jsonb_build_object(\n      'ok', false, 'error', 'p6 input failed',\n      'entity', p_entity_name, 'detail', v_p6->>'error'\n    );\n  END IF;\n\n  SELECT ep.entity_id INTO v_entity_id\n  FROM ccc.entity_profiles ep\n  WHERE lower(ep.entity_name) = lower(p_entity_name)\n  LIMIT 1;\n\n  v_forecast_status    := COALESCE(v_p6->>'forecast_status',    'WEAK');\n  v_decision_readiness := COALESCE(v_p6->>'decision_readiness', 'WAIT');\n  v_decision_mode_hint := COALESCE(v_p6->>'decision_mode_hint', 'HOLD');\n  v_pressure           := COALESCE(v_p6->>'pressure',           'LOW');\n  v_trajectory_code    := COALESCE(v_p6->>'trajectory_code',    'STABLE');\n  v_timeline_force     := COALESCE((v_p6->>'timeline_force')::float, 0.0);\n  v_confidence         := COALESCE((v_p6->>'confidence')::float, 0.5);\n  v_confidence_label   := COALESCE(v_p6->>'confidence_label',   'LOW');\n  v_trust_score        := COALESCE((v_p6->>'trust_score')::float, 0.0);\n  v_trust_label        := COALESCE(v_p6->>'trust_label',        'LOW');\n  v_gate_passed        := COALESCE((v_p6->>'confidence_gate_passed')::boolean, false);\n  v_alert              := v_p6->>'alert';\n\n  -- Rule 1\n  IF NOT v_gate_passed THEN\n    IF v_forecast_status = 'BLOCKED' THEN\n      v_action_status := 'NO_ACTION'; v_action_mode := 'HOLD';\n      v_risk_boundary := 'BLOCKED';\n      v_primary_rule  := 'Rule 1: Gate Blocking Rule (BLOCKED)';\n    ELSE\n      v_action_status := 'WAIT'; v_action_mode := 'HOLD';\n      v_risk_boundary := 'BLOCKED';\n      v_primary_rule  := 'Rule 1: Gate Blocking Rule (WEAK)';\n    END IF;\n\n  -- Rule 2\n  ELSIF v_forecast_status = 'VALID' AND v_decision_readiness = 'READY' THEN\n    v_action_status := 'ACTION';\n    v_primary_rule  := 'Rule 2: Ready Action Rule';\n\n    -- Rule 3\n    IF v_pressure = 'CRITICAL' AND v_trajectory_code = 'UP' THEN\n      v_action_level  := 'CRITICAL'; v_action_mode := 'ESCALATION_PREP';\n      v_risk_boundary := CASE\n        WHEN v_confidence_label = 'HIGH' AND v_trust_label = 'HIGH' THEN 'LOOSE'\n        ELSE 'NORMAL' END;\n      v_primary_rule  := 'Rule 3: Critical Escalation Rule';\n\n    -- Rule 6\n    ELSIF v_decision_mode_hint = 'HOLD' THEN\n      v_action_level  := 'HIGH'; v_action_mode := 'HOLD';\n      v_risk_boundary := 'NORMAL';\n      v_primary_rule  := 'Rule 6: No Strong Direction Rule';\n\n    ELSE\n      v_action_level  := CASE v_pressure\n        WHEN 'CRITICAL' THEN 'HIGH' WHEN 'HIGH' THEN 'HIGH'\n        WHEN 'MEDIUM'   THEN 'MEDIUM' ELSE 'LOW' END;\n      v_action_mode   := v_decision_mode_hint;\n      v_risk_boundary := CASE\n        WHEN v_confidence_label = 'HIGH' AND v_trust_label = 'HIGH' THEN 'LOOSE'\n        WHEN v_forecast_status = 'VALID' THEN 'NORMAL'\n        ELSE 'STRICT' END;\n    END IF;\n\n  -- Rule 4\n  ELSIF v_pressure IN ('HIGH','CRITICAL')\n    AND v_trajectory_code = 'STABLE'\n    AND v_decision_readiness = 'MONITOR' THEN\n    v_action_status := 'MONITOR'; v_action_level := 'MEDIUM';\n    v_action_mode   := 'DEFENSIVE'; v_risk_boundary := 'NORMAL';\n    v_primary_rule  := 'Rule 4: Stable High Pressure Rule';\n\n  -- Rule 5\n  ELSIF v_forecast_status = 'WEAK' THEN\n    v_action_status := 'WAIT'; v_action_level := 'LOW';\n    v_action_mode   := 'HOLD'; v_risk_boundary := 'STRICT';\n    v_primary_rule  := 'Rule 5: Weak Evidence Rule';\n\n  ELSE\n    v_action_status := 'MONITOR'; v_action_level := 'MEDIUM';\n    v_action_mode   := COALESCE(v_decision_mode_hint, 'HOLD');\n    v_risk_boundary := 'NORMAL';\n    v_primary_rule  := 'Default: Monitor Rule';\n  END IF;\n\n  v_review_trigger := CASE\n    WHEN v_forecast_status IN ('BLOCKED','WEAK') THEN 'MANUAL_REVIEW'\n    WHEN v_forecast_status = 'WATCH'             THEN 'SIGNAL_BASED'\n    WHEN v_trajectory_code = 'UP'                THEN 'ESCALATION_CHANGE'\n    WHEN v_trajectory_code = 'STABLE'            THEN 'TIME_BASED'\n    WHEN v_trajectory_code = 'DOWN'              THEN 'SIGNAL_BASED'\n    ELSE 'TIME_BASED'\n  END;\n\n  IF v_action_level IS NULL THEN\n    v_action_level := CASE v_action_status\n      WHEN 'NO_ACTION' THEN 'NONE'\n      WHEN 'WAIT'      THEN 'LOW'\n      WHEN 'MONITOR'   THEN 'MEDIUM'\n      ELSE 'LOW' END;\n  END IF;\n\n  -- 评分\n  v_score_status := CASE v_action_status\n    WHEN 'ACTION' THEN 1.00 WHEN 'MONITOR' THEN 0.55\n    WHEN 'WAIT'   THEN 0.30 WHEN 'NO_ACTION' THEN 0.00 ELSE 0.00 END;\n  v_score_level := CASE v_action_level\n    WHEN 'CRITICAL' THEN 1.00 WHEN 'HIGH'   THEN 0.80\n    WHEN 'MEDIUM'   THEN 0.55 WHEN 'LOW'    THEN 0.30\n    WHEN 'NONE'     THEN 0.00 ELSE 0.00 END;\n  v_score_mode := CASE v_action_mode\n    WHEN 'ESCALATION_PREP' THEN 1.00 WHEN 'OPPORTUNISTIC' THEN 0.85\n    WHEN 'DEFENSIVE'       THEN 0.65 WHEN 'HOLD'          THEN 0.45\n    WHEN 'DE_ESCALATION'   THEN 0.30 ELSE 0.45 END;\n  v_score_boundary := CASE v_risk_boundary\n    WHEN 'LOOSE'   THEN 1.00 WHEN 'NORMAL' THEN 0.75\n    WHEN 'STRICT'  THEN 0.40 WHEN 'BLOCKED' THEN 0.00 ELSE 0.00 END;\n  v_score_trigger := CASE v_review_trigger\n    WHEN 'ESCALATION_CHANGE' THEN 1.00 WHEN 'SIGNAL_BASED'   THEN 0.70\n    WHEN 'TIME_BASED'        THEN 0.50 WHEN 'CONFIDENCE_DROP' THEN 0.30\n    WHEN 'MANUAL_REVIEW'     THEN 0.20 ELSE 0.50 END;\n\n  v_decision_score := ROUND((\n    v_score_status   * 0.30 +\n    v_score_level    * 0.30 +\n    v_score_mode     * 0.20 +\n    v_score_boundary * 0.15 +\n    v_score_trigger  * 0.05\n  )::numeric, 4);\n\n  -- 分数映射\n  v_final_decision := CASE\n    WHEN v_decision_score >= 0.80 THEN 'DO'\n    WHEN v_decision_score >= 0.60 THEN 'DO_WITH_CAUTION'\n    WHEN v_decision_score >= 0.45 THEN 'MONITOR_ONLY'\n    WHEN v_decision_score >= 0.25 THEN 'WAIT'\n    ELSE 'NO_GO'\n  END;\n\n  -- ── 硬覆盖规则（含 Rule 7/8/9）─────────────────────────────────\n\n  -- Rule 9: Blocked Boundary Ceiling\n  IF v_risk_boundary = 'BLOCKED' AND v_final_decision NOT IN ('WAIT','NO_GO') THEN\n    v_final_decision := 'WAIT';\n  END IF;\n\n  -- Rule 1 硬阻断\n  IF v_forecast_status = 'BLOCKED' OR v_action_status = 'NO_ACTION' THEN\n    v_final_decision := 'NO_GO';\n  END IF;\n  IF v_action_status = 'WAIT' AND v_final_decision NOT IN ('WAIT','NO_GO') THEN\n    v_final_decision := 'WAIT';\n  END IF;\n\n  -- Rule 7: Defensive Monitor Upgrade\n  -- MONITOR + DEFENSIVE + NORMAL/LOOSE + score >= 0.60 → DO_WITH_CAUTION\n  IF v_action_status = 'MONITOR'\n    AND v_action_mode = 'DEFENSIVE'\n    AND v_risk_boundary IN ('NORMAL','LOOSE')\n    AND v_decision_score >= 0.60\n  THEN\n    v_final_decision := 'DO_WITH_CAUTION';\n\n  -- MONITOR 其他情况封顶 MONITOR_ONLY\n  ELSIF v_action_status = 'MONITOR'\n    AND v_final_decision IN ('DO','DO_WITH_CAUTION')\n    AND NOT (v_action_mode = 'DEFENSIVE' AND v_decision_score >= 0.60)\n  THEN\n    v_final_decision := 'MONITOR_ONLY';\n  END IF;\n\n  -- Rule 8: Hold Mode Ceiling\n  IF v_action_mode = 'HOLD'\n    AND v_risk_boundary != 'BLOCKED'\n    AND v_final_decision = 'DO'\n  THEN\n    v_final_decision := 'DO_WITH_CAUTION';\n  END IF;\n\n  -- final_priority\n  v_final_priority := CASE\n    WHEN v_final_decision = 'DO'     AND v_action_level = 'CRITICAL' THEN 'P0'\n    WHEN v_final_decision = 'DO'     AND v_action_level = 'HIGH'     THEN 'P1'\n    WHEN v_final_decision = 'DO_WITH_CAUTION'                        THEN 'P2'\n    WHEN v_final_decision = 'MONITOR_ONLY'                           THEN 'P2'\n    WHEN v_final_decision = 'WAIT'                                   THEN 'P3'\n    WHEN v_final_decision = 'NO_GO'                                  THEN 'P4'\n    ELSE 'P3'\n  END;\n\n  -- final_instruction\n  v_final_instruction := CASE\n    WHEN v_final_decision = 'DO' AND v_action_mode = 'ESCALATION_PREP'\n      THEN '进入升级预备，优先配置资源，准备应对高强度变化。'\n    WHEN v_final_decision = 'DO' AND v_action_mode = 'OPPORTUNISTIC'\n      THEN '机会窗口开启，可低风险捕捉，避免过度暴露。'\n    WHEN v_final_decision = 'DO' AND v_action_mode = 'HOLD'\n      THEN '行动条件具备，但方向不明确，保持准备状态，不主动升级。'\n    WHEN v_final_decision = 'DO_WITH_CAUTION' AND v_action_mode = 'DEFENSIVE'\n      THEN '高压稳定态势，可低风险防御准备，不主动升级，保持观察。'\n    WHEN v_final_decision = 'DO_WITH_CAUTION'\n      THEN '允许低风险准备，但不得主动升级，等待方向确认。'\n    WHEN v_final_decision = 'MONITOR_ONLY' AND v_action_mode = 'DEFENSIVE'\n      THEN '保持防御观察，记录变化信号，不进入主动行动。'\n    WHEN v_final_decision = 'MONITOR_ONLY'\n      THEN '持续监控，信号尚未达到行动阈值，保持观察。'\n    WHEN v_final_decision = 'WAIT'\n      THEN '证据不足，暂不行动，等待更高可信度信号。'\n    WHEN v_final_decision = 'NO_GO'\n      THEN '预测被阻断，不进入行动层。'\n    ELSE '状态未明，保持观察。'\n  END;\n\n  v_gate_reason := CASE\n    WHEN NOT v_gate_passed AND v_forecast_status = 'BLOCKED'\n      THEN 'Gate blocked: confidence and evidence both below threshold. Forecast status BLOCKED.'\n    WHEN NOT v_gate_passed\n      THEN 'Gate blocked: confidence or evidence below operational threshold.'\n    WHEN v_gate_passed AND v_forecast_status = 'VALID'\n      THEN 'Gate passed: confidence and evidence above threshold. Forecast status VALID.'\n    WHEN v_gate_passed\n      THEN 'Gate passed: threshold met. Forecast status ' || v_forecast_status || '.'\n    ELSE 'Gate state unknown.'\n  END;\n\n  RETURN jsonb_build_object(\n    'ok',             true,\n    'schema_version', 'decision_engine_output_v1',\n    'entity',         p_entity_name,\n    'entity_id',      v_entity_id,\n    'generated_at',   now(),\n\n    'p7_input_snapshot', jsonb_build_object(\n      'canonical_entity',       p_entity_name,\n      'forecast_status',        v_forecast_status,\n      'decision_readiness',     v_decision_readiness,\n      'decision_mode_hint',     v_decision_mode_hint,\n      'pressure',               v_pressure,\n      'trajectory_code',        v_trajectory_code,\n      'timeline_force',         round(v_timeline_force::numeric, 4),\n      'confidence',             round(v_confidence::numeric, 2),\n      'confidence_label',       v_confidence_label,\n      'trust_score',            round(v_trust_score::numeric, 4),\n      'trust_label',            v_trust_label,\n      'confidence_gate_passed', v_gate_passed,\n      'alert',                  v_alert,\n      'source_schema_version',  'prediction_output_standard_v1'\n    ),\n\n    'action_status',  v_action_status,\n    'action_level',   v_action_level,\n    'action_mode',    v_action_mode,\n    'risk_boundary',  v_risk_boundary,\n    'review_trigger', v_review_trigger,\n\n    'decision_score', v_decision_score,\n    'score_breakdown', jsonb_build_object(\n      'action_status_score',  v_score_status,\n      'action_level_score',   v_score_level,\n      'action_mode_score',    v_score_mode,\n      'risk_boundary_score',  v_score_boundary,\n      'review_trigger_score', v_score_trigger,\n      'weights', '{"action_status":0.30,"action_level":0.30,"action_mode":0.20,"risk_boundary":0.15,"review_trigger":0.05}'::jsonb\n    ),\n\n    'final_decision',    v_final_decision,\n    'final_priority',    v_final_priority,\n    'final_instruction', v_final_instruction,\n\n    'decision_reason', jsonb_build_object(\n      'primary_rule', v_primary_rule,\n      'gate_effect',  v_gate_reason,\n      'action_bias',  v_action_mode,\n      'reason', concat(\n        'forecast_status=', v_forecast_status,\n        ', decision_readiness=', v_decision_readiness,\n        ', pressure=', v_pressure,\n        ', trajectory=', v_trajectory_code,\n        ', gate_passed=', v_gate_passed::text,\n        ', timeline_force=', round(v_timeline_force::numeric, 4)\n      )\n    )\n  );\nEND;\n$function$\n	b2592f340bb5b196e8a263c252a8ae28	2026-06-07 10:52:58.839002+12
\.


--
-- Data for Name: person_aliases; Type: TABLE DATA; Schema: ccc; Owner: postgres
--

COPY ccc.person_aliases (id, canonical, alias, alias_type, created_at) FROM stdin;
1	习近平	xi jin ping	pinyin	2026-05-22 09:49:46.816424+12
2	习近平	xijinping	pinyin	2026-05-22 09:49:46.816424+12
3	习近平	xijingpin	pinyin	2026-05-22 09:49:46.816424+12
4	习近平	xi jinping	pinyin	2026-05-22 09:49:46.816424+12
5	习近平	xjp	abbr	2026-05-22 09:49:46.816424+12
6	习近平	xi	abbr	2026-05-22 09:49:46.816424+12
7	习近平	习主席	nickname	2026-05-22 09:49:46.816424+12
8	习近平	包子	nickname	2026-05-22 09:49:46.816424+12
9	习近平	习包子	nickname	2026-05-22 09:49:46.816424+12
10	习近平	庆丰帝	nickname	2026-05-22 09:49:46.816424+12
11	习近平	清零宗	nickname	2026-05-22 09:49:46.816424+12
12	习近平	小熊维尼	nickname	2026-05-22 09:49:46.816424+12
13	习近平	维尼	nickname	2026-05-22 09:49:46.816424+12
14	习近平	大大	nickname	2026-05-22 09:49:46.816424+12
15	习明泽	xi ming ze	pinyin	2026-05-22 09:49:46.816424+12
16	习明泽	ximingze	pinyin	2026-05-22 09:49:46.816424+12
17	习明泽	木子	nickname	2026-05-22 09:49:46.816424+12
18	习明泽	xmz	abbr	2026-05-22 09:49:46.816424+12
19	毛泽东	mao ze dong	pinyin	2026-05-22 09:49:46.816424+12
20	毛泽东	maozedong	pinyin	2026-05-22 09:49:46.816424+12
21	毛泽东	mao zedong	pinyin	2026-05-22 09:49:46.816424+12
22	毛泽东	mao	abbr	2026-05-22 09:49:46.816424+12
23	毛泽东	mzt	abbr	2026-05-22 09:49:46.816424+12
24	毛泽东	毛主席	nickname	2026-05-22 09:49:46.816424+12
25	毛泽东	毛腊肉	nickname	2026-05-22 09:49:46.816424+12
26	毛泽东	毛匪	nickname	2026-05-22 09:49:46.816424+12
27	毛泽东	毛贼东	nickname	2026-05-22 09:49:46.816424+12
28	毛泽东	老毛	nickname	2026-05-22 09:49:46.816424+12
29	邓小平	deng xiao ping	pinyin	2026-05-22 09:49:46.816424+12
30	邓小平	dengxiaoping	pinyin	2026-05-22 09:49:46.816424+12
31	邓小平	deng xiaoping	pinyin	2026-05-22 09:49:46.816424+12
32	邓小平	deng	abbr	2026-05-22 09:49:46.816424+12
33	邓小平	dxp	abbr	2026-05-22 09:49:46.816424+12
34	邓小平	小平	nickname	2026-05-22 09:49:46.816424+12
35	邓小平	矮子	nickname	2026-05-22 09:49:46.816424+12
36	江泽民	jiang ze min	pinyin	2026-05-22 09:49:46.816424+12
37	江泽民	jiangzemin	pinyin	2026-05-22 09:49:46.816424+12
38	江泽民	jiang zemin	pinyin	2026-05-22 09:49:46.816424+12
39	江泽民	jiang	abbr	2026-05-22 09:49:46.816424+12
40	江泽民	jzm	abbr	2026-05-22 09:49:46.816424+12
41	江泽民	蛤蟆	nickname	2026-05-22 09:49:46.816424+12
42	江泽民	蛤	nickname	2026-05-22 09:49:46.816424+12
43	江泽民	老蛤	nickname	2026-05-22 09:49:46.816424+12
44	江泽民	江core	nickname	2026-05-22 09:49:46.816424+12
45	胡锦涛	hu jin tao	pinyin	2026-05-22 09:49:46.816424+12
46	胡锦涛	hujintao	pinyin	2026-05-22 09:49:46.816424+12
47	胡锦涛	hu jintao	pinyin	2026-05-22 09:49:46.816424+12
48	胡锦涛	hu	abbr	2026-05-22 09:49:46.816424+12
49	胡锦涛	hjt	abbr	2026-05-22 09:49:46.816424+12
50	胡锦涛	科学发展观	nickname	2026-05-22 09:49:46.816424+12
51	李克强	li ke qiang	pinyin	2026-05-22 09:49:46.816424+12
52	李克强	likeqiang	pinyin	2026-05-22 09:49:46.816424+12
53	李克强	li keqiang	pinyin	2026-05-22 09:49:46.816424+12
54	李克强	lkq	abbr	2026-05-22 09:49:46.816424+12
55	李克强	克强	nickname	2026-05-22 09:49:46.816424+12
56	李强	li qiang	pinyin	2026-05-22 09:49:46.816424+12
57	李强	liqiang	pinyin	2026-05-22 09:49:46.816424+12
58	王毅	wang yi	pinyin	2026-05-22 09:49:46.816424+12
59	王毅	wangyi	pinyin	2026-05-22 09:49:46.816424+12
60	王毅	wy	abbr	2026-05-22 09:49:46.816424+12
61	周恩来	zhou en lai	pinyin	2026-05-22 09:49:46.816424+12
62	周恩来	zhouenlai	pinyin	2026-05-22 09:49:46.816424+12
63	周恩来	zhou enlai	pinyin	2026-05-22 09:49:46.816424+12
64	周恩来	zhou	abbr	2026-05-22 09:49:46.816424+12
65	周恩来	zel	abbr	2026-05-22 09:49:46.816424+12
66	周恩来	总理	nickname	2026-05-22 09:49:46.816424+12
67	林彪	lin biao	pinyin	2026-05-22 09:49:46.816424+12
68	林彪	linbiao	pinyin	2026-05-22 09:49:46.816424+12
69	林彪	lb	abbr	2026-05-22 09:49:46.816424+12
70	刘少奇	liu shao qi	pinyin	2026-05-22 09:49:46.816424+12
71	刘少奇	liushaoqi	pinyin	2026-05-22 09:49:46.816424+12
72	刘少奇	lsq	abbr	2026-05-22 09:49:46.816424+12
73	彭德怀	peng de huai	pinyin	2026-05-22 09:49:46.816424+12
74	彭德怀	pengdehuai	pinyin	2026-05-22 09:49:46.816424+12
75	彭德怀	pdh	abbr	2026-05-22 09:49:46.816424+12
76	薄熙来	bo xi lai	pinyin	2026-05-22 09:49:46.816424+12
77	薄熙来	boxilai	pinyin	2026-05-22 09:49:46.816424+12
78	薄熙来	bxl	abbr	2026-05-22 09:49:46.816424+12
79	周永康	zhou yong kang	pinyin	2026-05-22 09:49:46.816424+12
80	周永康	zhouyongkang	pinyin	2026-05-22 09:49:46.816424+12
81	周永康	zyk	abbr	2026-05-22 09:49:46.816424+12
82	王岐山	wang qi shan	pinyin	2026-05-22 09:49:46.816424+12
83	王岐山	wangqishan	pinyin	2026-05-22 09:49:46.816424+12
84	王岐山	wqs	abbr	2026-05-22 09:49:46.816424+12
85	蔡英文	tsai ing wen	pinyin	2026-05-22 09:49:46.816424+12
86	蔡英文	tsaiingwen	pinyin	2026-05-22 09:49:46.816424+12
87	蔡英文	cai ying wen	pinyin	2026-05-22 09:49:46.816424+12
88	蔡英文	caiyingwen	pinyin	2026-05-22 09:49:46.816424+12
89	蔡英文	tsai	abbr	2026-05-22 09:49:46.816424+12
90	蔡英文	小英	nickname	2026-05-22 09:49:46.816424+12
91	赖清德	lai ching te	pinyin	2026-05-22 09:49:46.816424+12
92	赖清德	laiqingde	pinyin	2026-05-22 09:49:46.816424+12
93	赖清德	william lai	variant	2026-05-22 09:49:46.816424+12
94	赖清德	lai	abbr	2026-05-22 09:49:46.816424+12
95	拜登	joe biden	pinyin	2026-05-22 09:49:46.816424+12
96	拜登	biden	pinyin	2026-05-22 09:49:46.816424+12
97	拜登	bai deng	pinyin	2026-05-22 09:49:46.816424+12
98	特朗普	donald trump	pinyin	2026-05-22 09:49:46.816424+12
99	特朗普	trump	pinyin	2026-05-22 09:49:46.816424+12
100	特朗普	te lang pu	pinyin	2026-05-22 09:49:46.816424+12
101	特朗普	川普	nickname	2026-05-22 09:49:46.816424+12
102	特朗普	懂王	nickname	2026-05-22 09:49:46.816424+12
103	特朗普	tlp	abbr	2026-05-22 09:49:46.816424+12
104	奥巴马	barack obama	pinyin	2026-05-22 09:49:46.816424+12
105	奥巴马	obama	pinyin	2026-05-22 09:49:46.816424+12
106	普京	vladimir putin	pinyin	2026-05-22 09:49:46.816424+12
107	普京	putin	pinyin	2026-05-22 09:49:46.816424+12
108	普京	pu jing	pinyin	2026-05-22 09:49:46.816424+12
109	泽连斯基	zelensky	pinyin	2026-05-22 09:49:46.816424+12
110	泽连斯基	zelenskyy	variant	2026-05-22 09:49:46.816424+12
111	泽连斯基	volodymyr zelensky	pinyin	2026-05-22 09:49:46.816424+12
112	金正恩	kim jong un	pinyin	2026-05-22 09:49:46.816424+12
113	金正恩	kimjongun	pinyin	2026-05-22 09:49:46.816424+12
114	金正恩	胖子	nickname	2026-05-22 09:49:46.816424+12
115	李光耀	lee kuan yew	pinyin	2026-05-22 09:49:46.816424+12
116	李光耀	leekuanyew	pinyin	2026-05-22 09:49:46.816424+12
117	李光耀	lky	abbr	2026-05-22 09:49:46.816424+12
123	胡锦涛	胡core	nickname	2026-05-22 13:06:26.753152+12
124	温家宝	wen jia bao	pinyin	2026-05-22 13:06:26.753152+12
125	温家宝	wenjiabao	pinyin	2026-05-22 13:06:26.753152+12
126	温家宝	wen jiabao	pinyin	2026-05-22 13:06:26.753152+12
127	温家宝	wjb	abbr	2026-05-22 13:06:26.753152+12
128	温家宝	影帝	nickname	2026-05-22 13:06:26.753152+12
129	温家宝	温影帝	nickname	2026-05-22 13:06:26.753152+12
130	朱镕基	zhu rong ji	pinyin	2026-05-22 13:06:26.753152+12
131	朱镕基	zhurongji	pinyin	2026-05-22 13:06:26.753152+12
132	朱镕基	zhu rongji	pinyin	2026-05-22 13:06:26.753152+12
133	朱镕基	zrj	abbr	2026-05-22 13:06:26.753152+12
134	朱镕基	rongji	pinyin	2026-05-22 13:06:26.753152+12
135	李鹏	li peng	pinyin	2026-05-22 13:06:26.753152+12
136	李鹏	lipeng	pinyin	2026-05-22 13:06:26.753152+12
137	李鹏	lp	abbr	2026-05-22 13:06:26.753152+12
138	李鹏	李屠夫	nickname	2026-05-22 13:06:26.753152+12
139	赵紫阳	zhao zi yang	pinyin	2026-05-22 13:06:26.753152+12
140	赵紫阳	zhaoziy ang	pinyin	2026-05-22 13:06:26.753152+12
141	赵紫阳	zhao ziyang	pinyin	2026-05-22 13:06:26.753152+12
142	赵紫阳	zzy	abbr	2026-05-22 13:06:26.753152+12
143	赵紫阳	ziyang	pinyin	2026-05-22 13:06:26.753152+12
144	华国锋	hua guo feng	pinyin	2026-05-22 13:06:26.753152+12
145	华国锋	huaguofeng	pinyin	2026-05-22 13:06:26.753152+12
146	华国锋	hgf	abbr	2026-05-22 13:06:26.753152+12
147	叶剑英	ye jian ying	pinyin	2026-05-22 13:06:26.753152+12
148	叶剑英	yejianying	pinyin	2026-05-22 13:06:26.753152+12
149	叶剑英	yjy	abbr	2026-05-22 13:06:26.753152+12
150	曾庆红	zeng qing hong	pinyin	2026-05-22 13:06:26.753152+12
151	曾庆红	zengqinghong	pinyin	2026-05-22 13:06:26.753152+12
152	曾庆红	zqh	abbr	2026-05-22 13:06:26.753152+12
153	李瑞环	li rui huan	pinyin	2026-05-22 13:06:26.753152+12
154	李瑞环	liruihuan	pinyin	2026-05-22 13:06:26.753152+12
155	李瑞环	lrh	abbr	2026-05-22 13:06:26.753152+12
156	乔石	qiao shi	pinyin	2026-05-22 13:06:26.753152+12
157	乔石	qiaoshi	pinyin	2026-05-22 13:06:26.753152+12
158	乔石	qs	abbr	2026-05-22 13:06:26.753152+12
159	彭真	peng zhen	pinyin	2026-05-22 13:06:26.753152+12
160	彭真	pengzhen	pinyin	2026-05-22 13:06:26.753152+12
161	彭真	pz	abbr	2026-05-22 13:06:26.753152+12
162	陈云	chen yun	pinyin	2026-05-22 13:06:26.753152+12
163	陈云	chenyun	pinyin	2026-05-22 13:06:26.753152+12
164	陈云	cy	abbr	2026-05-22 13:06:26.753152+12
165	刘伯承	liu bo cheng	pinyin	2026-05-22 13:06:26.753152+12
166	刘伯承	liubocheng	pinyin	2026-05-22 13:06:26.753152+12
167	刘伯承	lbc	abbr	2026-05-22 13:06:26.753152+12
168	朱德	zhu de	pinyin	2026-05-22 13:06:26.753152+12
169	朱德	zhude	pinyin	2026-05-22 13:06:26.753152+12
170	朱德	zd	abbr	2026-05-22 13:06:26.753152+12
171	彭德怀	彭大将军	nickname	2026-05-22 13:06:26.753152+12
172	习仲勋	xi zhong xun	pinyin	2026-05-22 13:06:26.753152+12
173	习仲勋	xizhongxun	pinyin	2026-05-22 13:06:26.753152+12
174	习仲勋	xzx	abbr	2026-05-22 13:06:26.753152+12
175	叶选宁	ye xuan ning	pinyin	2026-05-22 13:06:26.753152+12
176	叶选宁	yexuanning	pinyin	2026-05-22 13:06:26.753152+12
177	叶选宁	yxn	abbr	2026-05-22 13:06:26.753152+12
178	叶选平	ye xuan ping	pinyin	2026-05-22 13:06:26.753152+12
179	叶选平	yexuanping	pinyin	2026-05-22 13:06:26.753152+12
180	叶选平	yxp	abbr	2026-05-22 13:06:26.753152+12
181	叶静子	ye jing zi	pinyin	2026-05-22 13:06:26.753152+12
182	叶静子	yejingzi	pinyin	2026-05-22 13:06:26.753152+12
183	叶静子	yjz	abbr	2026-05-22 13:06:26.753152+12
184	谷开来	gu kai lai	pinyin	2026-05-22 13:06:26.753152+12
185	谷开来	gukailai	pinyin	2026-05-22 13:06:26.753152+12
186	谷开来	gkl	abbr	2026-05-22 13:06:26.753152+12
187	薄一波	bo yi bo	pinyin	2026-05-22 13:06:26.753152+12
188	薄一波	boyibo	pinyin	2026-05-22 13:06:26.753152+12
189	薄一波	byb	abbr	2026-05-22 13:06:26.753152+12
190	俞正声	yu zheng sheng	pinyin	2026-05-22 13:06:26.753152+12
191	俞正声	yuzhengshe ng	pinyin	2026-05-22 13:06:26.753152+12
192	俞正声	yzs	abbr	2026-05-22 13:06:26.753152+12
193	刘延东	liu yan dong	pinyin	2026-05-22 13:06:26.753152+12
194	刘延东	liuyandong	pinyin	2026-05-22 13:06:26.753152+12
195	刘延东	lyd	abbr	2026-05-22 13:06:26.753152+12
196	张德江	zhang de jiang	pinyin	2026-05-22 13:06:26.753152+12
197	张德江	zhangdejiang	pinyin	2026-05-22 13:06:26.753152+12
198	张德江	zdj	abbr	2026-05-22 13:06:26.753152+12
199	李源潮	li yuan chao	pinyin	2026-05-22 13:06:26.753152+12
200	李源潮	liyuanchao	pinyin	2026-05-22 13:06:26.753152+12
201	李源潮	lyc	abbr	2026-05-22 13:06:26.753152+12
202	周永康	周老虎	nickname	2026-05-22 13:06:26.753152+12
203	周永康	老虎	nickname	2026-05-22 13:06:26.753152+12
204	薄熙来	薄大公子	nickname	2026-05-22 13:06:26.753152+12
205	王岐山	灭火队长	nickname	2026-05-22 13:06:26.753152+12
206	刘鹤	liu he	pinyin	2026-05-22 13:06:26.753152+12
207	刘鹤	liuhe	pinyin	2026-05-22 13:06:26.753152+12
208	刘鹤	lh	abbr	2026-05-22 13:06:26.753152+12
209	栗战书	li zhan shu	pinyin	2026-05-22 13:06:26.753152+12
210	栗战书	lizhanshu	pinyin	2026-05-22 13:06:26.753152+12
211	栗战书	lzs	abbr	2026-05-22 13:06:26.753152+12
212	汪洋	wang yang	pinyin	2026-05-22 13:06:26.753152+12
213	汪洋	wangyang	pinyin	2026-05-22 13:06:26.753152+12
214	汪洋	wy	abbr	2026-05-22 13:06:26.753152+12
215	韩正	han zheng	pinyin	2026-05-22 13:06:26.753152+12
216	韩正	hanzheng	pinyin	2026-05-22 13:06:26.753152+12
217	韩正	hz	abbr	2026-05-22 13:06:26.753152+12
218	赵乐际	zhao le ji	pinyin	2026-05-22 13:06:26.753152+12
219	赵乐际	zhaoleji	pinyin	2026-05-22 13:06:26.753152+12
220	赵乐际	zlj	abbr	2026-05-22 13:06:26.753152+12
221	丁薛祥	ding xue xiang	pinyin	2026-05-22 13:06:26.753152+12
222	丁薛祥	dingxuexiang	pinyin	2026-05-22 13:06:26.753152+12
223	丁薛祥	dxx	abbr	2026-05-22 13:06:26.753152+12
224	李希	li xi	pinyin	2026-05-22 13:06:26.753152+12
225	李希	lixi	pinyin	2026-05-22 13:06:26.753152+12
226	蔡奇	cai qi	pinyin	2026-05-22 13:06:26.753152+12
227	蔡奇	caiqi	pinyin	2026-05-22 13:06:26.753152+12
228	蔡奇	cq	abbr	2026-05-22 13:06:26.753152+12
229	陈全国	chen quan guo	pinyin	2026-05-22 13:06:26.753152+12
230	陈全国	chenquanguo	pinyin	2026-05-22 13:06:26.753152+12
231	陈全国	cqg	abbr	2026-05-22 13:06:26.753152+12
232	邓朴方	deng pu fang	pinyin	2026-05-22 13:06:26.753152+12
233	邓朴方	dengpufang	pinyin	2026-05-22 13:06:26.753152+12
234	邓朴方	dpf	abbr	2026-05-22 13:06:26.753152+12
235	朱云来	zhu yun lai	pinyin	2026-05-22 13:06:26.753152+12
236	朱云来	zhuyunlai	pinyin	2026-05-22 13:06:26.753152+12
237	朱燕来	zhu yan lai	pinyin	2026-05-22 13:06:26.753152+12
238	朱燕来	zhuyanlai	pinyin	2026-05-22 13:06:26.753152+12
239	李克强	地摊经济	nickname	2026-05-22 13:06:26.753152+12
240	李克强	6亿人月收入1000	nickname	2026-05-22 13:06:26.753152+12
241	胡海峰	hu hai feng	pinyin	2026-05-22 13:06:26.753152+12
242	胡海峰	huhaifeng	pinyin	2026-05-22 13:06:26.753152+12
243	温云松	wen yun song	pinyin	2026-05-22 13:06:26.753152+12
244	温云松	wenyunsong	pinyin	2026-05-22 13:06:26.753152+12
245	温云松	陈杭	variant	2026-05-22 13:06:26.753152+12
246	温云松	郑建源	variant	2026-05-22 13:06:26.753152+12
247	江绵恒	jiang mian heng	pinyin	2026-05-22 13:06:26.753152+12
248	江绵恒	jiangmianheng	pinyin	2026-05-22 13:06:26.753152+12
249	毛新宇	mao xin yu	pinyin	2026-05-22 13:06:26.753152+12
250	毛新宇	maoxinyu	pinyin	2026-05-22 13:06:26.753152+12
251	毛新宇	毛泽东孙子	nickname	2026-05-22 13:06:26.753152+12
252	刘源	liu yuan	pinyin	2026-05-22 13:06:26.753152+12
253	刘源	liuyuan	pinyin	2026-05-22 13:06:26.753152+12
254	刘源	刘少奇之子	nickname	2026-05-22 13:06:26.753152+12
255	陈毅	chen yi	pinyin	2026-05-22 13:06:26.753152+12
256	陈毅	chenyi	pinyin	2026-05-22 13:06:26.753152+12
257	贺龙	he long	pinyin	2026-05-22 13:06:26.753152+12
258	贺龙	helong	pinyin	2026-05-22 13:06:26.753152+12
259	聂荣臻	nie rong zhen	pinyin	2026-05-22 13:06:26.753152+12
260	聂荣臻	nierongzhen	pinyin	2026-05-22 13:06:26.753152+12
261	聂荣臻	nrz	abbr	2026-05-22 13:06:26.753152+12
262	叶挺	ye ting	pinyin	2026-05-22 13:06:26.753152+12
263	叶挺	yeting	pinyin	2026-05-22 13:06:26.753152+12
264	粟裕	su yu	pinyin	2026-05-22 13:06:26.753152+12
265	粟裕	suyu	pinyin	2026-05-22 13:06:26.753152+12
266	罗荣桓	luo rong huan	pinyin	2026-05-22 13:06:26.753152+12
267	罗荣桓	luoronghuan	pinyin	2026-05-22 13:06:26.753152+12
268	陈赓	chen geng	pinyin	2026-05-22 13:06:26.753152+12
269	陈赓	chengeng	pinyin	2026-05-22 13:06:26.753152+12
270	张爱萍	zhang ai ping	pinyin	2026-05-22 13:06:26.753152+12
271	张爱萍	zhangaiping	pinyin	2026-05-22 13:06:26.753152+12
272	王震	wang zhen	pinyin	2026-05-22 13:06:26.753152+12
273	王震	wangzhen	pinyin	2026-05-22 13:06:26.753152+12
274	廖承志	liao cheng zhi	pinyin	2026-05-22 13:06:26.753152+12
275	廖承志	liaochengzhi	pinyin	2026-05-22 13:06:26.753152+12
276	李先念	li xian nian	pinyin	2026-05-22 13:06:26.753152+12
277	李先念	lixiannian	pinyin	2026-05-22 13:06:26.753152+12
278	李先念	lxn	abbr	2026-05-22 13:06:26.753152+12
279	邓颖超	deng ying chao	pinyin	2026-05-22 13:06:26.753152+12
280	邓颖超	dengyingchao	pinyin	2026-05-22 13:06:26.753152+12
281	邓颖超	dyc	abbr	2026-05-22 13:06:26.753152+12
282	万里	wan li	pinyin	2026-05-22 13:06:26.753152+12
283	万里	wanli	pinyin	2026-05-22 13:06:26.753152+12
284	胡耀邦	hu yao bang	pinyin	2026-05-22 13:06:26.753152+12
285	胡耀邦	huyaobang	pinyin	2026-05-22 13:06:26.753152+12
286	胡耀邦	hyb	abbr	2026-05-22 13:06:26.753152+12
287	胡耀邦	胡赵	nickname	2026-05-22 13:06:26.753152+12
288	方励之	fang li zhi	pinyin	2026-05-22 13:06:26.753152+12
289	方励之	fanglizhi	pinyin	2026-05-22 13:06:26.753152+12
290	魏京生	wei jing sheng	pinyin	2026-05-22 13:06:26.753152+12
291	魏京生	weijingsheng	pinyin	2026-05-22 13:06:26.753152+12
292	刘晓波	liu xiao bo	pinyin	2026-05-22 13:06:26.753152+12
293	刘晓波	liuxiaobo	pinyin	2026-05-22 13:06:26.753152+12
294	刘晓波	lxb	abbr	2026-05-22 13:06:26.753152+12
295	艾未未	ai wei wei	pinyin	2026-05-22 13:06:26.753152+12
296	艾未未	aiweiwei	pinyin	2026-05-22 13:06:26.753152+12
297	艾未未	aww	abbr	2026-05-22 13:06:26.753152+12
298	陈光诚	chen guang cheng	pinyin	2026-05-22 13:06:26.753152+12
299	陈光诚	chenguangcheng	pinyin	2026-05-22 13:06:26.753152+12
300	陈光诚	cgc	abbr	2026-05-22 13:06:26.753152+12
301	高智晟	gao zhi sheng	pinyin	2026-05-22 13:06:26.753152+12
302	高智晟	gaozhisheng	pinyin	2026-05-22 13:06:26.753152+12
303	高智晟	gzs	abbr	2026-05-22 13:06:26.753152+12
317	Steve Bannon	班农	auto	2026-05-25 19:59:58.661492+12
318	ISIS	ISIS-k	auto	2026-05-25 19:59:58.661492+12
334	特朗普	Donald John Trump	manual	2026-06-05 14:43:32.561281+12
335	特朗普	Donald Trump	manual	2026-06-05 14:43:32.561281+12
336	特朗普	Trump	manual	2026-06-05 14:43:32.561281+12
337	特朗普	Donald J. Trump	manual	2026-06-05 14:43:32.561281+12
338	特朗普	DJT	manual	2026-06-05 14:43:32.561281+12
340	习近平	Xi Jinping	manual	2026-06-05 14:43:32.561281+12
341	习近平	Xi	manual	2026-06-05 14:43:32.561281+12
342	习近平	XJP	manual	2026-06-05 14:43:32.561281+12
343	习近平	習近平	manual	2026-06-05 14:43:32.561281+12
344	美联储	Federal Reserve	manual	2026-06-05 14:43:32.561281+12
345	美联储	Fed	manual	2026-06-05 14:43:32.561281+12
346	美联储	FOMC	manual	2026-06-05 14:43:32.561281+12
347	美联储	Federal Open Market Committee	manual	2026-06-05 14:43:32.561281+12
348	美联储	聯準會	manual	2026-06-05 14:43:32.561281+12
349	WEF	World Economic Forum	manual	2026-06-05 14:43:32.561281+12
350	WEF	Davos	manual	2026-06-05 14:43:32.561281+12
351	WEF	达沃斯	manual	2026-06-05 14:43:32.561281+12
352	WEF	世界经济论坛	manual	2026-06-05 14:43:32.561281+12
353	WEF	世界經濟論壇	manual	2026-06-05 14:43:32.561281+12
354	中共	CCP	manual	2026-06-05 14:43:32.561281+12
355	中共	CPC	manual	2026-06-05 14:43:32.561281+12
356	中共	Chinese Communist Party	manual	2026-06-05 14:43:32.561281+12
357	中共	中国共产党	manual	2026-06-05 14:43:32.561281+12
358	中共	中國共產黨	manual	2026-06-05 14:43:32.561281+12
359	中共	中共	canonical	2026-06-05 21:26:12.461635+12
360	中共	中国	state_alias	2026-06-05 21:26:12.461635+12
361	中共	中国政府	state_org_alias	2026-06-05 21:26:12.461635+12
363	中共	中华人民共和国	state_alias	2026-06-05 21:26:12.461635+12
364	中共	中华人民共和国政府	state_org_alias	2026-06-05 21:26:12.461635+12
365	中共	国务院	state_org_alias	2026-06-05 21:26:12.461635+12
366	中共	中共中央	party_org_alias	2026-06-05 21:26:12.461635+12
367	中共	中國	traditional_state_alias	2026-06-05 21:26:12.461635+12
368	中共	中國政府	traditional_state_org_alias	2026-06-05 21:26:12.461635+12
370	中共	中華人民共和國	traditional_state_alias	2026-06-05 21:26:12.461635+12
371	中共	中華人民共和國政府	traditional_state_org_alias	2026-06-05 21:26:12.461635+12
372	中共	國務院	traditional_state_org_alias	2026-06-05 21:26:12.461635+12
373	中共	China	english_state_alias	2026-06-05 21:26:12.461635+12
374	中共	PRC	english_state_alias	2026-06-05 21:26:12.461635+12
375	中共	P.R.C.	english_state_alias	2026-06-05 21:26:12.461635+12
376	中共	People's Republic of China	english_state_alias	2026-06-05 21:26:12.461635+12
377	中共	PRC Government	english_state_org_alias	2026-06-05 21:26:12.461635+12
378	中共	Chinese government	english_state_org_alias	2026-06-05 21:26:12.461635+12
379	中共	Government of China	english_state_org_alias	2026-06-05 21:26:12.461635+12
380	中共	State Council	english_state_org_alias	2026-06-05 21:26:12.461635+12
381	中共	PRC State Council	english_state_org_alias	2026-06-05 21:26:12.461635+12
382	中共	Beijing	metonymy_state_org_alias	2026-06-05 21:26:12.461635+12
386	中共	Communist Party of China	english_party_alias	2026-06-05 21:26:12.461635+12
387	中共	Chinese Communist Party of China	english_party_alias	2026-06-05 21:26:12.461635+12
388	中共	CCP Central Committee	english_party_org_alias	2026-06-05 21:26:12.461635+12
389	中共	Central Committee of the CCP	english_party_org_alias	2026-06-05 21:26:12.461635+12
390	中共	zhonggong	pinyin_party_alias	2026-06-05 21:26:12.461635+12
391	中共	zhong gong	pinyin_party_alias	2026-06-05 21:26:12.461635+12
392	中共	zhongguo	pinyin_state_alias	2026-06-05 21:26:12.461635+12
393	中共	zhong guo	pinyin_state_alias	2026-06-05 21:26:12.461635+12
394	中共	zhongguo zhengfu	pinyin_state_org_alias	2026-06-05 21:26:12.461635+12
395	中共	zhong guo zheng fu	pinyin_state_org_alias	2026-06-05 21:26:12.461635+12
396	中共	zhongguogongchandang	pinyin_party_alias	2026-06-05 21:26:12.461635+12
397	中共	zhong guo gong chan dang	pinyin_party_alias	2026-06-05 21:26:12.461635+12
398	中共	zhonghua renmin gongheguo	pinyin_state_alias	2026-06-05 21:26:12.461635+12
401	中共	中国共產党	mixed_party_alias	2026-06-05 21:33:25.97869+12
402	中共	中國共产党	mixed_party_alias	2026-06-05 21:33:25.97869+12
414	习近平	习近平	canonical	2026-06-05 22:17:09.923769+12
425	习近平	習主席	traditional_title_alias	2026-06-05 22:17:09.923769+12
426	习近平	总书记	title_alias	2026-06-05 22:17:09.923769+12
427	习近平	總書記	traditional_title_alias	2026-06-05 22:17:09.923769+12
428	习近平	习近平思想	ideology_alias	2026-06-05 22:17:09.923769+12
429	习近平	習近平思想	traditional_ideology_alias	2026-06-05 22:17:09.923769+12
432	习近平	習包子	traditional_nickname	2026-06-05 22:17:09.923769+12
434	习近平	慶豐帝	traditional_nickname	2026-06-05 22:17:09.923769+12
437	习近平	維尼	traditional_nickname	2026-06-05 22:17:09.923769+12
439	习近平	小熊維尼	traditional_nickname	2026-06-05 22:17:09.923769+12
441	特朗普	特朗普	canonical	2026-06-05 22:17:09.923769+12
444	特朗普	川建国	nickname	2026-06-05 22:17:09.923769+12
445	特朗普	川建國	traditional_nickname	2026-06-05 22:17:09.923769+12
446	特朗普	唐纳德特朗普	chinese_full	2026-06-05 22:17:09.923769+12
447	特朗普	唐納德特朗普	traditional_full	2026-06-05 22:17:09.923769+12
448	特朗普	唐纳德·特朗普	chinese_full	2026-06-05 22:17:09.923769+12
449	特朗普	唐納德·川普	traditional_full	2026-06-05 22:17:09.923769+12
458	特朗普	telangpu	pinyin	2026-06-05 22:17:09.923769+12
459	特朗普	chuan pu	pinyin	2026-06-05 22:17:09.923769+12
460	特朗普	chuanpu	pinyin	2026-06-05 22:17:09.923769+12
461	WEF	WEF	canonical	2026-06-05 22:17:09.923769+12
464	WEF	Davos Forum	english	2026-06-05 22:17:09.923769+12
465	WEF	World Economic Forum Annual Meeting	english	2026-06-05 22:17:09.923769+12
469	WEF	達沃斯	traditional_metonymy	2026-06-05 22:17:09.923769+12
470	WEF	达沃斯论坛	simplified	2026-06-05 22:17:09.923769+12
471	WEF	達沃斯論壇	traditional	2026-06-05 22:17:09.923769+12
472	WEF	夏季达沃斯	simplified	2026-06-05 22:17:09.923769+12
473	WEF	夏季達沃斯	traditional	2026-06-05 22:17:09.923769+12
483	比尔盖茨	比尔盖茨	canonical	2026-06-05 22:25:34.807658+12
484	比尔盖茨	比爾蓋茲	traditional	2026-06-05 22:25:34.807658+12
485	比尔盖茨	比尔·盖茨	simplified	2026-06-05 22:25:34.807658+12
486	比尔盖茨	比爾·蓋茲	traditional	2026-06-05 22:25:34.807658+12
487	比尔盖茨	Bill Gates	english	2026-06-05 22:25:34.807658+12
488	比尔盖茨	William Henry Gates III	english_full	2026-06-05 22:25:34.807658+12
489	比尔盖茨	Gates	english_short	2026-06-05 22:25:34.807658+12
490	比尔盖茨	bier gaici	pinyin	2026-06-05 22:25:34.807658+12
491	比尔盖茨	bi er gai ci	pinyin	2026-06-05 22:25:34.807658+12
492	Klaus Schwab	Klaus Schwab	english	2026-06-06 09:14:10.812552+12
493	Klaus Schwab	克劳斯·施瓦布	simplified	2026-06-06 09:14:10.812552+12
494	Klaus Schwab	克勞斯·施瓦布	traditional	2026-06-06 09:14:10.812552+12
495	Klaus Schwab	施瓦布	nickname	2026-06-06 09:14:10.812552+12
496	盖茨基金会	Bill & Melinda Gates Foundation	english	2026-06-06 09:14:10.812552+12
497	盖茨基金会	Gates Foundation	english_short	2026-06-06 09:14:10.812552+12
498	盖茨基金会	比尔及梅琳达·盖茨基金会	simplified	2026-06-06 09:14:10.812552+12
499	盖茨基金会	比爾及梅琳達·蓋茲基金會	traditional	2026-06-06 09:14:10.812552+12
500	林小旭	Lin Xiaoxu	english	2026-06-06 10:02:31.964818+12
501	ICTV	International Committee on Taxonomy of Viruses	english	2026-06-06 10:02:31.964818+12
502	CEPI	Coalition for Epidemic Preparedness Innovations	english	2026-06-06 10:02:31.964818+12
503	CEPI	流行病防范创新联盟	simplified	2026-06-06 10:02:31.964818+12
504	GAVI	Gavi, the Vaccine Alliance	english	2026-06-06 10:02:31.964818+12
505	GAVI	全球疫苗免疫联盟	simplified	2026-06-06 10:02:31.964818+12
506	WHO	World Health Organization	english	2026-06-06 10:02:31.964818+12
507	WHO	世界卫生组织	simplified	2026-06-06 10:02:31.964818+12
508	约翰斯·霍普金斯卫生安全中心	Johns Hopkins Center for Health Security	english	2026-06-06 10:02:31.964818+12
509	混合X疾病	Disease X	english	2026-06-06 10:02:31.964818+12
\.


--
-- Data for Name: person_noise_library; Type: TABLE DATA; Schema: ccc; Owner: postgres
--

COPY ccc.person_noise_library (word) FROM stdin;
unknown
null
none
n/a
name
person
people
user
admin
staff
official
source
spokesman
spokesperson
reporter
correspondent
editor
author
the
a
an
this
that
he
she
they
it
we
mr
ms
dr
sir
chairman
director
minister
president
secretary
general
colonel
officer
monday
tuesday
wednesday
thursday
friday
saturday
sunday
january
february
march
april
may
june
july
august
september
october
november
december
china
usa
rfa
ai
control
day
beijing
hong
kong
taiwan
tibet
xinjiang
macau
中国
美国
香港
台湾
北京
上海
政府
当局
警方
法院
组织
机构
委员会
部门
办公室
发言人
消息人士
观察人士
分析人士
知情人士
相关人士
记者
编辑
作者
来源
报告
声明
文件
协议
决议
法案
事件
情况
问题
措施
行动
活动
会议
峰会
论坛
访问
制裁
封锁
镇压
逮捕
起诉
of
in
at
on
to
and
or
for
with
from
said
says
told
according
report
government
police
court
party
committee
ministry
bureau
office
statement
document
agreement
resolution
现在是极权
实德
文中也提到
混混
参考线路
以前
dì
←前の職場
←对日本人yotaro
←済南事件で中国革命軍に殺害された日本人男性東条弥太郎の検死の様子
→ソ連がやっていた人体実験
→ソ連の人体実験の説明
→苏联人体实验说明
→苏联进行的人体实验
=帝王蟹
=死亡陷阱
｜中国人的祖父借来的时间
｜中诚信乱评
｜最苦逼的部门
～法国里昂
∵大西洋月刊
⊲合伙人
⊲头破血流
⊲小白
⊲盲目跟风伸手党炮灰
▍社会信任日益崩塌
▍程序真空带来恐惧
▍纪检权力不受司法制约
▶paypal-“黑于黨”成員彼得蒂爾也曾計劃在組西蘭瓦納卡湖區，openai
▶捷克的奧皮杜姆坐落在波西米亞地區的一個山脉之中
▶澳大利亚中部松间溪军事基地
▶美国专利与商标办公室/美国专利商标局（英语：united
▶美国新墨西哥州外星人研究杜尔塞基地
●不亂服用成份不明、來源有問題的健康食品
●任何營養品都不能過量
●定時健康檢查、聽從醫囑與建議
●要買天然產品，最好從食物取得。化學成份若長期囤積體內反而有害，而形成疾病
万一
万人
万亿
\.


--
-- Data for Name: raw_documents; Type: TABLE DATA; Schema: ccc; Owner: postgres
--

COPY ccc.raw_documents (id, raw_content, source, created_at) FROM stdin;
2	1997中共元老排位，薄一波家族及张红文案相关网络	xmind	2026-05-25 12:25:06.420091+12
3	1997中共元老排位，薄一波家族及张红文案相关网络	xmind	2026-05-25 12:34:14.363306+12
4	1997中共元老排位，薄一波家族及张红文案相关网络	xmind	2026-05-25 13:41:39.499046+12
5	1997中共元老排位，薄一波家族及张红文案相关网络	xmind	2026-05-25 13:43:36.115109+12
6	1997中共元老排位，薄一波家族及张红文案相关网络	xmind	2026-05-25 14:03:23.524269+12
7	全球事件时间线Excel 2019-2026，横轴时间纵轴事件流	excel_timeline	2026-05-25 19:59:58.661492+12
9	全球事件时间线Excel 2019-2026，横轴时间纵轴事件流	excel_timeline	2026-05-26 08:33:36.517433+12
\.


--
-- Data for Name: revision_log; Type: TABLE DATA; Schema: ccc; Owner: postgres
--

COPY ccc.revision_log (id, node_id, field_changed, old_value, new_value, reason, revised_by, created_at) FROM stdin;
\.


--
-- Data for Name: rsal_checkpoints; Type: TABLE DATA; Schema: ccc; Owner: postgres
--

COPY ccc.rsal_checkpoints (id, checkpoint_label, module, note, created_at) FROM stdin;
2	SRV3_entity_resolve_v3_local_stable	Search Router v3 Local	Stable checkpoint: multilingual entity resolution. RSAL rule: China/PRC/Chinese government/Beijing/State Council route to canonical 中共. Xi/Trump/Fed/WEF aliases verified. Bill Gates remains separate PERSON and links to WEF through graph edge. Regression PASS=53.	2026-06-05 22:33:58.88775+12
3	P5_trust_fusion_v3_rule_weight_stable_candidate	Layer 5 Trust / Source Effective Weight	Stable candidate: source_effective_weight_v3 adds rule_weight fusion without schema change. Channel matrix: primary 75/25, reverse_indicator 70/30, pattern_signal 55/45. Pattern sources are suppressed below media/investigation layer while official/think-tank reverse indicators retain rule value.	2026-06-06 18:44:39.385381+12
1	P6.3d_forecast_v1_1_confidence_gate_stable	Layer 6 Prediction / Forecast Engine	Renamed from old P7.3d. Stable checkpoint: entity audit + route-specific semantics + confidence evidence gate. No rigidity multiplier yet. P6 = Prediction Output; P7 is reserved for Decision Engine.	2026-06-05 18:49:31.590412+12
4	P5_trust_topology_locked	Layer 5 Rule / Trust Topology	P5 LOCKED. Trust topology finalized. source_rule_weight_v1 and source_effective_weight_v3 regression passed: 16 PASS / 0 FAIL. Channel matrix fixed: primary 75/25, reverse_indicator 70/30, pattern_signal 55/45. Contradiction routing integrated. No further modifications allowed without opening P5.1 revision.	2026-06-06 21:46:02.601179+12
8	P6.5_search_panel_integration_stable	Layer 6 Prediction / Search Panel Integration	search_router_v3_local_forecast_trust_v3 updated to include prediction_panel_v1 output. final_result now carries pressure_label / alert_level / trajectory / summary from four-card panel. All 6 entities PASS. Search → Forecast → Panel full pipeline connected. P6.5 LOCKED.	2026-06-06 22:43:05.503458+12
7	P6.5_prediction_panel_v1_stable	P6	prediction_panel_v1 created. Four-card output structure: card_1_pressure / card_2_timeline / card_3_contradiction / card_4_forecast. All 6 entities PASS. Data sources: entity_profiles + behavioral_models + event_nodes + causal_edges + contradiction_engine + forecast_v1_1_trust_v3. Forecast JSON → Prediction Panel conversion complete.	2026-06-06 22:41:52.201581+12
5	P6.4_trust_v3_migration_stable	Layer 6 Prediction / Trust V3 Migration	forecast_v1_1_trust_v3 created. Trust weight upgraded: source_effective_weight.reverse_indicator_weight → source_effective_weight_v3.final_effective_weight_v3. Regression PASS=6/FAIL=0. All route_profile / decision / option_a / option_b / confidence unchanged. Resonance micro-drift on 习近平 (-0.014) and 普京 (-0.006) confirmed as expected Trust Fusion rule correction, not error.	2026-06-06 22:22:36.628851+12
6	P6.4_search_forecast_trust_v3_stable	Layer 6 Prediction / Search Forecast Trust V3 Bridge	search_router_v3_local_forecast_trust_v3 created and verified. Search → forecast_v1_1_trust_v3 pipeline fully connected. All 6 entities PASS: status=FORECAST_ATTACHED, trust_model=source_effective_weight_v3. route_profile / decision / option_a / confidence consistent with pre-migration baseline. P6.4 Trust V3 Migration LOCKED.	2026-06-06 22:28:04.560933+12
10	P6.6_timeline_force_injection_stable	Layer 6 Prediction / Timeline Force Injection	forecast_v1_2_timeline created. timeline_force injected into resonance/friction/neutral via causal_edges + event_nodes. Proxy table timeline_proxy_map active: 普京→俄罗斯, 习近平→中共. Regression PASS=6/FAIL=0. All decisions unchanged. Notable: 特朗普 confidence 0.50→0.65 via timeline compensation (contradiction_engine empty). Layer4→Layer6 pipeline first full closure.	2026-06-06 23:34:53.448635+12
12	P6.7_prediction_output_standard_v1_locked	Layer 6 Prediction / Output Standard	prediction_output_standard_v1 function created. Four-card schema frozen: card1_forecast_summary / card2_confidence_gate / card3_timeline_force / card4_decision_input. P7 interface contract locked: confidence_gate_passed=false blocks READY state. All 6 entities PASS. Enumeration values fixed. Schema version locked as prediction_output_standard_v1. P6.7 LOCKED.	2026-06-07 07:43:36.046559+12
13	P6_forecast_system_locked	Layer 6 Prediction	P6 Forecast System fully locked. Chain: forecast_v1_1_core → forecast_v1_1_trust_v3 → forecast_v1_2_timeline → prediction_panel_v1 → prediction_output_standard_v1. Trust V3 integrated. Timeline Force injected. Four-card panel standardized. P7 input interface frozen. All regression PASS=6/FAIL=0. P6 LOCKED → P7 Decision Engine next.	2026-06-07 07:43:48.815702+12
14	P7_decision_engine_locked	Layer 7 Decision Engine	P7 Decision Engine fully locked. Function: decision_engine_v1. Schema: decision_engine_output_v1. Rules 1–9 implemented. Hard overrides: Rule 7 Defensive Monitor Upgrade, Rule 8 Hold Mode Ceiling, Rule 9 Blocked Boundary Ceiling. Regression PASS=6/FAIL=0: 习近平 DO/P0, 普京 DO_WITH_CAUTION/P2, 特朗普 WAIT/P3, 中共 DO/P0, 美联储 DO_WITH_CAUTION/P2, WEF NO_GO/P4. P7.5 output schema frozen as decision_engine_output_v1. No downstream P8. Seven-layer system boundary closed.	2026-06-07 10:52:58.839002+12
15	SQLV1_locked	System / Architecture	SQLV1 was rebuilt locally during development. Local data may be less complete than cloud-side historical data. Some intermediate schema/function changes may contain legacy residue. However, the P1–P7 logic chain is complete and operational. The full pipeline is closed: raw input → entity graph → essence → behavioral model → timeline → trust topology → prediction output → decision engine. Final output compresses to DO / DO_WITH_CAUTION / WAIT / NO_GO. SQLV1 is accepted as a functional closed-loop prototype, not a clean-room final architecture. Future optimization should be handled as SQLV2 clean architecture, not by endlessly patching SQLV1.	2026-06-07 11:14:05.411461+12
\.


--
-- Data for Name: signals; Type: TABLE DATA; Schema: ccc; Owner: postgres
--

COPY ccc.signals (id, node_id, entity_id, signal_type, signal_text, strength, triggered_at, expires_at, is_active, created_at, entity_profile_id, trigger_condition, pressure_delta, linked_prediction, source_label) FROM stdin;
1	\N	16	critical_pressure	习近平：centralization_accelerating，压力=0.82，趋势=rising	0.82	2026-05-28 06:59:38.422723+12	\N	t	2026-05-28 06:59:38.422723+12	1	经济下行压力 + 派系清洗加速 + 地方债危机	0.1	进一步收缩民间资本空间，对台压力持续上升	entity_trajectories
2	\N	60	elevated_pressure	普京：imperial_restoration_locked，压力=0.78，趋势=stable	0.78	2026-05-28 06:59:38.422723+12	\N	t	2026-05-28 06:59:38.422723+12	2	乌克兰战争消耗 + 西方制裁累积 + 精英阶层不满	0	乌克兰战争持续消耗，内部压力上升但政权稳定	entity_trajectories
3	\N	17	elevated_pressure	特朗普：transactional_unpredictability，压力=0.71，趋势=rising	0.71	2026-05-28 06:59:38.422723+12	\N	t	2026-05-28 06:59:38.422723+12	3	关税战重启 + NATO压力 + 美元政策不确定	0.1	第二任期政策大幅摆动，盟友体系重新谈判	entity_trajectories
4	\N	34	critical_pressure	中共：stability_at_all_costs，压力=0.85，趋势=rising	0.85	2026-05-28 06:59:38.422723+12	\N	t	2026-05-28 06:59:38.422723+12	4	青年失业率高企 + 地方债危机 + 房地产持续下行	0.1	经济下行压力加剧，维稳成本上升，叙事管控强化	entity_trajectories
5	\N	35	elevated_pressure	美联储：liquidity_stress，压力=0.68，趋势=stable	0.68	2026-05-28 06:59:38.422723+12	\N	t	2026-05-28 06:59:38.422723+12	5	通胀粘性 + 就业市场降温 + 美债可持续性	0	降息周期开启但经济软着陆不确定，美元体系压力持续	entity_trajectories
6	\N	59	normal_pressure	WEF：agenda_consolidation，压力=0.55，趋势=stable	0.55	2026-05-28 06:59:38.422723+12	\N	t	2026-05-28 06:59:38.422723+12	6	民粹主义反弹 + AI治理议题上升 + 去全球化趋势	0	全球治理议程推进受民粹主义阻力，技术官僚路线调整	entity_trajectories
7	\N	59	narrative_gap	WEF 官方叙事与现实偏差：WEF是开放包容的全球治理论坛，服务全人类利益... gap=0.6	0.6	2026-05-28 06:59:38.422723+12	\N	t	2026-05-28 06:59:38.422723+12	\N	参与门槛极高 | 议程由少数精英设定 | 利益相关者资本主义绕过民主程序	-0.12	\N	WEF官网,年度报告
8	\N	16	narrative_collapse	习近平 官方叙事与现实偏差：中国经济稳定复苏，改革开放持续深化... gap=0.82	0.82	2026-05-28 06:59:38.422723+12	\N	t	2026-05-28 06:59:38.422723+12	\N	青年失业率历史高位 | 房地产持续下行 | 地方债危机扩散 | 外资撤离加速	-0.25	\N	官方GDP数据,人民日报,新华社
9	\N	16	narrative_divergence	习近平 官方叙事与现实偏差：台湾问题可以和平解决，北京无意动武... gap=0.75	0.75	2026-05-28 06:59:38.422723+12	\N	t	2026-05-28 06:59:38.422723+12	\N	军事演习频率上升 | 对台军购阻挠 | 解放军现代化加速 | 统一时间表叙事强化	-0.2	\N	官方声明,外交辞令
10	\N	34	narrative_divergence	中共 官方叙事与现实偏差：中国是维护全球自由贸易秩序的重要力量... gap=0.8	0.8	2026-05-28 06:59:38.422723+12	\N	t	2026-05-28 06:59:38.422723+12	\N	对澳大利亚经济胁迫 | 稀土出口限制 | 华为供应链切断 | 一带一路债务陷阱	-0.18	\N	商务部声明,外交部发言
11	\N	34	narrative_collapse	中共 官方叙事与现实偏差：新冠病毒源于自然界，中国第一时间透明通报... gap=0.85	0.85	2026-05-28 06:59:38.422723+12	\N	t	2026-05-28 06:59:38.422723+12	\N	早期预警压制 | 李文亮事件 | 病毒序列延迟公布 | 武汉实验室调查阻碍	-0.3	\N	国家卫健委,外交部,WHO联合报告
12	\N	35	narrative_gap	美联储 官方叙事与现实偏差：美联储完全独立于政治压力，决策基于数据... gap=0.55	0.55	2026-05-28 06:59:38.422723+12	\N	t	2026-05-28 06:59:38.422723+12	\N	2019年特朗普压力下降息 | 2020年MMT边界模糊 | 政治周期与货币周期重合	-0.1	\N	联储声明,FOMC纪要
13	\N	60	narrative_divergence	普京 官方叙事与现实偏差：俄罗斯特别军事行动目标有限，随时可以谈判... gap=0.78	0.78	2026-05-28 06:59:38.422723+12	\N	t	2026-05-28 06:59:38.422723+12	\N	战线持续扩大 | 民用基础设施攻击 | 核威胁升级 | 谈判条件不断提高	-0.22	\N	克里姆林宫声明,RT,塔斯社
14	\N	60	narrative_divergence	普京 官方叙事与现实偏差：俄罗斯经济在制裁下保持稳定，卢布坚挺... gap=0.72	0.72	2026-05-28 06:59:38.422723+12	\N	t	2026-05-28 06:59:38.422723+12	\N	实际购买力下降 | 技术进口中断 | 影子舰队绕制裁 | 人才外逃加速	-0.18	\N	俄罗斯央行数据,官方媒体
\.


--
-- Data for Name: source_accuracy_history; Type: TABLE DATA; Schema: ccc; Owner: postgres
--

COPY ccc.source_accuracy_history (id, source_id, event_summary, event_date, predicted, outcome, accuracy, domain, created_at) FROM stdin;
\.


--
-- Data for Name: source_bias_vectors; Type: TABLE DATA; Schema: ccc; Owner: postgres
--

COPY ccc.source_bias_vectors (id, source_id, domain, bias_direction, bias_strength, notes, created_at) FROM stdin;
1	31	官方叙事/政权意图	regime_legitimacy_bias	0.88	适合作为政权叙事信号，不适合作为独立事实源	2026-06-04 08:13:32.594995+12
2	32	官方叙事/政权意图	regime_legitimacy_bias	0.88	适合作为政权叙事信号，不适合作为独立事实源	2026-06-04 08:13:32.594995+12
3	33	官方叙事/政权意图	regime_legitimacy_bias	0.88	适合作为政权叙事信号，不适合作为独立事实源	2026-06-04 08:13:32.594995+12
4	35	官方叙事/政权意图	regime_legitimacy_bias	0.88	适合作为政权叙事信号，不适合作为独立事实源	2026-06-04 08:13:32.594995+12
5	18	政策议程/权力叙事	elite_policy_agenda_bias	0.65	反映精英政策方向，但不是中立事实源	2026-06-04 08:13:32.594995+12
6	19	政策议程/权力叙事	elite_policy_agenda_bias	0.65	反映精英政策方向，但不是中立事实源	2026-06-04 08:13:32.594995+12
7	20	政策议程/权力叙事	elite_policy_agenda_bias	0.65	反映精英政策方向，但不是中立事实源	2026-06-04 08:13:32.594995+12
8	21	政策议程/权力叙事	elite_policy_agenda_bias	0.65	反映精英政策方向，但不是中立事实源	2026-06-04 08:13:32.594995+12
9	22	政策议程/权力叙事	elite_policy_agenda_bias	0.65	反映精英政策方向，但不是中立事实源	2026-06-04 08:13:32.594995+12
10	13	金融市场/短期事实	institutional_market_bias	0.32	偏向建制金融视角，但短期事实准确性较高	2026-06-04 08:13:32.594995+12
11	15	金融市场/短期事实	institutional_market_bias	0.32	偏向建制金融视角，但短期事实准确性较高	2026-06-04 08:13:32.594995+12
12	16	金融市场/短期事实	institutional_market_bias	0.32	偏向建制金融视角，但短期事实准确性较高	2026-06-04 08:13:32.594995+12
13	5	非线性模式/长周期信号	symbolic_pattern_bias	0.45	不能作为事实源，只作为模式信号	2026-06-04 08:13:32.594995+12
14	6	非线性模式/长周期信号	symbolic_pattern_bias	0.45	不能作为事实源，只作为模式信号	2026-06-04 08:13:32.594995+12
15	7	非线性模式/长周期信号	symbolic_pattern_bias	0.45	不能作为事实源，只作为模式信号	2026-06-04 08:13:32.594995+12
\.


--
-- Data for Name: source_conflict_matrix; Type: TABLE DATA; Schema: ccc; Owner: postgres
--

COPY ccc.source_conflict_matrix (id, source_a_id, source_b_id, conflict_domain, conflict_score, conflict_type, example, created_at) FROM stdin;
\.


--
-- Data for Name: source_domain_authority; Type: TABLE DATA; Schema: ccc; Owner: postgres
--

COPY ccc.source_domain_authority (id, source_id, domain, authority_score, evidence, created_at) FROM stdin;
1	1	泄露文件/权力行为	0.94	{原始泄露文件,权力行为直接证据}	2026-06-04 08:13:14.247244+12
2	2	泄露文件/权力行为	0.94	{原始泄露文件,权力行为直接证据}	2026-06-04 08:13:14.247244+12
3	4	泄露文件/权力行为	0.94	{原始泄露文件,权力行为直接证据}	2026-06-04 08:13:14.247244+12
4	3	离岸金融/权贵资产	0.93	{离岸金融原始数据,跨境资产网络}	2026-06-04 08:13:14.247244+12
5	8	离岸金融/权贵资产	0.93	{离岸金融原始数据,跨境资产网络}	2026-06-04 08:13:14.247244+12
6	9	犯罪网络/腐败结构	0.9	{跨国犯罪调查,腐败网络追踪}	2026-06-04 08:13:14.247244+12
7	11	犯罪网络/腐败结构	0.9	{跨国犯罪调查,腐败网络追踪}	2026-06-04 08:13:14.247244+12
8	10	军事行动/开源核查	0.88	{OSINT,地理定位,影像核查}	2026-06-04 08:13:14.247244+12
9	13	金融市场/短期事实	0.88	{高频事实流,市场即时数据}	2026-06-04 08:13:14.247244+12
10	15	金融市场/短期事实	0.88	{高频事实流,市场即时数据}	2026-06-04 08:13:14.247244+12
11	16	金融市场/短期事实	0.88	{高频事实流,市场即时数据}	2026-06-04 08:13:14.247244+12
12	17	亚洲产业链/区域经济	0.82	{亚洲产业链报道,区域经济观察}	2026-06-04 08:13:14.247244+12
13	18	政策议程/权力叙事	0.86	{政策共识生成,未来政策方向}	2026-06-04 08:13:14.247244+12
14	19	政策议程/权力叙事	0.86	{政策共识生成,未来政策方向}	2026-06-04 08:13:14.247244+12
15	20	政策议程/权力叙事	0.86	{政策共识生成,未来政策方向}	2026-06-04 08:13:14.247244+12
16	21	政策议程/权力叙事	0.86	{政策共识生成,未来政策方向}	2026-06-04 08:13:14.247244+12
17	22	政策议程/权力叙事	0.86	{政策共识生成,未来政策方向}	2026-06-04 08:13:14.247244+12
18	23	群体心理/民意趋势	0.84	{民意调查,社会情绪检测}	2026-06-04 08:13:14.247244+12
19	24	群体心理/民意趋势	0.84	{民意调查,社会情绪检测}	2026-06-04 08:13:14.247244+12
20	25	经济现实/行为成本	0.92	{硬经济数据,行为成本信号}	2026-06-04 08:13:14.247244+12
21	26	经济现实/行为成本	0.92	{硬经济数据,行为成本信号}	2026-06-04 08:13:14.247244+12
22	27	经济现实/行为成本	0.92	{硬经济数据,行为成本信号}	2026-06-04 08:13:14.247244+12
23	28	经济现实/行为成本	0.92	{硬经济数据,行为成本信号}	2026-06-04 08:13:14.247244+12
24	29	经济现实/行为成本	0.92	{硬经济数据,行为成本信号}	2026-06-04 08:13:14.247244+12
25	30	经济现实/行为成本	0.92	{硬经济数据,行为成本信号}	2026-06-04 08:13:14.247244+12
26	31	官方叙事/政权意图	0.82	{官方口径,权力意图信号}	2026-06-04 08:13:14.247244+12
27	32	官方叙事/政权意图	0.82	{官方口径,权力意图信号}	2026-06-04 08:13:14.247244+12
28	33	官方叙事/政权意图	0.82	{官方口径,权力意图信号}	2026-06-04 08:13:14.247244+12
29	35	官方叙事/政权意图	0.82	{官方口径,权力意图信号}	2026-06-04 08:13:14.247244+12
30	5	非线性模式/长周期信号	0.78	{历史命中模式,非线性信号}	2026-06-04 08:13:14.247244+12
31	6	非线性模式/长周期信号	0.78	{历史命中模式,非线性信号}	2026-06-04 08:13:14.247244+12
32	7	非线性模式/长周期信号	0.78	{历史命中模式,非线性信号}	2026-06-04 08:13:14.247244+12
\.


--
-- Data for Name: source_profiles; Type: TABLE DATA; Schema: ccc; Owner: postgres
--

COPY ccc.source_profiles (id, source_name, trust_tier, source_type, signal_type, domain_authority, bias_vector, blind_spots, use_as, reliability_score, notes, created_at, funding_source, regime_alignment, predictive_reliability, historical_accuracy, updated_at) FROM stdin;
1	WikiLeaks	T0	leak	linear	{外交电报,军事文件,政府行为}	{反美倾向,西方政府优先曝光}	{缺乏上下文,噪音高,时效性有限}	primary	0.9	原始文件，绕过官方叙事，成本极高故可信	2026-06-02 10:49:01.255185+12	\N	\N	0.5	0.5	2026-06-04 07:13:58.659672+12
2	Snowden文件	T0	leak	linear	{情报体系结构,监控网络,NSA行为}	{美国中心,技术情报偏重}	{时效2013年后有限,非美国情报体系覆盖弱}	primary	0.92	迄今最完整的情报体系结构泄露	2026-06-02 10:49:01.255185+12	\N	\N	0.5	0.5	2026-06-04 07:13:58.659672+12
3	ICIJ原始数据	T0	leak	linear	{离岸金融,权贵资产隐藏,"shell company"}	{西方视角,选择性释放,部分国家覆盖弱}	{内部关联复杂,需要专业解读}	primary	0.88	Panama/Pandora Papers原始来源	2026-06-02 10:49:01.255185+12	\N	\N	0.5	0.5	2026-06-04 07:13:58.659672+12
4	FOIA解密文件	T0	leak	linear	{美国政府历史行为,CIA行动,外交决策}	{严重滞后25年+,美国视角}	{非美国行为覆盖极弱}	primary	0.85	时效滞后但原始可信度极高	2026-06-02 10:49:01.255185+12	\N	\N	0.5	0.5	2026-06-04 07:13:58.659672+12
5	辛普森预言	T0	nonlinear	nonlinear	{长周期社会趋势,精英议程泄露,集体无意识}	{娱乐包装,难以系统化}	{无法精确时间定位,机制不明}	pattern_signal	0.65	历史命中率异常高，可能是精英圈议程泄露或集体无意识压缩	2026-06-02 10:49:01.255185+12	\N	\N	0.5	0.5	2026-06-04 07:13:58.659672+12
6	光明会塔牌	T0	nonlinear	nonlinear	{文明级压力场,长周期结构变化}	{解读高度主观,噪音极高}	{无科学验证机制,易被滥用}	pattern_signal	0.5	非线性信号源，仅作模式参考，不作事实依据	2026-06-02 10:49:01.255185+12	\N	\N	0.5	0.5	2026-06-04 07:13:58.659672+12
7	传统预言学	T0	nonlinear	nonlinear	{文明级趋势,历史周期压力}	{文化局限,解读分歧大}	{时间定位不准,现代验证困难}	pattern_signal	0.45	高维模式压缩，仅供趋势参考	2026-06-02 10:49:01.255185+12	\N	\N	0.5	0.5	2026-06-04 07:13:58.659672+12
8	ICIJ	T1	investigation	linear	{离岸网络,洗钱,权贵财富结构,"shell company"}	{有议程筛选,西方民主框架,部分威权国家覆盖弱}	{内部政治解释有限,执行层行为分析弱}	primary	0.87	离岸金融和权贵资产追踪最权威来源	2026-06-02 10:49:01.255185+12	\N	\N	0.5	0.5	2026-06-04 07:13:58.659672+12
9	OCCRP	T1	investigation	linear	{东欧犯罪网络,俄罗斯寡头,中亚腐败}	{东欧中心,反俄倾向}	{亚洲覆盖弱,中国相关有限}	primary	0.83	东欧和俄罗斯犯罪网络最佳来源	2026-06-02 10:49:01.255185+12	\N	\N	0.5	0.5	2026-06-04 07:13:58.659672+12
10	Bellingcat	T1	investigation	linear	{OSINT,军事行动核实,地理定位,武器追踪}	{亲西方,反俄倾向}	{依赖开源可被反制,中国相关弱}	primary	0.82	OSINT方法论最强，军事行动核实权威	2026-06-02 10:49:01.255185+12	\N	\N	0.5	0.5	2026-06-04 07:13:58.659672+12
11	ProPublica	T1	investigation	linear	{美国权力滥用,企业腐败,政府失职}	{美国中心,左倾}	{非美国议题覆盖极弱}	primary	0.8	美国国内深度调查最可信来源	2026-06-02 10:49:01.255185+12	\N	\N	0.5	0.5	2026-06-04 07:13:58.659672+12
12	FRONTLINE	T1	investigation	linear	{深度政治纪录,权力运作,历史重建}	{美国PBS立场,建制派倾向}	{制作周期长,实时性差}	primary	0.78	长周期政治纪录片，历史可信度高	2026-06-02 10:49:01.255185+12	\N	\N	0.5	0.5	2026-06-04 07:13:58.659672+12
13	Reuters	T2	media	linear	{即时事件,金融市场,公司动态}	{避免系统性政治冲突,维护金融秩序,不挑战西方核心利益}	{深层政治结构,情报体系,国家级黑箱}	reverse_indicator	0.75	事件层准确率高，但系统性政治批评极度保守	2026-06-02 10:49:01.255185+12	\N	\N	0.5	0.5	2026-06-04 07:13:58.659672+12
14	AP通讯	T2	media	linear	{原始新闻流,即时事件,战争动态}	{美国外交政策倾向,建制派}	{深度分析弱,结构性问题忽略}	reverse_indicator	0.72	原始新闻事实可信，叙事框架需警惕	2026-06-02 10:49:01.255185+12	\N	\N	0.5	0.5	2026-06-04 07:13:58.659672+12
15	Bloomberg	T2	media	linear	{全球资本动向,金融市场,企业并购}	{金融精英视角,资本利益优先}	{政治底层逻辑分析弱,非金融议题偏差大}	reverse_indicator	0.73	金融数据权威，政治分析谨慎参考	2026-06-02 10:49:01.255185+12	\N	\N	0.5	0.5	2026-06-04 07:13:58.659672+12
16	Financial Times	T2	media	linear	{欧洲资本动向,全球经济,企业战略}	{欧洲建制派,自由贸易秩序维护}	{地缘政治底层逻辑,威权体系内部分析}	reverse_indicator	0.71	欧洲视角经济分析权威	2026-06-02 10:49:01.255185+12	\N	\N	0.5	0.5	2026-06-04 07:13:58.659672+12
17	Nikkei Asia	T2	media	linear	{亚洲产业链,日本企业,供应链动态}	{日本国家利益,亲美同盟}	{中国内部政治,东南亚深度}	reverse_indicator	0.7	亚洲产业链和供应链最佳观察窗口	2026-06-02 10:49:01.255185+12	\N	\N	0.5	0.5	2026-06-04 07:13:58.659672+12
18	WEF	T3	think_tank	behavioral	{全球治理议程,技术官僚路线,利益相关者资本主义}	{精英主义,去主权倾向,技术解决方案主义}	{民众真实需求,主权国家利益,经济不平等深层矛盾}	reverse_indicator	0.6	定义未来政策框架，读其议程比读其结论更有价值	2026-06-02 10:49:01.255185+12	\N	\N	0.5	0.5	2026-06-04 07:13:58.659672+12
19	CFR	T3	think_tank	behavioral	{美国外交政策共识,全球秩序设计,精英外交网络}	{美国霸权维护,建制派民主党倾向}	{非西方视角,多极化趋势低估}	reverse_indicator	0.62	美国对外行为的政策实验室，读其议程预判美国行动	2026-06-02 10:49:01.255185+12	\N	\N	0.5	0.5	2026-06-04 07:13:58.659672+12
20	RAND	T3	think_tank	behavioral	{美国军事战略,冲突模拟,技术安全}	{军工复合体关联,美国国防利益}	{对手内部逻辑,非军事解决方案}	reverse_indicator	0.65	美国军事决策的智库来源，预判军事行动方向	2026-06-02 10:49:01.255185+12	\N	\N	0.5	0.5	2026-06-04 07:13:58.659672+12
21	Brookings	T3	think_tank	behavioral	{美国内政政策,经济政策,民主治理}	{民主党政策实验室,建制派自由主义}	{共和党视角,非西方政治体系}	reverse_indicator	0.58	美国民主党政策方向预判	2026-06-02 10:49:01.255185+12	\N	\N	0.5	0.5	2026-06-04 07:13:58.659672+12
22	CSIS	T3	think_tank	behavioral	{印太战略,中国政策,技术竞争}	{美国印太战略框架,反华倾向}	{中国内部真实逻辑,经济相互依存}	reverse_indicator	0.6	美国对华政策和印太战略最重要的智库	2026-06-02 10:49:01.255185+12	\N	\N	0.5	0.5	2026-06-04 07:13:58.659672+12
23	Pew Research	T4	survey	behavioral	{全球民意,群体认知状态,社会情绪}	{西方民主框架,问卷设计偏差}	{威权国家真实民意,非英语群体}	reverse_indicator	0.65	群体认知状态检测器，不是事实源	2026-06-02 10:49:01.255185+12	\N	\N	0.5	0.5	2026-06-04 07:13:58.659672+12
24	Gallup	T4	survey	behavioral	{美国社会情绪,全球幸福指数,就业信心}	{美国中心,中产阶级视角}	{边缘群体,非民主国家}	reverse_indicator	0.63	美国社会情绪温度计	2026-06-02 10:49:01.255185+12	\N	\N	0.5	0.5	2026-06-04 07:13:58.659672+12
25	非农就业数据	T5	economic	linear	{美国经济健康,就业市场,消费能力}	{修订频繁,季节性调整有争议}	{就业质量,非正规就业}	primary	0.85	美国经济最重要的月度指标，利益无法撒谎	2026-06-02 10:49:01.255185+12	\N	\N	0.5	0.5	2026-06-04 07:13:58.659672+12
26	CPI/PCE数据	T5	economic	linear	{通胀压力,货币政策方向,消费者购买力}	{政府统计方法论争议,篮子构成偏差}	{资产通胀,影子通胀}	primary	0.82	货币政策决定的核心依据	2026-06-02 10:49:01.255185+12	\N	\N	0.5	0.5	2026-06-04 07:13:58.659672+12
27	AIS船舶数据	T5	economic	linear	{实际贸易流量,港口活动,能源运输}	{军事船只不广播,部分区域盲区}	{内河贸易,非正规贸易}	primary	0.88	行为成本最高的贸易数据，极难造假	2026-06-02 10:49:01.255185+12	\N	\N	0.5	0.5	2026-06-04 07:13:58.659672+12
28	卫星图像	T5	economic	linear	{军事部署,工业活动,城市建设,农业产量}	{云层遮挡,解读需专业}	{地下设施,伪装行动}	primary	0.87	物理现实最直接的观测手段	2026-06-02 10:49:01.255185+12	\N	\N	0.5	0.5	2026-06-04 07:13:58.659672+12
29	国债收益率曲线	T5	economic	linear	{衰退预警,流动性压力,市场预期}	{央行干预扭曲,QE影响}	{非市场化经济体}	primary	0.83	历史上最准确的衰退预测指标	2026-06-02 10:49:01.255185+12	\N	\N	0.5	0.5	2026-06-04 07:13:58.659672+12
30	M2货币供应	T5	economic	linear	{流动性方向,通胀前瞻,信贷扩张}	{货币流通速度变化,定义修订}	{影子银行,加密货币}	primary	0.8	流动性和通胀的领先指标	2026-06-02 10:49:01.255185+12	\N	\N	0.5	0.5	2026-06-04 07:13:58.659672+12
31	人民日报	T6	official	behavioral	{CCP权力意图,政策方向,叙事优先级}	{完全服务于CCP利益,事实严重扭曲}	{真实民意,经济真实状况}	reverse_indicator	0.3	不追求真相，追踪CCP叙事方向和政策优先级	2026-06-02 10:49:01.255185+12	\N	\N	0.5	0.5	2026-06-04 07:13:58.659672+12
32	新华社	T6	official	behavioral	{中国官方立场,外交信号,政策宣示}	{官方喉舌,选择性报道}	{内部真实决策过程,派系动态}	reverse_indicator	0.28	外交信号和政策方向的官方窗口	2026-06-02 10:49:01.255185+12	\N	\N	0.5	0.5	2026-06-04 07:13:58.659672+12
33	RT	T6	official	behavioral	{俄方叙事框架,反西方议题,能源地缘}	{完全服务俄罗斯国家利益,事实扭曲}	{俄罗斯内部真实状况,普京政权内部}	reverse_indicator	0.25	识别俄方叙事意图，不作为事实来源	2026-06-02 10:49:01.255185+12	\N	\N	0.5	0.5	2026-06-04 07:13:58.659672+12
34	Fox News	T6	media	behavioral	{美国右翼情绪动员,共和党基本盘,文化战争议题}	{党派立场极强,情绪优先于事实}	{复杂政策分析,国际事务深度}	reverse_indicator	0.35	美国右翼情绪和共和党基本盘的晴雨表	2026-06-02 10:49:01.255185+12	\N	\N	0.5	0.5	2026-06-04 07:13:58.659672+12
35	伊朗Press TV	T6	official	behavioral	{伊朗官方立场,中东反西方叙事,什叶派视角}	{伊朗国家利益优先,事实严重扭曲}	{伊朗内部真实民意,反对派声音}	reverse_indicator	0.22	识别伊朗对外叙事意图	2026-06-02 10:49:01.255185+12	\N	\N	0.5	0.5	2026-06-04 07:13:58.659672+12
\.


--
-- Data for Name: source_weight_evaluations; Type: TABLE DATA; Schema: ccc; Owner: postgres
--

COPY ccc.source_weight_evaluations (id, source_id, source_name, domain, context, trust_tier, use_as, signal_type, tier_weight, reliability_score, historical_accuracy, predictive_reliability, domain_authority, bias_penalty, fact_weight, narrative_signal_weight, pattern_signal_weight, prediction_weight, reverse_indicator_weight, final_effective_weight, result, created_at) FROM stdin;
\.


--
-- Data for Name: timeline_proxy_map; Type: TABLE DATA; Schema: ccc; Owner: postgres
--

COPY ccc.timeline_proxy_map (id, entity_id, entity_name, proxy_entity_id, proxy_entity_name, proxy_type, proxy_source, weight, is_active, note, created_at) FROM stdin;
1	60	普京	40	俄罗斯	leader_state_proxy	hardcoded_v1	1	t	P6.6 timeline force proxy: Putin timeline should inherit Russia state-machine causal chain.	2026-06-06 23:31:03.713968+12
2	16	习近平	34	中共	leader_party_state_proxy	hardcoded_v1	1	t	P6.6 timeline force proxy: Xi timeline may inherit CCP party-state causal chain under RSAL entity convention.	2026-06-06 23:31:03.713968+12
\.


--
-- Data for Name: trust_fusion_v3_regression_expectations; Type: TABLE DATA; Schema: ccc; Owner: postgres
--

COPY ccc.trust_fusion_v3_regression_expectations (id, source_name, expected_min, expected_max, expected_use_as, note, created_at) FROM stdin;
1	Snowden文件	0.68	0.7	primary	T0 leak primary should remain top tier	2026-06-06 20:47:48.443191+12
2	WikiLeaks	0.67	0.7	primary	T0 leak primary strong fact/evidence source	2026-06-06 20:47:48.443191+12
3	ICIJ原始数据	0.67	0.69	primary	T0 original leak/data source should remain high	2026-06-06 20:47:48.443191+12
4	AIS船舶数据	0.66	0.69	primary	Physical reality source should remain high	2026-06-06 20:47:48.443191+12
5	卫星图像	0.66	0.69	primary	Physical observation source should remain high	2026-06-06 20:47:48.443191+12
6	WEF	0.67	0.7	reverse_indicator	Think tank / agenda source retains rule value	2026-06-06 20:47:48.443191+12
7	RAND	0.67	0.7	reverse_indicator	Military-strategy think tank should remain high reverse/rule signal	2026-06-06 20:47:48.443191+12
8	CFR	0.67	0.7	reverse_indicator	Foreign policy consensus source should remain high reverse/rule signal	2026-06-06 20:47:48.443191+12
9	人民日报	0.61	0.64	reverse_indicator	Official narrative source: low fact, useful rule/reverse signal	2026-06-06 20:47:48.443191+12
10	新华社	0.61	0.64	reverse_indicator	Official state narrative source should remain rule/reverse signal	2026-06-06 20:47:48.443191+12
11	RT	0.6	0.63	reverse_indicator	Russian official narrative source should remain reverse signal	2026-06-06 20:47:48.443191+12
12	Reuters	0.58	0.61	reverse_indicator	Mainstream media reverse indicator should stay mid-low	2026-06-06 20:47:48.443191+12
13	Bloomberg	0.58	0.61	reverse_indicator	Financial media reverse indicator should stay mid-low	2026-06-06 20:47:48.443191+12
14	辛普森预言	0.56	0.59	pattern_signal	Pattern signal must be suppressed below media/investigation layer	2026-06-06 20:47:48.443191+12
15	光明会塔牌	0.55	0.58	pattern_signal	High-noise nonlinear signal must remain low	2026-06-06 20:47:48.443191+12
16	传统预言学	0.55	0.58	pattern_signal	Traditional prophecy remains low trust / pattern-only	2026-06-06 20:47:48.443191+12
\.


--
-- Data for Name: wenziyu_cases; Type: TABLE DATA; Schema: ccc; Owner: postgres
--

COPY ccc.wenziyu_cases (id, document_id, raw_text, case_date, case_year, location, person_name, identity, platform, content, background, punishment, punishment_days, created_at) FROM stdin;
1	27	【中国文字狱事件记录】\n日期：2013年08月26日\n地点：河北清河县\n当事人：赵某\n平台：贴吧\n言论内容：听说娄庄发生命案了，有谁知道真相吗？\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:20.803792+12
2	98	【中国文字狱事件记录】\n日期：2016年10月24日\n地点：广东深圳\n当事人：明某鹭\n平台：微信公众平台\n言论内容：《深圳水贝村拆迁每家赔偿至少2亿》\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:24.101062+12
3	23	【中国文字狱事件记录】\n日期：2013年07月19日\n地点：甘肃古浪县\n当事人：章某\n平台：QQ\n言论内容：发布与转发“诋毁公安机关和公安民警的言论”\n处罚：治安处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:20.612586+12
4	24	【中国文字狱事件记录】\n日期：2013年07月19日\n地点：甘肃古浪县\n当事人：牛某\n平台：QQ\n言论内容：发布与转发“诋毁公安机关和公安民警的言论”\n处罚：治安处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:20.675603+12
5	25	【中国文字狱事件记录】\n日期：2013年07月19日\n地点：甘肃古浪县\n当事人：栗某\n平台：QQ\n言论内容：发布与转发“诋毁公安机关和公安民警的言论”\n处罚：治安处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:20.716464+12
6	26	【中国文字狱事件记录】\n日期：2013年08月13日\n地点：甘肃古浪县\n当事人：严某\n平台：QQ空间、腾讯微博\n言论内容：“诋毁政府和公安部门的言论”\n处罚：治安处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:20.760013+12
7	2550	【文字狱】日期：2013-07-19\n当事人：章某\n处罚：治安处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:07:59.758574+12
8	28	【中国文字狱事件记录】\n日期：2013年08月27日\n地点：辽宁大连\n当事人：杨爽\n平台：微信私聊\n言论内容：***总书记将于2013年8月28日至30日在大连视察\n处罚：拘留10日\n备注：言论内容属实\n法律文书：高公（治）决字（2013）第103号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:20.850041+12
9	29	【中国文字狱事件记录】\n日期：2013年09月17日\n地点：甘肃张家川县\n当事人：杨某\n身份：初中生\n平台：微博、QQ空间\n言论内容：警察包庇罪犯、殴打游行群众等\n背景事件：当地某KTV发生命案\n处罚：刑拘转行拘7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:20.89715+12
10	30	【中国文字狱事件记录】\n日期：2013年10月22日\n地点：四川仁寿县\n当事人：谭寿康\n平台：论坛网站\n言论内容：举报政府不作为，官商勾结黑恶势力\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:20.943552+12
11	31	【中国文字狱事件记录】\n日期：2013年11月28日\n地点：云南云龙县\n当事人：吴桂雄\n身份：中共党员\n平台：腾讯微博\n言论内容：反动言论\n处罚：开除党籍	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:20.990914+12
12	32	【中国文字狱事件记录】\n日期：2014年03月06日\n地点：北京\n当事人：孙兵\n身份：退役武警\n平台：现实\n言论内容：向天安门城楼毛泽东画像扔墨水瓶\n处罚：有期徒刑1年2个月\n备注：出狱时患癌症，2017年病逝	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:21.036723+12
13	33	【中国文字狱事件记录】\n日期：2014年08月07日\n地点：广东博罗县\n当事人：刘荣东\n平台：QQ群、现实\n言论内容：六四内容、攻击党和国家领导人、辱骂县政府和县公安局领导、组织游行示威\n处罚：有期徒刑3年、缓刑5年\n法律文书：（2014）惠博法刑一初字第339号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:21.09044+12
14	34	【中国文字狱事件记录】\n日期：2014年08月29日\n地点：安徽蚌埠\n当事人：张林\n平台：微博、腾讯微博\n言论内容：发起“送安妮上学”活动；组织游行示威\n处罚：有期徒刑3年6个月\n法律文书：（2013）蚌山刑初字第00316号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:21.139262+12
15	35	【中国文字狱事件记录】\n日期：2014年10月27日\n地点：北京\n当事人：郭某\n平台：QQ群\n言论内容：涉及国家领导人、国家处置“法轮功”、国家处置“六四”事件及国家政治稳定的反面报道文章\n处罚：有期徒刑1年\n备注：二审维持原判\n法律文书：（2014）密刑初字第356号；（2014）三中刑终字第00906号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:21.188724+12
16	36	【中国文字狱事件记录】\n日期：2015年01月04日\n地点：甘肃敦煌\n当事人：聂某\n平台：QQ、甘肃新民周刊\n言论内容：创办甘肃新民周刊，在其上发表多篇“不实，诽谤性文章”以及在QQ群转发纪念六四的帖子\n背景事件：六四事件\n处罚：有期徒刑3年\n法律文书：（2014）敦刑初字第268号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:21.235277+12
17	37	【中国文字狱事件记录】\n日期：2015年01月30日\n地点：广东广州\n当事人：郭建\n平台：朋友圈\n言论内容：（转发）“侮辱国家领导人的言论”\n处罚：拘留5日\n法律文书：穗公越行罚决字（2015）00491号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:21.279091+12
18	38	【中国文字狱事件记录】\n日期：2015年02月13日\n地点：四川江油市\n当事人：吴江川\n平台：微博\n言论内容：《单身妇女被群殴警员出警姿态不雅》，指责警察在出警时手揣兜和背在身后\n处罚：拘留5日\n法律文书：江公（涪江）行罚决字（2015）115号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:21.327124+12
19	39	【中国文字狱事件记录】\n日期：2015年02月25日\n地点：四川成都\n当事人：黄泽荣（铁流）\n平台：网络、著书\n言论内容：批评刘云山的文章\n处罚：有期徒刑二年半\n法律文书：（2015）青羊刑初字第243号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:21.373789+12
20	40	【中国文字狱事件记录】\n日期：2015年04月24日\n地点：青海海东\n当事人：舒家明\n平台：多个平台\n言论内容：指控玉树地震灾害重建工程偷工减料和拖欠工人工资的文章\n处罚：有期徒刑2年\n备注：二审维持原判\n法律文书：（2015）乐刑初字第2号；（2015）东刑终字第41号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:21.420816+12
21	41	【中国文字狱事件记录】\n日期：2015年05月15日\n地点：湖北罗田县\n当事人：王豫东\n身份：中共党员\n平台：朋友圈\n言论内容：“不当政治言论，丑化党国形象”\n处罚：党内处分	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:21.466758+12
22	42	【中国文字狱事件记录】\n日期：2015年05月27日\n地点：兰州日报\n当事人：赵文\n身份：公职人员/事业单位人员\n平台：微博\n言论内容：条子不捣蛋，案子少一半，恶警充爹娘，快快来发丧！\n处罚：被单位开除及吊销记者证	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:21.512953+12
23	43	【中国文字狱事件记录】\n日期：2015年07月01日\n地点：岭南师范学院\n当事人：梁新生\n身份：学者/教师\n平台：微博\n言论内容：“有损党和国家形象的过激博文”\n处罚：行政撤职	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:21.559776+12
24	44	【中国文字狱事件记录】\n日期：2015年07月02日\n地点：浙江丽水\n当事人：唐某\n平台：微博\n言论内容：万可房产和政府‘官官相护’、‘官商勾结’、‘特警队员当街殴打业主’等\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:21.606239+12
25	45	【中国文字狱事件记录】\n日期：2015年07月03日\n地点：广东惠州\n当事人：李红安\n平台：网络\n言论内容：举报惠州区委书记拥有多处房产\n处罚：有期徒刑一年半	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:21.652663+12
26	46	【中国文字狱事件记录】\n日期：2015年07月03日\n地点：广东惠州\n当事人：魏云新\n平台：网络\n言论内容：举报惠州区委书记拥有多处房产\n处罚：有期徒刑一年半	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:21.698351+12
27	47	【中国文字狱事件记录】\n日期：2015年07月05日\n地点：陕西汉中\n当事人：刘某\n身份：党政官员\n平台：微博\n言论内容：没事的时候，好吃好喝的供着他们，国家有事需要他们的时候，他们就得去，这是基本的契约精神\n处罚：行政记过	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:21.744292+12
28	48	【中国文字狱事件记录】\n日期：2015年08月18日\n地点：安徽合肥\n当事人：沈良庆\n平台：推特\n言论内容：天津大爆炸死亡至少1400人，失踪700人\n背景事件：812天津港大爆炸\n处罚：拘留9日\n法律文书：合公包（芜）行罚决字[2015]10986号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:21.792266+12
29	49	【中国文字狱事件记录】\n日期：2015年08月29日\n地点：江西德兴市\n当事人：夏某\n平台：QQ群\n言论内容：“天津爆炸案谣言”和“诋毁现任和前任党和国家领导人”\n背景事件：812天津港大爆炸\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:21.839142+12
30	50	【中国文字狱事件记录】\n日期：2015年08月30日\n地点：江苏徐州\n当事人：倪学善\n平台：多个平台\n言论内容：《我叫倪学善》系列伸冤视频，为其亡女（被公交车撞死）和亡兄（在公交公司讨要说法时被打死）喊冤\n处罚：拘留10日\n法律文书：贾公（夏）行罚决字【2015】866号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:21.885854+12
31	358	【中国文字狱事件记录】\n日期：2018年06月04日\n地点：广东深圳\n当事人：林群勇\n平台：不详\n言论内容：纪念六四内容\n背景事件：六四事件\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:35.888311+12
32	51	【中国文字狱事件记录】\n日期：2015年08月31日\n地点：山西运城\n当事人：邵重国\n平台：微信群\n言论内容：“侮辱谩骂国家领导人习近平主席”\n处罚：拘留10日\n法律文书：行罚决字【2015】002239号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:21.93132+12
33	52	【中国文字狱事件记录】\n日期：2015年10月31日\n地点：江苏泰兴\n当事人：王某\n平台：QQ空间\n言论内容：警察被混混追打视频，未公开\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:21.977697+12
34	53	【中国文字狱事件记录】\n日期：2015年11月05日\n地点：山东青岛\n当事人：邓某\n平台：QQ群、现实\n言论内容：“颠覆国家政权的言论”，以及成立中国民主正义党，试图推翻中共政权\n处罚：有期徒刑4年\n法律文书：（2015）青刑一初字第40号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:22.025052+12
35	54	【中国文字狱事件记录】\n日期：2015年11月05日\n地点：山东青岛\n当事人：曲某\n平台：QQ群、现实\n言论内容：“颠覆国家政权的言论”，以及成立中国民主正义党，试图推翻中共政权\n处罚：有期徒刑3年6个月\n法律文书：（2015）青刑一初字第40号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:22.072399+12
36	55	【中国文字狱事件记录】\n日期：2015年11月19日\n地点：子洲交警队\n当事人：苗乐（子洲交警微博号管理员）\n身份：公职人员/事业单位人员\n平台：微博\n言论内容：土改运动是杀人越货、谋财害命（用子洲交警官方号发布）\n处罚：有期徒刑1年\n备注：二审维持原判\n法律文书：（2015）子洲刑初字第00075号；（2016）陕08刑终39号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:22.120552+12
37	56	【中国文字狱事件记录】\n日期：2015年12月18日\n地点：东部某市\n当事人：吴某（公安局副局长）\n身份：党政官员\n平台：朋友圈\n言论内容：转发一篇抨击和否定一国两制的文章\n处罚：党内纪律处分	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:22.170301+12
38	57	【中国文字狱事件记录】\n日期：2015年12月22日\n地点：北京\n当事人：浦志强\n身份：律师\n平台：微博\n言论内容：“挑拨民族关系，煽动民族仇恨”的内容\n处罚：有期徒刑3年、缓刑3年	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:22.2143+12
39	58	【中国文字狱事件记录】\n日期：2015年12月22日\n地点：山西临县\n当事人：武锦荣\n平台：贴吧\n言论内容：武家沟村支书兼主任武某1勾结镇党委书记张某某顶风违纪瞒上欺下；山西最腐败县政府临县山西排名第一，大批官员集体腐败被媒体曝光\n处罚：有期徒刑1年\n备注：二审维持原判\n法律文书：（2015）临刑初字第275号；（2016）晋11刑终75号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:22.260693+12
40	59	【中国文字狱事件记录】\n日期：2015年12月29日\n地点：广东惠州\n当事人：叶晓峥\n平台：天涯、西子论坛\n言论内容：《惠州市博罗的杨先生因热情待人被警方追捕》；博罗数码哥因在网上骂领导被关押一年\n处罚：有期徒刑1年6个月\n备注：二审维持原判\n法律文书：（2015）惠城法刑一初字第502号；(2016)粤13刑终108号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:22.30711+12
41	60	【中国文字狱事件记录】\n日期：2016年01月15日\n地点：新疆乌鲁木齐\n当事人：张海涛\n平台：推特、微信等\n言论内容：大量政治话题、接受外媒采访\n处罚：有期徒刑19年\n法律文书：（2015）乌中刑一初字第192号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:22.351396+12
42	61	【中国文字狱事件记录】\n日期：2016年01月20日\n地点：湖南邵阳县\n当事人：刘某义\n平台：QQ空间\n言论内容：（视频）这就是邵阳的所谓的为人民服务。事情发生在邵阳县。看到这个视频真为这些带证的流氓感到伤心\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:22.394233+12
43	62	【中国文字狱事件记录】\n日期：2016年02月17日\n地点：青海同仁县\n当事人：周卡加（周洛）\n身份：作家\n平台：网络\n言论内容：西藏警方盘查藏人，这样肯定让藏人不满等”危害社会稳定“的文章\n处罚：有期徒刑3年	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:22.43986+12
44	63	【中国文字狱事件记录】\n日期：2016年03月23日\n地点：内蒙古锡林郭勒\n当事人：恩和巴图等4人\n平台：微信群\n言论内容：策划针对环境污染的游行示威\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:22.484652+12
45	64	【中国文字狱事件记录】\n日期：2016年03月30日\n地点：湖南邵阳\n当事人：刘俊君\n平台：朋友圈\n言论内容：山东疫苗事件里政府不作为\n背景事件：山东假疫苗事件\n处罚：拘留6日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:22.528225+12
46	65	【中国文字狱事件记录】\n日期：2016年03月30日\n地点：湖南湘乡市\n当事人：尹卫和\n平台：网络、现实\n言论内容：声援良心犯、平反六四等内容\n处罚：有期徒刑3年\n备注：二审维持原判\n法律文书：（2013）湘法刑初字第359号；（2016）湘03刑终157号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:22.57349+12
47	66	【中国文字狱事件记录】\n日期：2016年04月12日\n地点：天津\n当事人：周世锋\n身份：律师\n平台：网络、现实\n言论内容：攻击社会主义制度、一国两制基本国策，煽动对抗国家政权\n处罚：有期徒刑7年	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:22.62122+12
96	114	【中国文字狱事件记录】\n日期：2017年01月17日\n地点：上海\n当事人：朱周烁\n平台：微信群\n言论内容：“辱骂国家领导人”\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:24.941667+12
48	67	【中国文字狱事件记录】\n日期：2016年04月14日\n地点：安徽阜南县\n当事人：曾某英\n平台：微信公众平台\n言论内容：《一家七口横尸满地！现场惨不忍睹，太恐怖了！》（由其老板提供素材并要求发布）\n处罚：有期徒刑2年\n备注：二审维持原判\n法律文书：（2016）皖1225刑初77号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:22.666384+12
49	68	【中国文字狱事件记录】\n日期：2016年04月15日\n地点：广东佛山\n当事人：葛永喜\n身份：律师\n平台：朋友圈\n言论内容：邓小平、江泽民和习近平游泳的PS图片，写有“巴拿马的河水，真的好深；摸着石头过河，原来是过巴拿马河\n背景事件：巴拿马文件事件\n处罚：传唤警告	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:22.712283+12
50	69	【中国文字狱事件记录】\n日期：2016年04月19日\n地点：浙江温州\n当事人：陈德铮\n平台：微博\n言论内容：巴拿马文件是个女子文件，——毛旧宇\n背景事件：巴拿马文件事件\n处罚：拘留8日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:22.760781+12
51	70	【中国文字狱事件记录】\n日期：2016年05月04日\n地点：浙江苍南\n当事人：陆某\n平台：朋友圈\n言论内容：交警同志以后贴罚单擦亮你的狗眼睛……\n处罚：拘留2日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:22.806527+12
52	71	【中国文字狱事件记录】\n日期：2016年05月06日\n地点：江西新余\n当事人：应某\n平台：推特、微信\n言论内容：一段含有《九评共产党》下载链接及“三退”链接的推文；一条“自由上网”链接，含有“三退链接”\n处罚：有期徒刑1年6个月\n法律文书：（2015）渝刑初字第00505号；（2016）赣05刑终41号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:22.853199+12
53	72	【中国文字狱事件记录】\n日期：2016年05月07日\n地点：广东佛山\n当事人：陈某\n平台：网络\n言论内容：WD楼盘5月1日后在电梯井出问题死去了8人，在整个建筑期间死去二十多人，建筑行业内部也清楚\n处罚：拘留9日、罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:22.898171+12
54	440	【中国文字狱事件记录】\n日期：2018年08月31日\n地点：河北滦平县\n当事人：刘某\n平台：朋友圈\n言论内容：”辱骂交警群体“的内容\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:39.409087+12
55	73	【中国文字狱事件记录】\n日期：2016年05月13日\n地点：云南镇雄县\n当事人：涂某\n平台：QQ空间\n言论内容：（视频）镇雄县委书记亲自带狗娘养的上百名特警，暴力殴打手无寸铁的老百姓，不分老幼。视频长达十分钟，不求点赞，只求扩散。这还有法律，有王法吗\n处罚：有期徒刑6个月\n法律文书：（2016）云0627刑初138号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:22.944169+12
56	74	【中国文字狱事件记录】\n日期：2016年05月17日\n地点：广西钟山县\n当事人：欧荣贵\n平台：现实/横幅\n言论内容：反对强拆（帮他人制作）\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:22.990221+12
57	75	【中国文字狱事件记录】\n日期：2016年05月18日\n地点：广东五华县\n当事人：周某\n平台：微博\n言论内容：（视频）广东梅州五华县发生严重的土地征收冲突事件\n处罚：有期徒刑1年\n法律文书：（2016）粤1424刑初117号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:23.038718+12
58	76	【中国文字狱事件记录】\n日期：2016年05月18日\n地点：浙江杭州\n当事人：魏满意（水木然）\n身份：网络作家\n平台：网络\n言论内容：《比承包医院更黑：莆田人承包了中国90%的寺庙！》\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:23.082279+12
59	77	【中国文字狱事件记录】\n日期：2016年06月01日\n地点：湖北潜江\n当事人：彭云\n平台：微信群\n言论内容：传播请愿书，希望政府停止引进奥古斯特项目\n处罚：传唤警告	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:23.12858+12
60	78	【中国文字狱事件记录】\n日期：2016年06月02日\n地点：江苏兴化\n当事人：张某\n平台：QQ群\n言论内容：兴化民警死亡\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:23.173852+12
61	79	【中国文字狱事件记录】\n日期：2016年06月05日\n地点：浙江温州\n当事人：卢某\n平台：朋友圈\n言论内容：三岁小孩被人贩子抱走\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:23.233355+12
62	80	【中国文字狱事件记录】\n日期：2016年06月10日\n地点：河南光山县\n当事人：董璺馥\n平台：微博\n言论内容：“辱骂国家领导人***”的言论\n处罚：拘留10日\n法律文书：光公（罗）行罚决字（2016）0679号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:23.280038+12
63	81	【中国文字狱事件记录】\n日期：2016年06月14日\n地点：浙江杭州\n当事人：吕耿松\n平台：多个境外媒体网站\n言论内容：成立中国民主党，发表大量反动言论\n处罚：有期徒刑11年\n备注：二审维持原判\n法律文书：（2016）浙刑终311号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:23.324819+12
64	82	【中国文字狱事件记录】\n日期：2016年06月14日\n地点：浙江杭州\n当事人：陈树庆\n平台：多个境外媒体网站\n言论内容：成立中国民主党，发表大量反动言论\n处罚：有期徒刑10年半\n备注：二审维持原判\n法律文书：（2016）浙刑终310号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:23.374348+12
65	83	【中国文字狱事件记录】\n日期：2016年06月21日\n地点：广东汕头\n当事人：不详\n平台：微信群\n言论内容：（评论某交警死亡新闻）太好了，以后少一个开罚单的，为民除害，为这司机点赞\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:23.422299+12
66	84	【中国文字狱事件记录】\n日期：2016年07月08日\n地点：安徽巢湖市\n当事人：曲某\n平台：网络\n言论内容：今日巢湖东大圩决堤，半汤沦陷！\n处罚：行政罚款	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:23.466089+12
67	85	【中国文字狱事件记录】\n日期：2016年07月25日\n地点：浙江台州\n当事人：郭恩平\n身份：公职人员/事业单位人员\n平台：QQ空间\n言论内容：文章《杭州，为你羞耻》，讲述G20劳民伤财\n背景事件：2016杭州G20峰会\n处罚：拘留10日、单位免职、纪委介入调查	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:23.511406+12
68	86	【中国文字狱事件记录】\n日期：2016年07月26日\n地点：河北邢台\n当事人：史某\n平台：微博\n言论内容：“夸大受灾人数”\n背景事件：邢台洪灾\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:23.556575+12
69	87	【中国文字狱事件记录】\n日期：2016年07月26日\n地点：河北邢台\n当事人：单某\n平台：朋友圈\n言论内容：6个村庄淹死了700多人\n背景事件：邢台洪灾\n处罚：治安处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:23.60168+12
70	88	【中国文字狱事件记录】\n日期：2016年07月26日\n地点：河北邢台\n当事人：候某\n平台：贴吧\n言论内容：“水库放水虚假汛情”\n背景事件：邢台洪灾\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:23.64658+12
71	89	【中国文字狱事件记录】\n日期：2016年08月12日\n地点：云南马龙县\n当事人：戴宗言（戴克健）\n平台：网络、现实\n言论内容：打横幅、举标语、网络发帖等指控马龙政府欠债330万工程款不还\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:23.691603+12
72	90	【中国文字狱事件记录】\n日期：2016年08月15日\n地点：浙江苍南县\n当事人：张小孩\n平台：微博\n言论内容：（转发）#温州中院二审张启双等16人黑社会假案#；苍南公安局办案人员扬言：自己是有证的黑社会！\n处罚：拘留4日\n法律文书：苍公（治安一）行罚决字〔2016〕13825号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:23.737173+12
73	91	【中国文字狱事件记录】\n日期：2016年08月17日\n地点：山东济南\n当事人：谭志兰\n身份：公职人员/事业单位人员\n平台：朋友圈\n言论内容：2016.8.7上午当这位被称为王拆拆的官员在众星捧月般的游园时，二钢的居民正在遭受强拆的煎熬等指控济南CBD强拆的内容\n处罚：拘留10日\n法律文书：历公（智）行罚决字［2016］10094号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:23.783273+12
74	92	【中国文字狱事件记录】\n日期：2016年08月17日\n地点：山东济南\n当事人：谢小萍\n平台：朋友圈\n言论内容：他是带领强拆二钢居民的家园的罪人。现在的官员都在做了什么？等四张图片\n处罚：拘留10日\n法律文书：历公（智）行罚决字[2016]10093号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:23.831447+12
75	93	【中国文字狱事件记录】\n日期：2016年09月02日\n地点：浙江杭州\n当事人：戴鸿\n平台：推特\n言论内容：（视频）杭州维权者来梅忠（其妻）因G20峰会维稳被非法囚禁\n处罚：拘留5日\n法律文书：萧公（北干）行罚决字[2016]14151号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:23.877631+12
76	94	【中国文字狱事件记录】\n日期：2016年09月05日\n地点：广东惠州\n当事人：彭某\n平台：微信群\n言论内容：“不实言论“\n处罚：传唤警告	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:23.924164+12
77	95	【中国文字狱事件记录】\n日期：2016年09月14日\n地点：广东深圳\n当事人：黄美娟\n身份：访民\n平台：朋友圈\n言论内容：转发关于乌坎村抗议内容\n背景事件：乌坎抗议事件\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:23.969945+12
78	96	【中国文字狱事件记录】\n日期：2016年09月20日\n地点：四川宜宾\n当事人：袁某\n平台：微信\n言论内容：习近平是怂包\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:24.013826+12
79	97	【中国文字狱事件记录】\n日期：2016年09月30日\n地点：吉林延边\n当事人：权平\n平台：现实/T恤\n言论内容：#XITLER、#习包子、#大撒币\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:24.056526+12
80	1080	【中国文字狱事件记录】\n日期：2019年10月31日\n地点：湖南常德\n当事人：田某\n平台：微博\n言论内容：警察打人视频\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:09.460179+12
81	99	【中国文字狱事件记录】\n日期：2016年10月24日\n地点：广东深圳\n当事人：祝某\n平台：微信公众平台\n言论内容：《深圳水贝村拆迁每家赔偿至少2亿》\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:24.145884+12
82	100	【中国文字狱事件记录】\n日期：2016年10月24日\n地点：广东深圳\n当事人：高某华\n平台：微信公众平台\n言论内容：《深圳水贝村拆迁每家赔偿至少2亿》\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:24.194057+12
83	101	【中国文字狱事件记录】\n日期：2016年10月25日\n地点：安徽合肥\n当事人：陈某\n平台：微博\n言论内容：（视频）你有没有工作证，没有工作证我现在立即打电话叫人给你带走（指警察）……\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:24.314161+12
84	102	【中国文字狱事件记录】\n日期：2016年11月04日\n地点：湖南江华县\n当事人：黄明成\n身份：党政官员\n平台：微信\n言论内容：沱江县城街道上连续发生抢劫和抢小孩案件，抱上车就走\n背景事件：其本人刚追赶劫匪未果\n处罚：拘留5日、党内警告	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:24.362727+12
85	103	【中国文字狱事件记录】\n日期：2016年11月05日\n地点：吉林长春\n当事人：郭庆军\n平台：微信群\n言论内容：穿文化衫抗议习包子，留美归国学生被綁架\n处罚：拘留5日\n法律文书：二公（东站）行罚决字[2016]506号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:24.408374+12
86	104	【中国文字狱事件记录】\n日期：2016年11月07日\n地点：四川绵阳\n当事人：邓雪梅\n平台：现实/拉横幅、喊口号\n言论内容：毛某、习某画像，以及“薄某是反转民族英雄”的横幅\n处罚：有期徒刑2年\n备注：二审撤销原判\n法律文书：（2016）川0703刑初119号；（2016）川07刑终468号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:24.456024+12
87	105	【中国文字狱事件记录】\n日期：2016年12月08日\n地点：湖北红安县\n当事人：熊飞骏（熊应学）\n平台：著书\n言论内容：《中国在这里反思》和《中国近代史的前车之鉴》\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:24.507649+12
88	106	【中国文字狱事件记录】\n日期：2016年12月15日\n地点：福建光泽县\n当事人：卢月宏\n平台：朋友圈\n言论内容：（视频）一男子被交警查车围堵跳河，警察见死不救\n处罚：有期徒刑10个月、缓刑1年\n法律文书：（2016）闽0723刑初85号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:24.563798+12
89	107	【中国文字狱事件记录】\n日期：2016年12月19日\n地点：河南省柘城县\n当事人：张腾飞\n平台：QQ群、微信群\n言论内容：PS后的国家领导人照片、虚假信息、抨击社会舆论制度、煽动群众、谣言\n处罚：有期徒刑8个月\n法律文书：（2016）豫1424刑初794号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:24.613015+12
90	108	【中国文字狱事件记录】\n日期：2016年12月23日\n地点：河北晋州\n当事人：李某\n平台：QQ群\n言论内容：传播佛法；“辱骂、诋毁国内外国家元首元首、国家领导人、国家宗教政策和国内重大事件的虚假信息”\n处罚：有期徒刑1年6个月\n法律文书：（2016）冀0183刑初251号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:24.661798+12
91	109	【中国文字狱事件记录】\n日期：2016年12月30日\n地点：陕西西安\n当事人：雷镭\n平台：微信群\n言论内容：组织参战老兵集会的内容，以迎接元旦\n处罚：拘留10日\n法律文书：新公（长西）行罚决字〔2016〕1709号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:24.709209+12
92	110	【中国文字狱事件记录】\n日期：2017年01月06日\n地点：山东建筑大学\n当事人：邓相超（山东省政协委员、山东省常委）\n身份：教师、党政官员\n平台：微博\n言论内容：转发批评毛泽东微博\n处罚：双开	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:24.756155+12
93	111	【中国文字狱事件记录】\n日期：2017年01月08日\n地点：江西资溪县\n当事人：乔志平\n身份：党政官员\n平台：网络\n言论内容：（视频）政府也有违法的时候；政府就不可能不会做错事，也不可能不违法\n处罚：免职	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:24.801547+12
94	112	【中国文字狱事件记录】\n日期：2017年01月08日\n地点：江西资溪县\n当事人：吴剑\n身份：党政官员\n平台：网络\n言论内容：（视频）一句话，说到底还是权大于法\n处罚：撤职	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:24.847459+12
95	113	【中国文字狱事件记录】\n日期：2017年01月16日\n地点：河北石家庄\n当事人：左春和（石家庄文广新局副局长、河北省人大代表）\n身份：党政官员\n平台：微博\n言论内容：共产党是邪教、毛泽东是魔鬼\n处罚：免职并记过	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:24.893622+12
97	115	【中国文字狱事件记录】\n日期：2017年01月18日\n地点：江苏南通\n当事人：刘某\n平台：贴吧\n言论内容：执勤时间边喝酒边吃烧烤，边喝酒边吹牛逼，吃完了还要查人身份证，别人没带还要动手打人\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:24.989912+12
98	116	【中国文字狱事件记录】\n日期：2017年01月27日\n地点：广东广州\n当事人：陈某\n平台：微博\n言论内容：凡打杀公安者皆为英雄\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:25.033943+12
99	117	【中国文字狱事件记录】\n日期：2017年02月03日\n地点：云南昆明\n当事人：刘某\n平台：微信\n言论内容：（转发）一段疑似学生打架的视频，并称发生在自己老家\n处罚：拘留10日、罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:25.076816+12
100	118	【中国文字狱事件记录】\n日期：2017年02月23日\n地点：陕西延安\n当事人：李某\n平台：朋友圈\n言论内容：日交警娘的，可长时间么吃罚单了\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:25.118697+12
101	119	【中国文字狱事件记录】\n日期：2017年02月24日\n地点：辽宁大洼县\n当事人：康成玉\n平台：多个平台\n言论内容：《九成地产项目停工辽东湾新区楼盘陷困局》《盘锦市新建22栋政府大楼占地超千亩》\n处罚：有期徒刑1年10个月\n备注：二审维持原判\n法律文书：（2016）辽1121刑初259号；（2017）辽11刑终48号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:25.16229+12
102	120	【中国文字狱事件记录】\n日期：2017年02月26日\n地点：丽江市中级法院\n当事人：李炳祥（法官）\n身份：党政官员\n平台：微博\n言论内容：（人民网发布的57岁交警雪中执勤）其实是作秀，等“不当言论”\n处罚：停职、立案调查	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:25.208959+12
103	121	【中国文字狱事件记录】\n日期：2017年03月10日\n地点：江苏靖江\n当事人：不详\n平台：网络\n言论内容：靖江莲沁苑小学数学老师马某衣冠禽兽！占女生便宜！\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:25.257292+12
104	122	【中国文字狱事件记录】\n日期：2017年03月17日\n地点：四川渠县\n当事人：代忠\n平台：不详\n言论内容：“侮辱政府”的打油诗和上访\n处罚：拘留20日\n法律文书：渠公（治）行罚决字[2017]431号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:25.300058+12
105	227	【中国文字狱事件记录】\n日期：2017年12月04日\n地点：贵州德江县\n当事人：安某\n平台：微信群\n言论内容：（转发）当地政府贪污腐败，截留补助款项的消息\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:30.029451+12
106	123	【中国文字狱事件记录】\n日期：2017年03月21日\n地点：河南睢县\n当事人：杨红昌\n平台：微博\n言论内容：《狗日的派出所不作为，村民办证跑断腿》等多篇文章指控当地警察部门不作为\n处罚：有期徒刑1年、缓刑2年\n法律文书：（2017）豫1422刑初126号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:25.344308+12
107	124	【中国文字狱事件记录】\n日期：2017年03月25日\n地点：浙江温州\n当事人：杨某\n身份：党政官员\n平台：微信群\n言论内容：应该组织家长委员会，策划方案、募集资金、组织发动队伍封锁市教育局\n处罚：党内警告、免职	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:25.389418+12
108	125	【中国文字狱事件记录】\n日期：2017年03月28日\n地点：上海\n当事人：王巍\n平台：微信公众平台、网易新闻\n言论内容：《闵行教育已经到了最危险的时刻！——细数闵行教育七宗罪》\n处罚：拘役5个月\n法律文书：（2017）沪0112刑初423号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:25.434863+12
109	126	【中国文字狱事件记录】\n日期：2017年03月31日\n地点：四川成都\n当事人：陈云飞\n平台：推特\n言论内容：组织为六四遇难者扫墓\n背景事件：六四事件\n处罚：有期徒刑四年\n备注：二审维持原判\n法律文书：（2016）川0107刑初410号；（2017）川01刑终485号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:25.479053+12
110	127	【中国文字狱事件记录】\n日期：2017年04月02日\n地点：湖南湘潭县\n当事人：文某\n平台：现实/贴大字报\n言论内容：“诋毁该村两委换届选举候选人”\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:25.525129+12
111	128	【中国文字狱事件记录】\n日期：2017年04月02日\n地点：湖南湘潭县\n当事人：李某\n平台：现实/贴大字报\n言论内容：“诋毁该村两委换届选举候选人”\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:25.572138+12
112	129	【中国文字狱事件记录】\n日期：2017年04月03日\n地点：四川泸县\n当事人：唐小波\n平台：QQ、快手\n言论内容：太腐败了，孩子明明是打死的，还得说是跳楼摔死的；直播警民冲突现场\n背景事件：泸州太伏中学事件\n处罚：有期徒刑2年6个月	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:25.619003+12
113	130	【中国文字狱事件记录】\n日期：2017年04月07日\n地点：山东招远\n当事人：王江峰\n平台：QQ、微信\n言论内容：称毛泽东为“毛贼”，称习近平为“包子”，“傻逼”\n处罚：有期徒刑2年\n备注：二审改判1年10个月\n法律文书：（2017）鲁0685刑初9号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:25.66372+12
114	131	【中国文字狱事件记录】\n日期：2017年04月19日\n地点：江苏镇江\n当事人：申某\n平台：某视频直播平台\n言论内容：镇江市朱方路这群穿着警察衣服的狗，专门查穷人的电动车\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:25.708887+12
115	132	【中国文字狱事件记录】\n日期：2017年04月25日\n地点：湖北远安县\n当事人：赵某\n平台：微信\n言论内容：交警这帮狗子没一个好东西，同意的顶起来\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:25.75508+12
116	133	【中国文字狱事件记录】\n日期：2017年05月01日\n地点：湖南邵阳\n当事人：张文武（释大成）\n平台：推特\n言论内容：声援709、支持郭文贵\n背景事件：709大抓捕；郭文贵爆料事件\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:25.801713+12
117	134	【中国文字狱事件记录】\n日期：2017年05月01日\n地点：陕西周至县\n当事人：李某\n平台：网络\n言论内容：关于H7N9的疫情“谣言”\n处罚：“依法处罚”	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:25.846265+12
118	135	【中国文字狱事件记录】\n日期：2017年05月01日\n地点：陕西周至县\n当事人：金某\n平台：网络\n言论内容：关于H7N9的疫情“谣言”\n处罚：“依法处罚”	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:25.890324+12
119	136	【中国文字狱事件记录】\n日期：2017年05月02日\n地点：贵州凯里\n当事人：李某\n平台：朋友圈\n言论内容：十万个艹艹艹都难解心里之恨，下班路过，狗杂种些三轮车都不放过\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:25.934676+12
120	137	【中国文字狱事件记录】\n日期：2017年05月03日\n地点：福建晋江\n当事人：颜某\n平台：朋友圈\n言论内容：安海龙山寺和尚吊死于寺内\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:25.97857+12
121	138	【中国文字狱事件记录】\n日期：2017年05月10日\n地点：浙江东阳县\n当事人：何某\n平台：微信群\n言论内容：“虚假信息”（引发民众聚集）\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:26.021572+12
122	139	【中国文字狱事件记录】\n日期：2017年05月18日\n地点：贵州德江县\n当事人：李某\n平台：微博\n言论内容：“诋毁堰塘乡党委政府等部门”\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:26.067572+12
123	140	【中国文字狱事件记录】\n日期：2017年05月19日\n地点：四川仁寿县\n当事人：陈某\n平台：微博、陌陌、朋友圈\n言论内容：出人命了，年轻的生命死得这般凄惨；老百姓无人诉苦逼的一个20多岁的年轻小伙子跳楼，天理何在\n处罚：行政处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:26.116022+12
124	141	【中国文字狱事件记录】\n日期：2017年05月19日\n地点：四川仁寿县\n当事人：颜某\n平台：朋友圈\n言论内容：好吓人！昨晚8点多朋友在黑龙滩大坝遭抢！\n处罚：行政处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:26.165309+12
125	142	【中国文字狱事件记录】\n日期：2017年05月25日\n地点：四川眉山\n当事人：张鸥\n平台：微信群\n言论内容：仁寿死了7个禽流感了，就在县医院；真的，政府部门控制了，没有报出来\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:26.209727+12
126	143	【中国文字狱事件记录】\n日期：2017年05月25日\n地点：江苏连云港\n当事人：沈立秀\n平台：现实/举牌\n言论内容：指控当地政府强拆的内容\n处罚：有期徒刑2年6个月\n备注：二审维持原判\n法律文书：（2016)苏0706刑初505号；（2017)苏07刑终240号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:26.254279+12
127	144	【中国文字狱事件记录】\n日期：2017年05月26日\n地点：四川眉山\n当事人：钟源\n平台：微信群\n言论内容：真的是死了7个了，政府肯定是瞒报了的\n处罚：拘留2日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:26.296748+12
128	145	【中国文字狱事件记录】\n日期：2017年05月26日\n地点：山东东营\n当事人：陈宗光\n平台：贴吧\n言论内容：“针对中国共产党和党和国家领导人的不当言论”\n处罚：拘留10日\n法律文书：鲁滨公海（朝阳）行罚决字【2017】10020号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:26.341254+12
129	146	【中国文字狱事件记录】\n日期：2017年06月03日\n地点：福建厦门\n当事人：冯周管\n平台：微信群\n言论内容：青年人称呼习大大，小朋友称呼习爷爷，我称呼肥猪、包子、撒币\n处罚：拘留5日\n法律文书：厦公思（何边）行罚决字[2017]00196号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:26.38432+12
130	147	【中国文字狱事件记录】\n日期：2017年06月07日\n地点：甘肃兰州\n当事人：党某\n平台：微信、现实\n言论内容：当面质问两名辅警执法是不是为了弄钱，并将过程拍视频发到微信群\n处罚：拘留7日、罚款300元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:26.427243+12
131	1094	【中国文字狱事件记录】\n日期：2019年11月09日\n地点：辽宁铁岭\n当事人：张某\n平台：微信群\n言论内容：该死的交警\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:10.98073+12
132	148	【中国文字狱事件记录】\n日期：2017年06月09日\n地点：陕西渭南\n当事人：李某\n身份：教师\n平台：西部网\n言论内容：华州区强制所有公职人员捐款200元，请问是否合理\n处罚：拘留5日\n法律文书：华公（治）行罚决字［2017］157号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:26.470452+12
133	149	【中国文字狱事件记录】\n日期：2017年06月12日\n地点：湖南新晃县\n当事人：舒某\n平台：微信群\n言论内容：（针对一段执法视频和不实言论的评论）辱警言论\n处罚：拘留15日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:26.515131+12
134	150	【中国文字狱事件记录】\n日期：2017年06月19日\n地点：安徽界首\n当事人：田某\n平台：微信群\n言论内容：“侮辱政府和民警的言论”\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:26.560086+12
135	151	【中国文字狱事件记录】\n日期：2017年06月20日\n地点：浙江仙居县\n当事人：汪某\n平台：微信群\n言论内容：将某段讽刺江西浮梁县干部贪腐的顺口溜改为仙居县版本并转发\n处罚：拘留2日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:26.605164+12
136	152	【中国文字狱事件记录】\n日期：2017年06月26日\n地点：广东惠州\n当事人：李秋青\n平台：朋友圈\n言论内容：郭文贵爆料内容\n背景事件：郭文贵爆料事件\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:26.649405+12
137	153	【中国文字狱事件记录】\n日期：2017年06月28日\n地点：湖北阳新县\n当事人：王某\n平台：微博\n言论内容：（视频）阳新县兴国镇林峰路夜市发生特大斗殴案件，受伤人员有生命危险\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:26.694768+12
138	154	【中国文字狱事件记录】\n日期：2017年06月30日\n地点：湖南衡阳\n当事人：单某\n平台：网络\n言论内容：衡阳县西渡小孩被挖肾挖眼睛\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:26.739758+12
139	155	【中国文字狱事件记录】\n日期：2017年06月30日\n地点：湖南衡阳\n当事人：罗某国\n平台：网络\n言论内容：（转发）衡阳县西渡小孩被挖肾挖眼睛\n处罚：罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:26.784434+12
140	156	【中国文字狱事件记录】\n日期：2017年07月04日\n地点：吉林四平\n当事人：张某\n平台：微信群\n言论内容：“侮辱警察”的言论\n处罚：拘留9日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:26.83047+12
141	157	【中国文字狱事件记录】\n日期：2017年07月04日\n地点：吉林四平\n当事人：郝某\n平台：朋友圈\n言论内容：四平警察，真是笨的跟猪似滴，让一个吸毒犯给干死一个，伤一个，抓了4个半小时才抓都，真猪啊\n处罚：拘留9日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:26.875927+12
142	158	【中国文字狱事件记录】\n日期：2017年07月07日\n地点：广东广州\n当事人：刘星\n平台：现实/印于T恤\n言论内容：（中英双语）当人民恐惧政府即为暴政\n处罚：拘留5日\n法律文书：穗公越行罚决字［2017］02213号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:26.922959+12
143	159	【中国文字狱事件记录】\n日期：2017年07月08日\n地点：贵州沿河县\n当事人：陈荣\n平台：微信群\n言论内容：（视频）尊敬的习主席、李克强总理，您们好，这里是XX地的一户贫困家庭，他们是……电话是……\n处罚：拘留5日\n法律文书：沿公法行罚决字［2017］733号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:26.969993+12
144	160	【中国文字狱事件记录】\n日期：2017年07月14日\n地点：内蒙古质监局\n当事人：张海顺\n身份：党政官员\n平台：现实/会议\n言论内容：总书记号召‘撸起袖子加油干’，我局要认真落实！要‘撩起裙子使劲干’\n处罚：免职	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:27.013869+12
145	161	【中国文字狱事件记录】\n日期：2017年07月16日\n地点：四川成都\n当事人：邬某\n平台：贴吧\n言论内容：“侮辱协警”的言论\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:27.05862+12
146	162	【中国文字狱事件记录】\n日期：2017年07月17日\n地点：贵州德江县\n当事人：安某、冯某\n平台：微信\n言论内容：警察用锥形桶砸人视频，以及评论“草，这帮XX，穿身狗皮”\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:27.104122+12
147	163	【中国文字狱事件记录】\n日期：2017年07月25日\n地点：北京师范大学\n当事人：史杰鹏\n身份：学者/教师\n平台：微博\n言论内容：“错误言论”\n处罚：解聘	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:27.151312+12
148	164	【中国文字狱事件记录】\n日期：2017年07月26日\n地点：辽宁沈阳\n当事人：胡国义\n平台：现实/举牌\n言论内容：冤；见公安局长打人\n处罚：拘留10日\n法律文书：沈铁沈公（治）行罚决字[2017]578号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:27.199344+12
149	165	【中国文字狱事件记录】\n日期：2017年07月27日\n地点：江苏张家港市\n当事人：冯某\n平台：多个平台\n言论内容：这些狗饿坏了，谁都咬；这帮狗这几天怎么不来了呀；这些狗是为人民币服务的\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:27.24668+12
150	166	【中国文字狱事件记录】\n日期：2017年07月27日\n地点：广西平南县\n当事人：谢某\n平台：现实\n言论内容：“拉横幅、喊口号（具体内容不详）“\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:27.291976+12
151	167	【中国文字狱事件记录】\n日期：2017年07月27日\n地点：广西平南县\n当事人：邓某\n平台：现实\n言论内容：“拉横幅、喊口号（具体内容不详）“\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:27.338535+12
152	168	【中国文字狱事件记录】\n日期：2017年07月27日\n地点：广西平南县\n当事人：岑某\n平台：现实\n言论内容：“拉横幅、喊口号（具体内容不详）“\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:27.381952+12
153	169	【中国文字狱事件记录】\n日期：2017年07月31日\n地点：山东菏泽\n当事人：周某\n平台：微博、微信\n言论内容：（以退休公安的名义）善心汇被查实质是公安内部腐败分子借此制造内乱\n背景事件：善心汇事件\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:27.426786+12
154	170	【中国文字狱事件记录】\n日期：2017年08月01日\n地点：山东工商学院\n当事人：李默海\n身份：学者/教师\n平台：不详\n言论内容：批评极权言论\n处罚：停职	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:27.472639+12
155	171	【中国文字狱事件记录】\n日期：2017年08月03日\n地点：云南大理\n当事人：卢昱宇\n平台：谷歌、Tumblr、推特、微博等\n言论内容：《非新闻》栏目，即从互联网搜集地方游行抗议事件\n处罚：有期徒刑4年\n备注：二审维持原判	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:27.520022+12
156	172	【中国文字狱事件记录】\n日期：2017年08月04日\n地点：河北雄县\n当事人：于某、许某\n平台：微信群\n言论内容：今晚雄县新闻报道：今天中午，在雄中操场举办的广场舞比赛中，多人中暑，82人昏迷不醒，两位老大妈不治身亡\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:27.564021+12
157	173	【中国文字狱事件记录】\n日期：2017年08月06日\n地点：辽宁大连\n当事人：范某\n平台：微博\n言论内容：烈士子女直接参警是政策规定，咱比不了（使用名为“大连交警小范”的微博）\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:27.609479+12
158	174	【中国文字狱事件记录】\n日期：2017年08月07日\n地点：河南郑州\n当事人：吕某国\n平台：微信群\n言论内容：一段交警被撞身亡的视频，”大快人心“\n处罚：拘留15日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:27.652602+12
159	175	【中国文字狱事件记录】\n日期：2017年08月07日\n地点：河北雄县\n当事人：于某、许某\n平台：微信群\n言论内容：今晚雄县新闻报道：今天中午，在雄中操场举办的广场舞比赛中，多人中暑，82人昏迷不醒，两位老大妈不治身亡\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:27.697118+12
160	176	【中国文字狱事件记录】\n日期：2017年08月10日\n地点：贵州黔东南\n当事人：刘某\n平台：微信群\n言论内容：一条带有诽谤、侮辱性质的不当政治言论\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:27.742476+12
161	177	【中国文字狱事件记录】\n日期：2017年08月10日\n地点：河北巨鹿县\n当事人：胡某\n平台：微信群\n言论内容：（交警被车撞视频）警犬对碰，小心警狗咬人\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:27.785073+12
162	178	【中国文字狱事件记录】\n日期：2017年08月10日\n地点：吉林永吉县\n当事人：徐某\n平台：微博、优酷\n言论内容：视频：直击永吉-真实的永吉713\n处罚：有期徒刑6个月、缓刑1年\n法律文书：（2017）吉0221刑初199号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:27.828394+12
163	179	【中国文字狱事件记录】\n日期：2017年08月11日\n地点：北京\n当事人：梁小军\n身份：律师\n平台：推特\n言论内容：转发吴淦开庭通知\n背景事件：709大抓捕事件\n处罚：传唤警告	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:27.873275+12
164	180	【中国文字狱事件记录】\n日期：2017年08月14日\n地点：云南威信县\n当事人：陈某\n平台：朋友圈\n言论内容：“两段辱骂讽刺麟凤派出所执勤民警的视频”\n处罚：拘留10日、罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:27.918747+12
165	181	【中国文字狱事件记录】\n日期：2017年08月19日\n地点：云南罗平县\n当事人：马某\n平台：微信群\n言论内容：习包子，量中华之物力结与国之欢心\n处罚：拘留5日\n法律文书：罗公（马）行罚决字（2017）第35号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:27.962655+12
166	182	【中国文字狱事件记录】\n日期：2017年08月23日\n地点：广东深圳\n当事人：连某\n平台：微博、微信等\n言论内容：多篇涉及国家领导人的恶性政治谣言文章\n处罚：有期徒刑8个月\n法律文书：（2017）粤0307刑初1824号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:28.008196+12
167	183	【中国文字狱事件记录】\n日期：2017年08月25日\n地点：新疆乌鲁木齐\n当事人：秦某\n平台：网络\n言论内容：代潘某发表《乌木木齐：是谁动了沙帕尔兄弟的“奶酪”》等三篇文章\n处罚：有期徒刑2年3个月\n法律文书：（2016）新0109刑初190号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:28.05498+12
168	184	【中国文字狱事件记录】\n日期：2017年08月25日\n地点：新疆乌鲁木齐\n当事人：潘某\n平台：网络\n言论内容：《乌木木齐：是谁动了沙帕尔兄弟的“奶酪”》等三篇文章\n处罚：有期徒刑2年6个月、罚金10万元\n法律文书：（2016）新0109刑初190号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:28.103545+12
169	185	【中国文字狱事件记录】\n日期：2017年08月26日\n地点：四川成都\n当事人：于庸河\n平台：不详\n言论内容：撰文《公民问计》声援被捕的异议人士黄晓敏\n背景事件：异议人士黄晓敏被捕\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:28.151808+12
170	186	【中国文字狱事件记录】\n日期：2017年08月28日\n地点：山西太原\n当事人：王某宏、张某美\n平台：微信群\n言论内容：转发抵制煤改气言论\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:28.198029+12
171	187	【中国文字狱事件记录】\n日期：2017年08月28日\n地点：宁夏中卫\n当事人：周某\n身份：公职人员\n平台：微信群\n言论内容：”辱骂警察的不当言论“\n处罚：警告、免职	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:28.241574+12
172	188	【中国文字狱事件记录】\n日期：2017年08月31日\n地点：福建厦门\n当事人：林隆\n平台：推特、微博\n言论内容：打倒中国共产党！推翻共产主义！打死中国共产党员！坚决反对中国共产党执政！中华民国万岁！中国国民党万岁！\n处罚：拘留10日\n法律文书：厦公湖（五边）行罚决字[2017]00100号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:28.286886+12
173	189	【中国文字狱事件记录】\n日期：2017年09月01日\n地点：重庆师范大学\n当事人：谭松\n身份：学者/教师\n平台：现实/课题研究\n言论内容：关于土改课题研究\n处罚：开除	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:28.331403+12
174	190	【中国文字狱事件记录】\n日期：2017年09月05日\n地点：安徽界首市\n当事人：杨某\n平台：微信群\n言论内容：他们傻逼吗，下雨还查，一群傻逼穷这个样\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:28.381268+12
175	191	【中国文字狱事件记录】\n日期：2017年09月17日\n地点：内蒙古鄂尔多斯\n当事人：闫某\n平台：微信群\n言论内容：“侮辱警察”的言论\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:28.429681+12
176	192	【中国文字狱事件记录】\n日期：2017年09月19日\n地点：广东潮州\n当事人：田应俊\n平台：微信群\n言论内容：以“梦见猪”代指孟建柱谈论政治\n背景事件：郭文贵爆料事件\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:28.476916+12
177	193	【中国文字狱事件记录】\n日期：2017年09月19日\n地点：河南濮阳\n当事人：陈守理\n平台：微信群\n言论内容：哈哈该不会是王芳跟孟吧\n背景事件：郭文贵爆料事件\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:28.525583+12
178	194	【中国文字狱事件记录】\n日期：2017年09月20日\n地点：山东定陶县\n当事人：王某\n平台：微信群\n言论内容：音频和视频文件，抹黑党国形象\n处罚：拘留15日、罚款1000元\n法律文书：定公（东）行罚决字［2017］10552号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:28.568754+12
179	195	【中国文字狱事件记录】\n日期：2017年09月22日\n地点：陕西西安\n当事人：李某\n平台：微博\n言论内容：“对四川牺牲英雄辅警的侮辱性言论”\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:28.609079+12
180	196	【中国文字狱事件记录】\n日期：2017年09月22日\n地点：浙江缙云县\n当事人：蒋某\n平台：朋友圈\n言论内容：拍车狗\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:28.653433+12
181	197	【中国文字狱事件记录】\n日期：2017年09月27日\n地点：贵州湄潭县\n当事人：陈某（湄江中学）\n身份：学者/教师\n平台：微博\n言论内容：当地扶贫工作是走形式\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:28.692304+12
182	198	【中国文字狱事件记录】\n日期：2017年10月01日\n地点：贵州德江县\n当事人：张某\n平台：微信群\n言论内容：杀人了，快点看啊，城北杀人了，对场就砍死了（警方称是砍伤，没有砍死）\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:28.734008+12
183	199	【中国文字狱事件记录】\n日期：2017年10月03日\n地点：天津\n当事人：吴某\n平台：现实\n言论内容：用剪刀在两个小区内共损毁了66面国旗\n处罚：有期徒刑2年	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:28.773279+12
184	200	【中国文字狱事件记录】\n日期：2017年10月07日\n地点：山东烟台\n当事人：初某军\n平台：朋友圈\n言论内容：本来挺好的日子，让个搅屎棍给搅乱了；派出所的狗狗来暗访啦\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:28.812738+12
185	1196	【中国文字狱事件记录】\n日期：2019年12月29日\n地点：山东淄博\n当事人：王某\n平台：QQ群\n言论内容：“精日言论”\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:16.54736+12
186	201	【中国文字狱事件记录】\n日期：2017年10月08日\n地点：云南玉溪\n当事人：普某\n平台：朋友圈\n言论内容：是哪只狗做的，大清早的有没有公德心。旁边几张车怎么没有，瞎狗！\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:28.853946+12
187	202	【中国文字狱事件记录】\n日期：2017年10月09日\n地点：浙江杭州\n当事人：张合记\n平台：微信群\n言论内容：组织诈骗案受害者到杭州报案，警方称组织非法集会\n处罚：拘留15日\n法律文书：杭上公（湖）行罚决字[2017]11251号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:28.896202+12
188	203	【中国文字狱事件记录】\n日期：2017年10月10日\n地点：陕西西安\n当事人：宜北北\n平台：网络\n言论内容：（评论当地一名辅警被车撞视频）把交警撞死才好\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:28.94029+12
189	204	【中国文字狱事件记录】\n日期：2017年10月15日\n地点：河北邯郸\n当事人：曲利风\n平台：微博\n言论内容：对永年区政府及其下属单位侮辱、谩骂等不当言论\n处罚：拘留10日\n备注：法院随后为其平反\n法律文书：永公（治稳）行罚决字[2017]1301号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:28.983624+12
190	205	【中国文字狱事件记录】\n日期：2017年10月17日\n地点：广东佛山\n当事人：谭捷芳\n平台：朋友圈\n言论内容：完成早餐向习大大出发\n处罚：拘留10日\n备注：警方称拘留原因是不配合调查\n法律文书：佛顺公行罚决字[2017]23089号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:29.028428+12
191	206	【中国文字狱事件记录】\n日期：2017年10月19日\n地点：江苏南京\n当事人：王健\n平台：脸书、推特、微信等\n言论内容：视频：公民有言论出版集会结社游行示威的自由，南京王健；解除党禁、报禁、释放所有政治犯，结束一党专制\n处罚：拘留15日\n法律文书：江公（东）行罚决字〔2017〕1749号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:29.073533+12
192	207	【中国文字狱事件记录】\n日期：2017年10月21日\n地点：浙江台州\n当事人：王法正\n平台：朋友圈\n言论内容：”诋毁和辱骂党和国家及党和国家领导人的内容“\n处罚：行政拘留14日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:29.120884+12
193	208	【中国文字狱事件记录】\n日期：2017年10月21日\n地点：浙江台州\n当事人：王林友\n平台：朋友圈\n言论内容：发布“不当言论”和转发“不良言论”\n处罚：拘留14日\n法律文书：台公（椒）（西）行罚决字[2017]12263号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:29.167154+12
194	209	【中国文字狱事件记录】\n日期：2017年10月26日\n地点：江苏无锡\n当事人：孙某\n平台：贴吧\n言论内容：草特么，别人违章你怎么不管，就当给你买骨灰盒\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:29.215562+12
195	210	【中国文字狱事件记录】\n日期：2017年10月31日\n地点：福建三明\n当事人：詹华平\n平台：微信群\n言论内容：@文中贝这种奴才跟随脑残XXX（某位国家领导人）的挺中医药大旗，让愚昧无知的@慧海继续吃有害无益的中草药\n处罚：拘留10日\n法律文书：三公梅（徐碧）行罚决字（2017）00269号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:29.260356+12
196	211	【中国文字狱事件记录】\n日期：2017年11月01日\n地点：天津\n当事人：刘志勇\n平台：QQ\n言论内容：“辱骂中国国家领导人及外国国家元首、攻击、污蔑共产党、诋毁国家宗教政策的图片”\n处罚：有期徒刑1年\n法律文书：（2017）津0101刑初356号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:29.304379+12
197	212	【中国文字狱事件记录】\n日期：2017年11月01日\n地点：新疆伊犁\n当事人：木沙·阿依提拜\n身份：学者/教师\n平台：现实\n言论内容：举报多名校领导乱收费及教学管理方面等问题\n处罚：取消教师资格	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:29.353089+12
198	213	【中国文字狱事件记录】\n日期：2017年11月01日\n地点：陕西安康\n当事人：贾某\n平台：贴吧\n言论内容：爱德华门口发生砍人事件了\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:29.397054+12
199	214	【中国文字狱事件记录】\n日期：2017年11月01日\n地点：陕西安康\n当事人：汪某\n平台：贴吧\n言论内容：爱德华门口砍人，现场血腥（图片）\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:29.442937+12
200	215	【中国文字狱事件记录】\n日期：2017年11月03日\n地点：上海\n当事人：袁航宇\n平台：微信群\n言论内容：宋庆龄才是国母，彭丽媛是戏子、鸡，及反共言论\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:29.48859+12
201	216	【中国文字狱事件记录】\n日期：2017年11月04日\n地点：广西柳州\n当事人：石某\n平台：微信群\n言论内容：“侮辱民警”的言论\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:29.532479+12
202	217	【中国文字狱事件记录】\n日期：2017年11月06日\n地点：湖南邵阳\n当事人：释大成（佛教徒）\n平台：推特\n言论内容：转发郭文贵言论\n背景事件：郭文贵爆料事件\n处罚：有期徒刑1年8个月	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:29.577866+12
203	218	【中国文字狱事件记录】\n日期：2017年11月14日\n地点：湖南石门县\n当事人：张某\n平台：微信群\n言论内容：“辱骂村干部”\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:29.623114+12
204	219	【中国文字狱事件记录】\n日期：2017年11月14日\n地点：青海化隆县\n当事人：马某\n平台：网络\n言论内容：大量散布谣言，捏造虚假信息及图片，引发民族矛盾、破坏民族团结、伤害民族感情\n处罚：有期徒刑1年	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:29.669669+12
205	220	【中国文字狱事件记录】\n日期：2017年11月14日\n地点：江苏睢宁县\n当事人：贾耀祖\n平台：西祠胡同\n言论内容：《请睢宁县公安局领导同志教我们学法》；《请睢宁县国土局领导给与回复》等\n处罚：有期徒刑3年\n备注：二审维持原判\n法律文书：（2017）苏0324刑初205号；（2017）苏03刑终443号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:29.715535+12
206	221	【中国文字狱事件记录】\n日期：2017年11月17日\n地点：广东肇庆\n当事人：吴某等5人\n平台：微信群\n言论内容：“散布发电项目谣言煽动村民非法集会”\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:29.760445+12
207	222	【中国文字狱事件记录】\n日期：2017年11月25日\n地点：浙江新昌县\n当事人：王某\n平台：微信群\n言论内容：”称交警为狗的言论“\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:29.805955+12
208	223	【中国文字狱事件记录】\n日期：2017年11月28日\n地点：湖南岳阳\n当事人：彭宇华\n平台：QQ群\n言论内容：诋毁、攻击国家基本政治制度的文章、书籍、视频等\n处罚：有期徒刑7年	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:29.852153+12
209	224	【中国文字狱事件记录】\n日期：2017年11月28日\n地点：湖南岳阳\n当事人：李明哲（台籍）\n平台：QQ群\n言论内容：诋毁、攻击国家基本政治制度的文章、书籍、视频等\n处罚：有期徒刑5年	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:29.896185+12
210	225	【中国文字狱事件记录】\n日期：2017年12月01日\n地点：河南新密市\n当事人：刘某\n平台：微博\n言论内容：“辱骂交警的言论”\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:29.941213+12
211	226	【中国文字狱事件记录】\n日期：2017年12月01日\n地点：陕西佳县\n当事人：邵重国\n平台：推特\n言论内容：大量反动言论\n处罚：拘役5个月\n法律文书：（2017）陕0828刑初69号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:29.985134+12
212	228	【中国文字狱事件记录】\n日期：2017年12月05日\n地点：青海治多县\n当事人：巴叶旦正多杰\n平台：全民K歌\n言论内容：希望赛巴活佛不要在参加阿扎寺和贡萨寺的宗教活动，要说实话，不要见风使舵\n处罚：有期徒刑1年、缓刑2年\n备注：二审维持原判\n法律文书：（2017）青2724刑初9号；（2017）青27刑终19号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:30.075303+12
213	229	【中国文字狱事件记录】\n日期：2017年12月05日\n地点：内蒙古鄂尔多斯\n当事人：乌日古木拉\n平台：微信群\n言论内容：摩林河种畜场职工抢羊打人视频\n处罚：拘留9日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:30.121819+12
214	230	【中国文字狱事件记录】\n日期：2017年12月06日\n地点：湖南张家界\n当事人：周叙珍\n平台：微信群\n言论内容：刚才汉奸（指小区业委会主任）带队让她签名已被拒绝\n处罚：拘留5日\n备注：释放时群友献花迎接	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:30.16859+12
215	231	【中国文字狱事件记录】\n日期：2017年12月06日\n地点：重庆\n当事人：韩良\n平台：现实\n言论内容：（印于衣服）人权高于一切，一个国家良心的体现：全民免费医疗、教育、养老\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:30.216035+12
216	232	【中国文字狱事件记录】\n日期：2017年12月07日\n地点：福建晋江\n当事人：蔡某\n平台：微信群\n言论内容：（转发，视频）晋江、聚众斗殴、搞死了3个\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:30.260972+12
217	233	【中国文字狱事件记录】\n日期：2017年12月07日\n地点：江苏如东县\n当事人：钱小飞\n平台：濠滨论坛\n言论内容：如果让南通全民公投，决定是否加入日本，会有什么结果\n处罚：拘留8日\n法律文书：如公（开）行罚决字〔2017〕1416号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:30.306092+12
218	234	【中国文字狱事件记录】\n日期：2017年12月07日\n地点：天津\n当事人：张长虹（六四幸存者）\n平台：网络、现实\n言论内容：贴“纪念六四”、“平反六四”等六四主题大字报，并拍摄传到互联网\n背景事件：六四事件\n处罚：有期徒刑3年3个月\n备注：二审维持原判\n法律文书：（2017）津0113刑初493号；（2018）津01刑终105号-张长虹	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:30.350793+12
219	235	【中国文字狱事件记录】\n日期：2017年12月12日\n地点：宁夏银川\n当事人：罗某\n平台：快手\n言论内容：其踩踏成吉思汗画像的视频\n处罚：有期徒刑1年	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:30.394006+12
220	236	【中国文字狱事件记录】\n日期：2017年12月15日\n地点：甘肃永靖县\n当事人：王某\n平台：快手\n言论内容：“交警正常执法执勤视频，进行恶意谩骂”\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:30.438355+12
221	237	【中国文字狱事件记录】\n日期：2017年12月21日\n地点：浙江长兴县\n当事人：李君君（化名）\n平台：朋友圈\n言论内容：妈的……天天来烦你妈的个……\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:30.484142+12
222	238	【中国文字狱事件记录】\n日期：2017年12月21日\n地点：天津\n当事人：吴淦（超级低俗屠夫）\n平台：网络、现实\n言论内容：杀猪宝典、喝茶宝典、推墙思想、以及大量反共言论；组织抗议游行\n处罚：有期徒刑8年\n法律文书：（2016）津02刑初146号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:30.527515+12
223	239	【中国文字狱事件记录】\n日期：2017年12月23日\n地点：广东海丰\n当事人：郑某忠\n平台：朋友圈\n言论内容：评论某民警发布的走失儿童认领信息时使用“辱警言论”\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:30.569755+12
224	240	【中国文字狱事件记录】\n日期：2017年12月26日\n地点：四川开江县\n当事人：黄木权\n平台：天涯社区\n言论内容：撰写《宣汉县白皮书》，内容为指控宣汉县政府部门贪污腐败、徇私枉法，以及”侮辱“县领导\n处罚：有期徒刑1年6个月\n法律文书：（2017）川1723刑初148号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:30.613609+12
225	241	【中国文字狱事件记录】\n日期：2017年12月26日\n地点：四川开江县\n当事人：罗德明\n平台：天涯社区\n言论内容：发表《宣汉县白皮书》，内容为指控宣汉县政府部门贪污腐败、徇私枉法，以及”侮辱“县领导\n处罚：有期徒刑1年3个月\n法律文书：（2017）川1723刑初148号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:30.658038+12
226	242	【中国文字狱事件记录】\n日期：2017年12月27日\n地点：湖南湘潭县\n当事人：郭德建\n平台：微信群\n言论内容：“捏造事实而损害国家领导人员名誉、攻击国家领导人员的消息”\n处罚：拘留5日\n法律文书：潭公（天）决字〔2017〕第1813号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:30.702188+12
227	243	【中国文字狱事件记录】\n日期：2017年12月28日\n地点：浙江碧剑律师事务所\n当事人：吴有水\n身份：律师\n平台：微博、微信公众平台\n言论内容：再大的遥还不如人民日报啊、《不讲道理的”爱国“，就是耍流氓》等\n处罚：停职九个月	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:30.747124+12
228	244	【中国文字狱事件记录】\n日期：2017年12月28日\n地点：陕西洋县\n当事人：张某忠\n平台：现实\n言论内容：在房屋墙壁书写和公开演讲“诋毁党和国家领导人和曲解国家政策的标语”\n处罚：有期徒刑2年\n法律文书：（2017）陕0723刑初141号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:30.793511+12
229	245	【中国文字狱事件记录】\n日期：2018年01月05日\n地点：山东烟台\n当事人：姜某\n平台：QQ群\n言论内容：“丑化国家领导人的照片及消息”以及“攻击党和政府的音视频与言论”\n处罚：起诉（寻衅滋事罪）\n法律文书：烟芝检公刑诉〔2018〕32号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:30.841686+12
230	246	【中国文字狱事件记录】\n日期：2018年01月09日\n地点：辽宁沈阳\n当事人：臧宝涛\n平台：快手\n言论内容：发布和转发共8段侮辱交警的视频\n处罚：有期徒刑1年\n法律文书：（2018）辽0115刑初5号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:30.889131+12
231	247	【中国文字狱事件记录】\n日期：2018年01月10日\n地点：四川岳池县\n当事人：李立君\n平台：微信\n言论内容：“发布和转发污蔑党和国家领导人的言论”\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:30.931705+12
232	248	【中国文字狱事件记录】\n日期：2018年01月10日\n地点：安徽宁国\n当事人：赖某\n平台：论坛网站\n言论内容：警察有没有父母！那样推一个老人应该吗？你就是土匪\n处罚：拘留15日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:30.973452+12
233	249	【中国文字狱事件记录】\n日期：2018年01月11日\n地点：安徽宁国\n当事人：江某\n平台：网络\n言论内容：华泰医院警察打人了\n处罚：侦办中	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:31.017629+12
234	250	【中国文字狱事件记录】\n日期：2018年01月17日\n地点：黑龙江富裕县\n当事人：王某\n平台：快手\n言论内容：”辱骂交警“\n处罚：拘留10日、罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:31.059493+12
235	251	【中国文字狱事件记录】\n日期：2018年01月23日\n地点：河南台前县\n当事人：何远坤\n平台：QQ、微博\n言论内容：“大量含有党、政府和国家领导人的虚假信息”；转发境外网络信息至境内\n处罚：有期徒刑一年半	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:31.103989+12
236	252	【中国文字狱事件记录】\n日期：2018年01月28日\n地点：河北保定\n当事人：顾双全\n平台：微信\n言论内容：真有此事，吃人肉，还得喝人血．．．．．醒醒吧，老百姓！打着政府的名义欺压老百姓\n处罚：拘留5日\n法律文书：莲北公（百）行罚决字[2018]0031号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:31.148247+12
237	253	【中国文字狱事件记录】\n日期：2018年01月29日\n地点：山东烟台\n当事人：徐某\n平台：微信\n言论内容：“辱骂国家领导人以及诋毁中国共产党执政的言论”\n处罚：起诉（寻衅滋事罪）\n法律文书：烟开检公刑诉〔2018〕54号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:31.191781+12
238	254	【中国文字狱事件记录】\n日期：2018年01月31日\n地点：青海刚察县\n当事人：多某\n平台：微信群\n言论内容：两条语音信息。质疑政府在慰问活动中存在不按规定发放慰问品现象\n处罚：拘留9日、罚款200元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:31.234661+12
239	255	【中国文字狱事件记录】\n日期：2018年02月02日\n地点：内蒙古通辽\n当事人：潘彤\n平台：多个平台\n言论内容：其友杜红因举报通辽市领导巨额洗钱而被打击报复，家破人亡，其自己也因此被报复\n处罚：有期徒刑4年\n备注：二审维持原判\n法律文书：（2017）内0502刑初838号；（2018）内05刑终80号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:31.27828+12
240	256	【中国文字狱事件记录】\n日期：2018年02月06日\n地点：广东陆丰\n当事人：翁某仰\n平台：朋友圈\n言论内容：操你妈的交警狗…是不是没钱过年？\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:31.322662+12
241	257	【中国文字狱事件记录】\n日期：2018年02月07日\n地点：山西晋城\n当事人：李某\n平台：微信\n言论内容：“辱骂国家领导人”\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:31.367238+12
242	258	【中国文字狱事件记录】\n日期：2018年02月07日\n地点：内蒙古通辽\n当事人：杜红\n平台：网络、现实\n言论内容：上访举报通辽市领导巨额洗钱，以及在网上曝光自己因此受到打击报复\n处罚：有期徒刑4年\n备注：二审维持原判\n法律文书：（2017）内0502刑初738号；（2018）内05刑终92号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:31.412967+12
243	259	【中国文字狱事件记录】\n日期：2018年02月08日\n地点：四川广安\n当事人：黄某\n平台：快手\n言论内容：我还能够说啥子额，你妈XX，回来都着了\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:31.458207+12
244	260	【中国文字狱事件记录】\n日期：2018年02月11日\n地点：河北井陉县\n当事人：朱某\n平台：QQ空间、聊天群\n言论内容：转发”诽谤国家领导人的不实图文信息“\n处罚：有期徒刑1年2个月	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:31.503679+12
245	261	【中国文字狱事件记录】\n日期：2018年02月11日\n地点：四川成都\n当事人：谢俊彪\n平台：微信群\n言论内容：可能有大爷到双流视察\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:31.548829+12
246	262	【中国文字狱事件记录】\n日期：2018年02月11日\n地点：贵州安顺\n当事人：李明\n平台：微信群\n言论内容：公安部发出紧急通知，上访被拘留的可以起诉当地公安局\n处罚：拘留10日\n法律文书：安公西分（刑）行罚决字[2018]125号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:31.594958+12
247	263	【中国文字狱事件记录】\n日期：2018年02月11日\n地点：江苏南京\n当事人：史庭福\n平台：现实\n言论内容：穿着“勿忘六四”血衣，对路人演讲六四真相\n背景事件：六四事件\n处罚：有期徒刑1年、缓刑1年6个月	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:31.641443+12
248	264	【中国文字狱事件记录】\n日期：2018年02月12日\n地点：广东中山\n当事人：印明娟\n平台：QQ、微博、微信\n言论内容：中山市法院抢我手机、将我打晕，非法关押我丈夫；政府逼我儿子退学\n处罚：有期徒刑3年\n备注：二审维持原判\n法律文书：（2017）粤2072刑初2554号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:31.688022+12
249	265	【中国文字狱事件记录】\n日期：2018年02月14日\n地点：湖北武汉\n当事人：丁文婷\n平台：微博\n言论内容：武汉市委书记滚出武汉\n处罚：行拘10日转刑拘	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:31.731947+12
250	266	【中国文字狱事件记录】\n日期：2018年02月15日\n地点：山东临沂\n当事人：禚宝伟\n平台：微博\n言论内容：这个人（中国核潜艇之父）从科技上来说有贡献，作为一个儿子就是个畜生\n处罚：拘留10日、罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:31.773602+12
251	267	【中国文字狱事件记录】\n日期：2018年02月16日\n地点：四川广安\n当事人：范某\n平台：朋友圈\n言论内容：给大年初一还坚守岗位的狗致以崇高的敬意\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:31.815573+12
252	268	【中国文字狱事件记录】\n日期：2018年02月18日\n地点：河南郑州\n当事人：李某\n平台：朋友圈\n言论内容：太好了！又死一条狗（重庆民警杨雪峰）\n处罚：拘留14日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:31.857517+12
253	269	【中国文字狱事件记录】\n日期：2018年02月21日\n地点：黑龙江拜泉县\n当事人：侯某\n平台：快手\n言论内容：名人个粑粑，他（当地交警大队副队长贾大庆）就是个人名。他就是个狗\n处罚：拘留10日、罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:31.903077+12
254	270	【中国文字狱事件记录】\n日期：2018年02月21日\n地点：黑龙江拜泉县\n当事人：赵某\n平台：快手\n言论内容：对对，讲得对\n处罚：拘留10日、罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:31.949942+12
255	271	【中国文字狱事件记录】\n日期：2018年02月23日\n地点：河南郑州\n当事人：李某\n平台：网络\n言论内容：“辱警言论”\n处罚：拘留14日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:31.9941+12
256	272	【中国文字狱事件记录】\n日期：2018年02月24日\n地点：江西黎川县\n当事人：黄某\n平台：微信群\n言论内容：12点警察来了围了现场，一直现场两小时才死亡，警察就是来做个形式的，这条命就是经查拖死的\n背景事件：当地一名女子被楼上掉落的砖块砸死\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:32.036353+12
257	273	【中国文字狱事件记录】\n日期：2018年02月24日\n地点：江西永丰县\n当事人：李维某\n平台：微博\n言论内容：君埠乡政府存在强拆行为\n处罚：行政处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:32.077892+12
258	274	【中国文字狱事件记录】\n日期：2018年02月26日\n地点：江苏兴化\n当事人：徐祥\n身份：记者（曾任职新华社与南都日报\n平台：微博\n言论内容：举报官员骚扰女性\n处罚：拘留5日\n备注：后因调查腐败被刑拘	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:32.120492+12
259	275	【中国文字狱事件记录】\n日期：2018年03月01日\n地点：山东日照\n当事人：张某\n平台：微信\n言论内容：“不当言论”\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:32.163638+12
260	276	【中国文字狱事件记录】\n日期：2018年03月01日\n地点：新疆乌鲁木齐\n当事人：李发长\n平台：微信\n言论内容：转发关于习近平修宪的”辱骂他人“言论\n处罚：拘留5日\n法律文书：新公（河）行罚决字[2018]386号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:32.209013+12
261	277	【中国文字狱事件记录】\n日期：2018年03月02日\n地点：湖北武汉\n当事人：黄静怡、耿彩文\n平台：不详\n言论内容：录制倒车视频、讽刺习近平修宪\n处罚：拘留15日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:32.253992+12
262	278	【中国文字狱事件记录】\n日期：2018年03月03日\n地点：江西永丰县\n当事人：李振某\n平台：微博\n言论内容：（图片与视频）永丰县政府强拆百姓房屋\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:32.30072+12
263	279	【中国文字狱事件记录】\n日期：2018年03月03日\n地点：湖南祁东县\n当事人：吕耕轩\n平台：现实/贴于对联\n言论内容：惜天下，民穷天下乱，官贪江山亡\n处罚：拘留15日\n备注：后处罚被撤销\n法律文书：祁公（国）决字［2018］第0252号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:32.344713+12
264	280	【中国文字狱事件记录】\n日期：2018年03月04日\n地点：山东莒县\n当事人：宋某\n平台：贴吧\n言论内容：“虚假帖文”\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:32.388228+12
265	281	【中国文字狱事件记录】\n日期：2018年03月05日\n地点：湖南湘潭\n当事人：李杰\n平台：多个平台\n言论内容：《二十多名救灾英雄被湘潭市公安局强制抓走》\n处罚：有期徒刑8个月\n法律文书：（2017）湘0302刑初508号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:32.43016+12
266	282	【中国文字狱事件记录】\n日期：2018年03月08日\n地点：河北巨鹿县\n当事人：毕某\n平台：网络\n言论内容：“辱骂交警”的视频\n处罚：拘留10日、罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:32.470175+12
267	283	【中国文字狱事件记录】\n日期：2018年03月09日\n地点：湖北保康县\n当事人：赵兴明\n平台：QQ、微信等\n言论内容：”丑化、污蔑、侮辱党和国家形象“的信息\n处罚：拘留15日\n法律文书：保公（歇）行罚决字〔2018〕468号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:32.510331+12
268	284	【中国文字狱事件记录】\n日期：2018年03月09日\n地点：广东深圳\n当事人：李某\n平台：微博\n言论内容：他妈的哪个傻逼贴的；字写的比狗爬还难看也就只有做狗腿子的命；操他娘的狗杂种\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:32.551534+12
269	285	【中国文字狱事件记录】\n日期：2018年03月10日\n地点：山东日照\n当事人：杨某\n平台：微信群\n言论内容：“虚假信息”\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:32.59278+12
270	286	【中国文字狱事件记录】\n日期：2018年03月12日\n地点：浙江丽水\n当事人：周某\n平台：微信\n言论内容：狗日的，妈了个**\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:32.633877+12
271	287	【中国文字狱事件记录】\n日期：2018年03月13日\n地点：浙江松阳县\n当事人：周某\n平台：微信\n言论内容：松阳交警是不是****\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:32.677418+12
272	288	【中国文字狱事件记录】\n日期：2018年03月14日\n地点：浙江江山\n当事人：徐某\n平台：现实\n言论内容：（在法院公告栏和信访局窗户张贴）题为“我的冤案错案”的书面材料\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:32.722063+12
273	289	【中国文字狱事件记录】\n日期：2018年03月15日\n地点：湘潭大学\n当事人：成然\n身份：学者/教师\n平台：现实/课堂\n言论内容：引用外媒报道，发表“丑化党和国家领导人形象、曲解党和国家政策物等不当和错误言论“\n处罚：留党察看两年、降薪	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:32.765671+12
634	651	【中国文字狱事件记录】\n日期：2019年03月26日\n地点：甘肃临夏\n当事人：刘某\n平台：陌陌\n言论内容：雷锋山这边的交警支队一帮畜生\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:48.87884+12
274	290	【中国文字狱事件记录】\n日期：2018年03月19日\n地点：内蒙古赤峰\n当事人：张某\n平台：微博\n言论内容：这是一起典型的愚蠢执法人员办的愚蠢案例！愚昧无知的办案人员却称其为‘故意杀人案’！\n处罚：拘留12日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:32.809196+12
275	291	【中国文字狱事件记录】\n日期：2018年03月22日\n地点：甘肃文县\n当事人：赵某\n平台：朋友圈\n言论内容：文县城的交警老子日你妈，总有一天我要以牙还牙以血还血老子一定会找机会报复你们\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:32.851872+12
276	292	【中国文字狱事件记录】\n日期：2018年03月25日\n地点：贵州玉屏县\n当事人：张某\n平台：微信群\n言论内容：电费计算和用途存在欺骗；当地数千人拒交电费抗议\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:32.894902+12
277	293	【中国文字狱事件记录】\n日期：2018年03月26日\n地点：广东云浮\n当事人：林某\n平台：朋友圈\n言论内容：的交警居然穷到入村打劫\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:32.938629+12
278	294	【中国文字狱事件记录】\n日期：2018年03月27日\n地点：广东郁南县\n当事人：刘某\n平台：微信群\n言论内容：土匪进村拉快跑\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:32.980506+12
279	295	【中国文字狱事件记录】\n日期：2018年03月28日\n地点：山东青岛\n当事人：高某\n身份：退伍军人\n平台：现实/印于锦旗等\n言论内容：昔日为国杀敌流血，今日为生活所迫流泪——山东省青岛市参试参战老兵等口号于诉求\n处罚：有期徒刑2年\n备注：二审维持原判\n法律文书：（2017）鲁0202刑初367号；（2018）鲁02刑终272号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:33.024012+12
280	296	【中国文字狱事件记录】\n日期：2018年03月31日\n地点：辽宁沈阳\n当事人：赵某\n平台：今日头条\n言论内容：人民英雄，太给力了（别误会，我说的是杀警的壮士）\n背景事件：当地一名警察执行任务时遇袭死亡\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:33.142911+12
281	297	【中国文字狱事件记录】\n日期：2018年03月31日\n地点：辽宁沈阳\n当事人：孙某\n平台：今日头条\n言论内容：干得好、干得漂亮、警察叔叔干死了\n背景事件：当地一名警察执行任务时遇袭死亡\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:33.181172+12
282	298	【中国文字狱事件记录】\n日期：2018年03月31日\n地点：江西弋阳县\n当事人：杨某\n平台：微博\n言论内容：死的好，2个抓一个都抓不了，我们供着他干嘛？还是歹徒练了武功？这样也能当警察\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:33.220609+12
283	299	【中国文字狱事件记录】\n日期：2018年04月01日\n地点：北京建筑大学\n当事人：许传青\n身份：学者/教师\n平台：现实/课堂\n言论内容：“将日本民族和中华民族进行不恰当对比，宣泄个人不满”\n处罚：开除	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:33.260233+12
284	300	【中国文字狱事件记录】\n日期：2018年04月02日\n地点：江西黎川县\n当事人：熊某\n平台：微信群\n言论内容：一则笑话，暗讽交警不是人养的\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:33.304829+12
285	301	【中国文字狱事件记录】\n日期：2018年04月02日\n地点：福建南安市\n当事人：尤某欣\n平台：微信群\n言论内容：“辱骂交警”的言论\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:33.352188+12
286	302	【中国文字狱事件记录】\n日期：2018年04月02日\n地点：江西兴国县\n当事人：张某\n平台：微博\n言论内容：一张老鼠被架起来的照片，图中文字“兴国交警某某，这就是你的下场”，兴国交警以权谋私，欺压百姓\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:33.395949+12
287	303	【中国文字狱事件记录】\n日期：2018年04月02日\n地点：浙江温州\n当事人：王某、姜缪\n平台：网络\n言论内容：警察打人、李明辉的妻子自杀\n背景事件：温州工人李明辉猝死，导致家人抗议\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:33.441078+12
288	304	【中国文字狱事件记录】\n日期：2018年04月03日\n地点：湖北武穴\n当事人：张某\n平台：微博\n言论内容：底层老百姓岂敢无缘无故杀害民警？或许另有隐情，是警察贼喊捉贼\n处罚：拘留15日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:33.485532+12
289	305	【中国文字狱事件记录】\n日期：2018年04月03日\n地点：浙江温州\n当事人：廖某\n平台：微博\n言论内容：交警狗该打，天天出来抢钱\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:33.529409+12
290	306	【中国文字狱事件记录】\n日期：2018年04月03日\n地点：甘肃静宁县\n当事人：马某\n平台：快手\n言论内容：辱骂城管的视频\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:33.574461+12
291	307	【中国文字狱事件记录】\n日期：2018年04月08日\n地点：江西赣州\n当事人：杨某\n平台：朋友圈\n言论内容：无凭无据；什么证据都没有你说风就是风，说雨就是雨；（脏话）\n背景事件：其父被警察处罚\n处罚：拘留7日，罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:33.621037+12
292	308	【中国文字狱事件记录】\n日期：2018年04月08日\n地点：江西南昌\n当事人：刘某\n平台：朋友圈\n言论内容：交警执法视频以及“辱警语言”\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:33.668325+12
293	309	【中国文字狱事件记录】\n日期：2018年04月09日\n地点：甘肃永靖县\n当事人：孔某\n平台：快手\n言论内容：评论某段交警执勤视频时对警察进行”诋毁和辱骂“\n处罚：拘留10日、罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:33.711605+12
294	310	【中国文字狱事件记录】\n日期：2018年04月09日\n地点：河南修武县\n当事人：丁某\n平台：快手\n言论内容：真让爷爷猜中了，大清早堵车不是好兆头，快到家了孙子给个罚款单\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:33.765345+12
295	311	【中国文字狱事件记录】\n日期：2018年04月10日\n地点：浙江杭州\n当事人：张杰\n平台：微信群\n言论内容：这个社会被习皇玩坏了\n处罚：不明	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:33.811574+12
296	312	【中国文字狱事件记录】\n日期：2018年04月11日\n地点：山西吕梁\n当事人：张某海\n平台：微博\n言论内容：“诋毁政府”\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:33.858983+12
297	313	【中国文字狱事件记录】\n日期：2018年04月11日\n地点：甘肃静宁县\n当事人：戴某\n平台：朋友圈\n言论内容：辱骂运政人员的视频\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:33.907347+12
298	314	【中国文字狱事件记录】\n日期：2018年04月11日\n地点：湖南株洲\n当事人：孟铭\n平台：现实/举牌\n言论内容：实现自由民主，中国或成最大赢家\n处罚：拘留8日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:33.958686+12
299	315	【中国文字狱事件记录】\n日期：2018年04月11日\n地点：湖南株洲\n当事人：陈小平\n平台：现实/举牌\n言论内容：实现自由民主，中国或成最大赢家\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:34.010107+12
300	316	【中国文字狱事件记录】\n日期：2018年04月11日\n地点：湖南株洲\n当事人：吴明\n平台：现实/举牌\n言论内容：实现自由民主，中国或成最大赢家\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:34.065262+12
301	317	【中国文字狱事件记录】\n日期：2018年04月11日\n地点：湖南株洲\n当事人：郭闽\n平台：现实/举牌\n言论内容：实现自由民主，中国或成最大赢家\n处罚：拘留12日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:34.139418+12
302	318	【中国文字狱事件记录】\n日期：2018年04月11日\n地点：湖南株洲\n当事人：李飞\n平台：现实/举牌\n言论内容：实现自由民主，中国或成最大赢家\n处罚：传唤警告	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:34.189959+12
303	319	【中国文字狱事件记录】\n日期：2018年04月12日\n地点：广东湛江\n当事人：卜永梓\n平台：朋友圈\n言论内容：重量级的国家领导人都已经搬起石头砸了自己的脚，行动不便，目前都在家养脚伤\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:34.236647+12
304	320	【中国文字狱事件记录】\n日期：2018年04月12日\n地点：四川自贡\n当事人：陈某\n平台：论坛网站\n言论内容：警察看到警车压线闯红灯没有被罚，交警和抢钱的土匪有什么区别\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:34.285694+12
305	321	【中国文字狱事件记录】\n日期：2018年04月15日\n地点：四川遂宁\n当事人：陈某（未成年）\n平台：微博\n言论内容：希望给北京也来一个（美国空袭）\n处罚：警方带走接受调查，后续不明	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:34.3346+12
306	322	【中国文字狱事件记录】\n日期：2018年04月19日\n地点：河南洛阳\n当事人：李某亮\n平台：朋友圈\n言论内容：（视频）这排车被狗咬了，交警又出来赚外快啦\n处罚：拘留10日、罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:34.387862+12
307	323	【中国文字狱事件记录】\n日期：2018年04月19日\n地点：河南泌阳县\n当事人：田雨\n平台：网络\n言论内容：指控警察对其相亲对象不退还彩礼一事不立案，称其为“黑警”\n处罚：有期徒刑1年2个月\n法律文书：（2018）豫1726刑初75号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:34.427358+12
308	324	【中国文字狱事件记录】\n日期：2018年04月20日\n地点：内蒙古镶黄旗\n当事人：贺生斌\n平台：微博\n言论内容：镶黄旗公安局贪污腐败\n处罚：拘留5日\n法律文书：镶公（网）行罚决字[2018]23号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:34.465512+12
309	325	【中国文字狱事件记录】\n日期：2018年04月20日\n地点：河北故城县\n当事人：张某\n平台：朋友圈\n言论内容：“侮辱派出所户籍工作人员的视频”\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:34.502089+12
310	326	【中国文字狱事件记录】\n日期：2018年04月21日\n地点：浙江丽水\n当事人：彭某\n平台：朋友圈\n言论内容：我就一个草泥马，大清早被狗抓，晦气，今天不出门\n处罚：拘留8日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:34.540461+12
311	327	【中国文字狱事件记录】\n日期：2018年04月23日\n地点：湖北武汉\n当事人：肖明\n平台：微信群\n言论内容：国家领导人相关信息\n处罚：拘留10日\n法律文书：硚公（新）行罚决字〔2018〕11741号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:34.581655+12
312	328	【中国文字狱事件记录】\n日期：2018年04月23日\n地点：河南洛阳\n当事人：张小平张智斌夫妇\n平台：微博\n言论内容：举报洛阳市长与另一名厅级干部\n处罚：刑事拘留与行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:34.620639+12
313	329	【中国文字狱事件记录】\n日期：2018年04月24日\n地点：上海\n当事人：张某\n平台：某直播平台\n言论内容：”美化日本军国主义的言论“\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:34.658854+12
314	330	【中国文字狱事件记录】\n日期：2018年04月25日\n地点：湖北武汉\n当事人：付利书\n平台：微信群\n言论内容：习大大来汉\n处罚：拘留5日\n法律文书：硚公（新）行罚决字（2018）11824号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:34.69614+12
315	331	【中国文字狱事件记录】\n日期：2018年04月25日\n地点：山西交城县\n当事人：吕晓光\n平台：朋友圈\n言论内容：国家领导人被警察抓捕的照片以及说他是中国顶级黑社会老大等抨击国家领导人言论\n处罚：批捕（后因发现其患有精神分裂症而释放）	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:34.735486+12
316	332	【中国文字狱事件记录】\n日期：2018年04月27日\n地点：陕西铜川\n当事人：唐某\n平台：微博\n言论内容：（交警暴力执法视频）继上次青岗岭出那么大事，这群狗难道还是这样执法？\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:34.775717+12
317	333	【中国文字狱事件记录】\n日期：2018年04月28日\n地点：广东深圳\n当事人：黄美娟\n平台：朋友圈\n言论内容：转发关于乌坎村抗议内容\n背景事件：乌坎抗议事件\n处罚：被失踪	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:34.816061+12
318	334	【中国文字狱事件记录】\n日期：2018年04月29日\n地点：河北衡水\n当事人：王某、李某\n平台：现实/贴大字报\n言论内容：指控当地村官贪污，以及“侮辱”\n处罚：拘留9日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:34.856463+12
319	335	【中国文字狱事件记录】\n日期：2018年05月01日\n地点：中南财经政法大学\n当事人：翟桔红\n身份：学者/教师\n平台：现实/课堂\n言论内容：批评习近平废除任期限制\n处罚：开除、吊销教师资格证	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:34.897556+12
320	336	【中国文字狱事件记录】\n日期：2018年05月08日\n地点：广东吴川市\n当事人：李某\n平台：微信群\n言论内容：“负面不当言论”\n处罚：批评教育	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:34.939396+12
321	337	【中国文字狱事件记录】\n日期：2018年05月08日\n地点：辽宁沈阳\n当事人：邓某\n平台：微博\n言论内容：两名民警引诱少女卖淫、迫害威胁群众等共4万多条涉警不实负面言论\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:34.980283+12
322	338	【中国文字狱事件记录】\n日期：2018年05月10日\n地点：广东佛山\n当事人：梁某宾（未成年）\n平台：微博、微信\n言论内容：死得好；就知道欺负百姓\n处罚：行政拘留不执行	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:35.021041+12
323	339	【中国文字狱事件记录】\n日期：2018年05月11日\n地点：浙江丽水\n当事人：钭某、应某、章某\n平台：朋友圈\n言论内容：交警打人视频及“以前国民党也不敢这样，现在共产党是极度膨胀了”\n处罚：拘留6-8日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:35.064023+12
324	340	【中国文字狱事件记录】\n日期：2018年05月11日\n地点：浙江温州\n当事人：李某\n平台：朋友圈\n言论内容：狗子又出来赚钱了；cnm；我操你妈一晚贴了两次我祝你全家今晚死光光\n处罚：拘留8日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:35.10832+12
325	341	【中国文字狱事件记录】\n日期：2018年05月12日\n地点：广东陆河县\n当事人：罗林曲\n平台：微信\n言论内容：交警执勤视频及“辱骂交警的言论”\n处罚：行政处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:35.150961+12
326	342	【中国文字狱事件记录】\n日期：2018年05月13日\n地点：广东陆河县\n当事人：廖振凯\n平台：微信\n言论内容：交警执勤视频及“辱骂交警的言论”\n处罚：行政处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:35.194201+12
327	343	【中国文字狱事件记录】\n日期：2018年05月15日\n地点：江苏泗洪县\n当事人：孙某\n平台：微信群\n言论内容：狗仔队 狗仔队 泗洪狗仔队 ……（指城管）\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:35.240051+12
328	344	【中国文字狱事件记录】\n日期：2018年05月17日\n地点：宁夏银川\n当事人：蒋某\n平台：微博\n言论内容：董存瑞活该炸死，黄继光活该被枪打死，因为这样是没有意义的，如果我被抓了就说明公民没有言论自由\n背景事件：中国英烈保护法通过\n处罚：拘留10日，罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:35.289026+12
329	345	【中国文字狱事件记录】\n日期：2018年05月22日\n地点：青海玉树\n当事人：扎西文色\n平台：纽约时报\n言论内容：接受纽约时报驻华记者采访，与之拍摄和制作视频《一个藏人的追求正义之路》\n处罚：有期徒刑5年	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:35.335188+12
330	346	【中国文字狱事件记录】\n日期：2018年05月23日\n地点：江西高安市\n当事人：袁某\n平台：朋友圈\n言论内容：交警执勤视频，其中他说了“侮辱性”词语\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:35.379599+12
331	347	【中国文字狱事件记录】\n日期：2018年05月24日\n地点：山西芮城县\n当事人：李某\n平台：微信\n言论内容：一段“侮辱交警”的视频\n处罚：拘留10日，罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:35.43716+12
332	348	【中国文字狱事件记录】\n日期：2018年05月24日\n地点：内蒙古额尔古纳市\n当事人：张喜莲\n身份：公职人员/事业单位人员\n平台：微信群\n言论内容：选委会用钱买就行，钱是万能的；不用选，书记说谁行谁就行\n处罚：党内严重警告	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:35.482696+12
333	349	【中国文字狱事件记录】\n日期：2018年05月24日\n地点：吉林前郭县\n当事人：王晓东\n平台：推特\n言论内容：大量“虚假信息”，并被网络媒体转载和大量网民点赞\n处罚：有期徒刑2年\n备注：2019/10/29减刑4个月\n法律文书：（2018）吉0721刑初241号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:35.523345+12
334	350	【中国文字狱事件记录】\n日期：2018年05月25日\n地点：天津商业大学\n当事人：王伟（王博士的精神家园）\n身份：学者/教师\n平台：微博\n言论内容：“诋毁党的领袖、抹黑政府形象的过激言论”\n处罚：记过、停职	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:35.562772+12
335	351	【中国文字狱事件记录】\n日期：2018年05月30日\n地点：宁夏同心县\n当事人：田自存\n身份：中共党员\n平台：微博\n言论内容：辱骂春节习俗为“特色猪圈文化传承”，“支那”\n处罚：拘留10日，留党察看一年	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:35.600676+12
336	352	【中国文字狱事件记录】\n日期：2018年05月30日\n地点：湖南株洲\n当事人：何峻辉\n平台：现实\n言论内容：举牌纪念六四\n背景事件：六四事件\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:35.640366+12
337	353	【中国文字狱事件记录】\n日期：2018年06月01日\n地点：厦门大学\n当事人：尤盛东\n身份：学者/教师\n平台：现实/课堂\n言论内容：某党就是发国难财上台等”偏激言论“\n处罚：解聘	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:35.680269+12
338	354	【中国文字狱事件记录】\n日期：2018年06月02日\n地点：河北唐山\n当事人：王久存\n平台：微信群\n言论内容：呼吁村民抵制签订拆迁协议\n处罚：拘留7日\n法律文书：唐公北（果）行罚决字【2018】0486号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:35.721493+12
339	355	【中国文字狱事件记录】\n日期：2018年06月02日\n地点：河北唐山\n当事人：于爽\n平台：微信群\n言论内容：“呼吁村民抵制签订拆迁协议，散布对拆迁的不满言论，诋毁拆迁政策，抹黑政府形象”\n处罚：拘留7日\n法律文书：唐公北（果）行罚决［2018］0487号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:35.762389+12
340	356	【中国文字狱事件记录】\n日期：2018年06月02日\n地点：湖南株洲\n当事人：陈思明\n平台：现实\n言论内容：举牌纪念六四\n背景事件：六四事件\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:35.80335+12
341	357	【中国文字狱事件记录】\n日期：2018年06月02日\n地点：广西梧州\n当事人：农定财\n平台：现实\n言论内容：在T恤上印“铭记八酒六四”\n背景事件：六四事件\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:35.845464+12
342	359	【中国文字狱事件记录】\n日期：2018年06月05日\n地点：湖北武汉\n当事人：张毅\n平台：朋友圈\n言论内容：刘晓波衣冠冢照片\n背景事件：刘晓波之死\n处罚：刑拘改行拘5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:35.930763+12
343	360	【中国文字狱事件记录】\n日期：2018年06月05日\n地点：浙江杭州\n当事人：张某\n平台：朋友圈\n言论内容：（交警图片）狼狗聚会\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:35.973603+12
344	361	【中国文字狱事件记录】\n日期：2018年06月06日\n地点：贵州铜仁\n当事人：唐僚\n平台：微信群\n言论内容：六四敏感言论、纪念六四内容\n背景事件：六四事件\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:36.01534+12
345	362	【中国文字狱事件记录】\n日期：2018年06月06日\n地点：河北大城\n当事人：衡某\n平台：微信群\n言论内容：“辱骂交警的视频”\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:36.057866+12
346	363	【中国文字狱事件记录】\n日期：2018年06月06日\n地点：湖南岳林律师事务所\n当事人：杨金柱\n身份：律师\n平台：网络、现实\n言论内容：代理敏感案件、发布不当言论等\n处罚：吊销律师资格证\n备注：2019年3月25日皈依佛门	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:36.103372+12
347	364	【中国文字狱事件记录】\n日期：2018年06月11日\n地点：山西太原\n当事人：陈某明\n平台：朋友圈\n言论内容：哎！200大洋喂了狗了！就当给汪汪队买狗粮了～\n处罚：批评教育	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:36.144929+12
348	365	【中国文字狱事件记录】\n日期：2018年06月13日\n地点：江西赣州\n当事人：赖某\n平台：微信群\n言论内容：题为“会昌县庄口派出所民警对一位83岁老人动手动脚”的视频\n处罚：拘留6日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:36.186446+12
349	366	【中国文字狱事件记录】\n日期：2018年06月14日\n地点：宁夏银川\n当事人：金成国\n平台：微信群\n言论内容：国外自由民主资讯\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:36.227434+12
350	367	【中国文字狱事件记录】\n日期：2018年06月15日\n地点：河南浚县\n当事人：姜生珍\n平台：网络\n言论内容：《实名举报河南浚县卫贤镇尚村村霸申宝堂欺压百姓无人问，谁在背后撑腰》等\n处罚：有期徒刑2年6个月\n备注：二审维持原判\n法律文书：（2018）豫0621刑初87号；（2018）豫06刑终117号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:36.268737+12
635	652	【中国文字狱事件记录】\n日期：2019年03月27日\n地点：广西百色\n当事人：覃某\n平台：微信群\n言论内容：这帮狗东西又捞了一笔钱\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:48.919325+12
351	368	【中国文字狱事件记录】\n日期：2018年06月18日\n地点：山东无棣县\n当事人：邵某爱\n平台：微信群\n言论内容：今天交警队长说：有父亲的都回家给爹过节。有个交警问：没有的呢？队长说：XXX\n处罚：拘留5日，罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:36.310616+12
352	369	【中国文字狱事件记录】\n日期：2018年06月18日\n地点：安徽当涂县\n当事人：孙某\n平台：朋友圈\n言论内容：“辱骂交警”\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:36.351388+12
353	370	【中国文字狱事件记录】\n日期：2018年06月20日\n地点：甘肃宕昌县\n当事人：张某\n平台：朋友圈\n言论内容：哎！这些杂种。操…（指交警）\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:36.39227+12
354	371	【中国文字狱事件记录】\n日期：2018年06月21日\n地点：江苏扬州\n当事人：李某（化名）\n平台：朋友圈\n言论内容：有谁认识这两个XX？其它多条“辱警信息”\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:36.431916+12
355	372	【中国文字狱事件记录】\n日期：2018年06月22日\n地点：陕西渭南\n当事人：徐天赐\n平台：QQ群\n言论内容：”辱骂国家领导人及政府“的言论\n处罚：拘留10日\n法律文书：渭经公（辛）行罚决字[2018]98号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:36.469791+12
356	373	【中国文字狱事件记录】\n日期：2018年06月23日\n地点：江西宁都县\n当事人：刘某\n平台：微信公众平台\n言论内容：《拆老宅，拆不出一个社会主义》，内容为指控政府强拆，以及此前发布的“敏感、虚假、负面“的信息\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:36.509826+12
357	374	【中国文字狱事件记录】\n日期：2018年06月24日\n地点：广东梅州\n当事人：钟某\n平台：微信群\n言论内容：开车英雄，点个赞；只要伤的不是百姓，关我鸟是，公安多死几个，就拍手呢\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:36.551402+12
358	375	【中国文字狱事件记录】\n日期：2018年06月26日\n地点：江苏兴化\n当事人：徐祥\n身份：记者（曾任职新华社与南都日报\n平台：微博、现实\n言论内容：调查与揭露官员腐败现象\n处罚：刑事拘留\n备注：曾因举报官员被拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:36.587577+12
359	376	【中国文字狱事件记录】\n日期：2018年06月27日\n地点：浙江仙居县\n当事人：王某\n平台：微信群\n言论内容：好多狗；共产党是条狗；共产党没有文化，没有教养，做事一刀切，像条疯狗\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:36.624636+12
360	377	【中国文字狱事件记录】\n日期：2018年06月27日\n地点：湖南邵阳\n当事人：彭佩玉（彭松华）\n平台：网络\n言论内容：《讨习檄文》\n处罚：拘留15日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:36.662486+12
361	378	【中国文字狱事件记录】\n日期：2018年06月28日\n地点：甘肃徽县\n当事人：龙克海\n平台：微信\n言论内容：歪曲、丑化中国共产党和国家领导人的图文\n处罚：拘留10日\n法律文书：徽公（国）行罚决字【2018】01号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:36.703261+12
362	379	【中国文字狱事件记录】\n日期：2018年06月28日\n地点：吉林伊通县\n当事人：赵某\n平台：微信群\n言论内容：“辱骂与挑衅群内民警”\n处罚：拘留7日、罚款300元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:36.745501+12
363	380	【中国文字狱事件记录】\n日期：2018年06月28日\n地点：山东济宁\n当事人：季某\n平台：推特、贴吧\n言论内容：”捏造散布虚假信息，随意贬损诽谤国家领导人“\n处罚：有期徒刑9个月\n法律文书：（2018）鲁0811刑初489号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:36.78686+12
364	381	【中国文字狱事件记录】\n日期：2018年07月03日\n地点：江西南昌\n当事人：吴某\n平台：微博\n言论内容：终于有一个找当事人报复而不是报复普通老百姓的了，为他点赞\n背景事件：石家庄火车站发生一起袭警案\n处罚：被查获，后续未知	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:36.827689+12
365	382	【中国文字狱事件记录】\n日期：2018年07月03日\n地点：黑龙江齐齐哈尔\n当事人：刘某\n平台：朋友圈\n言论内容：我就操你妈了逼的齐齐哈尔交警队！操你妈的\n处罚：拘留10日、罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:36.868548+12
366	383	【中国文字狱事件记录】\n日期：2018年07月03日\n地点：四川岳池县\n当事人：李立君\n平台：朋友圈\n言论内容：“侮辱党和国家的言论”\n处罚：拘留15日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:36.909202+12
367	384	【中国文字狱事件记录】\n日期：2018年07月03日\n地点：陕西志丹县\n当事人：郝某与白某\n平台：网络\n言论内容：“对国家机关产生不良影响的虚假信息”\n处罚：批捕	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:36.949716+12
368	385	【中国文字狱事件记录】\n日期：2018年07月04日\n地点：江苏镇江\n当事人：李某（P2P受害者）\n平台：微信群\n言论内容：组织维权示威\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:36.990982+12
369	386	【中国文字狱事件记录】\n日期：2018年07月04日\n地点：上海\n当事人：董瑶琼\n平台：推特\n言论内容：（口述直播）反对习近平独裁，反对中国共产党（向习近平画像泼墨）\n处罚：被关押至湖南株洲精神病院\n备注：2019/11/19获释	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:37.032993+12
370	387	【中国文字狱事件记录】\n日期：2018年07月04日\n地点：天津\n当事人：王广元\n平台：微信、微博\n言论内容：关于自己房屋被强拆的维权视频\n处罚：有期徒刑10个月\n法律文书：（2018）津0112刑初99号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:37.076273+12
371	388	【中国文字狱事件记录】\n日期：2018年07月06日\n地点：江西抚州\n当事人：乐某\n平台：微信群\n言论内容：（救灾死亡官员）死得好、美国打过来，我愿当汉奸\n处罚：拘留6日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:37.12039+12
372	389	【中国文字狱事件记录】\n日期：2018年07月06日\n地点：贵州凯里\n当事人：翟某\n平台：朋友圈\n言论内容：感谢交警蜀黍的奖励，稍后我再问候你的全家以及你的祖宗十八代\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:37.163015+12
373	390	【中国文字狱事件记录】\n日期：2018年07月08日\n地点：山西忻州\n当事人：董斌（湖北文理学院客座研究员）\n平台：网络、现实\n言论内容：创建全球公民党、发起声援董瑶琼活动、异见言论\n处罚：有期徒刑8个月\n法律文书：（2018）晋0902刑初342号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:37.20689+12
374	391	【中国文字狱事件记录】\n日期：2018年07月10日\n地点：国家自然资源部\n当事人：张晓山（副部级官员）\n身份：党政官员\n平台：微信群\n言论内容：”妄议中央，抹黑党国“\n处罚：立案调查（后续不明）	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:37.248699+12
375	392	【中国文字狱事件记录】\n日期：2018年07月10日\n地点：河北赞皇县\n当事人：许某\n平台：微信群\n言论内容：一则“诋毁政府”的顺口溜\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:37.291616+12
376	393	【中国文字狱事件记录】\n日期：2018年07月16日\n地点：甘肃会宁县\n当事人：杨某君\n平台：微信群\n言论内容：其本人脚踢警察塑像并对其“辱骂”的视频\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:37.335271+12
377	394	【中国文字狱事件记录】\n日期：2018年07月18日\n地点：广东佛山\n当事人：杨光汉\n平台：现实/举牌\n言论内容：今天是清明节，深切怀念：林昭、刘晓波、杨天水、彭明；反对独裁、反对伪宪法；反对连任，反对终身\n处罚：有期徒刑6个月、缓刑1年6个月\n法律文书：（2018）粤0605刑初2256号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:37.378744+12
378	395	【中国文字狱事件记录】\n日期：2018年07月19日\n地点：江西上饶县\n当事人：黄某\n平台：朋友圈\n言论内容：这两个狗儿子……狗仗人势\n处罚：查处	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:37.420585+12
379	396	【中国文字狱事件记录】\n日期：2018年07月22日\n地点：黑龙江伊春\n当事人：吴某\n平台：微信群\n言论内容：鐵力局鹿鳴礦業將尾礦蓄水池化學污水排放到河中，鐵力水源被山上礦業排放化學污水污染\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:37.465981+12
380	397	【中国文字狱事件记录】\n日期：2018年07月23日\n地点：江苏扬州\n当事人：王国扬（境外人士）\n平台：QQ、推特、微信等\n言论内容：郭文贵爆料内容\n背景事件：郭文贵爆料事件\n处罚：有期徒刑1年2个月\n法律文书：（2018）苏1091刑初84号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:37.518473+12
381	398	【中国文字狱事件记录】\n日期：2018年07月27日\n地点：广西贵港\n当事人：谭军\n平台：推特\n言论内容：疫苗案有关视频\n背景事件：山东毒疫苗事件\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:37.562248+12
382	399	【中国文字狱事件记录】\n日期：2018年08月01日\n地点：江苏常州\n当事人：吕千荣\n平台：多个平台\n言论内容：多篇政论文章\n处罚：强制关押在精神病院65天	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:37.606774+12
383	400	【中国文字狱事件记录】\n日期：2018年08月01日\n地点：贵州大学\n当事人：杨绍政\n身份：学者/教师\n平台：微信、现实/课堂\n言论内容：批评公款养党\n处罚：开除、限制出境	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:37.649473+12
384	401	【中国文字狱事件记录】\n日期：2018年08月01日\n地点：湖南吉首\n当事人：邹某（贫困户/孕妇）\n平台：湖南政府举报平台\n言论内容：举报村支书截留扶贫款项\n处罚：口头警告	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:37.691944+12
385	402	【中国文字狱事件记录】\n日期：2018年08月01日\n地点：江苏睢宁县\n当事人：赵某\n平台：朋友圈\n言论内容：又这二个憨*， 再乱贴乱画…… \n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:37.734132+12
386	403	【中国文字狱事件记录】\n日期：2018年08月02日\n地点：甘肃高台县\n当事人：杨某\n平台：微信\n言论内容：“辱骂国家行政机关”\n处罚：拘留15日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:37.778022+12
387	404	【中国文字狱事件记录】\n日期：2018年08月02日\n地点：四川成都\n当事人：黄某\n平台：腾讯新闻\n言论内容：其实警察和小偷是一伙的，叫奥迪来帮小偷逃走，结果把他撞死了\n处罚：有期徒刑8个月\n法律文书：（2018）川0114刑初421号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:37.821675+12
388	405	【中国文字狱事件记录】\n日期：2018年08月03日\n地点：河北安平县\n当事人：王某\n平台：朋友圈\n言论内容：哪个狗xx给我贴的条，就停了一分钟，你个xx的真xx的快\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:37.864382+12
389	406	【中国文字狱事件记录】\n日期：2018年08月03日\n地点：浙江新昌县\n当事人：黄某\n平台：朋友圈\n言论内容：（视频）城管打人（警方称内容为断章取义）\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:37.906856+12
390	407	【中国文字狱事件记录】\n日期：2018年08月05日\n地点：内蒙古\n当事人：郭凯\n平台：网络\n言论内容：《内蒙古大宗土地违法问题引发官民关系趋于紧张》\n处罚：已审、罪名成立、判决不详	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:37.950997+12
391	408	【中国文字狱事件记录】\n日期：2018年08月06日\n地点：浙江宁波\n当事人：朱某\n平台：微博\n言论内容：死的好，活该；怎么会是施救，明明是抓捕过程中体力不支，平时不好好锻炼身体，活该\n处罚：刑事拘留，（9/7正式批捕）	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:37.994297+12
392	409	【中国文字狱事件记录】\n日期：2018年08月08日\n地点：浙江苍南\n当事人：章某\n平台：微博\n言论内容：鬼子（指政府人员）进村了，连七十八十的老人都打，老人都被打去世了\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:38.040129+12
393	410	【中国文字狱事件记录】\n日期：2018年08月09日\n地点：湖南长沙\n当事人：许某\n平台：不详\n言论内容：“侮辱牺牲民警言论”\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:38.082796+12
394	411	【中国文字狱事件记录】\n日期：2018年08月10日\n地点：广西北流\n当事人：梁某宾\n平台：QQ、微博、微信\n言论内容：“侮辱刘贵斌、沈华祥等牺牲民警辅警”\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:38.125623+12
395	1888	【中国文字狱事件记录】\n日期：2020年03月13日\n地点：山东泰安\n当事人：廉某\n平台：不详\n言论内容：虚构事实\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:50.973057+12
396	412	【中国文字狱事件记录】\n日期：2018年08月10日\n地点：山东潍坊\n当事人：刘某\n平台：网络 \n言论内容：“在潍坊高新区金马路玉清街路口电死三个人”\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:38.169621+12
397	413	【中国文字狱事件记录】\n日期：2018年08月11日\n地点：山东青岛\n当事人：徐某\n平台：微信群\n言论内容：（视频）青岛崂山仰口隧道出现泥石流\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:38.21227+12
398	414	【中国文字狱事件记录】\n日期：2018年08月11日\n地点：山东桓台县\n当事人：罗某\n平台：抖音\n言论内容：（视频）少海路塌方\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:38.259734+12
399	415	【中国文字狱事件记录】\n日期：2018年08月11日\n地点：山东东营\n当事人：李某\n平台：网络\n言论内容：河口某小区有人在水中被电死\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:38.304105+12
400	416	【中国文字狱事件记录】\n日期：2018年08月13日\n地点：江苏南通\n当事人：李某\n平台：微信群\n言论内容：土匪（交警）在查酒驾\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:38.346572+12
401	417	【中国文字狱事件记录】\n日期：2018年08月13日\n地点：甘肃永靖县\n当事人：马某\n平台：快手\n言论内容：（视频）出大事了输液一针打死了；完蛋了，这一家医院不敢住院了\n处罚：拘留7日\n备注：视频仅被浏览6次	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:38.388199+12
402	418	【中国文字狱事件记录】\n日期：2018年08月13日\n地点：山西太原\n当事人：吴某\n平台：朋友圈\n言论内容：警察草泥马～吃个早饭给我贴上了\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:38.43017+12
403	419	【中国文字狱事件记录】\n日期：2018年08月16日\n地点：安徽马鞍山\n当事人：杨某\n平台：微博\n言论内容：安倍首相是我亲爹，哪条法律不允许台湾国了\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:38.470691+12
404	420	【中国文字狱事件记录】\n日期：2018年08月16日\n地点：广西河池\n当事人：韦某\n平台：微博\n言论内容：批评当地政府玩忽职守，吃喝嫖赌\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:38.514459+12
405	421	【中国文字狱事件记录】\n日期：2018年08月20日\n地点：黑龙江大庆\n当事人：张某\n平台：快手\n言论内容：大同区交警抢摩托了（视频）\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:38.558083+12
406	422	【中国文字狱事件记录】\n日期：2018年08月21日\n地点：海南三亚\n当事人：倪华平\n平台：微信群\n言论内容：习猪头最近怎么样了\n处罚：拘留10日、罚款500	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:38.599923+12
407	423	【中国文字狱事件记录】\n日期：2018年08月21日\n地点：陕西铜川\n当事人：焦某\n平台：微博\n言论内容：是因为受到了警察的威胁而被迫开的锁\n背景事件：讨薪时将公司门锁住，警察来了之后开锁\n处罚：拘留15日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:38.642526+12
408	424	【中国文字狱事件记录】\n日期：2018年08月22日\n地点：辽宁抚顺\n当事人：刘某宇\n平台：微信群\n言论内容：交警执勤视频，其中他使用了“狗”、“妈”等字眼进行描述\n处罚：距离5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:38.690305+12
409	425	【中国文字狱事件记录】\n日期：2018年08月23日\n地点：自贡市社科联\n当事人：蒋明（副主席）\n身份：党政官员\n平台：推特\n言论内容：“坚持资产阶级自由化立场、反对四项基本原则、丑化国家形象、诋毁污蔑党和国家领导人“的文章和评论\n处罚：政务撤职、行政降级、开除党籍\n法律文书：自监发［2028］7号；自纪发［2018］23号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:38.734177+12
410	426	【中国文字狱事件记录】\n日期：2018年08月23日\n地点：浙江杭州\n当事人：沈某\n平台：朋友圈\n言论内容：“辱警言论”\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:38.776236+12
411	427	【中国文字狱事件记录】\n日期：2018年08月24日\n地点：天津\n当事人：王某\n平台：朋友圈\n言论内容：（交通罚单照片）7月15了鬼节；缺钱了，早说啊，我烧点不得了\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:38.829775+12
412	428	【中国文字狱事件记录】\n日期：2018年08月25日\n地点：山东济宁\n当事人：冯某\n平台：微信群\n言论内容：（转发）任城区政府森林公园！一男子杀死自己老婆和他老婆舞伴。\n处罚：拘留5日\n法律文书：济公任（任）行罚决字【2018】1054号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:38.875493+12
413	429	【中国文字狱事件记录】\n日期：2018年08月27日\n地点：山东淄博\n当事人：丁某朋\n平台：微博\n言论内容：一群垃圾，装什么大尾巴狼；死有余辜\n背景事件：寿光洪灾，二名辅警丧命\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:38.911993+12
414	430	【中国文字狱事件记录】\n日期：2018年08月27日\n地点：河北保定\n当事人：路某\n平台：微博\n言论内容：”辱骂交警的言论“\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:38.950167+12
415	431	【中国文字狱事件记录】\n日期：2018年08月27日\n地点：江苏扬中市\n当事人：杨某\n平台：朋友圈\n言论内容：今天这些狗是不是都疯了，一个路口十几个人；看到交警就头疼\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:38.991466+12
416	432	【中国文字狱事件记录】\n日期：2018年08月27日\n地点：江西南昌\n当事人：裘某瑶\n平台：朋友圈\n言论内容：交警全部是禽兽；……贴你妈妈吻禽兽\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:39.040359+12
417	433	【中国文字狱事件记录】\n日期：2018年08月27日\n地点：浙江宁波\n当事人：张某\n平台：朋友圈\n言论内容：“辱警言论”\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:39.085788+12
418	434	【中国文字狱事件记录】\n日期：2018年08月27日\n地点：江苏镇江\n当事人：倪某\n平台：梦溪论坛\n言论内容：指控当地派出所打死了他的狗并称警察为畜生\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:39.132347+12
419	435	【中国文字狱事件记录】\n日期：2018年08月27日\n地点：浙江岱山县\n当事人：“没有烟的男人”\n平台：舟山108社区\n言论内容：衢山这个蜗牛工程何时是个头？已经严重影响百姓出行\n处罚：传唤警告	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:39.17828+12
420	436	【中国文字狱事件记录】\n日期：2018年08月28日\n地点：安徽天长市\n当事人：王某\n平台：微信群\n言论内容：天长的狗全部出动了\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:39.2241+12
421	437	【中国文字狱事件记录】\n日期：2018年08月30日\n地点：河南郑州\n当事人：武某\n平台：微博\n言论内容：自编打油诗控诉交警腐败\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:39.269678+12
422	438	【中国文字狱事件记录】\n日期：2018年08月30日\n地点：河南伊川县\n当事人：张某\n平台：朋友圈\n言论内容：缓慢爬行25分钟挪动了30迷，大早上伊川的交警狗都去哪了，不见贴罚单时的威猛了\n处罚：拘留5日\n法律文书：伊公（白元）行罚决字【2018】10694号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:39.316259+12
423	439	【中国文字狱事件记录】\n日期：2018年08月31日\n地点：甘肃岷县\n当事人：买某平\n平台：快手、微信群\n言论内容：“诋毁政府”的视频\n处罚：拘留8日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:39.361527+12
424	441	【中国文字狱事件记录】\n日期：2018年08月31日\n地点：广西贵港\n当事人：季某\n平台：朋友圈\n言论内容：贵港交警真的是大狗逼！什么逼玩意儿，头顶一片草泥马\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:39.45074+12
425	442	【中国文字狱事件记录】\n日期：2018年08月31日\n地点：贵州凯里\n当事人：顾某\n平台：朋友圈\n言论内容：凯里的交警都是杂碎，这么晚还出来整这些丧良心的事，操他妈的🐶逼\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:39.496127+12
426	443	【中国文字狱事件记录】\n日期：2018年09月01日\n地点：厦门大学\n当事人：周运中（东海道子）\n身份：学者/教师\n平台：微博\n言论内容：中國人最高的境界就是說假話、做假帳、訂假合同，是最低劣民族；等\n处罚：解聘	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:39.538123+12
427	444	【中国文字狱事件记录】\n日期：2018年09月01日\n地点：厦门大学\n当事人：田佳良（洁洁良）\n身份：厦大硕士研究生、党员干部\n平台：微博\n言论内容：傻逼国人，粉豚智商低等\n处罚：开除学籍与党籍	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:39.581708+12
428	445	【中国文字狱事件记录】\n日期：2018年09月01日\n地点：中国劳动关系学院\n当事人：胡浩\n身份：学者/教师\n平台：现实/课堂\n言论内容：宣扬资产阶级自由化、法治化、民主化思想\n处罚：解聘、党内警告	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:39.62402+12
429	446	【中国文字狱事件记录】\n日期：2018年09月02日\n地点：湖南省衡阳县商粮局\n当事人：陈某辉（党建办主任）\n身份：公职人员/事业单位人员\n平台：微信群\n言论内容：（视频）衡阳交警就是疯狗，尤其衡阳县交警；他们如果真的做了像疯狗一样的事，就不会怕别人说\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:39.66947+12
430	447	【中国文字狱事件记录】\n日期：2018年09月02日\n地点：广东东莞\n当事人：香某\n平台：今日头条\n言论内容：“诽谤、侮辱、威胁公安民警及警务辅助人员的信息”十余条\n处罚：拘留15日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:39.713101+12
431	448	【中国文字狱事件记录】\n日期：2018年09月03日\n地点：广东汕头\n当事人：陈某森\n平台：微信群\n言论内容：（视频）谷饶打起来了，政府和灾民，不让人进去救援\n背景事件：830潮汕水灾\n处罚：自首，后续不明	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:39.756093+12
432	449	【中国文字狱事件记录】\n日期：2018年09月03日\n地点：广东汕头\n当事人：肖某权\n平台：微信群\n言论内容：（视频）谷饶镇的老百姓自助救灾，老百姓集资救助受难人民，政府不让，说必须以政府的名义\n背景事件：830潮汕水灾\n处罚：自首，后续不明	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:39.800002+12
433	450	【中国文字狱事件记录】\n日期：2018年09月04日\n地点：湖北云梦县\n当事人：龚某\n平台：孝感槐荫论坛\n言论内容：”不当言论“\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:39.841751+12
434	451	【中国文字狱事件记录】\n日期：2018年09月04日\n地点：北京\n当事人：全世欣\n平台：推特\n言论内容：抨击党和国家领导人言论\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:39.88405+12
435	452	【中国文字狱事件记录】\n日期：2018年09月04日\n地点：湖北恩施\n当事人：杨某\n平台：朋友圈\n言论内容：指控当地干部以权谋私\n处罚：拘留4日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:39.926002+12
436	453	【中国文字狱事件记录】\n日期：2018年09月04日\n地点：江苏江阴\n当事人：李某\n平台：朋友圈\n言论内容：（视频）无锡前洲加油站，打电话引起爆炸，为了自己和他人人身安全，加油时请勿打电话\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:39.968514+12
437	454	【中国文字狱事件记录】\n日期：2018年09月04日\n地点：河南潢川县\n当事人：朱某伟\n平台：潢川在线\n言论内容：潢川交警想钱想疯了吗，在路边停下车去办点事，还找哥人看车，不到两分钟的事……这潢川交警就这素质吗\n处罚：拘留2日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:40.011205+12
438	455	【中国文字狱事件记录】\n日期：2018年09月04日\n地点：陕西汉中\n当事人：杨某\n平台：贴吧\n言论内容：具有煽动性的不当言论”\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:40.053108+12
439	456	【中国文字狱事件记录】\n日期：2018年09月06日\n地点：安徽宿州\n当事人：苌某\n平台：微信群\n言论内容：警察现在变成权势的走狗了\n背景事件：当地某中学发生斗殴致死事件\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:40.095617+12
440	457	【中国文字狱事件记录】\n日期：2018年09月07日\n地点：重庆\n当事人：冉崇碧\n平台：现实/举牌\n言论内容：声援其他被捕异议人士内容和“诋毁政府与官员”的内容\n处罚：有期徒刑3年半\n法律文书：（2018）渝02刑终286号-	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:40.138332+12
441	458	【中国文字狱事件记录】\n日期：2018年09月10日\n地点：安徽宿州\n当事人：董某\n平台：朋友圈\n言论内容：共产党就应该当初被日本人全部刹光\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:40.180023+12
442	459	【中国文字狱事件记录】\n日期：2018年09月11日\n地点：陕西泾阳县\n当事人：刑某\n平台：微博\n言论内容：关于警察执法的29条“虚假言论”，如“泾阳县王桥镇社树村村长与村民出现纠纷，村民被拘留，因不满投诉””\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:40.222052+12
443	460	【中国文字狱事件记录】\n日期：2018年09月11日\n地点：陕西泾阳县\n当事人：王某\n平台：朋友圈\n言论内容：（一段疑似警暴的视频）官匪抓人了；伟大的朋友圈转死畜生\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:40.265473+12
444	461	【中国文字狱事件记录】\n日期：2018年09月13日\n地点：宁夏彭阳县\n当事人：张某\n平台：微信群\n言论内容：“谩骂攻击党委政府和村干部”\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:40.307069+12
445	462	【中国文字狱事件记录】\n日期：2018年09月13日\n地点：宁夏彭阳县\n当事人：张某\n平台：微信群\n言论内容：”谩骂攻击党委政府和村干部“\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:40.351432+12
446	463	【中国文字狱事件记录】\n日期：2018年09月15日\n地点：湖北江陵县\n当事人：庄某\n平台：微信群\n言论内容：抗议农业税，称国家早已取消但当地仍在收取，并发起集会\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:40.394121+12
447	464	【中国文字狱事件记录】\n日期：2018年09月17日\n地点：福建莆田\n当事人：梁某\n平台：微信群\n言论内容：某人上台后，尤其x修宪后\n背景事件：习近平修宪\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:40.436542+12
448	465	【中国文字狱事件记录】\n日期：2018年09月18日\n地点：湖北武汉\n当事人：吴勇\n平台：QQ群、微信群\n言论内容：诽谤和辱骂国家领导人、散布“亡国“和”假共“等信息\n处罚：有期徒刑8个月\n法律文书：（2018）鄂0111刑初711号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:40.479909+12
449	466	【中国文字狱事件记录】\n日期：2018年09月22日\n地点：湖南城市学院\n当事人：王栋\n平台：微博\n言论内容：爱国是不可能的，这辈子不可能爱国\n处罚：取消入学资格	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:40.521521+12
450	467	【中国文字狱事件记录】\n日期：2018年09月22日\n地点：山东嘉祥县\n当事人：杨攀\n平台：朋友圈\n言论内容：孟姑镇人大副主席王志勇，副科级干部，信访办事员。这个未知的种类。练我的征地补偿款都挪用了……\n处罚：拘留5日\n法律文书：嘉公（孟）行罚决字[2018]980号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:40.565308+12
451	468	【中国文字狱事件记录】\n日期：2018年09月23日\n地点：贵州凯里\n当事人：杨某\n平台：微信群\n言论内容：哪个傻逼的杰作，辛苦了，大晚上还没下班；辛苦了，哈卵\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:40.607994+12
452	469	【中国文字狱事件记录】\n日期：2018年09月24日\n地点：四川岳池县\n当事人：李立君\n平台：微信\n言论内容：“侮辱党和政府的言论”\n处罚：拘留15日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:40.649569+12
453	470	【中国文字狱事件记录】\n日期：2018年09月25日\n地点：四川石渠县\n当事人：王某\n平台：朋友圈\n言论内容：几条狗把老子的行驶证给扣了\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:40.691755+12
454	471	【中国文字狱事件记录】\n日期：2018年09月27日\n地点：山东德州\n当事人：李振广\n平台：天涯社区\n言论内容：德州陵城区政府违法占地，以租代征500亩地比当年恶霸土匪有过之无不及\n处罚：拘留10日、罚款1000元\n法律文书：陵城公（郑）行罚决字【2018】344号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:40.73421+12
480	497	【中国文字狱事件记录】\n日期：2018年10月16日\n地点：安徽芜湖\n当事人：奚某平\n平台：微博\n言论内容：多次发布“侮辱党和国家领导人”言论\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:41.857377+12
455	472	【中国文字狱事件记录】\n日期：2018年09月27日\n地点：福建福州\n当事人：林依妹\n平台：网络、现实\n言论内容：发起“每周一聚”活动，并在网络发表\n处罚：有期徒刑1年8个月\n备注：二审维持原判\n法律文书：（2018）闽01刑终1540号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:40.777869+12
456	473	【中国文字狱事件记录】\n日期：2018年09月27日\n地点：河南周口\n当事人：李某杰\n平台：贴吧\n言论内容：“辱骂周口交警”\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:40.822464+12
457	474	【中国文字狱事件记录】\n日期：2018年09月28日\n地点：湖南吉首\n当事人：王某山\n平台：微信\n言论内容：（在评论8月邹某案例官方通报时）“无端指责、诋毁政府，丑化党的形象“\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:40.866316+12
458	475	【中国文字狱事件记录】\n日期：2018年09月28日\n地点：石家庄工程技术学校\n当事人：不详\n平台：微博\n言论内容：（使用该校团委微博号发布）邱少云：我今天要火、黄继光：我趴着也能中枪、董存瑞：我要碉堡了\n处罚：传唤、后续不明	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:40.91075+12
459	476	【中国文字狱事件记录】\n日期：2018年09月29日\n地点：四川泸州\n当事人：许华\n平台：中国酒城论坛\n言论内容：拒删其网站上的政治有害信息\n处罚：已审、判决未知	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:40.954673+12
460	477	【中国文字狱事件记录】\n日期：2018年09月29日\n地点：上海\n当事人：唐燕涛\n平台：多个平台\n言论内容：《秋雨图说》\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:40.999676+12
461	478	【中国文字狱事件记录】\n日期：2018年10月01日\n地点：广东惠州\n当事人：聂某琦\n平台：微博\n言论内容：现在MJ还能死呢啊？遇事就跑……我说的就是广东某一票MJ，你们小民警好垃圾哟，来抓我\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:41.042539+12
462	479	【中国文字狱事件记录】\n日期：2018年10月01日\n地点：浙江传媒学院\n当事人：赵思运\n身份：学者/教师\n平台：微博、现实\n言论内容：2018年新生开学典礼迎新致辞中的不当措辞\n处罚：党内严重处分	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:41.085118+12
463	480	【中国文字狱事件记录】\n日期：2018年10月02日\n地点：四川康定\n当事人：邓某\n平台：微博\n言论内容：康定的交警是都死完了吗\n背景事件：其车堵在雪山，长时间未等候到交警处理\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:41.128272+12
464	481	【中国文字狱事件记录】\n日期：2018年10月03日\n地点：浙江杭州\n当事人：朱某宝\n平台：网络\n言论内容：这个人（牺牲民警）是跟人家偷情被抓住了，从4楼跳下来摔死的\n处罚：拘留13日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:41.171884+12
465	482	【中国文字狱事件记录】\n日期：2018年10月04日\n地点：四川峨眉山市\n当事人：杨某芳\n平台：朋友圈\n言论内容：我只想说这些🐶🐔******是饿疯了还是穷疯了老子车子停在自己小区楼下都被罚款了\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:41.216644+12
466	483	【中国文字狱事件记录】\n日期：2018年10月06日\n地点：青海西宁\n当事人：不详\n平台：朋友圈\n言论内容：孬种一帮龟孙，驾照没带扣分还罚钱\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:41.259162+12
467	484	【中国文字狱事件记录】\n日期：2018年10月08日\n地点：宁夏中卫\n当事人：不详\n平台：英雄联盟\n言论内容：“反华”言论\n处罚：拘留13日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:41.306331+12
468	485	【中国文字狱事件记录】\n日期：2018年10月09日\n地点：陕西三原县\n当事人：苏某\n平台：微信\n言论内容：三原阳光菜市场叫黑社会打人，朋友帮忙转发\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:41.34882+12
469	486	【中国文字狱事件记录】\n日期：2018年10月09日\n地点：陕西三原县\n当事人：王某\n平台：微信群\n言论内容：转发题为“阳光集团老总聚集社会无业游民，联合派出所对商户大打出手，人民警察勾结不法商人欺压百姓”\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:41.389953+12
470	487	【中国文字狱事件记录】\n日期：2018年10月09日\n地点：陕西三原县\n当事人：王某（女）\n平台：微博\n言论内容：三原县阳光果蔬市场老板纠结黑社会与派出所欺压贩菜农民\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:41.431739+12
471	488	【中国文字狱事件记录】\n日期：2018年10月09日\n地点：陕西三原县\n当事人：李某柱\n平台：贴吧、微信群\n言论内容：转发“阳光集团老总王学峰，亲自率领社会闲杂人等，联手园区派出所对我市场手无寸铁，合法摊主大打出手!堪称警匪合作”\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:41.474649+12
472	489	【中国文字狱事件记录】\n日期：2018年10月10日\n地点：广西德保县\n当事人：陆某\n平台：微信群\n言论内容：有没有人认识这个人？有多大的权利可以让一个屯的车不进出村口？到底吃了多少赵老板的钱这么卖命\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:41.517393+12
473	490	【中国文字狱事件记录】\n日期：2018年10月11日\n地点：山东郓城县\n当事人：黄某\n平台：微信群\n言论内容：（视频）架子歪了，摔死了6个！\n处罚：拘留10日、罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:41.559579+12
474	491	【中国文字狱事件记录】\n日期：2018年10月11日\n地点：广东博罗县\n当事人：黄文勋\n平台：网络\n言论内容：将要以跑步的方式来纪念这个特殊日子（10月10日，中华民国国庆节）\n处罚：刑事拘留\n法律文书：博公（柏）拘通字［2018］010号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:41.60183+12
475	492	【中国文字狱事件记录】\n日期：2018年10月12日\n地点：河南商洛\n当事人：吴邦用\n平台：微信群\n言论内容：大家应该把家业送给共产党……否则就送进新疆再教育营进行马克思主义教育\n处罚：拘留14日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:41.644327+12
476	493	【中国文字狱事件记录】\n日期：2018年10月12日\n地点：广西贵港\n当事人：甘某\n平台：微信群\n言论内容：宇洋门口啊，西山一号门口啊，滴XX交警在这里查测速、压实线，滴XXX交警啊\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:41.687049+12
477	494	【中国文字狱事件记录】\n日期：2018年10月14日\n地点：浙江衢州\n当事人：方超\n平台：微博\n言论内容：这嘴脸，啧啧啧，老百姓完全再养猪啊，这个死猪，一点小事不让看监控，也不问事故经过，cnmd为人民服务\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:41.728804+12
478	495	【中国文字狱事件记录】\n日期：2018年10月14日\n地点：上海\n当事人：杨凯莉（莉哥）\n身份：网红\n平台：虎牙直播\n言论内容：“篡改国歌”（并未修改歌词，而是用非严肃方式演唱“\n处罚：拘留5日、封号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:41.771009+12
479	496	【中国文字狱事件记录】\n日期：2018年10月16日\n地点：浙江杭州\n当事人：彭好安\n平台：微信群\n言论内容：不详，警方和法院称是“针对中央领导同志的不当言论，其自己称是”铁证如山的事实“\n处罚：拘留7日\n法律文书：余公（中）行罚决字〔2018〕16924号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:41.814951+12
481	498	【中国文字狱事件记录】\n日期：2018年10月17日\n地点：吉林德惠市\n当事人：石桂海\n平台：微博\n言论内容：德惠市公安局镇摄老百姓上访，殴打访民等\n处罚：拘留13日\n法律文书：德公(治)行罚决字(2018)1037号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:41.901083+12
482	499	【中国文字狱事件记录】\n日期：2018年10月17日\n地点：江苏昆山\n当事人：叶代国\n平台：现实/张贴传单\n言论内容：告全国人民书江苏省苏州中级人民法院、江苏省高级人民法院公开枉法裁判，江苏省人民检察院公开枉法裁判，公开强奸法律\n处罚：拘留7日\n法律文书：昆公（陆家）行罚决字{2018}9469号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:41.947073+12
483	500	【中国文字狱事件记录】\n日期：2018年10月18日\n地点：四川德阳\n当事人：罗某\n平台：微博\n言论内容：长期发文指控某警察收受贿赂，为他人办事\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:41.991041+12
484	501	【中国文字狱事件记录】\n日期：2018年10月20日\n地点：吉林吉林\n当事人：郭某\n平台：微信群\n言论内容：尤其是习近平上台后，民生一点都没有改善\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:42.032887+12
485	502	【中国文字狱事件记录】\n日期：2018年10月21日\n地点：山东菏泽\n当事人：王某\n平台：微博\n言论内容：郓城李楼煤矿发生重大安全事故21人被掩埋，已确认9人死亡\n处罚：拘留10日\n备注：官方后来通报死亡21人	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:42.075477+12
486	503	【中国文字狱事件记录】\n日期：2018年10月22日\n地点：河南商丘\n当事人：王某\n平台：微信群\n言论内容：8秒视频，其中将警察称为土匪\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:42.119017+12
487	504	【中国文字狱事件记录】\n日期：2018年10月23日\n地点：安徽濉溪县\n当事人：谢某\n平台：微信群\n言论内容：针对警方设卡盘查行动的”辱警言论“\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:42.162616+12
488	505	【中国文字狱事件记录】\n日期：2018年10月24日\n地点：山东郓城县\n当事人：张某\n平台：微信群\n言论内容：李楼煤矿二次塌方，底下救人的70多人又被困30多个\n处罚：拘留10日、罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:42.212323+12
489	506	【中国文字狱事件记录】\n日期：2018年10月26日\n地点：浙江海盐县\n当事人：杨某\n平台：朋友圈\n言论内容：狗（交警和政府部门执法人员）都在上班了，我们也要努力啦！\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:42.266348+12
490	507	【中国文字狱事件记录】\n日期：2018年10月26日\n地点：陕西武功县\n当事人：杨某\n平台：朋友圈\n言论内容：”辱骂、诋毁民警的视频“\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:42.313463+12
491	508	【中国文字狱事件记录】\n日期：2018年10月27日\n地点：湖北宜昌\n当事人：谭军\n身份：公职人员/事业单位人员\n平台：推特\n言论内容：”大量诽谤党和国家领导人的内容“\n处罚：行拘10日转刑拘\n备注：2018/12/13检方撤诉	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:42.373635+12
492	509	【中国文字狱事件记录】\n日期：2018年10月28日\n地点：福建莆田\n当事人：蔡某\n平台：微信群\n言论内容：“煽动发布不当言论”\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:42.41928+12
493	510	【中国文字狱事件记录】\n日期：2018年10月29日\n地点：河北保定\n当事人：赵某\n平台：微信群\n言论内容：死得好！往东站站20秒被这帮狗县城抓住3分100\n背景事件：当地一名交警车祸身亡\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:42.46448+12
494	511	【中国文字狱事件记录】\n日期：2018年10月29日\n地点：广东深圳\n当事人：董奇\n平台：现实/印制T恤\n言论内容：一切才刚刚开始\n背景事件：郭文贵爆料事件\n处罚：有期徒刑一年6个月	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:42.511608+12
495	512	【中国文字狱事件记录】\n日期：2018年10月29日\n地点：湖北巴东县\n当事人：向贤玲\n平台：网络、现实\n言论内容：上访；《两条人命谁来偿还呼吁社会还我公道》等\n背景事件：其子死于学校，其夫因此自杀\n处罚：有期徒刑3年\n备注：二审维持原判\n法律文书：（2019）鄂28刑终115号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:42.562366+12
496	513	【中国文字狱事件记录】\n日期：2018年10月31日\n地点：福建惠安县\n当事人：张某\n平台：朋友圈\n言论内容：条子饥渴成性、那么猖狂抓车、居然电动车都明目张胆抓了，世道还我没王法了。。尼玛，真可恨，真气愤\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:42.611896+12
497	514	【中国文字狱事件记录】\n日期：2018年11月01日\n地点：浙江临海市\n当事人：谢英科\n平台：推特\n言论内容：”虚构事实侮辱、诽谤国家领导人“\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:42.658942+12
498	515	【中国文字狱事件记录】\n日期：2018年11月01日\n地点：安徽六安\n当事人：吴怀云\n平台：推特、微博、微信\n言论内容：关于巴拿马文件内容\n背景事件：巴拿马文件事件\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:42.704979+12
499	516	【中国文字狱事件记录】\n日期：2018年11月01日\n地点：青海西宁\n当事人：李某\n平台：朋友圈\n言论内容：车匪路霸！出租车也挡！\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:42.74776+12
500	517	【中国文字狱事件记录】\n日期：2018年11月02日\n地点：辽宁大连\n当事人：刘井春\n平台：QQ群\n言论内容：731根本子虚乌有，是某党杜撰的以及”对党和社会不满的言论“\n处罚：有期徒刑8个月、缓刑1年\n法律文书：（2018）辽0211刑初895号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:42.789435+12
501	623	【中国文字狱事件记录】\n日期：2019年03月01日\n地点：北京大学\n当事人：柴晓明\n身份：学者/教师\n平台：微信公众平台\n言论内容：关于马克思主义不当言论\n处罚：监视居住	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:47.60404+12
502	518	【中国文字狱事件记录】\n日期：2018年11月02日\n地点：广西梧州\n当事人：黎某\n平台：朋友圈\n言论内容：你老婆叫你番交公粮啊；晚晚甘夜出来抄牌，好易戴多顶帽概，冇系官帽哦\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:42.830364+12
503	519	【中国文字狱事件记录】\n日期：2018年11月02日\n地点：重庆\n当事人：刘继春\n平台：网络\n言论内容：长期转发批评时政文章\n处罚：有期徒刑1年	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:42.871131+12
504	520	【中国文字狱事件记录】\n日期：2018年11月02日\n地点：江西鄱阳县\n当事人：雷某\n平台：网络\n言论内容：鄱阳交警像疯狗一样乱咬乱叫\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:42.912753+12
505	521	【中国文字狱事件记录】\n日期：2018年11月05日\n地点：陕西平利县\n当事人：杨某\n平台：贴吧\n言论内容：指控平利法院包庇偏袒地方黑恶势力；要去北京上访；要让平利法院上腾讯头条\n处罚：司法拘留15日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:42.954384+12
506	522	【中国文字狱事件记录】\n日期：2018年11月07日\n地点：四川巴中\n当事人：李某\n平台：微信群\n言论内容：“辱警信息”\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:42.994361+12
507	523	【中国文字狱事件记录】\n日期：2018年11月07日\n地点：广东广州\n当事人：徐琳\n平台：脸书等\n言论内容：大量政治言论\n处罚：有期徒刑3年\n法律文书：（2018）粤0115刑初360号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:43.035936+12
508	524	【中国文字狱事件记录】\n日期：2018年11月08日\n地点：安徽灵璧县\n当事人：张某\n平台：快手\n言论内容：“大灵璧的交警那么冷的天那么敬业…”等辱警言论\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:43.07775+12
509	525	【中国文字狱事件记录】\n日期：2018年11月12日\n地点：江苏南京\n当事人：史竟（史庭福之子）\n平台：微信\n言论内容：对政治犯朱承志的关切的言论\n处罚：拘留13日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:43.120951+12
510	526	【中国文字狱事件记录】\n日期：2018年11月12日\n地点：江苏赣榆县\n当事人：钱某娟\n平台：陌陌\n言论内容：该千杀的交警乱查乱拉，好人死多少他们也不死\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:43.16215+12
511	527	【中国文字狱事件记录】\n日期：2018年11月12日\n地点：江西赣州\n当事人：郑某\n平台：朋友圈\n言论内容：（交通罚单照片）我他妈的，日了狗吧，没2分钟，这帮狗叼的\n处罚：拘留2日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:43.202635+12
512	528	【中国文字狱事件记录】\n日期：2018年11月13日\n地点：辽宁沈阳\n当事人：李某\n平台：朋友圈\n言论内容：“辱骂交警”的言论\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:43.24561+12
513	529	【中国文字狱事件记录】\n日期：2018年11月14日\n地点：内蒙古宁城县\n当事人：王某（网红）\n平台：快手\n言论内容：（直播用搞怪方式唱）中国国歌\n处罚：拘留15日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:43.288654+12
514	530	【中国文字狱事件记录】\n日期：2018年11月16日\n地点：辽宁大连\n当事人：赵琴\n平台：微信、现实\n言论内容：“辱骂共产党、国家司法机关、微信群友”\n背景事件：其被人打伤，伤人者被罚500元，且处罚随后撤销\n处罚：有期徒刑8个月\n法律文书：（2018）辽0211刑初859号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:43.331772+12
515	531	【中国文字狱事件记录】\n日期：2018年11月20日\n地点：四川甘孜\n当事人：未知\n平台：朋友圈\n言论内容：杂种些看来是守株待兔哈\n处罚：未知处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:43.374923+12
516	532	【中国文字狱事件记录】\n日期：2018年11月27日\n地点：湖南吉首\n当事人：江某\n平台：微信群\n言论内容：“反动言论”\n处罚：拘留7日；罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:43.417411+12
517	533	【中国文字狱事件记录】\n日期：2018年11月27日\n地点：山西运城\n当事人：刘美廷（韩丽芳夫）\n平台：微信群\n言论内容：大量反共言论\n处罚：有期徒刑4年\n备注：2019/7/29判决撤销\n法律文书：（2018）晋08刑初8号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:43.460351+12
518	534	【中国文字狱事件记录】\n日期：2018年11月27日\n地点：山西运城\n当事人：韩丽芳（刘美廷妻）\n平台：微信群\n言论内容：大量反共言论\n处罚：有期徒刑3年\n备注：2019/7/29判决撤销\n法律文书：（2018）晋08刑初8号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:43.508856+12
519	535	【中国文字狱事件记录】\n日期：2018年11月27日\n地点：江西于都县\n当事人：张某\n平台：微信群\n言论内容：银坑交警吃屎的吗\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:43.555524+12
520	536	【中国文字狱事件记录】\n日期：2018年11月27日\n地点：江苏宿迁\n当事人：余某\n平台：朋友圈\n言论内容：洋河交警蔡XX喊你吗起来吃早点了；洋河交警蔡XX我XXX\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:43.600462+12
521	537	【中国文字狱事件记录】\n日期：2018年11月29日\n地点：山东曹县\n当事人：安昌\n平台：快手\n言论内容：交警执勤视频，其中其对交警进行了“辱骂”\n处罚：有期徒刑8个月、缓刑1年\n法律文书：（2018）鲁1721刑初648号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:43.644781+12
522	538	【中国文字狱事件记录】\n日期：2018年11月30日\n地点：广西那坡县\n当事人：唐某\n平台：微信私聊\n言论内容：（视频）土匪在这里查车，碧水蓝天这里，路口，注意注意，各位各位\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:43.689985+12
523	539	【中国文字狱事件记录】\n日期：2018年12月03日\n地点：浙江嘉兴\n当事人：何某\n平台：网络\n言论内容：不当言论（引发民众聚集）\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:43.734926+12
524	540	【中国文字狱事件记录】\n日期：2018年12月03日\n地点：广西防城港\n当事人：黎某\n平台：QQ空间、推特\n言论内容：“辱骂党和国家领导人、辱骂中国人民及政府的不当言论”\n处罚：起诉（寻衅滋事罪）\n法律文书：港检刑诉〔2018〕174号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:43.77886+12
525	541	【中国文字狱事件记录】\n日期：2018年12月05日\n地点：湖南绥宁县\n当事人：张某\n平台：微信群\n言论内容：（警察执法视频）都是些协警，土匪\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:43.824003+12
526	542	【中国文字狱事件记录】\n日期：2018年12月05日\n地点：青海祁连县\n当事人：田某\n平台：微信群\n言论内容：“辱骂村长和村支书的言论”\n处罚：拘留8日\n备注：跨省抓捕	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:43.870789+12
527	543	【中国文字狱事件记录】\n日期：2018年12月11日\n地点：广西贺州\n当事人：潘某兴\n平台：朋友圈\n言论内容：（民警执勤照片）哈哈哈，冷得这些大土匪……\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:43.915277+12
528	544	【中国文字狱事件记录】\n日期：2018年12月11日\n地点：贵州凯里\n当事人：龙某\n平台：朋友圈\n言论内容：鸡巴交警饿钱死，这个鸡巴交警来提罚款早晚也是被车撞死\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:43.962275+12
529	570	【中国文字狱事件记录】\n日期：2019年01月02日\n地点：贵州毕节\n当事人：谢某\n平台：微博\n言论内容：是二十多个生命，不是几个的问题\n背景事件：当地发生火灾，官方通报5死4伤\n处罚：罚款100元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:45.159316+12
530	545	【中国文字狱事件记录】\n日期：2018年12月14日\n地点：四川岳池县\n当事人：李立君\n平台：微信、现实\n言论内容：穿冤衣在省信访局门口拍照，拉横幅；微信中说“中国司法腐败，官员不作为或乱作为，比国民党坏19倍，比清朝坏100倍\n处罚：拘留20日\n法律文书：岳公（经）行罚决字[2018]1314号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:44.015975+12
531	546	【中国文字狱事件记录】\n日期：2018年12月14日\n地点：上海\n当事人：丁少龙\n平台：微信群\n言论内容：《如何将上海这一仗推向高潮》等方式组织维权示威\n处罚：有期徒刑2年\n备注：二审维持原判\n法律文书：（2019）沪01刑终104号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:44.062488+12
532	547	【中国文字狱事件记录】\n日期：2018年12月15日\n地点：黑龙江五常市\n当事人：刘某春\n平台：微信群\n言论内容：转发信息，组织上访\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:44.108095+12
533	548	【中国文字狱事件记录】\n日期：2018年12月18日\n地点：四川乐山\n当事人：苟某\n平台：微信群\n言论内容：撞死那些狗交警；就知道罚款扣分，交通堵，他们看不见\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:44.154481+12
534	549	【中国文字狱事件记录】\n日期：2018年12月19日\n地点：江苏睢宁县\n当事人：倪斌\n平台：多个平台\n言论内容：指控警察私闯民宅和殴打群众\n处罚：有期徒刑1年2个月\n备注：二审维持原判\n法律文书：（2018）苏0324刑初460号；（2019）苏03刑终51号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:44.201002+12
535	550	【中国文字狱事件记录】\n日期：2018年12月19日\n地点：江西宜春\n当事人：周某航（17岁）\n平台：微博\n言论内容：中国是卑劣的民族、感恩大日本帝国\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:44.248214+12
536	551	【中国文字狱事件记录】\n日期：2018年12月20日\n地点：河南漯河\n当事人：郝某\n平台：朋友圈\n言论内容：”辱警信息“\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:44.294584+12
537	552	【中国文字狱事件记录】\n日期：2018年12月21日\n地点：贵州威宁县\n当事人：赵某\n平台：微信群\n言论内容：“侮辱马金涛”的言论\n背景事件：贵阳民警马金涛遇袭死亡\n处罚：抓获，后续不明	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:44.339774+12
538	553	【中国文字狱事件记录】\n日期：2018年12月21日\n地点：贵州贵阳\n当事人：秦某\n平台：网络\n言论内容：死得好\n背景事件：贵阳民警马金涛遇袭死亡\n处罚：抓获，后续不明	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:44.385315+12
539	554	【中国文字狱事件记录】\n日期：2018年12月21日\n地点：河南舞阳县\n当事人：郝某\n平台：朋友圈\n言论内容：“侮辱交警”的内容\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:44.428839+12
540	555	【中国文字狱事件记录】\n日期：2018年12月22日\n地点：上海\n当事人：王某（女）\n平台：微博\n言论内容：诅咒警察及家属\n背景事件：其被邻居殴打，报警后警方不处理\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:44.474536+12
541	556	【中国文字狱事件记录】\n日期：2018年12月22日\n地点：贵州贵阳\n当事人：陈某\n平台：微博\n言论内容：（关于马金涛的）侮辱言论\n背景事件：贵阳民警马金涛遇袭死亡\n处罚：抓获，后续不明	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:44.519321+12
542	557	【中国文字狱事件记录】\n日期：2018年12月23日\n地点：贵州贵阳\n当事人：谭某\n平台：微博\n言论内容：该死\n背景事件：贵阳民警马金涛遇袭死亡\n处罚：抓获、后续不详	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:44.563759+12
543	558	【中国文字狱事件记录】\n日期：2018年12月24日\n地点：江西景德镇\n当事人：李某等6人\n平台：微信群\n言论内容：组织维权\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:44.608044+12
544	559	【中国文字狱事件记录】\n日期：2018年12月24日\n地点：河北沧州\n当事人：回某\n平台：贴吧\n言论内容：“辱骂城管”\n处罚：拘留7日、罚款200元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:44.652561+12
545	560	【中国文字狱事件记录】\n日期：2018年12月25日\n地点：河南项城市\n当事人：刘振华\n平台：凯迪社区\n言论内容：《这是个坑爹时代》（7）“侮辱、辱骂项城市永丰镇人民政府、项城市公检法机关，以及相关国家公职人员”\n处罚：有期徒刑4年2个月\n备注：二审维持原判\n法律文书：（2018）豫1681刑初749号；（2019）豫16刑终123号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:44.698142+12
546	561	【中国文字狱事件记录】\n日期：2018年12月25日\n地点：江苏扬州\n当事人：刘红波\n平台：推特\n言论内容：转发推特400余篇（其中“诽谤党和国家领导人”推文72篇，“损害党和政府形象”推文329篇）\n处罚：有期徒刑6个月\n法律文书：（2018）苏1003刑初851号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:44.743481+12
547	562	【中国文字狱事件记录】\n日期：2018年12月26日\n地点：贵州黔西县\n当事人：黄克普\n平台：微博、贴吧\n言论内容：当地村道公路是豆腐渣工程，贵州所有村道公路几乎都是豆腐渣工程\n处罚：有期徒刑1年6个月\n备注：二审维持原判\n法律文书：（2018）黔0522刑初316号；（2019）黔05刑终129号-黄克普	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:44.789172+12
548	563	【中国文字狱事件记录】\n日期：2018年12月29日\n地点：贵州纳雍县\n当事人：李龙全\n平台：六四天网、现实\n言论内容：举牌及游行，表达其收到的退耕还林补偿不足，并发表到六四天网\n处罚：有期徒刑5年\n备注：二审维持原判\n法律文书：（2019）黔05刑终141号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:44.83596+12
549	564	【中国文字狱事件记录】\n日期：2018年12月29日\n地点：河南商丘\n当事人：胡某\n平台：微信群\n言论内容：“攻击、辱骂国家领导人”\n处罚：刑事拘留\n备注：2019/5/17不予起诉	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:44.881518+12
550	565	【中国文字狱事件记录】\n日期：2018年12月30日\n地点：海南万宁\n当事人：蔡某哲\n平台：今日头条、天涯、微博\n言论内容：其土地被他人非法侵占以及地上树木被非法砍伐；市乡村干部包庇黑恶势力\n处罚：拘留10日\n备注：行政复议、行政一审二审均维持处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:44.926836+12
551	566	【中国文字狱事件记录】\n日期：2018年12月30日\n地点：广东深圳\n当事人：黄昭云\n平台：推特\n言论内容：大量政治言论，包含六四事件\n背景事件：六四事件\n处罚：拘留10日、要求删除推特账号及所有推文	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:44.971956+12
552	567	【中国文字狱事件记录】\n日期：2018年12月31日\n地点：上海\n当事人：宫敏赓（宫正兄）\n平台：现实/印于衣服、发传单\n言论内容：打倒共匪；申冤内容\n处罚：刑事拘留\n备注：2019/1/31取保候审	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:45.017341+12
553	568	【中国文字狱事件记录】\n日期：2018年12月31日\n地点：上海\n当事人：宫正（宫明赓弟）\n平台：现实/印于衣服、发传单\n言论内容：打倒共匪；申冤内容\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:45.064579+12
554	569	【中国文字狱事件记录】\n日期：2019年01月01日\n地点：贵州毕节\n当事人：李某\n平台：微博\n言论内容：毕节地区金沙县沙土镇诚才足疗凌晨4时许发生火灾，确认死者13名，逃出四到五人\n背景事件：当地发生火灾，官方通报5死4伤\n处罚：批评训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:45.111452+12
555	571	【中国文字狱事件记录】\n日期：2019年01月03日\n地点：贵州毕节\n当事人：贾某\n平台：微博\n言论内容：毕节养生店火灾报道五死四伤很荒唐……死伤特别惨烈……\n背景事件：当地发生火灾，官方通报5死4伤\n处罚：拘留4日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:45.204403+12
556	572	【中国文字狱事件记录】\n日期：2019年01月03日\n地点：甘肃正宁县\n当事人：王某\n平台：快手\n言论内容：（警察进行交通管制视频）正宁这狗\n处罚：拘留5日、罚款200元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:45.255735+12
581	597	【中国文字狱事件记录】\n日期：2019年01月25日\n地点：山东东阿县\n当事人：王某霞\n平台：网络\n言论内容：（视频）司法局欠钱不还，还我农民工血汗钱\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:46.412345+12
557	573	【中国文字狱事件记录】\n日期：2019年01月03日\n地点：江苏东海县\n当事人：崔某\n平台：朋友圈\n言论内容：（评论警察殉职新闻）东海警察都在混日子，一个还没有死呢\n处罚：拘留8日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:45.30557+12
558	574	【中国文字狱事件记录】\n日期：2019年01月04日\n地点：重庆\n当事人：黄成城\n平台：推特\n言论内容：“翻墙”\n处罚：传唤警告	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:45.352252+12
559	575	【中国文字狱事件记录】\n日期：2019年01月05日\n地点：天津\n当事人：王某\n平台：快手\n言论内容：（民警执勤视频）及辱骂内容\n处罚：拘留9日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:45.397034+12
560	576	【中国文字狱事件记录】\n日期：2019年01月07日\n地点：黑龙江肇州县\n当事人：谭某\n平台：微信群\n言论内容：（交警执法视频）辱警文字以取乐\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:45.441806+12
561	577	【中国文字狱事件记录】\n日期：2019年01月07日\n地点：山东济南\n当事人：亓越娥\n平台：微博\n言论内容：共产党就是土匪，这是我们老百姓都知道的常识，他们代表了中国，辱华骂土匪没毛病!别不承认\n处罚：拘留10日\n法律文书：城公（城西）行罚决字[2019]5号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:45.48834+12
562	578	【中国文字狱事件记录】\n日期：2019年01月08日\n地点：宁夏吴忠\n当事人：孙二狗（化名）\n平台：网易新闻\n言论内容：砍死狗日的（辅警）。疯狗一样贴罚单，该死\n处罚：拘留8日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:45.53417+12
563	579	【中国文字狱事件记录】\n日期：2019年01月08日\n地点：黑龙江泰来县\n当事人：翟某\n平台：贴吧\n言论内容：在新的一年里祝XX派出所的警察死全家\n处罚：拘留10日、罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:45.577603+12
564	580	【中国文字狱事件记录】\n日期：2019年01月10日\n地点：山东莒县\n当事人：霍某\n平台：微信群\n言论内容：带有“辱骂交警”言论的视频\n处罚：拘留7日、罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:45.623216+12
565	581	【中国文字狱事件记录】\n日期：2019年01月10日\n地点：广东安仁律师事务所\n当事人：刘正清\n身份：律师\n平台：现实/庭审\n言论内容：在（2016）新刑终73号案件（新疆张海涛案）与（2017）粤06刑终557号案件（法轮功学员李艳明与雷敏案）庭审中的违法辩词\n处罚：吊销律师资格证	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:45.669646+12
566	582	【中国文字狱事件记录】\n日期：2019年01月14日\n地点：上海\n当事人：季孝龙\n平台：推特、现实\n言论内容：在推特上发起“厕所革命（在公厕门上书写政治诉求）”\n处罚：有期徒刑3年6个月\n备注：已提起上诉	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:45.713693+12
567	583	【中国文字狱事件记录】\n日期：2019年01月15日\n地点：江苏宝应县\n当事人：何某、季某\n平台：微信群\n言论内容：堵那个院长去；团结起来、闹他\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:45.756805+12
568	584	【中国文字狱事件记录】\n日期：2019年01月16日\n地点：江西鄱阳\n当事人：彭某华\n平台：微博\n言论内容：像于敏（氢弹之父）这样的人应该早点死\n处罚：拘留15日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:45.802039+12
569	585	【中国文字狱事件记录】\n日期：2019年01月16日\n地点：云南昭通\n当事人：左某\n平台：快手\n言论内容：侮辱巧家县交警视频\n处罚：拘留5日不执行	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:45.845679+12
570	586	【中国文字狱事件记录】\n日期：2019年01月18日\n地点：四川仁寿县\n当事人：田某\n平台：天天快报\n言论内容：砍杀警察是作为公民的选择，警察太坏了；警察好的少，坏的多；人没有多大的仇恨是不会做傻事的\n背景事件：富加镇派出所砍人事件\n处罚：有期徒刑6个月\n法律文书：（2019）川1421刑初27号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:45.891767+12
571	587	【中国文字狱事件记录】\n日期：2019年01月18日\n地点：四川仁寿县\n当事人：黄某\n平台：微信群\n言论内容：我支持，要整就整这些人，拿了本本得土匪，一天到晚要不完的样子，不把老百姓当回事\n背景事件：富加镇派出所砍人事件\n处罚：拘役6个月\n法律文书：（2019）川1421刑初32号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:45.939898+12
572	588	【中国文字狱事件记录】\n日期：2019年01月18日\n地点：河北河间市\n当事人：刘双喜\n身份：中共党员\n平台：网络\n言论内容：乡镇干部贪污腐败、干扰村选举、强拆房屋等\n处罚：有期徒刑1年2个月\n备注：二审维持原判\n法律文书：（2018）冀0984刑初472号；（2019）冀09刑终351号\n	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:45.987243+12
573	589	【中国文字狱事件记录】\n日期：2019年01月21日\n地点：四川成都\n当事人：谢俊彪\n平台：推特\n言论内容：转发新闻《前警察访民举报国保报复　炮制假绝密文件构陷黄琦》\n处罚：刑事拘留\n备注：2/28取保候审	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:46.032217+12
574	590	【中国文字狱事件记录】\n日期：2019年01月21日\n地点：辽宁朝阳县\n当事人：陈国吉\n平台：推特\n言论内容：颠覆国家政权类内容、攻击国家体制、攻击国家领导人、发表煽动性内容等\n处罚：有期徒刑2年、缓刑2年\n法律文书：（2018）辽1321刑初164号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:46.084282+12
575	591	【中国文字狱事件记录】\n日期：2019年01月22日\n地点：湖北武穴\n当事人：陈某\n平台：微博\n言论内容：”侮辱已故国家领导人、攻击社会体制及改革开放的不当言论“\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:46.136758+12
576	592	【中国文字狱事件记录】\n日期：2019年01月23日\n地点：江西新余\n当事人：朱菊如\n平台：微信、现实\n言论内容：派发政治传单以及在微信中发送大量政治诉求图片，例如爱国民主游行、结束专政、平反六四、释放民运人士等\n处罚：有期徒刑2年6个月\n法律文书：（2018）赣0502刑初459号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:46.182842+12
577	593	【中国文字狱事件记录】\n日期：2019年01月24日\n地点：黑龙江塔河县\n当事人：满某\n平台：微信群\n言论内容：塔河县政府搞形象工程，蔡某某残疾军人身份，政府未对蔡某某进行帮扶\n处罚：拘留15日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:46.230087+12
578	594	【中国文字狱事件记录】\n日期：2019年01月24日\n地点：黑龙江塔河县\n当事人：韩某\n平台：微信群\n言论内容：塔河县政府搞形象工程，蔡某某残疾军人身份，政府未对蔡某某进行帮扶\n处罚：拘留12日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:46.276229+12
579	595	【中国文字狱事件记录】\n日期：2019年01月24日\n地点：黑龙江龙江县\n当事人：孙某\n平台：网络\n言论内容：交警巡逻车视频；好狗带路呵呵呵呵\n处罚：抓获、后续不详	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:46.32164+12
580	596	【中国文字狱事件记录】\n日期：2019年01月25日\n地点：河北玉田县\n当事人：吴某\n平台：推特\n言论内容：“煽动颠覆国家政权、推翻社会主义制度的内容”\n处罚：刑事拘留\n备注：检方以寻衅滋事罪提起公诉，法院判定其涉嫌煽颠罪，要求重新调查\n法律文书：（2019）冀0229刑初370号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:46.368002+12
582	598	【中国文字狱事件记录】\n日期：2019年01月26日\n地点：湖北潜江\n当事人：朱某祖\n平台：网络\n言论内容：针对习近平的侮辱、诽谤性言论\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:46.458384+12
583	599	【中国文字狱事件记录】\n日期：2019年01月28日\n地点：甘肃会宁县\n当事人：梁某\n平台：微信群\n言论内容：“辱骂负伤民警”的言论\n处罚：拘留13日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:46.504099+12
584	600	【中国文字狱事件记录】\n日期：2019年01月28日\n地点：河南许昌\n当事人：刘某\n平台：微博\n言论内容：“辱警言论”\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:46.550287+12
585	601	【中国文字狱事件记录】\n日期：2019年01月28日\n地点：湖北武汉\n当事人：郭宪华\n平台：现实/贴大字报\n言论内容：两张标题为“中华人民联合宣言”的“反党反政府”图文\n处罚：有期徒刑2年\n法律文书：（2019）鄂0105刑初55号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:46.596349+12
586	602	【中国文字狱事件记录】\n日期：2019年01月29日\n地点：湖北当阳\n当事人：金某\n平台：朋友圈\n言论内容：育溪狗子在拦车\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:46.641658+12
587	603	【中国文字狱事件记录】\n日期：2019年01月29日\n地点：湖北随州\n当事人：刘飞跃（民生观察创始人）\n平台：民生观察网\n言论内容：大量中共迫害异见人士内容\n处罚：有期徒刑5年	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:46.687752+12
588	604	【中国文字狱事件记录】\n日期：2019年02月01日\n地点：黑龙江齐齐哈尔\n当事人：王鹏\n平台：贴吧\n言论内容：举报市财政局副局长姜某贪污腐败\n处罚：拘留7日、罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:46.732061+12
589	605	【中国文字狱事件记录】\n日期：2019年02月05日\n地点：新疆沙湾县\n当事人：胡某\n平台：朋友圈\n言论内容：大年三十你说你装什么x呢；艹你先人，呸，恶心\n处罚：拘留15日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:46.781246+12
590	606	【中国文字狱事件记录】\n日期：2019年02月06日\n地点：浙江衢州\n当事人：王某\n平台：微信群\n言论内容：当地政府不重视民生\n处罚：拘留6日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:46.826304+12
591	607	【中国文字狱事件记录】\n日期：2019年02月06日\n地点：内蒙古通辽\n当事人：丁某\n平台：电话\n言论内容：110啊，我XXX（脏话）……\n处罚：拘留15日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:46.871502+12
592	608	【中国文字狱事件记录】\n日期：2019年02月11日\n地点：贵州兴义市\n当事人：董某\n平台：朋友圈\n言论内容：“违背、歪曲上级党委政府的决策，丑化党和国家形象的言论”\n处罚：党内严重警告	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:46.918341+12
593	609	【中国文字狱事件记录】\n日期：2019年02月12日\n地点：广东汕头\n当事人：冯某\n平台：现实/街头涂写\n言论内容：侮辱党旗和国旗，辱骂党和政府、官员和军队的字句\n处罚：有期徒刑1年3个月\n备注：被捕时拒捕\n法律文书：（2019）粤05刑终19号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:46.962521+12
594	610	【中国文字狱事件记录】\n日期：2019年02月15日\n地点：浙江仙居县\n当事人：朱某\n平台：朋友圈\n言论内容：让这帮王八蛋（交警）空手而归；精诚合作，驱逐日狗\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:47.006948+12
595	611	【中国文字狱事件记录】\n日期：2019年02月16日\n地点：河北灵寿县\n当事人：张某\n平台：快手\n言论内容：XX保平安；有血统，有证的，警犬\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:47.050889+12
596	612	【中国文字狱事件记录】\n日期：2019年02月20日\n地点：河南孟津县\n当事人：周进锋\n平台：中国聚焦民生网\n言论内容：帮他人发表：新安县仓头镇中学老师打学生和举报地方官员的信息\n处罚：有期徒刑6个月\n法律文书：（2019）豫0322刑初11号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:47.100431+12
597	613	【中国文字狱事件记录】\n日期：2019年02月20日\n地点：陕西西安\n当事人：赵某\n平台：微博\n言论内容：“辱骂民警”\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:47.146788+12
598	614	【中国文字狱事件记录】\n日期：2019年02月22日\n地点：吉林桦甸\n当事人：卢某\n平台：微信群\n言论内容：警察打人视频\n处罚：拘留10日、罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:47.192367+12
599	615	【中国文字狱事件记录】\n日期：2019年02月22日\n地点：浙江温州\n当事人：蔡某\n平台：朋友圈\n言论内容：这两个人是诈骗犯，他们有两个同伙（司法人员）坐在他们右边\n处罚：司法拘留15日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:47.239113+12
600	616	【中国文字狱事件记录】\n日期：2019年02月22日\n地点：广东廉江市\n当事人：黄石海\n平台：朋友圈\n言论内容：（图片）头部为习某某，一个上身赤裸且有纹身，右手拿大刀，刀口朝下，姿态站立是男性\n处罚：有期徒刑6个月、缓刑6个月\n法律文书：（2019）粤0881刑初40号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:47.284772+12
601	617	【中国文字狱事件记录】\n日期：2019年02月26日\n地点：辽宁大石桥市\n当事人：战某\n平台：微信群\n言论内容：（视频）警察在截车,你看那警察像狗似的,吓不吓人\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:47.328827+12
602	618	【中国文字狱事件记录】\n日期：2019年02月26日\n地点：山东临沂\n当事人：孟某（街道处办事员）\n身份：公职人员/事业单位人员\n平台：贴吧\n言论内容：平邑政府腐败、不作为等\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:47.374072+12
603	619	【中国文字狱事件记录】\n日期：2019年02月27日\n地点：宁夏银川\n当事人：成某\n平台：QQ群\n言论内容：“辱骂国家、国家领导人、侮辱妄议社会及首都形象以及表达自杀意向的信息言论”\n处罚：有期徒刑1年，缓刑1年\n法律文书：（2019）宁0105刑初37号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:47.421782+12
604	620	【中国文字狱事件记录】\n日期：2019年02月27日\n地点：江西奉新县\n当事人：余某\n平台：微博\n言论内容：《赤裸裸的权利大谋杀冤案》《江西省公安厅玩忽职守非法行政渎职侵权犯罪》\n处罚：有期徒刑1年、缓刑3年\n法律文书：（2018）赣0921刑初214号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:47.468637+12
605	621	【中国文字狱事件记录】\n日期：2019年02月27日\n地点：安徽宿松县\n当事人：贺某贵\n平台：朋友圈\n言论内容：妈的，出门被宿松三中对狗咬一口\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:47.513427+12
606	622	【中国文字狱事件记录】\n日期：2019年02月28日\n地点：江西德兴市\n当事人：董某\n平台：网络\n言论内容：（视频）其打快板的视频，文字内容属于“谣言”\n处罚：拘留15日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:47.558392+12
607	624	【中国文字狱事件记录】\n日期：2019年03月01日\n地点：清华大学\n当事人：许章润\n身份：学者/教师\n平台：现实/课堂、公开演讲\n言论内容：再度修宪，平反六四，杜绝“大撒币”，实施官员财产阳光法案\n处罚：停职	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:47.653311+12
608	625	【中国文字狱事件记录】\n日期：2019年03月02日\n地点：四川南充\n当事人：柯某\n平台：朋友圈\n言论内容：老子的车你都敢开罚单，你这交警还想不想干了\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:47.695891+12
609	626	【中国文字狱事件记录】\n日期：2019年03月04日\n地点：四川仁寿县\n当事人：贾某\n平台：微信群\n言论内容：（视频）杨某的三轮车电瓶被交警查扣后自行抢了出来，警方现场处置情景\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:47.740843+12
610	627	【中国文字狱事件记录】\n日期：2019年03月04日\n地点：广东佛山\n当事人：杨兆星\n平台：推特\n言论内容：关注、转发、评论有关我国政党、政权、国家领导人的虚假信息\n处罚：有期徒刑10个月\n法律文书：(2019)粤0605刑初639号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:47.78684+12
611	628	【中国文字狱事件记录】\n日期：2019年03月05日\n地点：湖北黄梅县\n当事人：梁万茂\n平台：天涯社区\n言论内容：《向中央扫黑除恶第七督导组一份公开控告信》\n处罚：拘留15日\n法律文书：梅公（孔垅）行罚决字[2019]660号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:47.831134+12
612	629	【中国文字狱事件记录】\n日期：2019年03月06日\n地点：甘肃永靖县\n当事人：赵某\n平台：微博\n言论内容：川城镇贪污腐败，扶贫工作不到位\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:47.876711+12
613	630	【中国文字狱事件记录】\n日期：2019年03月07日\n地点：辽宁沈阳\n当事人：丁某\n平台：微信群\n言论内容：那警察就鸡吧跟狗似的，都开2枪给人打死了，还给人按地上又骂又打的，警察是真鸡吧怕死\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:47.922684+12
614	631	【中国文字狱事件记录】\n日期：2019年03月07日\n地点：天津\n当事人：张某\n平台：微信群\n言论内容：这位义士值得敬佩，干死这帮穿着狗皮的畜生，干死一个够本，杀两个赚一个\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:47.968927+12
615	632	【中国文字狱事件记录】\n日期：2019年03月08日\n地点：黑龙江佳木斯\n当事人：刘某\n平台：微信群\n言论内容：才撞死一个\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:48.013098+12
616	633	【中国文字狱事件记录】\n日期：2019年03月08日\n地点：山东烟台\n当事人：王某\n平台：微信群\n言论内容：“辱骂已故国家领导人”\n处罚：“相应处罚”	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:48.056948+12
617	634	【中国文字狱事件记录】\n日期：2019年03月09日\n地点：四川巴中\n当事人：朱某\n平台：微信群\n言论内容：日本天皇万岁，中国共产党的公安该死\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:48.102971+12
618	635	【中国文字狱事件记录】\n日期：2019年03月12日\n地点：广东深圳\n当事人：胡某军\n平台：微信群\n言论内容：“虚假信息”\n处罚：有期徒刑11个月\n法律文书：（2019）粤0307刑初477号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:48.149193+12
619	636	【中国文字狱事件记录】\n日期：2019年03月12日\n地点：青海民和县\n当事人：裴某\n平台：快手\n言论内容：发布7条视频，“无端指责、诋毁政府，丑化党的形象，并肆意辱骂、威胁我乡政府工作人员”\n处罚：拘留15日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:48.194209+12
620	637	【中国文字狱事件记录】\n日期：2019年03月13日\n地点：江苏海安市\n当事人：李某\n平台：微信群\n言论内容：狗日的鬼子又上路抓礼让行人了\n处罚：治安拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:48.241996+12
621	638	【中国文字狱事件记录】\n日期：2019年03月14日\n地点：福建泉州\n当事人：杨某\n平台：微博\n言论内容：泉州这个交警很厉害!冒昧问一句，你们这个有业绩考核吗?见面都只想说一句牛(la)逼(ji)\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:48.289212+12
622	639	【中国文字狱事件记录】\n日期：2019年03月15日\n地点：浙江江山市\n当事人：徐某\n平台：朋友圈\n言论内容：（交警执勤视频）三头狼仔\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:48.334401+12
623	640	【中国文字狱事件记录】\n日期：2019年03月18日\n地点：辽宁葫芦岛\n当事人：郑某\n平台：推特\n言论内容：“侮辱、辱骂国家领导人的推文163条”\n处罚：起诉（寻衅滋事罪）\n法律文书：葫连检公诉刑诉〔2019〕64号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:48.379011+12
624	641	【中国文字狱事件记录】\n日期：2019年03月19日\n地点：广东徐闻县\n当事人：沈某干\n平台：微信群\n言论内容：用“辱警言论”为一段执法视频配音\n处罚：拘留15日、罚款1000元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:48.424352+12
625	642	【中国文字狱事件记录】\n日期：2019年03月19日\n地点：甘肃永靖县\n当事人：王某\n平台：快手\n言论内容：永靖腐败！腐败！建档立卡户五万元无息贷款谁家拿到了？没有拿到的赶紧转起\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:48.470509+12
626	643	【中国文字狱事件记录】\n日期：2019年03月19日\n地点：湖北建始县\n当事人：鲁某\n平台：朋友圈\n言论内容：小西口碰到狗了；交警啊\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:48.517339+12
627	644	【中国文字狱事件记录】\n日期：2019年03月20日\n地点：浙江康恒律师事务所\n当事人：竺修远\n身份：律师\n平台：推特\n言论内容：为多条“侮辱党和国家领导人的有害信息”点赞\n处罚：通报警告	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:48.561465+12
628	645	【中国文字狱事件记录】\n日期：2019年03月20日\n地点：江西鄱阳县\n当事人：蔡某\n平台：朋友圈\n言论内容：卧槽什么鬼东西，老娘骑个电动车也给我来这一出，她妈的鄱阳交警是傻逼吗，吃屎吧\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:48.60763+12
629	646	【中国文字狱事件记录】\n日期：2019年03月20日\n地点：重庆师范大学\n当事人：唐云\n身份：学者/教师\n平台：现实/课堂\n言论内容：在《鲁迅研究》课程里发表“损害国家声誉”的言论\n处罚：吊销教师资格证	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:48.651255+12
630	647	【中国文字狱事件记录】\n日期：2019年03月20日\n地点：河南新乡\n当事人：何方美\n平台：网络、现实\n言论内容：在王府井募捐、创建维权团体等\n背景事件：其女被毒疫苗致残\n处罚：刑事拘留\n备注：2020/1/10撤诉获释	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:48.696958+12
631	648	【中国文字狱事件记录】\n日期：2019年03月20日\n地点：浙江海翔律师事务所\n当事人：平易\n身份：律师\n平台：郭媒体\n言论内容：仅注册\n处罚：通报警告	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:48.742645+12
632	649	【中国文字狱事件记录】\n日期：2019年03月23日\n地点：河北石家庄\n当事人：孙愿平\n平台：推特\n言论内容：涉政不当言论\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:48.78894+12
633	650	【中国文字狱事件记录】\n日期：2019年03月25日\n地点：四川成都\n当事人：李仁宗\n平台：微信\n言论内容：不详，官方称是“侮辱他人”的言论，当事人坚称是批评政府的言论\n处罚：拘留5日\n法律文书：成双公（九）行罚决字〔2019〕1423号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:48.834178+12
636	653	【中国文字狱事件记录】\n日期：2019年03月27日\n地点：四川遂溪县\n当事人：庞志勇\n平台：无界一点通\n言论内容：使用无界一点通浏览境外网站，未发布内容\n处罚：传唤警告	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:48.95822+12
637	654	【中国文字狱事件记录】\n日期：2019年03月27日\n地点：广西百色\n当事人：吴某\n平台：朋友圈\n言论内容：土匪一帮（指交警）\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:48.998649+12
638	655	【中国文字狱事件记录】\n日期：2019年03月28日\n地点：福建泉州\n当事人：施根源\n平台：脸书、推特\n言论内容：“歪曲国家重大事件，攻击 党和国家领导人，炒作敏感事件“\n处罚：有期徒刑3年\n法律文书：（2019）闽0503刑初137号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:49.040321+12
639	656	【中国文字狱事件记录】\n日期：2019年03月29日\n地点：广西梧州\n当事人：袁某\n平台：微信群\n言论内容：地交警系XXX骑\n处罚：拘留6日\n法律文书：https://mp.weixin.qq.com/s/43qTzjGipuem3hVDzFnxGA	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:49.100716+12
640	657	【中国文字狱事件记录】\n日期：2019年03月29日\n地点：内蒙古通辽\n当事人：张某\n平台：微信群\n言论内容：“扣河子镇政府部门工作人员警匪一家，欺压百姓”的视频和文字\n处罚：拘留5日、罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:49.155942+12
641	658	【中国文字狱事件记录】\n日期：2019年03月29日\n地点：河南商丘\n当事人：秦来宾\n平台：推特\n言论内容：多条推特言论（涉及政治）\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:49.201138+12
642	659	【中国文字狱事件记录】\n日期：2019年03月30日\n地点：山西保德县\n当事人：张某山\n平台：朋友圈\n言论内容：（视频）忻口这儿，撞死5、6个人，堵成铁壳，哪儿也走不了，半夜也回不去，撞死好几个\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:49.254016+12
643	660	【中国文字狱事件记录】\n日期：2019年04月01日\n地点：四川攀枝花\n当事人：郑某\n平台：QQ群\n言论内容：又有几十个富婆了\n背景事件：四川木里森林大火\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:49.298325+12
644	661	【中国文字狱事件记录】\n日期：2019年04月01日\n地点：四川成都\n当事人：陈兵\n平台：微信、现实\n言论内容：自制一款名为“铭记八酒六四”的白酒，定价为89.64元在微信销售\n背景事件：六四事件\n处罚：有期徒刑3年6个月	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:49.343482+12
645	662	【中国文字狱事件记录】\n日期：2019年04月01日\n地点：四川成都\n当事人：符海陆\n平台：微信、现实\n言论内容：自制一款名为“铭记八酒六四”的白酒，定价为89.64元在微信销售\n背景事件：六四事件\n处罚：有期徒刑3年、缓刑5年	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:49.387804+12
646	663	【中国文字狱事件记录】\n日期：2019年04月01日\n地点：江西赣州\n当事人：严某\n平台：微博\n言论内容：当地法官罗某与其有私人关系\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:49.437437+12
647	664	【中国文字狱事件记录】\n日期：2019年04月02日\n地点：四川成都\n当事人：张隽勇\n平台：微信、现实\n言论内容：自制一款名为“铭记八酒六四”的白酒，定价为89.64元在微信销售\n背景事件：六四事件\n处罚：有期徒刑3年、缓刑4年	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:49.482546+12
648	665	【中国文字狱事件记录】\n日期：2019年04月02日\n地点：云南镇雄县\n当事人：黄某\n平台：微信公众平台\n言论内容：“打你吓你，问你怕否，似土匪下山不走”……（发表于2017年7月）\n处罚：拘留14日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:49.533993+12
649	666	【中国文字狱事件记录】\n日期：2019年04月02日\n地点：甘肃陇南\n当事人：刘某\n平台：微信群\n言论内容：“过激不当言论”\n背景事件：四川木里森林大火\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:49.579512+12
650	667	【中国文字狱事件记录】\n日期：2019年04月02日\n地点：广西梧州\n当事人：钟某\n平台：微博\n言论内容：自身素质跟不上，不能成英雄\n背景事件：四川木里森林大火\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:49.62456+12
651	668	【中国文字狱事件记录】\n日期：2019年04月02日\n地点：广西梧州\n当事人：钟某\n平台：朋友圈\n言论内容：牺牲又能证明什么\n背景事件：四川木里森林大火\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:49.668868+12
652	669	【中国文字狱事件记录】\n日期：2019年04月02日\n地点：福建泉州\n当事人：尹某云\n平台：百度\n言论内容：”侮辱救火英雄“\n背景事件：四川木里森林大火\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:49.715519+12
653	670	【中国文字狱事件记录】\n日期：2019年04月03日\n地点：四川成都\n当事人：罗富誉\n平台：微信、现实\n言论内容：自制一款名为“铭记八酒六四”的白酒，定价为89.64元在微信销售\n处罚：有期徒刑3年、缓刑4年	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:49.760222+12
654	671	【中国文字狱事件记录】\n日期：2019年04月03日\n地点：陕西延安\n当事人：孙某发\n平台：懂球帝\n言论内容：唉，能烧尽量多烧死一点\n背景事件：四川木里森林大火\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:49.804003+12
655	672	【中国文字狱事件记录】\n日期：2019年04月03日\n地点：辽宁大连\n当事人：魏琪\n平台：推特\n言论内容：100余条”反党、反共、侮辱国家领导人和其它类型的不当言论“内容\n处罚：有期徒刑6个月\n法律文书：(2019)辽0291刑初146号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:49.847323+12
656	673	【中国文字狱事件记录】\n日期：2019年04月03日\n地点：河北保定\n当事人：霍某\n平台：朋友圈\n言论内容：死了好，不然当官都是祸害\n背景事件：四川木里森林大火\n处罚：拘留15日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:49.892021+12
657	674	【中国文字狱事件记录】\n日期：2019年04月03日\n地点：重庆\n当事人：唐某\n平台：朋友圈\n言论内容：”侮辱牺牲消防员“\n背景事件：四川木里森林大火\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:49.937407+12
658	675	【中国文字狱事件记录】\n日期：2019年04月03日\n地点：广西贵港\n当事人：陈某\n平台：朋友圈\n言论内容：（其本人炫摩托车技视频，无危险或违章动作）挑战全贵港交警，，，，我说的\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:49.981039+12
659	676	【中国文字狱事件记录】\n日期：2019年04月03日\n地点：江西南昌县\n当事人：王一飞（兴华会创始人）\n平台：现实/喷涂、张贴\n言论内容：平反六四。结束一党专政等（落款兴华会）\n背景事件：六四事件\n处罚：有期徒刑2年\n法律文书：（2019）赣0121刑初70号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:50.026586+12
660	1889	【中国文字狱事件记录】\n日期：2020年03月13日\n地点：山东泰安\n当事人：张某\n平台：不详\n言论内容：虚构事实\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:51.023072+12
688	704	【中国文字狱事件记录】\n日期：2019年04月13日\n地点：广西阳朔县\n当事人：俸某\n平台：微信群\n言论内容：这野仔的又搞电动车伞了\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:51.323057+12
661	677	【中国文字狱事件记录】\n日期：2019年04月03日\n地点：河南滑县\n当事人：肖某\n平台：推特\n言论内容：“抨击我国宪法、攻击我国现行法律体系、损害国家领导人形象等混淆视听的虚假信息”\n处罚：起诉（寻衅滋事罪）\n法律文书：安滑检公诉刑诉〔2019〕151号 	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:50.070447+12
662	678	【中国文字狱事件记录】\n日期：2019年04月04日\n地点：四川成都\n当事人：罗富誉\n平台：微信、现实\n言论内容：自制一款名为“铭记八酒六四”的白酒，定价为89.64元在微信销售\n处罚：有期徒刑3年	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:50.118444+12
663	679	【中国文字狱事件记录】\n日期：2019年04月04日\n地点：广东中山\n当事人：曾某\n平台：微信群\n言论内容：这30个人不是救火死的，是在里面预约啪啪啪，烧死的；没少祸害老百姓；这年头只有祸害老百姓的英雄，没有真正的英雄\n背景事件：四川木里森林大火\n处罚：拘留15日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:50.167555+12
664	680	【中国文字狱事件记录】\n日期：2019年04月04日\n地点：苏州广播电台\n当事人：朱诚卓\n身份：公职人员/事业单位人员\n平台：推特\n言论内容：关注与浏览"非法网站上的有害信息"\n处罚：撤职降级	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:50.215356+12
665	681	【中国文字狱事件记录】\n日期：2019年04月04日\n地点：浙江瑞安市\n当事人：张辉\n平台：推特\n言论内容：习近平代表的中国的形象已经变成大撒币；等“编造谣言侮辱他人”的内容\n处罚：罚款300元\n法律文书：瑞公（陶）行罚决字［2019］51426号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:50.263166+12
666	682	【中国文字狱事件记录】\n日期：2019年04月04日\n地点：四川南充\n当事人：郑某\n平台：贴吧\n言论内容：搞钱要紧，看屁点烈士\n背景事件：四川木里森林大火\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:50.309762+12
667	683	【中国文字狱事件记录】\n日期：2019年04月04日\n地点：四川南充\n当事人：王某\n平台：陌陌\n言论内容：明天带上酱油，醋，红油，辣椒面，去吃火烧XXX，看看什么味道\n背景事件：四川木里森林大火\n处罚：拘留15日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:50.355806+12
668	684	【中国文字狱事件记录】\n日期：2019年04月05日\n地点：广东东莞\n当事人：褚某、黄某军、何某萍\n平台：QQ群、微信群\n言论内容：不实言论，煽动游行示威\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:50.40127+12
669	685	【中国文字狱事件记录】\n日期：2019年04月05日\n地点：陕西韩城市\n当事人：贾某平\n平台：微信群\n言论内容：“不当言论”\n处罚：拘留12日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:50.445671+12
670	686	【中国文字狱事件记录】\n日期：2019年04月06日\n地点：河南沈丘县\n当事人：徐某\n平台：微信群\n言论内容：制作发布一段“辱骂、指责、诋毁政府的视频”\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:50.491035+12
671	687	【中国文字狱事件记录】\n日期：2019年04月06日\n地点：广东广州\n当事人：刘某\n平台：微博\n言论内容：“不实信息，辱骂民警”\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:50.536882+12
672	688	【中国文字狱事件记录】\n日期：2019年04月06日\n地点：天津\n当事人：李某\n平台：微博\n言论内容：“侮辱在木里森林大火里牺牲的消防战士”\n背景事件：四川木里森林大火\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:50.584269+12
673	689	【中国文字狱事件记录】\n日期：2019年04月06日\n地点：四川南充\n当事人：王某英\n平台：陌陌\n言论内容：路又不是蒋飞飞他家开的；他要回来南充不要搞这么大的吧\n背景事件：四川木里森林大火\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:50.629456+12
674	690	【中国文字狱事件记录】\n日期：2019年04月07日\n地点：广西田林县\n当事人：陆某彬\n平台：微信群\n言论内容：都是吃屎的；一万人抓一个还是自首的\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:50.674233+12
675	691	【中国文字狱事件记录】\n日期：2019年04月08日\n地点：山西太原\n当事人：李志明\n平台：微信群\n言论内容：包子的五个女人\n处罚：6个月拘役	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:50.720765+12
676	692	【中国文字狱事件记录】\n日期：2019年04月08日\n地点：内蒙古呼和浩特\n当事人：麻某\n身份：网红\n平台：微博\n言论内容：好人不当兵，好铁不碾钉\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:50.764619+12
677	693	【中国文字狱事件记录】\n日期：2019年04月08日\n地点：河北保定\n当事人：李某\n平台：高阳县医院LED显示屏\n言论内容：支持中国的是傻逼，打倒中国帝国主义\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:50.809349+12
678	694	【中国文字狱事件记录】\n日期：2019年04月09日\n地点：浙江缙云县\n当事人：陶某\n平台：微信群\n言论内容：“侮辱”四川火灾牺牲英雄的言论\n处罚：拘留9日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:50.854712+12
679	695	【中国文字狱事件记录】\n日期：2019年04月10日\n地点：四川广元\n当事人：柳某\n平台：微信群\n言论内容：这点都做不到，死有余辜；该死不会动脑子\n背景事件：四川木里森林大火\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:50.900171+12
680	696	【中国文字狱事件记录】\n日期：2019年04月10日\n地点：福建永安\n当事人：王某\n平台：微信群\n言论内容：改编《常回家看看》讽刺交警\n处罚：拘留2日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:50.945552+12
681	697	【中国文字狱事件记录】\n日期：2019年04月10日\n地点：湖南长沙\n当事人：周某\n平台：微信群\n言论内容：“诋毁凉山救火英雄”\n背景事件：四川木里森林大火\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:50.992066+12
682	698	【中国文字狱事件记录】\n日期：2019年04月10日\n地点：云南华宁县\n当事人：金某\n平台：微信群\n言论内容：“不当言论”\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:51.038097+12
683	699	【中国文字狱事件记录】\n日期：2019年04月10日\n地点：湖南临武县\n当事人：邓某华、邓某文\n平台：抖音\n言论内容：一段警察审讯嫖娼者视频，由该二人扮演，其中有脏话\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:51.084072+12
684	700	【中国文字狱事件记录】\n日期：2019年04月11日\n地点：河北迁西县\n当事人：付某\n平台：快手\n言论内容：”辱警言论“\n处罚：拘留6日、罚款100元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:51.136906+12
685	701	【中国文字狱事件记录】\n日期：2019年04月11日\n地点：河南郑州\n当事人：白某恒等6人\n平台：现实\n言论内容：穿日本军装迎亲\n处罚：行政拘留与训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:51.185734+12
686	702	【中国文字狱事件记录】\n日期：2019年04月11日\n地点：陕西安康\n当事人：胡某荣\n平台：贴吧\n言论内容：”针对党和政府的攻击性、煽动性言论“\n处罚：拘留15日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:51.23245+12
687	703	【中国文字狱事件记录】\n日期：2019年04月12日\n地点：北京\n当事人：宋某\n平台：朋友圈\n言论内容：“辱骂交通协管员”\n处罚：拘留9日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:51.278525+12
689	705	【中国文字狱事件记录】\n日期：2019年04月14日\n地点：河南南阳\n当事人：贾某\n平台：微信群\n言论内容：要烧了市政府，杀了开发商\n背景事件：其2010年所购房屋至今未拿到房产证\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:51.368878+12
690	706	【中国文字狱事件记录】\n日期：2019年04月14日\n地点：云南昆明\n当事人：丁某\n平台：微博\n言论内容：东川区交警就是匪，就黑社会\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:51.412174+12
691	707	【中国文字狱事件记录】\n日期：2019年04月15日\n地点：云南党校\n当事人：子肃\n身份：党政官员\n平台：微信\n言论内容：《关于在中共十九大上开放党内民主直选和选举胡德平先生为新一届中共总书记的建议》\n处罚：有期徒刑四年	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:51.458594+12
692	708	【中国文字狱事件记录】\n日期：2019年04月16日\n地点：江苏南通\n当事人：曹建山\n平台：多个平台\n言论内容：申请公开3.21响水化工厂爆炸事故遇难者信息公开信\n背景事件：3.21响水化工厂爆炸\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:51.505221+12
693	709	【中国文字狱事件记录】\n日期：2019年04月16日\n地点：贵州威宁县\n当事人：林某\n平台：快手\n言论内容：“辱警视频”\n处罚：拘留13日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:51.551479+12
694	710	【中国文字狱事件记录】\n日期：2019年04月18日\n地点：广西河池\n当事人：周某\n平台：微信群\n言论内容：城管是非法组织，号召群友一起喊“打倒城管”\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:51.596211+12
695	711	【中国文字狱事件记录】\n日期：2019年04月18日\n地点：四川叙永县\n当事人：徐远芬\n平台：微信群\n言论内容：（视频）扶贫全部作假，搞数字脱贫；胥某在成为贫困户之后没有领过一分钱；等\n处罚：有期徒刑1年\n备注：二审维持原判\n法律文书：（2019）川05刑终91号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:51.641377+12
696	712	【中国文字狱事件记录】\n日期：2019年04月19日\n地点：四川丹棱县\n当事人：蒋建国\n平台：多个平台\n言论内容：《举报：眉山市鸿通房地产开发有限公司称霸眉山，无法无天》等多篇指控法院枉法裁判的文章\n处罚：有期徒刑2年、缓刑3年\n法律文书：（2019）川1424刑初13号；（2019）川14刑终86号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:51.687703+12
697	713	【中国文字狱事件记录】\n日期：2019年04月19日\n地点：江西万年县\n当事人：杨某、汪某\n平台：微信、现实\n言论内容：杨某穿着印有“误导性文字”的衣服躺在县政府门口；汪某拍摄视频发布至朋友圈\n处罚：依法处置	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:51.732392+12
698	714	【中国文字狱事件记录】\n日期：2019年04月19日\n地点：甘肃岷县\n当事人：吴某忠\n平台：微信群\n言论内容：“辱骂村干部”\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:51.776751+12
699	715	【中国文字狱事件记录】\n日期：2019年04月19日\n地点：江苏连云港\n当事人：齐某\n平台：朋友圈\n言论内容：马场桥头一群XX连三轮车都查，摩托车也查\n处罚：拘留15日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:51.821775+12
700	716	【中国文字狱事件记录】\n日期：2019年04月19日\n地点：江苏张家港\n当事人：陈某\n平台：朋友圈\n言论内容：第一次被狗咬（交通罚单照片）\n处罚：拘留2日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:51.865011+12
701	717	【中国文字狱事件记录】\n日期：2019年04月20日\n地点：青海海东\n当事人：田某\n平台：快手\n言论内容：马营狗见车就抓\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:51.909771+12
702	718	【中国文字狱事件记录】\n日期：2019年04月20日\n地点：贵州凯里\n当事人：潘某\n平台：朋友圈\n言论内容：狗杂种你有早餐吃了\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:51.954777+12
703	719	【中国文字狱事件记录】\n日期：2019年04月22日\n地点：河北沧州\n当事人：王某\n平台：微博\n言论内容：“两条关于沧州渤海新区南大港产业园区管委会依法收回李家堡村委会租用盐场土地一事的不实言论”\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:51.999587+12
704	720	【中国文字狱事件记录】\n日期：2019年04月22日\n地点：内蒙古呼伦贝尔\n当事人：王某\n平台：贴吧\n言论内容：“辱骂交警”\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:52.045172+12
705	721	【中国文字狱事件记录】\n日期：2019年04月23日\n地点：广西宜州市\n当事人：周某\n平台：微信群\n言论内容：如果有一个带头哥出来喊“打倒城管”，你看天下就定没“城管”来；因为城管的成立是不合法的，这邪恶的部门\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:52.092007+12
706	722	【中国文字狱事件记录】\n日期：2019年04月23日\n地点：广西平果县\n当事人：许某\n平台：朋友圈\n言论内容：（交警执勤视频）一帮土X\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:52.141951+12
707	723	【中国文字狱事件记录】\n日期：2019年04月24日\n地点：广西德保县\n当事人：李某\n平台：微信群\n言论内容：（视频）狗查车\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:52.188468+12
708	724	【中国文字狱事件记录】\n日期：2019年04月24日\n地点：广西贺州\n当事人：温泉\n平台：红豆社区\n言论内容：《严正抗议贺州市政府借扫黑除恶名义涉黑行恶》等四个帖子，指控当地政府腐败、涉黑和保护黑恶势力\n处罚：拘留12日\n法律文书：贺公八行罚决字〔2019〕00683号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:52.233537+12
709	725	【中国文字狱事件记录】\n日期：2019年04月25日\n地点：山东济南\n当事人：卞旭苹\n平台：QQ群\n言论内容：郭文贵爆料内容\n背景事件：郭文贵爆料事件\n处罚：有期徒刑1年7个月\n备注：二审维持原判\n法律文书：（2018）鲁0112刑初430号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:52.278519+12
710	726	【中国文字狱事件记录】\n日期：2019年04月25日\n地点：山东济南\n当事人：严某\n平台：QQ群\n言论内容：郭文贵爆料内容\n背景事件：郭文贵爆料事件\n处罚：拘役3个月\n备注：二审维持原判\n法律文书：（2018）鲁0112刑初430号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:52.322341+12
711	727	【中国文字狱事件记录】\n日期：2019年04月25日\n地点：山东济南\n当事人：张某\n平台：QQ群\n言论内容：郭文贵爆料内容\n背景事件：郭文贵爆料事件\n处罚：有期徒刑1年\n备注：二审维持原判\n法律文书：（2018）鲁0112刑初430号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:52.36621+12
712	728	【中国文字狱事件记录】\n日期：2019年04月25日\n地点：山东济南\n当事人：孙某\n平台：QQ群\n言论内容：郭文贵爆料内容\n背景事件：郭文贵爆料事件\n处罚：有期徒刑1年7个月\n备注：二审维持原判\n法律文书：（2018）鲁0112刑初430号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:52.40977+12
713	729	【中国文字狱事件记录】\n日期：2019年04月25日\n地点：山东济南\n当事人：殷某\n平台：QQ群\n言论内容：郭文贵爆料内容\n背景事件：郭文贵爆料事件\n处罚：有期徒刑1年7个月\n备注：二审维持原判\n法律文书：（2018）鲁0112刑初430号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:52.454108+12
714	757	【中国文字狱事件记录】\n日期：2019年05月14日\n地点：安徽阜阳\n当事人：班某东\n平台：朋友圈\n言论内容：“给狗取名‘城管’和‘协管’并发到朋友圈”\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:54.021775+12
715	730	【中国文字狱事件记录】\n日期：2019年04月25日\n地点：山东济南\n当事人：黎某\n平台：QQ群\n言论内容：郭文贵爆料内容\n背景事件：郭文贵爆料事件\n处罚：有期徒刑1年\n备注：二审维持原判\n法律文书：（2018）鲁0112刑初430号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:52.499003+12
716	731	【中国文字狱事件记录】\n日期：2019年04月26日\n地点：广西河池\n当事人：莫某\n平台：微信群\n言论内容：凤山法院太黑、这个社会有钱杀人都可以不负责任了\n处罚：行政拘留（不执行）	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:52.543669+12
717	732	【中国文字狱事件记录】\n日期：2019年04月26日\n地点：山东威海\n当事人：候某\n平台：微信群\n言论内容：一段自家回迁房地暖管路较少的视频以及“不实言论”\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:52.586541+12
718	733	【中国文字狱事件记录】\n日期：2019年04月27日\n地点：浙江温州\n当事人：黄美玲\n平台：微信群\n言论内容：村改居不能改，前腐后续变更土地资产转移……官商勾结欺骗手段，镇压村民\n处罚：拘留9日\n法律文书：温龙公（永）行罚决字[2019]50990号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:52.692474+12
719	734	【中国文字狱事件记录】\n日期：2019年04月27日\n地点：北京\n当事人：马萧（谢强）\n平台：网络、现实\n言论内容：多篇政治作品；大量关于中国政治犯的报道\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:52.744517+12
720	735	【中国文字狱事件记录】\n日期：2019年04月28日\n地点：陕西商洛\n当事人：孔某\n平台：微信\n言论内容：煽动性言论与视频\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:52.795931+12
721	736	【中国文字狱事件记录】\n日期：2019年04月28日\n地点：河北沧州\n当事人：位某\n平台：微博\n言论内容：“一条关于中捷拆迁楼产权问题的不实言论，并诋毁党委政府形象”\n处罚：拘留15日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:52.842872+12
722	737	【中国文字狱事件记录】\n日期：2019年04月30日\n地点：湖北武汉\n当事人：何灯超\n平台：推特\n言论内容：（转发）郭文贵爆料内容\n背景事件：郭文贵爆料事件\n处罚：拘留10日\n法律文书：岸公(塔)行罚决字[2019]14236号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:52.888645+12
723	738	【中国文字狱事件记录】\n日期：2019年05月01日\n地点：辽宁大连\n当事人：卢世宁\n身份：境外人士\n平台：不详\n言论内容：“辱华”、“反华”漫画以及“精日”言论\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:52.936809+12
724	739	【中国文字狱事件记录】\n日期：2019年05月01日\n地点：辽宁丹东\n当事人：于某\n平台：现实/街头使用喇叭播放\n言论内容：“有关内容”官方称谣言\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:52.980059+12
725	740	【中国文字狱事件记录】\n日期：2019年05月02日\n地点：四川成都\n当事人：唐某\n平台：微博\n言论内容：今日成都漫展 匿名（附图为多张穿着暴露的女性，警方称实为日本漫展）\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:53.026619+12
726	741	【中国文字狱事件记录】\n日期：2019年05月03日\n地点：贵州德江县\n当事人：晏某\n平台：朋友圈\n言论内容：大中午被狗咬两口\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:53.068671+12
727	742	【中国文字狱事件记录】\n日期：2019年05月05日\n地点：山西泽州县\n当事人：吴某阳\n平台：微信群\n言论内容：（交通事故视频）死了10个人，快管管吧\n处罚：传唤、后续不详	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:53.111615+12
728	743	【中国文字狱事件记录】\n日期：2019年05月06日\n地点：河北故城县\n当事人：堵某\n平台：朋友圈\n言论内容：“一段交警执法的视频，其中他对交警进行辱骂”\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:53.155275+12
729	744	【中国文字狱事件记录】\n日期：2019年05月07日\n地点：甘肃礼县\n当事人：马某\n平台：快手\n言论内容：“侮辱民警的言论”\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:53.42419+12
730	745	【中国文字狱事件记录】\n日期：2019年05月08日\n地点：内蒙古呼和浩特\n当事人：赵某\n身份：公职人员/事业单位人员\n平台：微信群\n言论内容：一段改编自《常回家看看》的歌词，用于讽调侃交警\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:53.474276+12
731	746	【中国文字狱事件记录】\n日期：2019年05月08日\n地点：天津\n当事人：杨某\n平台：抖音、今日头条\n言论内容：”辱骂消防员“\n处罚：拘留15日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:53.524904+12
732	747	【中国文字狱事件记录】\n日期：2019年05月10日\n地点：青海海东\n当事人：李某寿\n平台：微信群\n言论内容：“辱骂乡政府工作人员”\n处罚：拘留7日、罚款300元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:53.571833+12
733	748	【中国文字狱事件记录】\n日期：2019年05月10日\n地点：江西龙南县\n当事人：郭庆军\n平台：脸书、推特\n言论内容：“雷洋之死歌曲”及“中国特色社会主义株连九族罪”\n背景事件：雷洋案\n处罚：有期徒刑1年6个月	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:53.618175+12
734	749	【中国文字狱事件记录】\n日期：2019年05月10日\n地点：江苏连云港\n当事人：赵斌\n平台：朋友圈\n言论内容：交警真是草死你妈的逼了\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:53.664259+12
735	750	【中国文字狱事件记录】\n日期：2019年05月11日\n地点：陕西安康\n当事人：李某安、张某\n平台：微信群\n言论内容：李某安发布一段强拆现场警民冲突视频；张某作为群主没有制止和举报\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:53.708568+12
736	751	【中国文字狱事件记录】\n日期：2019年05月11日\n地点：广东深圳\n当事人：匿名网友\n平台：推特\n言论内容：关于六四事件内容\n背景事件：六四事件\n处罚：拘留15日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:53.753548+12
737	752	【中国文字狱事件记录】\n日期：2019年05月13日\n地点：河南平舆县\n当事人：朱雪峰\n平台：天涯、大河网等\n言论内容：《举报河南省平舆县十字路乡党委书记韩某》等文章，反映该县环境污染问题、政府部门用人问题等\n处罚：有罪免罚\n备注：二审维持原判\n法律文书：（2018）豫1723刑初600号；（2019）豫17刑终384号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:53.79868+12
738	753	【中国文字狱事件记录】\n日期：2019年05月13日\n地点：山东禹城市\n当事人：张某\n平台：微信群\n言论内容：（转发）一段9秒的车祸视频\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:53.843206+12
739	754	【中国文字狱事件记录】\n日期：2019年05月13日\n地点：山东禹城市\n当事人：李某\n平台：微信群\n言论内容：（视频）别走市中路南延了，是不是撞车了\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:53.889523+12
740	755	【中国文字狱事件记录】\n日期：2019年05月13日\n地点：河南修武县\n当事人：祝某\n平台：微信群\n言论内容：xxx二中队哪都去他xxx\n处罚：拘留8日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:53.934146+12
741	756	【中国文字狱事件记录】\n日期：2019年05月14日\n地点：甘肃西和县\n当事人：任某\n平台：微博\n言论内容：“抹黑西和形象的言论”\n处罚：拘留8日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:53.977666+12
742	758	【中国文字狱事件记录】\n日期：2019年05月15日\n地点：江苏南京\n当事人：戴某翼\n平台：微博\n言论内容：南京大屠杀是假的\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:54.065042+12
743	759	【中国文字狱事件记录】\n日期：2019年05月16日\n地点：安徽合肥\n当事人：沈良庆\n身份：党政官员（退休）\n平台：不详\n言论内容：疑与六四有关言论\n背景事件：六四事件\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:54.111659+12
744	760	【中国文字狱事件记录】\n日期：2019年05月16日\n地点：广西北海\n当事人：花某\n平台：微信群\n言论内容：称警察为“狗叼”\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:54.158504+12
745	761	【中国文字狱事件记录】\n日期：2019年05月16日\n地点：河南商丘\n当事人：张某\n平台：推特\n言论内容：“侮辱党和国家领导人的有害信息”\n处罚：起诉（寻衅滋事罪）\n法律文书：商梁检一部刑诉〔2019〕39号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:54.213621+12
746	762	【中国文字狱事件记录】\n日期：2019年05月17日\n地点：浙江海宁市\n当事人：沈百明\n平台：天涯社区\n言论内容：《浙江省嘉兴海宁法制沦为空谈，党员干部小偷败类横行官官相护，无法无天！》等帖子\n处罚：拘留12日\n法律文书：海公（村）行罚决字[2019]51602号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:54.258247+12
747	763	【中国文字狱事件记录】\n日期：2019年05月17日\n地点：四川珙县\n当事人：杨体和\n平台：微信群、脸书\n言论内容：在脸书转发多条反共信息，包括声援王全璋等，放任自己的两个微信群群员发表涉政有害信息\n背景事件：709大抓捕\n处罚：拘留10日\n法律文书：珙县公（国）行罚决字【2019】001号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:54.307435+12
748	764	【中国文字狱事件记录】\n日期：2019年05月17日\n地点：河北献县\n当事人：张某\n平台：快手\n言论内容：“侮辱城管人员的视频”\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:54.35381+12
749	765	【中国文字狱事件记录】\n日期：2019年05月18日\n地点：浙江德清县\n当事人：何某\n平台：网络\n言论内容：村干部贪污、挪用公款、乱办补助等事\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:54.397558+12
750	766	【中国文字狱事件记录】\n日期：2019年05月20日\n地点：湖南岳阳县\n当事人：黄某林\n平台：朋友圈\n言论内容：妈了个巴子，一早起来被狗咬（交通违章罚单照片）\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:54.4425+12
751	767	【中国文字狱事件记录】\n日期：2019年05月20日\n地点：山东烟台\n当事人：刘淑静\n身份：法轮功学员\n平台：现实\n言论内容：反对中共及宣传法轮功标语（通过人民币传播）\n处罚：有期徒刑2年\n法律文书：（2019）鲁0613刑初65号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:54.487282+12
752	768	【中国文字狱事件记录】\n日期：2019年05月21日\n地点：广东汕头\n当事人：姚章龙\n平台：微信公众平台\n言论内容：“政府不作为”“相关媒体发布受灾信息全被封杀”“当地政府官员阻止救援”“义工被政府劝退”“靠政府还不如拜老爷”等\n背景事件：830潮汕水灾\n处罚：有期徒刑1年6个月\n法律文书：（2019）粤0514刑初226号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:54.534822+12
753	769	【中国文字狱事件记录】\n日期：2019年05月23日\n地点：江苏泰州\n当事人：李某\n平台：朋友圈\n言论内容：（警察检查消防的视频）这就是现在法律这些狗\n处罚：拘留6日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:54.580412+12
754	770	【中国文字狱事件记录】\n日期：2019年05月24日\n地点：青海互助县\n当事人：梅某\n平台：微信群\n言论内容：”辱骂“村干部\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:54.625033+12
755	771	【中国文字狱事件记录】\n日期：2019年05月27日\n地点：山东日照\n当事人：刘某\n平台：微信群、抖音\n言论内容：“侮辱”村干部的言论\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:54.671022+12
756	772	【中国文字狱事件记录】\n日期：2019年05月27日\n地点：山西寿阳县\n当事人：李永贵\n平台：快手\n言论内容：“辱骂交警的文字和视频”（共三次）\n处罚：有期徒刑6个月\n法律文书：（2019）晋0725刑初63号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:54.718444+12
757	773	【中国文字狱事件记录】\n日期：2019年05月28日\n地点：青海互助县\n当事人：王某福\n平台：微信群\n言论内容：”辱骂“村干部\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:54.763533+12
758	774	【中国文字狱事件记录】\n日期：2019年05月28日\n地点：江苏扬州\n当事人：赵某、高某\n平台：网络\n言论内容：辱骂扫黑办并受到威胁的伪造截图\n处罚：拘留12日、10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:54.809659+12
759	775	【中国文字狱事件记录】\n日期：2019年05月29日\n地点：辽宁铁岭\n当事人：杨某\n平台：微信群\n言论内容：警察最特么不是东西，干警察就完了\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:54.856342+12
760	776	【中国文字狱事件记录】\n日期：2019年05月29日\n地点：贵州天柱县\n当事人：龙某\n平台：现实\n言论内容：“诋毁政府”\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:54.902908+12
761	777	【中国文字狱事件记录】\n日期：2019年05月30日\n地点：湖南双峰县\n当事人：郭有弟\n平台：多个平台\n言论内容：多篇指控当地政府贪污腐败和迫害百姓的文章\n处罚：有期徒刑2年6个月\n法律文书：（2019）湘1321刑初60号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:54.947139+12
762	778	【中国文字狱事件记录】\n日期：2019年05月30日\n地点：广西田林县\n当事人：黄某甲\n平台：微信群\n言论内容：兄弟们潞城高速公路有狗，十二桥也有狗；这帮狗，下雨也出来\n处罚：拘留8日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:54.992785+12
763	779	【中国文字狱事件记录】\n日期：2019年05月30日\n地点：广西田林县\n当事人：陈某贵\n平台：微信群\n言论内容：以后大家叫他们一狗，二狗，一狗代表白帽，二狗代表蓝帽\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:55.035529+12
764	780	【中国文字狱事件记录】\n日期：2019年05月30日\n地点：广西田林县\n当事人：岑某明\n平台：微信群\n言论内容：田林路况货源群”上发布“兄弟们潞城高速公路有狗，十二桥也有狗\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:55.081195+12
765	781	【中国文字狱事件记录】\n日期：2019年05月30日\n地点：陕西安康\n当事人：张某\n平台：朋友圈\n言论内容：长期发布“抨击国家方针政策、侮辱国家领导人、侮辱国家机关工作人员的图文信息”\n处罚：拘留15日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:55.126878+12
766	782	【中国文字狱事件记录】\n日期：2019年05月31日\n地点：内蒙古包头\n当事人：高某\n平台：朋友圈\n言论内容：“辱警言论”\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:55.173176+12
767	783	【中国文字狱事件记录】\n日期：2019年06月01日\n地点：电子科技大学\n当事人：郑文锋\n身份：学者/教师\n平台：QQ群\n言论内容：“四大发明在世界上都不领先”\n处罚：停职两年	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:55.219381+12
768	784	【中国文字狱事件记录】\n日期：2019年06月02日\n地点：山东潍坊\n当事人：于某\n平台：微博\n言论内容：现实版的土匪，强盗@爆料潍坊 @潍坊那点事儿 @潍坊大众网 @潍坊论坛\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:55.26521+12
769	785	【中国文字狱事件记录】\n日期：2019年06月02日\n地点：贵州德江县\n当事人：张某\n平台：朋友圈\n言论内容：这种鸡巴豆腐渣工程（当地扶贫攻坚工程）忽悠老百姓\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:55.310648+12
770	786	【中国文字狱事件记录】\n日期：2019年06月04日\n地点：广东惠州\n当事人：刘某有、刘某娟\n平台：不详\n言论内容：政府（对其姐之死）不作为，且侮辱、恐吓殴打他们\n背景事件：其姐不久前死于意外事故\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:55.357075+12
771	787	【中国文字狱事件记录】\n日期：2019年06月05日\n地点：安徽芜湖县\n当事人：刘礼军\n平台：微信群\n言论内容：“不当言论、侮辱中国共产党”\n处罚：拘留5日\n法律文书：芜县公（花）行罚决字［2019］12号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:55.403309+12
772	788	【中国文字狱事件记录】\n日期：2019年06月06日\n地点：广东汕头\n当事人：张利文\n平台：微信群\n言论内容：垃圾压缩站会导致垃圾车辆在村中行驶致使村民出行有生命危险，并破坏村中的生态环境，影响人体健康，危害子孙后代\n处罚：有期徒刑1年、缓刑3年\n法律文书：（2018）粤0513刑初805号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:55.446996+12
773	789	【中国文字狱事件记录】\n日期：2019年06月06日\n地点：广东汕头\n当事人：张盛辉\n平台：微信群\n言论内容：垃圾压缩站会导致垃圾车辆在村中行驶致使村民出行有生命危险，并破坏村中的生态环境，影响人体健康，危害子孙后代\n处罚：有期徒刑10个月、缓刑1年6个月\n法律文书：（2018）粤0513刑初805号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:55.493036+12
774	790	【中国文字狱事件记录】\n日期：2019年06月06日\n地点：广东汕头\n当事人：张进桂\n平台：微信群\n言论内容：垃圾压缩站会导致垃圾车辆在村中行驶致使村民出行有生命危险，并破坏村中的生态环境，影响人体健康，危害子孙后代\n处罚：有期徒刑8个月、缓刑1年\n法律文书：（2018）粤0513刑初805号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:55.53565+12
775	791	【中国文字狱事件记录】\n日期：2019年06月06日\n地点：广东汕头\n当事人：张科雄\n平台：微信群\n言论内容：垃圾压缩站会导致垃圾车辆在村中行驶致使村民出行有生命危险，并破坏村中的生态环境，影响人体健康，危害子孙后代\n处罚：有期徒刑6个月、缓刑1年\n法律文书：（2018）粤0513刑初805号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:55.573057+12
776	792	【中国文字狱事件记录】\n日期：2019年06月08日\n地点：贵州德江县\n当事人：吴某婵\n平台：电话\n言论内容：（在扶贫队未征得其同意且她不在场情况时将她的物品搬出了她的房子后）辱骂村干部\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:55.611579+12
777	793	【中国文字狱事件记录】\n日期：2019年06月10日\n地点：甘肃临夏县\n当事人：马某\n平台：快手\n言论内容：发布执法视频并配以“侮辱性言论”\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:55.651996+12
778	794	【中国文字狱事件记录】\n日期：2019年06月10日\n地点：河南洛阳\n当事人：刘某娟\n平台：朋友圈\n言论内容：这死交警，每次都是老子往里面开着你在后面拍着死XX，给姐杠上了不是\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:55.695401+12
779	795	【中国文字狱事件记录】\n日期：2019年06月11日\n地点：河南许昌\n当事人：聂丽娜\n平台：多家外媒网站\n言论内容：发《在废墟上过年》视频，提供给多家外媒\n处罚：有期徒刑3年\n备注：二审维持原判\n法律文书：（2019）豫10刑终246号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:55.740711+12
780	796	【中国文字狱事件记录】\n日期：2019年06月11日\n地点：海南五指山\n当事人：李某\n平台：微信群\n言论内容：抹黑保亭警方的不当言论\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:55.78723+12
781	797	【中国文字狱事件记录】\n日期：2019年06月11日\n地点：浙江台州\n当事人：江某林\n平台：现实\n言论内容：拉横幅、穿庄衣、发传单等\n处罚：有期徒刑一年四个月	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:55.831449+12
782	798	【中国文字狱事件记录】\n日期：2019年06月12日\n地点：辽宁朝阳县\n当事人：亚广君\n平台：现实/举横幅\n言论内容：”反动条幅“和划叉的国家领导人照片\n处罚：有期徒刑1年\n法律文书：（2019）辽1321刑初68号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:55.879337+12
783	799	【中国文字狱事件记录】\n日期：2019年06月13日\n地点：广东连平县\n当事人：谢某锦、江某嫣、谢某全\n平台：网络\n言论内容：连平内莞河两边人员需要转移，显村电站可能会出现问题；上坪高涧水库、内莞显村水库快要崩塌，下游群众赶快撤离\n背景事件：连平洪灾\n处罚：行政处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:55.925599+12
784	800	【中国文字狱事件记录】\n日期：2019年06月13日\n地点：湖北武汉\n当事人：邱先桥\n平台：网络、现实\n言论内容：组织静坐示威、拉横幅、网络曝光等\n处罚：有期徒刑1年半\n法律文书：（2019）鄂01刑终935号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:55.97245+12
785	801	【中国文字狱事件记录】\n日期：2019年06月13日\n地点：湖北武汉\n当事人：胡闯\n平台：网络、现实\n言论内容：组织静坐示威、拉横幅、网络曝光等\n处罚：有期徒刑8个月\n法律文书：（2019）鄂01刑终935号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:56.017108+12
786	802	【中国文字狱事件记录】\n日期：2019年06月14日\n地点：齐鲁工业大学\n当事人：刘书庆\n身份：学者/教师\n平台：不详\n言论内容：“损害党中央的权威和偏离党的路线方针“匿名文章\n处罚：记过、停职	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:56.062959+12
787	803	【中国文字狱事件记录】\n日期：2019年06月14日\n地点：甘肃成县\n当事人：邓某\n平台：微信群\n言论内容：辱骂公务人员\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:56.109321+12
788	804	【中国文字狱事件记录】\n日期：2019年06月14日\n地点：江西赣州\n当事人：肖小平\n平台：微信群\n言论内容：看对什么情况？如果打日本人，牺牲了就是真英雄，像这样用火烧死的，对于老百姓，就是猪一头\n处罚：拘役3个月\n法律文书：（2019）赣0791刑初186号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:56.15814+12
789	805	【中国文字狱事件记录】\n日期：2019年06月14日\n地点：广东博罗县\n当事人：刘某\n平台：朋友圈\n言论内容：侮辱性文字（针对交警）\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:56.206698+12
790	806	【中国文字狱事件记录】\n日期：2019年06月15日\n地点：河北武安市\n当事人：魏永良\n平台：天涯社区\n言论内容：“不当言论，歪曲历史事实，丑化革命烈士魏日盤”\n处罚：拘留10日、罚款500元\n法律文书：武公（石）行罚决字[2019]0434号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:56.255282+12
791	807	【中国文字狱事件记录】\n日期：2019年06月15日\n地点：宁夏西吉县\n当事人：海某\n平台：快手\n言论内容：评论某用户发布的警察执法视频时的“不良言论”\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:56.30102+12
792	808	【中国文字狱事件记录】\n日期：2019年06月15日\n地点：贵州德江县\n当事人：卢某\n平台：朋友圈\n言论内容：诋毁国家脱贫攻坚政策和我镇脱贫攻坚工作\n处罚：拘留5日\n备注：跨省传唤	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:56.346242+12
793	809	【中国文字狱事件记录】\n日期：2019年06月16日\n地点：山西运城\n当事人：郑斌\n平台：不详\n言论内容：反送中示威相关视频\n背景事件：香港反送中示威\n处罚：羁押、没收手机	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:56.394462+12
794	810	【中国文字狱事件记录】\n日期：2019年06月16日\n地点：安徽泗洪县\n当事人：江某才\n平台：朋友圈\n言论内容：大清早送100块大洋给交警XXX；泗洪县交警都应该XXX\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:56.441116+12
795	811	【中国文字狱事件记录】\n日期：2019年06月17日\n地点：湖北京山\n当事人：孙某\n平台：微信群\n言论内容：{视频}镇政府是黑恶势力保护伞；多名村民被打伤\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:56.487975+12
796	812	【中国文字狱事件记录】\n日期：2019年06月17日\n地点：四川长宁县\n当事人：”小米粥OvO“\n身份：斗鱼主播\n平台：微博\n言论内容：哪里是地震了，明明是我对你心动了\n背景事件：617长宁地震\n处罚：共青团点评批评，直播平台封杀	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:56.535012+12
797	813	【中国文字狱事件记录】\n日期：2019年06月17日\n地点：广东汕尾\n当事人：彭某范\n平台：现实/政府围墙\n言论内容：“不当言论”\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:56.580167+12
798	814	【中国文字狱事件记录】\n日期：2019年06月18日\n地点：甘肃陇南\n当事人：李某\n平台：微博\n言论内容：”关于镇政府的不实言论”\n处罚：拘留15日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:56.625583+12
799	815	【中国文字狱事件记录】\n日期：2019年06月18日\n地点：浙江湖州\n当事人：卫小兵\n平台：推特\n言论内容：形势大好，加油\n背景事件：香港反送中示威\n处罚：拘留15天\n备注：警方拒给行政处罚书	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:56.672904+12
800	816	【中国文字狱事件记录】\n日期：2019年06月19日\n地点：陕西榆林\n当事人：许建榆\n身份：中共党员\n平台：推特\n言论内容：“辱骂党和国家领导人、抨击社会主义制度、军人及警察群体”等推文47篇\n处罚：有期徒刑2年6个月\n法律文书：（2019）陕0802刑初383号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:56.720919+12
801	817	【中国文字狱事件记录】\n日期：2019年06月21日\n地点：甘肃陇南\n当事人：王某\n平台：微信群\n言论内容：“骂村镇干部工作人员”\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:56.766963+12
802	818	【中国文字狱事件记录】\n日期：2019年06月21日\n地点：广西都安县\n当事人：谭某\n平台：微信群\n言论内容：发布与转发“驾车摸B摸奶扣6分罚2000”的PS警示图\n处罚：拘留15日与5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:56.811797+12
803	819	【中国文字狱事件记录】\n日期：2019年06月22日\n地点：吉林公主岭\n当事人：王某\n平台：微信群\n言论内容：大岭这帮玩应真他妈可恨，我几个警察可他妈正装犊子了；这帮警察没他妈好揍\n处罚：拘留13日、罚款700元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:56.856596+12
804	820	【中国文字狱事件记录】\n日期：2019年06月22日\n地点：上海\n当事人：章某\n平台：知乎\n言论内容：发文控诉某交警素质低下、渎职、以权谋私\n处罚：拘留8日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:56.90356+12
805	821	【中国文字狱事件记录】\n日期：2019年06月23日\n地点：贵州大方县\n当事人：张某发\n平台：微信群\n言论内容：辱骂群内警员\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:56.947097+12
806	822	【中国文字狱事件记录】\n日期：2019年06月23日\n地点：河南洛阳\n当事人：卢某\n平台：朋友圈\n言论内容：XX的，一分钟没看见\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:56.992581+12
807	823	【中国文字狱事件记录】\n日期：2019年06月24日\n地点：河南新乡\n当事人：郑其峰\n平台：微信群\n言论内容：抨击中国共产党和政府、丑化党和国家形象、诋毁、污蔑党和国家已故领导人\n处罚：有期徒刑10个月\n法律文书：（2019）豫0702刑初342号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:57.037266+12
808	824	【中国文字狱事件记录】\n日期：2019年06月24日\n地点：贵州德江县\n当事人：曾某花\n平台：朋友圈\n言论内容：这些老*警察，日他妈咯，老是罚款罚款，罚他妈呀；鸡*交警又在拦车，拦他妈呀*\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:57.083745+12
809	825	【中国文字狱事件记录】\n日期：2019年06月24日\n地点：湖北武汉\n当事人：彭某\n平台：微信群\n言论内容：“诋毁国家领导人的小视频”\n处罚：起诉（寻衅滋事罪）\n法律文书：洪检刑诉〔2019〕769号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:57.128998+12
810	826	【中国文字狱事件记录】\n日期：2019年06月26日\n地点：湖北荆门\n当事人：张中凤\n平台：不详\n言论内容：关于香港反送中示威信息\n背景事件：香港反送中示威\n处罚：口头警告\n备注：其夫周远志为在押政治犯	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:57.173718+12
811	827	【中国文字狱事件记录】\n日期：2019年06月26日\n地点：江西上饶\n当事人：郑某\n平台：朋友圈\n言论内容：（交警执勤视频）土狗挺多的\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:57.219723+12
812	828	【中国文字狱事件记录】\n日期：2019年06月27日\n地点：湖南湘西\n当事人：田某\n平台：微信群\n言论内容：“无端指责与诋毁政府”\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:57.266732+12
813	829	【中国文字狱事件记录】\n日期：2019年06月27日\n地点：青海西宁\n当事人：胡长江\n平台：推推、法轮功网站\n言论内容：（推特）严重损害国家形象、严重危害国家利益的虚假信息；在法轮功网站发布三退声明\n处罚：有期徒刑1年6个月\n法律文书：（2019）青0102刑初194号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:57.311624+12
814	830	【中国文字狱事件记录】\n日期：2019年06月28日\n地点：湖北荆门\n当事人：周远志（独立中文笔会会员）\n平台：多个平台\n言论内容：长期撰文批评时政\n处罚：有期徒刑4年6个月\n备注：已上诉	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:57.357884+12
815	831	【中国文字狱事件记录】\n日期：2019年06月28日\n地点：湖南长沙\n当事人：孙特颖\n平台：微信群\n言论内容：《举报阳光壹佰物业重疑似贿赂岳麓区交警中队对小区抄牌》\n处罚：拘留10日\n法律文书：岳公（麓）决字[2019]第1135号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:57.404985+12
816	832	【中国文字狱事件记录】\n日期：2019年06月28日\n地点：宁夏银川\n当事人：米某彦\n平台：朋友圈\n言论内容：XXX（脏话）我就想起那晚扣我的一分……看监控不给看\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:57.45173+12
817	833	【中国文字狱事件记录】\n日期：2019年06月29日\n地点：湖北赤壁\n当事人：刘某波\n平台：微信群\n言论内容：（视频）今天下午新店镇掩埋二千多头猪，最近不要买猪肉吃哦\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:57.494674+12
818	834	【中国文字狱事件记录】\n日期：2019年06月29日\n地点：湖北赤壁\n当事人：吴某东\n平台：微信群\n言论内容：（视频）今天下午新店镇掩埋二千多头猪，最近不要买猪肉吃哦\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:57.540686+12
819	835	【中国文字狱事件记录】\n日期：2019年07月01日\n地点：浙江宁波\n当事人：郑某\n平台：朋友圈\n言论内容：辱骂警务人员\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:57.585297+12
820	836	【中国文字狱事件记录】\n日期：2019年07月01日\n地点：湖南邵阳县\n当事人：陈某珍\n平台：朋友圈\n言论内容：我外公被派出所人员粗暴对待，推到在地\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:57.629424+12
821	837	【中国文字狱事件记录】\n日期：2019年07月01日\n地点：湖南邵阳县\n当事人：唐某\n平台：朋友圈\n言论内容：（转发）我外公被派出所人员粗暴对待，推到在地\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:57.674772+12
822	838	【中国文字狱事件记录】\n日期：2019年07月01日\n地点：内蒙古赤峰\n当事人：张某\n平台：现实\n言论内容：于2017年举报村支书薛某贪污工程款\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:57.720093+12
823	839	【中国文字狱事件记录】\n日期：2019年07月01日\n地点：安徽霍邱县\n当事人：李某\n平台：朋友圈\n言论内容：（视频）二狗子逮车\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:57.764548+12
824	840	【中国文字狱事件记录】\n日期：2019年07月02日\n地点：四川遂宁\n当事人：蒋鹏\n平台：亚马逊、油管\n言论内容：观看视频和购物\n处罚：传唤警告	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:57.80939+12
825	841	【中国文字狱事件记录】\n日期：2019年07月02日\n地点：安徽明光\n当事人：杨某\n平台：微博\n言论内容：举报屠宰场负责人充当保护伞，使病猪肉流通\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:57.855825+12
826	842	【中国文字狱事件记录】\n日期：2019年07月02日\n地点：江苏南通\n当事人：李某\n平台：朋友圈\n言论内容：（视频）一大早就这样一个活生生的生命没了，是个女的；是个女孩高考没考好，想不开\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:57.901913+12
827	843	【中国文字狱事件记录】\n日期：2019年07月03日\n地点：浙江宁波\n当事人：傅某\n平台：微博\n言论内容：招人招点好看的等“辱警言论”\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:57.946806+12
828	844	【中国文字狱事件记录】\n日期：2019年07月03日\n地点：浙江宁波\n当事人：裘某\n平台：朋友圈\n言论内容：叶xxxxx这都几点了 还贴罚单\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:57.99157+12
829	845	【中国文字狱事件记录】\n日期：2019年07月05日\n地点：四川南充\n当事人：郭云平\n平台：现实/街头举牌\n言论内容：举报xx贪污\n处罚：拘留5日\n法律文书：南顺公（西城）行罚决字〔2019〕1213号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:58.036767+12
830	846	【中国文字狱事件记录】\n日期：2019年07月05日\n地点：四川合江县\n当事人：李先利\n平台：破楼梦（其本人创建）\n言论内容：辱骂、丑化国家领导人、国家机关及国家机关工作人员、丑化党的基本制度的内容\n处罚：有期徒刑2年\n备注：二审维持原判\n法律文书：（2019）川05刑终167号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:58.083536+12
831	847	【中国文字狱事件记录】\n日期：2019年07月06日\n地点：陕西旬阳县\n当事人：不详\n平台：微信群\n言论内容：”不当言论、辱骂警察“\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:58.131591+12
832	848	【中国文字狱事件记录】\n日期：2019年07月06日\n地点：甘肃永靖县\n当事人：全某\n平台：快手\n言论内容：有一名（全国滑翔伞锦标赛）运动员掉入水里\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:58.177859+12
833	849	【中国文字狱事件记录】\n日期：2019年07月08日\n地点：青海海东\n当事人：李某\n平台：微博\n言论内容：诋毁乡政府言论\n处罚：拘留9日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:58.226824+12
834	850	【中国文字狱事件记录】\n日期：2019年07月08日\n地点：湖南长沙\n当事人：王美余\n平台：现实/举牌\n言论内容：强烈要求习近平、李克强等立即下台\n处罚：被羁押后9月23日宣布猝死	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:58.275601+12
835	851	【中国文字狱事件记录】\n日期：2019年07月09日\n地点：甘肃永靖县\n当事人：司某\n平台：微信群\n言论内容：“对政府和国家有关政策的不实言论”\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:58.320175+12
836	852	【中国文字狱事件记录】\n日期：2019年07月09日\n地点：湖北恩施\n当事人：廖座位\n平台：朋友圈\n言论内容：四个小孩被碾压，脑浆洒了一地（明显为玩笑）\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:58.364207+12
837	853	【中国文字狱事件记录】\n日期：2019年07月10日\n地点：贵州大方县\n当事人：张某\n平台：微博\n言论内容：（图文）大方县黄泥乡有腐败分子，吃了大岩下面十几户人家的搬迁款，现在一直住在危险地带过着提心吊胆的日子……\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:58.410169+12
838	854	【中国文字狱事件记录】\n日期：2019年07月10日\n地点：湖北宜昌\n当事人：向某\n平台：朋友圈\n言论内容：“辱警内容”\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:58.455207+12
839	855	【中国文字狱事件记录】\n日期：2019年07月10日\n地点：河南郑州\n当事人：王罡宇\n平台：现实/街头涂写\n言论内容：“辱骂国家领导人习某某和李某某的文字”\n处罚：有期徒刑1年\n法律文书：（2019）豫0105刑初433号；（2019）豫01刑终960号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:58.499715+12
840	856	【中国文字狱事件记录】\n日期：2019年07月11日\n地点：广东吴川市\n当事人：凌某荣\n平台：微信\n言论内容：交警执法视频以及“辱警语言”\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:58.544963+12
841	857	【中国文字狱事件记录】\n日期：2019年07月11日\n地点：云南楚雄\n当事人：王藏\n身份：作家\n平台：推特\n言论内容：关于香港反送中示威及六四事件信息\n背景事件：香港反送中示威、六四事件\n处罚：传唤、警告	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:58.590617+12
842	858	【中国文字狱事件记录】\n日期：2019年07月12日\n地点：黑龙江齐齐哈尔\n当事人：王某\n平台：微信群\n言论内容：数条关于中国共产党及党和国家领导人的负面信息\n处罚：有期徒刑2年\n法律文书：（2019）黑0204刑初71号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:58.636495+12
843	859	【中国文字狱事件记录】\n日期：2019年07月13日\n地点：安徽固镇县\n当事人：杨某\n平台：微信群\n言论内容：（视频：乘客乘坐某趟新开通公交）生意真好，第一天通车（背景音乐为葬礼音乐）\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:58.680752+12
844	860	【中国文字狱事件记录】\n日期：2019年07月14日\n地点：甘肃陇南\n当事人：郭某\n平台：微信群\n言论内容：“扬言扰乱公共秩序”\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:58.7253+12
845	861	【中国文字狱事件记录】\n日期：2019年07月14日\n地点：甘肃成县\n当事人：安某（71岁）\n平台：微信群\n言论内容：宣传他妈的XX，硬化都没打，扶他妈X的扶贫里\n处罚：拘留7日、罚款300元\n法律文书：成公（纸）行罚决字［2019］120号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:58.770055+12
846	862	【中国文字狱事件记录】\n日期：2019年07月14日\n地点：浙江宁波\n当事人：郑某\n平台：朋友圈\n言论内容：一个傻x交警x冒雨贴牌，把我所有晚上的美好心情都破坏掉了\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:58.814766+12
847	888	【中国文字狱事件记录】\n日期：2019年07月24日\n地点：广东始兴县\n当事人：曾某\n平台：微信群\n言论内容：比鬼子还鬼，比土匪还匪\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:00.004889+12
848	863	【中国文字狱事件记录】\n日期：2019年07月15日\n地点：广西河池\n当事人：蓝某\n平台：微信群\n言论内容：”指控当地政府克扣赔偿款项的图片“\n背景事件：当地发生房屋垮塌\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:58.860374+12
849	864	【中国文字狱事件记录】\n日期：2019年07月15日\n地点：安徽合肥\n当事人：于勤\n平台：微信群\n言论内容：“不正当言论”和煽动非法集会\n处罚：拘留20日\n法律文书：合公庐(逍)行罚决字〔2019〕11366号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:58.907638+12
850	865	【中国文字狱事件记录】\n日期：2019年07月16日\n地点：湖北黄石\n当事人：王某\n平台：微信群\n言论内容：一条带有诽谤、污蔑性质的不当政治言论\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:58.952989+12
851	866	【中国文字狱事件记录】\n日期：2019年07月16日\n地点：广西都安县\n当事人：黄某\n平台：微信群\n言论内容：一首自编的“诋毁县党委政府形象的打油诗”\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:58.996796+12
852	867	【中国文字狱事件记录】\n日期：2019年07月16日\n地点：海南保亭县\n当事人：谢某\n平台：微信群\n言论内容：养兵一时！当兵的不死谁去死呀！老百姓头上的三坐大山太厉害了所以不用同情的\n背景事件：四川木里森林大火\n处罚：有期徒刑8个月	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:59.042163+12
853	868	【中国文字狱事件记录】\n日期：2019年07月16日\n地点：江西上饶\n当事人：刘某\n平台：朋友圈\n言论内容：《江西上饶创建文明城市暴力执法，全市百姓苦不堪言》的视频\n处罚：拘留15日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:59.088905+12
854	869	【中国文字狱事件记录】\n日期：2019年07月16日\n地点：福建仙游县\n当事人：林某\n平台：朋友圈\n言论内容：差点又被交警狗抓到\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:59.136316+12
855	870	【中国文字狱事件记录】\n日期：2019年07月17日\n地点：湖北阳新县\n当事人：王某\n平台：微信群\n言论内容：“不当政治言论”\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:59.18246+12
856	871	【中国文字狱事件记录】\n日期：2019年07月17日\n地点：浙江宁波\n当事人：董某\n平台：朋友圈\n言论内容：傻x交警我x你x\n处罚：罚款200元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:59.23286+12
857	872	【中国文字狱事件记录】\n日期：2019年07月18日\n地点：黑龙江伊春\n当事人：王某、蒋某、候某、莫某\n平台：微信群\n言论内容：“诋毁我市形象的打油诗”，疑似：兴安岭上雪无敌，城中变换大王旗。鸟尽弓藏兽四散，只剩几条混水鱼。\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:59.279363+12
858	873	【中国文字狱事件记录】\n日期：2019年07月18日\n地点：黑龙江伊春\n当事人：郑某春\n平台：贴吧\n言论内容：“辱骂、丑化政府形象，无端指责、诋毁政府言论”\n处罚：拘留7日\n法律文书：伊公（网）行罚决字﹝2019﹞210号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:59.324339+12
859	874	【中国文字狱事件记录】\n日期：2019年07月19日\n地点：山西太原\n当事人：杜二伟\n平台：不详\n言论内容：“七不准”内容\n处罚：羁押约24小时\n备注：8月被刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:59.370283+12
860	875	【中国文字狱事件记录】\n日期：2019年07月19日\n地点：甘肃陇南\n当事人：尹某山\n平台：微信群\n言论内容：“辱骂各级干部”\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:59.413779+12
861	876	【中国文字狱事件记录】\n日期：2019年07月19日\n地点：江西余干县\n当事人：徐某玲\n平台：微博\n言论内容：#余干交警霸权主义#余干县的交警啊还真不是一般的恶心，又凶素质还差，说他两句就要打人\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:59.459603+12
862	877	【中国文字狱事件记录】\n日期：2019年07月19日\n地点：湖南邵阳\n当事人：安某\n平台：朋友圈\n言论内容：“辱警言论”\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:59.506828+12
863	878	【中国文字狱事件记录】\n日期：2019年07月21日\n地点：广西都安县\n当事人：潘某与蓝某等四人\n平台：现实/举大字报\n言论内容：强烈要求县领导惩治乡及腐败分子\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:59.550031+12
864	879	【中国文字狱事件记录】\n日期：2019年07月22日\n地点：辽宁海城市\n当事人：马德胜\n平台：微信群\n言论内容：“攻击我国政体、污蔑党和国家领导人并发表恶意评论”\n处罚：有期徒刑6个月\n法律文书：（2019）辽0381刑初353号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:59.594467+12
865	880	【中国文字狱事件记录】\n日期：2019年07月22日\n地点：山东成思律师事务所\n当事人：李金星\n身份：维权律师\n平台：微博\n言论内容：不当言论”、发起联署签名活动、诋毁司法机关等\n处罚：吊销律师资格证	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:59.63921+12
866	881	【中国文字狱事件记录】\n日期：2019年07月22日\n地点：四川眉山\n当事人：李某\n平台：朋友圈\n言论内容：“辱骂执勤民警及其家属”\n处罚：拘留14日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:59.682807+12
867	882	【中国文字狱事件记录】\n日期：2019年07月22日\n地点：宁夏银川\n当事人：栾凝（法轮功学员）\n平台：现实\n言论内容：向多个政府单位小区邮寄法轮功材料\n背景事件：法轮功被镇压事件\n处罚：有期徒刑3年\n法律文书：（2019）宁刑终31号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:59.727792+12
868	883	【中国文字狱事件记录】\n日期：2019年07月22日\n地点：河北沙河市\n当事人：张俊强\n平台：邢台123论坛\n言论内容：和一名“爱国群众”辩论争吵并发表“精日”言论和侮辱他人言论\n处罚：拘留5日\n法律文书：邢东公（华）行罚决字（2019）0326号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:59.774396+12
869	884	【中国文字狱事件记录】\n日期：2019年07月22日\n地点：陕西安康\n当事人：王某\n平台：微信群\n言论内容：“违法言论”\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:59.819375+12
870	885	【中国文字狱事件记录】\n日期：2019年07月23日\n地点：安徽金寨县\n当事人：张经远\n平台：多个平台\n言论内容：（视频）请全社会关注金寨县南溪变了味的脱贫搬迁，内容为指控政府在过程中有暗箱操作\n处罚：有期徒刑3年6个月\n备注：二审维持原判\n法律文书：（2019）皖1524刑初163号；（2019）皖15刑终297号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:59.865909+12
871	886	【中国文字狱事件记录】\n日期：2019年07月23日\n地点：安徽金寨县\n当事人：黄朝银\n平台：多个平台\n言论内容：（视频）请全社会关注金寨县南溪变了味的脱贫搬迁，内容为指控政府在过程中有暗箱操作\n处罚：有期徒刑2年6个月\n备注：二审维持原判\n法律文书：（2019）皖1524刑初163号；（2019）皖15刑终297号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:59.911995+12
872	887	【中国文字狱事件记录】\n日期：2019年07月23日\n地点：安徽金寨县\n当事人：何先武\n平台：多个平台\n言论内容：（视频）请全社会关注金寨县南溪变了味的脱贫搬迁，内容为指控政府在过程中有暗箱操作\n处罚：有期徒刑1年6个月\n备注：二审维持原判\n法律文书：（2019）皖1524刑初163号；（2019）皖15刑终297号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:04:59.959553+12
873	889	【中国文字狱事件记录】\n日期：2019年07月24日\n地点：四川成都\n当事人：朱舒\n平台：朋友圈\n言论内容：“涉及近期香港不稳定言论和图片”\n背景事件：香港反送中示威\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:00.05269+12
874	890	【中国文字狱事件记录】\n日期：2019年07月24日\n地点：江苏南京\n当事人：邵明亮\n平台：现实\n言论内容：创建中国民复党、上街举牌抗议等\n处罚：已审未判	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:00.097014+12
875	891	【中国文字狱事件记录】\n日期：2019年07月24日\n地点：陕西安康\n当事人：陈某\n平台：抖音\n言论内容：“辱骂执勤交警的不当言论”\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:00.142668+12
876	892	【中国文字狱事件记录】\n日期：2019年07月25日\n地点：浙江宁波\n当事人：张某\n平台：朋友圈\n言论内容：（交警执法照片）x🐶🐶辛苦了！\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:00.189638+12
877	893	【中国文字狱事件记录】\n日期：2019年07月29日\n地点：山西太原\n当事人：苑某\n平台：微信群\n言论内容：两段“辱骂交警”的视频\n处罚：拘留15日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:00.240211+12
878	894	【中国文字狱事件记录】\n日期：2019年07月29日\n地点：江苏涟水县\n当事人：周某鹏\n平台：微博\n言论内容：涟水的交警真孬 真孬 真孬，缺钱缺到上门抢了；涟水的交警现在像狗一样\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:00.293565+12
879	895	【中国文字狱事件记录】\n日期：2019年07月29日\n地点：黑龙江大庆\n当事人：陈某\n平台：某直播平台\n言论内容：别和狗狗讲道理，狗咬一口你还能咬狗一口呀\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:00.337399+12
880	896	【中国文字狱事件记录】\n日期：2019年07月29日\n地点：浙江慈溪市\n当事人：姜某\n平台：微博\n言论内容：我骑个电动车被罚款……罚款的款项不还是被这些交警狗用了……罚的款就当老子给你们xxx\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:00.392814+12
881	897	【中国文字狱事件记录】\n日期：2019年07月30日\n地点：四川眉山\n当事人：李某\n平台：微信公众平台\n言论内容：《劝四川省丹棱县汪某法官自首书》，指控法官对其敲诈勒索，并炮制了其妹的冤案\n处罚：有期徒刑1年、缓刑1年\n法律文书：（2019）川1403刑初67号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:00.443106+12
882	898	【中国文字狱事件记录】\n日期：2019年07月30日\n地点：四川眉山\n当事人：程某\n平台：微信公众平台\n言论内容：《劝四川省丹棱县汪某法官自首书》，指控法官对其敲诈勒索，并炮制了李某妹妹的冤案\n处罚：拘役6个月、缓刑1年\n法律文书：（2019）川1403刑初67号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:00.49672+12
883	899	【中国文字狱事件记录】\n日期：2019年07月30日\n地点：山东滨州\n当事人：刘某喜\n平台：微信群\n言论内容：滨州市惠民县皂户李镇政府因安排收取闲散土地费、宅基超占费等费用涉嫌乱收费\n处罚：拘留9日、罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:00.547564+12
884	900	【中国文字狱事件记录】\n日期：2019年07月30日\n地点：海南万宁\n当事人：孟令键\n平台：微博\n言论内容：《海南万宁美亚.榕天下强拆事件--强拆海南梦》\n处罚：有期徒刑7个月\n法律文书：（2019）琼9006刑初314号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:00.593006+12
885	901	【中国文字狱事件记录】\n日期：2019年07月30日\n地点：山西平遥\n当事人：安某瑞\n平台：朋友圈\n言论内容：一段视频，视频中她将警察称为走狗\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:00.640197+12
886	902	【中国文字狱事件记录】\n日期：2019年07月30日\n地点：江苏仪征市\n当事人：陈某\n平台：朋友圈\n言论内容：“辱骂民警”的言论\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:00.687593+12
887	903	【中国文字狱事件记录】\n日期：2019年08月02日\n地点：重庆\n当事人：黄洋\n平台：微信群\n言论内容：敢不敢像我一样走上街头声援东方之珠？\n背景事件：香港反送中示威\n处罚：羁押20小时	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:00.732474+12
888	904	【中国文字狱事件记录】\n日期：2019年08月02日\n地点：甘肃永靖县\n当事人：刘某\n平台：微信群\n言论内容：“恶意攻击干部推送的天气预警信息、挑衅镇村干部、诋毁扶贫政策”\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:00.77538+12
889	905	【中国文字狱事件记录】\n日期：2019年08月02日\n地点：山东宁津县\n当事人：张某\n平台：朋友圈\n言论内容：“25条攻击党、政府和国家领导人的不当言论”\n处罚：拘役6个月，缓刑一年\n法律文书：（2019）鲁1422刑初68号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:00.831121+12
890	906	【中国文字狱事件记录】\n日期：2019年08月02日\n地点：新疆伊犁\n当事人：董春雷\n平台：网络、现实\n言论内容：官员不作为，谁能来帮忙；相信政府等帖子；上访；组织出租车司机罢工\n处罚：有期徒刑1年\n备注：二审维持原判	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:00.87296+12
891	907	【中国文字狱事件记录】\n日期：2019年08月03日\n地点：浙江杭州\n当事人：徐光\n平台：YouTube\n言论内容：评论台湾问题、刘晓波事件和六四事件等，以及抨击中国共产党和中国国家体制\n处罚：拘留6日\n法律文书：杭西公（玉）行罚决字［2019］53098号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:00.913902+12
892	908	【中国文字狱事件记录】\n日期：2019年08月06日\n地点：广西平南县\n当事人：李某\n平台：朋友圈\n言论内容：政府、公安等充当物业保护伞、所谓人民警察真是够黑暗\n处罚：拘留10日、罚款1000元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:00.95353+12
893	909	【中国文字狱事件记录】\n日期：2019年08月06日\n地点：广西平南县\n当事人：吴某\n平台：微博\n言论内容：（转发）政府、公安等充当物业保护伞、所谓人民警察真是够黑暗\n处罚：拘留10日、罚款1000元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:00.993353+12
894	910	【中国文字狱事件记录】\n日期：2019年08月08日\n地点：安徽砀山县\n当事人：周某\n平台：多个平台\n言论内容：当地县政府干部贪污腐败、迫害他等\n处罚：有期徒刑2年2个月\n法律文书：（2019）皖1321刑初189号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:01.03346+12
895	911	【中国文字狱事件记录】\n日期：2019年08月09日\n地点：广西柳州\n当事人：何某\n平台：微信群\n言论内容：“辱警”言论\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:01.074399+12
896	912	【中国文字狱事件记录】\n日期：2019年08月09日\n地点：甘肃徽县\n当事人：雒某\n平台：微信群\n言论内容：“辱骂村干部”\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:01.114073+12
897	913	【中国文字狱事件记录】\n日期：2019年08月09日\n地点：河南伊川县\n当事人：张某\n平台：抖音\n言论内容：狗腿子们，啥他娘那蛋妨碍公务\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:01.162163+12
898	914	【中国文字狱事件记录】\n日期：2019年08月09日\n地点：广西钦州\n当事人：梁某鹏\n平台：朋友圈\n言论内容：xx臭交警真贱，诅咒你喝酒喝死你；x你大爷的交警……\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:01.20148+12
899	1073	【中国文字狱事件记录】\n日期：2019年10月29日\n地点：河北承德\n当事人：李某\n平台：恶俗维基\n言论内容：仅观看，未发布内容\n处罚：传唤警告	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:09.098936+12
900	915	【中国文字狱事件记录】\n日期：2019年08月10日\n地点：安徽宣城\n当事人：裴某\n平台：抖音\n言论内容：“一段关于宁国洪灾的不实视频”\n背景事件：台风“利奇马”\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:01.241285+12
901	916	【中国文字狱事件记录】\n日期：2019年08月12日\n地点：吉林长春\n当事人：范淑琴\n平台：网络\n言论内容：多篇文章，指控政府给其征地补偿不足\n处罚：有期徒刑2年\n法律文书：（2019）吉0104刑初315号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:01.28181+12
902	917	【中国文字狱事件记录】\n日期：2019年08月13日\n地点：安徽宣城\n当事人：彭某\n平台：不详\n言论内容：宁国洪灾，今天在宁国市虹龙找到6具尸体\n背景事件：台风“利奇马”\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:01.324674+12
903	918	【中国文字狱事件记录】\n日期：2019年08月13日\n地点：安徽宣城\n当事人：汪某\n平台：不详\n言论内容：宁国洪灾、安徽救援，光一个镇都死了20多人\n背景事件：台风“利奇马”\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:01.372766+12
904	919	【中国文字狱事件记录】\n日期：2019年08月14日\n地点：贵州雷山县\n当事人：杨某\n平台：微信公众平台\n言论内容：《狗官当道，畜生为王》等文章\n处罚：有期徒刑10个月\n法律文书：（2019）黔2634刑初42号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:01.42203+12
905	920	【中国文字狱事件记录】\n日期：2019年08月14日\n地点：山东寿光\n当事人：杨某强\n平台：微信群\n言论内容：“诋毁救灾官兵”\n背景事件：台风“利奇马”\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:01.464549+12
906	921	【中国文字狱事件记录】\n日期：2019年08月15日\n地点：安徽合肥\n当事人：张某\n平台：微信\n言论内容：支持香港百姓一人一票当家作主；何某某同志是香港的好女儿,是中国的好女儿\n背景事件：香港反送中示威\n处罚：拘留5日\n法律文书：合公庐(安)行罚决字〔2019〕11553号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:01.508561+12
907	922	【中国文字狱事件记录】\n日期：2019年08月15日\n地点：广西北海\n当事人：刘某\n平台：微信、QQ、英雄联盟\n言论内容：我又不是中国人、五星红旗让我蒙羞\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:01.550715+12
908	923	【中国文字狱事件记录】\n日期：2019年08月15日\n地点：山西临汾\n当事人：张某\n平台：朋友圈\n言论内容：“辱警言论”\n处罚：拘留15日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:01.592624+12
909	924	【中国文字狱事件记录】\n日期：2019年08月15日\n地点：山西大同\n当事人：张某\n平台：贴吧\n言论内容：交警是不是吃到啥不干净的东西了，看到停靠的车就扣本\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:01.633348+12
910	925	【中国文字狱事件记录】\n日期：2019年08月16日\n地点：甘肃永靖县\n当事人：孔某\n平台：快手\n言论内容：（当地镇政府工作人员整治街道卫生的视频）中庄十字，五大金刚；我要让你们上热门、四只眼、狂至狠\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:01.675854+12
911	926	【中国文字狱事件记录】\n日期：2019年08月16日\n地点：广东广州\n当事人：赖日福\n平台：推特\n言论内容：支持香港示威言论\n背景事件：香港反送中示威\n处罚：羁押、警告、强制删贴\n备注：一个月后再次被捕	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:01.720284+12
912	927	【中国文字狱事件记录】\n日期：2019年08月17日\n地点：上海\n当事人：蒋某\n平台：推特\n言论内容：冒充长龙航空空姐刘文萱称支持国泰航空，中国民航管理局是垃圾机构\n背景事件：香港反送中示威\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:01.764657+12
913	928	【中国文字狱事件记录】\n日期：2019年08月18日\n地点：山西太原\n当事人：杜二伟\n平台：不详\n言论内容：“七不准”内容\n处罚：刑事拘留\n备注：此前曾被羁押	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:01.843768+12
914	929	【中国文字狱事件记录】\n日期：2019年08月18日\n地点：浙江安吉县\n当事人：曹某\n平台：微博\n言论内容：还英雄老婆都是别人的了，人就是这么现实，绿帽英雄还差不多；英雄背后谁知道活着的时候收了多少黑心钱\n处罚：拘留5日、罚款200元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:01.885728+12
915	930	【中国文字狱事件记录】\n日期：2019年08月19日\n地点：云南蒙自市\n当事人：杨劲松\n平台：朋友圈\n言论内容：支持“港独”的言论\n背景事件：香港反送中示威\n处罚：拘留5日\n法律文书：蒙公（国）行罚决字〔2019〕2号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:01.925746+12
916	931	【中国文字狱事件记录】\n日期：2019年08月19日\n地点：河南沈丘县\n当事人：夏伟峰\n平台：朋友圈\n言论内容：这几个狗有要里没有天天乱咬人，谁喂谁牵走啊\n处罚：拘留14日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:01.96557+12
917	932	【中国文字狱事件记录】\n日期：2019年08月20日\n地点：湖南益阳\n当事人：冷某春\n身份：70岁\n平台：微信群\n言论内容：反党反政府言论\n处罚：拘留12日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:02.009264+12
918	933	【中国文字狱事件记录】\n日期：2019年08月20日\n地点：福建南平\n当事人：黄某\n平台：微信群\n言论内容：“侮辱在木里森林大火里牺牲的消防战士与政府干部”\n背景事件：四川木里森林大火\n处罚：有期徒刑7个月	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:02.048001+12
919	934	【中国文字狱事件记录】\n日期：2019年08月22日\n地点：陕西旬阳县\n当事人：肖文斌\n平台：多个平台\n言论内容：“辱骂”安康市党政主要负责人、县级有关部门办案人员和共产党\n处罚：有期徒刑8个月\n法律文书：（2019）陕0928刑初112号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:02.102042+12
920	935	【中国文字狱事件记录】\n日期：2019年08月22日\n地点：河南遂平县\n当事人：吴某\n身份：退伍军人\n平台：微信、现实\n言论内容：上访（过程中无过激行为）和在微信群内“扬言要上访”\n处罚：拘役5个月\n法律文书：（2019）豫1728刑初201号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:02.160205+12
921	936	【中国文字狱事件记录】\n日期：2019年08月22日\n地点：湖北丹江口市\n当事人：李某\n平台：推特\n言论内容：不当言论（以武汉网警名义发表）\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:02.20069+12
922	937	【中国文字狱事件记录】\n日期：2019年08月22日\n地点：山东德州\n当事人：李某\n平台：猫眼传媒\n言论内容：法官是穿袍的土匪、万恶之源\n处罚：有期徒刑2年	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:02.276889+12
923	938	【中国文字狱事件记录】\n日期：2019年08月23日\n地点：浙江台州\n当事人：许某\n平台：朋友圈\n言论内容：穿拖鞋被狗咬一口（被交警罚款），大家注意安全\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:02.323725+12
924	939	【中国文字狱事件记录】\n日期：2019年08月23日\n地点：陕西安康\n当事人：张某\n平台：微博\n言论内容：”辱警言论“\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:02.366765+12
925	940	【中国文字狱事件记录】\n日期：2019年08月26日\n地点：辽宁大连\n当事人：葛仁强\n平台：推特、YouTube\n言论内容：“大量点赞、评论、转发侮辱、污蔑国家领导人的言论、视频等”\n处罚：有期徒刑6个月\n法律文书：（2019）辽0291刑初379号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:02.415497+12
926	941	【中国文字狱事件记录】\n日期：2019年08月26日\n地点：广西柳州\n当事人：韦某\n平台：朋友圈\n言论内容：其子名为”韦我独尊“的PS户口本照片\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:02.459564+12
927	942	【中国文字狱事件记录】\n日期：2019年08月26日\n地点：四川泸州\n当事人：王某顾\n平台：某直播平台\n言论内容：在直播悼念活动里评论“多死几个”\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:02.512147+12
928	943	【中国文字狱事件记录】\n日期：2019年08月26日\n地点：山东日照\n当事人：江希文\n平台：网络\n言论内容：指控政府对信访人诉求推诿、暴力强拆、贪污腐败，称其为新型的中国式法西斯\n处罚：有期徒刑3年6个月，罚款2万元\n备注：二审维持原判\n法律文书：（2019）鲁1102刑初197号；（2019）鲁11刑终132号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:02.566332+12
929	944	【中国文字狱事件记录】\n日期：2019年08月27日\n地点：湖北通城县\n当事人：张某进\n平台：朋友圈\n言论内容：沙堆镇政府狗官\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:02.615559+12
930	945	【中国文字狱事件记录】\n日期：2019年08月27日\n地点：四川广安\n当事人：王某\n平台：朋友圈\n言论内容：广安这帮狗还真是敬业哦，都快到9点了还在外面贴罚单，丢雷老母，去吃屎啦\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:02.663037+12
931	946	【中国文字狱事件记录】\n日期：2019年08月29日\n地点：广东惠州\n当事人：薛斌\n平台：QQ群\n言论内容：参加香港游行示威、站队可以得到相应的报酬\n背景事件：香港反送中示威\n处罚：有期徒刑7个月\n法律文书：（2019）粤1302刑初1325号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:02.711399+12
932	947	【中国文字狱事件记录】\n日期：2019年08月29日\n地点：安徽阜阳\n当事人：李卉\n平台：推特、微信\n言论内容：创办自由之声论坛；发表侮辱社会主义制度的言论\n处罚：有期徒刑三年	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:02.758688+12
933	948	【中国文字狱事件记录】\n日期：2019年08月31日\n地点：西藏拉萨\n当事人：孔某\n平台：微博\n言论内容：“辱骂民警”\n处罚：拘留10日、罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:02.805688+12
934	949	【中国文字狱事件记录】\n日期：2019年08月31日\n地点：江苏沭阳\n当事人：刘某\n平台：微博\n言论内容：警察吃屎\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:02.852255+12
935	950	【中国文字狱事件记录】\n日期：2019年09月03日\n地点：黑龙江富裕县\n当事人：杨德福\n平台：网络、现实\n言论内容：向多个政府部门邮寄材料举报和在凯迪社区和天涯社区发帖指控办案人员包庇杀害他儿子的罪犯\n处罚：有期徒刑3年半\n法律文书：(2019)黑0227刑初123号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:02.899343+12
936	951	【中国文字狱事件记录】\n日期：2019年09月04日\n地点：湖北咸宁\n当事人：吴某辉\n平台：微信群\n言论内容：我们在玉立喝酒，不知道那里来了狗（警察）\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:02.946451+12
937	952	【中国文字狱事件记录】\n日期：2019年09月04日\n地点：山东临沂\n当事人：杨某\n平台：微信群\n言论内容：”辱骂交警“（语音信息）\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:02.993942+12
938	953	【中国文字狱事件记录】\n日期：2019年09月04日\n地点：山东临沂\n当事人：王某\n平台：微信群\n言论内容：”辱骂交警“（语音信息）\n处罚：拘留5日、罚款500	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:03.041189+12
939	954	【中国文字狱事件记录】\n日期：2019年09月04日\n地点：安徽凤阳县\n当事人：岳某\n平台：朋友圈\n言论内容：（交通罚单照片）买药吃啊，马勒xx\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:03.088017+12
940	955	【中国文字狱事件记录】\n日期：2019年09月05日\n地点：湖南株洲\n当事人：陈思明及其20多友人\n平台：微信群\n言论内容：捂住右眼拍照抗议\n背景事件：香港反送中示威\n处罚：羁押、强制删贴、警告\n备注：已是第六次被传唤	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:03.135876+12
941	956	【中国文字狱事件记录】\n日期：2019年09月06日\n地点：内蒙古通辽\n当事人：黄某\n平台：微信群\n言论内容：组织罢工\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:03.185199+12
942	957	【中国文字狱事件记录】\n日期：2019年09月06日\n地点：四川成都\n当事人：刁礼杨\n平台：推特\n言论内容：（在中共各官媒推特下评论）光复香港，时代革命；五大诉求，缺一不可\n背景事件：香港反送中示威\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:03.232459+12
943	958	【中国文字狱事件记录】\n日期：2019年09月06日\n地点：安徽潜山\n当事人：程钱生\n平台：推特\n言论内容：发布或者转发诋毁、辱骂他人、诋毁党和政府形象等推文471条\n处罚：有期徒刑10个月\n法律文书：（2019）皖0824刑初110号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:03.280067+12
944	959	【中国文字狱事件记录】\n日期：2019年09月06日\n地点：广东中山\n当事人：何坚铭\n平台：朋友圈、脸书、推特\n言论内容：“有损社会主义制度及国家领导人的不实言论及图片”\n处罚：有期徒刑1年\n法律文书：（2019）粤2072刑初1676号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:03.327392+12
945	960	【中国文字狱事件记录】\n日期：2019年09月07日\n地点：河南固始县\n当事人：张贵刚\n平台：QQ群\n言论内容：教师节当天全县教师到教育局门口庆祝教师节，具体安排请进群查看\n处罚：拘留10日\n法律文书：固公（治）行罚决字［2019］11243号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:03.382758+12
946	961	【中国文字狱事件记录】\n日期：2019年09月10日\n地点：河南正阳县\n当事人：王某\n平台：朋友圈\n言论内容：正阳的交警儿子们，爸爸回来看你们了\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:03.427529+12
947	962	【中国文字狱事件记录】\n日期：2019年09月10日\n地点：上海\n当事人：张展\n身份：律师\n平台：现实/印于雨伞\n言论内容：结束社会主义、共产党下台\n处罚：刑事拘留\n备注：65天后获释	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:03.475291+12
948	963	【中国文字狱事件记录】\n日期：2019年09月10日\n地点：江苏南京\n当事人：秦沪辉\n平台：现实/贴于自己车上\n言论内容：宪政、新闻自由、司法独立、官员财产公示等\n处罚：不公开审理	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:03.521578+12
949	964	【中国文字狱事件记录】\n日期：2019年09月11日\n地点：浙江宁波\n当事人：邵某\n平台：朋友圈\n言论内容：XX（不明不雅词汇，指交警）来了，有帽子的快戴上\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:03.567793+12
950	965	【中国文字狱事件记录】\n日期：2019年09月11日\n地点：浙江开化\n当事人：徐某\n平台：朋友圈\n言论内容：“辱警言论”\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:03.613042+12
951	966	【中国文字狱事件记录】\n日期：2019年09月12日\n地点：辽宁丹东\n当事人：孙安民\n平台：朋友圈\n言论内容：五条“侮辱警察的内容”\n处罚：有期徒刑10个月\n法律文书：（2019）辽0604刑初159号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:03.659902+12
952	967	【中国文字狱事件记录】\n日期：2019年09月13日\n地点：贵州贵阳\n当事人：张贾龙\n身份：知名异议人士，曾获克里接见\n平台：不详\n言论内容：大量政治言论\n处罚：批捕	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:03.707568+12
953	968	【中国文字狱事件记录】\n日期：2019年09月16日\n地点：湖北宜昌\n当事人：古顺明\n平台：微博、腾讯微博等\n言论内容：宜昌市委书记官商勾结；造假捐款；非法转移集体资产\n处罚：有期徒刑1年\n法律文书：（2019）鄂05刑终297号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:03.755974+12
954	969	【中国文字狱事件记录】\n日期：2019年09月16日\n地点：广东广州\n当事人：赖日福\n平台：朋友圈\n言论内容：这是我的祖国，我要让她自由（配乐“愿荣光归香港”）\n背景事件：香港反送中示威\n处罚：刑事拘留\n备注：此前已被捕过	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:03.803381+12
955	970	【中国文字狱事件记录】\n日期：2019年09月17日\n地点：青海化隆县\n当事人：马某\n平台：微信群\n言论内容：”辱警信息“\n处罚：拘留9日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:03.851239+12
956	971	【中国文字狱事件记录】\n日期：2019年09月19日\n地点：上海\n当事人：顾国平\n平台：大纪元、新唐人\n言论内容：接受采访时称支持香港；组织撑港集会\n背景事件：香港反送中示威\n处罚：刑事拘留\n备注：10月11日获释	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:03.898275+12
957	972	【中国文字狱事件记录】\n日期：2019年09月19日\n地点：广东陆丰\n当事人：陈泽良\n平台：微信公众平台\n言论内容：《湖东镇自来水公司强制收取镇内自来水用户400改造工本费，是否合法公平？》等文章，指控该公司舞弊\n处罚：有期徒刑1年3个月\n备注：二审改判1年\n法律文书：（2019）粤1581刑初553号；（2019）粤15刑终415号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:03.945959+12
958	973	【中国文字狱事件记录】\n日期：2019年09月19日\n地点：贵州黔东南\n当事人：宁某\n平台：微信群\n言论内容：政府算个屁\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:03.99346+12
959	974	【中国文字狱事件记录】\n日期：2019年09月19日\n地点：广东韶关\n当事人：甘某\n平台：朋友圈\n言论内容：饿老鬼就下班了还来抄我\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:04.038897+12
960	975	【中国文字狱事件记录】\n日期：2019年09月21日\n地点：江苏常熟市\n当事人：叶福涛\n平台：微博\n言论内容：举报拐卖儿童八年无结果罪犯许天宝拐卖儿童得到常熟市公安局局党委批准开大会表扬\n处罚：拘留10日、罚款500元\n法律文书：熟公（琴）行罚决字[2019]6301号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:04.085545+12
961	976	【中国文字狱事件记录】\n日期：2019年09月22日\n地点：安徽亳州i\n当事人：不详\n平台：朋友圈\n言论内容：奶奶的腿，一天得查八回\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:04.130151+12
962	977	【中国文字狱事件记录】\n日期：2019年09月23日\n地点：江西弋阳县\n当事人：雷献铅\n平台：多个平台\n言论内容：《弋阳县村霸违法违纪贪污腐败分子张某和陈某》等文章，指控乡村干部腐败\n处罚：有期徒刑1年\n法律文书：（2019）赣1126刑初107号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:04.169726+12
963	978	【中国文字狱事件记录】\n日期：2019年09月24日\n地点：贵州民族大学\n当事人：黄椿\n身份：学者/教师\n平台：推特、微信\n言论内容：关于香港反送中示威及六四事件信息\n背景事件：香港反送中示威、六四事件\n处罚：拘留15日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:04.209327+12
964	979	【中国文字狱事件记录】\n日期：2019年09月25日\n地点：吉林延吉市\n当事人：刘百林\n平台：QQ群\n言论内容：辱骂邓**及继任的国家领导人，侮辱现有法律，抹黑延吉市政府等言论\n处罚：拘留10日\n法律文书：延公（小）刑罚决字[2019]999号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:04.248991+12
965	980	【中国文字狱事件记录】\n日期：2019年09月25日\n地点：福建连城县\n当事人：项锦峰\n平台：推特\n言论内容：异见言论\n处罚：拘留9日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:04.28807+12
966	981	【中国文字狱事件记录】\n日期：2019年09月26日\n地点：江西会昌县\n当事人：刘晟（化名）\n平台：微信群\n言论内容：现在的交警就是狗；祝他们当交警的死全家\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:04.327126+12
967	982	【中国文字狱事件记录】\n日期：2019年09月26日\n地点：四川通江县\n当事人：周代城\n平台：微博\n言论内容：《爆炸新闻,问责控告四川省纪委巴中市纪委,包庇袒护纵容通江县重大贪腐》等指控当地政府腐败的文章\n处罚：有期徒刑2年2个月\n法律文书：（2019）川1921刑初144号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:04.369367+12
968	983	【中国文字狱事件记录】\n日期：2019年09月27日\n地点：浙江杭州\n当事人：毛庆祥（中国民主党浙江筹委会成员）\n平台：微信群\n言论内容：香港反送中示威有关信息\n背景事件：香港反送中示威\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:04.41384+12
969	984	【中国文字狱事件记录】\n日期：2019年09月28日\n地点：山东菏泽\n当事人：肖某\n平台：抖音\n言论内容：龙王庙街，让日本鬼子扫得比镜子都亮，真想关门来个旅游去\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:04.461001+12
970	985	【中国文字狱事件记录】\n日期：2019年09月28日\n地点：河南邓州\n当事人：余江帆\n平台：推特\n言论内容：全民觉醒、香港加油等\n背景事件：香港反送中示威\n处罚：刑事拘留\n备注：曾服刑三年半并三次被拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:04.508142+12
971	986	【中国文字狱事件记录】\n日期：2019年09月28日\n地点：湖南长沙\n当事人：樊钧益等人\n平台：现实/举牌\n言论内容：坚决反对当局大阅兵，费纳税人血汗民生不安；穷兵黩武 古有惩戒 内张爪利 外失度衡\n背景事件：中共建政70周年阅兵\n处罚：拘留5-15日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:04.555137+12
972	987	【中国文字狱事件记录】\n日期：2019年09月30日\n地点：四川达州\n当事人：候多蜀\n平台：微信\n言论内容：批评申纪兰被授予共和国勋章\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:04.60169+12
973	988	【中国文字狱事件记录】\n日期：2019年09月30日\n地点：四川南充\n当事人：戚某龙\n平台：微信群\n言论内容：阅兵有什么好看的\n背景事件：中共建政70周年阅兵\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:04.65339+12
974	989	【中国文字狱事件记录】\n日期：2019年09月30日\n地点：四川泸州\n当事人：王正春\n平台：微信群\n言论内容：天下乌鸦一般黑，市政府、公检法就是黑恶势力本身兼黑恶势力保护伞等\n处罚：拘留15日\n法律文书：泸江分公（北）行罚决字（2019）1924号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:04.717288+12
975	990	【中国文字狱事件记录】\n日期：2019年09月30日\n地点：浙江江山\n当事人：程某华\n平台：朋友圈\n言论内容：这些放移动测速的的，我就希望你们的老婆XXX\n处罚：拘留15日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:04.777651+12
976	991	【中国文字狱事件记录】\n日期：2019年09月30日\n地点：湖南张家界\n当事人：陈某勇\n平台：现实\n言论内容：撤掉某商铺悬挂的国旗并丢在地上\n处罚：拘留12日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:04.846002+12
977	992	【中国文字狱事件记录】\n日期：2019年10月01日\n地点：辽宁鞍山\n当事人：高广俊\n平台：微信群\n言论内容：让主席把我嘣了吧早晚我要反\n背景事件：中共建政70周年阅兵\n处罚：拘留15日\n法律文书：鞍公东（治）行罚决字[2019]743号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:04.905352+12
978	993	【中国文字狱事件记录】\n日期：2019年10月01日\n地点：北京\n当事人：“夏娃”\n平台：推特\n言论内容：要举青天白日旗上街\n背景事件：中共建政70周年阅兵\n处罚：刑事拘留\n备注：36天后获释	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:04.962591+12
979	994	【中国文字狱事件记录】\n日期：2019年10月01日\n地点：江苏镇江\n当事人：李某\n平台：论坛网站\n言论内容：交警执法视频以及“辱警语言”\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:05.007573+12
980	995	【中国文字狱事件记录】\n日期：2019年10月02日\n地点：广东清远\n当事人：莫某、王某\n平台：不详\n言论内容：精日言论\n处罚：拘留10日、5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:05.05684+12
981	996	【中国文字狱事件记录】\n日期：2019年10月02日\n地点：广东韶关\n当事人：黄某华\n平台：微信群\n言论内容：现在的警察和以前的日本人和土匪没什么两样\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:05.102291+12
982	997	【中国文字狱事件记录】\n日期：2019年10月02日\n地点：福建南靖县\n当事人：简朝国\n平台：微博\n言论内容：李同志荣获“不捉老鼠的花猫”\n处罚：拘留10日\n法律文书：靖公（治安）行罚决字［2019］00090号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:05.147974+12
983	998	【中国文字狱事件记录】\n日期：2019年10月02日\n地点：云南弥勒\n当事人：白某\n平台：朋友圈、微博\n言论内容：中国就是他妈的腐败国\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:05.188019+12
984	999	【中国文字狱事件记录】\n日期：2019年10月03日\n地点：新疆泽普县\n当事人：张某\n平台：境外网站\n言论内容：下载和传播法轮功电子书籍\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:05.229564+12
985	1000	【中国文字狱事件记录】\n日期：2019年10月03日\n地点：浙江台州\n当事人：林辉\n平台：推特\n言论内容：涉港言论、十一期间不当言论\n背景事件：香港反送中示威\n处罚：拘留15日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:05.272525+12
986	1001	【中国文字狱事件记录】\n日期：2019年10月03日\n地点：山东日照\n当事人：许某\n平台：朋友圈\n言论内容：祖国没养你，是你妈养的你\n背景事件：中共建政70周年阅兵\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:05.317074+12
987	1002	【中国文字狱事件记录】\n日期：2019年10月04日\n地点：河北石家庄\n当事人：徐某\n平台：微博\n言论内容：有可能是正直的警察被穷凶极恶的歹徒攻击，也可能是贪赃枉法的黑警被迫害过的人报复\n背景事件：浙江台州两名警察遇袭死亡\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:05.364282+12
988	1003	【中国文字狱事件记录】\n日期：2019年10月04日\n地点：江苏宿迁\n当事人：徐某\n平台：朋友圈\n言论内容：文明国家把机器变成军人，流氓国家把军人变成机器\n背景事件：中共建政70周年阅兵\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:05.411114+12
989	1004	【中国文字狱事件记录】\n日期：2019年10月05日\n地点：甘肃陇南\n当事人：张某喜\n平台：抖音\n言论内容：11条“诋毁扶贫政策和辱骂扶贫干部”的视频\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:05.458403+12
990	1005	【中国文字狱事件记录】\n日期：2019年10月06日\n地点：吉林辽源\n当事人：王颢达\n平台：微博\n言论内容：我与球队共存亡、来抓我吧、哈们（烧国旗照片）\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:05.505237+12
991	1006	【中国文字狱事件记录】\n日期：2019年10月06日\n地点：云南大理\n当事人：李某\n平台：微博\n言论内容：以前的警察为人民服务，现在的警察为人民币服务！恶心的警察，恶心的势力\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:05.55176+12
992	1007	【中国文字狱事件记录】\n日期：2019年10月06日\n地点：湖南郴州\n当事人：黎某林\n平台：朋友圈\n言论内容：装逼这些人渣，天天只知道搞人家的血汗钱（指民警）\n处罚：拘留15日、罚款1000元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:05.601263+12
993	1008	【中国文字狱事件记录】\n日期：2019年10月07日\n地点：江苏太仓\n当事人：印某\n平台：现实\n言论内容：点燃了某小区悬挂国旗的一角\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:05.648506+12
994	1009	【中国文字狱事件记录】\n日期：2019年10月07日\n地点：浙江杭州\n当事人：李某\n平台：现实\n言论内容：折断国旗旗杆、取下国旗并对其踩踏、小便\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:05.696716+12
995	1010	【中国文字狱事件记录】\n日期：2019年10月09日\n地点：浙江松阳县\n当事人：陈某\n平台：微信群\n言论内容：松阳交警队都是吃屎的\n处罚：拘留6日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:05.743686+12
996	1011	【中国文字狱事件记录】\n日期：2019年10月09日\n地点：贵州道真县\n当事人：郑某\n平台：朋友圈\n言论内容：你这些狗xx，五分钟不到就给我贴了。老子腿都跑断了都没跑到赢。你生儿子都不会xxx”\n处罚：拘留2日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:05.79015+12
997	1012	【中国文字狱事件记录】\n日期：2019年10月09日\n地点：山西清徐县\n当事人：韩某鹏\n平台：朋友圈\n言论内容：“涉政有害言论”\n处罚：拘留15日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:05.838122+12
998	1013	【中国文字狱事件记录】\n日期：2019年10月10日\n地点：河南漯河\n当事人：刘某\n平台：朋友圈\n言论内容：到家了给老爹对我这我操你妈卧槽你妈怼\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:05.886226+12
999	1014	【中国文字狱事件记录】\n日期：2019年10月10日\n地点：贵州松桃县\n当事人：刘某\n平台：朋友圈\n言论内容：帖你妈个逼呀！给你家买棺材，老子有的是钱，看看你家能死多少个我包了\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:05.933678+12
1000	1015	【中国文字狱事件记录】\n日期：2019年10月10日\n地点：新疆博乐市\n当事人：李某\n平台：网络\n言论内容：散布攻击、诋毁我区维稳政策的虚假、有害信息\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:05.98248+12
1001	1016	【中国文字狱事件记录】\n日期：2019年10月11日\n地点：成都理工大学\n当事人：刘玉富\n身份：学者/教师\n平台：QQ群、现实/课堂\n言论内容：毛概课堂里错误言论以及QQ群里妄议修宪\n背景事件：习近平修宪\n处罚：免职、吊销教师资格证	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:06.029796+12
1002	1017	【中国文字狱事件记录】\n日期：2019年10月11日\n地点：江苏无锡\n当事人：顾某与李某\n平台：微信群\n言论内容：一个地级市官员戴400万手表\n背景事件：无锡312国道高架桥塌陷，官员到场视察\n处罚：被传唤，无后续	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:06.07792+12
1003	1018	【中国文字狱事件记录】\n日期：2019年10月11日\n地点：山东曹县\n当事人：朱令洲\n平台：快手\n言论内容：转发一段有人把交警喊土匪的视频\n处罚：有期徒刑6个月，缓刑一年\n法律文书：（2019）鲁1721刑初523号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:06.125597+12
1004	1019	【中国文字狱事件记录】\n日期：2019年10月13日\n地点：河北石家庄\n当事人：温某\n平台：QQ群、微信群\n言论内容：侮辱受阅女兵、侮辱港警\n背景事件：中共建政70周年阅兵；香港反送中示威\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:06.174556+12
1005	1020	【中国文字狱事件记录】\n日期：2019年10月13日\n地点：宁夏银川\n当事人：不详\n平台：微信群\n言论内容：傻逼警察又来贴罚单了！都赶紧挪车！这警察是个250～\n处罚：拘留8日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:06.222393+12
1006	1021	【中国文字狱事件记录】\n日期：2019年10月13日\n地点：甘肃康县\n当事人：王某\n平台：朋友圈\n言论内容：”辱骂交警“\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:06.268975+12
1007	1022	【中国文字狱事件记录】\n日期：2019年10月14日\n地点：湖南邵阳\n当事人：于某\n平台：微信群\n言论内容：李西派出所的是垃圾、派出所没什么叨用\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:06.316738+12
1008	1023	【中国文字狱事件记录】\n日期：2019年10月14日\n地点：贵州铜仁\n当事人：周某\n平台：朋友圈\n言论内容：地震还是小了一点，最少12级才有感觉\n背景事件：铜仁地震\n处罚：拘留5日\n备注：人在福建，回老家自首	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:06.363979+12
1009	1024	【中国文字狱事件记录】\n日期：2019年10月15日\n地点：内蒙古\n当事人：赵八虎\n身份：作家\n平台：微信群\n言论内容：蒙文诗文及“攻击国家自治区政策言论”\n处罚：拘留15日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:06.412507+12
1010	1025	【中国文字狱事件记录】\n日期：2019年10月15日\n地点：湖北广水市\n当事人：马金龙\n平台：微信群\n言论内容：广水市境外的垃圾会运到焚烧厂焚烧，垃圾焚烧污染周围几十公里空气，垃圾焚烧会严重损害身体健康等\n处罚：有期徒刑1年5个月\n备注：二审维持原判\n法律文书：（2019）鄂1381刑初187号；（2019）鄂13刑终162号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:06.460474+12
1011	1026	【中国文字狱事件记录】\n日期：2019年10月15日\n地点：湖北广水市\n当事人：李松\n平台：微信群\n言论内容：广水十里有望成为省级垃圾站。附近地下水将严重污染，空气污染将覆盖几十公里，广水到了生死存亡的时候！癌症将激增\n处罚：有期徒刑1年3个月\n备注：二审维持原判\n法律文书：（2019）鄂1381刑初187号；（2019）鄂13刑终162号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:06.5071+12
1012	1027	【中国文字狱事件记录】\n日期：2019年10月15日\n地点：湖北广水市\n当事人：周建华\n平台：微信群\n言论内容：涉及垃圾焚烧厂建设的虚假信息，积极与群中人员商讨、谋划游行\n处罚：有期徒刑1年2个月、缓刑2年\n备注：二审维持原判\n法律文书：（2019）鄂1381刑初187号；（2019）鄂13刑终162号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:06.554737+12
1013	1028	【中国文字狱事件记录】\n日期：2019年10月15日\n地点：湖北广水市\n当事人：郑浩\n平台：微信群\n言论内容：发表虚假信息，并积极鼓动群成员上访、举报，制造声势影响\n处罚：有期徒刑1年2个月、缓刑2年\n备注：二审维持原判\n法律文书：（2019）鄂1381刑初187号；（2019）鄂13刑终162号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:06.601242+12
1014	1029	【中国文字狱事件记录】\n日期：2019年10月15日\n地点：湖北广水市\n当事人：刘秋花\n平台：微信群\n言论内容：发布虚假信息，积极谋划再次游行活动\n处罚：有期徒刑1年1个月、缓刑2年\n备注：二审维持原判\n法律文书：（2019）鄂1381刑初187号；（2019）鄂13刑终162号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:06.648711+12
1015	1030	【中国文字狱事件记录】\n日期：2019年10月15日\n地点：湖北广水市\n当事人：朱熹梅\n平台：微信群\n言论内容：“震怒百万广水人……”和游行示威图片；“我们要团结起来，共同抵制垃圾焚烧厂”\n处罚：有期徒刑1年1个月、缓刑2年\n备注：二审维持原判\n法律文书：（2019）鄂1381刑初187号；（2019）鄂13刑终162号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:06.700183+12
1016	1031	【中国文字狱事件记录】\n日期：2019年10月15日\n地点：湖北广水市\n当事人：乾红波\n平台：微信群\n言论内容：虚假言论、图片、视频，抵制广水市建垃圾焚烧厂\n处罚：有期徒刑1年、缓刑1年6个月\n备注：二审维持原判\n法律文书：（2019）鄂1381刑初187号；（2019）鄂13刑终162号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:06.753688+12
1017	1032	【中国文字狱事件记录】\n日期：2019年10月15日\n地点：湖北广水市\n当事人：聂锶银\n平台：微信群\n言论内容：散布虚假信息，策划游行\n处罚：有期徒刑1年、缓刑1年6个月\n备注：二审维持原判\n法律文书：（2019）鄂1381刑初187号；（2019）鄂13刑终162号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:06.806366+12
1243	1260	【中国文字狱事件记录】\n日期：2020年01月23日\n地点：广西宾阳县\n当事人：刘某才\n平台：网络\n言论内容：“诋毁公安的辛勤付出”\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:19.438098+12
1018	1033	【中国文字狱事件记录】\n日期：2019年10月15日\n地点：湖北广水市\n当事人：王霞\n平台：微信群\n言论内容：过激言论，共同抵制广水建垃圾焚烧厂\n处罚：有期徒刑1年、缓刑1年6个月\n备注：二审维持原判\n法律文书：（2019）鄂1381刑初187号；（2019）鄂13刑终162号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:06.858247+12
1019	1034	【中国文字狱事件记录】\n日期：2019年10月15日\n地点：河南郑州\n当事人：聂某\n平台：微博\n言论内容：“辱骂当地交警”\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:06.91099+12
1020	1035	【中国文字狱事件记录】\n日期：2019年10月16日\n地点：陕西西安\n当事人：高某\n平台：网络\n言论内容：针对牺牲民警的不当言论\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:06.967614+12
1021	1036	【中国文字狱事件记录】\n日期：2019年10月17日\n地点：广东广州\n当事人：黄雪琴\n平台：Matters\n言论内容：《记录我的反送中大游行》\n背景事件：香港反送中示威\n处罚：被警方带走，疑似被刑拘	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:07.012885+12
1022	1037	【中国文字狱事件记录】\n日期：2019年10月17日\n地点：新疆哈密市\n当事人：赵某\n平台：境外网站\n言论内容：浏览、转发危害国家荣誉、侵害他人名誉等虚假、有害图文信息\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:07.062204+12
1023	1038	【中国文字狱事件记录】\n日期：2019年10月17日\n地点：江西鄱阳\n当事人：罗某\n平台：微信\n言论内容：大日本帝国万岁，天皇陛下万岁\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:07.117531+12
1024	1039	【中国文字狱事件记录】\n日期：2019年10月17日\n地点：湖北武汉\n当事人：黄某\n平台：微信群\n言论内容：不当言论\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:07.164191+12
1025	1040	【中国文字狱事件记录】\n日期：2019年10月17日\n地点：安徽舒城县\n当事人：俞某\n平台：微信群\n言论内容：去派出所办事遇到刁难，被要求出示不必要证明，给在纪委工作的哥哥打电话之后就好了\n处罚：罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:07.232605+12
1026	1041	【中国文字狱事件记录】\n日期：2019年10月17日\n地点：山西清徐县\n当事人：姚某辰\n平台：微信群\n言论内容：“污蔑国家领导人的涉政有害信息”\n处罚：拘留15日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:07.293873+12
1027	1042	【中国文字狱事件记录】\n日期：2019年10月17日\n地点：山西清徐县\n当事人：庞某水\n平台：微信群\n言论内容：“污蔑国家领导人的涉政有害信息”\n处罚：拘留15日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:07.349223+12
1028	1043	【中国文字狱事件记录】\n日期：2019年10月17日\n地点：内蒙古海拉尔\n当事人：孙某\n平台：朋友圈\n言论内容：“辱警言论”\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:07.414236+12
1029	1044	【中国文字狱事件记录】\n日期：2019年10月17日\n地点：辽宁辽阳市\n当事人：顾某\n平台：推特\n言论内容：“辱骂国家领导人、攻击中国共产党和社会主义制度、包括支持香港独立、煽动分裂国家政权”等\n处罚：起诉（寻衅滋事罪）\n法律文书：辽白检公诉刑诉〔2019〕202号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:07.470765+12
1030	1045	【中国文字狱事件记录】\n日期：2019年10月18日\n地点：江苏无锡\n当事人：冯峻勇\n平台：不详\n言论内容：美国收的25%关税，是收的习的智商税\n背景事件：中美贸易战\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:07.527232+12
1031	1046	【中国文字狱事件记录】\n日期：2019年10月18日\n地点：广东汕尾\n当事人：郑某培、彭某涛\n平台：不详\n言论内容：“辱警言论”\n处罚：拘留15日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:07.578777+12
1032	1047	【中国文字狱事件记录】\n日期：2019年10月18日\n地点：甘肃临夏\n当事人：党某\n平台：微信群\n言论内容：“攻击当地合作医疗体系”及“辱骂党和国家工作人员”\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:07.637241+12
1033	1048	【中国文字狱事件记录】\n日期：2019年10月18日\n地点：陕西西安\n当事人：杨某\n平台：新闻客户端\n言论内容：撞得好嚣张的地头蛇\n背景事件：西安警察殉职\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:07.688767+12
1034	1049	【中国文字狱事件记录】\n日期：2019年10月18日\n地点：河南滑县\n当事人：李某\n平台：推特\n言论内容：“抨击我国现行法律体系，损害国家领导人及共产党形象等混淆视听的虚假有害信息”\n处罚：起诉（寻衅滋事罪）\n法律文书：安滑检一部刑诉〔2019〕329号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:07.739859+12
1035	1050	【中国文字狱事件记录】\n日期：2019年10月19日\n地点：湖北武汉\n当事人：占某\n平台：QQ群\n言论内容：不当言论\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:07.792558+12
1036	1051	【中国文字狱事件记录】\n日期：2019年10月20日\n地点：安徽泾县\n当事人：胡某\n平台：朋友圈\n言论内容：大白天的就肆意抓狗，公然屠杀……干这种事的人祝你们早点下地狱！\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:07.84054+12
1037	1052	【中国文字狱事件记录】\n日期：2019年10月21日\n地点：山西财经大学\n当事人：曹继生\n身份：学者/教师\n平台：微信群\n言论内容：不当言论\n处罚：行政记过	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:07.894852+12
1038	1053	【中国文字狱事件记录】\n日期：2019年10月21日\n地点：江西万年县\n当事人：姜荣生\n平台：朋友圈\n言论内容：放弃生命不是英雄，是狗熊，又少了几个浪费粮食的，真好\n背景事件：四川木里森林大火\n处罚：有期徒刑1年8个月\n备注：二审改判9个月\n法律文书：（2019）赣11刑终380号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:07.960248+12
1039	1054	【中国文字狱事件记录】\n日期：2019年10月21日\n地点：广西河池\n当事人：陈某\n平台：朋友圈、论坛\n言论内容：当地某福彩活动造假\n处罚：行政处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:08.028446+12
1040	1055	【中国文字狱事件记录】\n日期：2019年10月21日\n地点：浙江宁波\n当事人：周某\n平台：论坛网站\n言论内容：黑警、黑狗、畜生等\n处罚：6个月拘役	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:08.097702+12
1041	1056	【中国文字狱事件记录】\n日期：2019年10月21日\n地点：河北邢台县\n当事人：王老二\n平台：多个平台\n言论内容：指控当地村支书在村委会选举中贿选，且在工作中存在腐败和滥权的情况\n处罚：有期徒刑1年2个月\n备注：二审维持原判\n法律文书：（2019）冀0521刑初149号；（2019）冀05刑终552号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:08.188491+12
1042	1057	【中国文字狱事件记录】\n日期：2019年10月22日\n地点：河北永清县\n当事人：司云鹏\n平台：多个其自有的网站\n言论内容：《河北永清县：廊霸路韩村段造林绿化工程被指违法违规》等指控政府的文章\n处罚：有期徒刑11个月\n法律文书：（2019）冀1023刑初189号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:08.234665+12
1043	1058	【中国文字狱事件记录】\n日期：2019年10月22日\n地点：广西百色\n当事人：陆某传\n平台：微信\n言论内容：一张张丑漏（陋）的嘴脸，为了政绩疯狂着\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:08.292626+12
1044	1059	【中国文字狱事件记录】\n日期：2019年10月22日\n地点：内蒙古鄂尔多斯\n当事人：梁某\n平台：微信群\n言论内容：某化肥产品质量不好（引发群众聚集抗议）\n处罚：拘留8日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:08.348472+12
1045	1060	【中国文字狱事件记录】\n日期：2019年10月22日\n地点：广东汕尾\n当事人：熊某华、李某真\n平台：微信群\n言论内容：发布与转发“辱警视频”\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:08.399789+12
1046	1061	【中国文字狱事件记录】\n日期：2019年10月23日\n地点：湖南长沙\n当事人：李冬\n平台：推特\n言论内容：支持香港；反对中共\n背景事件：香港反送中示威\n处罚：拘留12日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:08.450093+12
1047	1062	【中国文字狱事件记录】\n日期：2019年10月23日\n地点：浙江台州\n当事人：王法正\n平台：朋友圈\n言论内容：”诋毁和辱骂党和国家及党和国家领导人的内容“\n处罚：有期徒刑2年\n备注：曾因相同原因被行拘\n法律文书：（2019）浙1002刑初578号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:08.507336+12
1048	1063	【中国文字狱事件记录】\n日期：2019年10月23日\n地点：安徽六安\n当事人：朱某\n平台：贴吧\n言论内容：比起杀人犯，执法的吊毛更像个SB\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:08.565915+12
1049	1064	【中国文字狱事件记录】\n日期：2019年10月24日\n地点：贵州黔东南\n当事人：杨某\n平台：微信群\n言论内容：”诋毁中国共产党的视频“\n处罚：拘留15日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:08.625465+12
1050	1065	【中国文字狱事件记录】\n日期：2019年10月24日\n地点：河北唐山\n当事人：姚某\n平台：恶俗维基\n言论内容：“谣言”与“反华内容”\n处罚：传唤警告	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:08.682094+12
1051	1066	【中国文字狱事件记录】\n日期：2019年10月24日\n地点：河北唐山\n当事人：谷某\n平台：恶俗维基\n言论内容：“谣言”与“反华内容”\n处罚：传唤警告	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:08.738018+12
1052	1067	【中国文字狱事件记录】\n日期：2019年10月25日\n地点：山东临沂\n当事人：魏某锁\n平台：微信群\n言论内容：“诋毁党的声誉的反动言论”\n处罚：拘留15日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:08.79938+12
1053	1068	【中国文字狱事件记录】\n日期：2019年10月25日\n地点：辽宁沈阳\n当事人：孙晓龙\n平台：推特\n言论内容：大量严重损害国家形象，严重危害国家利益的虚假信息\n处罚：有期徒刑10个月\n法律文书：（2019）辽0113刑初350号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:08.854769+12
1054	1069	【中国文字狱事件记录】\n日期：2019年10月25日\n地点：云南永平县\n当事人：杨某\n平台：朋友圈\n言论内容：“诋毁国家政策、诬蔑政府形象”\n处罚：拘留9日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:08.898383+12
1055	1074	【中国文字狱事件记录】\n日期：2019年10月29日\n地点：浙江宁波\n当事人：唐某\n平台：朋友圈\n言论内容：“辱警言论”\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:09.145176+12
1056	1070	【中国文字狱事件记录】\n日期：2019年10月26日\n地点：辽宁辽阳\n当事人：王敬\n平台：微信群\n言论内容：香港是自由的灯塔，世界的香港。拥有自由，没有独裁和暴政，无论哪里都能成为香港\n背景事件：香港反送中示威\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:08.95039+12
1057	1071	【中国文字狱事件记录】\n日期：2019年10月28日\n地点：广西河池\n当事人：杨某\n平台：微信群\n言论内容：死了二十八个人\n背景事件：当地发生矿难\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:08.998273+12
1058	1072	【中国文字狱事件记录】\n日期：2019年10月28日\n地点：河北沧县\n当事人：尹治岭\n平台：现实\n言论内容：在派出所墙壁及自己三轮车上书写“打倒共产党”等反共标语，当面辱骂政府官员\n处罚：有期徒刑一年\n备注：二审维持原判\n法律文书：（2019）冀0921刑初306号；（2020）冀09刑终113号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:09.049032+12
1059	1075	【中国文字狱事件记录】\n日期：2019年10月29日\n地点：新疆伊宁县\n当事人：马某\n平台：推特\n言论内容：浏览“涉及反党、反习、反社会主义、反宗教民族政策类型的视频”，发布“反动言论”共计37条\n处罚：起诉（寻衅滋事罪）\n法律文书：伊宁县检公诉刑诉〔2019〕565号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:09.191461+12
1060	1076	【中国文字狱事件记录】\n日期：2019年10月30日\n地点：辽宁葫芦岛\n当事人：刘海（残疾人）\n平台：QQ群\n言论内容：“辱骂国家领导人（习近平或其他本届领导）”\n处罚：有期徒刑6个月\n法律文书：（2019）辽1402刑初310号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:09.241099+12
1061	1077	【中国文字狱事件记录】\n日期：2019年10月30日\n地点：湖南涟源\n当事人：刘某\n平台：朋友圈\n言论内容：一大早买个蔡，被狗咬一口\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:09.29347+12
1062	1078	【中国文字狱事件记录】\n日期：2019年10月30日\n地点：北京\n当事人：董泽华\n平台：现实\n言论内容：于2019年六四当天在天安门广场就“敏感话题”采访广场上的外国人\n处罚：有期徒刑7个月\n法律文书：（2019）京0101刑初789号；（2019）京02刑终776号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:09.346001+12
1063	1079	【中国文字狱事件记录】\n日期：2019年10月30日\n地点：北京\n当事人：原帅\n平台：现实\n言论内容：于2019年六四当天在天安门广场穿着有“敏感标志”的t恤拍照，并就“敏感话题”采访广场上的外国人\n处罚：有期徒刑6个月\n法律文书：（2019）京0101刑初789号；（2019）京02刑终776号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:09.406349+12
1064	1081	【中国文字狱事件记录】\n日期：2019年10月31日\n地点：贵州岑巩县\n当事人：周某\n平台：朋友圈\n言论内容：“辱骂交警”\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:09.532886+12
1065	1082	【中国文字狱事件记录】\n日期：2019年10月31日\n地点：江苏宿迁\n当事人：徐某\n平台：贴吧\n言论内容：（沭阳县）人民医院的水平已经差成这样了？\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:09.586376+12
1066	1083	【中国文字狱事件记录】\n日期：2019年11月01日\n地点：广西柳州\n当事人：余某\n平台：朋友圈\n言论内容：心中一万个xxx，大半夜还碍一单，你是有多饿钱啊，祝你全家都被车撞死\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:09.628478+12
1067	1084	【中国文字狱事件记录】\n日期：2019年11月01日\n地点：山东日照\n当事人：孙某\n平台：朋友圈\n言论内容：看看我们日照的伪军（指交警）\n处罚：拘留10日、罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:09.680011+12
1068	1085	【中国文字狱事件记录】\n日期：2019年11月01日\n地点：河南淮滨县\n当事人：王某\n平台：网络\n言论内容：”不良言论“\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:09.733979+12
1069	1086	【中国文字狱事件记录】\n日期：2019年11月02日\n地点：湖南长沙\n当事人：周再强\n平台：推特\n言论内容：支持香港示威言论\n背景事件：香港反送中示威\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:09.78858+12
1070	1087	【中国文字狱事件记录】\n日期：2019年11月05日\n地点：湖北武汉\n当事人：罗岱青\n身份：境外人士\n平台：推特\n言论内容：“丑化国家领导人形象的言论及不雅拼装图片信息40余条”（在美国发表）\n处罚：有期徒刑6个月\n法律文书：（2019）鄂0106刑初1087号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:09.842396+12
1071	1088	【中国文字狱事件记录】\n日期：2019年11月05日\n地点：新疆昌吉\n当事人：袁某\n平台：网络\n言论内容：“谣言信息”\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:09.900328+12
1072	1089	【中国文字狱事件记录】\n日期：2019年11月06日\n地点：广东惠州\n当事人：曾某\n平台：微博\n言论内容：阿里妞妞推文截图，内容为中共高层人事变动信息；翻墙使用脸书\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:09.967221+12
1073	1090	【中国文字狱事件记录】\n日期：2019年11月07日\n地点：甘肃陇南\n当事人：王某\n平台：微信群\n言论内容：辱骂村镇干部\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:10.080124+12
1074	1091	【中国文字狱事件记录】\n日期：2019年11月07日\n地点：广东中山\n当事人：汪北源\n平台：推特\n言论内容：诋毁国家领导人、抹黑中国政府及抨击国家政策\n处罚：有期徒刑1年\n法律文书：（2019）粤2071刑初1881号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:10.257665+12
1075	1092	【中国文字狱事件记录】\n日期：2019年11月08日\n地点：广东汕尾\n当事人：吕某雄\n平台：QQ群\n言论内容：”辱骂交警“\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:10.70671+12
1076	1093	【中国文字狱事件记录】\n日期：2019年11月08日\n地点：安徽阜南县\n当事人：鲍前林\n平台：中华新闻通讯社\n言论内容：当地村干部违规为自己亲友办理低保等指控官员腐败的信息\n处罚：有期徒刑1年6个月\n备注：二审维持原判\n法律文书：（2019）皖1225刑初306号；（2019）皖12刑终798号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:10.885795+12
1077	1095	【中国文字狱事件记录】\n日期：2019年11月09日\n地点：浙江温州\n当事人：赵某\n平台：微信群\n言论内容：城市的派出所和我们农村的不一样，我们农村的是疯狗\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:11.064084+12
1078	1096	【中国文字狱事件记录】\n日期：2019年11月11日\n地点：湖北长阳县\n当事人：田迎华\n平台：凯迪社区、现实\n言论内容：上访以及在凯迪社区发表《法院不为民作主，百姓有冤向谁诉》等帖子\n处罚：有期徒刑2年半\n备注：曾服刑1年半\n法律文书：(2019)黑0227刑初123号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:11.148677+12
1079	1097	【中国文字狱事件记录】\n日期：2019年11月11日\n地点：广西桂林\n当事人：陈某\n平台：电话\n言论内容：那你们警察就是吃干饭的咯？\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:11.219354+12
1080	1098	【中国文字狱事件记录】\n日期：2019年11月12日\n地点：云南大理\n当事人：王某、于某\n平台：QQ群、微博\n言论内容：大理大学护理学院一位女生被留学生强奸了？\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:11.297076+12
1081	1099	【中国文字狱事件记录】\n日期：2019年11月12日\n地点：陕西咸阳\n当事人：冯某\n平台：抖音\n言论内容：大快人心\n背景事件：西安警察殉职\n处罚：拘留15日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:11.370151+12
1082	1100	【中国文字狱事件记录】\n日期：2019年11月12日\n地点：江苏泰州\n当事人：周某\n平台：朋友圈\n言论内容：最近的狗，最近的狗，这是怎么了\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:11.461037+12
1083	1101	【中国文字狱事件记录】\n日期：2019年11月12日\n地点：四川绵阳\n当事人：叶某\n平台：朋友圈\n言论内容：JJ烦得跟狗样\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:11.602296+12
1084	1102	【中国文字狱事件记录】\n日期：2019年11月12日\n地点：吉林松原\n当事人：姜玉春\n平台：朋友圈\n言论内容：房价即将崩盘、中共喉舌疯狂叫嚣，三连炫耀武力，灭亡路上穷兵黩武的疯狂等\n处罚：有期徒刑1年2个月\n法律文书：（2019）吉0702刑初471号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:11.684289+12
1085	1103	【中国文字狱事件记录】\n日期：2019年11月12日\n地点：贵州黔东南\n当事人：胡某等五人\n身份：退伍军人\n平台：现实\n言论内容：乞讨\n处罚：已审未判	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:11.767281+12
1086	1104	【中国文字狱事件记录】\n日期：2019年11月13日\n地点：湖北黄冈\n当事人：张某\n平台：微信\n言论内容：评论“湖北黄冈交警”发布的内容时的“辱警信息”\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:11.872019+12
1087	1105	【中国文字狱事件记录】\n日期：2019年11月13日\n地点：南昌航空大学\n当事人：牛杰（研究生导师）\n身份：学者/教师\n平台：微信群\n言论内容：所谓暴徒都是孩子，没有整死一个人\n背景事件：香港反送中示威\n处罚：介入调查	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:12.008415+12
1088	1106	【中国文字狱事件记录】\n日期：2019年11月13日\n地点：辽宁绥中县\n当事人：吕某\n平台：朋友圈\n言论内容：绥中的老百姓，只要你是2015年1月1日之后办理过房产证，交过公共维修基金的，定于11月14日上午10点到绥中县房产大厅集合，要回大家的钱。\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:12.104193+12
1089	1107	【中国文字狱事件记录】\n日期：2019年11月14日\n地点：广东深圳\n当事人：胡双庆\n平台：微信群\n言论内容：声援香港示威言论\n背景事件：香港反送中示威\n处罚：拘留13日；公司辞退	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:12.185302+12
1090	1108	【中国文字狱事件记录】\n日期：2019年11月14日\n地点：安徽池州\n当事人：周执忠\n平台：网络、现实\n言论内容：上访申冤、贴大字报和网络发帖指控政府\n处罚：有期徒刑4年\n备注：二审维持原判\n法律文书：（2019）皖17刑终124号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:12.274622+12
1091	1109	【中国文字狱事件记录】\n日期：2019年11月16日\n地点：甘肃天水\n当事人：郭某田\n平台：QQ群\n言论内容：“不当言论”\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:12.358076+12
1092	1110	【中国文字狱事件记录】\n日期：2019年11月17日\n地点：山西灵石县\n当事人：王某\n平台：快手\n言论内容：“不正当言论”\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:12.426781+12
1093	1111	【中国文字狱事件记录】\n日期：2019年11月17日\n地点：辽宁铁岭\n当事人：王某\n平台：朋友圈\n言论内容：草你奶奶腿儿的交警\n处罚：拘留5日、罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:12.482599+12
1094	1112	【中国文字狱事件记录】\n日期：2019年11月17日\n地点：福建莆田\n当事人：林某金\n平台：朋友圈\n言论内容：“辱警言论”\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:12.534928+12
1095	1113	【中国文字狱事件记录】\n日期：2019年11月18日\n地点：福建漳州\n当事人：林某\n平台：微信群\n言论内容：前增桥又在抓了，疯狗，疯狗（指警察）\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:12.587051+12
1096	1114	【中国文字狱事件记录】\n日期：2019年11月18日\n地点：福建龙海\n当事人：林某\n平台：微信群\n言论内容：“辱骂执勤民警”\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:12.638003+12
1097	1115	【中国文字狱事件记录】\n日期：2019年11月18日\n地点：广西北海\n当事人：王某华\n平台：朋友圈\n言论内容：”涉港不当言论“；支持”港独“图片\n背景事件：香港反送中示威\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:12.686939+12
1098	1116	【中国文字狱事件记录】\n日期：2019年11月19日\n地点：甘肃定西\n当事人：汪某\n平台：微信群\n言论内容：畜生（指交警）\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:12.738862+12
1099	1117	【中国文字狱事件记录】\n日期：2019年11月20日\n地点：浙江杭州\n当事人：彭某\n平台：微博\n言论内容：傻逼萧山交警，天天头盔头盔，烦得一批，头盔在你xx呢，去拿阿\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:12.788133+12
1100	1118	【中国文字狱事件记录】\n日期：2019年11月20日\n地点：四川宜宾\n当事人：刘某\n平台：社交网站\n言论内容：一则“对交警处罚不满的带攻击性语言的消息”\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:12.841004+12
1101	1119	【中国文字狱事件记录】\n日期：2019年11月21日\n地点：河北文安县\n当事人：张某\n平台：快手\n言论内容：一段村镇干部工作的视频及侮辱性文字\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:12.886207+12
1102	1120	【中国文字狱事件记录】\n日期：2019年11月22日\n地点：辽宁丹东\n当事人：于晶磊\n平台：微信\n言论内容：“不当言论”（警方称是谣言）\n处罚：拘留10日、罚款500元\n法律文书：丹公兴（治）行罚决字[2019]1211号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:12.928321+12
1103	1121	【中国文字狱事件记录】\n日期：2019年11月22日\n地点：河北石家庄\n当事人：曹某、叶某\n平台：微信群\n言论内容：《裕华区疾控防疫中心（鼠疫）通知》照片\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:12.983281+12
1104	1122	【中国文字狱事件记录】\n日期：2019年11月22日\n地点：河北石家庄\n当事人：张某、丁某\n平台：微信群\n言论内容：转发《裕华区疾控防疫中心（鼠疫）通知》照片\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:13.026443+12
1105	1123	【中国文字狱事件记录】\n日期：2019年11月22日\n地点：福建福州\n当事人：林应强、唐兆星与林兰英\n平台：现实\n言论内容：在看守所门口迎接被释放的维权人士严兴声，并在场放鞭炮庆祝\n处罚：已审未判	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:13.071893+12
1106	1124	【中国文字狱事件记录】\n日期：2019年11月22日\n地点：湖南茶陵县\n当事人：肖明娇\n平台：现实\n言论内容：在车上张贴申冤标语和穿状衣进京上访\n处罚：有期徒刑2年半\n备注：二审维持原判\n法律文书：（2019）湘02刑终427号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:13.115962+12
1107	1125	【中国文字狱事件记录】\n日期：2019年11月23日\n地点：安徽东至县\n当事人：张志祥\n平台：微信群\n言论内容：21世纪现代文明社会，共匪不亡，天理不容（其后在庭审中辩称指的是美国共和党）\n处罚：拘留5日\n法律文书：东公（泥）行罚决字[2019]第698号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:13.160271+12
1108	1126	【中国文字狱事件记录】\n日期：2019年11月24日\n地点：甘肃长武县\n当事人：张某\n平台：快手\n言论内容：“辱警言论”\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:13.213878+12
1109	1127	【中国文字狱事件记录】\n日期：2019年11月24日\n地点：吉林珲春\n当事人：马某\n平台：朋友圈\n言论内容：一段“辱骂和挑衅”交警的视频\n处罚：拘留10日、罚款300元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:13.264469+12
1110	1128	【中国文字狱事件记录】\n日期：2019年11月25日\n地点：北京\n当事人：黄硕\n平台：微信群\n言论内容：烈士又不是给我家救火死的，关我屁事\n处罚：拘役4个月\n法律文书：（2019）京0101刑初543号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:13.305759+12
1111	1129	【中国文字狱事件记录】\n日期：2019年11月25日\n地点：甘肃定西\n当事人：陈某\n平台：微信群\n言论内容：“辱骂村干部”\n处罚：罚款400元、教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:13.34909+12
1112	1130	【中国文字狱事件记录】\n日期：2019年11月26日\n地点：陕西咸阳\n当事人：王宽宽\n平台：QQ群\n言论内容：”不实信息，攻击党和国家领导人“\n处罚：有期徒刑1年\n法律文书：（2019）陕0402刑初 586号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:13.396059+12
1113	1131	【中国文字狱事件记录】\n日期：2019年11月26日\n地点：辽宁丹东\n当事人：张晓虎\n平台：推特\n言论内容：“大量发布、转发、评论关于国内重大事件的虚假信息和损害国家形象的信息”\n处罚：有期徒刑9个月\n法律文书：（2019）辽0602刑初226号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:13.446957+12
1114	1132	【中国文字狱事件记录】\n日期：2019年11月26日\n地点：山西晋城\n当事人：李某\n平台：推特、微信\n言论内容：涉习负面信息\n处罚：有期徒刑1年\n备注：曾因同样原因被拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:13.495755+12
1115	1133	【中国文字狱事件记录】\n日期：2019年11月26日\n地点：江西九江\n当事人：钟某\n平台：朋友圈\n言论内容：修水交警，我要骂死你祖宗十八代……拿我摩托车的人，会过不了今晚\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:13.548082+12
1116	1134	【中国文字狱事件记录】\n日期：2019年11月26日\n地点：陕西宝鸡\n当事人：龙克海\n平台：脸书、推特\n言论内容：批评习近平言论\n处罚：有期徒刑一年半\n备注：2018年曾因同样原因被拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:13.596212+12
1117	1135	【中国文字狱事件记录】\n日期：2019年11月27日\n地点：安徽马鞍山\n当事人：张荣沂\n平台：微信群\n言论内容：关于国家领导人的不实信息、诽谤国家领导人、习近平访问朝鲜的诋毁信息\n处罚：有期徒刑6个月\n法律文书：（2019）皖0506刑初116号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:13.649555+12
1118	1136	【中国文字狱事件记录】\n日期：2019年11月27日\n地点：辽宁抚顺\n当事人：李浩\n平台：推特\n言论内容：“损害国家形象、严重危害国家利益的虚假信息120个”\n处罚：有期徒刑1年\n法律文书：（2019）辽0404刑初210号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:13.699167+12
1119	1137	【中国文字狱事件记录】\n日期：2019年11月28日\n地点：贵州清镇市\n当事人：于某\n平台：微信群\n言论内容：“辱警语音信息”\n处罚：拘留15日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:13.755929+12
1120	1138	【中国文字狱事件记录】\n日期：2019年11月29日\n地点：辽宁营口\n当事人：王某\n平台：朋友圈\n言论内容：（视频）警察打人了，又撂倒一个；狗就是狗，如果发生在你家，你就不会这个态度了\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:13.807449+12
1121	1139	【中国文字狱事件记录】\n日期：2019年11月30日\n地点：黑龙江大兴安岭\n当事人：姜坤\n平台：推特\n言论内容：攻击中华人民共和国社会主义制度和国家政策的推文\n处罚：有期徒刑8个月\n法律文书：（2019）黑2701刑初71号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:13.85735+12
1122	1140	【中国文字狱事件记录】\n日期：2019年12月01日\n地点：云南永善\n当事人：王某\n平台：微博\n言论内容：关于当地扶贫政策的攻击性言论\n处罚：拘留9日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:13.908586+12
1123	1141	【中国文字狱事件记录】\n日期：2019年12月02日\n地点：天津\n当事人：顾某\n平台：抖音\n言论内容：（居民烧火取暖视频）新闻静海区福林小镇物业不作为，逼的老百姓没办法了\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:13.966145+12
1124	1142	【中国文字狱事件记录】\n日期：2019年12月02日\n地点：山西太原\n当事人：刘淑芳\n平台：网络\n言论内容：关于香港示威图片\n背景事件：香港反送中示威\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:14.018836+12
1125	1143	【中国文字狱事件记录】\n日期：2019年12月02日\n地点：山西太原\n当事人：赵国栋\n平台：网络\n言论内容：香港给中国捐了很多钱；香港亲共势力落选，共产党就把气出在中国人身上\n背景事件：香港反送中示威\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:14.068181+12
1126	1144	【中国文字狱事件记录】\n日期：2019年12月02日\n地点：河南修武县\n当事人：侯某\n平台：朋友圈\n言论内容：“辱骂交警”的视频\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:14.116657+12
1127	1145	【中国文字狱事件记录】\n日期：2019年12月03日\n地点：广西南宁\n当事人：覃永沛\n平台：推特、微博等\n言论内容：“诋毁造谣国家领导人、攻击国家政权和社会主义制度”；“诽谤司法机关腐败、抹黑现行司法体制”\n处罚：批捕\n法律文书：南公捕通字［2019］0715号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:14.162818+12
1128	1146	【中国文字狱事件记录】\n日期：2019年12月04日\n地点：贵州沿河县\n当事人：杨某\n平台：微信群\n言论内容：“辱骂村干部”\n处罚：拘留8日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:14.216203+12
1129	1147	【中国文字狱事件记录】\n日期：2019年12月04日\n地点：湖南涟源市\n当事人：陈某\n平台：朋友圈\n言论内容：你奶奶的腿，告花子，老是搞我的路\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:14.27146+12
1130	1148	【中国文字狱事件记录】\n日期：2019年12月04日\n地点：黑龙江大庆\n当事人：李艳梅\n平台：朋友圈、现实\n言论内容：（朋友圈）辱骂国家领导人、评议社会的负面信息；（贴大字报、举横幅）辱骂国家领导人\n处罚：有期徒刑6个月\n法律文书：（2019）黑0602刑初366号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:14.323332+12
1131	1149	【中国文字狱事件记录】\n日期：2019年12月04日\n地点：云南昆明\n当事人：杨得龙\n平台：陌陌、朋友圈\n言论内容：“侮辱凉山消防英雄得言论”\n背景事件：四川木里森林大火\n处罚：有期徒刑9个月\n法律文书：（2019）云0111刑初1934号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:14.375071+12
1132	1150	【中国文字狱事件记录】\n日期：2019年12月05日\n地点：安徽广德市\n当事人：胡某\n平台：微信群\n言论内容：”抹黑党委政府形象“和”煽动聚集闹事“\n处罚：拘留12日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:14.427241+12
1133	1151	【中国文字狱事件记录】\n日期：2019年12月05日\n地点：湖北恩施\n当事人：不详\n平台：抖音\n言论内容：“辱骂交警的言论”\n处罚：拘留15日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:14.491813+12
1134	1152	【中国文字狱事件记录】\n日期：2019年12月05日\n地点：河南灵宝市\n当事人：何某\n平台：朋友圈\n言论内容：一张违章处罚剪切图，内容为其因未给狗让路而被罚\n处罚：拘留10日、罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:14.540936+12
1135	1153	【中国文字狱事件记录】\n日期：2019年12月06日\n地点：四川轻化工大学\n当事人：李志\n身份：学者/教师\n平台：不详\n言论内容：不当言论\n处罚：行政记过；调至图书馆	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:14.588889+12
1136	1154	【中国文字狱事件记录】\n日期：2019年12月06日\n地点：内蒙古锡林郭勒\n当事人：席某\n平台：微信群\n言论内容：称警察为看门狗的语音信息\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:14.638493+12
1137	1155	【中国文字狱事件记录】\n日期：2019年12月06日\n地点：浙江象山县\n当事人：茅春花\n平台：新浪网\n言论内容：指控当地派出所包庇黑恶势力并受到上级政法委保护的多篇文章\n处罚：有期徒刑1年\n备注：二审维持原判\n法律文书：（2019）浙02刑终826号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:14.67838+12
1138	1156	【中国文字狱事件记录】\n日期：2019年12月08日\n地点：山西保德县\n当事人：韩某锋\n平台：QQ群\n言论内容：“不当政治言论”\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:14.721218+12
1139	1157	【中国文字狱事件记录】\n日期：2019年12月08日\n地点：湖北麻城\n当事人：李某\n平台：贴吧\n言论内容：麻城警方真尼玛XX\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:14.76086+12
1140	1158	【中国文字狱事件记录】\n日期：2019年12月09日\n地点：甘肃宕昌县\n当事人：包某\n平台：微信群\n言论内容：“辱骂村干部”\n处罚：治安罚款	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:14.801073+12
1141	1159	【中国文字狱事件记录】\n日期：2019年12月09日\n地点：北京\n当事人：侯某\n平台：推特\n言论内容：“辱骂国家领导人以及中国共产党”\n处罚：起诉（寻衅滋事罪）\n法律文书：京朝检公诉刑诉〔2019〕3285号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:14.845951+12
1142	1160	【中国文字狱事件记录】\n日期：2019年12月10日\n地点：湖南平江县\n当事人：袁某\n平台：微信群\n言论内容：“辱警言论”\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:14.89237+12
1143	1161	【中国文字狱事件记录】\n日期：2019年12月12日\n地点：甘肃陇南\n当事人：张某\n平台：微信群\n言论内容：“辱骂乡镇干部、村委会干部”\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:14.939682+12
1144	1162	【中国文字狱事件记录】\n日期：2019年12月12日\n地点：广东汕头\n当事人：胡某雄\n平台：微信群\n言论内容：一段房屋倒塌视频（事后官方称是正常拆除）：不知道有多少人死亡\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:14.986463+12
1145	1163	【中国文字狱事件记录】\n日期：2019年12月12日\n地点：河北康保县\n当事人：闫某\n平台：微信群\n言论内容：“辱骂村干部”\n处罚：拘留12日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:15.033481+12
1146	1164	【中国文字狱事件记录】\n日期：2019年12月12日\n地点：吉林松原\n当事人：张某\n平台：朋友圈\n言论内容：XX（指交警）又出来咬人了，伯都纳这里，大家注意\n处罚：拘留13日、罚款700元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:15.08057+12
1147	1165	【中国文字狱事件记录】\n日期：2019年12月13日\n地点：河北易县\n当事人：马某\n平台：朋友圈\n言论内容：我欠弄死他们\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:15.127253+12
1148	1166	【中国文字狱事件记录】\n日期：2019年12月13日\n地点：贵州镇远县\n当事人：徐某\n平台：朋友圈\n言论内容：五里牌这里查车嘞，个个莫来嘞，这三咚（个）XX，我XXX......\n处罚：拘留12日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:15.173999+12
1149	1167	【中国文字狱事件记录】\n日期：2019年12月13日\n地点：福建石狮\n当事人：吴某\n平台：某APP\n言论内容：一段派出所门口视频以及侮辱性语音\n处罚：拘留6日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:15.224439+12
1150	1168	【中国文字狱事件记录】\n日期：2019年12月14日\n地点：河南潢川县\n当事人：王某\n平台：潢川在线\n言论内容：潢川交警、城管都不是人XX，都是XXXX\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:15.271721+12
1151	1169	【中国文字狱事件记录】\n日期：2019年12月15日\n地点：河南郑州\n当事人：郑某雷\n平台：朋友圈\n言论内容：二队的交警，我XXXX咋还贴条了？咋不XXXX\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:15.319758+12
1152	1170	【中国文字狱事件记录】\n日期：2019年12月16日\n地点：湖南平江县\n当事人：唐某生\n平台：微信群\n言论内容：对执法民警进行侮辱的言论\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:15.366822+12
1153	1171	【中国文字狱事件记录】\n日期：2019年12月16日\n地点：甘肃宕昌县\n当事人：杨某\n平台：微信群\n言论内容：“辱骂村干部”\n处罚：拘留7日、罚款	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:15.413113+12
1154	1172	【中国文字狱事件记录】\n日期：2019年12月17日\n地点：湖北武汉\n当事人：王强\n平台：推特\n言论内容：大量反动言论\n处罚：有期徒刑1年3个月	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:15.458655+12
1155	1173	【中国文字狱事件记录】\n日期：2019年12月17日\n地点：云南富宁县\n当事人：王某\n平台：朋友圈\n言论内容：倒霉，土匪\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:15.50096+12
1156	1174	【中国文字狱事件记录】\n日期：2019年12月17日\n地点：广东东莞\n当事人：屈某\n平台：微信群\n言论内容：“诋毁中国共产党、辱骂国家领导人不良言论”\n处罚：刑事拘留\n备注：2020/3/25不予起诉	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:15.545602+12
1157	1175	【中国文字狱事件记录】\n日期：2019年12月18日\n地点：上海\n当事人：宫敏赓（宫正兄）\n平台：微信群\n言论内容：独裁政府不能保护公民财产，所以香港人誓死捍卫自由与民主，所以全世界人民在灭共\n背景事件：香港反送中示威\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:15.59094+12
1158	1176	【中国文字狱事件记录】\n日期：2019年12月18日\n地点：广东肇庆\n当事人：刘飞龙\n平台：推特\n言论内容：“丑化执政党、国家、政府及领导人的虚假信息共计8000条”\n处罚：有期徒刑1年、缓刑1年6个月\n法律文书：（2019）粤1202刑初414号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:15.634261+12
1159	1177	【中国文字狱事件记录】\n日期：2019年12月19日\n地点：青海西宁\n当事人：吴雨森\n平台：推特\n言论内容：攻击国家领导人，散布“涉政谣言”\n处罚：有期徒刑10个月\n法律文书：（2019）青0105刑初372号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:15.680097+12
1160	1178	【中国文字狱事件记录】\n日期：2019年12月19日\n地点：甘肃宕昌县\n当事人：冯某\n平台：微信群\n言论内容：“辱骂派出所驻村工作组干部“\n处罚：拘留6日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:15.728651+12
1161	1179	【中国文字狱事件记录】\n日期：2019年12月19日\n地点：河南伊川县\n当事人：李某晶\n平台：朋友圈\n言论内容：交警真狗，就停了5分钟不到\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:15.776896+12
1162	1180	【中国文字狱事件记录】\n日期：2019年12月20日\n地点：内蒙古赤峰\n当事人：马某\n平台：朋友圈\n言论内容：交通罚单照片及“辱骂”文字\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:15.817112+12
1163	1181	【中国文字狱事件记录】\n日期：2019年12月20日\n地点：浙江缙云县\n当事人：施某\n平台：网络\n言论内容：关于“缙云县第三污水厂项目的不实信息”\n处罚：拘留9日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:15.857006+12
1164	1182	【中国文字狱事件记录】\n日期：2019年12月21日\n地点：吉林通化\n当事人：沈某\n平台：微信群\n言论内容：沈阳的一个大客车，整个楞的一车人没了\n处罚：行政处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:15.896212+12
1165	1183	【中国文字狱事件记录】\n日期：2019年12月23日\n地点：湖北武汉\n当事人：张泽曦\n平台：网络\n言论内容：“辱骂他人（疑似国家领导人）的推文200条“\n处罚：有期徒刑10个月\n法律文书：（2019）鄂0192刑初824号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:15.937763+12
1166	1184	【中国文字狱事件记录】\n日期：2019年12月24日\n地点：青海西宁\n当事人：马华英\n平台：境外网站\n言论内容：“党和国家领导人、民族、宗教政策、国内法律法规的负面新闻”\n处罚：有期徒刑10个月\n法律文书：（2019）青0105刑初391号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:15.983681+12
1167	1185	【中国文字狱事件记录】\n日期：2019年12月24日\n地点：辽宁鞍山\n当事人：高振强\n平台：推特\n言论内容：17051条推文，其中80%以上攻击了党和国家领导人\n处罚：有期徒刑6个月\n法律文书： （2019）辽0304刑初323号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:16.031488+12
1168	1186	【中国文字狱事件记录】\n日期：2019年12月24日\n地点：辽宁大连\n当事人：王承刚\n平台：推特\n言论内容：污蔑、辱骂前国家领导人、现国家领导人、中国共产党等言论或文章\n处罚：有期徒刑1年6个月\n备注：二审维持原判\n法律文书：（2019）辽02刑终681号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:16.079114+12
1169	1187	【中国文字狱事件记录】\n日期：2019年12月24日\n地点：湖南宁远县\n当事人：李艳军\n平台：脸书\n言论内容：抹黑我国政府、诽谤国家领导人，诽谤外国人影响国际关系；创建“中国大陆支援香港反送中阵线”\n背景事件：香港反送中示威\n处罚：有期徒刑6个月\n法律文书：（2019）湘1126刑初435号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:16.126711+12
1170	1188	【中国文字狱事件记录】\n日期：2019年12月25日\n地点：浙江龙游县\n当事人：黄军\n平台：微信群\n言论内容：死了三个好，省得留着祸害老百姓；安全带他们自己都不扣；不要再纠结那几个死翘翘的人了\n背景事件：当地三名交警车祸身亡\n处罚：有期徒刑6个月\n法律文书：（2019）浙0825刑初300号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:16.174421+12
1171	1189	【中国文字狱事件记录】\n日期：2019年12月25日\n地点：浙江台州\n当事人：蔡某\n平台：论坛网站\n言论内容：街头交警跟中生样\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:16.218084+12
1172	1190	【中国文字狱事件记录】\n日期：2019年12月26日\n地点：山东龙门市\n当事人：姜国臣\n平台：微信、现实\n言论内容：进京上访；“赵作媛上访被法院、公安机关绑架、非法拘禁并可能迫害致死”\n处罚：有期徒刑1年4个月\n备注：二审维持原判\n法律文书：（2020）鲁06刑终92号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:16.262636+12
1173	1191	【中国文字狱事件记录】\n日期：2019年12月26日\n地点：贵州毕节\n当事人：尤泽燚\n平台：微博\n言论内容：赵明伟编造的自己性侵多名儿童的聊天记录\n处罚：有期徒刑4年6个月\n法律文书：（2019）黔0502刑初592号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:16.31086+12
1174	1192	【中国文字狱事件记录】\n日期：2019年12月26日\n地点：河南新密市\n当事人：高锦标\n平台：推特\n言论内容：大量反对党和国家以及政府的言论、图片和视频\n处罚：有期徒刑2年\n备注：二审维持原判\n法律文书：（2020）豫01刑终91号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:16.359275+12
1175	1193	【中国文字狱事件记录】\n日期：2019年12月26日\n地点：湖南长沙\n当事人：杨天桥\n平台：朋友圈\n言论内容：因为我痛恨专制，所以我反感毛**，发动文革的人，当然是中华民族的罪人\n处罚：拘留12日\n法律文书：岳公（咸）决字[2019]第2811号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:16.408168+12
1176	1194	【中国文字狱事件记录】\n日期：2019年12月27日\n地点：山东莒县\n当事人：张兴修\n平台：微博、博客\n言论内容：《山东省日照市莒县城阳党委书记吴某1违纪密谋策划侵吞村民房屋赔偿款曝光》等指控当地政府腐败的帖文\n处罚：有期徒刑2年\n法律文书：（2019）鲁1122刑初428号；（2020）鲁11刑终62号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:16.45479+12
1177	1195	【中国文字狱事件记录】\n日期：2019年12月27日\n地点：河南潢川县\n当事人：徐某\n平台：朋友圈\n言论内容：“不当言论”\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:16.501375+12
1178	1197	【中国文字狱事件记录】\n日期：2019年12月30日\n地点：辽宁抚顺\n当事人：唐国刚\n平台：推特\n言论内容：诽谤国家领导人和国家制度\n处罚：有期徒刑1年6个月\n法律文书：（2019）辽0402刑初87号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:16.593322+12
1179	1198	【中国文字狱事件记录】\n日期：2019年12月30日\n地点：河南开封\n当事人：金某军\n平台：朋友圈\n言论内容：市民之家附近哪个XX贴的，我XXX\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:16.639403+12
1180	1199	【中国文字狱事件记录】\n日期：2019年12月30日\n地点：四川乐山\n当事人：邹某\n平台：朋友圈\n言论内容：这交警xx嘻嘻的，这撒子破地方还贴罚单，哪里妨碍交通了，xx还贴罚单\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:16.685728+12
1181	1200	【中国文字狱事件记录】\n日期：2019年12月31日\n地点：浙江湖州\n当事人：卫小兵\n平台：微信群\n言论内容：在“声援1226大抓捕朋友们”微信群发表的“不当言论”\n处罚：拘留15日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:16.732405+12
1182	1201	【中国文字狱事件记录】\n日期：2020年01月02日\n地点：福建莆田\n当事人：朱洪林\n平台：多个平台\n言论内容：《在莆田：他举报了“黑恶势力”家里送来了“花圈”》等指控官员包庇黑恶势力的文章\n处罚：有期徒刑9个月15天\n法律文书：（2019）闽0305刑初395号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:16.781668+12
1183	1202	【中国文字狱事件记录】\n日期：2020年01月03日\n地点：武汉中心医院\n当事人：李文亮\n平台：微信群\n言论内容：华南水果海鲜市场确诊了7例SARS，在我们医院急诊科隔离；是冠状病毒，具体还在分型\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫\n备注：随后其本人也被感染，2月6日去世	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:16.828692+12
1184	1203	【中国文字狱事件记录】\n日期：2020年01月03日\n地点：贵州遵义\n当事人：王某\n平台：朋友圈\n言论内容：这些狗，那么多车不贴，就贴我，操；快过年啦，这些狗要找过年盘子啦\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:16.877191+12
1185	1204	【中国文字狱事件记录】\n日期：2020年01月06日\n地点：山东济南\n当事人：彭博\n平台：网络、现实\n言论内容：举报某厅级干部生活淫乱；发表《实名举报山东厅级干部生活淫乱，银行资产损失近30亿元》等文章\n处罚：有期徒刑4年\n备注：二审维持原判\n法律文书：（2020）鲁01刑终80号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:16.92644+12
1186	1205	【中国文字狱事件记录】\n日期：2020年01月06日\n地点：广东中山\n当事人：陈某\n平台：微信\n言论内容：“有损社会主义制度及国家领导人的不实言论及图片”\n处罚：起诉（寻衅滋事罪）\n法律文书：中检二区二部刑诉〔2020〕10号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:16.976296+12
1187	1297	【中国文字狱事件记录】\n日期：2020年01月24日\n地点：江苏沭阳县\n当事人：徐某\n平台：微博\n言论内容：宿迁沭阳确诊1例，领导们开会XX下来\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留2日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:21.044119+12
1188	1206	【中国文字狱事件记录】\n日期：2020年01月09日\n地点：广西河池\n当事人：韦尉剑\n平台：微信群\n言论内容：侮辱中国共产党、支持香港暴乱、我有汗奸证的等\n背景事件：香港反送中示威\n处罚：有期徒刑10个月\n法律文书：（2019）桂1281刑初321号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:17.02561+12
1189	1207	【中国文字狱事件记录】\n日期：2020年01月09日\n地点：安徽亳州\n当事人：不详\n平台：朋友圈\n言论内容：奶奶的腿，接个小孩停十分钟一百\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:17.072273+12
1190	1208	【中国文字狱事件记录】\n日期：2020年01月10日\n地点：广西西林县\n当事人：黄某\n平台：微信群\n言论内容：悬赏通缉令和一段有人在尸体前哭喊视频（二者均属实但无关联，黄称有关联）\n处罚：罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:17.118793+12
1191	1209	【中国文字狱事件记录】\n日期：2020年01月11日\n地点：黑龙江伊春\n当事人：李树森\n平台：微信群\n言论内容：“侮辱党和国家领导人”的言论\n处罚：拘留5日\n法律文书：伊公（治）行罚决字﹝2020﹞16号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:17.164859+12
1192	1210	【中国文字狱事件记录】\n日期：2020年01月13日\n地点：河北涞源县\n当事人：蔺某某\n平台：微信群\n言论内容：（语音）侮辱殉职交警的信息\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:17.212211+12
1193	1211	【中国文字狱事件记录】\n日期：2020年01月13日\n地点：河北涞源县\n当事人：刘某某\n平台：微信群\n言论内容：该撞死！在冯村那我见了！查酒驾！是警察自己要找死的！\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:17.257843+12
1194	1212	【中国文字狱事件记录】\n日期：2020年01月16日\n地点：安徽淮南\n当事人：张冬宁\n身份：境外人士\n平台：网络\n言论内容：猪头人身系列漫画\n处罚：有期徒刑1年	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:17.304528+12
1195	1213	【中国文字狱事件记录】\n日期：2020年01月17日\n地点：广东广州\n当事人：杨家豪\n平台：微信群\n言论内容：文章《致习锦平》，“公然损害国家形象，诽谤国家领导人”\n处罚：有期徒刑1年3个月\n法律文书：穗天检刑诉〔2019〕955号；（2019）粤0106刑初960号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:17.37563+12
1196	1214	【中国文字狱事件记录】\n日期：2020年01月17日\n地点：广西柳州\n当事人：覃某\n平台：微信群\n言论内容：（视频）就是这条老狗叼，去年在荣军路口差点跟他差点打起来，这种废狗注定到这个年纪还蹲马路边岗亭\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:17.421756+12
1197	1215	【中国文字狱事件记录】\n日期：2020年01月20日\n地点：辽宁瓦房店\n当事人：高树峰\n平台：微信群\n言论内容：“诽谤中国社会主义制度和诽谤党和国家领导人的图片”\n处罚：有期徒刑6个月\n法律文书：（2020）辽0281刑初21号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:17.463008+12
1289	1306	【中国文字狱事件记录】\n日期：2020年01月24日\n地点：浙江永康\n当事人：曹某\n平台：朋友圈\n言论内容：在医院过年（新型冠状病毒肺炎确诊PS图）\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:21.46121+12
1198	1216	【中国文字狱事件记录】\n日期：2020年01月20日\n地点：河南商水县\n当事人：曹帅\n平台：推特\n言论内容：于2013年10月转发一些辱骂攻击他人或不实信息\n处罚：有期徒刑6个月\n法律文书：（2020）豫1623刑初23号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:17.500331+12
1199	1217	【中国文字狱事件记录】\n日期：2020年01月20日\n地点：广东广州\n当事人：杨旭彬\n平台：现实\n言论内容：（街头喷涂）民主、独立、普选、光复广州，时代革命；广东独立等\n处罚：有期徒刑9个月\n法律文书：（2020）粤0105刑初23号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:17.536635+12
1200	1218	【中国文字狱事件记录】\n日期：2020年01月20日\n地点：广东佛山\n当事人：邓锡强\n平台：Instagram、现实\n言论内容：在Instagram发布反动内容及小熊维尼漫画‘创作反动漫画赠与他人\n处罚：有期徒刑2年、缓刑3年\n法律文书：（2020）粤0604刑初72号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:17.57409+12
1201	1219	【中国文字狱事件记录】\n日期：2020年01月21日\n地点：内蒙古突泉县\n当事人：王某\n平台：多个平台\n言论内容：《内蒙古自治区主席布小林失职证据》《内蒙古自治区主席布小林失职》等文章\n处罚：有期徒刑1年6个月\n法律文书：（2019）内2224刑初261号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:17.613417+12
1202	1220	【中国文字狱事件记录】\n日期：2020年01月21日\n地点：内蒙古突泉县\n当事人：于某\n平台：多个平台\n言论内容：（为他人代发）多篇维权文章，控诉政府\n处罚：有期徒刑1年6个月\n法律文书：（2019）内2224刑初261号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:17.653823+12
1203	1221	【中国文字狱事件记录】\n日期：2020年01月21日\n地点：河南商丘\n当事人：陈某\n平台：微信群\n言论内容：商丘已经死亡121人，封城了，白菜52元一颗，大家快抢啊\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:17.695919+12
1204	1222	【中国文字狱事件记录】\n日期：2020年01月21日\n地点：河北唐山\n当事人：邢某伟\n平台：微博\n言论内容：唐山市丰南区三人感染冠状病毒死亡\n背景事件：武汉新型冠状病毒肺炎\n处罚：“依法控制”	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:17.739335+12
1205	1223	【中国文字狱事件记录】\n日期：2020年01月21日\n地点：新疆乌鲁木齐\n当事人：“泡沫初～夏”\n平台：网络\n言论内容：新型冠状病毒，没事别往武汉跑，非典来了，把你自己都照顾好。已经死人了。基本在，武汉，上海，深圳，但是新疆已经死了一个人了。\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:17.784382+12
1206	1224	【中国文字狱事件记录】\n日期：2020年01月21日\n地点：新疆乌鲁木齐\n当事人：“灿”\n平台：网络\n言论内容：乌鲁木齐已经出现肺炎死亡病例，大家最近不要到公众场合去了\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:17.826346+12
1207	1225	【中国文字狱事件记录】\n日期：2020年01月21日\n地点：广东佛山\n当事人：黄某\n平台：现实/张贴传单\n言论内容：用谐音方式“辱骂国家领导人”\n处罚：批捕	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:17.86703+12
1208	1226	【中国文字狱事件记录】\n日期：2020年01月22日\n地点：四川安岳县\n当事人：肖某\n平台：QQ\n言论内容：最近新型病毒有点凶，咱川渝两地都发现了病例，最近出去各位做好防护措施哈；县城已经死了一个了；卫生院隐瞒了消息，还没有报上去\n背景事件：武汉新型冠状病毒肺炎\n处罚：“依法处理”\n备注：言论内容部分属实	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:17.910488+12
1209	1227	【中国文字狱事件记录】\n日期：2020年01月22日\n地点：山东青岛\n当事人：杨某杰\n平台：不详\n言论内容：青岛出现首例武肺患者的报道及一些“添油加醋（患者具体地点）”细节\n背景事件：武汉新型冠状病毒肺炎\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:17.95386+12
1210	1228	【中国文字狱事件记录】\n日期：2020年01月22日\n地点：河北秦皇岛\n当事人：白某晨\n平台：微信群\n言论内容：秦皇岛中医院发现两名冠状病毒发病患者\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:17.996496+12
1211	1982	【中国文字狱事件记录】\n日期：2020年05月29日\n地点：四川开江县\n当事人：朱某\n平台：抖音\n言论内容：“诋毁综合执法人员的视频”\n处罚：行政处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:55.69168+12
1212	1229	【中国文字狱事件记录】\n日期：2020年01月22日\n地点：江西永丰县\n当事人：王某\n平台：微信群\n言论内容：县医院确诊新型冠状病毒一例，疑似一例，现在感染科隔离，请大家注意防护！！！（两人都是从武汉回来的）\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:18.039339+12
1213	1230	【中国文字狱事件记录】\n日期：2020年01月22日\n地点：湖南慈利县\n当事人：向某\n平台：微信群\n言论内容：慈利已出现一例新型冠状病毒感染者\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:18.083799+12
1214	1231	【中国文字狱事件记录】\n日期：2020年01月22日\n地点：四川广安\n当事人：补某\n平台：微博\n言论内容：湖北新型肺炎累计444例死亡，我在四川广安，我这边也已经发现了，目前已经死亡三人\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:18.129183+12
1215	1232	【中国文字狱事件记录】\n日期：2020年01月22日\n地点：山东平邑县\n当事人：王勇\n平台：推特\n言论内容：”诽谤国家领导人和煽动台独的言论“\n处罚：有期徒刑10个月\n法律文书：(2019)鲁1326刑初854号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:18.173825+12
1216	1233	【中国文字狱事件记录】\n日期：2020年01月22日\n地点：河北香河县\n当事人：田某\n平台：朋友圈\n言论内容：新型冠状病毒已进入香河，并且有2例确诊\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:18.218197+12
1217	1234	【中国文字狱事件记录】\n日期：2020年01月22日\n地点：江西永丰县\n当事人：黄某\n平台：朋友圈\n言论内容：听说永丰县医院发现两例肺炎冠状病毒案例；本人不对消息负责\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:18.262006+12
1218	1235	【中国文字狱事件记录】\n日期：2020年01月22日\n地点：河南长垣县\n当事人：不详\n平台：网络\n言论内容：咱县有一例疑似肺炎的，差不多确诊了\n背景事件：武汉新型冠状病毒肺炎\n处罚：“依法处理”	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:18.303762+12
1219	1236	【中国文字狱事件记录】\n日期：2020年01月22日\n地点：河南长垣县\n当事人：不详\n平台：网络\n言论内容：（转发）咱县有一例疑似肺炎的，差不多确诊了\n背景事件：武汉新型冠状病毒肺炎\n处罚：“依法处理”	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:18.348815+12
1846	1864	【中国文字狱事件记录】\n日期：2020年03月06日\n地点：辽宁丹东\n当事人：孙某\n平台：不详\n言论内容：“疫情谣言”\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:49.841035+12
1220	1237	【中国文字狱事件记录】\n日期：2020年01月23日\n地点：湖南长沙\n当事人：周某\n平台：微信群\n言论内容：长沙县3614小区有4人被确诊新型冠状病毒肺炎\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留\n备注：次日谣言被证实	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:18.392411+12
1221	1238	【中国文字狱事件记录】\n日期：2020年01月23日\n地点：河北定兴县\n当事人：陈某\n平台：微信群\n言论内容：定兴已发现一例，北店的。都注意点吧；也是从武汉回来的、应该在县医院吧，已经隔离”等\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:18.440507+12
1222	1239	【中国文字狱事件记录】\n日期：2020年01月23日\n地点：河北高阳县\n当事人：胡某\n平台：微信群\n言论内容：（视频）西演镇卫生院发现疑似新型冠状病毒肺炎病例\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:18.484724+12
1223	1240	【中国文字狱事件记录】\n日期：2020年01月23日\n地点：河南汝阳县\n当事人：陈某\n平台：微信群\n言论内容：陶营有人感染新型冠状病毒肺炎，已被隔离\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日、罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:18.528487+12
1224	1241	【中国文字狱事件记录】\n日期：2020年01月23日\n地点：重庆\n当事人：刘某\n平台：微信群\n言论内容：江北盘溪、石马河地区已被警方封锁\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:18.571978+12
1225	1242	【中国文字狱事件记录】\n日期：2020年01月23日\n地点：广东郁南县\n当事人：刘某\n平台：微信群\n言论内容：提个醒：广东郁南桂圩已经确诊一例新型肺炎病例，大家外出的时候，要注意做好防范措施\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:18.617411+12
1226	1243	【中国文字狱事件记录】\n日期：2020年01月23日\n地点：湖南岳阳县\n当事人：方某\n平台：微信群\n言论内容：涉及冠状病毒感染肺炎虚假疫情信息\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:18.662761+12
1227	1244	【中国文字狱事件记录】\n日期：2020年01月23日\n地点：广东陆丰\n当事人：蔡某莉\n平台：微信群\n言论内容：甲子有5个中招隔离\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:18.707676+12
1228	1245	【中国文字狱事件记录】\n日期：2020年01月23日\n地点：江苏丹阳市\n当事人：汤某强\n平台：微信群\n言论内容：新型肺炎是武汉病毒研究所研究人员被传染带出来的；非典是北京病毒研究所造成的，不要被专家忽悠\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:18.752103+12
1229	1246	【中国文字狱事件记录】\n日期：2020年01月23日\n地点：海南文昌\n当事人：符某源\n平台：微信群\n言论内容：海甸岛三西路有病毒；那个市政花园死人了；现在封起来消毒\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:18.796451+12
1230	1247	【中国文字狱事件记录】\n日期：2020年01月23日\n地点：山西晋城\n当事人：张某鹏\n平台：微信群\n言论内容：武汉归来后一直发烧不退，且拒不到医院接受治疗\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:18.842092+12
1231	1248	【中国文字狱事件记录】\n日期：2020年01月23日\n地点：新疆新和县\n当事人：穆某\n平台：微信群\n言论内容：昨天凌晨2点13分，X男X女感染新型传染性肺炎病毒死亡，最大的35岁，最小的1岁\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:18.887135+12
1232	1249	【中国文字狱事件记录】\n日期：2020年01月23日\n地点：新疆昌吉\n当事人：柳某\n平台：微信群\n言论内容：听说昌吉已经有不少感染了，昌吉最少X例，是真的；上面不让传，害怕恐慌\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:18.930112+12
1233	1250	【中国文字狱事件记录】\n日期：2020年01月23日\n地点：上海\n当事人：徐某\n平台：微信群\n言论内容：上海死亡人数超过32了，内部数据，心大者无视；上海死亡40 确认120 疑似60\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:18.972477+12
1234	1251	【中国文字狱事件记录】\n日期：2020年01月23日\n地点：江西安义县\n当事人：余某芬\n平台：微信群\n言论内容：马上封城安义\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:19.013797+12
1235	1252	【中国文字狱事件记录】\n日期：2020年01月23日\n地点：四川成都\n当事人：杨某\n平台：微信群\n言论内容：成都明天不会封城，但疾控中心会有一个大消息，现在疫情情况严重，让大家立即去超市囤食物，千万不要出门\n背景事件：武汉新型冠状病毒肺炎\n处罚：从轻处理\n备注：次日四川启动一级响应	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:19.056602+12
1236	1253	【中国文字狱事件记录】\n日期：2020年01月23日\n地点：广东龙川县\n当事人：周某平\n平台：微信群\n言论内容：一张涉及疫情的图片\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:19.105464+12
1237	1254	【中国文字狱事件记录】\n日期：2020年01月23日\n地点：辽宁鞍山\n当事人：田某\n平台：微信群\n言论内容：鞍山现有40多疑似新型冠状病毒病例\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:19.159333+12
1238	1255	【中国文字狱事件记录】\n日期：2020年01月23日\n地点：新疆轮台县\n当事人：王某\n平台：微信群\n言论内容：轮台县确诊2名新型冠装病毒肺炎患者\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:19.209226+12
1239	1256	【中国文字狱事件记录】\n日期：2020年01月23日\n地点：甘肃兰州\n当事人：李某\n平台：微博\n言论内容：歪曲官方关于新型冠状病毒肺炎感染人数的新闻报道；嘲讽被感染人员、侮辱政府\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留15日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:19.255452+12
1240	1257	【中国文字狱事件记录】\n日期：2020年01月23日\n地点：甘肃东乡县\n当事人：马某\n平台：快手\n言论内容：肺炎已经来兰州了，这个病看不好，治不好，就会一针打死，赶紧能吃就吃\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:19.303324+12
1241	1258	【中国文字狱事件记录】\n日期：2020年01月23日\n地点：重庆\n当事人：王某\n平台：朋友圈\n言论内容：重庆沙坪坝、江北区、渝北区开始管制\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:19.347523+12
1242	1259	【中国文字狱事件记录】\n日期：2020年01月23日\n地点：河北任丘市\n当事人：孙某\n平台：朋友圈\n言论内容：任丘什么时候封城就好了，最好全部染上病毒，这样我们任丘就出名了，上新闻了\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:19.393249+12
1244	1261	【中国文字狱事件记录】\n日期：2020年01月23日\n地点：新疆尉犁县\n当事人：李某\n平台：网络\n言论内容：尉犁县已确诊一名新型冠状病毒肺炎刚拉到县医院，你们出入都把口罩带好\n背景事件：武汉新型冠状病毒肺炎\n处罚：“依法处理”	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:19.481843+12
1245	1262	【中国文字狱事件记录】\n日期：2020年01月23日\n地点：新疆乌鲁木齐\n当事人：“十字军 统帥”\n平台：网络\n言论内容：乌鲁木齐已经死亡2例了\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:19.523373+12
1246	1263	【中国文字狱事件记录】\n日期：2020年01月23日\n地点：新疆乌鲁木齐\n当事人：“荣儿”\n平台：网络\n言论内容：在乌鲁木齐已经出现了两历病患70多人已经被隔离，忘姐妹们出门记得戴口罩。\n背景事件：武汉新型冠状病毒肺炎\n处罚：侦办中	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:19.572354+12
1247	1264	【中国文字狱事件记录】\n日期：2020年01月23日\n地点：新疆乌鲁木齐\n当事人：不详\n平台：网络\n言论内容：新疆死亡人数两例，都注意了\n背景事件：武汉新型冠状病毒肺炎\n处罚：罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:19.619944+12
1248	1265	【中国文字狱事件记录】\n日期：2020年01月23日\n地点：广东澄海\n当事人：不详（4人）\n平台：网络\n言论内容：发布转发新型冠状病毒感染肺炎疫情，甚至传播我区，有关人员受感染\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:19.663844+12
1249	1266	【中国文字狱事件记录】\n日期：2020年01月23日\n地点：江苏如东县\n当事人：季某东\n平台：微信群\n言论内容：如东明天要戒严，岔河发现四例”、“县政府晚上召开紧急会议，明天交警上路\n背景事件：武汉新型冠状病毒肺炎\n处罚：罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:19.710944+12
1250	1267	【中国文字狱事件记录】\n日期：2020年01月24日\n地点：甘肃庆阳\n当事人：鲜某\n平台：微信\n言论内容：现1例新型冠状病毒肺炎疑似的，后官寨村从武汉回来的，也疑似新型冠状病毒肺炎\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:19.754709+12
1251	1268	【中国文字狱事件记录】\n日期：2020年01月24日\n地点：河南新野县\n当事人：赵某\n平台：微信群\n言论内容：2000元拼车可以不走高速、不过关卡、不测体温、小路离汉\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:19.796886+12
1252	1269	【中国文字狱事件记录】\n日期：2020年01月24日\n地点：浙江玉环\n当事人：张某志\n平台：微信群\n言论内容：（转发）浙XX这个车子刚从武汉回来，车上的人确诊了偷跑回来的\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:19.839637+12
1253	1270	【中国文字狱事件记录】\n日期：2020年01月24日\n地点：湖南浏阳县\n当事人：李某\n平台：微信群\n言论内容：大瑶镇汇丰社区确认发现两例新型冠状病毒感染者，已被送往长沙隔离\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:19.883904+12
1254	1271	【中国文字狱事件记录】\n日期：2020年01月24日\n地点：河北献县\n当事人：郭某\n平台：微信群\n言论内容：关于我县新型肺炎的不实消息\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:19.926311+12
1255	1272	【中国文字狱事件记录】\n日期：2020年01月24日\n地点：河北献县\n当事人：李某云\n平台：微信群\n言论内容：关于我县新型肺炎的不实消息\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:19.970281+12
1256	1273	【中国文字狱事件记录】\n日期：2020年01月24日\n地点：河北平泉\n当事人：李某\n平台：微信群\n言论内容：平泉已经出现了六个感染者，二医院是隔离区\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:20.014429+12
1257	1274	【中国文字狱事件记录】\n日期：2020年01月24日\n地点：江西南城县\n当事人：吴某\n平台：微信群\n言论内容：明天大家没事别出门了，今天上唐有人感染了送人民医院了\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:20.057473+12
1258	1321	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：四川泸州\n当事人：唐某\n平台：微信群\n言论内容：纳溪一例疑似患者已经确认，但逃跑了\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:22.156833+12
1259	1275	【中国文字狱事件记录】\n日期：2020年01月24日\n地点：宁夏中卫\n当事人：廖某\n平台：微信群\n言论内容：（转发）车牌号浙B L0535 这个车刚从武汉回来，车上的人确诊了冠状肺炎偷跑回来的，大家看到了及时报警\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:20.103616+12
1260	1276	【中国文字狱事件记录】\n日期：2020年01月24日\n地点：广东电白\n当事人：卓某\n平台：微信群\n言论内容：水东已经有人确诊感染肺炎，大家出门一定要戴上口罩，在武汉回来的，现自己隔离\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:20.148302+12
1261	1277	【中国文字狱事件记录】\n日期：2020年01月24日\n地点：新疆和静县\n当事人：夏某\n平台：微信群\n言论内容：和静已经有两个感染病毒，一个孩子从武汉上大学回来，然后把她妈妈也传染了，两人现在隔离起来了\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:20.191412+12
1262	1278	【中国文字狱事件记录】\n日期：2020年01月24日\n地点：河南信阳\n当事人：张某\n平台：微信群\n言论内容：1月25日下午2点信阳将因新型冠状病毒感染的肺炎疫情封城\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:20.234657+12
1263	1279	【中国文字狱事件记录】\n日期：2020年01月24日\n地点：河南洛阳\n当事人：王某\n平台：微信群\n言论内容：认识洛阳市疾控中心主任，洛阳新型冠状病毒肺炎病例诊29人、武汉近10万人感染\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:20.278281+12
1264	1280	【中国文字狱事件记录】\n日期：2020年01月24日\n地点：河南伊川县\n当事人：张某\n平台：微信群\n言论内容：伊川有422名武汉返乡人员，有8人确诊，其中4人到过某超市\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:20.321446+12
1265	1281	【中国文字狱事件记录】\n日期：2020年01月24日\n地点：江西安义县\n当事人：余某\n平台：微信群\n言论内容：浙BL0535看到就跑，跑回安义了\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:20.364506+12
1266	1282	【中国文字狱事件记录】\n日期：2020年01月24日\n地点：山西岚县\n当事人：刘某\n平台：微信群\n言论内容：山西沦陷了，太原今天还偷跑了一个\n背景事件：武汉新型冠状病毒肺炎\n处罚：罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:20.407907+12
1267	1283	【中国文字狱事件记录】\n日期：2020年01月24日\n地点：山西文水县\n当事人：李某\n平台：微信群\n言论内容：文水县共排查出从武汉返回文水县的学生和打工人员计120人，发现5人出现高烧、疑似病例，已隔离治疗\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:20.452806+12
1268	1284	【中国文字狱事件记录】\n日期：2020年01月24日\n地点：天津\n当事人：高某\n平台：微信群\n言论内容：故意夸大全和本市感染新型冠状病毒肺炎人数\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:20.497556+12
1269	1285	【中国文字狱事件记录】\n日期：2020年01月24日\n地点：河北保定\n当事人：范某\n平台：微信群\n言论内容：昨天晚上去某村理发，这个村里说居然隔离了七个人\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:20.540556+12
1270	1286	【中国文字狱事件记录】\n日期：2020年01月24日\n地点：河北保定\n当事人：王某\n平台：微信群\n言论内容：你给我发红包不，发红包我就不去找你了.去了就从你们那打喷嚏\n背景事件：武汉新型冠状病毒肺炎\n处罚：罚款100元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:20.579876+12
1271	1287	【中国文字狱事件记录】\n日期：2020年01月24日\n地点：广东湛江\n当事人：许某莲\n平台：微信群\n言论内容：人家下来查，老杨村封村；不要出来坡头了；证实了，老杨村有人有症状；怀疑中，还没确准\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:20.617116+12
1272	1288	【中国文字狱事件记录】\n日期：2020年01月24日\n地点：广东湛江\n当事人：郑某明\n平台：微信群\n言论内容：武汉封城前飞湛江的那班飞机，所有人都在金马酒店住，政府包吃包住隔离观察。这些整副武装的人是送饭菜的\n背景事件：武汉新型冠状病毒肺炎\n处罚：侦办中	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:20.654952+12
1273	1289	【中国文字狱事件记录】\n日期：2020年01月24日\n地点：河北涞水县\n当事人：赵某\n平台：微信群\n言论内容：板城出现了一例疑似新型冠状病毒性肺炎，患者已经去县医院收治！大家提高警惕做好防护！\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:20.693921+12
1274	1290	【中国文字狱事件记录】\n日期：2020年01月24日\n地点：河北唐县\n当事人：周某\n平台：微信群\n言论内容：唐县三里庄村有一疑似感染病例，已被县医院隔离\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:20.737121+12
1275	1291	【中国文字狱事件记录】\n日期：2020年01月24日\n地点：河北玉田县\n当事人：不详\n平台：微信群\n言论内容：玉田有3人疑似肺炎患者转唐山医院去了，其中有两位是武汉大学生，现在中医院隔离一位患者呢，过年了，大家尽量别走亲访友，家庭聚餐\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:20.781359+12
1276	1292	【中国文字狱事件记录】\n日期：2020年01月24日\n地点：浙江温岭市\n当事人：郑某\n平台：微信群\n言论内容：大溪成为重灾区、我在公安局、从武汉回到大溪镇一千多人、现在公安局全部去抓了、隔离15日\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:20.825557+12
1277	1293	【中国文字狱事件记录】\n日期：2020年01月24日\n地点：河南温县\n当事人：王某\n平台：微博\n言论内容：我们河南省温县发现两名病人，一个确诊，一个正在观察，但是没有上报\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:20.869775+12
1278	1294	【中国文字狱事件记录】\n日期：2020年01月24日\n地点：河南温县\n当事人：董某\n平台：微博\n言论内容：病情远比想象中严重多了，温县已经死了一个人了，通报了吗？没有！\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:20.913903+12
1279	1295	【中国文字狱事件记录】\n日期：2020年01月24日\n地点：山东阳谷县\n当事人：张某\n平台：微博\n言论内容：现在竟然阳谷也出现了病例，据说已经死亡一例\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:20.956485+12
1280	1296	【中国文字狱事件记录】\n日期：2020年01月24日\n地点：山西沁水县\n当事人：张某\n平台：微博\n言论内容：嘉峰镇昨天有两个在武汉打工的人偷偷回来了，感冒咳嗽发烧，被人举报住进县医院\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:20.999644+12
1281	1298	【中国文字狱事件记录】\n日期：2020年01月24日\n地点：山东青岛\n当事人：王某\n平台：微博\n言论内容：王台镇已经没有口罩；青岛胶南一个村就有12人已经全部控制起来了，明天拜年全部戴口罩\n背景事件：武汉新型冠状病毒肺炎\n处罚：罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:21.08863+12
1282	1299	【中国文字狱事件记录】\n日期：2020年01月24日\n地点：河北保定\n当事人：陈某\n平台：微博\n言论内容：保定市徐水区翟庄村已经出现三粒（例）感染者，已经封村\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:21.133555+12
1283	1300	【中国文字狱事件记录】\n日期：2020年01月24日\n地点：广西平果县\n当事人：梁某\n平台：微博\n言论内容：安全逃离武汉灾区，安心在家过好年\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:21.179649+12
1284	1301	【中国文字狱事件记录】\n日期：2020年01月24日\n地点：安徽宿州\n当事人：刘某\n平台：微博\n言论内容：皖北煤电总医院21名医护人员因不明原因的病毒性肺炎已被隔离多日\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留6日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:21.226506+12
1285	1302	【中国文字狱事件记录】\n日期：2020年01月24日\n地点：新疆伊犁\n当事人：杨某\n平台：手机短信\n言论内容：广东有病人逃窜新疆，已造成X人死亡\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:21.275215+12
1286	1303	【中国文字狱事件记录】\n日期：2020年01月24日\n地点：新疆乌鲁木齐\n当事人：邵某\n平台：手机短信\n言论内容：有种新型冠状病毒肺炎会致人死亡，乌鲁木齐已经死了X个，武汉人都隔离观察\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:21.321485+12
1287	1304	【中国文字狱事件记录】\n日期：2020年01月24日\n地点：天津\n当事人：奚某\n平台：朋友圈\n言论内容：与新型冠状病毒肺炎有关的“不实信息”\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:21.368236+12
1288	1305	【中国文字狱事件记录】\n日期：2020年01月24日\n地点：浙江慈溪\n当事人：陈某\n平台：朋友圈\n言论内容：此人从武汉携带大量病毒回慈溪，望大家快速转发”文字的照片\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:21.41497+12
1290	1307	【中国文字狱事件记录】\n日期：2020年01月24日\n地点：天津\n当事人：赵某\n平台：朋友圈\n言论内容：与新型肺炎有关的“虚假信息”\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:21.50765+12
1291	1308	【中国文字狱事件记录】\n日期：2020年01月24日\n地点：河北固安县\n当事人：马某\n平台：朋友圈\n言论内容：今天瘟疫到柳泉大家提前做好防疫；北房上发现一个\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:21.553639+12
1292	1309	【中国文字狱事件记录】\n日期：2020年01月24日\n地点：黑龙江大庆\n当事人：刘某\n平台：朋友圈\n言论内容：重大通知！杜阳，大庆市大同区人。近日从武汉回来， 身上携带大量新型冠状病毒潜逃\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留7日、罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:21.600621+12
1293	1310	【中国文字狱事件记录】\n日期：2020年01月24日\n地点：甘肃环县\n当事人：任某\n平台：朋友圈\n言论内容：环县医院收进一位疑似患有新型冠状病毒感染肺炎患者\n背景事件：武汉新型冠状病毒肺炎\n处罚：罚款200元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:21.647191+12
1294	1311	【中国文字狱事件记录】\n日期：2020年01月24日\n地点：甘肃广河县\n当事人：马某\n平台：朋友圈\n言论内容：最新消息，三甲集医院发现一例新型冠状病毒性肺炎病例，三甲集药店所有的一次性口罩限购等\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:21.693545+12
1295	1312	【中国文字狱事件记录】\n日期：2020年01月24日\n地点：重庆\n当事人：王某\n平台：网络\n言论内容：对政府部门防范处理疫情的“断掌取义谣言“\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:21.74019+12
1296	1313	【中国文字狱事件记录】\n日期：2020年01月24日\n地点：新疆库尔勒\n当事人：努某\n平台：网络\n言论内容：欢迎“冠状病毒”到来我们美丽的库尔勒\n背景事件：武汉新型冠状病毒肺炎\n处罚：“依法处理”	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:21.788732+12
1297	1314	【中国文字狱事件记录】\n日期：2020年01月24日\n地点：河南杞县\n当事人：刘某\n平台：网络\n言论内容：杞县人民医院已有2例，4至5例高度疑似\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:21.834562+12
1298	1315	【中国文字狱事件记录】\n日期：2020年01月24日\n地点：陕西镇巴县兴隆镇财政审计所\n当事人：陈国琴\n平台：微信群\n言论内容：20日有公安机关的人员在武汉押犯人回来，被感染;公安局的工作人员是确诊，明天会宣布\n背景事件：武汉新型冠状病毒肺炎\n处罚：党内警告	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:21.88126+12
1299	1316	【中国文字狱事件记录】\n日期：2020年01月24日\n地点：陕西镇巴县\n当事人：符春黎\n平台：微信群\n言论内容：（转发）20日有公安机关的人员在武汉押犯人回来，被感染;公安局的工作人员是确诊，明天会宣布\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政警告	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:21.927125+12
1300	1317	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：江西资溪县\n当事人：朱某（未成年人）\n平台：QQ群\n言论内容：资溪有一个确诊新型冠状病毒的；好像从武汉跑回来过年了\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:21.973318+12
1301	1318	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：江西资溪县\n当事人：林某（未成年人）\n平台：QQ群\n言论内容：资溪大觉山刚刚好像有人得了冠性肺炎,景区那么多人哎,开学我应该不用去了\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:22.018842+12
1302	1319	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：江西资溪县\n当事人：戴某\n平台：微信\n言论内容：车牌号浙BL0535这个车刚从武汉回来，车上的人确诊了偷跑回来的，大家看到了及时报警\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:22.064603+12
1303	1320	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：天津\n当事人：孟某\n平台：微信群\n言论内容：与新型冠状病毒肺炎有关的“不实信息”\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:22.110454+12
1304	1322	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：四川自贡\n当事人：孙某\n平台：微信群\n言论内容：此次疫情系解放军传播病毒导致\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:22.201634+12
1305	1323	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：四川绵竹县\n当事人：张某\n平台：微信群\n言论内容：（视频）绵竹富新已出现感染者\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:22.249256+12
1306	1324	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：河南栾川县\n当事人：王某\n平台：微信群\n言论内容：栾川县人民医院治疗新型冠状病毒感染肺炎病例诊断证明\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:22.296177+12
1307	1325	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：广西岑溪市\n当事人：李某\n平台：微信群\n言论内容：岑溪筋竹已经确诊一例新型冠状病毒......已经确诊，武汉回来的\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:22.341913+12
1308	1326	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：福建安溪县\n当事人：白某\n平台：微信群\n言论内容：五里铺从武汉回来的那个人晚上死了，去看他的那个医生也很严重了，估计没救了，官桥已沦陷\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:22.388657+12
1309	1327	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：甘肃宕昌县\n当事人：杨某杰\n平台：微信群\n言论内容：何家堡确诊了一例新冠状病毒的患者……大家还是注意防范，能不出门就不出门\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:22.434796+12
1310	1328	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：江苏宿迁\n当事人：孙某\n平台：微信群\n言论内容：XX花园的已经死了；是的；死在俺儿媳医院的\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留6日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:22.483292+12
1311	1329	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：新疆博乐\n当事人：马某\n平台：微信群\n言论内容：博乐有从湖北回来的学生有1000多名，发烧的有十几个，确诊的有三个\n背景事件：武汉新型冠状病毒肺炎\n处罚：“依法处理”	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:22.530367+12
1955	1971	【中国文字狱事件记录】\n日期：2020年05月13日\n地点：河南修武县\n当事人：谢某林\n平台：微博\n言论内容：“辱骂交警”的言论\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:55.190741+12
1312	1330	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：新疆博乐\n当事人：李某\n平台：微信群\n言论内容：“有关新型冠状病毒疫情防控工作相关虚假信息”\n背景事件：武汉新型冠状病毒肺炎\n处罚：“依法处理”	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:22.577105+12
1313	1331	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：吉林通化\n当事人：刘某明\n平台：微信群\n言论内容：通化市有疑似感染新型肺炎病人\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:22.624158+12
1314	1332	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：内蒙古包头\n当事人：袁某\n平台：微信群\n言论内容：对不起，我被确诊了，昨天去了迷鹿，我对不起大家，和我接触的快去体检\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日、罚款200元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:22.670188+12
1315	1333	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：浙江金华\n当事人：王某\n平台：微信群\n言论内容：金东区澧浦西旺村已经封村，有一个武汉工作的人员逃回来了，全村观察封村\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:22.716463+12
1316	1334	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：浙江东阳\n当事人：陈某\n平台：微信群\n言论内容：横店商贸城里塘村有一个病人湖北回来的确诊了，全村封锁了\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:22.762616+12
1317	1335	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：湖北钟祥县\n当事人：杨某\n平台：微信群\n言论内容：柴湖死了几个；冷水6个；路市12个；官庄湖3个；五庙一个\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:22.921958+12
1318	1336	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：湖北钟祥县\n当事人：王某\n平台：微信群\n言论内容：（转发）浙XX这个车子刚从武汉回来，车上的人确诊了偷跑回来的\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:22.96974+12
1319	1337	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：广东陆丰\n当事人：黄某\n平台：微信群\n言论内容：明天开始估计陆丰要封掉高速公路；乌石部30多人在武汉回来，他家人最近在买退烧药、下寨有一个已经高烧，也是武汉回家\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:23.008569+12
1320	1338	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：贵州三穗县\n当事人：杨某\n平台：微信群\n言论内容：10万人确诊心性肺炎、新闻都是骗人的，现在每天最少死100多个人\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:23.047704+12
1321	1339	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：吉林辉南县\n当事人：刘某\n平台：微信群\n言论内容：浙DL05N5的车辆，是新型冠状肺炎病毒感染者，大家注意啊。遇到此车赶紧报案\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:23.089724+12
1322	1340	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：甘肃环县\n当事人：石某\n平台：微信群\n言论内容：西峰地区已经确诊2例新型冠状病毒感染肺炎患者\n背景事件：武汉新型冠状病毒肺炎\n处罚：罚款200元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:23.134881+12
1323	1341	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：甘肃环县\n当事人：李某\n平台：微信群\n言论内容：（转发）西峰地区已经确诊2例新型冠状病毒感染肺炎患者\n背景事件：武汉新型冠状病毒肺炎\n处罚：罚款200元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:23.181203+12
1324	1342	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：甘肃环县\n当事人：杨某\n平台：微信群\n言论内容：（转发）西峰地区已经确诊2例新型冠状病毒感染肺炎患者\n背景事件：武汉新型冠状病毒肺炎\n处罚：罚款200元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:23.227265+12
1325	1343	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：河北盐山县\n当事人：李某\n平台：微信群\n言论内容：病毒通过50米以内空气和眼睛都能传播,孟村可能死亡一例,沧州市确定确诊两例,没有任何特效药能治疗,\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:23.274114+12
1326	1344	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：宁夏银川\n当事人：陈某\n平台：微信群\n言论内容：北川一女性感染SB250病毒死亡\n背景事件：武汉新型冠状病毒肺炎\n处罚：批评教育	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:23.321089+12
1327	1345	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：甘肃玉门\n当事人：李某\n平台：微信群\n言论内容：昨天晚上两个湖北武汉的入住玉门龙源商务酒店，大家做好防范措施；车牌号浙BL0535 这个车刚从武汉回来\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留4日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:23.369927+12
1328	1346	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：甘肃高台县\n当事人：张某\n平台：微信群\n言论内容：罗成侯庄出了 3 例疑似 \n背景事件：武汉新型冠状病毒肺炎\n处罚：罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:23.41679+12
1329	1347	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：甘肃高台县\n当事人：许某\n平台：微信群\n言论内容：高台县已经有一例疑似病人，近期大家不要再串门，我们休假已取消明天正常上班一定要重视\n背景事件：武汉新型冠状病毒肺炎\n处罚：罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:23.463951+12
1330	1348	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：甘肃民乐县\n当事人：郑某、王某\n平台：微信群\n言论内容：（转发）黄青村目前已出现一例疑似病人，全家人以及医护人员都已被隔离\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:23.510372+12
1331	1349	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：甘肃定西\n当事人：陈某\n平台：微信群\n言论内容：安定某宾馆发现 2 名，某宾馆都被隔离\n背景事件：武汉新型冠状病毒肺炎\n处罚：”依法处理“	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:23.556128+12
1332	1350	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：甘肃定西\n当事人：姜某\n平台：微信群\n言论内容：武汉来的车，全省高速全部封闭、隔离了 72 人\n背景事件：武汉新型冠状病毒肺炎\n处罚：”依法处理“	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:23.603662+12
1333	1351	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：新疆阿克苏\n当事人：迪某\n平台：微信群\n言论内容：明天早上四点到四点半不要出门，因为政府安排飞机洒消毒药水\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留8日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:23.649868+12
2238	2258	【中国文字狱事件记录】\n日期：2021年06月24日\n地点：陕西汉阴县\n当事人：刘某勇\n平台：朋友圈\n言论内容：“辱骂交警”的视频\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:09.104368+12
1334	1352	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：新疆乌鲁木齐\n当事人：池某\n平台：微信群\n言论内容：新疆死亡总人数X人\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫、罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:23.695869+12
1335	1353	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：江西永丰县\n当事人：王某\n平台：微信群\n言论内容：藤田镇岭南村有一个新型病毒的，送吉安去了，大家少出门\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:23.742506+12
1336	1354	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：江西永丰县\n当事人：曹某\n平台：微信群\n言论内容：瑶田三湾村有户人家的儿子从武汉偷偷回来，现在全家都有咳嗽\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:23.789093+12
1337	1355	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：广西百色\n当事人：邓某\n平台：微信群\n言论内容：百色市联防联控指挥部关于疫情防控工作的会议要求\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:23.842203+12
1338	1356	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：广西德保县\n当事人：黄某桃\n平台：微信群\n言论内容：有老虎洞那边有人已经感染了、嫁去武汉的女儿回来感染全家、现在隔离在中医院\n背景事件：武汉新型冠状病毒肺炎\n处罚：“依法处理”	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:23.890954+12
1339	1357	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：河南光山县\n当事人：张某\n平台：微信群\n言论内容：息县曹黄林乡凉亭村因冠状病毒感染已死一人，拉到医院一人\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留7日、罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:23.93826+12
1340	1358	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：河南伊川县\n当事人：杨某军\n平台：微信群\n言论内容：（转发）我县排查出武汉返回伊川人员422名，已确诊8例\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日、罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:23.985494+12
1341	1359	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：河南民权县\n当事人：王某\n平台：微信群\n言论内容：民权武汉返乡五百多人确认二十多人带病毒\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:24.030557+12
1342	1360	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：江西金溪县\n当事人：李某\n平台：微信群\n言论内容：在发人温（瘟），我昨晚X村30年夜在看打牌，死了一个人48岁，公共场所少去聚餐，唱歌为好\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:24.077665+12
1343	1361	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：广东翁源县\n当事人：不详\n平台：微信群\n言论内容：翁源已经有两例病毒感染了，你们一定要注意卫生，最好戴口罩，勤洗手\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:24.122887+12
1344	1362	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：广东翁源县\n当事人：不详\n平台：微信群\n言论内容：现在龙仙几例了，XX都有两人死掉了\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:24.171086+12
1345	1363	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：吉林敦化\n当事人：贾某富\n平台：微信群\n言论内容：车牌号浙BL0535这个车刚从武汉回来，车上的人确诊了偷跑回来的，大家看到了及时报警，希望大家留意此车牌号，转发各个群，朋友圈，以免更多人受到传染\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:24.22045+12
1346	1364	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：河南新密市\n当事人：郝某\n平台：微信群\n言论内容：紧急通知：刚才河南省郑州市新密市超化镇新庄村确诊1例冠状病毒肺炎感染病例,此人在新县城座过9路公共汽车,现在自己驾车逃跑失联,都要高度重视\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:24.266412+12
1347	1365	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：山西岚县\n当事人：牛某军\n平台：微信群\n言论内容：我在山西，官方说6例，实际不止这点，谎报很严重啊\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:24.31221+12
1348	1366	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：山西柳林县\n当事人：贾某\n平台：微信群\n言论内容：柳林一例已确诊的病人，住于柳林镇家属院内，请家人们出门一定戴口罩，尽量不参加各种聚会\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:24.358044+12
1349	1367	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：广东阳春\n当事人：黄某\n平台：微信群\n言论内容：各位，最新消息，武汉有九家来到春湾逃难，现被政府控制，安排某酒店，政府人员被紧急召回商量，还是在家里比较安全\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:24.404833+12
1350	1368	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：四川德阳\n当事人：黄某\n平台：微信群\n言论内容：有一辆浙B的小汽车从武汉跑出来了，就随口说这个车就在孝感镇某某村\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:24.449789+12
1351	1369	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：青海湟中县\n当事人：海某\n平台：微信群\n言论内容：西宁市出租车25日起全面停运公告\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:24.495786+12
1352	1370	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：广东龙川县\n当事人：何某霞\n平台：微信群\n言论内容：县城某小区有人感染新型冠状病毒肺炎\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:24.543364+12
1353	1371	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：贵州思南县\n当事人：杨某\n平台：微信群\n言论内容：这个肺炎老火了，铜仁市思南县1例，县城即将封闭\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:24.589827+12
1354	1372	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：新疆阿克苏\n当事人：陈某\n平台：微信群\n言论内容：新疆本来就特殊一些，出去看到哪个都是感染者\n背景事件：武汉新型冠状病毒肺炎\n处罚：罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:24.634907+12
1355	1373	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：山西应县\n当事人：李某\n平台：微信群\n言论内容：这次疫情应该比想象的严重，在我们陕西省只有一例确诊的时候，我们县都有两例，感觉当官的在谎报\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:24.679826+12
1356	1374	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：广东湛江\n当事人：林某玲（医生）\n平台：微信群\n言论内容：附院已住满了；起码收治十例确诊为新型冠状病毒感染肺炎病人\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:24.726304+12
1357	1375	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：河北承德县\n当事人：不详\n平台：微信群\n言论内容：承德县回来50多个武汉的，5例疑似在观察，目前有发烧症状但没有确诊，现在大平台有1例今早基本确诊了，县医院有1例基本确诊了\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:24.772147+12
1358	1376	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：河北内丘县\n当事人：张某进\n平台：微信群\n言论内容：内丘已经发现三例患者，全部死亡\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:24.817573+12
1359	1377	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：河北内丘县\n当事人：刘某国\n平台：微信群\n言论内容：内丘柳林乡下马庄村今天死了一个新型冠状病毒患者\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:24.864108+12
1360	1378	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：湖南资兴市\n当事人：宋某\n平台：微信群\n言论内容：刚听到消息，资兴兴宁传染十多人了，一老人家从武汉回，把病带过来的，医护人员都传染八名……\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:24.912431+12
1361	1379	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：湖南双峰县\n当事人：彭某群\n平台：微信群\n言论内容：双峰诸家村蒋某今天已去世的消息是真的，请各位亲人高度重视\n背景事件：武汉新型冠状病毒肺炎\n处罚：“依法查处”	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:24.958266+12
1362	1380	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：北京\n当事人：栾某\n平台：微信群\n言论内容：（视频）白庙村出现新型冠状病毒肺炎病例\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:25.004615+12
1363	1381	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：天津\n当事人：薛某\n平台：微信群\n言论内容：“新型冠状病毒肺炎疫情的虚假言论”\n背景事件：武汉新型冠状病毒肺炎\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:25.051134+12
1364	1382	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：安徽泗县\n当事人：邵某\n平台：微信群\n言论内容：泗县黄圩镇巩沟村发现一例冠状病毒感染者\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:25.097712+12
1365	1383	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：湖南慈利县\n当事人：汪某\n平台：微信群\n言论内容：慈利县新型冠状病毒感染的肺炎防控指挥部令【第1号】\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:25.143607+12
1366	1384	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：山东兖州市\n当事人：王某\n平台：微信群\n言论内容：@大家注意，薛庙社区已出现一位新冠肺炎，已确诊！！！出门一定戴口罩！！！确实是真的，我们医院已接到通知\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留7日、罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:25.190401+12
1367	1385	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：河北高碑店\n当事人：马某\n平台：微信群、电话\n言论内容：在群里说其丈夫回家后发高烧，并报警\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:25.235098+12
1368	1386	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：黑龙江大庆\n当事人：高某\n平台：微博\n言论内容：黑龙江大庆，昨晚确诊一男孩，坚持回家，好害怕为什么要回家啊\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:25.27939+12
1369	1387	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：吉林通化\n当事人：胡某莉\n平台：微博\n言论内容：通化市确诊一例新型冠状病毒病人\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政罚款	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:25.324917+12
1370	1388	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：广西合浦县\n当事人：何某\n平台：微博\n言论内容：新型肺炎已经在合浦某小区传播\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:25.368798+12
1371	1389	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：吉林松原县\n当事人：李某\n平台：微博\n言论内容：（未发布，与亲友视频聊天时说道）疫情谣言\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日，罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:25.413294+12
1372	1390	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：吉林松原县\n当事人：张某\n平台：微博\n言论内容：疫情谣言\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日，罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:25.457782+12
1373	1391	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：贵州德江县\n当事人：沈某\n平台：微博\n言论内容：德江已有6例被隔离，我就是本地人，官方只有两例完全就是胡扯，担心引起恐慌\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:25.500131+12
1374	1392	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：宁夏银川\n当事人：康某\n平台：微博\n言论内容：经人举报发现我家小区由于从武汉偷偷打黑车溜回的\n背景事件：武汉新型冠状病毒肺炎\n处罚：批评教育	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:25.542148+12
1375	1393	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：河北唐山\n当事人：王某\n平台：微博\n言论内容：弘慈医院急诊科接受武汉回来的发热病人\n背景事件：武汉新型冠状病毒肺炎\n处罚：批评教育	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:25.584169+12
1376	1394	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：湖北舞阳县\n当事人：赖某\n平台：抖音\n言论内容：（视频）刚从武汉逃回来（不实）\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:25.62746+12
1377	1395	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：广西融安县\n当事人：罗某会\n平台：朋友圈\n言论内容：当地（融安县长安镇）有2人确诊为新型肺炎\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:25.672498+12
1378	1396	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：江西德兴\n当事人：余某亮\n平台：朋友圈\n言论内容：事态严重，黄柏都有人确诊了\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:25.715933+12
1379	1397	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：江苏宿迁\n当事人：曹某\n平台：朋友圈\n言论内容：武汉死了十万人了知道吗？武汉已经流向全国230万人次你们知道吗？\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留6日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:25.760063+12
1380	1398	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：吉林通化\n当事人：国某斌\n平台：朋友圈\n言论内容：（视频）通化市确诊两例，疑似一例，通化市戒严\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政罚款	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:25.804609+12
1381	1399	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：陕西延安\n当事人：某腾\n平台：朋友圈\n言论内容：（视频）刚从武汉回来（不实）\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:25.847922+12
1382	1400	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：山东东阿县\n当事人：李某龙\n平台：朋友圈\n言论内容：茄李村发现一例病毒感染，现在已经把该村封锁\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政罚款	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:25.891542+12
1383	1401	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：山东昌邑市\n当事人：周某\n平台：朋友圈\n言论内容：重要通知，昌邑已经有新型病毒感染者，饮马小营有一例，大家不要出门，多用消毒液家里进行消毒\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:25.936433+12
1384	1402	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：辽宁大连\n当事人：周某\n平台：朋友圈\n言论内容：金州区三十里堡一名武汉大学生春节期间放假回来，随身携带新型冠状病毒肺炎已经死亡，金州三院全院所有医护人员已经被强制性隔离\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:25.98077+12
1385	1403	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：天津\n当事人：李某\n平台：朋友圈\n言论内容：“针对新型冠状病毒感染的肺炎疫情涉及的地区及医务人员攻击性、侮辱性言论”\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:26.026224+12
1386	1404	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：河北内丘县\n当事人：李某静\n平台：朋友圈\n言论内容：内丘已经有冠状病毒患者\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:26.072576+12
1387	1405	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：新疆轮台县\n当事人：阿某\n平台：朋友圈\n言论内容：武汉确诊患者驾车偷跑入疆\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:26.119771+12
1388	1406	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：天津\n当事人：曹某\n平台：朋友圈\n言论内容：“涉及新型冠状病毒肺炎疫情的虚假信息”\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:26.165038+12
1389	1407	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：广西融安县\n当事人：吴某强\n平台：网络\n言论内容：与新型肺炎有关的“虚假信息”\n背景事件：武汉新型冠状病毒肺炎\n处罚：口头警告	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:26.209049+12
1390	1408	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：四川德格县\n当事人：登某\n平台：网络\n言论内容：甘孜州（德格县）龚垭乡13个人都被一汉族人传染了，请大家一定注意\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:26.254801+12
1391	1409	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：新疆库尔勒\n当事人：周某\n平台：网络\n言论内容：我有同学已经被感染了，去了趟新汇嘉被传染的\n背景事件：武汉新型冠状病毒肺炎\n处罚：“依法处理”	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:26.300097+12
1392	1410	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：新疆乌鲁木齐\n当事人：“威廉”\n平台：网络\n言论内容：咱们乌鲁木齐市民不要盲目自信了，12月30日-1月20日地窝堡机场接纳13000来自武汉的旅客\n背景事件：武汉新型冠状病毒肺炎\n处罚：侦办中	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:26.346041+12
1393	1411	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：贵州黄平县\n当事人：杨某\n平台：网络\n言论内容：黄平县发现一名前几天从武汉回来的病例；尽量少出门，出门请带上口罩\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:26.392765+12
1394	1412	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：广东揭阳\n当事人：谢某升\n平台：网络\n言论内容：有一年龄约60岁左右的男子因感染新型冠状病毒治疗无效死亡（警方称死于其它肺病）\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:26.442301+12
1395	1436	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：江苏南京\n当事人：孙某\n平台：微信群\n言论内容：（以记者名义发布）南京自1月27日交通停运、全面封城\n背景事件：武汉新型冠状病毒肺炎\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:27.515006+12
1396	1413	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：辽宁大连\n当事人：胡某\n平台：网络\n言论内容：金州区三十里堡一名武汉大学生春节期间放假回来，随身携带新型冠状病毒肺炎已经死亡，金州三院全院所有医护人员已经被强制性隔离\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:26.489991+12
1397	1414	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：福建福清市\n当事人：江某凎\n平台：网络\n言论内容：（视频）飞机泼洒消毒水\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:26.535922+12
1398	1415	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：福建福清市\n当事人：郑某民\n平台：网络\n言论内容：（视频）高山镇沦陷\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:26.579879+12
1399	1416	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：福建福清市\n当事人：林某华\n平台：网络\n言论内容：（视频）高山镇沦陷\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政罚款	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:26.625895+12
1400	1417	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：福建福清市\n当事人：林某玲\n平台：网络\n言论内容：（视频）高山镇沦陷\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政罚款	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:26.672529+12
1401	1418	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：福建福清市\n当事人：王某娟\n平台：网络\n言论内容：（视频）高山镇沦陷\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:26.718031+12
1402	1419	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：广西宾阳县\n当事人：杨某\n平台：网络\n言论内容：转发宾阳县联防联控指挥部会议要求\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:26.762987+12
1403	1420	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：广西宾阳县\n当事人：巫某\n平台：网络\n言论内容：古辣镇淡道村有一例疑似新型肺炎病例\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留2日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:26.808965+12
1404	1421	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：四川德阳\n当事人：冯某\n平台：网络\n言论内容：（视频）在旌阳区德新镇出现了感染新型冠状病毒的病人，病人已经被强制带走\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:26.855074+12
1405	1422	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：辽宁开原市\n当事人：不详\n平台：网络\n言论内容：中医院有一例疑似新冠患者隐瞒实情拒不上报\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:26.900264+12
1406	1423	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：黑龙江克山县\n当事人：房某\n平台：网络\n言论内容：克山县存在疫情\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:26.94474+12
1407	1424	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：安徽黟县\n当事人：“随麦老去”\n平台：虎扑\n言论内容：一大巴车武汉人逃到我们“深山老林”避难了真的很可恶可恨\n背景事件：武汉新型冠状病毒肺炎\n处罚：已查获，将“依法严惩”	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:26.990424+12
1408	1425	【中国文字狱事件记录】\n日期：2020年01月25日\n地点：陕西米脂县\n当事人：冯某\n平台：钉钉群\n言论内容：榆林截止昨晚已经6例（暂未发布）全部在高新区一院隔离，所有的医护人员也已经全部隔离\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:27.03148+12
1409	1426	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：四川大竹县\n当事人：胡某\n平台：QQ群\n言论内容：（转发自徐某）伪造大竹县人民医院新型冠状病毒感染肺炎诊断书照片\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:27.07359+12
1410	1427	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：广东罗定市\n当事人：吴某东\n平台：今日头条\n言论内容：罗定市金鸡镇有一个从武汉回家过年的女孩带回病毒，导致全镇封锁，一人死亡\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:27.115171+12
1411	1428	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：甘肃兰州\n当事人：李某栋\n平台：微信\n言论内容：兰州即将封城\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:27.157887+12
1412	1429	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：广东阳江\n当事人：黄某\n平台：微信\n言论内容：东平核电站有1例病毒感染，已封路，不能进入东平了，东平的不能出阳江了\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政罚款	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:27.198722+12
1413	1430	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：新疆阿克苏\n当事人：拜某\n平台：微信\n言论内容：中国消费者协会官方网特意介绍某公司的空气净化器，因为这个机器自带新型冠状病毒处理功能，每一个家庭必须安装，不用跑到三亚找新鲜空气\n背景事件：武汉新型冠状病毒肺炎\n处罚：罚款300元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:27.243933+12
1414	1431	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：河北承德县\n当事人：杨某\n平台：微信\n言论内容：《承德县新型冠状病毒感染的肺炎防控指挥部令》\n背景事件：武汉新型冠状病毒肺炎\n处罚：罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:27.28693+12
1415	1432	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：海南儋州\n当事人：符善波\n平台：微信群\n言论内容：大家赶紧去买米，人家大陆的米马上不进岛了\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:27.33037+12
1416	1433	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：四川旺苍县\n当事人：何某\n平台：微信群\n言论内容：将”韶关市关于新型冠状病毒肺炎感染应急指挥部公告 第一号“改为广元市\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:27.375633+12
1417	1434	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：河南光山县\n当事人：谢某\n平台：微信群\n言论内容：媒体坑爹，估计已死了几千人了，医院故意不给确诊，就不算肺炎死的，这样可谎报数字\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日、罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:27.422339+12
1418	1435	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：湖北巴东县\n当事人：汪某\n平台：微信群\n言论内容：我们这个地方还有蛮多人不相信，总以为才死40几个人，其实内部人员说武汉死了十几万了，不然国家没有那么重视\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:27.46973+12
1419	1437	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：吉林梅河口\n当事人：于某\n平台：微信群\n言论内容：官方公布的数据不准；加油站没有油；没感染的人自我隔离\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:27.560318+12
1420	1438	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：吉林通化\n当事人：张某\n平台：微信群\n言论内容：通化有冠状病毒感染肺炎病例患者\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:27.608356+12
1421	1439	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：宁夏平罗县\n当事人：杨某\n平台：微信群\n言论内容：今天平罗明月新村120拉走一个高烧患者，新利小区拉走一个高烧患者，山水名居隔离一个湖北返乡人员\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政罚款	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:27.657376+12
1422	1440	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：贵州德江县\n当事人：吕某\n平台：微信群\n言论内容：沿河一个16岁女孩从武汉回来的，今天已经确认感染上了， 德江明天封城\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:27.705461+12
1423	1441	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：黑龙江牡丹江\n当事人：刘某、张某、董某（未成年人）\n平台：微信群\n言论内容：夏威夷（酒店）已经查出来一个武汉人在那住了好几天，目前已发烧，整个酒店已经开始消毒了\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:27.75433+12
1424	1442	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：河北威县\n当事人：王某\n平台：微信群\n言论内容：王目村已经有一个确认而且死亡的，一定要重视，我们村已经封路了\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日\n备注：该群群主也被约谈	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:27.805147+12
1425	1443	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：贵州道真县\n当事人：韩某\n平台：微信群\n言论内容：疫情谣言\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日\n备注：该群群主也被约谈	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:27.851489+12
1426	1444	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：新疆乌鲁木齐\n当事人：李某\n平台：微信群\n言论内容：将“武威市新型冠状病毒感染的肺炎疫情防控工作小组通告”改为乌鲁木齐\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:27.89685+12
1427	1445	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：新疆博湖县\n当事人：孙某\n平台：微信群\n言论内容：库尔勒的普通口罩都涨了天价，库尔勒的超市已经关门，周边小店全部让关门了\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:27.943234+12
1428	1446	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：新疆阿克陶县\n当事人：孜某\n平台：微信群\n言论内容：大家不要再出门了，阿克陶县刚刚发现了一个，他在武汉上大学，家在玉麦乡，现在在县医院刚刚发现的\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:27.990377+12
1429	1447	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：河北博野县\n当事人：王某\n平台：微信群\n言论内容：1月20日博野县小店镇谭庄村谭广孝、谭吉与15人聚餐后疑似感染了新型冠状病毒并已送至保定市传染病医院治疗\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:28.036074+12
1430	1448	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：河北博野县\n当事人：时某旭\n平台：微信群\n言论内容：1月20日博野县小店镇谭庄村谭广孝、谭吉与15人聚餐后疑似感染了新型冠状病毒并已送至保定市传染病医院治疗\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:28.083642+12
1431	1449	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：河北博野县\n当事人：卢某兰\n平台：微信群\n言论内容：1月20日博野县小店镇谭庄村谭广孝、谭吉与15人聚餐后疑似感染了新型冠状病毒并已送至保定市传染病医院治疗\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:28.132638+12
1432	1450	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：河北博野县\n当事人：陈某琴\n平台：微信群\n言论内容：1月20日博野县小店镇谭庄村谭广孝、谭吉与15人聚餐后疑似感染了新型冠状病毒并已送至保定市传染病医院治疗\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:28.179064+12
1433	1451	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：河北博野县\n当事人：李某珍\n平台：微信群\n言论内容：1月20日博野县小店镇谭庄村谭广孝、谭吉与15人聚餐后疑似感染了新型冠状病毒并已送至保定市传染病医院治疗\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:28.224661+12
1434	1452	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：山西忻州\n当事人：肖某\n平台：微信群\n言论内容：（视频）武汉人回四川老家，被老家人举报了，他就把举报人给杀了\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:28.273085+12
1435	1453	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：广西浦北县\n当事人：谭某\n平台：微信群\n言论内容：请注意，浦北小江与福旺大湾已确诊1例新型冠状肺炎病毒\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:28.320331+12
1436	1454	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：广西田东县\n当事人：卢某南\n平台：微信群\n言论内容：田东县思林镇林秀村一男子刚去武汉回来患疫情病毒死亡\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:28.365546+12
1437	1455	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：广西平果县\n当事人：韦某\n平台：微信群\n言论内容：我刚从武汉回来三天，你们每人给我转100块红包，要不然我天天就在小区里面转\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:28.413007+12
1438	1456	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：江西新余\n当事人：黄某\n平台：微信群\n言论内容：听挖（听说）新余那个金盾花园的挂了，而且新余这一例没上报\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:28.460222+12
1439	1457	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：江西定南县\n当事人：胡某华\n平台：微信群\n言论内容：（图片）遥溪观公路封路通行不了了\n背景事件：武汉新型冠状病毒肺炎\n处罚：治安拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:28.505705+12
1440	1458	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：江西抚州\n当事人：刘某\n平台：微信群\n言论内容：东乡区患者已经死亡\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:28.55208+12
1441	1459	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：江西抚州\n当事人：陈某\n平台：微信群\n言论内容：东乡区者已经死亡\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:28.598752+12
1442	1460	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：江西永修县\n当事人：王某\n平台：微信群\n言论内容：九江：明天早上四点到四点半不要出门，因为政府安排飞机洒消毒药水\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:28.644531+12
1443	1461	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：江西资溪县\n当事人：邓某\n平台：微信群\n言论内容：（视频）新型冠状病毒爆发后，十八省米、菜都已停运，现在已无法运进资溪，呼吁大家快去抢购\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:28.691496+12
1444	1462	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：江苏苏州\n当事人：徐某\n平台：微信群\n言论内容：（视频）平望镇新尚海酒店内被隔离23名疫情人员\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:28.734699+12
1445	1463	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：江苏苏州\n当事人：姚某\n平台：微信群\n言论内容：（视频）平望镇新尚海酒店内被隔离23名疫情人员\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:28.778692+12
1446	1464	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：广西兴业县\n当事人：马某\n平台：微信群\n言论内容：高田有疫情，今日封路了；因为有一个是在武汉读书回来的，他们一家人传染了，现在送去玉林了；应该是真的\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留2日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:28.824881+12
1447	1465	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：湖北仙桃市\n当事人：许某等3人\n平台：微信群\n言论内容：（视频）一家防护用品企业员工感染新型冠状病毒肺炎\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:28.874373+12
1448	1466	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：吉林敦化\n当事人：由某辉\n平台：微信群\n言论内容：百货大楼一名营业员确诊为患者，正在就诊\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:28.923099+12
1449	1467	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：甘肃金塔县\n当事人：代某、刘某\n平台：微信群\n言论内容：从武汉返回酒泉的人数共991人，现全部检查，已有9人确诊为病毒感染。希望大家备好半年的米、面、菜，做好在家打持久战的准备\n背景事件：武汉新型冠状病毒肺炎\n处罚：治安处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:28.97197+12
1450	1468	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：四川达州\n当事人：曹某\n平台：微信群\n言论内容：达州市出租车将停止运营\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:29.016967+12
1451	1469	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：四川绵竹\n当事人：张某\n平台：微信群\n言论内容：（视频）好吓人，好吓人，富新都有了\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:29.062252+12
1452	1470	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：江苏高邮\n当事人：陈某\n平台：微信群\n言论内容：涉及新型冠状病毒感染的肺炎疫情不实言论\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:29.107543+12
1453	1471	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：江苏宝应县\n当事人：苗某\n平台：微信群\n言论内容：涉及新型冠状病毒感染的肺炎疫情不实言论\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:29.154896+12
1454	1472	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：广东蕉岭县\n当事人：黄某凤、黄某盛\n平台：微信群\n言论内容：分水岌封路了\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:29.200132+12
1455	1473	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：广东龙川县\n当事人：欧阳某旋\n平台：微信群\n言论内容：关疫情的不实信息\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:29.244801+12
1456	1474	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：贵州铜仁\n当事人：柳某\n平台：微信群\n言论内容：铜仁谢桥着了好多新型病毒感染者，铜仁马上要封城了\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:29.291875+12
1457	1475	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：江西遂川县\n当事人：邓某\n平台：微信群\n言论内容：堆子前某村有两人感染病毒死亡……\n背景事件：武汉新型冠状病毒肺炎\n处罚：治安处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:29.339076+12
1458	1476	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：山西朔州\n当事人：王某\n平台：微信群\n言论内容：玛德山西疑似的一个也不报，这还不算瞒报\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:29.386797+12
1459	1477	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：辽宁东港市\n当事人：梁某\n平台：微信群\n言论内容：辽宁省葫芦岛发现100多人感染上新型病毒\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:29.432544+12
1460	1478	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：贵州清镇市\n当事人：李某民\n平台：微信群\n言论内容：（视频）清镇确诊一名感染新型冠状病毒人员\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:29.479767+12
1461	1479	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：新疆轮台县\n当事人：艾某\n平台：微信群\n言论内容：湖北的一名警察被隔离在轮台县医院\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:29.525571+12
1462	1480	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：河北沽源县\n当事人：任某\n平台：微信群\n言论内容：某小区楼内，武汉学生发烧入院；\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:29.571213+12
1463	1481	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：广东陆河县\n当事人：谢某洁\n平台：微信群\n言论内容：明天所有医院都要上班，陆河有一例冠状病毒肺炎了，那个人不去医院，跑走了，现在所有人在找他找不到\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:29.61887+12
1464	1482	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：湖南张家界\n当事人：郝某宏\n平台：微信群\n言论内容：《张家界新型冠状病毒感染肺炎防控指挥部令第1号》\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:29.66855+12
1465	1483	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：河北邯郸\n当事人：郝某\n平台：微信群\n言论内容：肺炎疫情期间邯郸市出租车停运\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:29.71317+12
1466	1484	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：河北邯郸\n当事人：李某\n平台：微信群\n言论内容：（转发）肺炎疫情期间邯郸市出租车停运\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:29.75885+12
1467	1485	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：河北邯郸\n当事人：胡某\n平台：微信群\n言论内容：（转发）肺炎疫情期间邯郸市出租车停运\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:29.804885+12
1468	1486	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：河北邯郸\n当事人：马某\n平台：微信群\n言论内容：（转发）肺炎疫情期间邯郸市出租车停运\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:29.853778+12
1580	1598	【中国文字狱事件记录】\n日期：2020年01月28日\n地点：河北石家庄\n当事人：曹某\n平台：网络\n言论内容：大蒜水能治疗新型冠状病毒肺炎\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:35.070782+12
1469	1487	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：山东兖州市\n当事人：武某\n平台：微信群\n言论内容：小孟二村袁某某的儿子确诊为新型冠状病毒肺炎患者，村庄已经全部隔离，医学观察76人，不要走新驿到宁阳的县道。\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:29.899298+12
1470	1488	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：辽宁岫岩县\n当事人：唐某\n平台：微博\n言论内容：如果我被感染了共党不给钱老子一定要去多传染几个\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留15日、罚款1000元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:29.945168+12
1471	1489	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：广西腾县\n当事人：孙某清\n平台：微博\n言论内容：有关虚假肺炎疫情信息\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:29.990441+12
1472	1490	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：甘肃正宁县\n当事人：巩某\n平台：微博\n言论内容：离我家不到五公里的村子已经确诊了 2 例，隔离 11 个 \n背景事件：武汉新型冠状病毒肺炎\n处罚：罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:30.03742+12
1473	1491	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：广西灵山县\n当事人：苏某浩\n平台：微博\n言论内容：灵山有三例新型冠状病毒感染的肺炎病例\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:30.084216+12
1474	1492	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：江苏如东县\n当事人：季某晗\n平台：微博\n言论内容：我家附近有从武汉回来的大学生得了新型冠状病毒，有六个，已经死亡两个，还有一个领导感染上了，还瞒着政府不上报怕丢官\n背景事件：武汉新型冠状病毒肺炎\n处罚：罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:30.132135+12
1475	1493	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：内蒙古通辽\n当事人：满某\n平台：快手\n言论内容：（视频）现在的新型冠状病毒引起的肺炎，是美国向中国使用病毒基因武器造成的\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日、罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:30.181372+12
1476	1494	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：浙江台州\n当事人：黄某川\n平台：朋友圈\n言论内容：连夜带新型冠状病毒回来；回台州的路上\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:30.228906+12
1477	1495	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：广西苍梧县\n当事人：全某\n平台：朋友圈\n言论内容：经确定达坡村有一名从武汉坐高铁回来人员……达坡村今晚开始由武警封村14天\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:30.274062+12
1478	1496	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：湖北恩施\n当事人：卢某\n平台：朋友圈\n言论内容：（视频）有人被隔离\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:30.320099+12
1479	1497	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：吉林辉南县\n当事人：杨某\n平台：朋友圈\n言论内容：通知：辉南县团林镇纪家街发现疑似病历，全镇封闭\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:30.364935+12
1480	1498	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：甘肃兰州\n当事人：闫某\n平台：朋友圈\n言论内容：（聚餐视频）发生的疫情根本没人管，政府也不作为，疫情很快会爆发\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:30.41274+12
1481	1499	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：海南万宁\n当事人：李某云\n平台：朋友圈\n言论内容：（视频）新型冠状病毒感染肺炎疫情致大茂镇一人死亡\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日、罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:30.459113+12
1482	1500	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：江西乐安县\n当事人：徐某、张某\n平台：朋友圈\n言论内容：乐安县金域龙城两人感染新型冠状病毒肺炎……\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:30.506489+12
1483	1501	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：河北沽源县\n当事人：孟某\n平台：朋友圈\n言论内容：某小区楼内，武汉学生发烧入院；\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:30.552013+12
1484	1502	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：重庆\n当事人：秦某\n平台：网络\n言论内容：禁止各类整酒，禁止串门，所有景点景区一律关闭，市属所有客运班车、公交车、出租车一律暂时停运……\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:30.596543+12
1485	1503	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：新疆和颐县\n当事人：马某\n平台：网络\n言论内容：目前焉耆县已经有2人已被传染\n背景事件：武汉新型冠状病毒肺炎\n处罚：“依法处理”	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:30.642892+12
1486	1504	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：山西太原\n当事人：田某\n平台：网络\n言论内容：太原市将实施交通管制\n背景事件：武汉新型冠状病毒肺炎\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:30.688654+12
1487	1505	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：四川大竹县\n当事人：徐某\n平台：网络\n言论内容：（私发给胡某）伪造大竹县人民医院新型冠状病毒感染肺炎诊断书照片\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:30.73723+12
1488	1506	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：广东蕉岭县\n当事人：林某玉\n平台：网络\n言论内容：蕉岭确诊新型冠状病毒感染两例\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留6日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:30.781848+12
1489	1507	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：广东蕉岭县\n当事人：徐某平\n平台：网络\n言论内容：（视频）蕉岭确诊新型冠状病毒感染两例\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:30.827208+12
1490	1508	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：辽宁沈阳\n当事人：汤某\n平台：网络\n言论内容：沈阳将封城\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:30.873893+12
1491	1509	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：广东遂溪县\n当事人：尤某\n平台：网络\n言论内容：70000名武汉人已到达湛江躲避新型冠状病毒，且北坡镇车塘村有人感染，已被送往医院治疗\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:30.920691+12
1492	1510	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：广东遂溪县\n当事人：叶某\n平台：网络\n言论内容：70000名武汉人已到达湛江躲避新型冠状病毒，且北坡镇车塘村有人感染，已被送往医院治疗\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:30.969223+12
1493	1511	【中国文字狱事件记录】\n日期：2020年01月26日\n地点：河北石家庄\n当事人：陈某\n平台：贴吧\n言论内容：石家庄谈固有一死亡病例\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:31.013112+12
1494	1512	【中国文字狱事件记录】\n日期：2020年01月27日\n地点：河北井陉县\n当事人：陈某\n平台：QQ群\n言论内容：河北已感染病毒313人、死亡26人\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:31.058948+12
1495	1513	【中国文字狱事件记录】\n日期：2020年01月27日\n地点：河北武安市\n当事人：赵某\n平台：QQ群\n言论内容：武安市矿山镇发现两例新型冠状病毒\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:31.105797+12
1496	1514	【中国文字狱事件记录】\n日期：2020年01月27日\n地点：河北石家庄\n当事人：陈某\n平台：QQ群\n言论内容：河北感染病毒313人，死亡26人\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:31.153172+12
1497	1515	【中国文字狱事件记录】\n日期：2020年01月27日\n地点：甘肃庆阳\n当事人：张某\n平台：微信\n言论内容：经上级批示，我区政府决定明早4一10点飞机空中洒消毒液，为了市民身体安全，不要出门，有出进传染疫情的，8一15年有期徒刑\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:31.200263+12
1498	1516	【中国文字狱事件记录】\n日期：2020年01月27日\n地点：江苏徐州\n当事人：韩某\n平台：微信群\n言论内容：宁愿看到疫情扩散，死上千人，也不愿看到科比离开世上的消息\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:31.249811+12
1499	1517	【中国文字狱事件记录】\n日期：2020年01月27日\n地点：河北易县\n当事人：田某\n平台：微信群\n言论内容：翟家左村，他们村从湖北回来24人，现已确诊超过24例新型肺炎\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:31.296468+12
1500	1518	【中国文字狱事件记录】\n日期：2020年01月27日\n地点：广西苍梧县\n当事人：袁某杰\n平台：微信群\n言论内容：狮寨竹楼高佬两录仔中招了；已隔离出龙圩；怕啵\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:31.341387+12
1501	1519	【中国文字狱事件记录】\n日期：2020年01月27日\n地点：山东冠县\n当事人：不详（高中生）\n平台：微信群\n言论内容：（图片）冠县人民医院新型冠状病毒疫情实时通报，确诊病例1例 疑似病例0例\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:31.388942+12
1502	1520	【中国文字狱事件记录】\n日期：2020年01月27日\n地点：山东临清\n当事人：杨某\n平台：微信群\n言论内容：冠新型肺炎山东感染者已到达潘庄镇!已确诊一例\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:31.435948+12
1503	1521	【中国文字狱事件记录】\n日期：2020年01月27日\n地点：山东临清\n当事人：都某\n平台：微信群\n言论内容：（转发）冠新型肺炎山东感染者已到达潘庄镇!已确诊一例\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:31.482636+12
1504	1522	【中国文字狱事件记录】\n日期：2020年01月27日\n地点：宁夏吴忠\n当事人：王某\n平台：微信群\n言论内容：我是一名17岁的高中生，现在得了武汉肺炎，想在死之前看一下活生生的奶子\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:31.529784+12
1505	1523	【中国文字狱事件记录】\n日期：2020年01月27日\n地点：陕西定边县\n当事人：石某\n平台：微信群\n言论内容：白泥井镇向阳村发现一例确诊肺炎患者，全村已封锁消息，请做好防护\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:31.576415+12
1506	1524	【中国文字狱事件记录】\n日期：2020年01月27日\n地点：陕西清涧县\n当事人：白某\n平台：微信群\n言论内容：（转发）新城小区7号楼刚隔离一个从武汉回来的学生，发烧五天\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:31.622946+12
1507	1525	【中国文字狱事件记录】\n日期：2020年01月27日\n地点：新疆塔城县\n当事人：王某\n平台：微信群\n言论内容：乌鲁木齐现在是疫区，这次真的不是新闻看的那么简单，是瘟疫，全国实际死亡人数是X万。\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:31.669102+12
1508	1526	【中国文字狱事件记录】\n日期：2020年01月27日\n地点：新疆伊犁\n当事人：顾某\n平台：微信群\n言论内容：我表弟说武汉的情况比报道要严重X倍，医院没有物资救治，武汉医院排队的人太多了，医生直接都不收了。\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:31.713995+12
1509	1527	【中国文字狱事件记录】\n日期：2020年01月27日\n地点：甘肃文县\n当事人：张某\n平台：微信群\n言论内容：听说中寨镇发现一疑似病例前往县医院检查\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:31.759587+12
1510	1528	【中国文字狱事件记录】\n日期：2020年01月27日\n地点：福建泉州\n当事人：连某英\n平台：微信群\n言论内容：泉港区已经确诊一例：郭某，峰尾某某村；整个泉港区进入一级防备（警方称其还在观察期，尚未确诊）\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:31.80821+12
1511	1529	【中国文字狱事件记录】\n日期：2020年01月27日\n地点：福建南安\n当事人：洪某全\n平台：微信群\n言论内容：下午接到经兜村通知，发现经兜村有4例新型冠状病毒性肺炎，其中三例确诊，一例疑似\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:31.853173+12
1512	1530	【中国文字狱事件记录】\n日期：2020年01月27日\n地点：江西余干县\n当事人：陈某华\n平台：微信群\n言论内容：余干县听说死了3个人，武汉有20多万人得了这种病\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:31.901835+12
1513	1531	【中国文字狱事件记录】\n日期：2020年01月27日\n地点：江西崇义县\n当事人：吴某\n平台：微信群\n言论内容：大家告诉家里人，外出千万不要收现金，当地已经在多批次人民币表面监测新型冠状病毒病原体\n背景事件：武汉新型冠状病毒肺炎\n处罚：治安拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:31.947775+12
1514	1532	【中国文字狱事件记录】\n日期：2020年01月27日\n地点：江西乐安县\n当事人：罗某\n平台：微信群\n言论内容：不要出门, 乐安出现一个, 我一个朋友在武汉, 其实武汉感染了10万人, 死了几千个。政府隐瞒了\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:31.994305+12
1515	1533	【中国文字狱事件记录】\n日期：2020年01月27日\n地点：甘肃华亭县\n当事人：张某\n平台：微信群\n言论内容：（转发）上关镇出现一例新冠病毒\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:32.038546+12
1516	1534	【中国文字狱事件记录】\n日期：2020年01月27日\n地点：广东高州\n当事人：吕某\n平台：微信群\n言论内容：高州将封城三个月，大家快去买米\n背景事件：武汉新型冠状病毒肺炎\n处罚：”依法拘留“	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:32.083812+12
1517	1535	【中国文字狱事件记录】\n日期：2020年01月27日\n地点：四川广安\n当事人：罗某\n平台：微信群\n言论内容：昨天晚上曹家沟死了4个人了，公安局都来人了，这回这个事情很严重，说是武汉的车子，呼吁大家出门一定戴口罩\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:32.132825+12
1518	1536	【中国文字狱事件记录】\n日期：2020年01月27日\n地点：四川广安\n当事人：沈某\n平台：微信群\n言论内容：XX小区XX号楼刚隔离一个从从武汉回来的学生，发烧5天昨天晚上八点多拉走的\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:32.180383+12
1519	1537	【中国文字狱事件记录】\n日期：2020年01月27日\n地点：山西方山县\n当事人：杨某\n平台：微信群\n言论内容：山西确诊500左右，估计会封城\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:32.226813+12
1520	1538	【中国文字狱事件记录】\n日期：2020年01月27日\n地点：四川达州\n当事人：李某\n平台：微信群\n言论内容：达川区麻柳镇一家三口被确诊感染新冠病毒肺炎\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:32.273505+12
1521	1539	【中国文字狱事件记录】\n日期：2020年01月27日\n地点：河南商丘\n当事人：蔡某\n平台：微信群\n言论内容：今天下午商丘交通广播1007说，火车站有一名偷跑回来的病毒携带者，已接触50人以上。邻居们出门注意啦\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:32.320068+12
1522	1540	【中国文字狱事件记录】\n日期：2020年01月27日\n地点：河南永城\n当事人：曲某\n平台：微信群\n言论内容：永城已有一例感染新型冠状病毒肺炎患者刘某某确认死亡\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:32.364893+12
1523	1541	【中国文字狱事件记录】\n日期：2020年01月27日\n地点：山西朔州\n当事人：吕某\n平台：微信群\n言论内容：我这几天翻墙出去看推特，好多武汉的视频说政府不作为\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:32.409959+12
1524	1542	【中国文字狱事件记录】\n日期：2020年01月27日\n地点：山西应县\n当事人：杨某\n平台：微信群\n言论内容：今天上报山西一共发现九例，结果应县都这么多了，感觉国家在瞒报情况\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:32.457307+12
1525	1543	【中国文字狱事件记录】\n日期：2020年01月27日\n地点：山西朔州\n当事人：殷某\n平台：微信群\n言论内容：庄头有从武汉回来的死了（语音）\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:32.507875+12
1526	1544	【中国文字狱事件记录】\n日期：2020年01月27日\n地点：广东湛江\n当事人：余某（护士）\n平台：微信群\n言论内容：东山街道调逻村有2人感染到新型冠状病毒，已被东山街道某医院（其自己工作的医院）隔离\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:32.555381+12
1527	1545	【中国文字狱事件记录】\n日期：2020年01月27日\n地点：河北平泉市\n当事人：不详\n平台：微信群\n言论内容：武汉市已经死亡超过1万人了，估计已经有10万人感染\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:32.599563+12
1528	1546	【中国文字狱事件记录】\n日期：2020年01月27日\n地点：黑龙江大庆\n当事人：潘某\n平台：微信群\n言论内容：有一个孩子从武汉回到大庆，已高烧10多天，并且这个孩子过年期间一直与家里10余人聚集在一起\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:32.644986+12
1529	1547	【中国文字狱事件记录】\n日期：2020年01月27日\n地点：湖南双峰县\n当事人：李某\n平台：微信群\n言论内容：全组同胞注意，刚刚得到消息，印泉榨油的谢某的儿子己感染，被娄底防疫部门接走，大家外出一定小心\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:32.68992+12
1530	1548	【中国文字狱事件记录】\n日期：2020年01月27日\n地点：四川汉源县\n当事人：李某\n平台：微信群\n言论内容：汉源一中发现病例，已被中医院隔离，萝卜岗今天一家三口已被县医院隔离，病毒已传到汉源\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:32.737623+12
1531	1549	【中国文字狱事件记录】\n日期：2020年01月27日\n地点：吉林梅河口\n当事人：张某瑜\n平台：微博\n言论内容：最新疫情地图，长春昨天已经死了一个，7岁小女孩，没有药治\n背景事件：武汉新型冠状病毒肺炎\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:32.784638+12
1532	1550	【中国文字狱事件记录】\n日期：2020年01月27日\n地点：河北涿州\n当事人：尚某\n平台：微博\n言论内容：真心觉得瞒报了，离我们村子二十公里的一个村子，听说30晚上发生一例确诊，昨天听说已经6例了，然后都没有报道\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:32.830776+12
1533	1551	【中国文字狱事件记录】\n日期：2020年01月27日\n地点：河南新密市\n当事人：张某\n平台：微博\n言论内容：春节假期延长至2月2日##郑州[地点]#【郑州市新密县多所高校提前开学】不知道河南省郑州市的一个小县城新密县是怎么想的!孩子的成绩比命还重要吗?\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:32.876719+12
1534	1552	【中国文字狱事件记录】\n日期：2020年01月27日\n地点：山东嘉祥县\n当事人：李玉交\n平台：微博\n言论内容：指控当地刑警队大队队长包庇黑恶势力，称其是公安队武里的冠状病毒；比今年的病毒还可怕\n处罚：拘留7日\n法律文书：嘉公（仲）行罚决字〔2020〕128号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:32.923082+12
1802	1820	【中国文字狱事件记录】\n日期：2020年02月16日\n地点：黑龙江双鸭山\n当事人：吴某\n平台：微信群\n言论内容：“辱骂警察”\n处罚：拘留15日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:47.412539+12
1535	1553	【中国文字狱事件记录】\n日期：2020年01月27日\n地点：江西鄱阳县\n当事人：方某\n平台：朋友圈\n言论内容：凰岗培里村已发现两个病毒感染者；南昌河西那边的一定要注意，戴口罩，勤洗手\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:32.969232+12
1536	1554	【中国文字狱事件记录】\n日期：2020年01月27日\n地点：江西鄱阳县\n当事人：方某\n平台：朋友圈\n言论内容：某村有两个从湖北返乡人员感染了新型冠状病毒，已被送去南昌治疗\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:33.012956+12
1537	1555	【中国文字狱事件记录】\n日期：2020年01月27日\n地点：江西永新县\n当事人：马某\n平台：朋友圈\n言论内容：龙门刘下喔一从武汉回来的老师因新型冠状病毒死亡的信息\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:33.060127+12
1538	1556	【中国文字狱事件记录】\n日期：2020年01月27日\n地点：江西铅山县\n当事人：祝某\n平台：朋友圈\n言论内容：《紧急通知》\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:33.10564+12
1539	1557	【中国文字狱事件记录】\n日期：2020年01月27日\n地点：辽宁大连\n当事人：孟某\n平台：朋友圈\n言论内容：刘家桥和周水子一带那里已出事了，大连市卫生局已派人员把整个出事的楼进行消毒，武汉回大连的孙某已经死亡，家属发病也住院了\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:33.153616+12
1540	1558	【中国文字狱事件记录】\n日期：2020年01月27日\n地点：江苏扬州\n当事人：万某\n平台：朋友圈\n言论内容：西区大润发已有一名男子倒下，在场所有围观群众都带去检查了……\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:33.199425+12
1541	1559	【中国文字狱事件记录】\n日期：2020年01月27日\n地点：贵州铜仁\n当事人：不详\n平台：朋友圈\n言论内容：不当言论\n背景事件：武汉新型冠状病毒肺炎\n处罚：不详	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:33.253931+12
1542	1560	【中国文字狱事件记录】\n日期：2020年01月27日\n地点：贵州台江县\n当事人：王某\n平台：朋友圈\n言论内容：台江封城，物价上涨\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:33.302019+12
1543	1561	【中国文字狱事件记录】\n日期：2020年01月27日\n地点：新疆库尔勒\n当事人：代某\n平台：网络\n言论内容：今天州医院跑了一个疑似被感染的人\n背景事件：武汉新型冠状病毒肺炎\n处罚：“依法处理”	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:33.347524+12
1544	1562	【中国文字狱事件记录】\n日期：2020年01月27日\n地点：广西横县\n当事人：余某\n平台：网络\n言论内容：（视频）峦城镇某村有4名武汉回来的务工人员，其中一名已经感染了新型冠状病毒\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:33.393848+12
1545	1563	【中国文字狱事件记录】\n日期：2020年01月27日\n地点：贵州碧江县\n当事人：孙某\n平台：网络\n言论内容：（视频）铜仁都死完了，这种感觉真好\n背景事件：武汉新型冠状病毒肺炎\n处罚：抓获，后续未知	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:33.439376+12
1546	1564	【中国文字狱事件记录】\n日期：2020年01月27日\n地点：江苏盐城\n当事人：韦某\n平台：网络\n言论内容：1月27日0时起市区出租车一律停止运营\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:33.486433+12
1547	1565	【中国文字狱事件记录】\n日期：2020年01月27日\n地点：广东五华县\n当事人：叶某华\n平台：网络（私发）\n言论内容：华城环城街封路，有一个从武汉回来的大学生犯病了\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日、罚款300元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:33.530356+12
1548	1566	【中国文字狱事件记录】\n日期：2020年01月27日\n地点：河北晋州\n当事人：李某\n平台：贴吧\n言论内容：晋州市紧急会议通知，因新型冠状病毒防治工作需要，全县各村封村\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:33.574845+12
1549	1567	【中国文字狱事件记录】\n日期：2020年01月27日\n地点：陕西安康\n当事人：李某\n平台：微信群\n言论内容：“涉疫不实信息”\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:33.619503+12
1550	1568	【中国文字狱事件记录】\n日期：2020年01月27日\n地点：江西万年县\n当事人：虞某\n平台：微信群\n言论内容：接上级电话通知……万年已有一例新型肺炎死亡病例，明日起训练场暂停培训\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:33.668077+12
1551	1569	【中国文字狱事件记录】\n日期：2020年01月28日\n地点：河南新县\n当事人：陈某\n平台：微信群\n言论内容：沙窝镇因冠状病毒死了一人，沙窝街道已封锁，千万不要去沙窝了\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:33.712479+12
1552	1570	【中国文字狱事件记录】\n日期：2020年01月28日\n地点：江苏启东\n当事人：施某\n平台：微信群\n言论内容：为了不让冠状病毒扩散，启东市区以及各乡镇的所有超市将于29日停止营业！\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:33.758028+12
1553	1571	【中国文字狱事件记录】\n日期：2020年01月28日\n地点：江苏宿迁\n当事人：李某\n平台：微信群\n言论内容：现在XX人把野生动物和其它肉混在一起卖，大家都小心警惕肉已经经过货运运不同的城市了\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:33.805103+12
1554	1572	【中国文字狱事件记录】\n日期：2020年01月28日\n地点：安徽含山县\n当事人：汤某、蒋某\n平台：微信群\n言论内容：最新消息，和少牛（注：仙踪镇的一个自然村）确诊一例”“所有去他家拜年的，全部隔离\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:33.851261+12
1555	1573	【中国文字狱事件记录】\n日期：2020年01月28日\n地点：黑龙江牡丹江\n当事人：王某山\n平台：微信群\n言论内容：牡丹江地区一车牌号浙BL0535，这个车刚从武汉回来，车上的人确诊了偷跑回来的，大家看到了及时报警...\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:33.895861+12
1556	1574	【中国文字狱事件记录】\n日期：2020年01月28日\n地点：江苏苏州\n当事人：徐某\n平台：微信群\n言论内容：“关于疫情防控的不实视频”\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:33.940418+12
1557	1575	【中国文字狱事件记录】\n日期：2020年01月28日\n地点：江西铅山县\n当事人：余某\n平台：微信群\n言论内容：隔壁镇的一个返乡和尚死亡，死前举办过法会，一大堆人在一起吃饭\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:33.986343+12
1558	1576	【中国文字狱事件记录】\n日期：2020年01月28日\n地点：江西铅山县\n当事人：肖某\n平台：微信群\n言论内容：黄岗山社区徐某与疑似新型冠状病毒感染者直接接触，被卫健委跟踪测量体温\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:34.033706+12
1559	1577	【中国文字狱事件记录】\n日期：2020年01月28日\n地点：陕西乾县\n当事人：杜某\n平台：微信群\n言论内容：乾县太平新村新村宾馆，有乾县五人从武汉回来没有回家过年，在宾馆隐藏今天中午病情同时发作发烧，咳嗽。已经隔离，请大家不要到东街来\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日、罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:34.0831+12
1560	1578	【中国文字狱事件记录】\n日期：2020年01月28日\n地点：江苏太仓\n当事人：王某\n平台：微信群\n言论内容：要接21个湖北朋友进住小区\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:34.133322+12
1561	1579	【中国文字狱事件记录】\n日期：2020年01月28日\n地点：陕西渭南\n当事人：陈某\n平台：微信群\n言论内容：双王医院全体被隔离了，官底那个华南海鲜市场回来的，有亲戚在双王医院上班，过年出门了，所以，全院包括院长已经被隔离了。大家尽最大可能，在家待着\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:34.18232+12
1562	1580	【中国文字狱事件记录】\n日期：2020年01月28日\n地点：广东汕尾\n当事人：许某儒、许某\n平台：微信群\n言论内容：汕尾首例确诊新型冠状病毒肺炎患者是湖尾村村民谢某，湖尾村全村村民已被隔离\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:34.234481+12
1563	1581	【中国文字狱事件记录】\n日期：2020年01月28日\n地点：河北保定\n当事人：高某\n平台：微信群\n言论内容：我是武汉回来的；我那个同伴呢？我睡醒了，还去物业找麻烦不\n背景事件：武汉新型冠状病毒肺炎\n处罚：罚款100元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:34.287642+12
1564	1582	【中国文字狱事件记录】\n日期：2020年01月28日\n地点：贵州贵阳\n当事人：唐某\n平台：微信群\n言论内容：凯里才公布发现了300名疑似新型冠状病毒肺炎在贵州医院被隔离了\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政罚款	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:34.333046+12
1565	1583	【中国文字狱事件记录】\n日期：2020年01月28日\n地点：贵州黄平县\n当事人：潘某\n平台：微信群\n言论内容：我刚从武汉回来，已经感染了新型冠状病毒引起的肺炎，我要传染给你们，我还要上贵阳去传染给更多的人！\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:34.378592+12
1566	1584	【中国文字狱事件记录】\n日期：2020年01月28日\n地点：河南潢川县\n当事人：何某\n平台：微信群\n言论内容：“与疫情相关不实信息”\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:34.42553+12
1567	1585	【中国文字狱事件记录】\n日期：2020年01月28日\n地点：四川达州\n当事人：黄某\n平台：微信群\n言论内容：（视频）黄都街上又感染了一个，马上拉起走了！\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:34.470705+12
1568	1586	【中国文字狱事件记录】\n日期：2020年01月28日\n地点：河北正定县\n当事人：樊某\n平台：微信群\n言论内容：“涉政不当言论”\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:34.515861+12
1569	1587	【中国文字狱事件记录】\n日期：2020年01月28日\n地点：河北石家庄\n当事人：马某\n平台：微信群\n言论内容：发现紫御澜湾有确诊冠状病毒新型肺炎患者\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:34.561551+12
1570	1588	【中国文字狱事件记录】\n日期：2020年01月28日\n地点：四川大英县\n当事人：唐某\n平台：微博\n言论内容：新城小区7号楼刚隔离一个从武汉回来的学生，发烧五天\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:34.608357+12
1571	1589	【中国文字狱事件记录】\n日期：2020年01月28日\n地点：四川大英县\n当事人：曹某\n平台：微博\n言论内容：新城小区7号楼刚隔离一个从武汉回来的学生，发烧五天\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:34.654651+12
1572	1590	【中国文字狱事件记录】\n日期：2020年01月28日\n地点：河北保定\n当事人：魏某\n平台：快手、微信\n言论内容：“辱骂村干部”\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留4日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:34.700501+12
1573	1591	【中国文字狱事件记录】\n日期：2020年01月28日\n地点：海南澄迈县\n当事人：龙某\n平台：抖音\n言论内容：（视频）使用山柚油和绿茶可以治疗新型冠状肺炎\n背景事件：武汉新型冠状病毒肺炎\n处罚：罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:34.744592+12
1574	1592	【中国文字狱事件记录】\n日期：2020年01月28日\n地点：吉林德惠\n当事人：赵某、郭某\n平台：朋友圈\n言论内容：从1月26日起，德惠喜事丧事停办，不准聚餐\n背景事件：武汉新型冠状病毒肺炎\n处罚：治安处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:34.790189+12
1575	1593	【中国文字狱事件记录】\n日期：2020年01月28日\n地点：江西抚州\n当事人：徐某\n平台：朋友圈\n言论内容：一张全国各地疫情人员数量的图片，图片显示的确诊人数为虚假数字\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:34.836405+12
1576	1594	【中国文字狱事件记录】\n日期：2020年01月28日\n地点：黑龙江牡丹江\n当事人：孟某某\n平台：朋友圈\n言论内容：宁安某超市导购员女儿从武汉放假回来，发热传染给导购员，现在已经封闭，疫情比想象中严重，疫情蔓延严重\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:34.881284+12
1577	1595	【中国文字狱事件记录】\n日期：2020年01月28日\n地点：贵州兴义市\n当事人：车某\n平台：朋友圈\n言论内容：明天开始不准杀猪杀牛出售\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:34.92935+12
1578	1596	【中国文字狱事件记录】\n日期：2020年01月28日\n地点：贵州兴义市\n当事人：刘某\n平台：朋友圈\n言论内容：刚刚从武汉回来，可能要克窜哈门，看见我朋友圈的每人给我转500，不然我要克你家坐起咳\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:34.976372+12
1579	1597	【中国文字狱事件记录】\n日期：2020年01月28日\n地点：云南曲靖\n当事人：严某\n平台：朋友圈\n言论内容：曲靖人死了吗？整个地方就我一家人出来，我是有病，还是曲靖人太有病？\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:35.023809+12
1581	1599	【中国文字狱事件记录】\n日期：2020年01月28日\n地点：广西柳州\n当事人：罗某\n平台：网络\n言论内容：（视频）有人被抢救了，你看医生跑得很快，有人感染了\n背景事件：武汉新型冠状病毒肺炎\n处罚：罚款200元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:35.116605+12
1582	1600	【中国文字狱事件记录】\n日期：2020年01月28日\n地点：新疆北屯\n当事人：张某\n平台：网络\n言论内容：北屯有3个武汉大学生得了新型冠状肺炎，在北屯医院待着呢\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:35.163935+12
1583	1601	【中国文字狱事件记录】\n日期：2020年01月28日\n地点：新疆北屯\n当事人：胡某\n平台：网络\n言论内容：明天早上四点半不要出门，因为政府安排飞机洒消毒水，请互相转告\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:35.210729+12
1584	1602	【中国文字狱事件记录】\n日期：2020年01月28日\n地点：新疆北屯\n当事人：胡某\n平台：网络\n言论内容：有一个顾客说他侄子是阿勒泰政府部门工作，昨晚发现阿勒泰出现一例冠状病毒，是出门旅游刚回来的，亲们，出门一定带口罩\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:35.270957+12
1585	1603	【中国文字狱事件记录】\n日期：2020年01月28日\n地点：福建安溪县\n当事人：吴某飞\n平台：网络\n言论内容：前几天从武汉小路跑出来，武汉已经断药了，不出来也没药吃啊。网上说偷跑出来要判刑怎么办？\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:35.320224+12
1586	1604	【中国文字狱事件记录】\n日期：2020年01月28日\n地点：湖南冷水江\n当事人：欧某、段某、范某、周某\n平台：聊天群与微博\n言论内容：（发布与转发）冷水江市三尖镇刘某某因感染新型冠状病毒已死亡\n背景事件：武汉新型冠状病毒肺炎\n处罚：“依法处理”	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:35.365199+12
1587	1605	【中国文字狱事件记录】\n日期：2020年01月28日\n地点：陕西安康\n当事人：米某\n平台：微信群\n言论内容：（其自己拍摄的涉疫视频，内容不详）\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:35.410977+12
1588	1606	【中国文字狱事件记录】\n日期：2020年01月28日\n地点：陕西安康\n当事人：张某\n平台：朋友圈\n言论内容：“涉疫不实信息”\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:35.456716+12
1589	1607	【中国文字狱事件记录】\n日期：2020年01月29日\n地点：广东汕头\n当事人：庄某、张某、何某\n平台：微信群\n言论内容：汕头澄海区一名感染了新型冠状病毒的人逃跑\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:35.506992+12
1590	1608	【中国文字狱事件记录】\n日期：2020年01月29日\n地点：广东电白\n当事人：黄某\n平台：微信群\n言论内容：吴某江（确诊患者）和朋友聚会的集体照\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:35.594647+12
1591	1609	【中国文字狱事件记录】\n日期：2020年01月29日\n地点：陕西子洲县\n当事人：安某\n平台：微信群\n言论内容：子洲有两例已经确诊……\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:35.643794+12
1592	1610	【中国文字狱事件记录】\n日期：2020年01月29日\n地点：陕西子洲县\n当事人：马某\n平台：微信群\n言论内容：（转发）子洲有两例已经确诊……\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:35.688518+12
1593	1611	【中国文字狱事件记录】\n日期：2020年01月29日\n地点：江西黎川县\n当事人：吴某\n平台：微信群\n言论内容：黎川县政府准备将数百名新型冠状病毒疑似病人放在德胜镇老中学改建的无任何医疗设施的宾馆内隔离\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:35.73681+12
1594	1612	【中国文字狱事件记录】\n日期：2020年01月29日\n地点：江西乐安县\n当事人：游某\n平台：微信群\n言论内容：乐安县增田今天确认一个感染者，还请了六十桌客\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:35.78717+12
1595	1613	【中国文字狱事件记录】\n日期：2020年01月29日\n地点：浙江义乌\n当事人：楼某\n平台：微信群\n言论内容：城西街道被盯牢，已经有四五十个确诊病例\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:35.840741+12
1596	1614	【中国文字狱事件记录】\n日期：2020年01月29日\n地点：广东电白县\n当事人：陈某\n平台：微信群\n言论内容：南海虎头山村吴姓二人已确为病例，今天又发现南海晏镜村二人与吴姓同车回来的也已经确定病例，希望各校区认真做好防范工作\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:35.898+12
1597	1615	【中国文字狱事件记录】\n日期：2020年01月29日\n地点：海南澄迈县\n当事人：廖某1\n平台：微信群\n言论内容：澄迈县桥头镇有一例感染新型冠状肺炎，且桥头镇已封村\n背景事件：武汉新型冠状病毒肺炎\n处罚：罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:35.948689+12
1598	1616	【中国文字狱事件记录】\n日期：2020年01月29日\n地点：海南澄迈县\n当事人：廖某2\n平台：微信群\n言论内容：（视频）澄迈县桥头镇有一例感染新型冠状肺炎，且桥头镇已封村\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:36.002982+12
1599	1617	【中国文字狱事件记录】\n日期：2020年01月29日\n地点：湖南衡阳县\n当事人：林某\n平台：微信群\n言论内容：在库宗街上信用社附近一叫王某的媳妇在武汉有一个闺蜜，这个闺蜜先被确诊感染病毒，还称王某媳妇之前与此闺蜜有接触，叫大家注意\n背景事件：武汉新型冠状病毒肺炎\n处罚：罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:36.055502+12
1600	1618	【中国文字狱事件记录】\n日期：2020年01月29日\n地点：湖南衡阳县\n当事人：蒋某\n平台：微信群\n言论内容：（转发）在库宗街上信用社附近一叫王某的媳妇在武汉有一个闺蜜，这个闺蜜先被确诊感染病毒，还称王某媳妇之前与此闺蜜有接触，叫大家注意\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:36.112243+12
1601	1619	【中国文字狱事件记录】\n日期：2020年01月29日\n地点：新疆阿克苏\n当事人：康某\n平台：微信群\n言论内容：阿克苏已经确诊了X例，昨天一趟来阿克苏的飞机上就发现X个发烧的\n背景事件：武汉新型冠状病毒肺炎\n处罚：罚款400元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:36.173712+12
1602	1620	【中国文字狱事件记录】\n日期：2020年01月29日\n地点：河北石家庄\n当事人：李某\n平台：微信群\n言论内容：“疫情虚假信息”\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:36.229536+12
1603	1621	【中国文字狱事件记录】\n日期：2020年01月29日\n地点：安徽凤台县\n当事人：吴某\n平台：微博\n言论内容：这个数据不准确，我在淮南凤台县，光知道的就已经有三个，还有个已经去世了\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:36.287506+12
1604	1622	【中国文字狱事件记录】\n日期：2020年01月29日\n地点：陕西榆林\n当事人：原建猛（记者）\n平台：微博、新浪博客\n言论内容：转发《“大刀队”横行乡里，区委王效力真的为民效力了吗？》\n处罚：拘留8日\n法律文书：横公（网安）行罚决字〔2019〕67号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:36.339644+12
1605	1623	【中国文字狱事件记录】\n日期：2020年01月29日\n地点：黑龙江兰西县\n当事人：王某\n平台：抖音\n言论内容：（视频）返乡人员于某四肢无力，脸红脖子粗，身体无劲儿，报告卫生机关不管\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:36.391514+12
1606	1624	【中国文字狱事件记录】\n日期：2020年01月29日\n地点：广西百色\n当事人：李某\n平台：朋友圈\n言论内容：越来越多的湖北人来百色\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:36.439486+12
1607	1625	【中国文字狱事件记录】\n日期：2020年01月29日\n地点：四川达州\n当事人：夏某\n平台：现实/口述\n言论内容：自己刚从武汉回来，目前正高烧至39度，怀疑可能感染上了新型冠状病毒\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:36.488399+12
1608	1626	【中国文字狱事件记录】\n日期：2020年01月29日\n地点：黑龙江齐齐哈尔\n当事人：李某\n平台：网络\n言论内容：疫情相关的网络谣言\n背景事件：武汉新型冠状病毒肺炎\n处罚：刑事强制措施	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:36.539463+12
1609	1627	【中国文字狱事件记录】\n日期：2020年01月30日\n地点：福建惠安县\n当事人：陈某\n平台：微信群\n言论内容：武汉死了两万人将近，可是新闻却只对外公布说死了几千人而已，只是为了安抚民心，我叔公就是在武汉上班\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:36.59448+12
1610	1628	【中国文字狱事件记录】\n日期：2020年01月30日\n地点：贵州仁怀市\n当事人：向某\n平台：微信群\n言论内容：大家不要出门了哦，双龙村有一个武汉回来的大学生，与其吃饭的两人，发烧40度。该大学生接触有100多人\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:36.645735+12
1611	1629	【中国文字狱事件记录】\n日期：2020年01月30日\n地点：贵州仁怀市\n当事人：杨某\n平台：微信群\n言论内容：（转发）大家不要出门了哦，双龙村有一个武汉回来的大学生，与其吃饭的两人，发烧40度。该大学生接触有100多人\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:36.695239+12
1612	1630	【中国文字狱事件记录】\n日期：2020年01月30日\n地点：山东菏泽\n当事人：孟某菊\n平台：微信群\n言论内容：她们说的医院的人说的，陈集死人的是真的\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:36.747596+12
1613	1631	【中国文字狱事件记录】\n日期：2020年01月30日\n地点：山东菏泽\n当事人：贾某云\n平台：微信群\n言论内容：尽量别出门，菏泽死了5个啦\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:36.798368+12
1614	1632	【中国文字狱事件记录】\n日期：2020年01月30日\n地点：江西修水县\n当事人：熊某\n平台：微信群\n言论内容：我们这边好像死了4个；江西目前至少死了10个；那又怎么样？群封了那就再建一个\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:36.849982+12
1615	1633	【中国文字狱事件记录】\n日期：2020年01月30日\n地点：广东电白县\n当事人：陈某茵\n平台：微信群\n言论内容：茂名电白的这两例冠状肺炎病毒患者，年二十七八回到霞里，去过斜阳美食城、去过汇景、去过霞里菜市场买菜、去过打牌，提醒大家注意防范\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:36.909098+12
1616	1634	【中国文字狱事件记录】\n日期：2020年01月30日\n地点：广东电白县\n当事人：林某燕\n平台：微信群\n言论内容：各位亲戚们非常时期一定要宅在家里，岭门已经死亡一例了，死者是岭门河头村从武汉回来的\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:36.964049+12
1617	1635	【中国文字狱事件记录】\n日期：2020年01月30日\n地点：陕西镇安县\n当事人：刘某\n平台：微信群\n言论内容：铁厂都死六个人了；死了好像不管我的事，多死一些就平常了；市封了、商场封了、乡村封了、道路封了，我也疯了\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日，罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:37.017054+12
1618	1636	【中国文字狱事件记录】\n日期：2020年01月30日\n地点：湖南新邵县\n当事人：刘某云\n平台：微信群\n言论内容：（视频）武汉回来一个人，感染全家人；新邵县雀塘黄泥塘村陈某女婿（从武汉回来的），初二到黄泥塘院子里拜年，今天确诊为新型肺炎\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:37.074858+12
1619	1637	【中国文字狱事件记录】\n日期：2020年01月30日\n地点：广东梅州\n当事人：“越健~郭某锌”\n平台：微信群\n言论内容：（视频）出深圳了，看我能得肺病么，得到肺病就传染给你们，我回来，你们要看稳来哟\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:37.129412+12
1620	1638	【中国文字狱事件记录】\n日期：2020年01月30日\n地点：贵州镇远县\n当事人：肖某\n平台：微信群\n言论内容：大家外出小心，我朋友做医疗器械的，在贵州有项目，据他说贵州可能隐瞒了疫情，镇远县有两个确诊了，但是没上报……\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:37.184931+12
1621	1639	【中国文字狱事件记录】\n日期：2020年01月30日\n地点：河北邱县\n当事人：马某A\n平台：微信群\n言论内容：陈村已确诊一例患者\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:37.23805+12
1622	1640	【中国文字狱事件记录】\n日期：2020年01月30日\n地点：河北邱县\n当事人：马某B\n平台：微信群\n言论内容：陈村已确诊一例患者\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:37.292589+12
1623	1641	【中国文字狱事件记录】\n日期：2020年01月30日\n地点：河北邱县\n当事人：马某C\n平台：微信群\n言论内容：陈村已确诊一例患者\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:37.352964+12
1624	1642	【中国文字狱事件记录】\n日期：2020年01月30日\n地点：河南商丘\n当事人：曹某华\n平台：微信群\n言论内容：“污蔑攻击疫情防控工作负面言论”\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留15日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:37.409152+12
1625	1643	【中国文字狱事件记录】\n日期：2020年01月30日\n地点：河北石家庄\n当事人：王某\n平台：微信群\n言论内容：“疫情虚假信息”\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:37.46624+12
1626	1644	【中国文字狱事件记录】\n日期：2020年01月30日\n地点：江西宁都县\n当事人：叶某俊\n平台：微信群\n言论内容：“有关新型冠状病毒感染的肺炎疫情谣言，指责党和政府对疫情的处置”\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:37.526748+12
1627	1645	【中国文字狱事件记录】\n日期：2020年01月30日\n地点：贵州台江县\n当事人：张某\n平台：微博\n言论内容：（一张白菜售价20元的图片）台江县政府怎么不关注这方面，连超市都想在国难时期发横财。\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:37.584327+12
1628	1646	【中国文字狱事件记录】\n日期：2020年01月30日\n地点：福建泉州\n当事人：黄某\n平台：抖音\n言论内容：（视频）与多名武汉返乡人员聚餐，且大呼“不怕”\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:37.637131+12
1629	1647	【中国文字狱事件记录】\n日期：2020年01月30日\n地点：福建莆田\n当事人：洪某临\n平台：朋友圈\n言论内容：小伙伴们，我从武汉回来了，那几个要喝酒三公的在哪里\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:37.696293+12
1630	1648	【中国文字狱事件记录】\n日期：2020年01月30日\n地点：贵州贵阳\n当事人：项某梅\n平台：网络\n言论内容：遵义余庆死亡一人，清镇华丰市场发现疑似病人，清镇曹家井疑似病人，请各位家人安心在家呆起哈\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:37.75105+12
1631	1649	【中国文字狱事件记录】\n日期：2020年01月30日\n地点：四川广安\n当事人：“小白XXX”\n平台：贴吧\n言论内容：说是武胜明天封城了\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:37.80762+12
1632	1650	【中国文字狱事件记录】\n日期：2020年01月30日\n地点：内蒙古乌兰察布\n当事人：张某\n平台：陌陌\n言论内容：我刚从武汉回到乌兰察布，向附近的人问好\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:37.862844+12
1633	1651	【中国文字狱事件记录】\n日期：2020年01月30日\n地点：河南新安县\n当事人：高某\n平台：朋友圈\n言论内容：刚听说新安县封城了\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:37.922617+12
1634	1652	【中国文字狱事件记录】\n日期：2020年01月31日\n地点：云南洱源县\n当事人：易某、杨某等6人\n平台：微信\n言论内容：关于新型冠状病毒感染肺炎疫情的谣言，谣言内容为一段文字截图\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:37.980052+12
1635	1653	【中国文字狱事件记录】\n日期：2020年01月31日\n地点：海南万宁\n当事人：王某\n平台：微信群\n言论内容：（视频）吴某“辱骂某知名院士”的内容\n处罚：拘留15日、罚款1000元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:38.0391+12
1636	1654	【中国文字狱事件记录】\n日期：2020年01月31日\n地点：山西晋城\n当事人：赵某\n平台：微信群\n言论内容：涉及疫情的虚假言论\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:38.098629+12
1637	1655	【中国文字狱事件记录】\n日期：2020年01月31日\n地点：贵州贵阳\n当事人：王某华\n平台：微信群\n言论内容：官方人员称花果园U区新增3例，请各位邻居注意安全\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:38.157273+12
1638	1656	【中国文字狱事件记录】\n日期：2020年01月31日\n地点：贵州贵阳\n当事人：王某\n平台：微信群\n言论内容：（转发）武汉已经开始追杀流浪狗和猫了；一旦感染就隔离自生自灭，医护人员根本就不够，根本招呼不来\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:38.217062+12
1639	1657	【中国文字狱事件记录】\n日期：2020年01月31日\n地点：贵州贵阳\n当事人：王某兰\n平台：微信群\n言论内容：（视频）金阳世纪城的武汉大学生已经发病，整栋楼隔离，大家注意点\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:38.273941+12
1640	1658	【中国文字狱事件记录】\n日期：2020年01月31日\n地点：山东菏泽\n当事人：寇某洲\n平台：微信群\n言论内容：最新消息，菏泽死7个了\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:38.325279+12
1641	1659	【中国文字狱事件记录】\n日期：2020年01月31日\n地点：广西柳州\n当事人：熊某欢\n平台：微信群\n言论内容：刚刚收到消息，金竺花苑确诊一例感染者，请大家注意\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留4日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:38.377651+12
1642	1660	【中国文字狱事件记录】\n日期：2020年01月31日\n地点：广西灵山县\n当事人：区某\n平台：微信群\n言论内容：旧州镇旧州村委龙尾坝村有人从武汉回来后发热，旧州疫情爆发\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:38.432185+12
1643	1661	【中国文字狱事件记录】\n日期：2020年01月31日\n地点：广西隆林县\n当事人：黄某\n平台：微信群\n言论内容：百色报假的，死人了还天天2例，最少也有十几个了\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:38.486664+12
1644	1662	【中国文字狱事件记录】\n日期：2020年01月31日\n地点：湖南绥宁县\n当事人：张某平\n平台：微信群\n言论内容：绥宁县有15人因感染冠状病在人民医院住院治疗\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:38.546031+12
1645	1663	【中国文字狱事件记录】\n日期：2020年01月31日\n地点：福建福安市\n当事人：兰某\n平台：微信群\n言论内容：潭头镇一从武汉返乡女子，逃避隔离，发病死亡\n背景事件：武汉新型冠状病毒肺炎\n处罚：治安拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:38.599266+12
1646	1664	【中国文字狱事件记录】\n日期：2020年01月31日\n地点：江苏苏州\n当事人：胡某\n平台：微信群\n言论内容：（视频）自己发烧且拒不配合保安检查体温（警方称不实）\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:38.64467+12
2443	2466	【中国文字狱事件记录】\n日期：2022年08月14日\n地点：内蒙古乌海\n当事人：不详\n平台：微信群\n言论内容：“不当言论”\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:20.635485+12
1647	1665	【中国文字狱事件记录】\n日期：2020年01月31日\n地点：北京\n当事人：王某\n平台：微信群\n言论内容：自己感染新冠肺炎，准备传染给他人\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:38.685669+12
1648	1666	【中国文字狱事件记录】\n日期：2020年01月31日\n地点：甘肃镇源显\n当事人：刘某\n平台：微信群\n言论内容：通知：大家注意了，甘M03HQ7这个车昨晚从武汉回来，车上的人确诊了偷跑回来的，武汉警车一直追踪到甘肃附近丢失，大家看到及时报警\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:38.739445+12
1649	1667	【中国文字狱事件记录】\n日期：2020年01月31日\n地点：广西融安县\n当事人：陈某\n平台：微信群\n言论内容：今天板揽马江确诊一例，现在县医院院长和县有关领导一起赶板揽，病人送柳州治疗，我爸喊我们这几天最好不要出门去\n背景事件：武汉新型冠状病毒肺炎\n处罚：罚款200元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:38.795921+12
1650	1668	【中国文字狱事件记录】\n日期：2020年01月31日\n地点：河北邯郸\n当事人：何某\n平台：微信群\n言论内容：（视频）百家乐园出现一例新冠状病毒感染肺炎病例\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:38.852577+12
1651	1669	【中国文字狱事件记录】\n日期：2020年01月31日\n地点：大连市公安局甘井子分局\n当事人：鞠振涛\n身份：警察\n平台：微信群\n言论内容：关于新型冠状病毒的“不当言论”，其中政府对公众隐瞒真相的内容，进而“诋毁政府公信力”\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留7日\n法律文书：大公沙（治）行罚决字[2020]59号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:38.908148+12
1652	1670	【中国文字狱事件记录】\n日期：2020年01月31日\n地点：江西宁都县\n当事人：刘某婷\n平台：微信群\n言论内容：宁都县凤凰城小区发现一例感染者\n背景事件：武汉新型冠状病毒肺炎\n处罚：警告训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:38.963957+12
1653	1671	【中国文字狱事件记录】\n日期：2020年01月31日\n地点：江西宁都县\n当事人：刘某云\n平台：微信群\n言论内容：（转发）宁都县凤凰城小区发现一例感染者\n背景事件：武汉新型冠状病毒肺炎\n处罚：警告训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:39.018754+12
1654	1672	【中国文字狱事件记录】\n日期：2020年01月31日\n地点：江西宁都县\n当事人：刘某\n平台：微信群\n言论内容：（转发）宁都县凤凰城小区发现一例感染者\n背景事件：武汉新型冠状病毒肺炎\n处罚：警告训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:39.074657+12
1655	1673	【中国文字狱事件记录】\n日期：2020年01月31日\n地点：广西隆林县\n当事人：韦某\n平台：微博\n言论内容：百色只有一个吗，为啥听我妈说隆林这里有两个了\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:39.131433+12
1656	1674	【中国文字狱事件记录】\n日期：2020年01月31日\n地点：广西隆林县\n当事人：杨某\n平台：微博\n言论内容：百色只有一个是真实的吗，隆林和田阳都有人被隔离\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:39.189785+12
1657	1675	【中国文字狱事件记录】\n日期：2020年01月31日\n地点：海南万宁\n当事人：吴某\n平台：现实\n言论内容：在与朋友喝酒时“辱骂某知名院士”\n处罚：拘留15日、罚款1000元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:39.247337+12
1658	1676	【中国文字狱事件记录】\n日期：2020年02月01日\n地点：山东菏泽\n当事人：葛某凯\n平台：QQ群\n言论内容：别出门啦,菏泽又死了好几个\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:39.302059+12
1659	1677	【中国文字狱事件记录】\n日期：2020年02月01日\n地点：广西浦北县\n当事人：郑某、卢某\n平台：微信群\n言论内容：”污言秽语、公然挑衅、污浊网络环境的自拍视频“\n处罚：行政处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:39.352909+12
1660	1678	【中国文字狱事件记录】\n日期：2020年02月01日\n地点：云南弥渡县\n当事人：丁某\n平台：微信群\n言论内容：（视频）住着两个武汉人，老板想钱想疯了，公安查房一直隐瞒，现在拉去隔离了\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:39.40398+12
1661	1679	【中国文字狱事件记录】\n日期：2020年02月01日\n地点：江西宜黄县\n当事人：洪某\n平台：微信群\n言论内容：涉疫情不当言论\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:39.458247+12
1662	1680	【中国文字狱事件记录】\n日期：2020年02月01日\n地点：山东菏泽\n当事人：王某国\n平台：微信群\n言论内容：虚假信息\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:39.512577+12
1663	1681	【中国文字狱事件记录】\n日期：2020年02月01日\n地点：安徽宿松县\n当事人：邓某\n平台：微信群\n言论内容：（视频）坝头街上、坝头街上，隔离、隔离查出来了\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:39.56878+12
1664	1682	【中国文字狱事件记录】\n日期：2020年02月01日\n地点：河南巩义市\n当事人：董某\n平台：微信群\n言论内容：巩义胡某在郑州六院已死亡\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:39.622592+12
1665	1683	【中国文字狱事件记录】\n日期：2020年02月01日\n地点：山东沂水县\n当事人：李某\n平台：微信群\n言论内容：沂水县“新型冠状病毒”患者在中心医院死亡\n背景事件：武汉新型冠状病毒肺炎\n处罚：罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:39.677991+12
1666	1684	【中国文字狱事件记录】\n日期：2020年02月01日\n地点：陕西镇安县\n当事人：张某\n平台：微信群\n言论内容：群内的所有兄弟们好在这个非常时期，大家都注意了，在柴坪和木村有一个病毒的人，是......拉回来的，今......已经隔离了，从腊月20回来的亲们，做过......车的人，请都不要见，亲戚都一样，请大家注意了\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:39.731627+12
1667	1685	【中国文字狱事件记录】\n日期：2020年02月01日\n地点：河北遵化市\n当事人：柳某\n平台：微信群\n言论内容：“新型冠状病毒不实信息”\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:39.785321+12
1668	1686	【中国文字狱事件记录】\n日期：2020年02月01日\n地点：河北遵化市\n当事人：王某\n平台：微信群\n言论内容：“新型冠状病毒不实信息”\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:39.845373+12
1669	1687	【中国文字狱事件记录】\n日期：2020年02月01日\n地点：河北遵化市\n当事人：王某俊\n平台：微信群\n言论内容：某企业对冠状病毒感染者未采取措施\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:39.913326+12
1670	1688	【中国文字狱事件记录】\n日期：2020年02月01日\n地点：陕西清涧县\n当事人：刘某\n平台：微信群\n言论内容：（转发）一段落款为榆林市公安局的警情通报，警方称内容为涉及疫情的不当言论\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:39.972469+12
1671	1689	【中国文字狱事件记录】\n日期：2020年02月01日\n地点：广西柳州\n当事人：罗某艳\n平台：微信群\n言论内容：各位家长老师，穿山下街有一个确诊有冠状病毒了，大家出门注意安全，记得戴口罩\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:40.032121+12
1672	1758	【中国文字狱事件记录】\n日期：2020年02月05日\n地点：福建泉州\n当事人：纪某\n平台：微信群\n言论内容：关帝爷出来巡境保佑大家平安了……\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:44.040142+12
1673	1690	【中国文字狱事件记录】\n日期：2020年02月01日\n地点：安徽宿松县\n当事人：孙某（未成年人）\n平台：微博\n言论内容：安徽省安庆市宿松县某高三八班的老师在这紧要关头竟然提前开课！！！太不把党中央放在眼里了\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:40.090113+12
1674	1691	【中国文字狱事件记录】\n日期：2020年02月01日\n地点：江苏苏州\n当事人：商某\n平台：朋友圈\n言论内容：（视频）苏州市高新区某小区一例新型冠状病毒肺炎患者在家死亡并被火化\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:40.151685+12
1675	1692	【中国文字狱事件记录】\n日期：2020年02月01日\n地点：陕西安康\n当事人：张某\n平台：微信群\n言论内容：安康人屁事太多了，应该攻坚克难，做好经济工作，武汉死光都没事，应该多关心安康贪官污吏咋处理，黑社会，地头蛇刻咋打死\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:40.206551+12
1676	1693	【中国文字狱事件记录】\n日期：2020年02月02日\n地点：江西进贤县\n当事人：吴某\n平台：QQ群\n言论内容：某某村感染好几人\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:40.26378+12
1677	1694	【中国文字狱事件记录】\n日期：2020年02月02日\n地点：江苏靖江\n当事人：陈某、高某、包某\n平台：微信\n言论内容：西来郁家村有六十多人感染肺炎并发烧\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:40.317422+12
1678	1695	【中国文字狱事件记录】\n日期：2020年02月02日\n地点：福建泉州\n当事人：王某\n平台：微信群\n言论内容：湖南出现鸡瘟，某村也有一例，某村也有一例病毒感染患者\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:40.371097+12
1679	1696	【中国文字狱事件记录】\n日期：2020年02月02日\n地点：山东菏泽\n当事人：苏某强\n平台：微信群\n言论内容：听说牡丹区河南王，死了四个\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:40.422474+12
1680	1697	【中国文字狱事件记录】\n日期：2020年02月02日\n地点：山东菏泽\n当事人：于某虹\n平台：微信群\n言论内容：谎报并散布有关疫情的虚假谣言\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日、罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:40.506059+12
1681	1698	【中国文字狱事件记录】\n日期：2020年02月02日\n地点：江苏南通\n当事人：王某怡\n平台：微信群\n言论内容：这是集中安置江苏的病例；开始说放在苏州，苏州不同意。现在初定港闸或兴仁\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:40.54829+12
1682	1699	【中国文字狱事件记录】\n日期：2020年02月02日\n地点：江苏南通\n当事人：冯某霞\n平台：微信群\n言论内容：这是集中安置江苏的病例；开始说放在苏州，苏州不同意。现在初定港闸或兴仁\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日、罚款200元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:40.609267+12
1683	1700	【中国文字狱事件记录】\n日期：2020年02月02日\n地点：山西中阳县\n当事人：马某\n平台：微信群\n言论内容：从武汉回来的下枣林乡某村人袁某某为确诊感染新型冠状病毒感染肺患者\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:40.663892+12
1684	1701	【中国文字狱事件记录】\n日期：2020年02月02日\n地点：江苏江阴\n当事人：蔡某、缪某\n平台：微信群\n言论内容：那女人十几个姘头的，开房记录都挖出来了；我们朋友警察局查出来，她有十几个姘头\n背景事件：武汉新型冠状病毒肺炎\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:40.723869+12
1685	1702	【中国文字狱事件记录】\n日期：2020年02月02日\n地点：甘肃兰州\n当事人：金某\n平台：微信群\n言论内容：（通知其员工）不要去盐场堡及周边区域\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:40.789748+12
1686	1703	【中国文字狱事件记录】\n日期：2020年02月02日\n地点：吉林东丰县\n当事人：杨某\n平台：微信群\n言论内容：东丰**人死了。今晚12点全县戒严，明天所有门市必须关门。最低戒严一星期，家缺啥少啥的赶紧备货\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留7日、罚款300元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:40.83691+12
1687	1704	【中国文字狱事件记录】\n日期：2020年02月02日\n地点：山东鄄城县\n当事人：马某丽\n平台：微信群\n言论内容：县中医院已有十几个（新型肺炎）确诊的了\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:40.887384+12
1688	1705	【中国文字狱事件记录】\n日期：2020年02月02日\n地点：山东鄄城县\n当事人：孙某鹏\n平台：微信群\n言论内容：鄄城已经有一个了（新型肺炎），而且已经死了\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:40.943557+12
1689	1706	【中国文字狱事件记录】\n日期：2020年02月02日\n地点：山东青州市\n当事人：刘某\n平台：微信群\n言论内容：青州市某医疗公司(生产抗击疫情医用物资)一名员工被确诊感染需隔离处置\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:41.007454+12
1690	1707	【中国文字狱事件记录】\n日期：2020年02月02日\n地点：黑龙江大庆\n当事人：姜某涛\n平台：微信群\n言论内容：大庆已经死亡好几个了\n背景事件：武汉新型冠状病毒肺炎\n处罚：罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:41.067584+12
1691	1708	【中国文字狱事件记录】\n日期：2020年02月02日\n地点：江西德安县\n当事人：李某强\n平台：微信群\n言论内容：（视频）德安县有五例新型冠状病毒确诊患者\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留4日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:41.126667+12
2444	2467	【中国文字狱事件记录】\n日期：2022年08月14日\n地点：内蒙古乌海\n当事人：“**咫尺”\n平台：微信群\n言论内容：“不当言论”\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:20.69103+12
1692	1709	【中国文字狱事件记录】\n日期：2020年02月02日\n地点：贵州贵阳\n当事人：颜某璋\n平台：微博\n言论内容：东东告诉我贵阳花果园V区今天查出一例肺炎，救护车已经抬走了\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:41.194852+12
1693	1710	【中国文字狱事件记录】\n日期：2020年02月02日\n地点：吉林镇赉县\n当事人：李某\n平台：微博\n言论内容：镇赉县坦途镇封路，不测体温不做登记直接封死，回家不让回，住的地方没有，强行流浪街头，很合理\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:41.252563+12
1694	1711	【中国文字狱事件记录】\n日期：2020年02月02日\n地点：江苏江阴市\n当事人：张某\n平台：抖音\n言论内容：（私发给青海海西州公安局官方账号）你有关部门全部人家没病，要你检查什么，你全家全部死光全部死光；侵犯人权\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:41.30715+12
1695	1803	【中国文字狱事件记录】\n日期：2020年02月12日\n地点：新疆阿克苏\n当事人：向某\n平台：微信群\n言论内容：涉自治区领导人的谣言\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留13日不执行、罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:46.496608+12
1696	1712	【中国文字狱事件记录】\n日期：2020年02月02日\n地点：广东揭西县\n当事人：“杨曼曼”\n平台：朋友圈\n言论内容：跟我做朋友吗？去我舅舅政府单位拿的（口罩）\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日、罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:41.361207+12
1697	1713	【中国文字狱事件记录】\n日期：2020年02月02日\n地点：广东云浮\n当事人：陈某明\n平台：贴吧\n言论内容：已经确诊隔离了一例了；已经确认一例了，边度地方我就唔讲了，费事拘留\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:41.414028+12
1698	1714	【中国文字狱事件记录】\n日期：2020年02月03日\n地点：陕西渭南\n当事人：王某博\n平台：微信\n言论内容：《关于对仓程路百合园小区实施隔离封闭管理公告》\n背景事件：武汉新型冠状病毒肺炎\n处罚：办理中\n备注：2月7日谣言成真	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:41.467153+12
1699	1715	【中国文字狱事件记录】\n日期：2020年02月03日\n地点：云南陆良县\n当事人：易某朋\n平台：微信群\n言论内容："不当言论"\n处罚：治安处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:41.69645+12
1700	1716	【中国文字狱事件记录】\n日期：2020年02月03日\n地点：广东云浮\n当事人：钟某\n平台：微信群\n言论内容：今晚下午横山有一家三口从武汉回前锋，救护车车出云浮了\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:41.777337+12
1701	1717	【中国文字狱事件记录】\n日期：2020年02月03日\n地点：江苏无锡\n当事人：邹某\n平台：微信群\n言论内容：某市区内，今日凌晨24小时后所有路口红绿灯统一24小时改红灯，除特种车辆外，私家车闯一次6分200，禁止私家车辆出行\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:41.836567+12
1702	1718	【中国文字狱事件记录】\n日期：2020年02月03日\n地点：山东临沭县\n当事人：胡某兵\n平台：微信群\n言论内容：该县多人、多村已感染新型冠状病毒肺炎\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:41.880605+12
1703	1719	【中国文字狱事件记录】\n日期：2020年02月03日\n地点：青海西宁\n当事人：安某\n平台：微信群\n言论内容：今天北关七一小区、金牛小区、玉带桥大寺瓦窑沟，整个被封了；切记、切记。东区非常严重\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:41.92411+12
1704	1720	【中国文字狱事件记录】\n日期：2020年02月03日\n地点：山东曹县\n当事人：吕某\n平台：微信群\n言论内容：我们这里出现了一例，一个女的，死了，现在常乐集大街封了，公安天天在街上撵人\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:41.969038+12
1705	1721	【中国文字狱事件记录】\n日期：2020年02月03日\n地点：山东鄄城县\n当事人：谢某\n平台：微信群\n言论内容：鄄城出现了新型冠状病毒肺炎病人，在去市立医院的路上死了……\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:42.017711+12
1706	1722	【中国文字狱事件记录】\n日期：2020年02月03日\n地点：山东鄄城县\n当事人：牛某\n平台：微信群\n言论内容：俺那里（闫什镇）的张庄，死了两个人，闫什口有一个，拉到菏泽去了……..\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:42.067142+12
1707	1723	【中国文字狱事件记录】\n日期：2020年02月03日\n地点：贵州贵阳\n当事人：宋俊宏（小学教师）\n平台：微信群\n言论内容：通报的死亡人数都是虚假，光武汉一天就死500人，全国更不敢想像。武汉现在又重新启用一家已经关闭的殡仪馆，总共8家殡仪馆，一天24小时不停火化死者，死亡人数更不敢想\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日、吊销教师资格证	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:42.12246+12
1708	1724	【中国文字狱事件记录】\n日期：2020年02月03日\n地点：江苏靖江\n当事人：顾某、卢某\n平台：微信群\n言论内容：靖江市公安局重要通知，城区于今日凌晨24时后所有路口统一改红灯标禁止私家车出行，除特种车辆外，私家车闯一次记6分罚款200元，2月3日晚6点开始\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:42.174776+12
1709	1725	【中国文字狱事件记录】\n日期：2020年02月03日\n地点：黑龙江大庆\n当事人：王某元\n平台：微信群\n言论内容：大庆就死亡5例\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:42.231615+12
1710	1726	【中国文字狱事件记录】\n日期：2020年02月03日\n地点：山东日照\n当事人：王某\n平台：微信群\n言论内容：亲们，前滩西得肺炎的死了\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:42.289592+12
1711	1727	【中国文字狱事件记录】\n日期：2020年02月03日\n地点：云南永善县\n当事人：王某\n平台：微信群\n言论内容：“涉及新型冠状病毒核酸检测呈阳性患者刘某的虚假信息”\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:42.343892+12
1712	1728	【中国文字狱事件记录】\n日期：2020年02月03日\n地点：山东费县\n当事人：赵某\n平台：微博\n言论内容：不实疫情信息\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:42.398134+12
1713	1729	【中国文字狱事件记录】\n日期：2020年02月03日\n地点：黑龙江宁安市\n当事人：吴某\n平台：微博\n言论内容：三条微博内容，“辱骂”了国务院和钟南山\n背景事件：武汉新型冠状病毒肺炎\n处罚：“依法处理”	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:42.452506+12
1714	1730	【中国文字狱事件记录】\n日期：2020年02月03日\n地点：贵州贵阳\n当事人：黄某\n平台：朋友圈\n言论内容：贵阳人可怕，大陆人都可怕。蝗虫之名果真不是浪得虚名；武汉今天屠城了！如果不明白这两个字，请百度\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留15日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:42.502665+12
1715	1731	【中国文字狱事件记录】\n日期：2020年02月03日\n地点：广西南宁\n当事人：梁某珠\n平台：网络\n言论内容：湖北省武汉市这次瘟疫已经死上10万人了\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日，罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:42.551194+12
1716	1732	【中国文字狱事件记录】\n日期：2020年02月03日\n地点：江苏如东县\n当事人：管某冬\n平台：微信群\n言论内容：如东苴镇某村干部陈某“感染新型冠状病毒肺炎，目前已被强制隔离”\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:42.600202+12
1717	1733	【中国文字狱事件记录】\n日期：2020年02月03日\n地点：江苏如东县\n当事人：季某\n平台：微信群\n言论内容：栟茶镇第三例确诊者从正月初一至正月初五一直在母婴店上班\n背景事件：武汉新型冠状病毒肺炎\n处罚：罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:42.649559+12
1718	1734	【中国文字狱事件记录】\n日期：2020年02月04日\n地点：广东郁南县\n当事人：黄某\n平台：QQ群\n言论内容：“疫情谣言”\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:42.703243+12
1719	1735	【中国文字狱事件记录】\n日期：2020年02月04日\n地点：广东江门\n当事人：刘某辉\n平台：微信群\n言论内容：刚收到消息，中心医院刚查到一例，那病人知道后逃走出去，已经报警，大家请转达暂时不要外出。\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政罚款	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:42.757547+12
1720	1736	【中国文字狱事件记录】\n日期：2020年02月04日\n地点：广东江门\n当事人：周某燕\n平台：微信群\n言论内容：刚收到消息，中心医院刚查到一例，那病人知道后逃走出去，已经报警，大家请转达暂时不要外出。\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:42.810225+12
1721	1737	【中国文字狱事件记录】\n日期：2020年02月04日\n地点：广东江门\n当事人：钟某\n平台：微信群\n言论内容：江门越来越多了，蓬江区杜阮镇又有两个了，两父子从湖北回来后就发烧，老爸因为害怕丢下儿子，如果没人知道他们有病，就容易感染全江门了\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:42.868534+12
1722	1738	【中国文字狱事件记录】\n日期：2020年02月04日\n地点：湖南韶山\n当事人：陶某\n平台：微信群\n言论内容：亲们注意了，这次病毒不是一般的严重，银田的这例已经死亡了，工贸又确诊一例，长胡还有一例疑似。大家千万不要出门\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:42.92122+12
1723	1739	【中国文字狱事件记录】\n日期：2020年02月04日\n地点：湖南韶山\n当事人：肖某、汤某、刘某等\n平台：微信群\n言论内容：（转发）亲们注意了，这次病毒不是一般的严重，银田的这例已经死亡了，工贸又确诊一例，长胡还有一例疑似。大家千万不要出门\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:42.975857+12
1724	1740	【中国文字狱事件记录】\n日期：2020年02月04日\n地点：江苏海安\n当事人：丁某\n平台：微信群\n言论内容：南莫的那个肺炎者已经死了\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留2日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:43.031342+12
1725	1741	【中国文字狱事件记录】\n日期：2020年02月04日\n地点：山西临猗县\n当事人：陈某\n平台：微信群\n言论内容：临猗失陷了！嵋阳镇确诊一例；刚刚乡政府开会传达的\n背景事件：武汉新型冠状病毒肺炎\n处罚：“依法处理”	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:43.09041+12
1726	1742	【中国文字狱事件记录】\n日期：2020年02月04日\n地点：江苏盐城\n当事人：孙某\n平台：微信群\n言论内容：县各城区内，于今日凌晨24时后所有路口红绿灯，统一24小时改红灯\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:43.14917+12
1727	1743	【中国文字狱事件记录】\n日期：2020年02月04日\n地点：陕西武功县\n当事人：张某\n平台：微信群\n言论内容：之前苏坊确诊病例死亡\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:43.209413+12
1728	1744	【中国文字狱事件记录】\n日期：2020年02月04日\n地点：陕西武功县\n当事人：段某\n平台：微信群\n言论内容：已确诊7例肺炎\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:43.276994+12
1729	1745	【中国文字狱事件记录】\n日期：2020年02月04日\n地点：陕西武功县\n当事人：郑某\n平台：微信群\n言论内容：庄子发现七例，现全村已封\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:43.333735+12
1730	1746	【中国文字狱事件记录】\n日期：2020年02月04日\n地点：陕西武功县\n当事人：田某\n平台：微信群\n言论内容：“涉疫不实言论”\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:43.385195+12
1731	1747	【中国文字狱事件记录】\n日期：2020年02月04日\n地点：四川眉山\n当事人：向某\n平台：微博\n言论内容：彭山有人感染了，还死了\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:43.437502+12
1732	1748	【中国文字狱事件记录】\n日期：2020年02月04日\n地点：四川眉山\n当事人：“不想让你找到我”\n平台：微博\n言论内容：彭山有人感染了，还死了\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:43.495679+12
1733	1749	【中国文字狱事件记录】\n日期：2020年02月04日\n地点：青海互助县\n当事人：王某\n平台：快手、微信\n言论内容：（视频）我从武汉来的，有本事来抓我啊！\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留15日、罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:43.54815+12
1734	1750	【中国文字狱事件记录】\n日期：2020年02月04日\n地点：辽宁台安县\n当事人：李某\n平台：朋友圈\n言论内容：台安县出租车已停、今日凌晨24时后所有路口改红灯，禁止私家车通行\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:43.602393+12
1735	1751	【中国文字狱事件记录】\n日期：2020年02月04日\n地点：辽宁台安县\n当事人：赵某\n平台：朋友圈\n言论内容：（转发）台安县出租车已停、今日凌晨24时后所有路口改红灯，禁止私家车通行\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:43.659073+12
1736	1752	【中国文字狱事件记录】\n日期：2020年02月04日\n地点：山西繁峙县\n当事人：杨某\n平台：网络\n言论内容：砂河董三小区今日与2020年2月1日发现一例新型冠状病毒\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:43.712717+12
1737	1753	【中国文字狱事件记录】\n日期：2020年02月04日\n地点：山西繁峙县\n当事人：白某\n平台：网络\n言论内容：繁峙新城小区和锦绣苑小区隔离武汉回繁发烧人员\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:43.766651+12
1738	1754	【中国文字狱事件记录】\n日期：2020年02月04日\n地点：江苏苏州\n当事人：周某\n平台：网络\n言论内容：姑苏区新民桥菜场、娄门菜场和大润发超市等菜场、大型超市及商场将关门停业至2月10日\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留2日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:43.821363+12
1739	1755	【中国文字狱事件记录】\n日期：2020年02月04日\n地点：山东曹县\n当事人：晋某\n平台：贴吧\n言论内容：曹县八里湾木瓜园发现新型冠状病毒肺炎？抓走100多个\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:43.876688+12
1740	1756	【中国文字狱事件记录】\n日期：2020年02月05日\n地点：湖南长沙\n当事人：彭某\n平台：微信群\n言论内容：燕山街已经死人了，长沙第一例死亡\n背景事件：武汉新型冠状病毒肺炎\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:43.93012+12
1741	1757	【中国文字狱事件记录】\n日期：2020年02月05日\n地点：南宁卫健委\n当事人：任蓝智\n平台：微信群\n言论内容：“关于疫情防控不实信息”\n背景事件：武汉新型冠状病毒肺炎\n处罚：免职	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:43.985494+12
1742	1759	【中国文字狱事件记录】\n日期：2020年02月05日\n地点：甘肃西和县\n当事人：方某\n平台：微信群\n言论内容：同学们，今天都别去森美超市，刚一朋友说，今天县医院接收两个从武汉来的发热病人，这两人今天到森美超市转了一圈，望给亲朋好友转发\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:44.097669+12
1743	1760	【中国文字狱事件记录】\n日期：2020年02月05日\n地点：湖南株洲\n当事人：邓某\n平台：微信群\n言论内容：这几天不要到XX超市去，那里发现了疑似病例，这是XX人事部通知的，应该是真的\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:44.156803+12
1744	1761	【中国文字狱事件记录】\n日期：2020年02月05日\n地点：湖南郴州\n当事人：张某\n身份：警察\n平台：微信群\n言论内容：有一名确诊的新型冠状病毒感染的肺炎患者擅自脱离隔离，且有反社会情绪，并于2月2日逃脱，至今未找到\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留7日、撤职、留党察看	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:44.211322+12
1745	1762	【中国文字狱事件记录】\n日期：2020年02月05日\n地点：内蒙古赤峰\n当事人：尚某\n平台：微信群\n言论内容：家人们紧急通知，明天大家都尽量别出去了，新房身确定三例了\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:44.26289+12
1746	1763	【中国文字狱事件记录】\n日期：2020年02月06日\n地点：湖北武汉\n当事人：陈秋实\n平台：推特、油管\n言论内容：武汉多家医院和患者家庭采访视频；我陈秋实连死都不怕，我还怕你共产党么\n背景事件：武汉新型冠状病毒肺炎\n处罚：疑似被拘留，官方称医学隔离	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:44.312225+12
1747	1764	【中国文字狱事件记录】\n日期：2020年02月06日\n地点：黑龙江齐齐哈尔\n当事人：吴某\n平台：不详\n言论内容：大福源一店确认新型冠状病毒肺炎一例，我同学媳妇在那上班，没事别去逛了\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政警告	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:44.365689+12
1748	1765	【中国文字狱事件记录】\n日期：2020年02月06日\n地点：江西黎川县\n当事人：胡某\n平台：微信群\n言论内容：豫A3H88T这个车昨晚从武汉回来，车上的人确诊了偷跑回来\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:44.421122+12
1749	1766	【中国文字狱事件记录】\n日期：2020年02月06日\n地点：黑龙江齐齐哈尔\n当事人：应某\n平台：微信群\n言论内容：（转发）大福源一店确认新型冠状病毒肺炎一例，我同学媳妇在那上班，没事别去逛了\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日、罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:44.478498+12
1750	1767	【中国文字狱事件记录】\n日期：2020年02月06日\n地点：广东普宁市\n当事人：官某\n平台：抖音\n言论内容：（视频）某口罩工厂疑似非法回收再造口罩\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留、罚款	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:44.538673+12
1751	1768	【中国文字狱事件记录】\n日期：2020年02月06日\n地点：黑龙江齐齐哈尔\n当事人：刘某\n平台：网络\n言论内容：（转发）大福源一店确认新型冠状病毒肺炎一例，我同学媳妇在那上班，没事别去逛了\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政警告	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:44.592611+12
1752	1769	【中国文字狱事件记录】\n日期：2020年02月06日\n地点：黑龙江伊春\n当事人：刘某\n平台：微博\n言论内容：伊春早就有了、明明有了老百姓们都人尽皆知、还装没有呢...\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日、罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:44.645219+12
1753	1770	【中国文字狱事件记录】\n日期：2020年02月07日\n地点：江西南昌\n当事人：潘某\n平台：微信群\n言论内容：一段舞龙灯视频，并对其谴责，指其不应在近期外出聚集（警方称事件发生于去年）\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:44.697895+12
1754	1771	【中国文字狱事件记录】\n日期：2020年02月07日\n地点：广西北流市\n当事人：黄某\n平台：微信群\n言论内容：当地将封城、禁止外出等\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:44.748937+12
1755	1772	【中国文字狱事件记录】\n日期：2020年02月07日\n地点：广西宜州\n当事人：蒙某\n平台：微信群\n言论内容：（视频）有肺炎患者逃离了医院，并在警察追赶之下跳河\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:44.799691+12
1756	1773	【中国文字狱事件记录】\n日期：2020年02月07日\n地点：黑龙江杜尔伯特县\n当事人：仲某东\n平台：微博\n言论内容：经核实的武汉返乡人员名单，对政府负面言论\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:44.849387+12
1757	1774	【中国文字狱事件记录】\n日期：2020年02月07日\n地点：黑龙江肇源县\n当事人：尹某男\n平台：微博\n言论内容：黑龙江发布的疫情信息虚假\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:44.900316+12
1758	1775	【中国文字狱事件记录】\n日期：2020年02月07日\n地点：广东饶平县\n当事人：黄某雄\n平台：抖音\n言论内容：（视频）饶平县出现鸡瘟，有人宰杀病鸡准备出售，视频中有大量被褪了毛的生鸡\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:44.953129+12
1759	1776	【中国文字狱事件记录】\n日期：2020年02月07日\n地点：中国社会科学院大学\n当事人：周佩仪（港籍）\n身份：学者/教师\n平台：朋友圈\n言论内容：制度形成的社会问题真不是听几个心理课程就完事的…小粉红把我删了吧\n处罚：解聘	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:45.006328+12
1760	1777	【中国文字狱事件记录】\n日期：2020年02月07日\n地点：广东饶平县\n当事人：郑某玲\n平台：朋友圈\n言论内容：饶平县疫情及各地封路情况\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:45.061938+12
1761	1778	【中国文字狱事件记录】\n日期：2020年02月07日\n地点：辽宁瓦房店市\n当事人：邱某\n平台：朋友圈\n言论内容：本小区业主李某一家三口患病毒肺炎拒绝治疗，从医院逃跑\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:45.1173+12
1762	1779	【中国文字狱事件记录】\n日期：2020年02月08日\n地点：山东菏泽\n当事人：丁某\n平台：微信群\n言论内容：孟海死一个，孟海曹庄离我们很近，有两个，死了一个\n背景事件：武汉新型冠状病毒肺炎\n处罚：罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:45.168349+12
1763	1780	【中国文字狱事件记录】\n日期：2020年02月08日\n地点：青海囊谦县\n当事人：才某某某\n平台：微信群\n言论内容：运输过来的蔬菜中带有病毒，南大门检查站的执勤人员不知道在干什么？请大家做好防范\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留4日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:45.220431+12
1764	1781	【中国文字狱事件记录】\n日期：2020年02月08日\n地点：广东饶平县\n当事人：黄某钊\n平台：朋友圈\n言论内容：（视频）饶平县黄冈镇后田有人感染新型肺炎拒绝隔离，公安机关准备破门\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:45.274111+12
1765	1782	【中国文字狱事件记录】\n日期：2020年02月08日\n地点：江西鄱阳县\n当事人：程某\n平台：朋友圈\n言论内容：（视频）谢家滩镇三名脱管新冠肺炎病人逃到田畈街镇长方村\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:45.326079+12
1766	1783	【中国文字狱事件记录】\n日期：2020年02月09日\n地点：山东兖州市\n当事人：刘某\n平台：微信私聊\n言论内容：六中家属院有一个从武汉返兖人员，疑是冠状病毒，现已去医院就诊，道路已封\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:45.382178+12
1767	1784	【中国文字狱事件记录】\n日期：2020年02月09日\n地点：山东成武县\n当事人：杨某\n平台：微信群\n言论内容：警告，警告，山东省菏泽市成武县孙寺镇郑庄行政村于阳历2月9号，农历正月十六21:00点出现一例新冠病毒，请大家注意\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日、罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:45.437638+12
1768	1785	【中国文字狱事件记录】\n日期：2020年02月09日\n地点：宁夏中卫\n当事人：赵某\n平台：微博\n言论内容：我的家属（其女友赵某，当时被隔离）已经超过两天没有进食、休息，心理和情绪已经崩溃。本来好好的人现在精神失常了\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:45.492322+12
1769	1786	【中国文字狱事件记录】\n日期：2020年02月09日\n地点：贵州雷山县\n当事人：罗某\n平台：朋友圈\n言论内容：高速公路路口有土匪把守不给出不许进\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留15日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:45.546107+12
1770	1787	【中国文字狱事件记录】\n日期：2020年02月10日\n地点：湖北武汉\n当事人：方斌\n平台：推特、油管\n言论内容：武汉多家医院和红十字会现场视频，多具尸体被运走的视频\n背景事件：武汉新型冠状病毒肺炎\n处罚：疑似被捕	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:45.599286+12
1771	1788	【中国文字狱事件记录】\n日期：2020年02月10日\n地点：湖南浏阳\n当事人：刘某\n平台：微信群\n言论内容：工业园蓝思今天发现一例……工业园刚刚通知开了工的单位明天全部停工\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:45.652515+12
1772	1789	【中国文字狱事件记录】\n日期：2020年02月10日\n地点：山东成武县\n当事人：史某\n平台：微信群\n言论内容：（转发）警告，警告，山东省菏泽市成武县孙寺镇郑庄行政村于阳历2月9号，农历正月十六21:00点出现一例新冠病毒，请大家注意\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留7日、罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:45.705908+12
1773	1790	【中国文字狱事件记录】\n日期：2020年02月10日\n地点：黑龙江五常\n当事人：潘某飞\n平台：微信群\n言论内容：虚假疫情人数信息等不实言论\n背景事件：武汉新型冠状病毒肺炎\n处罚：罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:45.762894+12
1774	1791	【中国文字狱事件记录】\n日期：2020年02月10日\n地点：黑龙江宁安市\n当事人：吴某\n平台：微博\n言论内容：转发国务院新闻时评论了“辱骂性言论”\n背景事件：武汉新型冠状病毒肺炎\n处罚：起诉（寻衅滋事罪）	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:45.819633+12
1775	1792	【中国文字狱事件记录】\n日期：2020年02月10日\n地点：山东成武县\n当事人：陈某\n平台：抖音\n言论内容：（视频）隔壁村确诊一位（新冠肺炎）\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:45.874287+12
1776	1793	【中国文字狱事件记录】\n日期：2020年02月11日\n地点：新疆阿克苏\n当事人：廖某\n平台：微信\n言论内容：涉及国家领导人的谣言\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留15日、罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:45.92946+12
1777	1794	【中国文字狱事件记录】\n日期：2020年02月11日\n地点：河南信阳\n当事人：江某\n平台：微信群\n言论内容：青龙街一男子因怀疑感染冠状病毒杀死三人\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:45.986136+12
1778	1795	【中国文字狱事件记录】\n日期：2020年02月11日\n地点：湖南茶陵县\n当事人：唐某红\n平台：微信群\n言论内容：（视频）思聪大兴确诊了两例新型冠状病毒感染肺炎，民警已到现场处置\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:46.041656+12
1779	1796	【中国文字狱事件记录】\n日期：2020年02月11日\n地点：黑龙江五常\n当事人：高某利\n平台：微信群\n言论内容：关于武汉冠状病毒肺炎疫情的虚假言论\n背景事件：武汉新型冠状病毒肺炎\n处罚：罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:46.098217+12
1780	1797	【中国文字狱事件记录】\n日期：2020年02月11日\n地点：湖南冷水江\n当事人：刘某\n平台：微信群\n言论内容：各位亲们，千万别出门啊！我哥他们昨天来冷江采样，冷水江空气都有病毒，非常严重！！为了健康，大家好好宅在家里\n背景事件：武汉新型冠状病毒肺炎\n处罚：“依法处理”	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:46.157344+12
1781	1798	【中国文字狱事件记录】\n日期：2020年02月11日\n地点：河南濮阳\n当事人：张某\n平台：微信群\n言论内容：居住在中央城小区的医护人员一律不准出入本小区\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:46.211901+12
1782	1799	【中国文字狱事件记录】\n日期：2020年02月11日\n地点：江西南昌县\n当事人：朱某兰\n平台：微信群\n言论内容：我在听课，说到现在死亡人数1000多个只是国家想让我们看到的数据，1000多的数据时真正的死亡人数的2.1%\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:46.272223+12
1783	1800	【中国文字狱事件记录】\n日期：2020年02月11日\n地点：江苏盐城\n当事人：闫忠文\n平台：微博\n言论内容：我很好奇，这个地方没有官方吗？这么大的舆情（江苏医疗队在湖北丢失行李、物资被扣），随便找一只野鸡出来，举个手指头就能辟谣？\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留15日、罚款1000元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:46.326154+12
1784	1801	【中国文字狱事件记录】\n日期：2020年02月11日\n地点：广东普宁市\n当事人：李某佳、庄某亿\n平台：网络\n言论内容：燎原街道辖区有一男子从湖北逃跑出来且声称已是确诊病人，并藏匿在光南村\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留8日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:46.381036+12
1785	1802	【中国文字狱事件记录】\n日期：2020年02月12日\n地点：新疆阿克苏\n当事人：刘某\n平台：微信群\n言论内容：阿克苏又出X例，现在又严了，还是出不去小区，有通行证也不管用。说阿克苏有X例了，还死了X个\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留13日不执行	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:46.439493+12
1786	1804	【中国文字狱事件记录】\n日期：2020年02月12日\n地点：江西南昌县\n当事人：毛某\n平台：某外卖app\n言论内容：莲塘要死绝了，空城一座；哈哈哈一起下地狱吧\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:46.552344+12
1787	1805	【中国文字狱事件记录】\n日期：2020年02月13日\n地点：北京\n当事人：杨某\n平台：微信\n言论内容：北京市定于晚间进行大面积消杀、消毒工作\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:46.606881+12
1788	1806	【中国文字狱事件记录】\n日期：2020年02月13日\n地点：山东鄄城县\n当事人：李某莉\n平台：微信群\n言论内容：鄄城县下面一个镇一个人外出回来，在家呆了24天病死了，他老婆查出来是冠状病毒，一个村都封起来了。新闻上没报，俺村大喇叭喊的\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:46.664403+12
1789	1807	【中国文字狱事件记录】\n日期：2020年02月13日\n地点：黑龙江五常\n当事人：宋某\n平台：微信群\n言论内容：公安机关封群的虚假信息\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:46.717829+12
1790	1808	【中国文字狱事件记录】\n日期：2020年02月13日\n地点：广东紫金县\n当事人：杨某锋\n平台：微信群\n言论内容：紫金某商场销售员接触过河源市区披萨店被确诊病例患者\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:46.770982+12
1791	1809	【中国文字狱事件记录】\n日期：2020年02月13日\n地点：山东单县\n当事人：柴某\n平台：微信群\n言论内容：我刚从武汉回来\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日、罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:46.827475+12
1792	1810	【中国文字狱事件记录】\n日期：2020年02月13日\n地点：安徽蚌埠\n当事人：李某\n平台：抖音\n言论内容：“两段涉及疫情防控辱骂村干部的视频”\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:46.876257+12
1793	1811	【中国文字狱事件记录】\n日期：2020年02月14日\n地点：新疆阿克苏\n当事人：梁某\n平台：微信群\n言论内容：阿克苏今天又新增X例，阿克苏各小区现在已经封闭了，不让出小区，出租车也停了\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:46.920949+12
1794	1812	【中国文字狱事件记录】\n日期：2020年02月14日\n地点：辽宁阜新\n当事人：王某\n平台：微信群\n言论内容：你们信吗；驰援武汉的医生们，肯定压力特别大；遍地都是xx的，信吗；都是道德绑架，什么最美逆行者，整那些心灵鸡汤\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:46.9657+12
1795	1813	【中国文字狱事件记录】\n日期：2020年02月14日\n地点：内蒙古乌兰察布\n当事人：陈某\n平台：某直播平台\n言论内容：《同城进来听，集宁大事件》；关于当地一起坠楼事件的“主观臆断”\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:47.022686+12
1796	1814	【中国文字狱事件记录】\n日期：2020年02月15日\n地点：湖北武穴\n当事人：周某\n平台：微信群\n言论内容：（视频）大家赶紧到政府门口抢蔬菜，政府门口已经有多人在领取\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:47.080428+12
1797	1815	【中国文字狱事件记录】\n日期：2020年02月15日\n地点：广西德保县\n当事人：罗华某\n平台：微信群\n言论内容：德保县芳山苑两名学生确诊为冠状病毒感染！希望大家注意安全\n背景事件：武汉新型冠状病毒肺炎\n处罚：治安处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:47.138634+12
1798	1816	【中国文字狱事件记录】\n日期：2020年02月15日\n地点：广西德保县\n当事人：李某宁\n平台：微信群\n言论内容：德保今天确诊两例肺炎，而且都是学生，请大家不要让学生再出来玩，不串门，切记切记\n背景事件：武汉新型冠状病毒肺炎\n处罚：治安处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:47.192845+12
1799	1817	【中国文字狱事件记录】\n日期：2020年02月15日\n地点：广东阳山县\n当事人：杨某\n平台：网络\n言论内容：对阳山县援助湖北医疗队出征仪式的照片发表不当言论\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:47.249773+12
1800	1818	【中国文字狱事件记录】\n日期：2020年02月16日\n地点：浙江龙港市\n当事人：方某\n平台：微信群\n言论内容：龙港新冠肺炎确诊患者黄某因病死亡\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:47.307225+12
1801	1819	【中国文字狱事件记录】\n日期：2020年02月16日\n地点：新疆阿克苏\n当事人：陈某\n平台：微信群\n言论内容：快回家，谁出来抓去培训学习。看看吧，快回家\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:47.359608+12
1803	1821	【中国文字狱事件记录】\n日期：2020年02月16日\n地点：四川眉山\n当事人：易肹弘\n平台：贴吧\n言论内容：眉山市委书记和市长是“一个彻底的反中共主 义者，敢与中共法律相对抗。\n处罚：拘留8日\n法律文书：眉园公(刑)行罚决字(2020)3号；（2020）川1402行初242号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:47.47138+12
1804	1822	【中国文字狱事件记录】\n日期：2020年02月17日\n地点：黑龙江丰林县\n当事人：祁某\n平台：微信群\n言论内容：（视频）不让出小区把志愿者砍了，红星刚刚发生的事\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日、罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:47.52041+12
1805	1823	【中国文字狱事件记录】\n日期：2020年02月17日\n地点：黑龙江铁力市\n当事人：杨某\n平台：微信群\n言论内容：（视频）不让出小区把志愿者砍了，红星刚刚发生的事\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:47.566584+12
1806	1824	【中国文字狱事件记录】\n日期：2020年02月17日\n地点：黑龙江伊春\n当事人：姜某\n平台：微信群\n言论内容：（视频）伊春市伊美区美溪镇居民姜某又进一步编辑该视频，称有居民因不能出门砍死志愿者\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:47.618558+12
1807	1825	【中国文字狱事件记录】\n日期：2020年02月17日\n地点：新疆阿克苏\n当事人：缪某\n平台：微信群\n言论内容：大家注意：不听话乱窜人员，集中到体育馆学习。体育馆已准备好了学习班，只要被警察看到的人，没有证明的，一律抓进去学习，疫情解散才放回家中，并支付所产生的费用\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:47.666784+12
1808	1826	【中国文字狱事件记录】\n日期：2020年02月17日\n地点：湖南衡阳县\n当事人：罗某\n平台：抖音\n言论内容：这群废物（交警）管不了我，他们看了我得点头哈腰\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:47.723375+12
1809	1827	【中国文字狱事件记录】\n日期：2020年02月18日\n地点：陕西镇巴县农业局\n当事人：何景林\n平台：微信群\n言论内容：纪委不怕死；纪委百毒不侵；纪委可以征用防护设施；好搞笑，领导一指示，底下跟风全收到\n背景事件：武汉新型冠状病毒肺炎\n处罚：党内严重警告	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:47.775777+12
1810	1828	【中国文字狱事件记录】\n日期：2020年02月18日\n地点：浙江乐清市\n当事人：石某\n平台：微信群\n言论内容：乐清翁垟人，晚上7点半死了，第一列\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:47.830761+12
1811	1829	【中国文字狱事件记录】\n日期：2020年02月18日\n地点：湖南永兴县\n当事人：代某\n平台：朋友圈\n言论内容：永兴重症肺炎患者龙某亮已死亡\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:47.88242+12
1812	1830	【中国文字狱事件记录】\n日期：2020年02月18日\n地点：甘肃正宁县\n当事人：樊某\n平台：朋友圈\n言论内容：疫情防控一线医务工作者身穿防护服躺在地上休息的照片，并虚构事实发布不当言论\n背景事件：武汉新型冠状病毒肺炎\n处罚：治安处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:47.935522+12
1813	1831	【中国文字狱事件记录】\n日期：2020年02月19日\n地点：黑龙江伊春\n当事人：李某\n平台：微信群\n言论内容：这不是去混政绩就是去过度去了回来就升职（指伊春支援孝感医疗队）\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日、罚款200元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:47.989861+12
1814	1832	【中国文字狱事件记录】\n日期：2020年02月19日\n地点：湖南茶陵县\n当事人：谈某发\n平台：微信群\n言论内容：左垅村一家六口初步检测是阳性\n背景事件：武汉新型冠状病毒肺炎\n处罚：批评教育	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:48.046353+12
1815	1833	【中国文字狱事件记录】\n日期：2020年02月19日\n地点：广东广州\n当事人：杨开放\n平台：电报、推特\n言论内容：反党、反社会主义、诋毁现任国家领导人、关于香港修例风波的不实信息\n背景事件：郭文贵爆料事件；香港反送中示威\n处罚：有期徒刑6个月\n法律文书：（2020）粤0112刑初159号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:48.108419+12
1816	1834	【中国文字狱事件记录】\n日期：2020年02月19日\n地点：江西上高县\n当事人：李某\n平台：微信群\n言论内容：翰堂广坪村出现一起新冠肺炎病例，昨天晚上在上高县人民医院确诊了\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:48.165458+12
1817	1835	【中国文字狱事件记录】\n日期：2020年02月20日\n地点：青海贵南县\n当事人：索某\n平台：微信私聊\n言论内容：（转发）数段涉及新冠肺炎疫情虚假语音\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日、罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:48.219085+12
1818	1836	【中国文字狱事件记录】\n日期：2020年02月20日\n地点：青海贵南县\n当事人：冷某\n平台：微信群\n言论内容：（转发）数段涉及新冠肺炎疫情虚假语音至宫某的微信群\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日、罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:48.274466+12
1819	1837	【中国文字狱事件记录】\n日期：2020年02月20日\n地点：青海贵南县\n当事人：宫某\n平台：微信群\n言论内容：（放任他人在自己群内转发）数段涉及新冠肺炎疫情虚假语音\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:48.326192+12
1820	1838	【中国文字狱事件记录】\n日期：2020年02月21日\n地点：江西石城县\n当事人：赖某\n平台：微信群\n言论内容：石城温坊发现一例新型冠状病毒，从南昌回来的，大家小心了；应该是真，不过官方还没发文，我是听人说的，没亲眼见\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:48.381565+12
1821	1839	【中国文字狱事件记录】\n日期：2020年02月22日\n地点：北京\n当事人：肖某\n平台：微信群\n言论内容：京东从湖北去上海的物流司机感染新冠病毒，被发现死在车里了；京东上海仓库要封闭，不要买京东吃的了\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:48.437226+12
1822	1840	【中国文字狱事件记录】\n日期：2020年02月23日\n地点：山东聊城\n当事人：蒋某\n平台：微信群\n言论内容：因为疫情管控，山东聊城梁水镇一村民持菜刀将值班人员砍死…\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:48.492918+12
1823	1841	【中国文字狱事件记录】\n日期：2020年02月23日\n地点：北京\n当事人：柴某\n平台：微信群\n言论内容：积水潭医院刚接到通知，要开始建方舱医院了，北京的疫情远比新闻报的严重，请各位日常做好防护工作\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:48.550902+12
1824	1842	【中国文字狱事件记录】\n日期：2020年02月24日\n地点：河南汝南县\n当事人：徐某\n平台：微信群\n言论内容：汝南××的司机，现已确诊，各科极(级)干部，社区，乡镇己有多名感染，图表接触者一千多人被隔离，千万别乱跑了\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:48.607489+12
1825	1843	【中国文字狱事件记录】\n日期：2020年02月24日\n地点：河南汝南县\n当事人：胡某\n平台：微信群\n言论内容：（汝南乡镇排查武汉、湖北返乡人员表格图片）汝南县又这么严重吗\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政罚款	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:48.66298+12
1826	1844	【中国文字狱事件记录】\n日期：2020年02月24日\n地点：广州医科大学附属第三医院\n当事人：曾迎春\n平台：柳叶刀全球健康杂志\n言论内容：《中国医务人员请求国际医疗援助以对抗新型冠状病毒肺炎》\n背景事件：武汉新型冠状病毒肺炎\n处罚：停职降级	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:48.713997+12
1827	1845	【中国文字狱事件记录】\n日期：2020年02月24日\n地点：河南漯河\n当事人：郭某\n平台：网络\n言论内容：（视频）合肥一名干部妻子不戴口罩还打骂保安和防疫人员\n背景事件：武汉新型冠状病毒肺炎\n处罚：侦办中	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:48.763433+12
1828	1846	【中国文字狱事件记录】\n日期：2020年02月24日\n地点：上海\n当事人：左某\n平台：网络\n言论内容：（视频）合肥一名干部妻子不戴口罩还打骂保安和防疫人员\n背景事件：武汉新型冠状病毒肺炎\n处罚：侦办中	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:48.815327+12
1829	1847	【中国文字狱事件记录】\n日期：2020年02月26日\n地点：湖北武汉\n当事人：李泽华（前央视记者）\n平台：Youtube\n言论内容：武汉医院、百步亭社区、火葬场等地关于新冠肺炎的采访视频\n背景事件：武汉新型冠状病毒肺炎\n处罚：疑似被捕	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:48.86975+12
1830	1848	【中国文字狱事件记录】\n日期：2020年02月26日\n地点：山东青岛\n当事人：国某玉\n平台：微信群\n言论内容：其在国家信访局门口拍摄的三段带有“煽动性和侮辱性”语言的视频\n处罚：有期徒刑1年3个月\n备注：二审维持原判\n法律文书：（2019）鲁0213刑初574号；（2020）鲁02刑终341号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:48.925961+12
1831	1849	【中国文字狱事件记录】\n日期：2020年02月27日\n地点：黑龙江讷河市\n当事人：邹某\n平台：朋友圈\n言论内容：关于疫情排查的“虚假信息”\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:48.983781+12
1832	1850	【中国文字狱事件记录】\n日期：2020年02月27日\n地点：江西上高县\n当事人：李某\n平台：微信群\n言论内容：上高又确诊一例，湖北过来上班的，老婆上高的，抓了20几个去日月潭隔离\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:49.03992+12
1833	1851	【中国文字狱事件记录】\n日期：2020年02月28日\n地点：北京\n当事人：刘星星\n平台：QQ、微信\n言论内容：我感染了新型冠状病毒，昨天赶紧去了朝阳大悦城、西单大悦城门口咳嗽上百次，感染的人越多越好\n背景事件：武汉新型冠状病毒肺炎\n处罚：有期徒刑8个月\n法律文书：（2020）京0112刑初229号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:49.100958+12
1834	1852	【中国文字狱事件记录】\n日期：2020年02月28日\n地点：广西柳州\n当事人：林某华\n平台：微信群\n言论内容：武汉开放通行三小时期间，有约40个武汉人 逃到柳州\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:49.158691+12
1835	1853	【中国文字狱事件记录】\n日期：2020年02月28日\n地点：湖南株洲\n当事人：王某\n平台：网络\n言论内容：（视频）省直中医院关门了\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:49.21383+12
1836	1854	【中国文字狱事件记录】\n日期：2020年02月29日\n地点：黑龙江大庆\n当事人：王某\n平台：微信群\n言论内容：大庆XXXX潜回隔离\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留7日、罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:49.27572+12
1837	1855	【中国文字狱事件记录】\n日期：2020年02月29日\n地点：黑龙江伊春\n当事人：王某\n平台：微博\n言论内容：祝你们（警察）全部得肺炎\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日、罚款200元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:49.337839+12
1838	1856	【中国文字狱事件记录】\n日期：2020年02月29日\n地点：吉林长春\n当事人：杜某\n平台：抖音\n言论内容：东北，长春，我回来了，春城各方面渠道尽快梳理，确保一切顺利，不被隔离；感谢长春方方面面的一路绿灯；应该不用隔离，我是战友直接在内场给我接走了\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:49.390837+12
1839	1857	【中国文字狱事件记录】\n日期：2020年03月01日\n地点：四川成都\n当事人：仁青持真\n平台：微信、个人网站\n言论内容：批评中共针对西藏政策的言论\n处罚：有期徒刑4年6个月	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:49.446928+12
1840	1858	【中国文字狱事件记录】\n日期：2020年03月01日\n地点：湖北随县\n当事人：周某\n平台：微信群\n言论内容：攻击我国体制并建议民众储备粮食、蔬菜、水等各种生活物资至少6个月到2年时间\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日、罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:49.50152+12
1841	1859	【中国文字狱事件记录】\n日期：2020年03月02日\n地点：天津\n当事人：张跃堂\n平台：微信\n言论内容：70余条“诋毁、辱骂党和国家及党和国家领导人的言论及图片；诋毁政府抗疫措施\n背景事件：武汉新型冠状病毒肺炎\n处罚：有期徒刑8个月\n法律文书：（2020）津0102刑初65号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:49.558789+12
1842	1860	【中国文字狱事件记录】\n日期：2020年03月03日\n地点：广西西林县\n当事人：王某\n平台：抖音\n言论内容：（政府执法人员巡逻视频）土匪上来了\n处罚：拘留6日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:49.6144+12
1843	1861	【中国文字狱事件记录】\n日期：2020年03月03日\n地点：辽宁北票市\n当事人：闫某\n平台：现实\n言论内容：金、银河小区有确诊病例\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:49.671977+12
1844	1862	【中国文字狱事件记录】\n日期：2020年03月04日\n地点：江西龙南\n当事人：朱某志\n平台：朋友圈\n言论内容：相信自由民主 反对集权；钟南山就是骗子；伊朗官方都承认六万，中国才八万人数骗鬼吧\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日、罚款1000元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:49.725183+12
1845	1863	【中国文字狱事件记录】\n日期：2020年03月05日\n地点：湖北天门\n当事人：伍某\n平台：网络\n言论内容：（图片）天门市新型冠状病毒感染肺炎疫情防控指挥部《关于撤销乡镇和村组交通卡口的紧急通知》\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:49.781024+12
1847	1865	【中国文字狱事件记录】\n日期：2020年03月06日\n地点：辽宁丹东\n当事人：金某\n平台：微信\n言论内容：（转发）视频：宽甸确诊女患者死亡\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:49.897357+12
1848	1866	【中国文字狱事件记录】\n日期：2020年03月06日\n地点：辽宁丹东\n当事人：葛某\n平台：微信\n言论内容：（转发）视频：宽甸确诊女患者死亡\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:49.972904+12
1849	1867	【中国文字狱事件记录】\n日期：2020年03月06日\n地点：辽宁丹东\n当事人：程某\n平台：微信私聊\n言论内容：视频：宽甸确诊女患者死亡\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:50.018775+12
1850	1868	【中国文字狱事件记录】\n日期：2020年03月06日\n地点：辽宁丹东\n当事人：于某\n平台：微信群\n言论内容：（转发）宽甸确诊女患者已死亡\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:50.064369+12
1851	1869	【中国文字狱事件记录】\n日期：2020年03月06日\n地点：辽宁丹东\n当事人：赵某\n平台：微信群\n言论内容：（转发）宽甸确诊女患者已死亡\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:50.108518+12
1852	1870	【中国文字狱事件记录】\n日期：2020年03月06日\n地点：辽宁丹东\n当事人：门某\n平台：微信群\n言论内容：（转发）宽甸确诊女患者已死亡\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政罚款	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:50.152763+12
1853	1871	【中国文字狱事件记录】\n日期：2020年03月06日\n地点：辽宁丹东\n当事人：纪某\n平台：微信群\n言论内容：宽甸确诊女患者已死亡\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:50.195889+12
1854	1872	【中国文字狱事件记录】\n日期：2020年03月06日\n地点：辽宁宽甸县\n当事人：宋某\n平台：微信群\n言论内容：石柱子村发现二名冠状病毒患者\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:50.243587+12
1855	1873	【中国文字狱事件记录】\n日期：2020年03月07日\n地点：湖北广水市\n当事人：蔡某\n平台：微信群\n言论内容：特大喜讯，11号准时开放，广水市所有的病人都转到武汉去了，前天转走的，现在正在消毒\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:50.293325+12
1856	1874	【中国文字狱事件记录】\n日期：2020年03月09日\n地点：浙江温州\n当事人：张选复\n平台：微信群\n言论内容：涉及新型冠状肺炎确诊患者复发去世并向街道相关工作人员确认过该消息\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:50.340128+12
1857	1875	【中国文字狱事件记录】\n日期：2020年03月09日\n地点：浙江温州\n当事人：不详\n平台：微信群\n言论内容：教练你还是先别急着复工了，锦春大厦一治愈患者于昨晚复发死亡\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:50.384775+12
1858	1876	【中国文字狱事件记录】\n日期：2020年03月09日\n地点：吉林德惠市\n当事人：杨某苹\n平台：快手\n言论内容：关于疫情防控的“不当言论”\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:50.429847+12
1859	1877	【中国文字狱事件记录】\n日期：2020年03月09日\n地点：浙江云和县\n当事人：叶伟华\n平台：朋友圈\n言论内容：警察暴力执法\n背景事件：其家正被强拆\n处罚：拘留8日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:50.474119+12
1860	1878	【中国文字狱事件记录】\n日期：2020年03月09日\n地点：山东德州\n当事人：尹某\n平台：朋友圈\n言论内容：交警你是吃蝙蝠了么。马勒戈壁\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:50.518716+12
1861	1879	【中国文字狱事件记录】\n日期：2020年03月10日\n地点：宁夏银川\n当事人：王鹏\n平台：QQ群\n言论内容：新疆刚发生暴乱了，穆斯林维族人在新疆杀汉人，同是穆斯林的回族，去新疆被警察高度盘查，有错吗？\n处罚：拘留5日\n备注：法院撤销处罚\n法律文书：银兴公（凤凰）行罚决字[2020]10186号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:50.563889+12
1862	1880	【中国文字狱事件记录】\n日期：2020年03月11日\n地点：辽宁大连\n当事人：周某\n平台：微信群\n言论内容：3月16日居民出行正常化，17日公交正常化，18日逐步企业生产和市场经营正常化，22日重点场所正常化，25日机场、高速、动车、国道正常化......\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:50.607724+12
1863	1881	【中国文字狱事件记录】\n日期：2020年03月11日\n地点：云南彝良县\n当事人：钟陆方\n平台：朋友圈\n言论内容：“发布信息，肆意评论、抨击、辱骂党政国家机关及国家领导人”\n处罚：有期徒刑1年\n备注：二审维持原判\n法律文书：（2020）云0628刑初24号；（2020）云06刑终147号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:50.652041+12
1864	1882	【中国文字狱事件记录】\n日期：2020年03月11日\n地点：广东云浮\n当事人：卢某\n平台：朋友圈\n言论内容：死交警没钱发工资都不要出来乱拖车啊，老子的小电动好好的停着得罪了你们什么\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:50.69814+12
1865	1883	【中国文字狱事件记录】\n日期：2020年03月12日\n地点：湖北随州\n当事人：庞某、王某\n平台：微信群\n言论内容：周家台子有人去世，消防破门而入，把人都带走了……\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:50.746159+12
1866	1884	【中国文字狱事件记录】\n日期：2020年03月12日\n地点：广东广州\n当事人：钟某萍\n平台：微信群\n言论内容：转发“郭某”、“xx访谈”等包含反共言论的政治谣言\n处罚：有期徒刑9个月\n法律文书：（2020）粤0105刑初221号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:50.792305+12
1867	1885	【中国文字狱事件记录】\n日期：2020年03月12日\n地点：天津\n当事人：董兴苑\n平台：微博\n言论内容：“不当言论”\n处罚：拘留5日\n法律文书：开公（万）行罚决字［2020］102号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:50.838173+12
1868	1886	【中国文字狱事件记录】\n日期：2020年03月12日\n地点：安徽五河县\n当事人：顾某\n平台：抖音\n言论内容：（就其丈夫联系的货运车被防疫工作人员劝返一事）”辱骂“防疫工作人员\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:50.883388+12
1869	1887	【中国文字狱事件记录】\n日期：2020年03月13日\n地点：山东泰安\n当事人：谢某\n平台：不详\n言论内容：虚构事实\n处罚：拘留10日、罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:50.928569+12
1870	1890	【中国文字狱事件记录】\n日期：2020年03月15日\n地点：浙江庆元县\n当事人：杨丽霞\n平台：微信群\n言论内容：外面传言，我们建材市场发现******，建材市场封了\n背景事件：武汉新型冠状病毒肺炎\n处罚：罚款100元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:51.072412+12
1871	1891	【中国文字狱事件记录】\n日期：2020年03月16日\n地点：广西马山县\n当事人：覃某（某镇副镇长）\n身份：党政官员\n平台：微信群\n言论内容：将网络传播的外地地名为“新塘”的疫情信息改编成马山县周鹿镇“石塘”村\n背景事件：武汉新型冠状病毒肺炎\n处罚：立案调查	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:51.118352+12
1872	1892	【中国文字狱事件记录】\n日期：2020年03月16日\n地点：浙江仙居县\n当事人：章小飞\n平台：微信群\n言论内容：疫情不实言论\n背景事件：武汉新型冠状病毒肺炎\n处罚：罚款200元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:51.166252+12
1873	1893	【中国文字狱事件记录】\n日期：2020年03月16日\n地点：云南福贡县\n当事人：余某\n平台：微信群\n言论内容：福贡县有一名意大利输入新冠肺炎\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:51.211274+12
1874	1894	【中国文字狱事件记录】\n日期：2020年03月17日\n地点：广州云端传媒有限公司\n当事人：欧阳佳子\n平台：微信公众平台\n言论内容：“张扣扣事件”、“上海交警事件”、“全国两会政策”等涉及国内重大事件等“虚假信息”\n处罚：有期徒刑1年1个月\n法律文书：（2020）粤0112刑初230号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:51.260783+12
1875	1895	【中国文字狱事件记录】\n日期：2020年03月17日\n地点：广州云端传媒有限公司\n当事人：谢家俊\n平台：微信公众平台\n言论内容：“张扣扣事件”、“上海交警事件”、“全国两会政策”等涉及国内重大事件等“虚假信息”\n处罚：有期徒刑1年\n法律文书：（2020）粤0112刑初230号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:51.306109+12
1876	1896	【中国文字狱事件记录】\n日期：2020年03月17日\n地点：广州云端传媒有限公司\n当事人：徐茂\n平台：微信公众平台\n言论内容：“张扣扣事件”、“上海交警事件”、“全国两会政策”等涉及国内重大事件等“虚假信息”\n处罚：有期徒刑11个月15天\n法律文书：（2020）粤0112刑初230号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:51.351612+12
1877	1983	【中国文字狱事件记录】\n日期：2020年05月30日\n地点：广西宾阳县\n当事人：韦某平\n平台：微信群\n言论内容：“辱骂警察”的言论\n处罚：拘留10日、罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:55.735317+12
1878	1897	【中国文字狱事件记录】\n日期：2020年03月17日\n地点：广州云端传媒有限公司\n当事人：石梅\n平台：微信公众平台\n言论内容：“张扣扣事件”、“上海交警事件”、“全国两会政策”等涉及国内重大事件等“虚假信息”\n处罚：有期徒刑11个月15天\n法律文书：（2020）粤0112刑初230号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:51.397033+12
1879	1898	【中国文字狱事件记录】\n日期：2020年03月17日\n地点：广州云端传媒有限公司\n当事人：刘青\n平台：微信公众平台\n言论内容：“张扣扣事件”、“上海交警事件”、“全国两会政策”等涉及国内重大事件等“虚假信息”\n处罚：有期徒刑11个月15天\n法律文书：（2020）粤0112刑初230号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:51.442121+12
1880	1899	【中国文字狱事件记录】\n日期：2020年03月17日\n地点：广州云端传媒有限公司\n当事人：伍智慧\n平台：微信公众平台\n言论内容：“张扣扣事件”、“上海交警事件”、“全国两会政策”等涉及国内重大事件等“虚假信息”\n处罚：有期徒刑11个月15天\n法律文书：（2020）粤0112刑初230号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:51.488344+12
1881	1900	【中国文字狱事件记录】\n日期：2020年03月17日\n地点：广州云端传媒有限公司\n当事人：呙济明\n平台：微信公众平台\n言论内容：“张扣扣事件”、“上海交警事件”、“全国两会政策”等涉及国内重大事件等“虚假信息”\n处罚：有期徒刑11个月15天\n法律文书：（2020）粤0112刑初230号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:51.533523+12
1882	1901	【中国文字狱事件记录】\n日期：2020年03月17日\n地点：黑龙江龙江县\n当事人：不详\n平台：朋友圈\n言论内容：（视频）龙江县四名意大利返乡人员出现发烧症状，大家都别出来了\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日，罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:51.578439+12
1883	1902	【中国文字狱事件记录】\n日期：2020年03月18日\n地点：广西钦州\n当事人：陶某\n平台：微信群\n言论内容：（转发截图）钦州有一个密切接触者，城西的，昨晚已在某某大酒店隔离。其今天下午刚联系城西社区了解情况，该密切接触者目前检测阴性。昨晚警察封屋\n背景事件：武汉新型冠状病毒肺炎\n处罚：批评教育	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:51.62551+12
1884	1903	【中国文字狱事件记录】\n日期：2020年03月18日\n地点：广东广州\n当事人：覃龙腾\n平台：花花H5\n言论内容：“有关国家领导人讲话、上海交警处罚事件、张扣扣事件等不实信息”\n处罚：有期徒刑1年2个月\n法律文书：（2020）粤0112刑初229号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:51.670789+12
1885	1904	【中国文字狱事件记录】\n日期：2020年03月18日\n地点：广东广州\n当事人：杨铭\n平台：花花H5\n言论内容：创建花花H5平台，覃龙腾在该平台发布“有关国家领导人讲话、上海交警处罚事件、张扣扣事件等不实信息”\n处罚：有期徒刑1年\n法律文书：（2020）粤0112刑初229号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:51.715563+12
1886	1905	【中国文字狱事件记录】\n日期：2020年03月18日\n地点：贵州贵阳\n当事人：赵某\n平台：推特\n言论内容：“诽谤中国国家领导人的视频、照片及言论”\n处罚：起诉（寻衅滋事罪）\n法律文书：观检刑诉〔2020〕156号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:51.762702+12
1887	1906	【中国文字狱事件记录】\n日期：2020年03月19日\n地点：广州飞成公司和广州闪创云公司\n当事人：吴磊\n平台：微信公众平台\n言论内容：“张扣扣事件”、“上海交警事件”、“全国两会政策”等涉及国内重大事件等“虚假信息”\n处罚：有期徒刑1年4个月10天\n法律文书：（2020）粤0112刑初231号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:51.808642+12
1888	1907	【中国文字狱事件记录】\n日期：2020年03月19日\n地点：广州飞成公司和广州闪创云公司\n当事人：蒋睿\n平台：微信公众平台\n言论内容：“张扣扣事件”、“上海交警事件”、“全国两会政策”等涉及国内重大事件等“虚假信息”\n处罚：有期徒刑1年4个月\n法律文书：（2020）粤0112刑初231号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:51.855679+12
1889	1908	【中国文字狱事件记录】\n日期：2020年03月19日\n地点：广州飞成公司\n当事人：吴帅\n平台：微信公众平台\n言论内容：“张扣扣事件”、“上海交警事件”、“全国两会政策”等涉及国内重大事件等“虚假信息”\n处罚：有期徒刑1年2个月\n法律文书：（2020）粤0112刑初231号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:51.902101+12
1890	1909	【中国文字狱事件记录】\n日期：2020年03月19日\n地点：广州闪创云公司\n当事人：敖裕刚\n平台：微信公众平台\n言论内容：“张扣扣事件”、“上海交警事件”、“全国两会政策”等涉及国内重大事件等“虚假信息”\n处罚：有期徒刑1年15天\n法律文书：（2020）粤0112刑初231号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:51.946548+12
1891	1910	【中国文字狱事件记录】\n日期：2020年03月19日\n地点：广州闪创云公司\n当事人：蓝柳盛\n平台：微信公众平台\n言论内容：“张扣扣事件”、“上海交警事件”、“全国两会政策”等涉及国内重大事件等“虚假信息”\n处罚：有期徒刑1年15天\n法律文书：（2020）粤0112刑初231号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:51.992076+12
1892	1911	【中国文字狱事件记录】\n日期：2020年03月19日\n地点：广州闪创云公司\n当事人：徐毅\n平台：微信公众平台\n言论内容：“张扣扣事件”、“上海交警事件”、“全国两会政策”等涉及国内重大事件等“虚假信息”\n处罚：有期徒刑1年10天\n法律文书：（2020）粤0112刑初231号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:52.041192+12
1893	1912	【中国文字狱事件记录】\n日期：2020年03月19日\n地点：广州闪创云公司\n当事人：杨浩\n平台：微信公众平台\n言论内容：“张扣扣事件”、“上海交警事件”、“全国两会政策”等涉及国内重大事件等“虚假信息”\n处罚：有期徒刑1年5天\n法律文书：（2020）粤0112刑初231号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:52.089188+12
1894	1913	【中国文字狱事件记录】\n日期：2020年03月19日\n地点：广州闪创云公司\n当事人：徐刚\n平台：微信公众平台\n言论内容：“张扣扣事件”、“上海交警事件”、“全国两会政策”等涉及国内重大事件等“虚假信息”\n处罚：有期徒刑1年\n法律文书：（2020）粤0112刑初231号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:52.138683+12
1895	1914	【中国文字狱事件记录】\n日期：2020年03月19日\n地点：广州飞成公司\n当事人：薛爽\n平台：微信公众平台\n言论内容：“张扣扣事件”、“上海交警事件”、“全国两会政策”等涉及国内重大事件等“虚假信息”\n处罚：有期徒刑1年\n法律文书：（2020）粤0112刑初231号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:52.184774+12
1896	1915	【中国文字狱事件记录】\n日期：2020年03月19日\n地点：广州飞成公司\n当事人：陈乾\n平台：微信公众平台\n言论内容：“张扣扣事件”、“上海交警事件”、“全国两会政策”等涉及国内重大事件等“虚假信息”\n处罚：有期徒刑1年\n法律文书：（2020）粤0112刑初231号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:52.229326+12
1897	1984	【中国文字狱事件记录】\n日期：2020年06月01日\n地点：广东翁源县\n当事人：张某\n平台：朋友圈\n言论内容：（视频）吃国家粮的，压榨老百姓，算嘛拽毛，交警算嘛拽毛\n处罚：罚款100元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:55.779181+12
1898	1916	【中国文字狱事件记录】\n日期：2020年03月19日\n地点：广州飞成公司\n当事人：周海文\n平台：微信公众平台\n言论内容：“张扣扣事件”、“上海交警事件”、“全国两会政策”等涉及国内重大事件等“虚假信息”\n处罚：有期徒刑1年\n法律文书：（2020）粤0112刑初231号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:52.275173+12
1899	1917	【中国文字狱事件记录】\n日期：2020年03月19日\n地点：广州飞成公司\n当事人：古国清\n平台：微信公众平台\n言论内容：“张扣扣事件”、“上海交警事件”、“全国两会政策”等涉及国内重大事件等“虚假信息”\n处罚：有期徒刑1年\n法律文书：（2020）粤0112刑初231号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:52.319221+12
1900	1918	【中国文字狱事件记录】\n日期：2020年03月19日\n地点：广州飞成公司\n当事人：陈浩\n平台：微信公众平台\n言论内容：“张扣扣事件”、“上海交警事件”、“全国两会政策”等涉及国内重大事件等“虚假信息”\n处罚：有期徒刑1年\n法律文书：（2020）粤0112刑初231号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:52.363827+12
1901	1919	【中国文字狱事件记录】\n日期：2020年03月19日\n地点：广州飞成公司\n当事人：杨桥\n平台：微信公众平台\n言论内容：“张扣扣事件”、“上海交警事件”、“全国两会政策”等涉及国内重大事件等“虚假信息”\n处罚：有期徒刑1年\n法律文书：（2020）粤0112刑初231号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:52.409418+12
1902	1920	【中国文字狱事件记录】\n日期：2020年03月19日\n地点：广州企兴邦科技公司\n当事人：谢赛华（法人代表）\n平台：微信公众平台\n言论内容：全国进入备战状态、10万军队前往东部战区等\n处罚：有期徒刑1年2个月\n法律文书：（2020）粤0112刑初231号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:52.45679+12
1903	1921	【中国文字狱事件记录】\n日期：2020年03月20日\n地点：甘肃陇南\n当事人：杨某文\n平台：微信群\n言论内容：还要钱里看看干的活，是人干的不；政府叫人干的啊；不给钱了\n处罚：批评教育	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:52.50338+12
1904	1922	【中国文字狱事件记录】\n日期：2020年03月21日\n地点：湖北沙洋县\n当事人：魏某\n平台：微信群\n言论内容：大家没事都少出门，御水京都又封了，有境外人员回来已经确诊了，安全第一；不是谣言\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政罚款	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:52.549035+12
1905	1923	【中国文字狱事件记录】\n日期：2020年03月21日\n地点：北京\n当事人：祁怡元\n平台：现实/印制T恤\n言论内容：反对习近平倒行逆施，反对共产党一党独裁\n处罚：有期徒刑2年\n法律文书：（2019）京0102刑初981号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:52.595495+12
1906	1924	【中国文字狱事件记录】\n日期：2020年03月21日\n地点：北京\n当事人：张盼成\n平台：现实/印制t恤\n言论内容：反对习近平倒行逆施，反对共产党一党独裁\n处罚：有期徒刑1年6个月\n法律文书：（2019）京0102刑初981号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:52.64319+12
1907	1925	【中国文字狱事件记录】\n日期：2020年03月23日\n地点：新疆阿克苏\n当事人：秦新莉\n平台：网络、现实\n言论内容：（贴横幅）七年拆迁未果，求社会关注；黑心开发商，还老百姓公道；（网络）《阿克苏谁为刘新良撑起保护伞》\n处罚：有期徒刑4年\n法律文书：（2019）新2901刑初3043号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:52.688988+12
1908	1926	【中国文字狱事件记录】\n日期：2020年03月23日\n地点：新疆阿克苏\n当事人：刘耀骏\n平台：网络、现实\n言论内容：（贴横幅）七年拆迁未果，求社会关注；黑心开发商，还老百姓公道；（网络）《阿克苏谁为刘新良撑起保护伞》\n处罚：有期徒刑1年6个月\n法律文书：（2019）新2901刑初3043号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:52.73553+12
1909	1927	【中国文字狱事件记录】\n日期：2020年03月30日\n地点：江苏睢宁县\n当事人：蔡彬\n平台：西祠胡同\n言论内容：“辱骂睢宁县官山镇党委政府及工作人员”\n处罚：有期徒刑1年\n备注：二审维持原判\n法律文书：（2019）苏0324刑初895号；（2020）苏03刑终258号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:52.781109+12
1910	1928	【中国文字狱事件记录】\n日期：2020年04月01日\n地点：黄石市中心医院\n当事人：余向东（副院长）\n平台：微博、微信\n言论内容：对戴口罩、居家管理、封城等临时措施以及安徽支援1.2吨中药材等问题，发表一些不当言论\n背景事件：武汉新型冠状病毒肺炎\n处罚：免职	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:52.826538+12
1911	1929	【中国文字狱事件记录】\n日期：2020年04月04日\n地点：安徽固镇县\n当事人：代某\n平台：微信群\n言论内容：你特么不能玩游戏你不生气？所以说中国人迷信，外国肯定不会这样；有吊用，心里有（死者）比啥都强\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:52.875314+12
1912	1930	【中国文字狱事件记录】\n日期：2020年04月04日\n地点：广东罗定县\n当事人：李某\n平台：朋友圈\n言论内容：一条带有侮辱性不当言论并加上国家哀悼日的宣传图片截图\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政罚款	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:52.923659+12
1913	1931	【中国文字狱事件记录】\n日期：2020年04月04日\n地点：辽宁营口\n当事人：孙某\n平台：朋友圈\n言论内容：其本人对着电视中进行哀悼日讲话的领导人进行口头“侮辱”的视频；国家领导人讲话的视频截图配有“不当文字”\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:52.971046+12
1914	1932	【中国文字狱事件记录】\n日期：2020年04月05日\n地点：江苏徐州\n当事人：张某闻（未成年）\n平台：QQ\n言论内容：吃屎了吗？我哀悼恁妈！\n背景事件：武汉新型冠状病毒肺炎\n处罚：批评教育	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:53.017486+12
1915	1933	【中国文字狱事件记录】\n日期：2020年04月05日\n地点：江苏宿迁\n当事人：刘某伟\n平台：QQ\n言论内容：游戏全部停服？不就死了几个人妈？草！\n背景事件：武汉新型冠状病毒肺炎\n处罚：批评教育	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:53.062634+12
1916	1934	【中国文字狱事件记录】\n日期：2020年04月05日\n地点：江苏苏州\n当事人：许某怡（未成年）\n平台：QQ\n言论内容：游戏都能和疫情扯上，我觉得中国越来越**了！\n背景事件：武汉新型冠状病毒肺炎\n处罚：批评教育	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:53.110056+12
1917	1935	【中国文字狱事件记录】\n日期：2020年04月05日\n地点：江苏南通\n当事人：窦某君\n平台：微信\n言论内容：他妈悼念还不让人打游戏了？傻逼默哀！\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:53.156733+12
1918	1936	【中国文字狱事件记录】\n日期：2020年04月05日\n地点：黑龙江鸡西\n当事人：关某学\n平台：微信私聊\n言论内容：（视频）俺家小区又戒严了，咔咔又全都封上了，从国外俄罗斯回来18个新冠肺炎感染者，城子河又要戒严了……\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:53.512754+12
1919	1985	【中国文字狱事件记录】\n日期：2020年06月02日\n地点：广东翁源县\n当事人：王某\n平台：微信群\n言论内容：交警土匪样\n处罚：罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:55.822936+12
1920	1937	【中国文字狱事件记录】\n日期：2020年04月05日\n地点：黑龙江鸡西\n当事人：王某英\n平台：微信群\n言论内容：（转发视频）俺家小区又戒严了，咔咔又全都封上了，从国外俄罗斯回来18个新冠肺炎感染者，城子河又要戒严了……\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:53.565998+12
1921	1938	【中国文字狱事件记录】\n日期：2020年04月05日\n地点：江苏扬州\n当事人：颜某俊（未成年）\n平台：微博\n言论内容：游戏不让玩，视频不让看。那些该死的军人反正也没人记得，用不着悼念！\n背景事件：武汉新型冠状病毒肺炎\n处罚：批评教育	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:53.619538+12
1922	1939	【中国文字狱事件记录】\n日期：2020年04月07日\n地点：广东惠州\n当事人：廖珍华\n平台：多个新闻网站\n言论内容：“辱骂国家领导人”和散布“谣言”\n处罚：有期徒刑6个月\n法律文书：（2020）粤1302刑初225号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:53.66848+12
1923	1940	【中国文字狱事件记录】\n日期：2020年04月09日\n地点：河南焦作\n当事人：张红\n平台：推特\n言论内容：发布与转发政治推文\n处罚：有期徒刑1年、罚款1000元\n法律文书：（2020）豫0811刑初62号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:53.723622+12
1924	1941	【中国文字狱事件记录】\n日期：2020年04月10日\n地点：贵州铜仁\n当事人：覃某\n平台：朋友圈\n言论内容：谢桥又土匪查酒驾\n处罚：罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:53.778036+12
1925	1942	【中国文字狱事件记录】\n日期：2020年04月11日\n地点：广东深圳\n当事人：陆辉煌\n平台：QQ邮箱\n言论内容：《对当前政局的分析于呼吁》等七篇政论文章，揭露社会时局现状和呼吁改革\n处罚：有期徒刑2年6个月\n法律文书：（2019）粤0309刑初734号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:53.829803+12
1926	1943	【中国文字狱事件记录】\n日期：2020年04月13日\n地点：河南内黄县\n当事人：张运杰\n平台：推特、微博\n言论内容：“抨击我国现行法律制度、损害国家领导人及共产党形象等涉政虚假信息”\n处罚：起诉（寻衅滋事罪）\n备注：1.0\n法律文书：安内检一部刑诉〔2020〕46号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:53.879383+12
1927	1944	【中国文字狱事件记录】\n日期：2020年04月14日\n地点：贵州凯里\n当事人：吴某\n平台：微信群\n言论内容：（视频）醉了醉了，这些狗日的，狗真多\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:53.932817+12
1928	1945	【中国文字狱事件记录】\n日期：2020年04月15日\n地点：湖北黄石\n当事人：张龙泉\n平台：微信群\n言论内容：转发“辱骂和攻击党和政府、党和国家领导人的言论信息、图片”\n处罚：有期徒刑8个月\n法律文书：（2020）鄂0203刑初29号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:53.979799+12
1929	1946	【中国文字狱事件记录】\n日期：2020年04月15日\n地点：吉林吉林\n当事人：辛某\n平台：微博\n言论内容：“辱骂交警的视频”\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:54.028708+12
1930	1947	【中国文字狱事件记录】\n日期：2020年04月16日\n地点：上海\n当事人：朱洪广（凌霜）\n平台：QQ、脸书、微信等\n言论内容：“诽谤国家领导人的言论和图片”\n处罚：有期徒刑10个月\n备注：二审维持原判\n法律文书：（2020）沪02刑终614号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:54.074405+12
1931	1948	【中国文字狱事件记录】\n日期：2020年04月16日\n地点：江西景德镇中院\n当事人：陈光平\n身份：党政官员（退休）\n平台：微博、微信等\n言论内容：多篇文章质疑乐平警方办理的一起案件里存在于黑恶势力勾结的情况，称其为黑警并举报\n处罚：有期徒刑2年6个月\n备注：自诉案件	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:54.121365+12
1932	1949	【中国文字狱事件记录】\n日期：2020年04月17日\n地点：北京\n当事人：刘某\n平台：微博\n言论内容：靠着贴条赚钱吗？？大疫情的缺钱了是吗？？？谁特么8点贴条啊SB\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:54.166287+12
1933	1950	【中国文字狱事件记录】\n日期：2020年04月20日\n地点：山东莒南县\n当事人：王成龙\n平台：推特、脸书、YouTube\n言论内容："辱骂国家领导人的言论或推文"\n处罚：有期徒刑7个月\n法律文书：（2020）鲁1327刑初113号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:54.210494+12
1934	1951	【中国文字狱事件记录】\n日期：2020年04月21日\n地点：广西桂林\n当事人：唐坤全\n平台：现实/书写于公开场合\n言论内容：香港问题辱骂国家领导人的文字和辱骂国家领导人的文字\n背景事件：香港反送中示威\n处罚：拘役5个月\n法律文书：（2020）桂0305刑初74号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:54.25522+12
1935	1952	【中国文字狱事件记录】\n日期：2020年04月21日\n地点：浙江杭州\n当事人：谢丽美\n平台：网络、现实\n言论内容：马屁精、无德无能、恶毒、共匪勾结等（指多名政府官员）；上访\n处罚：有期徒刑2年\n备注：二审维持原判\n法律文书：（2020）浙0109刑初156号；（2020）浙01刑终302号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:54.303772+12
1936	1953	【中国文字狱事件记录】\n日期：2020年04月23日\n地点：陕西延安\n当事人：康某\n平台：社交网站\n言论内容：有关疫情不当言论\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:54.350474+12
1937	1954	【中国文字狱事件记录】\n日期：2020年04月24日\n地点：湖北荆门\n当事人：刘艳丽\n平台：QQ、微信\n言论内容：自2009年以来多条反动言论\n处罚：有期徒刑4年\n法律文书：（2018）鄂0802刑初409号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:54.395755+12
1938	1955	【中国文字狱事件记录】\n日期：2020年04月24日\n地点：山东桓台县\n当事人：张岗\n平台：微博、微信\n言论内容：（视频）田庄镇文庄村王某某是贪官；桓台县纪委、有关政府工作人员系黑恶势力、贪官保护伞\n处罚：有期徒刑2年\n备注：二审改判2年2个月\n法律文书：（2020）鲁0321刑初80号；（2020）鲁03刑终102号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:54.442962+12
1939	1956	【中国文字狱事件记录】\n日期：2020年04月24日\n地点：湖北巴东县\n当事人：梁某\n平台：现实\n言论内容：张贴大字报指控村干部办事不公；当众口头“辱骂国家领导人”\n处罚：起诉（寻衅滋事罪）\n法律文书：鄂巴检刑诉〔2020〕23号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:54.488382+12
1940	1957	【中国文字狱事件记录】\n日期：2020年04月26日\n地点：安徽临泉县\n当事人：张合理\n平台：微信群\n言论内容：攻击侮辱我国的社会主义制度、执政党以 及原国家领导人的言论文字图片和音视频\n处罚：有期徒刑二年，缓刑三年\n法律文书：（2020）皖1221刑初14号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:54.533634+12
1941	1958	【中国文字狱事件记录】\n日期：2020年04月26日\n地点：湖北大学\n当事人：梁艳萍\n身份：学者/教师\n平台：微博\n言论内容：那一日 巷空 城空，天也空 坦克开进广场，凛凛威风；你把三十万的名单拿出来啊？周梓乐同学，一路走好\n处罚：停职、记过、开除党籍\n法律文书：https://k.sina.com.cn/article_3363163410_c875cd1204000ukb4.html?from=news&subch=onews	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:54.588924+12
1942	1991	【中国文字狱事件记录】\n日期：2020年06月07日\n地点：辽宁沈阳\n当事人：王某\n平台：微信\n言论内容：“辱警言论”\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:56.083177+12
1943	1959	【中国文字狱事件记录】\n日期：2020年04月28日\n地点：安徽阜南县\n当事人：刘瑞虎\n平台：微信\n言论内容：《村干部的保护伞》《基层干部黑暗势力强大，以权栽赃陷害维权人》等”抹黑辱骂“县领导的文章\n处罚：有期徒刑1年3个月\n法律文书：（2020）皖1225刑初6号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:54.633197+12
1944	1960	【中国文字狱事件记录】\n日期：2020年04月28日\n地点：四川平昌县\n当事人：李飞\n平台：朋友圈、现实/打横幅\n言论内容：“辱骂党和国家领导人以及支持港独”\n处罚：有期徒刑10个月\n法律文书：（2020）川1923刑初15号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:54.678985+12
1945	1961	【中国文字狱事件记录】\n日期：2020年04月28日\n地点：广东中山市\n当事人：何某\n平台：推特\n言论内容：“诋毁中国共产党、损害国家形象、危害国家利益的虚假信息”\n处罚：起诉（寻衅滋事罪）\n法律文书：中检二区一部刑诉〔2020〕900号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:54.724118+12
1946	1962	【中国文字狱事件记录】\n日期：2020年04月29日\n地点：湖北罗田县\n当事人：冯汇川\n平台：微信群\n言论内容：“辱骂党和国家领导人、涉政有害信息“以及”诋毁党、政府及国家领导人的形象”\n处罚：有期徒刑10个月\n法律文书：（2020）鄂1123刑初46号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:54.771353+12
1947	1963	【中国文字狱事件记录】\n日期：2020年04月30日\n地点：海南大学\n当事人：王小妮\n身份：学者/教师（退休）\n平台：微博\n言论内容：支持占中运动；支持太阳花运动；批评毛泽东；批评学雷锋活动等（发表于11-14年间）\n处罚：已成立调查组调查	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:54.817333+12
1948	1964	【中国文字狱事件记录】\n日期：2020年04月30日\n地点：湖南桂阳县\n当事人：陈杰人\n平台：网络\n言论内容：”虚假信息或者负面信息，恶意炒作有关案事件，攻击、诋毁党政、司法机关及其工作人员“\n处罚：有期徒刑15年、罚款701万	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:54.863106+12
1949	1965	【中国文字狱事件记录】\n日期：2020年05月06日\n地点：广东揭西县\n当事人：曾某甲钦\n平台：微信与现实\n言论内容：发布其穿有美国国旗图案的衣服到朋友圈，配文“我支持美国”；当众焚烧中共党旗\n处罚：起诉（寻衅滋事罪）\n法律文书：揭西检一部刑诉〔2020〕47号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:54.91008+12
1950	1966	【中国文字狱事件记录】\n日期：2020年05月07日\n地点：哈尔滨师范大学\n当事人：于琳琦\n身份：学者/教师\n平台：微博\n言论内容：批评马克思；批评共产主义；批评中共；支持方方等（最早的内容发表于2011年）\n处罚：已成立调查组调查\n备注：2014年4月已被免职	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:54.95851+12
1951	1967	【中国文字狱事件记录】\n日期：2020年05月08日\n地点：四川邻水县\n当事人：许宽\n身份：退伍军人\n平台：推特\n言论内容：涉及香港重大事件的虚假信息、攻击国家领导人和中国政体的推文\n处罚：有期徒刑9个月\n法律文书：（2020）川1623刑初78号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:55.007179+12
1952	1968	【中国文字狱事件记录】\n日期：2020年05月09日\n地点：吉林吉林\n当事人：刘某\n平台：微信群\n言论内容：（视频）新冠肺炎病毒疫情扩散到吉林龙潭区铁东地区，现已在铁东街道办事处院内搭帐篷，严查舒兰输入人员\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:55.055098+12
1953	1969	【中国文字狱事件记录】\n日期：2020年05月11日\n地点：华东政法大学\n当事人：张雪忠\n身份：学者/教师；人权律师\n平台：不详\n言论内容：（公开信）呼吁尽早启动国民制宪程序，努力实现政治和平转型\n处罚：疑似被捕	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:55.100676+12
1954	1970	【中国文字狱事件记录】\n日期：2020年05月11日\n地点：四川成都\n当事人：谢俊彪\n平台：现实/举牌\n言论内容：戴表不为民做主，不如回家抓老鼠\n处罚：刑事拘留\n备注：6月9日取保候审	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:55.145893+12
1956	1972	【中国文字狱事件记录】\n日期：2020年05月14日\n地点：河南清丰县\n当事人：王喜全\n平台：微信公众平台\n言论内容：（在公安部悼念杨雪峰文章下评论）兔子急了还咬人呢；凶手是善良的，一个不折不扣的水浒英雄人物\n处罚：拘役3个月\n法律文书：（2020）豫0922刑初63号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:55.235173+12
1957	1973	【中国文字狱事件记录】\n日期：2020年05月15日\n地点：广东翁源县\n当事人：陈某\n平台：微信群\n言论内容：交警抢劫\n处罚：罚款100元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:55.2795+12
1958	1974	【中国文字狱事件记录】\n日期：2020年05月15日\n地点：河南南召县\n当事人：段某\n平台：朋友圈\n言论内容：一段“城管执法视频以及辱骂文字”\n处罚：拘留5日、罚款500元\n法律文书：召公（城）行罚决字［2020］193号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:55.32442+12
1959	1975	【中国文字狱事件记录】\n日期：2020年05月19日\n地点：河北沽源县\n当事人：王某\n平台：微博\n言论内容：沽源县**局不作为、多次举报无果、受贿等\n处罚：拘留4日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:55.369976+12
1960	1976	【中国文字狱事件记录】\n日期：2020年05月20日\n地点：天津\n当事人：金寿魁\n平台：网易新闻\n言论内容：“辱骂党和国家领导人”；“虚假信息”\n处罚：有期徒刑9个月\n法律文书：（2020）津0104刑初217号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:55.416986+12
1961	1977	【中国文字狱事件记录】\n日期：2020年05月21日\n地点：内蒙古赤峰\n当事人：王炜\n身份：公职人员/事业单位人员\n平台：大纪元、推特\n言论内容：攻击党和政府、支持香港反送中运动、赞同法轮功观点，发表三退声明\n背景事件：香港反送中示威\n处罚：有期徒刑4年、罚金5000元\n法律文书：（2020）内0403刑初21号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:55.459945+12
1962	1978	【中国文字狱事件记录】\n日期：2020年05月26日\n地点：北京\n当事人：许迪航\n平台：抖音、现实\n言论内容：向交警竖中指，并将过程拍摄视频发布至抖音\n处罚：有期徒刑7个月\n法律文书：（2020）京0102刑初217号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:55.506047+12
1963	1979	【中国文字狱事件记录】\n日期：2020年05月27日\n地点：广东翁源县\n当事人：冯某\n平台：微信群\n言论内容：交警收了黑钱要给开发商办事\n处罚：罚款100元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:55.550309+12
1964	1980	【中国文字狱事件记录】\n日期：2020年05月27日\n地点：广西百色\n当事人：赵某\n平台：朋友圈\n言论内容：这帮土非（吐舌表情）及交警照片\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:55.596908+12
1965	1981	【中国文字狱事件记录】\n日期：2020年05月29日\n地点：河南新野县\n当事人：杨泽乾\n平台：QQ群\n言论内容：”侮辱中国共产党和政府言论以及辱骂多名国家领导人“\n处罚：有期徒刑1年6个月\n法律文书：（2020）豫1329刑初132号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:55.645033+12
1966	1986	【中国文字狱事件记录】\n日期：2020年06月03日\n地点：云南昆明\n当事人：陈晋\n平台：多个平台\n言论内容：“侮辱”、“诽谤”云南政府、政府领导人、公务人员的言论和视频\n处罚：有期徒刑1年1个月\n法律文书：（2020）云0111刑初526号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:55.867068+12
1967	1987	【中国文字狱事件记录】\n日期：2020年06月03日\n地点：青海互助县\n当事人：李某某旦\n平台：微信群\n言论内容：“辱骂村干部”\n处罚：拘留4日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:55.911021+12
1968	1988	【中国文字狱事件记录】\n日期：2020年06月05日\n地点：河北高碑店市\n当事人：刘某\n平台：朋友圈\n言论内容：“辱警信息”\n处罚：拘留15日、罚款800元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:55.953782+12
1969	1989	【中国文字狱事件记录】\n日期：2020年06月05日\n地点：河北高碑店市\n当事人：刘某\n平台：朋友圈\n言论内容：不干人事……（指交警）\n处罚：拘留15日、罚款800元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:55.996243+12
1970	1990	【中国文字狱事件记录】\n日期：2020年06月05日\n地点：湖南株洲\n当事人：陈思明\n平台：现实/举牌\n言论内容：纪念六四31周年\n背景事件：六四事件\n处罚：拘留15日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:56.0404+12
1971	1992	【中国文字狱事件记录】\n日期：2020年06月08日\n地点：广州云端传媒有限公司\n当事人：蒋凯\n平台：微信公众平台\n言论内容：“张扣扣事件”、“上海交警事件”、“全国两会政策”等涉及国内重大事件等“虚假信息”\n处罚：有期徒刑1年2个月\n法律文书：（2020）粤0112刑初521号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:56.12769+12
1972	1993	【中国文字狱事件记录】\n日期：2020年06月09日\n地点：江苏连云港\n当事人：王洪全\n平台：中华新闻通讯社\n言论内容：创办《中华新闻通讯社》并运营，发表大量关于中共的负面报道\n处罚：有期徒刑1年6个月\n法律文书：（2020）苏0707刑初48号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:56.174313+12
1973	1994	【中国文字狱事件记录】\n日期：2020年06月09日\n地点：江苏连云港\n当事人：唐云立\n平台：中华新闻通讯社\n言论内容：担任《中华新闻通讯社》首席记者，在上面发表关于中共的负面报道\n处罚：有期徒刑1年1个月\n法律文书：（2020）苏0707刑初48号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:56.219644+12
1974	1995	【中国文字狱事件记录】\n日期：2020年06月16日\n地点：广西南宁\n当事人：邓某铧\n平台：网络\n言论内容：明园新都酒店接待了北京来的人，有20多人发烧，被集体隔离\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:56.265073+12
1975	1996	【中国文字狱事件记录】\n日期：2020年06月17日\n地点：广东深圳\n当事人：桑某\n平台：微信群\n言论内容：6月17日在辖区某地铁站发现确诊病例\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:56.309824+12
1976	1997	【中国文字狱事件记录】\n日期：2020年06月17日\n地点：四川资中县\n当事人：罗某\n平台：朋友圈\n言论内容：（交警执法照片）这些交警都不是个好东西……\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:56.354919+12
1977	1998	【中国文字狱事件记录】\n日期：2020年06月17日\n地点：西藏拉萨\n当事人：陈某\n平台：某社交软件\n言论内容：尼玛的，你们到底是有多缺钱\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:56.399031+12
1978	1999	【中国文字狱事件记录】\n日期：2020年06月19日\n地点：山东青岛\n当事人：王某\n平台：微博\n言论内容：黄岛交警，fu×k you，干你们全家！\n处罚：拘留15日、罚款1000元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:56.443147+12
1979	2000	【中国文字狱事件记录】\n日期：2020年06月19日\n地点：江西新余\n当事人：何某凤\n平台：朋友圈\n言论内容：大家别到处乱跑，疫情又来了，新余今天封了一个村”，“下村太桥，一个孕妇在北京回来生小孩子，确诊了\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:56.489449+12
1980	2001	【中国文字狱事件记录】\n日期：2020年06月19日\n地点：江西新余\n当事人：陈某文\n平台：朋友圈\n言论内容：（转发）大家别到处乱跑，疫情又来了，新余今天封了一个村”，“下村太桥，一个孕妇在北京回来生小孩子，确诊了\n背景事件：武汉新型冠状病毒肺炎\n处罚：罚款200元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:56.534132+12
1981	2002	【中国文字狱事件记录】\n日期：2020年06月20日\n地点：北京\n当事人：赵某\n平台：不详\n言论内容：死了40多万人\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:56.579323+12
1982	2003	【中国文字狱事件记录】\n日期：2020年06月20日\n地点：北京\n当事人：谭某克\n平台：微信私聊\n言论内容：新发地8300人检测结果：5800人阴性，其余2500人阳性，这个比例太恐怖了\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:56.62379+12
1983	2004	【中国文字狱事件记录】\n日期：2020年06月20日\n地点：北京\n当事人：吴某\n平台：微信群\n言论内容：（转发自谭某克）新发地8300人检测结果：5800人阴性，其余2500人阳性，这个比例太恐怖了\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:56.666568+12
1984	2005	【中国文字狱事件记录】\n日期：2020年06月20日\n地点：北京\n当事人：焦某涛\n平台：朋友圈\n言论内容：本人核酸检测阳性\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:56.711525+12
1985	2006	【中国文字狱事件记录】\n日期：2020年06月20日\n地点：北京\n当事人：刘某\n平台：网络\n言论内容：政府也不工作，这几天也没封闭新发地市场，也没核酸检测，死了几千北京人了\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:56.756784+12
1986	2007	【中国文字狱事件记录】\n日期：2020年06月22日\n地点：新疆乌鲁木齐\n当事人：李管\n平台：优酷、呼声网\n言论内容：《新疆李管及前妻维权事件》视频\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:56.803579+12
1987	2008	【中国文字狱事件记录】\n日期：2020年06月23日\n地点：陕西神木市\n当事人：李丽\n平台：多个平台\n言论内容：“神木假户口迷案”相关内容大量文章，指控当地政府与警察勾结办理大量假户口\n处罚：有期徒刑1年2个月\n法律文书：（2020）陕0881刑初55号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:56.8498+12
1988	2009	【中国文字狱事件记录】\n日期：2020年06月23日\n地点：广西宾阳县\n当事人：赵某令\n平台：微信\n言论内容：“侮辱当地一名在车祸中受伤的辅警”的言论\n处罚：拘留10日、罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:56.895544+12
1989	2010	【中国文字狱事件记录】\n日期：2020年06月23日\n地点：广西隆林县\n当事人：杨某\n平台：抖音\n言论内容：土匪抓车就在他大门口抓车，回不去啦！\n处罚：拘留10日、罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:56.942131+12
1990	2011	【中国文字狱事件记录】\n日期：2020年06月23日\n地点：广西宾阳县\n当事人：陈某还\n平台：网络\n言论内容：“侮辱当地一名在车祸中受伤的辅警”的言论\n处罚：拘留10日、罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:56.990453+12
1991	2012	【中国文字狱事件记录】\n日期：2020年06月23日\n地点：河北张北县\n当事人：武某\n平台：今日头条\n言论内容：河北张家口成龙学校，发现一例冠肺感染者，和沽源一个病源\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:57.03794+12
1992	2013	【中国文字狱事件记录】\n日期：2020年06月24日\n地点：广西宾阳县\n当事人：不详（2人）\n平台：微信群\n言论内容：“辱骂警察”的言论\n处罚：拘留10日、罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:57.083039+12
1993	2014	【中国文字狱事件记录】\n日期：2020年06月24日\n地点：江苏涟水县\n当事人：刘治雄\n平台：推特\n言论内容：指责、辱骂、诋毁中共领导和、宣传纪念六四、支持港独台独、诋毁国家政治制度的内容\n处罚：有期徒刑1年\n法律文书：（2019）苏0826刑初385号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:57.130207+12
1994	2015	【中国文字狱事件记录】\n日期：2020年06月26日\n地点：广西昭平县\n当事人：陆某\n平台：微信群\n言论内容：检查三次全是阳性，已确诊，现在封楼了，你们大家要买口罩就买啵，看完信息不要举报我，是真的的\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:57.178093+12
1995	2016	【中国文字狱事件记录】\n日期：2020年06月26日\n地点：广西隆林县\n当事人：黄某辉\n平台：朋友圈\n言论内容：老车站今晚有点过分了 这邦狗\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:57.226843+12
1996	2017	【中国文字狱事件记录】\n日期：2020年06月28日\n地点：辽宁大连\n当事人：姚永生\n平台：推特\n言论内容：关注纽约时报、美国驻华使领馆和自由亚洲电台等经常发布“不实信息”的账号，转发28条和主动发布1条“不实信息”\n处罚：有期徒刑6个月\n法律文书：（2020）辽0291刑初200号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:57.275666+12
1997	2018	【中国文字狱事件记录】\n日期：2020年06月28日\n地点：辽宁沈阳\n当事人：田野\n平台：朋友圈\n言论内容：“侮辱公安机关、检察机关及国家领导人”的言论\n处罚：有期徒刑9个月\n法律文书：（2020）辽0103刑初381号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:57.314628+12
1998	2019	【中国文字狱事件记录】\n日期：2020年06月29日\n地点：山西太原\n当事人：高志刚\n平台：微信私聊\n言论内容：号召参与“全民共振”的视频\n处罚：有期徒刑10个月	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:57.352548+12
1999	2020	【中国文字狱事件记录】\n日期：2020年06月29日\n地点：北京\n当事人：刘某全\n平台：微信群\n言论内容：美高美新增23个病例在确认前将丰台区云冈周围的超市逛了个遍\n背景事件：武汉新型冠状病毒肺炎\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:57.391004+12
2000	2021	【中国文字狱事件记录】\n日期：2020年06月29日\n地点：陕西商南县\n当事人：王小红\n平台：推特\n言论内容：就他人转发的申纪兰去世的推文下进行不当评论，辱骂申纪兰\n处罚：拘留15日\n法律文书：商南公(61252430)行罚决字［2020］259号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:57.427819+12
2001	2022	【中国文字狱事件记录】\n日期：2020年06月30日\n地点：河北唐山\n当事人：仇建正\n平台：推特\n言论内容：”污蔑党和国家领导人，诋毁国家政权和社会主义制度“的内容\n处罚：有期徒刑10个月\n法律文书：（2020）冀02刑初9号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:57.466022+12
2002	2023	【中国文字狱事件记录】\n日期：2020年06月30日\n地点：江苏常熟市\n当事人：王某\n平台：朋友圈\n言论内容：忙碌的同时被日本鬼子逮住，扣三分罚款一百元\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:57.507347+12
2028	2049	【中国文字狱事件记录】\n日期：2020年07月23日\n地点：宁夏银川\n当事人：古某\n平台：推特\n言论内容：攻击我国现行社会制度、煽动颠覆国家政权等言论\n处罚：有期徒刑2年\n法律文书：（2020）宁0105刑初82号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:58.576042+12
2003	2024	【中国文字狱事件记录】\n日期：2020年07月01日\n地点：湖南临湘市\n当事人：谢某华\n平台：微信\n言论内容：城管暴力执法，打得我和我老婆还有我妹妹只有进的气没有出的气了\n处罚：拘留10日\n法律文书：临公（云）决字［2020］第0226号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:57.547962+12
2004	2025	【中国文字狱事件记录】\n日期：2020年07月01日\n地点：安徽舒城县\n当事人：张某\n平台：抖音\n言论内容：（视频）村主任对此事（塌方）不管不问\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:57.586068+12
2005	2026	【中国文字狱事件记录】\n日期：2020年07月04日\n地点：广东陆丰\n当事人：陈某州\n平台：抖音\n言论内容："辱骂镇政府的视频"\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:57.624253+12
2006	2027	【中国文字狱事件记录】\n日期：2020年07月06日\n地点：湖南慈利县\n当事人：罗雪翠\n平台：微信公众平台\n言论内容：某地村干部要在扫黑除恶行动后弄死实名举报人；上访\n处罚：有期徒刑1年4个月\n法律文书：（2020）湘0821刑初37号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:57.661902+12
2007	2028	【中国文字狱事件记录】\n日期：2020年07月06日\n地点：湖南慈利县\n当事人：胡君\n平台：微信公众平台\n言论内容：某地村干部要在扫黑除恶行动后弄死实名举报人\n处罚：有期徒刑1年\n法律文书：（2020）湘0821刑初37号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:57.698534+12
2008	2029	【中国文字狱事件记录】\n日期：2020年07月06日\n地点：广东广州\n当事人：陈宗\n平台：微信群\n言论内容：从境外网站转发的“虚假信息”\n处罚：有期徒刑1年3个月\n法律文书：（2020）粤0103刑初61号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:57.736902+12
2009	2030	【中国文字狱事件记录】\n日期：2020年07月06日\n地点：江苏泗阳县\n当事人：刘某\n平台：微博\n言论内容：”不当言论“\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:57.773321+12
2010	2031	【中国文字狱事件记录】\n日期：2020年07月06日\n地点：河南修武县\n当事人：苏某\n平台：微信群\n言论内容：“辱骂村干部的言论”\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:57.812437+12
2011	2032	【中国文字狱事件记录】\n日期：2020年07月06日\n地点：宁夏银川\n当事人：李某\n平台：贴吧\n言论内容：如狼似虎啊的兴庆区交通警察支队，像狗一样的无事生非，处罚过路行人，如此行为，莫名其妙\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:57.856225+12
2012	2033	【中国文字狱事件记录】\n日期：2020年07月07日\n地点：重庆\n当事人：吴欣玥（未成年）\n平台：aidezy.com（其自有）\n言论内容：翻墙教程\n处罚：口头警告	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:57.903988+12
2013	2034	【中国文字狱事件记录】\n日期：2020年07月07日\n地点：宁夏银川\n当事人：李某\n平台：朋友圈\n言论内容：“辱骂交警”的言论\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:57.947617+12
2014	2035	【中国文字狱事件记录】\n日期：2020年07月07日\n地点：河南新密市\n当事人：甄某方\n平台：朋友圈\n言论内容：“辱骂交警的言论”\n处罚：拘留5日、罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:57.992021+12
2015	2036	【中国文字狱事件记录】\n日期：2020年07月08日\n地点：江苏射阳县\n当事人：郑海涛\n平台：微博、微信公众平台\n言论内容：《被告步步为营操控、法院甘心为奴再审——关于射阳法院XXX等人涉嫌违法办案的公开信》和类似文章\n处罚：拘留10日、罚款10万元\n法律文书：（2020）苏0924司惩1号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:58.038287+12
2016	2037	【中国文字狱事件记录】\n日期：2020年07月08日\n地点：江苏扬州\n当事人：吴大维\n平台：推特\n言论内容：“侮辱国家领导人、诋毁共产党、支持台独、支持香港暴乱等言论“\n背景事件：香港反送中示威\n处罚：有期徒刑1年\n法律文书：（2020）苏1091刑初3号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:58.085771+12
2017	2038	【中国文字狱事件记录】\n日期：2020年07月09日\n地点：黑龙江龙江县\n当事人：王某\n平台：微信群\n言论内容：“辱骂派出所”\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:58.133161+12
2018	2039	【中国文字狱事件记录】\n日期：2020年07月09日\n地点：安徽歙县\n当事人：黄某华\n平台：朋友圈\n言论内容：习近平到黄山歙县潭渡村黎明（视察水灾）\n背景事件：2020南方洪灾\n处罚：罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:58.177868+12
2019	2040	【中国文字狱事件记录】\n日期：2020年07月10日\n地点：云南丘北县\n当事人：简某\n平台：微博\n言论内容：云南省文山州丘北县普者黑黑恶势力猖獗……希望当地警方可以严肃处理\n处罚：罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:58.222564+12
2020	2041	【中国文字狱事件记录】\n日期：2020年07月11日\n地点：江苏苏州\n当事人：朱承志\n平台：脸书、推特\n言论内容：大量“严重损害国家形象”和“严重危害国家利益”的内容，例如攻击国家领导人、国家政体等\n处罚：有期徒刑3年6个月\n备注：二审维持原判\n法律文书：（2019）苏0506刑初537号；（2020）苏05刑终660号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:58.268004+12
2021	2042	【中国文字狱事件记录】\n日期：2020年07月14日\n地点：天津\n当事人：宋洁\n平台：微博\n言论内容：公安机关参与强拆、对宋洁报案事项不予立案等“不实言论”\n处罚：拘留5日\n法律文书：津公（双桥）行罚决字[2020]759号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:58.307496+12
2022	2043	【中国文字狱事件记录】\n日期：2020年07月15日\n地点：清华大学\n当事人：许章润\n身份：学者/教师\n平台：著书\n言论内容：《戊戌六章》等异见文章\n处罚：开除\n备注：已于2019年被停职	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:58.343132+12
2023	2044	【中国文字狱事件记录】\n日期：2020年07月15日\n地点：河南开封\n当事人：朱某伟\n平台：微信群\n言论内容：”关于开封村镇银行不实信息“（导致大量储户集中取款）\n背景事件：河南多家村镇银行暴雷\n处罚：行政拘留\n备注：两年后谣言应验	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:58.380345+12
2024	2045	【中国文字狱事件记录】\n日期：2020年07月17日\n地点：云南丘北县\n当事人：刘某\n平台：朋友圈\n言论内容：XXXX，又克了老子3分150元\n处罚：拘留6日、罚款300元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:58.417213+12
2025	2046	【中国文字狱事件记录】\n日期：2020年07月18日\n地点：湖南岳阳县\n当事人：付某\n平台：朋友圈\n言论内容：”辱骂交警执法人员“\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:58.454175+12
2026	2047	【中国文字狱事件记录】\n日期：2020年07月19日\n地点：山东青岛\n当事人：吴某\n平台：微信群\n言论内容：“辱骂村干部”\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:58.49143+12
2027	2048	【中国文字狱事件记录】\n日期：2020年07月22日\n地点：辽宁沈阳\n当事人：李某\n平台：朋友圈\n言论内容：“辱警信息”\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:58.532252+12
2029	2050	【中国文字狱事件记录】\n日期：2020年07月23日\n地点：广东阳春市\n当事人：李某\n平台：抖音、朋友圈\n言论内容：天下乌鸦一般黑，恶霸和派出所人同流合污\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:58.621229+12
2030	2051	【中国文字狱事件记录】\n日期：2020年07月26日\n地点：山西临汾\n当事人：白某\n平台：朋友圈\n言论内容：这些狗大晚上的都不得消停，大半夜的给我整了个逆行\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:58.665407+12
2031	2052	【中国文字狱事件记录】\n日期：2020年07月27日\n地点：广西梧州\n当事人：黄某\n平台：微信群\n言论内容：多条视频，内容为“交警在长洲区某十字路口处依法依规查车的视频, 拍摄者说脏话”\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:58.709736+12
2032	2053	【中国文字狱事件记录】\n日期：2020年07月27日\n地点：广东东源县\n当事人：张国兵\n平台：推特、微信\n言论内容：转发多条“诋毁党政、国家领导人、抨击国家制度”的推文和在微信发布“虚假信息”\n处罚：有期徒刑2年9个月\n法律文书：（2020）粤1625刑初86号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:58.752275+12
2033	2054	【中国文字狱事件记录】\n日期：2020年07月27日\n地点：河南洛阳\n当事人：毛某娜\n平台：网络\n言论内容：没有乱停，没有占道，没有影响交通，售楼部一打电话，交警孩子就来了，真是听他们父母的话\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:58.791394+12
2034	2055	【中国文字狱事件记录】\n日期：2020年07月28日\n地点：湖北钟祥市\n当事人：黄某国\n平台：网络\n言论内容：（评论某段交警执法视频）辱警言论\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:58.829467+12
2035	2056	【中国文字狱事件记录】\n日期：2020年07月28日\n地点：山东济南\n当事人：于新永\n平台：网络、现实\n言论内容：在多地举牌i”信访口号“以及在网络声援他人维权\n处罚：有期徒刑4年6个月\n备注：二审维持原判\n法律文书：（2018）鲁0102刑初502号；（2020）鲁01刑终322号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:58.868831+12
2036	2057	【中国文字狱事件记录】\n日期：2020年07月29日\n地点：湖南邵阳县\n当事人：管正国\n平台：中国观察杂志\n言论内容：《病亡家属指控湖南邵阳县人民医院走私贩卖人体器官刻意致人死亡》\n处罚：有期徒刑1年6个月\n法律文书：（2020）湘0523刑初107号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:58.906658+12
2037	2058	【中国文字狱事件记录】\n日期：2020年07月29日\n地点：福建莆田\n当事人：郑某\n平台：朋友圈\n言论内容：现在的交警就跟土匪没区别，还是正规的土匪，道德沦丧，毫无人性，光天化日之下举证抢劫\n处罚：拘留4日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:58.944905+12
2038	2059	【中国文字狱事件记录】\n日期：2020年07月29日\n地点：福建仙游县\n当事人：郑某\n平台：朋友圈\n言论内容：现在的大济交警就跟土匪没什么区别……道德沦丧、毫无人性、天理难容……\n处罚：拘留4日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:58.985492+12
2039	2060	【中国文字狱事件记录】\n日期：2020年07月30日\n地点：四川仁寿县\n当事人：胡某\n平台：微博\n言论内容：谁支持你这个人渣败类干这种毫无人性的暴力执法；奇葩仁寿县派出所民警，黑白颠倒，扭曲事实\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:59.028073+12
2040	2061	【中国文字狱事件记录】\n日期：2020年07月31日\n地点：云南瑞丽市\n当事人：刘某\n平台：微信\n言论内容：“严重损害国家形象的虚假信息”\n处罚：有期徒刑2年、缓刑3年\n法律文书：（2020）云3102刑初34号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:59.072864+12
2041	2062	【中国文字狱事件记录】\n日期：2020年07月31日\n地点：云南宾川县\n当事人：“紫气东来”\n平台：微博\n言论内容：宾川交警乱开罚单，拦路抢劫\n处罚：拘留8日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:59.118675+12
2042	2063	【中国文字狱事件记录】\n日期：2020年08月03日\n地点：湖北武汉\n当事人：吴勇\n平台：QQ群、中革中央网站\n言论内容：宣“中革中央”、“中国真共产党”等言论；侮辱国家领导人的文字，非法存储侮辱国家领导人的图片\n处罚：有期徒刑1年2个月\n备注：曾于2018/9/18被判刑8个月\n法律文书：（2020）鄂0111刑初473号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:59.174267+12
2043	2064	【中国文字狱事件记录】\n日期：2020年08月05日\n地点：贵州遵义\n当事人：卢昱宇\n平台：推特\n言论内容：《不正确的记忆》（其在狱中服刑经历，包括其遭受酷刑）\n处罚：书面警告\n法律文书：播公（遵南）行罚决字［2020］3622号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:59.222738+12
2044	2065	【中国文字狱事件记录】\n日期：2020年08月05日\n地点：青海西宁\n当事人：鲜桐\n平台：推特\n言论内容：“抨击、诋毁中国共产党、国家领导人、民族问题、武汉疫情等不实言论共计148条”\n背景事件：武汉新型冠状病毒肺炎\n处罚：有期徒刑10个月\n法律文书：（2020）青0102刑初170号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:59.271737+12
2045	2066	【中国文字狱事件记录】\n日期：2020年08月08日\n地点：安徽休宁县\n当事人：戴某\n平台：朋友圈\n言论内容：镇政府人员工作的小视频，并配有“辱骂性”的文字\n处罚：拘留6日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:59.320919+12
2046	2067	【中国文字狱事件记录】\n日期：2020年08月11日\n地点：上海\n当事人：俞某\n平台：推特\n言论内容：“涉及我国抗击新冠肺炎疫情的不实言论及诋毁我国政治制度、国内重大事件、国家领导人的推文”\n背景事件：武汉新型冠状病毒肺炎\n处罚：有期徒刑1年\n法律文书：（2020）沪0109刑初488号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:59.36849+12
2047	2068	【中国文字狱事件记录】\n日期：2020年08月11日\n地点：湖南纲维律师事务所\n当事人：谢阳\n身份：律师\n平台：网络、现实\n言论内容：声援良心犯、“辱骂法官”和在网络发表“煽动颠覆国家政权的言论”\n处罚：吊销律师资格证\n法律文书：湘司罚决［2020］8号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:59.417623+12
2048	2069	【中国文字狱事件记录】\n日期：2020年08月12日\n地点：陕西志丹县\n当事人：刘汉锋\n平台：天涯社区\n言论内容：其父刘某乙的死亡系被他人殴打所致、其哥刘某甲的自杀、其嫂刘某庚被他人殴打、以及官员腐败等\n处罚：有期徒刑1年\n备注：二审维持原判\n法律文书：(2019)陕0625刑初164号；（2020）陕06刑终171号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:59.472817+12
2049	2070	【中国文字狱事件记录】\n日期：2020年08月12日\n地点：广东汕尾\n当事人：张某\n平台：网络\n言论内容：关于交警执法的“不实言论”\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:59.518822+12
2050	2071	【中国文字狱事件记录】\n日期：2020年08月15日\n地点：四川彭州市\n当事人：胡祖刚\n平台：电报\n言论内容：”不当言论“（据其本人称是声援香港抗争者和谴责中共在新疆开设再教育营的言论）\n处罚：拘留15日\n法律文书：彭公（光）行罚决字［2020］1663号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:59.56523+12
2051	2072	【中国文字狱事件记录】\n日期：2020年08月17日\n地点：河南伊川县\n当事人：曹某军\n平台：微信群\n言论内容：憋孙真敬业啊！你们谁上班有这敬业！以后不要抱怨老板开工资少啊\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:59.611979+12
2052	2073	【中国文字狱事件记录】\n日期：2020年08月17日\n地点：中共中央党校\n当事人：蔡霞\n身份：学者/教师（退休）\n平台：现实/讲话\n言论内容：中共是政治僵尸、习近平是黑帮老大等“有严重政治问题和损害国家形象的言论”\n处罚：开除党籍、取消退休福利	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:59.657485+12
2053	2074	【中国文字狱事件记录】\n日期：2020年08月17日\n地点：北京\n当事人：王某\n平台：推特\n言论内容：“辱骂他人，虚假信息以及煽动性言论“\n处罚：起诉（寻衅滋事罪）\n法律文书：京朝检公诉刑诉〔2020〕1563号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:59.703812+12
2054	2075	【中国文字狱事件记录】\n日期：2020年08月18日\n地点：广西乐业县\n当事人：姚某\n平台：微信群\n言论内容：乐业交警就他们一群合法的黑社会组织，那天民意调查老子不会讲好话的\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:59.748925+12
2055	2076	【中国文字狱事件记录】\n日期：2020年08月21日\n地点：山东日照\n当事人：相某\n平台：微信群\n言论内容：也是那瘪犊子（指交警）\n处罚：拘留5日、罚款200元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:59.796551+12
2056	2077	【中国文字狱事件记录】\n日期：2020年08月21日\n地点：山东日照\n当事人：刘某\n平台：微信群\n言论内容：都是捏畜生干的（指交警）\n处罚：拘留5日、罚款200元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:59.841733+12
2057	2078	【中国文字狱事件记录】\n日期：2020年08月25日\n地点：河南伊川县\n当事人：赵某\n平台：朋友圈\n言论内容：伊川的交警真他妈厉害，靠这发家致富呢\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:59.882225+12
2058	2079	【中国文字狱事件记录】\n日期：2020年08月28日\n地点：河北昌黎县\n当事人：曾宪会\n平台：今日头条\n言论内容：昌黎县公安局黄金海岸边防派出所为黑社会组织保护伞等\n处罚：有期徒刑1年\n法律文书：（2020）冀0322刑初110号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:59.920302+12
2059	2080	【中国文字狱事件记录】\n日期：2020年08月28日\n地点：山东蒙阴县体育中心\n当事人：公维强（办公室主任）\n身份：党政官员\n平台：微信群\n言论内容：马克思说过，黑暗的专制东方，只有罪恶的轮回\n处罚：免职	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:59.957822+12
2060	2081	【中国文字狱事件记录】\n日期：2020年08月30日\n地点：山东肥城市\n当事人：刘某\n平台：网络\n言论内容：“辱骂警察”的言论\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:05:59.99541+12
2061	2082	【中国文字狱事件记录】\n日期：2020年08月31日\n地点：山东烟台\n当事人：王建军\n身份：公职人员/事业单位人员\n平台：推特\n言论内容：“侮辱国家领导人和诋毁中国共产党执政”的言论\n处罚：有期徒刑1年\n备注：二审维持原判\n法律文书：（2020）鲁0691刑初106号；（2020）鲁06刑终387号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:00.032202+12
2062	2083	【中国文字狱事件记录】\n日期：2020年08月31日\n地点：湖北武汉\n当事人：谢某\n平台：网络\n言论内容：某小学出现一例发热病症核酸阳性\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:00.068857+12
2063	2084	【中国文字狱事件记录】\n日期：2020年09月01日\n地点：内蒙古阿鲁科尔沁旗\n当事人：乌某\n平台：微信群\n言论内容：（转发，视频）通辽某学校不让学生出去，导致一名五年级学生跳楼\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:00.106247+12
2064	2224	【中国文字狱事件记录】\n日期：2021年05月22日\n地点：广东江门\n当事人：黄某\n平台：朋友圈\n言论内容：针对袁隆平院士的“侮辱性”言论\n背景事件：袁隆平去世\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:07.11605+12
2065	2085	【中国文字狱事件记录】\n日期：2020年09月02日\n地点：辽宁本溪\n当事人：梁某\n平台：朋友圈\n言论内容：这倒逼警察越指挥越堵车！绿灯不让走！指挥滴四条路都堵死了！\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:00.14349+12
2066	2086	【中国文字狱事件记录】\n日期：2020年09月03日\n地点：北京\n当事人：范继福\n平台：微信群\n言论内容：各位同学真的要注意了！今日北京王府井百货大楼确诊1例，要做好个人防护！并提醒家人！\n背景事件：武汉新型冠状病毒肺炎\n处罚：有期徒刑6个月\n法律文书：（2020）京0101刑初432号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:00.182593+12
2067	2087	【中国文字狱事件记录】\n日期：2020年09月03日\n地点：四川泸定县\n当事人：程玄鑫\n平台：推特\n言论内容：大量虚假信息，危害公共安全的反动宣传信息\n处罚：有期徒刑2年\n法律文书：（2020）川3322刑初10号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:00.220845+12
2068	2088	【中国文字狱事件记录】\n日期：2020年09月08日\n地点：浙江缙云县\n当事人：曹金炜\n平台：微信群\n言论内容：让习大大做中国梦，我们做做春梦就好；跳楼惊动新省委书记，就会有人要倒霉\n处罚：拘留5日\n法律文书：缙公（壶）行罚决字[2020]01770号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:00.261822+12
2069	2089	【中国文字狱事件记录】\n日期：2020年09月08日\n地点：河北三河市\n当事人：张文芳（玛丽莲梦六）\n平台：微博\n言论内容：一条长微博，其中包含数十条武汉封城期间的民间惨状\n背景事件：武汉新型冠状病毒肺炎\n处罚：有期徒刑6个月\n法律文书：（2020）冀1082刑初263号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:00.314335+12
2070	2090	【中国文字狱事件记录】\n日期：2020年09月08日\n地点：山东枣庄\n当事人：张超（释道果）\n身份：佛教徒\n平台：推特\n言论内容：“涉政不法推文“，内容明显”攻击抹黑他人、中国共产党和社会制度“\n处罚：有期徒刑1年8个月\n法律文书：（2020）鲁0406刑初75号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:00.363278+12
2071	2091	【中国文字狱事件记录】\n日期：2020年09月09日\n地点：北京\n当事人：耿潇男\n平台：网络、现实\n言论内容：声援多位良心犯，“我做不了英雄，但可以为英雄献花和欢呼，为英雄牵马，为英雄挡枪子儿，为英雄收尸”\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:00.415966+12
2072	2092	【中国文字狱事件记录】\n日期：2020年09月10日\n地点：河北大厂县\n当事人：陈湘鹏\n平台：朋友圈\n言论内容：就“全国抗击新冠肺炎表彰大会”发表“不正当言论”\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日\n法律文书：廊大厂公（夏）行罚决字［2020］0410号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:00.474243+12
2073	2093	【中国文字狱事件记录】\n日期：2020年09月10日\n地点：浙江台州\n当事人：杨某明\n平台：朋友圈\n言论内容：这些畜生！停店门口也要贴！\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:00.550869+12
2074	2094	【中国文字狱事件记录】\n日期：2020年09月14日\n地点：辽宁大连\n当事人：渠某\n平台：推特\n言论内容：“涉党、政治体系、侮辱国家领导人等各类不当言论”\n处罚：起诉（寻衅滋事罪）\n法律文书：旅检公诉刑诉〔2020〕204号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:00.603967+12
2075	2095	【中国文字狱事件记录】\n日期：2020年09月15日\n地点：云南华坪县\n当事人：张某\n平台：朋友圈\n言论内容：天星加油站有土狼，撒班孩勒，注意，还有安全带，我已经着了\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:00.655261+12
2076	2096	【中国文字狱事件记录】\n日期：2020年09月16日\n地点：湖北云梦县\n当事人：王尊建\n平台：网络、现实\n言论内容：声援良心犯内容、报道社会热点事件内容、支持香港反送中运动、纪念六四等\n背景事件：香港反送中示威；六四事件\n处罚：有期徒刑2年6个月\n备注：二审维持原判\n法律文书：（2020）鄂0923刑初99号；（2020）鄂09刑终207号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:00.711779+12
2077	2097	【中国文字狱事件记录】\n日期：2020年09月17日\n地点：广东汕头\n当事人：李某玲\n平台：微博\n言论内容：当地即将捕杀流浪狗以及“不当言论”\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:00.774123+12
2078	2098	【中国文字狱事件记录】\n日期：2020年09月17日\n地点：黑龙江富裕县\n当事人：李某\n平台：QQ群\n言论内容：“诋毁、辱骂党和国家及国家领导人的不当言论”\n处罚：起诉（寻衅滋事罪）\n法律文书：黑富裕检刑诉〔2020〕120号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:00.819205+12
2079	2099	【中国文字狱事件记录】\n日期：2020年09月18日\n地点：浙江龙港市\n当事人：蔡祖成\n身份：律师\n平台：微博\n言论内容：我有一个让祖国和平统一的好办法：解散中共，推举蔡英文为临时大总统，之后再选举正式大总统\n处罚：拘留13日、罚款1000元\n法律文书：龙公（城南）行罚决字[2020]01177号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:00.864099+12
2080	2100	【中国文字狱事件记录】\n日期：2020年09月18日\n地点：江苏徐州\n当事人：黄根宝\n平台：推特\n言论内容：“辱骂国家领导人”和散布“损害国家形象和危害国家利益的虚假信息”\n处罚：有期徒刑1年4个月\n法律文书：（2020）苏0302刑初39号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:00.908361+12
2081	2101	【中国文字狱事件记录】\n日期：2020年09月22日\n地点：陕西洛南县\n当事人：张某\n平台：抖音\n言论内容：“侮辱谩骂”村干部\n处罚：拘留7日、罚款200元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:00.948288+12
2082	2102	【中国文字狱事件记录】\n日期：2020年09月22日\n地点：北京\n当事人：任志强\n身份：党政官员\n平台：网络\n言论内容：批评中国当局应对疫情严重失职，还暗示习近平是“剥光了衣服也要坚持当皇帝的小丑”\n处罚：有期徒刑18年	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:00.990705+12
2083	2103	【中国文字狱事件记录】\n日期：2020年09月23日\n地点：陕西咸阳\n当事人：陈鹰军\n平台：QQ群\n言论内容：“涉政谣言”（疑似郭文贵爆料内容）\n背景事件：郭文贵爆料事件\n处罚：有期徒刑3年\n法律文书：（2020）陕0402刑初110号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:01.036862+12
2084	2104	【中国文字狱事件记录】\n日期：2020年09月23日\n地点：陕西咸阳\n当事人：王兴杰\n平台：QQ群\n言论内容：“涉政谣言”（疑似郭文贵爆料内容）\n背景事件：郭文贵爆料事件\n处罚：有期徒刑1年9个月\n法律文书：（2020）陕0402刑初110号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:01.080348+12
2085	2105	【中国文字狱事件记录】\n日期：2020年09月23日\n地点：陕西咸阳\n当事人：卢向辉\n平台：QQ群\n言论内容：“涉政谣言”（疑似郭文贵爆料内容）\n背景事件：郭文贵爆料事件\n处罚：有期徒刑1年9个月\n法律文书：（2020）陕0402刑初110号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:01.126145+12
2086	2106	【中国文字狱事件记录】\n日期：2020年09月23日\n地点：陕西咸阳\n当事人：刘芗\n平台：QQ群\n言论内容：“涉政谣言”（疑似郭文贵爆料内容）\n背景事件：郭文贵爆料事件\n处罚：有期徒刑1年7个月\n法律文书：（2020）陕0402刑初110号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:01.168578+12
2087	2280	【中国文字狱事件记录】\n日期：2021年08月05日\n地点：陕西西安\n当事人：陈某\n平台：微博\n言论内容：“辱警”言论\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:10.257459+12
2088	2107	【中国文字狱事件记录】\n日期：2020年09月23日\n地点：陕西咸阳\n当事人：周昱\n平台：QQ群\n言论内容：“涉政谣言”（疑似郭文贵爆料内容）\n背景事件：郭文贵爆料事件\n处罚：有期徒刑1年7个月\n法律文书：（2020）陕0402刑初110号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:01.213156+12
2089	2108	【中国文字狱事件记录】\n日期：2020年09月23日\n地点：陕西咸阳\n当事人：朱远亮\n平台：QQ群\n言论内容：“涉政谣言”（疑似郭文贵爆料内容）\n背景事件：郭文贵爆料事件\n处罚：有期徒刑1年7个月\n法律文书：（2020）陕0402刑初110号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:01.256833+12
2090	2109	【中国文字狱事件记录】\n日期：2020年09月23日\n地点：陕西咸阳\n当事人：李好轩\n平台：QQ群\n言论内容：“涉政谣言”（疑似郭文贵爆料内容）\n背景事件：郭文贵爆料事件\n处罚：有期徒刑1年7个月\n法律文书：（2020）陕0402刑初110号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:01.303481+12
2091	2110	【中国文字狱事件记录】\n日期：2020年09月23日\n地点：陕西咸阳\n当事人：徐海波\n平台：QQ群\n言论内容：“涉政谣言”（疑似郭文贵爆料内容）\n背景事件：郭文贵爆料事件\n处罚：有期徒刑1年7个月\n法律文书：（2020）陕0402刑初110号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:01.348499+12
2092	2111	【中国文字狱事件记录】\n日期：2020年09月23日\n地点：陕西咸阳\n当事人：李泰营\n平台：QQ群\n言论内容：“涉政谣言”（疑似郭文贵爆料内容）\n背景事件：郭文贵爆料事件\n处罚：有期徒刑1年7个月\n法律文书：（2020）陕0402刑初110号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:01.395255+12
2093	2112	【中国文字狱事件记录】\n日期：2020年09月23日\n地点：陕西咸阳\n当事人：周富坪\n平台：QQ群\n言论内容：“涉政谣言”（疑似郭文贵爆料内容）\n背景事件：郭文贵爆料事件\n处罚：有期徒刑1年7个月\n法律文书：（2020）陕0402刑初110号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:01.441593+12
2094	2113	【中国文字狱事件记录】\n日期：2020年09月23日\n地点：陕西咸阳\n当事人：潘建\n平台：QQ群\n言论内容：“涉政谣言”（疑似郭文贵爆料内容）\n背景事件：郭文贵爆料事件\n处罚：有期徒刑1年7个月\n法律文书：（2020）陕0402刑初110号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:01.491292+12
2095	2114	【中国文字狱事件记录】\n日期：2020年09月23日\n地点：陕西咸阳\n当事人：廖焕华\n平台：QQ群\n言论内容：“涉政谣言”（疑似郭文贵爆料内容）\n背景事件：郭文贵爆料事件\n处罚：有期徒刑1年6个月\n法律文书：（2020）陕0402刑初110号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:01.538476+12
2096	2115	【中国文字狱事件记录】\n日期：2020年09月23日\n地点：陕西咸阳\n当事人：武刚\n平台：QQ群\n言论内容：“涉政谣言”（疑似郭文贵爆料内容）\n背景事件：郭文贵爆料事件\n处罚：有期徒刑1年6个月\n法律文书：（2020）陕0402刑初110号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:01.594884+12
2097	2116	【中国文字狱事件记录】\n日期：2020年09月23日\n地点：陕西咸阳\n当事人：不详\n平台：微博\n言论内容：咸阳是玉泉路彩虹高架十字，创文XX比，平时和X一样\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:01.646279+12
2098	2117	【中国文字狱事件记录】\n日期：2020年09月27日\n地点：陕西渭南\n当事人：王景景\n平台：微信私聊\n言论内容：《关于对仓程路百合园小区实施隔离封闭管理公告》\n背景事件：武汉新型冠状病毒肺炎\n处罚：有罪免罚\n备注：谣言发布5天后成真\n法律文书：（2020）陕0502刑初200号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:01.690767+12
2099	2118	【中国文字狱事件记录】\n日期：2020年09月27日\n地点：河南嵩县\n当事人：姚某\n平台：推特\n言论内容：“疫情涉政虚假信息”37条，其中24条原创，13条转发\n背景事件：武汉新型冠状病毒肺炎\n处罚：有期徒刑6个月\n法律文书：（2020）豫0325刑初240号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:01.733516+12
2100	2119	【中国文字狱事件记录】\n日期：2020年09月28日\n地点：山西新绛县\n当事人：宋某\n平台：多个平台\n言论内容：维权信息、“丑化国家的信息、反动信息、诋毁国家领导人和丑化计划生育政策的信息”等\n处罚：有期徒刑10个月\n法律文书：（2020）晋0825刑初124号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:01.776704+12
2101	2120	【中国文字狱事件记录】\n日期：2020年09月29日\n地点：广西金秀县\n当事人：莫某梅\n平台：朋友圈\n言论内容：真的是人在做，天在看，真的是报应来的，所以说阿！不要因为你的皮就狗眼看人低，真是活该\n背景事件：当地某警察遇袭受伤\n处罚：拘留15日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:01.820858+12
2102	2121	【中国文字狱事件记录】\n日期：2020年09月29日\n地点：山西阳泉\n当事人：王海余\n平台：脸书\n言论内容：100余条“虚假信息”\n处罚：有期徒刑1年6个月\n法律文书：（2020）晋0302刑初265号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:01.863779+12
2103	2122	【中国文字狱事件记录】\n日期：2020年10月09日\n地点：江西樟树市\n当事人：徐某\n平台：推特\n言论内容：“涉疫虚假信息”\n背景事件：武汉新型冠状病毒肺炎\n处罚：起诉（寻衅滋事罪）	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:01.907782+12
2104	2123	【中国文字狱事件记录】\n日期：2020年10月10日\n地点：河北蔚县\n当事人：李某\n平台：微信群\n言论内容：一张交警当街小便的图片，上面写有“这就是蔚县交警的素质”\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:01.952139+12
2105	2124	【中国文字狱事件记录】\n日期：2020年10月12日\n地点：广东阳春市\n当事人：罗某\n平台：朋友圈\n言论内容：“侮辱交警、诋毁交警执法形象为主要内容的有害言论”\n处罚：拘留12日、罚款1000元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:01.996133+12
2106	2125	【中国文字狱事件记录】\n日期：2020年10月14日\n地点：许昌市电气职业技术学院\n当事人：文长安\n身份：学者/教师\n平台：推特\n言论内容：“污蔑、辱骂国家领导人、中国共产党及攻击中国政治体制等推文”1500余条\n处罚：有期徒刑1年\n法律文书：（2020）豫1002刑初314号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:02.040119+12
2107	2126	【中国文字狱事件记录】\n日期：2020年10月14日\n地点：安徽合肥\n当事人：张国云\n平台：网络\n言论内容：（转发）涉港言论\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:02.085199+12
2108	2127	【中国文字狱事件记录】\n日期：2020年10月15日\n地点：江西湖口县\n当事人：杨某\n平台：推特、微博\n言论内容：“严重损害国家形象、危害国家利益的虚假信息”\n处罚：起诉（寻衅滋事罪）\n法律文书：湖检一部刑诉〔2020〕126号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:02.134156+12
2109	2128	【中国文字狱事件记录】\n日期：2020年10月21日\n地点：江苏南京\n当事人：江腾达\n平台：QQ群\n言论内容：侮辱中华民族、侮辱国家领导人、侮辱先烈、歪曲南京大屠杀历史、抨击共产主义、支持台湾独立等\n处罚：有期徒刑2年\n法律文书：（2020）苏0102刑初300号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:02.179001+12
2110	2129	【中国文字狱事件记录】\n日期：2020年10月29日\n地点：浙江龙游县\n当事人：金宁\n平台：朋友圈\n言论内容：“诋毁某位国家领导人的一段9秒小视频”\n处罚：有罪免罚\n法律文书：（2020）浙0825刑初146号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:02.230784+12
2111	2130	【中国文字狱事件记录】\n日期：2020年10月30日\n地点：河南项城市\n当事人：朱某\n身份：律师\n平台：多个平台\n言论内容：指责当地法院法官及法警炮制了其父亲的冤案，并称其为狗官和匪警等\n处罚：有罪免罚\n法律文书：（2020）豫1681刑初390号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:02.27993+12
2112	2131	【中国文字狱事件记录】\n日期：2020年10月30日\n地点：河南汝州市\n当事人：赵某\n平台：推特\n言论内容：支持“香港暴乱”的信息、攻击国家政治体制和领导人、射击台独和东突等信息、疫情谣言信息等\n处罚：有期徒刑1年\n法律文书：（2020）豫0482刑初475号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:02.326464+12
2113	2132	【中国文字狱事件记录】\n日期：2020年11月02日\n地点：上海\n当事人：孙某\n平台：QQ群\n言论内容：“侮辱国家领导人的言论和图片”\n处罚：有期徒刑7个月\n法律文书：（2020）沪0107刑初1097号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:02.369513+12
2114	2133	【中国文字狱事件记录】\n日期：2020年11月02日\n地点：江苏江阴市\n当事人：黄某\n平台：微信群、土豆群、推特\n言论内容：“虚假时事信息，结合个人观点进行播报；涉疫虚假信息”；帮助他人向法治基金捐款\n处罚：起诉（寻衅滋事罪）\n法律文书：澄检一部刑诉〔2020〕2352号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:02.413678+12
2115	2134	【中国文字狱事件记录】\n日期：2020年11月02日\n地点：江苏江阴市\n当事人：孙某\n平台：微信群、土豆群\n言论内容：“虚假时事信息，结合个人观点进行播报；涉疫虚假信息”\n处罚：起诉（寻衅滋事罪）\n法律文书：澄检一部刑诉〔2020〕2352号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:02.458276+12
2116	2135	【中国文字狱事件记录】\n日期：2020年11月02日\n地点：江苏江阴市\n当事人：郭某\n平台：微信群\n言论内容：“虚假时事信息，结合个人观点进行播报；涉疫虚假信息”\n处罚：起诉（寻衅滋事罪）\n法律文书：澄检一部刑诉〔2020〕2352号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:02.502344+12
2117	2136	【中国文字狱事件记录】\n日期：2020年11月04日\n地点：贵州毕节\n当事人：任某\n平台：微信群\n言论内容：看这个草包支书怎么说的\n处罚：拘留3日\n备注：处罚被撤销\n法律文书：毕公（洪）行罚决字【2020】5229号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:02.544622+12
2118	2137	【中国文字狱事件记录】\n日期：2020年11月06日\n地点：吉林洮南市\n当事人：孙某甲\n平台：微信群\n言论内容：一段视频，疑似为警民冲突\n处罚：批评教育	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:02.588302+12
2212	2232	【中国文字狱事件记录】\n日期：2021年05月24日\n地点：广西百色\n当事人：黄某\n平台：网络\n言论内容：“侮辱袁隆平院士”的言论\n背景事件：袁隆平去世\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:07.658261+12
2119	2138	【中国文字狱事件记录】\n日期：2020年11月06日\n地点：吉林洮南市\n当事人：孙某乙\n平台：微信群\n言论内容：（评论孙某甲发送的疑似警暴视频）为这位农民朋友点赞，一帮土匪，打小日本都这样就行了\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:02.63072+12
2120	2139	【中国文字狱事件记录】\n日期：2020年11月13日\n地点：青海贵德县\n当事人：才让措\n平台：朋友圈\n言论内容：“涉稳”信息\n处罚：拘留10日\n法律文书：贵公（国）行罚决字【2020】01号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:02.674817+12
2121	2140	【中国文字狱事件记录】\n日期：2020年11月13日\n地点：湖南衡东县\n当事人：侯茂先\n平台：红网\n言论内容：《状告衡东县蓬源镇人大主席为首的贪污受贿行为》等多篇文章，指控镇村干部腐败和赌博\n处罚：有期徒刑1年\n法律文书：（2020）湘0424刑初192号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:02.721959+12
2122	2141	【中国文字狱事件记录】\n日期：2020年11月15日\n地点：内蒙古磴口县\n当事人：马某\n平台：微信群\n言论内容：现在磴口万豪酒店发现一例无症状冠状病毒感染者…\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:02.767413+12
2123	2142	【中国文字狱事件记录】\n日期：2020年11月18日\n地点：天津\n当事人：周绍卿\n平台：推特\n言论内容：有损党和国家领导人及国家政治制度、诋毁国家应对新型冠状病毒肺炎疫情防控举措的信息\n背景事件：武汉新型冠状病毒肺炎\n处罚：有期徒刑9个月\n法律文书：（2020）津0102刑初345号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:02.813192+12
2124	2143	【中国文字狱事件记录】\n日期：2020年11月27日\n地点：辽宁大连\n当事人：徐某\n平台：推特、微博\n言论内容：“放开言论就炸锅了、香港市民大概需要把不要脸特首换掉的自由吧等“损害国家形象”的信息\n背景事件：香港反送中示威\n处罚：有期徒刑1年\n法律文书：（2020）辽0203刑初321号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:02.858976+12
2125	2144	【中国文字狱事件记录】\n日期：2020年11月30日\n地点：山西阳泉\n当事人：李银锁（75岁）\n身份：公职人员/事业单位人员（退休）\n平台：微博、现实\n言论内容：举报当地多个政府部门和官员贪污腐败和违纪\n处罚：有期徒刑12年、罚金17000元\n法律文书：（2020）晋0303刑初105号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:02.906429+12
2126	2145	【中国文字狱事件记录】\n日期：2020年12月04日\n地点：安徽全椒县\n当事人：郑某\n平台：朋友圈\n言论内容：今天在古河派出所办事！真的不知道是民警还是流氓！说话下流！贱淫！\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:02.953826+12
2127	2146	【中国文字狱事件记录】\n日期：2020年12月05日\n地点：广西来宾市\n当事人：何某连\n平台：朋友圈\n言论内容：他奶奶的今天又白帮共产党做工了，以后我天天在家里看店，看你们这帮狗仔以后还怎么罚款\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:02.998947+12
2128	2147	【中国文字狱事件记录】\n日期：2020年12月07日\n地点：山西阳泉\n当事人：贾朝晖\n平台：网络、现实\n言论内容：在公安局旧址门口张贴“煽动颠覆国家政权的内容”并拍摄视频传到网络\n处罚：有期徒刑1年6个月\n法律文书：（2020）晋0302刑初275号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:03.04533+12
2129	2148	【中国文字狱事件记录】\n日期：2020年12月09日\n地点：四川蓬安县\n当事人：黎某\n平台：朋友圈\n言论内容：“辱骂公安交警的言论”\n处罚：拘留2日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:03.092439+12
2130	2149	【中国文字狱事件记录】\n日期：2020年12月11日\n地点：辽宁沈阳\n当事人：李某\n平台：GTV\n言论内容：“涉港、涉郭、涉美、颠覆国家政权的内容、侮辱国家领导人的内容、庆祝新中国联邦成立”\n背景事件：郭文贵爆料事件\n处罚：有期徒刑8个月\n法律文书：（2020）辽0112刑初422号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:03.137756+12
2131	2150	【中国文字狱事件记录】\n日期：2020年12月14日\n地点：河南许昌\n当事人：卢小龙\n平台：推特\n言论内容：“损害国家形象的不当言论”\n处罚：有期徒刑6个月\n法律文书：（2020）豫1002刑初556号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:03.182348+12
2132	2151	【中国文字狱事件记录】\n日期：2020年12月21日\n地点：河南平顶山\n当事人：隋春艳\n平台：多个新闻网站\n言论内容：为其他访民发表的维权伸冤内容\n处罚：有期徒刑3年\n法律文书：（2020）豫0402刑初269号；（2020）豫04刑终540号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:03.228074+12
2133	2330	【中国文字狱事件记录】\n日期：2021年11月09日\n地点：贵州赫章县\n当事人：李某\n平台：朋友圈\n言论内容：x妈又着了儿子要钱了\n处罚：拘留12日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:13.07099+12
2134	2152	【中国文字狱事件记录】\n日期：2020年12月21日\n地点：河南平顶山\n当事人：卢青国\n平台：多个新闻网站\n言论内容：为其他访民发表的维权伸冤内容\n处罚：有期徒刑2年6个月\n法律文书：（2020）豫0402刑初269号；（2020）豫04刑终540号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:03.272717+12
2135	2153	【中国文字狱事件记录】\n日期：2020年12月21日\n地点：河南平顶山\n当事人：程毅\n平台：多个新闻网站\n言论内容：为其他访民发表的维权伸冤内容\n处罚：有期徒刑3年6个月\n法律文书：（2020）豫0402刑初269号；（2020）豫04刑终540号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:03.323668+12
2136	2154	【中国文字狱事件记录】\n日期：2020年12月22日\n地点：辽宁海城市\n当事人：张树林\n平台：QQ群等\n言论内容：“侮辱国家重要领导人”的图片和言论\n处罚：有期徒刑1年3个月\n法律文书：（2020）辽0381刑初884号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:03.362084+12
2137	2155	【中国文字狱事件记录】\n日期：2020年12月22日\n地点：山东桓台县\n当事人：耿家峰\n平台：微博、微信\n言论内容：声援张岗，指控当地警方对张岗非法拘禁和打击报复\n处罚：有期徒刑4年6个月、罚金1万元\n备注：二审维持原判\n法律文书：（2020）鲁0321刑初259号；（2021）鲁03刑终14号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:03.410437+12
2138	2156	【中国文字狱事件记录】\n日期：2020年12月23日\n地点：云南昆明\n当事人：关清源\n平台：推特\n言论内容：诋毁国家领导人、抹黑中国共产党和中国政府、抨击国家抗击新冠疫情政策等“有害信息”\n背景事件：武汉新型冠状病毒肺炎\n处罚：有期徒刑8个月\n法律文书：（2020）云0111刑初2300号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:03.457575+12
2139	2157	【中国文字狱事件记录】\n日期：2020年12月25日\n地点：贵州平塘县\n当事人：宋某\n平台：抖音\n言论内容：“不当言论”\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:03.503278+12
2140	2158	【中国文字狱事件记录】\n日期：2020年12月25日\n地点：陕西榆林\n当事人：王某\n平台：某直播平台\n言论内容：（视频）一男子手拿羊照片哭丧，另一人为羊掘墓，并称要为它办葬礼\n处罚：拘留15日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:03.548426+12
2141	2159	【中国文字狱事件记录】\n日期：2020年12月25日\n地点：广东湛江\n当事人：梁某\n平台：推特\n言论内容：“辱华、丑化及侮辱国家领导人、诋毁社会主义制度、分裂国家等虚假负面信息”\n处罚：起诉（寻衅滋事罪）\n法律文书：霞检刑诉〔2020〕39号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:03.595098+12
2142	2160	【中国文字狱事件记录】\n日期：2020年12月25日\n地点：河南辉县市\n当事人：张某\n平台：推特\n言论内容：“侮辱、谩骂、诋毁国家领导人，诋毁中国共产党，诋毁社会主义制度”\n处罚：起诉（寻衅滋事罪）\n法律文书：新辉检一部刑诉〔2020〕335号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:03.641809+12
2143	2161	【中国文字狱事件记录】\n日期：2020年12月28日\n地点：上海\n当事人：张展\n平台：YouTube\n言论内容：在YouTube直播武汉封城期间疫情实况\n背景事件：武汉新型冠状病毒肺炎\n处罚：有期徒刑4年\n法律文书：（2020）沪0115刑初1002号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:03.686831+12
2144	2162	【中国文字狱事件记录】\n日期：2020年12月30日\n地点：广东东莞\n当事人：田维权\n平台：电报、油管、推特\n言论内容：“辱骂政府和国家领导人、发布有关政府、国家领导人和国内重大事件的虚假信息”\n处罚：有期徒刑2年\n备注：二审维持原判\n法律文书：（2020）粤1972刑初1630号；（2021）粤19刑终131号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:03.730321+12
2145	2163	【中国文字狱事件记录】\n日期：2020年12月31日\n地点：河南郑州\n当事人：孙家栋\n平台：推特\n言论内容：涉港、涉台、涉疆、涉警、反共等涉及国内重大事件、严重损害国家形象、严重危害国家利益的“虚假信息”\n处罚：有期徒刑1年1个月\n法律文书：（2020）豫0191刑初566号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:03.772871+12
2146	2164	【中国文字狱事件记录】\n日期：2021年01月04日\n地点：四川金契律师事务所\n当事人：卢思位\n身份：律师\n平台：网络\n言论内容：”不当言论“\n处罚：吊销律师资格证\n法律文书：川司罚告字［2021］第1号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:03.816392+12
2147	2165	【中国文字狱事件记录】\n日期：2021年01月05日\n地点：黑龙江伊春\n当事人：赵某\n平台：不详\n言论内容：伊美区出现1名大连市返伊人员核酸检测为阳性的\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:03.867225+12
2148	2166	【中国文字狱事件记录】\n日期：2021年01月05日\n地点：黑龙江伊春\n当事人：张某\n平台：不详\n言论内容：伊美区出现1名大连市返伊人员核酸检测为阳性的\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:03.911311+12
2149	2167	【中国文字狱事件记录】\n日期：2021年01月06日\n地点：宁夏银川\n当事人：黄某\n平台：微信群\n言论内容：@所有人， 邻居们，X们在我们小区后面贴条子着呢，谁的车在后面赶快去移\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:03.954028+12
2150	2168	【中国文字狱事件记录】\n日期：2021年01月07日\n地点：云南马关县\n当事人：黄某\n平台：朋友圈\n言论内容：有狗（交警执勤照片）\n处罚：拘留8日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:03.994551+12
2151	2169	【中国文字狱事件记录】\n日期：2021年01月11日\n地点：黑龙江黑河\n当事人：李某\n平台：网络\n言论内容：“涉疫虚假言论”\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:04.036991+12
2152	2171	【中国文字狱事件记录】\n日期：2021年01月13日\n地点：山西洪洞县\n当事人：师某\n平台：微博\n言论内容：“涉疫谣言”\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:04.124147+12
2153	2172	【中国文字狱事件记录】\n日期：2021年01月15日\n地点：山东平原县\n当事人：韩某\n平台：微信群\n言论内容：平原县出现首例疫情确诊病例\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:04.171843+12
2154	2173	【中国文字狱事件记录】\n日期：2021年01月18日\n地点：天津\n当事人：安淏\n平台：陌陌、朋友圈\n言论内容：”辱骂“公安静海分局刑侦支队的言论及视频\n处罚：有期徒刑6个月\n法律文书：（2021）津0118刑初24号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:04.262646+12
2155	2174	【中国文字狱事件记录】\n日期：2021年01月19日\n地点：湖南娄底\n当事人：陈宇辉\n平台：微信公众平台\n言论内容：炒作社会热点、负面事件，和“不当言论”\n处罚：政务立案调查	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:04.303708+12
2156	2175	【中国文字狱事件记录】\n日期：2021年01月19日\n地点：江西万年县\n当事人：李某新\n平台：朋友圈\n言论内容：这两个xx，给老子贴了几次罚单，祝他俩xxx\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:04.375198+12
2157	2176	【中国文字狱事件记录】\n日期：2021年01月21日\n地点：广州大学华软软件学院\n当事人：郑某\n身份：学者/教师/中共党员\n平台：微博\n言论内容：四首打油诗，指责广东省和广州市政府官员官商勾结、包庇罪犯\n处罚：管制1年\n法律文书：（2021）粤0117刑初13号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:04.425604+12
2158	2177	【中国文字狱事件记录】\n日期：2021年01月21日\n地点：浙江温岭市\n当事人：林某\n平台：抖音\n言论内容：下午温岭发现病例；隔离去了应该是准确的，到底是红码的缘故还是有病并不清楚，XX菜场已经加强管理了\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:04.479274+12
2159	2178	【中国文字狱事件记录】\n日期：2021年01月22日\n地点：浙江泰顺县\n当事人：叶海静\n平台：网络、现实\n言论内容：称当地政府干部是土生、土匪头子，并指控官员强拆其房屋\n处罚：有期徒刑1年8个月\n备注：二审维持原判\n法律文书：（2020）浙0329刑初185号；（2021）浙03刑终105号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:04.530512+12
2160	2179	【中国文字狱事件记录】\n日期：2021年01月24日\n地点：江苏海安市\n当事人：张某\n平台：微信私聊\n言论内容：其自己核酸检测报告结果为阳性的合成图\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留2日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:04.58921+12
2161	2180	【中国文字狱事件记录】\n日期：2021年01月25日\n地点：广西都安县\n当事人：蒙某\n平台：网络\n言论内容：（转发）自治区人民政府已经决定于2021年1月29日凌晨实行全区封城\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:04.644236+12
2162	2181	【中国文字狱事件记录】\n日期：2021年01月26日\n地点：广东云浮\n当事人：王某\n平台：朋友圈\n言论内容：死交警追我追到工地，说我的车太脏了，车牌见不到，差点扣12分，还好给我一次机会，放了我\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:04.699015+12
2163	2182	【中国文字狱事件记录】\n日期：2021年01月27日\n地点：广东深圳\n当事人：吴某\n平台：朋友圈\n言论内容：（图片）离开深圳再回来，需要隔离14天，请想好再上高速\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:04.750939+12
2164	2183	【中国文字狱事件记录】\n日期：2021年01月27日\n地点：广西都安县\n当事人：石某\n平台：网络\n言论内容：受新冠疫情影响，1月28日南宁封城想回来都难\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:04.80405+12
2165	2184	【中国文字狱事件记录】\n日期：2021年01月27日\n地点：广西罗城县\n当事人：罗某\n平台：网络\n言论内容：南宁有2例新冠肺炎，南宁现已封城了\n背景事件：武汉新型冠状病毒肺炎\n处罚：罚款200元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:04.872298+12
2166	2185	【中国文字狱事件记录】\n日期：2021年01月29日\n地点：辽宁大连\n当事人：盛中华\n平台：推特\n言论内容：侮辱党和国家领导人以及涉及国内重大事件的不当言论和虚假信息\n处罚：有期徒刑10个月\n法律文书：（2020）辽0211刑初459号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:04.935972+12
2167	2186	【中国文字狱事件记录】\n日期：2021年02月02日\n地点：吉林通化\n当事人：刘某\n平台：今日头条\n言论内容：大家好我是通化市居民，当地已经民不聊生……我饿了快十天\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日、罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:05.001787+12
2168	2187	【中国文字狱事件记录】\n日期：2021年02月02日\n地点：广东台山市\n当事人：陈某伟\n平台：微博\n言论内容：台山交警好扑街，在这乱开罚单……到底有冇公里，小心俾雷劈你们班也\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:05.061616+12
2169	2188	【中国文字狱事件记录】\n日期：2021年02月06日\n地点：广西贵港\n当事人：伍某\n平台：微信群\n言论内容：“不实言论”\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:05.114846+12
2170	2189	【中国文字狱事件记录】\n日期：2021年02月07日\n地点：河南三门峡\n当事人：薛某\n平台：朋友圈\n言论内容：这帮x狗，都是临时工，都是关系进去的，没有一点素质，真真的\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:05.170319+12
2171	2190	【中国文字狱事件记录】\n日期：2021年02月08日\n地点：河南睢县\n当事人：孟跟东（孟晓东）\n平台：推特\n言论内容：“辱骂他人，侮辱中国共产党的言论”\n处罚：有期徒刑6个月\n法律文书：（2020）豫1422刑初243号；（2021）豫14刑终236号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:05.224591+12
2172	2191	【中国文字狱事件记录】\n日期：2021年02月09日\n地点：云南峨山县\n当事人：童某\n平台：朋友圈\n言论内容：（交警执法视频）这些狗，开始出动了\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:05.277838+12
2173	2192	【中国文字狱事件记录】\n日期：2021年02月20日\n地点：北京\n当事人：陈某强\n平台：微信群\n言论内容：“侮辱诋毁卫国戍边英雄官兵的言论”\n背景事件：中印边境冲突\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:05.341291+12
2174	2193	【中国文字狱事件记录】\n日期：2021年02月20日\n地点：江苏南京\n当事人：仇子明（蜡笔小球）\n平台：微博\n言论内容：看来这个团长个性是“飞将+脱兔+神机+血路+强运“；救人的人都牺牲了，说明阵亡肯定不止4人\n背景事件：中印边境冲突\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:05.388981+12
2175	2194	【中国文字狱事件记录】\n日期：2021年02月20日\n地点：河北石家庄\n当事人：刘某\n平台：网络\n言论内容：藁城区降级，20日起石家庄藁城全城调整为低风险……藁城区已符合调整至低风险等级标准\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日\n备注：1天后谣言成真	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:05.440338+12
2176	2195	【中国文字狱事件记录】\n日期：2021年02月21日\n地点：广东茂名\n当事人：田某论\n平台：微信群\n言论内容：“侮辱诋毁卫国戍边英雄官兵的言论”\n背景事件：中印边境冲突\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:05.497937+12
2177	2196	【中国文字狱事件记录】\n日期：2021年02月21日\n地点：四川绵阳\n当事人：杨某（知名Zed）\n平台：微博\n言论内容：这么油腻？蝈男真是油\n背景事件：中印边境冲突\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:05.55629+12
2178	2197	【中国文字狱事件记录】\n日期：2021年02月21日\n地点：重庆\n当事人：王靖渝（TSCB8）\n身份：境外人士\n平台：微博\n言论内容：该死 解放军自己惹事 该 打得好 印度人杀得好 死得该\n背景事件：中印边境冲突\n处罚：刑事拘留（上网追逃）	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:05.625327+12
2179	2198	【中国文字狱事件记录】\n日期：2021年02月21日\n地点：河北秦皇岛\n当事人：唐某\n平台：微博\n言论内容：“侮辱诋毁卫国戍边英雄官兵的言论”\n背景事件：中印边境冲突\n处罚：拘留15日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:05.678813+12
2180	2199	【中国文字狱事件记录】\n日期：2021年02月21日\n地点：贵州贵阳\n当事人：代某\n平台：朋友圈\n言论内容：“侮辱诋毁卫国戍边英雄官兵的言论”\n背景事件：中印边境冲突\n处罚：拘留13日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:05.734099+12
2181	2200	【中国文字狱事件记录】\n日期：2021年02月24日\n地点：四川职业技术学院\n当事人：不详\n身份：学者/教师\n平台：QQ群\n言论内容：反对强制戴口罩、“侮辱”英烈、反对战争式动员宣传的言论\n背景事件：武汉新型冠状病毒肺炎\n处罚：停职	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:05.788366+12
2182	2201	【中国文字狱事件记录】\n日期：2021年02月25日\n地点：安徽砀山县\n当事人：邱某\n平台：朋友圈\n言论内容：（视频）诋毁交警正常执法，恶意辱骂交警\n处罚：拘留15日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:05.842689+12
2183	2202	【中国文字狱事件记录】\n日期：2021年03月01日\n地点：广东云浮\n当事人：黄某\n平台：微博\n言论内容：够凶的，你妹的，竟然破口大骂群众，警察够恶心的\n处罚：拘留15日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:05.897189+12
2184	2203	【中国文字狱事件记录】\n日期：2021年03月02日\n地点：云南祥云县\n当事人：代某\n平台：朋友圈\n言论内容：（交通罚单照片）不顺的时候了嘛出门逗狗\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:05.949593+12
2185	2204	【中国文字狱事件记录】\n日期：2021年03月04日\n地点：云南鲁甸县\n当事人：熊某芝\n平台：网络\n言论内容：社长不让她家修路，不给她家通水，并称在为老百姓办理低保、落户时私自收取费用，称村干部为狗官\n处罚：拘留15日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:06.002528+12
2186	2205	【中国文字狱事件记录】\n日期：2021年03月08日\n地点：江苏泰兴市\n当事人：叶某\n平台：朋友圈\n言论内容：泰兴的交警是xxxxxx了吗，我停店门口也给我罚单，……无法无天？\n处罚：拘留5日、罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:06.0579+12
2187	2206	【中国文字狱事件记录】\n日期：2021年03月15日\n地点：北京\n当事人：潘某\n身份：境外人士\n平台：微博\n言论内容：听说至少一个营地被印度活埋了……好像没机会天葬\n背景事件：中印边境冲突\n处罚：刑事拘留（上网追逃）	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:06.118488+12
2188	2207	【中国文字狱事件记录】\n日期：2021年03月17日\n地点：广东清远\n当事人：张五洲\n平台：现实/举牌\n言论内容：勿忘六四，撤回恶法\n背景事件：六四事件；港版《国安法》事件\n处罚：有期徒刑2年6个月\n法律文书：（2020）粤1802刑初584号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:06.164468+12
2189	2208	【中国文字狱事件记录】\n日期：2021年03月19日\n地点：河南商城县\n当事人：刘某\n平台：微信群\n言论内容：“辱骂民警”的言论\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:06.214928+12
2190	2209	【中国文字狱事件记录】\n日期：2021年03月25日\n地点：河南扶沟县\n当事人：陈少天（天哥天书院）\n平台：推特\n言论内容：50条“炒作中国国内热敏感事件、攻击政治体制、辱骂丑化国家工作人员”的视频\n处罚：有期徒刑1年2个月\n法律文书：（2021）豫1621刑初94号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:06.271951+12
2191	2210	【中国文字狱事件记录】\n日期：2021年03月30日\n地点：北京\n当事人：王某\n平台：微博\n言论内容：北京交警不公平执法，男司机不懒，专门懒恧司机……交警刮民脂民膏，挣缺德钱，不得好死\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:06.32933+12
2192	2211	【中国文字狱事件记录】\n日期：2021年04月01日\n地点：北京\n当事人：王某\n平台：微信群\n言论内容：“侮辱‘海空卫士’王伟及其遗孀的言论”\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:06.386182+12
2193	2212	【中国文字狱事件记录】\n日期：2021年04月04日\n地点：陕西三原县\n当事人：张某（15岁）\n平台：微博\n言论内容：北京天安门那为什么挂男的照片？集美们一起把他冲了，开国十大元帅没有一个是伟大的女性，真想不通当时怎么通过的\n处罚：“依法处置”	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:06.443436+12
2194	2213	【中国文字狱事件记录】\n日期：2021年04月05日\n地点：江苏淮安\n当事人：刘某\n平台：微信群\n言论内容：接种新冠疫苗的人都是试验品，男人接种后丧失性功能，女人接种后不生育\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留4日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:06.499889+12
2195	2214	【中国文字狱事件记录】\n日期：2021年04月08日\n地点：云南昆明\n当事人：徐昆\n平台：推特\n言论内容：“抨击诋毁国家政权制度、政党，侮辱领导人，歪曲国内重大事件等不实有害信息”\n背景事件：香港反送中示威\n处罚：有期徒刑2年\n法律文书：（2020）云0103刑初64号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:06.554+12
2196	2215	【中国文字狱事件记录】\n日期：2021年04月22日\n地点：广西乐业县\n当事人：刘某\n平台：朋友圈\n言论内容：“辱骂110及公安民警的恶劣语言”\n处罚：拘留15日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:06.607917+12
2197	2216	【中国文字狱事件记录】\n日期：2021年05月13日\n地点：浙江磐安县\n当事人：羊耀政\n身份：公职人员/事业单位人员\n平台：微博\n言论内容：自己 不公开监控有啥好说的……资本主义社会主义的差距参照一下朝鲜韩国就可以了……一味搞文字狱\n背景事件：成都49中学生坠楼事件\n处罚：停职（举报者自称）	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:06.662115+12
2198	2217	【中国文字狱事件记录】\n日期：2021年05月22日\n地点：河南淇县\n当事人：杨某\n平台：QQ群\n言论内容：死得好啊；死得好\n背景事件：袁隆平去世\n处罚：拘留15日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:06.723707+12
2199	2218	【中国文字狱事件记录】\n日期：2021年05月22日\n地点：北京\n当事人：不详\n平台：微信群\n言论内容：死个院士，纳税人也可以少花点钱；毕竟副部级待遇\n背景事件：袁隆平去世\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:06.779675+12
2200	2219	【中国文字狱事件记录】\n日期：2021年05月22日\n地点：江苏苏州\n当事人：蒋某（画家蒋林音）\n平台：微博\n言论内容：（袁隆平去世新闻截图）特大喜讯：暗搞转基因被韭菜拜为阴谋集团塑造的“神”挂了\n背景事件：袁隆平去世\n处罚：刑事强制措施	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:06.838422+12
2201	2220	【中国文字狱事件记录】\n日期：2021年05月22日\n地点：福建厦门\n当事人：王某雄（社会专门投诉微博）\n平台：微博\n言论内容：都是一帮傻逼就好像他们的爸爸死了一样在追无语了……日本万岁，我爱日本\n背景事件：袁隆平去世\n处罚：刑事强制措施	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:06.895682+12
2202	2221	【中国文字狱事件记录】\n日期：2021年05月22日\n地点：山东日照\n当事人：贾某（18岁）\n平台：微博\n言论内容：“侮辱袁隆平院士”的言论\n背景事件：袁隆平去世\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:06.952092+12
2203	2222	【中国文字狱事件记录】\n日期：2021年05月22日\n地点：江西弋阳县\n当事人：侯某\n平台：抖音\n言论内容：（视频）弋阳县火车站被洪水淹没\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:07.008132+12
2204	2223	【中国文字狱事件记录】\n日期：2021年05月22日\n地点：天津\n当事人：李某\n平台：朋友圈\n言论内容：（袁隆平去世新闻截图）他终于死了……这个水稻老鸨子，让水稻成为性奴，改变了水稻的纯洁\n背景事件：袁隆平去世\n处罚：刑事强制措施	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:07.064314+12
2205	2225	【中国文字狱事件记录】\n日期：2021年05月22日\n地点：西藏当雄县\n当事人：旦某\n平台：抖音\n言论内容：视频，内容为一辆警车，配文为“这些肮脏的人在这里”，视频中其口头“辱骂”警察\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:07.167164+12
2206	2226	【中国文字狱事件记录】\n日期：2021年05月23日\n地点：广东清远\n当事人：梁某\n平台：微信群\n言论内容：“侮辱袁隆平”的言论\n背景事件：袁隆平去世\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:07.218112+12
2207	2227	【中国文字狱事件记录】\n日期：2021年05月23日\n地点：江苏金湖县\n当事人：金某\n平台：朋友圈\n言论内容：一个是被资本家需要吹上天的垄断全国杂交稻种子的牌坊而已，一个是手上沾满鲜血的西医诈骗集团吃人血馒头的戏子而已\n背景事件：袁隆平去世\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:07.276124+12
2208	2228	【中国文字狱事件记录】\n日期：2021年05月23日\n地点：江苏无锡\n当事人：高某顺\n平台：朋友圈\n言论内容：针对袁隆平的“侮辱性、诋毁性”言论\n背景事件：袁隆平去世\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:07.330623+12
2209	2229	【中国文字狱事件记录】\n日期：2021年05月24日\n地点：湖北麻城\n当事人：朱某\n平台：微信群\n言论内容：“侮辱袁隆平院士”的言论\n背景事件：袁隆平去世\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:07.383712+12
2210	2230	【中国文字狱事件记录】\n日期：2021年05月24日\n地点：陕西西安\n当事人：刘某\n平台：微博\n言论内容：新冠疫苗致人死亡\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:07.446692+12
2211	2231	【中国文字狱事件记录】\n日期：2021年05月24日\n地点：重庆\n当事人：熊某\n平台：朋友圈\n言论内容：“侮辱袁隆平”的言论\n背景事件：袁隆平去世\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:07.506712+12
2213	2233	【中国文字狱事件记录】\n日期：2021年05月25日\n地点：山东淄博\n当事人：岳某\n平台：微信群\n言论内容：“诋毁袁隆平教授的言论“\n背景事件：袁隆平去世\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:07.704669+12
2214	2234	【中国文字狱事件记录】\n日期：2021年05月25日\n地点：山东德州\n当事人：潘某\n平台：朋友圈\n言论内容：针对袁隆平院士的“侮辱性”言论\n背景事件：袁隆平去世\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:07.75366+12
2215	2235	【中国文字狱事件记录】\n日期：2021年05月25日\n地点：湖南会同县\n当事人：李某\n平台：朋友圈\n言论内容：“侮辱诽谤袁隆平及袁隆平父亲的文字”\n背景事件：袁隆平去世\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:07.805553+12
2216	2236	【中国文字狱事件记录】\n日期：2021年05月25日\n地点：陕西西安\n当事人：李某\n平台：网络\n言论内容：“侮辱袁隆平院士”的视频\n背景事件：袁隆平去世\n处罚：刑事强制措施	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:07.863847+12
2217	2237	【中国文字狱事件记录】\n日期：2021年05月26日\n地点：北京\n当事人：袁某\n平台：微博\n言论内容：“侮辱”袁隆平的言论；中国早没救了，东亚病夫不是白喊的蛤；铁拳没砸到自己身上的时候都觉得与你无关\n背景事件：袁隆平去世\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:07.925375+12
2218	2238	【中国文字狱事件记录】\n日期：2021年05月26日\n地点：安徽芜湖\n当事人：骆某\n平台：朋友圈\n言论内容：贱民，无处不在，照他们的逻辑…等抨击民众对袁隆平个人崇拜的文字\n背景事件：袁隆平去世\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:07.976165+12
2219	2239	【中国文字狱事件记录】\n日期：2021年05月27日\n地点：山东临沂\n当事人：刘某（17岁）\n平台：多个平台\n言论内容：“侮辱袁隆平院士”的言论\n背景事件：袁隆平去世\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:08.026833+12
2220	2240	【中国文字狱事件记录】\n日期：2021年05月27日\n地点：山西中阳县\n当事人：高某\n平台：微博\n言论内容：（袁隆平去世新闻）“侮辱性”评论\n背景事件：袁隆平去世\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:08.084325+12
2221	2241	【中国文字狱事件记录】\n日期：2021年05月28日\n地点：山东惠民县\n当事人：杨某湖\n平台：微信群\n言论内容：涉及袁隆平院士逝世的“不当言论”\n背景事件：袁隆平去世\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:08.144513+12
2222	2242	【中国文字狱事件记录】\n日期：2021年05月29日\n地点：广东广州\n当事人：王爱忠\n平台：推特\n言论内容：（疑似）大量反对中共政权的言论\n处罚：刑事拘留\n法律文书：穗公天拘通字［2021］310620号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:08.207758+12
2223	2243	【中国文字狱事件记录】\n日期：2021年05月31日\n地点：广东汕头\n当事人：钟某妮\n平台：微信群\n言论内容：（转发）“涉及疫情传播的信息”\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:08.275278+12
2224	2244	【中国文字狱事件记录】\n日期：2021年05月31日\n地点：湖南株洲\n当事人：陈思明\n平台：推特\n言论内容：而我依然要纪念这个中国当代史上最重要的日子，这是一个公民的责任。我们缅怀六四英烈\n背景事件：六四事件\n处罚：拘留15日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:08.331883+12
2225	2245	【中国文字狱事件记录】\n日期：2021年06月01日\n地点：广东汕头\n当事人：庄某林\n平台：微信群\n言论内容：（转发）一名女子核酸检测呈阳性\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:08.389792+12
2226	2246	【中国文字狱事件记录】\n日期：2021年06月04日\n地点：江西安福县\n当事人：李某\n平台：微信群\n言论内容：老林业局！有狗查酒驾？\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:08.444386+12
2227	2247	【中国文字狱事件记录】\n日期：2021年06月05日\n地点：广东阳春市\n当事人：曾某倍\n平台：微信群\n言论内容：（视频，转发）河㙟有一单啦，荔湾区返个啦，现在整到都学校都轰动了……\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:08.502578+12
2228	2248	【中国文字狱事件记录】\n日期：2021年06月05日\n地点：广东汕头\n当事人：周某岳\n平台：微信群\n言论内容：其新冠核酸检测阳性\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:08.55855+12
2229	2249	【中国文字狱事件记录】\n日期：2021年06月07日\n地点：四川成都\n当事人：谢俊彪\n平台：推特\n言论内容：影射六四事件悼念死难者的图片\n背景事件：六四事件\n处罚：刑事拘留\n法律文书：成双公（怡）拘通字［2021］763号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:08.616588+12
2230	2250	【中国文字狱事件记录】\n日期：2021年06月10日\n地点：江苏如东县\n当事人：缪某华\n平台：抖音\n言论内容：（视频）交警队在工作时间无人办公，并用脏话辱骂\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:08.680572+12
2231	2251	【中国文字狱事件记录】\n日期：2021年06月11日\n地点：华东政法大学\n当事人：包毅楠\n身份：学者/教师\n平台：朋友圈\n言论内容：国家既然强调科教兴国，就必须重视高校教师的生机，以及生活问题譬如允许多配偶制、终生补贴制\n处罚：停职	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:08.742361+12
2232	2252	【中国文字狱事件记录】\n日期：2021年06月13日\n地点：广东佛山\n当事人：严某\n平台：某短视频平台\n言论内容：广东省佛山市南海区里水镇得胜村新增一例\n背景事件：武汉新型冠状病毒肺炎\n处罚：“依法处理”	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:08.803811+12
2233	2253	【中国文字狱事件记录】\n日期：2021年06月16日\n地点：陕西白河县\n当事人：白某\n平台：朋友圈\n言论内容：“辱骂交警”的言论\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:08.852568+12
2234	2254	【中国文字狱事件记录】\n日期：2021年06月17日\n地点：湖南邵阳县\n当事人：卿某\n平台：QQ\n言论内容：亵渎革命英烈的言论\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:08.907039+12
2235	2255	【中国文字狱事件记录】\n日期：2021年06月19日\n地点：陕西白河县\n当事人：王某\n平台：朋友圈\n言论内容：“辱骂交警”的言论\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:08.954007+12
2236	2256	【中国文字狱事件记录】\n日期：2021年06月23日\n地点：江苏镇江\n当事人：叶某\n平台：GTV\n言论内容：“有害、 不实且损害国家形象的信息9条”\n处罚：起诉（寻衅滋事罪）\n法律文书：润检一部刑诉〔2021〕120号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:09.000281+12
2237	2257	【中国文字狱事件记录】\n日期：2021年06月23日\n地点：江苏镇江\n当事人：黄某\n平台：GTV、微信\n言论内容：“有害、不实且损害国家形象的信息145条”\n处罚：起诉（寻衅滋事罪）\n法律文书：润检一部刑诉〔2021〕120号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:09.051168+12
2239	2259	【中国文字狱事件记录】\n日期：2021年07月12日\n地点：河南武陟县\n当事人：韩某\n平台：抖音\n言论内容：（视频）沁河大坝多处决堤，材料真实可查\n背景事件：2021年7月河南洪灾\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:09.152154+12
2240	2260	【中国文字狱事件记录】\n日期：2021年07月14日\n地点：辽宁大石桥市\n当事人：张某文\n平台：现实/街头表演\n言论内容：着侵华日军及汉奸服装进行话剧表演\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:09.198574+12
2241	2261	【中国文字狱事件记录】\n日期：2021年07月14日\n地点：辽宁大石桥市\n当事人：张某军\n平台：现实/街头表演\n言论内容：着侵华日军及汉奸服装进行话剧表演\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:09.248016+12
2242	2262	【中国文字狱事件记录】\n日期：2021年07月20日\n地点：湖南城市学院\n当事人：李剑\n身份：学者/教师\n平台：现实/课堂\n言论内容：日本人精益求精\n处罚：停职、调至图书馆\n法律文书：湖城院人发［2021］1号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:09.297196+12
2243	2263	【中国文字狱事件记录】\n日期：2021年07月21日\n地点：湖北大冶市\n当事人：尹旭安\n平台：推特\n言论内容：交警被认为不讲理，遭狂揍，向勇士学习；不是中国人不打中国人吗；（其与友人在8964车牌面前的合影）\n处罚：有期徒刑4年6个月\n法律文书：（2019）鄂0281刑初572号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:09.3494+12
2244	2264	【中国文字狱事件记录】\n日期：2021年07月22日\n地点：湖南株洲\n当事人：欧彪峰\n平台：推特\n言论内容：声援董瑶琼和常玮平律师等良心犯的内容\n处罚：批捕\n法律文书：株公直（国）捕通字［2021］0001号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:09.4052+12
2245	2265	【中国文字狱事件记录】\n日期：2021年07月24日\n地点：河北鸡泽县\n当事人：赵某\n平台：朋友圈\n言论内容：“防汛不实视频，决堤谣言”\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:09.462594+12
2246	2266	【中国文字狱事件记录】\n日期：2021年07月25日\n地点：河北鸡泽县\n当事人：李某\n平台：抖音\n言论内容：“抗洪防汛不实信息”\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:09.519621+12
2247	2267	【中国文字狱事件记录】\n日期：2021年07月26日\n地点：贵州铜仁\n当事人：田某\n平台：抖音\n言论内容：（交警执勤视频）妈的 烦死了，天天都在查查\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:09.575198+12
2248	2268	【中国文字狱事件记录】\n日期：2021年07月27日\n地点：甘肃西和县\n当事人：张某\n平台：微信群\n言论内容：“侮辱村委会”\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:09.629358+12
2249	2269	【中国文字狱事件记录】\n日期：2021年07月28日\n地点：吉林扶余市\n当事人：张某\n平台：微信群\n言论内容：“侮辱村干部”\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:09.682353+12
2250	2270	【中国文字狱事件记录】\n日期：2021年07月28日\n地点：河南辉县市\n当事人：不详\n平台：现实\n言论内容：（拍摄视频的同时口述）大家看，这些人来作秀呢，卸下来的物资现在又装车拉走\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:09.737321+12
2251	2272	【中国文字狱事件记录】\n日期：2021年07月30日\n地点：山东日照\n当事人：丁某云\n平台：微信群\n言论内容：“疫情虚假谣言”\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:09.839336+12
2252	2273	【中国文字狱事件记录】\n日期：2021年07月30日\n地点：山东日照\n当事人：丁某洋\n平台：微信群\n言论内容：“疫情虚假谣言”\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:09.892293+12
2253	2274	【中国文字狱事件记录】\n日期：2021年07月30日\n地点：山东招远市\n当事人：王某\n平台：微博\n言论内容：对其曾被判处两年半有期徒刑一事不满的“不实言论”\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:09.940188+12
2254	2275	【中国文字狱事件记录】\n日期：2021年07月31日\n地点：四川广安\n当事人：杨某\n平台：微信群\n言论内容：广安马上封城\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:09.987608+12
2255	2276	【中国文字狱事件记录】\n日期：2021年08月01日\n地点：湖南娄底\n当事人：童某\n平台：微信群\n言论内容：某医院紧急通知……娄底已发现3起新冠病毒\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:10.040915+12
2256	2277	【中国文字狱事件记录】\n日期：2021年08月02日\n地点：浙江浦江县\n当事人：蒋某\n平台：朋友圈\n言论内容：浦江被隔离的高密接触者至少已经超100人；义乌超800了\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:10.091577+12
2257	2278	【中国文字狱事件记录】\n日期：2021年08月02日\n地点：广东汕头\n当事人：李某涛\n平台：微信群\n言论内容：澄海区中冠华府小区新确诊1例新冠肺炎病例\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:10.147337+12
2258	2279	【中国文字狱事件记录】\n日期：2021年08月05日\n地点：河南遂平县\n当事人：戈某\n平台：微信群\n言论内容：涉及疫情的“不当言论”\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:10.201757+12
2259	2281	【中国文字狱事件记录】\n日期：2021年08月06日\n地点：河南西平县\n当事人：王某\n平台：微信群\n言论内容：涉及疫情的“不当言论”\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:10.309348+12
2260	2282	【中国文字狱事件记录】\n日期：2021年08月06日\n地点：河南遂平县\n当事人：戈某\n平台：微信群\n言论内容：我这几天也是眼痛喉咙痛哩，遂平几个大超市我跑一边，我下午准备去爱家百货，西亚德裕，喜盈门逛逛\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:10.364261+12
2261	2283	【中国文字狱事件记录】\n日期：2021年08月06日\n地点：湖南桃源县\n当事人：周某\n平台：微信群\n言论内容：观音寺形势严峻，已经确诊一例，大家注意来往行人\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:10.41523+12
2262	2284	【中国文字狱事件记录】\n日期：2021年08月06日\n地点：湖南桃源县\n当事人：朱某\n平台：微信群\n言论内容：观音寺一司机从长沙机场接了南京回来的人回观音寺，两人核酸检测为阳性\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:10.470549+12
2263	2285	【中国文字狱事件记录】\n日期：2021年08月07日\n地点：河南修武县\n当事人：张某\n平台：微信群\n言论内容：焦作有确诊病例，不让公开\n背景事件：武汉新型冠状病毒肺炎\n处罚：罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:10.524517+12
2390	2412	【中国文字狱事件记录】\n日期：2022年03月23日\n地点：河北大名县\n当事人：李某\n平台：某短视频平台\n言论内容：“辱骂负责侦办其涉嫌故意伤害案的民警”\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:17.678991+12
2264	2286	【中国文字狱事件记录】\n日期：2021年08月09日\n地点：山东武城县\n当事人：刘某\n平台：微信群\n言论内容：家人们，现在不是观察桥底下水位的时候了，疫情来德州了，今天三八路东方明珠西戎府小区发现一位病例了\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:10.581474+12
2265	2287	【中国文字狱事件记录】\n日期：2021年08月11日\n地点：江西丰城市\n当事人：张某良\n身份：学者/教师\n平台：今日头条\n言论内容：可不可以让扬州实验一下放弃严格防疫，与病毒共存，看看会产生什么效果……仅仅是建议，勿喷\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留15日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:10.639759+12
2266	2288	【中国文字狱事件记录】\n日期：2021年08月12日\n地点：宁夏银川\n当事人：吴某\n平台：朋友圈\n言论内容：“辱警”言论\n处罚：罚款300元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:10.69574+12
2267	2289	【中国文字狱事件记录】\n日期：2021年08月12日\n地点：宁夏吴忠\n当事人：贺某\n平台：朋友圈\n言论内容：“辱警”言论\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:10.748706+12
2268	2290	【中国文字狱事件记录】\n日期：2021年08月13日\n地点：宁夏石嘴山\n当事人：马路\n平台：微博\n言论内容：说真话的人号没了；疫苗根本对应不了病毒变异；不套干掏空医保，有些人不甘心；嘴上全是主义，心里全是生意\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留15日\n法律文书：石大公（朝阳街）行罚决字［2021］10557号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:10.807979+12
2269	2291	【中国文字狱事件记录】\n日期：2021年08月13日\n地点：云南水富市\n当事人：杨某银\n平台：抖音\n言论内容：（其亲家刑满出狱的视频）凯旋归来\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:10.864935+12
2270	2292	【中国文字狱事件记录】\n日期：2021年08月18日\n地点：浙江磐安县\n当事人：王某\n平台：某短视频平台\n言论内容：交警执法视频和“侮辱性文字”\n处罚：拘留8日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:10.9214+12
2271	2293	【中国文字狱事件记录】\n日期：2021年08月19日\n地点：河南南阳\n当事人：陈宏伟\n平台：微信群\n言论内容：自己不打疫苗是没有配合贪官套取医保基金；“未经核实的涉党涉政不良信息“\n处罚：拘留13日\n法律文书：卧公（武）行罚决字［2021］1305号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:10.9776+12
2272	2294	【中国文字狱事件记录】\n日期：2021年08月19日\n地点：陕西西安\n当事人：张某\n平台：微博\n言论内容：大量辱国、辱军、辱民等不当言论\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:11.031406+12
2273	2295	【中国文字狱事件记录】\n日期：2021年08月19日\n地点：江西于都县\n当事人：孙某福\n平台：微信群\n言论内容：现在土匪抢劫太厉害了；这是岭背支队的土匪\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:11.085337+12
2274	2296	【中国文字狱事件记录】\n日期：2021年08月24日\n地点：河北安平县\n当事人：王某\n平台：抖音\n言论内容：针对城市管理警察大队的“不当言论”\n处罚：拘留15日、罚款1000元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:11.14154+12
2275	2297	【中国文字狱事件记录】\n日期：2021年08月25日\n地点：河南周口\n当事人：王某志\n平台：微信群\n言论内容：一张诋毁国家反诈中心app宣传人员的图片\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:11.196729+12
2276	2298	【中国文字狱事件记录】\n日期：2021年08月25日\n地点：黑龙江伊春\n当事人：张某辉\n平台：抖音\n言论内容：当地某社区强制将高龄老人拉去打疫苗，并且虚报疫苗接种率\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:11.253843+12
2277	2299	【中国文字狱事件记录】\n日期：2021年08月25日\n地点：浙江慈溪市\n当事人：李某\n平台：朋友圈\n言论内容：你们都是畜生；有种你们天天来，老子就要你们没的闲；狗东西又出门了（指警察）\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:11.308596+12
2278	2300	【中国文字狱事件记录】\n日期：2021年08月26日\n地点：山西长治\n当事人：贾某\n平台：微博\n言论内容：长治县前巷交警二大队的煞笔交警鬼节当天出来贴罚单，你是没钱给你家人买纸钱了么？\n处罚：拘留10日\n法律文书：长城公行罚决字［2021］000800号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:11.366574+12
2279	2301	【中国文字狱事件记录】\n日期：2021年08月28日\n地点：浙江温州\n当事人：C某（化名）\n平台：微信群\n言论内容：“辱骂村干部的言论”\n处罚：拘留6日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:11.422708+12
2280	2302	【中国文字狱事件记录】\n日期：2021年08月31日\n地点：浙江永嘉县\n当事人：不详\n平台：朋友圈\n言论内容：“多条称警察为土匪的内容”\n处罚：拘留6日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:11.479898+12
2281	2303	【中国文字狱事件记录】\n日期：2021年09月07日\n地点：安徽全椒县\n当事人：田某\n平台：微信群\n言论内容：打的好，警察不是好的\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:11.532649+12
2282	2304	【中国文字狱事件记录】\n日期：2021年09月08日\n地点：河南商城县\n当事人：李某\n平台：抖音\n言论内容：人人喊打一群过街老鼠，没人性的玩意，没通融性的东西，怎么有脸硬抢，以为穿上这身皮多牛逼似的\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:11.591451+12
2283	2305	【中国文字狱事件记录】\n日期：2021年09月08日\n地点：陕西吴堡县\n当事人：宋某\n平台：微博\n言论内容：“虚假信息”\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:11.647547+12
2284	2306	【中国文字狱事件记录】\n日期：2021年09月09日\n地点：安徽宿松县\n当事人：刘某辉\n平台：抖音\n言论内容：“辱骂交警”的视频\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:11.704333+12
2285	2307	【中国文字狱事件记录】\n日期：2021年09月15日\n地点：江西南丰县\n当事人：袁某\n平台：抖音\n言论内容：当地一名五年级小女孩险被拐卖，咬伤了人贩子的手得以逃脱\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:11.761055+12
2286	2308	【中国文字狱事件记录】\n日期：2021年09月17日\n地点：浙江舟山\n当事人：刘某\n平台：网络\n言论内容：9个来普陀山的莆田人确诊新冠肺炎\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:11.817484+12
2287	2309	【中国文字狱事件记录】\n日期：2021年09月19日\n地点：湖北丹江口市\n当事人：熊某\n平台：微信群、QQ群\n言论内容：农夫山泉一大货车司机被确诊…\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:11.871568+12
2288	2310	【中国文字狱事件记录】\n日期：2021年09月22日\n地点：浙江金华\n当事人：方某\n平台：现实/印制锦旗\n言论内容：浑浑噩噩滥用法律\n处罚：拘留10日\n备注：为其印制锦旗的广告公司也被罚款一万元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:11.93007+12
2289	2311	【中国文字狱事件记录】\n日期：2021年09月26日\n地点：江苏常州\n当事人：陈某\n平台：微信群\n言论内容：“篡改国歌”的内容，大意为抵制物业入驻小区\n处罚：行政警告	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:11.984893+12
2290	2312	【中国文字狱事件记录】\n日期：2021年09月26日\n地点：安徽泾县\n当事人：周某\n平台：微信群\n言论内容：死人骨头（朝鲜战争志愿军遗骸）有必要运回来吗，浪费土地\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:12.039578+12
2291	2313	【中国文字狱事件记录】\n日期：2021年09月26日\n地点：湖南汝城县\n当事人：钟某红\n平台：抖音、朋友圈\n言论内容：“辱骂共产党、汝城县交警的视频、图片”\n处罚：拘留12日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:12.096461+12
2292	2314	【中国文字狱事件记录】\n日期：2021年09月27日\n地点：贵州黄平县\n当事人：周某穗\n平台：抖音\n言论内容：（评论交警执勤视频）还有几条狗\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:12.15735+12
2293	2315	【中国文字狱事件记录】\n日期：2021年09月29日\n地点：内蒙古阿巴嘎旗\n当事人：付某\n平台：微博\n言论内容：阿巴嘎旗这个工地欠工钱不给，打电话要钱还骂人有涉黑倾向\n处罚：批评教育	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:12.218077+12
2294	2316	【中国文字狱事件记录】\n日期：2021年10月09日\n地点：四川蓬溪县\n当事人：魏某\n平台：朋友圈\n言论内容：今天星期六这些灾舅子不耍假还在任家桥小学查车。可能是么得烟钱了。哎呦卧槽\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:12.273095+12
2295	2317	【中国文字狱事件记录】\n日期：2021年10月10日\n地点：江西南昌\n当事人：左某东\n平台：微博\n言论内容：沙雕连不能说？沙雕连！沙雕连！沙雕连！寒战最大的成果就是蛋炒饭，感谢蛋炒饭！\n背景事件：罗昌平被刑事拘留\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:12.330404+12
2296	2318	【中国文字狱事件记录】\n日期：2021年10月12日\n地点：北京\n当事人：许某怡\n平台：微博\n言论内容：一个不能上街游行的国家，养了一堆窝家互联网暴民，有跟董存瑞似的彩妆gay\n处罚：有期徒刑7个月	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:12.38916+12
2297	2319	【中国文字狱事件记录】\n日期：2021年10月13日\n地点：浙江嘉兴\n当事人：李某\n平台：微信\n言论内容：对抗美援朝英烈的“侮辱”言论\n处罚：拘留6日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:12.444971+12
2298	2320	【中国文字狱事件记录】\n日期：2021年10月21日\n地点：青海海东\n当事人：余某\n平台：微信群\n言论内容：西宁确诊1例，平安确诊2例，她在西宁密集接触了500多人！平安已经封城了，平安的学校和办事大厅都停了\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:12.503077+12
2299	2321	【中国文字狱事件记录】\n日期：2021年10月21日\n地点：青海海东\n当事人：张某\n平台：微博\n言论内容：疫情大爆发，海东平安县发现三例，也太可怕了\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:12.562186+12
2300	2322	【中国文字狱事件记录】\n日期：2021年10月30日\n地点：宁夏青铜峡市\n当事人：李某\n平台：微信群\n言论内容：一张表情图，内容为一条狗戴着警帽，手拿警察证\n处罚：拘留9日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:12.61916+12
2301	2323	【中国文字狱事件记录】\n日期：2021年11月03日\n地点：安徽泗县\n当事人：高某\n平台：抖音\n言论内容：xxx是交警，逮到我骑电动车没戴头盔罚我站两小时\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:12.677929+12
2302	2324	【中国文字狱事件记录】\n日期：2021年11月03日\n地点：青海化隆县\n当事人：肖某\n平台：朋友圈\n言论内容：希望这个瘟疫能维持久点儿和能死更多的人。永远都好不起来那种；看我不顺眼的人，我都弄死他——我压根也没看你\n背景事件：武汉新型冠状病毒肺炎\n处罚：“依法处理”	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:12.736322+12
2303	2325	【中国文字狱事件记录】\n日期：2021年11月03日\n地点：山东淄博\n当事人：邹志平\n平台：电报\n言论内容：反对政府的言论，警方称“有害信息”\n处罚：拘留15日\n法律文书：张公（法）行罚决字［2021］17号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:12.792123+12
2304	2326	【中国文字狱事件记录】\n日期：2021年11月03日\n地点：河北深泽县\n当事人：刘某\n平台：微信群\n言论内容：“涉疫虚假信息”\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:12.850602+12
2305	2327	【中国文字狱事件记录】\n日期：2021年11月04日\n地点：河北辛集市\n当事人：贾某\n平台：快手\n言论内容：“与疫情防控不符的不当言论”\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留7日、罚款300元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:12.907231+12
2306	2328	【中国文字狱事件记录】\n日期：2021年11月08日\n地点：浙江台州\n当事人：李某\n平台：朋友圈\n言论内容：（交通罚单照片）妈的被狗咬了\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:12.965116+12
2307	2329	【中国文字狱事件记录】\n日期：2021年11月08日\n地点：陕西定边县\n当事人：郑某燕\n平台：某短视频平台\n言论内容：（视频直播）“社会敏感案事件妄加猜测，道听途说，散播不实信息”\n处罚：行政处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:13.018237+12
2308	2331	【中国文字狱事件记录】\n日期：2021年11月10日\n地点：贵州凯里\n当事人：欧某\n平台：微信群\n言论内容：交警这些才是狗日的，每个人应该有一次警告的机会，这些交警真的是野生动物\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:13.124104+12
2309	2332	【中国文字狱事件记录】\n日期：2021年11月10日\n地点：青海互助县\n当事人：宋某\n平台：微信群\n言论内容：“辱骂村干部的言论”\n处罚：拘留10日、罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:13.174339+12
2310	2333	【中国文字狱事件记录】\n日期：2021年11月12日\n地点：山东临沭县\n当事人：张某生\n平台：微信群\n言论内容：“侮辱交警”的语音信息\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:13.240131+12
2311	2334	【中国文字狱事件记录】\n日期：2021年11月13日\n地点：内蒙古呼和浩特\n当事人：赵某\n平台：抖音\n言论内容：呼市又确诊一例\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:13.295799+12
2312	2335	【中国文字狱事件记录】\n日期：2021年11月14日\n地点：甘肃会宁县\n当事人：高某\n平台：某直播平台\n言论内容：对一女童失踪案“妄加猜测”，散播“不实言论”\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:13.350582+12
2313	2336	【中国文字狱事件记录】\n日期：2021年11月15日\n地点：新疆皮山县\n当事人：李奇贤\n平台：今日头条\n言论内容：其站在陈祥榕墓碑旁边的一张自拍照，照片中其脚踩到了墓碑底座\n处罚：有期徒刑7个月	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:13.405051+12
2314	2337	【中国文字狱事件记录】\n日期：2021年11月15日\n地点：四川资中县\n当事人：邓某\n平台：抖音\n言论内容：资中的交警要吃人了，解个小手，打起双闪，就开个罚单\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:13.461593+12
2391	2413	【中国文字狱事件记录】\n日期：2022年03月23日\n地点：四川筠连县\n当事人：张某\n平台：网络\n言论内容：“辱骂交警的不当言论“\n处罚：拘留8日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:17.732511+12
2315	2338	【中国文字狱事件记录】\n日期：2021年11月16日\n地点：陕西汉中\n当事人：肖某\n平台：微信群\n言论内容：四号桥的抢劫犯；这是土匪，有本事去打美国，只会在这里横\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:13.516979+12
2316	2339	【中国文字狱事件记录】\n日期：2021年11月18日\n地点：贵州台江县\n当事人：杨某辉\n平台：微信群\n言论内容：“侮辱民警的语音”\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:13.570528+12
2317	2340	【中国文字狱事件记录】\n日期：2021年11月21日\n地点：广西桂平市\n当事人：谢某\n平台：今日头条\n言论内容：“涉疫不当言论”\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:13.62582+12
2318	2341	【中国文字狱事件记录】\n日期：2021年11月26日\n地点：北京道衡律师事务所\n当事人：梁小军\n平台：推特、微博\n言论内容：“支持法轮功的言论和丑化、抹黑宪法法律确立的根本制度和基本原则”的言论\n处罚：吊销律师资格证\n法律文书：京司（罚告）（2021）14号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:13.682803+12
2319	2342	【中国文字狱事件记录】\n日期：2021年11月30日\n地点：黑龙江讷河市\n当事人：董某\n平台：快手\n言论内容：涉疫情“不当言论”\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:13.738906+12
2320	2343	【中国文字狱事件记录】\n日期：2021年12月02日\n地点：吉林双辽市\n当事人：王某\n平台：微信群\n言论内容：“辱警言论”\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:13.796411+12
2321	2344	【中国文字狱事件记录】\n日期：2021年12月03日\n地点：浙江温岭市\n当事人：肖某\n平台：微信群\n言论内容：对的，抓小偷抓骗子多不管，开始对电动车下手了……接到狗子的电话……简直强盗\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:13.850758+12
2322	2345	【中国文字狱事件记录】\n日期：2021年12月06日\n地点：浙江台州\n当事人：易某\n平台：朋友圈\n言论内容：（交通罚单照片）今天又被狗咬了\n处罚：拘留6日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:13.906108+12
2323	2346	【中国文字狱事件记录】\n日期：2021年12月07日\n地点：广西融水县\n当事人：韦某生\n平台：朋友圈\n言论内容：（交警执法视频）土匪又在贴单\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:13.966176+12
2324	2347	【中国文字狱事件记录】\n日期：2021年12月08日\n地点：贵州丹寨县\n当事人：潘某\n平台：朋友圈\n言论内容：大早上 饿钱多找你妈 找我\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:14.019734+12
2325	2348	【中国文字狱事件记录】\n日期：2021年12月09日\n地点：甘肃陇南\n当事人：张某\n平台：微信群\n言论内容：“辱骂村干部的言论”\n处罚：拘留6日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:14.072235+12
2326	2349	【中国文字狱事件记录】\n日期：2021年12月11日\n地点：青岛大学\n当事人：高薇嘉（高鸭）\n身份：学者/教师\n平台：微博\n言论内容：我们这代，靖国神社随便去；堂堂中华儿女，身正不怕影子斜！心中无鬼，俯仰天地\n处罚：成立工作组调查	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:14.12576+12
2327	2350	【中国文字狱事件记录】\n日期：2021年12月13日\n地点：江苏淮安\n当事人：史某\n平台：微博\n言论内容：淮安这个黑交警真的一塌糊涂，四次来淮安，四次被罚\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:14.194222+12
2328	2351	【中国文字狱事件记录】\n日期：2021年12月15日\n地点：上海震旦职业学院\n当事人：宋庚一\n身份：学者/教师\n平台：现实/课堂\n言论内容：你这个30万如果没史料支撑，那也可能只是民间说说而已\n处罚：开除	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:14.253781+12
2329	2352	【中国文字狱事件记录】\n日期：2021年12月15日\n地点：贵州施秉县\n当事人：廖某\n平台：抖音\n言论内容：你几爷崽阴魂不散呢，吃个早餐也能遇见你\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:14.303807+12
2330	2353	【中国文字狱事件记录】\n日期：2021年12月16日\n地点：广西横州市\n当事人：阿辉（化名）\n平台：朋友圈\n言论内容：以国歌为背景音乐的“负面言论”视频\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:14.358481+12
2331	2354	【中国文字狱事件记录】\n日期：2021年12月17日\n地点：湖南衡阳县\n当事人：刘某文\n平台：QQ群\n言论内容：南京大屠杀不是假的吗？有些人说是假的；为了营造爱国气氛虚构出来的；不知道是不是\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:14.416212+12
2332	2355	【中国文字狱事件记录】\n日期：2021年12月21日\n地点：深圳大学\n当事人：吴远卿\n平台：朋友圈\n言论内容：《人民日报：不告密不揭发是道德底线》；恶意举报老师的小人，其告密行为将记入档案，终生受益呦\n背景事件：上海震旦学院教师宋庚一因课堂言论被开除\n处罚：调查中	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:14.469228+12
2333	2356	【中国文字狱事件记录】\n日期：2021年12月22日\n地点：吉林长春\n当事人：王某阳\n平台：抖音\n言论内容：（视频）查干湖冬捕欺骗了全国\n处罚：行政拘留、罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:14.526567+12
2334	2357	【中国文字狱事件记录】\n日期：2021年12月23日\n地点：宁夏银川\n当事人：王某\n平台：微博\n言论内容：“西安疫情防控太差”；“诅咒西安人及疫情防控”\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:14.584476+12
2335	2358	【中国文字狱事件记录】\n日期：2021年12月28日\n地点：宁夏西吉县\n当事人：张某\n平台：微信群\n言论内容：“辱骂村干部的言论”\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:14.64382+12
2336	2359	【中国文字狱事件记录】\n日期：2021年12月30日\n地点：江西上犹县\n当事人：曾某\n平台：朋友圈\n言论内容：（交通罚单照片）出门没看黄历，一大早，被狗咬了一下\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:14.701626+12
2337	2360	【中国文字狱事件记录】\n日期：2021年12月31日\n地点：四川成都\n当事人：蒲正宝\n平台：推特\n言论内容：“攻击党和国家领导人及涉港的负面言论”\n处罚：拘留10日\n法律文书：成武公（玉）行罚决字［2022］95号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:14.761761+12
2338	2361	【中国文字狱事件记录】\n日期：2021年12月31日\n地点：江西萍乡\n当事人：陈某\n平台：抖音\n言论内容：看今天这些交警，些🐶样，车子没有戴头盔的全部下来\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:14.819964+12
2339	2362	【中国文字狱事件记录】\n日期：2022年01月04日\n地点：广西融水县\n当事人：兰某\n平台：微信群\n言论内容：（含有警察的一张照片）白云口小学有狗\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:14.874311+12
2340	2363	【中国文字狱事件记录】\n日期：2022年01月05日\n地点：陕西彬州市\n当事人：段某\n平台：网络\n言论内容：针对疫情防控的“不当言论”\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:14.930121+12
2341	2364	【中国文字狱事件记录】\n日期：2022年01月05日\n地点：陕西彬州市\n当事人：师某\n平台：网络\n言论内容：针对疫情防控的“不当言论”\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:14.989421+12
2342	2365	【中国文字狱事件记录】\n日期：2022年01月05日\n地点：陕西彬州市\n当事人：任某\n平台：网络\n言论内容：针对疫情防控的“不当言论”\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:15.037201+12
2343	2366	【中国文字狱事件记录】\n日期：2022年01月05日\n地点：陕西彬州市\n当事人：何某\n平台：网络\n言论内容：针对疫情防控的“不当言论”\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:15.089429+12
2344	2367	【中国文字狱事件记录】\n日期：2022年01月05日\n地点：云南江城县\n当事人：毕某\n平台：朋友圈\n言论内容：有关新冠疫情及疫苗的“不当言论”\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:15.148794+12
2345	2368	【中国文字狱事件记录】\n日期：2022年01月05日\n地点：广西崇左市\n当事人：许某龙\n平台：红豆社区\n言论内容：崇左交警绝对有罚款KPI指标。为了罚款而罚款。穿着警察的服装，干着土匪的事情。\n处罚：教育训诫、进一步办理中	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:15.201968+12
2346	2369	【中国文字狱事件记录】\n日期：2022年01月05日\n地点：浙江缙云县\n当事人：何某\n平台：朋友圈\n言论内容：每次出门都遇到狼狗，真的和狼狗杠上了\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:15.262271+12
2347	2370	【中国文字狱事件记录】\n日期：2022年01月05日\n地点：云南勐腊县\n当事人：毕某\n平台：朋友圈\n言论内容：“关于新冠疫情及疫苗有关的不当言论”\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:15.319+12
2348	2371	【中国文字狱事件记录】\n日期：2022年01月06日\n地点：中国侨联基层建设部组织处\n当事人：宋汶洮\n身份：党政官员\n平台：微信公众平台\n言论内容：文章《西安百姓的悲哀：为什么有人不惜违法、冒死也要逃离西安？》（批评西安防疫手段，并为民众诉苦)\n背景事件：武汉新型冠状病毒肺炎\n处罚：免职	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:15.372738+12
2349	2372	【中国文字狱事件记录】\n日期：2022年01月09日\n地点：山西太原\n当事人：胡新成\n平台：网络、现实\n言论内容：呼吁推行全民免费医疗的内容\n处罚：刑事拘留（宣扬恐怖主义罪）	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:15.426241+12
2350	2373	【中国文字狱事件记录】\n日期：2022年01月11日\n地点：湖南长沙\n当事人：谢阳\n身份：律师\n平台：现实/举牌\n言论内容：接李田田老师母子回家\n处罚：刑事拘留\n法律文书：长公（国）拘字［2022］A001号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:15.483218+12
2351	2374	【中国文字狱事件记录】\n日期：2022年01月12日\n地点：江苏扬中市\n当事人：余某\n平台：朋友圈\n言论内容：刚准备送小巴西上学就碰到这个XX…典型的无利不起早\n处罚：拘留2日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:15.538607+12
2352	2375	【中国文字狱事件记录】\n日期：2022年01月15日\n地点：四川南江县\n当事人：吴某\n平台：朋友圈\n言论内容：南江的🐶又开始挣过年钱了\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:15.594219+12
2353	2376	【中国文字狱事件记录】\n日期：2022年01月17日\n地点：陕西彬州市\n当事人：李某\n平台：微信群\n言论内容：打完疫苗不能直接做核酸，否则就是阳性，核酸后打疫苗不影响，切记切记！！！\n背景事件：武汉新型冠状病毒肺炎\n处罚：罚款500元\n备注：1/19处罚撤销	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:15.650575+12
2354	2377	【中国文字狱事件记录】\n日期：2022年01月20日\n地点：内蒙古四子王旗\n当事人：康某\n平台：微信群\n言论内容：“不良言论”及组织上访\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:15.706857+12
2355	2378	【中国文字狱事件记录】\n日期：2022年02月04日\n地点：广西都安县\n当事人：蓝某\n平台：网络\n言论内容：这种人死不足惜，试问他打过仗了吗？保家卫国了吗？为民做好事了吗？没有资格称英雄\n背景事件：当地两名消防员在救火时牺牲\n处罚：拘留10日、罚款1000元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:15.764208+12
2356	2379	【中国文字狱事件记录】\n日期：2022年02月08日\n地点：广西德保县\n当事人：卢某\n平台：微信群\n言论内容：这回德保县人全部死亡了，说这话不对吗？关闭一个月买东西也买不了\n处罚：“依法处理”	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:15.822424+12
2357	2380	【中国文字狱事件记录】\n日期：2022年02月08日\n地点：四川苍溪县\n当事人：阳某\n平台：网络\n言论内容：境外输入新冠检测异常人员复核结果为阴性，所在小区已解封\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:15.882591+12
2358	2381	【中国文字狱事件记录】\n日期：2022年02月09日\n地点：河南舞阳县\n当事人：张某\n平台：抖音\n言论内容：（评论舞阳交警发布的一则视频）这X裤子都没提上\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:15.942272+12
2359	2382	【中国文字狱事件记录】\n日期：2022年02月18日\n地点：云南勐腊县\n当事人：曹某\n平台：网络\n言论内容：（针对疫情管控措施的）“怂恿、煽动性言论”\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:16.001893+12
2360	2383	【中国文字狱事件记录】\n日期：2022年02月21日\n地点：江西万年县\n当事人：徐某\n平台：抖音\n言论内容：“辱骂交警”的言论\n处罚：拘留6日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:16.056936+12
2361	2384	【中国文字狱事件记录】\n日期：2022年02月25日\n地点：浙江江山市\n当事人：张某\n平台：网络\n言论内容：**科技疫情大暴发，出现100例\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:16.111274+12
2362	2385	【中国文字狱事件记录】\n日期：2022年02月25日\n地点：甘肃静宁县\n当事人：胡莘\n平台：推特\n言论内容：在手机上安装推特等境外软件以及在推特发布涉政言论和“丑化国家领导人”的信息\n处罚：拘留7日\n法律文书：静公（网）行罚决字（2022）63号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:16.166864+12
2363	2386	【中国文字狱事件记录】\n日期：2022年02月28日\n地点：海南屯昌县\n当事人：赵某\n平台：网络\n言论内容：“侮辱交警”的言论\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:16.222391+12
2364	2387	【中国文字狱事件记录】\n日期：2022年03月03日\n地点：湖南长沙\n当事人：彭佩玉（彭松华）\n平台：网络\n言论内容：《关于发起反战游行示威的公民呼吁书》呼吁反战人士到俄罗斯驻华大使馆门口游行示威\n背景事件：俄罗斯入侵乌克兰\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:16.276243+12
2441	2464	【中国文字狱事件记录】\n日期：2022年08月09日\n地点：吉林龙口市\n当事人：姜某\n平台：网络\n言论内容：“不实言论”\n处罚：拘留3日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:20.523032+12
2365	2388	【中国文字狱事件记录】\n日期：2022年03月07日\n地点：吉林磐石市\n当事人：于某\n平台：某短视频平台\n言论内容：2条涉疫视频\n背景事件：武汉新型冠状病毒肺炎\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:16.330062+12
2366	2389	【中国文字狱事件记录】\n日期：2022年03月07日\n地点：浙江兰溪市\n当事人：郭某\n平台：朋友圈\n言论内容：兰溪城管，你家里到底死了多少人，需要买棺材，人在车上你不过来拍，人刚下车停了两分钟被你贴去\n处罚：拘留9日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:16.384118+12
2367	2390	【中国文字狱事件记录】\n日期：2022年03月08日\n地点：江苏连云港\n当事人：谢某\n平台：朋友圈\n言论内容：一张疫情数据分析图，并配有“不当言论”\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留15日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:16.439461+12
2368	2391	【中国文字狱事件记录】\n日期：2022年03月08日\n地点：吉林永吉县\n当事人：郑某\n平台：网络\n言论内容：关于新冠肺炎疫情的“虚假言论”\n背景事件：武汉新型冠状病毒肺炎\n处罚：治安处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:16.496025+12
2369	2392	【中国文字狱事件记录】\n日期：2022年03月09日\n地点：吉林吉林\n当事人：昌某\n平台：某短视频平台\n言论内容：“虚假涉疫信息和涉疫谣言”\n背景事件：武汉新型冠状病毒肺炎\n处罚：治安拘留并罚款	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:16.553517+12
2370	2393	【中国文字狱事件记录】\n日期：2022年03月13日\n地点：河南修武县\n当事人：王某\n平台：微博\n言论内容：修武交警这是怎么了，没钱花了么，天天他妈查老百姓，xxxxxx……\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:16.612817+12
2371	2394	【中国文字狱事件记录】\n日期：2022年03月16日\n地点：贵州思南县\n当事人：张某\n平台：网络\n言论内容：“涉疫不当言论”\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:16.672343+12
2372	2395	【中国文字狱事件记录】\n日期：2022年03月16日\n地点：广东深圳\n当事人：赵某波\n平台：网络\n言论内容：一张修改过的“良民出入证”照片，原内容为“居民出入证”\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:16.73235+12
2373	2396	【中国文字狱事件记录】\n日期：2022年03月16日\n地点：河北南宫市\n当事人：马某\n平台：微信群\n言论内容：南宫垂杨确诊一列，又芭比Q\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留2日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:16.796205+12
2374	2397	【中国文字狱事件记录】\n日期：2022年03月16日\n地点：河北南宫市\n当事人：王某\n平台：微信群\n言论内容：（转发）南宫垂杨确诊一列，又芭比Q\n背景事件：武汉新型冠状病毒肺炎\n处罚：罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:16.856825+12
2375	2398	【中国文字狱事件记录】\n日期：2022年03月16日\n地点：浙江湖州\n当事人：不详（共5人）\n平台：网络\n言论内容：爱家又新增一例，织里童装城关了\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:16.914203+12
2376	2399	【中国文字狱事件记录】\n日期：2022年03月16日\n地点：浙江湖州\n当事人：不详（5人）\n平台：网络\n言论内容：爱家又新增一例，织里童装城关了；大家注意了，这个人也被传染上了\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:16.972064+12
2377	2400	【中国文字狱事件记录】\n日期：2022年03月17日\n地点：河南鹤壁\n当事人：张某\n平台：网络\n言论内容：“侮辱交警”的视频\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:17.027419+12
2378	2401	【中国文字狱事件记录】\n日期：2022年03月17日\n地点：四川筠连县\n当事人：张某\n平台：朋友圈\n言论内容：你这些狗日的停个车子两分钟就把违章贴起了。是搞得快。喊你们出警的时候咋个弄慢安。\n处罚：拘留8日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:17.083962+12
2379	2402	【中国文字狱事件记录】\n日期：2022年03月17日\n地点：吉林龙口市\n当事人：张某\n平台：微信群\n言论内容：龙口有一例确诊的\n背景事件：武汉新型冠状病毒肺炎\n处罚：治安处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:17.141475+12
2380	2403	【中国文字狱事件记录】\n日期：2022年03月18日\n地点：浙江平阳县\n当事人：王某\n平台：朋友圈\n言论内容：尼玛的死交警；你tmd死交警，竟耽误我事儿\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:17.200565+12
2381	2404	【中国文字狱事件记录】\n日期：2022年03月19日\n地点：江苏常州\n当事人：唐某\n平台：网络\n言论内容：“质疑核酸检测的必要性和科学性，煽动他人不要出门做核酸检测”\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:17.258433+12
2382	2405	【中国文字狱事件记录】\n日期：2022年03月19日\n地点：辽宁盖州市\n当事人：安某润\n平台：朋友圈\n言论内容：针对疫情的“不当言论”\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:17.311425+12
2383	2406	【中国文字狱事件记录】\n日期：2022年03月19日\n地点：河北魏县\n当事人：陈某林\n平台：网络\n言论内容：（视频）回隆镇刘庄营村确诊6例新冠疫情阳性病例\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:17.358535+12
2384	2407	【中国文字狱事件记录】\n日期：2022年03月20日\n地点：湖南永州\n当事人：谭某军\n平台：抖音\n言论内容：针对疫情的“不当言论”\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:17.408482+12
2385	2408	【中国文字狱事件记录】\n日期：2022年03月20日\n地点：山东武城县\n当事人：赵某\n平台：微信群\n言论内容：“不实言论，随意捏造新增病例数量”\n背景事件：武汉新型冠状病毒肺炎\n处罚：罚款200元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:17.463629+12
2386	2459	【中国文字狱事件记录】\n日期：2022年07月31日\n地点：山西文水县\n当事人：赵某\n平台：微信群\n言论内容：“辱骂交警的言论”\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:20.242964+12
2387	2409	【中国文字狱事件记录】\n日期：2022年03月21日\n地点：福建石狮市\n当事人：林某\n平台：朋友圈\n言论内容：村里刚通知，某某公司确诊三个。基本可以躺平了！……\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:17.515766+12
2388	2410	【中国文字狱事件记录】\n日期：2022年03月23日\n地点：上海\n当事人：张某\n平台：网络\n言论内容：上海马上封城7天；全封4天\n背景事件：武汉新型冠状病毒肺炎\n处罚：立案侦查\n备注：数日后谣言成真	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:17.571072+12
2389	2411	【中国文字狱事件记录】\n日期：2022年03月23日\n地点：上海\n当事人：俞某\n平台：网络\n言论内容：上海马上封城7天；全封4天\n背景事件：武汉新型冠状病毒肺炎\n处罚：立案侦查\n备注：数日后谣言成真	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:17.623704+12
2392	2414	【中国文字狱事件记录】\n日期：2022年03月25日\n地点：山西运城\n当事人：黄某\n平台：网络\n言论内容：运城盐湖区停工停产，全部排队做核酸；山西运城又有3例了\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:17.782733+12
2393	2415	【中国文字狱事件记录】\n日期：2022年03月26日\n地点：河北香河县\n当事人：江某\n平台：网络\n言论内容：“防疫消极言论”和一条“未经证实的香河县居民跳楼的视频”\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:17.837639+12
2394	2416	【中国文字狱事件记录】\n日期：2022年03月26日\n地点：吉林龙口市\n当事人：邵某\n平台：抖音\n言论内容：龙口封城\n背景事件：武汉新型冠状病毒肺炎\n处罚：治安处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:17.893569+12
2395	2417	【中国文字狱事件记录】\n日期：2022年03月31日\n地点：吉林长春\n当事人：马某财\n平台：网络\n言论内容：视频，内容为防疫人员在摆拍送菜，并配文发生在长春\n背景事件：武汉新型冠状病毒肺炎\n处罚：刑事拘留\n备注：官方通报事件属实，发生在吉林市	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:17.948419+12
2396	2418	【中国文字狱事件记录】\n日期：2022年04月02日\n地点：海南海口\n当事人：李某\n平台：微信群\n言论内容：国科园查出24例\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:18.001317+12
2397	2419	【中国文字狱事件记录】\n日期：2022年04月03日\n地点：海南海口\n当事人：张某\n平台：微信群\n言论内容：海甸岛新增12例\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:18.053311+12
2398	2420	【中国文字狱事件记录】\n日期：2022年04月03日\n地点：江苏涟水县\n当事人：季某\n平台：网络\n言论内容：“涉疫情防控不实信息”\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:18.105992+12
2399	2421	【中国文字狱事件记录】\n日期：2022年04月05日\n地点：海南三亚\n当事人：周某\n平台：网络\n言论内容：三亚儋州社区大事件，核酸检测过程出现意外；做核酸的人，是老人突然不舒服，抢救无效去世了\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日、罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:18.154378+12
2400	2422	【中国文字狱事件记录】\n日期：2022年04月06日\n地点：海南昌江县\n当事人：林某\n平台：微信群\n言论内容：视频；海尾来了一例了\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:18.210266+12
2401	2423	【中国文字狱事件记录】\n日期：2022年04月07日\n地点：山西吕梁\n当事人：任某\n平台：微信群\n言论内容：“不当言论”，引发隔离人员聚集（其本人当时也正在隔离）\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:18.260756+12
2402	2424	【中国文字狱事件记录】\n日期：2022年04月08日\n地点：吉林长春\n当事人：王某\n平台：微信群\n言论内容：“煽动敲盆行动”\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留7日、罚款300元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:18.313039+12
2403	2425	【中国文字狱事件记录】\n日期：2022年04月09日\n地点：海南三亚\n当事人：郭某飞\n平台：网络\n言论内容：（视频）做核酸瞬间两例，直接封现场不做了，太可怕了\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日、罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:18.367548+12
2404	2426	【中国文字狱事件记录】\n日期：2022年04月12日\n地点：江西赣州\n当事人：廖某\n平台：微信群\n言论内容：“辱骂交警”的言论\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:18.422993+12
2405	2427	【中国文字狱事件记录】\n日期：2022年04月15日\n地点：广西灵山县\n当事人：劳某\n平台：微信群\n言论内容：三里江有狗查车\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:18.481537+12
2406	2428	【中国文字狱事件记录】\n日期：2022年04月16日\n地点：黑龙江哈尔滨\n当事人：唐某敏\n平台：微信群\n言论内容：“要封城了”\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留\n备注：次日谣言成真	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:18.537979+12
2407	2429	【中国文字狱事件记录】\n日期：2022年04月17日\n地点：四川自贡\n当事人：杨某\n平台：抖音\n言论内容：（评论公安发布的抓赌视频）是抢劫16人，不是被抓；贡井土匪抢劫16人，抢得钱财20万\n处罚：拘留14日、罚款900元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:18.591298+12
2408	2430	【中国文字狱事件记录】\n日期：2022年04月17日\n地点：黑龙江哈尔滨\n当事人：姚某\n平台：微信群\n言论内容：道外区三棵、黎华、振江、东原、南马、火车头街道20合一采样均有阳性\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留7日、罚款500元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:18.655306+12
2409	2431	【中国文字狱事件记录】\n日期：2022年04月19日\n地点：浙江义乌\n当事人：黄某\n平台：网络\n言论内容：义乌有好多新冠确诊，可能要封城\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留\n备注：一周后谣言成真	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:18.709445+12
2410	2432	【中国文字狱事件记录】\n日期：2022年04月21日\n地点：吉林和龙市\n当事人：张某龙\n平台：抖音\n言论内容：与疫情相关的“不良言论”\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留14日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:18.757795+12
2411	2433	【中国文字狱事件记录】\n日期：2022年04月22日\n地点：河北邢台\n当事人：聂某\n平台：抖音\n言论内容：视频，内容为防疫人员殴打民众，官方称其为当事人摆拍\n背景事件：武汉新型冠状病毒肺炎\n处罚：调查中	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:18.808702+12
2412	2434	【中国文字狱事件记录】\n日期：2022年04月22日\n地点：河北邢台\n当事人：刘某\n平台：抖音\n言论内容：视频，内容为防疫人员殴打民众，官方称其为当事人摆拍\n背景事件：武汉新型冠状病毒肺炎\n处罚：调查中	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:18.864958+12
2413	2435	【中国文字狱事件记录】\n日期：2022年04月25日\n地点：浙江杭州\n当事人：马某\n平台：网络（疑似电报）\n言论内容：《独立宣言》，“煽动分裂国家、煽动颠覆国家政权”\n处罚：刑事强制措施	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:18.919139+12
2414	2436	【中国文字狱事件记录】\n日期：2022年05月02日\n地点：陕西富县\n当事人：郭某\n平台：抖音\n言论内容：评论疫情防控点交警执勤的“辱警言论”\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:18.972148+12
2415	2437	【中国文字狱事件记录】\n日期：2022年05月05日\n地点：海南三亚\n当事人：罗昌平\n平台：微博\n言论内容：半个世纪后国人少有反思这场战争的正义性，就像当年的沙雕连不会怀疑上峰的“英明决策”\n处罚：有期徒刑7个月	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:19.024005+12
2442	2465	【中国文字狱事件记录】\n日期：2022年08月09日\n地点：吉林龙口市\n当事人：张某\n平台：网络\n言论内容：“不实言论”\n处罚：拘留9日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:20.57879+12
2416	2438	【中国文字狱事件记录】\n日期：2022年05月06日\n地点：辽宁绥中县\n当事人：范某\n平台：网络（直播）\n言论内容：我县区域核酸检测过程中王家店有两个人核酸检测结果异常、王家店人都不让出屋\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:19.074667+12
2417	2439	【中国文字狱事件记录】\n日期：2022年05月11日\n地点：江苏南京\n当事人：丁燕\n平台：微信群\n言论内容：一封写给习近平的公开信，呼吁其放弃清零政策以保障民生\n处罚：关押至精神病院	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:19.12754+12
2418	2440	【中国文字狱事件记录】\n日期：2022年05月12日\n地点：河北曲周县\n当事人：张某\n平台：微信群\n言论内容：关于疫情的“不当言论”\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:19.184386+12
2419	2441	【中国文字狱事件记录】\n日期：2022年05月12日\n地点：河北曲周县\n当事人：张某\n平台：微信群\n言论内容：（转发）关于疫情的“不当言论”\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:19.245959+12
2420	2442	【中国文字狱事件记录】\n日期：2022年05月12日\n地点：河北曲周县\n当事人：赵某\n平台：微信群\n言论内容：（转发）关于疫情的“不当言论”\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:19.298099+12
2421	2443	【中国文字狱事件记录】\n日期：2022年05月14日\n地点：河南平顶山\n当事人：谢某\n平台：微信群\n言论内容：新冠疫情封控区平顶山市新华区乐福小区”不当言论“\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:19.35013+12
2422	2444	【中国文字狱事件记录】\n日期：2022年05月14日\n地点：河南平顶山\n当事人：刘某\n平台：微信群\n言论内容：新冠疫情封控区平顶山市新华区乐福小区”不当言论“\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:19.404497+12
2423	2445	【中国文字狱事件记录】\n日期：2022年05月24日\n地点：湖北鄂州\n当事人：余钱\n平台：推特\n言论内容：质疑当地2020年初疫情封控措施的合法性以及批评中共政权的言论\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留15日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:19.458513+12
2424	2446	【中国文字狱事件记录】\n日期：2022年05月28日\n地点：海南海口\n当事人：郑贵贤\n平台：网络\n言论内容：转发“对国家外交部发言人赵立坚的辱骂言论”并“扬言要殴打赵立坚”\n处罚：拘留15日\n法律文书：美公（人民路）行罚决字［2022］1144号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:19.514191+12
2425	2447	【中国文字狱事件记录】\n日期：2022年06月01日\n地点：湖南岳阳县\n当事人：周某\n平台：微信群\n言论内容：那几个杂毛会遭雷劈的；老子硬是怀疑这些杂种叮抖我的外地牌在抄\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:19.567286+12
2426	2448	【中国文字狱事件记录】\n日期：2022年06月04日\n地点：河南固始县\n当事人：王某\n平台：抖音\n言论内容：实名举报秀水派出所民警张某是黑势力保护伞\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:19.621793+12
2427	2449	【中国文字狱事件记录】\n日期：2022年06月06日\n地点：云南省教育厅\n当事人：罗崇敏（原厅长）\n身份：党政机关官员\n平台：微信公众平台\n言论内容：《端午：一个鼓励自杀的日子》（文章提到刘胡兰等人是不好的榜样，是忠君爱国的自杀者）\n处罚：调查中	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:19.679171+12
2428	2450	【中国文字狱事件记录】\n日期：2022年06月12日\n地点：甘肃徽县\n当事人：龙克海\n平台：微信\n言论内容：批评政府的言论（处罚书中称谣言虚假信息）\n处罚：拘留10日\n法律文书：徽公（国）行罚决字［2022］469号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:19.733746+12
2429	2451	【中国文字狱事件记录】\n日期：2022年06月12日\n地点：甘肃徽县\n当事人：龙克海\n平台：微信\n言论内容：反对战争，谴责战争犯的视频\n处罚：拘留10日\n法律文书：徽公（国）行罚决字［2022］472号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:19.789548+12
2430	2452	【中国文字狱事件记录】\n日期：2022年06月30日\n地点：河南商丘\n当事人：陈某\n平台：微信\n言论内容：交警真血半服；商丘交警够班服嘞\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:19.845132+12
2431	2453	【中国文字狱事件记录】\n日期：2022年07月07日\n地点：青海化隆县\n当事人：赵某\n平台：微信群\n言论内容：“辱骂村干部的言论”\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:19.8971+12
2432	2454	【中国文字狱事件记录】\n日期：2022年07月09日\n地点：唐山师范学院\n当事人：石文瑛\n身份：学者/教师（退休）\n平台：微博\n言论内容：关于安倍先生遇刺，我很庆幸，在我的微信朋友圈没有看到欢呼雀跃的支那劣根奴\n背景事件：安倍晋三遇刺\n处罚：成立工作组调查	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:19.956678+12
2433	2455	【中国文字狱事件记录】\n日期：2022年07月13日\n地点：广西博白县\n当事人：李某\n平台：抖音\n言论内容：广西xx人民政府……以搬迁为由强拆，强征，强埋农人的农田，池塘\n处罚：拘留8日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:20.014059+12
2434	2456	【中国文字狱事件记录】\n日期：2022年07月19日\n地点：湖南湘乡\n当事人：刘某\n平台：抖音\n言论内容：“2段带有对城管局工作人员侮辱性言论的视频”\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:20.071176+12
2435	2457	【中国文字狱事件记录】\n日期：2022年07月19日\n地点：海南东方市\n当事人：蔡某涛\n平台：网络\n言论内容：（视频）三家派出所插手土地纠纷、帮助村委会书记抢占村民土地\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:20.124637+12
2436	2458	【中国文字狱事件记录】\n日期：2022年07月20日\n地点：四川苍溪县\n当事人：赵某\n平台：某短视频平台\n言论内容：县纪委不作为，对他信访反映村干部问题不处理\n处罚：行政处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:20.185921+12
2437	2460	【中国文字狱事件记录】\n日期：2022年08月04日\n地点：山东平原县\n当事人：徐某\n平台：抖音\n言论内容：“不当言论”\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:20.296926+12
2438	2461	【中国文字狱事件记录】\n日期：2022年08月04日\n地点：贵州道真县\n当事人：刘某\n平台：网络\n言论内容：“文恶意攻击、公然诋毁道真县执法机关”的视频\n处罚：拘留6日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:20.352545+12
2439	2462	【中国文字狱事件记录】\n日期：2022年08月05日\n地点：山东招远\n当事人：赵某\n平台：网络\n言论内容：（霉烂食材照片）星童幼儿园采购并使用这样的食材给孩子们吃\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:20.409796+12
2440	2463	【中国文字狱事件记录】\n日期：2022年08月09日\n地点：河北唐山\n当事人：毛慧斌\n平台：微信公众平台\n言论内容：《记者唐山采访遭暴力扣押8小时 央视采访车被砸》等关于唐山烧烤店打人案的文章\n背景事件：唐山烧烤店打人事件\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:20.466884+12
2445	2468	【中国文字狱事件记录】\n日期：2022年08月16日\n地点：湖南祁阳市\n当事人：唐某\n平台：抖音\n言论内容：（视频）“辱骂政府文明创建工作，诋毁祁阳市委市政府形象”\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:20.751209+12
2446	2469	【中国文字狱事件记录】\n日期：2022年08月21日\n地点：广西靖西市\n当事人：颜某\n平台：网络\n言论内容：“涉疫不当言论”\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:20.808806+12
2447	2470	【中国文字狱事件记录】\n日期：2022年08月25日\n地点：安徽蚌埠\n当事人：刘建\n身份：警察\n平台：网络\n言论内容：其单位警察存在私自烧毁案件文件等违法违规行为，导致案件无法侦破\n处罚：刑事拘留\n法律文书：蚌交公（刑）拘通字（2022）12xxx	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:20.866595+12
2448	2471	【中国文字狱事件记录】\n日期：2022年08月28日\n地点：四川成都\n当事人：刘某\n平台：网络\n言论内容：成都环球中心海洋乐园水体样本阳性；今日政府7点会议议程内容\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:20.924222+12
2449	2472	【中国文字狱事件记录】\n日期：2022年08月29日\n地点：四川成都\n当事人：佘某\n平台：微信群\n言论内容：省上要求整个成都市静态管理，市上还在争取……还没有完全确定，现在还在开会商量\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留15日、罚款1000元\n备注：3天后谣言成真	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:20.984405+12
2450	2473	【中国文字狱事件记录】\n日期：2022年09月06日\n地点：湖南衡山县\n当事人：陈某\n平台：微博\n言论内容：乱赋黄码、层层加码；利用全民核酸检测掏空医保资金\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:21.041202+12
2451	2474	【中国文字狱事件记录】\n日期：2022年09月06日\n地点：西藏阿里地区\n当事人：格某\n平台：微信群\n言论内容：阳性、阴性人员混居、没有生活保障以及“辱骂政府、污蔑防疫工作人员”\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留9日、罚款300元	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:21.095766+12
2452	2475	【中国文字狱事件记录】\n日期：2022年09月13日\n地点：山东济宁\n当事人：吴某\n平台：微信群\n言论内容：”号召业主们去抖音平台的央视直播间求助（因疫情封控物资供应不足），并附带直播间链接“\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:21.149822+12
2453	2476	【中国文字狱事件记录】\n日期：2022年09月13日\n地点：山西太原\n当事人：胡某\n平台：微信群\n言论内容：（视频）尖草坪区光社村发生当街斗殴\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:21.206946+12
2454	2477	【中国文字狱事件记录】\n日期：2022年09月14日\n地点：西藏拉萨\n当事人：王某\n平台：网络\n言论内容：“传播涉疫谣言，煽动对立情绪，怂恿聚集滋事”\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:21.274711+12
2455	2478	【中国文字狱事件记录】\n日期：2022年09月18日\n地点：西藏通门县\n当事人：次某\n平台：微博\n言论内容：“涉疫谣言、混淆视听、煽动对立、怂恿聚集滋事“\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:21.335201+12
2456	2479	【中国文字狱事件记录】\n日期：2022年09月18日\n地点：西藏拉萨\n当事人：次某\n平台：网络\n言论内容：“涉疫谣言、混淆视听、煽动对立、怂恿聚集滋事“\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:21.387339+12
2457	2480	【中国文字狱事件记录】\n日期：2022年09月18日\n地点：西藏墨竹工卡县\n当事人：格某\n平台：抖音\n言论内容：“涉疫谣言、混淆视听、煽动对立、怂恿聚集滋事“\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:21.445566+12
2458	2481	【中国文字狱事件记录】\n日期：2022年09月18日\n地点：河南洛阳\n当事人：张某\n平台：微博\n言论内容：扔了200元喂孟津这条xx，让我对孟津恶心至级，孟津穷疯了，xx玩意\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:21.504566+12
2459	2482	【中国文字狱事件记录】\n日期：2022年09月23日\n地点：上海\n当事人：季孝龙\n平台：推特\n言论内容：批评中国防疫政策及中共政府的言论\n背景事件：武汉新型冠状病毒肺炎\n处罚：批捕\n法律文书：沪公浦逮通字（2022）010001号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:21.570505+12
2460	2483	【中国文字狱事件记录】\n日期：2022年09月28日\n地点：青海格尔木\n当事人：李某\n平台：微博\n言论内容：“诋毁防疫政策的言论”\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:21.630327+12
2461	2484	【中国文字狱事件记录】\n日期：2022年09月29日\n地点：新疆察布查尔锡伯县\n当事人：赖某\n平台：短视频平台\n言论内容：伊宁市疫情防控核酸检测结果为”阴性＋阳性“\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:21.688086+12
2462	2485	【中国文字狱事件记录】\n日期：2022年09月30日\n地点：广东深圳\n当事人：姚某\n平台：微信群\n言论内容：深圳明天宣布全市静默3天\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:21.747719+12
2463	2486	【中国文字狱事件记录】\n日期：2022年10月04日\n地点：新疆特克斯县\n当事人：袁某\n平台：即时通讯工具\n言论内容：这个疫情把人害死了，我们这里有上吊的、跳楼的、病死的，比比皆是\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:21.798923+12
2464	2487	【中国文字狱事件记录】\n日期：2022年10月04日\n地点：新疆伊宁\n当事人：古某\n平台：即时通讯工具\n言论内容：听说巩留一个六岁女孩烧的厉害直接死了、直接没有埋、尸体烧了\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:21.853221+12
2465	2488	【中国文字狱事件记录】\n日期：2022年10月05日\n地点：湖北荆州\n当事人：向某\n平台：抖音\n言论内容：（视频）今天抢菜都拿刀抢菜，警察都喊来了\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:21.914138+12
2466	2489	【中国文字狱事件记录】\n日期：2022年10月07日\n地点：新疆阿瓦提县\n当事人：安某\n平台：即时通讯工具\n言论内容：街上的动物都要做核酸\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:21.962655+12
2467	2490	【中国文字狱事件记录】\n日期：2022年10月08日\n地点：新疆伊宁县\n当事人：韩某\n平台：即时通讯工具\n言论内容：伊宁市好多小区没人管了，居民到处跑呢\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:22.014072+12
2468	2491	【中国文字狱事件记录】\n日期：2022年10月08日\n地点：新疆伊宁\n当事人：李某\n平台：即时通讯工具\n言论内容：今天阳出来好多，抓了好几个，巩留拉走……\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政警告	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:22.074058+12
2469	2492	【中国文字狱事件记录】\n日期：2022年10月08日\n地点：新疆克拉玛依\n当事人：黄某\n平台：即时通讯工具\n言论内容：今晚凌晨开始，全克拉玛依静默七天，白碱滩区静默十天\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:22.131983+12
2470	2493	【中国文字狱事件记录】\n日期：2022年10月08日\n地点：新疆伊宁\n当事人：余某\n平台：即时通讯工具\n言论内容：咱们10月9号0点封，取消核酸检测，取消一切配送服务，全疆静默\n背景事件：武汉新型冠状病毒肺炎\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:22.186735+12
2471	2494	【中国文字狱事件记录】\n日期：2022年10月08日\n地点：内蒙古鄂尔多斯\n当事人：高某\n平台：抖音\n言论内容：“不实言论视频，恶意解读疫情防控措施”\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:22.243434+12
2472	2495	【中国文字狱事件记录】\n日期：2022年10月11日\n地点：上海\n当事人：“米毛酷”\n平台：推特\n言论内容：“丑化国家领导人的推文”\n处罚：传唤警告	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:22.297189+12
2473	2496	【中国文字狱事件记录】\n日期：2022年10月11日\n地点：河南郑州\n当事人：张某\n平台：微信群\n言论内容：郑州市疾控中心上午开会研判，从明天开始，郑州市全域实行三天静默管理，包括五市县，先准备几天的菜吧\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日\n备注：后来实际封城远不止3天	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:22.354252+12
2474	2497	【中国文字狱事件记录】\n日期：2022年10月12日\n地点：新疆乌鲁木齐\n当事人：文某均\n平台：微信群\n言论内容：“煽动群众聚集滋事的言论”\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:22.40975+12
2475	2498	【中国文字狱事件记录】\n日期：2022年10月12日\n地点：新疆乌鲁木齐\n当事人：杨某毕\n平台：微信群\n言论内容：“煽动群众聚集滋事的言论”\n背景事件：武汉新型冠状病毒肺炎\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:22.465924+12
2476	2499	【中国文字狱事件记录】\n日期：2022年10月12日\n地点：新疆乌鲁木齐\n当事人：吴某轩\n平台：微信群\n言论内容：“煽动群众违反管控措施的言论”\n背景事件：武汉新型冠状病毒肺炎\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:22.523135+12
2477	2500	【中国文字狱事件记录】\n日期：2022年10月15日\n地点：江西南昌\n当事人：萧亮\n平台：推特\n言论内容：其自己创作的彭立发肖像图片\n背景事件：北京市海淀区四通桥抗议\n处罚：逮捕	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:22.586679+12
2478	2501	【中国文字狱事件记录】\n日期：2022年10月22日\n地点：广东普宁市\n当事人：卢某秀\n平台：网络\n言论内容：其18岁那年被人贩子以“招工”为由骗到潮汕，嫁给今天的老公\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:22.644355+12
2479	2502	【中国文字狱事件记录】\n日期：2022年10月31日\n地点：青海西宁\n当事人：倪某\n平台：社交平台\n言论内容：“涉疫不实信息”\n背景事件：武汉新型冠状病毒肺炎\n处罚：“依法处置”	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:22.702118+12
2480	2503	【中国文字狱事件记录】\n日期：2022年10月31日\n地点：青海西宁\n当事人：郭某\n平台：社交平台\n言论内容：“涉疫不实信息”\n背景事件：武汉新型冠状病毒肺炎\n处罚：“依法处置”	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:22.757732+12
2481	2504	【中国文字狱事件记录】\n日期：2022年10月31日\n地点：青海西宁\n当事人：李某\n平台：网络\n言论内容：核酸之都、方舱故里、菜包之乡、静默之城\n背景事件：武汉新型冠状病毒肺炎\n处罚：“依法处置”	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:22.816439+12
2482	2505	【中国文字狱事件记录】\n日期：2022年10月31日\n地点：青海西宁\n当事人：谢某\n平台：网络\n言论内容：核酸之都、方舱故里、菜包之乡、静默之城\n背景事件：武汉新型冠状病毒肺炎\n处罚：“依法处置”	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:22.874383+12
2483	2506	【中国文字狱事件记录】\n日期：2022年11月01日\n地点：新疆乌鲁木齐\n当事人：王某\n平台：即时通讯工具\n言论内容：“不当言论，煽动多人外出聚集”\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:22.933907+12
2484	2507	【中国文字狱事件记录】\n日期：2022年11月02日\n地点：新疆乌鲁木齐\n当事人：明某\n平台：即时通讯工具\n言论内容：“不当言论，煽动多人外出聚集”\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:22.990738+12
2485	2508	【中国文字狱事件记录】\n日期：2022年11月05日\n地点：新疆乌鲁木齐\n当事人：刘某\n平台：即时通讯工具\n言论内容：冲出去，和他们干\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留15日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:23.047037+12
2486	2509	【中国文字狱事件记录】\n日期：2022年11月07日\n地点：云南楚雄\n当事人：王藏（王玉文）\n平台：境外媒体\n言论内容：“攻击中国政治制度的言论、污蔑党和国家的言论”\n处罚：有期徒刑4年\n法律文书：（2020）云23刑初48号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:23.097777+12
2487	2510	【中国文字狱事件记录】\n日期：2022年11月07日\n地点：云南楚雄\n当事人：王利芹（王藏之妻）\n平台：境外媒体\n言论内容：协助其夫王藏整理拍摄其“煽动颠覆国家政权言论”的素材\n处罚：有期徒刑2年6个月\n法律文书：（2020）云23刑初48号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:23.15388+12
2488	2511	【中国文字狱事件记录】\n日期：2022年11月12日\n地点：新疆喀什\n当事人：李某\n平台：短视频平台\n言论内容：抖音官媒统计，我们知道该怎么做了吧\n背景事件：武汉新型冠状病毒肺炎\n处罚：立案侦查	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:23.209484+12
2489	2512	【中国文字狱事件记录】\n日期：2022年11月12日\n地点：新疆乌鲁木齐\n当事人：黄某\n平台：短视频平台\n言论内容：乌鲁木齐（刷屏）\n背景事件：武汉新型冠状病毒肺炎\n处罚：立案侦查	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:23.263259+12
2490	2513	【中国文字狱事件记录】\n日期：2022年11月12日\n地点：新疆乌鲁木齐\n当事人：李某\n平台：短视频平台\n言论内容：“其他用户在官方新闻评论区刷屏评论的内容录屏”\n背景事件：武汉新型冠状病毒肺炎\n处罚：立案侦查	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:23.318734+12
2491	2514	【中国文字狱事件记录】\n日期：2022年11月18日\n地点：泰国曼谷\n当事人：李南飞\n身份：境外人士\n平台：现实/举牌\n言论内容：习近平陛下，你爹喊你滚下来，结束中国专制，还人民自由\n处罚：逮捕	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:23.374551+12
2492	2515	【中国文字狱事件记录】\n日期：2022年11月21日\n地点：陕西靖边县\n当事人：闫某欣\n平台：微信群\n言论内容：（视频）中心城区进行封控演练\n背景事件：武汉新型冠状病毒肺炎\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:23.433722+12
2493	2516	【中国文字狱事件记录】\n日期：2022年11月25日\n地点：新疆乌鲁木齐\n当事人：苏某\n平台：微信群\n言论内容：当地11月24日火灾的“不实死亡人数”\n背景事件：乌鲁木齐1125火灾\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:23.491642+12
2494	2517	【中国文字狱事件记录】\n日期：2022年11月30日\n地点：甘肃宕昌县\n当事人：杜某\n平台：微信群\n言论内容：“辱骂村干部的言论”\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:23.547474+12
2495	2518	【中国文字狱事件记录】\n日期：2023年01月06日\n地点：山西太原\n当事人：杨某\n平台：推特\n言论内容：“112篇反动文章”；“中华民国山西自治同盟会“徽旗、徽章和纲领\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:23.605189+12
2496	2519	【中国文字狱事件记录】\n日期：2023年01月12日\n地点：山东莘县\n当事人：段某\n平台：抖音\n言论内容：“辱骂交警的视频”\n处罚：拘留7日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:23.660462+12
2497	2520	【中国文字狱事件记录】\n日期：2023年01月12日\n地点：陕西澄城县\n当事人：李某\n平台：网络\n言论内容：“虚假信息，肆意抹黑、攻击国家机关及其工作人员形象”\n处罚：起诉（寻衅滋事）	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:23.714329+12
2498	2521	【中国文字狱事件记录】\n日期：2023年01月13日\n地点：云南通海县\n当事人：窦某\n平台：抖音\n言论内容：“辱骂交警的视频”\n处罚：拘留6日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:23.770016+12
2499	2522	【中国文字狱事件记录】\n日期：2023年01月20日\n地点：山东沂南县\n当事人：庞某\n平台：微信公众平台\n言论内容：《山东临沂市沂南县交通执法太厉害，上路追车还打人》\n处罚：刑事拘留\n法律文书：沂南公（刑）拘通字［2023］70号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:23.825265+12
2500	2523	【中国文字狱事件记录】\n日期：2023年02月10日\n地点：上海\n当事人：阮晓寰（编程随想）\n平台：blogger\n言论内容：大量批评中共政权的文章，较知名的有《太子党关系网络》等\n处罚：有期徒刑7年、罚款20000元\n法律文书：（2021）沪02刑初67号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:23.881543+12
2501	2524	【中国文字狱事件记录】\n日期：2023年03月08日\n地点：南京航空航天大学\n当事人：陈赛彬\n身份：学者/教师\n平台：现实/课堂\n言论内容：美国持枪是好事，美国比中国发达和安全，西方在学术方面比中国发达，多数科技产品都是欧美的……\n处罚：停职	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:23.938156+12
2502	2525	【中国文字狱事件记录】\n日期：2023年03月23日\n地点：湖北黄梅县\n当事人：商某\n平台：抖音\n言论内容：9条短视频，指控城管打人\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:23.992429+12
2503	2526	【中国文字狱事件记录】\n日期：2023年03月29日\n地点：山东济南\n当事人：张桂祺（鲁扬）\n平台：不详\n言论内容：（视频）习近平下台，中共独裁政权必须结束\n处罚：有期徒刑6年\n法律文书：鲁省狱入通字［2023］0244号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:24.049293+12
2504	2527	【中国文字狱事件记录】\n日期：2023年04月06日\n地点：广东陆河县\n当事人：朱某寿\n平台：微信群\n言论内容：（输变电工程）对xx祠堂的风水破坏，对村民居家生活安全存在严重安全隐患\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:24.106372+12
2505	2528	【中国文字狱事件记录】\n日期：2023年04月07日\n地点：四川德阳\n当事人：陈某龙\n平台：网络\n言论内容：一段微信群聊截图，内容为其拒绝加班，怒怼领导并带领其他员工集体辞职\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:24.165092+12
2506	2529	【中国文字狱事件记录】\n日期：2023年04月08日\n地点：内蒙古达拉特旗\n当事人：冯某\n平台：网络\n言论内容：其单位存在非法排污、官商勾结和拖欠工资的情况\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:24.226311+12
2507	2530	【中国文字狱事件记录】\n日期：2023年05月06日\n地点：河北沙河市\n当事人：牛某\n平台：抖音\n言论内容：（视频）你们那下雪了吗？（定位显示是河北省沙河市）\n处罚：教育训诫	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:24.290279+12
2508	2531	【中国文字狱事件记录】\n日期：2023年05月06日\n地点：广西融安县\n当事人：罗某\n平台：网络\n言论内容：（交警执法视频）融安出强盗了，土匪啊，抢钱啊，抢电车啊。\n处罚：拘留4日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:24.34917+12
2509	2532	【中国文字狱事件记录】\n日期：2023年05月17日\n地点：北京\n当事人：上海笑笙文化传媒有限公司\n平台：现实（脱口秀演出）\n言论内容：这两条野狗让我想起来八个字，‘作风优良，能打胜仗’\n处罚：警告、罚款1325万元、无限期停演	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:24.407079+12
2510	2533	【中国文字狱事件记录】\n日期：2023年05月17日\n地点：北京\n当事人：李昊石（艺名house）\n平台：现实（脱口秀演出）\n言论内容：这两条野狗让我想起来八个字，‘作风优良，能打胜仗’\n处罚：立案侦查	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:24.465597+12
2511	2534	【中国文字狱事件记录】\n日期：2023年05月17日\n地点：辽宁大连\n当事人：史某\n平台：微博\n言论内容：#是否应该永久封杀house#为啥要封杀啊！！兵哥哥难道不都是🐶哥哥么\n背景事件：笑果巡演被处罚事件\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:24.523505+12
2512	2535	【中国文字狱事件记录】\n日期：2023年05月23日\n地点：云南大理\n当事人：张孟（化名）\n平台：多个场合\n言论内容：“反党反国家、污蔑中央领袖、抨击防疫政策、妄谈台湾问题和新疆问题等言论”\n处罚：拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:24.580881+12
2513	2536	【中国文字狱事件记录】\n日期：2023年05月26日\n地点：广西西林县\n当事人：黄某\n平台：朋友圈\n言论内容：还是老老实实回家呆着吧！土匪太多了\n处罚：“依法查处”	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:24.635997+12
2514	2537	【中国文字狱事件记录】\n日期：2023年06月02日\n地点：陕西蒲城县\n当事人：王某\n平台：抖音\n言论内容：（视频）“兴镇执法队胡弄”\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:24.691613+12
2515	2538	【中国文字狱事件记录】\n日期：2023年06月13日\n地点：江西上犹县\n当事人：谢某\n平台：某短视频平台\n言论内容：交集乱罚款；大家注意，交集见车就拦在抢钱；交集是土匪\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:24.747732+12
2516	2539	【中国文字狱事件记录】\n日期：2023年06月25日\n地点：湖南岳阳县\n当事人：唐某\n平台：网络\n言论内容：“编造虚假信息侮辱、诽谤公安机关”\n处罚：拘留15日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:24.803512+12
2517	2540	【中国文字狱事件记录】\n日期：2023年06月29日\n地点：上海\n当事人：贺某\n平台：小红书\n言论内容：上海二号线出事了！！人民广场站好多警察，知道的友友们快回复！\n处罚：行政拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:24.863304+12
2518	2541	【中国文字狱事件记录】\n日期：2023年07月06日\n地点：黑龙江五常市\n当事人：王某玲\n平台：网络\n言论内容：（转发）“太解气了，警察在幼儿园暴打幼师”\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:24.921357+12
2519	2542	【中国文字狱事件记录】\n日期：2023年07月06日\n地点：黑龙江五常市\n当事人：张某凤\n平台：网络\n言论内容：（转发）“太解气了，警察在幼儿园暴打幼师”\n处罚：拘留10日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:24.97695+12
2520	2543	【中国文字狱事件记录】\n日期：2023年07月13日\n地点：甘肃陇西县\n当事人：“外向蛋糕6X3”\n平台：今日头条\n言论内容：陇西县信访局局长何世雄冒名顶替他人上大学\n处罚：行政处罚	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:25.032523+12
2521	2544	【中国文字狱事件记录】\n日期：2023年07月20日\n地点：山西定襄县\n当事人：郝劲松\n平台：多个平台\n言论内容：“虚假信息”实为控诉地方政府，为访民发声\n处罚：有期徒刑9年	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:25.086403+12
2522	2545	【中国文字狱事件记录】\n日期：2023年07月23日\n地点：陕西西安\n当事人：施某\n平台：网络\n言论内容：《告同胞书》（在西安回流生事件里呼吁河南家长打赢舆论战）\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:25.148079+12
2523	2546	【中国文字狱事件记录】\n日期：2023年07月27日\n地点：四川古蔺县\n当事人：嬴某\n平台：抖音\n言论内容：龟儿子些有钱往城里头跑嘛，说我们是农村人，乡巴佬进城，安死你狗日了些。\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:25.208458+12
2524	2547	【中国文字狱事件记录】\n日期：2023年07月04日\n地点：湖北安陆市\n当事人：郑某\n平台：抖音\n言论内容：“恶意诋毁安陆市自媒体协会制度、辱骂他人”\n处罚：拘留5日	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:25.26574+12
2525	2548	【中国文字狱事件记录】\n日期：2023年07月21日\n地点：山东青岛\n当事人：宁斌\n平台：推特、品葱\n言论内容：涉政“不实言论、不当言论、谣言”\n处罚：有期徒刑2年8个月\n法律文书：（2021）鲁0215刑初689号	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:25.323761+12
2526	2549	【中国文字狱事件记录】\n日期：2024年05月07日\n地点：山西太原\n当事人：史某\n平台：推特\n言论内容：“辱华和仇华言论“以及”谎称“自己是当地税务局公务员的言论\n处罚：刑事拘留	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2026-05-22 18:06:25.383048+12
\.


--
-- Name: behavioral_models_id_seq; Type: SEQUENCE SET; Schema: ccc; Owner: postgres
--

SELECT pg_catalog.setval('ccc.behavioral_models_id_seq', 17, true);


--
-- Name: causal_edges_id_seq; Type: SEQUENCE SET; Schema: ccc; Owner: postgres
--

SELECT pg_catalog.setval('ccc.causal_edges_id_seq', 71, true);


--
-- Name: claims_id_seq; Type: SEQUENCE SET; Schema: ccc; Owner: postgres
--

SELECT pg_catalog.setval('ccc.claims_id_seq', 5085, true);


--
-- Name: clean_document_entities_id_seq; Type: SEQUENCE SET; Schema: ccc; Owner: postgres
--

SELECT pg_catalog.setval('ccc.clean_document_entities_id_seq', 160, true);


--
-- Name: clean_entities_id_seq; Type: SEQUENCE SET; Schema: ccc; Owner: postgres
--

SELECT pg_catalog.setval('ccc.clean_entities_id_seq', 103, true);


--
-- Name: clean_graph_edges_id_seq; Type: SEQUENCE SET; Schema: ccc; Owner: postgres
--

SELECT pg_catalog.setval('ccc.clean_graph_edges_id_seq', 527, true);


--
-- Name: cognitive_edges_id_seq; Type: SEQUENCE SET; Schema: ccc; Owner: postgres
--

SELECT pg_catalog.setval('ccc.cognitive_edges_id_seq', 1, false);


--
-- Name: cognitive_nodes_id_seq; Type: SEQUENCE SET; Schema: ccc; Owner: postgres
--

SELECT pg_catalog.setval('ccc.cognitive_nodes_id_seq', 1, false);


--
-- Name: contradiction_engine_id_seq; Type: SEQUENCE SET; Schema: ccc; Owner: postgres
--

SELECT pg_catalog.setval('ccc.contradiction_engine_id_seq', 8, true);


--
-- Name: contradictions_id_seq; Type: SEQUENCE SET; Schema: ccc; Owner: postgres
--

SELECT pg_catalog.setval('ccc.contradictions_id_seq', 1, false);


--
-- Name: documents_id_seq; Type: SEQUENCE SET; Schema: ccc; Owner: postgres
--

SELECT pg_catalog.setval('ccc.documents_id_seq', 14, true);


--
-- Name: entity_profiles_id_seq; Type: SEQUENCE SET; Schema: ccc; Owner: postgres
--

SELECT pg_catalog.setval('ccc.entity_profiles_id_seq', 6, true);


--
-- Name: entity_trajectories_id_seq; Type: SEQUENCE SET; Schema: ccc; Owner: postgres
--

SELECT pg_catalog.setval('ccc.entity_trajectories_id_seq', 6, true);


--
-- Name: event_chains_id_seq; Type: SEQUENCE SET; Schema: ccc; Owner: postgres
--

SELECT pg_catalog.setval('ccc.event_chains_id_seq', 50, true);


--
-- Name: event_dashboard_id_seq; Type: SEQUENCE SET; Schema: ccc; Owner: postgres
--

SELECT pg_catalog.setval('ccc.event_dashboard_id_seq', 66224, true);


--
-- Name: event_nodes_id_seq; Type: SEQUENCE SET; Schema: ccc; Owner: postgres
--

SELECT pg_catalog.setval('ccc.event_nodes_id_seq', 121, true);


--
-- Name: events_id_seq; Type: SEQUENCE SET; Schema: ccc; Owner: postgres
--

SELECT pg_catalog.setval('ccc.events_id_seq', 5189, true);


--
-- Name: function_snapshots_id_seq; Type: SEQUENCE SET; Schema: ccc; Owner: postgres
--

SELECT pg_catalog.setval('ccc.function_snapshots_id_seq', 10, true);


--
-- Name: person_aliases_id_seq; Type: SEQUENCE SET; Schema: ccc; Owner: postgres
--

SELECT pg_catalog.setval('ccc.person_aliases_id_seq', 513, true);


--
-- Name: raw_documents_id_seq; Type: SEQUENCE SET; Schema: ccc; Owner: postgres
--

SELECT pg_catalog.setval('ccc.raw_documents_id_seq', 9, true);


--
-- Name: revision_log_id_seq; Type: SEQUENCE SET; Schema: ccc; Owner: postgres
--

SELECT pg_catalog.setval('ccc.revision_log_id_seq', 1, false);


--
-- Name: rsal_checkpoints_id_seq; Type: SEQUENCE SET; Schema: ccc; Owner: postgres
--

SELECT pg_catalog.setval('ccc.rsal_checkpoints_id_seq', 15, true);


--
-- Name: signals_id_seq; Type: SEQUENCE SET; Schema: ccc; Owner: postgres
--

SELECT pg_catalog.setval('ccc.signals_id_seq', 14, true);


--
-- Name: source_accuracy_history_id_seq; Type: SEQUENCE SET; Schema: ccc; Owner: postgres
--

SELECT pg_catalog.setval('ccc.source_accuracy_history_id_seq', 1, false);


--
-- Name: source_bias_vectors_id_seq; Type: SEQUENCE SET; Schema: ccc; Owner: postgres
--

SELECT pg_catalog.setval('ccc.source_bias_vectors_id_seq', 15, true);


--
-- Name: source_conflict_matrix_id_seq; Type: SEQUENCE SET; Schema: ccc; Owner: postgres
--

SELECT pg_catalog.setval('ccc.source_conflict_matrix_id_seq', 1, false);


--
-- Name: source_domain_authority_id_seq; Type: SEQUENCE SET; Schema: ccc; Owner: postgres
--

SELECT pg_catalog.setval('ccc.source_domain_authority_id_seq', 32, true);


--
-- Name: source_profiles_id_seq; Type: SEQUENCE SET; Schema: ccc; Owner: postgres
--

SELECT pg_catalog.setval('ccc.source_profiles_id_seq', 35, true);


--
-- Name: source_weight_evaluations_id_seq; Type: SEQUENCE SET; Schema: ccc; Owner: postgres
--

SELECT pg_catalog.setval('ccc.source_weight_evaluations_id_seq', 1, false);


--
-- Name: timeline_proxy_map_id_seq; Type: SEQUENCE SET; Schema: ccc; Owner: postgres
--

SELECT pg_catalog.setval('ccc.timeline_proxy_map_id_seq', 2, true);


--
-- Name: trust_fusion_v3_regression_expectations_id_seq; Type: SEQUENCE SET; Schema: ccc; Owner: postgres
--

SELECT pg_catalog.setval('ccc.trust_fusion_v3_regression_expectations_id_seq', 16, true);


--
-- Name: wenziyu_cases_id_seq; Type: SEQUENCE SET; Schema: ccc; Owner: postgres
--

SELECT pg_catalog.setval('ccc.wenziyu_cases_id_seq', 2526, true);


--
-- Name: behavioral_models behavioral_models_pkey; Type: CONSTRAINT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.behavioral_models
    ADD CONSTRAINT behavioral_models_pkey PRIMARY KEY (id);


--
-- Name: causal_edges causal_edges_pkey; Type: CONSTRAINT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.causal_edges
    ADD CONSTRAINT causal_edges_pkey PRIMARY KEY (id);


--
-- Name: claims claims_pkey; Type: CONSTRAINT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.claims
    ADD CONSTRAINT claims_pkey PRIMARY KEY (id);


--
-- Name: clean_document_entities clean_document_entities_pkey; Type: CONSTRAINT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.clean_document_entities
    ADD CONSTRAINT clean_document_entities_pkey PRIMARY KEY (id);


--
-- Name: clean_entities clean_entities_pkey; Type: CONSTRAINT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.clean_entities
    ADD CONSTRAINT clean_entities_pkey PRIMARY KEY (id);


--
-- Name: clean_graph_edges clean_graph_edges_pkey; Type: CONSTRAINT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.clean_graph_edges
    ADD CONSTRAINT clean_graph_edges_pkey PRIMARY KEY (id);


--
-- Name: cognitive_edges cognitive_edges_pkey; Type: CONSTRAINT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.cognitive_edges
    ADD CONSTRAINT cognitive_edges_pkey PRIMARY KEY (id);


--
-- Name: cognitive_nodes cognitive_nodes_pkey; Type: CONSTRAINT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.cognitive_nodes
    ADD CONSTRAINT cognitive_nodes_pkey PRIMARY KEY (id);


--
-- Name: contradiction_engine contradiction_engine_pkey; Type: CONSTRAINT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.contradiction_engine
    ADD CONSTRAINT contradiction_engine_pkey PRIMARY KEY (id);


--
-- Name: contradictions contradictions_pkey; Type: CONSTRAINT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.contradictions
    ADD CONSTRAINT contradictions_pkey PRIMARY KEY (id);


--
-- Name: documents documents_content_hash_key; Type: CONSTRAINT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.documents
    ADD CONSTRAINT documents_content_hash_key UNIQUE (content_hash);


--
-- Name: documents documents_pkey; Type: CONSTRAINT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.documents
    ADD CONSTRAINT documents_pkey PRIMARY KEY (id);


--
-- Name: entity_profiles entity_profiles_pkey; Type: CONSTRAINT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.entity_profiles
    ADD CONSTRAINT entity_profiles_pkey PRIMARY KEY (id);


--
-- Name: entity_resolve_v3_local_expectations entity_resolve_v3_local_expectations_pkey; Type: CONSTRAINT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.entity_resolve_v3_local_expectations
    ADD CONSTRAINT entity_resolve_v3_local_expectations_pkey PRIMARY KEY (q);


--
-- Name: entity_trajectories entity_trajectories_pkey; Type: CONSTRAINT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.entity_trajectories
    ADD CONSTRAINT entity_trajectories_pkey PRIMARY KEY (id);


--
-- Name: event_chains event_chains_pkey; Type: CONSTRAINT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.event_chains
    ADD CONSTRAINT event_chains_pkey PRIMARY KEY (id);


--
-- Name: event_dashboard event_dashboard_document_id_person_name_event_summary_key; Type: CONSTRAINT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.event_dashboard
    ADD CONSTRAINT event_dashboard_document_id_person_name_event_summary_key UNIQUE (document_id, person_name, event_summary);


--
-- Name: event_dashboard event_dashboard_pkey; Type: CONSTRAINT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.event_dashboard
    ADD CONSTRAINT event_dashboard_pkey PRIMARY KEY (id);


--
-- Name: event_nodes event_nodes_pkey; Type: CONSTRAINT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.event_nodes
    ADD CONSTRAINT event_nodes_pkey PRIMARY KEY (id);


--
-- Name: events events_pkey; Type: CONSTRAINT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.events
    ADD CONSTRAINT events_pkey PRIMARY KEY (id);


--
-- Name: forecast_regression_expectations forecast_regression_expectations_pkey; Type: CONSTRAINT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.forecast_regression_expectations
    ADD CONSTRAINT forecast_regression_expectations_pkey PRIMARY KEY (entity_name);


--
-- Name: function_snapshots function_snapshots_checkpoint_label_function_signature_key; Type: CONSTRAINT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.function_snapshots
    ADD CONSTRAINT function_snapshots_checkpoint_label_function_signature_key UNIQUE (checkpoint_label, function_signature);


--
-- Name: function_snapshots function_snapshots_pkey; Type: CONSTRAINT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.function_snapshots
    ADD CONSTRAINT function_snapshots_pkey PRIMARY KEY (id);


--
-- Name: person_aliases person_aliases_canonical_alias_key; Type: CONSTRAINT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.person_aliases
    ADD CONSTRAINT person_aliases_canonical_alias_key UNIQUE (canonical, alias);


--
-- Name: person_aliases person_aliases_pkey; Type: CONSTRAINT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.person_aliases
    ADD CONSTRAINT person_aliases_pkey PRIMARY KEY (id);


--
-- Name: person_noise_library person_noise_library_pkey; Type: CONSTRAINT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.person_noise_library
    ADD CONSTRAINT person_noise_library_pkey PRIMARY KEY (word);


--
-- Name: raw_documents raw_documents_pkey; Type: CONSTRAINT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.raw_documents
    ADD CONSTRAINT raw_documents_pkey PRIMARY KEY (id);


--
-- Name: revision_log revision_log_pkey; Type: CONSTRAINT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.revision_log
    ADD CONSTRAINT revision_log_pkey PRIMARY KEY (id);


--
-- Name: rsal_checkpoints rsal_checkpoints_checkpoint_label_key; Type: CONSTRAINT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.rsal_checkpoints
    ADD CONSTRAINT rsal_checkpoints_checkpoint_label_key UNIQUE (checkpoint_label);


--
-- Name: rsal_checkpoints rsal_checkpoints_pkey; Type: CONSTRAINT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.rsal_checkpoints
    ADD CONSTRAINT rsal_checkpoints_pkey PRIMARY KEY (id);


--
-- Name: signals signals_pkey; Type: CONSTRAINT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.signals
    ADD CONSTRAINT signals_pkey PRIMARY KEY (id);


--
-- Name: source_accuracy_history source_accuracy_history_pkey; Type: CONSTRAINT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.source_accuracy_history
    ADD CONSTRAINT source_accuracy_history_pkey PRIMARY KEY (id);


--
-- Name: source_bias_vectors source_bias_vectors_pkey; Type: CONSTRAINT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.source_bias_vectors
    ADD CONSTRAINT source_bias_vectors_pkey PRIMARY KEY (id);


--
-- Name: source_conflict_matrix source_conflict_matrix_pkey; Type: CONSTRAINT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.source_conflict_matrix
    ADD CONSTRAINT source_conflict_matrix_pkey PRIMARY KEY (id);


--
-- Name: source_domain_authority source_domain_authority_pkey; Type: CONSTRAINT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.source_domain_authority
    ADD CONSTRAINT source_domain_authority_pkey PRIMARY KEY (id);


--
-- Name: source_profiles source_profiles_pkey; Type: CONSTRAINT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.source_profiles
    ADD CONSTRAINT source_profiles_pkey PRIMARY KEY (id);


--
-- Name: source_profiles source_profiles_source_name_key; Type: CONSTRAINT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.source_profiles
    ADD CONSTRAINT source_profiles_source_name_key UNIQUE (source_name);


--
-- Name: source_weight_evaluations source_weight_evaluations_pkey; Type: CONSTRAINT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.source_weight_evaluations
    ADD CONSTRAINT source_weight_evaluations_pkey PRIMARY KEY (id);


--
-- Name: timeline_proxy_map timeline_proxy_map_entity_id_proxy_entity_id_proxy_type_key; Type: CONSTRAINT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.timeline_proxy_map
    ADD CONSTRAINT timeline_proxy_map_entity_id_proxy_entity_id_proxy_type_key UNIQUE (entity_id, proxy_entity_id, proxy_type);


--
-- Name: timeline_proxy_map timeline_proxy_map_pkey; Type: CONSTRAINT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.timeline_proxy_map
    ADD CONSTRAINT timeline_proxy_map_pkey PRIMARY KEY (id);


--
-- Name: trust_fusion_v3_regression_expectations trust_fusion_v3_regression_expectations_pkey; Type: CONSTRAINT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.trust_fusion_v3_regression_expectations
    ADD CONSTRAINT trust_fusion_v3_regression_expectations_pkey PRIMARY KEY (id);


--
-- Name: trust_fusion_v3_regression_expectations trust_fusion_v3_regression_expectations_source_name_key; Type: CONSTRAINT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.trust_fusion_v3_regression_expectations
    ADD CONSTRAINT trust_fusion_v3_regression_expectations_source_name_key UNIQUE (source_name);


--
-- Name: wenziyu_cases wenziyu_cases_pkey; Type: CONSTRAINT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.wenziyu_cases
    ADD CONSTRAINT wenziyu_cases_pkey PRIMARY KEY (id);


--
-- Name: idx_behavioral_models_confidence; Type: INDEX; Schema: ccc; Owner: postgres
--

CREATE INDEX idx_behavioral_models_confidence ON ccc.behavioral_models USING btree (confidence DESC);


--
-- Name: idx_behavioral_models_entity; Type: INDEX; Schema: ccc; Owner: postgres
--

CREATE INDEX idx_behavioral_models_entity ON ccc.behavioral_models USING btree (entity_profile_id);


--
-- Name: idx_causal_edges_source; Type: INDEX; Schema: ccc; Owner: postgres
--

CREATE INDEX idx_causal_edges_source ON ccc.causal_edges USING btree (source_event_id);


--
-- Name: idx_clean_doc_ent_uniq; Type: INDEX; Schema: ccc; Owner: postgres
--

CREATE UNIQUE INDEX idx_clean_doc_ent_uniq ON ccc.clean_document_entities USING btree (document_id, entity_id);


--
-- Name: idx_clean_entities_name_type; Type: INDEX; Schema: ccc; Owner: postgres
--

CREATE UNIQUE INDEX idx_clean_entities_name_type ON ccc.clean_entities USING btree (lower(canonical_name), entity_type);


--
-- Name: idx_clean_graph_edge_uniq; Type: INDEX; Schema: ccc; Owner: postgres
--

CREATE UNIQUE INDEX idx_clean_graph_edge_uniq ON ccc.clean_graph_edges USING btree (source_entity_id, target_entity_id, relation_type, COALESCE(relation_label, ''::text));


--
-- Name: idx_conflict_source_a; Type: INDEX; Schema: ccc; Owner: postgres
--

CREATE INDEX idx_conflict_source_a ON ccc.source_conflict_matrix USING btree (source_a_id);


--
-- Name: idx_contradiction_engine_entity; Type: INDEX; Schema: ccc; Owner: postgres
--

CREATE INDEX idx_contradiction_engine_entity ON ccc.contradiction_engine USING btree (entity_id);


--
-- Name: idx_contradiction_engine_severity; Type: INDEX; Schema: ccc; Owner: postgres
--

CREATE INDEX idx_contradiction_engine_severity ON ccc.contradiction_engine USING btree (severity, narrative_gap DESC);


--
-- Name: idx_documents_hash; Type: INDEX; Schema: ccc; Owner: postgres
--

CREATE INDEX idx_documents_hash ON ccc.documents USING btree (content_hash);


--
-- Name: idx_documents_raw_id; Type: INDEX; Schema: ccc; Owner: postgres
--

CREATE INDEX idx_documents_raw_id ON ccc.documents USING btree (raw_document_id);


--
-- Name: idx_entity_profiles_confidence; Type: INDEX; Schema: ccc; Owner: postgres
--

CREATE INDEX idx_entity_profiles_confidence ON ccc.entity_profiles USING btree (confidence DESC);


--
-- Name: idx_entity_profiles_entity; Type: INDEX; Schema: ccc; Owner: postgres
--

CREATE UNIQUE INDEX idx_entity_profiles_entity ON ccc.entity_profiles USING btree (entity_id);


--
-- Name: idx_event_nodes_chain; Type: INDEX; Schema: ccc; Owner: postgres
--

CREATE INDEX idx_event_nodes_chain ON ccc.event_nodes USING btree (chain_id);


--
-- Name: idx_event_nodes_entity; Type: INDEX; Schema: ccc; Owner: postgres
--

CREATE INDEX idx_event_nodes_entity ON ccc.event_nodes USING btree (entity_id);


--
-- Name: idx_event_nodes_time; Type: INDEX; Schema: ccc; Owner: postgres
--

CREATE INDEX idx_event_nodes_time ON ccc.event_nodes USING btree (event_time);


--
-- Name: idx_person_aliases_alias; Type: INDEX; Schema: ccc; Owner: postgres
--

CREATE INDEX idx_person_aliases_alias ON ccc.person_aliases USING btree (lower(alias));


--
-- Name: idx_person_aliases_canonical; Type: INDEX; Schema: ccc; Owner: postgres
--

CREATE INDEX idx_person_aliases_canonical ON ccc.person_aliases USING btree (canonical);


--
-- Name: idx_source_accuracy_source; Type: INDEX; Schema: ccc; Owner: postgres
--

CREATE INDEX idx_source_accuracy_source ON ccc.source_accuracy_history USING btree (source_id);


--
-- Name: idx_source_bias_source; Type: INDEX; Schema: ccc; Owner: postgres
--

CREATE INDEX idx_source_bias_source ON ccc.source_bias_vectors USING btree (source_id);


--
-- Name: idx_source_domain_source; Type: INDEX; Schema: ccc; Owner: postgres
--

CREATE INDEX idx_source_domain_source ON ccc.source_domain_authority USING btree (source_id);


--
-- Name: idx_source_profiles_tier; Type: INDEX; Schema: ccc; Owner: postgres
--

CREATE INDEX idx_source_profiles_tier ON ccc.source_profiles USING btree (trust_tier);


--
-- Name: idx_source_profiles_use; Type: INDEX; Schema: ccc; Owner: postgres
--

CREATE INDEX idx_source_profiles_use ON ccc.source_profiles USING btree (use_as);


--
-- Name: idx_source_weight_eval_domain; Type: INDEX; Schema: ccc; Owner: postgres
--

CREATE INDEX idx_source_weight_eval_domain ON ccc.source_weight_evaluations USING btree (domain);


--
-- Name: idx_source_weight_eval_source; Type: INDEX; Schema: ccc; Owner: postgres
--

CREATE INDEX idx_source_weight_eval_source ON ccc.source_weight_evaluations USING btree (source_id);


--
-- Name: idx_trajectories_entity_date; Type: INDEX; Schema: ccc; Owner: postgres
--

CREATE INDEX idx_trajectories_entity_date ON ccc.entity_trajectories USING btree (entity_name, snapshot_date DESC);


--
-- Name: idx_trajectories_pressure; Type: INDEX; Schema: ccc; Owner: postgres
--

CREATE INDEX idx_trajectories_pressure ON ccc.entity_trajectories USING btree (pressure DESC);


--
-- Name: behavioral_models behavioral_models_entity_profile_id_fkey; Type: FK CONSTRAINT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.behavioral_models
    ADD CONSTRAINT behavioral_models_entity_profile_id_fkey FOREIGN KEY (entity_profile_id) REFERENCES ccc.entity_profiles(id) ON DELETE CASCADE;


--
-- Name: causal_edges causal_edges_source_event_id_fkey; Type: FK CONSTRAINT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.causal_edges
    ADD CONSTRAINT causal_edges_source_event_id_fkey FOREIGN KEY (source_event_id) REFERENCES ccc.event_nodes(id);


--
-- Name: causal_edges causal_edges_target_event_id_fkey; Type: FK CONSTRAINT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.causal_edges
    ADD CONSTRAINT causal_edges_target_event_id_fkey FOREIGN KEY (target_event_id) REFERENCES ccc.event_nodes(id);


--
-- Name: cognitive_edges cognitive_edges_source_node_id_fkey; Type: FK CONSTRAINT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.cognitive_edges
    ADD CONSTRAINT cognitive_edges_source_node_id_fkey FOREIGN KEY (source_node_id) REFERENCES ccc.cognitive_nodes(id);


--
-- Name: cognitive_edges cognitive_edges_target_node_id_fkey; Type: FK CONSTRAINT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.cognitive_edges
    ADD CONSTRAINT cognitive_edges_target_node_id_fkey FOREIGN KEY (target_node_id) REFERENCES ccc.cognitive_nodes(id);


--
-- Name: contradiction_engine contradiction_engine_entity_id_fkey; Type: FK CONSTRAINT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.contradiction_engine
    ADD CONSTRAINT contradiction_engine_entity_id_fkey FOREIGN KEY (entity_id) REFERENCES ccc.clean_entities(id);


--
-- Name: contradictions contradictions_entity_id_fkey; Type: FK CONSTRAINT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.contradictions
    ADD CONSTRAINT contradictions_entity_id_fkey FOREIGN KEY (entity_id) REFERENCES ccc.clean_entities(id);


--
-- Name: contradictions contradictions_node_id_fkey; Type: FK CONSTRAINT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.contradictions
    ADD CONSTRAINT contradictions_node_id_fkey FOREIGN KEY (node_id) REFERENCES ccc.cognitive_nodes(id);


--
-- Name: documents documents_raw_document_id_fkey; Type: FK CONSTRAINT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.documents
    ADD CONSTRAINT documents_raw_document_id_fkey FOREIGN KEY (raw_document_id) REFERENCES ccc.raw_documents(id);


--
-- Name: entity_profiles entity_profiles_entity_id_fkey; Type: FK CONSTRAINT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.entity_profiles
    ADD CONSTRAINT entity_profiles_entity_id_fkey FOREIGN KEY (entity_id) REFERENCES ccc.clean_entities(id);


--
-- Name: entity_trajectories entity_trajectories_entity_profile_id_fkey; Type: FK CONSTRAINT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.entity_trajectories
    ADD CONSTRAINT entity_trajectories_entity_profile_id_fkey FOREIGN KEY (entity_profile_id) REFERENCES ccc.entity_profiles(id) ON DELETE CASCADE;


--
-- Name: event_chains event_chains_entity_id_fkey; Type: FK CONSTRAINT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.event_chains
    ADD CONSTRAINT event_chains_entity_id_fkey FOREIGN KEY (entity_id) REFERENCES ccc.clean_entities(id);


--
-- Name: event_nodes event_nodes_chain_id_fkey; Type: FK CONSTRAINT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.event_nodes
    ADD CONSTRAINT event_nodes_chain_id_fkey FOREIGN KEY (chain_id) REFERENCES ccc.event_chains(id);


--
-- Name: event_nodes event_nodes_entity_id_fkey; Type: FK CONSTRAINT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.event_nodes
    ADD CONSTRAINT event_nodes_entity_id_fkey FOREIGN KEY (entity_id) REFERENCES ccc.clean_entities(id);


--
-- Name: event_nodes event_nodes_event_id_fkey; Type: FK CONSTRAINT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.event_nodes
    ADD CONSTRAINT event_nodes_event_id_fkey FOREIGN KEY (event_id) REFERENCES ccc.events(id);


--
-- Name: revision_log revision_log_node_id_fkey; Type: FK CONSTRAINT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.revision_log
    ADD CONSTRAINT revision_log_node_id_fkey FOREIGN KEY (node_id) REFERENCES ccc.cognitive_nodes(id);


--
-- Name: signals signals_entity_profile_id_fkey; Type: FK CONSTRAINT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.signals
    ADD CONSTRAINT signals_entity_profile_id_fkey FOREIGN KEY (entity_profile_id) REFERENCES ccc.entity_profiles(id);


--
-- Name: signals signals_node_id_fkey; Type: FK CONSTRAINT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.signals
    ADD CONSTRAINT signals_node_id_fkey FOREIGN KEY (node_id) REFERENCES ccc.cognitive_nodes(id);


--
-- Name: source_accuracy_history source_accuracy_history_source_id_fkey; Type: FK CONSTRAINT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.source_accuracy_history
    ADD CONSTRAINT source_accuracy_history_source_id_fkey FOREIGN KEY (source_id) REFERENCES ccc.source_profiles(id);


--
-- Name: source_bias_vectors source_bias_vectors_source_id_fkey; Type: FK CONSTRAINT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.source_bias_vectors
    ADD CONSTRAINT source_bias_vectors_source_id_fkey FOREIGN KEY (source_id) REFERENCES ccc.source_profiles(id);


--
-- Name: source_conflict_matrix source_conflict_matrix_source_a_id_fkey; Type: FK CONSTRAINT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.source_conflict_matrix
    ADD CONSTRAINT source_conflict_matrix_source_a_id_fkey FOREIGN KEY (source_a_id) REFERENCES ccc.source_profiles(id);


--
-- Name: source_conflict_matrix source_conflict_matrix_source_b_id_fkey; Type: FK CONSTRAINT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.source_conflict_matrix
    ADD CONSTRAINT source_conflict_matrix_source_b_id_fkey FOREIGN KEY (source_b_id) REFERENCES ccc.source_profiles(id);


--
-- Name: source_domain_authority source_domain_authority_source_id_fkey; Type: FK CONSTRAINT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.source_domain_authority
    ADD CONSTRAINT source_domain_authority_source_id_fkey FOREIGN KEY (source_id) REFERENCES ccc.source_profiles(id);


--
-- Name: source_weight_evaluations source_weight_evaluations_source_id_fkey; Type: FK CONSTRAINT; Schema: ccc; Owner: postgres
--

ALTER TABLE ONLY ccc.source_weight_evaluations
    ADD CONSTRAINT source_weight_evaluations_source_id_fkey FOREIGN KEY (source_id) REFERENCES ccc.source_profiles(id);


--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: postgres
--

REVOKE USAGE ON SCHEMA public FROM PUBLIC;


--
-- PostgreSQL database dump complete
--

\unrestrict 684mgj3aCJHh8oJldlxultqPKz0he16KpogTfY79UFpkTXZnHz23tvoRwIa7OnS

