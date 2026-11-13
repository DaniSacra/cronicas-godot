#!/usr/bin/env python3
"""Offline renderer for the PROVISIONAL audio of the Godot slice (decision D3, path A).

Port of the WebAudio synth of the old JS game (/home/dani/games/dungeon-rpg/src/audio.js, scores in
dungeon-rpg/docs/som/) to plain Python, standard library only, so it runs anywhere. Melodies, harmonies
and timbres were written with an AI assistant: every file it makes must be declared on Steam
(see assets/audio/ORIGEM.md and docs/conteudo-ia.md).

Usage (from the project root):
    python3 tools/audio/render.py               # render everything into assets/audio/
    python3 tools/audio/render.py --only cursor,valmor_noite
    python3 tools/audio/render.py --list
Needs ffmpeg with libvorbis for the .ogg files. Output is deterministic (fixed seeds).

Story rules baked in: no theme or motif for the great enemy; the Sineiro sounds of bell, bronze and stone
only (no choir, no organ); the soft choir belongs to the heroes (Holy Light).
"""
import argparse
import math
import os
import random
import re
import subprocess
import sys
import tempfile
import wave
from array import array

SR = 44100
TAU = 2.0 * math.pi
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


# ---------------------------------------------------------------- buffers

def zeros(sec):
    return [0.0] * int(round(sec * SR))


def mix(dst, src, at=0.0, gain=1.0):
    """Add src into dst starting at `at` seconds (clipped to dst)."""
    o = int(round(at * SR))
    n = min(len(src), len(dst) - o)
    if n <= 0:
        return dst
    dst[o:o + n] = [a + b * gain for a, b in zip(dst[o:o + n], src[:n])]
    return dst


def scale(x, g):
    return [v * g for v in x]


def peak(x):
    return max((abs(v) for v in x), default=0.0)


def db(v):
    return 20.0 * math.log10(v) if v > 0 else -120.0


def fold(x, n):
    """Seamless loop for deterministic events: add whatever rings past the loop end back onto its start."""
    out = x[:n]
    for i in range(n, len(x)):
        out[(i - n) % n] += x[i]
    return out


def xfade_loop(x, n, fade):
    """Seamless loop for noise beds: x must be at least n + fade long; equal-power crossfade of the tail."""
    out = x[:n]
    f = int(fade * SR)
    for i in range(f):
        k = i / f
        out[i] = x[i] * math.sqrt(k) + x[n + i] * math.sqrt(1.0 - k)
    return out


def fade_edges(x, fin=0.0, fout=0.0):
    a, b = int(fin * SR), int(fout * SR)
    for i in range(min(a, len(x))):
        x[i] *= i / a
    for i in range(min(b, len(x))):
        x[len(x) - 1 - i] *= i / b
    return x


# ---------------------------------------------------------------- oscillators

TN = 4096
DUTY = {'p50': 0.5, 'p25': 0.25, 'p12': 0.125}
_tables = {}


def table(kind, nh):
    """Band-limited single-cycle table, peak normalised to 1 (as WebAudio PeriodicWave does)."""
    key = (kind, nh)
    if key in _tables:
        return _tables[key]
    if kind == 'sine':
        t = [math.sin(TAU * i / TN) for i in range(TN)]
    else:
        terms = []
        for k in range(1, nh + 1):
            if kind == 'tri':
                if k % 2:
                    terms.append((k, 0.0, (-1) ** ((k - 1) // 2) / (k * k)))
            elif kind == 'saw':
                terms.append((k, 0.0, (-1) ** (k + 1) / k))
            elif kind == 'sq':
                if k % 2:
                    terms.append((k, 0.0, 1.0 / k))
            else:  # pulse: cosine series, same as audio.js setup()
                terms.append((k, 2.0 / (k * math.pi) * math.sin(k * math.pi * DUTY[kind]), 0.0))
        t = []
        for i in range(TN):
            x = TAU * i / TN
            t.append(sum(a * math.cos(k * x) + b * math.sin(k * x) for k, a, b in terms))
    m = max(abs(v) for v in t) or 1.0
    t = [v / m for v in t]
    t.append(t[0])
    _tables[key] = t
    return t


def osc(kind, f0, dur, f1=None, vib=0.0, t0=0.0, phase=0.0):
    """dur seconds of a band-limited oscillator. f1: exponential glide (like exponentialRampToValueAtTime).
    vib: vibrato depth in cents at 5.5 Hz on the shared clock t0 (like the LFO of audio.js)."""
    n = int(dur * SR)
    if n <= 0:
        return []
    fmax = max(f0, f1 or f0)
    nh = 1 if kind == 'sine' else max(1, min(31, int(17000 / fmax)))
    tab = table(kind, nh)
    out = [0.0] * n
    ph = (phase % 1.0) * TN
    inc = f0 * TN / SR
    mul = (f1 / f0) ** (1.0 / n) if f1 else 1.0
    if vib:
        w = TAU * 5.5 / SR
        base = TAU * 5.5 * t0
        c = vib / 1200.0
        for i in range(n):
            ip = int(ph)
            a = tab[ip]
            out[i] = a + (tab[ip + 1] - a) * (ph - ip)
            ph += inc * 2.0 ** (c * math.sin(base + w * i))
            inc *= mul
            while ph >= TN:
                ph -= TN
    else:
        for i in range(n):
            ip = int(ph)
            a = tab[ip]
            out[i] = a + (tab[ip + 1] - a) * (ph - ip)
            ph += inc
            inc *= mul
            if ph >= TN:
                ph -= TN
    return out


def white(dur, rng):
    u = rng.uniform
    return [u(-1.0, 1.0) for _ in range(int(dur * SR))]


def brown(dur, rng, leak=0.995):
    out, y, u = [], 0.0, rng.uniform
    for _ in range(int(dur * SR)):
        y = y * leak + u(-1.0, 1.0) * 0.1
        out.append(y)
    m = peak(out) or 1.0
    return [v / m for v in out]


# ---------------------------------------------------------------- envelopes

def env_exp(x, vol=1.0, attack=0.005, floor=0.0001):
    """audio.js tone()/noise(): linear rise to vol, then exponential fall to 0.0001 at the end."""
    n = len(x)
    a = max(1, min(n - 1, int(attack * SR)))
    rest = max(1, n - a)
    k = (floor / vol) ** (1.0 / rest) if vol > 0 else 0.0
    for i in range(a):
        x[i] *= vol * i / a
    g = vol
    for i in range(a, n):
        x[i] *= g
        g *= k
    return x


def env_decay(x, tau, attack=0.003, vol=1.0):
    """Exponential decay with time constant tau after a short linear attack."""
    a = max(1, int(attack * SR))
    k = math.exp(-1.0 / (tau * SR))
    g = vol
    for i in range(len(x)):
        if i < a:
            x[i] *= vol * i / a
        else:
            x[i] *= g
            g *= k
    return x


def env_curve(x, points):
    """Piecewise-linear gain from [(t, g), ...]."""
    pts = [(int(t * SR), g) for t, g in points]
    j = 0
    for i in range(len(x)):
        while j < len(pts) - 2 and i >= pts[j + 1][0]:
            j += 1
        (ta, ga), (tb, gb) = pts[j], pts[j + 1]
        if i <= ta:
            g = ga
        elif i >= tb:
            g = gb
        else:
            g = ga + (gb - ga) * (i - ta) / (tb - ta)
        x[i] *= g
    return x


def env_pow(x, rise, p=2.0, release=0.02):
    """Crescendo: gain (t/rise)^p, then a short release at the very end (the rule for specials)."""
    n, r = len(x), int(rise * SR)
    rel = int(release * SR)
    for i in range(n):
        g = (min(i, r) / r) ** p
        if i > n - rel:
            g *= (n - i) / rel
        x[i] *= g
    return x


# ---------------------------------------------------------------- filters

def _coefs(kind, f, q):
    f = min(max(f, 10.0), SR * 0.45)
    w = TAU * f / SR
    c, s = math.cos(w), math.sin(w)
    al = s / (2.0 * q)
    if kind == 'lp':
        b0, b1, b2 = (1 - c) / 2, 1 - c, (1 - c) / 2
    elif kind == 'hp':
        b0, b1, b2 = (1 + c) / 2, -(1 + c), (1 + c) / 2
    else:  # 'bp', 0 dB peak (like WebAudio bandpass)
        b0, b1, b2 = al, 0.0, -al
    a0 = 1 + al
    return b0 / a0, b1 / a0, b2 / a0, -2 * c / a0, (1 - al) / a0


def filt(x, kind, f, q=0.707, f1=None, block=32):
    """Biquad (lp, hp, bp). With f1 the cutoff glides exponentially from f to f1 across the buffer."""
    n = len(x)
    out = [0.0] * n
    x1 = x2 = y1 = y2 = 0.0
    b0, b1, b2, a1, a2 = _coefs(kind, f, q)
    ratio = (f1 / f) if f1 else 1.0
    for i in range(n):
        if f1 and i % block == 0:
            b0, b1, b2, a1, a2 = _coefs(kind, f * ratio ** (i / n), q)
        v = x[i]
        y = b0 * v + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1, y2, y1 = x1, v, y1, y
        out[i] = y
    return out


def reverb(x, size=0.84, damp=0.3, wet=0.35, tail=2.0, room=1.0, spread=0):
    """Small Freeverb (4 combs, 2 allpasses). room scales the delay lengths (cave > 1)."""
    n = len(x) + int(tail * SR)
    src = x + [0.0] * (n - len(x))
    acc = [0.0] * n
    for d in (1116, 1277, 1422, 1557):
        L = int((d + spread) * room)
        buf = [0.0] * L
        idx, store = 0, 0.0
        for i in range(n):
            y = buf[idx]
            store = y * (1 - damp) + store * damp
            buf[idx] = src[i] * 0.015 + store * size
            idx += 1
            if idx == L:
                idx = 0
            acc[i] += y
    for d in (556, 441):
        L = int((d + spread) * room)
        buf = [0.0] * L
        idx = 0
        for i in range(n):
            b = buf[idx]
            v = acc[i]
            acc[i] = b - v
            buf[idx] = v + b * 0.5
            idx += 1
            if idx == L:
                idx = 0
    return [s + a * 3.0 * wet for s, a in zip(src, acc)]


def limit(chans, crest_db, block=64, look=4, release=0.08):
    """Gentle peak limiter for the music: holds peaks to crest_db above the RMS, so tracks with spiky
    pulse-wave peaks (the boss) are not quieter than the waltz at the same -18 dBFS peak."""
    n = len(chans[0])
    rms = math.sqrt(sum(v * v for c in chans for v in c) / (n * len(chans)))
    ceil = rms * 10 ** (crest_db / 20.0)
    nb = (n + block - 1) // block
    need = []
    for b in range(nb):
        m = max(abs(c[i]) for c in chans for i in range(b * block, min(n, (b + 1) * block)))
        need.append(min(1.0, ceil / m) if m > 0 else 1.0)
    k = math.exp(-block / (release * SR))
    g = 1.0
    for _ in range(2):  # the second pass starts from the state at the loop end, so the seam stays seamless
        gains = []
        for b in range(nb):
            target = min(need[(b + j) % nb] for j in range(look + 1))
            g = target if target < g else target + (g - target) * k
            gains.append(g)
    gains.append(gains[0])
    out = []
    for c in chans:
        y = [0.0] * n
        for i in range(n):
            b, f = divmod(i, block)
            y[i] = c[i] * (gains[b] + (gains[b + 1] - gains[b]) * f / block)
        out.append(y)
    return out


def stereo_reverb(x, **kw):
    return reverb(x, spread=0, **kw), reverb(x, spread=23, **kw)


# ---------------------------------------------------------------- instruments

def tone(dst, f, dur, kind='sq', vol=0.06, slide=None, delay=0.0):
    """audio.js Sfx tone(): 5 ms linear attack, exponential fall over dur."""
    s = env_exp(osc(kind, f, dur, slide), vol)
    mix(dst, s, delay)


def noise(dst, dur, vol, delay, freq, q, rng, kind='bp'):
    """audio.js Sfx noise(): filtered white noise, exponential fall."""
    s = filt(white(dur, rng), kind, freq, q)
    s = env_exp(s, vol, attack=0.001)
    mix(dst, s, delay)


# Partials of an old bronze bell: (ratio to the prime, amplitude, decay in seconds per second of length).
# Hum an octave below, minor-third tierce and slightly sharp/flat upper partials: "out of tune" on purpose.
BELL = [(0.5, 0.55, 1.0), (1.0, 1.0, 0.55), (1.19, 0.55, 0.45), (1.5, 0.3, 0.32), (2.0, 0.45, 0.28),
        (2.52, 0.22, 0.2), (2.66, 0.2, 0.17), (3.01, 0.16, 0.14), (4.08, 0.11, 0.1), (5.43, 0.07, 0.07)]


def bell(f, dur, rng, bright=1.0, bend=None, strike=0.25, detune=1.0):
    """Additive bronze bell. bend: final pitch ratio (the drain toll bends down)."""
    n = int(dur * SR)
    out = [0.0] * n
    for r, a, d in BELL:
        ff = f * r * (1.0 + rng.uniform(-0.006, 0.006) * detune)
        amp = a * (bright ** math.log2(r) if r > 1 else 1.0)
        s = osc('sine', ff, dur, ff * bend if bend else None, phase=rng.random())
        tau = max(0.04, d * dur)
        beat = rng.uniform(0.6, 2.4)
        k = math.exp(-1.0 / (tau * SR))
        g = amp
        w = TAU * beat / SR
        att = int(0.002 * SR)
        for i in range(n):
            e = g * (1.0 + 0.22 * math.sin(w * i))
            if i < att:
                e *= i / att
            out[i] += s[i] * e
            g *= k
    if strike:
        hit = filt(white(0.03, rng), 'bp', min(f * 6, 6000), 0.8)
        mix(out, env_exp(hit, strike, 0.0005))
    return out


def thud(f0=90, f1=40, dur=0.3, rng=None, body=0.6):
    """Low impact: falling sine plus lowpassed noise."""
    s = env_decay(osc('sine', f0, dur, f1), dur * 0.35, 0.002)
    if rng:
        nz = env_decay(filt(white(dur, rng), 'lp', 300), dur * 0.2, 0.001)
        mix(s, nz, 0, body)
    return s


def pings(dst, rng, count, t0, t1, flo, fhi, tau=(0.04, 0.12), vol=(0.3, 1.0)):
    """Scattered short metallic or glassy pings."""
    for _ in range(count):
        f = rng.uniform(flo, fhi)
        d = rng.uniform(*tau)
        s = env_decay(osc('sine', f, d * 5), d, 0.001, rng.uniform(*vol))
        mix(dst, s, rng.uniform(t0, t1))


def formant_choir(notes, dur, rng, vowel=(700, 1100, 2600)):
    """Soft wordless 'aah': detuned band-limited saws through three formant bandpasses. Heroes only."""
    src = [0.0] * int(dur * SR)
    for f in notes:
        for cents in (-6.0, 6.0):
            ff = f * 2 ** (cents / 1200)
            mix(src, osc('saw', ff, dur, vib=14, t0=rng.random(), phase=rng.random()), 0, 0.5)
    f1, f2, f3 = vowel
    out = filt(src, 'bp', f1, 6.0)
    mix(out, filt(src, 'bp', f2, 8.0), 0, 0.55)
    mix(out, filt(src, 'bp', f3, 12.0), 0, 0.22)
    mix(out, filt(src, 'lp', 500), 0, 0.15)
    return out


# ---------------------------------------------------------------- music (port of the Music sequencer)

NAMES = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11}


def nn(s):
    m = re.match(r'^([A-G])(#|b)?(-?\d)$', s)
    if not m:
        raise ValueError('bad note: ' + s)
    return 12 * (int(m.group(3)) + 1) + NAMES[m.group(1)] + (1 if m.group(2) == '#' else -1 if m.group(2) == 'b' else 0)


def mel(text):
    out = []
    for tk in text.split():
        a, _, b = tk.partition(':')
        out.append((0 if a == 'r' else nn(a), int(b) if b else 1))
    return out


def arp(chords, pattern, length=2):
    out = []
    for tk in chords.split():
        c, _, rep = tk.partition('*')
        tones = [nn(x) for x in c.split('.')]
        for _ in range(int(rep) if rep else 1):
            for p in pattern:
                i, d = p if isinstance(p, (list, tuple)) else (p, length)
                out.append((0 if i < 0 else tones[i % len(tones)] + 12 * (i // len(tones)), d))
    return out


def rest(steps):
    return [(0, steps)]


def midi(n):
    return 440.0 * 2 ** ((n - 69) / 12.0)


ENV = {'sus': (0.012, 0.7, 0.08, 0.035), 'pluck': (0.004, 0.25, 0.07, 0.03),
       'soft': (0.08, 0.9, 0.2, 0.12), 'bass': (0.006, 0.8, 0.1, 0.03)}
WAVE = {'tri': 'tri', 'p50': 'p50', 'p25': 'p25', 'p12': 'p12'}


def music_note(kind, f, dur, vol, env, vib, t0):
    """One note with the audio.js envelope: attack, setTarget to sustain, release after dur, stop at dur + 6r."""
    a, s, tau, r = ENV[env]
    total = dur + r * 6
    x = osc(WAVE[kind], f, total, vib=vib if (vib and dur > 0.3) else 0.0, t0=t0)
    na, nd = int(a * SR), int(dur * SR)
    ka = math.exp(-1.0 / (tau * SR))
    kr = math.exp(-1.0 / (r * SR))
    g = 0.0
    for i in range(len(x)):
        if i < na:
            g = vol * i / na
        elif i < nd:
            g = vol * s + (g - vol * s) * ka
        else:
            g *= kr
        x[i] *= g
    return x


def drum(k, dv, rng):
    if k == 'k':
        s = osc('tri', 150, 0.16, 42 * (42 / 150) ** (0.05 / 0.11))
        return env_exp(s, 0.13 * dv, 0.001)
    if k == 's':
        return env_exp(filt(white(0.11, rng), 'bp', 1800, 0.7), 0.05 * dv, 0.001)
    return env_exp(filt(white(0.05, rng), 'hp', 7000, 0.7), 0.018 * dv, 0.001)


def pan_gains(p):
    a = (p + 1) * math.pi / 4
    return math.cos(a), math.sin(a)


def render_song(song, seed, extra=None, tail=3.0):
    """Render one loop of a song as stereo (L, R). Echo voices sit to the side for a little width.
    extra(L, R, step_seconds) can add non-note layers (the boss bell)."""
    rng = random.Random(seed)
    sd = 60.0 / song['bpm'] / song['spb']
    steps = max(sum(d for _, d in c['notes']) for c in song['ch'])
    loop = steps * sd
    n = int(round(loop * SR))
    L = zeros(loop + tail)
    R = zeros(loop + tail)

    def put(x, at, p):
        gl, gr = pan_gains(p)
        mix(L, x, at, gl)
        mix(R, x, at, gr)

    for c in song['ch']:
        pos = 0
        for note, d in c['notes']:
            if note:
                t = pos * sd
                dur = d * sd * 0.92
                put(music_note(c['w'], midi(note), dur, c['v'], c['env'], c.get('vib', 0), t), t, c.get('pan', 0.0))
                if 'echo' in c:
                    e, ev = c['echo']
                    put(music_note(c['w'], midi(note), dur, c['v'] * ev, c['env'], c.get('vib', 0), t + e * sd),
                        t + e * sd, c.get('echo_pan', 0.4))
                if 'dbl' in c:
                    o, dv = c['dbl']
                    put(music_note(c['w'], midi(note + o), dur, c['v'] * dv, c['env'], c.get('vib', 0), t), t, 0.0)
            pos += d
    if song.get('dr'):
        pat = song['dr']
        for s in range(steps):
            k = pat[s % len(pat)]
            if k != '.':
                put(drum(k, song.get('dv', 1.0), rng), s * sd, 0.25 if k == 'h' else 0.0)
    if extra:
        extra(put, sd, rng)
    L = filt(scale(L, 0.45), 'lp', 6500)
    R = filt(scale(R, 0.45), 'lp', 6500)
    return tuple(limit([fold(L, n), fold(R, n)], song.get('crest', 9.0)))


# Valmor at night: calm waltz in F (audio.js `town`), plus the part B in D minor proposed in
# docs/som/avaliacao-2026-11-07.md so the loop tires less (A 16 bars + B 8 bars = 45 s).
TOWN_LEAD = mel('''
    F4:4 G4:2 A4:2 C5:4   D5:6 C5:2 A4:4   Bb4:4 A4:2 G4:2 F4:4   G4:10 r:2
    F4:4 G4:2 A4:2 C5:4   F5:6 E5:2 D5:4   C5:4 A4:2 Bb4:2 G4:4   F4:10 r:2
    D5:4 E5:2 F5:2 A5:4   G5:6 F5:2 D5:4   C5:4 D5:2 E5:2 F5:4    E5:10 r:2
    D5:4 F5:2 A5:2 G5:4   F5:6 E5:2 D5:4   C5:4 F5:2 E5:2 G5:4    F5:8 r:4''')
TOWN_B = mel('''
    A4:4 D5:2 F5:2 E5:4   D5:6 C5:2 A4:4   Bb4:4 G4:2 A4:2 F4:4   E4:10 r:2
    A4:4 C5:2 D5:2 F5:4   E5:6 D5:2 C#5:4  D5:4 A4:2 Bb4:2 G4:4   A4:10 r:2''')
TOWN_CH = ('F2.C3 D2.A2 Bb1.F2 C2.G2 F2.C3 D2.A2 C2.G2 F2.C3 D2.A2 Bb1.F2 C2.G2 A1.E2 D2.A2 Bb1.F2 C2.G2 F2.C3 '
           'D2.A2 D2.A2 G2.D3 A1.E2 D2.A2 A1.E2 G2.D3 A1.E2')
TOWN_PAD = mel('A4:12 A4:12 F4:12 G4:12 A4:12 A4:12 G4:12 A4:12 A4:12 Bb4:12 G4:12 C#5:12 A4:12 Bb4:12 G4:12 A4:12 '
               'F4:12 F4:12 G4:12 E4:12 F4:12 E4:12 G4:12 E4:12')
VALMOR = {'bpm': 96, 'spb': 4, 'ch': [
    {'w': 'p25', 'v': 0.03, 'env': 'sus', 'vib': 7, 'echo': (3, 0.3), 'notes': TOWN_LEAD + rest(96)},
    {'w': 'p12', 'v': 0.034, 'env': 'sus', 'vib': 7, 'echo': (3, 0.3), 'echo_pan': -0.4, 'notes': rest(192) + TOWN_B},
    {'w': 'p12', 'v': 0.014, 'env': 'soft', 'pan': -0.3, 'notes': TOWN_PAD},
    {'w': 'tri', 'v': 0.085, 'env': 'bass', 'notes': arp(TOWN_CH, [0, 2, 1], 4)},
]}

# Boss: C minor, low and chromatic (audio.js `boss`). A boss track, not a character theme.
BOSS_A1 = mel('''
    C5:3 Db5:1 C5:4 r:2 G4:2 Ab4:2 B4:2   C5:3 Db5:1 C5:4 r:2 Eb5:2 D5:2 Db5:2
    Db5:3 D5:1 Db5:4 r:2 Ab4:2 A4:2 C5:2   F5:4 E5:4 Eb5:4 D5:4
    C5:3 Db5:1 C5:4 r:2 G4:2 Ab4:2 B4:2''')
BOSS_LEAD = (BOSS_A1 + mel('Eb5:4 G5:4 F#5:4 G5:4   Ab5:6 G5:2 F5:4 Eb5:4   D5:4 Eb5:4 B4:8') + BOSS_A1
             + mel('G5:4 C6:4 B5:4 C6:4   C6:6 B5:2 Ab5:4 F5:4   G5:4 Ab5:4 B5:8')
             + mel('''F5:8 Ab5:8   G5:8 F5:4 E5:4   Gb5:8 Db5:8   C5:8 F5:4 Ab5:4
                      Ab5:8 Eb5:4 C5:4   Eb5:4 F5:4 Gb5:4 F5:4   G5:8 F5:4 Eb5:4   D5:4 B4:4 G4:4 B4:4'''))
BOSS_CH = ('C2.C3.B1*2 Db2.Db3.C2*2 C2.C3.B1*2 Ab1.Ab2.G1 G1.G2.F#1 '
           'C2.C3.B1*2 Db2.Db3.C2*2 C2.C3.B1*2 Ab1.Ab2.G1 G1.G2.F#1 '
           'F2.F3.E2*2 Gb2.Gb3.F2 F2.F3.E2 Ab1.Ab2.G1*2 G1.G2.F#1*2')
BOSS = {'bpm': 160, 'spb': 4, 'dv': 1.0, 'dr': 'kkh.s.h.kkh.s.hs', 'ch': [
    {'w': 'p50', 'v': 0.026, 'env': 'sus', 'dbl': (-12, 0.5), 'notes': BOSS_LEAD},
    {'w': 'tri', 'v': 0.095, 'env': 'bass', 'notes': arp(BOSS_CH, [0, 0, 1, 0, 2, 0, 1, 0], 2)},
], 'crest': 8.0}


def boss_bell(put, sd, rng):
    """The bell inside the boss loop: one G3 toll every 4 bars (the object of the scene, not a villain theme)."""
    for k in range(6):
        b = filt(bell(196.0, 3.2, rng, bright=0.7, strike=0.1), 'lp', 2500)
        put(scale(b, 0.03), k * 64 * sd, 0.0)


# Victory: short and restrained, relief rather than triumph. Ab, Bb, then C major after the C minor fight.
VICTORY = {'bpm': 110, 'spb': 4, 'ch': [
    {'w': 'p25', 'v': 0.03, 'env': 'sus', 'vib': 7, 'echo': (3, 0.3), 'notes': mel('Eb5:2 Ab5:6 F5:2 Bb5:6 G5:2 C6:14')},
    {'w': 'p12', 'v': 0.016, 'env': 'soft', 'pan': -0.3, 'notes': mel('C5:8 D5:8 E5:16')},
    {'w': 'tri', 'v': 0.07, 'env': 'soft', 'notes': mel('Ab2:8 Bb2:8 C3:16')},
]}


def render_jingle(song, seed, length):
    rng = random.Random(seed)
    sd = 60.0 / song['bpm'] / song['spb']
    L, R = zeros(length), zeros(length)
    for c in song['ch']:
        pos = 0
        for note, d in c['notes']:
            if note:
                t, dur = pos * sd, d * sd * 0.92
                gl, gr = pan_gains(c.get('pan', 0.0))
                x = music_note(c['w'], midi(note), dur, c['v'], c['env'], c.get('vib', 0), t)
                mix(L, x, t, gl)
                mix(R, x, t, gr)
                if 'echo' in c:
                    e, ev = c['echo']
                    gl, gr = pan_gains(0.4)
                    x = music_note(c['w'], midi(note), dur, c['v'] * ev, c['env'], c.get('vib', 0), t)
                    mix(L, x, t + e * sd, gl)
                    mix(R, x, t + e * sd, gr)
            pos += d
    _ = rng
    L, R = filt(L, 'lp', 6500), filt(R, 'lp', 6500)
    return fade_edges(L, 0, 0.3), fade_edges(R, 0, 0.3)


# ---------------------------------------------------------------- the sounds

def s_valmor_noite():
    return render_song(VALMOR, 1)


def s_chefe_sineiro():
    return render_song(BOSS, 2, extra=boss_bell)


def s_vitoria():
    return render_jingle(VICTORY, 3, 5.2)


def s_derrota():
    rng = random.Random(4)
    L, R = zeros(4.8), zeros(4.8)
    b = filt(bell(196.0, 4.5, rng, bright=0.6, strike=0.15), 'lp', 1400)
    bl, br = stereo_reverb(scale(b, 0.5), room=1.3, wet=0.5, tail=0.2)
    mix(L, bl)
    mix(R, br)
    chord = [0.0] * int(4.4 * SR)
    for i, f in enumerate((midi(nn('C3')), midi(nn('G3')), midi(nn('C4')), midi(nn('Eb4')), midi(nn('G4')))):
        mix(chord, osc('tri', f, 4.4, phase=i * 0.17), 0, 0.22 if i else 0.3)
    env_curve(chord, [(0, 0), (0.6, 1.0), (1.4, 0.8), (4.4, 0.0)])
    line = [0.0] * int(4.0 * SR)
    for t, nm, d in ((0.5, 'G4', 0.9), (1.4, 'Eb4', 0.9), (2.3, 'C4', 1.6)):
        mix(line, music_note('p12', midi(nn(nm)), d, 0.5, 'soft', 6, t), t)
    gl, gr = pan_gains(-0.2)
    mix(L, chord, 0.3, gl * 0.35)
    mix(R, chord, 0.3, gr * 0.35)
    mix(L, line, 0.3, 0.12)
    mix(R, line, 0.3, 0.12)
    return fade_edges(L, 0, 0.4), fade_edges(R, 0, 0.4)


def s_valmor_vento():
    """Cold wind with rare gusts and a faint distant hearth. 60 s loop."""
    rng = random.Random(5)
    loop, fade = 60.0, 3.0
    out = []
    for ch in range(2):
        nz = brown(loop + fade, rng, 0.98)
        mixw = [0.0] * len(nz)
        # wind body: band sweeps slowly; modulators are periodic over the loop
        n = len(nz)
        mod = [0.55 + 0.25 * math.sin(TAU * (i / SR) * 3 / loop + ch) + 0.2 * math.sin(TAU * (i / SR) * 7 / loop + 2.1)
               for i in range(0, n, 32)]
        y1 = y2 = x1 = x2 = 0.0
        for i in range(n):
            if i % 32 == 0:
                m = mod[i // 32]
                b0, b1, b2, a1, a2 = _coefs('bp', 250 + 650 * m * m, 1.2)
            v = nz[i]
            y = b0 * v + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2, x1, y2, y1 = x1, v, y1, y
            mixw[i] = y * (0.35 + 0.65 * m)
        # two soft gusts per loop: airy high band swelling (inside the loop, never across the seam)
        for g0 in (14.0 + ch * 0.4, 41.0 + ch * 0.3):
            gust = filt(white(4.0, rng), 'bp', 1400, 0.9, f1=700)
            env_curve(gust, [(0, 0), (1.6, 0.35), (2.2, 0.3), (4.0, 0)])
            mix(mixw, gust, g0)
        out.append(xfade_loop(mixw, int(loop * SR), fade))
    # distant hearth crackle, very low, folded so nothing is cut at the seam
    crack = zeros(loop + 1)
    for _ in range(40):
        c = filt(env_decay(white(0.02, rng), 0.004, 0.0005), 'bp', rng.uniform(1500, 3000), 1.0)
        mix(crack, c, rng.uniform(0, loop), rng.uniform(0.15, 0.4))
    crack = fold(filt(crack, 'lp', 3500), int(loop * SR))
    pk = max(peak(out[0]), peak(out[1]))
    return mix(scale(out[0], 1 / pk), crack, 0, 0.25), mix(scale(out[1], 1 / pk), crack, 0, 0.2)


def snow_step(seed):
    rng = random.Random(100 + seed)
    out = zeros(0.22)
    for _ in range(rng.randint(8, 12)):
        t = 0.13 * rng.random() ** 1.4
        d = rng.uniform(0.005, 0.018)
        g = env_decay(white(d, rng), d * 0.35, 0.0005, rng.uniform(0.4, 1.0) * (1 - t / 0.16))
        mix(out, g, 0.004 + t)
    out = filt(out, 'bp', 1900 + 300 * seed, 0.7)
    mix(out, thud(110, 60, 0.12, rng, 0.8), 0, 0.25)
    return fade_edges(filt(out, 'lp', 7000), 0, 0.02)


def stone_step(rng, gain=1.0):
    s = zeros(0.12)
    noise(s, 0.05, 0.2 * gain, 0, 800, 0.9, rng)
    tone(s, 95, 0.05, 'tri', 0.045 * gain)
    return s


def s_descer_cripta():
    """Heavy stone slab grinding open, then three slow steps going down, echoing (the old church)."""
    rng = random.Random(7)
    dry = zeros(2.0)
    grind = filt(brown(0.85, rng, 0.99), 'bp', 320, 1.3)
    jitter, g = [], 0.0
    for _ in range(len(grind)):
        g += (rng.uniform(0, 1) - g) * 0.004
        jitter.append(g)
    grind = [v * (0.4 + 0.9 * j) for v, j in zip(grind, jitter)]
    env_curve(grind, [(0, 0), (0.12, 1), (0.65, 0.9), (0.85, 0)])
    grit = filt(white(0.85, rng), 'bp', 1800, 1.5)
    env_curve(grit, [(0, 0), (0.1, 0.25), (0.7, 0.15), (0.85, 0)])
    mix(dry, grind, 0.0, 1.0)
    mix(dry, grit, 0.0, 0.4)
    mix(dry, thud(70, 38, 0.35, rng), 0.82, 0.8)
    for k, t in enumerate((1.1, 1.45, 1.8)):
        st = filt(stone_step(rng), 'lp', 2600 - 600 * k)
        mix(dry, st, t, 4.0 * (1 - 0.18 * k))
    return reverb(dry, room=1.5, size=0.86, damp=0.35, wet=0.45, tail=1.6)


def s_cripta_gotas():
    """Ancient crypt: deep stone rumble, sparse drips with long echo, faint air. 60 s loop."""
    rng = random.Random(8)
    loop, fade = 60.0, 3.0
    n = int(loop * SR)
    beds = []
    for ch in range(2):
        rum = filt(brown(loop + fade, rng, 0.995), 'lp', 110, 0.9)
        air = filt(white(loop + fade, rng), 'bp', 900, 0.5)
        lfo_step = [0.7 + 0.3 * math.sin(TAU * (i / SR) * 2 / loop + ch) for i in range(0, len(rum), 64)]
        bed = [r * lfo_step[i // 64] + a * 0.05 for i, (r, a) in enumerate(zip(rum, air))]
        beds.append(xfade_loop(bed, n, fade))
    pk = max(peak(beds[0]), peak(beds[1]))
    drips = zeros(loop + 4.0)
    t = 1.5
    while t < loop - 0.5:
        f = rng.choice((1318.5, 1760.0, 1174.7, 1568.0)) * rng.uniform(0.97, 1.03)
        d = env_decay(osc('sine', f, 0.06, f * 1.6), 0.012, 0.0005)
        mix(drips, d, t, rng.uniform(0.5, 1.0))
        t += rng.uniform(2.5, 7.5)
    wl, wr = stereo_reverb(drips, room=2.2, size=0.9, damp=0.4, wet=0.9, tail=0.0)
    wl, wr = fold(wl, n), fold(wr, n)
    return mix(scale(beds[0], 0.6 / pk), wl, 0, 0.5), mix(scale(beds[1], 0.6 / pk), wr, 0, 0.5)


def s_sino_entrada():
    """One huge bronze bell struck once, deep thud, long decay in the crypt. The boss music waits for it."""
    rng = random.Random(9)
    b = bell(98.0, 4.2, rng, bright=0.9, strike=0.4)
    mix(b, thud(60, 32, 0.6, rng, 0.9), 0, 0.9)
    return fade_edges(reverb(b, room=1.6, size=0.86, damp=0.4, wet=0.35, tail=1.0), 0, 0.5)


def s_badalada():
    """Two violent strikes of the cracked bell, low shockwave, stone dust. Loudest enemy sound."""
    rng = random.Random(10)
    out = zeros(2.6)
    for t, g in ((0.0, 0.85), (0.55, 1.0)):
        b = bell(196.0, 1.9, rng, bright=1.1, strike=0.6, detune=2.0)
        mix(out, b, t, g)
        mix(out, thud(62, 30, 0.7, rng, 1.0), t, 1.3 * g)
    dust = filt(white(1.4, rng), 'hp', 2500)
    env_curve(dust, [(0, 0), (0.1, 0.12), (1.4, 0)])
    mix(out, dust, 0.6)
    return fade_edges(reverb(out, room=1.4, wet=0.3, tail=0.6), 0, 0.3)


def s_dobre():
    """Slow muffled toll that bends down while it drains a hero; a faint glint as the life reaches him."""
    rng = random.Random(11)
    out = zeros(1.9)
    b = filt(bell(196.0, 1.7, rng, bright=0.5, bend=0.93, strike=0.1), 'lp', 1100)
    env_curve(b, [(0, 0), (0.05, 1), (1.7, 1)])
    mix(out, b)
    hum = env_curve(osc('sine', 330, 1.3, 110), [(0, 0), (0.3, 0.25), (1.0, 0.2), (1.3, 0)])
    mix(out, hum, 0.15)
    for f in (1568.0, 2349.3):
        mix(out, env_decay(osc('sine', f, 0.5), 0.12, 0.01, 0.06), 1.2)
    return fade_edges(reverb(out, room=1.3, wet=0.3, tail=0.4), 0, 0.2)


def s_golpe_sino():
    """The bell swung as a weapon: hollow metal on a body, short."""
    rng = random.Random(12)
    out = zeros(0.6)
    b = bell(330.0, 0.55, rng, bright=1.2, strike=0.8, detune=1.5)
    mix(out, b, 0, 0.6)
    mix(out, thud(130, 50, 0.25, rng, 1.2), 0, 1.2)
    flesh = env_decay(filt(white(0.1, rng), 'bp', 600, 1.0), 0.03, 0.001)
    mix(out, flesh, 0.005, 0.8)
    return fade_edges(out, 0, 0.05)


def s_furia():
    """Frantic shaking of the cracked bell below 40 % life: fast, uneven, two clashing pitches."""
    rng = random.Random(13)
    out = zeros(1.45)
    t, k = 0.0, 0
    while t < 1.15:
        f = (392.0, 415.3)[k % 2] * rng.uniform(0.99, 1.01)
        g = math.sin(math.pi * min(1.0, t / 1.15)) ** 0.6
        b = bell(f, 0.3, rng, bright=1.3, strike=0.5, detune=2.5)
        mix(out, b, t, 0.35 + 0.65 * g)
        t += rng.uniform(0.045, 0.085)
        k += 1
    rattle = filt(white(1.2, rng), 'hp', 3500)
    env_curve(rattle, [(0, 0), (0.5, 0.08), (1.2, 0)])
    mix(out, rattle)
    return fade_edges(out, 0, 0.1)


def s_ultimo_toque():
    """The bell rolls across the stones, then one last far toll, fading to silence."""
    rng = random.Random(14)
    out = zeros(7.0)
    roll = filt(brown(2.4, rng, 0.99), 'lp', 350)
    jit, g = [], 0.0
    for _ in range(len(roll)):
        g += (rng.random() - g) * 0.01
        jit.append(g)
    roll = [v * j for v, j in zip(roll, jit)]
    env_curve(roll, [(0, 0), (0.1, 1), (1.8, 0.6), (2.4, 0)])
    mix(out, roll, 0, 0.5)
    t, gap = 0.0, 0.12
    while t < 2.2:
        b = bell(196.0 * rng.uniform(0.98, 1.02), 0.4, rng, bright=0.8, strike=0.6)
        g = 1.0 - t / 2.6
        mix(out, b, t, 0.3 * g)
        mix(out, thud(110, 60, 0.15, rng, 1.0), t, 0.6 * g)
        t += gap * rng.uniform(0.7, 1.4)
        gap *= 1.12
    far = filt(bell(196.0, 3.6, rng, bright=0.6, strike=0.05), 'lp', 900)
    mix(out, far, 2.9, 0.18)
    return fade_edges(reverb(out, room=1.6, size=0.88, wet=0.4, tail=0.5), 0, 0.8)


def whoosh(dur, f0, f1, rng, points, q=0.9):
    w = filt(white(dur, rng), 'bp', f0, q, f1=f1)
    return env_curve(w, points)


def s_avanco():
    rng = random.Random(15)
    out = zeros(0.4)
    for d in (0.0, 0.07, 0.14):
        noise(out, 0.05, 0.6, d, 900, 0.8, rng)
    mix(out, whoosh(0.32, 500, 1600, rng, [(0, 0), (0.18, 1), (0.32, 0)]), 0.05, 0.9)
    return out


def s_volta():
    rng = random.Random(16)
    return whoosh(0.26, 1400, 500, rng, [(0, 0), (0.08, 1), (0.26, 0)])


def s_espada():
    rng = random.Random(17)
    s = filt(white(0.22, rng), 'bp', 2000, 0.9, f1=6000)
    env_curve(s, [(0, 0), (0.012, 1), (0.22, 0)])
    mix(s, env_decay(osc('sine', 2800, 0.12, 3300), 0.03, 0.002, 0.08))
    return s


def s_impacto():
    rng = random.Random(18)
    out = zeros(0.32)
    noise(out, 0.08, 0.15, 0, 800, 1, rng)
    tone(out, 140, 0.1, 'sq', 0.05, 60)
    crack = env_decay(filt(white(0.02, rng), 'hp', 3000), 0.004, 0.0003, 0.12)
    mix(out, crack)
    mix(out, env_decay(osc('tri', 420, 0.08), 0.02, 0.001, 0.06), 0.003)
    mix(out, thud(95, 45, 0.25, rng, 0.8), 0, 0.12)
    return out


def s_impacto_magico():
    rng = random.Random(19)
    out = zeros(0.45)
    noise(out, 0.12, 0.6, 0, 2500, 0.6, rng)
    mix(out, env_decay(osc('sine', 600, 0.12, 300), 0.04, 0.002, 0.6))
    pings(out, rng, 7, 0.0, 0.12, 2000, 4500, (0.03, 0.07), (0.15, 0.4))
    return fade_edges(out, 0, 0.05)


def s_dano_heroi():
    rng = random.Random(20)
    out = zeros(0.3)
    tone(out, 200, 0.15, 'saw', 0.07, 80)
    noise(out, 0.1, 0.1, 0, 500, 1, rng)
    mix(out, thud(90, 50, 0.12, rng, 0.8), 0, 0.12)
    return out


def s_queda():
    rng = random.Random(21)
    out = zeros(0.8)
    tone(out, 330, 0.5, 'tri', 0.02, 110)
    mix(out, thud(75, 38, 0.35, rng, 1.0), 0.06, 1.0)
    mix(out, thud(90, 50, 0.15, rng, 1.0), 0.24, 0.45)
    pings(out, rng, 9, 0.06, 0.4, 2000, 5000, (0.015, 0.04), (0.1, 0.3))
    return fade_edges(out, 0, 0.05)


def s_defender():
    rng = random.Random(22)
    out = zeros(0.55)
    for f, a in ((820, 1.0), (1270, 0.6), (1910, 0.45), (2650, 0.3)):
        mix(out, env_decay(osc('sine', f, 0.5), 0.14, 0.001, a * 0.25))
    shim = [0.0] * int(0.45 * SR)
    for f in (1568.0, 2093.0, 2637.0):
        mix(shim, osc('sine', f, 0.45))
    w = TAU * 14 / SR
    shim = [v * (0.6 + 0.4 * math.sin(w * i)) for i, v in enumerate(shim)]
    env_curve(shim, [(0, 0), (0.15, 0.06), (0.45, 0)])
    mix(out, shim, 0.04)
    tone(out, 330, 0.12, 'sq', 0.025)
    tone(out, 494, 0.1, 'sq', 0.02, None, 0.05)
    return out


def s_golpe_forte():
    """Aldo: heavy overhead smash. Crescendo into the hit."""
    rng = random.Random(23)
    out = zeros(1.0)
    mix(out, whoosh(0.28, 300, 1200, rng, [(0, 0), (0.25, 0.5), (0.28, 0.2)]), 0.0)
    mix(out, thud(110, 36, 0.6, rng, 1.2), 0.27, 1.0)
    hit = env_decay(filt(white(0.15, rng), 'lp', 1600), 0.04, 0.001)
    mix(out, hit, 0.27, 0.8)
    pings(out, rng, 4, 0.27, 0.3, 1100, 2600, (0.04, 0.08), (0.08, 0.15))
    return fade_edges(reverb(out, room=0.9, wet=0.2, tail=0.3), 0, 0.15)


def s_passo_sombras_some():
    """Andilla vanishes: dark breath rising, then cut into smoke."""
    rng = random.Random(24)
    out = zeros(0.45)
    w = filt(white(0.42, rng), 'bp', 1500, 1.0, f1=250)
    env_curve(w, [(0, 0), (0.28, 1), (0.32, 0.25), (0.42, 0)])
    mix(out, w)
    mix(out, env_curve(osc('sine', 120, 0.35, 60), [(0, 0), (0.25, 0.3), (0.35, 0)]))
    return out


def s_passo_sombras_volta():
    """Andilla reappears behind the enemy: short reverse breath, then a dagger strike."""
    rng = random.Random(25)
    out = zeros(0.55)
    mix(out, whoosh(0.13, 300, 2000, rng, [(0, 0), (0.12, 0.7), (0.13, 0)]))
    sl = filt(white(0.12, rng), 'bp', 3000, 0.9, f1=7000)
    env_curve(sl, [(0, 0), (0.008, 1), (0.12, 0)])
    mix(out, sl, 0.13, 0.9)
    for f in (3200, 4500, 6100):
        mix(out, env_decay(osc('sine', f, 0.15), 0.03, 0.001, 0.08), 0.14)
    noise(out, 0.08, 0.15, 0.15, 800, 1, rng)
    tone(out, 140, 0.1, 'sq', 0.04, 60, 0.15)
    return out


def s_fogo():
    """Lyra: fire. Ignition, roaring flight, explosion (crescendo into the blast)."""
    rng = random.Random(26)
    out = zeros(1.35)
    ign = env_decay(filt(white(0.12, rng), 'bp', 2000, 0.8), 0.04, 0.002)
    mix(out, ign, 0, 0.35)
    fl = filt(white(0.65, rng), 'bp', 600, 0.5, f1=900)
    w = TAU * 18 / SR
    fl = [v * (0.75 + 0.25 * math.sin(w * i)) for i, v in enumerate(fl)]
    env_pow(fl, 0.62, 1.6, 0.03)
    mix(out, fl, 0.08, 0.7)
    mix(out, env_pow(osc('saw', 220, 0.6, 80), 0.6, 1.5, 0.03), 0.1, 0.06)
    pings(out, rng, 10, 0.05, 0.7, 1500, 3500, (0.005, 0.012), (0.05, 0.15))
    ex = filt(white(0.55, rng), 'lp', 3000, 0.707, f1=300)
    env_decay(ex, 0.14, 0.002)
    mix(out, ex, 0.72, 1.0)
    mix(out, thud(85, 35, 0.5, rng, 0.8), 0.72, 1.0)
    return fade_edges(out, 0, 0.1)


def s_gelo():
    """Lyra: ice. Crystals forming (crescendo) then shattering."""
    rng = random.Random(27)
    out = zeros(1.15)
    for i, f in enumerate((1800, 1500, 2100, 1700, 2300)):
        g = 0.35 + 0.15 * i
        x = osc('tri', f, 0.25)
        mix(x, osc('sine', f * 2.76, 0.25), 0, 0.3)
        mix(out, env_decay(x, 0.07, 0.002, g * 0.3), i * 0.09)
    hiss = filt(white(0.6, rng), 'hp', 6000)
    env_pow(hiss, 0.58, 2.0, 0.02)
    mix(out, hiss, 0.0, 0.25)
    sh = env_decay(filt(white(0.3, rng), 'hp', 3000), 0.07, 0.001)
    mix(out, sh, 0.6, 0.9)
    pings(out, rng, 16, 0.6, 0.85, 2500, 6000, (0.02, 0.08), (0.2, 0.5))
    return fade_edges(out, 0, 0.08)


def s_cura():
    """Teo: heal. Warm rising glass-bell arpeggio and a soft shimmer."""
    rng = random.Random(28)
    out = zeros(1.2)
    for i, f in enumerate((523.3, 659.3, 784.0, 1046.5)):
        x = osc('sine', f, 0.9)
        mix(x, osc('sine', f * 2.0, 0.9), 0, 0.25)
        mix(x, osc('sine', f * 3.0, 0.9), 0, 0.08)
        mix(out, env_decay(x, 0.3, 0.006, 0.5), i * 0.09)
    pad = [0.0] * int(1.0 * SR)
    for f in (261.6, 329.6, 392.0):
        mix(pad, osc('tri', f, 1.0), 0, 0.3)
    env_curve(pad, [(0, 0), (0.4, 0.4), (1.0, 0)])
    mix(out, pad, 0.05, 0.4)
    pings(out, rng, 8, 0.3, 0.8, 2500, 5000, (0.05, 0.12), (0.03, 0.08))
    return fade_edges(out, 0, 0.1)


def s_luz_sagrada():
    """Teo: holy light. Soft wordless choir swelling with clear bells, radiant burst at the end.
    The choir belongs to the heroes; the strongest blow against the undead, so it has weight."""
    rng = random.Random(29)
    out = zeros(2.0)
    ch = formant_choir([196.0, 293.7, 392.0, 493.9, 587.3], 1.9, rng)
    pk = peak(ch) or 1.0
    ch = env_curve(scale(ch, 1 / pk), [(0, 0), (0.4, 0.15), (1.15, 0.7), (1.4, 0.55), (1.9, 0)])
    mix(out, ch, 0, 0.6)
    for i, f in enumerate((784.0, 988.0, 1175.0, 1568.0)):
        b = bell(f, 0.9, rng, bright=1.0, strike=0.1, detune=0.2)
        mix(out, b, 0.25 + i * 0.18, 0.06 + 0.02 * i)
    burst = env_decay(filt(white(0.6, rng), 'hp', 5000), 0.15, 0.003)
    mix(out, burst, 1.15, 0.35)
    for f in (1568.0, 1975.5, 2349.3):
        mix(out, env_decay(osc('sine', f, 0.8), 0.25, 0.004, 0.08), 1.15)
    mix(out, thud(98, 60, 0.4, None), 1.15, 0.35)
    l = reverb(out, room=1.2, wet=0.3, tail=0.4)
    return fade_edges(l, 0, 0.3)


def s_carga():
    """'Hold A to power up': riser of exactly 1.0 s (CHARGE_TIME). Crescendo; cut it with a short fade
    if the button is released early, and play carga_cheia when it reaches the end."""
    rng = random.Random(30)
    out = zeros(1.0)
    for c in (-7.0, 7.0):
        f = 196.0 * 2 ** (c / 1200)
        mix(out, osc('saw', f, 1.0, f * 4), 0, 0.3)
    mix(out, osc('tri', 98.0, 1.0, 196.0), 0, 0.4)
    out = filt(out, 'lp', 400, 1.2, f1=5000)
    sh = filt(white(1.0, rng), 'hp', 4000)
    env_pow(sh, 1.0, 3.0, 0.0)
    mix(out, sh, 0, 0.25)
    return env_pow(out, 0.98, 1.6, 0.02)


def s_carga_cheia():
    rng = random.Random(31)
    out = zeros(0.6)
    for f, a in ((1568.0, 1.0), (2349.3, 0.6), (3136.0, 0.3)):
        mix(out, env_decay(osc('sine', f, 0.6), 0.16, 0.003, a))
    pings(out, rng, 5, 0.0, 0.1, 3000, 6000, (0.03, 0.06), (0.1, 0.25))
    return fade_edges(out, 0, 0.05)


def s_cursor():
    out = zeros(0.06)
    tone(out, 1320, 0.035, 'tri', 0.05)
    tone(out, 2640, 0.015, 'sine', 0.01)
    return out


def s_confirmar():
    out = zeros(0.14)
    tone(out, 660, 0.06, 'tri', 0.05)
    tone(out, 990, 0.08, 'tri', 0.05, None, 0.045)
    return out


def s_voltar():
    out = zeros(0.1)
    tone(out, 440, 0.07, 'tri', 0.05, 220)
    return out


def s_negado():
    out = zeros(0.14)
    tone(out, 110, 0.12, 'sq', 0.06, 70)
    return filt(out, 'lp', 900)


# name -> (path under assets/audio, render, target peak dBFS, scene/use)
SOUNDS = {
    'valmor_noite':       ('music/valmor_noite.ogg', s_valmor_noite, -18, 'Valmor à noite, laço'),
    'chefe_sineiro':      ('music/chefe_sineiro.ogg', s_chefe_sineiro, -18, 'luta com o Sineiro, laço'),
    'valmor_vento':       ('amb/valmor_vento.ogg', s_valmor_vento, -24, 'vento de Valmor, laço'),
    'cripta_gotas':       ('amb/cripta_gotas.ogg', s_cripta_gotas, -24, 'cripta, abertura da luta, laço'),
    'vitoria':            ('sfx/jingle/vitoria.ogg', s_vitoria, -14, 'vitória contida'),
    'derrota':            ('sfx/jingle/derrota.ogg', s_derrota, -14, 'derrota'),
    'passo_neve_1':       ('sfx/field/passo_neve_1.wav', lambda: snow_step(1), -16, 'passo do líder na neve'),
    'passo_neve_2':       ('sfx/field/passo_neve_2.wav', lambda: snow_step(2), -16, 'passo do líder na neve'),
    'passo_neve_3':       ('sfx/field/passo_neve_3.wav', lambda: snow_step(3), -16, 'passo do líder na neve'),
    'passo_neve_4':       ('sfx/field/passo_neve_4.wav', lambda: snow_step(4), -16, 'passo do líder na neve'),
    'descer_cripta':      ('sfx/field/descer_cripta.wav', s_descer_cripta, -10, 'entrar na igreja velha'),
    'sino_entrada':       ('sfx/boss/sino_entrada.wav', s_sino_entrada, -6, 'badalada de entrada do chefe'),
    'badalada':           ('sfx/boss/badalada.wav', s_badalada, -6, 'Sineiro: ataque em todos'),
    'dobre':              ('sfx/boss/dobre.wav', s_dobre, -8, 'Sineiro: dobre que drena'),
    'golpe_sino':         ('sfx/boss/golpe_sino.wav', s_golpe_sino, -7, 'Sineiro: golpe com o sino'),
    'furia':              ('sfx/boss/furia.wav', s_furia, -8, 'Sineiro: fúria abaixo de 40%'),
    'ultimo_toque':       ('sfx/boss/ultimo_toque.wav', s_ultimo_toque, -8, 'fim: o sino rola e toca uma última vez'),
    'avanco':             ('sfx/battle/avanco.wav', s_avanco, -10, 'herói corre até o chefe'),
    'volta':              ('sfx/battle/volta.wav', s_volta, -13, 'herói volta ao lugar'),
    'espada':             ('sfx/battle/espada.wav', s_espada, -8, 'corte de Aldo e Andilla'),
    'impacto':            ('sfx/battle/impacto.wav', s_impacto, -7, 'lâmina acerta'),
    'impacto_magico':     ('sfx/battle/impacto_magico.wav', s_impacto_magico, -9, 'ataque normal de Lyra e Teo'),
    'dano_heroi':         ('sfx/battle/dano_heroi.wav', s_dano_heroi, -8, 'herói leva dano'),
    'queda':              ('sfx/battle/queda.wav', s_queda, -9, 'herói cai'),
    'defender':           ('sfx/battle/defender.wav', s_defender, -9, 'defender'),
    'golpe_forte':        ('sfx/skill/golpe_forte.wav', s_golpe_forte, -5, 'Aldo: Golpe Forte'),
    'passo_sombras_some': ('sfx/skill/passo_sombras_some.wav', s_passo_sombras_some, -9, 'Andilla: some'),
    'passo_sombras_volta': ('sfx/skill/passo_sombras_volta.wav', s_passo_sombras_volta, -7, 'Andilla: volta e golpeia'),
    'fogo':               ('sfx/skill/fogo.wav', s_fogo, -5, 'Lyra: Fogo'),
    'gelo':               ('sfx/skill/gelo.wav', s_gelo, -6, 'Lyra: Gelo'),
    'cura':               ('sfx/skill/cura.wav', s_cura, -9, 'Teo: Cura'),
    'luz_sagrada':        ('sfx/skill/luz_sagrada.wav', s_luz_sagrada, -4, 'Teo: Luz Sagrada'),
    'carga':              ('sfx/skill/carga.wav', s_carga, -10, 'Segure A: sobe em 1,0 s'),
    'carga_cheia':        ('sfx/skill/carga_cheia.wav', s_carga_cheia, -9, 'Segure A: carga cheia'),
    'cursor':             ('sfx/ui/cursor.wav', s_cursor, -20, 'cursor do menu'),
    'confirmar':          ('sfx/ui/confirmar.wav', s_confirmar, -20, 'confirmar'),
    'voltar':             ('sfx/ui/voltar.wav', s_voltar, -20, 'voltar'),
    'negado':             ('sfx/ui/negado.wav', s_negado, -20, 'opção indisponível'),
}


# ---------------------------------------------------------------- output

def write_wav(path, chans):
    """16-bit PCM, mono or stereo, 44.1 kHz, TPDF dither."""
    rng = random.Random(0)
    n = len(chans[0])
    data = array('h', [0]) * (n * len(chans))
    for c, x in enumerate(chans):
        for i in range(n):
            v = x[i] * 32767.0 + (rng.random() - rng.random())
            data[i * len(chans) + c] = max(-32768, min(32767, int(round(v))))
    if sys.byteorder == 'big':
        data.byteswap()
    with wave.open(path, 'wb') as w:
        w.setnchannels(len(chans))
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


def render(name, out_dir):
    rel, fn, target, _ = SOUNDS[name]
    if rel.endswith('.ogg'):
        target -= 0.5  # Vorbis overshoots the sample peak a little; keep the decoded peak under the target
    res = fn()
    chans = list(res) if isinstance(res, tuple) else [res]
    pk = max(peak(c) for c in chans) or 1.0
    g = 10 ** (target / 20.0) / pk
    chans = [scale(c, g) for c in chans]
    dst = os.path.join(out_dir, rel)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    if dst.endswith('.ogg'):
        with tempfile.TemporaryDirectory() as tmp:
            wav = os.path.join(tmp, 'x.wav')
            write_wav(wav, chans)
            subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', wav, '-c:a', 'libvorbis', '-q:a', '4', dst],
                           check=True)
    else:
        write_wav(dst, chans)
    return dst, len(chans[0]) / SR, len(chans)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--out', default=os.path.join(ROOT, 'assets', 'audio'))
    ap.add_argument('--only', default='')
    ap.add_argument('--list', action='store_true')
    a = ap.parse_args()
    if a.list:
        for k, (rel, _, t, use) in SOUNDS.items():
            print(f'{k:22s} {rel:36s} {t:4d} dBFS  {use}')
        return
    names = [x for x in a.only.split(',') if x] or list(SOUNDS)
    for k in names:
        dst, sec, ch = render(k, a.out)
        print(f'{k:22s} {sec:6.2f} s  {ch}ch  -> {os.path.relpath(dst, ROOT)}', flush=True)


if __name__ == '__main__':
    main()
