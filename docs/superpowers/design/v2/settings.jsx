// Aerie v2 — Settings
// Same glass shell as the main app. Sidebar with two sections: Accounts, Repositories.

const SET_W = 1040;
const SET_H = 760;

// ─── Settings window chrome (slightly different titlebar — center text "Settings") ───
function SettingsWindow({ children, title='Settings' }) {
  return (
    <div style={{ width: SET_W, height: SET_H, position: 'relative' }}>
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
            <span>Aerie · {title}</span>
          </div>
        </div>
        {children}
      </div>
    </div>
  );
}

// ─── Sidebar ───
function SettingsSidebar({ active }) {
  const Item = ({ id, label, icon, count }) => (
    <div style={{
      display:'flex', alignItems:'center', gap:11,
      padding:'9px 14px',
      borderRadius:9,
      background: id===active ? 'var(--glass-3)' : 'transparent',
      border: id===active ? '1px solid var(--glass-line)' : '1px solid transparent',
      color: id===active ? 'var(--text-1)' : 'var(--text-2)',
      cursor:'pointer',
    }}>
      <span style={{ color: id===active ? 'var(--amber)' : 'var(--text-3)', display:'inline-flex' }}>{icon}</span>
      <span style={{ fontSize:13, flex:1 }}>{label}</span>
      {count!=null && (
        <span className="mono" style={{ fontSize:11, color:'var(--text-4)' }}>{count}</span>
      )}
    </div>
  );
  return (
    <div style={{
      width:220, flexShrink:0,
      borderRight:'1px solid var(--glass-line)',
      padding:'18px 12px',
      display:'flex', flexDirection:'column', gap:4,
    }}>
      <div className="section-eyebrow" style={{ padding:'4px 14px 10px' }}>SETTINGS</div>
      <Item id="accounts"     label="Accounts"     count={3}  icon={<KeyIcon />} />
      <Item id="repositories" label="Repositories" count={9}  icon={<FolderIcon />} />
      <Item id="mcp"          label="MCP"          count={<span style={{ color:'var(--ok)' }}>●</span>}  icon={<PlugIcon />} />
      <Item id="advanced"     label="Advanced"                icon={<SlidersIcon />} />
      <div style={{ flex:1 }} />
      <Item id="about"        label="About"                   icon={<InfoIcon />} />
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// ACCOUNTS
// ─────────────────────────────────────────────────────────────
function AccountsScreen() {
  const accounts = [
    {
      id:'a1', login:'carlos-li', host:'github.com',
      avatar:'CL', tone:'amber',
      scopes:['repo','read:org','workflow'],
      primary:true,
      status:'active',
      repos:6, lastUsed:'14s ago',
    },
    {
      id:'a2', login:'cli-work', host:'github.com',
      avatar:'CW', tone:'blue',
      scopes:['repo','read:org'],
      primary:false,
      status:'active',
      repos:2, lastUsed:'2m ago',
    },
    {
      id:'a3', login:'c-internal', host:'ghe.orbital.dev',
      avatar:'CI', tone:'violet',
      scopes:['repo','read:org','workflow','admin:org'],
      primary:false,
      status:'active',
      repos:1, lastUsed:'4m ago',
    },
  ];

  return (
    <div style={{ flex:1, overflow:'hidden', padding:'34px 40px 40px' }}>
      <div className="section-eyebrow">ACCOUNTS</div>
      <div style={{ display:'flex', justifyContent:'space-between', alignItems:'flex-end', marginTop:6 }}>
        <div className="row" style={{ gap:14, alignItems:'baseline' }}>
          <div className="section-title">GitHub identities</div>
          <div className="mono" style={{ fontSize:13, color:'var(--text-3)' }}>3 accounts · via gh CLI</div>
        </div>
        <button className="btn ghost sm">↻ Rescan ⌘R</button>
      </div>

      {/* gh status banner */}
      <div className="card" style={{
        marginTop:22, padding:'14px 18px',
        display:'flex', alignItems:'center', gap:14,
      }}>
        <span className="dot ok" />
        <span style={{ fontSize:13.5, color:'var(--text-1)' }}>
          gh CLI <span className="mono" style={{ color:'var(--text-3)' }}>2.62.0</span> is authenticated to 3 hosts.
        </span>
        <span style={{ flex:1 }} />
        <span className="mono" style={{ fontSize:11.5, color:'var(--text-3)' }}>tokens kept in memory only</span>
      </div>

      {/* Account cards */}
      <div className="col" style={{ gap:12, marginTop:18 }}>
        {accounts.map(a => <AccountCard key={a.id} a={a} />)}
      </div>

      {/* Add account */}
      <div className="section-eyebrow" style={{ marginTop:32 }}>ADD ANOTHER ACCOUNT</div>
      <div className="card" style={{ padding:'18px 20px', marginTop:10 }}>
        <div style={{ fontSize:13.5, color:'var(--text-2)', lineHeight:1.55 }}>
          Run this in a terminal — Aerie will pick the new account up automatically within a few seconds.
        </div>
        <div style={{
          marginTop:12, padding:'12px 14px',
          background:'rgba(0,0,0,0.32)',
          border:'1px solid var(--glass-line)',
          borderRadius:8,
          display:'flex', alignItems:'center', gap:12,
        }}>
          <span className="mono" style={{ color:'var(--text-4)' }}>$</span>
          <span className="mono" style={{ flex:1, fontSize:13, color:'var(--text-1)' }}>
            gh auth login --hostname github.com --git-protocol ssh
          </span>
          <button className="btn sm">Copy</button>
        </div>
      </div>
    </div>
  );
}

function AccountCard({ a }) {
  const avatarBg = {
    amber:  'radial-gradient(circle at 30% 30%, oklch(0.88 0.14 78), oklch(0.50 0.13 60))',
    blue:   'radial-gradient(circle at 30% 30%, oklch(0.80 0.13 240), oklch(0.45 0.13 260))',
    violet: 'radial-gradient(circle at 30% 30%, oklch(0.78 0.13 300), oklch(0.42 0.13 290))',
  }[a.tone];

  return (
    <div className="card" style={{
      padding:'18px 20px',
      display:'grid',
      gridTemplateColumns:'auto 1fr auto',
      columnGap:18,
      alignItems:'center',
    }}>
      {/* Avatar */}
      <div style={{
        width:42, height:42, borderRadius:'50%',
        background: avatarBg,
        display:'flex', alignItems:'center', justifyContent:'center',
        fontFamily:'var(--font-mono)', fontSize:13, fontWeight:500,
        color:'oklch(0.15 0.02 70)',
        boxShadow:'inset 0 1px 0 0 rgba(255,255,255,0.35)',
      }}>{a.avatar}</div>

      {/* Identity */}
      <div className="col" style={{ gap:6, minWidth:0 }}>
        <div className="row" style={{ gap:10, alignItems:'baseline' }}>
          <span style={{ fontSize:16, fontWeight:500, color:'var(--text-1)' }}>{a.login}</span>
          <span className="mono" style={{ fontSize:12, color:'var(--text-3)' }}>@ {a.host}</span>
          {a.primary && <span className="pill amber" style={{ padding:'1px 7px', fontSize:10 }}>primary</span>}
        </div>
        <div className="row" style={{ gap:14, fontSize:12, color:'var(--text-3)' }}>
          <span><span className="dot ok" style={{ marginRight:6, verticalAlign:'middle' }} />signed in</span>
          <span>{a.repos} repos</span>
          <span>last call {a.lastUsed}</span>
          <span className="mono" style={{ fontSize:11 }}>scopes: {a.scopes.join(' · ')}</span>
        </div>
      </div>

      {/* Actions */}
      <div className="row" style={{ gap:8 }}>
        {!a.primary && <button className="btn ghost sm">Make primary</button>}
        <button className="btn ghost sm">Sign out…</button>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// REPOSITORIES
// ─────────────────────────────────────────────────────────────
function RepositoriesScreen() {
  const repos = [
    { id:'r1', name:'aerie',            path:'~/code/aerie',                  gh:'carlos-li/aerie',           account:'carlos-li',  branch:'feat/virtual-clock',  status:'dirty'  },
    { id:'r2', name:'shrike-renderer',  path:'~/code/orbital/shrike-renderer',gh:'orbital/shrike-renderer',   account:'cli-work',   branch:'perf/glyph-cache',    status:'dirty'  },
    { id:'r3', name:'orbital-platform', path:'~/code/orbital/platform',       gh:'orbital/orbital-platform',  account:'cli-work',   branch:'main',                status:'clean'  },
    { id:'r4', name:'orbital-cli',      path:'~/code/orbital/cli',            gh:'orbital/orbital-cli',       account:'cli-work',   branch:'fix/auth-fallback',   status:'clean'  },
    { id:'r5', name:'libgit2-swift',    path:'~/code/vendor/libgit2-swift',   gh:'orbital/libgit2-swift',     account:'cli-work',   branch:'rc/0.18',             status:'behind' },
    { id:'r6', name:'falcon-edge',      path:'~/code/orbital/falcon-edge',    gh:'orbital/falcon-edge',       account:'cli-work',   branch:'main',                status:'clean'  },
    { id:'r7', name:'aerie-website',    path:'~/code/aerie-website',          gh:'carlos-li/aerie-website',   account:'carlos-li',  branch:'main',                status:'clean'  },
    { id:'r8', name:'sketchpad',        path:'~/code/sketchpad',              gh:'carlos-li/sketchpad',       account:'carlos-li',  branch:'wip-canvas-refactor', status:'dirty'  },
  ];

  return (
    <div style={{ flex:1, display:'flex', flexDirection:'column', overflow:'hidden' }}>
      {/* Header */}
      <div style={{ padding:'34px 40px 18px' }}>
        <div className="section-eyebrow">REPOSITORIES</div>
        <div style={{ display:'flex', justifyContent:'space-between', alignItems:'flex-end', marginTop:6 }}>
          <div className="row" style={{ gap:14, alignItems:'baseline' }}>
            <div className="section-title">Tracked locally</div>
            <div className="mono" style={{ fontSize:13, color:'var(--text-3)' }}>{repos.length} repositories</div>
          </div>
          <div className="row" style={{ gap:8 }}>
            <button className="btn ghost sm">↻ Refresh all</button>
            <button className="btn amber">+ Add repository</button>
          </div>
        </div>
      </div>

      {/* Column legend — only as a faint guide above the cards */}
      <div style={{
        padding:'0 40px',
        display:'grid',
        gridTemplateColumns:'18px 1fr 1.3fr 130px 28px',
        columnGap:18,
        marginBottom:6,
      }}>
        <span />
        <span className="section-eyebrow" style={{ fontSize:9, letterSpacing:'0.20em' }}>NAME · PATH</span>
        <span className="section-eyebrow" style={{ fontSize:9, letterSpacing:'0.20em' }}>GITHUB · CURRENT BRANCH</span>
        <span className="section-eyebrow" style={{ fontSize:9, letterSpacing:'0.20em' }}>ACCOUNT</span>
        <span />
      </div>

      {/* Repo rows — single glass shell containing all rows for tighter rhythm */}
      <div style={{ padding:'0 40px 40px', flex:1, overflow:'hidden' }}>
        <div className="card" style={{ padding:0, overflow:'hidden' }}>
          {repos.map((r, i) => <RepoSettingsRow key={r.id} r={r} first={i===0} last={i===repos.length-1} />)}
        </div>
      </div>
    </div>
  );
}

function RepoSettingsRow({ r, first, last }) {
  return (
    <div style={{
      display:'grid',
      gridTemplateColumns:'18px 1fr 1.3fr 130px 28px',
      columnGap:18,
      alignItems:'center',
      padding:'16px 20px',
      borderBottom: last ? 'none' : '1px solid var(--glass-line)',
    }}>
      {/* Grip */}
      <span style={{ color:'var(--text-4)', cursor:'grab', fontSize:14, lineHeight:1 }}>⠿</span>

      {/* Name + path */}
      <div className="col" style={{ gap:3, minWidth:0 }}>
        <span style={{ fontSize:14.5, fontWeight:500, color:'var(--text-1)' }}>{r.name}</span>
        <span className="mono" style={{ fontSize:11.5, color:'var(--text-3)', whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis' }}>{r.path}</span>
      </div>

      {/* gh + branch */}
      <div className="col" style={{ gap:3, minWidth:0 }}>
        <span className="mono" style={{ fontSize:12.5, color:'var(--text-2)' }}>{r.gh}</span>
        <span className="row" style={{ gap:8 }}>
          <BranchTiny />
          <span className="mono" style={{ fontSize:11.5, color:'var(--text-3)' }}>{r.branch}</span>
          {r.status === 'dirty' && <span className="dot warn" style={{ width:5, height:5 }} />}
          {r.status === 'behind' && <span className="dot" style={{ width:5, height:5, background:'var(--amber)' }} />}
        </span>
      </div>

      {/* Account */}
      <div className="row" style={{ gap:8 }}>
        <span style={{
          width:18, height:18, borderRadius:'50%',
          background: r.account==='carlos-li'
            ? 'radial-gradient(circle at 30% 30%, oklch(0.88 0.14 78), oklch(0.50 0.13 60))'
            : 'radial-gradient(circle at 30% 30%, oklch(0.80 0.13 240), oklch(0.45 0.13 260))',
          flexShrink:0,
        }} />
        <span className="mono" style={{ fontSize:12, color:'var(--text-2)' }}>{r.account}</span>
      </div>

      {/* Remove */}
      <span style={{ color:'var(--text-4)', cursor:'pointer', display:'inline-flex', justifyContent:'flex-end' }}>
        <XIcon />
      </span>
    </div>
  );
}

// ─── Icons ───
function KeyIcon() { return (
  <svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round">
    <circle cx="5" cy="11" r="3"/><path d="M7 9l6.5-6.5"/><path d="M11 5l2 2"/>
  </svg>
); }
function FolderIcon() { return (
  <svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round">
    <path d="M2 4.5a1 1 0 011-1h3l1.5 1.5h5.5a1 1 0 011 1V12a1 1 0 01-1 1H3a1 1 0 01-1-1z"/>
  </svg>
); }
function InfoIcon() { return (
  <svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round">
    <circle cx="8" cy="8" r="6"/><path d="M8 7.2v4"/><circle cx="8" cy="5" r="0.5" fill="currentColor"/>
  </svg>
); }
function PlugIcon() { return (
  <svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round">
    <path d="M5 2v3M11 2v3"/><path d="M3.5 5h9v3a4.5 4.5 0 11-9 0z"/><path d="M8 12.5V15"/>
  </svg>
); }
function SlidersIcon() { return (
  <svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round">
    <path d="M2 4h7M11 4h3M2 12h3M7 12h7"/><circle cx="10" cy="4" r="1.5"/><circle cx="6" cy="12" r="1.5"/>
  </svg>
); }
function XIcon() { return (
  <svg width="13" height="13" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round">
    <path d="M4 4l8 8M12 4l-8 8"/>
  </svg>
); }
function BranchTiny() { return (
  <svg width="11" height="11" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" style={{ color:'var(--text-4)' }}>
    <circle cx="4" cy="3" r="1.4"/><circle cx="4" cy="13" r="1.4"/><circle cx="12" cy="6" r="1.4"/>
    <path d="M4 4.4v7.2"/><path d="M4 8c4 0 7-1 7-2.6"/>
  </svg>
); }

// ─── Composed screens (sidebar + body) ───
function SettingsAccounts() {
  return (
    <SettingsWindow title="Settings">
      <div style={{ flex:1, display:'flex', overflow:'hidden' }}>
        <SettingsSidebar active="accounts" />
        <div style={{ flex:1, display:'flex', flexDirection:'column', overflow:'hidden' }}>
          <AccountsScreen />
        </div>
      </div>
    </SettingsWindow>
  );
}
function SettingsRepositories() {
  return (
    <SettingsWindow title="Settings">
      <div style={{ flex:1, display:'flex', overflow:'hidden' }}>
        <SettingsSidebar active="repositories" />
        <div style={{ flex:1, display:'flex', flexDirection:'column', overflow:'hidden' }}>
          <RepositoriesScreen />
        </div>
      </div>
    </SettingsWindow>
  );
}

Object.assign(window, { SettingsAccounts, SettingsRepositories, SettingsSidebar, SettingsWindow, RepositoriesScreen, SET_W, SET_H });
