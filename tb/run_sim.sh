#!/bin/bash
# Usage: cd tb && ./run_sim.sh
# 1) regenerates hex files  2) compiles RTL+TB with Icarus  3) runs every case twice
#    (back-to-back samples, and with 30% random stalls)  4) prints PASS/FAIL per case
cd "$(dirname "$0")"
python3 gen_tests.py > /dev/null || exit 1
iverilog -g2012 -o sim.vvp channelizer_top.v tb_channelizer.v || exit 1
fails=0
: > sim_results.txt
for xf in psfiles/*_x.hex; do
  n=$(basename "$xf" _x.hex)
  for gap in 0 30; do
    out=$(vvp -n sim.vvp +XF=psfiles/${n}_x.hex +HF=psfiles/${n}_h.hex +EF=psfiles/${n}_exp.hex +N=1024 +GAP=$gap +TAG=${n}_gap${gap})
    echo "$out" | tee -a sim_results.txt
    echo "$out" | grep -q "^PASS" || fails=$((fails+1))
  done
done
echo "-----"; echo "failed runs: $fails"
[ $fails -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
