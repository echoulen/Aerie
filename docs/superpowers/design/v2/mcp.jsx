// MCP — consent dialog, activity toasts, settings panel

// ════════════════════════════════════════════════════════════
// 1. MCP CONSENT DIALOG
// First-run-after-setup popup. Asks user to write Aerie's entry
// into ~/.claude/.mcp.json so Claude Code can auto-discover it.
// ════════════════════════════════════════════════════════════
function DialogMCPConsent() {
  return (
    <DialogShell parent="prs">
      <div style={{
        width: 560, maxWidth:'92%',
        background:'rgba(28, 26, 32, 0.82)',
        border:'1px solid var(--amber-line)',
        borderRadius:18,
        backdropFilter:'blur(48px) saturate(180%)',
        WebkitBackdropFilter:'blur(48px) saturate(180%)',
        boxShadow:'0 30px 80px -20px rgba(0,0,0,0.7), inset 0 1px 0 0 var(--glass-highlight)',
        overflow:'hidden',
      }}>
        <div style={{ padding:'28px 30px 18px' }}>
          {/* Hero — small Claude×Aerie pairing */}
          <div className="row" style={{ gap:14, alignItems:'center' }}>
            <div style={{
              width:38, height:38, borderRadius:11,
              background:'radial-gradient(circle at 30% 30%, oklch(0.75 0.13 30), oklch(0.50 0.16 25))',
              boxShadow:'inset 0 1px 0 0 rgba(255,255,255,0.20)',
              display:'flex', alignItems:'center', justifyContent:'center',
              fontFamily:'var(--font-sans)', fontWeight:600, fontSize:18, color:'#fff',
            }}>C</div>
            <div style={{ color:'var(--text-4)', fontSize:18 }}>—</div>
            <div style={{
              width:38, height:38, borderRadius:11,
              background:
                'radial-gradient(circle at 30% 30%, oklch(0.88 0.14 78), oklch(0.45 0.12 60)),' +
                'oklch(0.20 0.02 70)',
              boxShadow:'inset 0 1px 0 0 rgba(255,255,255,0.30), 0 0 14px oklch(0.83 0.135 75 / 0.45)',
            }} />
          </div>

          <div style={{ fontSize:20, fontWeight:500, color:'var(--text-1)', letterSpacing:'-0.005em', marginTop:18 }}>
            Let Claude Code talk to Aerie?
          </div>
          <div style={{ fontSize:13.5, color:'var(--text-2)', marginTop:8, lineHeight:1.55 }}>
            Aerie can register itself in <span className="mono" style={{ color:'var(--text-1)' }}>~/.claude/.mcp.json</span> so every Claude
            Code session on this machine can read your local repo cache, queue merges, and confirm hard resets — through Aerie, not against your repos directly.
          </div>

          {/* JSON preview */}
          <div style={{
            marginTop:18,
            background:'rgba(0,0,0,0.32)',
            border:'1px solid var(--glass-line)',
            borderRadius:10,
            overflow:'hidden',
          }}>
            <div style={{
              display:'flex', justifyContent:'space-between', alignItems:'center',
              padding:'8px 12px', borderBottom:'1px solid var(--glass-line)',
              background:'rgba(0,0,0,0.20)',
            }}>
              <span className="mono" style={{ fontSize:11, color:'var(--text-4)' }}>~/.claude/.mcp.json · diff</span>
              <button className="btn ghost sm">Copy</button>
            </div>
            <pre style={{
              margin:0, padding:'12px 14px',
              fontFamily:'var(--font-mono)', fontSize:11.5, lineHeight:1.6,
              color:'var(--text-2)', whiteSpace:'pre',
              overflowX:'auto',
            }}>{`{
  "mcpServers": {
`}<span style={{ color:'var(--ok)' }}>{`+   "aerie": {
+     "url": "http://127.0.0.1:47823/mcp",
+     "headers": {
+       "Authorization": "Bearer aer_••••••••••••••••"
+     }
+   }`}</span>{`
  }
}`}</pre>
          </div>

          {/* Footnotes */}
          <ul style={{
            margin:'16px 0 0', paddingLeft:0, listStyle:'none',
            display:'flex', flexDirection:'column', gap:7,
          }}>
            <Note>The bearer token rotates each time Aerie launches.</Note>
            <Note>Aerie only touches its own <span className="mono">aerie</span> entry — other servers are untouched.</Note>
            <Note>You can revoke or rotate this any time from <span style={{ color:'var(--text-2)' }}>Settings · MCP</span>.</Note>
          </ul>
        </div>

        <div style={{
          display:'flex', justifyContent:'space-between', alignItems:'center',
          padding:'14px 22px', background:'rgba(0,0,0,0.22)',
          borderTop:'1px solid var(--glass-line)',
        }}>
          <span style={{ fontSize:11.5, color:'var(--text-4)' }}>You can change this later in Settings</span>
          <div className="row" style={{ gap:8 }}>
            <button className="btn ghost">Not now</button>
            <button className="btn amber">Allow</button>
          </div>
        </div>
      </div>
    </DialogShell>
  );
}
function Note({ children }) {
  return (
    <li style={{
      display:'flex', alignItems:'flex-start', gap:9,
      fontSize:12, color:'var(--text-3)', lineHeight:1.5,
    }}>
      <span style={{
        width:4, height:4, borderRadius:'50%',
        background:'var(--text-4)', marginTop:7, flexShrink:0,
      }} />
      <span>{children}</span>
    </li>
  );
}

// ════════════════════════════════════════════════════════════
// 2. MCP ACTIVITY TOAST
// Appears bottom-right when an MCP client calls a write tool.
// ════════════════════════════════════════════════════════════
function ToastStack() {
  // We render the PR view dimmed to give the toast a real context.
  return (
    <div style={{ width: W, height: H, position:'relative' }}>
      <div className="backdrop" />
      <div className="window" style={{ position:'relative', width:'100%', height:'100%' }}>
        <div className="titlebar">
          <div className="traffic"><span className="r"/><span className="y"/><span className="g"/></div>
          <div className="brand"><span className="brand-mark"/><span>Aerie</span></div>
        </div>
        <div style={{ flex:1, minHeight:0, overflow:'hidden', position:'relative' }}>
          <PRView />
          <div style={{
            position:'absolute', bottom:24, right:24,
            display:'flex', flexDirection:'column', gap:10, alignItems:'flex-end',
            pointerEvents:'none',
          }}>
            <MCPToast
              tool="merge_pr"
              target="cems-ui · #1234"
              agent="cc-session-7f2a"
              time="just now"
              status="success"
            />
            <MCPToast
              tool="hard_reset_to_default"
              target="shrike-renderer"
              agent="cc-session-7f2a"
              time="14:23:01"
              status="success"
            />
            <MCPToast
              tool="merge_pr"
              target="orbital-platform · #8814"
              agent="unknown agent"
              time="14:22:48"
              status="failed"
              error="merge conflict on db/migrations/2026_05_18_audit.sql"
            />
          </div>
        </div>
      </div>
    </div>
  );
}

function MCPToast({ tool, target, agent, time, status, error }) {
  const ok = status === 'success';
  return (
    <div style={{
      width: 340,
      background:'rgba(28, 26, 32, 0.86)',
      border:'1px solid ' + (ok ? 'var(--glass-line-2)' : 'oklch(0.74 0.165 26 / 0.40)'),
      borderRadius:12,
      backdropFilter:'blur(36px) saturate(180%)',
      WebkitBackdropFilter:'blur(36px) saturate(180%)',
      boxShadow:'0 12px 30px -8px rgba(0,0,0,0.6), inset 0 1px 0 0 var(--glass-highlight)',
      overflow:'hidden',
    }}>
      <div style={{ padding:'12px 14px', display:'flex', gap:10 }}>
        {/* Status icon */}
        <div style={{
          width:22, height:22, borderRadius:6, flexShrink:0,
          display:'flex', alignItems:'center', justifyContent:'center',
          background: ok ? 'oklch(0.82 0.13 158 / 0.18)' : 'oklch(0.74 0.165 26 / 0.18)',
          color: ok ? 'var(--ok)' : 'var(--err)',
          border:'1px solid ' + (ok ? 'oklch(0.82 0.13 158 / 0.32)' : 'oklch(0.74 0.165 26 / 0.36)'),
        }}>
          {ok
            ? <svg width="11" height="11" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round"><path d="M3 8.5l3.2 3 6.3-6.5"/></svg>
            : <svg width="11" height="11" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round"><path d="M4 4l8 8M12 4l-8 8"/></svg>
          }
        </div>

        <div style={{ flex:1, minWidth:0 }}>
          <div className="row" style={{ justifyContent:'space-between', gap:8 }}>
            <span className="mono" style={{ fontSize:12, color:'var(--text-1)' }}>
              <span style={{ color:'var(--amber)' }}>mcp</span> · {tool}
            </span>
            <span className="mono" style={{ fontSize:10, color:'var(--text-4)' }}>{time}</span>
          </div>
          <div style={{ fontSize:13, color:'var(--text-1)', marginTop:3 }}>
            {target}
          </div>
          <div className="row" style={{ justifyContent:'space-between', gap:8, marginTop:6 }}>
            <span className="mono" style={{ fontSize:11, color:'var(--text-3)' }}>by {agent}</span>
            <span style={{ fontSize:11, color: ok ? 'var(--ok)' : 'var(--err)' }}>{ok ? 'success' : 'failed'}</span>
          </div>
          {error && (
            <div style={{
              marginTop:8, padding:'6px 8px', borderRadius:5,
              background:'oklch(0.74 0.165 26 / 0.10)',
              border:'1px solid oklch(0.74 0.165 26 / 0.30)',
              fontFamily:'var(--font-mono)', fontSize:11, color:'var(--err)',
              lineHeight:1.4, wordBreak:'break-all',
            }}>{error}</div>
          )}
        </div>
      </div>
      <div style={{
        display:'flex', justifyContent:'flex-end', gap:8,
        padding:'7px 12px', borderTop:'1px solid var(--glass-line)',
        background:'rgba(0,0,0,0.18)',
      }}>
        <button style={{
          appearance:'none', border:0, background:'transparent',
          font:'500 11px var(--font-sans)', color:'var(--text-3)',
          padding:'2px 4px', cursor:'pointer',
        }}>View request</button>
      </div>
    </div>
  );
}

// ════════════════════════════════════════════════════════════
// 3. SETTINGS · MCP
// ════════════════════════════════════════════════════════════
function MCPSettingsBody() {
  return (
    <div style={{ flex:1, overflow:'hidden', padding:'34px 40px 40px' }}>
      <div className="section-eyebrow">MCP</div>
      <div className="row" style={{ justifyContent:'space-between', alignItems:'flex-end', marginTop:6 }}>
        <div className="row" style={{ gap:14, alignItems:'baseline' }}>
          <div className="section-title">Local MCP server</div>
          <div className="mono" style={{ fontSize:13, color:'var(--text-3)' }}>running · 7 tools exposed</div>
        </div>
        <div className="row" style={{ gap:8 }}>
          <button className="btn ghost sm">Rotate token now</button>
        </div>
      </div>

      {/* Server status */}
      <div className="card" style={{ padding:'18px 20px', marginTop:18 }}>
        <div className="row" style={{ gap:11, alignItems:'center' }}>
          <span className="dot ok" />
          <span style={{ fontSize:13.5, color:'var(--text-1)' }}>Server running</span>
          <span style={{ flex:1 }} />
          <span className="mono" style={{ fontSize:11, color:'var(--text-4)' }}>uptime 2h 14m · pid 81421</span>
        </div>

        <div style={{ marginTop:16, display:'grid', gridTemplateColumns:'130px 1fr auto', gap:'10px 16px', alignItems:'center' }}>
          <span className="mono" style={{ fontSize:11, color:'var(--text-4)', letterSpacing:'0.02em' }}>endpoint</span>
          <span className="mono" style={{ fontSize:12.5, color:'var(--text-1)' }}>http://127.0.0.1:47823/mcp</span>
          <button className="btn ghost sm">Copy</button>

          <span className="mono" style={{ fontSize:11, color:'var(--text-4)', letterSpacing:'0.02em' }}>bearer token</span>
          <div className="row" style={{ gap:8 }}>
            <span className="mono" style={{ fontSize:12.5, color:'var(--text-1)' }}>aer_••••••••••••••••</span>
            <button className="btn ghost sm" style={{ padding:'3px 7px' }}><EyeIcon /></button>
          </div>
          <button className="btn ghost sm">Copy</button>

          <span className="mono" style={{ fontSize:11, color:'var(--text-4)', letterSpacing:'0.02em' }}>discovery file</span>
          <span className="mono" style={{ fontSize:12.5, color:'var(--text-2)' }}>~/Library/Application Support/Aerie/mcp.json</span>
          <button className="btn ghost sm">Reveal</button>
        </div>
      </div>

      {/* Claude Code integration */}
      <div className="section-eyebrow" style={{ marginTop:28 }}>CLAUDE CODE INTEGRATION</div>
      <div className="card" style={{ padding:'18px 20px', marginTop:10 }}>
        <div className="row" style={{ gap:14, alignItems:'center' }}>
          <div className="col" style={{ flex:1, gap:4 }}>
            <span style={{ fontSize:14, color:'var(--text-1)' }}>Auto-register in <span className="mono">~/.claude/.mcp.json</span></span>
            <span style={{ fontSize:12, color:'var(--text-3)' }}>
              Every Claude Code session on this machine can discover Aerie automatically.
            </span>
          </div>
          <Toggle on={true} />
        </div>
        <div style={{
          marginTop:14, padding:'10px 12px', borderRadius:8,
          background:'oklch(0.82 0.13 158 / 0.10)',
          border:'1px solid oklch(0.82 0.13 158 / 0.30)',
          display:'flex', alignItems:'center', gap:10,
          fontSize:12.5, color:'var(--text-2)',
        }}>
          <span className="dot ok" />
          <span><span style={{ color:'var(--text-1)' }}>aerie</span> entry present · token in sync</span>
          <span style={{ flex:1 }} />
          <span className="mono" style={{ fontSize:11, color:'var(--text-4)' }}>last written 14s ago</span>
        </div>
      </div>

      {/* Recent activity */}
      <div className="row" style={{ marginTop:28, justifyContent:'space-between', alignItems:'baseline' }}>
        <div className="section-eyebrow">RECENT ACTIVITY</div>
        <span style={{ fontSize:11.5, color:'var(--text-3)', cursor:'pointer', borderBottom:'1px dashed var(--text-4)' }}>View all…</span>
      </div>
      <div className="card" style={{ marginTop:10, overflow:'hidden' }}>
        <div style={{
          display:'grid', gridTemplateColumns:'90px 150px 1fr 1fr 60px',
          padding:'10px 16px',
          background:'rgba(0,0,0,0.18)',
          borderBottom:'1px solid var(--glass-line)',
          fontFamily:'var(--font-mono)', fontSize:10, color:'var(--text-4)',
          letterSpacing:'0.12em', textTransform:'uppercase',
        }}>
          <span>time</span>
          <span>agent</span>
          <span>tool</span>
          <span>target</span>
          <span style={{ textAlign:'right' }}>result</span>
        </div>
        {[
          { time:'14:23:01', agent:'cc-session-7f2a', tool:'merge_pr',                target:'cems-ui · #1234',          ok:true  },
          { time:'14:23:00', agent:'cc-session-7f2a', tool:'list_open_prs',           target:'—',                         ok:true  },
          { time:'14:22:48', agent:'unknown',         tool:'merge_pr',                target:'orbital-platform · #8814', ok:false },
          { time:'14:22:30', agent:'cc-session-7f2a', tool:'hard_reset_to_default',   target:'shrike-renderer',          ok:true  },
          { time:'14:18:12', agent:'cc-session-9c11', tool:'get_repo_status',         target:'aerie',                    ok:true  },
          { time:'14:17:55', agent:'cc-session-9c11', tool:'list_open_prs',           target:'—',                         ok:true  },
        ].map((row, i, arr) => (
          <div key={i} style={{
            display:'grid', gridTemplateColumns:'90px 150px 1fr 1fr 60px',
            padding:'9px 16px', alignItems:'center',
            borderBottom: i<arr.length-1 ? '1px solid var(--glass-line)' : 'none',
            fontFamily:'var(--font-mono)', fontSize:12,
          }}>
            <span style={{ color:'var(--text-3)' }}>{row.time}</span>
            <span style={{ color:'var(--text-2)' }}>{row.agent}</span>
            <span style={{ color:'var(--text-1)' }}>{row.tool}</span>
            <span style={{ color:'var(--text-2)' }}>{row.target}</span>
            <span style={{ color: row.ok ? 'var(--ok)' : 'var(--err)', textAlign:'right' }}>{row.ok ? '✓' : '✕'}</span>
          </div>
        ))}
      </div>
    </div>
  );
}

function Toggle({ on }) {
  return (
    <div style={{
      width:38, height:22, borderRadius:999, padding:2,
      background: on ? 'var(--amber)' : 'var(--glass-3)',
      border:'1px solid ' + (on ? 'var(--amber-line)' : 'var(--glass-line-2)'),
      display:'flex',
      justifyContent: on ? 'flex-end' : 'flex-start',
      transition:'background 200ms',
      boxShadow: on ? '0 0 12px oklch(0.83 0.135 75 / 0.4)' : 'none',
      cursor:'pointer',
    }}>
      <div style={{
        width:16, height:16, borderRadius:'50%',
        background: on ? '#fff' : 'var(--text-2)',
        boxShadow:'0 1px 2px rgba(0,0,0,0.3)',
      }} />
    </div>
  );
}
function EyeIcon() {
  return (
    <svg width="13" height="13" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" style={{ color:'var(--text-2)' }}>
      <path d="M2 8s2.2-4 6-4 6 4 6 4-2.2 4-6 4S2 8 2 8z"/><circle cx="8" cy="8" r="1.6"/>
    </svg>
  );
}

function SettingsMCP() {
  return (
    <SettingsWindow title="Settings">
      <div style={{ flex:1, display:'flex', overflow:'hidden' }}>
        <SettingsSidebar active="mcp" />
        <div style={{ flex:1, display:'flex', flexDirection:'column', overflow:'hidden' }}>
          <MCPSettingsBody />
        </div>
      </div>
    </SettingsWindow>
  );
}

Object.assign(window, { DialogMCPConsent, ToastStack, SettingsMCP });
