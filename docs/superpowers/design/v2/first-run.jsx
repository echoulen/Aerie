// First-run gh setup — blocking onboarding when gh is missing or unauthenticated.
// Full window takeover (no main views behind), warm tone, single big action.

function FirstRun({ state = 'no-gh' }) {
  const body = state === 'no-gh' ? <NoGhBody /> : <NoAuthBody />;
  return (
    <div style={{ width: W, height: H, position:'relative' }}>
      <div className="backdrop" />
      <div className="window" style={{ position:'relative', width:'100%', height:'100%' }}>
        <div className="titlebar">
          <div className="traffic"><span className="r"/><span className="y"/><span className="g"/></div>
          <div className="brand"><span className="brand-mark"/><span>Aerie</span></div>
        </div>
        <div style={{ flex:1, minHeight:0, overflow:'hidden', position:'relative' }}>
          {/* warm hero backdrop layer */}
          <div style={{
            position:'absolute', inset:0,
            background:
              'radial-gradient(60% 50% at 80% 10%, oklch(0.55 0.13 55 / 0.28) 0%, transparent 60%),' +
              'radial-gradient(40% 50% at 15% 90%, oklch(0.45 0.13 80 / 0.18) 0%, transparent 60%)',
            pointerEvents:'none',
          }} />
          <div style={{
            position:'relative', height:'100%',
            display:'flex', alignItems:'center', justifyContent:'center',
            padding:'40px',
          }}>
            {body}
          </div>
        </div>
      </div>
    </div>
  );
}

// ───────────────────────────────────────────────────────────
// A — gh is not installed
// ───────────────────────────────────────────────────────────
function NoGhBody() {
  return (
    <div style={{ width: 640, maxWidth:'100%', textAlign:'left' }}>
      {/* Eyebrow icon — a gentle "missing puzzle piece" mark */}
      <div style={{
        width:54, height:54, borderRadius:14,
        background:'var(--glass-2)',
        border:'1px solid var(--glass-line-2)',
        backdropFilter:'blur(20px)', WebkitBackdropFilter:'blur(20px)',
        display:'flex', alignItems:'center', justifyContent:'center',
        color:'var(--amber)',
        boxShadow:'inset 0 1px 0 0 var(--glass-highlight)',
        marginBottom:24,
      }}>
        <svg width="26" height="26" viewBox="0 0 16 16" fill="none" stroke="currentColor"
             strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round">
          <path d="M2 6h3.5a1.5 1.5 0 100 3H2v5h5v-3.5a1.5 1.5 0 113 0V14h5V9h-3.5a1.5 1.5 0 110-3H14V2H2z"/>
        </svg>
      </div>

      <div style={{ fontSize:32, fontWeight:500, color:'var(--text-1)', letterSpacing:'-0.012em', lineHeight:1.15 }}>
        Aerie needs the GitHub CLI
      </div>
      <div style={{ fontSize:14.5, color:'var(--text-2)', marginTop:14, lineHeight:1.6, maxWidth:560 }}>
        Aerie gets your GitHub tokens from <span className="mono">gh</span> — that's how it juggles multiple accounts and
        falls back automatically. Install it once and Aerie will pick up everything from there.
      </div>

      {/* Command */}
      <div style={{
        marginTop:24, padding:'14px 16px',
        background:'rgba(0,0,0,0.32)',
        border:'1px solid var(--glass-line-2)',
        borderRadius:11,
        display:'flex', alignItems:'center', gap:12,
      }}>
        <span className="mono" style={{ color:'var(--text-4)' }}>$</span>
        <span className="mono" style={{ flex:1, fontSize:13.5, color:'var(--text-1)' }}>brew install gh</span>
        <button className="btn sm">Copy</button>
      </div>
      <div style={{ fontSize:12, color:'var(--text-3)', marginTop:10, lineHeight:1.5 }}>
        No Homebrew? See <span style={{ color:'var(--text-2)', borderBottom:'1px dashed var(--text-4)' }}>cli.github.com</span> for the macOS installer.
      </div>

      {/* Action row */}
      <div className="row" style={{ marginTop:32, gap:10, alignItems:'center' }}>
        <button className="btn amber">I've installed it — re-check</button>
        <button className="btn ghost">Quit Aerie</button>
        <span style={{ flex:1 }} />
        <span className="mono" style={{ fontSize:11, color:'var(--text-4)' }}>checking every 5s</span>
        <span className="dot" style={{ background:'var(--amber)', boxShadow:'0 0 8px var(--amber-glow)' }} />
      </div>
    </div>
  );
}

// ───────────────────────────────────────────────────────────
// B — gh is installed but no authenticated accounts
// ───────────────────────────────────────────────────────────
function NoAuthBody() {
  return (
    <div style={{ width: 640, maxWidth:'100%', textAlign:'left' }}>
      <div style={{
        width:54, height:54, borderRadius:14,
        background:'var(--glass-2)',
        border:'1px solid var(--glass-line-2)',
        backdropFilter:'blur(20px)', WebkitBackdropFilter:'blur(20px)',
        display:'flex', alignItems:'center', justifyContent:'center',
        color:'var(--amber)',
        boxShadow:'inset 0 1px 0 0 var(--glass-highlight)',
        marginBottom:24,
      }}>
        <svg width="26" height="26" viewBox="0 0 16 16" fill="none" stroke="currentColor"
             strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round">
          <circle cx="5" cy="11" r="3"/><path d="M7 9l6.5-6.5"/><path d="M11 5l2 2"/>
        </svg>
      </div>

      <div style={{ fontSize:32, fontWeight:500, color:'var(--text-1)', letterSpacing:'-0.012em', lineHeight:1.15 }}>
        Sign in to GitHub through gh
      </div>
      <div style={{ fontSize:14.5, color:'var(--text-2)', marginTop:14, lineHeight:1.6, maxWidth:560 }}>
        Run this in a terminal. You can do it more than once — Aerie will pick up every account you log in to,
        and use them automatically as fallbacks for one another.
      </div>

      {/* Command */}
      <div style={{
        marginTop:24, padding:'14px 16px',
        background:'rgba(0,0,0,0.32)',
        border:'1px solid var(--glass-line-2)',
        borderRadius:11,
        display:'flex', alignItems:'center', gap:12,
      }}>
        <span className="mono" style={{ color:'var(--text-4)' }}>$</span>
        <span className="mono" style={{ flex:1, fontSize:13.5, color:'var(--text-1)' }}>gh auth login --hostname github.com --git-protocol ssh</span>
        <button className="btn sm">Copy</button>
      </div>

      <div className="card" style={{ marginTop:18, padding:'14px 16px' }}>
        <div style={{ fontSize:12, color:'var(--text-3)', lineHeight:1.6 }}>
          <span style={{ color:'var(--text-1)' }}>Adding a GitHub Enterprise host?</span> Pass <span className="mono">--hostname your-ghe-host.com</span> instead. You can repeat this for every account or org you want Aerie to know about.
        </div>
      </div>

      <div className="row" style={{ marginTop:28, gap:10, alignItems:'center' }}>
        <button className="btn amber">I've signed in — re-check</button>
        <button className="btn ghost">Quit Aerie</button>
        <span style={{ flex:1 }} />
        <span className="mono" style={{ fontSize:11, color:'var(--text-4)' }}>checking every 5s</span>
        <span className="dot" style={{ background:'var(--amber)', boxShadow:'0 0 8px var(--amber-glow)' }} />
      </div>
    </div>
  );
}

Object.assign(window, { FirstRun });
