# Smart DICOM Viewer

Smart DICOM Viewer는 macOS용 네이티브 DICOM 뷰어입니다. 빠른 DICOM 로딩, 다중 패널 비교, MPR/MIP 보기, Window/Level 조정, 거리/각도/ROI 측정, DICOM 태그 확인을 지원합니다.

<img src="assets/README.ko_2026-07-09-07-42-53.png" width="700">

## 다운로드

- 최신 DMG: [Smart-DICOM-Viewer.dmg](https://github.com/brainok/smart-dicom-viewer-release/releases/latest/download/Smart-DICOM-Viewer.dmg)
- 릴리스 저장소: [brainok/smart-dicom-viewer-release](https://github.com/brainok/smart-dicom-viewer-release)
- 소스 저장소: [brainok/smart-dicom-viewer](https://github.com/brainok/smart-dicom-viewer)

## 설치

1. 최신 DMG를 다운로드합니다.
2. DMG를 열고 `Smart DICOM Viewer.app`을 `Applications` 폴더로 드래그합니다.
3. 앱을 실행합니다.

현재 배포본은 Developer ID로 서명되고 Apple notarization이 완료된 빌드입니다.

## 라이선스 활성화

- 처음 설치하면 30일 동안 전체 기능을 사용할 수 있습니다.
- 평가 기간 이후에는 Brainok 라이선스 코드 활성화가 필요합니다.
- 활성화는 `Smart DICOM Viewer` 메뉴의 `Activate License...`에서 할 수 있습니다.
- 최초 활성화에는 인터넷 연결이 필요합니다.
- 활성화 정보는 macOS Keychain에 저장되며, 활성화 후에는 오프라인에서도 사용할 수 있습니다.

## 주요 기능

- 빠른 DICOM 스캔 및 첫 이미지 표시
- 단일, 좌우, 상하, 4분할 다중 패널 레이아웃
- 시리즈 간 동기화 스크롤 및 줌
- MPR, MIP, MinIP, Average 볼륨 보기
- Window/Level 도구, 자동 W/L, ROI 기반 W/L
- 거리, 각도, ROI 통계 측정
- 패널 간 cross-reference line 표시
- DICOM 태그 인스펙터
- 커서 위치의 좌표 및 HU 값 표시
- 스크롤바 썸네일 미리보기
- DCMTK와 OpenJPEG 기반 JPEG 2000 압축 DICOM 지원
- DICOM 폴더 익명화 기능

## 기본 사용

- 파일 열기: `File` -> `Open...` 또는 `Cmd+O`
- DICOM 파일/폴더 열기: Finder에서 앱 창으로 드래그
- 패널 활성화: 패널 클릭
- 패널 전체화면 전환: 패널 더블 클릭
- DICOM 태그 보기: `T`
- 동기화 스크롤/줌: `L`
- cross-reference line: `X`
- 익명화: `File` -> `Anonymize Folder...` 또는 `Cmd+Shift+A`

## 키보드 단축키

탐색:

- `Up` / `Down`: 현재 시리즈의 이전/다음 이미지
- `Left` / `Right`: 이전/다음 시리즈
- `Scroll`: 슬라이스 이동
- `Page Up` / `Page Down`: 10장씩 이동
- `Home` / `End`: 첫 이미지/마지막 이미지로 이동
- `Tab`: 활성 패널 전환

레이아웃:

- `1` / `2` / `3` / `4`: 단일, 좌우, 상하, 4분할 레이아웃
- `Cmd+1` - `Cmd+4`: 메뉴 기반 레이아웃 전환
- `Cmd+Shift+M`: MPR 레이아웃
- `Cmd+Shift+L`: 패널 연결 토글

도구:

- `V`: 선택
- `P`: 이동
- `W`: Window/Level
- `Z`: 확대/축소
- `O`: ROI Window/Level
- `S`: ROI 통계
- `D`: 거리 측정
- `N`: 각도 측정
- `E`: 지우개

표시:

- `A`: 자동 Window/Level
- `I`: 이미지 반전
- `F`: 화면에 맞춤
- `R`: 보기 초기화
- `H`: 좌우 반전
- `]` 또는 `.`: 시계 방향 90도 회전
- `[` 또는 `,`: 반시계 방향 90도 회전

마우스:

- 왼쪽 클릭: 패널 활성화 또는 도구 동작
- 오른쪽 드래그: Window/Level 조정
- 휠 스크롤: 슬라이스 이동
- `Option` 또는 `Control` + 왼쪽 드래그: 이동
- `Option` 또는 `Control` + 스크롤: 확대/축소
- `Shift` + 클릭: 패널 그룹 선택
- Finder 또는 사이드바에서 드래그: 시리즈를 패널에 배치

## 개발

요구 사항:

- macOS 14.0 Sonoma 이상
- Xcode 15 이상 또는 Swift 5.9 이상
- Apple Silicon Mac, arm64 빌드 기준

빌드:

```bash
swift build
```

테스트:

```bash
swift test
```

앱과 DMG 패키징:

```bash
./scripts/package_app.sh
```

notarization까지 포함하려면 Keychain에 `OpenDicomViewer` notarytool 프로필이 필요합니다.

```bash
./scripts/package_app.sh --notarize
```

## 구조

```text
Sources/
  OpenDicomViewer/
    App.swift
    ContentView.swift
    DICOMModel.swift
    SimpleDICOM.swift
    MultiPanelContainer.swift
    PanelState.swift
    MPREngine.swift
    MetalVolumeRenderer.swift
    LicenseManager.swift
    HelpView.swift
    TagView.swift
  DCMTKWrapper/
    DCMTKHelper.mm
    include/DCMTKHelper.h
```

핵심 구조:

- `SimpleDICOM.swift`: 빠른 태그 읽기와 메타데이터 파싱
- `DCMTKWrapper`: 복잡한 transfer syntax와 압축 픽셀 데이터 디코딩
- `DICOMModel.swift`: 시리즈 로딩, 캐시, 패널 상태 조정
- `PanelState.swift`: 패널별 W/L, 줌, 도구, 메타데이터 상태
- `MPREngine.swift`와 `MetalVolumeRenderer.swift`: MPR 및 볼륨 렌더링
- `LicenseManager.swift`: 30일 평가판, Brainok 활성화, Keychain 저장

## 라이선스

소스 코드는 [MIT License](LICENSE)를 따릅니다. 배포 앱은 30일 평가판 이후 Brainok 라이선스 활성화를 사용합니다.

DCMTK는 BSD 라이선스, OpenJPEG는 BSD-2-Clause 라이선스를 따릅니다. 자세한 내용은 [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md)를 확인하세요.

## About

Open DICOM Viewer 에서 Fork 를 통해서 만든 앱은로
원 제작자는 연세의대 허준녕 교수임

https://github.com/ivmartel/dwv

Made by Hyo Suk Nam

- Email: [brainok777@gmail.com](mailto:brainok777@gmail.com)
- Store: [https://store.brainok.net](https://store.brainok.net)
