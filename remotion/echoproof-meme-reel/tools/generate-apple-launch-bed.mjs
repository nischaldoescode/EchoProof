import fs from 'node:fs';

const sampleRate = 48000;
const seconds = 26;
const channels = 2;
const sampleCount = sampleRate * seconds;
const samples = new Float32Array(sampleCount * channels);
const tau = Math.PI * 2;
const tempo = 112;
const beatLength = 60 / tempo;

const midiToHz = (midi) => 440 * Math.pow(2, (midi - 69) / 12);
const clamp = (value, minimum, maximum) => Math.max(minimum, Math.min(maximum, value));
const smoothstep = (value) => {
  const t = clamp(value, 0, 1);
  return t * t * (3 - 2 * t);
};

// this bed is written for the film's camera beats: a restrained pulse carries
// the feed, while short tonal risers and impacts mark each zoom into the ui.
const chords = [
  [45, 48, 52],
  [43, 47, 50],
  [40, 43, 47],
  [47, 50, 54],
  [45, 48, 52],
  [50, 54, 57],
  [43, 47, 50],
  [40, 43, 47],
];

const cameraBeats = [0.45, 3.28, 6.87, 10.63, 14.87, 18.07, 21.08];

for (let index = 0; index < sampleCount; index += 1) {
  const time = index / sampleRate;
  const beat = time / beatLength;
  const bar = Math.floor(beat / 4);
  const beatInBar = beat % 4;
  const phase = beat % 1;
  const chord = chords[bar % chords.length];
  const fadeIn = smoothstep(time / 0.8);
  const fadeOut = smoothstep((seconds - time) / 1.8);
  const envelope = fadeIn * fadeOut;

  let pad = 0;
  chord.forEach((midi, chordIndex) => {
    const frequency = midiToHz(midi + (chordIndex === 2 ? 12 : 0));
    const detune = Math.sin(tau * time * (0.07 + chordIndex * 0.021)) * 0.6;
    pad += Math.sin(tau * (frequency + detune) * time) * (0.032 - chordIndex * 0.006);
  });

  const bassFrequency = midiToHz(chord[0] - 12);
  const bassEnvelope = 0.5 + Math.exp(-phase * 7) * 0.5;
  const bass = Math.sin(tau * bassFrequency * time) * 0.07 * bassEnvelope;

  const pulseEnvelope = Math.exp(-phase * 15);
  const pulse = Math.sin(tau * (62 - phase * 22) * time) * pulseEnvelope * 0.11;

  const hatEnvelope = Math.exp(-((phase - 0.5) ** 2) * 150);
  const hat = Math.sin(tau * (4700 + Math.sin(time * 81) * 530) * time) * hatEnvelope * 0.008;

  const pluckPhase = (beat * 2) % 1;
  const pluckEnvelope = Math.exp(-pluckPhase * 9);
  const pluckFrequency = midiToHz(chord[(bar + 1) % chord.length] + 12);
  const pluck = Math.sin(tau * pluckFrequency * time) * pluckEnvelope * 0.045;

  let impact = 0;
  let riser = 0;
  for (const eventTime of cameraBeats) {
    const delta = time - eventTime;
    const impactEnvelope = Math.exp(-Math.max(0, delta) * 16) * (delta >= 0 ? 1 : 0);
    impact += Math.sin(tau * (84 - Math.min(Math.max(delta, 0), 0.24) * 210) * time) * impactEnvelope * 0.12;
    const riseProgress = clamp((delta + 0.42) / 0.42, 0, 1);
    const riseEnvelope = delta < 0 && delta > -0.42 ? smoothstep(riseProgress) : 0;
    riser += Math.sin(tau * (170 + riseProgress * 780) * time) * riseEnvelope * 0.014;
  }

  const stereoMotion = Math.sin(tau * time * 0.18) * 0.008;
  const mono = (pad + bass + pulse + hat + pluck + impact + riser + stereoMotion) * envelope;
  samples[index * channels] = mono * (0.97 + Math.sin(time * 0.23) * 0.03);
  samples[index * channels + 1] = mono * (0.97 + Math.cos(time * 0.19) * 0.03);
}

let peak = 0;
for (const sample of samples) peak = Math.max(peak, Math.abs(sample));
const gain = peak > 0 ? 0.72 / peak : 1;
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

for (let index = 0; index < samples.length; index += 1) {
  buffer.writeInt16LE(clamp(samples[index] * gain, -1, 1) * 32767, 44 + index * 2);
}

fs.mkdirSync('public/audio', {recursive: true});
fs.writeFileSync('public/audio/echoproof-launch-bed.wav', buffer);
console.log(`generated public/audio/echoproof-launch-bed.wav (${seconds}s)`);
