import os
import numpy as np
from psref import *

OUT = "psfiles"
os.makedirs(OUT, exist_ok=True)

def to_hex16(arr):
    return [f"{int(a) & 0xFFFF:04x}" for a in np.ravel(arr)]

def write_hex(path, arr):
    with open(path, "w") as f:
        f.write("\n".join(to_hex16(arr)) + "\n")

def to_int16(sig):
    return sat16(np.rint(sig)).astype(np.int64)

def make_lowpass_h(gain=0.9):
    n = np.arange(L)
    c = (L - 1) / 2
    fc = 1 / 16
    hh = 2 * fc * np.sinc(2 * fc * (n - c)) * np.hamming(L)
    hh = hh / hh.sum() * gain
    return np.clip(np.rint(hh * 32768), -32768, 32767).astype(np.int64)

def make_random_h(rng, amp):
    return rng.integers(-amp, amp, L).astype(np.int64)

def tone(k, amp, N):
    n = np.arange(N)
    return amp * np.cos(2 * np.pi * k * n / 8)

def multitone(rng, N, amp_each, nt=4):
    n = np.arange(N)
    s = np.zeros(N)
    for _ in range(nt):
        f = rng.uniform(0.01, 0.49)
        p = rng.uniform(0, 2 * np.pi)
        s += amp_each * np.cos(2 * np.pi * f * n + p)
    return s

def add_noise(rng, sig, amp):
    return sig + rng.uniform(-amp, amp, len(sig))

def save_case(name, x, h):
    x = to_int16(x)
    v, re, im = ref_channelizer(x, h)
    F = len(x) // M
    exp = np.empty((F, 2 * M), dtype=np.int64)
    exp[:, 0::2] = re
    exp[:, 1::2] = im
    write_hex(f"{OUT}/{name}_x.hex", x)
    write_hex(f"{OUT}/{name}_h.hex", h)
    write_hex(f"{OUT}/{name}_exp.hex", exp)
    print(f"{name:14s} N={len(x)} F={F} v_sat={(np.abs(v)>=32767).sum()}")
    return re, im

def check_single_tone(k, re, im):
    p = (re[3:].astype(float)**2 + im[3:].astype(float)**2).sum(axis=0)
    mirror = (8 - k) % 8
    want = p[k] + (p[mirror] if mirror != k else 0)
    frac = want / p.sum()
    assert frac > 0.95
    return frac

if __name__ == "__main__":
    N = 1024
    rng = np.random.default_rng(2026)
    h_lp = make_lowpass_h()
    h_rand = make_random_h(rng)

    for k in range(M):
        re, im = save_case(f"v1_tone_k{k}", tone(k, 20000, N), h_lp)
        print("   energy fraction:", round(check_single_tone(k, re, im), 4))

    ms = multitone(rng, N)
    save_case("v2_multi", ms, h_rand)

    save_case("v3_noise", add_noise(rng, ms), h_rand)
