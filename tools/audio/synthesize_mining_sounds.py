"""Author clean mining effects using damped resonators, without source audio.

The references informed the contact envelope and resonant frequency ranges.
Every output sample is generated here: no recording, denoising, sample copying,
noise loop, convolution impulse response, or external package is used.

Usage: python tools/audio/synthesize_mining_sounds.py [--group all|stone|ore]
"""

import argparse
import array
import hashlib
import json
import math
from pathlib import Path
import random
import sys
import wave


RATE = 48000
ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "assets" / "audio"
TAU = math.tau


def new_sound(duration):
    return [[0.0] * round(duration * RATE) for _ in range(2)]


def resonator(sound, start, frequency, gain, decay, pan=0.0, attack=0.0007,
              bend=0.0, bend_time=0.004, phase=0.0):
    """A struck, exponentially damped mode; high modes damp independently.

    Equal-power panning has no inverted/delayed channels, so phone speakers
    retain the contact and ring when summing the stereo file to mono.
    The integrated pitch bend gives the first milliseconds a solid impact.
    """
    assert 0.0 < frequency + abs(bend) < RATE * 0.40
    first = round(start * RATE)
    last = min(len(sound[0]), first + math.ceil(decay * 12.0 * RATE))
    left = math.sqrt((1.0 - pan) * 0.5) * gain
    right = math.sqrt((1.0 + pan) * 0.5) * gain
    for i in range(first, last):
        t = (i - first) / RATE
        envelope = (1.0 - math.exp(-t / attack)) * math.exp(-t / decay)
        angle = TAU * (frequency * t + bend * bend_time * (1.0 - math.exp(-t / bend_time))) + phase
        value = math.sin(angle) * envelope
        sound[0][i] += value * left
        sound[1][i] += value * right


def contact(sound, start, gain, pitch=1.0, pan=0.0, seed=0):
    """Dry pick-to-stone knock, a short bite, and a few irregular tiny chips.

    Many quickly damped modes make the impact broad without a recorded hiss
    or a random-noise bed. Seeded variation changes the material, not timing.
    """
    rng = random.Random(seed)
    for hz, weight, decay in [(147, 0.60, 0.013), (383, 0.60, 0.012),
                              (673, 0.78, 0.017), (947, 0.53, 0.013),
                              (1357, 0.31, 0.008), (3191, 0.28, 0.0036)]:
        resonator(sound, start, hz * pitch, gain * weight, decay,
                  pan=pan, bend=hz * 0.16, bend_time=0.003)
    for i in range(20):
        hz = rng.uniform(620.0, 5800.0) * pitch
        resonator(sound, start, hz, gain * rng.uniform(0.035, 0.12),
                  rng.uniform(0.002, 0.0065), pan=pan,
                  bend=hz * 0.08, bend_time=0.0015, phase=rng.uniform(-math.pi, math.pi))
    for i, delay in enumerate([0.013, 0.028, 0.047]):
        chip_pan = max(-0.7, min(0.7, pan + rng.uniform(-0.3, 0.3)))
        for hz in [978.0, 1837.0, 3113.0]:
            resonator(sound, start + delay, hz * pitch * rng.uniform(0.92, 1.08),
                      gain * 0.095 / (1.0 + i), 0.008, pan=chip_pan)


def metal(sound, start, frequency, gain, decay, pan=0.0, seed=0):
    """Small struck metal/crystal: close beating modes and inharmonic facets.

    The strongest ore modes sit around 2.3–3.1 kHz like the slot contacts in
    the reference; sustained 180–540 Hz accompaniment is intentionally absent.
    """
    rng = random.Random(seed)
    for ratio, weight, damping in [(0.503, 0.14, 0.45), (1.0, 0.73, 1.0),
                                    (1.007, 0.20, 0.79), (1.328, 0.40, 0.72),
                                    (1.751, 0.19, 0.48), (2.141, 0.085, 0.29),
                                    (2.679, 0.035, 0.20)]:
        resonator(sound, start, frequency * ratio, gain * weight,
                  decay * damping, pan=max(-0.7, min(0.7, pan + rng.uniform(-0.055, 0.055))),
                  attack=0.00045, bend=frequency * 0.015, bend_time=0.002,
                  phase=rng.uniform(-0.20, 0.20))


def stone_hit(variant):
    duration = [0.29, 0.32, 0.34][variant]
    sound = new_sound(duration)
    pitch = [0.96, 1.01, 1.065][variant]
    contact(sound, 0.0, 0.72, pitch, seed=701 + variant * 61)
    # Tool-head ring follows the 2.1 / 2.3 / 2.6 kHz contacts measured in
    # Mining_sound_Ref.wav, with a damped stone body beneath the metal bite.
    for hz, weight, decay in [(663, 0.19, 0.039), (899, 0.13, 0.034),
                              ([2074, 2285, 2613][variant], 0.54, 0.061),
                              ([2074, 2285, 2613][variant] * 1.012, 0.09, 0.046),
                              (3719, 0.055, 0.022)]:
        resonator(sound, 0.001, hz, weight, decay * [0.91, 1.0, 1.07][variant])
    return sound


def stone_break():
    sound = new_sound(0.72)
    contact(sound, 0.0, 0.90, 0.88, seed=1723)
    resonator(sound, 0.0, 104.0, 0.40, 0.027, bend=48.0)
    resonator(sound, 0.001, 2777.0, 0.44, 0.059)
    # A few authored falling chunks make a split/crumble, without a long
    # broadband gravel recording or reverb masking the next strike.
    for i, (time, level, pitch, pan) in enumerate([
        (0.027, 0.61, 0.79, -0.24), (0.068, 0.67, 1.08, 0.31),
        (0.105, 0.55, 0.91, -0.42), (0.159, 0.37, 1.22, 0.43),
        (0.225, 0.23, 1.05, -0.28), (0.304, 0.14, 1.31, 0.30),
        (0.394, 0.075, 1.12, -0.20), (0.478, 0.034, 1.40, 0.14)
    ]):
        contact(sound, time, level, pitch, pan, seed=1931 + i * 71)
    return sound


def ore_hit(variant):
    sound = new_sound([0.34, 0.36, 0.38][variant])
    contact(sound, 0.0, 0.45, [0.97, 1.02, 1.06][variant], seed=2801 + variant * 73)
    metal(sound, 0.001, [2315.0, 2467.0, 2616.0][variant], 0.82,
          [0.063, 0.067, 0.070][variant], seed=3301 + variant)
    # A quiet secondary contact gives a tactile coin-like double tick.
    metal(sound, 0.019 + variant * 0.003, 3058.0, 0.12, 0.024,
          pan=[-0.13, 0.10, 0.02][variant], seed=3527 + variant)
    return sound


def ore_discovery():
    sound = new_sound(1.26)
    contact(sound, 0.0, 0.72, 0.94, seed=4103)
    metal(sound, 0.001, 2315.0, 0.44, 0.047, seed=4307)
    # A short slot-like payout cascade; isolated decaying impacts, no melody,
    # bass accompaniment, synth pad, recorded tail, or continuous noise bed.
    for i, (time, frequency, level, pan) in enumerate([
        (0.039, 2142.0, 0.29, -0.16), (0.084, 2616.0, 0.37, 0.22),
        (0.139, 2371.0, 0.32, -0.29), (0.206, 2896.0, 0.40, 0.30),
        (0.281, 2537.0, 0.31, -0.20), (0.363, 3058.0, 0.36, 0.20)
    ]):
        metal(sound, time, frequency, level, 0.043, pan, seed=4507 + i * 37)
    # A broader final ding delivers the reveal. Close upper modes shimmer
    # while decaying naturally, ending in digital silence rather than hiss.
    metal(sound, 0.450, 2616.0, 0.68, 0.092, pan=-0.065, seed=5101)
    metal(sound, 0.463, 3481.0, 0.28, 0.074, pan=0.11, seed=5323)
    resonator(sound, 0.450, 1308.0, 0.12, 0.073, pan=0.0)
    return sound


def finish(sound, peak_db):
    """Soft saturation, DC removal and silent boundaries; no dither hiss."""
    frames = len(sound[0])
    silence = round(0.008 * RATE)
    fade = round(0.040 * RATE)
    # The 25 Hz one-pole DC blocker has no impact on the metal resonance.
    pole = math.exp(-TAU * 25.0 / RATE)
    for channel in sound:
        previous_in = previous_out = 0.0
        for i, value in enumerate(channel):
            filtered = value - previous_in + pole * previous_out
            previous_in, previous_out = value, filtered
            remaining = frames - silence - 1 - i
            envelope = 0.0 if remaining <= 0 else math.sin(min(1.0, remaining / fade) * math.pi * 0.5) ** 2
            # Exact zero at both ends also protects imports with trimming off.
            envelope *= min(1.0, i / (0.00035 * RATE))
            # Rounded contact peaks give the body of each strike more weight
            # at the same peak level, with no hard clipping or runtime effect.
            channel[i] = math.tanh(filtered * 1.4) * envelope
    peak = max(abs(v) for channel in sound for v in channel)
    scale = 10.0 ** (peak_db / 20.0) / peak
    pcm = array.array("h", (round(value * scale * 32767.0)
                             for pair in zip(*sound) for value in pair))
    assert max(abs(v) for v in pcm) < 32767
    assert pcm[0] == pcm[1] == 0 and not any(pcm[-silence * 2:])
    if sys.byteorder != "little":
        pcm.byteswap()
    return pcm.tobytes()


def save(path, pcm):
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as output:
        output.setparams((2, 2, RATE, 0, "NONE", "not compressed"))
        output.writeframes(pcm)


def statistics(pcm):
    values = array.array("h", pcm)
    if sys.byteorder != "little":
        values.byteswap()
    normalized = [v / 32768.0 for v in values]
    return {
        "duration_seconds": len(values) / (2.0 * RATE),
        "sample_rate": RATE, "channels": 2, "bits": 16,
        "peak_dbfs": round(20 * math.log10(max(abs(v) for v in normalized)), 3),
        "rms_dbfs": round(10 * math.log10(sum(v * v for v in normalized) / len(values)), 3),
        "dc_offset": round(sum(normalized) / len(values), 9),
        "last_8ms_silent": not any(values[-round(RATE * 0.008) * 2:]),
        "sha256_pcm": hashlib.sha256(pcm).hexdigest()
    }


def export_preview(bank):
    """Representative game gains, including ore hits at the normal fire rate."""
    sequence = []
    if "mining_hit_01" in bank:
        sequence += [(f"mining_hit_{i + 1:02}", -8.5, 0.56) for i in range(3)]
        sequence += [("mining_break", -9.0, 1.10)]
    if "ore_hit_01" in bank:
        sequence += [(f"ore_hit_{i + 1:02}", -9.0, 0.62) for i in range(3)]
        sequence += [(f"ore_hit_{i % 3 + 1:02}", -10.0 + i * 0.4, 0.20) for i in range(6)]
        sequence += [("ore_discovery", -7.0, 1.75)]
    start = round(RATE * 0.15)
    length = start + sum(round(gap * RATE) for _, _, gap in sequence)
    channels = [[0.0] * length for _ in range(2)]
    timeline = []
    for name, gain_db, gap in sequence:
        values = array.array("h", bank[name])
        if sys.byteorder != "little":
            values.byteswap()
        gain = 10 ** (gain_db / 20.0)
        for i in range(len(values) // 2):
            for channel in range(2):
                channels[channel][start + i] += values[i * 2 + channel] * gain
        timeline.append({"sound": name, "start_seconds": round(start / RATE, 3), "game_gain_db": gain_db})
        start += round(gap * RATE)
    values = array.array("h", (round(v) for pair in zip(*channels) for v in pair))
    assert max(abs(v) for v in values) < 32767
    if sys.byteorder != "little":
        values.byteswap()
    preview = ROOT / "artifacts" / "synthesized_mining_preview.wav"
    save(preview, values.tobytes())
    return timeline


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--group", choices=["all", "stone", "ore"], default="all")
    args = parser.parse_args()
    designs = []
    if args.group in ["all", "stone"]:
        designs += [(f"mining_hit_{i + 1:02}", stone_hit(i), -6.0) for i in range(3)]
        designs += [("mining_break", stone_break(), -5.0)]
    if args.group in ["all", "ore"]:
        designs += [(f"ore_hit_{i + 1:02}", ore_hit(i), -6.0) for i in range(3)]
        designs += [("ore_discovery", ore_discovery(), -5.0)]
    bank = {}
    report = {"origin": "New procedural synthesis; no reference PCM reused", "sounds": {}}
    for name, sound, peak_db in designs:
        pcm = finish(sound, peak_db)
        save(ASSETS / (name + ".wav"), pcm)
        bank[name] = pcm
        report["sounds"][name] = statistics(pcm)
        print(name, json.dumps(report["sounds"][name]))
    report["preview_timeline"] = export_preview(bank)
    (ROOT / "artifacts" / "synthesized_audio_report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
