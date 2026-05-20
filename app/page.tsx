export default function Home() {
  return (
    <div style={{ 
      minHeight: '100vh', 
      backgroundColor: '#0a0a0a', 
      color: 'white',
      display: 'flex',
      flexDirection: 'column',
      alignItems: 'center',
      justifyContent: 'center',
      textAlign: 'center',
      padding: '2rem',
      fontFamily: 'system-ui, sans-serif'
    }}>
      <h1 style={{ fontSize: '3.5rem', marginBottom: '1rem' }}>
        Reality Survival Analysis Laboratory
      </h1>
      <p style={{ fontSize: '1.6rem', marginBottom: '1rem' }}>
        To return the public for truth
      </p>
      <p style={{ fontSize: '2rem', color: '#00ffcc' }}>
        Study everything about survival
      </p>
      
      <p style={{ marginTop: '4rem', color: '#ffcc00', fontSize: '1.3rem' }}>
        测试页面已成功显示 ✅<br/>
        如果你看到这行字，说明拦截已被绕过
      </p>
    </div>
  );
}
