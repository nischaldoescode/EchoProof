import React from 'react';
import {Composition, registerRoot} from 'remotion';
import {EchoProofMemeReel} from './EchoProofMemeReel';
import {EchoProofNarrativeReel} from './EchoProofNarrativeReel';
import {EchoProofAppleLaunchFilm} from './EchoProofAppleLaunchFilm';

export const RemotionRoot = () => {
  return (
    <>
      <Composition
        id="EchoProofMemeReel"
        component={EchoProofMemeReel}
        durationInFrames={705}
        fps={30}
        width={1080}
        height={1920}
        defaultProps={{
          playStoreUrl: 'https://play.google.com/store/apps/details?id=com.echoproof.app',
        }}
      />
      <Composition
        id="EchoProofNarrativeReel"
        component={EchoProofNarrativeReel}
        durationInFrames={840}
        fps={30}
        width={1080}
        height={1920}
        defaultProps={{
          playStoreUrl: 'https://play.google.com/store/apps/details?id=com.echoproof.app',
        }}
      />
      <Composition
        id="EchoProofAppleLaunchFilm"
        component={EchoProofAppleLaunchFilm}
        durationInFrames={780}
        fps={30}
        width={1080}
        height={1920}
        defaultProps={{
          playStoreUrl: 'https://play.google.com/store/apps/details?id=com.echoproof.app',
        }}
      />
    </>
  );
};

registerRoot(RemotionRoot);
