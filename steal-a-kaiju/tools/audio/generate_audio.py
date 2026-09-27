#!/usr/bin/env python3
"""
Steal a Kaiju -- procedural audio pack generator.

Every sound in assets/audio/ is synthesized from scratch by this script
(oscillators, FM, filtered noise, Karplus-Strong, synthetic reverb...).
No samples, no downloads: the output is 100% original and royalty-free.

Deterministic: every sound uses its own fixed RNG seed (derived from its
name), so re-running produces identical files.

Usage:
    python3 generate_audio.py                 # generate everything + verify + README
    python3 generate_audio.py --only ui_click,alarm
    python3 generate_audio.py --verify-only

Requirements: numpy, scipy, soundfile (numba optional, only for speed).
"""
import argparse
import math
import os
import sys
import time
import zlib

import numpy as np
import soundfile as sf
from scipy import signal
from scipy.ndimage import maximum_filter1d, minimum_filter1d, uniform_filter1d

try:  # optional JIT for the per-sample filters
    from numba import njit
except Exception:  # pragma: no cover - pure-python fallback
    def njit(*args, **kwargs):
        if args and callable(args[0]):
            return args[0]
        return lambda f: f

SR = 44100
HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.normpath(os.path.join(HERE, "..", "..", "assets", "audio"))
CEIL_DB = -1.0
TWO_PI = 2.0 * np.pi

# --------------------------------------------------------------------------
# RNG (reset per sound for determinism)
# --------------------------------------------------------------------------
R = np.random.default_rng(0)


def set_seed(name):
    global R
    R = np.random.default_rng(zlib.crc32(name.encode("utf-8")))


# --------------------------------------------------------------------------
# Basic helpers
# --------------------------------------------------------------------------
def N(sec):
    return int(round(sec * SR))


def tt(n):
    return np.arange(n) / SR


def att(n, a):
    return np.minimum(1.0, tt(n) / max(a, 1e-5))


def ex(n, tau):
    return np.exp(-tt(n) / tau)


def gate(n, dur, rel):
    t = tt(n)
    return np.where(t < dur, 1.0, np.exp(-5.0 * (t - dur) / max(rel, 1e-4)))


def adsr(n, a, d, s, r, gate_t=None):
    t = tt(n)
    if gate_t is None:
        gate_t = max(0.0, n / SR - r)
    a = max(a, 1e-4)
    d = max(d, 1e-4)

    def lvl(q):
        return np.where(q < a, q / a, s + (1 - s) * np.exp(-(q - a) / d))

    e = lvl(t)
    g = float(lvl(np.array(gate_t)))
    return np.where(t < gate_t, e, g * np.exp(-5.0 * (t - gate_t) / max(r, 1e-4)))


def fix(x, n):
    if x.shape[-1] >= n:
        return x[..., :n]
    pad = [(0, 0)] * (x.ndim - 1) + [(0, n - x.shape[-1])]
    return np.pad(x, pad)


def place(buf, x, t0, g=1.0):
    i = N(t0)
    if i >= buf.shape[-1] or i < 0:
        return
    j = min(buf.shape[-1], i + x.shape[-1])
    buf[..., i:j] += g * x[..., : j - i]


def sat(x, drive=2.0):
    return np.tanh(x * drive) / np.tanh(drive)


def db(v):
    return 10 ** (v / 20.0)


def mtof(m):
    return 440.0 * 2 ** ((m - 69) / 12.0)


_PC = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def nm(s):
    """'C#5' / 'Bb4' / 'E6' -> midi"""
    pc = _PC[s[0].upper()]
    i = 1
    while i < len(s) and s[i] in "#b":
        pc += 1 if s[i] == "#" else -1
        i += 1
    return 12 * (int(s[i:]) + 1) + pc


def ramp_exp(n, v0, v1, t0, t1):
    """exponential interpolation v0->v1 between t0 and t1 (sec), held outside."""
    u = np.clip((tt(n) - t0) / max(t1 - t0, 1e-6), 0, 1)
    return v0 * (v1 / v0) ** u


def interp_log(n, pts):
    """piecewise exponential curve through [(t, v), ...]"""
    ts = np.array([p[0] for p in pts])
    vs = np.log(np.array([p[1] for p in pts], dtype=float))
    return np.exp(np.interp(tt(n), ts, vs))


def smooth_ctrl(x, fc):
    return lp(x - x[0], fc, 1) + x[0]


def interp_lin(n, pts):
    ts = np.array([p[0] for p in pts])
    vs = np.array([p[1] for p in pts], dtype=float)
    return np.interp(tt(n), ts, vs)


# memo for instrument renders (arrays are treated as read-only by callers)
_MEMO = {}


def memo(fn):
    def wrap(*args, **kw):
        key = (fn.__name__, args, tuple(sorted(kw.items())))
        v = _MEMO.get(key)
        if v is None:
            v = fn(*args, **kw)
            v.setflags(write=False)
            _MEMO[key] = v
        return v

    wrap.__name__ = fn.__name__
    return wrap


# --------------------------------------------------------------------------
# Noise
# --------------------------------------------------------------------------
def white(n):
    return R.standard_normal(n)


def brown(n):
    x = np.cumsum(R.standard_normal(n))
    x = hp(x, 15.0)
    return x / (np.std(x) + 1e-12)


def smooth_noise(n, rate):
    x = lp(R.standard_normal(n + 2000), rate, 2)[2000:]
    return x / (np.std(x) + 1e-12)


# --------------------------------------------------------------------------
# Filters
# --------------------------------------------------------------------------
def _sos(kind, fc, order=2):
    if isinstance(fc, (list, tuple)):
        fc = [min(max(f, 5.0), 0.49 * SR) for f in fc]
    else:
        fc = min(max(fc, 5.0), 0.49 * SR)
    return signal.butter(order, fc, btype=kind, fs=SR, output="sos")


def lp(x, fc, order=2):
    return signal.sosfilt(_sos("lowpass", fc, order), x, axis=-1)


def hp(x, fc, order=2):
    return signal.sosfilt(_sos("highpass", fc, order), x, axis=-1)


def bp(x, lo, hi, order=2):
    return signal.sosfilt(_sos("bandpass", [lo, hi], order), x, axis=-1)


@njit(cache=False)
def _svf(x, fc, q, mode, sr):
    n = x.shape[0]
    y = np.empty(n)
    ic1 = 0.0
    ic2 = 0.0
    k = 1.0 / q
    for i in range(n):
        g = math.tan(math.pi * fc[i] / sr)
        a1 = 1.0 / (1.0 + g * (g + k))
        a2 = g * a1
        a3 = g * a2
        v3 = x[i] - ic2
        v1 = a1 * ic1 + a2 * v3
        v2 = ic2 + a2 * ic1 + a3 * v3
        ic1 = 2.0 * v1 - ic1
        ic2 = 2.0 * v2 - ic2
        if mode == 0:
            y[i] = v2
        elif mode == 1:
            y[i] = k * v1
        else:
            y[i] = x[i] - k * v1 - v2
    return y


def svf(x, fc, q=0.707, mode="lp"):
    """Time-varying TPT state-variable filter (fc may be an array)."""
    x = np.ascontiguousarray(x, dtype=np.float64)
    fc = np.clip(np.broadcast_to(np.asarray(fc, dtype=np.float64), x.shape), 10.0, 0.45 * SR)
    fc = np.ascontiguousarray(fc)
    return _svf(x, fc, float(q), {"lp": 0, "bp": 1, "hp": 2}[mode], float(SR))


@njit(cache=False)
def _ks(excite, n, period, damp, blend):
    y = np.zeros(n)
    ip = int(period)
    fr = period - ip
    m = excite.shape[0]
    for i in range(n):
        x = excite[i] if i < m else 0.0
        if i >= ip + 2:
            d1 = (1.0 - fr) * y[i - ip] + fr * y[i - ip - 1]
            d2 = (1.0 - fr) * y[i - ip - 1] + fr * y[i - ip - 2]
            y[i] = x + damp * (blend * d1 + (1.0 - blend) * d2)
        else:
            y[i] = x
    return y


def ks_pluck(f, dur, bright=3500, damp=0.995, blend=0.5):
    """Karplus-Strong plucked string."""
    n = N(dur)
    period = SR / f - (1.0 - blend)
    ex_n = max(2, int(SR / f))
    e = lp(R.uniform(-1, 1, ex_n), bright, 1) * np.hanning(ex_n) ** 0.3
    y = _ks(np.ascontiguousarray(e), n, float(period), float(damp), float(blend))
    return y / (np.max(np.abs(y)) + 1e-9)


# --------------------------------------------------------------------------
# Oscillators (band-limited where it matters)
# --------------------------------------------------------------------------
def _farr(f, n):
    f = np.asarray(f, dtype=np.float64)
    if f.ndim == 0:
        return np.full(n, float(f))
    return fix(f, n) if len(f) >= n else np.concatenate([f, np.full(n - len(f), f[-1])])


def cycles(f, n):
    f = _farr(f, n)
    c = np.cumsum(f) / SR
    return c - c[0]


def osc_sine(f, n, ph=0.0):
    return np.sin(TWO_PI * (cycles(f, n) + ph))


def _blep(p, dt):
    y = np.zeros_like(p)
    m = p < dt
    t = p[m] / dt[m]
    y[m] = t + t - t * t - 1.0
    m = p > 1.0 - dt
    t = (p[m] - 1.0) / dt[m]
    y[m] = t * t + t + t + 1.0
    return y


def osc_saw(f, n, ph=0.0):
    fa = _farr(f, n)
    p = (cycles(fa, n) + ph) % 1.0
    dt = np.clip(np.abs(fa) / SR, 1e-9, 0.5)
    return 2.0 * p - 1.0 - _blep(p, dt)


def osc_pulse(f, n, duty=0.5, ph=0.0):
    fa = _farr(f, n)
    p1 = (cycles(fa, n) + ph) % 1.0
    p2 = (p1 + duty) % 1.0
    dt = np.clip(np.abs(fa) / SR, 1e-9, 0.5)
    s1 = 2.0 * p1 - 1.0 - _blep(p1, dt)
    s2 = 2.0 * p2 - 1.0 - _blep(p2, dt)
    return 0.5 * (s1 - s2)


def osc_tri(f, n, ph=0.0):
    p = (cycles(f, n) + ph) % 1.0
    return 2.0 * np.abs(2.0 * p - 1.0) - 1.0


def supersaw(f, n, voices=7, spread=0.2):
    fa = _farr(f, n)
    out = np.zeros(n)
    offs = np.linspace(-1, 1, voices) if voices > 1 else np.array([0.0])
    for o in offs:
        amp = 1.0 if abs(o) < 1e-9 else 0.8
        out += amp * osc_saw(fa * 2 ** (o * spread / 12.0), n, ph=R.random())
    return out / np.sqrt(voices)


def fm_bell(f, dur, dec=0.6, ratio=3.5, index=3.0):
    n = N(dur)
    t = tt(n)
    idx = index * min(1.0, 2200.0 / f) * np.exp(-t / (dec * 0.4))
    x = np.sin(TWO_PI * f * t + idx * np.sin(TWO_PI * f * ratio * t))
    return x * np.exp(-t / dec) * att(n, 0.001)


_BELL = [(1.0, 1.0, 1.0), (2.756, 0.5, 0.55), (5.404, 0.28, 0.3), (8.933, 0.14, 0.18), (13.34, 0.07, 0.1)]


def bell(f, dur, decay=0.6, bright=1.0):
    """glockenspiel-like bar (free-bar modal ratios)"""
    n = N(dur)
    t = tt(n)
    x = np.zeros(n)
    for r, a, d in _BELL:
        fr = f * r
        if fr > 17000:
            continue
        x += a * (bright if r > 1 else 1.0) * np.sin(TWO_PI * fr * t + R.random() * TWO_PI) * np.exp(-t / (decay * d))
    return x * att(n, 0.0008)


def coin_hit(f, dur=0.25, dec=0.1, bright=1.0):
    n = N(dur)
    t = tt(n)
    x = np.zeros(n)
    for r, a, d in [(1, 1, 1), (2.41, 0.55, 0.6), (3.87, 0.35, 0.4), (5.52, 0.2, 0.25)]:
        if f * r < 18500:
            x += a * np.sin(TWO_PI * f * r * t + R.random() * TWO_PI) * np.exp(-t / (dec * d))
    x *= att(n, 0.0006)
    x += 0.25 * bright * hp(white(n), 5000) * np.exp(-t / 0.001)
    return x


def chip_blip(f, dur, duty=0.5, dec=0.08):
    n = N(dur)
    t = tt(n)
    x = osc_pulse(f, n, duty) * np.exp(-t / dec) * att(n, 0.001)
    return lp(x, 9000, 2)


def pop(f0, f1, dur):
    n = N(dur)
    t = tt(n)
    f = f1 + (f0 - f1) * np.exp(-t / (dur * 0.18))
    x = osc_sine(f, n) * np.exp(-t / (dur * 0.3)) * att(n, 0.0008)
    x += 0.3 * hp(white(n), 3000) * np.exp(-t / 0.0012)
    return x


def boom(dur, f_end=42, f_start=150, dec=0.45, bright=5000, noise=1.0, drive=2.0):
    n = N(dur)
    t = tt(n)
    kick = osc_sine(f_end + f_start * np.exp(-t / 0.03) + 380 * np.exp(-t / 0.004), n)
    kick *= att(n, 0.001) * np.exp(-t / dec)
    blast = svf(brown(n) + 0.25 * white(n), 120 + bright * np.exp(-t / 0.06), 0.8)
    blast *= att(n, 0.0015) * np.exp(-t / (dec * 0.6)) * noise
    return sat(kick * 1.2 + blast * 0.8, drive)


def glitter(buf, t0, t1, count, amp=0.15, fmin=4500, fmax=11000, dec=0.035, fade=True):
    for _ in range(count):
        tg = t0 + (t1 - t0) * R.random()
        f = fmin * (fmax / fmin) ** R.random()
        m = N(dec * 6)
        tm = tt(m)
        a = amp * (0.35 + 0.65 * R.random())
        if fade:
            a *= max(0.0, 1.0 - (tg - t0) / (t1 - t0)) ** 0.8
        g = np.sin(TWO_PI * f * tm) * np.exp(-tm / dec) * att(m, 0.001)
        place(buf, g * a, tg)


def debris(buf, t0, t1, count, amp=0.25, fmin=700, fmax=4000, tau=0.5, skew=2.0):
    for _ in range(count):
        tg = t0 + (t1 - t0) * R.random() ** skew
        a = amp * (0.3 + 0.7 * R.random()) * np.exp(-(tg - t0) / tau)
        if R.random() < 0.5:
            f = fmin * (fmax / fmin) ** R.random()
            d = R.uniform(0.006, 0.025)
            m = N(d * 5)
            tm = tt(m)
            g = np.sin(TWO_PI * f * tm) * np.exp(-tm / d) + 0.5 * np.sin(TWO_PI * f * 1.73 * tm) * np.exp(-tm / (d * 0.6))
            g *= att(m, 0.0003)
        else:
            m = N(0.008)
            g = bp(white(m), fmin, min(fmax * 2.5, 16000)) * np.exp(-tt(m) / 0.0012)
            g /= np.max(np.abs(g)) + 1e-9
        place(buf, g * a, tg)


def thuds(buf, t0, t1, count, amp=0.35, tau=0.4, skew=1.5):
    for _ in range(count):
        tg = t0 + (t1 - t0) * R.random() ** skew
        m = N(0.12)
        g = lp(white(m), R.uniform(180, 600), 2) * np.exp(-tt(m) / R.uniform(0.012, 0.035)) * att(m, 0.001)
        g /= np.max(np.abs(g)) + 1e-9
        place(buf, g * amp * (0.4 + 0.6 * R.random()) * np.exp(-(tg - t0) / tau), tg)


def whoosh_noise(n, pts, q=1.4, env=None):
    fc = interp_log(n, pts)
    x = svf(white(n), fc, q, "bp") + 0.35 * svf(white(n), fc * 2.1, q * 1.3, "bp")
    return x if env is None else x * env


# --------------------------------------------------------------------------
# Reverb / delay
# --------------------------------------------------------------------------
_IR = {}


def make_ir(rt, ch=1, pre=0.012):
    key = (round(rt, 3), ch, round(pre, 4))
    if key in _IR:
        return _IR[key]
    rng = np.random.default_rng(1234 + int(rt * 1000) + ch * 7)
    n = N(rt * 1.15)
    t = tt(n)
    irs = []
    for c in range(ch):
        w = rng.standard_normal(n)
        lo = lp(w, 900)
        mid = bp(w, 900, 4000)
        hi = hp(w, 4000)
        ir = (lo * np.exp(-6.9 * t / (rt * 1.1)) + 0.8 * mid * np.exp(-6.9 * t / (rt * 0.8))
              + 0.45 * hi * np.exp(-6.9 * t / (rt * 0.4)))
        ir *= np.minimum(1.0, t / 0.01)
        for _ in range(12):  # early reflections
            pos = rng.uniform(0.003, 0.07)
            ir[N(pos)] += rng.choice([-1, 1]) * rng.uniform(1.5, 4.0) * (1 - pos / 0.09)
        ir = np.concatenate([np.zeros(N(pre)), ir])
        irs.append(ir / np.sqrt(np.sum(ir ** 2)))
    _IR[key] = irs
    return irs


def reverb(x, rt=1.0, mix=0.2, pre=0.01, hp_send=150):
    ir = make_ir(rt, 1, pre)[0]
    wet = signal.fftconvolve(hp(x, hp_send), ir)[: len(x)]
    return x + mix * wet


def reverb_circular(x, rt=0.6, mix=0.2):
    ir = make_ir(rt, 1)[0]
    L = len(x)
    irf = np.zeros(L)
    for i in range(0, len(ir), L):
        seg = ir[i:i + L]
        irf[: len(seg)] += seg
    wet = np.fft.irfft(np.fft.rfft(x) * np.fft.rfft(irf), L)
    return x + mix * wet


def echo(x, dt, fb=0.35, mix=0.3, taps=5, lpf=5000):
    out = x.copy()
    d = N(dt)
    cur = x
    for i in range(1, taps + 1):
        cur = lp(cur, lpf, 1) * fb
        if i * d >= len(x):
            break
        out[i * d:] += mix * cur[: len(x) - i * d]
    return out


def pingpong(x, dt, fb=0.4, mix=0.3, taps=6, lpf=4500):
    n = x.shape[1]
    out = x.copy()
    d = N(dt)
    cur = 0.5 * (x[0] + x[1])
    for i in range(1, taps + 1):
        cur = lp(cur, lpf, 1) * fb
        if i * d >= n:
            break
        out[i % 2, i * d:] += mix * cur[: n - i * d]
    return out


# --------------------------------------------------------------------------
# Dynamics / finalize
# --------------------------------------------------------------------------
def limiter(x, ceiling_db=CEIL_DB, look=0.005, smooth=0.012, wrap=False):
    thr = db(ceiling_db)
    a = np.abs(x) if x.ndim == 1 else np.max(np.abs(x), axis=0)
    mode = "wrap" if wrap else "nearest"
    la = max(1, N(look))
    pk = maximum_filter1d(a, size=2 * la + 1, mode=mode)
    g = np.minimum(1.0, thr / np.maximum(pk, 1e-12))
    s = max(1, N(smooth))
    g = minimum_filter1d(g, size=s, mode=mode)
    g = uniform_filter1d(g, size=s, mode=mode)
    g = uniform_filter1d(g, size=max(1, la), mode=mode)
    return x * g


def peak(x):
    return float(np.max(np.abs(x))) + 1e-12


def finalize_sfx(x, dur, push_db=3.0, fade_out=None, fade_in=0.0003):
    n = N(dur)
    x = fix(np.asarray(x, dtype=np.float64), n)
    x = hp(x, 20.0)
    x = x / peak(x) * db(push_db)
    x = limiter(x, CEIL_DB)
    x = x / peak(x) * db(CEIL_DB)
    fo = fade_out if fade_out is not None else min(0.03, 0.15 * dur)
    t = tt(n)
    x *= np.clip(t / fade_in, 0, 1)
    x *= np.clip((dur - t) / fo, 0, 1) ** 1.5
    return x / peak(x) * db(CEIL_DB)


def finalize_loop(x, push_db=3.0):
    """x is already circular (loop-length); only memoryless / wrap-aware ops."""
    x = x / peak(x) * db(push_db)
    x = limiter(x, CEIL_DB, wrap=True)
    return x / peak(x) * db(CEIL_DB)


def wrap_loop(x, L):
    out = x[..., :L].copy()
    tail = x[..., L:]
    for i in range(0, tail.shape[-1], L):
        seg = tail[..., i:i + L]
        out[..., : seg.shape[-1]] += seg
    return out


def set_level(b, target_db):
    mono = b if b.ndim == 1 else 0.5 * (b[0] + b[1])
    blk = N(0.1)
    nb = len(mono) // blk
    if nb == 0:
        return b
    r = np.sqrt(np.mean(mono[: nb * blk].reshape(nb, blk) ** 2, axis=1))
    if r.max() <= 0:
        return b
    act = r > r.max() * db(-30)
    rms = np.sqrt(np.mean(r[act] ** 2))
    return b * (db(target_db) / rms)


# ==========================================================================
# Drums (music + sfx)
# ==========================================================================
@memo
def dr_kick(var=0, dec=0.32, tone=48.0, punch=1.0):
    n = N(dec * 2.2 + 0.05)
    t = tt(n)
    f = tone + 120 * punch * np.exp(-t / 0.03) + 350 * np.exp(-t / 0.0035)
    x = osc_sine(f, n) * att(n, 0.0008) * np.exp(-t / dec)
    x += hp(white(n), 3000) * np.exp(-t / 0.0015) * 0.22
    return sat(x * 1.3, 1.6)


@memo
def dr_snare(var=0, dec=0.14, tone=190.0):
    n = N(0.45)
    t = tt(n)
    body = (osc_sine(tone * (1 + 0.25 * np.exp(-t / 0.008)), n) * np.exp(-t / 0.07) * 0.6
            + osc_sine(tone * 1.78, n) * np.exp(-t / 0.04) * 0.3)
    nz = bp(white(n), 1200, 9000) * np.exp(-t / dec) * 0.9 + hp(white(n), 5000) * np.exp(-t / (dec * 0.5)) * 0.3
    return sat((body + nz) * att(n, 0.0005), 1.5)


@memo
def dr_clap(var=0):
    n = N(0.4)
    t = tt(n)
    x = np.zeros(n)
    for k, o in enumerate([0.0, 0.009, 0.017]):
        b = bp(white(N(0.03)), 900, 3200) * np.exp(-tt(N(0.03)) / 0.004)
        place(x, b * (0.8 + 0.1 * k), o)
    tail = bp(white(n), 900, 5000) * np.exp(-np.maximum(t - 0.024, 0) / 0.11) * (t >= 0.024)
    return x + tail * 0.8


_HAT_F = [205.3, 304.4, 369.6, 522.7, 540.0, 800.0]


@memo
def dr_hat(var=0, open_=False):
    dec = 0.28 if open_ else 0.035
    n = N(dec * 5 + 0.02)
    t = tt(n)
    met = sum(np.sign(np.sin(TWO_PI * f * 1.6 * t + R.random() * 6)) for f in _HAT_F)
    x = hp(met, 7000, 2) * 0.5 + hp(white(n), 8000, 2) * 0.6
    return x * np.exp(-t / dec) * att(n, 0.0005)


@memo
def dr_crash(var=0, dec=1.4):
    n = N(dec * 3.2)
    t = tt(n)
    met = sum(np.sign(np.sin(TWO_PI * f * 2.7 * t + R.random() * 6)) for f in _HAT_F)
    x = hp(met, 4500, 2) * 0.35 + bp(white(n), 3500, 14000) * 0.8
    x = x * (np.exp(-t / dec) * 0.8 + 0.4 * np.exp(-t / 0.05)) * att(n, 0.002)
    return x


@memo
def dr_tom(freq=140.0, dec=0.25):
    n = N(dec * 3)
    t = tt(n)
    x = osc_sine(freq * (1 + 0.5 * np.exp(-t / 0.02)), n) * np.exp(-t / dec)
    x += lp(white(n), 2500) * np.exp(-t / 0.01) * 0.2
    return sat(x * att(n, 0.001) * 1.3, 1.4)


@memo
def dr_taiko(var=0, freq=62.0):
    n = N(1.2)
    t = tt(n)
    x = osc_sine(freq * (1 + 0.6 * np.exp(-t / 0.03)), n) * np.exp(-t / 0.45)
    x += 0.4 * osc_sine(freq * 1.52 * (1 + 0.4 * np.exp(-t / 0.03)), n) * np.exp(-t / 0.2)
    x += bp(white(n), 90, 900) * np.exp(-t / 0.07) * 0.8
    x += hp(white(n), 2500) * np.exp(-t / 0.004) * 0.25
    return sat(x * att(n, 0.0008) * 1.4, 1.8)


@memo
def dr_shaker(var=0):
    n = N(0.12)
    t = tt(n)
    return bp(white(n), 5000, 13000) * att(n, 0.008) * np.exp(-t / 0.035)


@memo
def dr_rim(var=0):
    n = N(0.1)
    t = tt(n)
    x = osc_sine(1700, n) * np.exp(-t / 0.012) + bp(white(n), 2000, 7000) * np.exp(-t / 0.004) * 0.7
    return x * att(n, 0.0004)


@memo
def ins_timpani(m, dur=1.2, vel=1.0):
    f = mtof(m)
    n = N(dur)
    t = tt(n)
    x = np.sin(TWO_PI * cycles(f * (1 + 0.08 * np.exp(-t / 0.05)), n)) * np.exp(-t / 0.7)
    x += 0.5 * np.sin(TWO_PI * 1.5 * f * t) * np.exp(-t / 0.35)
    x += 0.3 * np.sin(TWO_PI * 1.99 * f * t) * np.exp(-t / 0.25)
    x += lp(white(n), 1500) * np.exp(-t / 0.008) * 0.5
    return sat(x * att(n, 0.001) * vel, 1.3)


def rev_crash(dur):
    c = np.array(dr_crash(7, dec=dur * 1.1))
    x = fix(c, N(dur))[::-1].copy()
    return x * np.linspace(0, 1, len(x)) ** 1.5


def fx_riser(dur):
    n = N(dur)
    u = tt(n) / dur
    x = svf(white(n), 400 * 20 ** u, 2.0, "bp") * u ** 2 + 0.3 * hp(white(n), 6000) * u ** 3
    return x


# ==========================================================================
# Instruments (music)
# ==========================================================================
@memo
def ins_bass_funk(m, dur, vel=1.0):
    f = mtof(m)
    rel = 0.04
    n = N(dur + rel)
    t = tt(n)
    src = osc_saw(f, n) + 0.6 * osc_pulse(f * 1.003, n, 0.5)
    x = svf(src, 330 + 2000 * vel * np.exp(-t / 0.07), 1.6) + 0.9 * osc_sine(f, n)
    x *= adsr(n, 0.002, 0.12, 0.75, rel, dur)
    return sat(x, 2.0) * vel


@memo
def ins_bass_saw(m, dur, vel=1.0, bright=1.0):
    f = mtof(m)
    rel = 0.05
    n = N(dur + rel)
    t = tt(n)
    src = supersaw(f, n, 3, 0.12) + 0.5 * osc_pulse(f, n, 0.5)
    x = svf(src, 250 + 2600 * bright * vel * np.exp(-t / 0.09), 1.3) + 0.8 * osc_sine(f, n)
    x *= adsr(n, 0.002, 0.15, 0.8, rel, dur)
    return sat(x * 1.2, 2.2) * vel


@memo
def ins_bass_round(m, dur, vel=1.0):
    f = mtof(m)
    rel = 0.08
    n = N(dur + rel)
    x = osc_sine(f, n) + 0.35 * osc_tri(f, n) + 0.12 * osc_saw(f, n)
    x = lp(x, 900, 2) * adsr(n, 0.006, 0.3, 0.7, rel, dur)
    return sat(x, 1.3) * vel


@memo
def ins_bass_heavy(m, dur, vel=1.0):
    f = mtof(m)
    rel = 0.08
    n = N(dur + rel)
    t = tt(n)
    src = osc_saw(f, n) + osc_saw(f * 1.004, n) + 0.6 * osc_pulse(f * 0.5, n, 0.5)
    x = svf(src, 160 + 1400 * vel * np.exp(-t / 0.12), 1.2) + 1.1 * osc_sine(f, n)
    x *= adsr(n, 0.003, 0.25, 0.8, rel, dur)
    return sat(x * 1.3, 2.6) * vel


@memo
def ins_chip_lead(m, dur, vel=1.0, duty=0.25):
    f = mtof(m)
    rel = 0.08
    n = N(dur + rel)
    t = tt(n)
    vib = 1 + 0.007 * np.sin(TWO_PI * 5.8 * t) * np.clip((t - 0.15) / 0.2, 0, 1)
    x = osc_pulse(f * vib, n, duty) + 0.35 * osc_pulse(f * vib * 1.005, n, 0.5)
    x = lp(x, 7500, 2) * adsr(n, 0.003, 0.12, 0.7, rel, dur)
    return x * vel


@memo
def ins_saw_lead(m, dur, vel=1.0):
    f = mtof(m)
    rel = 0.12
    n = N(dur + rel)
    t = tt(n)
    vib = 1 + 0.005 * np.sin(TWO_PI * 5.5 * t) * np.clip((t - 0.2) / 0.25, 0, 1)
    src = supersaw(f * vib, n, 5, 0.14) + 0.3 * osc_pulse(f * vib * 0.5, n, 0.5)
    x = svf(src, 1800 + 3500 * vel * np.exp(-t / 0.15), 1.1) * adsr(n, 0.005, 0.2, 0.75, rel, dur)
    return sat(x, 1.4) * vel


@memo
def ins_pluck(m, dur, vel=1.0, bright=5000, dec=0.12, wave="pulse"):
    f = mtof(m)
    n = N(dur + 0.1)
    t = tt(n)
    if wave == "pulse":
        src = osc_pulse(f, n, 0.5)
    else:
        src = osc_saw(f, n) + 0.5 * osc_saw(f * 1.006, n)
    x = svf(src, 500 + bright * vel * np.exp(-t / (dec * 0.5)), 1.2)
    return x * np.exp(-t / dec) * att(n, 0.0015) * gate(n, dur, 0.04) * vel


@memo
def ins_pad(notes, dur, cutoff=2200, attack=0.25, rel=0.6, voices=5, spread=0.22):
    n = N(dur + rel)
    out = np.zeros((2, n))
    for ch in range(2):
        s = np.zeros(n)
        for m in notes:
            s += supersaw(mtof(m), n, voices, spread)
        out[ch] = lp(s, cutoff, 2)
    return out * adsr(n, attack, 0.6, 0.85, rel, dur) / len(notes) ** 0.5


@memo
def ins_stab(notes, dur, vel=1.0, bright=5000):
    n = N(dur + 0.15)
    t = tt(n)
    s = np.zeros(n)
    for m in notes:
        s += 0.5 * osc_pulse(mtof(m), n, 0.5) + 0.6 * osc_saw(mtof(m) * 1.003, n)
    x = svf(s, 600 + bright * np.exp(-t / 0.05), 1.3) * np.exp(-t / 0.12) * att(n, 0.002) * gate(n, dur, 0.06)
    return x * vel / len(notes) ** 0.5


@memo
def ins_bell(m, dur, vel=1.0, dec=0.8):
    f = mtof(m)
    d = max(dur, dec * 3.0)
    x = bell(f, d, decay=dec) * 0.6 + fm_bell(f, d, dec=dec * 0.8, ratio=3.5, index=1.5) * 0.5
    return x * vel


@memo
def ins_marimba(m, dur, vel=1.0):
    f = mtof(m)
    n = N(max(dur, 0.7))
    t = tt(n)
    x = np.sin(TWO_PI * f * t) * np.exp(-t / 0.35)
    x += 0.35 * np.sin(TWO_PI * 3.93 * f * t) * np.exp(-t / 0.06)
    if f * 9.2 < 18000:
        x += 0.12 * np.sin(TWO_PI * 9.2 * f * t) * np.exp(-t / 0.02)
    x += lp(white(n), 3000) * np.exp(-t / 0.002) * 0.15
    return x * att(n, 0.0008) * vel


@memo
def ins_ep(m, dur, vel=1.0):
    """FM electric piano"""
    f = mtof(m)
    rel = 0.25
    n = N(dur + rel)
    t = tt(n)
    idx = (1.2 * vel + 0.3) * np.exp(-t / 0.35) + 0.25
    x = np.sin(TWO_PI * f * t + idx * np.sin(TWO_PI * f * t)) * np.exp(-t / 1.6)
    if f * 14 < 18000:
        x += np.sin(TWO_PI * f * 14 * t) * np.exp(-t / 0.025) * 0.12 * vel
    return x * att(n, 0.002) * gate(n, dur, rel) * vel


@memo
def ins_brass(m, dur, vel=1.0, bright=1.0):
    f = mtof(m)
    rel = 0.18
    n = N(dur + rel)
    t = tt(n)
    scoop = 2 ** ((-0.4 * np.exp(-t / 0.04)) / 12)
    vib = 1 + 0.004 * np.sin(TWO_PI * 5.3 * t + R.random() * 6) * np.clip((t - 0.25) / 0.3, 0, 1)
    fr = f * scoop * vib
    src = supersaw(fr, n, 4, 0.12) + 0.3 * osc_pulse(fr, n, 0.3)
    cut = 380 + bright * vel * (2800 * np.minimum(1, t / 0.06) - 1100 * np.clip((t - 0.06) / 0.3, 0, 1))
    x = svf(src, cut, 0.9) * adsr(n, 0.045, 0.3, 0.8, rel, dur)
    return sat(x * 1.3, 1.6) * vel


@memo
def ins_strings_stac(m, dur, vel=1.0):
    f = mtof(m)
    n = N(dur + 0.08)
    t = tt(n)
    x = svf(supersaw(f, n, 3, 0.12), 600 + 2200 * vel * np.exp(-t / 0.06), 0.8)
    return x * adsr(n, 0.004, 0.07, 0.35, 0.06, dur) * vel


VOWELS = {
    "a": [(800, 80, 1.0), (1150, 90, 0.5), (2900, 120, 0.25), (3900, 130, 0.1)],
    "aw": [(620, 80, 1.0), (950, 90, 0.45), (2700, 120, 0.18)],
    "o": [(450, 70, 1.0), (800, 80, 0.3), (2830, 100, 0.1)],
    "u": [(325, 50, 1.0), (700, 60, 0.2), (2530, 170, 0.05)],
    "e": [(400, 60, 1.0), (1600, 80, 0.35), (2700, 120, 0.2)],
}


def formant_static(x, vowel, bw_mul=1.5):
    y = np.zeros_like(x)
    for fc, bw, a in VOWELS[vowel]:
        b = bw * bw_mul
        y += a * bp(x, fc - b, fc + b, 2)
    return y


def formant_morph(x, pts, bw_mul=1.6):
    """pts = [(t, vowel), ...]; time-varying formant bank"""
    n = len(x)
    y = np.zeros(n)
    nf = min(len(VOWELS[v]) for _, v in pts)
    for k in range(nf):
        fcs = interp_log(n, [(t, VOWELS[v][k][0]) for t, v in pts])
        amps = interp_lin(n, [(t, VOWELS[v][k][2]) for t, v in pts])
        bw = np.mean([VOWELS[v][k][1] for _, v in pts]) * bw_mul
        q = float(np.clip(np.mean(fcs) / (2 * bw), 1.5, 12))
        y += amps * svf(x, fcs, q, "bp")
    return y


@memo
def ins_choir(m, dur, vel=1.0, vowel="a"):
    f = mtof(m)
    rel = 0.4
    n = N(dur + rel)
    t = tt(n)
    src = np.zeros(n)
    for k in range(4):
        det = 2 ** ((R.uniform(-12, 12)) / 1200)
        vib = 1 + 0.006 * np.sin(TWO_PI * R.uniform(4.6, 5.6) * t + R.random() * 6)
        src += osc_saw(f * det * vib, n, ph=R.random())
    x = formant_static(src, vowel) + 0.15 * lp(src, 700)
    return x * adsr(n, 0.25, 0.3, 0.9, rel, dur) * vel


# ==========================================================================
# SFX
# ==========================================================================
def sfx_ui_click(d):
    n = N(d)
    t = tt(n)
    f = 650 + 1500 * np.exp(-t / 0.010)
    x = osc_sine(f, n) * np.exp(-t / 0.022) * att(n, 0.0006)
    x += 0.3 * osc_sine(f * 2.01, n) * np.exp(-t / 0.008)
    x += 0.5 * hp(white(n), 2500) * np.exp(-t / 0.0015)
    x += 0.35 * osc_sine(180 * (1 + np.exp(-t / 0.005)), n) * np.exp(-t / 0.012)
    return x


def sfx_ui_hover(d):
    n = N(d)
    t = tt(n)
    f = 1900 + 500 * (1 - np.exp(-t / 0.01))
    x = osc_sine(f, n) * np.exp(-t / 0.012) * att(n, 0.002)
    x += 0.25 * osc_sine(f * 2, n) * np.exp(-t / 0.006)
    x += 0.12 * hp(white(n), 6000) * np.exp(-t / 0.002)
    return x


def sfx_ui_open(d):
    n = N(d)
    t = tt(n)
    tp = 0.17
    u = np.clip(t / tp, 0, 1)
    post = np.where(t < tp, 1.0, np.exp(-(t - tp) / 0.02))
    x = svf(white(n), 500 * 12 ** u, 1.8, "bp") * u ** 2 * post * 0.6
    tf = 380 * 3.2 ** u
    x += (osc_sine(tf, n) + 0.3 * osc_tri(tf * 2, n)) * u * np.where(t < tp, 1, np.exp(-(t - tp) / 0.015)) * 0.35
    place(x, pop(700, 1500, 0.07) * 0.9, tp - 0.005)
    return reverb(x, 0.35, 0.15)


def sfx_ui_close(d):
    n = N(d)
    t = tt(n)
    u = np.clip(t / 0.15, 0, 1)
    x = svf(white(n), 5000 * (400 / 5000) ** u, 1.8, "bp") * att(n, 0.004) * np.exp(-t / 0.06) * 0.6
    tf = 1100 * 0.32 ** np.clip(t / 0.13, 0, 1)
    x += (osc_sine(tf, n) + 0.25 * osc_tri(tf * 2, n)) * att(n, 0.002) * np.exp(-t / 0.07) * 0.5
    m = N(0.06)
    tm = tt(m)
    place(x, osc_sine(150 + 110 * np.exp(-tm / 0.01), m) * np.exp(-tm / 0.02) * 0.5, 0.11)
    return reverb(x, 0.3, 0.12)


def sfx_ui_error(d):
    n = N(d)
    x = np.zeros(n)
    for t0, f1, f2 in [(0.0, 155, 147), (0.15, 139, 131)]:
        m = N(0.12)
        src = osc_pulse(f1, m, 0.35) + 0.8 * osc_saw(f2, m) + 0.25 * osc_sine(f1 / 2, m)
        src = sat(lp(src, 1400, 2) * 1.2, 2.5)
        place(x, src * adsr(m, 0.004, 0.05, 0.8, 0.03, 0.09), t0)
        c = N(0.01)
        place(x, hp(white(c), 1500) * np.exp(-tt(c) / 0.0015) * 0.4, t0)
    return x


def sfx_ui_tab(d):
    n = N(d)
    t = tt(n)
    f0 = 980 * (1 + 0.06 * np.exp(-t / 0.005))
    x = np.zeros(n)
    for r, a, dd in [(1, 1, 0.035), (2.43, 0.45, 0.018), (4.1, 0.2, 0.009)]:
        x += a * osc_sine(f0 * r, n) * np.exp(-t / dd)
    x *= att(n, 0.0005)
    x += 0.35 * hp(white(n), 4000) * np.exp(-t / 0.001)
    return x


def sfx_coin_tick(d):
    n = N(d)
    x = coin_hit(3200, d, dec=0.02) + 0.45 * coin_hit(4790, d, dec=0.012)
    return x


def sfx_cash_collect(d):
    n = N(d)
    x = np.zeros(n)
    notes = [79, 81, 84, 86, 88, 91, 93, 96, 98, 100]
    for i, m in enumerate(notes):
        ti = 0.035 * i * (1 - 0.02 * i) + R.uniform(0, 0.008)
        f = mtof(m) * (1 + 0.004 * R.standard_normal())
        place(x, coin_hit(f, 0.3, 0.07 + 0.03 * R.random()) * (0.6 + 0.4 * R.random()), ti)
    place(x, chip_blip(mtof(83), 0.08, 0.5, 0.03) * 0.3, 0.0)
    place(x, chip_blip(mtof(88), 0.2, 0.5, 0.07) * 0.3, 0.055)
    glitter(x, 0.05, 0.55, 30, amp=0.12, fmin=6000, fmax=12000, dec=0.02)
    return reverb(x, 0.7, 0.22)


def sfx_purchase(d):
    n = N(d)
    x = np.zeros(n)
    for k in range(7):  # mechanical "cha" rattle
        m = N(0.012)
        b = bp(white(m), 2500, 7000) * np.exp(-tt(m) / 0.0015) * (1 - k / 9)
        place(x, b, 0.012 * k + R.uniform(0, 0.004))
    m = N(0.2)
    tm = tt(m)
    place(x, osc_sine(140 * (1 + 0.5 * np.exp(-tm / 0.01)), m) * np.exp(-tm / 0.05) * 0.6, 0.0)
    m = N(0.09)
    place(x, whoosh_noise(m, [(0, 800), (0.09, 3000)], 1.5, np.sin(np.pi * tt(m) / 0.09)) * 0.25, 0.0)
    tb = 0.085  # "ching"
    ch = bell(1318.5, 0.42, 0.35) * 0.8 + bell(1661.2, 0.42, 0.3) * 0.6 + bell(2637.0, 0.42, 0.25) * 0.35
    ch += fm_bell(1318.5, 0.42, 0.3, 3.01, 1.2) * 0.3
    place(x, ch, tb)
    m = N(0.3)
    place(x, hp(white(m), 7000) * np.exp(-tt(m) / 0.08) * 0.15, tb)
    for k, mm in enumerate([100, 104, 107]):
        place(x, coin_hit(mtof(mm), 0.25, 0.08) * 0.3, tb + 0.04 + 0.05 * k)
    return reverb(x, 0.6, 0.2)


def sfx_sell(d):
    n = N(d)
    x = np.zeros(n)
    m = N(0.12)
    place(x, whoosh_noise(m, [(0, 800), (0.12, 3000)], 1.5, np.sin(np.pi * tt(m) / 0.12) ** 2) * 0.3, 0.0)
    place(x, pop(250, 600, 0.08) * 0.6, 0.06)
    place(x, chip_blip(mtof(91), 0.12, 0.25, 0.04) * 0.35 + coin_hit(mtof(91), 0.12, 0.06) * 0.6, 0.07)
    place(x, chip_blip(mtof(96), 0.25, 0.25, 0.08) * 0.35 + coin_hit(mtof(96), 0.25, 0.1) * 0.7, 0.15)
    glitter(x, 0.15, 0.35, 10, amp=0.12, fmin=6000, fmax=12000, dec=0.02)
    return reverb(x, 0.5, 0.18)


def sfx_meteor_whistle(d):
    n = N(d)
    t = tt(n)
    u = t / d
    f = 2400 * (330 / 2400) ** (u ** 1.25)
    f *= 1 + 0.004 * np.sin(TWO_PI * 6.5 * t)
    env = 0.15 + 0.85 * u ** 0.8
    whistle = (osc_sine(f, n) + 0.18 * osc_sine(2 * f, n)) * env
    wind = (svf(white(n), f * 1.02, 10, "bp") * 1.2 + 0.5 * svf(white(n), f * 0.5, 3, "bp")) * env
    roar = svf(brown(n), 300 + 1500 * u ** 2, 0.7, "lp") * u ** 1.6 * 1.2
    rumble = lp(brown(n), 120, 2) * u ** 2.2 * 1.5 + osc_sine(45 + 10 * u, n) * u ** 3 * 0.4
    crack = np.zeros(n)
    for _ in range(140):
        tg = d * R.random() ** 0.6
        m = N(0.004)
        g = hp(white(m), 1500) * np.exp(-tt(m) / 0.0006)
        place(crack, g * 0.3 * (tg / d) * R.random(), tg)
    x = whistle * 0.45 + wind * 0.35 + roar * 0.5 + rumble * 0.6 + crack
    return reverb(sat(x, 1.3), 1.0, 0.15)


def sfx_meteor_impact(d):
    n = N(d)
    t = tt(n)
    kick = osc_sine(42 + 140 * np.exp(-t / 0.03) + 400 * np.exp(-t / 0.004), n) * att(n, 0.001) * np.exp(-t / 0.45)
    sub = osc_sine(31, n) * att(n, 0.01) * np.exp(-t / 0.7) * 0.6
    blast = svf(brown(n) + 0.3 * white(n), 150 + 7000 * np.exp(-t / 0.07), 0.8) * att(n, 0.0015) * np.exp(-t / 0.3) * 1.2
    crack = hp(white(n), 1500) * np.exp(-t / 0.018) * 1.0
    crunch = bp(white(n), 300, 2200) * att(n, 0.002) * np.exp(-t / 0.12) * 0.8
    x = sat(kick * 1.2 + sub + blast, 2.2) + crack + crunch
    debris(x, 0.03, 1.25, 110, amp=0.3, fmin=800, fmax=4500, tau=0.45, skew=2.2)
    thuds(x, 0.05, 0.8, 10, amp=0.35, tau=0.4)
    return reverb(x, 1.6, 0.22)


def sfx_meteor_rare_alarm(d):
    n = N(d)
    t = tt(n)
    x = np.zeros(n)
    run = [83, 88, 92, 95]
    for r0 in (0.0, 0.36):
        for i, m in enumerate(run):
            f = mtof(m + (5 if r0 > 0 else 0))
            place(x, fm_bell(f, 0.5, 0.3, 3.5, 2.0) * 0.5, r0 + 0.06 * i)
            place(x, chip_blip(f, 0.2, 0.25, 0.05) * 0.25, r0 + 0.06 * i)
    place(x, fm_bell(mtof(100), 0.5, 0.45, 3.5, 2.0) * 0.6 + bell(mtof(100), 0.5, 0.5) * 0.4, 0.72)
    shim = sum(osc_sine(mtof(m), n) for m in (88, 95, 100))
    shim *= (1 - 0.5 * (0.5 + 0.5 * np.sin(TWO_PI * 13 * t))) * np.clip(t / 0.5, 0, 1) * np.clip((1.15 - t) / 0.3, 0, 1)
    x += shim * 0.07
    glitter(x, 0.1, 1.1, 40, amp=0.1, fmin=5000, fmax=12000, dec=0.03)
    return reverb(x, 1.0, 0.3)


def knock(f0, amp=1.0):
    m = N(0.12)
    tm = tt(m)
    x = np.zeros(m)
    for r, a, dd in [(1, 1, 0.045), (1.58, 0.6, 0.03), (2.31, 0.45, 0.022), (3.1, 0.3, 0.014), (4.4, 0.2, 0.009)]:
        x += a * np.sin(TWO_PI * f0 * r * tm + R.random() * 6) * np.exp(-tm / dd)
    x += bp(white(m), 800, 4000) * np.exp(-tm / 0.0015) * 0.6
    x += osc_sine(170, m) * np.exp(-tm / 0.025) * 0.5
    return x * att(m, 0.0005) * amp


def sfx_egg_wobble(d):
    x = np.zeros(N(d))
    place(x, knock(610), 0.0)
    place(x, knock(690, 0.8), 0.13)
    place(x, knock(560, 0.35), 0.215)
    return reverb(x, 0.3, 0.1)


def crack_grain(tau, hpf, amp):
    m = N(max(tau * 8, 0.004))
    g = hp(white(m), hpf) * np.exp(-tt(m) / tau) * att(m, 0.0002)
    return g / (peak(g)) * amp


def shell_modes(f0, amp, dec=0.04):
    m = N(dec * 5)
    tm = tt(m)
    x = np.zeros(m)
    for r, a in [(1, 1), (1.47, 0.6), (2.09, 0.4), (2.9, 0.25)]:
        x += a * np.sin(TWO_PI * f0 * r * tm + R.random() * 6) * np.exp(-tm / (dec / r ** 0.5))
    return x * amp


def sfx_egg_crack(d):
    n = N(d)
    t = tt(n)
    x = np.zeros(n)
    place(x, crack_grain(0.006, 1200, 1.0), 0.02)
    place(x, shell_modes(1350, 0.5), 0.02)
    for _ in range(16):
        place(x, crack_grain(R.uniform(0.0005, 0.002), R.uniform(2000, 6000), 0.5 * R.random()),
              0.03 + 0.28 * R.random() ** 1.5)
    crunch = bp(white(n), 500, 3000) * np.abs(smooth_noise(n, 60)) * 0.4
    crunch *= np.clip((t - 0.02) / 0.01, 0, 1) * np.exp(-np.maximum(t - 0.02, 0) / 0.08)
    x += crunch
    place(x, crack_grain(0.004, 1500, 0.7), 0.24)
    place(x, shell_modes(1600, 0.35), 0.24)
    for _ in range(6):
        place(x, crack_grain(R.uniform(0.0005, 0.0015), R.uniform(2500, 6000), 0.3 * R.random()),
              0.25 + 0.12 * R.random())
    return reverb(x, 0.4, 0.12)


def sfx_hatch_common(d):
    n = N(d)
    t = tt(n)
    x = np.zeros(n)
    place(x, pop(260, 1000, 0.09), 0.0)
    m = N(0.1)
    place(x, lp(white(m), 2500) * np.exp(-tt(m) / 0.02) * 0.4, 0.0)
    for i, mm in enumerate([84, 88, 91, 96]):
        last = i == 3
        f = mtof(mm)
        v = chip_blip(f, 0.6 if last else 0.35, 0.25, 0.3 if last else 0.12) * 0.5
        v = v + fix(bell(f, 0.6 if last else 0.35, 0.4 if last else 0.25), len(v)) * 0.35
        place(x, v, 0.09 + 0.06 * i)
    glitter(x, 0.25, 0.9, 20, amp=0.1)
    return reverb(x, 0.8, 0.22)


def sfx_hatch_epic(d):
    n = N(d)
    t = tt(n)
    x = np.zeros(n)
    place(x, pop(200, 800, 0.12), 0.0)
    m = N(0.5)
    tm = tt(m)
    place(x, osc_sine(45 + 45 * np.exp(-tm / 0.05), m) * np.exp(-tm / 0.25) * 0.7, 0.0)
    for i, mm in enumerate([74, 78, 81, 86, 90, 93, 98]):
        v = np.array(ins_pluck(mm, 0.12, 1.0, 6000, 0.14, "saw")) * 0.45
        v = v + fix(bell(mtof(mm), 0.3, 0.25), len(v)) * 0.3
        place(x, v, 0.08 + 0.065 * i)
    place(x, fx_riser(0.45) * 0.25, 0.1)
    chord = [62, 66, 69, 74, 78]
    m = N(1.25)
    tm = tt(m)
    s = sum(supersaw(mtof(k), m, 5, 0.2) for k in chord)
    s = svf(s, 1500 + 5000 * np.exp(-tm / 0.2), 0.9) * att(m, 0.01) * np.exp(-tm / 0.5) * 0.25
    place(x, s, 0.55)
    for k in [86, 90, 93, 98]:
        place(x, bell(mtof(k), 1.2, 0.8) * 0.18, 0.55)
    place(x, boom(0.8, 40, 60, 0.35, 1500, 0.4, 1.5) * 0.6, 0.55)
    glitter(x, 0.5, 1.6, 45, amp=0.12)
    return reverb(x, 1.4, 0.3)


def brass_chord(buf, notes, t0, dur, vel=1.0, bright=1.0, g=1.0):
    for m in notes:
        place(buf, np.array(ins_brass(m, dur, vel, bright)) * g / len(notes) ** 0.5, t0)


def sfx_hatch_legendary(d):
    n = N(d)
    x = np.zeros(n)
    for k in range(3):
        brass_chord(x, [55, 62, 67], 0.12 * k, 0.09, 0.85)
        place(x, np.array(dr_snare(k)) * 0.35, 0.12 * k)
    brass_chord(x, [48, 55, 60, 64, 67, 72, 76], 0.38, 0.85, 1.0, 1.1)
    brass_chord(x, [48, 53, 60, 65, 69, 72, 77], 1.26, 0.2, 0.95, 1.1)
    brass_chord(x, [43, 55, 59, 62, 67, 71, 74], 1.49, 0.2, 0.95, 1.1)
    brass_chord(x, [36, 48, 55, 60, 64, 67, 72, 76, 79], 1.72, 0.75, 1.0, 1.2, 1.2)
    place(x, np.array(ins_timpani(36, 1.2)) * 0.8, 0.38)
    place(x, np.array(ins_timpani(36, 1.2)) * 0.9, 1.72)
    place(x, rev_crash(0.38) * 0.3, 0.0)
    place(x, np.array(dr_crash(1, 1.2)) * 0.35, 0.38)
    place(x, np.array(dr_crash(2, 1.4)) * 0.4, 1.72)
    for k, mm in enumerate([84, 88, 91, 96]):
        place(x, bell(mtof(mm), 1.2, 0.9) * 0.15, 1.72 + 0.04 * k)
    glitter(x, 0.4, 2.8, 60, amp=0.07)
    return reverb(x, 1.4, 0.25)


def sfx_hatch_secret(d):
    n = N(d)
    t = tt(n)
    pre = np.zeros(n)
    m = N(2.05)
    tm = tt(m)
    u = tm / 2.0
    drone = supersaw(mtof(38), m, 5, 0.2) + supersaw(mtof(39), m, 5, 0.2) + 0.6 * supersaw(mtof(26), m, 3, 0.1)
    drone = svf(drone, (200 + 700 * u ** 1.5) * (1 + 0.3 * np.sin(TWO_PI * 0.8 * tm)), 2.0) * (0.25 + 0.75 * u)
    place(pre, drone * 0.35, 0.0)
    for tb, mm in [(0.15, 86), (0.6, 80), (1.05, 84), (1.4, 90)]:
        place(pre, fm_bell(mtof(mm), 1.2, 0.8, 1.41, 2.0) * 0.35, tb)
    for a, b in [(0.3, 0.45), (0.95, 1.08), (1.5, 1.6)]:
        for tb, g in [(a, 0.8), (b, 0.55)]:
            k = N(0.3)
            tk = tt(k)
            place(pre, osc_sine(55 * (1 + 0.4 * np.exp(-tk / 0.02)), k) * np.exp(-tk / 0.09) * g, tb)
    k = N(0.9)
    tk = tt(k)
    sf_ = 180 * (1400 / 180) ** (tk / 0.9)
    trem = 1 - 0.5 * (0.5 + 0.5 * np.sin(TWO_PI * cycles(6 + 30 * tk / 0.9, k)))
    place(pre, (osc_sine(sf_, k) + 0.3 * osc_saw(sf_, k)) * (tk / 0.9) ** 2 * trem * 0.25, 1.1)
    place(pre, rev_crash(1.0) * 0.35, 1.0)
    place(pre, fx_riser(1.0) * 0.2, 1.0)
    pre = reverb(pre, 1.8, 0.35)
    cut = N(2.0)
    fl = N(0.015)
    pre[cut - fl:cut] *= np.linspace(1, 0, fl)
    pre[cut:] = 0
    post = np.zeros(n)
    tr = 2.12
    place(post, boom(1.4, 40, 170, 0.5, 8000, 1.1, 2.2), tr)
    m = N(1.4)
    tm = tt(m)
    chord = [52, 59, 64, 68, 71, 76]
    s = sum(supersaw(mtof(k), m, 5, 0.22) for k in chord)
    s = svf(s, 900 + 8000 * np.exp(-tm / 0.25), 0.9) * att(m, 0.004) * np.exp(-tm / 0.6) * 0.3
    place(post, s, tr)
    for i, mm in enumerate([88, 92, 95, 100, 104]):
        place(post, bell(mtof(mm), 1.0, 0.7) * 0.22, tr + 0.03 + 0.05 * i)
    place(post, np.array(dr_crash(3, 1.3)) * 0.4, tr)
    glitter(post, tr + 0.03, 3.35, 70, amp=0.12)
    post = reverb(post, 1.8, 0.3)
    return pre + post


def sfx_stage_up(d):
    n = N(d)
    t = tt(n)
    u = np.clip(t / 0.9, 0, 1)
    f = 140 * (900 / 140) ** (u ** 1.2)
    trem = 1 - 0.35 * (0.5 + 0.5 * np.sin(TWO_PI * cycles(6 + 18 * u, n)))
    sw = svf(supersaw(f, n, 3, 0.18), 400 * 20 ** u, 2.5) * (0.3 + 0.7 * u) * trem
    sw *= np.where(t < 0.92, 1.0, np.exp(-(t - 0.92) / 0.05))
    x = sw * 0.45
    for i, mm in enumerate([72, 76, 79, 84, 88, 91, 96]):
        place(x, chip_blip(mtof(mm), 0.12, 0.5, 0.05) * 0.3, 0.11 * i)
    x += hp(white(n), 3000) * u ** 2 * (t < 0.9) * 0.12
    for mm in [84, 88, 91, 96]:
        place(x, bell(mtof(mm), 0.35, 0.35) * 0.22, 0.9)
    place(x, pop(500, 1200, 0.08) * 0.5, 0.9)
    glitter(x, 0.9, 1.15, 20, amp=0.1)
    return reverb(x, 0.8, 0.2)


def growl_src(f0, n, am_rate, am_depth, sub=0.0, detune_voices=1):
    t = tt(n)
    if detune_voices > 1:
        src = supersaw(f0, n, detune_voices, 0.25)
    else:
        src = osc_saw(f0, n) + 0.4 * osc_pulse(f0 * 1.01, n, 0.4)
    if sub:
        src += sub * osc_saw(f0 * 0.5, n)
    rate = am_rate * (1 + 0.2 * smooth_noise(n, 8))
    am = 1 - am_depth * (0.5 + 0.5 * np.sin(TWO_PI * cycles(rate, n)))
    return src * am, am


def sfx_roar_small(d):
    n = N(d)
    t = tt(n)
    f0 = smooth_ctrl(interp_lin(n, [(0, 230), (0.12, 340), (0.35, 290), (0.8, 170)]), 20)
    f0 = np.maximum(f0, 150) * (1 + 0.03 * smooth_noise(n, 30))
    src, am = growl_src(f0, n, 34, 0.45)
    pts = [(0, "e"), (0.15, "a"), (0.5, "aw"), (0.8, "o")]
    x = formant_morph(src, pts, 1.4) + 0.15 * formant_morph(white(n), pts, 2.0) * am
    x = sat(x * adsr(n, 0.03, 0.3, 0.9, 0.22, 0.55) * 1.5, 2.0)
    return reverb(x, 0.5, 0.15)


def sfx_roar_big(d):
    n = N(d)
    t = tt(n)
    f0 = smooth_ctrl(interp_lin(n, [(0, 52), (0.3, 88), (1.1, 76), (2.0, 42)]), 12)
    f0 = np.maximum(f0, 38) * (1 + 0.05 * smooth_noise(n, 25))
    src, am = growl_src(f0, n, 26, 0.6, sub=0.7, detune_voices=3)
    exc = src + white(n) * 0.5 * (0.6 + 0.4 * am)
    pts = [(0, "a"), (0.8, "aw"), (1.4, "o"), (2.0, "u")]
    x = formant_morph(exc, pts, 1.4) * 1.5 + 0.5 * lp(exc, 400)
    throat = osc_pulse(f0 * 0.5, n, 0.2) * am
    x += 0.6 * formant_morph(throat, [(0, "aw"), (2.0, "u")], 1.3)
    env = np.clip(t / 0.18, 0, 1) ** 1.5 * (1 - 0.15 * np.clip((t - 0.3) / 1.0, 0, 1))
    env *= np.where(t < 1.4, 1.0, np.exp(-(t - 1.4) / 0.18))
    x = lp(sat(x * env * 2.0, 4.0), 7000, 2)
    x += osc_sine(f0 * 0.5, n) * env * 0.5
    return reverb(x, 1.8, 0.28)


def sfx_steal_grab(d):
    n = N(d)
    x = np.zeros(n)
    place(x, lp(ks_pluck(mtof(55), 0.3, 3000, 0.994), 4000) * 0.9, 0.0)
    place(x, lp(ks_pluck(mtof(62), 0.3, 3500, 0.994), 4500) * 0.8, 0.085)
    place(x, pop(300, 700, 0.07) * 0.35, 0.085)
    m = N(0.18)
    place(x, whoosh_noise(m, [(0, 1200), (0.18, 5000)], 1.6, np.sin(np.pi * tt(m) / 0.18) ** 2) * 0.25, 0.02)
    return reverb(x, 0.4, 0.12)


def sfx_bonk(d):
    n = N(d)
    t = tt(n)
    x = np.zeros(n)
    f0 = 300 * (1 + 0.15 * np.exp(-t / 0.01))
    for r, a, dd in [(1, 1, 0.07), (2.2, 0.5, 0.035), (3.7, 0.25, 0.02)]:
        x += a * osc_sine(f0 * r, n) * np.exp(-t / dd)
    x *= att(n, 0.0005)
    x += bp(white(n), 1000, 5000) * np.exp(-t / 0.002) * 0.5
    x += osc_sine(140 * (1 + 0.8 * np.exp(-t / 0.008)), n) * np.exp(-t / 0.04) * 0.6
    m = N(0.33)
    tm = tt(m)
    wob_rate = 16 - 6 * tm / 0.33
    fb = 240 * (1 + 0.35 * np.exp(-tm / 0.02)) * (1 + 0.12 * np.exp(-tm / 0.12) * np.sin(TWO_PI * cycles(wob_rate, m)))
    c = cycles(fb, m)
    boing = np.sin(TWO_PI * c + 0.9 * np.exp(-tm / 0.1) * np.sin(TWO_PI * c)) * att(m, 0.004) * np.exp(-tm / 0.12)
    place(x, boing * 0.6, 0.015)
    return sat(x, 1.3)


def sfx_knockback_whoosh(d):
    n = N(d)
    t = tt(n)
    env = np.where(t < 0.1, (t / 0.1) ** 1.5, np.exp(-(t - 0.1) / 0.09))
    x = whoosh_noise(n, [(0, 350), (0.12, 2800), (0.4, 700)], 1.3, env)
    x *= 1 + 0.25 * np.sin(TWO_PI * 45 * t)
    m = N(0.2)
    tm = tt(m)
    place(x, osc_sine(50 + 50 * np.exp(-tm / 0.02), m) * np.exp(-tm / 0.07) * 0.5, 0.0)
    place(x, hp(white(N(0.01)), 2000) * np.exp(-tt(N(0.01)) / 0.0015) * 0.3, 0.0)
    return reverb(x, 0.3, 0.1)


def sfx_shield_on(d):
    n = N(d)
    t = tt(n)
    u = np.clip(t / 0.4, 0, 1)
    glide = 2 ** ((-12 * (1 - u) ** 2) / 12)
    hum = sum(supersaw(mtof(m) * glide, n, 3, 0.15) for m in (45, 52, 57))
    cut = np.where(t < 0.4, 250 + 3500 * u ** 1.5, 1600 + 2150 * np.exp(-(t - 0.4) / 0.1))
    hum = svf(hum, cut, 3.0)
    trem = 1 - 0.3 * (0.5 + 0.5 * np.sin(TWO_PI * cycles(10 + 6 * np.clip(t, 0, 1), n)))
    env = att(n, 0.05) * np.clip((0.98 - t) / 0.28, 0, 1)
    x = hum * trem * env * 0.35
    x += np.sin(TWO_PI * 880 * glide * t + 1.5 * np.sin(TWO_PI * 880 * 2.01 * t)) * 0.12 * u * env
    m = N(0.5)
    tm = tt(m)
    place(x, osc_sine(55 * 2 ** np.clip(tm / 0.3, 0, 1), m) * np.exp(-tm / 0.3) * att(m, 0.005) * 0.6, 0.0)
    place(x, bell(mtof(93), 0.5, 0.35) * 0.2 + bell(mtof(100), 0.5, 0.3) * 0.15, 0.4)
    glitter(x, 0.4, 0.8, 20, amp=0.1)
    x += hp(white(n), 2000) * u ** 2 * (t < 0.42) * 0.1
    return reverb(x, 0.9, 0.25)


def sfx_shield_zap(d):
    n = N(d)
    t = tt(n)
    step = N(0.0025)
    sh = np.repeat(R.uniform(-1, 1, n // step + 1), step)[:n]
    f = 1300 * (150 / 1300) ** np.clip(t / 0.3, 0, 1) * (1 + 0.35 * sh)
    buzz = bp(sat(osc_saw(f, n) * 3, 3), 500, 7000)
    gate_ = (smooth_noise(n, 400) > 0.6).astype(float)
    crack = hp(white(n) * gate_, 2500)
    fm = np.sin(TWO_PI * 90 * t + 5 * np.sin(TWO_PI * 90 * 7.3 * t))
    env = att(n, 0.001) * np.exp(-t / 0.12)
    x = (buzz * 0.5 + crack * 0.6 + fm * 0.3) * env
    x += hp(white(n), 1000) * np.exp(-t / 0.004) * 0.8
    return sat(x, 1.5)


def sfx_drop(d):
    n = N(d)
    x = np.zeros(n)

    def thud(g, dec):
        m = N(0.3)
        tm = tt(m)
        y = osc_sine(55 + 70 * np.exp(-tm / 0.02), m) * np.exp(-tm / dec) * att(m, 0.001)
        y += lp(white(m), 600) * np.exp(-tm / 0.03) * 0.6
        y += bp(white(m), 1500, 4000) * np.exp(-tm / 0.003) * 0.3
        for fr, a, dd in [(210, 0.5, 0.05), (395, 0.3, 0.03), (640, 0.15, 0.018)]:
            y += a * np.sin(TWO_PI * fr * tm) * np.exp(-tm / dd) * att(m, 0.0008)
        y += bp(white(m), 300, 1500) * np.exp(-tm / 0.025) * 0.35
        return y * g

    place(x, thud(1.0, 0.12), 0.0)
    place(x, thud(0.3, 0.06), 0.16)
    return reverb(x, 0.4, 0.1)


def sfx_heist_success(d):
    n = N(d)
    x = np.zeros(n)
    for i, mm in enumerate([55, 59, 62, 65]):
        place(x, lp(ks_pluck(mtof(mm), 0.25, 3500, 0.993), 5000) * 0.6, 0.09 * i)
    for tb in (0.0, 0.18):
        place(x, lp(ks_pluck(mtof(43), 0.3, 1500, 0.995), 2000) * 0.6, tb)
    for i in range(4):
        place(x, np.array(dr_hat(i)) * 0.15, 0.09 * i + 0.045)
    brass_chord(x, [60, 64, 67, 72], 0.40, 0.14, 0.9)
    brass_chord(x, [48, 60, 64, 67, 72, 76], 0.62, 0.5, 1.0, 1.1, 1.1)
    place(x, np.array(dr_snare(1)) * 0.35, 0.40)
    place(x, np.array(dr_snare(2)) * 0.4, 0.62)
    place(x, np.array(dr_crash(4, 1.0)) * 0.25, 0.62)
    for k, mm in enumerate([84, 88, 91, 96]):
        place(x, bell(mtof(mm), 0.8, 0.5) * 0.2, 0.62 + 0.05 * k)
    glitter(x, 0.65, 1.3, 30, amp=0.08)
    return reverb(x, 1.0, 0.22)


def sfx_rebirth(d):
    n = N(d)
    x = np.zeros(n)
    prog = [(0.0, [57, 60, 64, 69], 33), (0.7, [57, 60, 65, 69], 29), (1.4, [59, 62, 67, 71], 31)]
    for t0, ch, b in prog:
        for m in ch:
            place(x, np.array(ins_choir(m, 0.75, 1.0, "a")) * 0.35, t0)
        k = N(1.0)
        place(x, osc_sine(mtof(b + 12), k) * adsr(k, 0.1, 0.3, 0.8, 0.2, 0.75) * 0.4, t0)
    tb = 2.05
    for m in [60, 64, 67, 72, 76]:
        place(x, np.array(ins_choir(m, 0.55, 1.0, "a")) * 0.35, tb)
    m_ = N(0.95)
    place(x, osc_sine(mtof(36), m_) * adsr(m_, 0.01, 0.3, 0.8, 0.3, 0.6) * 0.5, tb)
    place(x, fx_riser(2.05) * 0.18, 0.0)
    place(x, rev_crash(0.8) * 0.3, tb - 0.8)
    place(x, boom(0.95, 38, 150, 0.5, 6000, 1.0, 2.2) * 0.9, tb)
    place(x, np.array(dr_crash(5, 1.0)) * 0.3, tb)
    for k, mm in enumerate([84, 88, 91, 96]):
        place(x, bell(mtof(mm), 0.9, 0.6) * 0.18, tb + 0.03 * k)
    glitter(x, tb, 2.9, 50, amp=0.1)
    return reverb(x, 2.0, 0.32)


def sfx_fusion_charge(d):
    n = N(d)
    t = tt(n)
    u = t / d
    f = 80 * 8 ** (u ** 1.6)
    ss = supersaw(f, n, 5, 0.25) + 0.5 * supersaw(f * 2, n, 3, 0.2)
    ss = svf(ss, 300 * 30 ** u, 3.5)
    trem = 1 - 0.55 * (0.5 + 0.5 * np.sin(TWO_PI * cycles(4 * 8 ** u, n)))
    riser = svf(white(n), 600 * 14 ** u, 1.2, "bp") * u ** 2 * 0.5
    sub = osc_sine(40 * 2 ** u, n) * u * 0.5 + lp(brown(n), 120) * u ** 1.5 * 0.5
    env = 0.25 + 0.75 * u ** 1.2
    x = sat((ss * env * trem * 0.4 + riser + sub) * 1.4, 1.8)
    tk, iv = 0.1, 0.22
    while tk < d - 0.05:
        place(x, fm_bell(R.uniform(1500, 3500), 0.06, 0.02, 1.7, 4.0) * 0.25 * (0.4 + 0.6 * tk / d), tk)
        tk += iv
        iv = max(0.035, iv * 0.85)
    return reverb(x, 0.8, 0.15)


def sfx_fusion_boom(d):
    n = N(d)
    x = np.zeros(n)
    place(x, boom(1.5, 50, 180, 0.4, 11000, 1.2, 2.0), 0.0)
    m = N(1.3)
    tm = tt(m)
    s = sum(supersaw(mtof(k), m, 5, 0.22) for k in [64, 68, 71, 76, 80])
    s = svf(s, 900 + 9000 * np.exp(-tm / 0.2), 0.9) * att(m, 0.003) * np.exp(-tm / 0.55) * 0.2
    place(x, s, 0.0)
    for i, mm in enumerate([88, 92, 95, 100]):
        place(x, bell(mtof(mm), 0.9, 0.6) * 0.25, 0.05 + 0.05 * i)
    place(x, np.array(dr_crash(6, 1.2)) * 0.35, 0.0)
    glitter(x, 0.05, 1.3, 80, amp=0.12)
    return reverb(x, 1.6, 0.28)


def sfx_reward_claim(d):
    n = N(d)
    x = np.zeros(n)
    place(x, pop(300, 900, 0.07) * 0.5, 0.0)
    for i, mm in enumerate([79, 83, 86, 91]):
        f = mtof(mm)
        place(x, chip_blip(f, 0.2, 0.25, 0.06) * 0.45 + fix(bell(f, 0.2, 0.2), N(0.2)) * 0.35, 0.02 + 0.055 * i)
    for mm in [91, 95, 98]:
        place(x, bell(mtof(mm), 0.55, 0.45) * 0.3, 0.24)
    for k, mm in enumerate([100, 103, 105]):
        place(x, coin_hit(mtof(mm), 0.2, 0.07) * 0.25, 0.25 + 0.05 * k)
    glitter(x, 0.2, 0.7, 25, amp=0.1)
    return reverb(x, 0.7, 0.2)


def sfx_quest_complete(d):
    n = N(d)
    x = np.zeros(n)
    for mm in [67, 72, 76]:
        place(x, np.array(ins_marimba(mm, 0.12)) * 0.3, 0.0)
    for mm in [72, 76, 79, 84]:
        place(x, np.array(ins_marimba(mm, 0.6)) * 0.3, 0.15)
    for mm in [84, 88, 91]:
        place(x, bell(mtof(mm), 0.85, 0.6) * 0.2, 0.15)
    m = N(0.85)
    tm = tt(m)
    pad = sum(supersaw(mtof(k), m, 5, 0.2) for k in [60, 64, 67, 72])
    place(x, lp(pad, 2200) * att(m, 0.02) * np.exp(-tm / 0.35) * 0.12, 0.15)
    k = N(0.2)
    place(x, hp(white(k), 6000) * np.exp(-tt(k) / 0.06) * 0.2, 0.15)
    glitter(x, 0.18, 0.8, 25, amp=0.1)
    return reverb(x, 0.9, 0.22)


def sfx_level_jingle(d):
    n = N(d)
    x = np.zeros(n)
    for i, mm in enumerate([77, 79, 81, 84, 86, 89]):
        place(x, chip_blip(mtof(mm), 0.1, 0.5, 0.05) * 0.4, 0.05 * i)
    place(x, np.array(ins_bass_round(53, 0.14)) * 0.5, 0.0)
    place(x, np.array(ins_bass_round(60, 0.14)) * 0.5, 0.15)
    place(x, np.array(ins_stab((70, 74, 77), 0.12, 1.0)) * 0.5, 0.33)
    place(x, np.array(ins_bass_round(46, 0.12)) * 0.5, 0.33)
    place(x, np.array(ins_chip_lead(89, 0.8, 1.0, 0.25)) * 0.4, 0.5)
    for mm in [69, 72, 77, 81]:
        place(x, np.array(ins_chip_lead(mm, 0.75, 1.0, 0.5)) * 0.15, 0.5)
    place(x, np.array(ins_bass_round(41, 0.75)) * 0.6, 0.5)
    place(x, np.array(dr_snare(3)) * 0.3, 0.5)
    place(x, np.array(dr_crash(8, 0.9)) * 0.2, 0.5)
    for mm in [89, 93, 96]:
        place(x, bell(mtof(mm), 0.9, 0.5) * 0.15, 0.5)
    return reverb(x, 0.9, 0.2)


def sfx_spin_tick(d):
    n = N(d)
    t = tt(n)
    x = osc_sine(2600, n) * np.exp(-t / 0.006) + 0.4 * osc_sine(2600 * 1.7, n) * np.exp(-t / 0.004)
    x = x * att(n, 0.0004) + hp(white(n), 3000) * np.exp(-t / 0.0008) * 0.5
    return x


def sfx_spin_win(d):
    n = N(d)
    x = np.zeros(n)
    for i, mm in enumerate([72, 74, 76, 79, 81, 84, 86, 88, 91, 93, 96]):
        place(x, chip_blip(mtof(mm), 0.12, 0.5, 0.06) * 0.3 + fix(bell(mtof(mm), 0.12, 0.1), N(0.12)) * 0.15, 0.032 * i)
    tb = 0.38
    for mm in [84, 88, 91, 96]:
        place(x, bell(mtof(mm), 1.0, 0.7) * 0.22, tb)
    place(x, np.array(ins_chip_lead(96, 0.6, 1.0, 0.25)) * 0.25, tb)
    m = N(0.9)
    tm = tt(m)
    pad = sum(supersaw(mtof(k), m, 5, 0.2) for k in [60, 64, 67, 72])
    place(x, lp(pad, 3000) * att(m, 0.01) * np.exp(-tm / 0.4) * 0.12, tb)
    place(x, np.array(dr_crash(9, 1.0)) * 0.25, tb)
    place(x, boom(0.5, 45, 100, 0.2, 2000, 0.3, 1.5) * 0.5, tb)
    for _ in range(18):
        mm = [91, 93, 96, 98, 100][R.integers(0, 5)]
        place(x, coin_hit(mtof(mm) * (1 + 0.003 * R.standard_normal()), 0.25, 0.08) * 0.22 * R.uniform(0.5, 1), tb + 0.02 + 0.7 * R.random())
    glitter(x, tb, 1.3, 50, amp=0.1)
    return reverb(x, 1.0, 0.22)


def sfx_event_horn(d):
    n = N(d)
    t = tt(n)
    cents = -120 * np.exp(-t / 0.12) + 15 * np.clip((t - 1.0) / 0.8, 0, 1)
    cents = cents + 8 * np.sin(TWO_PI * 4.8 * t) * np.clip((t - 0.4) / 0.4, 0, 1)
    f = 110 * 2 ** (cents / 1200)
    src = supersaw(f, n, 7, 0.12) + 0.7 * supersaw(f / 2, n, 3, 0.1) + 0.35 * supersaw(f * 1.5, n, 3, 0.1)
    cut = 180 + 2000 * np.clip(t / 0.35, 0, 1) ** 1.5 * (1 - 0.3 * np.clip((t - 0.5) / 1.0, 0, 1))
    env = np.clip(t / 0.28, 0, 1) ** 1.2 * np.where(t < 1.55, 1.0, np.exp(-(t - 1.55) / 0.14))
    x = lp(sat(svf(src, cut, 1.3) * env * 1.5, 2.5), 5000)
    fs = 380 * 1.6 ** np.clip(t / 1.3, 0, 1)
    c = cycles(fs, n)
    siren = sum(np.sin(TWO_PI * k * c) / k for k in (1, 3, 5, 7))
    x += lp(siren, 1500) * env * 0.12
    place(x, boom(1.0, 38, 80, 0.5, 1200, 0.6, 1.8) * 0.6, 0.0)
    return reverb(x, 2.0, 0.3)


def sfx_countdown_beep(d):
    n = N(d)
    t = tt(n)
    x = osc_sine(880, n) + 0.25 * lp(osc_pulse(880, n, 0.5), 5000) + 0.3 * osc_sine(1760, n)
    x = x * adsr(n, 0.002, 0.05, 0.8, 0.03, 0.1)
    x += hp(white(n), 3000) * np.exp(-t / 0.001) * 0.3
    return x


def sfx_boss_stomp(d):
    n = N(d)
    t = tt(n)
    sub = osc_sine(40 + 90 * np.exp(-t / 0.035) + 300 * np.exp(-t / 0.003), n) * att(n, 0.002) * np.exp(-t / 0.42)
    impact = svf(brown(n) + 0.2 * white(n), 120 + 3500 * np.exp(-t / 0.03), 0.7) * np.exp(-t / 0.12) * att(n, 0.001)
    crunch = bp(white(n), 250, 2500) * np.exp(-t / 0.06) * 1.0
    crunch += osc_sine(95 * (1 + 0.3 * np.exp(-t / 0.02)), n) * np.exp(-t / 0.15) * 0.4
    crunch += osc_sine(190, n) * np.exp(-t / 0.08) * 0.25
    rumble = lp(brown(n), 90) * np.exp(-t / 0.45) * att(n, 0.02) * 0.8 * (1 + 0.3 * np.sin(TWO_PI * 7 * t))
    x = sat(sub * 1.3 + impact + rumble, 2.5) + crunch
    debris(x, 0.02, 0.8, 50, amp=0.3, fmin=500, fmax=3000, tau=0.3, skew=1.8)
    thuds(x, 0.03, 0.6, 6, amp=0.3, tau=0.3)
    return reverb(x, 1.3, 0.2)


def sfx_whoosh(d):
    n = N(d)
    t = tt(n)
    env = np.sin(np.pi * np.clip(t / d, 0, 1) ** 0.9) ** 2
    x = whoosh_noise(n, [(0, 300), (0.25, 2200), (0.5, 500)], 1.4, env)
    return x * (1 + 0.15 * np.sin(TWO_PI * 30 * t))


# ---- loopable alarm -------------------------------------------------------
def loop_alarm(d):
    L = N(d)
    t = tt(L)
    seg = (np.floor(t / 0.375).astype(int)) % 2
    within = (t % 0.375) / 0.375
    target = np.where(seg == 0, 960.0, 720.0) * (1 + 0.035 * within)
    f = uniform_filter1d(target, size=N(0.02), mode="wrap")
    total = np.sum(f) / SR
    f *= round(total) / total  # integer number of cycles -> seamless phase
    ph = np.concatenate([[0.0], np.cumsum(f)[:-1]]) / SR
    x = np.zeros(L)
    for k in range(1, 40):
        if k * 1000 > 12000:
            break
        a = (1.0 / k) if k % 2 else (0.35 / k)
        x += a * np.sin(TWO_PI * k * ph)
    # circular low-pass in frequency domain
    X = np.fft.rfft(x)
    fr = np.fft.rfftfreq(L, 1 / SR)
    X /= np.sqrt(1 + (fr / 4500.0) ** 4)
    x = np.fft.irfft(X, L)
    x *= 1 - 0.15 * (0.5 + 0.5 * np.sin(TWO_PI * 16 * t))
    x *= 1 + 0.25 * np.exp(-(t % 0.375) / 0.05)
    x = sat(x * 1.5, 1.8)
    return reverb_circular(x, 0.5, 0.18)


# ==========================================================================
# Music sequencer
# ==========================================================================
def parse_bar(s):
    toks = s.split()
    k = len(toks)
    out = []
    cur = None
    for i, tok in enumerate(toks):
        if tok == "-":
            if cur:
                cur[1] += 1
        elif tok == ".":
            if cur:
                out.append(cur)
            cur = None
        else:
            if cur:
                out.append(cur)
            cur = [i, 1, nm(tok)]
    if cur:
        out.append(cur)
    return [(st * 16.0 / k, ln * 16.0 / k, m) for st, ln, m in out]


class Song:
    def __init__(self, bpm, bars, tail=4.5, swing=0.0):
        self.bpm = bpm
        self.beat = 60.0 / bpm
        self.step = self.beat / 4.0
        self.barlen = 4 * self.beat
        self.bars = bars
        self.L = N(bars * self.barlen)
        self.n = self.L + N(tail)
        self.swing = swing
        self.bus = {}
        self.kicks = []
        self._duck = {}

    def time(self, bar, step=0.0):
        t = bar * self.barlen + step * self.step
        if self.swing and abs(step - round(step)) < 1e-6 and int(round(step)) % 2 == 1:
            t += self.swing * self.step
        return t

    def add(self, bus, x, t0, gain=1.0, pan=0.0):
        b = self.bus.setdefault(bus, np.zeros((2, self.n)))
        x = np.asarray(x)
        if x.ndim == 1:
            th = (pan + 1) * np.pi / 4
            x = np.vstack([x * np.cos(th), x * np.sin(th)]) * np.sqrt(2)
        place(b, x, t0, gain)

    def hit(self, bus, x, bar, step, gain=1.0, pan=0.0):
        self.add(bus, x, self.time(bar, step), gain, pan)

    def note(self, bus, fn, m, bar, step, ln, vel=1.0, gain=1.0, pan=0.0, **kw):
        dur = round(ln * self.step, 4)
        self.add(bus, fn(m, dur, round(vel, 3), **kw), self.time(bar, step), gain, pan)

    def melody(self, bus, fn, bars, bar0, transpose=0, gain=1.0, pan=0.0, legato=0.92, **kw):
        for bi, s in enumerate(bars):
            for st, ln, m in parse_bar(s):
                self.note(bus, fn, m + transpose, bar0 + bi, st, ln * legato, 1.0, gain, pan, **kw)

    def kick(self, bar, step, x, gain=1.0):
        self.hit("kick", x, bar, step, gain)
        self.kicks.append(self.time(bar, step))

    def duck_env(self, depth, rel=0.14):
        key = (depth, rel)
        if key in self._duck:
            return self._duck[key]
        ks = np.array(sorted(set(round(k, 6) for k in self.kicks)))
        if len(ks) == 0:
            return np.ones(self.n)
        ks = np.concatenate([ks, ks + self.L / SR])
        t = tt(self.n)
        idx = np.searchsorted(ks, t, side="right") - 1
        dt = np.where(idx >= 0, t - ks[np.maximum(idx, 0)], 10.0)
        g = 1 - depth * np.exp(-dt / rel)
        self._duck[key] = uniform_filter1d(g, size=N(0.004))
        return self._duck[key]

    def render(self, spec, rt=1.6, push=3.0):
        out = np.zeros((2, self.n))
        send = np.zeros(self.n)
        for name, b in self.bus.items():
            p = spec.get(name, {})
            if "hp" in p:
                b = hp(b, p["hp"])
            if "lp" in p:
                b = lp(b, p["lp"])
            if "delay" in p:
                beats, fb, mix = p["delay"]
                b = pingpong(b, beats * self.beat, fb, mix)
            b = set_level(b, p.get("level", -20))
            if p.get("duck"):
                b = b * self.duck_env(p["duck"])
            out += b
            send += 0.5 * (b[0] + b[1]) * p.get("rev", 0.0)
        irs = make_ir(rt, 2, 0.02)
        send = hp(send, 200)
        for ch in range(2):
            out[ch] += signal.fftconvolve(send, irs[ch])[: self.n]
        out = hp(out, 28)
        loop = wrap_loop(out, self.L)
        return finalize_loop(loop, push)


def arp16(S, bus, fn, notes, bar, pattern, vel=1.0, gain=1.0, pan=0.0, ln=0.9, **kw):
    tones = sorted(notes)
    for st, idx in enumerate(pattern):
        v = vel * (1.0 if st % 4 == 0 else 0.75)
        S.note(bus, fn, tones[idx % len(tones)] + 12 * (idx // len(tones)), bar, st, ln, v, gain, pan, **kw)


def hats16(S, bar, vel=0.8, open_steps=(), skip=(), gain=1.0, eighths=False):
    acc = [1.0, 0.45, 0.7, 0.45]
    for st in range(16):
        if st in skip or (eighths and st % 2):
            continue
        if st in open_steps:
            S.hit("hats", dr_hat(st % 3, True), bar, st, vel * 0.8 * gain, 0.15)
        else:
            S.hit("hats", dr_hat(st % 4), bar, st, vel * acc[st % 4] * gain, 0.15)


# ---- music_main -----------------------------------------------------------
def music_main():
    S = Song(bpm=120, bars=40)
    CH = {
        "F": ([53, 57, 60, 64], 41), "G": ([55, 59, 62, 67], 43), "Em": ([52, 55, 59, 62], 40),
        "Am": ([55, 57, 60, 64], 45), "C": ([55, 60, 64, 67], 36), "Dm": ([53, 57, 60, 62], 38),
    }
    A = ["F", "G", "Em", "Am"] * 2
    B = ["C", "G", "Am", "F", "C", "G", "F", "G"]
    D = ["Dm", "G", "Em", "Am", "Dm", "G", "F", "G"]
    form = [("A", A), ("A2", A), ("B", B), ("D", D), ("B2", B)]
    melA = [". A4 C5 A4 E5 - D5 C5", "D5 - B4 G4 - . D5 E5", "G5 - E5 - D5 E5 - B4", "C5 - A4 - . . . .",
            ". A4 C5 A4 E5 - D5 C5", "D5 - B4 G4 - . G5 A5", "B5 - G5 - E5 - D5 E5", "A5 - - - . . . ."]
    melA2 = melA[:6] + ["B5 - G5 - B5 - C6 D6", "E6 - - - D6 - C6 B5"]
    melB = ["G5 - E5 G5 - A5 G5 E5", "D5 - - . B4 D5 G5 -", "E5 - C5 E5 - F5 E5 C5", "A4 - C5 - F5 - E5 D5",
            "G5 - E5 G5 - A5 G5 E5", "D5 - - . B4 D5 G5 A5", "C6 - B5 A5 - G5 A5 -", "B5 - - - D6 - - -"]
    bellD = ["F5 - - - A5 - - -", "G5 - - - D5 - - -", "E5 - - - B5 - - -", "C6 - - - - - - -",
             "F5 - - - A5 - - -", "B5 - - - D6 - - -", "C6 - - - A5 - - -", "B5 - - - - - - -"]
    BASS = [(0, 2, 0, 1), (3, 1, 12, 0.7), (4, 1, 0, 0.8), (6, 1, 0, 0.9), (7, 1, 12, 0.6), (8, 2, 0, 1),
            (10, 1, 7, 0.7), (11, 1, 12, 0.6), (12, 1, 0, 0.8), (14, 1, 7, 0.7), (15, 1, 12, 0.6)]
    ARP = [0, 1, 2, 3, 2, 1, 0, 1, 2, 3, 2, 1, 0, 1, 2, 3]
    K = dr_kick(0, 0.3, 50.0)
    bar0 = 0
    for sec, prog in form:
        for i, c in enumerate(prog):
            notes, root = CH[c]
            b = bar0 + i
            last = i == 7
            S.add("pad", ins_pad(tuple(notes), S.barlen), S.time(b), 1.3 if sec == "D" else 1.0)
            # bass
            if sec == "D":
                if i < 6:
                    S.note("bass", ins_bass_funk, root, b, 0, 9.5, 0.8)
                    S.note("bass", ins_bass_funk, root + 12, b, 10, 5.5, 0.6)
                else:
                    for st in range(0, 16, 2):
                        S.note("bass", ins_bass_funk, root, b, st, 1.6, 0.6 + 0.4 * (st / 16 + (i - 6)) / 2)
            else:
                for st, ln, off, v in BASS:
                    if last and st >= 12:
                        continue
                    S.note("bass", ins_bass_funk, root + off, b, st, ln * 0.9, v)
                if last:
                    for st, off in [(12, 0), (13, 3), (14, 5), (15, 7)]:
                        S.note("bass", ins_bass_funk, root + off, b, st, 0.9, 0.8)
            # drums
            if sec == "D" and i < 6:
                S.kick(b, 0, K, 0.8)
                S.kick(b, 8, K, 0.7)
                hats16(S, b, 0.55, eighths=True)
                S.hit("perc", dr_rim(i % 3), b, 12, 0.6)
            elif sec == "D":
                if i == 6:
                    for st in (0, 4, 8, 12):
                        S.kick(b, st, K, 0.9)
                    for st in range(0, 16, 2):
                        S.hit("snare", dr_snare(st % 4), b, st, 0.3 + 0.4 * st / 16)
                    S.add("fx", fx_riser(2 * S.barlen), S.time(b), 0.9)
                else:
                    for st in range(16):
                        S.hit("snare", dr_snare(st % 4), b, st, 0.5 + 0.5 * st / 16)
            else:
                ks = [0, 6, 8] + ([14] if i % 2 else [])
                for st in ks:
                    S.kick(b, st, K)
                fill = last and sec in ("A", "A2")
                for st in (4, 12):
                    if fill and st == 12:
                        continue
                    S.hit("snare", dr_snare(st % 4), b, st, 1.0)
                    if sec in ("B", "B2"):
                        S.hit("snare", dr_clap(b % 3), b, st, 0.7)
                if i % 2 == 1:
                    S.hit("snare", dr_snare(5, 0.08), b, 7, 0.25)
                    S.hit("snare", dr_snare(6, 0.08), b, 15, 0.2)
                opens = (14,) if sec == "A" else (2, 6, 10, 14)
                hats16(S, b, 0.8, open_steps=opens if sec != "A" else (14,), skip=range(12, 16) if fill else ())
                if sec in ("A2", "B2"):
                    for st in range(1, 16, 2):
                        S.hit("perc", dr_shaker(st % 4), b, st, 0.5, -0.3)
                if fill:
                    for st, fq in [(12, 210.0), (13, 175.0), (14, 140.0), (15, 110.0)]:
                        S.hit("perc", dr_tom(fq, 0.22), b, st, 0.9, 0.3 - 0.2 * (st - 12))
                        S.hit("snare", dr_snare(st % 4), b, st, 0.35)
                if i == 0 or (sec in ("B", "B2") and i == 4):
                    S.hit("fx", dr_crash(i % 3, 1.6), b, 0, 1.0, -0.2)
            # arp / stabs
            if sec in ("A", "A2", "D"):
                arp16(S, "arp", ins_pluck, notes, b, ARP, 1.0, 1.0, 0.25, 0.8, bright=4500, dec=0.09, wave="pulse")
            if sec in ("B", "B2"):
                for st in (2, 6, 10, 14):
                    S.hit("stab", ins_stab(tuple(n_ + 12 for n_ in notes), round(1.2 * S.step, 4), 1.0, 5000), b, st, 1.0, -0.2)
        if sec == "A":
            S.melody("lead", ins_chip_lead, melA, bar0, duty=0.25)
        elif sec == "A2":
            S.melody("lead", ins_chip_lead, melA2, bar0, duty=0.25)
            S.melody("lead2", ins_chip_lead, melA2, bar0, 12, 0.5, 0.3, duty=0.125)
        elif sec in ("B", "B2"):
            S.melody("lead", ins_saw_lead, melB, bar0)
            S.melody("lead2", ins_chip_lead, melB, bar0, 12, 0.6 if sec == "B2" else 0.35, -0.3, duty=0.25)
        elif sec == "D":
            S.melody("bell", ins_bell, bellD, bar0, 0, legato=1.0, dec=0.9)
        bar0 += 8
    spec = {
        "kick": dict(level=-14),
        "snare": dict(level=-19, rev=0.18),
        "hats": dict(level=-26, rev=0.05, hp=400),
        "perc": dict(level=-25, rev=0.15),
        "fx": dict(level=-25, rev=0.3),
        "bass": dict(level=-16, duck=0.35),
        "pad": dict(level=-23, duck=0.55, rev=0.3),
        "arp": dict(level=-24, delay=(0.75, 0.35, 0.35), rev=0.2, duck=0.3),
        "stab": dict(level=-23, rev=0.2, duck=0.3),
        "lead": dict(level=-17, delay=(0.75, 0.3, 0.25), rev=0.2),
        "lead2": dict(level=-24, rev=0.25),
        "bell": dict(level=-20, delay=(0.75, 0.35, 0.3), rev=0.4),
    }
    return S.render(spec, rt=1.6, push=4.5)


# ---- music_event ----------------------------------------------------------
def music_event():
    S = Song(bpm=140, bars=32)
    CH = {"Em": ([52, 55, 59, 64], 40), "C": ([52, 55, 60, 64], 36), "D": ([50, 54, 57, 62], 38),
          "B": ([51, 54, 59, 63], 35), "Am": ([52, 57, 60, 64], 45)}
    P = ["Em", "C", "D", "B"] * 2
    BD = ["Am", "C", "D", "B"] * 2
    form = [("I", P), ("L1", P), ("L2", P), ("BD", BD)]
    mel = ["B4 - E5 - G5 - F#5 E5", "E5 - C5 - G4 - C5 E5", "F#5 - D5 - A4 - D5 F#5", "D#5 - F#5 - B5 - A5 -",
           "B5 - G5 - E5 - G5 B5", "C6 - B5 - G5 - E5 -", "D6 - C6 - B5 - A5 F#5", "F#5 - D#5 - B4 - - -"]
    bellBD = ["C6 - - - B5 - - -", "G5 - - - E5 - - -", "F#5 - - - A5 - - -", "D#6 - - - - - - -"] * 2
    ARP = [0, 2, 1, 2, 3, 2, 1, 2, 0, 2, 1, 2, 3, 2, 1, 3]
    K = dr_kick(1, 0.26, 52.0, 1.1)
    bar0 = 0
    for sec, prog in form:
        for i, c in enumerate(prog):
            notes, root = CH[c]
            b = bar0 + i
            S.add("pad", ins_pad(tuple(notes), S.barlen, 2600), S.time(b), 1.2 if sec == "BD" else 1.0)
            half = sec == "BD" and i < 4
            build = sec == "BD" and i >= 4
            if half:
                S.note("bass", ins_bass_saw, root, b, 0, 15, 0.8, bright=0.6)
            else:
                for beat in range(4):
                    if build and i == 7 and beat == 3:
                        continue
                    for st, off, v, ln in [(0, 0, 1.0, 1.8), (2, 12, 0.6, 0.9), (3, 0, 0.8, 0.9)]:
                        S.note("bass", ins_bass_saw, root + off, b, beat * 4 + st, ln, v)
            # drums
            if half:
                S.kick(b, 0, K)
                S.kick(b, 10, K, 0.8)
                S.hit("snare", dr_snare(i % 4, 0.2), b, 8, 1.0)
                hats16(S, b, 0.6, eighths=True)
            elif build:
                for st in (0, 4, 8, 12):
                    if not (i == 7 and st == 12):
                        S.kick(b, st, K)
                rng_ = range(0, 16, 2) if i < 6 else range(16)
                for st in rng_:
                    if i == 7 and st >= 12:
                        continue
                    S.hit("snare", dr_snare(st % 4), b, st, 0.3 + 0.7 * ((i - 4) * 16 + st) / 64)
                if i == 5:
                    S.add("fx", fx_riser(3 * S.barlen - S.beat), S.time(b), 1.0)
            else:
                for st in (0, 4, 8, 12):
                    S.kick(b, st, K)
                for st in (4, 12):
                    S.hit("snare", dr_clap(st % 3), b, st, 1.0)
                    S.hit("snare", dr_snare(st % 4), b, st, 0.6)
                hats16(S, b, 0.85, open_steps=(2, 6, 10, 14) if (sec != "I" or i >= 4) else ())
                if i == 7:
                    for st, fq in [(12, 220.0), (13, 190.0), (14, 150.0), (15, 120.0)]:
                        S.hit("perc", dr_tom(fq, 0.2), b, st, 0.9, 0.3 - 0.2 * (st - 12))
                if sec in ("L2",):
                    for st in (3, 11):
                        S.hit("perc", dr_rim(st % 3), b, st, 0.5, 0.35)
            if i == 0 and sec != "BD" or (sec == "L2" and i == 4) or (sec == "BD" and i == 4):
                S.hit("fx", dr_crash(i % 3, 1.5), b, 0, 1.0, 0.2)
            arp16(S, "arp", ins_pluck, notes, b, ARP, 1.0, 1.0, -0.25, 0.8, bright=6000, dec=0.08, wave="saw")
            if sec == "L2":
                for st in (2, 6, 10, 14):
                    S.hit("stab", ins_stab(tuple(notes), round(1.2 * S.step, 4), 1.0, 4000), b, st, 1.0, 0.2)
        if sec == "L1":
            S.melody("lead", ins_saw_lead, mel, bar0)
        elif sec == "L2":
            S.melody("lead", ins_saw_lead, mel, bar0)
            S.melody("lead2", ins_chip_lead, mel, bar0, 12, 0.6, 0.25, duty=0.25)
        elif sec == "BD":
            S.melody("bell", ins_bell, bellBD, bar0, 0, legato=1.0, dec=0.9)
            for i in range(8):
                for m in CH[BD[i]][0]:
                    S.note("choir", ins_choir, m + 12, bar0 + i, 0, 15.5, 0.7)
        bar0 += 8
    spec = {
        "kick": dict(level=-13),
        "snare": dict(level=-18, rev=0.2),
        "hats": dict(level=-25, hp=400, rev=0.05),
        "perc": dict(level=-24, rev=0.2),
        "fx": dict(level=-24, rev=0.3),
        "bass": dict(level=-16, duck=0.4),
        "pad": dict(level=-24, duck=0.6, rev=0.3),
        "arp": dict(level=-22, delay=(0.75, 0.35, 0.3), duck=0.35, rev=0.15),
        "stab": dict(level=-23, rev=0.2, duck=0.3),
        "lead": dict(level=-17, delay=(0.75, 0.3, 0.22), rev=0.2),
        "lead2": dict(level=-24, rev=0.25),
        "bell": dict(level=-20, rev=0.4),
        "choir": dict(level=-24, rev=0.45, duck=0.3),
    }
    return S.render(spec, rt=1.5, push=4.5)


# ---- music_boss -----------------------------------------------------------
def music_boss():
    S = Song(bpm=100, bars=24)
    CH = {"Dm": ([50, 53, 57, 62], 38), "Bb": ([50, 53, 58, 62], 34), "Gm": ([50, 55, 58, 62], 31),
          "A": ([49, 52, 57, 61], 33), "Eb": ([51, 55, 58, 63], 39)}
    A = ["Dm", "Dm", "Bb", "A", "Dm", "Dm", "Eb", "A"]
    B = ["Dm", "Bb", "Gm", "A", "Dm", "Bb", "Eb", "A"]
    form = [("A", A), ("B", B), ("C", B)]
    theme = ["D4 - - - A4 - - -", "Bb4 - - - - - A4 G4", "G4 - - - F4 - E4 -", "E4 - - - - - - -",
             "D4 - F4 - A4 - D5 -", "D5 - - - - - C5 Bb4", "Bb4 - - - G4 - - -", "A4 - - - - - - -"]
    ACC = [0, 3, 6, 10, 13]
    K = dr_kick(2, 0.4, 44.0, 1.2)
    bar0 = 0
    for sec, prog in form:
        for i, c in enumerate(prog):
            notes, root = CH[c]
            b = bar0 + i
            third = 3 if c in ("Dm", "Gm") else 4
            mid = root + 12 if root < 45 else root
            pat = [0, 0, 0, 12, 0, 0, 12, 0, 0, 0, 12, 0, 0, 12, 7, third]
            for st in range(16):
                v = 1.0 if st in ACC else 0.55
                S.note("strings", ins_strings_stac, mid + pat[st], b, st, 0.7, v, 1.0, -0.2)
                if sec == "C":
                    S.note("strings", ins_strings_stac, mid + 12 + pat[st], b, st, 0.7, v * 0.6, 0.6, 0.3)
            for st, ln in [(0, 2.8), (3, 2.8), (6, 3.8), (10, 2.8), (13, 2.8)]:
                S.note("bass", ins_bass_heavy, root - 12 if root > 36 else root, b, st, ln, 1.0 if st == 0 else 0.8)
            low = [root + 12] + [m - 12 for m in notes]
            if sec == "A":
                if c == "Dm":
                    for st, ln in [(0, 5), (10, 5)]:
                        for m in (root + 12, root + 19, root + 24):
                            S.note("brass", ins_brass, m, b, st, ln, 1.0, 0.6, bright=1.0)
                else:
                    for m in low:
                        S.note("brass", ins_brass, m, b, 0, 15, 0.85, 0.5, bright=0.8)
            else:
                for m in low:
                    S.note("brass", ins_brass, m, b, 0, 15, 0.7, 0.35, bright=0.6)
            if sec == "C":
                S.add("choir", sum(np.array(ins_choir(m + 12, S.barlen * 0.97, 1.0, "a")) for m in notes), S.time(b))
            # drums
            if sec in ("A", "B"):
                S.kick(b, 0, K)
                S.kick(b, 10, K, 0.85)
                S.hit("snare", dr_snare(i % 4, 0.22, 170.0), b, 8, 1.0)
                for st, v in [(0, 1.0), (3, 0.6), (6, 0.8), (10, 0.7), (12, 0.6), (14, 0.8)]:
                    S.hit("taiko", dr_taiko(st % 3, 60.0 if st % 2 == 0 else 78.0), b, st, v, 0.2 if st % 2 else -0.2)
                if sec == "B":
                    hats16(S, b, 0.55, eighths=True)
            else:
                for st in (0, 6, 8, 10):
                    S.kick(b, st, K, 1.0 if st in (0, 8) else 0.8)
                for st in (4, 12):
                    S.hit("snare", dr_snare(st % 4, 0.2, 170.0), b, st, 1.0)
                hats16(S, b, 0.7)
                for st in ACC:
                    S.hit("taiko", dr_taiko(st % 3, 60.0), b, st, 0.8, 0.2 if st % 2 else -0.2)
            if i == 7:
                for st in range(8, 16):
                    fq = 180.0 - 10 * (st - 8)
                    S.hit("perc", dr_tom(fq, 0.25), b, st, 0.5 + 0.06 * (st - 8), 0.4 - 0.1 * (st - 8))
                S.hit("perc", ins_timpani(38, 1.5), b, 8, 0.8)
            if i == 0 or (sec == "C" and i == 4):
                S.hit("fx", dr_crash(i % 3, 2.0), b, 0, 1.0)
                S.hit("fx", ins_timpani(26, 1.8), b, 0, 1.0)
        if sec == "B":
            S.melody("horn", ins_brass, theme, bar0, 0, legato=0.97, bright=1.1)
        elif sec == "C":
            S.melody("horn", ins_brass, theme, bar0, 12, legato=0.97, bright=1.3)
            S.melody("horn", ins_brass, theme, bar0, 0, 0.6, legato=0.97, bright=0.9)
        bar0 += 8
    spec = {
        "kick": dict(level=-14),
        "snare": dict(level=-18, rev=0.35),
        "taiko": dict(level=-17, rev=0.25),
        "hats": dict(level=-27, hp=500, rev=0.1),
        "perc": dict(level=-21, rev=0.3),
        "fx": dict(level=-22, rev=0.35),
        "bass": dict(level=-17, duck=0.25),
        "strings": dict(level=-19, rev=0.2, duck=0.2),
        "brass": dict(level=-19, rev=0.3),
        "horn": dict(level=-16, rev=0.35),
        "choir": dict(level=-22, rev=0.45),
    }
    return S.render(spec, rt=2.2, push=4.5)


# ---- music_lobby_calm -----------------------------------------------------
def music_lobby_calm():
    S = Song(bpm=90, bars=20, swing=0.12)
    CH = {"F": ([53, 57, 60, 64], 41), "Em": ([52, 55, 59, 62], 40), "Dm": ([50, 53, 57, 60], 38),
          "C": ([48, 52, 55, 59], 36)}
    prog = ["F", "Em", "Dm", "C"] * 5
    melA = ["A5 - - G5 E5 - - -", "G5 - - E5 D5 - B4 -", "F5 - - E5 D5 - C5 -", "E5 - - - - - . ."]
    melB = ["A5 - - C6 B5 - G5 -", "G5 - - B5 A5 - E5 -", "F5 - E5 - D5 - C5 -", "G4 - - - - - . ."]
    K = dr_kick(3, 0.25, 50.0, 0.7)
    for b, c in enumerate(prog):
        notes, root = CH[c]
        sec = "I" if b < 4 else ("A" if b < 12 else "B")
        for st, ln, v in [(0, 5, 0.8), (6, 2, 0.5), (10, 5, 0.65)]:
            for m in notes:
                S.note("ep", ins_ep, m, b, st, ln, v, 1.0, 0.0)
        for st, ln, off in [(0, 6, 0), (7, 2, 7), (10, 5, 0), (14, 2, 12)]:
            S.note("bass", ins_bass_round, root, b, st, ln, 0.9) if off == 0 else \
                S.note("bass", ins_bass_round, root + off, b, st, ln, 0.7)
        hats16(S, b, 0.5, eighths=True)
        for st in range(16):
            S.hit("perc", dr_shaker(st % 4), b, st, 0.35 if st % 2 else 0.2, 0.3)
        if sec != "I":
            for st in (0, 7, 10):
                S.kick(b, st, K, 0.8)
            for st in (4, 12):
                S.hit("snare", dr_snare(st % 4, 0.09, 210.0), b, st, 0.7)
                S.hit("perc", dr_rim(st % 3), b, st, 0.4, -0.3)
        else:
            S.kick(b, 0, K, 0.6)
        if sec == "B":
            S.add("pad", ins_pad(tuple(m + 12 for m in notes), S.barlen, 1600, 0.6, 0.8), S.time(b))
    S.melody("bell", ins_marimba, melA * 2, 4, 0, 1.0, 0.1)
    S.melody("bell", ins_bell, melA * 2, 4, 12, 0.35, -0.2, legato=1.0, dec=0.7)
    S.melody("bell", ins_bell, melB * 2, 12, 0, 1.0, 0.1, legato=1.0, dec=0.9)
    S.melody("bell", ins_marimba, melB, 16, 12, 0.5, -0.2)
    spec = {
        "kick": dict(level=-17, lp=3000),
        "snare": dict(level=-22, rev=0.25, lp=6000),
        "hats": dict(level=-28, hp=500, lp=9000, rev=0.1),
        "perc": dict(level=-28, rev=0.15),
        "bass": dict(level=-18, duck=0.15),
        "ep": dict(level=-18, rev=0.25),
        "pad": dict(level=-25, rev=0.4, duck=0.2),
        "bell": dict(level=-19, delay=(0.75, 0.35, 0.3), rev=0.4),
    }
    return S.render(spec, rt=1.8, push=3.0)


# ==========================================================================
# Registry
# ==========================================================================
# name: (function, duration or None for music, kind, french description)
SFX = [
    ("ui_click", sfx_ui_click, 0.08, "Clic d'interface net et court (pop + transitoire)."),
    ("ui_hover", sfx_ui_hover, 0.05, "Petit tic doux au survol d'un bouton."),
    ("ui_open", sfx_ui_open, 0.25, "Ouverture de menu : souffle montant + pop final."),
    ("ui_close", sfx_ui_close, 0.2, "Fermeture de menu : souffle descendant + petit toc."),
    ("ui_error", sfx_ui_error, 0.3, "Erreur : double buzz grave « nuh-uh »."),
    ("ui_tab", sfx_ui_tab, 0.1, "Changement d'onglet : toc boisé."),
    ("cash_collect", sfx_cash_collect, 0.6, "Collecte d'argent : cascade de pièces + scintillement."),
    ("coin_tick", sfx_coin_tick, 0.06, "Minuscule tintement de pièce (compteur)."),
    ("purchase", sfx_purchase, 0.5, "Achat : « cha-ching » de caisse enregistreuse."),
    ("sell", sfx_sell, 0.4, "Vente : swoosh + deux pièces montantes."),
    ("meteor_whistle", sfx_meteor_whistle, 2.5, "Chute de météore : sifflement descendant, grondement et crépitements."),
    ("meteor_impact", sfx_meteor_impact, 1.5, "Impact de météore : gros boom, sub-basse et débris."),
    ("meteor_rare_alarm", sfx_meteor_rare_alarm, 1.2, "Alerte météore rare : carillon scintillant."),
    ("egg_wobble", sfx_egg_wobble, 0.3, "Œuf qui bouge : toc-toc de coquille."),
    ("egg_crack", sfx_egg_crack, 0.5, "Œuf qui se fissure : craquements de coquille."),
    ("hatch_common", sfx_hatch_common, 1.0, "Éclosion commune : pop joyeux + petit arpège."),
    ("hatch_epic", sfx_hatch_epic, 1.8, "Éclosion épique : grand arpège, accord et scintillement."),
    ("hatch_legendary", sfx_hatch_legendary, 3.0, "Éclosion légendaire : fanfare de cuivres, timbales et cymbales."),
    ("hatch_secret", sfx_hatch_secret, 3.5, "Éclosion secrète : montée mystérieuse puis révélation explosive."),
    ("stage_up", sfx_stage_up, 1.2, "Évolution du kaiju : montée « power-up » + carillon."),
    ("roar_small", sfx_roar_small, 0.8, "Petit rugissement mignon de bébé kaiju."),
    ("roar_big", sfx_roar_big, 2.0, "Énorme rugissement de kaiju (formants, grognement, distorsion)."),
    ("steal_grab", sfx_steal_grab, 0.4, "Vol : pincement de corde furtif + swoosh."),
    ("alarm", loop_alarm, 1.5, "Sirène d'alarme de base (boucle parfaite, à jouer en Looped)."),
    ("bonk", sfx_bonk, 0.35, "Coup de marteau cartoon « bonk » + boing."),
    ("knockback_whoosh", sfx_knockback_whoosh, 0.4, "Souffle rapide de projection (knockback)."),
    ("shield_on", sfx_shield_on, 1.0, "Activation du bouclier : dôme d'énergie qui monte."),
    ("shield_zap", sfx_shield_zap, 0.4, "Décharge électrique du bouclier."),
    ("drop", sfx_drop, 0.4, "Objet lâché : bruit sourd + petit rebond."),
    ("heist_success", sfx_heist_success, 1.5, "Vol réussi : motif furtif puis accord triomphal."),
    ("rebirth", sfx_rebirth, 3.0, "Renaissance : chœur ascendant épique + boom."),
    ("fusion_charge", sfx_fusion_charge, 2.0, "Charge de fusion : montée d'énergie qui accélère."),
    ("fusion_boom", sfx_fusion_boom, 1.5, "Explosion de fusion + accord brillant et étincelles."),
    ("reward_claim", sfx_reward_claim, 0.8, "Récompense réclamée : petit jingle brillant."),
    ("quest_complete", sfx_quest_complete, 1.0, "Quête terminée : « ta-da » marimba + cloches."),
    ("level_jingle", sfx_level_jingle, 1.5, "Montée de niveau : jingle chiptune ascendant."),
    ("spin_tick", sfx_spin_tick, 0.04, "Tic de la roue de la fortune."),
    ("spin_win", sfx_spin_win, 1.5, "Gain à la roue : glissando, accord et pluie de pièces."),
    ("event_horn", sfx_event_horn, 2.0, "Cor de guerre / sirène annonçant un événement."),
    ("countdown_beep", sfx_countdown_beep, 0.15, "Bip de compte à rebours."),
    ("boss_stomp", sfx_boss_stomp, 1.2, "Pas de boss géant : sub-basse, grondement et gravats."),
    ("whoosh", sfx_whoosh, 0.5, "Souffle générique (whoosh)."),
]

MUSIC = [
    ("music_main", music_main, "Musique principale en boucle : funk/chiptune x synthwave, 120 BPM, Do majeur."),
    ("music_event", music_event, "Musique d'événement en boucle : intense, 140 BPM, Mi mineur harmonique."),
    ("music_boss", music_boss, "Musique de boss en boucle : lourde et dramatique (taikos, cuivres, cordes), 100 BPM, Ré mineur."),
    ("music_lobby_calm", music_lobby_calm, "Musique calme en boucle (lobby) : lo-fi/chill, piano électrique, 90 BPM."),
]
LOOPS = {"alarm", "music_main", "music_event", "music_boss", "music_lobby_calm"}
MUSIC_LEN = {"music_main": 80.0, "music_event": 32 * 4 * 60 / 140, "music_boss": 57.6, "music_lobby_calm": 20 * 4 * 60 / 90}


def _write_chunked(path, data):
    # libsndfile's Vorbis encoder can crash on very large single writes: stream it.
    ch = 1 if data.ndim == 1 else data.shape[1]
    with sf.SoundFile(path, "w", SR, ch, format="OGG", subtype="VORBIS", compression_level=0.2) as f:
        for i in range(0, len(data), 16384):
            f.write(data[i:i + 16384])


def write_ogg(name, x):
    """Encode, then re-check the *decoded* peak and correct the gain (Vorbis
    shifts peaks slightly, especially on very short transient sounds)."""
    path = os.path.join(OUT_DIR, name + ".ogg")
    data = (x.T if x.ndim == 2 else x).astype(np.float64)
    for _ in range(3):
        _write_chunked(path, data.astype(np.float32))
        dec, _sr = sf.read(path, dtype="float64")
        err = CEIL_DB - 20 * np.log10(np.max(np.abs(dec)) + 1e-12)
        if abs(err) < 0.25:
            break
        data = data * db(err)
    return path


def generate(only=None):
    os.makedirs(OUT_DIR, exist_ok=True)
    for name, fn, dur, _ in SFX:
        if only and name not in only:
            continue
        t0 = time.time()
        set_seed(name)
        _MEMO.clear()
        x = fn(dur)
        if not np.all(np.isfinite(x)):
            raise RuntimeError(f"{name}: non-finite samples")
        if name in LOOPS:
            x = finalize_loop(fix(x, N(dur)), push_db=2.0)
        else:
            x = finalize_sfx(x, dur)
        write_ogg(name, x)
        print(f"  {name:20s} {dur:5.2f}s  ({time.time() - t0:.1f}s)")
    for name, fn, _ in MUSIC:
        if only and name not in only:
            continue
        t0 = time.time()
        set_seed(name)
        _MEMO.clear()
        x = fn()
        if not np.all(np.isfinite(x)):
            raise RuntimeError(f"{name}: non-finite samples")
        write_ogg(name, x)
        print(f"  {name:20s} {x.shape[-1] / SR:5.2f}s  ({time.time() - t0:.1f}s)")


def expected_duration(name):
    for n_, _, d, _ in SFX:
        if n_ == name:
            return d
    return MUSIC_LEN[name]


def verify():
    rows = []
    ok = True
    names = [s[0] for s in SFX] + [m[0] for m in MUSIC]
    for name in names:
        path = os.path.join(OUT_DIR, name + ".ogg")
        if not os.path.exists(path):
            rows.append((name, "MISSING", "", "", "", "", "", "FAIL"))
            ok = False
            continue
        data, sr = sf.read(path, always_2d=True, dtype="float64")
        dur = len(data) / sr
        exp = expected_duration(name)
        tol = max(0.005, 0.005 * exp)
        pk = 20 * np.log10(np.max(np.abs(data)) + 1e-12)
        nan = bool(np.isnan(data).any())
        size = os.path.getsize(path) / 1e6
        loop = ""
        good = sr == SR and abs(dur - exp) <= tol and not nan and -3.0 <= pk <= 0.0 and size < 19 and dur < 420
        if name in LOOPS:
            jump = float(np.max(np.abs(data[0] - data[-1])))
            typ = float(np.percentile(np.abs(np.diff(data, axis=0)), 99))
            loop = f"{jump:.4f}/{typ:.4f}"
            good = good and jump <= max(typ, 0.02)
        ok &= good
        rows.append((name, f"{dur:.3f}", f"{exp:.3f}", f"{pk:+.2f}", str(data.shape[1]), f"{size:.2f}", loop,
                     "OK" if good else "FAIL"))
    hdr = ("file", "dur(s)", "expected", "peak dBFS", "ch", "MB", "loop jump/p99 step", "status")
    w = [max(len(str(r[i])) for r in rows + [hdr]) for i in range(len(hdr))]
    line = "  ".join(h.ljust(w[i]) for i, h in enumerate(hdr))
    print(line)
    print("-" * len(line))
    for r in rows:
        print("  ".join(str(c).ljust(w[i]) for i, c in enumerate(r)))
    return ok, rows


def write_readme(rows):
    desc = {n: d for n, _, _, d in SFX}
    desc.update({n: d for n, _, d in MUSIC})
    dur = {r[0]: r[1] for r in rows}
    L = []
    L.append("# Steal a Kaiju — pack audio original\n")
    L.append("Tous les sons de ce dossier ont été **synthétisés de zéro** par "
             "`tools/audio/generate_audio.py` (oscillateurs, FM, bruit filtré, Karplus-Strong, "
             "réverbération synthétique…). Aucun échantillon externe, aucun téléchargement : "
             "le pack est 100 % original et libre de droits pour ce projet.\n")
    L.append("Format : OGG Vorbis, 44 100 Hz, crête normalisée à environ −1 dBFS. "
             "SFX en mono, musiques en stéréo. Les boucles (`alarm`, `music_*`) bouclent sans "
             "couture (longueur exacte en mesures, la queue est repliée sur le début).\n")
    L.append("Pour régénérer : `python3 tools/audio/generate_audio.py` (déterministe, "
             "dépendances : numpy, scipy, soundfile ; numba optionnel pour la vitesse).\n")
    L.append("## Fichiers\n")
    L.append("| Clé (fichier .ogg) | Durée (s) | Description |")
    L.append("|---|---|---|")
    for name in [s[0] for s in SFX] + [m[0] for m in MUSIC]:
        loop = " *(boucle)*" if name in LOOPS else ""
        L.append(f"| `{name}` | {dur.get(name, '?')} | {desc[name]}{loop} |")
    L.append("")
    L.append("## Import dans Roblox\n")
    L.append("1. Ouvrir le jeu dans **Roblox Studio**.")
    L.append("2. Ouvrir le **Gestionnaire de ressources** (onglet *Affichage* → *Asset Manager*), "
             "puis cliquer sur **Importation groupée** (*Bulk Import*) et sélectionner tous les "
             "fichiers `.ogg` de ce dossier. "
             "Alternative : **Creator Hub** → *Créations* → *Audio* → *Importer un fichier audio* (un par un).")
    L.append("3. Attendre la modération Roblox (quelques minutes). Chaque son reçoit un **ID d'asset** "
             "(`rbxassetid://123456789`).")
    L.append("4. Dans le Gestionnaire de ressources, clic droit sur chaque son → **Copier l'ID de "
             "l'asset**, puis le coller dans `src/shared/Config/Sounds.luau`, dans le champ "
             "`Uploaded` de la clé correspondante (la clé = le nom du fichier sans `.ogg`, "
             "par ex. `meteor_impact`).")
    L.append("5. Pour `alarm` et les `music_*`, activer `Looped = true` sur le `Sound`.")
    L.append("6. Tous les fichiers sont normalisés au même niveau de crête : régler l'équilibre "
             "final avec la propriété `Volume` de chaque `Sound` (ex. `ui_hover` ≈ 0.3, "
             "musiques ≈ 0.4–0.5, impacts ≈ 0.8).")
    L.append("")
    L.append("Limites Roblox respectées : chaque fichier fait moins de 7 minutes et bien moins de 19 Mo.\n")
    with open(os.path.join(OUT_DIR, "README.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(L))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="", help="comma-separated keys to (re)generate")
    ap.add_argument("--verify-only", action="store_true")
    a = ap.parse_args()
    only = set(s.strip() for s in a.only.split(",") if s.strip()) or None
    if not a.verify_only:
        print(f"Generating into {OUT_DIR}")
        generate(only)
    ok, rows = verify()
    write_readme(rows)
    print("\nALL OK" if ok else "\nSOME CHECKS FAILED")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
