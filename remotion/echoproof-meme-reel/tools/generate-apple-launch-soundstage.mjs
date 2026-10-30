import fs from 'node:fs';

const sampleRate = 48000;
const seconds = 26;
const channels = 2;
const sampleCount = sampleRate * seconds;
const samples = new Float32Array(sampleCount * channels);
const tau = Math.PI * 2;
const tempo = 96;
const beatLength = 60 / tempo;

const midiToHz = (midi) => 440 * Math.pow(2, (midi - 69) / 12);
const clamp = (value, minimum, maximum) => Math.max(minimum, Math.min(maximum, value));
const smoothstep = (value) => {
  const t = clamp(value, 0, 1);
  return t * t * (3 - 2 * t);
};

const focusMoments = [3.45, 6.15, 8.62, 11.05, 14.45, 18.62, 23.35];
const chords = [
  [52, 55, 59],
  [50, 53, 57],
  [48, 52, 55],
  [55, 59, 62],
  [52, 55, 59],
  [57, 60, 64],
];

// this soundstage replaces the looped launch bed with a slower, non-repeating
// arc: an airy opening, glass-like focus tones, short camera impacts, and a
// restrained final lift that follows the film's point-of-view transitions.
for (let index = 0; index < sampleCount; index += 1) {
  const time = index / sampleRate;
  const beat = time / beatLength;
  const bar = Math.floor(beat / 4);
  const phase = beat % 1;
  const chord = chords[bar % chords.length];
  const fadeIn = smoothstep(time / 0.9);
  const fadeOut = smoothstep((seconds - time) / 1.4);
  const envelope = fadeIn * fadeOut;

  let pad = 0;
  chord.forEach((midi, chordIndex) => {
    const frequency = midiToHz(midi + (chordIndex === 2 ? 12 : 0));
    const movement = 1 + Math.sin(time * (0.08 + chordIndex * 0.03)) * 0.0015;
    pad += Math.sin(tau * frequency * time * movement) * (0.028 - chordIndex * 0.004);
  });

  const low = Math.sin(tau * midiToHz(chord[0] - 12) * time) * 0.045;
  const subPulse = Math.sin(tau * (47 - phase * 9) * time) * Math.exp(-phase * 5) * 0.032;
  const pluckPhase = (beat * 2 + bar * 0.25) % 1;
  const pluck = Math.sin(tau * midiToHz(chord[(bar + 1) % chord.length] + 19) * time) * Math.exp(-pluckPhase * 13) * 0.034;
  const air = Math.sin(tau * (1900 + Math.sin(time * 4.1) * 120) * time) * 0.0025;

  let focus = 0;
  let rise = 0;
  for (const eventTime of focusMoments) {
    const delta = time - eventTime;
    const hitEnvelope = delta >= 0 ? Math.exp(-delta * 18) : 0;
    focus += Math.sin(tau * (148 - Math.min(Math.max(delta, 0), 0.16) * 250) * time) * hitEnvelope * 0.09;
    const riseProgress = clamp((delta + 0.55) / 0.55, 0, 1);
    const riseEnvelope = delta < 0 && delta > -0.55 ? smoothstep(riseProgress) : 0;
    rise += Math.sin(tau * (260 + riseProgress * 620) * time) * riseEnvelope * 0.010;
  }

  const beatTick = Math.sin(tau * 3200 * time) * Math.exp(-phase * 25) * 0.004;
  const stereo = Math.sin(tau * time * 0.11) * 0.006;
  const mono = (pad + low + subPulse + pluck + air + focus + rise + beatTick + stereo) * envelope;
  samples[index * channels] = mono * (0.98 + Math.sin(time * 0.17) * 0.02);
  samples[index * channels + 1] = mono * (0.98 + Math.cos(time * 0.13) * 0.02);
}

let peak = 0;
for (const sample of samples) peak = Math.max(peak, Math.abs(sample));
const gain = peak > 0 ? 0.9 / peak : 1;
// apply the measured gain after synthesis so the exported pcm reaches a
// consistent listening level instead of relying on the remotion volume prop
// to rescue a quiet source waveform.
for (let index = 0; index < samples.length; index += 1) samples[index] *= gain;
const dataSize = samples.length * 2;
const buffer = Buffer.alloc(44 + dataSize);
buffer.write('RIFF', 0);
buffer.writeUInt32LE(36 + dataSize, 4);
buffer.write('WAVE', 8);
buffer.write('fmt ', 12);
buffer.writeUInt32LE(16, 16);
buffer.writeUInt16LE(1, 20);
buffer.writeUInt16LE(channels, 22);
buffer.writeUInt32LE(sampleRate, 24);
buffer.writeUInt32LE(sampleRate * channels * 2, 28);
buffer.writeUInt16LE(channels * 2, 32);
buffer.writeUInt16LE(16, 34);
buffer.write('data', 36);
buffer.writeUInt32LE(dataSize, 40);

// write the normalized floating-point mix into the pcm payload; leaving this
// step out produces a valid-looking wav header with silent audio data.
for (let index = 0; index < samples.length; index += 1) {
  const pcm = clamp(Math.round(samples[index] * 32767), -32768, 32767);
  buffer.writeInt16LE(pcm, 44 + index * 2);
}

fs.mkdirSync('public/audio', {recursive: true});
fs.writeFileSync('public/audio/echoproof-launch-soundstage.wav', buffer);
console.log(`generated public/audio/echoproof-launch-soundstage.wav (${seconds}s)`);
