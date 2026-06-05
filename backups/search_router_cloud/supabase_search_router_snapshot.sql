-- Supabase Search Router Cloud Snapshot
-- Source: Supabase ccc schema
-- Purpose: backup production search RPC definitions

CREATE SCHEMA IF NOT EXISTS ccc;

-- ============================================================
-- Explicit RPC functions
-- ============================================================

-- Function: ccc.entity_resolve(text)
CREATE OR REPLACE FUNCTION ccc.entity_resolve(query_text text)
 RETURNS TABLE(canonical_name text, entity_id bigint, match_type text, confidence double precision, entity_type text)
 LANGUAGE sql
 STABLE
AS $function$
  SELECT * FROM (
    SELECT 
      pa.canonical, e.id, 'alias_exact'::text, 1.0::float,
      COALESCE(e.entity_type, 'PERSON')
    FROM ccc.person_aliases pa
    LEFT JOIN ccc.entities e ON lower(e.canonical_name) = lower(pa.canonical)
    WHERE lower(pa.alias) = lower(query_text)

    UNION ALL

    SELECT DISTINCT
      se.canonical_name, NULL::bigint, 'staging_exact'::text, 0.95::float,
      se.entity_type
    FROM ccc.staging_entities se
    WHERE lower(se.canonical_name) = lower(query_text)
      AND se.entity_type IN ('PERSON','ORG','GPE','EVENT','FAC')
      AND length(se.canonical_name) <= 20

    UNION ALL

    SELECT 
      e.canonical_name, e.id, 'entity_exact'::text, 0.9::float,
      COALESCE(e.entity_type, 'unknown')
    FROM ccc.entities e
    WHERE lower(e.canonical_name) = lower(query_text)
      AND length(e.canonical_name) <= 20

    UNION ALL

    SELECT 
      pa.canonical, e.id, 'alias_fuzzy'::text,
      similarity(lower(pa.alias), lower(query_text))::float,
      COALESCE(e.entity_type, 'PERSON')
    FROM ccc.person_aliases pa
    LEFT JOIN ccc.entities e ON lower(e.canonical_name) = lower(pa.canonical)
    WHERE similarity(lower(pa.alias), lower(query_text)) > 0.4

    UNION ALL

    SELECT DISTINCT
      se.canonical_name, NULL::bigint, 'staging_fuzzy'::text,
      similarity(se.canonical_name, query_text)::float,
      se.entity_type
    FROM ccc.staging_entities se
    WHERE similarity(se.canonical_name, query_text) > 0.5
      AND se.entity_type IN ('PERSON','ORG','GPE','EVENT','FAC')
      AND length(se.canonical_name) <= 20
  ) sub
  ORDER BY 4 DESC
  LIMIT 5;
$function$
;

-- Function: ccc.entity_graph_expand(bigint,integer,double precision)
CREATE OR REPLACE FUNCTION ccc.entity_graph_expand(seed_entity_id bigint, max_hops integer DEFAULT 1, min_weight double precision DEFAULT 1.0)
 RETURNS TABLE(entity_id bigint, canonical_name text, relation text, weight numeric, hop integer)
 LANGUAGE sql
 STABLE
AS $function$
  -- 一跳扩展（当前只做1跳，够用且快）
  SELECT 
    e.id            AS entity_id,
    e.canonical_name,
    ge.relation,
    ge.weight,
    1               AS hop
  FROM ccc.graph_edges ge
  JOIN ccc.entities e 
    ON (ge.target_entity_id = e.id AND ge.source_entity_id = seed_entity_id)
    OR (ge.source_entity_id = e.id AND ge.target_entity_id = seed_entity_id)
  WHERE ge.weight >= min_weight
    AND length(e.canonical_name) <= 20  -- 同样过滤噪音
  ORDER BY ge.weight DESC
  LIMIT 20;
$function$
;

-- Function: ccc.entity_intelligence(text)
CREATE OR REPLACE FUNCTION ccc.entity_intelligence(p_entity_name text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_result         jsonb;
  v_profile        jsonb;
  v_trajectory     jsonb;
  v_signals        jsonb;
  v_contradictions jsonb;
  v_behaviors      jsonb;
BEGIN
  SELECT jsonb_build_object(
    'essence',       ep.essence,
    'survival_mode', ep.survival_mode,
    'core_drives',   ep.core_drives,
    'mirror_bias',   ep.mirror_bias,
    'confidence',    ep.confidence
  ) INTO v_profile
  FROM ccc.entity_profiles ep
  WHERE lower(ep.entity_name) = lower(p_entity_name)
  LIMIT 1;

  SELECT jsonb_build_object(
    'trajectory_status',     et.trajectory_status,
    'pressure',              et.pressure,
    'pressure_trend',        et.pressure_trend,
    'risk_level',            et.risk_level,
    'short_term_prediction', et.short_term_prediction,
    'key_drivers',           et.key_drivers,
    'next_possible_events',  et.next_possible_events
  ) INTO v_trajectory
  FROM ccc.entity_trajectories et
  JOIN ccc.entity_profiles ep ON ep.id = et.entity_profile_id
  WHERE lower(ep.entity_name) = lower(p_entity_name)
  ORDER BY et.snapshot_date DESC
  LIMIT 1;

  SELECT jsonb_agg(sig) INTO v_signals
  FROM (
    SELECT jsonb_build_object(
      'type',     s.signal_type,
      'text',     s.signal_text,
      'strength', s.strength,
      'trigger',  s.trigger_condition
    ) AS sig
    FROM ccc.signals s
    JOIN ccc.clean_entities ce ON ce.id = s.entity_id
    WHERE lower(ce.canonical_name) = lower(p_entity_name)
      AND s.is_active = true
    ORDER BY s.strength DESC
  ) sub;

  SELECT jsonb_agg(con) INTO v_contradictions
  FROM (
    SELECT jsonb_build_object(
      'narrative',       ce.official_narrative,
      'gap',             ce.narrative_gap,
      'severity',        ce.severity,
      'counter_signals', ce.counter_signals
    ) AS con
    FROM ccc.contradiction_engine ce
    WHERE lower(ce.entity_name) = lower(p_entity_name)
      AND ce.is_active = true
    ORDER BY ce.narrative_gap DESC
  ) sub;

  SELECT jsonb_agg(beh) INTO v_behaviors
  FROM (
    SELECT jsonb_build_object(
      'triggers',   bm.trigger_conditions,
      'prediction', bm.predicted_action,
      'type',       bm.action_type,
      'confidence', bm.confidence,
      'horizon',    bm.time_horizon
    ) AS beh
    FROM ccc.behavioral_models bm
    JOIN ccc.entity_profiles ep ON ep.id = bm.entity_profile_id
    WHERE lower(ep.entity_name) = lower(p_entity_name)
    ORDER BY bm.confidence DESC
    LIMIT 3
  ) sub;

  v_result := jsonb_build_object(
    'entity',         p_entity_name,
    'profile',        COALESCE(v_profile,        '{}'::jsonb),
    'trajectory',     COALESCE(v_trajectory,     '{}'::jsonb),
    'active_signals', COALESCE(v_signals,        '[]'::jsonb),
    'contradictions', COALESCE(v_contradictions, '[]'::jsonb),
    'top_behaviors',  COALESCE(v_behaviors,      '[]'::jsonb),
    'generated_at',   now()
  );

  RETURN v_result;
END;
$function$
;

-- Function: ccc.search_router(text)
CREATE OR REPLACE FUNCTION ccc.search_router(q text)
 RETURNS json
 LANGUAGE plpgsql
AS $function$
DECLARE
  result json;
BEGIN

  SELECT json_build_object(

    'documents',
    (
      SELECT json_agg(t)
      FROM (
        SELECT document_id, preview, rank_score
        FROM ccc.search_keyword_preview(q, 10)
      ) t
    ),

    'entities',
    (
      SELECT json_agg(e)
      FROM (
        SELECT id, canonical_name
        FROM ccc.entities
        WHERE canonical_name ILIKE '%' || q || '%'
        LIMIT 10
      ) e
    ),

    'events',
    (
      SELECT json_agg(ev)
      FROM (
        SELECT person_name, event_summary, event_date
        FROM ccc.event_dashboard
        WHERE event_summary ILIKE '%' || q || '%'
        LIMIT 10
      ) ev
    )

  ) INTO result;

  RETURN result;

END;
$function$
;

-- Function: ccc.search_router_v2(text)
CREATE OR REPLACE FUNCTION ccc.search_router_v2(q text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare
  result jsonb;
begin

  select jsonb_build_object(

    -- =====================================
    -- keyword layer
    -- =====================================
    'keyword',
    (
      select jsonb_agg(t)
      from (
        select
          id,
          left(content, 300) as content,
          greatest(
            similarity(content, q),
            case
              when content ilike '%' || q || '%'
              then 1.0
              else 0.0
            end
          ) as score
        from ccc.documents
        where
          content ilike '%' || q || '%'
          or similarity(content, q) > 0.005
        order by score desc
        limit 10
      ) t
    ),

    -- =====================================
    -- vector layer
    -- =====================================
    'vector',
    (
      select jsonb_agg(v)
      from (
        select
          id,
          left(content, 300) as content,
          1 - (embedding <=> ccc.openai_embed_text(q)) as score
        from ccc.documents
        where embedding is not null
        order by embedding <=> ccc.openai_embed_text(q)
        limit 10
      ) v
    ),

    -- =====================================
    -- graph layer
    -- =====================================
    'graph',
    (
      select jsonb_agg(g)
      from (
        select
          e.id,
          e.relation,
          e.weight
        from ccc.graph_edges e
        order by e.weight desc
        limit 10
      ) g
    )

  )
  into result;

  return result;

end;
$function$
;

-- Function: ccc.search_router_v3(text)
CREATE OR REPLACE FUNCTION ccc.search_router_v3(q text)
 RETURNS TABLE(document_id bigint, content_preview text, keyword_score double precision, entity_score double precision, graph_score double precision, confidence_score double precision, signal_boost double precision, final_score double precision, resolved_entities jsonb, active_signals jsonb, contradictions jsonb, sources text[])
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_clean_ids   bigint[];
  v_resolved    jsonb := '[]'::jsonb;
  v_canonicals  text[] := ARRAY[]::text[];
  v_aliases     text[] := ARRAY[]::text[];
  v_has_kw      boolean := false;
BEGIN

  SELECT array_agg(DISTINCT er.canonical_name)
  INTO v_canonicals
  FROM ccc.entity_resolve(q) er
  WHERE er.canonical_name IS NOT NULL;
  v_canonicals := COALESCE(v_canonicals, ARRAY[]::text[]);

  SELECT array_agg(DISTINCT ce.id)
  INTO v_clean_ids
  FROM ccc.clean_entities ce
  WHERE lower(ce.canonical_name) = ANY(
    SELECT lower(c) FROM unnest(v_canonicals) c
  );
  v_clean_ids := COALESCE(v_clean_ids, ARRAY[]::bigint[]);

  SELECT jsonb_agg(jsonb_build_object(
    'canonical', er.canonical_name,
    'type',      er.entity_type,
    'confidence',er.confidence,
    'match',     er.match_type
  ))
  INTO v_resolved
  FROM ccc.entity_resolve(q) er;
  v_resolved := COALESCE(v_resolved, '[]'::jsonb);

  SELECT array_agg(DISTINCT pa.alias)
  INTO v_aliases
  FROM ccc.aliases_safe pa
  WHERE pa.canonical = ANY(v_canonicals);
  v_aliases := COALESCE(v_aliases, ARRAY[]::text[]);

  SELECT EXISTS(
    SELECT 1 FROM ccc.documents d
    WHERE d.content ILIKE '%' || q || '%' LIMIT 1
  ) INTO v_has_kw;

  RETURN QUERY
  WITH
  kw AS (
    SELECT d.id AS doc_id, LEFT(d.content, 200) AS preview, 1.0::float AS kw_score
    FROM ccc.documents d
    WHERE d.content ILIKE '%' || q || '%'
    LIMIT 30
  ),
  alias_docs AS (
    SELECT DISTINCT d.id AS doc_id, LEFT(d.content, 200) AS preview, 0.85::float AS alias_score
    FROM ccc.documents d
    WHERE EXISTS (SELECT 1 FROM unnest(v_canonicals) c WHERE d.content ILIKE '%' || c || '%')
       OR EXISTS (SELECT 1 FROM unnest(v_aliases) a WHERE d.content ILIKE '%' || a || '%')
    LIMIT 50
  ),
  ent AS (
    SELECT cde.document_id AS doc_id, SUM(cde.frequency)::float AS ent_raw
    FROM ccc.clean_document_entities cde
    WHERE cde.entity_id = ANY(v_clean_ids)
    GROUP BY cde.document_id
  ),
  ent_max AS (
    SELECT GREATEST(MAX(ent_raw), 0.0001) AS max_val FROM ent
  ),
  mention AS (
    SELECT dem.document_id AS doc_id,
           LEAST(LOG(SUM(dem.mention_count) + 1) / LOG(400)::float, 1.0) AS mention_score
    FROM ccc.doc_entity_mentions dem
    WHERE dem.canonical_name = ANY(v_canonicals)
    GROUP BY dem.document_id
  ),
  graph_neighbors AS (
    SELECT DISTINCT
      CASE
        WHEN cge.source_entity_id = ANY(v_clean_ids) THEN cge.target_entity_id
        ELSE cge.source_entity_id
      END AS neighbor_id,
      cge.weight
    FROM ccc.clean_graph_edges cge
    WHERE cge.source_entity_id = ANY(v_clean_ids)
       OR cge.target_entity_id = ANY(v_clean_ids)
    ORDER BY cge.weight DESC
    LIMIT 20
  ),
  graph_docs AS (
    SELECT cde.document_id AS doc_id,
           LEAST(MAX(gn.weight) / 10.0, 1.0)::float AS gr_score
    FROM ccc.clean_document_entities cde
    JOIN graph_neighbors gn ON cde.entity_id = gn.neighbor_id
    GROUP BY cde.document_id
  ),
  cog AS (
    SELECT cn.document_id AS doc_id,
           AVG(ccc.effective_confidence(cn.confidence, cn.decay_rate, cn.created_at))::float AS cog_score
    FROM ccc.cognitive_nodes cn
    WHERE cn.document_id IS NOT NULL
    GROUP BY cn.document_id
  ),
  contra AS (
    SELECT cn.document_id AS doc_id,
           jsonb_agg(jsonb_build_object(
             'text',        ct.contradiction,
             'alternative', ct.alternative_model,
             'severity',    ct.severity
           )) AS contra_json
    FROM ccc.contradictions ct
    JOIN ccc.cognitive_nodes cn ON ct.node_id = cn.id
    WHERE cn.document_id IS NOT NULL
    GROUP BY cn.document_id
  ),
  all_docs AS (
    SELECT doc_id FROM kw
    UNION SELECT doc_id FROM alias_docs
    UNION SELECT doc_id FROM ent
    UNION SELECT doc_id FROM graph_docs
    UNION SELECT doc_id FROM mention
  ),
  fused AS (
    SELECT
      ad.doc_id,
      COALESCE(kw.preview, al.preview, LEFT(d2.content, 200)) AS preview,
      COALESCE(kw.kw_score,      0.0) AS kw_s,
      COALESCE(ent.ent_raw / em.max_val, 0.0) AS ent_s,
      COALESCE(gd.gr_score,      0.0) AS gr_s,
      COALESCE(cog.cog_score,    0.5) AS cog_s,
      COALESCE(mn.mention_score, 0.0) AS mn_s,
      COALESCE(al.alias_score,   0.0) AS al_s,
      ARRAY_REMOVE(ARRAY[
        CASE WHEN kw.kw_score    IS NOT NULL THEN 'keyword'   END,
        CASE WHEN al.alias_score IS NOT NULL THEN 'alias'     END,
        CASE WHEN ent.ent_raw    IS NOT NULL THEN 'entity'    END,
        CASE WHEN mn.mention_score IS NOT NULL THEN 'mention' END,
        CASE WHEN gd.gr_score    IS NOT NULL THEN 'graph'     END,
        CASE WHEN cog.cog_score  IS NOT NULL THEN 'cognitive' END
      ], NULL) AS src
    FROM all_docs ad
    CROSS JOIN ent_max em
    LEFT JOIN kw            ON kw.doc_id   = ad.doc_id
    LEFT JOIN alias_docs al ON al.doc_id   = ad.doc_id
    LEFT JOIN ent           ON ent.doc_id  = ad.doc_id
    LEFT JOIN mention mn    ON mn.doc_id   = ad.doc_id
    LEFT JOIN graph_docs gd ON gd.doc_id   = ad.doc_id
    LEFT JOIN cog           ON cog.doc_id  = ad.doc_id
    LEFT JOIN ccc.documents d2 ON d2.id    = ad.doc_id
  )
  SELECT
    f.doc_id,
    f.preview,
    f.kw_s,
    f.ent_s,
    f.gr_s,
    f.cog_s,
    -- 信号激活层
    LEAST(ccc.signal_boost(f.doc_id), 0.3) AS sig_boost,
    -- 最终分：加入信号激活权重
    LEAST((
      f.kw_s  * 0.20 +
      f.al_s  * 0.10 +
      f.ent_s * 0.15 +
      f.mn_s  * 0.25 +
      f.gr_s  * 0.10 +
      f.cog_s * 0.05 +
      LEAST(ccc.signal_boost(f.doc_id), 0.3) * 0.15
    ), 1.0)::float AS final_s,
    v_resolved,
    COALESCE('[]'::jsonb, '[]'::jsonb),
    COALESCE(contra.contra_json, '[]'::jsonb),
    f.src
  FROM fused f
  LEFT JOIN contra ON contra.doc_id = f.doc_id
  ORDER BY final_s DESC
  LIMIT 15;

END;
$function$
;

-- ============================================================
-- Optional dependency functions by name
-- ============================================================

-- Function: effective_confidence(double precision,double precision,timestamp with time zone)
CREATE OR REPLACE FUNCTION ccc.effective_confidence(base_confidence double precision, decay_rate double precision, created_at timestamp with time zone)
 RETURNS double precision
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT GREATEST(
    0.05,  -- 最低可信度底线
    base_confidence * EXP(
      -decay_rate * EXTRACT(EPOCH FROM (now() - created_at)) / 86400.0
    )
  );
$function$
;

-- Function: search_ai(text,boolean)
CREATE OR REPLACE FUNCTION ccc.search_ai(q text, use_embedding boolean DEFAULT true)
 RETURNS TABLE(document_id bigint, content text, score double precision, method text)
 LANGUAGE plpgsql
AS $function$
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
$function$
;

-- Function: search_keyword(text)
CREATE OR REPLACE FUNCTION ccc.search_keyword(keyword text)
 RETURNS TABLE(document_id bigint, content text, rank_score real)
 LANGUAGE plpgsql
 STABLE
AS $function$
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
$function$
;

-- Function: search_vector(vector,integer)
CREATE OR REPLACE FUNCTION ccc.search_vector(query_embedding vector, match_count integer DEFAULT 10)
 RETURNS TABLE(document_id bigint, content text, similarity numeric)
 LANGUAGE sql
AS $function$
    SELECT
        id,
        left(content, 800),
        1 - (embedding <=> query_embedding)
    FROM ccc.documents
    WHERE embedding IS NOT NULL
    ORDER BY embedding <=> query_embedding
    LIMIT match_count;
$function$
;

-- Function: signal_boost(bigint)
CREATE OR REPLACE FUNCTION ccc.signal_boost(p_document_id bigint)
 RETURNS double precision
 LANGUAGE sql
 STABLE
AS $function$
  SELECT COALESCE(
    SUM(
      s.strength * 
      CASE s.signal_type
        WHEN 'narrative_collapse'  THEN 0.40
        WHEN 'critical_pressure'   THEN 0.35
        WHEN 'narrative_divergence' THEN 0.25
        WHEN 'elevated_pressure'   THEN 0.20
        WHEN 'narrative_gap'       THEN 0.10
        WHEN 'normal_pressure'     THEN 0.05
        ELSE 0.05
      END
    ), 0.0
  )
  FROM ccc.signals s
  JOIN ccc.clean_entities ce ON ce.id = s.entity_id
  JOIN ccc.clean_document_entities cde ON cde.entity_id = ce.id
  WHERE cde.document_id = p_document_id
    AND s.is_active = true
    AND (s.expires_at IS NULL OR s.expires_at > now());
$function$
;

-- Function: vector_search(vector,integer,double precision)
CREATE OR REPLACE FUNCTION ccc.vector_search(query_embedding vector, match_count integer DEFAULT 10, min_similarity double precision DEFAULT 0.3)
 RETURNS TABLE(document_id bigint, content text, similarity double precision)
 LANGUAGE sql
 STABLE
AS $function$
  SELECT
    d.id,
    d.content,
    1 - (d.embedding <=> query_embedding) AS similarity
  FROM ccc.documents d
  WHERE d.embedding IS NOT NULL
    AND 1 - (d.embedding <=> query_embedding) >= min_similarity
  ORDER BY d.embedding <=> query_embedding
  LIMIT match_count;
$function$
;

-- ============================================================
-- Related views
-- ============================================================

CREATE OR REPLACE VIEW ccc.aliases_safe AS
 SELECT canonical,
    alias,
    alias_type
   FROM person_aliases
  WHERE ((length(alias) >= 3) AND (alias <> ALL (ARRAY['the'::text, 'and'::text, 'for'::text, 'xi'::text])));;

