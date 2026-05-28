// Settings · Advanced — polling cadence, rate-limit status, behavior toggles.

function AdvancedSettingsBody() {
  return (
    <div style={{ flex:1, overflow:'hidden', padding:'34px 40px 40px' }}>
      <div className="section-eyebrow">ADVANCED</div>
      <div className="row" style={{ justifyContent:'space-between', alignItems:'flex-end', marginTop:6 }}>
        <div className="row" style={{ gap:14, alignItems:'baseline' }}>
          <div className="section-title">Polling &amp; rate limits</div>
          <div className="mono" style={{ fontSize:13, color:'var(--text-3)' }}>how often Aerie refreshes</div>
        </div>
        <button className="btn ghost sm">Reset to defaults</button>
      </div>

      {/* Polling cadence */}
      <div className="section-eyebrow" style={{ marginTop:28 }}>POLLING CADENCE</div>
      <div className="card" style={{ marginTop:10, padding:'22px 24px', display:'flex', flexDirection:'column', gap:28 }}>
        <CadenceRow
          label="Active repo"
          hint="The repo whose detail view is open."
          value="30s"
          fillPct={(30 - 10) / (300 - 10) * 100}
          min="10s" max="5m"
        />
        <CadenceRow
          label="Background repos"
          hint="Everything else — periodic refresh in the list views."
          value="5 min"
          fillPct={(300 - 60) / (1800 - 60) * 100}
          min="1 min" max="30 min"
        />

        <div style={{
          padding:'10px 12px',
          borderRadius:8,
          background:'oklch(0.86 0.14 88 / 0.10)',
          border:'1px solid oklch(0.86 0.14 88 / 0.30)',
          display:'flex', alignItems:'center', gap:10,
          fontSize:12, color:'var(--text-2)',
        }}>
          <span className="dot warn" />
          <span>Lower values use more of your GitHub API quota (5,000 / hr).</span>
        </div>
      </div>

      {/* Rate limit status (read-only) */}
      <div className="section-eyebrow" style={{ marginTop:28 }}>RATE LIMIT</div>
      <div className="card" style={{ marginTop:10, padding:'22px 24px' }}>
        <div className="row" style={{ gap:30 }}>
          <div className="col" style={{ flex:1, gap:8 }}>
            <span className="section-eyebrow" style={{ fontSize:9 }}>GITHUB API · CARLOS-LI</span>
            <div className="row" style={{ alignItems:'baseline', gap:8 }}>
              <span style={{ fontSize:30, fontWeight:500, color:'var(--text-1)', letterSpacing:'-0.012em' }}>4,823</span>
              <span className="mono" style={{ fontSize:13, color:'var(--text-3)' }}>/ 5,000</span>
            </div>
            <RateMeter pct={4823/5000*100} />
            <span style={{ fontSize:11.5, color:'var(--text-4)' }}>resets in 42 min</span>
          </div>
          <div style={{ width:1, background:'var(--glass-line)' }} />
          <div className="col" style={{ flex:1, gap:8 }}>
            <span className="section-eyebrow" style={{ fontSize:9 }}>GITHUB API · CLI-WORK</span>
            <div className="row" style={{ alignItems:'baseline', gap:8 }}>
              <span style={{ fontSize:30, fontWeight:500, color:'var(--text-1)', letterSpacing:'-0.012em' }}>3,201</span>
              <span className="mono" style={{ fontSize:13, color:'var(--text-3)' }}>/ 5,000</span>
            </div>
            <RateMeter pct={3201/5000*100} />
            <span style={{ fontSize:11.5, color:'var(--text-4)' }}>resets in 42 min</span>
          </div>
          <div style={{ width:1, background:'var(--glass-line)' }} />
          <div className="col" style={{ flex:1, gap:8 }}>
            <span className="section-eyebrow" style={{ fontSize:9 }}>GHE · C-INTERNAL</span>
            <div className="row" style={{ alignItems:'baseline', gap:8 }}>
              <span style={{ fontSize:30, fontWeight:500, color:'var(--text-1)', letterSpacing:'-0.012em' }}>14,991</span>
              <span className="mono" style={{ fontSize:13, color:'var(--text-3)' }}>/ 15,000</span>
            </div>
            <RateMeter pct={14991/15000*100} />
            <span style={{ fontSize:11.5, color:'var(--text-4)' }}>resets in 56 min</span>
          </div>
        </div>
      </div>

      {/* Behavior */}
      <div className="section-eyebrow" style={{ marginTop:28 }}>BEHAVIOR</div>
      <div className="card" style={{ marginTop:10 }}>
        <BehaviorRow
          on={true}
          title="Refresh immediately when Aerie regains focus"
          hint="So you see fresh data the moment you ⌘-Tab back."
        />
        <BehaviorRow
          on={true}
          last={true}
          title="Pause polling when Aerie loses focus"
          hint="Saves API quota when you're not looking."
        />
      </div>
    </div>
  );
}

function CadenceRow({ label, hint, value, fillPct, min, max }) {
  return (
    <div className="col" style={{ gap:9 }}>
      <div className="row" style={{ justifyContent:'space-between', alignItems:'baseline' }}>
        <div className="col" style={{ gap:3 }}>
          <span style={{ fontSize:14, fontWeight:500, color:'var(--text-1)' }}>{label}</span>
          <span style={{ fontSize:12, color:'var(--text-3)' }}>{hint}</span>
        </div>
        <span style={{ fontSize:22, fontWeight:500, color:'var(--text-1)', fontFamily:'var(--font-mono)', letterSpacing:'-0.005em' }}>{value}</span>
      </div>
      <Slider fillPct={fillPct} min={min} max={max} />
    </div>
  );
}

function Slider({ fillPct, min, max }) {
  return (
    <div className="col" style={{ gap:6 }}>
      <div style={{
        position:'relative',
        height:6, borderRadius:999,
        background:'rgba(0,0,0,0.32)',
        border:'1px solid var(--glass-line)',
      }}>
        <div style={{
          position:'absolute', left:0, top:0, bottom:0,
          width: fillPct + '%',
          background:'linear-gradient(90deg, oklch(0.78 0.14 75) 0%, oklch(0.88 0.14 78) 100%)',
          borderRadius:999,
          boxShadow:'0 0 10px oklch(0.83 0.135 75 / 0.4)',
        }} />
        <div style={{
          position:'absolute',
          left: `calc(${fillPct}% - 8px)`,
          top:'50%', transform:'translateY(-50%)',
          width:16, height:16, borderRadius:'50%',
          background:'#fff',
          boxShadow:'0 1px 4px rgba(0,0,0,0.6), inset 0 -1px 0 0 rgba(0,0,0,0.10)',
          border:'1px solid rgba(0,0,0,0.10)',
        }} />
      </div>
      <div className="row" style={{ justifyContent:'space-between', fontFamily:'var(--font-mono)', fontSize:10.5, color:'var(--text-4)' }}>
        <span>{min}</span>
        <span>{max}</span>
      </div>
    </div>
  );
}

function RateMeter({ pct }) {
  const color = pct > 90 ? 'var(--ok)' : pct > 30 ? 'var(--amber)' : 'var(--err)';
  return (
    <div style={{
      height:4, borderRadius:999,
      background:'rgba(0,0,0,0.32)',
      border:'1px solid var(--glass-line)',
      overflow:'hidden',
    }}>
      <div style={{
        height:'100%', width: pct + '%',
        background: color,
        boxShadow:'0 0 8px ' + color,
      }} />
    </div>
  );
}

function BehaviorRow({ title, hint, on, last }) {
  return (
    <div style={{
      display:'flex', alignItems:'center', gap:14,
      padding:'16px 20px',
      borderBottom: last ? 'none' : '1px solid var(--glass-line)',
    }}>
      <div className="col" style={{ flex:1, gap:4 }}>
        <span style={{ fontSize:14, color:'var(--text-1)' }}>{title}</span>
        <span style={{ fontSize:12, color:'var(--text-3)' }}>{hint}</span>
      </div>
      <Toggle on={on} />
    </div>
  );
}

function SettingsAdvanced() {
  return (
    <SettingsWindow title="Settings">
      <div style={{ flex:1, display:'flex', overflow:'hidden' }}>
        <SettingsSidebar active="advanced" />
        <div style={{ flex:1, display:'flex', flexDirection:'column', overflow:'hidden' }}>
          <AdvancedSettingsBody />
        </div>
      </div>
    </SettingsWindow>
  );
}

Object.assign(window, { SettingsAdvanced });
