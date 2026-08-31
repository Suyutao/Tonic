#!/bin/zsh
set -euo pipefail

device_id="${TONIC_DEVICE_ID:-88A7E6EC-C6D7-561D-8D46-3A84AF89BCDF}"
output="${1:-tonic-measurement.csv}"
raw_log="${TMPDIR:-/tmp}/tonic-console-$$.log"
console_pid=0
stop_console() {
  if (( console_pid > 0 )) && kill -0 "$console_pid" 2>/dev/null; then
    kill -INT "$console_pid" 2>/dev/null || true
    sleep 0.3
    kill "$console_pid" 2>/dev/null || true
  fi
}
trap 'pkill -f "ffplay -nodisp" 2>/dev/null || true; stop_console; rm -f "$raw_log"' EXIT

printf 'time,mac_raw,app_raw,app_smooth,app_level,display_frequency,note_letter,note_solfege,cents,chart_index,chart_cents\n' > "$output"

: > "$raw_log"
xcrun devicectl device process launch --device "$device_id" --terminate-existing \
  --console com.suyutao.ToneTuner -- --tonic-diagnostic >"$raw_log" 2>&1 &
console_pid=$!
deadline=$((SECONDS + 30))
while (( SECONDS < deadline )); do
  grep -Eq '^(TONIC_READY|TONIC_PITCH)' "$raw_log" && break
  if ! kill -0 "$console_pid" 2>/dev/null; then
    print -u2 "iPhone console exited before TONIC_READY"
    exit 1
  fi
  sleep 0.2
done
grep -Eq '^(TONIC_READY|TONIC_PITCH)' "$raw_log" || { print -u2 "timed out waiting for audio engine"; exit 1; }

for target in 440 466.16 493.88 523.25 392 261.63 82.41; do
  start_line=$(wc -l < "$raw_log")
  /opt/homebrew/bin/ffmpeg -hide_banner -loglevel error -f lavfi \
    -i "sine=frequency=${target}:sample_rate=48000" -t 3 -af volume=0.5 -f wav - \
    | /opt/homebrew/bin/ffplay -nodisp -hide_banner -loglevel error -autoexit -i - \
    >/dev/null 2>&1 &
  audio_pid=$!
  sleep 3
  kill "$audio_pid" 2>/dev/null || true
  sleep 0.2
  awk -F, -v target="$target" -v start_line="$start_line" '
    NR > start_line && $1 == "TONIC_CSV" && NF == 5 { print $2 "," target "," $3 "," $4 "," $5 ",,,,,," }
    NR > start_line && $1 == "TONIC_DISPLAY" && NF == 8 { print $2 "," target ",,,," $3 "," $4 "," $5 "," $6 "," $7 "," $8 }
  ' "$raw_log" >> "$output"
done

printf 'wrote %s\n' "$output"
