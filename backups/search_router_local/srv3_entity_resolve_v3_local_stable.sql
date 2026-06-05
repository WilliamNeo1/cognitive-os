-- SRV3 Entity Resolve v3 Local Stable Checkpoint
-- checkpoint: SRV3_entity_resolve_v3_local_stable
-- purpose: backup local multilingual entity resolver, aliases, regression, and WEF-Bill Gates graph edge

CREATE SCHEMA IF NOT EXISTS ccc;

-- ============================================================
-- Function: ccc.entity_resolve_v3_local(text)
-- ============================================================

CREATE OR REPLACE FUNCTION ccc.entity_resolve_v3_local(q text)
 RETURNS TABLE(canonical_name text, entity_id bigint, match_type text, confidence double precision, entity_type text)
 LANGUAGE sql
 STABLE
AS $function$
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
$function$


-- ============================================================
-- Regression view: ccc.entity_resolve_v3_local_regression
-- ============================================================

CREATE OR REPLACE VIEW ccc.entity_resolve_v3_local_regression AS
 WITH actual AS (
         SELECT e_1.q,
            r.canonical_name,
            r.entity_id,
            r.match_type,
            r.confidence,
            r.entity_type
           FROM ccc.entity_resolve_v3_local_expectations e_1
             CROSS JOIN LATERAL ( SELECT entity_resolve_v3_local.canonical_name,
                    entity_resolve_v3_local.entity_id,
                    entity_resolve_v3_local.match_type,
                    entity_resolve_v3_local.confidence,
                    entity_resolve_v3_local.entity_type
                   FROM ccc.entity_resolve_v3_local(e_1.q) entity_resolve_v3_local(canonical_name, entity_id, match_type, confidence, entity_type)
                  ORDER BY entity_resolve_v3_local.confidence DESC
                 LIMIT 1) r
        )
 SELECT a.q,
        CASE
            WHEN a.canonical_name = e.expected_canonical_name AND a.entity_id = e.expected_entity_id AND a.match_type = e.expected_match_type AND a.confidence >= e.min_confidence::double precision AND a.entity_type = e.expected_entity_type THEN 'PASS'::text
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
   FROM actual a
     JOIN ccc.entity_resolve_v3_local_expectations e ON e.q = a.q;;

-- ============================================================
-- Core clean_entities used by entity_resolve_v3_local
-- ============================================================

INSERT INTO ccc.clean_entities (id, canonical_name, entity_type, source, mention_count, confidence, created_at)
SELECT 59, 'WEF', 'ORG', 'manual', 0, 0.9, '2026-05-27T17:22:44.393002+12:00'::timestamptz::timestamptz
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.clean_entities
  WHERE canonical_name = 'WEF'
);

INSERT INTO ccc.clean_entities (id, canonical_name, entity_type, source, mention_count, confidence, created_at)
SELECT 34, '中共', 'ORG', 'ingest_v3', 2, 0.9, '2026-05-25T19:59:58.661492+12:00'::timestamptz::timestamptz
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.clean_entities
  WHERE canonical_name = '中共'
);

INSERT INTO ccc.clean_entities (id, canonical_name, entity_type, source, mention_count, confidence, created_at)
SELECT 16, '习近平', 'PERSON', 'ingest_v3', 7, 0.9, '2026-05-25T12:25:06.420091+12:00'::timestamptz::timestamptz
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.clean_entities
  WHERE canonical_name = '习近平'
);

INSERT INTO ccc.clean_entities (id, canonical_name, entity_type, source, mention_count, confidence, created_at)
SELECT 62, '比尔盖茨', 'PERSON', 'manual_graph_patch', 0, 0.9, '2026-06-05T22:25:34.807658+12:00'::timestamptz::timestamptz
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.clean_entities
  WHERE canonical_name = '比尔盖茨'
);

INSERT INTO ccc.clean_entities (id, canonical_name, entity_type, source, mention_count, confidence, created_at)
SELECT 17, '特朗普', 'PERSON', 'ingest_v3', 2, 0.9, '2026-05-25T19:59:58.661492+12:00'::timestamptz::timestamptz
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.clean_entities
  WHERE canonical_name = '特朗普'
);

INSERT INTO ccc.clean_entities (id, canonical_name, entity_type, source, mention_count, confidence, created_at)
SELECT 35, '美联储', 'ORG', 'ingest_v3', 2, 0.9, '2026-05-25T19:59:58.661492+12:00'::timestamptz::timestamptz
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.clean_entities
  WHERE canonical_name = '美联储'
);

-- ============================================================
-- Core person_aliases used by entity_resolve_v3_local
-- ============================================================

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT 'WEF', 'Davos', 'manual'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = 'WEF' AND alias = 'Davos'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT 'WEF', 'Davos Forum', 'english'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = 'WEF' AND alias = 'Davos Forum'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT 'WEF', 'WEF', 'canonical'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = 'WEF' AND alias = 'WEF'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT 'WEF', 'World Economic Forum', 'manual'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = 'WEF' AND alias = 'World Economic Forum'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT 'WEF', 'World Economic Forum Annual Meeting', 'english'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = 'WEF' AND alias = 'World Economic Forum Annual Meeting'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT 'WEF', '世界经济论坛', 'manual'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = 'WEF' AND alias = '世界经济论坛'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT 'WEF', '世界經濟論壇', 'manual'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = 'WEF' AND alias = '世界經濟論壇'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT 'WEF', '夏季达沃斯', 'simplified'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = 'WEF' AND alias = '夏季达沃斯'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT 'WEF', '夏季達沃斯', 'traditional'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = 'WEF' AND alias = '夏季達沃斯'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT 'WEF', '达沃斯', 'manual'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = 'WEF' AND alias = '达沃斯'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT 'WEF', '达沃斯论坛', 'simplified'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = 'WEF' AND alias = '达沃斯论坛'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT 'WEF', '達沃斯', 'traditional_metonymy'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = 'WEF' AND alias = '達沃斯'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT 'WEF', '達沃斯論壇', 'traditional'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = 'WEF' AND alias = '達沃斯論壇'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '中共', 'Beijing', 'metonymy_state_org_alias'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '中共' AND alias = 'Beijing'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '中共', 'CCP', 'manual'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '中共' AND alias = 'CCP'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '中共', 'CCP Central Committee', 'english_party_org_alias'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '中共' AND alias = 'CCP Central Committee'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '中共', 'Central Committee of the CCP', 'english_party_org_alias'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '中共' AND alias = 'Central Committee of the CCP'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '中共', 'China', 'english_state_alias'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '中共' AND alias = 'China'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '中共', 'Chinese Communist Party', 'manual'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '中共' AND alias = 'Chinese Communist Party'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '中共', 'Chinese Communist Party of China', 'english_party_alias'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '中共' AND alias = 'Chinese Communist Party of China'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '中共', 'Chinese government', 'english_state_org_alias'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '中共' AND alias = 'Chinese government'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '中共', 'Communist Party of China', 'english_party_alias'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '中共' AND alias = 'Communist Party of China'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '中共', 'CPC', 'manual'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '中共' AND alias = 'CPC'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '中共', 'Government of China', 'english_state_org_alias'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '中共' AND alias = 'Government of China'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '中共', 'P.R.C.', 'english_state_alias'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '中共' AND alias = 'P.R.C.'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '中共', 'People''s Republic of China', 'english_state_alias'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '中共' AND alias = 'People''s Republic of China'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '中共', 'PRC', 'english_state_alias'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '中共' AND alias = 'PRC'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '中共', 'PRC Government', 'english_state_org_alias'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '中共' AND alias = 'PRC Government'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '中共', 'PRC State Council', 'english_state_org_alias'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '中共' AND alias = 'PRC State Council'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '中共', 'State Council', 'english_state_org_alias'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '中共' AND alias = 'State Council'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '中共', 'zhong gong', 'pinyin_party_alias'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '中共' AND alias = 'zhong gong'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '中共', 'zhong guo', 'pinyin_state_alias'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '中共' AND alias = 'zhong guo'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '中共', 'zhong guo gong chan dang', 'pinyin_party_alias'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '中共' AND alias = 'zhong guo gong chan dang'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '中共', 'zhong guo zheng fu', 'pinyin_state_org_alias'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '中共' AND alias = 'zhong guo zheng fu'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '中共', 'zhonggong', 'pinyin_party_alias'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '中共' AND alias = 'zhonggong'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '中共', 'zhongguo', 'pinyin_state_alias'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '中共' AND alias = 'zhongguo'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '中共', 'zhongguo zhengfu', 'pinyin_state_org_alias'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '中共' AND alias = 'zhongguo zhengfu'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '中共', 'zhongguogongchandang', 'pinyin_party_alias'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '中共' AND alias = 'zhongguogongchandang'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '中共', 'zhonghua renmin gongheguo', 'pinyin_state_alias'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '中共' AND alias = 'zhonghua renmin gongheguo'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '中共', '中共', 'canonical'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '中共' AND alias = '中共'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '中共', '中共中央', 'party_org_alias'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '中共' AND alias = '中共中央'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '中共', '中华人民共和国', 'state_alias'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '中共' AND alias = '中华人民共和国'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '中共', '中华人民共和国政府', 'state_org_alias'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '中共' AND alias = '中华人民共和国政府'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '中共', '中国', 'state_alias'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '中共' AND alias = '中国'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '中共', '中国共产党', 'manual'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '中共' AND alias = '中国共产党'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '中共', '中国共產党', 'mixed_party_alias'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '中共' AND alias = '中国共產党'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '中共', '中国政府', 'state_org_alias'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '中共' AND alias = '中国政府'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '中共', '中國', 'traditional_state_alias'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '中共' AND alias = '中國'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '中共', '中國共产党', 'mixed_party_alias'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '中共' AND alias = '中國共产党'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '中共', '中國共產黨', 'manual'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '中共' AND alias = '中國共產黨'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '中共', '中國政府', 'traditional_state_org_alias'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '中共' AND alias = '中國政府'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '中共', '中華人民共和國', 'traditional_state_alias'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '中共' AND alias = '中華人民共和國'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '中共', '中華人民共和國政府', 'traditional_state_org_alias'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '中共' AND alias = '中華人民共和國政府'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '中共', '国务院', 'state_org_alias'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '中共' AND alias = '国务院'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '中共', '國務院', 'traditional_state_org_alias'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '中共' AND alias = '國務院'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '习近平', 'xi', 'abbr'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '习近平' AND alias = 'xi'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '习近平', 'Xi', 'manual'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '习近平' AND alias = 'Xi'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '习近平', 'xi jin ping', 'pinyin'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '习近平' AND alias = 'xi jin ping'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '习近平', 'xi jinping', 'pinyin'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '习近平' AND alias = 'xi jinping'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '习近平', 'Xi Jinping', 'manual'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '习近平' AND alias = 'Xi Jinping'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '习近平', 'xijingpin', 'pinyin'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '习近平' AND alias = 'xijingpin'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '习近平', 'xijinping', 'pinyin'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '习近平' AND alias = 'xijinping'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '习近平', 'xjp', 'abbr'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '习近平' AND alias = 'xjp'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '习近平', 'XJP', 'manual'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '习近平' AND alias = 'XJP'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '习近平', '习主席', 'nickname'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '习近平' AND alias = '习主席'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '习近平', '习包子', 'nickname'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '习近平' AND alias = '习包子'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '习近平', '习近平', 'canonical'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '习近平' AND alias = '习近平'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '习近平', '习近平思想', 'ideology_alias'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '习近平' AND alias = '习近平思想'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '习近平', '包子', 'nickname'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '习近平' AND alias = '包子'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '习近平', '大大', 'nickname'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '习近平' AND alias = '大大'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '习近平', '小熊維尼', 'traditional_nickname'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '习近平' AND alias = '小熊維尼'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '习近平', '小熊维尼', 'nickname'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '习近平' AND alias = '小熊维尼'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '习近平', '庆丰帝', 'nickname'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '习近平' AND alias = '庆丰帝'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '习近平', '总书记', 'title_alias'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '习近平' AND alias = '总书记'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '习近平', '慶豐帝', 'traditional_nickname'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '习近平' AND alias = '慶豐帝'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '习近平', '清零宗', 'nickname'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '习近平' AND alias = '清零宗'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '习近平', '維尼', 'traditional_nickname'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '习近平' AND alias = '維尼'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '习近平', '维尼', 'nickname'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '习近平' AND alias = '维尼'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '习近平', '總書記', 'traditional_title_alias'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '习近平' AND alias = '總書記'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '习近平', '習主席', 'traditional_title_alias'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '习近平' AND alias = '習主席'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '习近平', '習包子', 'traditional_nickname'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '习近平' AND alias = '習包子'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '习近平', '習近平', 'manual'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '习近平' AND alias = '習近平'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '习近平', '習近平思想', 'traditional_ideology_alias'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '习近平' AND alias = '習近平思想'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '比尔盖茨', 'bi er gai ci', 'pinyin'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '比尔盖茨' AND alias = 'bi er gai ci'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '比尔盖茨', 'bier gaici', 'pinyin'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '比尔盖茨' AND alias = 'bier gaici'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '比尔盖茨', 'Bill Gates', 'english'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '比尔盖茨' AND alias = 'Bill Gates'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '比尔盖茨', 'Gates', 'english_short'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '比尔盖茨' AND alias = 'Gates'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '比尔盖茨', 'William Henry Gates III', 'english_full'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '比尔盖茨' AND alias = 'William Henry Gates III'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '比尔盖茨', '比尔·盖茨', 'simplified'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '比尔盖茨' AND alias = '比尔·盖茨'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '比尔盖茨', '比尔盖茨', 'canonical'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '比尔盖茨' AND alias = '比尔盖茨'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '比尔盖茨', '比爾·蓋茲', 'traditional'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '比尔盖茨' AND alias = '比爾·蓋茲'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '比尔盖茨', '比爾蓋茲', 'traditional'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '比尔盖茨' AND alias = '比爾蓋茲'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '特朗普', 'chuan pu', 'pinyin'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '特朗普' AND alias = 'chuan pu'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '特朗普', 'chuanpu', 'pinyin'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '特朗普' AND alias = 'chuanpu'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '特朗普', 'DJT', 'manual'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '特朗普' AND alias = 'DJT'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '特朗普', 'Donald J. Trump', 'manual'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '特朗普' AND alias = 'Donald J. Trump'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '特朗普', 'Donald John Trump', 'manual'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '特朗普' AND alias = 'Donald John Trump'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '特朗普', 'donald trump', 'pinyin'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '特朗普' AND alias = 'donald trump'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '特朗普', 'Donald Trump', 'manual'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '特朗普' AND alias = 'Donald Trump'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '特朗普', 'te lang pu', 'pinyin'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '特朗普' AND alias = 'te lang pu'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '特朗普', 'telangpu', 'pinyin'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '特朗普' AND alias = 'telangpu'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '特朗普', 'tlp', 'abbr'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '特朗普' AND alias = 'tlp'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '特朗普', 'trump', 'pinyin'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '特朗普' AND alias = 'trump'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '特朗普', 'Trump', 'manual'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '特朗普' AND alias = 'Trump'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '特朗普', '唐納德·川普', 'traditional_full'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '特朗普' AND alias = '唐納德·川普'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '特朗普', '唐納德特朗普', 'traditional_full'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '特朗普' AND alias = '唐納德特朗普'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '特朗普', '唐纳德·特朗普', 'chinese_full'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '特朗普' AND alias = '唐纳德·特朗普'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '特朗普', '唐纳德特朗普', 'chinese_full'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '特朗普' AND alias = '唐纳德特朗普'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '特朗普', '川建国', 'nickname'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '特朗普' AND alias = '川建国'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '特朗普', '川建國', 'traditional_nickname'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '特朗普' AND alias = '川建國'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '特朗普', '川普', 'nickname'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '特朗普' AND alias = '川普'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '特朗普', '懂王', 'nickname'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '特朗普' AND alias = '懂王'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '特朗普', '特朗普', 'canonical'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '特朗普' AND alias = '特朗普'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '美联储', 'Fed', 'manual'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '美联储' AND alias = 'Fed'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '美联储', 'Federal Open Market Committee', 'manual'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '美联储' AND alias = 'Federal Open Market Committee'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '美联储', 'Federal Reserve', 'manual'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '美联储' AND alias = 'Federal Reserve'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '美联储', 'FOMC', 'manual'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '美联储' AND alias = 'FOMC'
);

INSERT INTO ccc.person_aliases (canonical, alias, alias_type)
SELECT '美联储', '聯準會', 'manual'
WHERE NOT EXISTS (
  SELECT 1 FROM ccc.person_aliases
  WHERE canonical = '美联储' AND alias = '聯準會'
);

-- ============================================================
-- Regression expectations
-- ============================================================


CREATE TABLE IF NOT EXISTS ccc.entity_resolve_v3_local_expectations (
  q text PRIMARY KEY,
  expected_canonical_name text NOT NULL,
  expected_entity_id bigint NOT NULL,
  expected_match_type text NOT NULL,
  min_confidence numeric NOT NULL,
  expected_entity_type text NOT NULL,
  note text,
  updated_at timestamp with time zone DEFAULT now()
);

INSERT INTO ccc.entity_resolve_v3_local_expectations (q, expected_canonical_name, expected_entity_id, expected_match_type, min_confidence, expected_entity_type, note)
VALUES ('Beijing', '中共', 34, 'alias_exact', 0.98, 'ORG', 'Metonymy routes to 中共')
ON CONFLICT (q) DO UPDATE SET
  expected_canonical_name = EXCLUDED.expected_canonical_name,
  expected_entity_id = EXCLUDED.expected_entity_id,
  expected_match_type = EXCLUDED.expected_match_type,
  min_confidence = EXCLUDED.min_confidence,
  expected_entity_type = EXCLUDED.expected_entity_type,
  note = EXCLUDED.note,
  updated_at = now();

INSERT INTO ccc.entity_resolve_v3_local_expectations (q, expected_canonical_name, expected_entity_id, expected_match_type, min_confidence, expected_entity_type, note)
VALUES ('Bill Gates', '比尔盖茨', 62, 'alias_exact', 0.98, 'PERSON', 'Bill Gates remains separate PERSON entity')
ON CONFLICT (q) DO UPDATE SET
  expected_canonical_name = EXCLUDED.expected_canonical_name,
  expected_entity_id = EXCLUDED.expected_entity_id,
  expected_match_type = EXCLUDED.expected_match_type,
  min_confidence = EXCLUDED.min_confidence,
  expected_entity_type = EXCLUDED.expected_entity_type,
  note = EXCLUDED.note,
  updated_at = now();

INSERT INTO ccc.entity_resolve_v3_local_expectations (q, expected_canonical_name, expected_entity_id, expected_match_type, min_confidence, expected_entity_type, note)
VALUES ('CCP', '中共', 34, 'alias_exact', 0.98, 'ORG', 'CCP routes to 中共')
ON CONFLICT (q) DO UPDATE SET
  expected_canonical_name = EXCLUDED.expected_canonical_name,
  expected_entity_id = EXCLUDED.expected_entity_id,
  expected_match_type = EXCLUDED.expected_match_type,
  min_confidence = EXCLUDED.min_confidence,
  expected_entity_type = EXCLUDED.expected_entity_type,
  note = EXCLUDED.note,
  updated_at = now();

INSERT INTO ccc.entity_resolve_v3_local_expectations (q, expected_canonical_name, expected_entity_id, expected_match_type, min_confidence, expected_entity_type, note)
VALUES ('China', '中共', 34, 'alias_exact', 0.98, 'ORG', 'RSAL rule: China routes to 中共')
ON CONFLICT (q) DO UPDATE SET
  expected_canonical_name = EXCLUDED.expected_canonical_name,
  expected_entity_id = EXCLUDED.expected_entity_id,
  expected_match_type = EXCLUDED.expected_match_type,
  min_confidence = EXCLUDED.min_confidence,
  expected_entity_type = EXCLUDED.expected_entity_type,
  note = EXCLUDED.note,
  updated_at = now();

INSERT INTO ccc.entity_resolve_v3_local_expectations (q, expected_canonical_name, expected_entity_id, expected_match_type, min_confidence, expected_entity_type, note)
VALUES ('Chinese Communist Party of China', '中共', 34, 'alias_exact', 0.98, 'ORG', 'Full English party alias routes to 中共')
ON CONFLICT (q) DO UPDATE SET
  expected_canonical_name = EXCLUDED.expected_canonical_name,
  expected_entity_id = EXCLUDED.expected_entity_id,
  expected_match_type = EXCLUDED.expected_match_type,
  min_confidence = EXCLUDED.min_confidence,
  expected_entity_type = EXCLUDED.expected_entity_type,
  note = EXCLUDED.note,
  updated_at = now();

INSERT INTO ccc.entity_resolve_v3_local_expectations (q, expected_canonical_name, expected_entity_id, expected_match_type, min_confidence, expected_entity_type, note)
VALUES ('Chinese government', '中共', 34, 'alias_exact', 0.98, 'ORG', 'English government alias routes to 中共')
ON CONFLICT (q) DO UPDATE SET
  expected_canonical_name = EXCLUDED.expected_canonical_name,
  expected_entity_id = EXCLUDED.expected_entity_id,
  expected_match_type = EXCLUDED.expected_match_type,
  min_confidence = EXCLUDED.min_confidence,
  expected_entity_type = EXCLUDED.expected_entity_type,
  note = EXCLUDED.note,
  updated_at = now();

INSERT INTO ccc.entity_resolve_v3_local_expectations (q, expected_canonical_name, expected_entity_id, expected_match_type, min_confidence, expected_entity_type, note)
VALUES ('Communist Party of China', '中共', 34, 'alias_exact', 0.98, 'ORG', 'English party alias routes to 中共')
ON CONFLICT (q) DO UPDATE SET
  expected_canonical_name = EXCLUDED.expected_canonical_name,
  expected_entity_id = EXCLUDED.expected_entity_id,
  expected_match_type = EXCLUDED.expected_match_type,
  min_confidence = EXCLUDED.min_confidence,
  expected_entity_type = EXCLUDED.expected_entity_type,
  note = EXCLUDED.note,
  updated_at = now();

INSERT INTO ccc.entity_resolve_v3_local_expectations (q, expected_canonical_name, expected_entity_id, expected_match_type, min_confidence, expected_entity_type, note)
VALUES ('CPC', '中共', 34, 'alias_exact', 0.98, 'ORG', 'CPC routes to 中共')
ON CONFLICT (q) DO UPDATE SET
  expected_canonical_name = EXCLUDED.expected_canonical_name,
  expected_entity_id = EXCLUDED.expected_entity_id,
  expected_match_type = EXCLUDED.expected_match_type,
  min_confidence = EXCLUDED.min_confidence,
  expected_entity_type = EXCLUDED.expected_entity_type,
  note = EXCLUDED.note,
  updated_at = now();

INSERT INTO ccc.entity_resolve_v3_local_expectations (q, expected_canonical_name, expected_entity_id, expected_match_type, min_confidence, expected_entity_type, note)
VALUES ('Davos', 'WEF', 59, 'alias_exact', 0.98, 'ORG', 'Davos routes to WEF')
ON CONFLICT (q) DO UPDATE SET
  expected_canonical_name = EXCLUDED.expected_canonical_name,
  expected_entity_id = EXCLUDED.expected_entity_id,
  expected_match_type = EXCLUDED.expected_match_type,
  min_confidence = EXCLUDED.min_confidence,
  expected_entity_type = EXCLUDED.expected_entity_type,
  note = EXCLUDED.note,
  updated_at = now();

INSERT INTO ccc.entity_resolve_v3_local_expectations (q, expected_canonical_name, expected_entity_id, expected_match_type, min_confidence, expected_entity_type, note)
VALUES ('DJT', '特朗普', 17, 'alias_exact', 0.98, 'PERSON', 'Abbreviation routes to 特朗普')
ON CONFLICT (q) DO UPDATE SET
  expected_canonical_name = EXCLUDED.expected_canonical_name,
  expected_entity_id = EXCLUDED.expected_entity_id,
  expected_match_type = EXCLUDED.expected_match_type,
  min_confidence = EXCLUDED.min_confidence,
  expected_entity_type = EXCLUDED.expected_entity_type,
  note = EXCLUDED.note,
  updated_at = now();

INSERT INTO ccc.entity_resolve_v3_local_expectations (q, expected_canonical_name, expected_entity_id, expected_match_type, min_confidence, expected_entity_type, note)
VALUES ('Donald J. Trump', '特朗普', 17, 'alias_exact', 0.98, 'PERSON', 'English alias routes to 特朗普')
ON CONFLICT (q) DO UPDATE SET
  expected_canonical_name = EXCLUDED.expected_canonical_name,
  expected_entity_id = EXCLUDED.expected_entity_id,
  expected_match_type = EXCLUDED.expected_match_type,
  min_confidence = EXCLUDED.min_confidence,
  expected_entity_type = EXCLUDED.expected_entity_type,
  note = EXCLUDED.note,
  updated_at = now();

INSERT INTO ccc.entity_resolve_v3_local_expectations (q, expected_canonical_name, expected_entity_id, expected_match_type, min_confidence, expected_entity_type, note)
VALUES ('Donald John Trump', '特朗普', 17, 'alias_exact', 0.98, 'PERSON', 'Full English name routes to 特朗普')
ON CONFLICT (q) DO UPDATE SET
  expected_canonical_name = EXCLUDED.expected_canonical_name,
  expected_entity_id = EXCLUDED.expected_entity_id,
  expected_match_type = EXCLUDED.expected_match_type,
  min_confidence = EXCLUDED.min_confidence,
  expected_entity_type = EXCLUDED.expected_entity_type,
  note = EXCLUDED.note,
  updated_at = now();

INSERT INTO ccc.entity_resolve_v3_local_expectations (q, expected_canonical_name, expected_entity_id, expected_match_type, min_confidence, expected_entity_type, note)
VALUES ('Donald Trump', '特朗普', 17, 'alias_exact', 0.98, 'PERSON', 'English alias routes to 特朗普')
ON CONFLICT (q) DO UPDATE SET
  expected_canonical_name = EXCLUDED.expected_canonical_name,
  expected_entity_id = EXCLUDED.expected_entity_id,
  expected_match_type = EXCLUDED.expected_match_type,
  min_confidence = EXCLUDED.min_confidence,
  expected_entity_type = EXCLUDED.expected_entity_type,
  note = EXCLUDED.note,
  updated_at = now();

INSERT INTO ccc.entity_resolve_v3_local_expectations (q, expected_canonical_name, expected_entity_id, expected_match_type, min_confidence, expected_entity_type, note)
VALUES ('Fed', '美联储', 35, 'alias_exact', 0.98, 'ORG', 'Fed routes to 美联储')
ON CONFLICT (q) DO UPDATE SET
  expected_canonical_name = EXCLUDED.expected_canonical_name,
  expected_entity_id = EXCLUDED.expected_entity_id,
  expected_match_type = EXCLUDED.expected_match_type,
  min_confidence = EXCLUDED.min_confidence,
  expected_entity_type = EXCLUDED.expected_entity_type,
  note = EXCLUDED.note,
  updated_at = now();

INSERT INTO ccc.entity_resolve_v3_local_expectations (q, expected_canonical_name, expected_entity_id, expected_match_type, min_confidence, expected_entity_type, note)
VALUES ('FOMC', '美联储', 35, 'alias_exact', 0.98, 'ORG', 'FOMC routes to 美联储')
ON CONFLICT (q) DO UPDATE SET
  expected_canonical_name = EXCLUDED.expected_canonical_name,
  expected_entity_id = EXCLUDED.expected_entity_id,
  expected_match_type = EXCLUDED.expected_match_type,
  min_confidence = EXCLUDED.min_confidence,
  expected_entity_type = EXCLUDED.expected_entity_type,
  note = EXCLUDED.note,
  updated_at = now();

INSERT INTO ccc.entity_resolve_v3_local_expectations (q, expected_canonical_name, expected_entity_id, expected_match_type, min_confidence, expected_entity_type, note)
VALUES ('Government of China', '中共', 34, 'alias_exact', 0.98, 'ORG', 'Government of China routes to 中共')
ON CONFLICT (q) DO UPDATE SET
  expected_canonical_name = EXCLUDED.expected_canonical_name,
  expected_entity_id = EXCLUDED.expected_entity_id,
  expected_match_type = EXCLUDED.expected_match_type,
  min_confidence = EXCLUDED.min_confidence,
  expected_entity_type = EXCLUDED.expected_entity_type,
  note = EXCLUDED.note,
  updated_at = now();

INSERT INTO ccc.entity_resolve_v3_local_expectations (q, expected_canonical_name, expected_entity_id, expected_match_type, min_confidence, expected_entity_type, note)
VALUES ('P.R.C.', '中共', 34, 'alias_exact', 0.98, 'ORG', 'P.R.C. routes to 中共')
ON CONFLICT (q) DO UPDATE SET
  expected_canonical_name = EXCLUDED.expected_canonical_name,
  expected_entity_id = EXCLUDED.expected_entity_id,
  expected_match_type = EXCLUDED.expected_match_type,
  min_confidence = EXCLUDED.min_confidence,
  expected_entity_type = EXCLUDED.expected_entity_type,
  note = EXCLUDED.note,
  updated_at = now();

INSERT INTO ccc.entity_resolve_v3_local_expectations (q, expected_canonical_name, expected_entity_id, expected_match_type, min_confidence, expected_entity_type, note)
VALUES ('People''s Republic of China', '中共', 34, 'alias_exact', 0.98, 'ORG', 'RSAL rule: official state name routes to 中共')
ON CONFLICT (q) DO UPDATE SET
  expected_canonical_name = EXCLUDED.expected_canonical_name,
  expected_entity_id = EXCLUDED.expected_entity_id,
  expected_match_type = EXCLUDED.expected_match_type,
  min_confidence = EXCLUDED.min_confidence,
  expected_entity_type = EXCLUDED.expected_entity_type,
  note = EXCLUDED.note,
  updated_at = now();

INSERT INTO ccc.entity_resolve_v3_local_expectations (q, expected_canonical_name, expected_entity_id, expected_match_type, min_confidence, expected_entity_type, note)
VALUES ('PRC', '中共', 34, 'alias_exact', 0.98, 'ORG', 'RSAL rule: PRC routes to 中共')
ON CONFLICT (q) DO UPDATE SET
  expected_canonical_name = EXCLUDED.expected_canonical_name,
  expected_entity_id = EXCLUDED.expected_entity_id,
  expected_match_type = EXCLUDED.expected_match_type,
  min_confidence = EXCLUDED.min_confidence,
  expected_entity_type = EXCLUDED.expected_entity_type,
  note = EXCLUDED.note,
  updated_at = now();

INSERT INTO ccc.entity_resolve_v3_local_expectations (q, expected_canonical_name, expected_entity_id, expected_match_type, min_confidence, expected_entity_type, note)
VALUES ('PRC Government', '中共', 34, 'alias_exact', 0.98, 'ORG', 'PRC Government routes to 中共')
ON CONFLICT (q) DO UPDATE SET
  expected_canonical_name = EXCLUDED.expected_canonical_name,
  expected_entity_id = EXCLUDED.expected_entity_id,
  expected_match_type = EXCLUDED.expected_match_type,
  min_confidence = EXCLUDED.min_confidence,
  expected_entity_type = EXCLUDED.expected_entity_type,
  note = EXCLUDED.note,
  updated_at = now();

INSERT INTO ccc.entity_resolve_v3_local_expectations (q, expected_canonical_name, expected_entity_id, expected_match_type, min_confidence, expected_entity_type, note)
VALUES ('State Council', '中共', 34, 'alias_exact', 0.98, 'ORG', 'State Council routes to 中共')
ON CONFLICT (q) DO UPDATE SET
  expected_canonical_name = EXCLUDED.expected_canonical_name,
  expected_entity_id = EXCLUDED.expected_entity_id,
  expected_match_type = EXCLUDED.expected_match_type,
  min_confidence = EXCLUDED.min_confidence,
  expected_entity_type = EXCLUDED.expected_entity_type,
  note = EXCLUDED.note,
  updated_at = now();

INSERT INTO ccc.entity_resolve_v3_local_expectations (q, expected_canonical_name, expected_entity_id, expected_match_type, min_confidence, expected_entity_type, note)
VALUES ('Trump', '特朗普', 17, 'alias_exact', 0.98, 'PERSON', 'English alias routes to 特朗普')
ON CONFLICT (q) DO UPDATE SET
  expected_canonical_name = EXCLUDED.expected_canonical_name,
  expected_entity_id = EXCLUDED.expected_entity_id,
  expected_match_type = EXCLUDED.expected_match_type,
  min_confidence = EXCLUDED.min_confidence,
  expected_entity_type = EXCLUDED.expected_entity_type,
  note = EXCLUDED.note,
  updated_at = now();

INSERT INTO ccc.entity_resolve_v3_local_expectations (q, expected_canonical_name, expected_entity_id, expected_match_type, min_confidence, expected_entity_type, note)
VALUES ('WEF', 'WEF', 59, 'entity_exact', 0.99, 'ORG', 'Canonical exact route')
ON CONFLICT (q) DO UPDATE SET
  expected_canonical_name = EXCLUDED.expected_canonical_name,
  expected_entity_id = EXCLUDED.expected_entity_id,
  expected_match_type = EXCLUDED.expected_match_type,
  min_confidence = EXCLUDED.min_confidence,
  expected_entity_type = EXCLUDED.expected_entity_type,
  note = EXCLUDED.note,
  updated_at = now();

INSERT INTO ccc.entity_resolve_v3_local_expectations (q, expected_canonical_name, expected_entity_id, expected_match_type, min_confidence, expected_entity_type, note)
VALUES ('World Economic Forum', 'WEF', 59, 'alias_exact', 0.98, 'ORG', 'English org alias routes to WEF')
ON CONFLICT (q) DO UPDATE SET
  expected_canonical_name = EXCLUDED.expected_canonical_name,
  expected_entity_id = EXCLUDED.expected_entity_id,
  expected_match_type = EXCLUDED.expected_match_type,
  min_confidence = EXCLUDED.min_confidence,
  expected_entity_type = EXCLUDED.expected_entity_type,
  note = EXCLUDED.note,
  updated_at = now();

INSERT INTO ccc.entity_resolve_v3_local_expectations (q, expected_canonical_name, expected_entity_id, expected_match_type, min_confidence, expected_entity_type, note)
VALUES ('Xi Jinping', '习近平', 16, 'alias_exact', 0.98, 'PERSON', 'Xi Jinping routes to 习近平 without fuzzy Putin pollution')
ON CONFLICT (q) DO UPDATE SET
  expected_canonical_name = EXCLUDED.expected_canonical_name,
  expected_entity_id = EXCLUDED.expected_entity_id,
  expected_match_type = EXCLUDED.expected_match_type,
  min_confidence = EXCLUDED.min_confidence,
  expected_entity_type = EXCLUDED.expected_entity_type,
  note = EXCLUDED.note,
  updated_at = now();

INSERT INTO ccc.entity_resolve_v3_local_expectations (q, expected_canonical_name, expected_entity_id, expected_match_type, min_confidence, expected_entity_type, note)
VALUES ('XJP', '习近平', 16, 'alias_exact', 0.98, 'PERSON', 'XJP routes to 习近平')
ON CONFLICT (q) DO UPDATE SET
  expected_canonical_name = EXCLUDED.expected_canonical_name,
  expected_entity_id = EXCLUDED.expected_entity_id,
  expected_match_type = EXCLUDED.expected_match_type,
  min_confidence = EXCLUDED.min_confidence,
  expected_entity_type = EXCLUDED.expected_entity_type,
  note = EXCLUDED.note,
  updated_at = now();

INSERT INTO ccc.entity_resolve_v3_local_expectations (q, expected_canonical_name, expected_entity_id, expected_match_type, min_confidence, expected_entity_type, note)
VALUES ('zhong guo', '中共', 34, 'alias_exact', 0.98, 'ORG', 'Pinyin state alias routes to 中共')
ON CONFLICT (q) DO UPDATE SET
  expected_canonical_name = EXCLUDED.expected_canonical_name,
  expected_entity_id = EXCLUDED.expected_entity_id,
  expected_match_type = EXCLUDED.expected_match_type,
  min_confidence = EXCLUDED.min_confidence,
  expected_entity_type = EXCLUDED.expected_entity_type,
  note = EXCLUDED.note,
  updated_at = now();

INSERT INTO ccc.entity_resolve_v3_local_expectations (q, expected_canonical_name, expected_entity_id, expected_match_type, min_confidence, expected_entity_type, note)
VALUES ('zhong guo zheng fu', '中共', 34, 'alias_exact', 0.98, 'ORG', 'Spaced pinyin government alias routes to 中共')
ON CONFLICT (q) DO UPDATE SET
  expected_canonical_name = EXCLUDED.expected_canonical_name,
  expected_entity_id = EXCLUDED.expected_entity_id,
  expected_match_type = EXCLUDED.expected_match_type,
  min_confidence = EXCLUDED.min_confidence,
  expected_entity_type = EXCLUDED.expected_entity_type,
  note = EXCLUDED.note,
  updated_at = now();

INSERT INTO ccc.entity_resolve_v3_local_expectations (q, expected_canonical_name, expected_entity_id, expected_match_type, min_confidence, expected_entity_type, note)
VALUES ('zhongguo zhengfu', '中共', 34, 'alias_exact', 0.98, 'ORG', 'Pinyin government alias routes to 中共')
ON CONFLICT (q) DO UPDATE SET
  expected_canonical_name = EXCLUDED.expected_canonical_name,
  expected_entity_id = EXCLUDED.expected_entity_id,
  expected_match_type = EXCLUDED.expected_match_type,
  min_confidence = EXCLUDED.min_confidence,
  expected_entity_type = EXCLUDED.expected_entity_type,
  note = EXCLUDED.note,
  updated_at = now();

INSERT INTO ccc.entity_resolve_v3_local_expectations (q, expected_canonical_name, expected_entity_id, expected_match_type, min_confidence, expected_entity_type, note)
VALUES ('zhongguogongchandang', '中共', 34, 'alias_exact', 0.98, 'ORG', 'Pinyin party alias routes to 中共')
ON CONFLICT (q) DO UPDATE SET
  expected_canonical_name = EXCLUDED.expected_canonical_name,
  expected_entity_id = EXCLUDED.expected_entity_id,
  expected_match_type = EXCLUDED.expected_match_type,
  min_confidence = EXCLUDED.min_confidence,
  expected_entity_type = EXCLUDED.expected_entity_type,
  note = EXCLUDED.note,
  updated_at = now();

INSERT INTO ccc.entity_resolve_v3_local_expectations (q, expected_canonical_name, expected_entity_id, expected_match_type, min_confidence, expected_entity_type, note)
VALUES ('zhonghua renmin gongheguo', '中共', 34, 'alias_exact', 0.98, 'ORG', 'Pinyin official state name routes to 中共')
ON CONFLICT (q) DO UPDATE SET
  expected_canonical_name = EXCLUDED.expected_canonical_name,
  expected_entity_id = EXCLUDED.expected_entity_id,
  expected_match_type = EXCLUDED.expected_match_type,
  min_confidence = EXCLUDED.min_confidence,
  expected_entity_type = EXCLUDED.expected_entity_type,
  note = EXCLUDED.note,
  updated_at = now();

INSERT INTO ccc.entity_resolve_v3_local_expectations (q, expected_canonical_name, expected_entity_id, expected_match_type, min_confidence, expected_entity_type, note)
VALUES ('世界经济论坛', 'WEF', 59, 'alias_exact', 0.98, 'ORG', 'Simplified org alias routes to WEF')
ON CONFLICT (q) DO UPDATE SET
  expected_canonical_name = EXCLUDED.expected_canonical_name,
  expected_entity_id = EXCLUDED.expected_entity_id,
  expected_match_type = EXCLUDED.expected_match_type,
  min_confidence = EXCLUDED.min_confidence,
  expected_entity_type = EXCLUDED.expected_entity_type,
  note = EXCLUDED.note,
  updated_at = now();

INSERT INTO ccc.entity_resolve_v3_local_expectations (q, expected_canonical_name, expected_entity_id, expected_match_type, min_confidence, expected_entity_type, note)
VALUES ('世界經濟論壇', 'WEF', 59, 'alias_exact', 0.98, 'ORG', 'Traditional org alias routes to WEF')
ON CONFLICT (q) DO UPDATE SET
  expected_canonical_name = EXCLUDED.expected_canonical_name,
  expected_entity_id = EXCLUDED.expected_entity_id,
  expected_match_type = EXCLUDED.expected_match_type,
  min_confidence = EXCLUDED.min_confidence,
  expected_entity_type = EXCLUDED.expected_entity_type,
  note = EXCLUDED.note,
  updated_at = now();

INSERT INTO ccc.entity_resolve_v3_local_expectations (q, expected_canonical_name, expected_entity_id, expected_match_type, min_confidence, expected_entity_type, note)
VALUES ('中国', '中共', 34, 'alias_exact', 0.98, 'ORG', 'RSAL rule: 中国 routes to 中共')
ON CONFLICT (q) DO UPDATE SET
  expected_canonical_name = EXCLUDED.expected_canonical_name,
  expected_entity_id = EXCLUDED.expected_entity_id,
  expected_match_type = EXCLUDED.expected_match_type,
  min_confidence = EXCLUDED.min_confidence,
  expected_entity_type = EXCLUDED.expected_entity_type,
  note = EXCLUDED.note,
  updated_at = now();

INSERT INTO ccc.entity_resolve_v3_local_expectations (q, expected_canonical_name, expected_entity_id, expected_match_type, min_confidence, expected_entity_type, note)
VALUES ('中国共产党', '中共', 34, 'alias_exact', 0.98, 'ORG', 'Party alias routes to 中共')
ON CONFLICT (q) DO UPDATE SET
  expected_canonical_name = EXCLUDED.expected_canonical_name,
  expected_entity_id = EXCLUDED.expected_entity_id,
  expected_match_type = EXCLUDED.expected_match_type,
  min_confidence = EXCLUDED.min_confidence,
  expected_entity_type = EXCLUDED.expected_entity_type,
  note = EXCLUDED.note,
  updated_at = now();

INSERT INTO ccc.entity_resolve_v3_local_expectations (q, expected_canonical_name, expected_entity_id, expected_match_type, min_confidence, expected_entity_type, note)
VALUES ('中国政府', '中共', 34, 'alias_exact', 0.98, 'ORG', 'Government alias routes to 中共')
ON CONFLICT (q) DO UPDATE SET
  expected_canonical_name = EXCLUDED.expected_canonical_name,
  expected_entity_id = EXCLUDED.expected_entity_id,
  expected_match_type = EXCLUDED.expected_match_type,
  min_confidence = EXCLUDED.min_confidence,
  expected_entity_type = EXCLUDED.expected_entity_type,
  note = EXCLUDED.note,
  updated_at = now();

INSERT INTO ccc.entity_resolve_v3_local_expectations (q, expected_canonical_name, expected_entity_id, expected_match_type, min_confidence, expected_entity_type, note)
VALUES ('中國', '中共', 34, 'alias_exact', 0.98, 'ORG', 'Traditional Chinese routes to 中共')
ON CONFLICT (q) DO UPDATE SET
  expected_canonical_name = EXCLUDED.expected_canonical_name,
  expected_entity_id = EXCLUDED.expected_entity_id,
  expected_match_type = EXCLUDED.expected_match_type,
  min_confidence = EXCLUDED.min_confidence,
  expected_entity_type = EXCLUDED.expected_entity_type,
  note = EXCLUDED.note,
  updated_at = now();

INSERT INTO ccc.entity_resolve_v3_local_expectations (q, expected_canonical_name, expected_entity_id, expected_match_type, min_confidence, expected_entity_type, note)
VALUES ('中國共產黨', '中共', 34, 'alias_exact', 0.98, 'ORG', 'Traditional party alias routes to 中共')
ON CONFLICT (q) DO UPDATE SET
  expected_canonical_name = EXCLUDED.expected_canonical_name,
  expected_entity_id = EXCLUDED.expected_entity_id,
  expected_match_type = EXCLUDED.expected_match_type,
  min_confidence = EXCLUDED.min_confidence,
  expected_entity_type = EXCLUDED.expected_entity_type,
  note = EXCLUDED.note,
  updated_at = now();

INSERT INTO ccc.entity_resolve_v3_local_expectations (q, expected_canonical_name, expected_entity_id, expected_match_type, min_confidence, expected_entity_type, note)
VALUES ('中國政府', '中共', 34, 'alias_exact', 0.98, 'ORG', 'Traditional government alias routes to 中共')
ON CONFLICT (q) DO UPDATE SET
  expected_canonical_name = EXCLUDED.expected_canonical_name,
  expected_entity_id = EXCLUDED.expected_entity_id,
  expected_match_type = EXCLUDED.expected_match_type,
  min_confidence = EXCLUDED.min_confidence,
  expected_entity_type = EXCLUDED.expected_entity_type,
  note = EXCLUDED.note,
  updated_at = now();

INSERT INTO ccc.entity_resolve_v3_local_expectations (q, expected_canonical_name, expected_entity_id, expected_match_type, min_confidence, expected_entity_type, note)
VALUES ('习包子', '习近平', 16, 'alias_exact', 0.98, 'PERSON', 'Nickname routes to 习近平')
ON CONFLICT (q) DO UPDATE SET
  expected_canonical_name = EXCLUDED.expected_canonical_name,
  expected_entity_id = EXCLUDED.expected_entity_id,
  expected_match_type = EXCLUDED.expected_match_type,
  min_confidence = EXCLUDED.min_confidence,
  expected_entity_type = EXCLUDED.expected_entity_type,
  note = EXCLUDED.note,
  updated_at = now();

INSERT INTO ccc.entity_resolve_v3_local_expectations (q, expected_canonical_name, expected_entity_id, expected_match_type, min_confidence, expected_entity_type, note)
VALUES ('习近平思想', '习近平', 16, 'alias_exact', 0.98, 'PERSON', 'Ideology alias routes to 习近平')
ON CONFLICT (q) DO UPDATE SET
  expected_canonical_name = EXCLUDED.expected_canonical_name,
  expected_entity_id = EXCLUDED.expected_entity_id,
  expected_match_type = EXCLUDED.expected_match_type,
  min_confidence = EXCLUDED.min_confidence,
  expected_entity_type = EXCLUDED.expected_entity_type,
  note = EXCLUDED.note,
  updated_at = now();

INSERT INTO ccc.entity_resolve_v3_local_expectations (q, expected_canonical_name, expected_entity_id, expected_match_type, min_confidence, expected_entity_type, note)
VALUES ('包子', '习近平', 16, 'alias_exact', 0.98, 'PERSON', 'Nickname routes to 习近平')
ON CONFLICT (q) DO UPDATE SET
  expected_canonical_name = EXCLUDED.expected_canonical_name,
  expected_entity_id = EXCLUDED.expected_entity_id,
  expected_match_type = EXCLUDED.expected_match_type,
  min_confidence = EXCLUDED.min_confidence,
  expected_entity_type = EXCLUDED.expected_entity_type,
  note = EXCLUDED.note,
  updated_at = now();

INSERT INTO ccc.entity_resolve_v3_local_expectations (q, expected_canonical_name, expected_entity_id, expected_match_type, min_confidence, expected_entity_type, note)
VALUES ('小熊维尼', '习近平', 16, 'alias_exact', 0.98, 'PERSON', 'Nickname routes to 习近平')
ON CONFLICT (q) DO UPDATE SET
  expected_canonical_name = EXCLUDED.expected_canonical_name,
  expected_entity_id = EXCLUDED.expected_entity_id,
  expected_match_type = EXCLUDED.expected_match_type,
  min_confidence = EXCLUDED.min_confidence,
  expected_entity_type = EXCLUDED.expected_entity_type,
  note = EXCLUDED.note,
  updated_at = now();

INSERT INTO ccc.entity_resolve_v3_local_expectations (q, expected_canonical_name, expected_entity_id, expected_match_type, min_confidence, expected_entity_type, note)
VALUES ('川建国', '特朗普', 17, 'alias_exact', 0.98, 'PERSON', 'Nickname routes to 特朗普')
ON CONFLICT (q) DO UPDATE SET
  expected_canonical_name = EXCLUDED.expected_canonical_name,
  expected_entity_id = EXCLUDED.expected_entity_id,
  expected_match_type = EXCLUDED.expected_match_type,
  min_confidence = EXCLUDED.min_confidence,
  expected_entity_type = EXCLUDED.expected_entity_type,
  note = EXCLUDED.note,
  updated_at = now();

INSERT INTO ccc.entity_resolve_v3_local_expectations (q, expected_canonical_name, expected_entity_id, expected_match_type, min_confidence, expected_entity_type, note)
VALUES ('川普', '特朗普', 17, 'alias_exact', 0.98, 'PERSON', 'Nickname routes to 特朗普')
ON CONFLICT (q) DO UPDATE SET
  expected_canonical_name = EXCLUDED.expected_canonical_name,
  expected_entity_id = EXCLUDED.expected_entity_id,
  expected_match_type = EXCLUDED.expected_match_type,
  min_confidence = EXCLUDED.min_confidence,
  expected_entity_type = EXCLUDED.expected_entity_type,
  note = EXCLUDED.note,
  updated_at = now();

INSERT INTO ccc.entity_resolve_v3_local_expectations (q, expected_canonical_name, expected_entity_id, expected_match_type, min_confidence, expected_entity_type, note)
VALUES ('庆丰帝', '习近平', 16, 'alias_exact', 0.98, 'PERSON', 'Nickname routes to 习近平')
ON CONFLICT (q) DO UPDATE SET
  expected_canonical_name = EXCLUDED.expected_canonical_name,
  expected_entity_id = EXCLUDED.expected_entity_id,
  expected_match_type = EXCLUDED.expected_match_type,
  min_confidence = EXCLUDED.min_confidence,
  expected_entity_type = EXCLUDED.expected_entity_type,
  note = EXCLUDED.note,
  updated_at = now();

INSERT INTO ccc.entity_resolve_v3_local_expectations (q, expected_canonical_name, expected_entity_id, expected_match_type, min_confidence, expected_entity_type, note)
VALUES ('懂王', '特朗普', 17, 'alias_exact', 0.98, 'PERSON', 'Nickname routes to 特朗普')
ON CONFLICT (q) DO UPDATE SET
  expected_canonical_name = EXCLUDED.expected_canonical_name,
  expected_entity_id = EXCLUDED.expected_entity_id,
  expected_match_type = EXCLUDED.expected_match_type,
  min_confidence = EXCLUDED.min_confidence,
  expected_entity_type = EXCLUDED.expected_entity_type,
  note = EXCLUDED.note,
  updated_at = now();

INSERT INTO ccc.entity_resolve_v3_local_expectations (q, expected_canonical_name, expected_entity_id, expected_match_type, min_confidence, expected_entity_type, note)
VALUES ('比尔盖茨', '比尔盖茨', 62, 'entity_exact', 0.99, 'PERSON', 'Bill Gates canonical entity')
ON CONFLICT (q) DO UPDATE SET
  expected_canonical_name = EXCLUDED.expected_canonical_name,
  expected_entity_id = EXCLUDED.expected_entity_id,
  expected_match_type = EXCLUDED.expected_match_type,
  min_confidence = EXCLUDED.min_confidence,
  expected_entity_type = EXCLUDED.expected_entity_type,
  note = EXCLUDED.note,
  updated_at = now();

INSERT INTO ccc.entity_resolve_v3_local_expectations (q, expected_canonical_name, expected_entity_id, expected_match_type, min_confidence, expected_entity_type, note)
VALUES ('比爾蓋茲', '比尔盖茨', 62, 'alias_exact', 0.98, 'PERSON', 'Traditional Bill Gates alias routes to 比尔盖茨')
ON CONFLICT (q) DO UPDATE SET
  expected_canonical_name = EXCLUDED.expected_canonical_name,
  expected_entity_id = EXCLUDED.expected_entity_id,
  expected_match_type = EXCLUDED.expected_match_type,
  min_confidence = EXCLUDED.min_confidence,
  expected_entity_type = EXCLUDED.expected_entity_type,
  note = EXCLUDED.note,
  updated_at = now();

INSERT INTO ccc.entity_resolve_v3_local_expectations (q, expected_canonical_name, expected_entity_id, expected_match_type, min_confidence, expected_entity_type, note)
VALUES ('清零宗', '习近平', 16, 'alias_exact', 0.98, 'PERSON', 'Nickname routes to 习近平')
ON CONFLICT (q) DO UPDATE SET
  expected_canonical_name = EXCLUDED.expected_canonical_name,
  expected_entity_id = EXCLUDED.expected_entity_id,
  expected_match_type = EXCLUDED.expected_match_type,
  min_confidence = EXCLUDED.min_confidence,
  expected_entity_type = EXCLUDED.expected_entity_type,
  note = EXCLUDED.note,
  updated_at = now();

INSERT INTO ccc.entity_resolve_v3_local_expectations (q, expected_canonical_name, expected_entity_id, expected_match_type, min_confidence, expected_entity_type, note)
VALUES ('维尼', '习近平', 16, 'alias_exact', 0.98, 'PERSON', 'Nickname routes to 习近平')
ON CONFLICT (q) DO UPDATE SET
  expected_canonical_name = EXCLUDED.expected_canonical_name,
  expected_entity_id = EXCLUDED.expected_entity_id,
  expected_match_type = EXCLUDED.expected_match_type,
  min_confidence = EXCLUDED.min_confidence,
  expected_entity_type = EXCLUDED.expected_entity_type,
  note = EXCLUDED.note,
  updated_at = now();

INSERT INTO ccc.entity_resolve_v3_local_expectations (q, expected_canonical_name, expected_entity_id, expected_match_type, min_confidence, expected_entity_type, note)
VALUES ('达沃斯论坛', 'WEF', 59, 'alias_exact', 0.98, 'ORG', 'Davos forum routes to WEF')
ON CONFLICT (q) DO UPDATE SET
  expected_canonical_name = EXCLUDED.expected_canonical_name,
  expected_entity_id = EXCLUDED.expected_entity_id,
  expected_match_type = EXCLUDED.expected_match_type,
  min_confidence = EXCLUDED.min_confidence,
  expected_entity_type = EXCLUDED.expected_entity_type,
  note = EXCLUDED.note,
  updated_at = now();

INSERT INTO ccc.entity_resolve_v3_local_expectations (q, expected_canonical_name, expected_entity_id, expected_match_type, min_confidence, expected_entity_type, note)
VALUES ('達沃斯論壇', 'WEF', 59, 'alias_exact', 0.98, 'ORG', 'Traditional Davos forum routes to WEF')
ON CONFLICT (q) DO UPDATE SET
  expected_canonical_name = EXCLUDED.expected_canonical_name,
  expected_entity_id = EXCLUDED.expected_entity_id,
  expected_match_type = EXCLUDED.expected_match_type,
  min_confidence = EXCLUDED.min_confidence,
  expected_entity_type = EXCLUDED.expected_entity_type,
  note = EXCLUDED.note,
  updated_at = now();

-- ============================================================
-- WEF ↔ Bill Gates graph edge
-- ============================================================


WITH ids AS (
  SELECT
    (SELECT id FROM ccc.clean_entities WHERE canonical_name = 'WEF' LIMIT 1) AS source_id,
    (SELECT id FROM ccc.clean_entities WHERE canonical_name = '比尔盖茨' LIMIT 1) AS target_id
)
INSERT INTO ccc.clean_graph_edges (
  source_entity_id,
  target_entity_id,
  relation_type,
  weight,
  document_count,
  created_at,
  relation_label,
  relation_direction,
  causal_weight,
  pressure,
  direction,
  updated_at
)
SELECT
  source_id,
  target_id,
  'elite_network_association',
  8.0,
  0,
  now(),
  'WEF associated actor: Bill Gates / global philanthropy-capital network',
  'undirected',
  0.75,
  'governance',
  'agenda_alignment',
  now()
FROM ids
WHERE source_id IS NOT NULL
  AND target_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1
    FROM ccc.clean_graph_edges e
    WHERE e.relation_type = 'elite_network_association'
      AND (
        (e.source_entity_id = ids.source_id AND e.target_entity_id = ids.target_id)
        OR
        (e.source_entity_id = ids.target_id AND e.target_entity_id = ids.source_id)
      )
  );

-- ============================================================
-- Checkpoint rows
-- ============================================================


INSERT INTO ccc.rsal_checkpoints (
  checkpoint_label,
  module,
  note
)
VALUES (
  'SRV3_entity_resolve_v3_local_stable',
  'Search Router v3 Local',
  'Stable checkpoint: multilingual entity resolution. RSAL rule: China/PRC/Chinese government/Beijing/State Council route to canonical 中共. Xi/Trump/Fed/WEF aliases verified. Bill Gates remains separate PERSON and links to WEF through graph edge. Regression PASS=53.'
)
ON CONFLICT (checkpoint_label) DO UPDATE SET
  module = EXCLUDED.module,
  note = EXCLUDED.note;

INSERT INTO ccc.function_snapshots (
  checkpoint_label,
  function_signature,
  function_definition,
  definition_hash
)
SELECT
  'SRV3_entity_resolve_v3_local_stable',
  'ccc.entity_resolve_v3_local(text)',
  pg_get_functiondef('ccc.entity_resolve_v3_local(text)'::regprocedure),
  md5(pg_get_functiondef('ccc.entity_resolve_v3_local(text)'::regprocedure))
ON CONFLICT (checkpoint_label, function_signature) DO UPDATE SET
  function_definition = EXCLUDED.function_definition,
  definition_hash = EXCLUDED.definition_hash,
  created_at = now();

COMMENT ON FUNCTION ccc.entity_resolve_v3_local(text)
IS 'Search Router v3 Local stable entity resolver. Multilingual aliases supported. RSAL rule: China/PRC/Chinese government/Beijing/State Council route to canonical 中共. Xi/Trump/Fed/WEF aliases verified. Bill Gates remains separate PERSON and links to WEF through graph edge. Exact/contained hits suppress fuzzy noise. Regression PASS=53.';

-- Verification:
-- SELECT regression_status, count(*) FROM ccc.entity_resolve_v3_local_regression GROUP BY regression_status;
