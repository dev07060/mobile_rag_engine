# PR5 — 위생: 손상 블롭 로깅 (N6) + 엔디안 문서화 (N5)

- 브랜치: `feat/loc-63-hygiene`
- Linear: [LOC-63](https://linear.app/loceract/issue/LOC-63)
- 상태: 🟦 진행 (PR 열림, CI green 대기)

## 스코프 (백엔드 무관, 독립)
### N6 — 손상 블롭 로깅 (실제 코드 변경)
HNSW 인덱스 빌드 경로의 `decode_f32_embedding(&blob).unwrap_or_default()` 6곳
([simple_rag.rs](../../../rust_builder/rust/src/api/simple_rag.rs) 188/193/199,
[source_rag.rs](../../../rust_builder/rust/src/api/source_rag.rs) 891/896/902)이 손상 임베딩을
빈 벡터로 만들어 `!embedding.is_empty()` 필터에서 **조용히 드롭**됨.
- `vector_math::decode_f32_embedding_or_warn(&blob, row_id)` 헬퍼 추가: 실패 시 `log::warn!`(row_id 포함)
  후 빈 Vec 반환 → **동작 보존**(여전히 드롭), 단 손상이 로그로 가시화. 6곳 패턴도 한 곳으로 dedup.

### N5 — 엔디안 (보수적: 문서화만)
임베딩은 native-endian f32로 저장/읽기(`to_ne_bytes`/`from_ne_bytes`). 인코딩 사이트가 5곳에 분산
(hybrid_search:714, source_rag:764/2614/2694, simple_rag:293)이고 **모든 타깃이 LE라 실효 이득 0**,
asymmetric 누락 위험만 있어 **전면 정규화는 하지 않음**. 대신 `decode_f32_embedding` doc에 native-endian/LE
가정 + (정렬 미보장으로) zero-copy 캐스팅 불가를 명시.
- 후속 backlog: 공유 `encode_f32_embedding`/`decode` 헬퍼로 5개 인코딩 사이트 dedup + LE 정규화(원하면).

## 결과 (Before → After)
- 손상 임베딩: 무음 드롭 → **`log::warn!` 가시화** (동작 동일).
- 로컬 검증: fallback `cargo test --lib vector_math` 3 green; faer `--features vector_faer` 4 green(패리티 포함);
  `cargo check --features vector_faer,vector_quant_i8` 통과(quant 분기의 헬퍼 호출 포함).
- CI: (PR #__ green 후 갱신)

## 받은 피드백 (리뷰)
- (PR 리뷰 후 갱신)

## 리스크 / 롤백
- R7(엔디안 호환성): **포맷 미변경**(doc only) → 마이그레이션/호환 리스크 없음 → 닫힘.
- 동작 변경 없음(드롭 동작 보존 + 로그 추가). 롤백: PR revert.

## 결정 로그
- N5 전면 정규화 보류(LE-only 환경에서 실효 0, diff 넓음) → 문서화로 축소. 공유 encode 헬퍼는 backlog.
