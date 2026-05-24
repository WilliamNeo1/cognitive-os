'use client';

import { createClient } from '@supabase/supabase-js';
import { useEffect, useState } from 'react';

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
);

interface ScoreMap { keyword: number; entity: number; graph: number; confidence: number; final: number; }
interface ResolvedEntity { canonical: string; type: string; confidence: number; match: string; }
interface Contradiction { text: string; alternative: string; severity: string; }
interface Signal { type: string; text: string; strength: number; }
interface Result {
  document_id: number;
  content_preview: string;
  scores: ScoreMap;
  resolved_entities: ResolvedEntity[];
  active_signals: Signal[];
  contradictions: Contradiction[];
  sources: string[];
}

const matchLabel: Record<string, string> = {
  alias_exact: '精确别名', alias_fuzzy: '模糊别名',
  entity_exact: '精确实体', entity_fuzzy: '模糊实体',
};

function scoreColor(v: number) {
  if (v >= 0.8) return '#00ff9d';
  if (v >= 0.5) return '#ffd166';
  return '#ff6b6b';
}

function ScoreBar({ label, value }: { label: string; value: number }) {
  const pct = Math.round(value * 100);
  const color = scoreColor(value);
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 4 }}>
      <span style={{ width: 48, fontSize: 10, color: '#444', textAlign: 'right' }}>{label}</span>
      <div style={{ flex: 1, height: 3, background: '#151515' }}>
        <div style={{ height: '100%', width: `${pct}%`, background: color }} />
      </div>
      <span style={{ width: 28, fontSize: 10, color, textAlign: 'right' }}>{pct}</span>
    </div>
  );
}

function ResultCard({ r, index }: { r: Result; index: number }) {
  const [open, setOpen] = useState(false);
  const finalPct = Math.round((r.scores?.final ?? 0) * 100);
  const color = scoreColor(r.scores?.final ?? 0);
  return (
    <div onClick={() => setOpen(!open)} style={{ marginBottom: 12, padding: 20, background: '#0c0c0c', border: open ? '1px solid #2a2a2a' : '1px solid #181818', cursor: 'pointer' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 12 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 12, flexWrap: 'wrap' }}>
          <span style={{ color: '#333', fontSize: 11, fontWeight: 700, letterSpacing: 2 }}>#{String(index + 1).padStart(2, '0')}</span>
          <span style={{ color: '#444', fontSize: 11 }}>DOC {r.document_id}</span>
          <div style={{ display: 'flex', gap: 6 }}>
            {(r.sources ?? []).map((s: string) => (
              <span key={s} style={{ padding: '2px 8px', background: '#141414', border: '1px solid #202020', fontSize: 10, color: '#555' }}>{s}</span>
            ))}
          </div>
        </div>
        <div style={{ display: 'flex', alignItems: 'baseline', gap: 4 }}>
          <span style={{ fontSize: 28, fontWeight: 700, color, lineHeight: 1 }}>{finalPct}</span>
          <span style={{ fontSize: 11, color: '#444' }}>分</span>
        </div>
      </div>
      <p style={{ margin: '0 0 16px', fontSize: 13, lineHeight: 1.7, color: '#777', borderLeft: '2px solid #1a1a1a', paddingLeft: 12 }}>{r.content_preview}</p>
      <ScoreBar label="关键词" value={r.scores?.keyword ?? 0} />
      <ScoreBar label="实体"   value={r.scores?.entity   ?? 0} />
      <ScoreBar label="图谱"   value={r.scores?.graph    ?? 0} />
      <ScoreBar label="可信度" value={r.scores?.confidence ?? 0.5} />
      {open && (
        <div style={{ marginTop: 20, paddingTop: 16, borderTop: '1px solid #151515' }}>
          {(r.active_signals ?? []).length > 0 && (
            <div style={{ marginBottom: 16 }}>
              <div style={{ fontSize: 10, color: '#555', letterSpacing: 2, marginBottom: 8 }}>⚡ 风险信号</div>
              {r.active_signals.map((s: Signal, i: number) => (
                <div key={i} style={{ display: 'flex', gap: 10, marginBottom: 8, padding: '8px 10px', background: '#0a0a0a', border: '1px solid #141414' }}>
                  <span style={{ padding: '2px 8px', fontSize: 10, background: '#ff440022', color: '#ff6644' }}>{s.type}</span>
                  <span style={{ fontSize: 12, color: '#777', flex: 1 }}>{s.text}</span>
                </div>
              ))}
            </div>
          )}
          {(r.contradictions ?? []).length > 0 && (
            <div style={{ marginBottom: 16 }}>
              <div style={{ fontSize: 10, color: '#555', letterSpacing: 2, marginBottom: 8 }}>⊘ 反证层</div>
              {r.contradictions.map((c: Contradiction, i: number) => (
                <div key={i} style={{ display: 'flex', gap: 10, marginBottom: 8, padding: '8px 10px', background: '#0a0a0a', border: '1px solid #141414' }}>
                  <span style={{ padding: '2px 8px', fontSize: 10, background: '#44444422', color: '#888' }}>{c.severity}</span>
                  <div style={{ flex: 1 }}>
                    <div style={{ fontSize: 12, color: '#777' }}>{c.text}</div>
                    {c.alternative && <div style={{ fontSize: 11, color: '#555', marginTop: 4, fontStyle: 'italic' }}>替代解释：{c.alternative}</div>}
                  </div>
                </div>
              ))}
            </div>
          )}
          {(r.active_signals ?? []).length === 0 && (r.contradictions ?? []).length === 0 && (
            <div style={{ fontSize: 11, color: '#333', textAlign: 'center', padding: '16px 0' }}>暂无风险信号或反证记录</div>
          )}
        </div>
      )}
      <div style={{ marginTop: 14, textAlign: 'right' }}>
        <span style={{ fontSize: 10, color: '#333' }}>{open ? '收起 ▲' : '展开详情 ▼'}</span>
      </div>
    </div>
  );
}

export default function Home() {
  const [user, setUser]         = useState<any>(null);
  const [authReady, setAuthReady] = useState(false);
  const [email, setEmail]       = useState('');
  const [password, setPassword] = useState('');
  const [loading, setLoading]   = useState(false);
  const [message, setMessage]   = useState('');
  const [isRegister, setIsRegister] = useState(false);
  const [q, setQ]               = useState('');
  const [results, setResults]   = useState<Result[]>([]);
  const [meta, setMeta]         = useState<{ query: string; count: number } | null>(null);
  const [searching, setSearching] = useState(false);
  const [entities, setEntities] = useState<ResolvedEntity[]>([]);

  useEffect(() => {
    supabase.auth.getSession().then(({ data: { session } }) => {
      setUser(session?.user ?? null);
      setAuthReady(true);
    });
    const { data: { subscription } } = supabase.auth.onAuthStateChange((_e, s) => {
      setUser(s?.user ?? null);
      setAuthReady(true);
    });
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
    setResults([]);
    setMeta(null);
    setEntities([]);
    try {
      const res  = await fetch(`/api/search?q=${encodeURIComponent(q)}`);
      const json = await res.json();
      if (json.ok && Array.isArray(json.results)) {
        setResults(json.results);
        setMeta({ query: json.query, count: json.count });
        const first = json.results[0];
        if (first?.resolved_entities?.length) {
          setEntities(first.resolved_entities.slice(0, 4));
        }
      }
    } catch (err) {
      console.error(err);
    }
    setSearching(false);
  };

  if (!authReady) return (
    <main style={{ minHeight: '100vh', background: '#080808', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
      <span style={{ color: '#00ff9d', fontFamily: 'monospace' }}>⬡</span>
    </main>
  );

  if (!user) return (
    <main style={{ minHeight: '100vh', background: '#080808', display: 'flex', alignItems: 'center', justifyContent: 'center', fontFamily: "'Courier New', monospace" }}>
      <div style={{ width: 360, padding: '48px 40px', border: '1px solid #222', background: '#0e0e0e' }}>
        <div style={{ fontSize: 32, color: '#00ff9d', marginBottom: 8 }}>⬡</div>
        <h1 style={{ margin: '0 0 4px', fontSize: 28, fontWeight: 700, letterSpacing: 8, color: '#fff' }}>RSAL</h1>
        <p style={{ margin: '0 0 32px', fontSize: 11, color: '#555', letterSpacing: 2 }}>Reality Survival Analysis Laboratory</p>
        <form onSubmit={handleSubmit} style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
          <input style={{ background: '#111', border: '1px solid #2a2a2a', color: '#ccc', padding: '10px 14px', fontSize: 14, fontFamily: 'inherit', outline: 'none' }}
            value={email} onChange={e => setEmail(e.target.value)} placeholder="电子邮件" type="email" />
          <input style={{ background: '#111', border: '1px solid #2a2a2a', color: '#ccc', padding: '10px 14px', fontSize: 14, fontFamily: 'inherit', outline: 'none' }}
            value={password} onChange={e => setPassword(e.target.value)} placeholder="密码" type="password" />
          <button style={{ background: '#00ff9d', color: '#000', border: 'none', padding: 12, fontSize: 13, fontWeight: 700, letterSpacing: 2, cursor: 'pointer' }}
            type="submit" disabled={loading}>{loading ? '处理中...' : isRegister ? '注册' : '登录'}</button>
        </form>
        <p style={{ marginTop: 20, fontSize: 12, color: '#444', cursor: 'pointer', textAlign: 'center' }}
          onClick={() => setIsRegister(!isRegister)}>
          {isRegister ? '已有账号？登录' : '没有账号？注册'}
        </p>
        {message && <p style={{ marginTop: 12, fontSize: 12, color: '#ff6b6b', textAlign: 'center' }}>{message}</p>}
      </div>
    </main>
  );

  return (
    <main style={{ minHeight: '100vh', background: '#080808', color: '#ccc', fontFamily: "'Courier New', monospace" }}>
      <header style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '16px 32px', borderBottom: '1px solid #181818' }}>
        <div style={{ display: 'flex', alignItems: 'baseline', gap: 16 }}>
          <span style={{ fontSize: 18, fontWeight: 700, color: '#00ff9d', letterSpacing: 4 }}>⬡ RSAL</span>
          <span style={{ fontSize: 11, color: '#444', letterSpacing: 2 }}>认知情报系统 v3</span>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 16 }}>
          <span style={{ fontSize: 11, color: '#444' }}>{user.email}</span>
          <button onClick={() => supabase.auth.signOut()}
            style={{ background: 'transparent', border: '1px solid #222', color: '#555', padding: '4px 12px', fontSize: 11, cursor: 'pointer' }}>退出</button>
        </div>
      </header>

      <section style={{ padding: '32px 32px 0' }}>
        <div style={{ display: 'flex', maxWidth: 800 }}>
          <input
            style={{ flex: 1, background: '#0e0e0e', border: '1px solid #2a2a2a', borderRight: 'none', color: '#fff', padding: '14px 20px', fontSize: 15, fontFamily: 'inherit', outline: 'none' }}
            value={q}
            onChange={e => setQ(e.target.value)}
            onKeyDown={e => e.key === 'Enter' && search()}
            placeholder="输入查询：人名 / 事件 / 拼音 / 绰号..."
            autoFocus
          />
          <button onClick={search} disabled={searching}
            style={{ background: '#00ff9d', color: '#000', border: 'none', padding: '14px 28px', fontSize: 13, fontWeight: 700, cursor: 'pointer', letterSpacing: 2, whiteSpace: 'nowrap' }}>
            {searching ? '···' : '搜索'}
          </button>
        </div>
      </section>

      {searching && (
        <div style={{ padding: '40px 32px', color: '#444', fontSize: 13, letterSpacing: 2 }}>
          <span style={{ color: '#00ff9d' }}>●</span> 正在推理...
        </div>
      )}

      {meta && (
        <section style={{ padding: '24px 32px', maxWidth: 900 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 16, paddingBottom: 12, borderBottom: '1px solid #151515' }}>
            <span style={{ color: '#555', fontSize: 13 }}>"{meta.query}"</span>
            <span style={{ color: '#333', fontSize: 11, letterSpacing: 2 }}>{meta.count} 条结果</span>
          </div>

          {entities.length > 0 && (
            <div style={{ display: 'flex', alignItems: 'center', flexWrap: 'wrap', gap: 10, marginBottom: 20, padding: '10px 14px', background: '#0d0d0d', border: '1px solid #1a1a1a' }}>
              <span style={{ fontSize: 10, color: '#444', letterSpacing: 2 }}>实体解析 →</span>
              {entities.map((e, i) => (
                <span key={i} style={{ display: 'flex', alignItems: 'center', gap: 6, padding: '4px 10px', background: '#111', border: '1px solid #1e1e1e', fontSize: 12 }}>
                  <span style={{ color: scoreColor(e.confidence) }}>●</span>
                  &nbsp;{e.canonical}
                  <span style={{ color: '#444', fontSize: 10, marginLeft: 4 }}>{matchLabel[e.match] ?? e.match} {Math.round(e.confidence * 100)}%</span>
                </span>
              ))}
            </div>
          )}

          {results.map((r, i) => <ResultCard key={r.document_id} r={r} index={i} />)}
        </section>
      )}
    </main>
  );
}
