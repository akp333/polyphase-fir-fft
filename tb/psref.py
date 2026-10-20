import numpy as np

M = 8
L = 32
NB = 4

I16_MIN, I16_MAX = -32768, 32767

def sat16(a):
    return np.clip(a, I16_MIN, I16_MAX)

def rshift_rne(a, s):
    a = np.asarray(a, dtype=np.int64)
    if s == 0:
        return a
    q = a >> s
    r = a - (q << s)
    half = 1 << (s-1)
    go_up = (r > half) | ((r == half) & ((q & 1) == 1))
    return q + go_up.astype(np.int64)

def fir_exact(x, h):
    x = np.asarray(x, dtype=np.int64)
    h = np.asarray(h, dtype=np.int64)
    assert len(x) % M == 0 and len(h) == L
    F = len(x) // M
    xp = np.concatenate([np.zeros(L - M, dtype=np.int64), x])
    S = np.zeros((F, M), dtype=np.int64)
    for m in range(F):
        for r in range(M):
            acc = 0
            for j in range (NB):
                coeff = int(h[M*j + r])
                sample = int(xp[M*(m - j) + (M - 1) - r + (L - M)])
                acc += coeff * sample
            S[m, r] = acc
    return S

def fir_scale(S):
    return sat16(rshift_rne(S, 15))

def fft8_double(v):
    return np.fft.fft(np.asarray(v).astype(np.float64), axis=1)

def ref_fft_stage(v):
    Y = fft8_double(v) / 8.0
    re = sat16(np.rint(Y.real)).astype(np.int64)
    im = sat16(np.rint(Y.imag)).astype(np.int64)
    return re,im

def ref_channelizer(x, h):
    v = fir_scale(fir_exact(x, h))
    re, im = ref_fft_stage(v)
    return v, re, im
