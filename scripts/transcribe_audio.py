#!/usr/bin/env python3
"""Transcribe an audio file via Groq Whisper API and emit a timestamped transcript.

Usage:
    python3 transcribe_audio.py AUDIO OUTDIR

Requires env var GROQ_API_KEY. Long audio is auto-chunked with ffmpeg
(10-minute WAV pieces, ~19MB each) so the 25MB API upload limit is never hit.

Outputs written to OUTDIR:
    transcript.txt   one line per segment:  [HH:MM:SS - HH:MM:SS] text
    transcript.json  machine-readable segments {start, end, text}
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile

GROQ_URL = "https://api.groq.com/openai/v1/audio/transcriptions"
GROQ_MODEL = "whisper-large-v3-turbo"
CHUNK_SECONDS = 600          # 10-minute chunks (~19MB WAV, under 25MB API limit)
SINGLE_FILE_LIMIT = 570      # under ~9.5 min -> upload directly


def fmt_ts(sec: float) -> str:
    sec = int(sec)
    h, rem = divmod(sec, 3600)
    m, s = divmod(rem, 60)
    if h:
        return f"{h:02d}:{m:02d}:{s:02d}"
    return f"{m:02d}:{s:02d}"


def probe_duration(path: str) -> float:
    out = subprocess.check_output(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
         "-of", "default=noprint_wrappers=1:nokey=1", path],
        text=True).strip()
    return float(out)


def detect_proxy() -> str | None:
    """HTTP proxy usable by this process.

    Uses $https_proxy if set, else falls back to the macOS system proxy
    (e.g. Clash Verge) which terminal/launchd processes do not inherit.
    Needed where Groq blocks direct egress (HTTP 403 from CN networks).
    """
    for var in ("https_proxy", "HTTPS_PROXY", "http_proxy", "HTTP_PROXY", "all_proxy"):
        if os.environ.get(var):
            return os.environ[var]
    try:
        out = subprocess.run(["scutil", "--proxy"], capture_output=True, text=True,
                             timeout=5).stdout
        enabled = "HTTPSEnable : 1" in out or "HTTPEnable : 1" in out
        host = port = None
        for line in out.splitlines():
            key, _, val = line.partition(":")
            key, val = key.strip(), val.strip()
            if key == "HTTPSProxy" or (host is None and key == "HTTPProxy"):
                host = val
            if key == "HTTPSPort" or (port is None and key == "HTTPPort"):
                port = val
        if enabled and host and port:
            return f"http://{host}:{port}"
    except Exception:
        pass
    return None


def transcribe_file(path: str, api_key: str, language: str | None) -> dict:
    cmd = ["curl", "-s", "--max-time", "900", GROQ_URL,
           "-H", f"Authorization: Bearer {api_key}",
           "-F", f"file=@{path};type=audio/wav",
           "-F", f"model={GROQ_MODEL}",
           "-F", "response_format=verbose_json"]
    proxy = detect_proxy()
    if proxy:
        cmd += ["-x", proxy]
    if language:
        cmd += ["-F", f"language={language}"]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        sys.exit(f"curl failed: {result.stderr}")
    try:
        data = json.loads(result.stdout)
    except json.JSONDecodeError:
        sys.exit(f"Unexpected response from Groq: {result.stdout[:300]}")
    if "error" in data:
        sys.exit(f"Groq API error: {data['error']}")
    return data


def extract_segments(result: dict, offset: float) -> list:
    segs = result.get("segments") or []
    return [{"start": offset + s["start"], "end": offset + s["end"],
             "text": s["text"].strip()} for s in segs if s["text"].strip()]


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit(f"Usage: {sys.argv[0]} AUDIO OUTDIR")
    audio, outdir = sys.argv[1], sys.argv[2]
    api_key = os.environ.get("GROQ_API_KEY")
    if not api_key:
        sys.exit("ERROR: GROQ_API_KEY not set. Get a free key at https://console.groq.com/keys "
                 "then run: export GROQ_API_KEY=...")
    if not os.path.isfile(audio):
        sys.exit(f"ERROR: audio file not found: {audio}")
    if not shutil.which("ffmpeg"):
        sys.exit("ERROR: ffmpeg not found (brew install ffmpeg)")
    language = os.environ.get("TRANSCRIBE_LANGUAGE")  # optional: zh / en

    os.makedirs(outdir, exist_ok=True)
    duration = probe_duration(audio)
    print(f"Audio duration: {fmt_ts(duration)}", file=sys.stderr)

    if duration <= SINGLE_FILE_LIMIT:
        wav = os.path.join(outdir, "_full.wav")
        subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", audio,
                        "-ac", "1", "-ar", "16000", "-c:a", "pcm_s16le", wav], check=True)
        segments = extract_segments(transcribe_file(wav, api_key, language), 0.0)
        os.remove(wav)
    else:
        segments = []
        with tempfile.TemporaryDirectory() as tmp:
            pattern = os.path.join(tmp, "chunk_%03d.wav")
            subprocess.run(
                ["ffmpeg", "-y", "-v", "error", "-i", audio, "-ac", "1", "-ar", "16000",
                 "-c:a", "pcm_s16le", "-f", "segment", "-segment_time", str(CHUNK_SECONDS),
                 "-reset_timestamps", "1", pattern], check=True)
            chunks = sorted(os.path.join(tmp, f) for f in os.listdir(tmp))
            for i, chunk in enumerate(chunks):
                offset = i * CHUNK_SECONDS
                print(f"Transcribing chunk {i + 1}/{len(chunks)} "
                      f"(from {fmt_ts(offset)})...", file=sys.stderr)
                segments.extend(extract_segments(transcribe_file(chunk, api_key, language), offset))

    with open(os.path.join(outdir, "transcript.txt"), "w", encoding="utf-8") as f:
        for s in segments:
            f.write(f"[{fmt_ts(s['start'])} - {fmt_ts(s['end'])}] {s['text']}\n")
    with open(os.path.join(outdir, "transcript.json"), "w", encoding="utf-8") as f:
        json.dump(segments, f, ensure_ascii=False, indent=2)
    print(f"Done: {len(segments)} segments -> {outdir}/transcript.txt")


if __name__ == "__main__":
    main()
