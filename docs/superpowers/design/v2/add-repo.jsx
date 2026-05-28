// "Add Repository" sheet — slides down from the titlebar of the Settings window.
// Two states presented: empty (waiting for a folder), and detected (folder picked, ready to add).

function AddRepoSheet({ state='detected' }) {
  return (
    <div style={{ width: SET_W, height: SET_H, position:'relative' }}>
      <div className="backdrop" />
      <div className="window" style={{ position:'relative', width:'100%', height:'100%' }}>
        <div className="titlebar">
          <div className="traffic">
            <span className="r" />
            <span className="y" />
            <span className="g" />
          </div>
          <div className="brand">
            <span className="brand-mark" />
            <span>Aerie · Settings</span>
          </div>
        </div>

        {/* Dimmed parent (repositories screen) for context */}
        <div style={{ position:'relative', flex:1, minHeight:0, overflow:'hidden' }}>
          <div style={{ filter:'blur(2px) saturate(0.85)', opacity:0.55, height:'100%', display:'flex' }}>
            <SettingsSidebar active="repositories" />
            <div style={{ flex:1, display:'flex', flexDirection:'column' }}>
              <RepositoriesScreen />
            </div>
          </div>
          <div style={{
            position:'absolute', inset:0,
            background:'rgba(0,0,0,0.30)',
            display:'flex', alignItems:'flex-start', justifyContent:'center',
            padding:'0 60px',
          }}>
            <div style={{
              width: 640, marginTop: 0,
              background:'rgba(28, 26, 32, 0.82)',
              border:'1px solid var(--glass-line-2)',
              borderTop: 'none',
              borderTopLeftRadius:0, borderTopRightRadius:0,
              borderBottomLeftRadius:18, borderBottomRightRadius:18,
              backdropFilter:'blur(48px) saturate(180%)',
              WebkitBackdropFilter:'blur(48px) saturate(180%)',
              boxShadow:'0 30px 80px -20px rgba(0,0,0,0.7)',
              overflow:'hidden',
            }}>
              {state === 'empty' ? <AddRepoEmpty /> : <AddRepoDetected />}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

function AddRepoEmpty() {
  return (
    <div>
      <div style={{ padding:'24px 28px 18px' }}>
        <div className="section-eyebrow">ADD REPOSITORY</div>
        <div style={{ fontSize:18, fontWeight:500, color:'var(--text-1)', marginTop:6, letterSpacing:'-0.005em' }}>
          Point Aerie at a local git repository
        </div>
        <div style={{ fontSize:13, color:'var(--text-3)', marginTop:6, lineHeight:1.55 }}>
          Aerie reads <span className="mono">.git/</span> for state and uses the origin URL to find the matching GitHub repo.
        </div>
      </div>

      {/* Drop zone */}
      <div style={{ padding:'4px 28px 18px' }}>
        <div style={{
          padding:'48px 24px',
          border:'1.5px dashed var(--glass-line-2)',
          borderRadius:14,
          background:'rgba(255,255,255,0.02)',
          textAlign:'center',
          display:'flex', flexDirection:'column', alignItems:'center', gap:10,
        }}>
          <div style={{
            width:48, height:48, borderRadius:14,
            background:'var(--glass-2)', border:'1px solid var(--glass-line)',
            display:'flex', alignItems:'center', justifyContent:'center',
            color:'var(--text-2)',
          }}><FolderBig /></div>
          <div style={{ fontSize:14, color:'var(--text-1)', marginTop:6 }}>Drag a folder here</div>
          <div style={{ fontSize:12, color:'var(--text-3)' }}>or</div>
          <button className="btn">Browse…</button>
        </div>
      </div>

      {/* Recent suggestions */}
      <div style={{ padding:'4px 28px 18px' }}>
        <div className="section-eyebrow" style={{ marginBottom:8 }}>RECENTLY SEEN</div>
        <div className="col" style={{ gap:2 }}>
          {[
            { name:'plover',     path:'~/code/orbital/plover',     gh:'orbital/plover' },
            { name:'crow',       path:'~/code/orbital/crow',       gh:'orbital/crow' },
            { name:'kestrel',    path:'~/code/orbital/kestrel',    gh:'orbital/kestrel' },
          ].map(r => (
            <div key={r.name} style={{
              padding:'10px 12px', borderRadius:8,
              display:'grid', gridTemplateColumns:'auto 1fr 1fr auto', columnGap:14,
              alignItems:'center',
              fontSize:13, color:'var(--text-2)',
            }}>
              <FolderTiny />
              <span style={{ color:'var(--text-1)' }}>{r.name}</span>
              <span className="mono" style={{ fontSize:11.5, color:'var(--text-3)' }}>{r.path}</span>
              <button className="btn ghost sm">Add</button>
            </div>
          ))}
        </div>
      </div>

      <div style={{
        display:'flex', justifyContent:'flex-end', gap:8,
        padding:'14px 22px', background:'rgba(0,0,0,0.18)',
        borderTop:'1px solid var(--glass-line)',
      }}>
        <button className="btn ghost">Cancel</button>
      </div>
    </div>
  );
}

function AddRepoDetected() {
  return (
    <div>
      <div style={{ padding:'24px 28px 16px' }}>
        <div className="row" style={{ justifyContent:'space-between', alignItems:'baseline' }}>
          <div className="section-eyebrow">ADD REPOSITORY</div>
          <div className="mono" style={{ fontSize:11, color:'var(--ok)' }}>✓ detected</div>
        </div>
        <div style={{ fontSize:18, fontWeight:500, color:'var(--text-1)', marginTop:6, letterSpacing:'-0.005em' }}>
          Add aerie to your fleet
        </div>
      </div>

      {/* Detected folder card */}
      <div style={{ padding:'0 28px 16px' }}>
        <div style={{
          padding:'14px 16px', borderRadius:10,
          background:'rgba(0,0,0,0.22)',
          border:'1px solid var(--glass-line)',
          display:'flex', alignItems:'center', gap:12,
        }}>
          <div style={{
            width:34, height:34, borderRadius:8,
            background:'var(--amber-soft)', border:'1px solid var(--amber-line)',
            display:'flex', alignItems:'center', justifyContent:'center', color:'var(--amber)',
          }}><FolderBig /></div>
          <div className="col" style={{ flex:1, gap:2 }}>
            <span style={{ fontSize:14, color:'var(--text-1)' }}>aerie</span>
            <span className="mono" style={{ fontSize:11.5, color:'var(--text-3)' }}>/Users/carlos/code/aerie</span>
          </div>
          <button className="btn ghost sm">Change…</button>
        </div>
      </div>

      {/* Detected fields */}
      <div style={{ padding:'0 28px 18px' }}>
        <KVListSheet rows={[
          ['github',           <span className="mono">carlos-li/aerie</span>,                          <span className="mono" style={{ color:'var(--text-4)' }}>from origin URL</span>],
          ['default branch',   <span className="mono">main</span>,                                     <span className="mono" style={{ color:'var(--text-4)' }}>refs/remotes/origin/HEAD</span>],
          ['current branch',   <span className="mono">feat/virtual-clock</span>,                       <span style={{ color:'var(--warn)' }}>● dirty working tree</span>],
          ['account',          <AccountSelect login="carlos-li" host="github.com" />,                 <span className="mono" style={{ color:'var(--text-4)' }}>inferred from origin</span>],
        ]} />
      </div>

      {/* Footer */}
      <div style={{
        display:'flex', justifyContent:'space-between', alignItems:'center',
        padding:'14px 22px', background:'rgba(0,0,0,0.18)',
        borderTop:'1px solid var(--glass-line)',
      }}>
        <span style={{ fontSize:11.5, color:'var(--text-4)' }} className="mono">polling starts within 30s</span>
        <div className="row" style={{ gap:8 }}>
          <button className="btn ghost">Cancel</button>
          <button className="btn amber">Add to fleet</button>
        </div>
      </div>
    </div>
  );
}

function KVListSheet({ rows }) {
  return (
    <div style={{
      borderRadius:10, border:'1px solid var(--glass-line)',
      background:'rgba(0,0,0,0.16)', padding:'2px 14px',
    }}>
      {rows.map(([k, v, hint], i) => (
        <div key={i} style={{
          display:'grid', gridTemplateColumns:'130px 1fr auto',
          alignItems:'center', columnGap:14,
          padding:'11px 0',
          borderBottom: i < rows.length-1 ? '1px solid var(--glass-line)' : 'none',
        }}>
          <span className="mono" style={{ fontSize:11, color:'var(--text-4)', letterSpacing:'0.02em' }}>{k}</span>
          <span style={{ fontSize:13, color:'var(--text-1)' }}>{v}</span>
          <span style={{ fontSize:11, color:'var(--text-3)' }}>{hint}</span>
        </div>
      ))}
    </div>
  );
}

function AccountSelect({ login, host }) {
  return (
    <div className="row" style={{
      gap:10, padding:'5px 10px 5px 6px', borderRadius:7,
      border:'1px solid var(--glass-line-2)',
      background:'var(--glass-2)',
      width:'fit-content',
    }}>
      <span style={{
        width:20, height:20, borderRadius:'50%',
        background:'radial-gradient(circle at 30% 30%, oklch(0.88 0.14 78), oklch(0.50 0.13 60))',
      }} />
      <span className="mono" style={{ fontSize:12.5, color:'var(--text-1)' }}>{login}</span>
      <span className="mono" style={{ fontSize:11, color:'var(--text-3)' }}>@ {host}</span>
      <ChevDown />
    </div>
  );
}

function FolderBig() { return (
  <svg width="20" height="20" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round">
    <path d="M2 4.5a1 1 0 011-1h3l1.5 1.5h5.5a1 1 0 011 1V12a1 1 0 01-1 1H3a1 1 0 01-1-1z"/>
  </svg>
); }
function FolderTiny() { return (
  <svg width="13" height="13" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" style={{ color:'var(--text-3)' }}>
    <path d="M2 4.5a1 1 0 011-1h3l1.5 1.5h5.5a1 1 0 011 1V12a1 1 0 01-1 1H3a1 1 0 01-1-1z"/>
  </svg>
); }
function ChevDown() { return (
  <svg width="10" height="10" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" style={{ color:'var(--text-3)' }}>
    <path d="M3 6l5 4 5-4"/>
  </svg>
); }

Object.assign(window, { AddRepoSheet });
