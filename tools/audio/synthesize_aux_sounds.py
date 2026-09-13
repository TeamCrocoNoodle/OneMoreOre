"""Original auxiliary equipment sounds: resonators only, no source recordings."""
import json
import array
import math
import random
from synthesize_mining_sounds import ROOT, RATE, new_sound, resonator, contact, metal, finish, save, statistics
import synthesize_tool_sounds as imports

OUT = ROOT / "assets" / "audio" / "auxiliary"
DESIGNS = {
    "laser_ready": .26, "laser_fire": .36, "beer": .68,
    "detector_ready": .30, "detector_ping": .12,
    "crusher_ready": .30, "crusher_start": .44, "crusher_grind": .72, "crusher_finish": .38,
    "xray_scan": .46, "pin_ready": .27, "pin_spawn": .30,
    "pin_hit_01": .18, "pin_hit_02": .18, "pin_hit_03": .18, "pin_break": .46,
    "detonator_ready": .32, "detonator_blast": .66,
}

def make(name, duration):
    sound = new_sound(duration)
    seed = 9357 + list(DESIGNS).index(name)*139
    rng = random.Random(seed)
    if name == "laser_fire":
        for f, gain in [(1350,.40),(2300,.22),(170,.33)]:
            resonator(sound,.006,f,gain,.05,bend=f*2.2,bend_time=.06)
        contact(sound,.045,.35,1.25,seed=seed)
    elif name == "beer":
        metal(sound,.008,1392,.16,.032,seed=seed)
        for i in range(7):
            resonator(sound,.07+i*.059,260+i*29,.22,.015,bend=-120,bend_time=.005)
        metal(sound,.48,1847,.16,.025,seed=seed+3)
    elif name.startswith("detector") or name == "xray_scan":
        for i in range(1 if name == "detector_ping" else 3):
            resonator(sound,.006+i*.072,1080+i*227,.33,.017,bend=100,bend_time=.015)
            resonator(sound,.008+i*.072,2157+i*131,.08,.012)
    elif name.startswith("crusher"):
        ticks = 22 if name == "crusher_grind" else 6
        gap = .027 if ticks == 22 else .035
        for i in range(ticks):
            contact(sound,.007+i*gap,.31*math.exp(-i*.018),rng.uniform(.45,.94),seed=seed+i*19)
            resonator(sound,.011+i*gap,95+i%4*37,.24,.020,bend=60)
        if name == "crusher_finish": metal(sound,.18,1643,.17,.028,seed=seed)
    elif name.startswith("pin"):
        n = int(name[-2:])-1 if name.startswith("pin_hit") else 0
        contact(sound,.002,.38,.9,seed=seed)
        metal(sound,.001,1693+n*340,.54,.021,seed=seed)
        if name == "pin_break":
            resonator(sound,.005,86,.72,.035,bend=80)
            for i in range(5): contact(sound,.025+i*.048,.22,.7+i*.17,seed=seed+i)
    elif name == "detonator_blast":
        for hz,level in [(44,.66),(79,.71),(142,.45),(313,.25)]:
            resonator(sound,.005,hz,level,.065,bend=hz*2,bend_time=.013)
        for i in range(10): contact(sound,.012+i*.031,.40*math.exp(-i*.18),rng.uniform(.5,1.3),pan=rng.uniform(-.22,.22),seed=seed+i)
    else:
        contact(sound,.005,.30,.80,seed=seed)
        metal(sound,.033,1747 if name == "laser_ready" else 763,.25,.028,seed=seed)
    return finish(sound,-5.5 if "ping" in name else -4.5)

def main():
    imports.ASSETS = OUT
    report = {"source":"Original oscillator/resonator synthesis; no recorded PCM","sounds":{}}
    code = ['extends RefCounted','## Authored 48 kHz stereo PCM; preloaded before mining.','const CUES := {']
    preview = bytearray(b'\x00' * int(RATE * .20) * 4)
    timeline = []
    for name,duration in DESIGNS.items():
        pcm = make(name,duration)
        save(OUT / f"{name}.wav",pcm)
        imports.pcm_import(name)
        report["sounds"][name] = statistics(pcm)
        gain_db = -18.0 if name == "detector_ping" else (-9.5 if name == "detonator_blast" else -10.5)
        timeline.append({"cue": name, "start_seconds": len(preview)/(RATE*4), "duration_seconds": duration, "gain_db": gain_db})
        values = array.array('h')
        values.frombytes(pcm)
        preview.extend(array.array('h',(round(value*10**(gain_db/20)) for value in values)).tobytes())
        preview.extend(b'\x00' * int(RATE * .30) * 4)
        code.append(f'\t"{name}": preload("res://assets/audio/auxiliary/{name}.wav"),')
    code += ['}','']
    (ROOT / "scripts" / "aux_audio_bank.gd").write_text('\n'.join(code),encoding="utf-8")
    (OUT / "manifest.json").write_text(json.dumps(report,indent=2),encoding="utf-8")
    save(ROOT / "artifacts" / "auxiliary_sound_preview.wav",preview)
    (ROOT / "artifacts" / "auxiliary_sound_timeline.json").write_text(json.dumps(timeline,indent=2),encoding="utf-8")
    print(f"AUX_AUDIO_AUTHORED files={len(DESIGNS)} sample_rate={RATE}")

if __name__ == "__main__": main()
