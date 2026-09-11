"""Suppress background music, then prepare ore contact and discovery samples.

Usage: python tools/audio/prepare_ore_reference.py "path/to/Ore Sound Ref_.wav"
The supplied stereo 44.1 kHz float WAV is converted to portable 16-bit PCM.
All processing is offline, with only the Python standard library.
"""

import argparse
import array
import math
from pathlib import Path
import struct
import statistics
import sys
import wave

from spectral_tools import stft, istft


def read_reference(path):
    raw = path.read_bytes()
    if raw[:4] != b"RIFF" or raw[8:12] != b"WAVE":
        raise ValueError("Expected RIFF/WAVE")
    position = 12
    format_info = None
    while position + 8 <= len(raw):
        chunk, size = struct.unpack_from("<4sI", raw, position)
        position += 8
        if position + size > len(raw):
            raise ValueError("Incomplete WAV chunk")
        if chunk == b"fmt ":
            format_info = struct.unpack_from("<HHIIHH", raw, position)
        if chunk == b"data":
            data = raw[position:position + size]
            break
        position += size + size % 2
    else:
        raise ValueError("No audio data")
    if format_info != (3, 2, 44100, 352800, 8, 32) or len(data) % 8:
        raise ValueError("Expected stereo 44.1 kHz 32-bit IEEE float samples")
    samples = array.array("f", data)
    if sys.byteorder != "little":
        samples.byteswap()
    if not all(math.isfinite(sample) for sample in samples):
        raise ValueError("Non-finite audio sample")
    return samples


def suppress_background_music(samples):
    """Keep short spectral events while attenuating sustained notes and bass.

    HPSS cannot identify musical meaning; this mask deliberately prioritizes
    the slot transients over sustained ringing. One shared mask preserves the
    original stereo phase instead of cancelling the centre channel.
    """
    rate, size, hop = 44100, 2048, 256
    mid = [(left + right) * 0.5 for left, right in zip(samples[::2], samples[1::2])]
    side = [(left - right) * 0.5 for left, right in zip(samples[::2], samples[1::2])]
    mid_frames = stft(mid, size, hop)
    side_frames = stft(side, size, hop)
    magnitude = [[math.sqrt(abs(m) ** 2 + abs(s) ** 2) for m, s in zip(mf, sf)]
                 for mf, sf in zip(mid_frames, side_frames)]
    rows, bins = len(magnitude), len(magnitude[0])
    # 296 ms temporal median identifies stable notes; a 366 Hz frequency
    # median identifies broad contact energy. The Wiener-style mask leaves
    # ambiguous energy out instead of mixing the original music back in.
    harmonic = [[statistics.median(magnitude[j][k] for j in range(max(0, t - 25), min(rows, t + 26)))
                 for k in range(bins)] for t in range(rows)]
    percussive = [[statistics.median(frame[max(0, k - 8):min(bins, k + 9)])
                  for k in range(bins)] for frame in magnitude]
    bass_filter = [0.0 if k == 0 else 1.0 / math.sqrt(1.0 + (950.0 / (k * rate / size)) ** 8)
                   for k in range(bins)]
    masks = [[p * p / (p * p + (3.0 * h) ** 2 + 1e-20) * bass_filter[k]
              for k, (p, h) in enumerate(zip(pf, hf))] for pf, hf in zip(percussive, harmonic)]
    masks = [[frame[max(0, k - 1)] * 0.25 + frame[k] * 0.5 + frame[min(bins - 1, k + 1)] * 0.25
              for k in range(bins)] for frame in masks]
    clean_mid = istft([[value * gain for value, gain in zip(frame, mask)]
                      for frame, mask in zip(mid_frames, masks)], len(mid), size, hop)
    clean_side = istft([[value * gain for value, gain in zip(frame, mask)]
                       for frame, mask in zip(side_frames, masks)], len(side), size, hop)
    cleaned = array.array("f", (value for m, s in zip(clean_mid, clean_side) for value in (m + s, m - s)))
    if max(abs(value) for value in cleaned) < 1e-5:
        raise ValueError("No usable effect remains after music suppression")
    return cleaned


def make_clip(samples, search_start, search_end, duration, peak_db, onset_samples=None):
    rate = 44100
    # Music suppression must not move the original contact timing.
    timing = samples if onset_samples is None else onset_samples
    onset = next(frame for frame in range(round(search_start * rate), round(search_end * rate))
                 if max(abs(timing[frame * 2 + channel]) for channel in range(2)) > 0.08)
    start = max(0, onset - round(rate * 0.003))
    end = min(len(samples) // 2, start + round(rate * duration))
    clip = samples[start * 2:end * 2]
    gain = 10 ** (peak_db / 20) / max(abs(sample) for sample in clip)
    output = array.array("h")
    for frame in range(end - start):
        fade = max(0.0, min(1.0, frame / (rate * 0.001), (end - start - 1 - frame) / (rate * 0.024)))
        for channel in range(2):
            sample = clip[frame * 2 + channel] * gain * fade
            output.append(round(max(-1.0, min(1.0, sample)) * 32767))
    assert output[0] == output[1] == output[-2] == output[-1] == 0
    assert max(abs(sample) for sample in output) < 32767
    if sys.byteorder != "little":
        output.byteswap()
    return output.tobytes(), start / rate, (end - start) / rate


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    args = parser.parse_args()
    samples = read_reference(args.source)
    cleaned = suppress_background_music(samples)
    destination = Path(__file__).resolve().parents[2] / "assets" / "audio"
    destination.mkdir(parents=True, exist_ok=True)
    for name, start, end, duration, peak in [
        ("ore_hit_01", 0.0, 0.09, 0.31, -6.0),
        ("ore_hit_02", 0.60, 0.65, 0.34, -6.0),
        ("ore_hit_03", 1.40, 1.47, 0.32, -6.0),
        ("ore_discovery", 0.0, 0.09, len(samples) / 88200, -5.0),
    ]:
        pcm, actual_start, actual_duration = make_clip(cleaned, start, end, duration, peak, onset_samples=samples)
        with wave.open(str(destination / (name + ".wav")), "wb") as output:
            output.setparams((2, 2, 44100, 0, "NONE", "not compressed"))
            output.writeframes(pcm)
        print(f"{name}: source {actual_start:.6f}s, duration {actual_duration:.6f}s, target peak {peak:.1f} dBFS")


if __name__ == "__main__":
    main()
