import fs from 'node:fs';

const sampleRate = 48000;
const seconds = 20.5;
const channels = 2;
const sampleCount = Math.ceil(sampleRate * seconds);
const samples = new Float32Array(sampleCount * channels);
const tau = Math.PI * 2;

const midiToHz = (midi) => 440 * Math.pow(2, (midi - 69) / 12);
const clamp = (value, minimum, maximum) => Math.max(minimum, Math.min(maximum, value));

// the score uses a changing eight-bar progression, a restrained pulse, and
// short transition accents so the product section feels like one continuous
// story instead of a short loop repeated under every card.
const chords = [
  [40, 43, 47],
  [43, 47, 50],
  [45, 48, 52],
  [38, 41, 45],
  [40, 43, 47],
  [47, 50, 54],
  [45, 48, 52],
  [43, 47, 50],
];

for (let sample = 0; sample < sampleCount; sample += 1) {
  const time = sample / sampleRate;
  const beat = time * 1.8;
  const bar = Math.floor(beat / 4);
  const beatInBar = beat % 4;
  const chord = chords[bar % chords.length];
  const beatPhase = beat % 1;
  const barPhase = beatInBar / 4;
  const envelope = Math.min(1, time / 0.7, (seconds - time) / 1.2);

  let pad = 0;
  chord.forEach((midi, index) => {
    const frequency = midiToHz(midi + (index === 2 ? 12 : 0));
    pad += Math.sin(tau * frequency * time + index * 0.4) * (0.032 - index * 0.004);
  });

  const bassFrequency = midiToHz(chord[0] - 12);
  const bass = Math.sin(tau * bassFrequency * time) * (0.06 + Math.sin(tau * barPhase) * 0.01);
  const pluckFrequency = midiToHz(chord[(bar + 1) % chord.length] + 12);
  const pluckEnvelope = Math.exp(-beatPhase * 7);
  const pluck = Math.sin(tau * pluckFrequency * time) * pluckEnvelope * 0.045;

  const kickEnvelope = Math.exp(-beatPhase * 18);
  const kick = Math.sin(tau * (74 - beatPhase * 35) * time) * kickEnvelope * 0.11;
  const hatEnvelope = Math.exp(-((beatPhase - 0.5) ** 2) * 100);
  const hat = Math.sin(tau * (4000 + Math.sin(time * 97) * 700) * time) * hatEnvelope * 0.012;
  const movement = Math.sin(tau * time * (0.18 + (bar % 3) * 0.03)) * 0.012;
  const transition = Math.exp(-((time - 6.4) ** 2) * 24) * 0.035
    + Math.exp(-((time - 13.1) ** 2) * 28) * 0.04
    + Math.exp(-((time - 17.3) ** 2) * 32) * 0.045;

  const mono = (pad + bass + pluck + kick + hat + movement + transition) * envelope;
  const left = clamp(mono * (0.96 + Math.sin(time * 0.31) * 0.04), -0.85, 0.85);
  const right = clamp(mono * (0.96 + Math.cos(time * 0.27) * 0.04), -0.85, 0.85);
  samples[sample * channels] = left;
  samples[sample * channels + 1] = right;
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
fs.writeFileSync('public/audio/echoproof-score.wav', buffer);
console.log(`generated public/audio/echoproof-score.wav (${seconds}s)`);
