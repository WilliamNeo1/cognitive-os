'use client';

import { createClient } from '@supabase/supabase-js';
import { useEffect, useState } from 'react';

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
);

export default function Home() {
  const [user, setUser] = useState<any>(null);

  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState('');
  const [isRegister, setIsRegister] = useState(false);

  const [q, setQ] = useState('');
  const [result, setResult] = useState<any>(null);
  const [searching, setSearching] = useState(false);

  useEffect(() => {
    supabase.auth.getSession().then(({ data: { session } }) => {
      setUser(session?.user ?? null);
    });

    const { data: { subscription } } =
      supabase.auth.onAuthStateChange((_event, session) => {
        setUser(session?.user ?? null);
      });

    return () => subscription.unsubscribe();
  }, []);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);
    setMessage('');

    try {
      if (isRegister) {
        const { error } = await supabase.auth.signUp({
          email,
          password,
          options: {
            emailRedirectTo: 'https://ccc-lab.vercel.app',
          },
        });

        setMessage(error ? error.message : '注册成功，请查邮箱');
      } else {
        const { error } = await supabase.auth.signInWithPassword({
          email,
          password,
        });

        if (error) setMessage(error.message);
      }
    } catch {
      setMessage('未知错误');
    }

    setLoading(false);
  };

  const handleLogout = async () => {
    await supabase.auth.signOut();
  };

  const search = async () => {
    setSearching(true);

    const res = await fetch(`/api/search?q=${encodeURIComponent(q)}`);
    const json = await res.json();

    setResult(json);
    setSearching(false);
  };

  if (user) {
    return (
      <main style={{ padding: 40, fontFamily: 'system-ui', color: 'white', background: '#0a0a0a', minHeight: '100vh' }}>
        <h1>Reality Survival Analysis Laboratory</h1>

        <p>欢迎回来：{user.email}</p>

        <button onClick={handleLogout}>登出</button>

        <hr style={{ margin: '30px 0' }} />

        <h2>Search System</h2>

        <input
          value={q}
          onChange={(e) => setQ(e.target.value)}
          placeholder="输入查询..."
          style={{ padding: 10, width: 300 }}
        />

        <button onClick={search} style={{ marginLeft: 10 }}>
          搜索
        </button>

        {searching && <p>loading...</p>}

        {result && (
          <pre style={{ marginTop: 20 }}>
            {JSON.stringify(result, null, 2)}
          </pre>
        )}
      </main>
    );
  }

  return (
    <main style={{ padding: 40, background: '#0a0a0a', color: 'white', minHeight: '100vh' }}>
      <h1>Reality Survival Analysis Laboratory</h1>

      <form onSubmit={handleSubmit}>
        <input value={email} onChange={(e) => setEmail(e.target.value)} placeholder="email" />
        <input value={password} onChange={(e) => setPassword(e.target.value)} placeholder="password" type="password" />

        <button type="submit" disabled={loading}>
          {isRegister ? '注册' : '登录'}
        </button>
      </form>

      <p onClick={() => setIsRegister(!isRegister)} style={{ cursor: 'pointer', color: '#00ffcc' }}>
        {isRegister ? '切换登录' : '切换注册'}
      </p>

      {message && <p>{message}</p>}
    </main>
  );
}