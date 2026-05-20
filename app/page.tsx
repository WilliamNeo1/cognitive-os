export default function Home() {
  return (
    <div style={{ 
      minHeight: '100vh', 
      display: 'flex', 
      flexDirection: 'column', 
      alignItems: 'center', 
      justifyContent: 'center',
      backgroundColor: '#0a0a0a',
      color: 'white',
      textAlign: 'center',
      padding: '2rem',
      fontFamily: 'system-ui, sans-serif'
    }}>
      <h1 style={{ 
        fontSize: '3.2rem', 
        marginBottom: '1rem',
        fontWeight: 'bold'
      }}>
        Reality Survival Analysis Laboratory
      </h1>
      
      <p style={{ 
        fontSize: '1.55rem', 
        maxWidth: '680px', 
        marginBottom: '1.5rem',
        opacity: 0.9
      }}>
        To return the public for truth
      </p>
      
      <p style={{ 
        fontSize: '1.85rem', 
        fontWeight: 'bold', 
        color: '#00ffcc',
        marginTop: '1rem'
      }}>
        Study everything about survival
      </p>
    </div>
  );
}
