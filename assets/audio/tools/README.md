# 주 도구 전용 채굴음

여섯 주 도구마다 일반 돌 타격 3종·보석 돌 타격 2종·파괴 1종·스윙 또는 기계 작동 1종을 직접 합성했습니다. 총 42개 WAV입니다. 이전 Mining/Ore 레퍼런스의 타격감과 금속 울림을 이어가되, 외부 녹음 구간이나 배경 음악은 사용하지 않습니다. 감쇠 진동자·공진 모드·짧은 날 접촉으로 파형 자체를 만듭니다.

| 파일 접두사 | 음색 |
|---|---|
| `pickaxe` | 짧은 강철 접촉과 돌의 몸통 울림 |
| `axe` | 날로 베는 마른 타격, 짧은 중음 공진 |
| `hammer` | 낮고 묵직한 충격과 굵은 파괴음 |
| `jackhammer` | 짧은 기계 타격, 공압부의 금속 반동 |
| `drill` | 빠른 날 접촉과 짧은 모터 공진 |
| `gold_pickaxe` | 묵직한 타격에 밝은 금속 울림 |

- 원본 및 Godot 재생 데이터: 48,000 Hz, 스테레오, PCM 16-bit, 무압축.
- 타격/보석 타격 최대 피크 −3.8 dBFS, 파괴 −3.3 dBFS, 작동 −8 dBFS. 게임에서 별도 볼륨으로 재생합니다.
- 파형 양끝 페이드 및 마지막 8 ms 무음, DC 제거, 클리핑 없음. [manifest.json](manifest.json)에 길이·레벨·PCM 해시를 기록합니다.
- 착암기 WAV는 한 타격입니다. 3점사는 게임의 실제 세 접촉 시점에서 재생하므로 종료 후 추가 타격음이 예약되어 남지 않습니다. 이미 친 소리의 짧은 감쇠만 자연스럽게 끝납니다.
- 파일은 [tool_audio_bank.gd](../../../scripts/tool_audio_bank.gd)에서 미리 불러오며, 장착 시 참조만 교체합니다. 14개 재생 노드를 재사용하고 보석 발견음용 재생 채널을 남깁니다.
- 보석 발견·회수·정산음은 기존 공통 효과음입니다.

재생성:

```powershell
python tools/audio/synthesize_tool_sounds.py
godot --headless --editor --path . --import
godot --headless --path . --script res://tests/validate_main_tools.gd
```

[합성 스크립트](../../../tools/audio/synthesize_tool_sounds.py)는 표준 Python 라이브러리만 사용합니다. 기존 합성 스크립트의 수학 함수만 공유하며 기존 녹음 PCM을 읽지 않습니다. `.wav.import`의 `compress/mode=0`을 유지해 Godot의 기본 QOA 압축으로 바뀌지 않게 합니다. `artifacts/tool_sound_<도구 ID>.wav`는 각 도구의 일반 타격·보석 타격·파괴를 차례로 들어볼 수 있는 별도 미리듣기 파일입니다.
