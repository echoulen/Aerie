// Settings · Appearance — interface zoom (display size).
// Scales the WHOLE UI — text, spacing, icons — like ⌘+/⌘- in a browser.
// 5 stops, default 100%. Static mock: the "Default" stop is the active one.

const ZOOM_STOPS = [
  { pct: 85,  label: 'Smaller' },
  { pct: 92,  label: 'Small'   },
  { pct: 100, label: 'Default' },
  { pct: 110, label: 'Large'   },
  { pct: 125, label: 'Larger'  },
];
const ZOOM_ACTIVE = 2; // index of the currently-selected stop

function AppearanceScreen() {
  const active = ZOOM_STOPS[ZOOM_ACTIVE];

  return (
    <div style={{ flex:1, overflow:'hidden', padding:'34px 40px 40px' }}>
      <div className="section-eyebrow">APPEARANCE</div>
      <div className="row" style={{ justifyContent:'space-between', alignItems:'flex-end', marginTop:6 }}>
        <div className="row" style={{ gap:14, alignItems:'baseline' }}>
          <div className="section-title">Display size</div>
          <div className="mono" style={{ fontSize:13, color:'var(--text-3)' }}>zoom the whole interface</div>
        </div>
        <button className="btn ghost sm">Reset to 100%</button>
      </div>

      {/* Interface zoom */}
      <div className="section-eyebrow" style={{ marginTop:28 }}>INTERFACE ZOOM</div>
      <div className="card" style={{ marginTop:10, padding:'24px 26px', display:'flex', flexDirection:'column', gap:22 }}>
        <div className="row" style={{ justifyContent:'space-between', alignItems:'flex-start' }}>
          <div className="col" style={{ gap:4 }}>
            <span style={{ fontSize:14.5, fontWeight:500, color:'var(--text-1)' }}>Interface zoom</span>
            <span style={{ fontSize:12.5, color:'var(--text-3)', maxWidth:360, lineHeight:1.5 }}>
              Text, spacing and icons all scale together — the same way ⌘+ zooms a browser.
            </span>
          </div>
          <span style={{ fontSize:30, fontWeight:500, color:'var(--text-1)', fontFamily:'var(--font-mono)', letterSpacing:'-0.01em' }}>
            {active.pct}%
          </span>
        </div>

        <ZoomStepper stops={ZOOM_STOPS} activeIndex={ZOOM_ACTIVE} />

        <div style={{ height:1, background:'var(--glass-line)' }} />

        {/* Keyboard shortcuts */}
        <div className="row" style={{ gap:22, alignItems:'center', flexWrap:'wrap' }}>
          <ShortcutHint keys={['⌘','+']} label="Zoom in" />
          <ShortcutHint keys={['⌘','−']} label="Zoom out" />
          <ShortcutHint keys={['⌘','0']} label="Reset to 100%" />
        </div>
      </div>

      {/* Live preview */}
      <div className="section-eyebrow" style={{ marginTop:28 }}>PREVIEW</div>
      <div className="card" style={{ marginTop:10, padding:'22px 24px', overflow:'hidden' }}>
        <ZoomPreview pct={active.pct} />
      </div>
    </div>
  );
}

// ─── Stepped zoom control: small A · track w/ 5 ticks · large A ───
function ZoomStepper({ stops, activeIndex }) {
  const n = stops.length;
  const pos = (i) => (i / (n - 1)) * 100;
  const fillPct = pos(activeIndex);

  return (
    <div className="col" style={{ gap:12 }}>
      <div className="row" style={{ gap:18, alignItems:'center' }}>
        <span style={{ fontSize:13, fontWeight:600, color:'var(--text-3)', lineHeight:1 }}>A</span>

        <div style={{ position:'relative', flex:1, height:18, display:'flex', alignItems:'center' }}>
          {/* track */}
          <div style={{
            position:'absolute', left:0, right:0, height:6, borderRadius:999,
            background:'rgba(0,0,0,0.32)', border:'1px solid var(--glass-line)',
          }} />
          {/* fill */}
          <div style={{
            position:'absolute', left:0, top:'50%', transform:'translateY(-50%)',
            height:6, width:`${fillPct}%`, borderRadius:999,
            background:'linear-gradient(90deg, oklch(0.78 0.14 75) 0%, oklch(0.88 0.14 78) 100%)',
            boxShadow:'0 0 10px oklch(0.83 0.135 75 / 0.4)',
          }} />
          {/* ticks */}
          {stops.map((s, i) => {
            const isActive = i === activeIndex;
            const passed = i <= activeIndex;
            return (
              <span key={i} style={{
                position:'absolute', left:`${pos(i)}%`, top:'50%',
                transform:'translate(-50%,-50%)',
                width: isActive ? 16 : 9, height: isActive ? 16 : 9,
                borderRadius:'50%',
                background: isActive ? '#fff' : (passed ? 'oklch(0.86 0.14 78)' : 'rgba(255,255,255,0.18)'),
                border: isActive ? '1px solid rgba(0,0,0,0.10)' : '1px solid var(--glass-line)',
                boxShadow: isActive ? '0 1px 4px rgba(0,0,0,0.6)' : 'none',
              }} />
            );
          })}
        </div>

        <span style={{ fontSize:22, fontWeight:600, color:'var(--text-1)', lineHeight:1 }}>A</span>
      </div>

      {/* stop labels */}
      <div className="row" style={{ justifyContent:'space-between' }}>
        {stops.map((s, i) => {
          const isActive = i === activeIndex;
          return (
            <div key={i} className="col" style={{ alignItems:'center', gap:2, flex:1 }}>
              <span className="mono" style={{
                fontSize:11, color: isActive ? 'var(--amber)' : 'var(--text-4)',
                fontWeight: isActive ? 600 : 400,
              }}>{s.pct}%</span>
              <span style={{
                fontSize:10, color: isActive ? 'var(--text-2)' : 'var(--text-4)',
                letterSpacing:'0.02em',
              }}>{s.label}</span>
            </div>
          );
        })}
      </div>
    </div>
  );
}

function ShortcutHint({ keys, label }) {
  return (
    <div className="row" style={{ gap:8, alignItems:'center' }}>
      <span className="row" style={{ gap:4 }}>
        {keys.map((k, i) => (
          <span key={i} style={{
            minWidth:20, height:20, padding:'0 5px',
            display:'inline-flex', alignItems:'center', justifyContent:'center',
            borderRadius:6,
            background:'rgba(0,0,0,0.30)',
            border:'1px solid var(--glass-line)',
            boxShadow:'inset 0 1px 0 0 rgba(255,255,255,0.06)',
            fontFamily:'var(--font-mono)', fontSize:12, color:'var(--text-2)',
          }}>{k}</span>
        ))}
      </span>
      <span style={{ fontSize:12.5, color:'var(--text-3)' }}>{label}</span>
    </div>
  );
}

// ─── Preview: a mini Aerie row whose type/spacing reflects the chosen zoom ───
function ZoomPreview({ pct }) {
  const k = pct / 100;
  return (
    <div style={{
      display:'flex', alignItems:'center', gap: 16 * k,
      padding: `${16 * k}px ${18 * k}px`,
      borderRadius: 12,
      background:'rgba(0,0,0,0.22)',
      border:'1px solid var(--glass-line)',
    }}>
      <span style={{
        width: 30 * k, height: 30 * k, borderRadius:'50%', flexShrink:0,
        background:'radial-gradient(circle at 30% 30%, oklch(0.88 0.14 78), oklch(0.50 0.13 60))',
        boxShadow:'inset 0 1px 0 0 rgba(255,255,255,0.35)',
      }} />
      <div className="col" style={{ gap: 5 * k, minWidth:0, flex:1 }}>
        <span style={{ fontSize: 16 * k, fontWeight:500, color:'var(--text-1)', letterSpacing:'-0.005em' }}>
          PollingScheduler: virtual clock for tests
        </span>
        <span className="mono" style={{ fontSize: 12 * k, color:'var(--text-3)' }}>
          aerie · #142 · feat/virtual-clock
        </span>
      </div>
      <span className="pill ok" style={{ fontSize: 11 * k, padding: `${3 * k}px ${9 * k}px` }}>
        <span className="dot ok" /> CI passing
      </span>
    </div>
  );
}

// ─── Composed screen (sidebar + body) ───
function SettingsAppearance() {
  return (
    <SettingsWindow title="Settings">
      <div style={{ flex:1, display:'flex', overflow:'hidden' }}>
        <SettingsSidebar active="appearance" />
        <div style={{ flex:1, display:'flex', flexDirection:'column', overflow:'hidden' }}>
          <AppearanceScreen />
        </div>
      </div>
    </SettingsWindow>
  );
}

Object.assign(window, { SettingsAppearance });
