# PR P4 — JSON/CSV export + 로그 + 메타 (baseline 산출)

- 브랜치: `feat/loc-69-profiler-export` (P3 위에 스택)
- Linear: [LOC-69](https://linear.app/loceract/issue/LOC-69)
- 상태: 🟦 진행 (PR 열림 예정, iPhone 실기 profile 런 green) — **baseline 산출 = 1차 목표 달성**

## 스코프
- `example/lib/profiling/profile_export.dart` — 리포트를 앱 documents dir에 `query_profile_<ts>.json/.csv`로 flush 기록 + 실행당 `PROFILE` 로그 1줄 + dir/파일명 로그(추출용). 물리기기 추출은 Xcode Download Container 또는 `xcrun devicectl`(simctl은 시뮬전용).
- 측정 엔트리에 export 배선 + 실행 메타(os/os_version; 기기모델·충전상태는 수동 기록).

## 결과 (baseline, iPhone iOS 26.5, profile, 컬렉션당 500 docs, topK=10)
| lane | category | embed p50/p95 | activate | search p50/p95 | hydrate p50/p95 |
|---|---|---|---|---|---|
| unfiltered | pure_cold (n=1) | 25.2 | **247.3** | 2.20 | 0.42 |
| unfiltered | pure_warm (n=30) | **26.7 / 36.7** | — | 1.60 / 2.08 | 0.27 / 0.41 |
| filtered(i8) | pure_warm (n=30) | **27.6 / 37.6** | — | 0.76 / 0.92 | 0.19 / 0.30 |
| unfiltered | switching_cold (n=30) | 25.7 / 37.0 | (로그 트렁케이션 유실) | 1.47 / 1.90 | (유실) |

I/O(query_metrics): full_hydrate_rows pure_warm 300 / filtered 90 / pure_cold 10. `scoped_exact_scan_*` 전부 0(현 쿼리 형태에서 콘텐츠 스캔 카운터 미증가).

## 지배 세그먼트 → P5(LOC-70) 게이트
- **Warm 정상상태: `embed`(ONNX) 지배** — p50 ~27ms, search/hydrate의 15–37배. PLAN 규칙상 *embed 지배 → 다음 타깃은 ONNX 추론(이 크레이트 외부), Rust 벡터 작업 불필요.*
- **Cold 첫 쿼리: `activate`(HNSW build/load) 지배** — 247ms ≫ embed/search/hydrate. *Phase-2(P5)에서 activate를 `bm25_rebuild` vs `hnsw_load`로 분해(cold/switch에 한해 필수).*
- 부가: 필터(i8 exact-scan) search가 unfiltered(HNSW+BM25 RRF)보다 빠름(0.76 vs 1.60ms) — [LOC-64](https://linear.app/loceract/issue/LOC-64) i8 결과와 일관.

## ⚠️ 측정 범위 (헤드라인 정정 — latency ≠ quality)
- 본 baseline은 **지연(latency) 분해**만 측정한다. **검색 품질(recall)은 측정하지 않는다.**
- LOC-64의 `recall@10 = 0.997`은 **i8 exact-scan vs f32 전수조사의 수학적 충실도**(양자화 커널 정확도)일 뿐, **실제 출시 경로의 HNSW 그래프 e2e 하이브리드 리콜이 아니다** — HNSW는 `dequantize_i8_to_f32`로 복원한 찌그러진 벡터 공간 위에서 그래프를 탐색하므로 별개. 즉 "i8가 빠르다 + 0.997"을 "출시 검색 품질이 우수하다"로 읽으면 안 된다.
- **실제 프로덕션 e2e 하이브리드 리콜은 미측정** → **P5(LOC-70)의 1순위 타깃**(폰에서 `[f32 순수 원본 전수조사 top-K]` 대비 `[i8-HNSW + BM25 RRF top-K]` 교집합률 산출). 90% 미만이면 모바일용 `M`/`ef_search` 상향 튜닝 필요.

## 받은 피드백 / 한계
- 어드버서리얼 리뷰 HIGH: 초기 추출 안내가 simctl(시뮬전용)이었음 → 물리기기는 Xcode Download Container / `devicectl`로 정정.
- `switching_cold`의 activate(스위치당 load 비용) 미확보: 콘솔 트렁케이션 + 성공 런 export가 다음 런 재설치로 삭제 + 이후 DDS 간헐실패. **결론 불변**(pure_cold 247ms가 cold에서 activate 지배 입증). CSV 행 단위 print 수정으로 다음 런에서 완전 수집 가능.
- 전체 디바이스/방법/디버그 로그는 [LOC-68 코멘트](https://linear.app/loceract/issue/LOC-68) 참조.

## 리스크 / 롤백 / 다음
- 동작 코드 변경 없음(example 프로파일링 export). 롤백: PR revert.
- ⚠️ **스택 PR**: P3(#LOC-68) 위에 스택. P3 먼저 머지 후 본 PR을 main으로 retarget(아니면 orphan).
- 다음: **P5(LOC-70)** Phase-2 — warm은 embed(ONNX) 지배라 Rust 벡터 작업 불요; cold가 중요하면 activate(bm25_rebuild vs hnsw_load) 분해. 데이터 게이트 충족.
