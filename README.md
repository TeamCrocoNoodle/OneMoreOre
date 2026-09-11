# OneMoreOre

Godot 4.7.2 / GDScript로 만든 3D 카툰 채굴 프로토타입.
`project.godot`을 열고 **F5**로 실행합니다. 게임 화면에는 돌, 곡괭이와 채굴 효과만 표시됩니다.

## 플레이

| 입력 | 채굴 | 돌 회전 / 조준 |
| --- | --- | --- |
| 마우스 + 키보드 | 왼쪽 클릭, 누르고 있기, Space | 오른쪽/가운데 버튼 드래그, 휠, WASD 또는 방향키 |
| 터치패드 | 클릭 또는 클릭 유지 | 두 손가락 스크롤, 보조 클릭 드래그 |
| 터치 화면 | 탭 또는 길게 누르기 | 한 손가락 드래그 |
| 컨트롤러 | A / Cross, 오른쪽 트리거, 오른쪽 범퍼 | 왼쪽 스틱·D-pad로 회전, 오른쪽 스틱으로 조준 |

`R`: 새 돌 생성. `F11`: 전체 화면 전환.

바깥층 38개, 중간층 30개, 안쪽층 24개의 독립적인 돌조각으로 구성됩니다. 조각마다 체력이 있으며 타격할수록 검은 균열이 자라고, 파괴되면 두께가 있는 조각이 떨어져 아래층이 드러납니다. 안쪽 보석을 직접 치면 돌이 무너지면서 보석이 나타나고, 잠시 후 새로운 돌이 생성됩니다.

돌·곡괭이·보석·파편은 실행 시 생성하는 원본 3D 메시입니다. 참고 이미지 파일이나 외부 유료 에셋은 포함하지 않습니다. 사운드는 시작할 때 WAV로 합성해 두고 재생합니다. UI, 판매, 업그레이드, 저장 기능은 이 프로토타입 범위에 포함하지 않습니다.

## 검증

Godot 실행 파일을 PATH에 등록한 경우:

```powershell
godot --headless --path . --log-file .godot/integration.log --script res://tests/validate_mining.gd
godot --path . --log-file .godot/capture.log -- --capture-sequence
```

첫 명령은 실제 물리 raycast와 입력 이벤트로 세 층의 채굴, 체력과 균열, 파괴 후 충돌 제거, 보석 중복 획득 방지, 재생성 시 정리, 입력 장치별 조작을 확인합니다. 두 번째 명령은 채굴을 자동 재생하고 `artifacts/`에 다섯 단계의 PNG와 가로·세로 화면 캡처를 저장합니다.

Windows / Godot 4.7.2 Compatibility 렌더러에서 실행 및 화면 검증을 수행했습니다. 입력 이벤트 자동 검증은 실제 Android·iOS 기기와 물리 컨트롤러 테스트를 대체하지 않습니다.

## 플랫폼

Windows, macOS, Linux, Android, iOS용 개발 export preset을 제공합니다. 공통 코드는 GDScript와 Compatibility 렌더러를 사용하며, 가로·세로 화면 비율에 맞춰 카메라와 곡괭이 배치를 조정합니다. 파편은 수량 제한이 있는 MultiMesh로 렌더링합니다.

현재 환경에는 Godot 4.7.2 export template과 Android SDK/JDK가 준비되어 있지 않아 플랫폼별 실행 패키지는 생성하지 않았습니다. Godot에서 일치하는 export template을 설치한 다음 `builds/` 아래로 내보낼 수 있습니다. Android는 SDK/JDK, iOS는 macOS의 Xcode 및 Apple 서명 설정이 필요합니다. 배포 전 bundle ID `com.onemoreore.prototype`와 각 플랫폼 서명 설정을 프로젝트에 맞춰 변경하세요.

컨트롤러 입력과 진동 설정의 엔진 동작은 [Godot 공식 문서](https://docs.godotengine.org/en/stable/tutorials/inputs/controllers_gamepads_joysticks.html)를 기준으로 합니다.
