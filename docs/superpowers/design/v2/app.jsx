// Aerie v2 — two views only: PRs · Repos. Glass, dark, breathing whitespace.

const W = 1280;
const H = 860;

// ─────────────────────────────────────────────────────────────
// Window chrome (titlebar with traffic lights + centered title)
// ─────────────────────────────────────────────────────────────
function Window({ children }) {
  return (
    <div style={{ width: W, height: H, position: 'relative' }}>
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
        {children}
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Header — page eyebrow + title + count + segmented switch + filter
// ─────────────────────────────────────────────────────────────
function Header({ eyebrow, title, count, active }) {
  return (
    <div style={{ padding: '34px 44px 24px' }}>
      <div className="section-eyebrow">{eyebrow}</div>
      <div className="row" style={{ justifyContent: 'space-between', alignItems: 'flex-end', marginTop: 6 }}>
        <div className="row" style={{ gap: 14, alignItems: 'baseline' }}>
          <div className="section-title">{title}</div>
          <div className="mono" style={{ color: 'var(--text-3)', fontSize: 13, letterSpacing: '0.02em' }}>
            {count}
          </div>
        </div>
        <div className="row" style={{ gap: 12 }}>
          <div className="segmented">
            <button className={active === 'prs' ? 'active' : ''}>Pull Requests</button>
            <button className={active === 'repos' ? 'active' : ''}>Repositories</button>
          </div>
        </div>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// PR card — the whole row is one piece of glass
// ─────────────────────────────────────────────────────────────
function PRCard({ pr }) {
  const ciOk = pr.ci === 'pass';
  const approved = pr.review === 'approved';
  const mergeable = ciOk && approved;

  // Localised status — single sentence, no decoration unless it matters
  let localState;
  const L = pr.local;
  if (!L.checkedOut) {
    localState = { tone: 'muted', text: 'Not checked out locally' };
  } else if (L.dirty) {
    localState = { tone: 'warn', text: `Branch checked out · working tree dirty` };
  } else if (L.ahead > 0 || L.behind > 0 || L.unpushed > 0) {
    const bits = [];
    if (L.ahead)    bits.push(`${L.ahead} ahead`);
    if (L.behind)   bits.push(`${L.behind} behind`);
    if (L.unpushed) bits.push(`${L.unpushed} unpushed`);
    localState = { tone: 'amber', text: `Branch checked out · ${bits.join(' · ')}` };
  } else {
    localState = { tone: 'ok', text: 'Branch checked out · clean & in sync' };
  }

  return (
    <div className="card" style={{
      padding: '22px 26px',
      display: 'grid',
      gridTemplateColumns: '1fr auto',
      columnGap: 28,
      alignItems: 'center',
    }}>
      {/* Left — meta, title, status row */}
      <div className="col" style={{ gap: 12, minWidth: 0 }}>
        <div className="row" style={{ gap: 10, color: 'var(--text-3)', fontSize: 12 }}>
          <span className="mono" style={{ color: 'var(--text-2)' }}>{pr.repo}</span>
          <span style={{ color: 'var(--text-4)' }}>·</span>
          <span className="mono">#{pr.num}</span>
          <span style={{ color: 'var(--text-4)' }}>·</span>
          <span>{pr.author}</span>
          {pr.mine && <span className="pill amber" style={{ padding: '1px 7px', fontSize: 10, marginLeft: 4 }}>yours</span>}
          <span style={{ flex: 1 }} />
          <span style={{ color: 'var(--text-4)' }}>{pr.updated} ago</span>
        </div>

        <div style={{
          fontSize: 18, fontWeight: 500, color: 'var(--text-1)',
          letterSpacing: '-0.005em', lineHeight: 1.35,
        }}>{pr.title}</div>

        <div className="row" style={{ gap: 10, marginTop: 4, flexWrap: 'wrap' }}>
          <CIStatus state={pr.ci} />
          <ReviewStatus state={pr.review} />
          <LocalStatus tone={localState.tone} text={localState.text} />
        </div>
      </div>

      {/* Right — actions */}
      <div className="row" style={{ gap: 8 }}>
        <button className="btn ghost sm">Open ↗</button>
        <button
          className={'btn ' + (mergeable ? 'amber' : '')}
          style={mergeable ? {} : { opacity: 0.45, cursor: 'not-allowed' }}
        >
          {mergeable ? 'Merge' : 'Merge'}
        </button>
      </div>
    </div>
  );
}

function CIStatus({ state }) {
  if (state === 'pass')    return <span className="pill ok"><span className="dot ok" /> CI passing</span>;
  if (state === 'fail')    return <span className="pill err"><span className="dot err" /> CI failing</span>;
  return <span className="pill warn"><span className="dot warn" /> CI pending</span>;
}
function ReviewStatus({ state }) {
  if (state === 'approved') return <span className="pill ok">Approved</span>;
  if (state === 'changes')  return <span className="pill err">Changes requested</span>;
  return <span className="pill">Review requested</span>;
}
function LocalStatus({ tone, text }) {
  // tone: ok | warn | amber | muted
  const cls = tone === 'muted' ? 'pill' : `pill ${tone}`;
  return <span className={cls} style={tone === 'muted' ? { color:'var(--text-3)' } : {}}>{text}</span>;
}

// ─────────────────────────────────────────────────────────────
// PR view
// ─────────────────────────────────────────────────────────────
function PRView() {
  return (
    <div className="col" style={{ flex: 1, minHeight: 0 }}>
      <Header
        eyebrow="VIEW · ⌘1"
        title="Open pull requests"
        count={`${V2_PRS.length} open · ${V2_PRS.filter(p=>p.ci==='pass'&&p.review==='approved').length} ready to merge`}
        active="prs"
      />
      <div style={{ flex: 1, overflow: 'hidden', padding: '0 44px 40px' }}>
        <div className="col" style={{ gap: 14 }}>
          {V2_PRS.map(pr => <PRCard key={pr.id} pr={pr} />)}
        </div>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Repo card
// ─────────────────────────────────────────────────────────────
function RepoCard({ repo }) {
  const onDefault = repo.branch === repo.defaultBranch;
  const clean = !repo.dirty && repo.ahead === 0 && repo.behind === 0 && repo.unpushed === 0;

  // Single, calm status sentence
  let status;
  if (clean) {
    status = { tone: 'ok', text: 'Clean · in sync with origin' };
  } else if (repo.dirty) {
    status = { tone: 'warn', text: 'Working tree dirty' };
  } else {
    const bits = [];
    if (repo.ahead)    bits.push(`${repo.ahead} ahead`);
    if (repo.behind)   bits.push(`${repo.behind} behind`);
    if (repo.unpushed) bits.push(`${repo.unpushed} unpushed`);
    status = { tone: 'amber', text: bits.join(' · ') };
  }

  return (
    <div className="card" style={{
      padding: '22px 26px',
      display: 'grid',
      gridTemplateColumns: '1.4fr 1fr auto',
      columnGap: 28,
      alignItems: 'center',
    }}>
      {/* Identity */}
      <div className="col" style={{ gap: 8, minWidth: 0 }}>
        <div className="row" style={{ gap: 10, color: 'var(--text-3)', fontSize: 12 }}>
          <span>{repo.owner}</span>
          {!onDefault && (
            <>
              <span style={{ color: 'var(--text-4)' }}>·</span>
              <span className="pill" style={{ padding:'1px 7px', fontSize:10, color:'var(--text-3)' }}>off default</span>
            </>
          )}
        </div>
        <div style={{
          fontSize: 20, fontWeight: 500, color: 'var(--text-1)',
          letterSpacing: '-0.008em',
        }}>{repo.name}</div>
        <div className="row" style={{ gap: 8, marginTop: 2 }}>
          <BranchIcon />
          <span className="mono" style={{ color: 'var(--text-2)', fontSize: 13 }}>{repo.branch}</span>
        </div>
      </div>

      {/* Status */}
      <div className="row" style={{ gap: 8 }}>
        <span className="dot" style={{
          background: status.tone === 'ok' ? 'var(--ok)'
                    : status.tone === 'warn' ? 'var(--warn)'
                    : 'var(--amber)',
          boxShadow: '0 0 8px ' + (
            status.tone === 'ok' ? 'oklch(0.82 0.13 158 / 0.6)' :
            status.tone === 'warn' ? 'oklch(0.86 0.14 88 / 0.6)' :
            'oklch(0.86 0.14 78 / 0.6)'
          ),
        }} />
        <span style={{ fontSize: 13.5, color: 'var(--text-2)' }}>{status.text}</span>
      </div>

      {/* Actions */}
      <div className="row" style={{ gap: 8 }}>
        <button className="btn ghost sm">Open ↗</button>
        <button className="btn danger">Reset to origin/main</button>
      </div>
    </div>
  );
}

function BranchIcon() {
  return (
    <svg width="13" height="13" viewBox="0 0 16 16" fill="none" stroke="currentColor"
         strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"
         style={{ color: 'var(--text-3)' }}>
      <circle cx="4" cy="3" r="1.4"/><circle cx="4" cy="13" r="1.4"/><circle cx="12" cy="6" r="1.4"/>
      <path d="M4 4.4v7.2"/><path d="M4 8c4 0 7-1 7-2.6"/>
    </svg>
  );
}

// ─────────────────────────────────────────────────────────────
// Repo view
// ─────────────────────────────────────────────────────────────
function RepoView() {
  const dirtyCount = V2_REPOS.filter(r => r.dirty).length;
  return (
    <div className="col" style={{ flex: 1, minHeight: 0 }}>
      <Header
        eyebrow="VIEW · ⌘2"
        title="Local repositories"
        count={`${V2_REPOS.length} tracked · ${dirtyCount} with changes`}
        active="repos"
      />
      <div style={{ flex: 1, overflow: 'hidden', padding: '0 44px 40px' }}>
        <div className="col" style={{ gap: 14 }}>
          {V2_REPOS.map(r => <RepoCard key={r.id} repo={r} />)}
        </div>
      </div>
    </div>
  );
}

Object.assign(window, { Window, PRView, RepoView, W, H });
