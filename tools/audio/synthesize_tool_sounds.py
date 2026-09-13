"""Original main-tool sound bank. Generates every sample; reads no recordings.

One jackhammer sample represents ONE contact. The game schedules the three
contacts, so no prerecorded triple burst can outlive the mining deadline.
"""
import json
import math
import hashlib
from pathlib import Path
import random
from synthesize_mining_sounds import RATE, ROOT, new_sound, resonator, contact, metal, finish, save, statistics

ASSETS = ROOT / "assets" / "audio" / "tools"
TOOLS = ["pickaxe", "axe", "hammer", "jackhammer", "drill", "gold_pickaxe"]
PROFILE = {
    "pickaxe": (1.00, 2100, 0.057, 0.32),
    "axe": (0.86, 1260, 0.032, 0.25),
    "hammer": (0.64, 660, 0.068, 0.37),
    "jackhammer": (1.17, 1830, 0.020, 0.18),
    "drill": (1.42, 3190, 0.018, 0.17),
    "gold_pickaxe": (0.93, 2570, 0.068, 0.39),
}


def pcm_import(name):
    """Keep transient-rich hits as PCM instead of Godot's default lossy QOA."""
    sidecar = ASSETS / f"{name}.wav.import"
    if sidecar.exists():
        import re
        text = re.sub(r"compress/mode=\d+", "compress/mode=0", sidecar.read_text(encoding="utf-8"))
    else:
        source = "res://" + (ASSETS / f"{name}.wav").relative_to(ROOT).as_posix()
        digest = hashlib.md5(source.encode("utf-8")).hexdigest()
        destination = f"res://.godot/imported/{name}.wav-{digest}.sample"
        text = (f'[remap]\n\nimporter="wav"\ntype="AudioStreamWAV"\npath="{destination}"\n'
                f'\n[deps]\n\nsource_file="{source}"\ndest_files=["{destination}"]\n'
                '\n[params]\n\nforce/8_bit=false\nforce/mono=false\nforce/max_rate=false\n'
                'force/max_rate_hz=48000\nedit/trim=false\nedit/normalize=false\n'
                'edit/loop_mode=0\nedit/loop_begin=0\nedit/loop_end=-1\ncompress/mode=0\n')
    sidecar.write_text(text, encoding="utf-8")


def strike(sound, tool, variant, start=0.0, level=1.0, pan=0.0):
    pitch, ring, decay, _ = PROFILE[tool]
    seed = 1947 + TOOLS.index(tool) * 173 + variant * 67
    detune = [0.977, 1.008, 1.037][variant % 3]
    contact(sound, start, 0.68 * level, pitch * detune, pan, seed)
    if tool == "hammer":
        for hz, amplitude, tail in [(71, .80, .042), (143, .53, .049), (291, .39, .041), (677, .25, .030)]:
            resonator(sound, start, hz * detune, amplitude * level, tail, pan, bend=hz * .30)
    elif tool == "axe":
        for hz, amplitude in [(203, .41), (483, .46), (1063, .28)]:
            resonator(sound, start + .002, hz * detune, amplitude * level, .021, pan, bend=-hz * .13)
        contact(sound, start + .012, .14 * level, 1.33, pan, seed + 7)
    elif tool == "jackhammer":
        resonator(sound, start, 186 * detune, .53 * level, .018, pan, bend=180, bend_time=.002)
        resonator(sound, start + .007, 1040, .28 * level, .012, pan)
        resonator(sound, start + .033, 403, .17 * level, .013, pan)
    elif tool == "drill":
        # Tiny tooth contacts and a quickly damped motor band, never a hiss bed.
        for i, offset in enumerate([.006, .015, .027, .043]):
            resonator(sound, start + offset, (1750 + i * 430) * detune, .19 * level, .009, pan, bend=450, bend_time=.003)
        for ratio, amplitude in [(1, .22), (2.04, .12), (3.17, .075)]:
            resonator(sound, start, 310 * ratio, amplitude * level, .025, pan, bend=130)
    elif tool == "gold_pickaxe":
        resonator(sound, start, 103, .48 * level, .043, pan, bend=35)
        metal(sound, start + .009, 3011 * detune, .19 * level, .038, pan, seed + 9)
    metal(sound, start + .001, ring * detune, (.32 if tool in ["axe", "hammer"] else .48) * level, decay, pan, seed)


def make(tool, kind, variant=0):
    duration = PROFILE[tool][3]
    if kind == "break":
        duration += .28
    elif kind == "ore":
        duration += .10
    elif kind == "swing":
        duration = .115 if tool not in ["jackhammer", "drill"] else .16
    sound = new_sound(duration)
    if kind == "swing":
        machine = tool in ["jackhammer", "drill"]
        rng = random.Random(22931 + TOOLS.index(tool))
        for i in range(20 if not machine else 8):
            hz = rng.uniform(260, 1250) if not machine else 190 + i * 96
            resonator(sound, .009 + i * .0018, hz, .055 / (1 + i * .07), .016 if not machine else .032,
                      bend=hz * .7, bend_time=.022, phase=rng.uniform(-math.pi, math.pi))
        return finish(sound, -8.0)
    strike(sound, tool, variant)
    if kind == "ore":
        metal(sound, .002, 2350 + 135 * variant, .55, .058, seed=6197 + variant)
    if kind == "break":
        for i, delay in enumerate([.023, .063, .103, .159, .221, .293]):
            contact(sound, delay, .36 * math.exp(-i * .34), .75 + i * .12, (-1 if i % 2 else 1) * .27, 6311 + i * 7)
    return finish(sound, -3.8 if kind != "break" else -3.3)


def main():
    bank = {}
    report = {"source": "Pure synthesis; no recorded source PCM", "sample_rate": RATE, "sounds": {}}
    code = ['extends RefCounted', '## Offline-authored 48 kHz stereo PCM. No loading or synthesis on impact.', 'const BANKS := {']
    for tool in TOOLS:
        names = []
        for kind, count in [("hit", 3), ("ore", 2), ("break", 1), ("swing", 1)]:
            for variant in range(count):
                name = f"{tool}_{kind}_{variant+1:02}"
                pcm = make(tool, kind, variant)
                save(ASSETS / f"{name}.wav", pcm)
                pcm_import(name)
                bank[name] = pcm
                report["sounds"][name] = statistics(pcm)
                names.append(name)
        resource = lambda name: f'preload("res://assets/audio/tools/{name}.wav")'
        code += [f'\t"{tool}": {{',
                 '\t\t"hits": [' + ', '.join(resource(n) for n in names[:3]) + '],',
                 '\t\t"ores": [' + ', '.join(resource(n) for n in names[3:5]) + '],',
                 '\t\t"break": ' + resource(names[5]) + ',',
                 '\t\t"swing": ' + resource(names[6]), '\t},']
        # Six listening examples at the same approximate gains used in-game.
        preview = bytearray(b'\x00' * int(RATE * .12) * 4)
        import array
        for name in names[:6]:
            values = array.array('h', bank[name])
            preview.extend(array.array('h', (round(v * .40) for v in values)).tobytes())
            preview.extend(b'\x00' * int(RATE * .25) * 4)
        save(ROOT / 'artifacts' / f'tool_sound_{tool}.wav', preview)
        print(f'AUTHORED {tool}: 7 distinct PCM files', flush=True)
    code += ['}', '']
    (ROOT / 'scripts' / 'tool_audio_bank.gd').write_text('\n'.join(code), encoding='utf-8')
    (ASSETS / 'manifest.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(f'TOOL_AUDIO_OK files={len(bank)}', flush=True)


if __name__ == '__main__':
    main()
