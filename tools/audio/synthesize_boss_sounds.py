"""Original boss impacts, abilities and stingers, synthesized without recordings."""
import array
import json
import math
from synthesize_mining_sounds import ROOT, RATE, new_sound, resonator, contact, metal, finish, save, statistics
import synthesize_tool_sounds as imports

OUT = ROOT / 'assets' / 'audio' / 'bosses'
BASE = [97, 173, 641, 233, 389, 71, 997]

def make(stage, event):
    duration = {'entry':1.15, 'hit':.24, 'break':.47, 'ability':.68, 'victory':1.45}[event]
    sound = new_sound(duration)
    hz = BASE[stage]
    seed = 160420 + stage * 719 + len(event)*47
    if event in ('hit','break'):
        contact(sound,.002,.48, .72+stage*.10,seed=seed)
        metal(sound,.008,hz*3.1,.23,.025 if event == 'hit' else .05,seed=seed)
        resonator(sound,.002,77+stage*8,.43,.028,bend=100)
        if event == 'break':
            for i in range(5): contact(sound,.04+i*.045,.19*math.exp(-i*.3),1.1+i*.11,pan=(i%2-.5)*.35,seed=seed+i)
    elif event == 'entry':
        for i, note in enumerate([1,1.34,1.78]):
            resonator(sound,.015+i*.23,max(82,hz*.44)*note,.5,.075,bend=90)
            metal(sound,.018+i*.23,hz*2.2*note,.24,.047,seed=seed+i)
        resonator(sound,.53,54,.65,.10,bend=80)
    elif event == 'ability':
        for i in range(6):
            at = .006+i*(.08 if stage not in (3,5) else .055)
            frequency = hz*(1+i*.19) if stage not in (0,5) else hz*(2-i*.16)
            resonator(sound,at,frequency,.36,.028,bend=hz*.3)
            if stage in (0,4,5): contact(sound,at,.20,.75+i*.13,seed=seed+i)
    else:
        for i, note in enumerate([1,1.25,1.5,2]):
            metal(sound,.01+i*.16,697*note*(1+stage*.035),.31,.065,seed=seed+i)
            resonator(sound,.015+i*.16,174*note,.25,.09)
    return finish(sound,-4.8)

def main():
    imports.ASSETS = OUT
    bank = ['extends RefCounted','## Offline-authored, uncompressed 48 kHz stereo PCM.','const CUES := {']
    report = {'source':'Original resonator synthesis; no recorded audio','sounds':{}}
    preview = bytearray()
    for stage in range(7):
        for event in ['entry','hit','break','ability','victory']:
            name = f'{stage}_{event}'
            pcm = make(stage,event)
            save(OUT / f'{name}.wav',pcm)
            imports.pcm_import(name)
            bank.append(f'\t"{name}": preload("res://assets/audio/bosses/{name}.wav"),')
            report['sounds'][name] = statistics(pcm)
            samples = array.array('h'); samples.frombytes(pcm)
            preview.extend(array.array('h',(round(x*.22) for x in samples)).tobytes())
            preview.extend(bytes(round(RATE*.18)*4))
    bank += ['}','']
    (ROOT/'scripts'/'boss_audio_bank.gd').write_text('\n'.join(bank),encoding='utf-8')
    (OUT/'manifest.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    save(ROOT/'artifacts'/'boss_sound_preview.wav',preview)
    print('BOSS_AUDIO_AUTHORED files=35 sample_rate=48000 channels=2 bits=16')

if __name__ == '__main__': main()
