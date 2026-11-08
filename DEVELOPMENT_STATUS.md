# DEVELOPMENT_STATUS

## Phase 1 — 프로젝트 기반과 육상 이동

### 구현
- Godot 4.7.2 Standard/GDScript/Compatibility 기준의 프로젝트 설정, main 장면, GameSession·SceneRouter 소유권 구조.
- 서울·인천 식별용 압축 지도, 단일 주인공, 직접 방향/클릭 이동, 카메라, 경계와 장애물 충돌, 동행 4슬롯 UI.
- 서울 사옥과 서울·인천 시청 출입구, 내부 장면, 나가기 후 출입구 복귀, 미구현 메뉴 비활성화.
- 위치·지역·동행자 ID 저장을 schema_version 1로 구성하고 임시 파일 검증 뒤 백업 교체.
- README에 실제 환경 확인 결과, 실행·저장·Windows 내보내기 방법, 임시 자산/미구현 범위를 기록.

### 실제 검증 결과
- PowerShell `Get-Command godot, godot4`, `where.exe godot`, 대표 설치 경로 확인: 실행 파일 없음.
- `%APPDATA%\Godot\export_templates` 경로는 존재하지만 내부 파일/버전이 없어 템플릿을 확인할 수 없음.
- 루트 최초 상태에는 project.godot, .git, 게임 소스가 없었음. Git 저장소 초기화는 하지 않았음.
- Godot 파싱/headless 장면 실행, Windows 내보내기, 마우스/키보드 조작 수동 확인은 엔진 부재로 미실행.
- 요청한 혼합 입력, 도달 불가 지점, 반복 출입, UI 클릭 차단, 저장 후 재실행 항목은 런타임 확인되지 않아 통과로 보고하지 않음.
- Phase 1 종료 시점에는 엔진 실행 검증을 대체하는 자체 검사 파일을 생성하지 않았음.

### 남은 범위
- 기획 기본안의 NavigationRegion2D/NavigationAgent2D 경로 탐색은 구현하지 않음. 직접 방향 이동과 장애물 충돌, 클릭 광선의 근접 도달점만 구성했으며 장애물 둘레 자동 우회는 없음.
- `.gitignore`와 `.gitattributes`만 추가. Git 메타데이터는 없으므로 초기화하지 않았음. export_presets.cfg도 템플릿/프리셋 상태를 알 수 없어 생성하지 않음.
- 지도·주인공·건물·내부 배경 및 인물 썸네일은 임시 도형/텍스트. 계좌·시장·경제·시간·전투·작업장은 비활성/미구현.
- Godot 실행 파일 및 해당 버전 템플릿이 확인되면 Phase 1 런타임 검증이 필요함.

### 다음 Phase
- 다음 Phase는 사용자 승인 전 착수하지 않음.

## Phase 2 — 시장 매매·인벤토리·계좌

### 구현
- `data/products.json`, `data/markets.json`: 기획안 6개 상품의 ID·기본가·지역 계수·1kg 중량, 서로 다른 서울/인천 시장 목록과 기존 시험 재고값.
- `game/core/game_session.gd`: 단일 상태 소유자에서 시장별 재고곡선 견적, 단위별 올림/내림·스프레드, 법인계좌 거래 정산, 단위 원가 lot·인물별 인벤토리, 원장·주문 중복방지, 세이브 schema 2 및 Phase 1 schema 1 위치/동행 마이그레이션을 구현.
- `game/city_hall/city_hall.gd/.tscn`: 현 지역 시장·상품과 매입/매도·인물·수량·견적·확정/취소 및 동행자 간 화물 이전을 연결.
- `game/office/finance.gd/.tscn`, `game/office/interior.gd`, `game/office/office.tscn`: 계좌 조회, 출자, 원금 반환, 실현이익 인출 UI를 사옥 내부 재무 패널로 연결. P1 일반 대출/은행 기능은 구현하지 않음.
- `tests/phase2_checks.gd`: 격리된 user:// 경로를 쓰는 정상 거래·취소 무변경·잔액/재고/적재 부족·미취급·지역 가격차·즉시 환매·분할 주문·거래/계좌 중복 확정·계좌 분리/예비금·저장/백업 복구·구버전 변환 검사를 작성.
- `README.md`에 플레이 사용법과 저장 버전/범위 갱신.

### 선행 기반 대조
- Phase 1 상태는 문서상 구현 보고지만 엔진 파싱/장면 실행/수동 조작은 검증되지 않은 상태였음.
- 실제 코드에는 지역 전환 테스트 버튼이 있고 이동 시간은 없으며 시청 화면은 시장 동작이 미구현이었음. 이 기존 지역 전환을 유지해 두 지역 매매 경로를 연결함.
- 기존 세이브 파일 경로 `user://saves/phase1_save.json`을 유지하고 schema 1 위치·지역·동행자를 보존하며 경제상태 기본값을 추가하는 명시 마이그레이션을 제공. 저장 파일 삭제/초기화는 하지 않음.

### 검증 기록
- 작성한 최소 검사 명령: `godot --headless --path . -s tests/phase2_checks.gd -- --phase2-tests`. 실제 시도 결과 PowerShell이 `godot` 명령을 찾지 못해 실행되지 않음.
- 실행 결과: 미실행. 환경 확인 결과 `godot`/`godot4` 실행 파일이 없어 테스트 스크립트, 엔진 파싱, 현재 장면, UI, 내보내기를 실행할 수 없음. 템플릿 폴더는 있으나 내부 템플릿 파일/버전 없음. 다운로드·설치는 하지 않음.
- PowerShell 정적 확인 명령으로 상품/시장 JSON 파싱, 6개 상품과 8개 시장의 상품 ID 연결, 모든 `.tscn` 외부 리소스 파일 경로, 허용 범위 회귀를 검사: `JSON_OK products=6 markets=8`, `SCENE_RESOURCE_PATHS_OK`, `PHASE2_SCOPE_CHECK_OK`. 이는 Godot 파싱/게임 동작 검증을 대체하지 않음.
- `tests/phase2_checks.gd`는 9개 검사 그룹을 담은 테스트 코드이며 통과 결과가 아님. `--phase2-tests` 실행 시 GameSession 초기화 전에 테스트 저장 경로를 선택하여 기존 사용자 저장을 읽거나 변경하지 않도록 했음. 사람이 직접 UI를 확인한 기능도 없음.

### 남은 범위와 제약
- 거래 저장 자동확정과 원자 rollback, 기존 저장 버전 변환 경로는 작성했으나 런타임/복구 검증은 미실행.
- 시청 지역 전환 버튼은 Phase 1의 즉시 테스트 전환을 재사용하며 현실 경로 이동·시간/차량비는 없음. 따라서 결과 손익은 실현 매출에서 판매한 수량의 매입원가를 뺀 값이며 운송비 등 미구현 비용은 포함하지 않음.
- 가격 상태는 날짜 진행 없이 초기 목표 재고/기준가로 시작하고 거래 수량에 따라 즉시 바뀜. 생산·소비 갱신은 Phase 3 대기.
- 동행 인물은 같은 현재 지역에 있는 것으로 취급. 저장 위치는 주인공·지역 단위이며 출장/개별 인물 위치는 미구현.
- 반환 예비금 180,000원은 기획의 현재 기본 월세 100,000원과 직원 급여 80,000원 합계로 계산. 향후 고정비 일정이 연결되면 실제 예정액 기준으로 교체해야 함.
- 기존 Git 메타데이터 부재는 그대로 유지. Phase 2에서 Git 초기화/커밋/브랜치 작업하지 않음.

### 다음 Phase
- 다음 Phase는 사용자 승인 전 시작하지 않음.

## Phase 3 — 사옥 업무·달력·시장 조사·뉴스

### 선행 상태와 구현
- Phase 2의 실제 코드에서 계좌·원장·시장·인벤토리·거래 경로를 확인하고 보존했다. Phase 2 거래 검사와 런타임은 Godot 부재로 앞서 실행되지 않았으므로 Phase 2를 런타임 검증 완료로 간주하지 않는다.
- `game/core/game_clock.gd`: 2025-01-20 기준일과 현실 활성 시간 600초/월 기념일 계산, 월말 일자 clamp·원래 기념일 보존·윤년·저장/복구를 구현했다. 시스템 시각/종료 시각은 진행 기준으로 쓰지 않는다.
- `game/core/game_session.gd`: 야외·사옥의 시간 진행과 정지 토큰, 날짜별 사건→시장 생산/소비·가격→출장 보고→월세·급여→알림 순서, 다일 경과 순회, 결정적 난수 및 schema 3 저장을 구현했다. Phase 2 schema 2의 경제 상태는 유지하며 달력·직원·뉴스 기본값을 추가하는 변환 경로를 넣었다.
- `data/events.json`, `data/office_rules.json`: 기획의 두 가상 사건(전자부품 공급 ×0.5, 생활잡화 수요 ×0.6, 각 14일)과 사용자 확정 출장 조건(5,000원·2게임일), 월세 100,000원·급여 80,000원을 분리했다.
- `game/office/interior.gd`, `game/office/office.tscn`: 조사 지역 선택, 동행 해제 및 화물 이전 확인, 법인 출장비, 취소(환불 없음), 직원 상태·합류, 전화 상태 확인, 보고 확인, 선택식 회의, 뉴스 보관, 기존 재무 메뉴를 연결했다. 재무·보고·회의·조사 화면은 시간 정지 토큰을 사용한다.
- `game/news/news_overlay.gd/.tscn`, `game/news/news_archive.gd/.tscn`: 날짜 뉴스 임시 컷씬, 시장 계수 설명, 확인 후 효과 진행, 기사 보관/재열람을 구현했다. 이미지는 외부 자료 없이 색상 패널·텍스트 임시 자산이다.
- `game/ui/time_hud.gd/.tscn`: 야외·사옥에 날짜·시각·계좌·정지 여부·다음 월 고정비 날짜·최근 알림을 표시하고 직원 출장 중 왼쪽 동행 썸네일을 숨긴다. 이동 대표는 주인공 한 명으로 유지한다.
- `tests/phase3_checks.gd`: 달력·정지 토큰·출장 중복/화물·뉴스 효과·정기비용 중복·저장 복구와 Phase 2 매매 회귀를 분리 저장 경로에서 확인하도록 6개 검사 그룹을 작성했다.
- `README.md`: Phase 3 사용 흐름, 시간·저장·검사 명령, 실제 엔진 환경, 임시 자산과 미구현 기능을 갱신했다.

### P0 체크리스트 대조
| 항목 | 코드 상태 | 검증 상태 |
|---|---|---|
| 프로젝트 실행 및 서울·인천 이동 | Godot 4.7.2 headless main 장면 실행 성공. 지역 전환은 Phase 1의 즉시 테스트 전환으로 실제 도보·차량 이동 경로는 아님 | headless 시작 검증, 수동 이동 미검증, P0 완료 미선언 |
| 사옥·시청 입출구 | 기존 입출구·출입구 복귀 코드를 재사용 | 수동 진입·반복 출입 미검증 |
| 법인계좌 상품 매입·인벤토리 | Phase 2 거래 서비스 보존, 날짜 처리 중 뉴스 대기 시 거래 차단 추가 | Phase 2 자동 검사 9그룹 통과, 수동 거래 미검증 |
| 타 지역 판매·거래 내역·순이익 | 기존 지역 매매·원장·매입원가 기반 손익 경로 보존, 거래 날짜 라벨 연결. 미구현 운송비는 제외 | 가격/거래 회귀 자동 검사 통과, 실제 지역 이동 판매 흐름 미검증 |
| 조사 지시·관측일 보고 | 출장·완료일 스냅샷·보고 UI 작성 | Phase 3 출장·보고 자동 검사 통과, UI 수동 확인 미검증 |
| 날짜·일별 시세·지정 뉴스 | 시간·가격·뉴스 데이터/처리 구현 | Phase 3 달력·뉴스 검사 통과, 화면 표시 수동 확인 미검증 |
| 계좌·화물·일정·사건·위치 저장/복원 | schema 3과 schema 1/2 변환 작성 | Phase 2/3 저장 관련 자동 검사 통과, 실제 GUI 재실행 미검증 |
| P1/P2 미구현 기능의 구분 | 일반대출·부동산·차량·전투·피랍·작업장·주식·해외 비활성/미구현으로 문서화 | 문서 정적 확인 |

**P0 전체 완료 여부: 미완료.** Godot headless 실행과 Phase 2/3 자동 검사 일부는 통과했지만, 수동 조작·실제 지역 간 이동·건물 입출구·거래에서 조사까지의 전체 GUI 흐름은 미검증이다. 지역 간 즉시 테스트 전환은 실제 이동을 대체하지 못한다.

### 검증 기록
- 실행한 PowerShell 정적 검사: 이벤트 JSON 2건, 출장 설정 5,000원/2게임일 확인 결과 `PHASE3_DATA_OK events=2 survey=5000/2`.
- 실행한 PowerShell 장면 참조 검사: 모든 `.tscn`의 `res://` 스크립트/장면 경로 존재 확인 결과 `SCENE_RESOURCES_OK`; 장면 부모 노드 정적 검사 결과 `SCENE_RESOURCES_AND_NODE_PARENTS_OK`.
- 해당 확인 명령은 PowerShell에서 `Get-Content -Raw data\events.json | ConvertFrom-Json`, `Get-Content -Raw data\office_rules.json | ConvertFrom-Json`, `Get-ChildItem game -Recurse -Filter *.tscn` 및 각 장면의 `path="res://..."` 실제 경로 검사다. 데이터 최종 재실행 결과는 `PHASE3_DATA_OK events=2 survey=5000/2`다.
- Godot 확인: `Get-Command godot,godot4`, `where.exe godot`, `C:\Program Files\Godot` 확인 결과 실행 파일 없음. `godot --headless --path . -s tests/phase3_checks.gd -- --phase3-tests` 시도 결과 PowerShell에서 `godot` 명령을 찾을 수 없어 종료 코드 1. 파싱·6개 검사 그룹·현재 장면·Phase 2 회귀 검사는 미실행이며 검사 통과 결과가 아니다.
- 템플릿 확인: `%APPDATA%\Godot\export_templates`에는 `4.4.1.stable.mono`만 있고 기준인 Godot 4.7.2 Standard 템플릿은 없다. 다운로드/설치는 하지 않았으며 Windows 내보내기 미실행.
- 사람의 마우스/키보드 조작·뉴스 모달·출장 완료·재실행 복구는 확인하지 못했다. 테스트 전용 경로를 코드에 설정했으나 엔진 실행이 되지 않아 저장 데이터를 만들지 않았다.
- Git 메타데이터는 루트에 없으며 `git status --short`가 `fatal: not a git repository`를 반환했다. 저장소 초기화·브랜치·커밋 작업은 하지 않았다.

### 남은 작업과 승인 대기
- Godot 4.7.2 Standard 실행 파일과 동일 버전 템플릿이 준비되면 Phase 3 검사, Godot 파싱/headless 장면 실행, 거래 회귀, UI 수동 시나리오, 가능 시 빈 Windows 내보내기를 실행해야 한다. 설치·다운로드는 사용자 승인 없이 진행하지 않는다.
- 보고 추세·가격 곡선, 날짜 지연 처리와 세이브 변환은 런타임 검사 전까지 코드 작성 상태다. 과거 Phase 2 테스트 역시 아직 미실행이다.
- UI 임시 자산은 실제 일러스트가 아니며, 차량 이동·비용과 P1/P2 기능은 구현하지 않았다.
- 다음 Phase/P1은 사용자 승인 대기이며 자동 착수하지 않는다.

### 2026-11-08 Godot 4.7.2 재검증
- 사용자가 제공한 압축 해제 폴더 안의 `Godot_v4.7.2-stable_win64_console.exe --version` 결과: `4.7.2.stable.official.ed1daf0bf`. 실행 파일 경로의 바깥 항목은 `.exe`라는 이름의 폴더였다.
- 파싱 중 발견한 `project.godot` 입력 키 식별자 오류를 Godot 키 코드 값으로 고쳤다. main 장면 실행에서 발견한 카메라 노드 경로와 TimeHUD의 `Rows` 자식 경로 오류도 수정했다.
- `--headless --editor --path . --quit`: 종료 코드 0, 파일 스캔 완료. 에디터 설정 safe-save 권한 경고는 출력됐으나 프로젝트 스캔 및 스크립트 파싱 오류는 없었다.
- `--headless --path . --quit-after 5`: 종료 코드 0, main 야외 장면 실행에서 오류 로그 없음.
- autoload를 포함하도록 검사 진입점을 `.tscn` 검사 장면으로 바꾸고 검증 실패 시 종료 코드 1을 반환하게 했다. Phase 2 자동 검사 9그룹은 `PHASE2_CHECKS_OK: 9 groups`, Phase 3 자동 검사 6그룹은 `PHASE3_CHECKS_OK: 6 groups`로 통과했다. Phase 2의 백업 복구 검사는 의도적으로 손상 JSON을 읽어 엔진 오류 로그가 나오지만 백업 복구 및 검사 그룹은 통과한다.
- 사용한 실행 명령(각각 `& $godot` 앞에 임시 `APPDATA` 지정):
  ```powershell
  $godot = '<Godot 4.7.2 console 실행 파일 경로>'
  & $godot --headless --editor --path . --quit
  & $godot --headless --path . --quit-after 5
  & $godot --headless --path . res://tests/phase2_checks.tscn -- --phase2-tests
  & $godot --headless --path . res://tests/phase3_checks.tscn -- --phase3-tests
  ```
- 검사 저장은 `%APPDATA%`를 프로젝트의 무시된 `.godot/phase_test_appdata`로 지정해 `user://phase2_checks/`, `user://phase3_checks/`를 기본 사용자 세이브와 분리했다.
- 추가 수정: `project.godot`, `game/world/korea_world.gd`, `game/ui/time_hud.gd`, `game/core/game_session.gd`, 두 검사 스크립트 및 검사 장면 2개.
- 아직 템플릿은 `%APPDATA%\Godot\export_templates\4.4.1.stable.mono`만 확인되어 4.7.2 Standard Windows 내보내기는 미실행이다. 화면에서 마우스/키보드 이동·UI 차단·건물 반복 출입을 직접 확인하지 않아 P0 완료로 판정하지 않는다.

### UI·주인공 시각 자산 적용
- 사용자가 목업 상태를 지적하고 UI/캐릭터 디자인 적용을 요청했다. `assets/protagonist_8dir_sheet.png`(4×2, 프레임별 320×640, 투명 배경)를 생성하고 `game/world/player.gd`에서 이동 벡터에 따라 방향 프레임을 표시하도록 연결했다. 걷기 애니메이션은 없고 8방향 정지 포즈 전환만 제공한다. `assets/staff_01_portrait.png`는 시작 직원 초상으로 생성해 왼쪽 동행 슬롯에 연결했다.
- `assets/ui_skin_sheet.png`(투명 배경 패널·버튼·초상 프레임)와 `game/ui/game_theme.tres`를 생성했다. 테마는 야외 패널·버튼, 날짜 HUD, 시청, 사옥에 적용했다. 야외 왼쪽 주인공 초상은 시트 정면 상반신 프레임과 액자 텍스처를 겹쳐 표시한다.
- 변경/추가 파일: `assets/protagonist_8dir_sheet.png`, `assets/staff_01_portrait.png`, `assets/ui_skin_sheet.png`, `game/ui/game_theme.tres`, `game/world/player.gd`, `game/world/korea_world.tscn`, `game/ui/time_hud.tscn`, `game/city_hall/city_hall.tscn`, `game/office/office.tscn`, `README.md`.
- 사용자 요청에 따라 이번 시각 변경은 Godot 파싱·실행 및 화면 검증을 수행하지 않았다. 사용자가 직접 실행해 이미지 투명도, 시트 방향 매핑, UI 크기와 가독성을 확인하고 피드백할 예정.
- 미술 미완료 구분: 야외 지형/도시와 사옥·시청 건물 외관, 내부 배경, 직원 초상, 뉴스 컷씬은 여전히 임시 도형/색상 패널/텍스트다. 주인공과 UI 이미지는 임시 생성 자산이며 최종 애니메이션·미술 검수는 남았다.
- 사용자 실행 중 `Player/Body` 이름 충돌 알림을 보고했다. `game/world/korea_world.tscn`에 남아 있던 기존 Polygon2D 선언을 제거해 Sprite2D만 남겼다. 사용자가 직접 실행 검증하기로 했으므로 이 수정 이후 Godot 실행/검증은 수행하지 않았다.
- 사용자가 F5 실행 중 `time_hud.gd`의 `PlayerThumb.visible` null 할당 오류와 입력 무반응을 보고했다. 좌측 초상 장면을 PlayerSlot/StaffSlot으로 바꾼 뒤 시간 HUD 갱신 코드가 구형 라벨 이름을 계속 찾는 것이 원인이다. 새 Control 슬롯 이름을 사용하고 없는 슬롯은 건너뛰도록 수정했다. 사용자가 보낸 실행 화면에서는 디버거가 해당 오류에서 일시정지된 상태라 입력 불가와 일치한다. UI 텍스처의 9분할 여백도 축소했다. 이번 변경의 Godot 재실행/파싱 검증은 하지 않았으며 사용자 재확인 대기다.

### 야외 건물·UI·지도 개선
- 사용자 실행 피드백에서 건물 클릭 불가, UI 텍스트 표시 문제와 `_show_next_pending_news`의 CanvasLayer→Control 타입 오류를 확인했다. 시장 거래 견적 경로의 미사용 `unit_weight` 경고도 함께 정리했다.
- 뉴스 오버레이 인스턴스 타입을 `CanvasLayer`로 맞췄다. 좌측 동행 UI를 새 PlayerSlot/StaffSlot 구조와 동기화했고, 사용자가 본 작은 HUD/버튼에서 긴 장식 텍스처가 눌려 보이던 문제는 간결한 남색/금색 StyleBox와 20px 기본 글자로 바꿔 대응했다. 상단 지역 이름과 지역 버튼은 HBoxContainer로 분리했다.
- `assets/seoul_office.png`, `assets/seoul_city_hall.png`, `assets/incheon_city_hall.png`를 투명 배경으로 생성해 야외 건물 외관에 적용했다. 건물 입구 Area2D의 마우스 선택 신호와 확대된 클릭 영역, 접근 목표의 도착 허용 범위를 연결해 클릭→접근→메뉴 흐름을 보강했다.
- 야외 이동 오브젝트는 Y-sort 그룹에 모아 건물 앞/뒤를 정렬하고, 서울-인천 축약 도로와 강 횡단부를 시각적으로 보강했다. 새 게임 시작점을 강 위에서 서울 육지로 옮기고 기존 저장 위치가 강 내부인 경우에만 지역별 육지 지점으로 보정한다. 지역 전환 버튼은 테스트용 순간 전환 그대로이며 실제 지역 간 도보 경로는 구현하지 않았다.
- 수정/추가: `assets/seoul_office.png`, `assets/seoul_city_hall.png`, `assets/incheon_city_hall.png`, `game/core/game_session.gd`, `game/world/korea_world.gd/.tscn`, `game/world/player.gd`, `game/ui/game_theme.tres`, `game/news/news_overlay.tscn`, `README.md`.
- 이번 수정 후 Godot 파싱·실행·수동 조작 검증은 하지 않았다. F5 실행 후 뉴스 오류 해소, 건물 직접 클릭→접근→메뉴, UI 글자 겹침/잘림 여부는 사용자 재확인이 필요하다.
- 다음 지도 개선 후보는 실제 서울↔인천 경로와 도착시간, 길·지형의 충돌/내비게이션, 구역별 지형과 거리 장식이다. 현재 도로는 시각 표현이며 이동 경로·차량비 계산이나 지형 충돌에는 사용하지 않는다.

### 야외 조작 일관성 수정
- 기획안 4절·15절에 맞춰 WASD 입력과 E 상호작용/별도 입장 버튼 방식 대신, 지면 클릭 이동·방향키 이동 및 건물 클릭 후 접근 이동→상호작용 메뉴 흐름으로 정리했다. 메뉴에서 내부 보기/취소를 선택한다. UI 위 클릭은 기존 `_unhandled_input` 경로로 야외 이동에 전달되지 않는다.
- 변경 파일: `project.godot`, `game/world/player.gd`, `game/world/korea_world.gd`, `game/world/korea_world.tscn`, `README.md`. 사용자가 확정한 야외 조작 규칙을 `AGENTS.md`의 핵심 방향 항목에 최소 반영했다.
- Godot 4.7.2 `--headless --editor --path . --quit`, `--headless --path . --quit-after 5`, Phase 2 검사 장면, Phase 3 검사 장면을 수정 후 재실행했다. 모두 종료 코드 0, 검사 결과는 각각 `PHASE2_CHECKS_OK: 9 groups`, `PHASE3_CHECKS_OK: 6 groups`. Phase 2 백업 복구 검증에서 손상 저장 JSON을 의도적으로 읽어 파싱 오류 로그가 한 번 나오지만 백업 복구 검사 그룹은 통과한다. 에디터는 safe-save 권한 경고가 있으나 스캔/파싱은 완료됐다.
- `rg`로 입력 설정과 안내 문구를 확인해 WASD 키코드·E 상호작용 입력·기존 입장 버튼 참조가 남지 않았음을 확인했다. 건물 클릭 메뉴는 접근 이동 후에만 나타나며, 화면에서 직접 클릭·방향키·UI 차단·입출구를 조작하는 검증은 아직 미완료다.
- GUI 직접 확인은 이전 허용된 시도에서 프로세스 창이 생성되지 않아 미검증으로 유지하며, 지역 전환은 기존 Phase 1 테스트 전환으로 실제 지역 간 경로 이동이 아니다.

### 2026-11-08 오류·건물 상호작용·지도 개선
- 원인 분석: `game/app/main.tscn`에 건물 노드를 이전 `Map/` 경로에서 찾는 상속 장면 오버라이드가 남아 있었고, 건물은 `WorldObjects/` 아래로 이동한 상태였다. 이로 인해 instantiate 시 Label 부모 경로 경고가 발생했다. 해당 세 개의 오래된 Label 오버라이드만 제거했다. 서울Town·인천Harbor 라벨과 UI Portrait 오버라이드는 현재 부모 경로가 유효해 유지했다.
- 종료 오류 원인: `korea_world.gd::_exit_tree()`가 위치를 저장하면서 `state_changed`를 emit했고, 분리되는 중인 `time_hud.gd::_refresh_party()`가 `get_tree()`를 호출했다. 종료 저장에서 UI 알림을 생략하는 인자를 추가하고 HUD는 `_exit_tree()`에서 오토로드 연결을 해제하며, 갱신 함수도 트리 소속 여부를 확인한다.
- 건물 상호작용 안정화: 메뉴 버튼 신호를 씬 준비 시 한 번만 연결해 취소·재진입 시 오래된 one-shot 신호가 누적되지 않게 했다. 메뉴 취소 시 예약된 접근 이동을 중지하고, 선택 건물이 현재 지역에 속하는지도 확인한다. 건물 클릭은 가장 가까운 현재 지역 출입구를 선택한다. 실제 GUI 클릭→이동→메뉴 확인은 Computer Use 앱 승인이 시간 초과되어 실행하지 못했다.
- 지도 개선: `game/world/korea_world.gd`에서 서울 한강공원·도심 구역·수목, 인천 항만 작업장·창고·부두, 시청/사옥 연결 보조 도로를 코드 기반 임시 도형으로 추가했다. 추가 라이브러리나 이미지 파일은 만들지 않았다. 도로는 여전히 시각 표식이며 실제 경로 찾기·지형/물 충돌과 일치하지 않는다.
- 변경 파일: `game/app/main.tscn`, `game/core/game_session.gd`, `game/ui/time_hud.gd`, `game/world/korea_world.gd`, `game/world/player.gd`, `README.md`, `DEVELOPMENT_STATUS.md`. AGENTS.md와 GAME_DESIGN.md는 변경하지 않았다.
- 검증: Godot `4.7.2.stable.official.ed1daf0bf`에서 `--headless --editor --path . --quit` 파일 스캔/파싱, `--headless --path . --quit-after 5` 현재 main 장면 실행, Phase 2 검사 `PHASE2_CHECKS_OK: 9 groups`, Phase 3 검사 `PHASE3_CHECKS_OK: 6 groups`를 수행했다. 모두 종료 코드 0이다. 에디터에서 safe-save 권한 오류가 출력됐지만 파싱과 테스트에는 영향을 주지 않았다. Phase 2 백업 검사 중 손상 JSON 파싱 로그는 검사에서 의도적으로 생성됐고 백업 복구 그룹은 통과했다.
- 사용 명령은 README의 Godot 4.7.2 콘솔 실행 파일을 사용해 위 네 명령을 순서대로 수행했으며, `APPDATA`를 프로젝트 `.godot/phase_test_appdata`로 지정해 기본 저장과 분리했다. GUI 조작, 클릭 경로와 화면 레이아웃, 사람의 시각 확인은 승인 시간 초과로 미검증이다. 윈도우 내보내기는 범위 밖이라 실행하지 않았다.
- 알려진 한계: 시청/사옥 클릭 후 접근·메뉴는 자동 검사로 검증되지 않았다. 지형 색상/도형은 최종 지도 자산이 아니며 실험적 장식 폴리곤 자체는 보행 충돌체가 아니다.

### 2026-11-08 건물 hover 및 클릭 판정 보강
- 사용자 피드백에서 건물 그림을 눌러도 메뉴가 뜨지 않는 문제가 재현 보고됐다. 출입구 중심 반경만 보던 기존 판정은 건물 이미지 상단 클릭을 놓칠 수 있어, 스프라이트의 실제 로컬 사각 영역을 먼저 검사하도록 바꿨다. 기존 Area2D/입구 주변 판정은 보조 경로로 유지했다.
- 마우스를 건물 스프라이트 위에 올리면 기존 그림 뒤에 금색 실루엣을 표시하고 손 모양 커서를 사용한다. UI 컨트롤 위에서는 hover를 끈다. 새 그림 파일은 필요하지 않아 추가하지 않았다.
- 변경 파일: `game/world/korea_world.gd`, `README.md`, `DEVELOPMENT_STATUS.md`.
- Godot 4.7.2에서 `--headless --editor --path . --quit` 및 `--headless --path . --quit-after 5`를 재실행해 파싱/현재 장면 실행이 종료 코드 0임을 확인했다. 에디터 safe-save 권한 오류 메시지는 반복 출력됐으나 파싱은 완료됐다. GUI 마우스 hover·건물 클릭→접근→메뉴는 컴퓨터 조작 창 승인이 시간 초과되어 직접 검증하지 못했다.

### 2026-11-08 건물 메뉴 미표시 추가 수정
- 사용자가 제공한 실행 화면에서 주인공이 사옥 앞에 도달했지만 상단 상태가 기본 안내로 돌아간 것을 확인했다. 기존 흐름은 Area2D 입력 이벤트 또는 unhandled 입력 전달에 의존했고, 클릭 이동 도착 신호만으로 메뉴를 열어 충돌체 때문에 목표점에 못 닿는 경우가 남아 있었다.
- 입력 경로를 UI 컨트롤 검사 후 처리하는 월드 `_input`으로 단일화하고 `Viewport.get_canvas_transform().affine_inverse() * event.position`으로 클릭을 월드 좌표로 변환한다. UI 위 클릭은 그대로 UI에 전달한다. 출입구 접근 중 115px 이내에 도달하면 클릭 이동 목표점 통과 여부와 무관하게 메뉴 요청을 완료한다.
- 변경 파일: `game/world/korea_world.gd`, `game/world/player.gd`, `DEVELOPMENT_STATUS.md`.
- Godot 4.7.2에서 `--headless --editor --path . --quit`와 `--headless --path . --quit-after 5`를 실행해 파싱과 현재 장면 headless 실행이 종료 코드 0임을 확인했다. safe-save 경고는 지속 출력됐다. 사용자 화면에서 실제 클릭·접근·메뉴와 UI 클릭 차단은 재확인 대기다.

### 2026-11-08 방문 버튼 및 정수 나눗셈 경고 수정
- 사용자가 제공한 로그 `korea_world.gd:249 INTEGER_DIVISION`은 수목 장식 행 위치에서 `int / int`를 사용한 데서 발생했다. `float(index) / 3.0`으로 바꿨다.
- 건물 외형 위에 `사옥 방문`/`서울시청 방문`/`인천시청 방문` 버튼을 상시 표시하고, 버튼도 건물 클릭과 같은 접근 이동→도착 후 상호작용 메뉴 경로로 연결했다. 건물 스프라이트 hover의 금색 실루엣도 유지했다.
- 변경 파일: `game/world/korea_world.gd`, `README.md`, `DEVELOPMENT_STATUS.md`.
- 방문 버튼은 Control UI 입력으로 먼저 처리하고, 버튼에서 소비되지 않은 지도 클릭만 `_unhandled_input`으로 보낸다. UI 위 클릭이 이동 코드에 먹히지 않도록 한다.
- 수정 후 Godot 4.7.2에서 `--headless --editor --path . --quit`와 `--headless --path . --quit-after 5`를 재실행해 둘 다 종료 코드 0을 확인했다. 이전 정수 나눗셈 경고는 재실행 로그에서 보이지 않았다. safe-save 권한 경고는 출력됐지만 스캔/실행은 완료됐다.
- GUI에서 방문 버튼·hover·메뉴가 실제로 보이고 동작하는지는 사용자 재확인이 필요하다.

### 2026-11-08 건물 상호작용 단계 로그 및 출입구 등록 원인 수정
- Godot headless 실행 로그가 `ready region=seoul entrance_count=0`을 출력해 런타임 원인을 확인했다. 장면에 있는 Entrance 노드가 그룹 검색 결과에 포함되지 않아 hover 표시·방문 버튼 생성·건물 클릭 판정이 모두 비활성 상태였다.
- 그룹 검색을 제거하고 `WorldObjects/SeoulOffice/Entrance`, `WorldObjects/SeoulHall/Entrance`, `WorldObjects/IncheonHall/Entrance` 경로로 명시 등록했다. 수정 후 실행 로그는 방문 버튼 3개 생성과 `entrance_count=3`을 확인했다.
- F5 디버그 Output에 `[BUILDING_INTERACTION]` 로그를 추가했다. 입력 수신 및 GUI hover, 월드 클릭 좌표/지도 판정, 건물 적중/지면 적중, 선택 목표, 도착 신호, 메뉴 표시, hover 변경을 단계별로 남긴다. 저장 파일이나 사용자 상태를 건드리지 않는 출력 로그다.
- 변경 파일: `game/world/korea_world.gd`, `game/world/player.gd`, `README.md`, `DEVELOPMENT_STATUS.md`.
- Godot 4.7.2에서 `--headless --editor --path . --quit` 및 `--headless --path . --quit-after 5` 종료 코드 0. headless 실행에서 `visit_button_ready` 3건과 `ready region=seoul entrance_count=3`을 확인했다. safe-save 권한 경고가 출력됐지만 파싱과 실행은 완료됐다.
- 실제 마우스 클릭/hover 및 메뉴 화면은 아직 직접 확인하지 않았다. F5 Output에서 `[BUILDING_INTERACTION]` 줄을 수집해 사용자 재현 경로를 최종 확인해야 한다.

### 현재 남은 작업 요약
- **P0/Phase 1~3:** 거래·저장·달력·뉴스 자동 검사와 main 장면 headless 실행은 통과 기록이 있다. 실제 마우스/방향키·UI 클릭 차단·시청/사옥 입출구 반복·건물 hover/메뉴·저장 재시작 및 전체 거래→조사→판매 흐름의 사람 확인은 남아 있다. 서울↔인천 버튼은 테스트 즉시 전환이라 실경로 이동·시간·비용은 없다. 따라서 P0 전체 완료는 미선언 상태다.
- **미술/지도:** 현재 건물·주인공·UI·지형 표현은 임시 생성 자산/코드 도형이다. 주인공 걷기 애니메이션, 최종 도시 지도, 길 찾기와 지형·물 충돌의 일치는 미완료다.
- **P1/Phase 4~5:** 이 문서에는 Phase 4/5 완료 기록이 없고, 프로젝트 README도 차량·적/전투·피랍·작업장·부동산·일반대출을 미구현으로 분류한다. 이를 구현 완료로 간주하지 않는다.
- **P2:** 해외·항해·해적·주식·위임 거래는 시작하지 않았다.
- 이번 요청의 코드 변경 이후 자동 파싱/headless 실행은 통과했지만 GUI 상호작용은 사용자 확인 대기다. Godot 콘솔 창을 열어 둔 상태에서 F5로 건물 hover와 접근/메뉴를 확인해 결과를 알려주면 다음 문제를 좁힐 수 있다.

### 2026-11-08 사옥 대표실 UI 및 SD 미니 에셋 적용
- 사용자 로그에서 건물 hover와 접근 후 `menu_open=true`를 확인했다. 현재 사옥 화면은 단색 바탕과 단일 버튼 목록이라 컴퓨터·전화·비서 업무 위치가 구분되지 않는 점을 개선 대상으로 정했다.
- `game/office/office.tscn`: 대표 책상 시점 배경을 추가하고, 컴퓨터(조사·보고·뉴스·재무), 전화, 비서/직원 상태, 회의, 야외 복귀 버튼을 장면 위치에 따라 배치했다. `interior.gd`가 사용하는 노드 이름과 기존 버튼 연결은 보존했다.
- `game/ui/game_theme.tres`, `game/city_hall/city_hall.tscn`: 기존 남색·금속 위주 색을 크림·세이지·테라코타 기반의 둥근 2D 스타일로 바꾸고 버튼 대비를 조정했다.
- `assets/office_interior_bg.png`: 대표 책상, 컴퓨터, 전화, 맞은편 비서, 서울 창밖이 보이는 16:9 배경을 추가했다. 배경의 비서 외형은 직원 초상과 일치하도록 한 차례 보정했다.
- 기존 `assets/protagonist_8dir_sheet.png`, `assets/staff_01_portrait.png`, `assets/ui_skin_sheet.png`, `assets/seoul_office.png`, `assets/seoul_city_hall.png`, `assets/incheon_city_hall.png`를 SD 미니/2D 일러스트 임시 그림으로 교체했다. `game/world/player.gd`는 4×2 시트의 텍스처 크기에서 방향 프레임을 계산하도록 수정했고 `game/world/korea_world.tscn`의 주인공 초상 범위도 새 그림에 맞췄다.
- `README.md`: 대표실 조작 안내, 자산 목록, 아직 필요한 미술과 화면별 사용자 확인 범위를 추가했다. `AGENTS.md`와 `GAME_DESIGN.md`는 변경하지 않았다.
- 개선 검토 결과: 실내는 고정 대표 시점으로 공간감을 주고 상호작용을 장비/인물 근처에 둔다. 조사·보고·뉴스·재무를 컴퓨터 아래 묶고, 전화와 직원 조작을 각각 전화기와 비서에 배치하며 회의/나가기는 상시 분리한다. 이를 반영했으며 미구현 기능을 새로 만들거나 기존 업무 로직을 갈아엎지는 않았다.
- 실내 인터페이스에 필요한 자산: (현재) 대표 책상 시점 배경, 직원 초상, 버튼/초상 프레임 테마, 야외 주인공 8방향 시트, 사옥·시청 외관. (후속 후보) 비서 전신/표정 포즈, 전화·컴퓨터·회의·보고·뉴스·재무 아이콘, 시청 내부 배경. 후속 후보는 이번 범위에서 추가 제작하지 않았다.

#### 검증 및 한계
- `Godot_v4.7.2-stable_win64_console.exe --version`: `4.7.2.stable.official.ed1daf0bf`.
- `--headless --editor --path . --quit`: 종료 코드 0, 신규/교체 그림 7개 재가져오기 완료. 기존 safe-save 권한 경고가 출력됐지만 파일 스캔과 가져오기는 끝났다.
- `--headless --path . --quit-after 3`: main 장면 실행 종료 코드 0, 건물 버튼 3개와 `entrance_count=3` 로그 확인.
- `--headless --path . res://game/office/office.tscn --quit-after 2`: 사옥 장면 로드/종료 코드 0.
- Phase 2 검사: `PHASE2_CHECKS_OK: 9 groups`; 손상 세이브 복구 검사 중 의도적으로 손상한 JSON 파싱 오류가 출력된 뒤 복구 검사가 통과했다. Phase 3 검사: `PHASE3_CHECKS_OK: 6 groups`.
- GUI 화면 확인은 미완료다. 컴퓨터 사용 도구의 Godot 창 연결 결과가 실제 캡처에서 VS Code 화면으로 일치하지 않아 입력을 중단했다. 실제 F5 실행에서 배경 크롭, 버튼과 소품 정렬, 한국어 가독성, 전체창 대응은 사용자가 직접 확인해야 한다.
- 그림은 생성 임시 자산이다. 고정 배경 안의 비서는 실제 직원 위치/상태를 시각적으로 동기화하는 애니메이션이 아니며, 버튼은 기존 조작 경로를 위한 오버레이다. 최종 미술 및 화면별 사람 검수는 완료되지 않았다.
- 다음 단계는 사용자의 새 F5 화면 피드백 대기다. 별도 Phase/P1 기능은 시작하지 않았다.


#### 실행한 확인 명령
```powershell
$ErrorActionPreference='Stop'; $products=Get-Content -Raw data\products.json | ConvertFrom-Json; $markets=Get-Content -Raw data\markets.json | ConvertFrom-Json; if($products.Count -ne 6){throw '상품 정의 개수 불일치'}; foreach($market in $markets){foreach($id in $market.product_ids){if(-not ($products.id -contains $id)){throw "미정의 상품: $id"}}}; $missing=@(); foreach($scene in Get-ChildItem game -Recurse -Filter *.tscn){foreach($match in [regex]::Matches((Get-Content -Raw $scene.FullName),'path="res://([^"]+)"')){$path=Join-Path (Get-Location) $match.Groups[1].Value.Replace('/','\'); if(-not (Test-Path -LiteralPath $path)){$missing += $path}}}; if($missing.Count){$missing; throw '장면 리소스 누락'}; 'JSON_OK products=6 markets='+$markets.Count; 'SCENE_RESOURCE_PATHS_OK'
```
결과: `JSON_OK products=6 markets=8`, `SCENE_RESOURCE_PATHS_OK`, `PHASE2_SCOPE_CHECK_OK`.
```powershell
godot --headless --path . -s tests/phase2_checks.gd -- --phase2-tests
```
결과: `godot` 명령을 찾지 못해 실행되지 않음. 구현된 검사 실행은 Godot 4.7.2 실행 파일과 별도 테스트 저장 경로가 준비되어야 함.

### 2026-11-08 사옥 오브젝트 hover 메뉴 및 좌측 상태 HUD
- 사용자 화면 피드백에 따라 상시 노출되던 노트북·전화·직원 버튼과 겹치는 상태 표시를 없앴다.
- `game/office/office.tscn`, `game/office/interior.gd`: 노트북·비서·전화기 위치에 투명 기본 상태의 클릭 영역을 만들고, hover 시 세이지 테두리/반투명 강조, 클릭 시 중앙 선택 메뉴를 표시한다. 노트북은 조사·보고·뉴스·재무, 비서는 현재 직원 상태에 허용된 동행 합류 또는 출장 취소, 전화기는 직원 연락 상태 확인만 보여준다. 없는 기능을 메뉴에 추가하지 않았다.
- `game/ui/time_hud.tscn`: 날짜·개인/법인 잔액·납부일·상태 HUD를 우측 상단에서 좌측 상단으로 옮겼다. 회의와 야외 복귀 버튼은 우측 상단에 유지한다.
- `README.md`: hover→클릭→메뉴 선택 조작으로 사용법을 수정했다.
- Godot 4.7.2 `--headless --path . res://game/office/office.tscn --quit-after 3`: 종료 코드 0, 스크립트/장면 로드 성공. 데이터 모델을 변경하지 않아 Phase 2·3 검사는 반복하지 않았다.
- 실제 마우스 hover 테두리, 메뉴 좌표, 글자 가독성은 GUI에서 확인하지 못했다. 자동 장면 로드는 기능 입력 검증과 다르며, 사용자가 F5로 확인할 항목이다. 검증용 실행은 `.godot/phase_test_appdata`를 사용했다.

### 2026-11-08 체크무늬·HUD 겹침·지도·hover 강조 개선
- 스크린샷에 보인 체크무늬의 원인을 확인했다. 기존 주인공·직원·사옥·시청·UI 프레임 PNG가 RGB 형식으로 알파 채널이 없었다. 주인공, 직원 초상, 3개 건물 그림을 RGBA 투명 그림으로 교체했다. 각 새 PNG 헤더는 color type 6이며 네 모서리 픽셀 알파값 0을 확인했다.
- UI 프레임 이미지의 체크무늬 사용을 중단했다. `game/world/korea_world.tscn`에서 이를 제거하고 StyleBox 둥근 초상 카드를 사용해 체크무늬가 UI 뒤에 남지 않도록 했다. 기존 `assets/ui_skin_sheet.png` 파일은 임의 삭제하지 않고 런타임 참조만 제거했다.
- `game/world/player.gd`: 주인공 8방향 배열을 1행 북·북동·동·남동, 2행 남·남서·서·북서로 정리하고 시트 셀 크기를 텍스처에서 계산한다. `game/world/korea_world.tscn`의 초상은 정면 프레임을 사용한다.
- `game/ui/time_hud.tscn`, `game/world/korea_world.tscn`: 상단 날짜·계좌 HUD 높이와 폭을 줄이고, 동행 슬롯을 HUD 아래로 내렸다. 지역 전환 바는 HUD 오른쪽으로 옮겼다.
- `game/world/korea_world.tscn`, `game/world/korea_world.gd`: 육지 배경을 화면 경계까지 확장하고 강 가장자리를 더 완만한 굴곡으로 변경했다. 공원 수목과 소형 도심 블록, 다리 표식과 연결 도로를 추가했다. 건물 방문 표식을 외관에 더 가깝게 옮겼다.
- `game/office/office.tscn`: 노트북·비서·전화기 hover 스타일에 더 선명한 둥근 외곽선, 반투명 배경, 세이지색 외곽광을 적용했다. 기존 포인터 안내와 메뉴 연결은 유지했다.
- `README.md`: 투명 배경, 지도, HUD 배치, 강한 오브젝트 hover 설명을 갱신했다. `AGENTS.md` 및 `GAME_DESIGN.md`는 수정하지 않았다.

#### 검증 결과 및 미확인 사항
- Godot 4.7.2 `--headless --editor --path . --quit`: 종료 코드 0, 교체한 이미지 5개 재가져오기 성공. safe-save 권한 경고는 계속 출력됐다.
- `--headless --path . res://game/office/office.tscn --quit-after 3`, `--headless --path . --quit-after 3`: 사옥과 main 실행 종료 코드 0. 방문 표식 3개와 `entrance_count=3` 확인.
- `res://tests/phase2_checks.tscn -- --phase2-tests`: `PHASE2_CHECKS_OK: 9 groups`. 손상 세이브 복구 테스트가 의도적으로 만든 JSON 파싱 오류를 출력했지만 전체 검사는 통과했다. Phase 3: `PHASE3_CHECKS_OK: 6 groups`.
- 실제 GUI에서 체크무늬가 사라졌는지, HUD와 동행 슬롯이 겹치지 않는지, 주인공의 각 방향 및 방문 표식 위치, 사무실 hover 외곽광을 확인하지 않았다. F5 입력을 통한 사용자 확인이 필요하다. 기능 파싱·headless 실행은 시각 검수 완료를 의미하지 않는다.
- 색면·도형으로 만든 지도 장식과 생성된 SD 그림은 아직 임시 미술이며 최종 지도 미술, 걷기 애니메이션, 창 크기별 GUI 검증은 남아 있다.





## 2026-11-08 P0 보완·통합 검증 — 현재 판정

이 절은 앞선 시점의 미검증/즉시 지역 전환 기록을 갱신하는 최신 결과다. 과거 기록은 이력으로 보존한다.

### 구현·수정
- `game/world/korea_world.gd`, `player.gd`, `korea_world.tscn`: 서울·인천을 하나의 지도에 표시하고 지역 버튼을 상대 시청까지 걷는 명령으로 변경했다. NavigationRegion2D/NavigationAgent2D로 강·건물 외곽을 우회하며, 강은 다리에서만 건넌다. 같은 강 다각형에서 충돌과 보행 제외 영역을 생성하고 건물 발밑 충돌체를 외관 위치에 맞췄다. 수목/작은 도심 실루엣은 배경 장식이다.
- 두 시청 출입구 사이 참조 경로 1,242.59px를 환산 30,000m와 도보 목표 45초에 대응시켰다. 보행 속도는 약 27.61px/s다. 자동 물리 프레임 검사 편도는 44.72초였으며, 목표점 8px 이내 도착 허용 차이다. 도로 중심선을 같은 내비게이션 경로로 그렸다. 차량비는 구현하지 않았다.
- 방향키 입력은 클릭 경로와 예약 상호작용을 취소한다. 도달 불가 클릭은 가까운 보행 지점으로 보정한다. 구버전 저장 위치도 새 보행면으로 보정하며 저장 스키마/경제 데이터는 유지한다. 위치를 2초 간격 및 정상 종료 시 동기화하고 카메라를 지도 범위로 제한했다.
- `game/app/scene_router.gd`: 내부 진입 중 야외 종료 저장이 확정된 복귀 출입구를 덮어쓰지 않도록 수정했다. 시작 시 저장된 지역/위치를 귀환 기본값으로 읽는다.
- `game/city_hall/city_hall.gd/.tscn`: 실제 진입 검사에서 발견한 구형 노드 경로(`Columns/Order` 등)를 현재 `Columns/Body/...`로 수정했다. 시장/주문 컨테이너 폭과 전체 화면 앵커, 견적/결과 줄바꿈을 보완했다. 기존 서비스 거래 명령과 정산 규칙은 보존했다.
- `game/office/interior.gd`, `office.tscn`: 오브젝트 강조 패널은 클릭을 소비하지 않으며 포인터 이탈 시 숨긴다. 중첩 hover 채색을 줄였다. 건물 선택 메뉴 및 사무실 오브젝트 메뉴의 시간 정지 토큰을 연결했다. 업무 패널을 HUD 아래로 내리고 보고에 최신/주의/오래됨과 경과일을 표시했다. 보고의 가격·재고 스냅샷은 변경하지 않는다.
- `game/ui/time_hud.gd`, `game_theme.tres`, `game/office/finance.tscn`, `game/news/news_overlay.gd/.tscn`, `news_archive.tscn`: 날짜/상태를 0.25초마다 표시 갱신한다. 실제 GUI에서 발견한 뉴스·보고 팝업의 어두운 글자/배경, 재무 배경, 선택된 체크박스 글자, 수량 입력칸 대비를 보완했다. 뉴스는 HUD보다 위에 표시하고 상품 이름을 한국어로 보여준다. 새 이미지/의존성은 추가하지 않았다.
- `game/core/game_session.gd`: `--p0-tests` 실행 시 초기 로드부터 검사 전용 저장을 선택한다. 사용자 세이브는 삭제하거나 초기화하지 않았다.
- `tests/p0_flow_checks.gd/.tscn`: 실제 물리 프레임 이동·지역별 거래, 입력 전환·물 클릭 보정·UI 클릭 차단, 세 건물 각각 2회 실제 장면 출입, 귀환 위치, hover 및 메뉴 정지, 조사·뉴스·비용·저장 복구와 새 엔진 프로세스 복원을 검사한다.

### 자동 검사 결과
| 검사 | 결과 | 주의/범위 |
|---|---|---|
| Godot 4.7.2 에디터 headless 스캔 | 종료 0, 파일 스캔 완료 | 기존 에디터 설정 safe-save 권한 경고가 있음. 게임 파싱 오류와 구분 |
| P0 통합 | `P0_FLOW_OK: failures=0`, 종료 0 | 최종 실행 로그에 SCRIPT ERROR/ERROR/P0_FAILED 없음 |
| P0 별도 프로세스 재시작 | `P0_RESTART_OK`, 종료 0 | 거래 ID·지역·조사 보고·열람 기사 복원 |
| 기존 Phase 2 | `PHASE2_CHECKS_OK: 9 groups`, 종료 0 | 손상 세이브 백업 검사에서 의도한 JSON 파싱 오류가 출력됨 |
| 기존 Phase 3 | `PHASE3_CHECKS_OK: 6 groups`, 종료 0 | 달력·정지 토큰·출장/화물·뉴스/해제·비용·저장/거래 회귀 |

초기 통합 검사에서 다리 직전 정지와 시청 UI 노드 경로 오류를 발견해 수정했다. 최초의 장면 경로만 확인하던 검사를 시장 목록/주문 위젯/견적 준비까지 확인하도록 강화했다. 테스트의 정상 종료 문구만으로 엔진 오류를 무시하지 않고 로그도 확인했다.

### 실제 GUI 도구로 확인한 항목
- AMD OpenGL Compatibility에서 격리된 게임 창을 실행했다. 서울 시청 상품 선택·매입, 실제 도보로 다리 건너 인천 이동, 인천 시청 진입·판매·재고/보유량/계좌/실현손익 표시를 확인했다.
- GUI 거래는 서울에서 수산물 4,102원 매입 후 인천에서 1,420원 판매하여 손익 -2,682원이었다. 수치를 바꾸어 이익으로 만들지 않았다. 반대 방향의 이익 발생 경로는 자동 물리 이동/거래 검사에서 확인했다.
- 사옥 복귀, 노트북 업무 선택, 동행 해제/화물 비움 확인, 출장 확정 시 법인 5,000원 차감, 2025-02-02 관측 보고 도착과 6개 품목의 가격·재고·추세 본문을 확인했다.
- 2025-02-01 뉴스 발생과 시간 정지, 뉴스 대기 중 종료/새 프로세스 실행 시 같은 기사 복원, 확인 후 시간 재개를 확인했다. 재시작 후 법인 잔액 992,318원과 직원 동행 슬롯 제외 상태가 유지됐다. 보고도 다음 재실행에서 유지됐다.
- 노트북·비서·전화기 강조, 포인터 이탈 후 강조 해제, 클릭 메뉴 및 시간 정지를 확인했다. 개선한 보고 본문 패널 가독성과 보통 창/최대화 시 HUD·업무 메뉴 배치를 확인했다.
- 사용자가 이전에 확인한 방향키/클릭 이동과 건물 메뉴 정상 보고는 별도 사용자 확인 이력이다. 이번 GUI 도구 검증을 사용자 최종 인수 승인으로 간주하지 않는다.

### P0 완료 체크리스트 대조
| 기획 항목 | 현재 판정 | 근거 |
|---|---|---|
| 실행 및 서울·인천 이동 | 기능 완료 | 실제 보행 연결, 자동 왕복 및 GUI 지역 이동 |
| 사옥·시청 진입/출구 복귀 | 기능 완료 | 세 건물 각 2회 자동 출입, 실제 GUI 사옥·두 시청 진입/복귀 |
| 법인 매입 및 인물 적재 | 기능 완료 | 기존 9그룹 + GUI 계좌/재고/보유량 변화 |
| 다른 지역 판매·내역·순이익 | 기능 완료 | 실제 도보 후 자동/GUI 판매, 원장/손익 서비스 검사 |
| 조사 지시·관측일 보고 | 기능 완료 | 비용/동행/화물 검사, GUI 지시·도착·보고, 저장 복원 |
| 날짜·일별 시세·뉴스 | 기능 완료 | Phase 3 자동 검사, GUI 날짜 뉴스·정지/재개 |
| 계좌·화물·일정·사건·위치 저장 | 기능 완료 | 구버전/백업 검사, 별도 프로세스 재시작, GUI 뉴스·출장·계좌 복원 |
| P1/P2 미구현 구분 | 완료 | 차량·전투·피랍·작업장·부동산·일반 대출 등은 미구현 유지 |

**P0 핵심 기능 구현 및 통합 검증 완료. 사용자 최종 인수는 대기.** 최종 미술이나 Windows 배포본 완성을 뜻하지 않는다.

### 남은 작업·제약
- Windows 내보내기와 실행 파일 검증은 이번에 수행하지 않았다. 이전 확인 이력에는 4.4.1 Mono 템플릿만 있어 4.7.2 Standard 템플릿 준비/설치 승인이 필요하다.
- 도시 지도/건물/주인공/실내는 임시 미술이다. 걷기 애니메이션, 분리된 비서 자산과 출장 상태에 따른 실내 그림 전환은 미완료다. 사무실 강조는 물체별 사각 영역이며 그림 윤곽을 따르는 마스크가 아니다.
- 모든 창 비율/고해상도와 장시간 경제 밸런스의 전수 검증은 하지 않았다. 방향키 전환·불가 지점·UI 입력 차단·비용 1회·뉴스 효과 해제는 자동 검사로 확인했으며 동일 항목을 전부 GUI로 재현했다고 주장하지 않는다.
- P1은 다음 사용자 승인 대기이며 이번에 시작하지 않았다. P2도 미착수다. AGENTS.md/GAME_DESIGN.md 변경 없음. 설치·유료 호출·외부 업로드·Git 초기화/커밋/푸시 없음.


## 2026-11-08 Phase 4 — 차량·적 조우·수동 전투·피랍

이 절이 Phase 4의 최신 결과다. Phase 5 작업장·부동산·국내 확장은 시작하지 않았다.

### 구현
- `data/vehicles.json`, `data/mercenaries.json`, `data/enemies.json`: 기획안에 정의된 차량 가격·하중·속도·거리비, 용병 능력치·고용료, 초급/일반 적 능력치를 데이터로 분리했다. 새로운 경제 수치는 추가하지 않았다.
- `game/core/game_session.gd`: 저장 schema 4와 schema 1·2·3 호환 기본값, 차량 구매/선택/거리비 잔액/주차/회수, 차량 화물·현지 보관, 용병 고용·치료·무료 재기, 전투 명령·결과 ID·결과별 화물 손실, 피랍 단계·고정 요구액·협상·석방 전용 구조 채무를 통합했다. 거래·계좌·화물·원장 변경은 상태 소유자 명령으로 처리한다.
- `game/world/player.gd`, `game/world/korea_world.gd`, `game/world/enemy/enemy_actor.gd`: 주인공 실제 이동 거리로 차량비를 청구하고 차량 선택 속도를 반영한다. 비용을 낼 수 없는 경우 차량이 해당 위치에 주차되고 화물은 차량에 남는다. 서울↔인천 경로 다리 순찰 적의 배회·감지·추격·접촉과 건물 주변 안전 구역, 재조우 유예, 전투 후 복귀 위치를 연결했다. 사용자가 적 출현 구간으로 지정한 서울↔인천 경로를 따랐다. 기획의 최초 안전 노선 권고와는 다르며, 사용자 확정에 따른 변경이다.
- `game/city_hall/city_hall.gd/.tscn`, `game/office/interior.gd`: 시장 주문의 화물 소유자 선택에 활성 차량을 추가하고 같은 시청 위치에서 인물/차량 간 화물 이전 및 현지 보관·재회수를 제공한다. 사옥 노트북은 차량 구매/선택, 비서는 용병 고용·치료·제한된 재기를 제공한다.
- `game/combat/battle.gd/.tscn`, `game/combat/battle_rules.gd`: 자동 전투 없이 공격·고유기·방어·교체·도주 선택, 순서/피해/재사용/지속 효과/불능 및 전투 결과를 처리한다.
- `game/captivity/captivity.gd/.tscn`, `game/app/scene_router.gd`: 패배 후 회사 전화→직원 협상→요구액 지급/구조자금→석방 장면→사옥 복귀를 저장된 단계로 이어준다. 피랍 중 계좌 간 자금 이전을 차단한다.
- `game/ui/time_hud.tscn`: 야외에 차량/중량 정보를 추가했다. `tests/phase4_checks.gd/.tscn`: P1 기능 및 별도 프로세스 저장 복구 검사를 추가했다.
- `README.md`: 차량·전투·피랍 조작과 schema 4, 전용 검사 명령을 갱신했다. `AGENTS.md`, `GAME_DESIGN.md`는 변경하지 않았다.

### 자동 검증
실행 엔진: Godot 4.7.2.stable.official.ed1daf0bf. 모든 자동 검사는 아래 격리 APPDATA로 실행해 기본 사용자 저장을 사용하지 않았다.
```powershell
$env:APPDATA = Join-Path (Get-Location) '.godot\p1_final_appdata'
$godot = '<Godot 4.7.2 console 실행 파일 경로>'
& $godot --headless --editor --path . --quit
& $godot --headless --path . res://tests/phase4_checks.tscn --quit-after 20 -- --phase4-tests
& $godot --headless --path . res://tests/phase4_checks.tscn --quit-after 20 -- --phase4-tests --phase4-reload
& $godot --headless --path . res://tests/p0_flow_checks.tscn --fixed-fps 60 -- --p0-tests
& $godot --headless --path . res://tests/p0_flow_checks.tscn -- --p0-tests --p0-reload
& $godot --headless --path . res://tests/phase2_checks.tscn -- --phase2-tests
& $godot --headless --path . res://tests/phase3_checks.tscn -- --phase3-tests
```
- 에디터 스캔은 종료 코드 0으로 프로젝트 스캔/클래스 등록을 완료했다. Godot 파일 safe-save 권한 경고가 한 번 나왔지만 에디터 프로세스는 정상 종료했다.
- Phase 4 검사: `PHASE4_OK`, 종료 0. Phase 3 저장 schema 3→4 변환과 위치/계좌 보존, 구매 잔액 부족·주문 중복·차량비 소수 누적·화물 이전/임시 보관/재회수·하중 초과 원자성·용병 정원·치료 단가와 계좌·하루 1회 무료 재기·공격 고유기 피해/재사용·중복 조우·잘못된 명령 무턴·방어 고유기·용병 교체·수동 승리·중복 전투 결과·재조우 유예·도주 화물 손실·패배 손실 범위·피랍 송금 차단·전화 순서·요구액/구조 채무·중복 지급 ID·저장 및 전투/피랍 장면 인스턴스화를 통과했다.
- Phase 4 별도 프로세스 재시작: `PHASE4_RESTART_OK`, 종료 0. 석방 컷씬 단계·법인 잔액·구조 채무 잔액/회차·지급 ID 복원을 확인했다.
- P0 통합: `P0_FLOW_OK: failures=0`, 종료 0. P0 재시작: `P0_RESTART_OK`, 종료 0. 자동 물리 이동·시청 진입·지역 거래·저장 복구 회귀를 통과했다.
- 기존 Phase 2: `PHASE2_CHECKS_OK: 9 groups`, 종료 0. 손상 세이브 백업 테스트가 의도된 JSON 파싱 오류 한 줄을 출력했지만 전체 검사 결과는 통과다. Phase 3: `PHASE3_CHECKS_OK: 6 groups`, 종료 0.

### 사용자 확인·미검증 구분
- 이번 턴 실제 Godot GUI 조작은 완료하지 못했다. 격리 APPDATA로 Godot 창을 실행하려 했으나 GUI 자동화의 현재 창 목록에 새 Godot 프로세스 창이 노출되지 않고 기존 종료 창 항목만 반환되어 GUI 입력/관찰을 진행할 수 없었다. 따라서 P1 화면 가독성, 전투 버튼 조작, 구매 UI, 추격/충돌은 자동 검사 통과와 구분해 **GUI 미검증**이다. 이전 P0 GUI 확인은 P1 GUI 검증으로 간주하지 않는다.
- 플레이 경로의 적 출현은 사용자 지정 구간을 반영했다. 현재 야외 배치는 다리 순찰 초급 적 1개다. 일반 적 그룹은 데이터만 준비됐으며 야외 배회자로 배치하지 않았다.
- 자동 검사에서 차량 구매 부족·하중 초과 및 거리비 소수 누적을 검사했으나 실제 지도 이동 중 운송비 잔액 부족으로 주차·현지 회수 UI를 끝까지 재현하지는 않았다.
- 자동 검사에서 방어 고유기·교체·공격 승리·도주·패배·구조 자금·저장 복원은 확인했다. 공격형/교란 고유기, 용병 치료·일일 무료 재기, 전투 속도 동률 경계, 구조 채무 월 납부 적용의 전수 조합은 미검증이다.
- 차량 표식·전투/피랍 메뉴는 임시 UI/도형 및 텍스트 자산이다. 최종 SD 원화·애니메이션/연출·모든 화면 비율은 남아 있다.
- 구조 채무 월 상환액이 부족한 경우 기획에 파산/연체/강제 처분 정책이 확정돼 있지 않아, 강제 게임오버·추가 이자·담보 처분을 만들지 않았다. 납부되지 않은 회차는 남아 다음 월 납부일에 재시도한다. 최종 연체/파산 정책은 추후 사용자 결정이 필요하다.
- 차량 하중/속도/거리 단가, 용병·적 수치, 치료비·도주 확률, 화물 손실 범위, 피랍 요구액 등은 기획에 맞춘다. 임의 가격 조정은 하지 않았다. 사용자는 적을 서울↔인천 경로에서 출현하도록 확정했다.

**Phase 4 코드 및 자동 검사 완료. 실제 GUI 인수 검증은 미완료. P1 범위 추가 구현이나 Phase 5/P2는 시작하지 않는다.**

### 실제 실행 명령 및 격리 위치
Windows Git Bash 기준 재현 명령(같은 인수로 PowerShell에서도 실행했다):
```bash
GODOT='<Godot 4.7.2 console 실행 파일 경로>'
APPDATA="$PWD/.godot/p0_check_appdata" "$GODOT" --headless --editor --path . --quit
APPDATA="$PWD/.godot/p0_check_appdata" "$GODOT" --headless --path . res://tests/p0_flow_checks.tscn --fixed-fps 60 -- --p0-tests
APPDATA="$PWD/.godot/p0_check_appdata" "$GODOT" --headless --path . res://tests/p0_flow_checks.tscn -- --p0-tests --p0-reload
APPDATA="$PWD/.godot/p0_regression_appdata" "$GODOT" --headless --path . res://tests/phase2_checks.tscn -- --phase2-tests
APPDATA="$PWD/.godot/p0_regression_appdata" "$GODOT" --headless --path . res://tests/phase3_checks.tscn -- --phase3-tests
APPDATA="$PWD/.godot/p0_gui_appdata" "$GODOT" --path . -- --p0-tests
```
검사 세이브는 각각 `user://p0_checks/`, `phase2_checks/`, `phase3_checks/`이며 GUI는 별도 APPDATA 아래 `p0_checks/`다. 최종 P0 로그는 무시되는 캐시 `.godot/p0_flow_result.log`, 에디터 로그는 `.godot/p0_editor_result.log`에 기록했다.

## Phase 5 — 국내 작업장·사옥 성장·P1 국내 통합 최신 결과

### 선행 상태 및 구현
- 직전 Phase 4 코드를 실제로 확인하고 차량·전투·피랍·P0 거래/뉴스/조사 경로를 보존했다. Phase 4 상태 schema 4에서 Phase 5 상태 schema 5로 기본값을 추가하는 변환을 구현했다.
- `data/regions.json`, `data/products.json`, `data/markets.json`: 서울·인천에 수원·천안을 추가하고 지역별 시장·취급 품목·기획 특산 계수·작업장 수당을 연결했다.
- `data/mahjong_levels.json`, `game/mahjong/mahjong_rules.gd`, `game/mahjong/mahjong.gd/.tscn`, `game/city_hall/city_hall.gd/.tscn`: 초·중·고 보드와 현실시간 제한, 최대 2회 꺾임/외곽 1칸 경로, 장애 패 차단, 풀 수 있는 보드·막힘 재배치·힌트·포기·강제 종료·시간 종료 동시 판정을 추가했다. 세계 시계는 정지하고 성공 보상은 개인 계좌에 1회 지급하며 피로도·해금·보상 ID를 저장한다.
- `data/office_rules.json`, `game/core/game_session.gd`, `game/office/finance.gd/.tscn`, `game/office/interior.gd`: 임대 확장·첫 자가 사옥·정원·직원 역할/고용·고정비·일반 대출 한도/이자/원금 상환을 연결했다. 일반 대출은 피랍 전용 구조 채무와 분리했다. 사용자 결정에 따라 미납 이자·구조 채무 분할금은 수수료 없이 이월, 담보 대출 완납 전 자가 사옥 매각 차단, 현금 부족 시 게임오버 없이 영업 지속을 적용했다.
- 파산 시 자산 처분 선택의 정책은 반영했지만 실제 처분 화면과 매각은 미구현이다. 기획에 자가 사옥·차량 처분 가격이나 산식이 없어 매각 대금을 임의로 만들지 않았다.
- `game/ui/time_hud.gd`: 설정을 `user://settings.cfg`에 분리 저장하고 화면 설정 조절을 연결했다. 뉴스 기사 재열람·한국어 표시·기존 대사/UI 구조는 보존했다.
- `game/world/korea_world.gd`: 실제 메인 장면의 NavigationServer 동기화가 끝난 뒤 서울·인천·수원·천안 경로를 확인하는 `--phase5-map-tests` 검사를 추가했다. 테스트 전용 장면을 별도 인스턴스해 지도 경로를 질의할 때는 테스트 장면의 NavigationServer 동기화가 되지 않는 현상이 있어 그 방식은 제거했다. 실제 main 장면 경로 검사로 바꾼 결과 4개 연결을 확인했다.
- `tests/phase5_checks.gd/.tscn`: 지역·가격 계수·작업장 연결/초기 보드·수당·중복 지급·피로·실시간 제한/강제 종료·사옥 성장·고용·대출/이월·담보 매각 잠금·schema 4 변환·schema 5 저장 및 새 프로세스 복구를 검사한다. Phase 4 검사 픽스처는 별도 APPDATA가 처음 생성된 경우에도 동작하도록 보완했다.
- `README.md`: 국내 4개 지역, 작업장·성장·대출·설정 저장·검사 명령·내보내기 제한을 갱신했다. `AGENTS.md`와 `GAME_DESIGN.md`는 변경하지 않았다.

### P0/P1 기준 대조
| 범위 | 판정 | 근거와 제한 |
|---|---|---|
| P0 서울·인천 이동, 건물 출입/복귀, UI 클릭 차단 | 자동 검사 통과 / GUI 미검증 | 최신 속도 적용 후 P0 이동 22.73초, 시청 포함 출입구 5곳 메뉴, UI 클릭 차단 통과 |
| P0 지역 시장, 거래 원자성, 계좌 분리, 인물 화물 | 자동 회귀 통과 | Phase 2 9그룹 및 P0 매입·이동·판매 흐름 통과 |
| P0 조사 출장·스냅샷 보고·달력·뉴스·월 비용 | 자동 회귀 통과 | Phase 3 6그룹 및 P0 저장/재시작 통과 |
| P0 저장 복구 및 구버전 변환 | 자동 회귀 통과 | P0_RESTART_OK, schema 4→5 변환 검사 통과 |
| P1 차량·적 조우·수동 전투·피랍·구조 채무 | 기존 자동 회귀 통과 / GUI 미검증 | Phase4_OK/RESTART_OK 회귀 통과; 본 Phase에서 기능 로직 수정 없음 |
| P1 수원·천안 시장·작업장 접근 | 자동 검사 통과 / GUI 미검증 | 네 지역 가격/시장 데이터 및 4지역 보행 경로 검사 통과 |
| P1 같은 패 연결 규칙·보상·시간·피로·저장 | 자동 검사 일부 통과 / GUI 미검증 | 경로·보드·보상 1회·제한시간·강제 종료·피로·재시작 검사 통과; 전수 보드/시각 상호작용은 미검증 |
| P1 임대 확장·자가 사옥·고용·고정비·일반 대출 | 자동 검사 일부 통과 / GUI 미검증 | 비용·정원·역할·이자·원금·미납 이월·담보 잠금 통과; 위기 자산 처분은 미구현 |
| P1 설정 분리·뉴스 재열람·한국어/창 크기 UI | 일부 구현 / GUI 미검증 | 설정 파일 분리 구현; 재열람 기존 동작 보존; 실제 리사이즈·가독성 확인 미실행 |
| P1 Windows 로컬 실행 파일 | 차단·미실행 | Godot 4.7.2 Standard 템플릿이 없어 빌드 불가; 설치 승인 필요 |

### 실제 자동 검증
엔진: Godot `4.7.2.stable.official.ed1daf0bf`. 검사 데이터는 사용자 저장과 분리한 프로젝트 `.godot/` 하위 APPDATA를 사용했다.

```powershell
$godot = '<Godot 4.7.2 console 실행 파일 경로>'
$env:APPDATA = Join-Path (Get-Location) '.godot\phase5_check_appdata'
& $godot --headless --path . res://tests/phase5_checks.tscn -- --phase5-tests
& $godot --headless --path . res://tests/phase5_checks.tscn -- --phase5-tests --phase5-reload
& $godot --headless --path . -- --phase5-map-tests
```
- 결과: `PHASE5_OK`, 별도 프로세스 `PHASE5_RESTART_OK`, 실제 main 월드에서 `PHASE5_MAP_OK: four regions have walkable paths`. 모두 종료 코드 0.
- P0 통합·재실행: 속도/UI 개편 후 `P0_FLOW_OK: failures=0`, `P0_RESTART_OK`, 종료 0. 시청 5곳 메뉴·방향키 이동 전환·물 위 목표 보정·UI 클릭 차단·4인 초상 슬롯 갱신·서울↔인천 경로 약 22.73초·거래 및 저장 복구를 확인했다.
- 회귀: Phase 2 `PHASE2_CHECKS_OK: 9 groups`, Phase 3 `PHASE3_CHECKS_OK: 6 groups`, Phase 4 `PHASE4_OK`, `PHASE4_RESTART_OK`, 종료 0. Phase 2 손상 저장 백업 테스트는 예상된 JSON 파싱 오류 로그 1줄을 남겼으나 전체 검사 결과는 통과했다.
- 에디터 파일 스캔 `--headless --editor --path . --quit` 및 메인 장면 `--headless --path . --quit-after 30`은 종료 코드 0. 에디터가 Windows Safe save 권한 경고를 출력했으나 스캔·클래스 로드와 장면 시작은 완료했다.
- 확인된 템플릿 경로 `%APPDATA%\Godot\export_templates`에는 `4.4.1.stable.mono`만 있다. Godot 4.7.2 Standard 템플릿은 없고 다운로드·설치 승인도 없어 Windows preset/export, `builds/windows/` 생성·실행은 미실행이다.

### 사람 확인과 미검증 구분
- Godot GUI 창을 자동화 도구에서 선택 가능한 창으로 가져오지 못해 실제 마우스/키보드 작업장 플레이, UI 배치/리사이즈, 거래→전투/피랍→작업장→성장 대표 흐름을 사람이 확인하지 못했다. headless 테스트 통과와 GUI 확인은 구분한다.
- 일반 대출 이자 미납 이월·사옥 담보 잠금은 자동 검사했다. 실제 파산 자산 처분 UI, 자산 매각과 처분 후 계좌/채무 결산은 가격 기준 부재로 미구현이다. 차량·사옥 매각가/산식에 대한 사용자 결정이 필요하다.
- 4개 지역 시장·수당 데이터 및 경로 가능성은 검사했지만 서울에서 모든 도시까지의 전체 이동시간·차량 비용 균형은 수원/천안 거리 수치가 기획에 지정되지 않아 임의로 산정하지 않았다.
- 작업장 패 연결·초기 보드/보상·제한시간/강제 종료는 자동 검사했으나 난도별 전수 보드, 포인터 조작감, 표시 글자/창 크기별 UI는 GUI 미검증이다.
- 임시 그림·아이콘·현 지도 장식은 최종 미술 자산이 아니다. P2의 항해·해외·해적·주식·아이템·직원 위임 거래는 시작하지 않았다.

### 다음 승인 대기
- Windows 로컬 실행 파일을 만들려면 Godot 4.7.2 Standard Windows export template 다운로드·설치 승인이 필요하다. 설치 없이 이번 요청의 export 완료 조건은 차단됨.
- 실제 자산 처분 기능을 완성하려면 자가 사옥·차량별 처분 가격/산식과 처분 순서의 승인이 필요하다. 현재는 영업 지속과 미납 이월까지만 적용한다.
- P1 국내 기능의 GUI 검증 및 남은 처분 기능은 완료되지 않았다. P2는 시작하지 않는다.

## 2026-11-08 후속 — 기본 이동속도 및 좌측 동행 HUD 개편

- 사용자 요청의 시각 참고는 첨부한 거상 스크린샷의 좌측 초상 세로 배치·좌측 하단 상태창 구조만 참고했다. 스크린샷의 게임 규칙·문구·에셋을 복제하거나 기획 지시로 취급하지 않았다.
- `game/world/korea_world.gd`: 기준 경로 환산 30km 및 차량 배수/거리비 산식은 유지하고 기본 도보 기준만 45초에서 22.5초로 줄여 이동속도를 2배로 했다. 이는 GAME_DESIGN.md의 기존 45초 권장값에 대한 최신 사용자 요청 반영이다.
- `assets/party_roster_plaque.png`: 이미지 생성 도구로 투명 배경·4칸 세로 초상 프레임을 새로 생성했다. 기존 SD 주인공/직원 초상을 각 슬롯에 겹쳐 쓴다. 임시 생성 자산이며 최종 미술은 아니다.
- `game/world/korea_world.tscn`: 기존 왼쪽 동행 패널을 세로 프레임으로 바꾸고 4개 슬롯에 맞췄다. 초기에는 주인공 이동 대표+직원 1명, 나머지는 빈 슬롯을 표시한다. 이동 대표와 계좌/화물 규칙은 변경하지 않았다.
- `game/ui/time_hud.tscn`, `game/ui/time_hud.gd`: 날짜·계좌·차량·월세/급여 상태창을 좌측 하단으로 옮기고 동행 목록을 최대 4칸까지 현재 파티 ID에 따라 표시하도록 조정했다. 기존 차량 정보는 하단 상태 HUD에 남긴다. 조작 안내 바는 하단 상태창과 겹치지 않도록 중앙으로 이동했다.
- `tests/p0_flow_checks.gd`: 사용자 변경에 맞춰 실제 이동시간 검사 기준을 약 22.5초로 바꿨다. 환산 거리 30km는 동일하다.
- `README.md`: 현재 초상·하단 HUD 위치, 이동속도 변경 및 임시 프레임 에셋을 기록했다.

### 이 변경의 검증 결과와 제한
- Godot 4.7.2 에디터 스캔 종료 코드 0(Windows Safe save 경고 1회), P0 이동/초상 HUD `P0_FLOW_OK: failures=0`, 새 프로세스 `P0_RESTART_OK`, Phase 5 저장 회귀 `PHASE5_OK`/`PHASE5_RESTART_OK`, 4지역 경로 `PHASE5_MAP_OK`를 확인했다.
- 자동 검사에서 기본 이동 편도 22.73초, 환산 거리 30km 유지, 네 슬롯 및 네 번째 직원 ID 라벨을 확인했다. 실제 화면에서 프레임 안 초상 정렬·텍스트 가독성·창 크기 대응을 확인하지 않아 GUI 시각 검증은 남아 있다.

## 2026-11-08 후속 — 서울 사옥 도시 배경 강화

- `assets/office_seoul_interior_bg.png`: 기존 사옥 실내의 책상·노트북·비서·전화 구도를 유지하면서 창밖에 남산 서울타워·한강·서울 시가지를 더 넓게 보여주는 16:9 임시 배경을 생성했다. 이전 `assets/office_interior_bg.png`는 원본 보존했다.
- `game/office/office.tscn`: 사옥 진입 시 새 서울 배경을 표시하도록 배경 텍스처 연결만 교체했다. 기존 핫스팟 좌표와 메뉴 동작은 유지했다.
- `README.md`: 새 배경의 내용과 임시 자산 상태를 기록했다. 이미지 생성 에셋은 최종 미술·상표 검토가 끝난 자산이 아니다.
- Godot 4.7.2에서 `--headless --editor --path . --quit`로 새 PNG import/장면 리소스 스캔을 마쳤고, `--headless --path . res://game/office/office.tscn --quit-after 30` 사옥 장면 기동도 종료 코드 0으로 끝났다. 에디터 스캔은 Windows Safe save 경고 1회를 출력했다. 실제 GUI 화면과 hover 핫스팟 정렬은 직접 확인하지 않았다.
