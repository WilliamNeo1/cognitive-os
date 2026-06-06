--
-- PostgreSQL database dump
--

\restrict e8MTP271EnF8ecac8oofGZIPaN5xG4aM993XHtzGyP9d1RucJhQRp9JXdLlHplo

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

\unrestrict e8MTP271EnF8ecac8oofGZIPaN5xG4aM993XHtzGyP9d1RucJhQRp9JXdLlHplo

