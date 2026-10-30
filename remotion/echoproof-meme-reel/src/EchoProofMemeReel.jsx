import React from 'react';
import {
  AbsoluteFill,
  Easing,
  Img,
  OffthreadVideo,
  Sequence,
  interpolate,
  spring,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from 'remotion';
import {Audio} from '@remotion/media';

const colors = {
  ink: '#07130e',
  paper: '#f4fbf4',
  muted: '#9ab3a2',
  green: '#56d67d',
  lime: '#baf6c8',
  teal: '#6de2d8',
  coral: '#ff8977',
  violet: '#a68cff',
  panel: '#10271a',
};

const playStoreUrl = 'https://play.google.com/store/apps/details?id=com.echoproof.app';
const downloadedHook = 'hooks/videohooks-little-shot-put.mp4';
const safeBottom = 170;

const clamp = {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'};

// each scene owns its own fade envelope so scene changes land on the same
// dark stage instead of hard-cutting between unrelated visual densities.
const sceneOpacity = (frame, duration, exit = 14) => interpolate(
  frame,
  [0, 12, duration - exit, duration],
  [0, 1, 1, 0],
  clamp,
);

const fadeIn = (frame, start, duration = 12) => interpolate(frame, [start, start + duration], [0, 1], clamp);

const fadeOut = (frame, start, duration = 12) => interpolate(frame, [start, start + duration], [1, 0], clamp);

const lift = (frame, start, distance = 36, duration = 18) => interpolate(frame, [start, start + duration], [`${distance}px`, '0px'], {
  ...clamp,
  easing: Easing.bezier(0.16, 1, 0.3, 1),
});

const bounce = (frame, fps, delay = 0, damping = 11) => spring({
  frame,
  fps,
  delay,
  config: {damping, stiffness: 180, mass: 0.62},
});

const logoStyle = {
  width: 58,
  height: 58,
  borderRadius: 16,
  border: '1px solid rgba(186,246,200,0.32)',
  boxShadow: '0 12px 30px rgba(0,0,0,0.25)',
};

const pageStyle = {
  fontFamily: 'Inter, Arial, sans-serif',
  letterSpacing: 0,
};

const Brand = ({frame}) => (
  <div
    style={{
      position: 'absolute',
      top: 66,
      left: 64,
      display: 'flex',
      alignItems: 'center',
      gap: 15,
      opacity: fadeIn(frame, 0, 16),
      zIndex: 20,
    }}
  >
    <Img src={staticFile('assets/echoproof-logo.png')} style={logoStyle} />
    <span style={{color: colors.paper, fontSize: 21, fontWeight: 800}}>EchoProof</span>
  </div>
);

const AnimatedIcon = ({type, frame, start = 0, color = colors.green, size = 42}) => {
  const {fps} = useVideoConfig();
  const progress = interpolate(bounce(frame, fps, start, 15), [0, 1], [0, 1], clamp);
  const common = {
    fill: 'none',
    stroke: color,
    strokeWidth: 2.6,
    strokeLinecap: 'round',
    strokeLinejoin: 'round',
  };

  return (
    <svg width={size} height={size} viewBox="0 0 48 48" style={{opacity: fadeIn(frame, start, 8), scale: interpolate(progress, [0, 1], [0.7, 1], clamp)}}>
      {type === 'source' && <><path {...common} d="M14 6h14l7 7v29H14z" /><path {...common} d="M28 6v8h7" /><path {...common} d="M20 25h9M20 32h9" strokeDasharray="40" strokeDashoffset={40 * (1 - progress)} /></>}
      {type === 'community' && <><circle {...common} cx="24" cy="16" r="6" /><circle {...common} cx="11" cy="23" r="4" /><circle {...common} cx="37" cy="23" r="4" /><path {...common} d="M13 38c1-6 5-9 11-9s10 3 11 9" strokeDasharray="60" strokeDashoffset={60 * (1 - progress)} /><path {...common} d="M4 38c.5-4 3-6 7-6M44 38c-.5-4-3-6-7-6" strokeDasharray="30" strokeDashoffset={30 * (1 - progress)} /></>}
      {type === 'hash' && <><path {...common} d="M19 6 15 42M33 6l-4 36M8 19h32M6 31h32" strokeDasharray="120" strokeDashoffset={120 * (1 - progress)} /></>}
      {type === 'check' && <><circle {...common} cx="24" cy="24" r="17" opacity="0.35" /><path {...common} d="m15 24 6 6 12-14" strokeDasharray="40" strokeDashoffset={40 * (1 - progress)} /></>}
    </svg>
  );
};

const DisclosurePanel = ({frame}) => {
  const open = interpolate(frame, [38, 54, 78, 96], [0, 1, 1, 0], clamp);
  const buttonPulse = interpolate(bounce(frame, 30, 38, 14), [0, 1], [0.92, 1], clamp);
  return (
    <div style={{
      position: 'absolute',
      left: 28,
      right: 28,
      top: 430,
      height: interpolate(open, [0, 1], [62, 250], clamp),
      overflow: 'hidden',
      borderRadius: 18,
      border: '1px solid rgba(42,138,77,0.26)',
      backgroundColor: 'rgba(255,255,255,0.72)',
      boxShadow: '0 12px 25px rgba(17,72,39,0.08)',
    }}>
      <div style={{height: 62, padding: '9px 16px', display: 'flex', alignItems: 'center', justifyContent: 'space-between', color: '#2f7146', fontSize: 17, fontWeight: 850, transformOrigin: 'center', scale: buttonPulse}}>
        <span style={{display: 'flex', alignItems: 'center', gap: 10}}><AnimatedIcon type="source" frame={frame} start={38} color="#2f9b58" size={31} /> source details</span>
        <span style={{position: 'relative', width: 28, height: 28, borderRadius: '50%', border: '1px solid rgba(47,155,88,0.4)'}}>
          <span style={{position: 'absolute', left: 7, top: 13, width: 12, height: 2, borderRadius: 2, backgroundColor: '#2f9b58'}} />
          <span style={{position: 'absolute', left: 12, top: 8, width: 2, height: 12, borderRadius: 2, backgroundColor: '#2f9b58', opacity: 1 - open}} />
        </span>
      </div>
      <div style={{padding: '0 18px 16px', opacity: open, translate: `0px ${interpolate(open, [0, 1], ['18px', '0px'], clamp)}`}}>
        <div style={{height: 1, backgroundColor: 'rgba(42,138,77,0.16)', marginBottom: 13}} />
        <div style={{display: 'flex', alignItems: 'center', gap: 9, color: '#527360', fontSize: 15, fontWeight: 750}}><AnimatedIcon type="source" frame={frame} start={48} color="#2f9b58" size={24} /> source attached</div>
        <div style={{display: 'flex', alignItems: 'center', gap: 9, marginTop: 12, color: '#527360', fontSize: 15, fontWeight: 750}}><AnimatedIcon type="community" frame={frame} start={55} color="#2aaea5" size={24} /> community review ready</div>
        <div style={{display: 'flex', alignItems: 'center', gap: 9, marginTop: 12, color: '#527360', fontSize: 15, fontWeight: 750}}><AnimatedIcon type="hash" frame={frame} start={62} color="#7965d7" size={24} /> record after the window closes</div>
      </div>
    </div>
  );
};

const Grain = ({frame}) => (
  <AbsoluteFill
    style={{
      pointerEvents: 'none',
      opacity: 0.07,
      backgroundImage: 'radial-gradient(rgba(255,255,255,0.8) 0.7px, transparent 0.8px)',
      backgroundSize: '5px 5px',
      mixBlendMode: 'soft-light',
      transform: `translateX(${Math.sin(frame / 17) * 2}px)`,
    }}
  />
);

const PaintedPhrase = ({children, frame, start = 0, paintColor = colors.green, paint = true, underline = false, underlineColor = colors.coral}) => {
  const {fps} = useVideoConfig();
  const progress = bounce(frame, fps, start, 14);
  return (
    <span style={{position: 'relative', display: 'inline-block', padding: '0 13px 11px', margin: '0 -4px', fontFamily: underline ? 'Georgia, Times New Roman, serif' : 'inherit', fontStyle: underline ? 'italic' : 'normal', fontWeight: underline ? 700 : 'inherit'}}>
      {paint && <svg viewBox="0 0 100 44" preserveAspectRatio="none" style={{position: 'absolute', left: -5, right: -5, top: 14, width: 'calc(100% + 10px)', height: '70%', zIndex: 0, opacity: 0.68, scale: interpolate(progress, [0, 1], [0.15, 1], clamp), rotate: '-1.5deg', transformOrigin: 'left center'}}>
        <path d="M2 15C18 7 32 12 48 9c17-3 31 5 50 1v23c-16 4-31-2-48 1-16 3-31-3-48 1z" fill={paintColor} />
      </svg>}
      <span style={{position: 'relative', zIndex: 1}}>{children}</span>
      {underline && <svg viewBox="0 0 100 18" preserveAspectRatio="none" style={{position: 'absolute', left: 2, right: 2, bottom: -1, width: 'calc(100% - 4px)', height: 18, zIndex: 2, overflow: 'visible', opacity: fadeIn(frame, start + 4, 8)}}>
        <path d="M2 10C21 15 34 5 51 10s30 2 47-2" fill="none" stroke={underlineColor} strokeWidth="5" strokeLinecap="round" strokeDasharray="110" strokeDashoffset={110 * (1 - progress)} />
      </svg>}
    </span>
  );
};

const BouncyText = ({children, frame, fps, delay = 0, color = colors.paper, size = 86, align = 'left', paint = false, paintColor = colors.green, underline = false, underlineColor = colors.coral}) => {
  const progress = bounce(frame, fps, delay, 10);
  return (
    <div
      style={{
        display: 'inline-block',
        color,
        fontSize: size,
        lineHeight: 0.93,
        fontWeight: 900,
        letterSpacing: -2.6,
        textAlign: align,
        opacity: fadeIn(frame, delay, 4),
        scale: interpolate(progress, [0, 1], [0.72, 1], {...clamp, easing: Easing.out(Easing.quad)}),
        translate: `0px ${interpolate(progress, [0, 1], ['46px', '0px'], clamp)}`,
        rotate: interpolate(progress, [0, 1], ['-5deg', '0deg'], clamp),
        transformOrigin: 'left center',
      }}
    >
      {paint || underline ? <PaintedPhrase frame={frame} start={delay} paint={paint} paintColor={paintColor} underline={underline} underlineColor={underlineColor}>{children}</PaintedPhrase> : children}
    </div>
  );
};

const Kicker = ({children, frame, start = 0, color = colors.green}) => (
  <div style={{
    color,
    fontSize: 17,
    lineHeight: 1.1,
    letterSpacing: 3,
    textTransform: 'uppercase',
    fontWeight: 850,
    opacity: fadeIn(frame, start, 12),
    translate: `0px ${lift(frame, start, 22, 18)}`,
  }}>
    {children}
  </div>
);

const Sticker = ({children, color, frame, start = 0, rotate = '-5deg'}) => (
  <div style={{
    display: 'inline-flex',
    alignItems: 'center',
    padding: '13px 18px',
    borderRadius: 14,
    border: `2px solid ${color}`,
    color,
    backgroundColor: 'rgba(7,19,14,0.84)',
    fontSize: 20,
    fontWeight: 900,
    opacity: fadeIn(frame, start, 10),
    scale: interpolate(bounce(frame, 30, start, 14), [0, 1], [0.75, 1], {...clamp, easing: Easing.out(Easing.quad)}),
    rotate,
    boxShadow: `0 12px 28px ${color}25`,
  }}>
    {children}
  </div>
);

const KineticBottomLine = ({children, frame, start = 0, color = colors.paper, accent = colors.green}) => {
  const {fps} = useVideoConfig();
  const progress = bounce(frame, fps, start, 12);
  return (
    <div style={{
      position: 'absolute',
      left: 64,
      right: 64,
      bottom: safeBottom,
      display: 'flex',
      justifyContent: 'center',
      zIndex: 12,
      opacity: fadeIn(frame, start, 10),
      scale: interpolate(progress, [0, 1], [0.82, 1], clamp),
      translate: `0px ${interpolate(progress, [0, 1], ['34px', '0px'], clamp)}`,
      transformOrigin: 'center bottom',
    }}>
      <div style={{
        maxWidth: 900,
        padding: '15px 24px 17px',
        borderRadius: 18,
        border: `1px solid ${accent}55`,
        backgroundColor: 'rgba(7,19,14,0.9)',
        boxShadow: `0 16px 38px ${accent}22`,
        color,
        fontSize: 40,
        lineHeight: 1.02,
        fontWeight: 900,
        letterSpacing: -0.7,
        textAlign: 'center',
      }}>
        {children}
      </div>
    </div>
  );
};

// this opening clip is deliberately isolated from the product scenes so the
// first beat reads as a hook, while the overlay remains inside a mobile-safe
// caption area on short screens and platform ui overlays.
const ExternalHookScene = () => {
  const frame = useCurrentFrame();
  const videoOpacity = interpolate(frame, [0, 8, 72, 90], [0, 1, 1, 0], clamp);
  const videoScale = interpolate(frame, [0, 90], [1.08, 1.02], clamp);
  return (
    <AbsoluteFill style={{...pageStyle, backgroundColor: colors.ink, overflow: 'hidden'}}>
      <OffthreadVideo
        src={staticFile(downloadedHook)}
        startFrom={0}
        style={{
          position: 'absolute',
          width: '100%',
          height: '100%',
          objectFit: 'cover',
          opacity: videoOpacity,
          transform: `scale(${videoScale})`,
          filter: 'saturate(0.88) contrast(1.08)',
        }}
      />
      <AbsoluteFill style={{backgroundImage: 'linear-gradient(180deg, rgba(7,19,14,0.68) 0%, rgba(7,19,14,0.05) 35%, rgba(7,19,14,0.82) 100%)', opacity: videoOpacity}} />
      <div style={{position: 'absolute', top: 112, left: 64, right: 64, color: colors.paper, fontSize: 52, lineHeight: 1, fontWeight: 900, letterSpacing: -1.4, textAlign: 'center', opacity: videoOpacity}}>pov: the source is “trust me bro”</div>
    </AbsoluteFill>
  );
};

const SourceCard = ({frame}) => {
  const {fps} = useVideoConfig();
  const cardProgress = bounce(frame, fps, 16, 14);
  const meter = interpolate(frame, [34, 76], [0, 0.04], clamp);
  return (
    <div style={{
      position: 'absolute',
      left: 76,
      right: 76,
      top: 690,
      padding: '25px 28px 28px',
      borderRadius: 28,
      backgroundColor: '#f4fbf4',
      color: colors.ink,
      opacity: fadeIn(frame, 8, 12),
      scale: interpolate(cardProgress, [0, 1], [0.88, 1], clamp),
      translate: `0px ${lift(frame, 8, 54, 22)}`,
      rotate: '-1.2deg',
      boxShadow: '0 30px 70px rgba(0,0,0,0.32)',
      transformOrigin: 'center center',
    }}>
      <div style={{display: 'flex', alignItems: 'center', justifyContent: 'space-between', color: '#5d7867', fontSize: 16, letterSpacing: 2, textTransform: 'uppercase', fontWeight: 850}}>
        <span style={{display: 'flex', alignItems: 'center', gap: 8}}><AnimatedIcon type="source" frame={frame} start={12} color="#2f9b58" size={29} /> source check</span>
        <span style={{color: colors.coral}}>context missing</span>
      </div>
      <div style={{marginTop: 30, textAlign: 'center'}}>
        <div style={{fontSize: 68, lineHeight: 0.9, fontWeight: 950, letterSpacing: -2.8}}>trust me</div>
        <div style={{marginTop: 8}}><BouncyText frame={frame} fps={fps} delay={24} size={78} color="#e86454" align="center" underline underlineColor="#e86454">bro</BouncyText></div>
      </div>
      <div style={{marginTop: 25, height: 11, borderRadius: 99, backgroundColor: '#e4eee5', overflow: 'hidden'}}><div style={{width: `${meter * 100}%`, height: '100%', borderRadius: 99, backgroundColor: colors.coral}} /></div>
      <div style={{display: 'flex', justifyContent: 'space-between', marginTop: 11, color: '#6c8574', fontSize: 16, fontWeight: 800}}><span>source confidence</span><span style={{color: colors.coral}}>0.04%</span></div>
    </div>
  );
};

const MemePost = ({frame, start = 0}) => (
  <div style={{
    position: 'absolute',
    left: 64,
    right: 64,
    top: 1045,
    padding: '28px 30px 26px',
    borderRadius: 26,
    backgroundColor: colors.paper,
    color: '#15251b',
    opacity: fadeIn(frame, start, 12),
    translate: `0px ${lift(frame, start, 66, 28)}`,
    scale: interpolate(bounce(frame, 30, start, 14), [0, 1], [0.93, 1], clamp),
    boxShadow: '0 28px 64px rgba(0,0,0,0.34)',
  }}>
    <div style={{display: 'flex', justifyContent: 'space-between', alignItems: 'center', color: '#698171', fontSize: 16, fontWeight: 800, letterSpacing: 1.4, textTransform: 'uppercase'}}>
      <span style={{display: 'flex', alignItems: 'center', gap: 10}}><span style={{width: 32, height: 32, borderRadius: '50%', backgroundColor: colors.violet}} /> @theinternet</span>
      <span>just now</span>
    </div>
    <div style={{marginTop: 38, fontSize: 50, lineHeight: 0.98, fontWeight: 900, letterSpacing: -1.5}}>
      this is <span style={{color: '#e86454'}}>100% true.</span>
    </div>
    <div style={{marginTop: 24, paddingTop: 20, borderTop: '1px solid rgba(12,28,19,0.14)', display: 'flex', justifyContent: 'space-between', color: '#688071', fontSize: 18}}>
      <span>likes <b style={{display: 'block', marginTop: 4, color: '#15251b', fontSize: 28}}>10M</b></span>
      <span>source <b style={{display: 'block', marginTop: 4, color: '#e86454', fontSize: 25}}>trust me bro</b></span>
    </div>
  </div>
);

const LoadingFace = ({frame}) => (
  <div style={{
    position: 'absolute',
    right: 62,
    top: 820,
    width: 240,
    height: 240,
    borderRadius: '50%',
    border: '2px solid rgba(186,246,200,0.18)',
    display: 'flex',
    justifyContent: 'center',
    alignItems: 'center',
    opacity: fadeIn(frame, 8, 12),
    rotate: `${interpolate(frame, [0, 60], [-4, 4], {...clamp, easing: Easing.inOut(Easing.sin)})}deg`,
  }}>
    <div style={{width: 146, height: 146, borderRadius: '50%', backgroundColor: '#dfeee2', color: colors.ink, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 76, fontWeight: 900, boxShadow: 'inset 0 -9px 0 rgba(0,0,0,0.08)'}}>?</div>
    <div style={{position: 'absolute', bottom: -16, right: 8}}><Sticker color={colors.coral} frame={frame} start={24} rotate="7deg">buffering...</Sticker></div>
  </div>
);

const FakePhone = ({frame, start = 0}) => (
  <div style={{
    position: 'absolute',
    left: 185,
    top: 670,
    width: 710,
    height: 1025,
    padding: 26,
    borderRadius: 58,
    border: '2px solid rgba(186,246,200,0.4)',
    backgroundColor: '#06100a',
    opacity: fadeIn(frame, start, 16),
    translate: `0px ${lift(frame, start, 96, 30)}`,
    scale: interpolate(bounce(frame, 30, start, 15), [0, 1], [0.92, 1], clamp),
    boxShadow: '0 45px 90px rgba(0,0,0,0.45)',
  }}>
    <div style={{position: 'relative', width: '100%', height: '100%', overflow: 'hidden', padding: '58px 28px 30px', borderRadius: 36, backgroundColor: '#e9f6eb', color: '#153020'}}>
      <div style={{display: 'flex', justifyContent: 'space-between', color: '#587963', fontSize: 16, letterSpacing: 2, textTransform: 'uppercase', fontWeight: 850}}><span>new echo</span><span style={{color: '#2a8b4d'}}>live</span></div>
      <div style={{marginTop: 48, padding: '26px 24px 23px', borderRadius: 22, backgroundColor: 'rgba(255,255,255,0.85)', boxShadow: '0 14px 28px rgba(17,72,39,0.1)'}}>
        <div style={{color: '#3f7150', fontSize: 14, letterSpacing: 2.3, textTransform: 'uppercase', fontWeight: 850}}>claim / public life</div>
        <div style={{marginTop: 24, fontSize: 37, lineHeight: 1.02, fontWeight: 900}}>is this actually true?</div>
        <div style={{marginTop: 16, color: '#688574', fontSize: 18, lineHeight: 1.25}}>add the source, then let the community inspect the signal.</div>
        <div style={{display: 'flex', gap: 12, marginTop: 26}}><div style={{flex: 1, padding: '15px 8px', borderRadius: 13, border: '1px solid rgba(42,138,77,0.35)', color: '#277843', textAlign: 'center', fontSize: 18, fontWeight: 850}}>support</div><div style={{flex: 1, padding: '15px 8px', borderRadius: 13, border: '1px solid rgba(230,94,82,0.3)', color: '#c65b51', textAlign: 'center', fontSize: 18, fontWeight: 850}}>challenge</div></div>
      </div>
      <div style={{position: 'absolute', left: 30, right: 30, bottom: 38, display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 10}}><div style={{padding: 14, borderTop: '2px solid #56d67d', color: '#4d6e5a', fontSize: 15, textAlign: 'center'}}>claim</div><div style={{padding: 14, borderTop: '2px solid #6de2d8', color: '#4d6e5a', fontSize: 15, textAlign: 'center'}}>evidence</div><div style={{padding: 14, borderTop: '2px solid #a68cff', color: '#4d6e5a', fontSize: 15, textAlign: 'center'}}>community</div></div>
    </div>
    <DisclosurePanel frame={frame} />
    <div style={{position: 'absolute', top: 15, left: '50%', width: 160, height: 20, borderRadius: 99, backgroundColor: '#020604', translate: '-50% 0px'}} />
  </div>
);

const HookScene = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  return (
    <AbsoluteFill style={{...pageStyle, backgroundColor: colors.ink, color: colors.paper, opacity: sceneOpacity(frame, 105)}}>
      <Brand frame={frame} />
      <div style={{position: 'absolute', left: 64, right: 64, top: 220}}>
        <Kicker frame={frame}>pov: your feed has evidence</Kicker>
        <div style={{marginTop: 30}}><BouncyText frame={frame} fps={fps} delay={2} size={83}>you saw the</BouncyText></div>
        <div style={{marginTop: 8}}><BouncyText frame={frame} fps={fps} delay={7} size={98} color={colors.green} paint paintColor="#f0c75e">10m likes.</BouncyText></div>
        <div style={{marginTop: 8}}><BouncyText frame={frame} fps={fps} delay={12} size={77} underline underlineColor={colors.coral}>so it must be true?</BouncyText></div>
      </div>
      <MemePost frame={frame} start={26} />
      <div style={{position: 'absolute', left: 68, top: 1518}}><Sticker color={colors.coral} frame={frame} start={34} rotate="-4deg">source: trust me bro</Sticker></div>
      <KineticBottomLine frame={frame} start={6} accent={colors.teal}>me: checking the receipts.</KineticBottomLine>
    </AbsoluteFill>
  );
};

const BufferScene = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  return (
    <AbsoluteFill style={{...pageStyle, backgroundColor: colors.ink, color: colors.paper, opacity: sceneOpacity(frame, 90)}}>
      <Brand frame={frame} />
      <div style={{position: 'absolute', left: 64, right: 64, top: 270, textAlign: 'center'}}>
        <Kicker frame={frame} start={0} color={colors.coral}>the source has entered the chat</Kicker>
        <div style={{marginTop: 35}}><BouncyText frame={frame} fps={fps} delay={3} size={89} align="center" underline underlineColor={colors.coral}>trust me bro</BouncyText></div>
        <div style={{marginTop: 14, color: colors.muted, fontSize: 29, opacity: fadeIn(frame, 15, 12)}}>a peer-reviewed publication by absolutely nobody</div>
      </div>
      <SourceCard frame={frame} />
      <div style={{position: 'absolute', right: 68, top: 1270}}><Sticker color={colors.teal} frame={frame} start={38} rotate="4deg">plot twist: there is</Sticker></div>
      <KineticBottomLine frame={frame} start={6} accent={colors.green}>there has to be a better way.</KineticBottomLine>
    </AbsoluteFill>
  );
};

const ProductScene = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const tap = bounce(frame, fps, 38, 14);
  return (
    <AbsoluteFill style={{...pageStyle, backgroundColor: colors.ink, color: colors.paper, opacity: sceneOpacity(frame, 108)}}>
      <Brand frame={frame} />
      <div style={{position: 'absolute', left: 64, right: 64, top: 220, textAlign: 'center'}}>
        <Kicker frame={frame} color={colors.lime}>enter echoproof</Kicker>
        <div style={{marginTop: 30}}><BouncyText frame={frame} fps={fps} delay={4} size={82} align="center" paint paintColor={colors.green}>bring receipts.</BouncyText></div>
        <div style={{marginTop: 18, color: colors.muted, fontSize: 28, opacity: fadeIn(frame, 18, 12)}}>not just louder opinions.</div>
      </div>
      <FakePhone frame={frame} start={20} />
      <div style={{position: 'absolute', left: 64, right: 64, top: 528, display: 'flex', gap: 16, zIndex: 8, opacity: fadeIn(frame, 34, 10), translate: `0px ${lift(frame, 34, 30, 18)}`}}>
        <div style={{flex: 1, minWidth: 0, minHeight: 82, padding: '14px 18px', borderRadius: 18, border: '1px solid rgba(86,214,125,0.42)', backgroundColor: 'rgba(15,49,28,0.95)', color: colors.green, display: 'flex', alignItems: 'center', gap: 12, fontSize: 29, lineHeight: 1, fontWeight: 900}}>
          <span style={{flex: '0 0 auto', width: 20, height: 20, borderRadius: '50%', backgroundColor: colors.green, boxShadow: '0 0 0 10px rgba(86,214,125,0.13)', scale: interpolate(tap, [0, 1], [0.7, 1], clamp)}} />
          <span>source added</span>
        </div>
        <div style={{flex: 1, minWidth: 0, minHeight: 82, padding: '14px 18px', borderRadius: 18, border: '1px solid rgba(109,226,216,0.38)', backgroundColor: 'rgba(11,43,39,0.95)', color: colors.teal, display: 'flex', alignItems: 'center', fontSize: 25, lineHeight: 1.06, fontWeight: 850}}>
          let the community<br />inspect it.
        </div>
      </div>
    </AbsoluteFill>
  );
};

const ReceiptsScene = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const cardProgress = bounce(frame, fps, 14, 14);
  return (
    <AbsoluteFill style={{...pageStyle, backgroundColor: colors.ink, color: colors.paper, opacity: sceneOpacity(frame, 102)}}>
      <Brand frame={frame} />
      <div style={{position: 'absolute', left: 64, right: 64, top: 230, textAlign: 'center'}}>
        <Kicker frame={frame} color={colors.teal}>the difference</Kicker>
        <div style={{marginTop: 30}}><BouncyText frame={frame} fps={fps} delay={5} size={83} align="center">likes are loud.</BouncyText></div>
        <div style={{marginTop: 12}}><BouncyText frame={frame} fps={fps} delay={10} size={90} color={colors.green} align="center" paint paintColor="#2b9f70" underline underlineColor={colors.lime}>proof has receipts.</BouncyText></div>
      </div>
      <div style={{position: 'absolute', left: 64, right: 64, top: 930, display: 'flex', gap: 18, alignItems: 'stretch'}}>
        <div style={{flex: 1, minHeight: 360, padding: 28, borderRadius: 24, backgroundColor: '#172a20', border: '1px solid rgba(255,137,119,0.35)', opacity: fadeIn(frame, 20, 12), translate: `0px ${lift(frame, 20, 60, 24)}`}}>
          <div style={{display: 'flex', alignItems: 'center', gap: 8, color: colors.coral, fontSize: 18, letterSpacing: 2, textTransform: 'uppercase', fontWeight: 850}}><AnimatedIcon type="community" frame={frame} start={20} color={colors.coral} size={30} /> likes</div>
          <div style={{marginTop: 40, color: colors.coral, fontSize: 82, fontWeight: 900, letterSpacing: -3}}>10M</div>
          <div style={{marginTop: 24, color: colors.muted, fontSize: 23}}>great volume.<br />zero context.</div>
        </div>
        <div style={{flex: 1, minHeight: 360, padding: 28, borderRadius: 24, backgroundColor: '#12301f', border: '1px solid rgba(86,214,125,0.45)', opacity: fadeIn(frame, 28, 12), translate: `0px ${lift(frame, 28, 60, 24)}`, scale: interpolate(cardProgress, [0, 1], [0.94, 1], clamp)}}>
          <div style={{display: 'flex', alignItems: 'center', gap: 8, color: colors.green, fontSize: 18, letterSpacing: 2, textTransform: 'uppercase', fontWeight: 850}}><AnimatedIcon type="check" frame={frame} start={28} color={colors.green} size={30} /> proof</div>
          <div style={{marginTop: 40, color: colors.green, fontSize: 82, fontWeight: 900, letterSpacing: -3}}>1</div>
          <div style={{marginTop: 24, color: colors.muted, fontSize: 23}}>one source.<br />much better vibes.</div>
        </div>
      </div>
      <div style={{position: 'absolute', left: 64, right: 64, bottom: 224, textAlign: 'center', color: colors.lime, fontSize: 27, fontWeight: 800, opacity: fadeIn(frame, 56, 12)}}>the timeline moves on. the record stays.</div>
    </AbsoluteFill>
  );
};

const VerifiedScene = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const scale = interpolate(bounce(frame, fps, 4, 13), [0, 1], [0.72, 1], clamp);
  return (
    <AbsoluteFill style={{...pageStyle, backgroundColor: colors.ink, color: colors.paper, opacity: sceneOpacity(frame, 102)}}>
      <Brand frame={frame} />
      <div style={{position: 'absolute', left: 64, right: 64, top: 270, textAlign: 'center'}}>
        <Kicker frame={frame} color={colors.lime}>when the signal survives</Kicker>
        <div style={{marginTop: 30}}><BouncyText frame={frame} fps={fps} delay={5} size={85} align="center">it becomes a record.</BouncyText></div>
      </div>
      <div style={{position: 'absolute', left: 105, right: 105, top: 805, padding: '34px 34px 28px', borderTop: `3px solid ${colors.green}`, borderBottom: '1px solid rgba(86,214,125,0.42)', backgroundColor: '#102d1d', opacity: fadeIn(frame, 18, 14), scale, translate: `0px ${lift(frame, 18, 56, 24)}`, boxShadow: '0 30px 70px rgba(0,0,0,0.28)'}}>
        <div style={{display: 'flex', justifyContent: 'space-between', alignItems: 'center', color: colors.muted, fontSize: 16, letterSpacing: 2, textTransform: 'uppercase', fontWeight: 850}}><span style={{display: 'flex', alignItems: 'center', gap: 8}}><AnimatedIcon type="hash" frame={frame} start={18} color={colors.green} size={28} /> echoproof record / 0xecho</span><span style={{display: 'flex', alignItems: 'center', gap: 6, color: colors.green}}><AnimatedIcon type="check" frame={frame} start={26} color={colors.green} size={27} /> verified</span></div>
        <div style={{margin: '82px 0 58px', color: colors.green, fontSize: 36, fontWeight: 850, letterSpacing: 1}}>7d8f / 3a21 / 84c0 / 5f91</div>
        <div style={{paddingTop: 24, borderTop: '1px solid rgba(230,250,236,0.18)', display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 12}}><div><span style={{display: 'block', color: '#779987', fontSize: 14, letterSpacing: 1.8, textTransform: 'uppercase'}}>signal</span><b style={{display: 'block', marginTop: 8, color: colors.paper, fontSize: 22}}>community</b></div><div><span style={{display: 'block', color: '#779987', fontSize: 14, letterSpacing: 1.8, textTransform: 'uppercase'}}>record</span><b style={{display: 'block', marginTop: 8, color: colors.paper, fontSize: 22}}>sha-256</b></div><div><span style={{display: 'block', color: '#779987', fontSize: 14, letterSpacing: 1.8, textTransform: 'uppercase'}}>status</span><b style={{display: 'block', marginTop: 8, color: colors.paper, fontSize: 22}}>permanent</b></div></div>
      </div>
      <div style={{position: 'absolute', left: 64, bottom: 232, color: colors.green, fontSize: 31, fontWeight: 850, opacity: fadeIn(frame, 48, 12)}}>popular fades.</div>
      <div style={{position: 'absolute', right: 64, bottom: 232, color: colors.paper, fontSize: 31, fontWeight: 850, opacity: fadeIn(frame, 54, 12)}}>proof stays.</div>
    </AbsoluteFill>
  );
};

const OutroScene = ({playStoreUrl: destination = playStoreUrl}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const mark = bounce(frame, fps, 6, 15);
  return (
    <AbsoluteFill style={{...pageStyle, backgroundColor: colors.ink, color: colors.paper, alignItems: 'center', justifyContent: 'center', textAlign: 'center', opacity: sceneOpacity(frame, 108)}}>
      <Img src={staticFile('assets/echoproof-logo.png')} style={{...logoStyle, width: 150, height: 150, borderRadius: 36, opacity: fadeIn(frame, 2, 12), scale: interpolate(mark, [0, 1], [0.72, 1], clamp)}} />
      <div style={{marginTop: 40, padding: '0 58px', fontSize: 70, lineHeight: 0.98, letterSpacing: -2.2, fontWeight: 900, opacity: fadeIn(frame, 12, 14), translate: `0px ${lift(frame, 12, 36, 22)}`}}>stop forwarding vibes.<br /><span style={{color: colors.green}}>start echoing with proof.</span></div>
      <div style={{marginTop: 28, color: colors.muted, fontSize: 28, opacity: fadeIn(frame, 28, 12)}}>your future group chat will thank you.</div>
      <a href={destination} style={{display: 'flex', alignItems: 'center', gap: 16, marginTop: 70, padding: '18px 26px', borderRadius: 17, backgroundColor: colors.paper, color: colors.ink, textDecoration: 'none', opacity: fadeIn(frame, 42, 12), scale: interpolate(bounce(frame, fps, 42, 14), [0, 1], [0.84, 1], clamp)}}>
        <span style={{width: 0, height: 0, borderTop: '15px solid transparent', borderBottom: '15px solid transparent', borderLeft: `24px solid ${colors.green}`}} />
        <span style={{textAlign: 'left'}}><small style={{display: 'block', fontSize: 13, fontWeight: 700, letterSpacing: 1}}>get it on</small><b style={{display: 'block', marginTop: 2, fontSize: 28, lineHeight: 1}}>Google Play</b></span>
      </a>
      <div style={{position: 'absolute', bottom: 150, color: colors.muted, fontSize: 15, letterSpacing: 1.2, opacity: fadeIn(frame, 48, 12)}}>play.google.com/store/apps/details?id=com.echoproof.app</div>
    </AbsoluteFill>
  );
};

export const EchoProofMemeReel = ({playStoreUrl: destination = playStoreUrl}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  return (
    <AbsoluteFill style={{backgroundColor: colors.ink}}>
      <Sequence from={0} durationInFrames={90} name="Downloaded transitional hook"><ExternalHookScene /></Sequence>
      <Sequence from={90} durationInFrames={105} name="Meme hook"><HookScene /></Sequence>
      <Sequence from={195} durationInFrames={90} name="Trust me bro joke"><BufferScene /></Sequence>
      <Sequence from={285} durationInFrames={108} name="EchoProof product moment"><ProductScene /></Sequence>
      <Sequence from={393} durationInFrames={102} name="Likes versus proof"><ReceiptsScene /></Sequence>
      <Sequence from={495} durationInFrames={102} name="Permanent record"><VerifiedScene /></Sequence>
      <Sequence from={597} durationInFrames={108} name="Google Play call to action"><OutroScene playStoreUrl={destination} /></Sequence>
      <Sequence from={90} durationInFrames={615} name="EchoProof score"><Audio src={staticFile('audio/echoproof-score.wav')} volume={0.2} /></Sequence>
      <Sequence from={88} durationInFrames={24} name="Hook handoff click"><Audio src={staticFile('audio/click.ogg')} volume={0.38} /></Sequence>
      <Sequence from={285} durationInFrames={30} name="Product beat"><Audio src={staticFile('audio/click.ogg')} volume={0.26} /></Sequence>
      <Sequence from={495} durationInFrames={30} name="Proof beat"><Audio src={staticFile('audio/confirm.ogg')} volume={0.24} /></Sequence>
      <Grain frame={frame} />
    </AbsoluteFill>
  );
};
