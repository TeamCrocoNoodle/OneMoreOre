"""Historical reference-edit experiment, retained for offline comparison.

Run from the project root:
    python tools/audio/prepare_mining_reference.py path/to/Mining_sound_Ref.wav
Writes artifacts/reference_edits; the game uses synthesize_mining_sounds.py.
No third-party packages required.
"""

import argparse
import array
import math
from pathlib import Path
import struct
import sys
import wave


def read_pcm(path):
    raw = path.read_bytes()
    if raw[:4] != b"RIFF" or raw[8:12] != b"WAVE":
        raise ValueError("Expected a RIFF/WAVE file")
    offset = 12
    format_info = None
    while offset + 8 <= len(raw):
        chunk, size = struct.unpack_from("<4sI", raw, offset)
        offset += 8
        if chunk == b"fmt ":
            format_info = struct.unpack_from("<HHIIHH", raw, offset)
        elif chunk == b"data":
            # The supplied streaming WAV has 0xffffffff size placeholders.
            # Bound the payload to actual bytes and write ordinary WAV headers.
            pcm = raw[offset:offset + min(size, len(raw) - offset)]
            break
        offset += size + size % 2
    else:
        raise ValueError("No PCM data chunk")
    if format_info != (1, 2, 48000, 192000, 4, 16) or len(pcm) % 4:
        raise ValueError("Expected complete stereo, 48 kHz, 16-bit PCM frames")
    values = array.array("h", pcm)
    if sys.byteorder != "little":
        values.byteswap()
    return values


def extract(values, search_start, search_end, duration, peak_db):
    rate, channels = 48000, 2
    # Retain 3 ms before the first strong transient, including its attack.
    onset = next(frame for frame in range(int(search_start * rate), int(search_end * rate))
                 if max(abs(values[frame * channels + channel]) for channel in range(channels)) > 0.08 * 32768)
    start = onset - int(0.003 * rate)
    frames = min(int(duration * rate), len(values) // channels - start)
    result = values[start * channels:(start + frames) * channels]
    gain = 32767 * 10 ** (peak_db / 20) / max(abs(value) for value in result)
    for frame in range(frames):
        # A short boundary fade removes edit clicks without softening contact.
        fade = min(1.0, frame / (rate * 0.001), (frames - 1 - frame) / (rate * 0.024))
        for channel in range(channels):
            index = frame * channels + channel
            result[index] = round(result[index] * gain * max(fade, 0.0))
    return result, start / rate


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    args = parser.parse_args()
    values = read_pcm(args.source)
    destination = Path(__file__).resolve().parents[2] / "artifacts" / "reference_edits"
    destination.mkdir(parents=True, exist_ok=True)
    cuts = [
        ("mining_hit_01", 0.87, 0.92, 0.34, -6.0),
        ("mining_hit_02", 1.54, 1.60, 0.57, -6.0),
        ("mining_hit_03", 2.26, 2.32, 0.64, -6.0),
        ("mining_break", 3.40, 3.46, 0.90, -5.0),
    ]
    for name, start, end, duration, peak_db in cuts:
        clip, actual_start = extract(values, start, end, duration, peak_db)
        assert clip[0] == clip[1] == clip[-2] == clip[-1] == 0
        measured_peak = 20 * math.log10(max(abs(value) for value in clip) / 32768)
        if sys.byteorder != "little":
            clip.byteswap()
        with wave.open(str(destination / (name + ".wav")), "wb") as output:
            output.setparams((2, 2, 48000, 0, "NONE", "not compressed"))
            output.writeframes(clip.tobytes())
        print(f"{name}: source {actual_start:.6f}s, duration {duration:.2f}s, peak {measured_peak:.2f} dBFS")


if __name__ == "__main__":
    main()
