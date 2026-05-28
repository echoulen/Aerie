// Confirmation dialogs — Reset, Merge, Sign out, Remove
// Shown on the same window chrome as their parent screens (dimmed backdrop + glass card)

function DialogShell({ children, parent='prs' }) {
  // Renders the parent window with a dimming layer + the dialog centered on top
  return (
    <div style={{ width: W, height: H, position:'relative' }}>
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
            <span>Aerie</span>
          </div>
        </div>
        {/* Dimmed parent — render a muted version of the relevant view */}
        <div style={{ position:'relative', flex:1, minHeight:0, overflow:'hidden' }}>
          <div style={{ filter:'blur(2px) saturate(0.8)', opacity:0.55, height:'100%', display:'flex', flexDirection:'column' }}>
            {parent === 'prs'   && <PRView />}
            {parent === 'repos' && <RepoView />}
          </div>
          <div style={{
            position:'absolute', inset:0,
            background:'rgba(0,0,0,0.45)',
            display:'flex', alignItems:'center', justifyContent:'center',
            padding:40,
          }}>
            {children}
          </div>
        </div>
      </div>
    </div>
  );
}

// Dialog body — glass with a thicker blur (cards on glass already look great
// in macOS Sequoia). Generous padding, single big title, structured key/value rows.
function Dialog({ icon, tone='neutral', title, subtitle, children, primary, primaryVariant='amber', secondary='Cancel' }) {
  const accentRing =
    tone==='danger' ? 'oklch(0.74 0.165 26 / 0.45)' :
    tone==='amber'  ? 'var(--amber-line)' :
                      'var(--glass-line-2)';
  const iconBg =
    tone==='danger' ? 'oklch(0.74 0.165 26 / 0.18)' :
    tone==='amber'  ? 'var(--amber-soft)' :
                      'var(--glass-2)';
  const iconColor =
    tone==='danger' ? 'oklch(0.85 0.14 26)' :
    tone==='amber'  ? 'var(--amber)' :
                      'var(--text-2)';

  return (
    <div style={{
      width: 520, maxWidth:'92%',
      background:'rgba(28, 26, 32, 0.78)',
      border:'1px solid '+accentRing,
      borderRadius:18,
      backdropFilter:'blur(48px) saturate(180%)',
      WebkitBackdropFilter:'blur(48px) saturate(180%)',
      boxShadow:'0 30px 80px -20px rgba(0,0,0,0.7), inset 0 1px 0 0 var(--glass-highlight)',
      overflow:'hidden',
    }}>
      <div style={{ padding:'26px 28px 18px' }}>
        <div className="row" style={{ gap:14, alignItems:'flex-start' }}>
          <div style={{
            width:36, height:36, borderRadius:10,
            background: iconBg,
            border:'1px solid '+accentRing,
            color: iconColor,
            display:'flex', alignItems:'center', justifyContent:'center',
            flexShrink:0,
          }}>{icon}</div>
          <div style={{ flex:1, minWidth:0 }}>
            <div style={{ fontSize:17, fontWeight:500, color:'var(--text-1)', letterSpacing:'-0.005em' }}>{title}</div>
            {subtitle && <div style={{ fontSize:13, color:'var(--text-3)', marginTop:4, lineHeight:1.5 }}>{subtitle}</div>}
          </div>
        </div>
        {children && <div style={{ marginTop:18 }}>{children}</div>}
      </div>
      <div style={{
        display:'flex', justifyContent:'flex-end', gap:8,
        padding:'14px 20px',
        background:'rgba(0,0,0,0.18)',
        borderTop:'1px solid var(--glass-line)',
      }}>
        <button className="btn ghost">{secondary}</button>
        <button className={'btn ' + primaryVariant}>{primary}</button>
      </div>
    </div>
  );
}

function KVList({ rows }) {
  return (
    <div style={{
      borderRadius:10,
      border:'1px solid var(--glass-line)',
      background:'rgba(0,0,0,0.22)',
      padding:'2px 14px',
    }}>
      {rows.map(([k, v], i) => (
        <div key={i} style={{
          display:'grid', gridTemplateColumns:'130px 1fr',
          gap:14, padding:'9px 0',
          borderBottom: i < rows.length-1 ? '1px solid var(--glass-line)' : 'none',
        }}>
          <span className="mono" style={{ fontSize:11, color:'var(--text-4)', letterSpacing:'0.02em' }}>{k}</span>
          <span style={{ fontSize:13, color:'var(--text-1)' }}>{v}</span>
        </div>
      ))}
    </div>
  );
}

// ─── Specific dialogs ───────────────────────────────────────

function DialogReset() {
  return (
    <DialogShell parent="repos">
      <Dialog
        tone="danger"
        icon={<WarnIcon />}
        title="Hard reset aerie to origin/main?"
        subtitle="This will run git reset --hard. Local commits and uncommitted changes on the current branch will be discarded."
        primary="Reset to origin/main"
        primaryVariant="danger"
      >
        <KVList rows={[
          ['repository',    <span className="mono">carlos-li/aerie</span>],
          ['current branch',<span className="mono">feat/virtual-clock</span>],
          ['working tree',  <span style={{ color:'var(--err)' }}>● dirty · 4 modified, 1 untracked</span>],
          ['unpushed',      <span style={{ color:'var(--amber)' }}>2 commits on this branch</span>],
          ['target',        <span className="mono">origin/main @ a91f3c2</span>],
        ]} />
      </Dialog>
    </DialogShell>
  );
}

function DialogMerge() {
  return (
    <DialogShell parent="prs">
      <Dialog
        tone="amber"
        icon={<MergeIcon />}
        title="Merge pull request #142?"
        subtitle="Squash and merge using carlos-li. The source branch will be deleted on github.com after merging."
        primary="Merge"
        primaryVariant="amber"
      >
        <div style={{
          padding:'14px 16px',
          borderRadius:10, border:'1px solid var(--glass-line)',
          background:'rgba(0,0,0,0.22)',
        }}>
          <div className="mono" style={{ fontSize:11, color:'var(--text-4)' }}>aerie · #142</div>
          <div style={{ fontSize:14.5, color:'var(--text-1)', marginTop:5 }}>PollingScheduler: virtual clock for tests</div>
          <div className="row" style={{ gap:14, marginTop:10, fontSize:12 }}>
            <span style={{ color:'var(--ok)' }}>✓ 12/12 checks</span>
            <span style={{ color:'var(--ok)' }}>✓ approved by maja-c</span>
            <span style={{ color:'var(--text-3)' }}>
              <span className="mono" style={{ color:'var(--ok)' }}>+312</span>{' '}
              <span className="mono" style={{ color:'var(--err)' }}>-184</span>{' '}
              · 7 files
            </span>
          </div>
        </div>
        <div style={{ marginTop:12 }}>
          <KVList rows={[
            ['method',      <span className="mono">squash + merge</span>],
            ['commit subj', <span className="mono">PollingScheduler: virtual clock (#142)</span>],
            ['account',     <span className="mono">carlos-li · github.com</span>],
          ]} />
        </div>
      </Dialog>
    </DialogShell>
  );
}

function DialogSignOut() {
  return (
    <DialogShell parent="prs">
      <Dialog
        tone="danger"
        icon={<KeyOffIcon />}
        title="Sign cli-work out of Aerie?"
        subtitle="Aerie will stop using this identity. 2 repositories tracked with this account will go into a no-access state until you re-authenticate via gh CLI."
        primary="Sign out"
        primaryVariant="danger"
      >
        <KVList rows={[
          ['account',  <span className="mono">cli-work @ github.com</span>],
          ['scopes',   <span className="mono">repo · read:org</span>],
          ['affected', <span>2 repositories: <span className="mono" style={{ color:'var(--text-2)' }}>orbital-platform</span>, <span className="mono" style={{ color:'var(--text-2)' }}>shrike-renderer</span></span>],
          ['note',     <span style={{ color:'var(--text-3)' }}>Tokens were never persisted — gh CLI keeps them.</span>],
        ]} />
      </Dialog>
    </DialogShell>
  );
}

function DialogRemoveRepo() {
  return (
    <DialogShell parent="repos">
      <Dialog
        tone="neutral"
        icon={<TrashIcon />}
        title="Stop tracking sketchpad?"
        subtitle="Aerie will stop polling this repository and remove it from your views. Your local files and .git/ are not touched — you can add the repo back any time."
        primary="Stop tracking"
        primaryVariant="danger"
      >
        <KVList rows={[
          ['display name', 'sketchpad'],
          ['path',         <span className="mono">~/code/sketchpad</span>],
          ['github',       <span className="mono">carlos-li/sketchpad</span>],
          ['will delete',  <span style={{ color:'var(--ok)' }}>nothing — files are untouched</span>],
        ]} />
      </Dialog>
    </DialogShell>
  );
}

// ─── Icons used in dialog headers ───
function WarnIcon() { return (
  <svg width="18" height="18" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
    <path d="M8 1.6l6.2 11.2H1.8z"/><path d="M8 6v3.6"/><circle cx="8" cy="11.7" r="0.6" fill="currentColor"/>
  </svg>
); }
function MergeIcon() { return (
  <svg width="18" height="18" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
    <circle cx="4" cy="3" r="1.5"/><circle cx="4" cy="13" r="1.5"/><circle cx="12" cy="13" r="1.5"/>
    <path d="M4 4.5v7"/><path d="M12 7v4.5"/><path d="M8.5 2.5l3 3-3 0"/>
  </svg>
); }
function KeyOffIcon() { return (
  <svg width="18" height="18" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
    <circle cx="5" cy="11" r="2.6"/><path d="M7 9l5-5"/><path d="M2 2l12 12"/>
  </svg>
); }
function TrashIcon() { return (
  <svg width="18" height="18" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
    <path d="M3 4.5h10"/><path d="M5 4.5V3a1 1 0 011-1h4a1 1 0 011 1v1.5"/>
    <path d="M4.5 4.5L5 13a1 1 0 001 1h4a1 1 0 001-1l.5-8.5"/>
  </svg>
); }

Object.assign(window, { DialogReset, DialogMerge, DialogSignOut, DialogRemoveRepo, DialogShell, Dialog, KVList });
