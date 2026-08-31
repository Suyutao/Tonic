#!/bin/zsh
set -euo pipefail

device_id="${TONIC_DEVICE_ID:-88A7E6EC-C6D7-561D-8D46-3A84AF89BCDF}"
output="${1:-tonic-song-$(date +%Y%m%d-%H%M%S).csv}"
work_dir="${TMPDIR:-/tmp}/tonic-song-$$"
mkdir -p "$work_dir"
console_pid=0
audio_pid=0
stop_console() {
  if (( console_pid > 0 )) && kill -0 "$console_pid" 2>/dev/null; then
    kill -INT "$console_pid" 2>/dev/null || true
    sleep 0.3
    kill "$console_pid" 2>/dev/null || true
  fi
}
trap 'kill "$audio_pid" 2>/dev/null || true; stop_console; rm -rf "$work_dir"' EXIT

song="${TONIC_SONG:-two-tigers}"
case "$song" in
  two-tigers)
    # Public-domain melody in 4/4: quarter, quarter, half-note proportions.
    notes=(261.63 293.66 329.63 261.63 261.63 293.66 329.63 261.63 \
           329.63 349.23 392.00 329.63 349.23 392.00 \
           392.00 440.00 392.00 349.23 329.63 261.63 \
           392.00 440.00 392.00 349.23 329.63 261.63)
    durations=(0.35 0.35 0.70 0.70 0.35 0.35 0.70 0.70 \
               0.35 0.35 0.70 0.70 0.35 0.35 0.70 \
               0.35 0.35 0.35 0.35 0.70 0.70 \
               0.35 0.35 0.35 0.35 0.70 0.70)
    ;;
  vivaldi-spring)
    # Short public-domain-style excerpt: repeated violin-like E-major motif.
    notes=(659.25 659.25 659.25 587.33 523.25 587.33 659.25 698.46 \
           783.99 783.99 783.99 698.46 659.25 587.33 523.25 587.33)
    durations=(0.22 0.22 0.44 0.22 0.22 0.22 0.44 0.22 \
               0.22 0.22 0.44 0.22 0.22 0.22 0.44 0.44)
    ;;
  ode-to-joy)
    notes=(329.63 329.63 349.23 392.00 392.00 349.23 329.63 293.66 \
           261.63 261.63 293.66 329.63 329.63 293.66 293.66)
    durations=(0.5 0.5 0.5 0.5 0.5 0.5 0.5 0.5 0.5 0.5 0.5 0.5 0.75 0.25 1)
    ;;
  *)
    print -u2 "TONIC_SONG must be two-tigers, vivaldi-spring, or ode-to-joy"
    exit 2
    ;;
esac

song_duration=$(printf '%s\n' "${durations[@]}" | awk '{ sum += $1 } END { printf "%.3f", sum }')

printf 'start_s,duration_s,expected_hz\n' > "$work_dir/song_score.csv"
elapsed=0
for ((index=1; index <= ${#notes[@]}; index++)); do
  duration="${durations[index]}"
  printf '%s,%s,%s\n' "$elapsed" "$duration" "${notes[index]}" >> "$work_dir/song_score.csv"
  elapsed=$(awk -v t="$elapsed" -v d="$duration" 'BEGIN { printf "%.3f", t+d }')
done

printf 'time,mac_raw,app_raw,app_smooth,app_level,display_frequency,note_letter,note_solfege,cents,chart_index,chart_cents\n' > "$output"
: > "$work_dir/console.log"
xcrun devicectl device process launch --device "$device_id" --terminate-existing \
  --console com.suyutao.ToneTuner -- --tonic-diagnostic >"$work_dir/console.log" 2>&1 &
console_pid=$!
deadline=$((SECONDS + 30))
while (( SECONDS < deadline )); do
  if grep -Eq '^(TONIC_READY|TONIC_PITCH)' "$work_dir/console.log"; then break; fi
  if ! kill -0 "$console_pid" 2>/dev/null; then
    print -u2 "iPhone console exited before audio engine became ready"
    exit 1
  fi
  sleep 0.2
done
grep -Eq '^(TONIC_READY|TONIC_PITCH)' "$work_dir/console.log" || { print -u2 "timed out waiting for audio engine"; exit 1; }

# Render melody plus a quiet bass, beat, and room-noise bed in one deterministic file.
ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i "aevalsrc=0.18*sin(2*PI*130*t):s=48000:d=${song_duration}" \
  -f lavfi -i "aevalsrc=0.04*sin(2*PI*2*t):s=48000:d=${song_duration}" \
  -filter_complex "[0:a][1:a]amix=inputs=2:normalize=0,volume=0.8" \
  -c:a pcm_s16le "$work_dir/bed.wav"

# Render every note first, then concatenate the finite files. Playing one
# continuous stream avoids process-start gaps between adjacent notes.
melody_list="$work_dir/melody.txt"
: > "$melody_list"
for ((index=1; index <= ${#notes[@]}; index++)); do
  frequency="${notes[index]}"
  duration="${durations[index]}"
  note_file="$work_dir/note-${index}.wav"
  ffmpeg -hide_banner -loglevel error -y \
    -f lavfi -i "sine=frequency=${frequency}:sample_rate=48000:duration=${duration}" \
    -af "afade=t=in:st=0:d=0.005,afade=t=out:st=$(awk -v d="$duration" 'BEGIN { printf "%.3f", d-0.005 }'):d=0.005" \
    -c:a pcm_s16le "$note_file"
  printf "file '%s'\n" "$note_file" >> "$melody_list"
done

ffmpeg -hide_banner -loglevel error -y -f concat -safe 0 -i "$melody_list" -c copy "$work_dir/melody.wav"
ffmpeg -hide_banner -loglevel error -y \
  -i "$work_dir/melody.wav" -i "$work_dir/bed.wav" \
  -filter_complex "[0:a][1:a]amix=inputs=2:duration=first:normalize=0,volume=0.55" \
  -c:a pcm_s16le "$work_dir/song.wav"

/opt/homebrew/bin/ffplay -nodisp -hide_banner -loglevel error -autoexit \
  -i "$work_dir/song.wav" >/dev/null 2>&1 &
audio_pid=$!
wait "$audio_pid" || true

stop_console
awk -F, '
  $1 == "TONIC_CSV" && NF == 5 { print $2 ",," $3 "," $4 "," $5 ",,,,,," }
  $1 == "TONIC_DISPLAY" && NF == 8 { print $2 ",,,," $3 "," $4 "," $5 "," $6 "," $7 "," $8 }
' "$work_dir/console.log" >> "$output"
cp "$work_dir/song_score.csv" "${output%.csv}-score.csv"
printf 'wrote %s and %s\n' "$output" "${output%.csv}-score.csv"
