# Mining and ore reference samples

## Ordinary stone

사용자가 제공한 `Mining_sound_Ref.wav`에서 네 타격을 분리했습니다. 원본 SHA-256: `d1f157a8002240906c8df6d69c196c4806866331ebafa309febc42f3b9a31160`.

| 파일 | 용도 | 원본 시작 지점 | 길이 | 피크 |
| --- | --- | ---: | ---: | ---: |
| `mining_hit_01.wav` | 일반 타격 | 0.881104초 | 0.34초 | -6 dBFS |
| `mining_hit_02.wav` | 일반 타격 | 1.553083초 | 0.57초 | -6 dBFS |
| `mining_hit_03.wav` | 일반 타격 | 2.268833초 | 0.64초 | -6 dBFS |
| `mining_break.wav` | 조각 파괴 | 3.409562초 | 0.90초 | -5 dBFS |

48 kHz·16-bit PCM·스테레오를 유지하며 Godot에서도 무압축으로 가져옵니다. 타격 앞 3 ms를 남겨 접촉 시점에 맞추고, 시작 1 ms와 끝 24 ms에 짧은 페이드를 적용했습니다. 타격 사이의 음량만 맞추며 EQ·리버브를 추가하지 않았습니다. 원본의 스트리밍용 WAV 길이 필드는 실제 PCM 길이로 다시 작성합니다.

일반 타격은 세 샘플을 직전과 다르게 선택하며 피치를 조금씩 바꿉니다. 일반 돌 파괴 순간에는 파괴 샘플 하나를 재생합니다. 소리는 시작할 때 불러오며 연속 채굴 중 파일 읽기나 샘플 합성을 하지 않습니다.

프로젝트 루트에서 재생성:

```powershell
python tools/audio/prepare_mining_reference.py "C:\path\to\Mining_sound_Ref.wav"
```

## Gem-bearing stone and discovery

사용자가 제공한 `Ore Sound Ref_.wav`를 직접 편집했습니다. 원본 SHA-256: `51f7724603698da85bf430bdcf642b8e9064fa2f403aa413830571723628d404`.

| 파일 | 용도 | 원본 시작 지점 | 길이 | 피크 |
| --- | --- | ---: | ---: | ---: |
| `ore_hit_01.wav` | 보석 돌 타격 | 0초 | 0.31초 | -6 dBFS |
| `ore_hit_02.wav` | 보석 돌 타격 | 0.599909초 | 0.34초 | -6 dBFS |
| `ore_hit_03.wav` | 보석 돌 타격 | 1.397732초 | 0.32초 | -6 dBFS |
| `ore_discovery.wav` | 보석 발견·즉시 획득 | 0초 | 1.915533초 | -5 dBFS |

원본의 44.1 kHz·스테레오를 유지하고, 32-bit float를 16-bit PCM으로 변환했습니다. 원본에 섞인 배경 음악을 억제한 뒤 구간 편집·음량 정렬·시작 1 ms/끝 24 ms 페이드를 적용합니다. Godot에서 무압축으로 미리 불러오며 별도의 소리를 합성하지 않습니다.

음악 억제는 전체 음원에 [harmonic/percussive 분리](https://librosa.org/doc/0.11.0/generated/librosa.decompose.hpss.html)를 적용합니다. FFT 2048·hop 256, 시간 51프레임/주파수 17bin 중앙값, power 2·margin 3의 부드러운 마스크와 950 Hz 저음 억제를 사용합니다. 같은 마스크를 좌우 채널에 적용하고 원본 위상을 유지합니다. 지속되는 음정과 저음이 강하게 줄어들며, 슬롯 효과의 긴 울림도 일부 짧아집니다. 이는 믹스된 음원에서 음악을 억제하는 처리이며, 음악과 효과를 의미로 판별해 완전히 분리하는 방식은 아닙니다.

분석·분리는 샘플 제작 시에만 실행됩니다. 재생 중에는 추가 필터 계산이나 파일 읽기가 없습니다. `spectral_tools.py`의 순수 Python FFT/STFT를 사용하므로 별도 패키지 설치 없이 재생성할 수 있습니다.

보석 돌 타격은 세 샘플 중 직전과 다른 것을 고릅니다. 드러난 빛의 등급이 높아질수록 피치가 조금 올라가며, 피해가 누적되면 음량도 조금 커집니다. 이 타격에는 일반 돌 타격음이 겹치지 않습니다. 보석이 나오는 순간에는 발견 샘플 하나만 재생하며, 일반·특별 등급은 음량과 피치로 구분합니다. 발견 재생은 예약된 voice를 사용해 후속 채굴이 끊지 않게 합니다. 실제 보석 획득이 실패한 파괴에는 일반 파괴음을 사용합니다.

```powershell
python tools/audio/prepare_ore_reference.py "C:\path\to\Ore Sound Ref_.wav"
```
