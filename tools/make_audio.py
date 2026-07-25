#!/usr/bin/env python3
"""
Procedural audio generator for Chroma Cascade.

Every sound the game plays is synthesised here from scratch — no samples, no
licences, no binary blobs that nobody can regenerate. Run it to (re)create the
WAV files in ChromaCascade/Resources/Audio.

    python3 tools/make_audio.py

Design notes
------------
* Blast tones climb a C-major pentatonic scale, one step per cascade rung. The
  rising pitch *is* the reward curve — by rung five the player is hearing a
  melody they built themselves.
* The two music loops share a chord progression and bar length, so the game can
  crossfade between "normal" and "fever" without a restart or a beat glitch.
"""

import math
import os
import struct
import wave

SAMPLE_RATE = 44100
OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                       "ChromaCascade", "Resources", "Audio")

# ---------------------------------------------------------------- primitives


def _rng(seed=12345):
    state = seed

    def rand():
        nonlocal state
        state = (1103515245 * state + 12345) % (1 << 31)
        return state / float(1 << 31)

    return rand


def silence(duration):
    return [0.0] * int(duration * SAMPLE_RATE)


def mix(target, source, offset=0.0, gain=1.0):
    """Adds `source` into `target` at `offset` seconds, extending as needed."""
    start = int(offset * SAMPLE_RATE)
    needed = start + len(source)
    if needed > len(target):
        target.extend([0.0] * (needed - len(target)))
    for i, value in enumerate(source):
        target[start + i] += value * gain
    return target


def envelope(n, attack, decay, sustain, release, sustain_level=0.7):
    """Sample-accurate ADSR of total length n."""
    a = max(1, int(attack * SAMPLE_RATE))
    d = max(1, int(decay * SAMPLE_RATE))
    r = max(1, int(release * SAMPLE_RATE))
    s = max(0, n - a - d - r)
    out = []
    for i in range(a):
        out.append(i / a)
    for i in range(d):
        out.append(1.0 + (sustain_level - 1.0) * (i / d))
    out.extend([sustain_level] * s)
    for i in range(r):
        out.append(sustain_level * (1.0 - i / r))
    if len(out) < n:
        out.extend([0.0] * (n - len(out)))
    return out[:n]


def tone(freq, duration, kind="sine", detune=0.0, harmonics=None):
    n = int(duration * SAMPLE_RATE)
    out = [0.0] * n
    harmonics = harmonics or [(1, 1.0)]
    for mult, amp in harmonics:
        f = freq * mult * (1.0 + detune)
        step = 2.0 * math.pi * f / SAMPLE_RATE
        phase = 0.0
        for i in range(n):
            if kind == "sine":
                value = math.sin(phase)
            elif kind == "square":
                value = 1.0 if math.sin(phase) >= 0 else -1.0
            elif kind == "saw":
                cycle = (phase / (2 * math.pi)) % 1.0
                value = 2.0 * cycle - 1.0
            elif kind == "tri":
                cycle = (phase / (2 * math.pi)) % 1.0
                value = 4.0 * abs(cycle - 0.5) - 1.0
            else:
                value = math.sin(phase)
            out[i] += value * amp
            phase += step
    return out


def sweep(f0, f1, duration, kind="sine"):
    n = int(duration * SAMPLE_RATE)
    out = [0.0] * n
    phase = 0.0
    for i in range(n):
        t = i / max(1, n - 1)
        f = f0 * (f1 / f0) ** t
        phase += 2.0 * math.pi * f / SAMPLE_RATE
        if kind == "square":
            out[i] = 1.0 if math.sin(phase) >= 0 else -1.0
        elif kind == "saw":
            cycle = (phase / (2 * math.pi)) % 1.0
            out[i] = 2.0 * cycle - 1.0
        else:
            out[i] = math.sin(phase)
    return out


def noise(duration, seed=1):
    rand = _rng(seed)
    return [rand() * 2.0 - 1.0 for _ in range(int(duration * SAMPLE_RATE))]


def lowpass(samples, cutoff):
    """One-pole low-pass; plenty for taking the fizz off noise."""
    rc = 1.0 / (2 * math.pi * cutoff)
    dt = 1.0 / SAMPLE_RATE
    alpha = dt / (rc + dt)
    out = []
    previous = 0.0
    for sample in samples:
        previous = previous + alpha * (sample - previous)
        out.append(previous)
    return out


def apply_env(samples, env):
    return [s * e for s, e in zip(samples, env)]


def note(freq, duration, kind="sine", attack=0.005, decay=0.06, release=0.12,
         sustain_level=0.6, harmonics=None):
    body = tone(freq, duration, kind=kind, harmonics=harmonics)
    env = envelope(len(body), attack, decay, duration, release, sustain_level)
    return apply_env(body, env)


def normalize(samples, peak=0.86):
    high = max((abs(s) for s in samples), default=0.0)
    if high < 1e-9:
        return samples
    scale = peak / high
    return [s * scale for s in samples]


def soft_clip(samples):
    return [math.tanh(s) for s in samples]


def write_wav(name, samples, peak=0.86):
    if not os.path.isdir(OUT_DIR):
        os.makedirs(OUT_DIR)
    samples = normalize(soft_clip(samples), peak)
    path = os.path.join(OUT_DIR, name + ".wav")
    with wave.open(path, "w") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(SAMPLE_RATE)
        frames = bytearray()
        for sample in samples:
            value = int(max(-1.0, min(1.0, sample)) * 32767)
            frames += struct.pack("<h", value)
        handle.writeframes(bytes(frames))
    return path


# ---------------------------------------------------------------- musical data

def midi(n):
    return 440.0 * (2.0 ** ((n - 69) / 12.0))


# C major pentatonic, two octaves — one step per cascade rung.
PENTATONIC = [60, 62, 64, 67, 69, 72, 74, 76]

# Am – F – C – G, the friendliest loop in existence.
PROGRESSION = [
    (45, [57, 60, 64]),   # Am
    (41, [53, 57, 60]),   # F
    (36, [48, 52, 55]),   # C
    (43, [55, 59, 62]),   # G
]


# ---------------------------------------------------------------- effects

def make_blasts():
    """Eight detonation tones, one per chain rung, rising in pitch and bite."""
    for index, pitch in enumerate(PENTATONIC):
        freq = midi(pitch)
        brightness = index / (len(PENTATONIC) - 1.0)
        duration = 0.42 + 0.06 * brightness

        bell = note(freq, duration, kind="sine",
                    attack=0.002, decay=0.10, release=duration * 0.7,
                    sustain_level=0.34,
                    harmonics=[(1, 1.0), (2, 0.45 + 0.3 * brightness),
                               (3, 0.18 + 0.25 * brightness), (4.2, 0.10)])

        # transient crack so it lands like an impact, not just a note
        crack = lowpass(noise(0.06, seed=17 + index), 2600 + 2200 * brightness)
        crack = apply_env(crack, envelope(len(crack), 0.001, 0.02, 0.0, 0.04, 0.2))

        body = sweep(freq * 2.4, freq, 0.14, kind="sine")
        body = apply_env(body, envelope(len(body), 0.001, 0.04, 0.0, 0.09, 0.3))

        out = list(bell)
        mix(out, crack, 0.0, 0.55)
        mix(out, body, 0.0, 0.42)
        write_wav("blast_%d" % (index + 1), out, peak=0.72 + 0.16 * brightness)


def make_effects():
    # --- UI tap: tiny, dry, out of the way
    tap = note(midi(84), 0.06, kind="square", attack=0.001, decay=0.02,
               release=0.03, sustain_level=0.25)
    write_wav("ui_tap", tap, peak=0.35)

    # --- pickup: short upward blip
    pick = sweep(midi(72), midi(79), 0.09, kind="square")
    pick = apply_env(pick, envelope(len(pick), 0.002, 0.02, 0.0, 0.06, 0.4))
    write_wav("pickup", pick, peak=0.42)

    # --- place: a satisfying, weighty thunk
    thud = sweep(190, 92, 0.13, kind="sine")
    thud = apply_env(thud, envelope(len(thud), 0.001, 0.03, 0.0, 0.09, 0.5))
    click = lowpass(noise(0.035, seed=5), 3800)
    click = apply_env(click, envelope(len(click), 0.001, 0.008, 0.0, 0.024, 0.15))
    out = list(thud)
    mix(out, click, 0.0, 0.5)
    write_wav("place", out, peak=0.6)

    # --- invalid: two flat descending blips
    out = silence(0.22)
    for i, pitch in enumerate([58, 53]):
        blip = note(midi(pitch), 0.09, kind="square", attack=0.002, decay=0.03,
                    release=0.05, sustain_level=0.3)
        mix(out, blip, 0.10 * i, 0.5)
    write_wav("invalid", out, peak=0.4)

    # --- fall: soft filtered noise swish
    swish = lowpass(noise(0.20, seed=9), 900)
    swish = apply_env(swish, envelope(len(swish), 0.02, 0.05, 0.02, 0.11, 0.5))
    write_wav("fall", swish, peak=0.3)

    # --- bomb: boom plus debris
    boom = sweep(150, 38, 0.55, kind="sine")
    boom = apply_env(boom, envelope(len(boom), 0.002, 0.10, 0.10, 0.33, 0.6))
    debris = lowpass(noise(0.5, seed=23), 1500)
    debris = apply_env(debris, envelope(len(debris), 0.002, 0.08, 0.06, 0.35, 0.35))
    out = list(boom)
    mix(out, debris, 0.0, 0.55)
    write_wav("bomb", out, peak=0.9)

    # --- powerup: bright three-note arpeggio
    out = silence(0.42)
    for i, pitch in enumerate([72, 76, 79]):
        blip = note(midi(pitch), 0.18, kind="square", attack=0.002, decay=0.04,
                    release=0.12, sustain_level=0.4,
                    harmonics=[(1, 1.0), (2, 0.3)])
        mix(out, blip, 0.07 * i, 0.45)
    write_wav("powerup", out, peak=0.62)

    # --- stage up: two-note stab, feels like a gear change
    out = silence(0.45)
    for i, pitch in enumerate([64, 71]):
        stab = note(midi(pitch), 0.28, kind="saw", attack=0.004, decay=0.07,
                    release=0.18, sustain_level=0.45)
        mix(out, stab, 0.09 * i, 0.4)
    sub = sweep(120, 200, 0.25, kind="sine")
    sub = apply_env(sub, envelope(len(sub), 0.004, 0.06, 0.05, 0.14, 0.5))
    mix(out, sub, 0.0, 0.5)
    write_wav("stage_up", out, peak=0.68)

    # --- fever start: rising five-note run plus a riser
    out = silence(1.0)
    for i, pitch in enumerate([60, 64, 67, 72, 76]):
        blip = note(midi(pitch), 0.26, kind="square", attack=0.002, decay=0.05,
                    release=0.16, sustain_level=0.45,
                    harmonics=[(1, 1.0), (2, 0.35), (3, 0.12)])
        mix(out, blip, 0.075 * i, 0.42)
    riser = sweep(200, 1400, 0.5, kind="saw")
    riser = apply_env(riser, envelope(len(riser), 0.2, 0.1, 0.1, 0.1, 0.7))
    mix(out, riser, 0.0, 0.22)
    boom = sweep(180, 60, 0.4, kind="sine")
    boom = apply_env(boom, envelope(len(boom), 0.002, 0.08, 0.05, 0.25, 0.5))
    mix(out, boom, 0.36, 0.55)
    write_wav("fever_start", out, peak=0.92)

    # --- fever end: gentle descent, no punishment
    out = silence(0.6)
    for i, pitch in enumerate([72, 67, 64]):
        blip = note(midi(pitch), 0.22, kind="tri", attack=0.004, decay=0.05,
                    release=0.14, sustain_level=0.4)
        mix(out, blip, 0.09 * i, 0.38)
    write_wav("fever_end", out, peak=0.45)

    # --- game over: descending minor figure
    out = silence(1.4)
    for i, pitch in enumerate([69, 65, 62, 57]):
        blip = note(midi(pitch), 0.5, kind="tri", attack=0.006, decay=0.10,
                    release=0.34, sustain_level=0.42,
                    harmonics=[(1, 1.0), (2, 0.2)])
        mix(out, blip, 0.17 * i, 0.42)
    pad = note(midi(45), 1.3, kind="saw", attack=0.05, decay=0.2, release=0.8,
               sustain_level=0.25)
    mix(out, pad, 0.0, 0.2)
    write_wav("game_over", out, peak=0.6)

    # --- high score: bright major fanfare
    out = silence(1.6)
    for i, pitch in enumerate([60, 64, 67, 72, 76, 79]):
        blip = note(midi(pitch), 0.34, kind="square", attack=0.003, decay=0.05,
                    release=0.22, sustain_level=0.45,
                    harmonics=[(1, 1.0), (2, 0.4), (3, 0.15)])
        mix(out, blip, 0.11 * i, 0.36)
    shimmer = note(midi(84), 0.9, kind="sine", attack=0.15, decay=0.2,
                   release=0.5, sustain_level=0.3)
    mix(out, shimmer, 0.6, 0.22)
    write_wav("high_score", out, peak=0.82)


# ---------------------------------------------------------------- music

def make_music(name, bpm, energy, bars):
    """
    A loop over Am–F–C–G (repeating the progression if `bars` exceeds it).

    `energy` (0..1) drives intensity: arpeggio density, filter brightness and
    drum weight.

    The two loops are deliberately chosen so their total length is identical
    (112 BPM × 4 bars == 140 BPM × 5 bars == 8.571 s). The fever switch is then
    a pure volume crossfade between two players that never drift apart, instead
    of a restart that would drop a beat at the most exciting moment of the run.
    """
    beat = 60.0 / bpm
    bar = beat * 4
    total = bar * bars
    out = silence(total)
    rand = _rng(7 if energy < 0.5 else 11)

    for bar_index in range(bars):
        bass_note, chord = PROGRESSION[bar_index % len(PROGRESSION)]
        bar_start = bar_index * bar

        # bass: root on every beat, octave jump on the last
        for b in range(4):
            pitch = bass_note + (12 if (b == 3 and energy > 0.5) else 0)
            length = beat * (0.5 if energy > 0.5 else 0.75)
            voice = note(midi(pitch), length, kind="saw",
                         attack=0.004, decay=0.06, release=length * 0.4,
                         sustain_level=0.5)
            voice = lowpass(voice, 420 + 500 * energy)
            mix(out, voice, bar_start + b * beat, 0.30)

        # pad: the chord held under everything
        for pitch in chord:
            voice = note(midi(pitch), bar * 0.98, kind="tri",
                         attack=0.08, decay=0.2, release=bar * 0.3,
                         sustain_level=0.22)
            mix(out, voice, bar_start, 0.10 + 0.03 * energy)

        # arpeggio: the hook
        steps = 8 if energy < 0.5 else 16
        step_length = bar / steps
        for s in range(steps):
            pitch = chord[s % len(chord)] + (12 if (s // len(chord)) % 2 else 0)
            if energy > 0.5:
                pitch += 12
            voice = note(midi(pitch), step_length * 0.9, kind="square",
                         attack=0.002, decay=0.03,
                         release=step_length * 0.5, sustain_level=0.30)
            gain = 0.10 + 0.09 * energy
            if s % 4 == 0:
                gain *= 1.35
            mix(out, voice, bar_start + s * step_length, gain)

        # drums
        for b in range(4):
            kick = sweep(140, 45, 0.11, kind="sine")
            kick = apply_env(kick, envelope(len(kick), 0.001, 0.03, 0.0, 0.07, 0.4))
            mix(out, kick, bar_start + b * beat, 0.40 + 0.2 * energy)

            hats = 2 if energy < 0.5 else 4
            for h in range(hats):
                hat = lowpass(noise(0.045, seed=int(rand() * 9999) + 1), 9000)
                hat = apply_env(hat, envelope(len(hat), 0.001, 0.008, 0.0, 0.03, 0.12))
                mix(out, hat, bar_start + b * beat + h * (beat / hats),
                    0.07 + 0.05 * energy)

            if energy > 0.5 and b % 2 == 1:
                snare = lowpass(noise(0.13, seed=int(rand() * 9999) + 2), 3200)
                snare = apply_env(snare, envelope(len(snare), 0.001, 0.03, 0.01, 0.08, 0.3))
                mix(out, snare, bar_start + b * beat, 0.20)

    # Trim to an exact loop length and fade the last few milliseconds into the
    # first, so looping playback has no click.
    exact = int(total * SAMPLE_RATE)
    out = out[:exact]
    blend = int(0.008 * SAMPLE_RATE)
    for i in range(blend):
        t = i / blend
        out[i] = out[i] * t + out[exact - blend + i] * (1 - t)
    write_wav(name, out, peak=0.62)


def main():
    make_blasts()
    make_effects()
    make_music("music_main", bpm=112, energy=0.25, bars=4)
    make_music("music_fever", bpm=140, energy=0.95, bars=5)
    files = sorted(os.listdir(OUT_DIR))
    total = sum(os.path.getsize(os.path.join(OUT_DIR, f)) for f in files)
    print("wrote %d files into %s (%.1f MB)" % (len(files), OUT_DIR, total / 1048576.0))
    for f in files:
        print("  %-18s %6.1f KB" % (f, os.path.getsize(os.path.join(OUT_DIR, f)) / 1024.0))


if __name__ == "__main__":
    main()
