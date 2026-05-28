// App icon — macOS-style squircle. Sodium amber radial set in dark glass,
// with a subtle radar-pulse / aerie (eagle's nest) geometry behind it.

function AppIcon({ size = 512, withRoundedClip = true }) {
  const r = size;
  // squircle border-radius: about 22-23% feels right on macOS
  const radius = r * 0.225;

  return (
    <div style={{
      width: r, height: r,
      borderRadius: withRoundedClip ? radius : 0,
      position:'relative', overflow:'hidden',
      // Dark glass base with a subtle warm gradient
      background:
        'radial-gradient(120% 100% at 20% 0%, oklch(0.30 0.04 70) 0%, transparent 55%),' +
        'radial-gradient(80% 80% at 80% 100%, oklch(0.18 0.06 290 / 0.6) 0%, transparent 60%),' +
        'linear-gradient(155deg, oklch(0.22 0.02 70) 0%, oklch(0.10 0.01 270) 100%)',
      boxShadow:
        '0 '+ (r*0.05) +'px '+ (r*0.12) +'px -'+ (r*0.04) +'px rgba(0,0,0,0.55),' +
        'inset 0 1px 0 0 rgba(255,255,255,0.10),' +
        'inset 0 -1px 0 0 rgba(0,0,0,0.40)',
    }}>
      {/* Concentric radar rings (very faint) */}
      <svg width={r} height={r} viewBox="0 0 100 100" style={{ position:'absolute', inset:0 }}>
        <defs>
          <radialGradient id={`glow-${r}`} cx="50%" cy="55%" r="40%">
            <stop offset="0%"   stopColor="oklch(0.95 0.16 80)" stopOpacity="1"/>
            <stop offset="35%"  stopColor="oklch(0.78 0.16 70)" stopOpacity="0.9"/>
            <stop offset="70%"  stopColor="oklch(0.55 0.14 60)" stopOpacity="0.4"/>
            <stop offset="100%" stopColor="oklch(0.35 0.08 50)" stopOpacity="0"/>
          </radialGradient>
          <radialGradient id={`orb-${r}`} cx="40%" cy="35%" r="50%">
            <stop offset="0%"   stopColor="oklch(0.98 0.10 80)"/>
            <stop offset="50%"  stopColor="oklch(0.85 0.15 75)"/>
            <stop offset="100%" stopColor="oklch(0.55 0.16 60)"/>
          </radialGradient>
          <linearGradient id={`sweep-${r}`} x1="0" y1="0" x2="1" y2="0">
            <stop offset="0%"   stopColor="oklch(0.85 0.15 75)" stopOpacity="0"/>
            <stop offset="100%" stopColor="oklch(0.85 0.15 75)" stopOpacity="0.55"/>
          </linearGradient>
        </defs>

        {/* Concentric range rings */}
        <g stroke="oklch(0.85 0.15 75)" strokeWidth="0.4" fill="none" opacity="0.18">
          <circle cx="50" cy="55" r="14"/>
          <circle cx="50" cy="55" r="22"/>
          <circle cx="50" cy="55" r="30"/>
          <circle cx="50" cy="55" r="38"/>
        </g>
        {/* Cross hairs */}
        <g stroke="oklch(0.85 0.15 75)" strokeWidth="0.3" opacity="0.10">
          <line x1="50" y1="13" x2="50" y2="97"/>
          <line x1="8"  y1="55" x2="92" y2="55"/>
        </g>

        {/* Radar sweep — a wedge from center going up-right */}
        <path
          d="M50 55 L50 17 A38 38 0 0 1 88 55 Z"
          fill={`url(#sweep-${r})`}
          opacity="0.55"
        />

        {/* Outer soft amber halo */}
        <circle cx="50" cy="55" r="32" fill={`url(#glow-${r})`} opacity="0.28"/>

        {/* The orb — sodium amber */}
        <circle cx="50" cy="55" r="12" fill={`url(#orb-${r})`} />
        {/* Specular highlight on orb */}
        <ellipse cx="46" cy="50" rx="4.5" ry="2.6" fill="oklch(1 0 0)" opacity="0.55"/>
      </svg>

      {/* Top-edge highlight */}
      <div style={{
        position:'absolute', left:0, right:0, top:0, height:'30%',
        background:'linear-gradient(180deg, rgba(255,255,255,0.06) 0%, transparent 100%)',
        pointerEvents:'none',
      }} />

      {/* Letter mark at the bottom — wordmark inside the icon */}
      {r >= 96 && (
        <div style={{
          position:'absolute', bottom: r*0.10, left:0, right:0,
          textAlign:'center',
          fontFamily:'var(--font-sans)', fontWeight:600,
          fontSize: r*0.075, letterSpacing:'0.18em',
          color:'oklch(0.92 0.05 75 / 0.85)',
          textShadow:'0 1px 2px rgba(0,0,0,0.6)',
        }}>AERIE</div>
      )}
    </div>
  );
}

function AppIconShowcase() {
  return (
    <div style={{
      width:'100%', height:'100%',
      background:'linear-gradient(160deg, oklch(0.18 0.02 70) 0%, oklch(0.10 0.01 270) 100%)',
      padding:'48px 56px',
      display:'flex', flexDirection:'column', gap:36,
      fontFamily:'var(--font-sans)', color:'var(--text-1)',
    }}>
      {/* Header */}
      <div>
        <div className="section-eyebrow">APP ICON</div>
        <div className="section-title" style={{ marginTop:6 }}>Aerie · sodium amber on dark glass</div>
        <div style={{ fontSize:13.5, color:'var(--text-3)', marginTop:6, maxWidth:680 }}>
          A radar-orb mark — concentric range rings with a soft sweep, centered on a sodium-amber orb.
          The squircle base is dark glass with a warm-cool diagonal gradient so it sits beautifully on any wallpaper.
        </div>
      </div>

      <div style={{ display:'grid', gridTemplateColumns:'auto 1fr', gap:48, alignItems:'flex-start' }}>
        {/* Hero icon */}
        <div style={{ display:'flex', flexDirection:'column', alignItems:'center', gap:14 }}>
          <AppIcon size={320} />
          <div className="mono" style={{ fontSize:11, color:'var(--text-4)', letterSpacing:'0.18em' }}>320 × 320</div>
        </div>

        {/* Right column: sizes + dock context */}
        <div style={{ display:'flex', flexDirection:'column', gap:34 }}>
          {/* Size scale */}
          <div>
            <div className="section-eyebrow" style={{ marginBottom:14 }}>SIZE SCALE</div>
            <div style={{ display:'flex', gap:26, alignItems:'flex-end' }}>
              {[128, 96, 64, 48, 32, 16].map(s => (
                <div key={s} style={{ display:'flex', flexDirection:'column', alignItems:'center', gap:8 }}>
                  <AppIcon size={s} />
                  <div className="mono" style={{ fontSize:10, color:'var(--text-4)' }}>{s}px</div>
                </div>
              ))}
            </div>
          </div>

          {/* In dock context */}
          <div>
            <div className="section-eyebrow" style={{ marginBottom:14 }}>IN DOCK</div>
            <div style={{
              padding:'14px 22px 18px',
              borderRadius:24,
              background:'rgba(255,255,255,0.06)',
              border:'1px solid rgba(255,255,255,0.10)',
              backdropFilter:'blur(40px)',
              WebkitBackdropFilter:'blur(40px)',
              display:'flex', alignItems:'flex-end', gap:14,
              maxWidth:560,
            }}>
              {/* Sibling app placeholders */}
              <DockSibling color="#3478F6" letter="X" />
              <DockSibling color="#1F1F1F" letter="T" />
              <DockSibling color="#FF3B30" letter="M" />
              <AppIcon size={64} />
              <DockSibling color="#0F766E" letter="N" />
              <DockSibling color="#7A4FDB" letter="L" />
              <DockSibling color="#0B0B0B" letter="●" mono />
            </div>
          </div>

          {/* On wallpaper preview */}
          <div>
            <div className="section-eyebrow" style={{ marginBottom:14 }}>ON DESKTOP</div>
            <div style={{
              width:560, height:200,
              borderRadius:14, overflow:'hidden',
              background:
                'radial-gradient(60% 70% at 70% 30%, oklch(0.45 0.13 60 / 0.5) 0%, transparent 60%),' +
                'radial-gradient(70% 80% at 20% 80%, oklch(0.40 0.13 280 / 0.6) 0%, transparent 60%),' +
                'linear-gradient(140deg, oklch(0.18 0.02 250) 0%, oklch(0.08 0.01 280) 100%)',
              position:'relative',
            }}>
              <div style={{ position:'absolute', left:28, bottom:24 }}>
                <AppIcon size={96} />
              </div>
              <div style={{ position:'absolute', left:140, bottom:32, fontSize:13, color:'rgba(255,255,255,0.85)' }}>
                <div style={{ fontWeight:500 }}>Aerie</div>
                <div className="mono" style={{ fontSize:11, color:'rgba(255,255,255,0.55)', marginTop:2 }}>v0.1.0 · macOS app</div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

function DockSibling({ color, letter, mono }) {
  return (
    <div style={{
      width:64, height:64, borderRadius:14,
      background:color,
      display:'flex', alignItems:'center', justifyContent:'center',
      color:'rgba(255,255,255,0.9)',
      fontFamily: mono ? 'var(--font-mono)' : 'var(--font-sans)',
      fontSize:24, fontWeight:600,
      boxShadow:'0 4px 10px -2px rgba(0,0,0,0.4), inset 0 1px 0 0 rgba(255,255,255,0.12)',
    }}>{letter}</div>
  );
}

Object.assign(window, { AppIcon, AppIconShowcase });
