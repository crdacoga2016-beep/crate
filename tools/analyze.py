#!/usr/bin/env python3
"""Crate audio analyzer.

Computes the musical features the AutoMix engine needs and writes them to
the app's support directory (or a path given with --out).

    python tools/analyze.py --root "C:\\Users\\me\\Music"
    python tools/analyze.py --root "D:\\Music" --limit 5
"""

from __future__ import annotations

import argparse
import json
import math
import os
import sys
import time
import traceback

import numpy as np

ANALYSIS_VERSION = 2

AUDIO_EXTENSIONS = {
    ".mp3",
    ".flac",
    ".m4a",
    ".aac",
    ".ogg",
    ".opus",
    ".wav",
    ".wma",
    ".aiff",
    ".ape",
}

NOTE_NAMES = [
    "C",
    "C#",
    "D",
    "Eb",
    "E",
    "F",
    "F#",
    "G",
    "Ab",
    "A",
    "Bb",
    "B",
]

MAJOR_PROFILE = np.array(
    [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
)
MINOR_PROFILE = np.array(
    [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]
)

MAJOR_CAMELOT = {11: 1, 6: 2, 1: 3, 8: 4, 3: 5, 10: 6, 5: 7, 0: 8, 7: 9, 2: 10, 9: 11, 4: 12}
MINOR_CAMELOT = {8: 1, 3: 2, 10: 3, 5: 4, 0: 5, 7: 6, 2: 7, 9: 8, 4: 9, 11: 10, 6: 11, 1: 12}


def default_output() -> str:
    appdata = os.environ.get("APPDATA")
    if appdata:
        return os.path.join(appdata, "com.crate", "crate", "analysis.json")
    return os.path.join(os.path.expanduser("~"), ".crate", "analysis.json")


def library_cache_path() -> str:
    return os.path.join(os.path.dirname(default_output()), "library_cache.json")


def find_ffmpeg() -> str:
    local = os.path.join(os.path.dirname(os.path.abspath(__file__)), "ffmpeg.exe")
    if os.path.exists(local):
        return local
    try:
        import imageio_ffmpeg

        return imageio_ffmpeg.get_ffmpeg_exe()
    except Exception:
        return "ffmpeg"


def load_audio(path: str, sr: int = 22050):
    import librosa

    try:
        return librosa.load(path, sr=sr, mono=True)
    except Exception:
        import subprocess
        import tempfile

        import soundfile as sf

        with tempfile.TemporaryDirectory() as tmp:
            wav = os.path.join(tmp, "decoded.wav")
            subprocess.run(
                [
                    find_ffmpeg(),
                    "-v",
                    "error",
                    "-y",
                    "-i",
                    path,
                    "-ac",
                    "1",
                    "-ar",
                    str(sr),
                    "-f",
                    "wav",
                    wav,
                ],
                check=True,
            )
            data, native_sr = sf.read(wav, dtype="float32")
        if getattr(data, "ndim", 1) > 1:
            data = data.mean(axis=1)
        return data, native_sr


def collect_files(root: str):
    result = []
    for dirpath, _dirnames, filenames in os.walk(root):
        for name in filenames:
            ext = os.path.splitext(name)[1].lower()
            if ext in AUDIO_EXTENSIONS:
                result.append(os.path.join(dirpath, name))
    result.sort()
    return result


def estimate_key(chroma_mean: np.ndarray):
    best = (-2.0, 0, False)
    for root in range(12):
        for is_minor, profile in ((False, MAJOR_PROFILE), (True, MINOR_PROFILE)):
            rotated = np.roll(profile, root)
            corr = float(np.corrcoef(chroma_mean, rotated)[0, 1])
            if corr > best[0]:
                best = (corr, root, is_minor)
    confidence, root, is_minor = best
    name = NOTE_NAMES[root] + (" minor" if is_minor else " major")
    number = (MINOR_CAMELOT if is_minor else MAJOR_CAMELOT)[root]
    camelot = f"{number}{'A' if is_minor else 'B'}"
    return {
        "keyRoot": root,
        "isMinor": is_minor,
        "key": name,
        "camelot": camelot,
        "keyConfidence": round(max(0.0, confidence), 4),
    }


def analyze_track(path: str, meter) -> dict:
    import librosa

    y, sr = load_audio(path)
    if y.size == 0:
        raise ValueError("empty audio")

    duration = float(librosa.get_duration(y=y, sr=sr))

    onset_env = librosa.onset.onset_strength(y=y, sr=sr, hop_length=512)
    onset_times = librosa.frames_to_time(
        np.arange(onset_env.size), sr=sr, hop_length=512
    )

    tempo, beat_frames = librosa.beat.beat_track(
        onset_envelope=onset_env,
        sr=sr,
        hop_length=512,
        trim=False,
    )
    tempo = float(np.atleast_1d(tempo)[0]) if np.size(tempo) else 0.0
    if not math.isfinite(tempo) or tempo <= 0:
        tempo = 120.0
    beat_times = librosa.frames_to_time(beat_frames, sr=sr, hop_length=512)

    rms = librosa.feature.rms(y=y, frame_length=2048, hop_length=512)[0]
    rms_times = librosa.frames_to_time(
        np.arange(rms.size), sr=sr, hop_length=512
    )
    peak = float(rms.max()) or 1e-9
    rms_norm = rms / peak

    audible = np.where(rms_norm > 0.02)[0]
    if audible.size:
        lead_in = float(rms_times[audible[0]])
        audible_end = float(rms_times[audible[-1]])
    else:
        lead_in = 0.0
        audible_end = duration

    stft = np.abs(librosa.stft(y, n_fft=2048, hop_length=512))
    freqs = librosa.fft_frequencies(sr=sr, n_fft=2048)
    low = stft[freqs < 150].mean(axis=0)
    low_times = librosa.frames_to_time(
        np.arange(low.size), sr=sr, hop_length=512
    )
    beat_low = (
        np.interp(beat_times, low_times, low)
        if beat_times.size
        else np.array([])
    )

    if beat_times.size >= 8 and beat_low.size:
        scores = []
        for offset in range(4):
            sample = beat_low[offset::4]
            scores.append(float(sample.mean()) if sample.size else 0.0)
        offset = int(np.argmax(scores))
        downbeats = beat_times[offset::4]
    else:
        downbeats = beat_times[:1]

    downbeats = [float(t) for t in downbeats]
    bar_length = 4.0 * 60.0 / tempo

    positive_onsets = onset_env[onset_env > 0]
    median_onset = (
        float(np.median(positive_onsets)) if positive_onsets.size else 0.0
    )
    strong_downbeats = []
    if downbeats and median_onset > 0:
        strengths = np.interp(downbeats, onset_times, onset_env)
        strong_downbeats = [
            float(t)
            for t, strength in zip(downbeats, strengths)
            if strength >= 0.35 * median_onset
        ]

    if strong_downbeats:
        first_strong = strong_downbeats[0]
        last_strong = strong_downbeats[-1]
    else:
        first_strong = lead_in
        last_strong = audible_end

    beatless_intro = (first_strong - lead_in) > 6.0
    beatless_outro = (audible_end - last_strong) > 6.0

    if beatless_intro:
        mix_in = first_strong
    else:
        mix_in_candidates = [
            t for t in downbeats if t >= max(lead_in, 0.0)
        ]
        mix_in = mix_in_candidates[0] if mix_in_candidates else lead_in

    if beatless_outro:
        mix_out = min(audible_end, last_strong + bar_length)
    else:
        mix_out = audible_end

    if mix_out <= mix_in + 2 * bar_length:
        mix_out = min(audible_end, mix_in + 8 * bar_length)
    if mix_out <= mix_in:
        mix_out = audible_end

    chroma = librosa.feature.chroma_stft(
        y=y, sr=sr, n_fft=4096, hop_length=2048
    )
    chroma_mean = chroma.mean(axis=1)
    key = estimate_key(chroma_mean)

    mfcc = librosa.feature.mfcc(y=y, sr=sr, n_mfcc=13, hop_length=1024)
    zcr = float(librosa.feature.zero_crossing_rate(y, hop_length=1024).mean())
    centroid = float(
        librosa.feature.spectral_centroid(y=y, sr=sr, hop_length=1024).mean()
    )
    flatness = float(
        librosa.feature.spectral_flatness(y=y, hop_length=1024).mean()
    )
    rolloff = float(
        librosa.feature.spectral_rolloff(y=y, sr=sr, hop_length=1024).mean()
    )
    features = [
        round(float(value), 4)
        for value in list(mfcc.mean(axis=1))
        + list(mfcc.std(axis=1))
        + list(chroma_mean)
        + [zcr, centroid, flatness, rolloff]
    ]

    try:
        lufs = float(meter.integrated_loudness(y))
        if not math.isfinite(lufs):
            lufs = None
    except Exception:
        lufs = None

    energy = float(np.clip(float(rms_norm.mean()), 0.0, 1.0))
    peak_db = 20.0 * math.log10(max(float(np.abs(y).max()), 1e-9))

    return {
        "version": ANALYSIS_VERSION,
        "bpm": round(tempo, 3),
        "beatsPerBar": 4,
        "barLength": round(bar_length, 4),
        "downbeats": downbeats,
        "downbeatPhase": downbeats[0] if downbeats else 0.0,
        "duration": round(duration, 3),
        "leadIn": round(lead_in, 3),
        "audibleEnd": round(audible_end, 3),
        "mixIn": round(mix_in, 3),
        "mixOut": round(mix_out, 3),
        "beatlessIntro": bool(beatless_intro),
        "beatlessOutro": bool(beatless_outro),
        "features": features,
        "energy": round(energy, 4),
        "lufs": round(lufs, 2) if lufs is not None else None,
        "peakDb": round(peak_db, 2),
        **key,
    }


def main() -> int:
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

    parser = argparse.ArgumentParser(description="Analyze a local music library for Crate.")
    parser.add_argument(
        "--root",
        default=os.path.join(os.path.expanduser("~"), "Music"),
        help="Music folder to scan.",
    )
    parser.add_argument(
        "--out",
        default=default_output(),
        help="Destination analysis.json.",
    )
    parser.add_argument("--limit", type=int, default=0, help="Max tracks to analyze.")
    parser.add_argument("--force", action="store_true", help="Ignore cache.")
    parser.add_argument(
        "--library",
        action="store_true",
        help="Analyze every path in the app's library cache.",
    )
    args = parser.parse_args()

    if args.library:
        cache_path = library_cache_path()
        files = []
        if os.path.exists(cache_path):
            try:
                with open(cache_path, "r", encoding="utf-8") as handle:
                    cache = json.load(handle)
                if isinstance(cache, dict):
                    files = [path for path in cache.keys() if os.path.isfile(path)]
            except Exception:
                files = []
        if not files:
            print("no hay caché de biblioteca; usando --root")
            if not os.path.isdir(args.root):
                print(f"no existe la carpeta: {args.root}")
                return 1
            files = collect_files(args.root)
    else:
        if not os.path.isdir(args.root):
            print(f"no existe la carpeta: {args.root}")
            return 1
        files = collect_files(args.root)

    files.sort()
    if args.limit:
        files = files[: args.limit]
    if not files:
        print("no se encontraron archivos de audio")
        return 1

    try:
        import pyloudnorm as pyln

        meter = pyln.Meter(22050)
    except Exception:
        meter = None

    os.makedirs(os.path.dirname(args.out), exist_ok=True)

    data = {"version": 1, "root": args.root, "tracks": {}}
    if os.path.exists(args.out) and not args.force:
        try:
            with open(args.out, "r", encoding="utf-8") as handle:
                loaded = json.load(handle)
            if isinstance(loaded, dict) and isinstance(loaded.get("tracks"), dict):
                data = loaded
                data["version"] = 1
        except Exception:
            pass

    tracks = data["tracks"]
    started = time.time()
    done = 0
    skipped = 0

    def save():
        temporary = args.out + ".tmp"
        with open(temporary, "w", encoding="utf-8") as handle:
            json.dump(data, handle, ensure_ascii=False, indent=1)
        os.replace(temporary, args.out)

    for index, path in enumerate(files, start=1):
        try:
            stat = os.stat(path)
        except OSError:
            continue

        cached = tracks.get(path)
        if (
            not args.force
            and isinstance(cached, dict)
            and cached.get("version") == ANALYSIS_VERSION
            and cached.get("mtime") == stat.st_mtime
            and cached.get("size") == stat.st_size
        ):
            skipped += 1
            continue

        print(f"[{index}/{len(files)}] {os.path.basename(path)}", flush=True)
        try:
            result = analyze_track(path, meter)
            result["mtime"] = stat.st_mtime
            result["size"] = stat.st_size
            tracks[path] = result
            done += 1
            if done % 25 == 0:
                save()
                print(f"  guardado parcial ({done} nuevas)", flush=True)
        except Exception as error:  # noqa: BLE001
            print(f"  ! {error}", flush=True)
            if os.environ.get("CRATE_ANALYZE_DEBUG"):
                traceback.print_exc()

    save()

    elapsed = time.time() - started
    print(
        f"listo: {done} analizadas, {skipped} en caché, "
        f"{len(tracks)} totales en {elapsed:.1f}s"
    )
    print(f"salida: {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
