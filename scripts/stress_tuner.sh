#!/bin/zsh
set -euo pipefail

device_id="${TONIC_DEVICE_ID:-88A7E6EC-C6D7-561D-8D46-3A84AF89BCDF}"
output="${1:-tonic-stress-$(date +%Y%m%d-%H%M%S).csv}"
work_dir="${TMPDIR:-/tmp}/tonic-stress-$$"
target_tolerance_cents="${TONIC_TARGET_TOLERANCE_CENTS:-1}"
mkdir -p "$work_dir"
console_pid=0
stop_console() {
  if (( console_pid > 0 )) && kill -0 "$console_pid" 2>/dev/null; then
    kill -INT "$console_pid" 2>/dev/null || true
    sleep 0.3
    kill "$console_pid" 2>/dev/null || true
  fi
}
trap 'pkill -f "ffplay -nodisp" 2>/dev/null || true; stop_console; rm -rf "$work_dir"' EXIT

printf 'time,scenario,mac_raw,app_raw,app_smooth,app_level,display_frequency,note_letter,note_solfege,cents,chart_index,chart_cents\n' > "$output"

start_console() {
  local log="$work_dir/console.log"
  : > "$log"
  xcrun devicectl device process launch --device "$device_id" --terminate-existing \
    --console com.suyutao.ToneTuner -- --tonic-diagnostic >"$log" 2>&1 &
  console_pid=$!
  local deadline=$((SECONDS + 30))
  while (( SECONDS < deadline )); do
    if grep -Eq '^(TONIC_READY|TONIC_PITCH)' "$log"; then return 0; fi
    if ! kill -0 "$console_pid" 2>/dev/null; then
      print -u2 "iPhone console exited before TONIC_READY"
      sed -n '1,80p' "$log" >&2
      return 1
    fi
    sleep 0.2
  done
  print -u2 "timed out waiting for TONIC_READY"
  sed -n '1,80p' "$log" >&2
  return 1
}

run_segment() {
  local scenario="$1" target="$2" input="$3" duration="$4"
  local start_line
  start_line=$(wc -l < "$work_dir/console.log")
  /opt/homebrew/bin/ffmpeg -hide_banner -loglevel error -f lavfi -i "$input" -t "$duration" \
    -af volume=0.5 -f wav - | /opt/homebrew/bin/ffplay -nodisp -hide_banner -loglevel error \
    -autoexit -i - >/dev/null 2>&1 &
  local audio_pid=$!
  monitor_audio_process "$audio_pid"
  sleep 0.2
  awk -F, -v scenario="$scenario" -v target="$target" -v start_line="$start_line" '
    NR > start_line && $1 == "TONIC_CSV" && NF == 5 { print $2 "," scenario "," target "," $3 "," $4 "," $5 ",,,,,," }
    NR > start_line && $1 == "TONIC_DISPLAY" && NF == 8 { print $2 "," scenario "," target ",,,," $3 "," $4 "," $5 "," $6 "," $7 "," $8 }
  ' "$work_dir/console.log" >> "$output"
  # Allow buffered device-console lines from this audio segment to arrive before
  # the next target starts, keeping segment attribution deterministic.
  sleep 0.5
}

monitor_audio_process() {
  local audio_pid="$1"
  local started_at=$SECONDS
  local last_activity=$SECONDS
  local previous_count=0 current_count=0
  while kill -0 "$audio_pid" 2>/dev/null; do
    current_count=$(grep -cE '^(TONIC_CSV|TONIC_DISPLAY),' "$work_dir/console.log" 2>/dev/null || true)
    if (( current_count > previous_count )); then
      previous_count=$current_count
      last_activity=$SECONDS
    fi
    # Give the device console time to deliver its first frames. After that,
    # a quiet console means the in-app tuner was paused or stopped.
    if (( SECONDS - started_at >= 2 && SECONDS - last_activity >= 2 )); then
      print -u2 "audio stopped because iPhone tuner was paused"
      kill "$audio_pid" 2>/dev/null || true
      pkill -TERM -P "$audio_pid" 2>/dev/null || true
      break
    fi
    sleep 0.1
  done
  wait "$audio_pid" 2>/dev/null || true
}

scenario="${TONIC_STRESS_SCENARIO:-all}"
start_console
if [[ "$scenario" == violin-bow ]]; then
    events_output="${output%.csv}-events.csv"
    python3 scripts/violin_tuner.py "$work_dir/console.log" "$output" "$events_output"
    exit 0
fi
if [[ "$scenario" == jumps || "$scenario" == all ]]; then
    jump_targets=(300 785 410 920 522 785 350 1000)
    if [[ -n "${TONIC_STRESS_TARGETS:-}" ]]; then
      jump_targets=(${(s:,:)TONIC_STRESS_TARGETS})
    fi
    for target in "${jump_targets[@]}"; do
      run_segment jump "$target" "sine=frequency=${target}:sample_rate=48000" 2
    done
fi
if [[ "$scenario" == random || "$scenario" == all ]]; then
    for target in 337 812 461 699 388 874 523 947; do
      run_segment random-jump "$target" "sine=frequency=${target}:sample_rate=48000" 2
    done
fi
if [[ "$scenario" == sweep-linear || "$scenario" == all ]]; then
    run_segment sweep-linear "300+20t" \
      "aevalsrc=sin(2*PI*(300*t+10*t*t)):s=48000" 10
    run_segment sweep-linear-down "500-20t" \
      "aevalsrc=sin(2*PI*(500*t-10*t*t)):s=48000" 10
fi
if [[ "$scenario" == sweep-quadratic || "$scenario" == all ]]; then
    run_segment sweep-quadratic "300+2t^2" \
      "aevalsrc=sin(2*PI*(300*t+2*t*t*t/3)):s=48000" 10
    run_segment sweep-quadratic-down "500-2t^2" \
      "aevalsrc=sin(2*PI*(500*t-2*t*t*t/3)):s=48000" 10
fi
if [[ "$scenario" == violin ]]; then
    # Real tuning is jerky: short checks, static-friction jumps, overshoot,
    # quick reversals, and irregular pauses rather than a smooth sweep.
    run_segment violin-G3 "196" "sine=frequency=190:sample_rate=48000" 1.4
    run_segment violin-G3 "196" "sine=frequency=201:sample_rate=48000" 0.8
    run_segment violin-G3 "196" "sine=frequency=194:sample_rate=48000" 1.1
    run_segment violin-G3 "196" "sine=frequency=198:sample_rate=48000" 0.6
    run_segment violin-G3 "196" "sine=frequency=195.5:sample_rate=48000" 1.7
    run_segment violin-D4 "293.66" "sine=frequency=285:sample_rate=48000" 1.0
    run_segment violin-D4 "293.66" "sine=frequency=302:sample_rate=48000" 0.7
    run_segment violin-D4 "293.66" "sine=frequency=289:sample_rate=48000" 1.3
    run_segment violin-D4 "293.66" "sine=frequency=296:sample_rate=48000" 0.5
    run_segment violin-D4 "293.66" "sine=frequency=293.2:sample_rate=48000" 1.8
    run_segment violin-A4 "440" "sine=frequency=432:sample_rate=48000" 1.2
    run_segment violin-A4 "440" "sine=frequency=448:sample_rate=48000" 0.6
    run_segment violin-A4 "440" "sine=frequency=437:sample_rate=48000" 0.9
    run_segment violin-A4 "440" "sine=frequency=443:sample_rate=48000" 0.4
    run_segment violin-A4 "440" "sine=frequency=439.2:sample_rate=48000" 1.5
    # The E string commonly has a fine tuner: use many smaller corrections.
    run_segment violin-E5 "659.25" "sine=frequency=657.0:sample_rate=48000" 0.7
    run_segment violin-E5 "659.25" "sine=frequency=661.2:sample_rate=48000" 0.4
    run_segment violin-E5 "659.25" "sine=frequency=658.4:sample_rate=48000" 0.9
    run_segment violin-E5 "659.25" "sine=frequency=660.1:sample_rate=48000" 0.35
    run_segment violin-E5 "659.25" "sine=frequency=658.9:sample_rate=48000" 0.55
    run_segment violin-E5 "659.25" "sine=frequency=659.6:sample_rate=48000" 1.2
fi
if [[ "$scenario" == violin-feedback ]]; then
    # Closed-loop human simulation: play a string, read displayed cents, then
    # apply an imperfect correction with inertia and occasional overshoot.
    run_feedback_string() {
      local label="$1" target="$2" current="$3"
      local attempt cents correction next
      for attempt in {1..7}; do
        run_segment "$label" "$target" "sine=frequency=${current}:sample_rate=48000" 1.2
        measured_cents=$(awk -F, '$1 == "TONIC_DISPLAY" && $6 != "" { value=$6 } END { print value }' "$work_dir/console.log")
        measured=$(awk -F, '$1 == "TONIC_DISPLAY" && $3 != "" { value=$3 } END { print value }' "$work_dir/console.log")
        if [[ -z "$measured" || -z "$measured_cents" ]]; then
          continue
        fi
        if awk -v c="$measured_cents" -v tolerance="$target_tolerance_cents" 'BEGIN { exit !(c >= -tolerance && c <= tolerance) }'; then
          print -u2 "feedback $label reached target: cents=$measured_cents"
          break
        fi
        next=$(awk -v f="$current" -v measured="$measured" -v target="$target" -v attempt="$attempt" 'BEGIN {
          # Correct 70% of the target-frequency error; alternate small overshoots.
          gain = (attempt % 3 == 0) ? 0.9 : 0.7
          printf "%.4f", f + (target - measured) * gain
        }')
        current="$next"
        awk -v measured="$measured" -v cents="$measured_cents" -v target="$target" -v label="$label" -v attempt="$attempt" -v next_hz="$next" 'BEGIN { printf "feedback %s attempt=%d displayed_hz=%.2f cents=%.2f target_hz=%.2f next_hz=%s\n", label, attempt, measured, cents, target, next_hz }' >&2
      done
    }
    run_feedback_string violin-feedback-G3 196 190
    run_feedback_string violin-feedback-D4 293.66 285
    run_feedback_string violin-feedback-A4 440 432
    run_feedback_string violin-feedback-E5 659.25 657
fi
if [[ "$scenario" == violin-bow ]]; then
    events_output="${output%.csv}-events.csv"
    printf 'time,string,target_hz,event_type,previous_end_hz,start_hz,end_hz,bow_duration,reversal_pause\n' > "$events_output"
    run_bow_string() {
      local label="$1" target="$2"; shift 2
      local index=0 spec start_frequency end_frequency duration pause tone silence event_type previous_end
      for spec in "$@"; do
        index=$((index + 1))
        IFS=: read -r event_type start_frequency end_frequency previous_end <<< "$spec"
        # Human bowing can last several seconds while listening closely, with
        # irregular stroke lengths and short reversal pauses on every run.
        duration=$(( (1500 + RANDOM % 1501) / 1000.0 ))
        pause=$(( (100 + RANDOM % 401) / 1000.0 ))
        printf '%s,%s,%s,%s,%s,%s,%s,%s,%s\n' "$(date +%s)" "$label" "$target" "$event_type" "$previous_end" "$start_frequency" "$end_frequency" "$duration" "$pause" >> "$events_output"
        tone="$work_dir/${label}-${index}-tone.wav"
        ffmpeg -hide_banner -loglevel error -y -f lavfi -i "aevalsrc=sin(2*PI*(${start_frequency}*t+(${end_frequency}-${start_frequency})/(2*${duration})*t*t)):s=48000:d=${duration}" -af "afade=t=in:st=0:d=0.008,afade=t=out:st=$(awk -v d="$duration" 'BEGIN { printf "%.3f", d-0.008 }'):d=0.008" -c:a pcm_s16le "$tone"
        local start_line=$(wc -l < "$work_dir/console.log")
        /opt/homebrew/bin/ffplay -nodisp -hide_banner -loglevel error -autoexit -i "$tone" >/dev/null 2>&1 &
        monitor_audio_process "$!"
        sleep "$pause"
        awk -F, -v label="$label" -v target="$target" -v start_line="$start_line" '
          NR > start_line && $1 == "TONIC_CSV" && NF == 5 { print $2 "," label "," target "," $3 "," $4 "," $5 ",,,,,," }
          NR > start_line && $1 == "TONIC_DISPLAY" && NF == 8 { print $2 "," label "," target ",,,," $3 "," $4 "," $5 "," $6 "," $7 "," $8 }
        ' "$work_dir/console.log" >> "$output"
      done
    }
    run_dynamic_bow() {
      local label="$1" target="$2" event_type="$3" previous_end="$4" current="$5" duration="$6" pause="$7"
      local elapsed=0.0 chunk=0.25 chunk_end measured_cents direction next_frequency tone start_line
      while awk -v e="$elapsed" -v d="$duration" 'BEGIN { exit !(e < d) }'; do
        measured_cents=$(awk -F, '$1 == "TONIC_DISPLAY" && $6 != "" { value=$6 } END { print value }' "$work_dir/console.log")
        if [[ -n "$measured_cents" ]] && awk -v c="$measured_cents" -v tolerance="$target_tolerance_cents" 'BEGIN { exit !(c > tolerance) }'; then direction=-1
        elif [[ -n "$measured_cents" ]] && awk -v c="$measured_cents" -v tolerance="$target_tolerance_cents" 'BEGIN { exit !(c < -tolerance) }'; then direction=1
        else direction=0
        fi
        chunk_end=$(awk -v e="$elapsed" -v d="$duration" 'BEGIN { print (e + 0.25 < d) ? 0.25 : d-e }')
        next_frequency=$(awk -v f="$current" -v t="$target" -v dir="$direction" -v dt="$chunk_end" 'BEGIN { step=(t-f)*0.45; if (dir == 0) step=0; printf "%.3f", f+step }')
        tone="$work_dir/${label}-dynamic.wav"
        ffmpeg -hide_banner -loglevel error -y -f lavfi -i "aevalsrc=sin(2*PI*(${current}*t+(${next_frequency}-${current})/(2*${chunk_end})*t*t)):s=48000:d=${chunk_end}" -af "afade=t=in:st=0:d=0.008,afade=t=out:st=$(awk -v d="$chunk_end" 'BEGIN { print (d > 0.016) ? d-0.008 : 0 }'):d=0.008" -c:a pcm_s16le "$tone"
        start_line=$(wc -l < "$work_dir/console.log")
        /opt/homebrew/bin/ffplay -nodisp -hide_banner -loglevel error -autoexit -i "$tone" >/dev/null 2>&1 &
        monitor_audio_process "$!"
        printf '%s,%s,%s,dynamic,%s,%s,%s,%s,%s\n' "$(date +%s)" "$label" "$target" "$previous_end" "$current" "$next_frequency" "$chunk_end" "$pause" >> "$events_output"
        awk -F, -v label="$label" -v target="$target" -v start_line="$start_line" 'NR > start_line && $1 == "TONIC_CSV" && NF == 5 { print $2 "," label "," target "," $3 "," $4 "," $5 ",,,,,," } NR > start_line && $1 == "TONIC_DISPLAY" && NF == 8 { print $2 "," label "," target ",,,," $3 "," $4 "," $5 "," $6 "," $7 "," $8 }' "$work_dir/console.log" >> "$output"
        current="$next_frequency"
        elapsed=$(awk -v e="$elapsed" -v d="$chunk_end" 'BEGIN { printf "%.3f", e+d }')
      done
      sleep "$pause"
    }
    random_bow_string() {
      local label="$1" target="$2" start_hz="$3" spread="$4"; shift 4
      local current="$start_hz" offset direction delta next_frequency index jump event_type measured_cents
      for index in {1..9}; do
        local stroke_start="$current"
        event_type=continuous
        measured_cents=$(awk -F, '$1 == "TONIC_DISPLAY" && $6 != "" { value=$6 } END { print value }' "$work_dir/console.log")
        if [[ -n "$measured_cents" ]] && awk -v c="$measured_cents" -v tolerance="$target_tolerance_cents" 'BEGIN { exit !(c >= -tolerance && c <= tolerance) }'; then
          event_type=hold
          stroke_start="$target"
          next_frequency="$target"
          run_dynamic_bow "$label" "$target" "$event_type" "$current" "$stroke_start" "$duration" "$pause"
          current="$next_frequency"
          continue
        fi
        # Every third stroke may jump across static friction before the bow
        # continues with a continuous correction.
        if (( index % 3 == 0 )); then
          jump=$(awk -v r="$((25 + RANDOM % 35))" -v spread="$spread" 'BEGIN { printf "%.3f", spread * r / 100 }')
          stroke_start=$(awk -v f="$current" -v t="$target" -v j="$jump" 'BEGIN { printf "%.3f", f + (f < t ? j : -j) }')
          event_type=jump
        fi
        if [[ -n "$measured_cents" ]] && awk -v c="$measured_cents" 'BEGIN { exit !(c > 0) }'; then direction=-1
        elif [[ -n "$measured_cents" ]] && awk -v c="$measured_cents" 'BEGIN { exit !(c < 0) }'; then direction=1
        else
          offset=$(awk -v f="$stroke_start" -v t="$target" 'BEGIN { print f-t }')
          if (( $(awk -v o="$offset" 'BEGIN { print (o > 0) }') )); then direction=-1
          elif (( $(awk -v o="$offset" 'BEGIN { print (o < 0) }') )); then direction=1
          else direction=$(( RANDOM % 2 ? 1 : -1 )); fi
        fi
        delta=$(awk -v r="$((12 + RANDOM % 89))" -v spread="$spread" 'BEGIN { printf "%.3f", spread * r / 100 }')
        next_frequency=$(awk -v f="$stroke_start" -v d="$delta" -v direction="$direction" 'BEGIN { printf "%.3f", f + direction*d }')
        run_dynamic_bow "$label" "$target" "$event_type" "$current" "$stroke_start" "$duration" "$pause"
        current="$next_frequency"
      done
      # Finish with repeated target bows; actual attainment is judged by phone cents.
      run_dynamic_bow "$label" "$target" hold "$current" "$target" 2.0 0.2
      run_dynamic_bow "$label" "$target" hold "$target" "$target" 2.0 0.2
      run_dynamic_bow "$label" "$target" hold "$target" "$target" 2.0 0.2
    }
    random_bow_string violin-bow-G3 196 190 10
    random_bow_string violin-bow-D4 293.66 285 14
    random_bow_string violin-bow-A4 440 432 18
    random_bow_string violin-bow-E5 659.25 657 4
fi
if [[ "$scenario" != jumps && "$scenario" != random && "$scenario" != sweep-linear && "$scenario" != sweep-quadratic && "$scenario" != violin && "$scenario" != violin-feedback && "$scenario" != violin-bow && "$scenario" != all ]]; then
    print -u2 "TONIC_STRESS_SCENARIO must be jumps, random, sweep-linear, sweep-quadratic, violin, violin-feedback, violin-bow, or all"
    exit 2
fi

printf 'wrote %s\n' "$output"
