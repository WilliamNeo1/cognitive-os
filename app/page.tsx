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

  useEffect(() => {
    supabase.auth.getSession().then(({ data: { session } }) => {
      setUser(session?.user ?? null);
    });

    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event, session) => {
      setUser(session?.user ?? null);
    });

    return () => {
      subscription.unsubscribe();
    };
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

        if (error) {
          setMessage(error.message);
        } else {
          setMessage('注册成功，请检查邮箱验证链接。');
        }
      } else {
        const { error } = await supabase.auth.signInWithPassword({
          email,
          password,
        });

        if (error) {
          setMessage(error.message);
        }
      }
    } catch (err) {
      setMessage('发生未知错误');
    }

    setLoading(false);
  };

  const handleLogout = async () => {
    await supabase.auth.signOut();
  };

  if (user) {
    return (
      <main
        style={{
          minHeight: '100vh',
          backgroundColor: '#0a0a0a',
          color: 'white',
          padding: '40px',
          fontFamily: 'system-ui',
        }}
      >
        <h1 style={{ fontSize: '2.5rem' }}>
          Reality Survival Analysis Laboratory
        </h1>

        <p style={{ marginTop: '20px', fontSize: '1.2rem' }}>
          欢迎回来：
          {user.email}
        </p>

        <button
          onClick={handleLogout}
          style={{
            marginTop: '30px',
            padding: '12px 24px',
            borderRadius: '8px',
            border: 'none',
            cursor: 'pointer',
            fontWeight: 'bold',
          }}
        >
          登出
        </button>

        <hr style={{ margin: '50px 0' }} />

        <h2>认知数据库系统</h2>

        <p>下一阶段：连接 PostgreSQL / Supabase 数据库。</p>
      </main>
    );
  }

  return (
    <main
      style={{
        minHeight: '100vh',
        backgroundColor: '#0a0a0a',
        color: 'white',
        display: 'flex',
        justifyContent: 'center',
        alignItems: 'center',
        fontFamily: 'system-ui',
      }}
    >
      <div
        style={{
          width: '100%',
          maxWidth: '480px',
          padding: '40px',
        }}
      >
        <h1
          style={{
            fontSize: '2.7rem',
            textAlign: 'center',
            marginBottom: '10px',
          }}
        >
          Reality Survival Analysis Laboratory
        </h1>

        <p
          style={{
            textAlign: 'center',
            color: '#cccccc',
            marginBottom: '40px',
          }}
        >
          Study survival, structure and reality.
        </p>

        <h2
          style={{
            textAlign: 'center',
            marginBottom: '20px',
          }}
        >
          {isRegister ? '注册账号' : '用户登录'}
        </h2>

        {message && (
          <p
            style={{
              color: message.includes('成功')
                ? '#00ffcc'
                : '#ff6666',
              textAlign: 'center',
              marginBottom: '20px',
            }}
          >
            {message}
          </p>
        )}

        <form
          onSubmit={handleSubmit}
          style={{
            display: 'flex',
            flexDirection: 'column',
            gap: '15px',
          }}
        >
          <input
            type="email"
            placeholder="邮箱"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            required
            style={{
              padding: '14px',
              borderRadius: '8px',
              border: 'none',
              fontSize: '1rem',
            }}
          />

          <input
            type="password"
            placeholder="密码（至少6位）"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            required
            style={{
              padding: '14px',
              borderRadius: '8px',
              border: 'none',
              fontSize: '1rem',
            }}
          />

          <button
            type="submit"
            disabled={loading}
            style={{
              padding: '14px',
              borderRadius: '8px',
              border: 'none',
              backgroundColor: '#00ffcc',
              color: 'black',
              fontWeight: 'bold',
              cursor: 'pointer',
            }}
          >
            {loading
              ? '处理中...'
              : isRegister
              ? '注册'
              : '登录'}
          </button>
        </form>

        <p
          onClick={() => {
            setIsRegister(!isRegister);
            setMessage('');
          }}
          style={{
            marginTop: '20px',
            textAlign: 'center',
            color: '#00ffcc',
            cursor: 'pointer',
          }}
        >
          {isRegister
            ? '已有账号？返回登录'
            : '没有账号？立即注册'}
        </p>
      </div>
    </main>
  );
}
