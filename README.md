# 8-Channel Polyphase Channelizer (Verilog RTL)

A synthesizable, fully pipelined 8-channel, critically sampled polyphase channelizer: a 32-tap polyphase FIR filter followed by an 8-point FFT, written in Verilog. It takes one 16-bit sample per clock cycle and produces eight complex 16-bit output bins per frame of 8 samples. Timing is closed at 100 MHz in a Nangate 45 nm flow (Yosys + OpenSTA).

Built for the Inter IIT Tech Meet 15.0 Prepathon, Frontend VLSI problem (SNTC, IIT (BHU) Varanasi).

## Results

| Metric | Result |
|---|---|
| Clock period | 10.0 ns (100 MHz) |
| Worst setup slack | +6.159 ns |
| Worst hold slack | +0.076 ns |
| Latency (newest sample of a frame to first output bin of that frame) | 7 cycles |
| Worst-case measured error vs. ideal reference | 2 LSB (limit: ±2 LSB), over <N> test cases |
| Throughput | 1 input sample per cycle, 1 frame (8 bins) per 8 cycles, continuous |

STA constraints: 10 ns clock, 2 ns input delay, 2 ns output delay. Timing is pre-layout, measured with OpenSTA on the Yosys-mapped Nangate 45 nm netlist.

## What it computes

For frame $m$ (newest input sample $x[8m+7]$) and channel $k \in [0,7]$:

```math
Y_k[m] = \sum_{n=0}^{31} h[n]\; e^{-j2\pi kn/8}\; x[8m+7-n]
```

The design uses the equivalent polyphase form. First, 8 branch outputs, each a 4-tap filter:

$$v_r[m] = \sum_{j=0}^{3} h[8j+r]\;x[8(m-j)+7-r], \qquad r = 0,\dots,7$$

then an 8-point FFT across the branches:

$$Y_k[m] = \sum_{r=0}^{7} v_r[m]\,e^{-j2\pi kr/8}$$

**Numerical specification**

- Input: real 16-bit signed samples. Coefficients $h[n]$: 16-bit signed Q1.15, arbitrary values (no symmetry assumed).
- FIR stage: exact integer accumulation, scaled by $2^{-15}$, rounded to nearest-even, saturated to 16 bits.
- FFT stage: scaled by $1/8$, rounded to nearest-even, saturated to 16 bits.
- Each output must match an ideal double-precision reference to within ±2 LSB.

## Why polyphase + FFT

Counting real operations per frame of 8 samples (coefficients with the twiddle factor pre-multiplied for the direct form; twiddle factors $\pm1, \pm j$ count as free):

| Structure | Real multiplications | Real additions |
|---|---|---|
| 8 independent direct-form channels | 320 | 306 |
| Polyphase FIR + FFT | 34 (32 FIR + 2 FFT) | 48 (24 FIR + 24 FFT) |

The FFT needs only two real multiplications. The one non-trivial twiddle factor is $1/\sqrt{2}$, and the 4-point DFTs have real inputs, so several outputs cost no adders. Full derivation: see [`docs/report.pdf`](docs/report.pdf).

## Fixed-point design

| Signal | Word length |
|---|---|
| FIR product $h\cdot x$ | 32 bits signed |
| FIR branch sum before scaling | 34 bits signed |
| $v_r$ after RNE and saturation | 16 bits |
| FFT stage 1 / stage 2 / final stage | 17 / 18 / 19 bits |
| Twiddle $1/\sqrt{2}$ | $181/2^8$ (8 fractional bits) |

**Why 8 fractional bits for $1/\sqrt{2}$.** If the hardware value before the final rounding is within $\varepsilon_Y$ of the ideal one, then after both roundings the integers differ by at most $\varepsilon_Y + 1$. Staying within 2 LSB therefore needs $\varepsilon_Y < 2$. With constant $C/2^B$ and truncation after the multiply, the error satisfies

$$\varepsilon_Y < 2^{14}\,\bigl|\delta\bigr| + \tfrac{1}{8}, \qquad \delta = \tfrac{C}{2^B} - \tfrac{1}{\sqrt{2}}$$

For $B=7$ ($C=91$) this bound is far above 2, so 7 bits are not enough. For $B=8$ ($C=181$) it gives $\varepsilon_Y \approx 1.36 < 2$, so the ±2 LSB limit is guaranteed. A randomized fixed-point simulation agrees with the bound.

## Architecture

![Datapath diagram](docs/datapath.png)

**FIR (4 multipliers).** A 25-register delay line holds the last 25 samples. Taps at delays 0, 8, 16 and 24 feed four 16×16 multipliers. Each clock cycle computes one branch $r$ (the branch number counts $7, 6, \dots, 0$), using four coefficients $h[r], h[8+r], h[16+r], h[24+r]$ from loadable coefficient registers. Eight cycles complete one frame. Four multipliers is the minimum for one sample per cycle, because 32 products are needed in 8 cycles.

**FFT (2 multipliers, parallel).** The 8 values $v_r$ are split into even and odd groups, each handled by a 4-point DFT, then combined. The only multiplications are two constant multiplications by 181 (18×9 bits). It is left fully parallel because its adders are narrow (17 to 19 bits), and sharing them would need wide multiplexers that cancel the saving.

**Serial output.** The 8 complex bins are held in a register, then read out one per cycle through two 8:1 multiplexers, followed by ÷8, round-to-nearest-even and saturation. Bins come out in increasing channel order, continuously.

**Pipeline.** Taking the cycle in which the newest sample of a frame is on the input pins as cycle $T$:

| Cycle | Event |
|---|---|
| $T+3$ (end) | all eight $v_r$ registered |
| $T+4$ (end) | FFT stages 1 and 2 registered |
| $T+5$ (end) | FFT final stage registered |
| $T+6$ (end) | output register loaded |
| $T+7$ | bin 0 visible (latency = 7 cycles) |
| $T+8 \dots T+14$ | bins 1 to 7 |
| $T+15$ | bin 0 of the next frame |

**Folding.** For an input of one sample every $c$ cycles, the FIR needs $\lceil 4/c \rceil$ multipliers.

## Interface

Top module: `channelizer_top` in [`rtl/channelizer_top.v`](rtl/channelizer_top.v).

| Port | Dir | Description |
|---|---|---|
| `clk` | in | clock |
| `rst` | in | synchronous reset, active high |
| `cfg_we` | in | write enable for the coefficient registers |
| `cfg_addr[4:0]` | in | coefficient index $n$ (0 to 31) |
| `cfg_data[15:0]` | in | coefficient value $h[n]$, signed Q1.15 |
| `in_valid` | in | `in_data` is a real sample this cycle |
| `in_data[15:0]` | in | input sample, signed |
| `out_valid` | out | output bin is valid this cycle |
| `out_idx[2:0]` | out | channel number of the bin on the output (0 to 7) |
| `out_re[15:0]`, `out_im[15:0]` | out | real and imaginary part of the bin, signed |

**Usage**

1. Apply reset.
2. While idle, load all 32 coefficients: write $h[n]$ at address $n$ with `cfg_we = 1`. Coefficients survive a reset.
3. Stream samples with `in_valid = 1`. The first valid sample after reset is the first sample of frame 0. `in_valid` may pause at any time, and the design waits.
4. Read one bin per cycle when `out_valid = 1`. The first 3 frames after reset are warm-up: the pipeline is still filling, but their output transfers still occur.

## Verification

- A Python reference model (`psref.py`) implements the numerical specification: integer FIR with round-half-to-even and saturation, double-precision FFT, output rounding and saturation.
- Test families: single tones centered on each channel (energy must appear in bins $k$ and $8-k$), multi-tone, and multi-tone with noise, plus <corner cases: full-scale inputs, all-zero input, saturation>.
- Every case is also run with pauses on `in_valid`.
- Measured worst-case error: **2 LSB** over <N> cases.

## Limitations and possible improvements

- Coefficients must be loaded while idle, not while samples are streaming.
- The setup slack of +6.159 ns means some pipeline stages could be merged to cut latency and registers.
- Area was not the optimisation target.
- Timing is pre-layout.
