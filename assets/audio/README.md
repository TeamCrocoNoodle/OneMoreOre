# Mining reference samples

사용자가 제공한 `Mining_sound_Ref.wav`에서 네 타격을 분리했습니다. 원본 SHA-256: `d1f157a8002240906c8df6d69c196c4806866331ebafa309febc42f3b9a31160`.

| 파일 | 용도 | 원본 시작 지점 | 길이 | 피크 |
| --- | --- | ---: | ---: | ---: |
| `mining_hit_01.wav` | 일반 타격 | 0.881104초 | 0.34초 | -6 dBFS |
| `mining_hit_02.wav` | 일반 타격 | 1.553083초 | 0.57초 | -6 dBFS |
| `mining_hit_03.wav` | 일반 타격 | 2.268833초 | 0.64초 | -6 dBFS |
| `mining_break.wav` | 조각 파괴 | 3.409562초 | 0.90초 | -5 dBFS |

48 kHz·16-bit PCM·스테레오를 유지하며 Godot에서도 무압축으로 가져옵니다. 타격 앞 3 ms를 남겨 접촉 시점에 맞추고, 시작 1 ms와 끝 24 ms에 짧은 페이드를 적용했습니다. 타격 사이의 음량만 맞추며 EQ·리버브를 추가하지 않았습니다. 원본의 스트리밍용 WAV 길이 필드는 실제 PCM 길이로 다시 작성합니다.

일반 타격은 세 샘플을 직전과 다르게 선택하며 피치를 조금씩 바꿉니다. 파괴 순간에는 파괴 샘플 하나를 재생합니다. 소리는 시작할 때 불러오며 연속 채굴 중 파일 읽기나 샘플 합성을 하지 않습니다.

프로젝트 루트에서 재생성:

```powershell
python tools/audio/prepare_mining_reference.py "C:\path\to\Mining_sound_Ref.wav"
```
