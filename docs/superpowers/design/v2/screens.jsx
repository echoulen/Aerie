// Aerie v2 — two screens, glass material, dark, spacious.
// Exports: PRScreen, RepoScreen, AppFrame, atomic primitives.

const W = 1240;
const H = 880;

// ===== App shell =====
function AppFrame({ active='prs', children }) {
  return (
    <div className="mac-window-v2" style={{ width: W, height: H }}>
      <div className="aerie-stage" style={{ width: W, height: H, position: 'relative' }}>
        <TopBar active={active} />
        <div style={{
          position: 'absolute', inset: '88px 0 0 0',
          overflow: 'hidden',
          display: 'flex', justifyContent: 'center',
        }}>
          <div style={{ width: 960, padding: '12px 0 60px' }}>
            {children}
          </div>
        </div>
        <AmbientGlow />
      </div>
    </div>
  );
}

// Subtle amber spot in the top-right corner, like sunrise over the nest
function AmbientGlow() {
  return (
    <>
      <div style={{
        position: 'absolute', top: -180, right: -160, width: 520, height: 520,
        borderRadius: '50%',
        background: 'radial-gradient(circle, oklch(0.84 0.135 75 / 0.20) 0%, transparent 65%)',
        filter: 'blur(40px)',
        pointerEvents: 'none',
      }} />
      <div style={{
        position: 'absolute', bottom: -200, left: -180, width: 480, height: 480,
        borderRadius: '50%',
        background: 'radial-gradient(circle, oklch(0.35 0.10 240 / 0.20) 0%, transparent 65%)',
        filter: 'blur(40px)',
        pointerEvents: 'none',
      }} />
    </>
  );
}

function TopBar({ active }) {
  return (
    <div style={{
      position: 'absolute', top: 0, left: 0, right: 0, height: 56,
      display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      padding: '0 18px 0 16px',
      zIndex: 5,
      background: 'oklch(0.10 0.012 252 / 0.4)',
      backdropFilter: 'blur(20px) saturate(140%)',
      WebkitBackdropFilter: 'blur(20px) saturate(140%)',
      borderBottom: '1px solid var(--edge-1)',
      boxShadow: 'inset 0 -1px 0 0 oklch(1 0 0 / 0.03)',
    }}>
      {/* left: traffic lights + wordmark */}
      <div style={{ display:'flex', alignItems:'center', gap:18, width:240 }}>
        <div className="mac-traffic-v2">
          <span className="r" />
          <span className="y" />
          <span className="g" />
        </div>
        <div style={{ display:'flex', alignItems:'center', gap:9 }}>
          <div style={{
            width:14, height:14, borderRadius:'50%',
            background:'radial-gradient(circle at 32% 30%, var(--amber) 0%, var(--amber-deep) 70%, oklch(0.30 0.08 70) 100%)',
            boxShadow:'0 0 14px var(--amber-glow)',
          }} />
          <span style={{ fontFamily:'var(--font-serif)', fontWeight:400, fontSize:15, color:'var(--ink-1)', letterSpacing:'0.005em' }}>Aerie</span>
        </div>
      </div>

      {/* center: segmented toggle */}
      <SegmentedToggle active={active} />

      {/* right: status */}
      <div style={{ width:240, display:'flex', justifyContent:'flex-end', alignItems:'center', gap:14, fontFamily:'var(--font-mono)', fontSize:11, color:'var(--ink-4)' }}>
        <span style={{ display:'flex', alignItems:'center', gap:7 }}>
          <span className="dot" style={{ color:'var(--ok)', width:5, height:5 }} />
          live · 14s
        </span>
        <span style={{ width:1, height:14, background:'var(--edge-1)' }} />
        <span style={{ display:'inline-flex', alignItems:'center', justifyContent:'center', width:24, height:24, borderRadius:6, background:'var(--glass-2)', border:'1px solid var(--edge-1)' }}>
          <svg width="13" height="13" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round">
            <circle cx="8" cy="8" r="2"/>
            <path d="M8 1.5v2M8 12.5v2M3.4 3.4l1.4 1.4M11.2 11.2l1.4 1.4M1.5 8h2M12.5 8h2M3.4 12.6l1.4-1.4M11.2 4.8l1.4-1.4"/>
          </svg>
        </span>
      </div>
    </div>
  );
}

function SegmentedToggle({ active }) {
  const items = [
    { id:'prs', label:'Pull Requests', count: 13 },
    { id:'repos', label:'Repos', count: 16 },
  ];
  return (
    <div className="glass-thin" style={{
      display:'flex', borderRadius:11, padding:3, gap:2,
      background:'var(--glass-2)',
    }}>
      {items.map(it => {
        const on = it.id === active;
        return (
          <div key={it.id} style={{
            display:'flex', alignItems:'center', gap:10,
            padding:'7px 16px', borderRadius:8,
            cursor:'pointer',
            background: on ? 'var(--amber-soft)' : 'transparent',
            border: on ? '1px solid var(--amber-line)' : '1px solid transparent',
            color: on ? 'var(--amber)' : 'var(--ink-3)',
            fontSize:12.5,
            boxShadow: on ? 'inset 0 1px 0 0 oklch(1 0 0 / 0.10), 0 6px 18px -8px var(--amber-glow)' : 'none',
            transition:'all 120ms',
          }}>
            <span>{it.label}</span>
            <span style={{
              fontFamily:'var(--font-mono)', fontSize:10.5,
              padding:'1px 7px', borderRadius:999,
              background: on ? 'oklch(0.84 0.135 75 / 0.25)' : 'var(--glass-3)',
              color: on ? 'var(--amber)' : 'var(--ink-3)',
              letterSpacing:'0.02em',
            }}>{it.count}</span>
          </div>
        );
      })}
    </div>
  );
}

// ===== Section header =====
function ScreenHeader({ title, meta }) {
  return (
    <div style={{ padding: '28px 0 28px', display:'flex', alignItems:'baseline', justifyContent:'space-between' }}>
      <div>
        <div style={{ fontFamily:'var(--font-serif)', fontWeight:300, fontSize:30, color:'var(--ink-1)', letterSpacing:'-0.005em' }}>{title}</div>
        <div style={{ fontFamily:'var(--font-mono)', fontSize:11.5, color:'var(--ink-4)', marginTop:6, letterSpacing:'0.04em' }}>{meta}</div>
      </div>
      <div style={{ fontFamily:'var(--font-mono)', fontSize:11, color:'var(--ink-4)', display:'flex', gap:14, alignItems:'center' }}>
        <span>↻ next 14s</span>
      </div>
    </div>
  );
}

// ===== PR card =====
function PRCard({ pr, repo, primary }) {
  const ci = pr.ci;
  const review = pr.review;
  return (
    <div className="glass" style={{
      padding: '24px 28px',
      marginBottom: 14,
      display: 'grid',
      gridTemplateColumns: '1fr auto',
      columnGap: 32, alignItems: 'center',
      border: primary ? '1px solid oklch(0.84 0.135 75 / 0.22)' : '1px solid var(--edge-1)',
      boxShadow: primary
        ? 'inset 0 1px 0 0 var(--edge-top), 0 24px 60px -22px rgb(0 0 0 / 0.55), 0 0 0 1px oklch(0.84 0.135 75 / 0.08), 0 0 60px -20px var(--amber-glow)'
        : undefined,
    }}>
      {/* left: PR info */}
      <div style={{ minWidth: 0 }}>
        <div style={{ display:'flex', alignItems:'center', gap:10, fontFamily:'var(--font-mono)', fontSize:11, color:'var(--ink-4)', letterSpacing:'0.02em', whiteSpace:'nowrap' }}>
          <span style={{ color:'var(--ink-2)' }}>{pr.repo}</span>
          <span>·</span>
          <span>#{pr.num}</span>
          <span>·</span>
          <span>{pr.author}</span>
          <span style={{ flex:1 }} />
          <span>{pr.updated} ago</span>
        </div>

        <div style={{
          fontFamily:'var(--font-sans)', fontWeight:400, fontSize:19,
          color:'var(--ink-1)', lineHeight:1.35,
          margin:'10px 0 16px',
          letterSpacing:'-0.005em',
        }}>{pr.title}</div>

        {/* status row */}
        <div style={{ display:'flex', gap:18, alignItems:'center', flexWrap:'wrap' }}>
          <StatusChip kind="ci" value={ci} />
          <StatusChip kind="review" value={review} />
          {pr.labels.includes('review-ready') && (
            <span style={{
              fontFamily:'var(--font-mono)', fontSize:10.5,
              color:'var(--amber)', letterSpacing:'0.10em', textTransform:'uppercase',
            }}>ready to ship</span>
          )}
        </div>

        {/* divider */}
        <div style={{ height:1, background:'var(--edge-1)', margin:'18px 0 16px' }} />

        {/* local state */}
        <div style={{ display:'flex', alignItems:'center', gap:22, flexWrap:'nowrap', fontFamily:'var(--font-mono)', fontSize:12, whiteSpace:'nowrap' }}>
          <span style={{ display:'inline-flex', alignItems:'center', gap:8, color:'var(--ink-4)', fontSize:10.5, letterSpacing:'0.16em', textTransform:'uppercase' }}>
            local
          </span>
          <BranchTag name={repo.branch} dirty={repo.dirty} />
          {repo.dirty ? (
            <span style={{ color:'var(--warn)', display:'inline-flex', gap:6, alignItems:'center' }}>
              <span style={{ width:6, height:6, borderRadius:'50%', background:'var(--warn)', boxShadow:'0 0 8px oklch(0.85 0.13 88 / 0.7)' }} />
              dirty · 4 modified, 1 untracked
            </span>
          ) : (
            <span style={{ color:'var(--ink-4)' }}>clean</span>
          )}
          <Delta ahead={repo.ahead} behind={repo.behind} unpushed={repo.unpushed} />
        </div>
      </div>

      {/* right: actions */}
      <div style={{ display:'flex', flexDirection:'column', gap:10, alignItems:'stretch', minWidth:140 }}>
        <button className="glass-button amber" style={{
          padding:'14px 18px', fontSize:13, fontWeight:500,
          letterSpacing:'0.01em',
          display:'flex', alignItems:'center', justifyContent:'center', gap:8,
        }}>
          <PlayGlyph />
          Merge
        </button>
        <button className="glass-button" style={{
          padding:'10px 14px', fontSize:12, color:'var(--ink-2)',
          display:'flex', alignItems:'center', justifyContent:'center', gap:8,
        }}>
          Open ↗
        </button>
      </div>
    </div>
  );
}

function PlayGlyph() {
  return (
    <svg width="11" height="11" viewBox="0 0 12 12" fill="currentColor">
      <path d="M3 2.2L9.5 6 3 9.8z"/>
    </svg>
  );
}

function StatusChip({ kind, value }) {
  let icon, label, color;
  if (kind === 'ci') {
    if (value === 'pass')    { icon='✓'; label='ci passes';  color='var(--ok)'; }
    else if (value === 'fail'){ icon='✕'; label='ci failing'; color='var(--err)'; }
    else                     { icon='◐'; label='ci pending'; color='var(--warn)'; }
  } else {
    if (value === 'approved')   { icon='✓'; label='approved';            color='var(--ok)'; }
    else if (value === 'changes'){ icon='✕'; label='changes requested';  color='var(--err)'; }
    else                        { icon='·'; label='review requested';    color='var(--ink-3)'; }
  }
  return (
    <span style={{ display:'inline-flex', alignItems:'center', gap:7, color, fontFamily:'var(--font-sans)', fontSize:12.5, whiteSpace:'nowrap' }}>
      <span style={{ display:'inline-flex', width:14, height:14, alignItems:'center', justifyContent:'center', fontFamily:'var(--font-mono)', flexShrink:0 }}>{icon}</span>
      {label}
    </span>
  );
}

function BranchTag({ name, dirty }) {
  return (
    <span style={{
      display:'inline-flex', alignItems:'center', gap:8,
      padding:'4px 10px', borderRadius:6,
      background:'var(--glass-2)', border:'1px solid var(--edge-1)',
      color:'var(--ink-1)', fontFamily:'var(--font-mono)', fontSize:11.5,
    }}>
      <BranchGlyph />
      {name}
    </span>
  );
}

function BranchGlyph() {
  return (
    <svg width="11" height="11" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" style={{ opacity:0.7 }}>
      <circle cx="4" cy="3" r="1.4"/>
      <circle cx="4" cy="13" r="1.4"/>
      <circle cx="12" cy="6" r="1.4"/>
      <path d="M4 4.4v7.2"/>
      <path d="M4 8c4 0 7-1 7-2.6"/>
    </svg>
  );
}

function Delta({ ahead, behind, unpushed }) {
  const item = (sign, val, color) => (
    <span style={{ color: val>0 ? color : 'var(--ink-5)', display:'inline-flex', alignItems:'center', gap:4 }}>
      <span>{sign}</span>
      <span className="tabular">{val}</span>
    </span>
  );
  return (
    <span style={{ display:'inline-flex', gap:14, fontFamily:'var(--font-mono)', fontSize:12 }}>
      {item('↑', ahead,    'var(--ink-1)')}
      {item('↓', behind,   'var(--ink-1)')}
      {item('⤒', unpushed, 'var(--amber)')}
    </span>
  );
}

// ===== Repo card =====
function RepoCard({ repo }) {
  const isMain = repo.branch === 'main';
  const canReset = !(isMain && !repo.dirty && repo.behind === 0 && repo.unpushed === 0);
  return (
    <div className="glass" style={{
      padding:'22px 28px',
      marginBottom:12,
      display:'grid',
      gridTemplateColumns:'1fr auto',
      columnGap:24, alignItems:'center',
    }}>
      <div style={{ minWidth:0 }}>
        <div style={{ display:'flex', alignItems:'baseline', gap:10 }}>
          <span style={{ fontFamily:'var(--font-sans)', fontWeight:500, fontSize:17, color:'var(--ink-1)' }}>{repo.name}</span>
          <span style={{ fontFamily:'var(--font-mono)', fontSize:11, color:'var(--ink-4)' }}>{repo.owner}/{repo.name}</span>
        </div>

        <div style={{
          display:'flex', alignItems:'center', gap:20,
          marginTop:14, flexWrap:'nowrap',
          whiteSpace:'nowrap',
          fontFamily:'var(--font-mono)', fontSize:12,
        }}>
          <BranchTag name={repo.branch} dirty={repo.dirty} />
          {repo.dirty ? (
            <span style={{ color:'var(--warn)', display:'inline-flex', gap:6, alignItems:'center' }}>
              <span style={{ width:6, height:6, borderRadius:'50%', background:'var(--warn)', boxShadow:'0 0 8px oklch(0.85 0.13 88 / 0.7)' }} />
              uncommitted changes
            </span>
          ) : (
            <span style={{ color:'var(--ink-4)' }}>clean</span>
          )}
          <Delta ahead={repo.ahead} behind={repo.behind} unpushed={repo.unpushed} />
        </div>
      </div>

      <div style={{ display:'flex', gap:10 }}>
        <button className="glass-button" style={{
          padding:'11px 14px', fontSize:12, color:'var(--ink-2)',
          display:'flex', alignItems:'center', justifyContent:'center', gap:7,
        }}>Open ↗</button>
        <button className={'glass-button' + (canReset ? ' amber' : '')} style={{
          padding:'11px 18px', fontSize:12.5,
          opacity: canReset ? 1 : 0.55,
          display:'flex', alignItems:'center', justifyContent:'center', gap:8,
        }}>
          <ResetGlyph />
          Hard reset
        </button>
      </div>
    </div>
  );
}

function ResetGlyph() {
  return (
    <svg width="12" height="12" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
      <path d="M3 8a5 5 0 018.7-3.4L13 6"/>
      <path d="M13 3v3h-3"/>
    </svg>
  );
}

// ===== Screens =====
function PRScreen() {
  const repoByName = Object.fromEntries(REPOS.map(r => [r.name, r]));
  // hide repos with no local match (account fallback failed)
  const list = PRS.filter(p => repoByName[p.repo]);
  return (
    <AppFrame active="prs">
      <ScreenHeader
        title="Open pull requests"
        meta={`${list.length} open · across 5 repositories · 7 mine`}
      />
      {list.slice(0, 6).map((pr, i) => (
        <PRCard
          key={pr.id}
          pr={pr}
          repo={repoByName[pr.repo]}
          primary={i === 0}
        />
      ))}
    </AppFrame>
  );
}

function RepoScreen() {
  // Hide repos that are 'noacc' from the main list? show but disable.
  const list = REPOS.slice(0, 7);
  return (
    <AppFrame active="repos">
      <ScreenHeader
        title="Repositories"
        meta={`16 in the fleet · 4 with uncommitted changes`}
      />
      {list.map(r => <RepoCard key={r.id} repo={r} />)}
    </AppFrame>
  );
}

Object.assign(window, { AppFrame, PRScreen, RepoScreen });
