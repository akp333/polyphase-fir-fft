import numpy as np
from psref import *

rng = np.random.default_rng(1)

def test_rounding():
    assert rshift_rne(3, 1) == 2
    assert rshift_rne(5, 1) == 2
    assert rshift_rne(7, 1) == 4
    assert rshift_rne(-3, 1) == -2
    assert rshift_rne(-5, 1) == -2
    assert rshift_rne(16384, 15) == 0
    assert rshift_rne(49152, 15) == 2
    assert rshift_rne(16385, 15) == 1
    print("test_rounding OK")


def test_impulse():
    h = rng.integers(-32768, 32768, L)
    for r0 in range(M):
        x = np.zeros(32, dtype=np.int64)
        x[7 - r0] = 1
        S = fir_exact(x, h)
        for j in range(NB):
            assert S[j, r0] == h[8 * j + r0]
        S2 = S.copy()
        S2[:NB, r0] = 0
        assert not S2.any()
    print("test_impulse OK")


def direct_form(x, h):
    x = np.asarray(x, dtype=np.int64)
    F = len(x) // M
    xp = np.concatenate([np.zeros(L - M, dtype=np.int64), x])
    n = np.arange(L)
    Y = np.zeros((F, M), dtype=complex)
    for m in range(F):
        seg = xp[8 * m + 7 - n + (L - M)]
        for k in range(M):
            Y[m, k] = np.sum(h * np.exp(-2j * np.pi * k * n / 8) * seg)
    return Y / 2**15 / 8

def test_matches_definition():
    for _ in range(10):
        x = rng.integers(-3000, 3000, 8 * 40)
        h = rng.integers(-16384, 16384, L)
        _, re, im = ref_channelizer(x, h)
        Yd = direct_form(x, h)
        assert np.max(np.abs(np.rint(Yd.real) - re)) <= 1
        assert np.max(np.abs(np.rint(Yd.imag) - im)) <= 1
    print("test_matches_definition OK")


def test_saturation_path():
    x = np.full(8 * 10, -32768)
    h = np.full(L, -32768)
    v, re, im = ref_channelizer(x, h)
    assert np.all(v[3:] == 32767)
    assert re.max() <= 32767 and re.min() >= -32768
    assert im.max() <= 32767 and im.min() >= -32768
    print("test_saturation_path OK")


if __name__ == "__main__":
    test_rounding()
    test_impulse()
    test_matches_definition()
    test_saturation_path()
    print("ALL REFERENCE MODEL TESTS PASSED")
