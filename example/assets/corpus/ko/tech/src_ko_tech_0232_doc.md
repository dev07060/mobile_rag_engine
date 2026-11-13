# 증명 보조기

- source_key: src_ko_tech_0232
- language: ko
- domain: tech
- length_bucket: medium
- collected_at: 2026-02-22
- url: https://ko.wikipedia.org/wiki/%EC%A6%9D%EB%AA%85_%EB%B3%B4%EC%A1%B0%EA%B8%B0

---

컴퓨터 과학 및 수리 논리학에서 증명 보조기 또는 대화형 정리 증명기는 인간-기계 협업에 의한 형식 증명을 보조하는 소프트웨어 도구이다. 증명 보조기는 대화형 증명 편집기 또는 기타 인터페이스가 포함하며, 이를 통해 인간의 증명 검색을 돕는다. 또한 증명 보조기는 증명의 세부 정보를 컴퓨터에 저장하고, 증명의 일부 단계를 컴퓨터로 계산한다.

시스템 비교

ACL2– Boyer-Moore 전통의 프로그래밍 언어, 1차 논리 이론 및 정리 증명기(대화형 모드와 자동 모드 모두 포함).
Coq- 수학적 주장의 표현을 허용하고, 이러한 주장의 증명을 기계적으로 확인하고, 형식적 증명을 찾는 데 도움을 주고, 형식 사양의 구성적 증명에서 인증된 프로그램을 추출한다.
HOL 정리 증명기– 궁극적으로 LCF 정리 증명기에서 파생된 도구 제품군이다. 이러한 시스템에서 논리적 핵심은 프로그래밍 언어의 라이브러리이다. 정리는 언어의 새로운 요소를 나타내며 논리적 정확성을 보장하는 "전략(strategy)"을 통해서만 도입될 수 있다. 전략 구성을 통해 사용자는 시스템과의 상호 작용이 비교적 적은 중요한 증명을 생성할 수 있다. 여기에 포함된 증명 보조기들은 다음과 같다.
HOL4– 아직 활발히 개발 중인 "기본 자손". 모스크바 ML 및 Poly/ML 모두 지원 . BSD 스타일 라이센스가 있다.
HOL Light – 번성하는 "미니멀리스트 포크". OCaml 기반.
ProofPower – 독점이 된 다음 오픈 소스로 돌아 왔다. 표준 ML을 기반으로 한다.
IMPS, 대화형 수학 증명 시스템
Isabelle은 HOL의 후속인 대화식 정리 증명자이다. 주요 코드 기반은 BSD 라이선스이지만 Isabelle 배포판은 다른 라이선스를 가진 많은 애드온 도구를 번들로 제공한다.
Jape – 자바 기반.
Lean
LEGO
Matita – 귀납적 구성의 미적분에 기반한 조명 시스템.
MINLOG – 1차 최소 논리를 기반으로 하는 증명 보조기.
Mizar – 자연 연역 스타일의 1차 논리와 타르스키-그로텐디크 집합론을 기반으로 하는 증명 보조기.
PhoX – 확장 가능한 고차 논리에 기반한 증명 보조기.
프로토타입 검증 시스템 (PVS) – 고차 논리에 기반한 증명 언어 및 시스템.
TPS 및 ETPS – 단순 형식 람다 대수의 독립적인 공식화와 구현을 기반으로 하는 대화형 증명 보조기.
Typelab
Yarrow 보관됨 2022-05-27 - 웨이백 머신
정리 증명기 박물관은 중요한 문화/과학적 인공물인 정리 증명 시스템의 향후 분석을 위해 소스를 보존하기 위한 이니셔티브이다. 위에서 언급한 많은 시스템의 소스가 여기에 있다.

사용자 인터페이스
증명 보조기를 위한 인기 있는 프론트엔드는 에든버러 대학교에서 개발된 Emacs 기반 Proof General이다. Coq에는 OCaml/GTK를 기반으로 하는 CoqIDE가 포함되어 있다. Isabelle에는 jEdit 및 문서 지향 증명 처리를 위한 Isabelle/Scala 인프라를 기반으로 하는 Isabelle/jEdit가 포함되어 있다. Coq 보관됨 2021-12-04 - 웨이백 머신, Isabelle의 비주얼 스튜디오 코드 확장도 개발되었다.

같이 보기
자동 정리 증명
컴퓨터를 이용한 증명
QED 선언문
형식 검증
만족도 모듈로 이론
Metamath – 이 언어에 대한 증명 검사기 및 수천 개의 입증된 정리 데이터베이스와 함께 공식화된 수학을 개발하기 위한 언어

참고 문헌
Henk Barendregt and Herman Geuvers (2001). "Proof-assistants using Dependent Type Systems". In Handbook of Automated Reasoning.
Frank Pfenning (2001). "Logical frameworks". In Handbook of Automated Reasoning.
Frank Pfenning (1996). "The Practice of Logical Frameworks".
Robert L. Constable (1998). "Types in computer science, philosophy and logic". In Handbook of Proof Theory.
H. Geuvers. "Proof assistants: History, ideas and future".
Freek Wiedijk. "The Seventeen Provers of the World"

각주

외부 링크
종속 유형이 있는 인증된 프로그래밍 의 "소개" .
Coq Proof Assistant 소개 (대화형 정리 증명에 대한 일반적인 소개 포함)
Agda 사용자를 위한 대화식 정리 증명 보관됨 2022-01-21 - 웨이백 머신
정리 증명 도구 목록

카탈로그
범주별 디지털 수학: Tactic Provers
자동 연역 체계 및 그룹
정리 증명 및 자동 추론 시스템
기존의 기계화 추론 시스템 데이터베이스
NuPRL: 기타 시스템 보관됨 2022-05-22 - 웨이백 머신
특정 논리적 프레임워크 및 구현
DMOZ : 과학: 수학: 논리 및 기초: 계산 논리: 논리 프레임워크 보관됨 2017-03-08 - 웨이백 머신
