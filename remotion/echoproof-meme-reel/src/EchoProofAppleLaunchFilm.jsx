import React from 'react';
import {
  AbsoluteFill,
  Audio,
  Easing,
  Img,
  interpolate,
  Sequence,
  spring,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from 'remotion';

const palette = {
  ink: '#101314',
  panel: '#1a1e20',
  panelRaised: '#242a2b',
  paper: '#f5fbf5',
  muted: '#9ca9a4',
  line: 'rgba(221, 237, 228, 0.15)',
  green: '#67df85',
  lime: '#c8f56f',
  teal: '#68ded0',
  coral: '#ff8977',
  gold: '#e7c56a',
  violet: '#a493ff',
};

const clamp = {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'};

const fade = (frame, start, end) => interpolate(frame, [start, end], [0, 1], clamp);
const fadeOut = (frame, start, end) => interpolate(frame, [start, end], [1, 0], clamp);
const ease = {easing: Easing.bezier(0.16, 1, 0.3, 1)};

const appear = (frame, start, duration = 16) => ({
  opacity: fade(frame, start, start + duration),
  transform: `translateY(${interpolate(frame, [start, start + duration], [28, 0], {...clamp, ...ease})}px)`,
});

const bounceIn = (frame, fps, start, damping = 16) => spring({
  frame: frame - start,
  fps,
  config: {damping, stiffness: 170, mass: 0.65},
});

const clampNumber = (value, minimum, maximum) => Math.min(maximum, Math.max(minimum, value));

const Background = ({frame}) => (
  <AbsoluteFill style={{backgroundColor: palette.ink, overflow: 'hidden'}}>
    <div style={{
      position: 'absolute',
      inset: 0,
      opacity: 0.35,
      backgroundImage: `linear-gradient(${palette.line} 1px, transparent 1px), linear-gradient(90deg, ${palette.line} 1px, transparent 1px)`,
      backgroundSize: '96px 96px',
      transform: `translate(${interpolate(frame, [0, 780], [0, -48], clamp)}px, ${interpolate(frame, [0, 780], [0, 24], clamp)}px)`,
    }} />
    <div style={{
      position: 'absolute',
      left: 0,
      right: 0,
      top: 0,
      height: 460,
      background: 'linear-gradient(180deg, rgba(103,223,133,0.08), transparent)',
    }} />
  </AbsoluteFill>
);

const BrandLockup = ({frame, muted = false}) => (
  <div style={{
    position: 'absolute',
    left: 76,
    top: 74,
    zIndex: 40,
    display: 'flex',
    alignItems: 'center',
    gap: 14,
    ...appear(frame, 0, 18),
    opacity: fade(frame, 0, 18) * fadeOut(frame, 120, 148),
  }}>
    <Img
      src={staticFile('assets/echoproof-logo.png')}
      style={{width: 54, height: 54, borderRadius: 16}}
    />
    <div>
      <div style={{
        color: muted ? palette.muted : palette.paper,
        fontSize: 22,
        fontWeight: 900,
        letterSpacing: 0.2,
      }}>EchoProof</div>
      <div style={{
        marginTop: 3,
        color: palette.muted,
        fontSize: 13,
        fontWeight: 700,
        letterSpacing: 1.7,
        textTransform: 'uppercase',
      }}>truth, verified by community</div>
    </div>
  </div>
);

const Kicker = ({children, frame, start = 0, color = palette.green, align = 'left'}) => (
  <div style={{
    color,
    fontSize: 17,
    fontWeight: 850,
    letterSpacing: 3.4,
    lineHeight: 1,
    textTransform: 'uppercase',
    textAlign: align,
    ...appear(frame, start, 14),
  }}>{children}</div>
);

const Underline = ({frame, start, color = palette.gold, width = 460}) => (
  <svg
    viewBox="0 0 100 22"
    preserveAspectRatio="none"
    style={{
      position: 'absolute',
      left: 0,
      bottom: -11,
      width,
      height: 25,
      opacity: fade(frame, start, start + 12),
      transform: `scaleX(${interpolate(bounceIn(frame, 30, start, 15), [0, 1], [0.05, 1], clamp)})`,
      transformOrigin: 'left center',
    }}
  >
    <path d="M2 11c14-5 27 2 41-1 16-3 32 4 55-2v10c-19 4-33-2-52 2-18 3-29-3-44 1z" fill={color} />
  </svg>
);

// the brush band gives each headline a tactile anchor without competing with the
// phone surface; its width is animated so the mark arrives with the zoomed type.
const BrushBand = ({frame, start, color = palette.green, width = 520}) => {
  const progress = bounceIn(frame, 30, start, 17);
  return (
    <svg
      viewBox="0 0 100 26"
      preserveAspectRatio="none"
      style={{
        position: 'absolute',
        left: '50%',
        bottom: 3,
        width,
        height: 31,
        opacity: fade(frame, start, start + 10),
        transform: `translateX(-50%) scaleX(${interpolate(Math.max(0, progress), [0, 1], [0.04, 1], clamp)}) rotate(-1deg)`,
        transformOrigin: 'center center',
        zIndex: 0,
      }}
    >
      <path d="M2 10c13-4 23 2 38-1 16-3 34 4 58-2l-2 13c-22 4-38-3-55 1-17 3-27-2-41 2z" fill={`${color}55`} />
      <path d="M4 7c17 1 28-3 45 0 15 3 29-1 47-1l-1 4c-20 2-31 4-47 1-16-2-27 2-44 0z" fill={`${color}2e`} />
    </svg>
  );
};

const Icon = ({kind, frame, start, color = palette.green, size = 34}) => {
  const progress = interpolate(bounceIn(frame, 30, start, 15), [0, 1], [0, 1], clamp);
  const stroke = {
    fill: 'none',
    stroke: color,
    strokeWidth: 2.8,
    strokeLinecap: 'round',
    strokeLinejoin: 'round',
  };
  return (
    <svg width={size} height={size} viewBox="0 0 48 48" style={{opacity: fade(frame, start, start + 8)}}>
      {kind === 'source' && <>
        <path {...stroke} d="M13 6h17l6 6v30H13z" />
        <path {...stroke} d="M30 6v8h7" />
        <path {...stroke} d="M19 24h12M19 31h12" strokeDasharray="40" strokeDashoffset={40 * (1 - progress)} />
      </>}
      {kind === 'support' && <>
        <circle {...stroke} cx="24" cy="24" r="16" opacity="0.35" />
        <path {...stroke} d="m15 24 6 6 12-14" strokeDasharray="40" strokeDashoffset={40 * (1 - progress)} />
      </>}
      {kind === 'challenge' && <>
        <circle {...stroke} cx="24" cy="24" r="16" opacity="0.35" />
        <path {...stroke} d="m17 17 14 14M31 17 17 31" strokeDasharray="44" strokeDashoffset={44 * (1 - progress)} />
      </>}
      {kind === 'record' && <>
        <path {...stroke} d="M18 6 14 42M34 6l-4 36M8 19h32M6 31h32" strokeDasharray="120" strokeDashoffset={120 * (1 - progress)} />
      </>}
      {kind === 'anchor' && <>
        <circle {...stroke} cx="24" cy="24" r="6" />
        <path {...stroke} d="M24 5v13M24 30v13M5 24h13M30 24h13" strokeDasharray="52" strokeDashoffset={52 * (1 - progress)} />
      </>}
    </svg>
  );
};

const ConnectionLine = ({frame, start, x1, y1, x2, y2, color = palette.green, opacity = 1}) => {
  const progress = fade(frame, start, start + 20);
  const length = Math.sqrt(((x2 - x1) ** 2) + ((y2 - y1) ** 2));
  return (
    <svg style={{position: 'absolute', inset: 0, overflow: 'visible', opacity: progress * opacity}}>
      <line
        x1={x1}
        y1={y1}
        x2={x2}
        y2={y2}
        stroke={color}
        strokeWidth={2}
        strokeDasharray={length}
        strokeDashoffset={length * (1 - progress)}
        opacity="0.72"
      />
    </svg>
  );
};

const ZoomHeadline = ({frame, start, exitStart, exitEnd, kicker, color = palette.paper, brushColor = color, children}) => {
  const {fps} = useVideoConfig();
  const intro = bounceIn(frame, fps, start, 17);
  const visible = fade(frame, start, start + 10) * fadeOut(frame, exitStart, exitEnd);
  const scale = interpolate(Math.max(0, intro), [0, 1], [1.16, 1], clamp);
  const y = interpolate(Math.max(0, intro), [0, 1], [34, 0], clamp);
  return (
    <div style={{
      position: 'absolute',
      left: 76,
      right: 76,
      top: 220,
      zIndex: 35,
      opacity: visible,
      transform: `translateY(${y}px) scale(${scale})`,
      transformOrigin: 'center top',
      textAlign: 'center',
    }}>
      <div style={{color: color === palette.paper ? palette.green : color, fontSize: 15, fontWeight: 850, letterSpacing: 3.3, textTransform: 'uppercase'}}>{kicker}</div>
      <div style={{position: 'relative', display: 'inline-block', marginTop: 22, color, fontSize: 66, lineHeight: 0.97, fontWeight: 950, letterSpacing: -2.6}}>
        <BrushBand frame={frame} start={start + 10} color={brushColor} width={Math.min(650, 510 + String(children).length * 2)} />
        <span style={{position: 'relative', zIndex: 1}}>{children}</span>
      </div>
    </div>
  );
};

const MobileSurface = ({frame, start, exitStart, exitEnd, children, tone = palette.green}) => {
  const {fps} = useVideoConfig();
  const intro = bounceIn(frame, fps, start, 17);
  const visible = fade(frame, start, start + 12) * fadeOut(frame, exitStart, exitEnd);
  const scale = interpolate(Math.max(0, intro), [0, 1], [0.95, 1], clamp);
  const y = interpolate(Math.max(0, intro), [0, 1], [44, 0], clamp);
  return (
    <div style={{
      position: 'absolute',
      inset: 0,
      padding: '26px 26px 42px',
      borderRadius: 0,
      border: 'none',
      backgroundColor: '#ffffff',
      color: '#10261a',
      opacity: visible,
      transform: `translateY(${y}px) scale(${scale})`,
      transformOrigin: 'center center',
      boxShadow: 'none',
    }}>{children}</div>
  );
};

const MobileHeader = ({label, accent = palette.green}) => (
  <>
    <div style={{display: 'flex', alignItems: 'center', justifyContent: 'space-between', color: '#587363', fontSize: 14, letterSpacing: 1.8, textTransform: 'uppercase', fontWeight: 850}}>
      <span style={{display: 'flex', alignItems: 'center', gap: 8}}><span style={{width: 9, height: 9, borderRadius: 99, backgroundColor: accent}} /> {label}</span>
      <span style={{color: '#9aa09d'}}>live feed</span>
    </div>
    <div style={{display: 'flex', gap: 22, marginTop: 25, paddingBottom: 14, borderBottom: '1px solid rgba(16,38,26,0.13)', color: '#70907c', fontSize: 16, fontWeight: 850}}>
      <span style={{color: '#10261a'}}>For you</span><span>Following</span><span>Discover</span>
    </div>
  </>
);

const MobileEchoCard = ({frame, focusMode}) => {
  const isolated = Boolean(focusMode);
  const chromeOpacity = isolated ? 0 : 1;
  const titleOpacity = !isolated || focusMode === 'title' ? 1 : 0;
  const bodyOpacity = !isolated || focusMode === 'body' ? 1 : 0;
  return (
    <MobileSurface frame={frame} start={196} exitStart={322} exitEnd={330} tone={palette.gold}>
      <div style={{opacity: chromeOpacity}}><MobileHeader label="claim posted" accent={palette.gold} /></div>
      <div style={{marginTop: 30, padding: 22, borderRadius: 22, backgroundColor: '#ffffff', border: '1px solid rgba(16,38,26,0.12)', boxShadow: '0 12px 24px rgba(16,38,26,0.08)'}}>
        <div style={{display: 'flex', alignItems: 'center', gap: 11, opacity: chromeOpacity}}>
          <div style={{width: 40, height: 40, borderRadius: 99, backgroundColor: '#d6eedb'}} />
          <div><div style={{fontSize: 18, fontWeight: 900}}>you</div><div style={{marginTop: 3, color: '#718a79', fontSize: 13, fontWeight: 700}}>unverified · illustrative claim</div></div>
          <div style={{marginLeft: 'auto', color: '#bd8d2d', fontSize: 14, fontWeight: 850}}>unverified</div>
        </div>
        <div style={{marginTop: 24, fontSize: 38, lineHeight: 1.05, fontWeight: 950, letterSpacing: -0.8, opacity: titleOpacity}}>the city water is safe to drink.</div>
        <div style={{marginTop: 20, color: '#6b8673', fontSize: focusMode === 'body' ? 42 : 22, lineHeight: 1.12, opacity: bodyOpacity}}>a receipt links this claim to its source, review, and result.</div>
        <div style={{display: 'flex', gap: 10, marginTop: 24, opacity: chromeOpacity}}>
          <div style={{flex: 1, padding: '12px 8px', borderRadius: 13, border: '1px solid #67df8580', color: '#23854a', textAlign: 'center', fontSize: 16, fontWeight: 900}}>source attached</div>
          <div style={{flex: 1, padding: '12px 8px', borderRadius: 13, border: '1px solid #68ded080', color: '#33857b', textAlign: 'center', fontSize: 16, fontWeight: 900}}>open for review</div>
        </div>
      </div>
      <div style={{display: 'flex', justifyContent: 'space-between', marginTop: 24, color: '#6d8776', fontSize: 14, fontWeight: 850, opacity: chromeOpacity}}><span>community confidence</span><span style={{color: '#bd8d2d'}}>41%</span></div>
      <div style={{height: 9, marginTop: 8, borderRadius: 99, backgroundColor: '#e3eee5', overflow: 'hidden', opacity: chromeOpacity}}><div style={{width: '41%', height: '100%', borderRadius: 99, backgroundColor: palette.gold}} /></div>
    </MobileSurface>
  );
};

const MobileReviewCard = ({frame, focusMode}) => {
  const isolated = Boolean(focusMode);
  const chromeOpacity = isolated ? 0 : 1;
  return (
    <MobileSurface frame={frame} start={396} exitStart={460} exitEnd={468} tone={palette.teal}>
      <div style={{opacity: chromeOpacity}}><MobileHeader label="source review" accent={palette.teal} /></div>
      <div style={{marginTop: 30, padding: focusMode === 'challenge' ? 0 : 22, borderRadius: 22, backgroundColor: '#ffffff', border: '1px solid rgba(16,38,26,0.12)', boxShadow: '0 12px 24px rgba(16,38,26,0.08)'}}>
        <div style={{color: '#3d776d', fontSize: 13, letterSpacing: 2, textTransform: 'uppercase', fontWeight: 900, opacity: chromeOpacity}}>community review</div>
        <div style={{marginTop: 18, fontSize: 30, lineHeight: 1.05, fontWeight: 950, opacity: chromeOpacity}}>can the source support it?</div>
        <div style={{marginTop: 14, color: '#6b8673', fontSize: 17, lineHeight: 1.25, opacity: chromeOpacity}}>the community checks the claim against the linked source.</div>
        <div style={{display: 'flex', justifyContent: focusMode === 'challenge' ? 'center' : 'stretch', gap: 11, marginTop: focusMode === 'challenge' ? 0 : 25}}>
          <div style={{flex: focusMode === 'challenge' ? 0 : 1, padding: '16px 8px', borderRadius: 14, backgroundColor: '#e7f8eb', color: '#23854a', textAlign: 'center', fontSize: 18, fontWeight: 950, opacity: focusMode === 'challenge' ? 0 : 1}}>support</div>
          <div style={{flex: focusMode === 'challenge' ? '0 0 100%' : 1, minWidth: focusMode === 'challenge' ? '100%' : 0, padding: focusMode === 'challenge' ? '20px 10px' : '16px 8px', borderRadius: 14, backgroundColor: '#fff0ed', color: '#c45e54', textAlign: 'center', fontSize: focusMode === 'challenge' ? 24 : 18, fontWeight: 950}}>challenge</div>
        </div>
      </div>
      <div style={{marginTop: 24, padding: '14px 16px', borderRadius: 14, border: '1px solid #68ded080', color: '#3d776d', fontSize: 15, fontWeight: 850, opacity: chromeOpacity}}>source link ready for inspection</div>
    </MobileSurface>
  );
};

const MobileTrustCard = ({frame, focusMode}) => {
  const value = interpolate(frame, [538, 560, 584, 598], [41, 58, 71, 84], clamp);
  const chromeOpacity = focusMode ? 0 : 1;
  // the receipt is issued only after the confidence signal crosses the visible threshold.
  const cleared = value >= 70;
  return (
    <MobileSurface frame={frame} start={538} exitStart={598} exitEnd={606} tone={palette.green}>
      <div style={{opacity: chromeOpacity}}><MobileHeader label="trust engine" accent={palette.green} /></div>
      <div style={{marginTop: 30, padding: 22, borderRadius: 22, backgroundColor: '#ffffff', border: '1px solid rgba(16,38,26,0.12)', boxShadow: '0 12px 24px rgba(16,38,26,0.08)'}}>
        <div style={{display: 'flex', justifyContent: focusMode ? 'center' : 'space-between', alignItems: 'end'}}><div><div style={{color: '#5c7e67', fontSize: focusMode ? 16 : 13, letterSpacing: 2, textTransform: 'uppercase', fontWeight: 900}}>confidence</div><div style={{marginTop: 8, fontSize: focusMode ? 72 : 56, lineHeight: 1, fontWeight: 950}}>{Math.round(value)}%</div></div><div style={{textAlign: 'right', opacity: focusMode ? 0 : 1}}><div style={{color: '#5c7e67', fontSize: 13, letterSpacing: 2, textTransform: 'uppercase', fontWeight: 900}}>trust</div><div style={{marginTop: 8, color: '#23854a', fontSize: 34, lineHeight: 1, fontWeight: 950}}>62</div></div></div>
        <div style={{height: 11, marginTop: 23, borderRadius: 99, backgroundColor: '#e3eee5', overflow: 'hidden'}}><div style={{width: `${value}%`, height: '100%', borderRadius: 99, backgroundColor: palette.green}} /></div>
        <div style={{position: 'relative', height: 30, marginTop: 7}}><div style={{position: 'absolute', left: '70%', top: 0, bottom: 0, width: 2, backgroundColor: palette.gold}} /><div style={{position: 'absolute', left: '70%', top: 14, transform: 'translateX(-50%)', color: '#bd8d2d', fontSize: 11, fontWeight: 900, whiteSpace: 'nowrap'}}>70% to issue a receipt</div></div>
        <div style={{display: 'flex', justifyContent: 'space-between', marginTop: 14, color: cleared ? '#23854a' : '#bd8d2d', fontSize: 14, fontWeight: 900, opacity: chromeOpacity}}><span>{cleared ? 'verified threshold met' : 'needs more evidence'}</span><span style={{color: '#78907e'}}>receipt {cleared ? 'eligible' : 'not issued'}</span></div>
      </div>
      <div style={{marginTop: 22, display: 'grid', gap: 9, opacity: chromeOpacity}}>
        {[["unverified", "1x", palette.muted], ["low", "2x", palette.teal], ["high", "4x", palette.green], ["elite", "5x", palette.gold]].map(([label, weight, color]) => <div key={label} style={{display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '11px 14px', borderRadius: 12, backgroundColor: '#f2f8f3', color: '#52705c', fontSize: 15, fontWeight: 850}}><span>{label}</span><b style={{color}}>{weight}</b></div>)}
      </div>
    </MobileSurface>
  );
};

const MobileRecordCard = ({frame, focusMode}) => (
  <MobileSurface frame={frame} start={676} exitStart={730} exitEnd={744} tone={palette.violet}>
    <div style={{opacity: focusMode ? 0 : 1}}><MobileHeader label="proof receipt" accent={palette.violet} /></div>
    <div style={{marginTop: 30, padding: 22, borderRadius: 22, backgroundColor: '#ffffff', border: '1px solid rgba(16,38,26,0.12)', boxShadow: '0 12px 24px rgba(16,38,26,0.08)'}}>
      <div style={{display: 'flex', alignItems: 'center', justifyContent: 'space-between', opacity: focusMode ? 0 : 1}}><div style={{display: 'flex', alignItems: 'center', gap: 9, color: '#55705d', fontSize: 14, fontWeight: 900, letterSpacing: 1.4, textTransform: 'uppercase'}}><Icon kind="record" frame={frame} start={686} color="#725fca" size={26} /> echo receipt</div><div style={{padding: '7px 10px', borderRadius: 99, backgroundColor: '#e7f8eb', color: '#23854a', fontSize: 12, fontWeight: 900, letterSpacing: 1, textTransform: 'uppercase'}}>verified</div></div>
      <div style={{margin: '42px 0 35px', color: '#725fca', fontFamily: 'monospace', fontSize: 25, lineHeight: 1.2, fontWeight: 800, textAlign: 'center'}}>sha256 / 7d8f / 3a21 / 84c0</div>
      <div style={{display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 8, paddingTop: 17, borderTop: '1px solid rgba(16,38,26,0.12)', opacity: focusMode ? 0 : 1}}><div><small style={{display: 'block', color: '#78907e', fontSize: 11, letterSpacing: 1, textTransform: 'uppercase'}}>claim</small><b style={{display: 'block', marginTop: 5, fontSize: 16}}>water safe</b></div><div><small style={{display: 'block', color: '#78907e', fontSize: 11, letterSpacing: 1, textTransform: 'uppercase'}}>review</small><b style={{display: 'block', marginTop: 5, fontSize: 16}}>84%</b></div><div><small style={{display: 'block', color: '#78907e', fontSize: 11, letterSpacing: 1, textTransform: 'uppercase'}}>anchor</small><b style={{display: 'block', marginTop: 5, fontSize: 16}}>recorded</b></div></div>
    </div>
    <div style={{marginTop: 22, padding: '14px 16px', borderRadius: 14, backgroundColor: '#f2efff', color: '#6658a5', fontSize: 15, lineHeight: 1.25, fontWeight: 850, opacity: focusMode ? 0 : 1}}>the receipt preserves the claim, evidence trail, and outcome.</div>
  </MobileSurface>
);

const AppTopBar = ({opacity = 1}) => (
  <div style={{
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    height: 86,
    padding: '0 28px',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    backgroundColor: '#ffffff',
    borderBottom: '1px solid #e6e6e6',
    zIndex: 20,
    opacity,
  }}>
    <div style={{display: 'flex', alignItems: 'center', gap: 11}}>
      <Img src={staticFile('assets/echoproof-logo.png')} style={{width: 34, height: 34, borderRadius: 10}} />
      <span style={{color: '#1a1a1a', fontSize: 23, fontWeight: 850, letterSpacing: -0.5}}>EchoProof</span>
    </div>
    <div style={{display: 'flex', alignItems: 'center', gap: 19, color: '#777d7a', fontSize: 18, fontWeight: 800}}>
      <span style={{width: 17, height: 17, border: '2px solid #777d7a', borderRadius: 99, position: 'relative'}}><span style={{position: 'absolute', width: 8, height: 2, backgroundColor: '#777d7a', right: -6, bottom: -3, transform: 'rotate(45deg)', borderRadius: 2}} /></span>
      <span style={{display: 'flex', alignItems: 'center', gap: 4}}><span style={{width: 5, height: 14, backgroundColor: '#777d7a', borderRadius: 2}} /><span style={{width: 5, height: 10, backgroundColor: '#777d7a', borderRadius: 2}} /><span style={{width: 5, height: 17, backgroundColor: '#777d7a', borderRadius: 2}} /></span>
      <span style={{width: 34, height: 34, borderRadius: 99, backgroundColor: '#eae7df', border: '1px solid #e6e6e6'}} />
    </div>
  </div>
);

const AppBottomBar = ({opacity = 1}) => (
  <div style={{
    position: 'absolute',
    left: 0,
    right: 0,
    bottom: 0,
    height: 76,
    padding: '0 36px',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    backgroundColor: '#ffffff',
    borderTop: '1px solid #e6e6e6',
    zIndex: 20,
    opacity,
  }}>
    {['home', 'discover', 'rooms', 'profile'].map((label, index) => (
      <div key={label} style={{display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 5, color: index === 0 ? '#2d7a4a' : '#9aa09d', fontSize: 12, fontWeight: 800}}>
        <span style={{width: 16, height: 16, borderRadius: index === 0 ? 5 : 99, border: `2px solid ${index === 0 ? '#4caf6e' : '#9aa09d'}`, transform: index === 0 ? 'rotate(45deg)' : 'none'}} />
        <span>{label}</span>
      </div>
    ))}
  </div>
);

// this is the real app surface without a device frame; the camera moves through
// the feed so each proof state feels like a product interaction, not a slide.
const AppViewport = ({frame}) => {
  const {fps} = useVideoConfig();
  const viewIn = bounceIn(frame, fps, 184, 18);
  // each ui state gets its own window after the preceding narrative has fully
  // exited; this keeps the headline readable and prevents visual competition.
  const appWindow = (start, end) => fade(frame, start, start + 12) * fadeOut(frame, end - 12, end);
  const viewOpacity = Math.max(
    appWindow(184, 330),
    appWindow(392, 468),
    appWindow(530, 606),
    appWindow(668, 744),
  );
  // once the camera reaches a target, hide the app chrome so the target owns
  // the frame instead of competing with the persistent header and tab bar.
  const focusWindow = (start, end) => fade(frame, start, start + 10) * fadeOut(frame, end - 10, end);
  const focusOpacity = Math.max(
    focusWindow(218, 322),
    focusWindow(396, 460),
    focusWindow(538, 598),
    focusWindow(676, 730),
  );
  const echoFocusMode = frame >= 218 && frame < 322 ? 'title' : undefined;
  const reviewFocusMode = frame >= 396 && frame < 460 ? 'challenge' : undefined;
  const trustFocusMode = frame >= 538 && frame < 598 ? 'trust' : undefined;
  const recordFocusMode = frame >= 676 && frame < 730 ? 'record' : undefined;
  const cameraScale = interpolate(
    frame,
    [176, 196, 218, 244, 278, 300, 322, 330, 350, 374, 396, 416, 440, 460, 468, 490, 530, 538, 560, 598, 606, 636, 668, 676, 730, 744, 780],
    [0.98, 1.00, 1.00, 1.12, 1.22, 1.10, 1.00, 1.00, 1.00, 1.05, 1.16, 1.08, 1.00, 1.00, 1.00, 1.08, 1.14, 1.02, 1.00, 1.14, 1.00, 1.00, 1.00, 1.06, 1.14, 1.00, 1.00],
    {...clamp, easing: Easing.bezier(0.16, 1, 0.3, 1)},
  );
  const cameraX = interpolate(
    frame,
    [176, 196, 218, 244, 278, 300, 322, 330, 350, 374, 396, 416, 440, 460, 468, 490, 530, 538, 560, 598, 606, 636, 668, 676, 730, 744, 780],
    [0, 0, 0, 35, 60, 20, 0, 0, 0, -150, -220, -170, -80, 0, 0, -80, -20, 0, 100, 160, 120, 0, 0, -100, -120, 0, 0],
    {...clamp, easing: Easing.bezier(0.16, 1, 0.3, 1)},
  );
  const cameraY = interpolate(
    frame,
    [176, 196, 218, 244, 278, 300, 322, 330, 350, 374, 396, 416, 440, 460, 468, 490, 530, 538, 560, 598, 606, 636, 668, 676, 730, 744, 780],
    [0, 0, 0, -10, -34, -12, 0, 0, 0, -20, -100, -40, 0, 0, 0, -25, -10, 0, 0, -40, 0, 0, 0, -40, -64, 0, 0],
    {...clamp, easing: Easing.bezier(0.16, 1, 0.3, 1)},
  );
  // the opening shot keeps the left edge readable while later beats re-center
  // around the signal meter and the final hash record.
  const cameraOrigin = frame < 330 ? 'center center' : frame < 468 ? 'right center' : 'center center';

  return (
    <div style={{
      position: 'absolute',
      left: 48,
      top: 610,
      width: 984,
      height: 1170,
      overflow: 'hidden',
      borderRadius: 34,
      backgroundColor: '#f8f7f5',
      border: '1px solid rgba(230, 230, 230, 0.95)',
      opacity: viewOpacity,
      transform: `scale(${interpolate(Math.max(0, viewIn), [0, 1], [0.96, 1], clamp)})`,
      transformOrigin: 'center center',
      boxShadow: '0 38px 100px rgba(0, 0, 0, 0.30)',
      zIndex: 18,
    }}>
      <AppTopBar opacity={1 - focusOpacity} />
      <div style={{position: 'absolute', top: 86, left: 0, right: 0, bottom: 76, overflow: 'hidden', backgroundColor: '#ffffff'}}>
      <div style={{position: 'absolute', inset: 0, transform: `translate(${cameraX}px, ${cameraY}px) scale(${cameraScale})`, transformOrigin: cameraOrigin}}>
          <MobileEchoCard frame={frame} focusMode={echoFocusMode} />
          <MobileReviewCard frame={frame} focusMode={reviewFocusMode} />
          <MobileTrustCard frame={frame} focusMode={trustFocusMode} />
          <MobileRecordCard frame={frame} focusMode={recordFocusMode} />
        </div>
      </div>
      <AppBottomBar opacity={1 - focusOpacity} />
    </div>
  );
};

const CameraCaption = ({frame, start, exitStart, label, children, color = palette.green, side = 'left'}) => {
  const {fps} = useVideoConfig();
  const intro = bounceIn(frame, fps, start, 18);
  const visible = fade(frame, start, start + 12) * fadeOut(frame, exitStart, exitStart + 16);
  const x = interpolate(Math.max(0, intro), [0, 1], [side === 'left' ? -34 : 34, 0], clamp);
  return (
    <div style={{
      position: 'absolute',
      left: side === 'left' ? 78 : 'auto',
      right: side === 'right' ? 78 : 'auto',
      top: 492,
      width: 350,
      zIndex: 42,
      opacity: visible,
      transform: `translateX(${x}px)`,
      textAlign: side === 'left' ? 'left' : 'right',
    }}>
      <div style={{display: 'inline-flex', alignItems: 'center', gap: 9, color, fontSize: 13, fontWeight: 900, letterSpacing: 2.6, textTransform: 'uppercase'}}>
        <span style={{width: 8, height: 8, borderRadius: 99, backgroundColor: color, boxShadow: `0 0 0 7px ${color}18`}} />
        {label}
      </div>
      <div style={{marginTop: 13, color: palette.paper, fontSize: 28, lineHeight: 1.04, fontWeight: 900, letterSpacing: -0.8}}>{children}</div>
      <div style={{marginTop: 13, width: 130, height: 3, marginLeft: side === 'right' ? 'auto' : 0, borderRadius: 99, backgroundColor: `${color}80`, transform: `scaleX(${interpolate(Math.max(0, intro), [0, 1], [0.04, 1], clamp)})`, transformOrigin: side === 'right' ? 'right center' : 'left center'}} />
    </div>
  );
};

const OpeningStatement = ({frame}) => {
  const {fps} = useVideoConfig();
  const intro = bounceIn(frame, fps, 12, 17);
  const exitSpring = spring({frame: Math.max(0, frame - 96), fps, config: {damping: 18, stiffness: 210, mass: 0.55}});
  const visible = fade(frame, 8, 24) * fadeOut(frame, 100, 112);
  const drift = interpolate(Math.max(0, intro), [0, 1], [32, 0], clamp);
  const introScale = interpolate(Math.max(0, intro), [0, 1], [1.24, 1], clamp);
  const exitY = interpolate(Math.max(0, exitSpring), [0, 1], [0, -130], clamp);
  const exitScale = interpolate(Math.max(0, exitSpring), [0, 1], [1, 1.16], clamp);
  return (
    <AbsoluteFill style={{opacity: visible, zIndex: 44, textAlign: 'center', pointerEvents: 'none'}}>
      <div style={{position: 'absolute', left: 92, right: 92, top: 625, transform: `translate3d(0, ${drift + exitY}px, 0) scale(${introScale * exitScale})`, transformOrigin: 'center center'}}>
        <div style={{color: palette.gold, fontSize: 16, fontWeight: 900, letterSpacing: 4, textTransform: 'uppercase'}}>before the signal</div>
        <div style={{marginTop: 27, color: palette.paper, fontSize: 82, lineHeight: 0.96, fontWeight: 950, letterSpacing: -2.4}}>the claim is only<br /><span style={{color: palette.green}}>the beginning.</span></div>
        <div style={{marginTop: 28, color: palette.muted, fontSize: 23, lineHeight: 1.28, fontWeight: 650}}>the receipt is what makes it useful.</div>
      </div>
    </AbsoluteFill>
  );
};

const PhaseNarrative = ({frame, start, exitStart, exitEnd = exitStart + 16, label, children, color = palette.green}) => {
  const {fps} = useVideoConfig();
  const intro = bounceIn(frame, fps, start, 17);
  const exitSpring = spring({frame: Math.max(0, frame - exitStart), fps, config: {damping: 18, stiffness: 210, mass: 0.55}});
  const visible = fade(frame, start, start + 10) * fadeOut(frame, exitStart, exitEnd);
  const y = interpolate(Math.max(0, intro), [0, 1], [26, 0], clamp);
  const scale = interpolate(Math.max(0, intro), [0, 1], [1.32, 1], clamp);
  const exitY = interpolate(Math.max(0, exitSpring), [0, 1], [0, -18], clamp);
  const exitScale = interpolate(Math.max(0, exitSpring), [0, 1], [1, 1.18], clamp);
  return (
    <div style={{
      position: 'absolute',
      left: 94,
      right: 94,
      top: 520,
      zIndex: 43,
      opacity: visible,
      transform: `translate3d(0, ${y + exitY}px, 0) scale(${scale * exitScale})`,
      transformOrigin: 'center center',
      textAlign: 'center',
      pointerEvents: 'none',
    }}>
      <div style={{display: 'inline-flex', alignItems: 'center', gap: 9, color, fontSize: 13, fontWeight: 900, letterSpacing: 3, textTransform: 'uppercase'}}>
        <span style={{width: 9, height: 9, borderRadius: 99, backgroundColor: color, boxShadow: `0 0 0 7px ${color}1c`}} />
        {label}
      </div>
      <div style={{marginTop: 13, color: palette.paper, fontSize: 78, lineHeight: 0.95, fontWeight: 950, letterSpacing: -2.4}}>{children}</div>
      <div style={{width: 132, height: 3, margin: '16px auto 0', borderRadius: 99, backgroundColor: `${color}a6`, transform: `scaleX(${interpolate(Math.max(0, intro), [0, 1], [0.05, 1], clamp)})`, transformOrigin: 'center center'}} />
    </div>
  );
};

// the master camera is the primary motion system; the app viewport supplies the
// subject, while this layer creates the wide push, lateral sweep, and pull-back.
const LaunchCamera = ({frame, children}) => {
  const scale = interpolate(
    frame,
    [0, 18, 108, 124, 150, 180, 196, 218, 244, 278, 300, 322, 330, 350, 374, 392, 396, 416, 440, 460, 468, 490, 530, 538, 560, 598, 606, 636, 668, 676, 730, 744, 780],
    [0.98, 1.00, 1.00, 0.82, 0.96, 1.00, 1.00, 1.18, 1.46, 1.40, 1.20, 1.00, 1.00, 1.00, 1.00, 1.00, 1.18, 1.58, 1.38, 1.08, 1.00, 1.08, 1.00, 1.00, 1.48, 1.18, 1.00, 1.00, 1.00, 1.34, 1.52, 1.00, 1.00],
    {...clamp, easing: Easing.bezier(0.16, 1, 0.3, 1)},
  );
  const x = interpolate(
    frame,
    [0, 18, 108, 124, 150, 180, 196, 218, 244, 278, 300, 322, 330, 350, 374, 392, 396, 416, 440, 460, 468, 490, 530, 538, 560, 598, 606, 636, 668, 676, 730, 744, 780],
    [0, 0, 0, -180, -60, 0, 0, 100, 220, 210, 170, 135, 0, 0, 0, 0, 60, -220, -220, -120, -30, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    {...clamp, easing: Easing.bezier(0.16, 1, 0.3, 1)},
  );
  const y = interpolate(
    frame,
    [0, 18, 108, 124, 150, 180, 196, 218, 244, 278, 300, 322, 330, 350, 374, 392, 396, 416, 440, 460, 468, 490, 530, 538, 560, 598, 606, 636, 668, 676, 730, 744, 780],
    [0, 0, 0, 100, 30, 0, 0, 0, -12, -68, -64, -16, 0, 0, 0, 0, 0, -90, -80, -20, 0, 0, 0, 0, -34, 0, 0, 0, 0, -40, -60, 0, 0],
    {...clamp, easing: Easing.bezier(0.16, 1, 0.3, 1)},
  );
  const rotateY = interpolate(frame, [96, 116, 142, 166, 190, 212, 252, 280, 316, 348, 372, 410, 430, 458, 500, 532, 560, 600, 640, 680], [0, 8, 4, 0, 0, -1, -1, -2, -2, 0, 0, 1, 0, -1, -1, 0, 0, -2, -2, 0], {...clamp, easing: Easing.bezier(0.16, 1, 0.3, 1)});
  const rotateX = interpolate(frame, [96, 116, 142, 166, 190, 212, 252, 280, 316, 348, 372, 410, 430, 458, 500, 532, 560, 600, 640, 680], [0, 4, 2, 0, 0, 0, 0, 1, 1, 0, 0, 2, 0, 0, 0, 0, 0, 1, 1, 0], {...clamp, easing: Easing.bezier(0.16, 1, 0.3, 1)});
  const transformOrigin = frame < 166 ? '16% 50%' : frame < 350 ? '50% 48%' : frame < 570 ? '52% 50%' : '50% 52%';
  return <div style={{position: 'absolute', inset: 0, perspective: 1800, transform: `translate3d(${x}px, ${y}px, 0) rotateY(${rotateY}deg) rotateX(${rotateX}deg) scale(${scale})`, transformOrigin}}>{children}</div>;
};

const MobileShell = ({frame}) => {
  const {fps} = useVideoConfig();
  const shellIn = bounceIn(frame, fps, 12, 18);
  const shellOpacity = fade(frame, 8, 22) * fadeOut(frame, 638, 680);
  return (
    <div style={{
      position: 'absolute',
      left: 148,
      top: 560,
      width: 784,
      height: 1110,
      padding: 20,
      borderRadius: 60,
      border: '2px solid rgba(205, 240, 213, 0.30)',
      backgroundColor: '#111718',
      opacity: shellOpacity,
      transform: `scale(${interpolate(Math.max(0, shellIn), [0, 1], [0.92, 1], clamp)})`,
      transformOrigin: 'center center',
      boxShadow: '0 44px 100px rgba(0,0,0,0.38)',
      zIndex: 18,
    }}>
      <div style={{position: 'relative', width: '100%', height: '100%', overflow: 'hidden', padding: '38px 26px 28px', borderRadius: 43, backgroundColor: '#edf7ee'}}>
        <div style={{position: 'absolute', top: 13, left: '50%', width: 170, height: 20, borderRadius: 99, backgroundColor: palette.ink, transform: 'translateX(-50%)'}} />
        <MobileEchoCard frame={frame} />
        <MobileReviewCard frame={frame} />
        <MobileTrustCard frame={frame} />
        <MobileRecordCard frame={frame} />
        <div style={{position: 'absolute', left: 26, right: 26, bottom: 17, display: 'flex', justifyContent: 'space-around', color: '#72907b', fontSize: 13, fontWeight: 850}}><span style={{color: '#23854a'}}>home</span><span>search</span><span>rooms</span><span>profile</span></div>
      </div>
    </div>
  );
};

const ClaimCard = ({frame, opacity = 1}) => {
  const {fps} = useVideoConfig();
  const cardIn = bounceIn(frame, fps, 16, 18);
  const x = interpolate(frame, [0, 84, 168, 360, 540, 650], [0, -80, -165, -150, -100, 0], clamp);
  const y = interpolate(frame, [0, 84, 168, 360, 540, 650], [40, 20, -10, -35, -55, 0], clamp);
  const scale = interpolate(frame, [0, 84, 168, 360, 540, 650], [1, 0.98, 0.92, 0.86, 0.84, 0.88], clamp);
  const statusProgress = fade(frame, 520, 570);
  return (
    <div style={{
      position: 'absolute',
      left: '50%',
      top: 770,
      width: 744,
      padding: '26px 30px 28px',
      borderRadius: 28,
      border: `1px solid ${palette.green}54`,
      backgroundColor: 'rgba(16, 38, 26, 0.96)',
      boxShadow: '0 34px 90px rgba(0,0,0,0.30)',
      opacity: fadeOut(frame, 642, 686) * opacity,
      transform: `translate(-50%, -50%) translate(${x}px, ${y}px) scale(${scale * interpolate(cardIn, [0, 1], [0.86, 1], clamp)})`,
      transformOrigin: 'center center',
      zIndex: 8,
    }}>
      <div style={{display: 'flex', justifyContent: 'space-between', alignItems: 'center'}}>
        <div style={{display: 'flex', alignItems: 'center', gap: 11, color: palette.muted, fontSize: 15, fontWeight: 850, letterSpacing: 2.2, textTransform: 'uppercase'}}>
          <span style={{width: 10, height: 10, borderRadius: 99, backgroundColor: palette.gold, boxShadow: `0 0 0 7px ${palette.gold}1c`}} />
          illustrative claim
        </div>
        <div style={{color: statusProgress > 0.5 ? palette.green : palette.gold, fontSize: 16, fontWeight: 850, letterSpacing: 1.9, textTransform: 'uppercase'}}>
          {statusProgress > 0.5 ? 'verified' : 'unverified'}
        </div>
      </div>
      <div style={{marginTop: 27, color: palette.paper, fontSize: 49, lineHeight: 1.04, fontWeight: 900, letterSpacing: -1.3}}>
        the city water is safe to drink.
      </div>
      <div style={{marginTop: 14, color: palette.muted, fontSize: 21, lineHeight: 1.28, fontWeight: 650}}>
        the claim starts unverified. the community checks the evidence in public.
      </div>
      <div style={{display: 'flex', gap: 12, marginTop: 25}}>
        <div style={{flex: 1, display: 'flex', alignItems: 'center', gap: 9, padding: '14px 15px', borderRadius: 14, border: `1px solid ${palette.green}52`, color: palette.green, fontSize: 18, fontWeight: 850}}><Icon kind="support" frame={frame} start={118} color={palette.green} size={24} /> support</div>
        <div style={{flex: 1, display: 'flex', alignItems: 'center', gap: 9, padding: '14px 15px', borderRadius: 14, border: `1px solid ${palette.coral}52`, color: palette.coral, fontSize: 18, fontWeight: 850}}><Icon kind="challenge" frame={frame} start={132} color={palette.coral} size={24} /> challenge</div>
      </div>
    </div>
  );
};

const SignalNode = ({frame, start, x, y, kind, tier, weight, color}) => {
  const {fps} = useVideoConfig();
  const progress = bounceIn(frame, fps, start, 15);
  const travel = interpolate(progress, [0, 1], [42, 0], clamp);
  return (
    <div style={{
      position: 'absolute',
      left: x,
      top: y,
      display: 'flex',
      alignItems: 'center',
      gap: 10,
      padding: '13px 15px',
      borderRadius: 16,
      border: `1px solid ${color}6b`,
      backgroundColor: 'rgba(7, 18, 12, 0.92)',
      opacity: fade(frame, start, start + 12),
      transform: `translate(${travel * (x < 540 ? -1 : 1)}px, ${travel * (y < 720 ? -1 : 1)}px) scale(${interpolate(progress, [0, 1], [0.88, 1], clamp)})`,
      boxShadow: `0 20px 42px ${color}19`,
      zIndex: 14,
    }}>
      <Icon kind={kind} frame={frame} start={start + 4} color={color} size={28} />
      <div>
        <div style={{color: palette.paper, fontSize: 18, fontWeight: 850}}>{tier}</div>
        <div style={{marginTop: 3, color, fontSize: 14, fontWeight: 850, letterSpacing: 1.3}}>{weight}x signal</div>
      </div>
    </div>
  );
};

const CommunitySignals = ({frame}) => (
  <div style={{opacity: fadeOut(frame, 330, 390)}}>
    <ConnectionLine frame={frame} start={150} x1={155} y1={570} x2={430} y2={720} color={palette.green} />
    <ConnectionLine frame={frame} start={166} x1={850} y1={550} x2={665} y2={720} color={palette.coral} />
    <ConnectionLine frame={frame} start={183} x1={240} y1={1020} x2={450} y2={850} color={palette.teal} />
    <ConnectionLine frame={frame} start={199} x1={840} y1={1030} x2={670} y2={850} color={palette.gold} />
    <SignalNode frame={frame} start={142} x={94} y={508} kind="support" tier="high" weight={4} color={palette.green} />
    <SignalNode frame={frame} start={158} x={766} y={488} kind="challenge" tier="unverified" weight={1} color={palette.coral} />
    <SignalNode frame={frame} start={175} x={166} y={1000} kind="support" tier="medium" weight={3} color={palette.teal} />
    <SignalNode frame={frame} start={191} x={750} y={1010} kind="challenge" tier="elite" weight={5} color={palette.gold} />
  </div>
);

const WeightPanel = ({frame}) => {
  const weights = [
    ['unverified', '1x', palette.muted],
    ['low', '2x', palette.teal],
    ['high', '4x', palette.green],
    ['elite', '5x', palette.gold],
  ];
  return (
    <div style={{position: 'absolute', left: 76, right: 76, top: 1290, opacity: fade(frame, 236, 252) * fadeOut(frame, 360, 390), transform: `translateY(${interpolate(frame, [236, 252], [26, 0], {...clamp, ...ease})}px)`, zIndex: 20}}>
      <div style={{color: palette.muted, fontSize: 15, letterSpacing: 2.4, textTransform: 'uppercase', fontWeight: 850}}>trust changes the weight</div>
      <div style={{display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 10, marginTop: 16}}>
        {weights.map(([label, value, color], index) => {
          const itemProgress = fade(frame, 248 + index * 8, 260 + index * 8);
          return <div key={label} style={{padding: '14px 11px', borderRadius: 15, border: `1px solid ${color}52`, backgroundColor: 'rgba(16,38,26,0.82)', opacity: itemProgress}}>
            <div style={{color, fontSize: 25, fontWeight: 900}}>{value}</div>
            <div style={{marginTop: 5, color: palette.muted, fontSize: 12, fontWeight: 800, letterSpacing: 1.2, textTransform: 'uppercase'}}>{label}</div>
            <div style={{height: 4, marginTop: 13, borderRadius: 99, backgroundColor: `${color}22`, overflow: 'hidden'}}><div style={{width: `${Number(value[0]) * 20}%`, height: '100%', borderRadius: 99, backgroundColor: color}} /></div>
          </div>;
        })}
      </div>
    </div>
  );
};

const ConfidencePanel = ({frame}) => {
  const value = interpolate(frame, [352, 390, 430, 470, 514], [41, 55, 64, 71, 84], clamp);
  const trust = interpolate(frame, [352, 430, 514], [24, 42, 62], clamp);
  return (
    <div style={{position: 'absolute', left: 100, right: 100, top: 1100, opacity: fade(frame, 340, 356) * fadeOut(frame, 512, 548), transform: `translateY(${interpolate(frame, [340, 356], [30, 0], {...clamp, ...ease})}px)`, zIndex: 24}}>
      <div style={{display: 'flex', justifyContent: 'space-between', alignItems: 'end'}}>
        <div>
          <div style={{color: palette.muted, fontSize: 16, letterSpacing: 2.5, textTransform: 'uppercase', fontWeight: 850}}>community confidence</div>
          <div style={{marginTop: 10, color: palette.paper, fontSize: 64, lineHeight: 1, fontWeight: 900, letterSpacing: -2}}>{Math.round(value)}%</div>
        </div>
        <div style={{textAlign: 'right'}}>
          <div style={{color: palette.muted, fontSize: 16, letterSpacing: 2.5, textTransform: 'uppercase', fontWeight: 850}}>trust score</div>
          <div style={{marginTop: 10, color: palette.green, fontSize: 38, lineHeight: 1, fontWeight: 900}}>{Math.round(trust)}</div>
        </div>
      </div>
      <div style={{height: 14, marginTop: 28, borderRadius: 99, backgroundColor: `${palette.paper}18`, overflow: 'hidden'}}>
        <div style={{width: `${value}%`, height: '100%', borderRadius: 99, backgroundColor: palette.green, boxShadow: `0 0 22px ${palette.green}70`}} />
      </div>
      <div style={{position: 'relative', height: 30, marginTop: 6}}>
        <div style={{position: 'absolute', left: '70%', top: 0, bottom: 0, width: 2, backgroundColor: palette.gold}} />
        <div style={{position: 'absolute', left: '70%', top: 17, color: palette.gold, fontSize: 13, fontWeight: 850, letterSpacing: 1.2, transform: 'translateX(-50%)', whiteSpace: 'nowrap'}}>verification threshold</div>
      </div>
    </div>
  );
};

const ThresholdMoment = ({frame}) => {
  const threshold = fade(frame, 454, 476);
  const cross = fade(frame, 486, 512);
  return (
    <div style={{position: 'absolute', left: 72, right: 72, top: 300, textAlign: 'center', opacity: threshold * fadeOut(frame, 532, 556), zIndex: 30}}>
      <Kicker frame={frame} start={454} color={palette.gold} align="center">the threshold is clear</Kicker>
      <div style={{marginTop: 26, color: palette.paper, fontSize: 59, lineHeight: 1.02, fontWeight: 900, letterSpacing: -1.7, transform: `scale(${1 + cross * 0.035})`}}>signal becomes<br /><span style={{color: palette.green}}>verification.</span></div>
      <div style={{display: 'inline-flex', gap: 22, marginTop: 30, padding: '15px 20px', borderRadius: 16, border: `1px solid ${palette.gold}5e`, backgroundColor: 'rgba(16,38,26,0.8)', color: palette.gold, fontSize: 18, fontWeight: 850, letterSpacing: 1.2}}>
        <span>confidence &gt; 70%</span><span style={{color: palette.muted}}>|</span><span>trust &gt; 50</span>
      </div>
    </div>
  );
};

const RecordCard = ({frame}) => {
  const {fps} = useVideoConfig();
  const progress = bounceIn(frame, fps, 538, 16);
  return (
    <div style={{position: 'absolute', left: 92, right: 92, top: 690, padding: '28px 28px 25px', borderTop: `3px solid ${palette.green}`, borderBottom: `1px solid ${palette.green}5e`, backgroundColor: 'rgba(16,38,26,0.98)', opacity: fade(frame, 532, 550) * fadeOut(frame, 676, 706), transform: `translateY(${interpolate(frame, [532, 550], [48, 0], {...clamp, ...ease})}px) scale(${interpolate(progress, [0, 1], [0.92, 1], clamp)})`, zIndex: 28, boxShadow: '0 34px 90px rgba(0,0,0,0.34)'}}>
      <div style={{display: 'flex', justifyContent: 'space-between', alignItems: 'center', color: palette.muted, fontSize: 15, letterSpacing: 2.1, textTransform: 'uppercase', fontWeight: 850}}>
        <span style={{display: 'flex', alignItems: 'center', gap: 8}}><Icon kind="record" frame={frame} start={548} color={palette.green} size={29} /> proof receipt</span>
        <span style={{display: 'flex', alignItems: 'center', gap: 8, color: palette.green}}><Icon kind="anchor" frame={frame} start={560} color={palette.green} size={26} /> on-chain</span>
      </div>
      <div style={{margin: '62px 0 46px', color: palette.green, fontSize: 34, letterSpacing: 1.7, fontWeight: 850, textAlign: 'center'}}>sha256 / 7d8f / 3a21 / 84c0</div>
      <div style={{display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 12, paddingTop: 20, borderTop: `1px solid ${palette.paper}1f`}}>
        <div><div style={{color: palette.muted, fontSize: 13, letterSpacing: 1.4, textTransform: 'uppercase', fontWeight: 800}}>claim</div><div style={{marginTop: 7, color: palette.paper, fontSize: 18, fontWeight: 850}}>water safe</div></div>
        <div><div style={{color: palette.muted, fontSize: 13, letterSpacing: 1.4, textTransform: 'uppercase', fontWeight: 800}}>review</div><div style={{marginTop: 7, color: palette.paper, fontSize: 18, fontWeight: 850}}>84%</div></div>
        <div><div style={{color: palette.muted, fontSize: 13, letterSpacing: 1.4, textTransform: 'uppercase', fontWeight: 800}}>anchor</div><div style={{marginTop: 7, color: palette.paper, fontSize: 18, fontWeight: 850}}>recorded</div></div>
      </div>
      <div style={{marginTop: 23, color: palette.muted, fontSize: 16, lineHeight: 1.25, textAlign: 'center'}}>the receipt preserves the claim, evidence trail, and outcome.</div>
    </div>
  );
};

const Outro = ({frame, playStoreUrl}) => {
  const {fps} = useVideoConfig();
  const progress = bounceIn(frame, fps, 744, 16);
  return (
    <AbsoluteFill style={{alignItems: 'center', justifyContent: 'center', textAlign: 'center', opacity: fade(frame, 742, 758), zIndex: 50}}>
      <Img src={staticFile('assets/echoproof-logo.png')} style={{width: 146, height: 146, borderRadius: 38, transform: `scale(${interpolate(progress, [0, 1], [0.76, 1], clamp)})`}} />
      <div style={{marginTop: 34, color: palette.paper, fontSize: 68, lineHeight: 0.98, fontWeight: 900, letterSpacing: -2.4}}>truth, verified<br /><span style={{color: palette.green}}>by community.</span></div>
      <div style={{marginTop: 25, color: palette.muted, fontSize: 22, lineHeight: 1.28}}>post an echo. bring the receipt.<br />let the record speak for itself.</div>
      <a href={playStoreUrl} style={{display: 'block', marginTop: 52, textDecoration: 'none', transform: `scale(${interpolate(bounceIn(frame, fps, 762, 14), [0, 1], [0.86, 1], clamp)})`}}>
        {/* this is the official google play badge asset, kept intact for brand clarity. */}
        <Img src={staticFile('assets/google-play-badge.png')} alt="get it on Google Play" style={{display: 'block', width: 292, height: 'auto'}} />
      </a>
      <div style={{position: 'absolute', bottom: 148, color: palette.muted, fontSize: 15, letterSpacing: 1.2}}>echoproof.online</div>
    </AbsoluteFill>
  );
};

const LaunchFilm = ({playStoreUrl}) => {
  const frame = useCurrentFrame();
  return (
    <AbsoluteFill style={{backgroundColor: palette.ink, color: palette.paper, overflow: 'hidden', fontFamily: 'Arial, Helvetica, sans-serif'}}>
      <Background frame={frame} />
      <OpeningStatement frame={frame} />
      <LaunchCamera frame={frame}>
        <AppViewport frame={frame} />
      </LaunchCamera>
      <PhaseNarrative frame={frame} start={112} exitStart={166} exitEnd={184} label="post / 01" color={palette.gold}>a claim enters<br />unverified.</PhaseNarrative>
      <PhaseNarrative frame={frame} start={330} exitStart={374} exitEnd={392} label="community / 02" color={palette.coral}>the community can<br />challenge the claim.</PhaseNarrative>
      <PhaseNarrative frame={frame} start={468} exitStart={512} exitEnd={530} label="weight / 03" color={palette.green}>trust changes<br />the signal.</PhaseNarrative>
      <PhaseNarrative frame={frame} start={606} exitStart={650} exitEnd={668} label="record / 04" color={palette.violet}>when it clears,<br />the receipt stays.</PhaseNarrative>
      <Outro frame={frame} playStoreUrl={playStoreUrl} />
      <Sequence from={0} durationInFrames={780} name="cinematic soundstage">
        <Audio src={staticFile('audio/echoproof-launch-soundstage.wav')} volume={(audioFrame) => clampNumber(interpolate(audioFrame, [0, 18, 700, 780], [0, 0.78, 0.78, 0], clamp), 0, 0.78)} />
      </Sequence>
    </AbsoluteFill>
  );
};

export const EchoProofAppleLaunchFilm = ({playStoreUrl = 'https://play.google.com/store/apps/details?id=com.echoproof.app'}) => (
  <LaunchFilm playStoreUrl={playStoreUrl} />
);
