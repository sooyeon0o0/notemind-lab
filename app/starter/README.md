# NoteMind 실습 시작 코드 (app-starter)

화면(UI)과 상태 관리는 완성되어 있고, 핵심(core) 함수 12개가 비어 있는 실습용 프로젝트입니다.
비어 있는 함수는 `UnimplementedError('TODO(n): ...')`를 던집니다.
앱은 실행되지만 해당 기능을 누르면 화면에 `UnimplementedError: TODO(n)` 오류가 표시됩니다.

## 실행

먼저 서버(Supabase, 추론 서버)를 켜고 에뮬레이터에 `adb reverse`를 등록합니다.
방법은 저장소 루트 [README의 '수업 때마다'](../README.md#수업-때마다)를 따르세요.

```bash
cd app-starter
flutter pub get
flutter run
```

처음 실행하면 **연결 설정** 탭이 열립니다. 각자 PC의 값을 넣고 **설정 저장**을 누르세요.

- Supabase 공개 키: `docker/supabase/.env`의 `ANON_KEY`
- 로컬 추론 API 키: `docker/vllm/.env`의 `VLLM_API_KEY`
- 주소·모델 ID는 기본값 그대로 사용합니다.

에뮬레이터는 Mac 클립보드를 공유하므로 Mac에서 복사한 키를 입력란에 붙여 넣을 수 있습니다.
완성본 앱과 같은 앱 ID(`kr.ac.daelim.notemind`)를 사용하므로, 에뮬레이터에 완성본이 설치되어 있으면 덮어씁니다.

## 구현 순서

| TODO | 파일 | 함수 | 끝나면 되는 것 | 확인 테스트 |
|---|---|---|---|---|
| 1 | `lib/core/text_processing.dart` | `chunkText` | 글자 단위 청크 분할 | `test/core_test.dart` |
| 2 | `lib/core/document_import.dart` | `extractDocumentChunks` | txt·md·pdf 텍스트 추출 | `test/document_import_test.dart` |
| 3 | `lib/data/inference.dart` | `embed` | 임베딩 벡터 요청 | `test/core_test.dart` |
| 4 | `lib/data/repository.dart` | `ingest` | **문서 업로드 동작** | 앱에서 업로드 |
| 5 | `lib/data/repository.dart` | `retryDocument` | 실패 문서 다시 시도 | 앱에서 재시도 |
| 6 | `lib/data/repository.dart` | `createConversation` | 대화 생성 | — |
| 7 | `lib/data/repository.dart` | `saveMessage` | 메시지 저장 | — |
| 8 | `lib/core/text_processing.dart` | `isDocumentOverviewRequest` | 요약 요청 판별 | `test/core_test.dart` |
| 9 | `lib/data/repository.dart` | `search` | 벡터 검색(근거 찾기) | — |
| 10 | `lib/data/repository.dart` | `overview` | 요약용 근거 | `test/overview_repository_test.dart` |
| 11 | `lib/core/text_processing.dart` | `sseData` | 스트리밍 응답 파싱 | `test/core_test.dart` |
| 12 | `lib/data/inference.dart` | `chat` | **질문하기 답변 동작** | `test/core_test.dart` |

- TODO 1~5를 끝내면 문서 업로드가 동작합니다.
- TODO 6~12를 끝내면 질문하기(RAG 답변)가 동작합니다.
- 각 함수 안의 주석에 단계별 힌트가 있습니다.

`flutter test`로 진행 상황을 확인할 수 있습니다. 처음에는 core 테스트가 실패하고,
TODO를 채울수록 통과하는 테스트가 늘어납니다.
전체 기능은 `integration_test/`의 통합 테스트로 확인합니다.

## 미리 완성된 부분

화면과 직접 연결된 함수는 그대로 동작합니다.

- `validateDocumentFile`: 파일 선택 직후 확장자·크기 검사
- `NoteRepository.documents` / `conversations` / `messages` / `removeDocument`: 문서함·대화 목록·삭제
- `InferenceSession.probe`: 연결 설정 탭의 **연결 확인**
- `lib/features/`의 화면과 컨트롤러, `lib/main.dart`, `lib/core/config.dart`, `lib/data/models.dart`
