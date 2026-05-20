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
  const [isRegister, setIsRegister] = useState(false);

  useEffect(() => {
    supabase.auth.getSession().then(({ data: { session } }) => {
      setUser(session?.user ?? null);
    });

    const { data: { subscription } } = supabase.auth.onAuthStateChange((_, session) => {
      setUser(session?.user ?? null);
    });

    return () => subscription.unsubscribe();
  }, []);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);
    setMessage('');

    const redirectTo = window.location.origin;   // 自动使用生产域名

    if (isRegister) {
      const { error } = await supabase.auth.signUp({
        email,
        password,
        options: { emailRedirectTo: redirectTo }
      });
      if (error) setMessage(error.message);
      else setMessage('注册成功！请前往邮箱点击验证链接（注意检查垃圾邮件）');
    } else {
      const { error } = await supabase.auth.signInWithPassword({ email, password });
      if (error) setMessage(error.message);
      else setMessage('登录成功！');
    }
    setLoading(false);
  };

  const logout = async () => await supabase.auth.signOut();

  // 已登录状态
  if (user) {
    return (
      <div style={{ minHeight: '100vh', backgroundColor: '#0a0a0a', color: 'white', padding: '40px', textAlign: 'center' }}>
        <h1>Reality Survival Analysis Laboratory</h1>
        <p style={{ fontSize: '1.4rem', margin: '20px 0' }}>已登录：{user.email}</p>
        <button onClick={logout} style={{ padding: '12px 30px', fontSize: '1.1rem' }}>登出</button>
        <hr style={{ margin: '40px 0' }} />
        <h3>数据库展示区（下一步实现）</h3>
      </div>
    );
  }

  // 未登录状态
  return (
    <div style={{ minHeight: '100vh', backgroundColor: '#0a0a0a', color: 'white', padding: '40px', fontFamily: 'system-ui' }}>
      <div style={{ maxWidth: '480px', margin: '0 auto', textAlign: 'center' }}>
        <h1 style={{ fontSize: '2.8rem' }}>Reality Survival Analysis Laboratory</h1>
        <p style={{ marginBottom: '30px' }}>To return the public for truth — Study everything about survival</p>

        <h2>{isRegister ? '注册新账号' : '用户登录'}</h2>

        {message && <p style={{ margin: '15px 0', color: message.includes('成功') ? '#00ffcc' : '#ff6666' }}>{message}</p>}

        <form onSubmit={handleSubmit} style={{ display: 'flex', flexDirection: 'column', gap: '15px' }}>
          <input type="email" placeholder="邮箱地址" value={email} onChange={(e) => setEmail(e.target.value)} style={{ padding: '15px', borderRadius: '8px', fontSize: '1.1rem' }} required />
          <input type="password" placeholder="密码（至少6位）" value={password} onChange={(e) => setPassword(e.target.value)} style={{ padding: '15px', borderRadius: '8px', fontSize: '1.1rem' }} required />
          
          <button type="submit" disabled={loading} style={{ padding: '16px', backgroundColor: '#00ffcc', color: 'black', fontWeight: 'bold', borderRadius: '8px', fontSize: '1.1rem' }}>
            {loading ? '处理中...' : (isRegister ? '注册' : '登录')}
          </button>
        </form>

        <p onClick={() => {setIsRegister(!isRegister); setMessage('');}} style={{ marginTop: '20px', color: '#00ffcc', cursor: 'pointer' }}>
          {isRegister ? '已有账号？返回登录' : '没有账号？去注册'}
        </p>
      </div>
    </div>
  );
}
