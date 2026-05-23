'use client';

import { createClient } from '@supabase/supabase-js';
import { useEffect, useState, useRef } from 'react';

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
);

// ── Types ─────────────────────────────────────────────
interface Score { keyword: number; entity: number; graph: number; confidence: number; final: number; }
interface ResolvedEntity { canonical: string; type: string; confidence: number; match: string; }
interface Contradiction { text: string; alternative: string; severity: string; }
interface Signal { type: string; text: string; strength: number; }
interface Result {
  document_id: number;
  content_preview: string;
  scores: Score;
  resolved_entities: ResolvedEntity[];
  active_signals: Signal[];
  contradictions: Contradiction[];
  sources: string[];
}
interface SearchResponse {
  ok: boolean;
  query: string;
  count: number;
  results: Result[];
}

// ── Helpers ───────────────────────────────────────────
const scoreColor = (v: number) => {
  if (v >= 0.8) return '#00ff9d';
  if (v >= 0.5) return '#ffd166';
  return '#ff6b6b';
};

const severityColor = (s: string) => ({
  strong: '#ff4444',
  moderate: '#ff9900',
  weak: '#888',
}[s] ?? '#888');

const matchLabel: Record<string, string> = {
  alias_exact:  '精确别名',
  alias_fuzzy:  '模糊别名',
  entity_exact: '精确实体',
  entity_fuzzy: '模糊实体',
};

export default function Home() {
  const [user, setUser]         = useState<any>(null);
  const [email, setEmail]       = useState('');
  const [password, setPassword] = useState('');
  const [loading, setLoading]   = useState(false);
  const [message, setMessage]   = useState('');
  const [isRegister, setIsRegister] = useState(false);
  const [q, setQ]               = useState('');
  const [result, setResult]     = useState<SearchResponse | null>(null);
  const [searching, setSearching] = useState(false);
  const [expanded, setExpanded] = useState<number | null>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    supabase.auth.getSession().then(({ data: { session } }) => setUser(session?.user ?? null));
    const { data: { subscription } } = supabase.auth.onAuthStateChange((_e, s) => setUser(s?.user ?? null));
    return () => subscription.unsubscribe();
  }, []);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);
    setMessage('');
    try {
      if (isRegister) {
        const { error } = await supabase.auth.signUp({ email, password, options: { emailRedirectTo: 'https://ccc-lab.vercel.app' } });
        setMessage(error ? error.message : '注册成功，请查邮箱');
      } else {
        const { error } = await supabase.auth.signInWithPassword({ email, password });
        if (error) setMessage(error.message);
      }
    } catch { setMessage('未知错误'); }
    setLoading(false);
  };

  const search = async () => {
    if (!q.trim()) return;
    setSearching(true);
    setResult(null);
    setExpanded(null);
    const res  = await fetch(`/api/search?q=${encodeURIComponent(q)}`);
    const json = await res.json();
    setResult(json);
    setSearching(false);
  };

  const onKey = (e: React.KeyboardEvent) => { if (e.key === 'Enter') search(); };

  // ── Login Page ────────────────────────────────────────
  if (!user) return (
    <main style={S.loginPage}>
      <div style={S.loginBox}>
        <div style={S.loginGlyph}>⬡</div>
        <h1 style={S.loginTitle}>RSAL</h1>
        <p style={S.loginSub}>Reality Survival Analysis Laboratory</p>
        <form onSubmit={handleSubmit} style={S.loginForm}>
          <input style={S.loginInput} value={email}    onChange={e => setEmail(e.target.value)}    placeholder="电子邮件" type="email" />
          <input style={S.loginInput} value={password} onChange={e => setPassword(e.target.value)} placeholder="密码"     type="password" />
          <button style={S.loginBtn} type="submit" disabled={loading}>
            {loading ? '处理中...' : isRegister ? '注册' : '登录'}
          </button>
        </form>
        <p style={S.loginToggle} onClick={() => setIsRegister(!isRegister)}>
          {isRegister ? '已有账号？登录' : '没有账号？注册'}
        </p>
        {message && <p style={S.loginMsg}>{message}</p>}
      </div>
    </main>
  );

  // ── Main App ──────────────────────────────────────────
  return (
    <main style={S.page}>
      {/* Header */}
      <header style={S.header}>
        <div style={S.headerLeft}>
          <span style={S.logo}>⬡ RSAL</span>
          <span style={S.headerSub}>认知情报系统 v3</span>
        </div>
        <div style={S.headerRight}>
          <span style={S.userEmail}>{user.email}</span>
          <button style={S.logoutBtn} onClick={() => supabase.auth.signOut()}>退出</button>
        </div>
      </header>

      {/* Search Bar */}
      <section style={S.searchSection}>
        <div style={S.searchRow}>
          <input
            ref={inputRef}
            style={S.searchInput}
            value={q}
            onChange={e => setQ(e.target.value)}
            onKeyDown={onKey}
            placeholder="输入查询：人名 / 事件 / 拼音 / 绰号..."
            autoFocus
          />
          <button style={S.searchBtn} onClick={search} disabled={searching}>
            {searching ? '···' : '搜索'}
          </button>
        </div>
      </section>

      {/* Results */}
      {searching && <div style={S.loading}><span style={S.loadingDot}>●</span> 正在推理...</div>}

      {result && (
        <section style={S.resultsSection}>

          {/* Meta bar */}
          <div style={S.metaBar}>
            <span style={S.metaQuery}>"{result.query}"</span>
            <span style={S.metaCount}>{result.count} 条结果</span>
          </div>

          {/* Resolved entities */}
          {result.results?.[0]?.resolved_entities?.length > 0 && (
            <div style={S.entityBar}>
              <span style={S.entityBarLabel}>实体解析 →</span>
              {result.results[0].resolved_entities.slice(0, 3).map((e, i) => (
                <span key={i} style={S.entityTag}>
                  <span style={{ color: scoreColor(e.confidence) }}>●</span>
                  &nbsp;{e.canonical}
                  <span style={S.entityMeta}>{matchLabel[e.match] ?? e.match} {(e.confidence * 100).toFixed(0)}%</span>
                </span>
              ))}
            </div>
          )}

          {/* Result cards */}
          {result.results.map((r, i) => (
            <div key={r.document_id} style={{ ...S.card, ...(expanded === i ? S.cardExpanded : {}) }}
              onClick={() => setExpanded(expanded === i ? null : i)}>

              {/* Card header */}
              <div style={S.cardHeader}>
                <div style={S.cardLeft}>
                  <span style={S.cardIdx}>#{String(i + 1).padStart(2, '0')}</span>
                  <span style={S.cardId}>DOC {r.document_id}</span>
                  <div style={S.sourceChips}>
                    {r.sources.map(s => <span key={s} style={S.chip}>{s}</span>)}
                  </div>
                </div>
                <div style={S.cardRight}>
                  <span style={{ ...S.finalScore, color: scoreColor(r.scores.final) }}>
                    {(r.scores.final * 100).toFixed(0)}
                  </span>
                  <span style={S.finalLabel}>分</span>
                </div>
              </div>

              {/* Content preview */}
              <p style={S.preview}>{r.content_preview}</p>

              {/* Score bars */}
              <div style={S.scoreBars}>
                {(['keyword','entity','graph','confidence'] as const).map(k => (
                  <div key={k} style={S.scoreRow}>
                    <span style={S.scoreLabel}>{
                      { keyword:'关键词', entity:'实体', graph:'图谱', confidence:'可信度' }[k]
                    }</span>
                    <div style={S.scoreTrack}>
                      <div style={{ ...S.scoreBar, width: `${r.scores[k] * 100}%`, background: scoreColor(r.scores[k]) }} />
                    </div>
                    <span style={{ ...S.scoreVal, color: scoreColor(r.scores[k]) }}>
                      {(r.scores[k] * 100).toFixed(0)}
                    </span>
                  </div>
                ))}
              </div>

              {/* Expanded: signals + contradictions */}
              {expanded === i && (
                <div style={S.expandedSection}>

                  {r.active_signals.length > 0 && (
                    <div style={S.cogBlock}>
                      <div style={S.cogBlockTitle}>⚡ 风险信号</div>
                      {r.active_signals.map((s, si) => (
                        <div key={si} style={S.cogItem}>
                          <span style={{ ...S.cogBadge, background: '#ff440022', color: '#ff6644' }}>{s.type}</span>
                          <span style={S.cogText}>{s.text}</span>
                          <span style={{ ...S.cogScore, color: scoreColor(s.strength) }}>{(s.strength * 100).toFixed(0)}%</span>
                        </div>
                      ))}
                    </div>
                  )}

                  {r.contradictions.length > 0 && (
                    <div style={S.cogBlock}>
                      <div style={S.cogBlockTitle}>⊘ 反证层</div>
                      {r.contradictions.map((c, ci) => (
                        <div key={ci} style={S.cogItem}>
                          <span style={{ ...S.cogBadge, background: severityColor(c.severity) + '22', color: severityColor(c.severity) }}>{c.severity}</span>
                          <div style={{ flex: 1 }}>
                            <div style={S.cogText}>{c.text}</div>
                            {c.alternative && <div style={S.cogAlt}>替代解释：{c.alternative}</div>}
                          </div>
                        </div>
                      ))}
                    </div>
                  )}

                  {r.active_signals.length === 0 && r.contradictions.length === 0 && (
                    <div style={S.cogEmpty}>暂无风险信号或反证记录</div>
                  )}
                </div>
              )}

              <div style={S.cardFooter}>
                <span style={S.expandHint}>{expanded === i ? '收起 ▲' : '展开详情 ▼'}</span>
              </div>
            </div>
          ))}
        </section>
      )}
    </main>
  );
}

// ── Styles ────────────────────────────────────────────
const S: Record<string, React.CSSProperties> = {
  // Login
  loginPage:   { minHeight:'100vh', background:'#080808', display:'flex', alignItems:'center', justifyContent:'center', fontFamily:"'Courier New', monospace" },
  loginBox:    { width:360, padding:'48px 40px', border:'1px solid #222', background:'#0e0e0e' },
  loginGlyph:  { fontSize:32, color:'#00ff9d', display:'block', marginBottom:8 },
  loginTitle:  { margin:'0 0 4px', fontSize:28, fontWeight:700, letterSpacing:8, color:'#fff' },
  loginSub:    { margin:'0 0 32px', fontSize:11, color:'#555', letterSpacing:2, textTransform:'uppercase' },
  loginForm:   { display:'flex', flexDirection:'column', gap:12 },
  loginInput:  { background:'#111', border:'1px solid #2a2a2a', color:'#ccc', padding:'10px 14px', fontSize:14, fontFamily:"'Courier New', monospace", outline:'none' },
  loginBtn:    { background:'#00ff9d', color:'#000', border:'none', padding:'12px', fontSize:13, fontWeight:700, letterSpacing:2, cursor:'pointer', textTransform:'uppercase' },
  loginToggle: { marginTop:20, fontSize:12, color:'#444', cursor:'pointer', textAlign:'center' },
  loginMsg:    { marginTop:12, fontSize:12, color:'#ff6b6b', textAlign:'center' },

  // App
  page:        { minHeight:'100vh', background:'#080808', color:'#ccc', fontFamily:"'Courier New', monospace" },

  // Header
  header:      { display:'flex', justifyContent:'space-between', alignItems:'center', padding:'16px 32px', borderBottom:'1px solid #181818' },
  headerLeft:  { display:'flex', alignItems:'baseline', gap:16 },
  logo:        { fontSize:18, fontWeight:700, color:'#00ff9d', letterSpacing:4 },
  headerSub:   { fontSize:11, color:'#444', letterSpacing:2 },
  headerRight: { display:'flex', alignItems:'center', gap:16 },
  userEmail:   { fontSize:11, color:'#444' },
  logoutBtn:   { background:'transparent', border:'1px solid #222', color:'#555', padding:'4px 12px', fontSize:11, cursor:'pointer', letterSpacing:1 },

  // Search
  searchSection: { padding:'32px 32px 0' },
  searchRow:   { display:'flex', gap:0, maxWidth:800 },
  searchInput: { flex:1, background:'#0e0e0e', border:'1px solid #2a2a2a', borderRight:'none', color:'#fff', padding:'14px 20px', fontSize:15, fontFamily:"'Courier New', monospace", outline:'none' },
  searchBtn:   { background:'#00ff9d', color:'#000', border:'none', padding:'14px 28px', fontSize:13, fontWeight:700, cursor:'pointer', letterSpacing:2, whiteSpace:'nowrap' },

  // Loading
  loading:     { padding:'40px 32px', color:'#444', fontSize:13, letterSpacing:2 },
  loadingDot:  { color:'#00ff9d', animation:'pulse 1s infinite' },

  // Results
  resultsSection: { padding:'24px 32px', maxWidth:900 },
  metaBar:     { display:'flex', justifyContent:'space-between', alignItems:'center', marginBottom:16, paddingBottom:12, borderBottom:'1px solid #151515' },
  metaQuery:   { color:'#555', fontSize:13 },
  metaCount:   { color:'#333', fontSize:11, letterSpacing:2 },

  // Entity bar
  entityBar:   { display:'flex', alignItems:'center', flexWrap:'wrap', gap:10, marginBottom:20, padding:'10px 14px', background:'#0d0d0d', border:'1px solid #1a1a1a' },
  entityBarLabel: { fontSize:10, color:'#444', letterSpacing:2, textTransform:'uppercase' },
  entityTag:   { display:'flex', alignItems:'center', gap:6, padding:'4px 10px', background:'#111', border:'1px solid #1e1e1e', fontSize:12 },
  entityMeta:  { color:'#444', fontSize:10, marginLeft:4 },

  // Cards
  card:        { marginBottom:12, padding:'20px', background:'#0c0c0c', border:'1px solid #181818', cursor:'pointer', transition:'border-color 0.15s' },
  cardExpanded: { border:'1px solid #2a2a2a' },
  cardHeader:  { display:'flex', justifyContent:'space-between', alignItems:'flex-start', marginBottom:12 },
  cardLeft:    { display:'flex', alignItems:'center', gap:12, flexWrap:'wrap' },
  cardIdx:     { color:'#333', fontSize:11, fontWeight:700, letterSpacing:2 },
  cardId:      { color:'#444', fontSize:11 },
  cardRight:   { display:'flex', alignItems:'baseline', gap:4 },
  finalScore:  { fontSize:28, fontWeight:700, lineHeight:1 },
  finalLabel:  { fontSize:11, color:'#444' },

  sourceChips: { display:'flex', gap:6 },
  chip:        { padding:'2px 8px', background:'#141414', border:'1px solid #202020', fontSize:10, color:'#555', letterSpacing:1 },

  preview:     { margin:'0 0 16px', fontSize:13, lineHeight:1.7, color:'#777', borderLeft:'2px solid #1a1a1a', paddingLeft:12 },

  // Score bars
  scoreBars:   { display:'flex', flexDirection:'column', gap:6 },
  scoreRow:    { display:'flex', alignItems:'center', gap:10 },
  scoreLabel:  { width:48, fontSize:10, color:'#444', letterSpacing:1, textAlign:'right' },
  scoreTrack:  { flex:1, height:3, background:'#151515' },
  scoreBar:    { height:'100%', transition:'width 0.4s ease' },
  scoreVal:    { width:28, fontSize:10, textAlign:'right' },

  // Expanded
  expandedSection: { marginTop:20, paddingTop:16, borderTop:'1px solid #151515' },
  cogBlock:    { marginBottom:16 },
  cogBlockTitle: { fontSize:10, color:'#555', letterSpacing:2, textTransform:'uppercase', marginBottom:8 },
  cogItem:     { display:'flex', alignItems:'flex-start', gap:10, marginBottom:8, padding:'8px 10px', background:'#0a0a0a', border:'1px solid #141414' },
  cogBadge:    { padding:'2px 8px', fontSize:10, letterSpacing:1, whiteSpace:'nowrap', flexShrink:0 },
  cogText:     { fontSize:12, color:'#777', lineHeight:1.6, flex:1 },
  cogAlt:      { fontSize:11, color:'#555', marginTop:4, fontStyle:'italic' },
  cogScore:    { fontSize:11, fontWeight:700, flexShrink:0 },
  cogEmpty:    { fontSize:11, color:'#333', letterSpacing:1, textAlign:'center', padding:'16px 0' },

  cardFooter:  { marginTop:14, textAlign:'right' },
  expandHint:  { fontSize:10, color:'#333', letterSpacing:1 },
};
