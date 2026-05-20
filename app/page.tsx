'use client';

import { createClient } from '@supabase/supabase-js';
import { useState, useEffect } from 'react';

const supabase = createClient(
  'https://mgigbiblwqywcegkhjpu.supabase.co',
  'sb_publishable_-lbISn3BDO-8spZxCMRrBw_DAZkDT2S'
);

export default function Home() {
  const [user, setUser] = useState<any>(null);
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState('');

  useEffect(() => {
    supabase.auth.getSession().then(({ data: { session } }) => {
      setUser(session?.user ?? null);
    });

    const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, session) => {
      setUser(session?.user ?? null);
    });

    return () => subscription.unsubscribe();
  }, []);

  const handleLogin = async () => {
    setLoading(true);
    setMessage('');
    const { error } = await supabase.auth.signInWithPassword({ email, password });
    if (error) setMessage(error.message);
    setLoading(false);
  };

  const handleRegister = async () => {
    setLoading(true);
    setMessage('');
    const { error } = await supabase.auth.signUp({ 
      email, 
      password,
      options: { emailRedirectTo: window.location.origin }
    });
    if (error) setMessage(error.message);
    else setMessage('注册成功！请查收邮箱并点击验证链接。');
    setLoading(false);
  };

  const logout = async () => {
    await supabase.auth.signOut();
    setMessage('');
  };

  return (
    <div style={{ 
      minHeight: '100vh', 
      backgroundColor: '#0a0a0a', 
      color: 'white',
      padding: '2rem',
      fontFamily: 'system-ui, sans-serif'
    }}>
      <div style={{ maxWidth: '800px', margin: '0 auto', textAlign: 'center' }}>
        <h1 style={{ fontSize: '3rem' }}>Reality Survival Analysis Laboratory</h1>
        <p style={{ fontSize: '1.4rem', marginBottom: '2rem' }}>
          To return the public for truth — Study everything about survival
        </p>

        {!user ? (
          <div style={{ maxWidth: '420px', margin: '0 auto' }}>
            <h2>{message ? message : '用户登录 / 注册'}</h2>
            
            <input 
              type="email" 
              placeholder="邮箱地址" 
              value={email} 
              onChange={(e) => setEmail(e.target.value)}
              style={{ width: '100%', padding: '14px', margin: '10px 0', borderRadius: '8px', fontSize: '1rem' }}
            />
            <input 
              type="password" 
              placeholder="密码（至少6位）" 
              value={password} 
              onChange={(e) => setPassword(e.target.value)}
              style={{ width: '100%', padding: '14px', margin: '10px 0', borderRadius: '8px', fontSize: '1rem' }}
            />

            <button onClick={handleLogin} disabled={loading} style={{ width: '100%', padding: '14px', margin: '10px 0', backgroundColor: '#00ffcc', color: 'black', fontWeight: 'bold' }}>
              登录
            </button>
            
            <button onClick={handleRegister} disabled={loading} style={{ width: '100%', padding: '14px', margin: '10px 0', backgroundColor: '#333' }}>
              注册新账号
            </button>
          </div>
        ) : (
          <div>
            <p>✅ 已登录：{user.email}</p>
            <button onClick={logout} style={{ padding: '10px 24px', fontSize: '1.1rem' }}>
              登出
            </button>

            <hr style={{ margin: '3rem 0' }} />
            <h3>数据库 ccc 数据展示区（准备中）</h3>
            <p>下一步我们会在这里显示你的数据表</p>
          </div>
        )}
      </div>
    </div>
  );
}
