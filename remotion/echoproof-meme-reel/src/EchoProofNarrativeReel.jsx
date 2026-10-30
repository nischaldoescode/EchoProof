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
  ink: '#06110b',
  paper: '#f5fbf5',
  muted: '#9bb5a3',
  green: '#56d67d',
  lime: '#c7f6cf',
  teal: '#6de2d8',
  coral: '#ff8977',
  violet: '#a68cff',
  panel: '#12301f',
};

const clamp = {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'};
const hookVideoStartFrame = 0;
// keep the opening footage free of template cards; the previous hook baked
// image placeholders into its pixels, so changing the overlay could not remove them.
const hookVideo = 'hooks/bucket-toss.mp4';

const fade = (frame, start, end) => interpolate(frame, [start, end], [0, 1], clamp);
const fadeOut = (frame, start, end) => interpolate(frame, [start, end], [1, 0], clamp);
// the product answer gets a separate rhythmic bed so the transition from the
// hook feels intentional; it fades at both edges to avoid an audible cut.
const productBedVolume = (frame) => interpolate(frame, [0, 12, 145, 165], [0, 0.22, 0.22, 0], clamp);

const pop = (frame, fps, start, damping = 13) => spring({
  frame: frame - start,
  fps,
  config: {damping, stiffness: 170, mass: 0.7},
});

const lift = (frame, start, distance = 36, duration = 18) => interpolate(
  frame,
  [start, start + duration],
  [`${distance}px`, '0px'],
  {...clamp, easing: Easing.bezier(0.16, 1, 0.3, 1)},
);

const Brand = ({frame, compact = false}) => (
  <div style={{
    position: 'absolute',
    top: 64,
    left: 64,
    display: 'flex',
    alignItems: 'center',
    gap: 14,
    opacity: fade(frame, 0, 16),
    zIndex: 30,
  }}>
    <Img src={staticFile('assets/echoproof-logo.png')} style={{width: compact ? 48 : 58, height: compact ? 48 : 58, borderRadius: compact ? 14 : 16}} />
    <span style={{color: colors.paper, fontSize: compact ? 19 : 21, fontWeight: 850}}>EchoProof</span>
  </div>
);

// typewriter text is driven by the frame clock so it renders consistently in
// studio, on the render server, and at every output frame.
const TypewriterText = ({text, frame, start = 0, charsPerFrame = 1.45, size = 58, color = colors.paper, weight = 850, align = 'left', lineHeight = 1.03, maxWidth = 900}) => {
  const visibleCount = Math.floor(Math.max(0, frame - start) * charsPerFrame);
  const visibleText = text.slice(0, visibleCount);
  const isTyping = frame >= start && visibleCount < text.length;
  return (
    <div style={{
      maxWidth,
      color,
      fontSize: size,
      lineHeight,
      fontWeight: weight,
      letterSpacing: -1.3,
      whiteSpace: 'pre-line',
      textAlign: align,
    }}>
      {visibleText}
      <span style={{opacity: isTyping ? (Math.floor(frame / 8) % 2 ? 1 : 0) : 0.8, color: colors.coral}}>|</span>
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
    opacity: fade(frame, start, start + 12),
    translate: `0px ${lift(frame, start, 22, 18)}`,
  }}>
    {children}
  </div>
);

const PaintMark = ({frame, start, color = colors.green, width = 640, bottom = -8, centered = false}) => (
  <svg viewBox="0 0 100 28" preserveAspectRatio="none" style={{
    position: 'absolute',
    left: centered ? '50%' : 0,
    bottom,
    width,
    height: 30,
    opacity: fade(frame, start, start + 12),
    scale: interpolate(pop(frame, 30, start, 14), [0, 1], [0.1, 1], clamp),
    translate: centered ? '-50% 0px' : '0px 0px',
    transformOrigin: 'left center',
    zIndex: 0,
  }}>
    <path d="M1 12c17-7 29 1 46-3 18-4 31 5 52-2v13c-18 4-31-2-50 2-17 3-31-3-48 2z" fill={color} />
  </svg>
);

// this quiet lower rail uses the open vertical space to reinforce the story
// without competing with the typewriter headline or the hook footage.
const SignalRail = ({frame, start = 0, bottom = 176}) => (
  <div style={{
    position: 'absolute',
    left: 72,
    right: 72,
    bottom,
    opacity: fade(frame, start, start + 14),
    translate: `0px ${lift(frame, start, 20, 16)}`,
  }}>
    <div style={{display: 'flex', alignItems: 'center', justifyContent: 'space-between', color: colors.muted, fontSize: 15, letterSpacing: 2.4, textTransform: 'uppercase', fontWeight: 850}}>
      <span style={{color: colors.green}}>claim</span>
      <span style={{color: colors.teal}}>source</span>
      <span style={{color: colors.violet}}>record</span>
    </div>
    <div style={{position: 'relative', height: 2, marginTop: 13, backgroundColor: 'rgba(245,251,245,0.18)'}}>
      <div style={{position: 'absolute', left: 0, top: -3, width: 8, height: 8, borderRadius: 99, backgroundColor: colors.green, boxShadow: `0 0 18px ${colors.green}`}} />
      <div style={{position: 'absolute', left: '50%', top: -3, width: 8, height: 8, borderRadius: 99, backgroundColor: colors.teal, boxShadow: `0 0 18px ${colors.teal}`}} />
      <div style={{position: 'absolute', right: 0, top: -3, width: 8, height: 8, borderRadius: 99, backgroundColor: colors.violet, boxShadow: `0 0 18px ${colors.violet}`}} />
    </div>
  </div>
);

const Icon = ({type, color = colors.green, size = 42, frame, start = 0}) => {
  const progress = interpolate(pop(frame, 30, start, 15), [0, 1], [0, 1], clamp);
  const stroke = {fill: 'none', stroke: color, strokeWidth: 2.7, strokeLinecap: 'round', strokeLinejoin: 'round'};
  return (
    <svg width={size} height={size} viewBox="0 0 48 48" style={{opacity: fade(frame, start, start + 8), scale: interpolate(progress, [0, 1], [0.7, 1], clamp)}}>
      {type === 'source' && <><path {...stroke} d="M14 6h14l7 7v29H14z" /><path {...stroke} d="M28 6v8h7" /><path {...stroke} d="M20 25h9M20 32h9" strokeDasharray="40" strokeDashoffset={40 * (1 - progress)} /></>}
      {type === 'review' && <><circle {...stroke} cx="24" cy="17" r="6" /><path {...stroke} d="M12 39c1-7 5-10 12-10s11 3 12 10" strokeDasharray="58" strokeDashoffset={58 * (1 - progress)} /><path {...stroke} d="m17 18 4 4 10-11" /></>}
      {type === 'record' && <><path {...stroke} d="M19 6 15 42M33 6l-4 36M8 19h32M6 31h32" strokeDasharray="120" strokeDashoffset={120 * (1 - progress)} /></>}
      {type === 'check' && <><circle {...stroke} cx="24" cy="24" r="17" opacity="0.35" /><path {...stroke} d="m15 24 6 6 12-14" strokeDasharray="40" strokeDashoffset={40 * (1 - progress)} /></>}
    </svg>
  );
};

const StepCard = ({frame, start, icon, title, body, color}) => {
  const {fps} = useVideoConfig();
  const progress = pop(frame, fps, start, 15);
  return (
    <div style={{
      display: 'flex',
      alignItems: 'center',
      gap: 18,
      padding: '22px 24px',
      borderRadius: 22,
      border: `1px solid ${color}66`,
      backgroundColor: 'rgba(14,41,25,0.92)',
      opacity: fade(frame, start, start + 10),
      translate: `0px ${lift(frame, start, 44, 20)}`,
      scale: interpolate(progress, [0, 1], [0.92, 1], clamp),
      boxShadow: `0 20px 45px ${color}16`,
    }}>
      <Icon type={icon} frame={frame} start={start} color={color} size={48} />
      <div>
        <div style={{color: colors.paper, fontSize: 28, fontWeight: 900, letterSpacing: -0.5}}>{title}</div>
        <div style={{marginTop: 5, color: colors.muted, fontSize: 20, lineHeight: 1.2, fontWeight: 650}}>{body}</div>
      </div>
    </div>
  );
};

const NarrativeHookScene = () => {
  const frame = useCurrentFrame();
  const storyStart = 84;
  const storyFrame = Math.max(0, frame - storyStart);
  const storyOpacity = interpolate(frame, [76, 100, 242, 255], [0, 1, 1, 0], clamp);
  const clipOpacity = interpolate(frame, [0, 8, 80, 100], [1, 1, 1, 0], clamp);
  const clipScale = interpolate(frame, [0, 100], [1.08, 1.01], clamp);
  return (
    <AbsoluteFill style={{backgroundColor: colors.ink, color: colors.paper, overflow: 'hidden'}}>
      <Sequence from={0} durationInFrames={100} name="opening hook video">
        <AbsoluteFill style={{overflow: 'hidden', opacity: clipOpacity, backgroundColor: colors.ink}}>
          <OffthreadVideo src={staticFile(hookVideo)} startFrom={hookVideoStartFrame} style={{width: '100%', height: '100%', objectFit: 'cover', opacity: clipOpacity, transform: `scale(${clipScale})`, filter: 'saturate(0.9) contrast(1.06)'}} />
          <AbsoluteFill style={{backgroundImage: 'linear-gradient(180deg, rgba(6,17,11,0.7) 0%, rgba(6,17,11,0.05) 40%, rgba(6,17,11,0.9) 100%)'}} />
          <div style={{position: 'absolute', top: 110, left: 70, right: 70, color: colors.paper, fontSize: 22, letterSpacing: 3.2, fontWeight: 850, textTransform: 'uppercase', opacity: fade(frame, 5, 18)}}>pov: everyone passed the claim along</div>
          <div style={{position: 'absolute', left: 68, right: 68, top: 548, textAlign: 'center', opacity: fade(frame, 16, 30)}}>
            <div style={{display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 34}}>
              <div style={{color: colors.paper, fontSize: 78, lineHeight: 1.06, fontWeight: 950, letterSpacing: -2.2}}>would you still</div>
              <div style={{position: 'relative', display: 'inline-block', padding: '0 22px 56px', color: colors.green, fontSize: 92, lineHeight: 1.02, fontWeight: 950, letterSpacing: -2.8}}>
                call that proof?
                <PaintMark frame={frame} start={24} color={colors.coral} width={620} bottom={10} centered />
              </div>
            </div>
            <div style={{display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 18, marginTop: 20, color: colors.muted, fontSize: 16, letterSpacing: 2.4, fontWeight: 800, textTransform: 'uppercase', opacity: fade(frame, 28, 40)}}>
              <span>claim</span>
              <span style={{width: 44, height: 1, backgroundColor: `${colors.muted}66`}} />
              <span style={{color: colors.coral}}>source?</span>
            </div>
          </div>
        </AbsoluteFill>
      </Sequence>

      <div style={{opacity: storyOpacity}}>
        <Brand frame={storyFrame} />
        <div style={{position: 'absolute', left: 72, right: 72, top: 246}}>
          <Kicker frame={storyFrame}>a thought experiment for your feed</Kicker>
          <div style={{position: 'relative', marginTop: 30}}>
            <TypewriterText frame={storyFrame} start={4} charsPerFrame={3.5} size={63} text={'if a claim could outrun the news,\ncross every group chat,\nand collect a million likes'} />
            <PaintMark frame={storyFrame} start={44} color="#b79846" width={790} />
          </div>
          <div style={{marginTop: 54, color: colors.coral, fontSize: 31, fontWeight: 850, opacity: fade(storyFrame, 52, 64), translate: `0px ${lift(storyFrame, 52, 26, 16)}`}}>before anyone asked for a source...</div>
        </div>
        <SignalRail frame={storyFrame} start={64} bottom={174} />
        <div style={{position: 'absolute', left: 70, right: 70, bottom: 248, zIndex: 20, opacity: fade(storyFrame, 94, 106), translate: `0px ${lift(storyFrame, 94, 34, 16)}`}}>
          <div style={{padding: '17px 22px', borderRadius: 18, border: `1px solid ${colors.teal}66`, backgroundColor: 'rgba(6,17,11,0.9)', color: colors.teal, fontSize: 34, lineHeight: 1, fontWeight: 900, textAlign: 'center'}}>that is exactly where the receipt matters.</div>
        </div>
      </div>
    </AbsoluteFill>
  );
};

const ProductAnswerScene = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const cardScale = interpolate(pop(frame, fps, 26, 15), [0, 1], [0.9, 1], clamp);
  return (
    <AbsoluteFill style={{backgroundColor: colors.ink, color: colors.paper}}>
      <Brand frame={frame} compact />
      <div style={{position: 'absolute', left: 72, right: 72, top: 245, textAlign: 'center'}}>
        <Kicker frame={frame} color={colors.lime}>the answer is not louder</Kicker>
        <div style={{marginTop: 28, display: 'flex', justifyContent: 'center'}}>
          <TypewriterText frame={frame} start={12} charsPerFrame={1.7} size={67} align="center" text={'EchoProof makes the\nreceipts part of the post.'} maxWidth={900} />
        </div>
      </div>
      <div style={{position: 'absolute', left: 72, right: 72, top: 730, padding: '30px 30px 28px', borderRadius: 28, backgroundColor: colors.paper, color: colors.ink, scale: cardScale, opacity: fade(frame, 25, 38), translate: `0px ${lift(frame, 25, 54, 22)}`, boxShadow: '0 32px 75px rgba(0,0,0,0.34)'}}>
        <div style={{display: 'flex', justifyContent: 'space-between', alignItems: 'center', color: '#5f7c68', fontSize: 16, letterSpacing: 2.2, textTransform: 'uppercase', fontWeight: 850}}><span>new echo</span><span style={{color: '#27864a'}}>open for review</span></div>
        <div style={{marginTop: 28, fontSize: 48, lineHeight: 1, fontWeight: 950, letterSpacing: -1.4}}>is this actually true?</div>
        <div style={{marginTop: 18, color: '#607d69', fontSize: 23, lineHeight: 1.22}}>add the link that lets everyone inspect the claim.</div>
        <div style={{display: 'flex', alignItems: 'center', gap: 12, marginTop: 28, padding: '16px 18px', borderRadius: 15, border: '1px solid rgba(39,134,74,0.3)', color: '#287c47', fontSize: 22, fontWeight: 850}}><Icon type="source" frame={frame} start={32} color="#2f9b58" size={29} /> source attached <span style={{marginLeft: 'auto', color: '#6c8c76'}}>✓</span></div>
      </div>
      <div style={{position: 'absolute', left: 72, right: 72, bottom: 170, color: colors.green, fontSize: 31, fontWeight: 850, textAlign: 'center', opacity: fade(frame, 95, 108), translate: `0px ${lift(frame, 95, 28, 16)}`}}>not a screenshot. a trail.</div>
    </AbsoluteFill>
  );
};

const ThreeStepScene = () => {
  const frame = useCurrentFrame();
  return (
    <AbsoluteFill style={{backgroundColor: colors.ink, color: colors.paper}}>
      <Brand frame={frame} compact />
      <div style={{position: 'absolute', left: 72, right: 72, top: 235}}>
        <Kicker frame={frame} color={colors.teal}>simple on purpose</Kicker>
        <div style={{marginTop: 28}}><TypewriterText frame={frame} start={10} charsPerFrame={1.8} size={64} text={'one post.\nthree signals.'} /></div>
      </div>
      <div style={{position: 'absolute', left: 72, right: 72, top: 760, display: 'grid', gap: 18}}>
        <StepCard frame={frame} start={34} icon="source" color={colors.green} title="attach the source" body="give the claim something checkable." />
        <StepCard frame={frame} start={62} icon="review" color={colors.teal} title="let people review" body="support or challenge it with context." />
        <StepCard frame={frame} start={90} icon="record" color={colors.violet} title="keep the record" body="when the window closes, preserve the result." />
      </div>
      <SignalRail frame={frame} start={118} bottom={250} />
      <div style={{position: 'absolute', left: 72, right: 72, bottom: 174, color: colors.muted, fontSize: 24, fontWeight: 750, textAlign: 'center', opacity: fade(frame, 122, 136)}}>the interface stays light. the trail stays clear.</div>
    </AbsoluteFill>
  );
};

const ProofScene = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const scale = interpolate(pop(frame, fps, 24, 14), [0, 1], [0.86, 1], clamp);
  return (
    <AbsoluteFill style={{backgroundColor: colors.ink, color: colors.paper}}>
      <Brand frame={frame} compact />
      <div style={{position: 'absolute', left: 72, right: 72, top: 250, textAlign: 'center'}}>
        <Kicker frame={frame} color={colors.lime}>when the window closes</Kicker>
        <div style={{marginTop: 28, display: 'flex', justifyContent: 'center'}}><TypewriterText frame={frame} start={10} charsPerFrame={1.55} size={67} align="center" text={'the noise moves on.\nthe record stays.'} /></div>
      </div>
      <div style={{position: 'absolute', left: 82, right: 82, top: 760, padding: '30px 28px 26px', borderTop: `3px solid ${colors.green}`, borderBottom: `1px solid ${colors.green}66`, backgroundColor: colors.panel, scale, opacity: fade(frame, 24, 38), translate: `0px ${lift(frame, 24, 50, 22)}`, boxShadow: '0 32px 70px rgba(0,0,0,0.3)'}}>
        <div style={{display: 'flex', alignItems: 'center', justifyContent: 'space-between', color: colors.muted, fontSize: 16, letterSpacing: 2, textTransform: 'uppercase', fontWeight: 850}}><span style={{display: 'flex', alignItems: 'center', gap: 8}}><Icon type="record" frame={frame} start={28} color={colors.green} size={30} /> echo record</span><span style={{display: 'flex', alignItems: 'center', gap: 7, color: colors.green}}><Icon type="check" frame={frame} start={38} color={colors.green} size={28} /> verified</span></div>
        <div style={{margin: '70px 0 48px', color: colors.green, fontSize: 38, letterSpacing: 1.5, fontWeight: 900, textAlign: 'center'}}>7d8f / 3a21 / 84c0 / 5f91</div>
        <div style={{display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 12, paddingTop: 22, borderTop: '1px solid rgba(230,250,236,0.18)'}}><div><span style={{display: 'block', color: '#779987', fontSize: 14, letterSpacing: 1.5, textTransform: 'uppercase'}}>source</span><b style={{display: 'block', marginTop: 8, color: colors.paper, fontSize: 22}}>attached</b></div><div><span style={{display: 'block', color: '#779987', fontSize: 14, letterSpacing: 1.5, textTransform: 'uppercase'}}>review</span><b style={{display: 'block', marginTop: 8, color: colors.paper, fontSize: 22}}>community</b></div><div><span style={{display: 'block', color: '#779987', fontSize: 14, letterSpacing: 1.5, textTransform: 'uppercase'}}>record</span><b style={{display: 'block', marginTop: 8, color: colors.paper, fontSize: 22}}>public</b></div></div>
      </div>
      <div style={{position: 'absolute', left: 72, right: 72, bottom: 170, color: colors.green, fontSize: 32, fontWeight: 900, textAlign: 'center', opacity: fade(frame, 94, 108)}}>proof you can come back to.</div>
    </AbsoluteFill>
  );
};

const NarrativeOutroScene = ({playStoreUrl}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const mark = pop(frame, fps, 8, 15);
  return (
    <AbsoluteFill style={{backgroundColor: colors.ink, color: colors.paper, alignItems: 'center', justifyContent: 'center', textAlign: 'center'}}>
      <Img src={staticFile('assets/echoproof-logo.png')} style={{width: 144, height: 144, borderRadius: 34, opacity: fade(frame, 4, 16), scale: interpolate(mark, [0, 1], [0.72, 1], clamp)}} />
      <div style={{marginTop: 38, padding: '0 62px', fontSize: 68, lineHeight: 0.98, letterSpacing: -2.3, fontWeight: 950, opacity: fade(frame, 16, 28), translate: `0px ${lift(frame, 16, 34, 20)}`}}>stop forwarding vibes.<br /><span style={{color: colors.green}}>start echoing with proof.</span></div>
      <div style={{marginTop: 26, color: colors.muted, fontSize: 27, opacity: fade(frame, 32, 44)}}>give the claim somewhere to land.</div>
      <a href={playStoreUrl} style={{display: 'flex', alignItems: 'center', gap: 15, marginTop: 58, padding: '18px 26px', borderRadius: 17, backgroundColor: colors.paper, color: colors.ink, textDecoration: 'none', opacity: fade(frame, 45, 58), scale: interpolate(pop(frame, fps, 45, 14), [0, 1], [0.84, 1], clamp)}}>
        <span style={{width: 0, height: 0, borderTop: '15px solid transparent', borderBottom: '15px solid transparent', borderLeft: `24px solid ${colors.green}`}} />
        <span style={{textAlign: 'left'}}><small style={{display: 'block', fontSize: 13, fontWeight: 700, letterSpacing: 1}}>get it on</small><b style={{display: 'block', marginTop: 2, fontSize: 28, lineHeight: 1}}>Google Play</b></span>
      </a>
    </AbsoluteFill>
  );
};

export const EchoProofNarrativeReel = ({playStoreUrl = 'https://play.google.com/store/apps/details?id=com.echoproof.app'}) => {
  const frame = useCurrentFrame();
  return (
    <AbsoluteFill style={{backgroundColor: colors.ink}}>
      <Sequence from={0} durationInFrames={255} name="hook-first narrative opening"><NarrativeHookScene /></Sequence>
      <Sequence from={255} durationInFrames={165} name="product answer"><ProductAnswerScene /></Sequence>
      <Sequence from={420} durationInFrames={165} name="three signal steps"><ThreeStepScene /></Sequence>
      <Sequence from={585} durationInFrames={150} name="proof record"><ProofScene /></Sequence>
      <Sequence from={735} durationInFrames={105} name="outro"><NarrativeOutroScene playStoreUrl={playStoreUrl} /></Sequence>
      <Sequence from={255} durationInFrames={165} name="product answer music"><Audio src={staticFile('audio/bed.mp3')} volume={productBedVolume} /></Sequence>
      <Sequence from={420} durationInFrames={390} name="narrative score"><Audio src={staticFile('audio/echoproof-score.wav')} volume={0.2} /></Sequence>
      <Sequence from={252} durationInFrames={24} name="narrative handoff click"><Audio src={staticFile('audio/click.ogg')} volume={0.38} /></Sequence>
      <Sequence from={585} durationInFrames={24} name="record confirm"><Audio src={staticFile('audio/confirm.ogg')} volume={0.24} /></Sequence>
      <div style={{position: 'absolute', inset: 0, pointerEvents: 'none', opacity: 0.06, backgroundImage: 'radial-gradient(rgba(255,255,255,0.8) 0.7px, transparent 0.8px)', backgroundSize: '5px 5px', mixBlendMode: 'soft-light', transform: `translateX(${Math.sin(frame / 17) * 2}px)`}} />
    </AbsoluteFill>
  );
};
