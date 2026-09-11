# OneMoreOre

Godot 4.7.2 / GDScript로 만든 3D 카툰 채굴 프로토타입.
`project.godot`을 열고 **F5**로 실행합니다. 돌·곡괭이·채굴 효과와 함께 제한 시간, 보석함, 골드 정산 UI가 표시됩니다.

## 30초 채굴과 정산

첫 유효한 채굴 동작부터 **30초**가 시작됩니다. 상단 바와 숫자로 남은 시간을 표시하고, 마지막 5초에는 색과 짧은 소리로 마감을 알립니다. 창이 비활성화되면 시간과 채굴 입력이 잠시 멈춥니다.

일반 돌 조각은 완전히 부술 때 한 개로 기록합니다. 보석을 품은 조각과 파괴 파편은 일반 돌 개수에 중복 포함하지 않습니다. 보석은 소유 조각을 부순 순간 획득 내역에 기록되고, 실제 결정이 구멍에서 나온 뒤 오른쪽 아래 보석함으로 날아가 도착할 때 해당 등급 숫자가 올라갑니다.

시간이 끝나면 추가 타격을 막고 마지막 보석의 이동을 마친 뒤 정산합니다. 돌 조각부터 획득한 보석의 낮은 등급 순으로 수량×단가를 계산하며, 각 행과 합계가 짧은 효과음에 맞춰 증가합니다. 마지막 골드 금액은 한 번만 지급합니다. `결과 바로 보기`로 연출을 건너뛰어도 지급액은 같습니다. `다시 채굴하기`로 새 30초 라운드를 시작하며, 보유 골드는 실행 중 라운드 사이에 누적됩니다.

| 정산 항목 | 개당 Gold |
| --- | ---: |
| 일반 돌 조각 | 1 |
| 일반 보석 | 10 |
| 특별 보석 | 50 |
| 희귀 보석 | 200 |
| 전설 보석 | 1,000 |
| 신화 보석 | 5,000 |
| 고대 보석 | 25,000 |

시간 안에 원석을 전부 캐거나 `R`로 교체해도 그 라운드의 남은 시간과 이미 획득한 내역은 유지됩니다. 정산 창은 마우스·터치와 키보드/컨트롤러의 확인 버튼으로 조작할 수 있습니다. 현재는 골드의 라운드 간 누적까지 구현하며, 상점·업그레이드·저장은 아직 없습니다.

## 플레이

곡괭이는 마우스 커서(컨트롤러·터치에서는 조준 위치)를 계속 따라갑니다. 누르면 커서 근처에서 짧게 휘두르며, 휘두르는 중 커서를 옮겨도 현재 위치를 따라가 그곳을 타격합니다. 타격 후에도 현재 커서 옆에서 자세를 회복합니다.

| 입력 | 채굴 | 돌 회전 / 조준 |
| --- | --- | --- |
| 마우스 + 키보드 | 왼쪽 클릭, 누르고 있기, Space | 오른쪽/가운데 버튼 드래그, 휠, WASD 또는 방향키 |
| 터치패드 | 클릭 또는 클릭 유지 | 두 손가락 스크롤, 보조 클릭 드래그 |
| 터치 화면 | 탭 또는 길게 누르기 | 한 손가락 드래그 |
| 컨트롤러 | A / Cross, 오른쪽 트리거, 오른쪽 범퍼 | 왼쪽 스틱·D-pad로 회전, 오른쪽 스틱으로 조준 |

`R`: 남은 시간을 유지하며 무작위 돌 생성. `F11`: 전체 화면 전환. 시간 제한 없이 채굴을 확인하려면 `-- --mining-sandbox`로 실행합니다. 이 확인 모드에서는 `G`로 여섯 등급 확인용 돌을 생성할 수 있습니다.

기본 원석의 반지름은 **2.6**이며, 바깥부터 38·24·12개, 총 **3겹 74조각**으로 구성됩니다. 이전 확인용 원석(반지름 4.9, 322조각)보다 작게 줄였고, 화면에서도 작은 크기로 보이도록 카메라와 바닥 그림자를 맞췄습니다. 일반 조각은 2~4번 타격하면 깨지며, 보석을 품은 조각은 **16 HP**입니다. 검은 균열과 떨어지는 파편을 통해 손상을 확인할 수 있습니다.

처음 등장하는 기본 원석에는 **일반 보석 3개와 특별 보석 1개**가 들어갑니다. 현재 새로 생성되는 기본 원석도 같은 구성을 사용합니다. 보석의 희귀도와 최종 균열 빛 색은 다음과 같습니다.

| 희귀도 | 보석·빛 색 |
| --- | --- |
| 일반 | 흰색 |
| 특별 | 초록색 |
| 희귀 | 파란색 |
| 전설 | 노란색 |
| 신화 | 보라색 |
| 고대 | 빨간색 |

보석 모양의 변형은 희귀도와 별개이므로, 서로 다른 모양의 일반 보석도 모두 흰색입니다. 보석은 참고 이미지처럼 위쪽이 좁고 아래쪽이 두툼한 비대칭 입체로, 넓은 절단면과 얇게 다듬은 모서리가 있습니다. 돌과 같은 단계별 명암에 색이 짙은 내부 면과 시점에 따라 움직이는 반사를 더했습니다. 내부의 광학적 깊이는 불투명 셰이더로 표현하므로 배경이나 다른 돌이 보석을 뚫고 비치지 않습니다.

보석은 바깥층 아래 두 깊이에 두 개씩 숨깁니다. 깊이에 배정하는 희귀도와 실제 조각은 무작위로 고르며, 서로 다른 조각을 쓰고 방향도 떨어뜨려 배치합니다. 특별 보석의 위치나 깊이는 고정되지 않습니다. 보석마다 이를 품은 돌조각의 실제 내부 공간에 맞춰 넣으므로, 주변 조각을 제거하거나 돌을 돌려도 주인 조각을 부수기 전에는 보석이 보이거나 채굴되지 않습니다.

보석을 품은 조각의 체력이 0이 되면 **그 타격에서 보석을 즉시 자동 획득**합니다. 추가 클릭이나 보석 타격은 필요하지 않습니다. 획득음과 반짝임이 재생되고, 보석은 방금 깬 구멍에서 튀어나와 넓은 절단면을 보여 준 뒤 오른쪽 아래 보석함으로 날아갑니다. 이 연출 중에는 이미 획득된 상태이며 채굴 입력을 가로막지 않습니다. 다른 돌조각과 그 안의 보석은 그대로 유지됩니다. 시간 제한 없는 확인 모드에서는 기존의 상승·사라짐 연출을 사용합니다.

돌조각에는 큰 균열 묶음이 최대 두 개 생기며, 각 묶음은 세 갈래로 뻗습니다. 이후 타격은 가장 가까운 기존 금에 짧게 연결하고, 이미 금이 간 곳은 그 금을 깊게 만듭니다. 길이와 두께의 성장을 제한해 여러 번 때려도 돌 표면을 잔금으로 뒤덮지 않도록 했습니다. 보석을 품은 조각에서는 실제로 열린 균열을 따라 빛이 새며, 새로 때린 부위와 균열의 방향에 맞춰 빛줄기도 달라집니다. 보석을 담지 않은 주변 조각은 빛을 내지 않습니다. 돌의 회전과 타격 시 흔들림에도 균열과 빛이 함께 움직입니다.

균열은 굵은 두 갈래와 작은 곁가지를 가진 각진 경로로 자랍니다. 폭은 꺾임마다 불규칙하게 달라지고, 마지막 끝에서는 뾰족하게 좁아집니다. 양쪽 단면의 명암과 가운데의 어두운 틈으로 깊이를 표현합니다. 갈림길과 교차점에서는 균열의 윤곽을 합친 뒤 노출된 가장자리에만 단면을 만들어, 한 갈래의 벽이 다른 틈을 가로막지 않게 했습니다. 모서리 위치와 색도 이웃 단면끼리 공유해 연결하며, 균열이 둘러싼 돌 부분은 그대로 남습니다. 빛의 중심과 주변 번짐도 같은 폭과 가장자리를 사용하며, 파편은 이 균열의 경로를 따라 나뉩니다.

앞면뿐 아니라 경사진 모서리·옆면·뒷면도 실제 타격 위치에 금이 생깁니다. 길이와 폭은 기존 앞면 균열의 크기를 유지하며, 타격 위치에서 충분히 자란 금만 가까운 모서리를 넘어갑니다. 균열은 실제 메시의 이웃 면을 따라 꺾여 자라며, 모서리를 넘어갈 때 양쪽 면이 같은 경계를 공유합니다. 면에 붙은 균열을 실제 삼각형으로 잘라 돌 밖으로 떠다니지 않게 하고, 면의 경계에는 균열을 가로막는 단면을 만들지 않습니다. 꺾임의 안쪽 벽은 합쳐진 틈 안에서 연결하고, 양쪽 면이 만나는 곳도 같은 안쪽 끝점을 사용해 벽의 폭이 갑자기 사라지지 않게 했습니다. 이미 생긴 꺾임은 움직이지 않고 끝부분만 자랍니다. 조각의 연결 정보는 생성 시 저장하고 균열 메시 갱신은 타격 시에만 수행합니다.

빛줄기는 문틈에서 새어 나오는 빛처럼, 돌 안의 공통 광원에서 모든 실제 균열 선분을 통과해 넓은 빛띠로 펼쳐집니다. 밑변 양 끝은 금의 양 끝에 붙고, 연결된 균열은 멀리 뻗은 끝에서도 이어집니다. 보석의 수납 위치에 광원을 유지해 앞·옆·뒤 각 면의 바깥쪽으로 빛이 나가며, 공통 투영 배율에 제한을 두어 얕은 조각에서도 지나치게 벌어지지 않게 합니다. 균열 가까이는 밝고 멀어질수록 투명해지며, 곧은 경계도 먼 끝에서 살짝 부드러워집니다. 빛띠 사이의 어두운 간격을 남기고 균열 수에 따라 밝기를 조절해 돌 표면이 비쳐 보입니다. 좁은 틈 주변의 빛 번짐과 작은 마름모 반짝임이 이를 받쳐 줍니다.

체력이 0이 되면 누적된 균열을 경계로 돌조각이 여러 입체 파편으로 갈라집니다. 끊긴 균열 끝은 파괴 순간 가장자리까지 이어집니다. 파편의 앞면은 금 모양을 따르고, 두께는 각 파편의 폭과 면적에 맞춥니다. 뒤쪽은 비대칭으로 좁아지고 단면은 비스듬히 꺾여, 얇은 돌 부스러기와 두툼한 쐐기 모양이 섞여 나옵니다. 파편마다 다른 방향과 속도로 벌어져 회전하며 떨어지고, 새 단면은 밝은 돌 색으로 표시합니다. 파편 수와 수명에 제한을 두며, 돌을 초기화하면 남은 파편도 정리됩니다.

첫 타격의 빛은 항상 흰색이며, 체력이 줄수록 그 보석의 실제 등급까지 차례로 올라갑니다. 붉은 등급 보석이 든 조각은 1·4·6·9·11·13번째 타격에 각각 흰색·초록색·파란색·노란색·보라색·붉은색에 도달합니다. 타격 전에는 빛이 없고, 광선은 다른 돌에 가려집니다. 조각이 파괴되는 순간 균열 빛은 잔상 없이 즉시 사라지며, 돌 초기화 시 남은 빛과 획득 연출도 모두 정리됩니다.

**시작 시에는 작은 원석과 숨겨진 무작위 배치**를 사용합니다. `R` 또는 완전 채굴 후에도 새로운 무작위 기본 원석이 생성됩니다. 여섯 등급 확인용 큰 원석은 시간 제한 없는 확인 모드의 `G` 또는 `--capture-sequence`로 요청합니다. 이 확인용 배치에서는 앞면 여섯 조각 안에 등급별 보석을 하나씩 넣어 둡니다. 테스트는 `showcase_on_start = true`를 설정해 이 배치를 명시적으로 선택하거나 `round_enabled = false`로 채굴 동작만 검증할 수 있습니다.

무작위 돌은 중앙을 뚫는 것만으로 내용물을 전부 알 수 없습니다. 돌을 돌려 여러 면과 깊이를 탐색하세요. 모든 돌조각을 캐고 네 보석을 전부 꺼내면 잠시 뒤 새로운 무작위 돌이 생성됩니다. 누르고 있는 채굴 입력은 다음 돌에서도 이어집니다. 자동 검증에서는 고정 seed로 같은 배치를 재현합니다.

돌·곡괭이·보석·파편은 실행 시 생성하는 원본 3D 메시입니다. 참고 이미지 파일이나 외부 유료 에셋은 포함하지 않습니다. 일반 돌의 채굴·파괴음은 제공된 `Mining_sound_Ref.wav`, 보석이 든 돌의 타격·보석 발견음은 `Ore Sound Ref_.wav`에서 배경 음악 성분을 억제하고 편집한 [WAV 샘플](assets/audio/README.md)을 미리 불러와 재생합니다. 보석 돌 타격에는 짧은 샘플을 쓰고, 발견 순간에는 긴 샘플을 한 번 재생합니다. 곡괭이 휘두르기·돌 재생성 소리와 보석함 도착·카운트다운·정산 효과음은 시작할 때 합성해 재사용합니다. 새 보상 효과음은 배경 음악 없이 짧은 종소리와 코인 소리로 구성한 24 kHz 모노 PCM 16-bit이며, 타격 중에는 오디오를 합성하거나 새 재생 노드를 만들지 않습니다.

## 검증

Godot 실행 파일을 PATH에 등록한 경우:

```powershell
godot --headless --path . --log-file .godot/integration.log --script res://tests/validate_mining.gd
godot --headless --path . --log-file .godot/gem_light.log --script res://tests/validate_gem_light.gd
godot --headless --path . --log-file .godot/fracture.log --script res://tests/validate_fracture.gd
godot --headless --path . --log-file .godot/crack_outline.log --script res://tests/validate_crack_outline.gd
godot --headless --path . --log-file .godot/crack_surface.log --script res://tests/validate_crack_surface.gd
godot --headless --path . --log-file .godot/all_face_cracks.log --script res://tests/validate_all_face_cracks.gd
godot --headless --path . --log-file .godot/crack_wrap.log --script res://tests/validate_crack_wrap.gd
godot --headless --path . --log-file .godot/crack_coalesce.log --script res://tests/validate_crack_coalesce.gd
godot --headless --path . --log-file .godot/gems.log --script res://tests/validate_gems.gd
godot --path . --log-file .godot/gem_capture.log --script res://tests/capture_gems.gd
godot --path . --log-file .godot/capture.log -- --capture-sequence
godot --path . --log-file .godot/crack_capture.log --script res://tests/capture_cracks.gd
godot --path . --log-file .godot/all_face_capture.log --script res://tests/capture_all_face_cracks.gd
godot --path . --log-file .godot/starter_capture.log --script res://tests/capture_starter_ore.gd
godot --headless --path . --log-file .godot/round_validation.log --script res://tests/validate_round.gd
godot --headless --path . --log-file .godot/hud_validation.log --script res://tests/validate_mining_hud.gd
godot --headless --path . --log-file .godot/reward_audio_validation.log --script res://tests/validate_reward_audio.gd
godot --path . --log-file .godot/round_capture.log --script res://tests/capture_round.gd
godot --path . --log-file .godot/hud_capture.log --script res://tests/capture_mining_hud.gd
godot --headless --path . --log-file .godot/pickaxe_follow_validation.log --script res://tests/validate_pickaxe_follow.gd
godot --path . --log-file .godot/pickaxe_follow_capture.log --script res://tests/capture_pickaxe_follow.gd
```

첫 명령은 실제 물리 raycast와 입력 이벤트로 기본 원석 세 층의 채굴, 일반 3개·특별 1개의 내부 배치·소유 관계·은폐·등장·회수, 재생성 조건, 남은 효과 정리와 입력 장치별 조작을 확인합니다. 별도로 명시적 여섯 등급 확인용 배치도 검사합니다. 두 번째 명령은 여섯 등급의 체력별 색 전환, 타격 위치별 균열 누적, 실제 균열과 광선의 일치, 기존 피해 보존과 깊이 판정을 검증합니다. 세 번째 명령은 균열을 따른 파편 분할, 면적 보존, 입체 메시와 분리 동작·수량·수명을 검증합니다.

균열 외곽과 표면 검증은 Y·T·X 교차, 고리 안의 돌 부분, 떨어진 균열, 가늘어진 끝과 실제 타격 이력을 검사합니다. 내부를 가로막는 단면이 없는지, 단면이 균열 밖으로 나오지 않는지, 입력 선분 순서를 바꿔도 같은 외곽이 나오는지 확인합니다.

전체 면 검증은 실제 삼각형의 앞·옆·뒤 타격, 기존 크기와 1:1인 경로 길이, 표면에 붙은 균열과 모서리 연결, 각 면에서 나가는 빛, 기존 손상과 파괴 시 정리를 확인합니다. 매핑·병합 검증은 접힌 면의 길이·폭·피복, 캐시 무효화와 같은 평면의 패치를 합치기 전후의 일치를 확인합니다. 전체 면 캡처는 실제 채굴 raycast로 세 방향에서 각각 때린 뒤 여러 각도의 확대 화면과 빛을 저장합니다. `artifacts/allfaces_side15_junction.png`에는 옆면을 15번 때린 갈림길의 내부 벽면을 더 확대해 저장합니다.

보석 검증은 여섯 종류의 실제 메시·충돌체·수납 경계와 재구성, 등장 및 선택 상태를 확인합니다. 보석 캡처는 게임과 같은 조명으로 여섯 결정을 두 각도에서 렌더링하고, 강조 전후와 확대 화면을 `artifacts/gems_*.png`에 저장합니다.

`--capture-sequence` 명령은 보석이 든 한 조각의 서로 다른 세 위치를 번갈아 때리면서 여섯 빛줄기와 보석 등장·획득을 재생하고, 일반 돌조각의 파괴도 확인합니다. `artifacts/lights_*.png`에는 색 단계별 화면을, `artifacts/impacts_*.png`에는 첫 세 타격의 빛과 누적 균열을, `artifacts/fracture_*.png`에는 파괴 직전부터 파편이 벌어지고 떨어지는 화면을 저장합니다. `capture_cracks.gd`는 실제 돌을 확대해 1·3·8·15회 타격 후 빛이 가라앉은 균열, 발광 상태와 비스듬한 시점을 `artifacts/cracks_*.png`에 저장합니다.

`capture_starter_ore.gd`는 실제 무작위 시작 원석과 회전한 모습, 내부 일반·특별 보석을 물리 raycast로 채굴하는 과정, 재생성과 세로 화면을 `artifacts/starter_ore_*.png`에 저장합니다. 사용한 seed와 실제 숨김 위치는 `artifacts/starter_ore_report.json`에서 확인할 수 있습니다.

라운드 검증은 정확한 30초 만료, 종료 프레임의 예약 타격 차단, 마지막 보석의 이동과 한 번만 지급되는 정산, 원석 교체 시 획득 내역 보존, 다음 라운드의 시간·지갑·입력 초기화를 확인합니다. HUD 검증은 모든 등급과 빈 정산, 순차 계산·건너뛰기·버튼 및 가로·세로 배치를 확인합니다. 오디오 검증은 PCM 규격·파형 범위·캐시 재사용·동시 재생 제한을 검사합니다. `capture_round.gd`는 실제 원석에서 채굴한 돌과 네 보석으로 진행한 게임·비행·정산·다음 라운드를 `artifacts/round_*.png`에 저장하고, 수량과 지급액은 `artifacts/round_report.json`에 기록합니다. `capture_mining_hud.gd`는 여섯 등급 정산과 빈 정산을 포함한 UI 화면을 별도로 저장합니다.

Windows / Godot 4.7.2 Compatibility 렌더러에서 실행 및 화면 검증을 수행했습니다. 입력 이벤트 자동 검증은 실제 Android·iOS 기기와 물리 컨트롤러 테스트를 대체하지 않습니다.

성능 비교는 `godot --path . --script res://tests/profile_mining.gd -- --tag=check`로 실행합니다. 고정 배치에서 대기·회전·96회 타격·6회 파괴를 재생하고, 이미지 저장 비용을 제외한 프레임 간격과 타격 처리 시간을 `artifacts/profile_mining_check.json`에 기록합니다. 측정 중에만 VSync와 FPS 제한을 해제합니다.

균열 빛과 반짝임은 타격마다 메시를 한 번 만들고, 재생 중에는 [셰이더의 정점 속성](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/spatial_shader.html)을 이용해 움직입니다. 파괴 순간에는 보이지 않을 균열 메시 생성을 생략하며, 돌 생성 때 읽은 정점을 파편 계산에 재사용합니다. 충격파의 메시·재질·노드도 재사용하고, 활성 효과가 없으면 효과의 프레임 처리를 중단합니다.

보석·균열 빛·돌가루·충격파는 시작할 때 별도의 96×96 뷰포트에서 기존 메시·재질·조명·그림자로 한 프레임 렌더링합니다. [Compatibility 렌더러의 첫 표시 비용](https://docs.godotengine.org/en/stable/tutorials/rendering/jitter_stutter.html)을 첫 타격과 보석 발견보다 먼저 처리하기 위한 예열입니다. 이 뷰포트는 즉시 정리되며, 실제 보석의 위치·숨김·소유 상태와 획득 수는 바꾸지 않습니다.

## 플랫폼

Windows, macOS, Linux, Android, iOS용 개발 export preset을 제공합니다. 공통 코드는 GDScript와 Compatibility 렌더러를 사용하며, 가로·세로 화면 비율에 맞춰 카메라와 곡괭이 배치를 조정합니다. 작은 돌가루와 반짝임은 MultiMesh로, 균열을 따라 갈라진 큰 파편은 개별 메시로 렌더링하며 각각 수량을 제한합니다.

현재 환경에는 Godot 4.7.2 export template과 Android SDK/JDK가 준비되어 있지 않아 플랫폼별 실행 패키지는 생성하지 않았습니다. Godot에서 일치하는 export template을 설치한 다음 `builds/` 아래로 내보낼 수 있습니다. Android는 SDK/JDK, iOS는 macOS의 Xcode 및 Apple 서명 설정이 필요합니다. 배포 전 bundle ID `com.onemoreore.prototype`와 각 플랫폼 서명 설정을 프로젝트에 맞춰 변경하세요.

컨트롤러 입력과 진동 설정의 엔진 동작은 [Godot 공식 문서](https://docs.godotengine.org/en/stable/tutorials/inputs/controllers_gamepads_joysticks.html)를 기준으로 합니다.
