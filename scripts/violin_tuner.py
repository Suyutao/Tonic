#!/usr/bin/env python3
import csv
import math
import os
import random
import subprocess
import sys
import time

SAMPLE_RATE = 48000
CONTROL_INTERVAL = 0.05
TARGET_TOLERANCE = float(os.environ.get("TONIC_TARGET_TOLERANCE_CENTS", "1"))
DEVICE_LOG = sys.argv[1]
OUTPUT = sys.argv[2]
EVENTS = sys.argv[3]

strings = [("G3", 196.0, 190.0, 10.0), ("D4", 293.66, 285.0, 14.0),
           ("A4", 440.0, 432.0, 18.0), ("E5", 659.25, 657.0, 4.0)]
if os.environ.get("TONIC_VIOLIN_LIMIT_STRINGS"):
    strings = strings[:int(os.environ["TONIC_VIOLIN_LIMIT_STRINGS"])]
stroke_limit = int(os.environ.get("TONIC_VIOLIN_STROKES", "12"))
rng_duration = os.environ.get("TONIC_VIOLIN_DURATION")
rng = random.SystemRandom()

def latest_cents(path, position, label, target):
    try:
        with open(path, encoding="utf-8", errors="replace") as stream:
            stream.seek(position)
            data = stream.read()
            position = stream.tell()
    except OSError:
        return None, position
    value = None
    for line in data.splitlines():
        fields = line.split(",")
        if fields and fields[0] == "TONIC_CSV" and len(fields) == 5:
            data_writer.writerow([fields[1], label, "", fields[2], fields[3], fields[4], "", "", "", "", "", ""])
            output.flush()
        if len(fields) >= 7 and fields[0] == "TONIC_DISPLAY" and fields[5]:
            data_writer.writerow([fields[1], label, "", "", "", "", fields[2], fields[3], fields[4], fields[5], fields[6], fields[7]])
            output.flush()
            try:
                value = float(fields[5])
            except ValueError:
                pass
    return value, position

def write_samples(process, phase, start_hz, end_hz, seconds, amplitude):
    count = max(1, int(seconds * SAMPLE_RATE))
    frames = bytearray()
    for index in range(count):
        progress = index / max(1, count - 1)
        frequency = start_hz + (end_hz - start_hz) * progress * progress
        phase += 2.0 * math.pi * frequency / SAMPLE_RATE
        sample = int(32767 * amplitude * math.sin(phase))
        frames += int(sample).to_bytes(2, byteorder="little", signed=True)
        if len(frames) >= 8192:
            process.stdin.write(frames)
            process.stdin.flush()
            frames.clear()
    if frames:
        process.stdin.write(frames)
        process.stdin.flush()
    return phase

with open(OUTPUT, "w", newline="") as output, open(EVENTS, "w", newline="") as events:
    data_writer = csv.writer(output)
    event_writer = csv.writer(events)
    data_writer.writerow(["time", "scenario", "mac_raw", "app_raw", "app_smooth", "app_level", "display_frequency", "note_letter", "note_solfege", "cents", "chart_index", "chart_cents"])
    event_writer.writerow(["time", "string", "target_hz", "event_type", "previous_end_hz", "start_hz", "end_hz", "bow_duration", "reversal_pause", "phone_cents"])
    player = subprocess.Popen(["/opt/homebrew/bin/ffplay", "-nodisp", "-autoexit", "-hide_banner", "-loglevel", "error", "-f", "s16le", "-ar", str(SAMPLE_RATE), "-ch_layout", "mono", "-i", "-"], stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    phase = 0.0
    log_position = 0
    try:
        for label, target, current, spread in strings:
            previous_end = current
            for stroke in range(stroke_limit):
                bow_duration = float(rng_duration) if rng_duration else (rng.uniform(1.5, 3.0) if stroke < 9 else 2.0)
                reversal_pause = rng.uniform(0.1, 0.5)
                elapsed = 0.0
                event_type = "continuous"
                while elapsed < bow_duration:
                    cents, log_position = latest_cents(DEVICE_LOG, log_position, label, target)
                    if cents is not None and abs(cents) <= TARGET_TOLERANCE:
                        event_type = "hold"
                        desired = target
                    elif cents is not None:
                        desired = current * (2.0 ** (-cents / 1200.0))
                    else:
                        desired = target
                    if stroke % 3 == 2 and elapsed < CONTROL_INTERVAL:
                        jump = spread * rng.uniform(0.25, 0.60)
                        current += jump if (cents is not None and cents < 0) else -jump
                        event_type = "jump"
                    correction = max(-spread * 0.18, min(spread * 0.18, desired - current))
                    next_frequency = current + correction
                    duration = min(CONTROL_INTERVAL, bow_duration - elapsed)
                    timestamp = time.time()
                    try:
                        phase = write_samples(player, phase, current, next_frequency, duration, 0.42)
                    except BrokenPipeError as error:
                        raise RuntimeError("ffplay exited while receiving the continuous PCM stream") from error
                    # Keep control time aligned with audible time. Without this
                    # pause the pipe buffers the whole test before the phone
                    # can react, making feedback appear instantaneous.
                    time.sleep(duration)
                    event_writer.writerow([f"{timestamp:.3f}", label, f"{target:.3f}", event_type, f"{previous_end:.3f}", f"{current:.3f}", f"{next_frequency:.3f}", f"{bow_duration:.3f}", f"{reversal_pause:.3f}", "" if cents is None else f"{cents:.3f}"])
                    events.flush()
                    current = next_frequency
                    previous_end = current
                    elapsed += duration
                silence_count = int(reversal_pause * SAMPLE_RATE)
                player.stdin.write(b"\x00\x00" * silence_count)
                player.stdin.flush()
    finally:
        if player.stdin:
            try:
                player.stdin.close()
            except BrokenPipeError:
                pass
        try:
            player.wait(timeout=2)
        except subprocess.TimeoutExpired:
            player.terminate()
            player.wait()
print(f"wrote {OUTPUT}")
