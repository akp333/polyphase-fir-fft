import numpy as np
from psgen import *

N = 1024 # samples per case 128 frames
rng = np.random.default_rng(2026) # one seeded generator

h_lp = make_lowpass_h(0.9) # lowpass filter
h_full  = make_random_h(rng, 32768) # arbitrary, full 16-bit range, non-symmetric

# V1 single tones
# each tone must land in bins k and 8-k
for k in range(M):
    re, im = save_case(f"v1_tone_k{k}", tone(k, 20000, N), h_lp)
    print("   power in bins k and 8-k:", round(check_single_tone(k, re, im), 4))

# V2 multi-tone
# any frequencies at once, arbitrary non-symmetric h
ms = multitone(rng, N, 5000, 4) # arbitrary amplitude and number of tones
save_case("v2_multi", ms, h_full)

# V3 multi-tone + noise
# same signal as V2 plus uniform noise
save_case("v3_noise", add_noise(rng, ms, 800), h_full) # arbitrary amplitude

# extreme values / saturation
# values at the edges of the 16-bit range to check overflow and clipping
save_case("e_fullscale_rand", rng.integers(-32768, 32768, N), h_full)
save_case("e_max_const", np.full(N, 32767), h_full)
save_case("e_clip_everywhere", np.full(N, -32768), np.full(L, -32768))
save_case("e_zeros", np.zeros(N), h_full)

# rounding ties
# h = 0.5 and small odd samples make FIR sums land exactly halfway between two integers
h_half = np.full(L, 16384)
save_case("f_round_ties", rng.integers(-7, 8, N), h_half)

# random breadth
# random signals and filters at different sizes (small, medium, large)
save_case("g_rand_small", rng.integers(-300, 301, N),     make_random_h(rng, 32768))
save_case("g_rand_mid",   rng.integers(-8000, 8001, N),   make_random_h(rng, 16384))
save_case("g_rand_large", rng.integers(-32768, 32768, N), make_random_h(rng, 8192))

# the FFT error is largest when the odd-group differences are as big as possible
h_pass = np.zeros(L, dtype=np.int64)
h_pass[0:8] = 32767
P, Mn = 32767, -32768
pattern_a = [P, 0, Mn, 0, Mn, 0, P, 0]
pattern_b = [Mn, 0, Mn, 0, P, 0, P, 0]
for tag, pat in (("a_pos", pattern_a), ("a_neg", [-q if q != 0 else 0 for q in pattern_a]),
                 ("b_pos", pattern_b), ("b_neg", [-q if q != 0 else 0 for q in pattern_b])):
    x = np.tile(np.array(pat, dtype=np.int64), N // 8)
    x[1::2] = rng.choice([Mn, P], N // 2)
    x = np.clip(x, Mn, P)
    save_case(f"h_worst_{tag}", x, h_pass)

# many random cases (breadth)
# the +-2 LSB claim must not rest on a few lucky signals
NUM_RANDOM = 100
sig_amps = [100, 1000, 8000, 32768]        # signal size classes
h_amps   = [2048, 8192, 16384, 32768]      # filter size classes
for i in range(NUM_RANDOM):
    a_sig = sig_amps[int(rng.integers(0, 4))]
    a_h   = h_amps[int(rng.integers(0, 4))]
    if i % 2 == 0:
        x = rng.integers(-a_sig, a_sig, N)
    else:
        x = add_noise(rng, multitone(rng, N, a_sig // 5, 4), a_sig // 20)
    save_case(f"r_{i:03d}", x, make_random_h(rng, a_h))
