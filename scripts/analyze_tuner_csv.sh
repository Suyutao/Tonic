#!/bin/zsh
set -euo pipefail

input="${1:?usage: scripts/analyze_tuner_csv.sh FILE.csv}"

awk -F, '
NR == 1 { next }
{
  target = $3
  if (target == "") next
  rows[target]++
  if ($4 != "") {
    raw[target]++
    error = $4 - target
    if (error < 0) error = -error
    if (error / target <= 0.02) {
      rawStable[target]++
      if (!(target in firstRawStable)) firstRawStable[target] = $1
    }
  }
  if ($7 != "") {
    display[target]++
    sum[target] += $7
    error = $7 - target
    if (error < 0) error = -error
    if (error / target <= 0.02) {
      stable[target]++
      if (!(target in firstStable)) firstStable[target] = $1
    }
  }
  if (!(target in start)) start[target] = $1
  end[target] = $1
}
END {
  printf "target,rows,raw_rows,display_rows,display_rate,raw_stable_rows,stable_rows,mean_display_hz,first_raw_stable_s,first_display_stable_s,display_minus_raw_s\n"
  for (target in rows) {
    rate = display[target] / rows[target]
    mean = display[target] ? sum[target] / display[target] : 0
    rawLatency = (target in firstRawStable) ? firstRawStable[target] - start[target] : -1
    displayLatency = (target in firstStable) ? firstStable[target] - start[target] : -1
    gap = (target in firstRawStable && target in firstStable) ? firstStable[target] - firstRawStable[target] : -1
    printf "%s,%d,%d,%d,%.3f,%d,%d,%.2f,%.3f,%.3f,%.3f\n", target, rows[target], raw[target], display[target], rate, rawStable[target], stable[target], mean, rawLatency, displayLatency, gap
  }
}' "$input" | sort -t, -k1,1n
