# BIMI

- source_key: src_ko_tech_0143
- language: ko
- domain: tech
- length_bucket: medium
- collected_at: 2026-02-22
- url: https://ko.wikipedia.org/wiki/BIMI

---

BIMI(Brand Indicators for Message Identification, 메시지 식별을 위한 브랜드 지표)는 이메일 수신함에서 발신자 이름 옆에 브랜드 로고를 표시할 수 있도록 하는 이메일 인증 표준이다. 이 기술은 수신자가 이메일이 위조되지 않은 합법적인 발신자로부터 온 것임을 시각적으로 쉽게 확인할 수 있게 하여 피싱과 같은 이메일 기반 공격을 줄이고 브랜드의 신뢰도와 가시성을 높이는 것을 목표로 한다.
BIMI는 DMARC(Domain-based Message Authentication, Reporting, and Conformance) 정책이 적용된 도메인에서만 작동하며, 이는 이메일 생태계 전반의 보안 수준을 높이는 데 기여한다.

기술적 원리
BIMI의 핵심은 발신 도메인의 DNS에 특정 형식의 텍스트(TXT) 레코드를 게시하는 것이다. 이메일 서비스 제공자(ESP)는 이 레코드를 확인하여 해당 도메인의 로고와 인증서 유효성을 검증한 후, 수신자의 받은 편지함에 로고를 표시한다. BIMI가 작동하기 위해서는 다음과 같은 기술적 요구사항이 충족되어야 한다.

DMARC 정책
BIMI를 구현하려는 도메인은 반드시 DMARC 정책을 시행해야 한다. DMARC 정책은 최소 `p=quarantine` 또는 `p=reject`로 설정되어야 한다. `p=none` 정책에서는 BIMI가 작동하지 않는다. 이는 도메인 소유자가 자신의 도메인에서 발송되는 이메일에 대해 엄격한 인증 책임을 진다는 것을 의미한다.

BIMI DNS 레코드
도메인 소유자는 DNS에 다음과 같은 형식의 TXT 레코드를 추가해야 한다.

위치: `default._bimi.도메인명`
형식: `v=BIMI1; l=로고_SVG_파일_URL; a=VMC_인증서_URL;`
default._bimi.example.com. IN TXT "v=BIMI1; l=https://media.example.com/logo.svg; a=https://media.example.com/certificate.pem;"

`v=BIMI1`: 사용되는 BIMI의 버전을 명시한다. 현재 버전은 'BIMI1'이다.
`l=`: HTTPS를 통해 접근 가능한 브랜드 로고의 URL을 지정한다. 로고는 SVG(Scalable Vector Graphics) 형식이어야 한다.
`a=`: 선택 사항이지만, Gmail 등 주요 이메일 제공업체에서 요구하는 VMC(Verified Mark Certificate) 파일의 URL을 지정한다.

로고 파일 형식
BIMI에 사용되는 로고는 특정 요구사항을 충족하는 SVG Tiny 1.2 형식이어야 한다. 주요 요구사항은 다음과 같다.

파일 형식: SVG (Scalable Vector Graphics)
프로파일: SVG Tiny 1.2
`baseProfile` 속성이 `tiny`로 설정되어야 한다.
외부 링크나 스크립트를 포함해서는 안 된다.
정사각형 비율을 권장한다.

VMC (Verified Mark Certificate)
VMC(Verified Mark Certificate, 검증된 마크 인증서)는 로고의 소유권이 해당 도메인에 있음을 증명하는 디지털 인증서이다. VMC는 공인된 인증 기관(Certificate Authority, CA)을 통해서만 발급받을 수 있으며, 발급 과정에서 해당 기관이 로고에 대한 상표권을 보유하고 있는지 확인하는 절차를 거친다.
대부분의 주요 이메일 제공업체는 VMC를 BIMI의 필수 요건으로 지정하고 있다. 이는 로고의 무단 도용을 방지하고 BIMI 생태계의 신뢰도를 높이기 위함이다.

도입의 이점
브랜드 가시성 및 신뢰도 향상: 수신함에서 로고가 직접 노출되므로 브랜드 인지도가 높아지고, 수신자는 해당 이메일이 공식 출처에서 온 것임을 쉽게 신뢰할 수 있다.
이메일 보안 강화: BIMI의 전제 조건인 DMARC의 `quarantine` 또는 `reject` 정책은 도메인 스푸핑 및 피싱 공격을 효과적으로 차단한다.
마케팅 효과 증대: 시각적으로 눈에 띄는 로고는 이메일 개봉률(Open Rate)과 사용자 참여도를 높이는 데 긍정적인 영향을 줄 수 있다.
보안 표준 채택 장려: BIMI라는 시각적 이점을 제공함으로써 더 많은 기업이 DMARC와 같은 강력한 이메일 인증 표준을 도입하도록 유도한다.

구현 단계
DMARC 정책 설정: SPF와 DKIM을 먼저 설정한 후, DMARC TXT 레코드를 DNS에 게시한다. 초기에는 `p=none`으로 시작하여 리포트를 분석한 뒤, 점진적으로 `p=quarantine` 또는 `p=reject`로 정책을 강화한다.
로고 준비: 브랜드 로고를 SVG Tiny 1.2 형식의 파일로 제작한다.
VMC 발급: 공인된 인증 기관(CA)에 상표권 증빙 자료를 제출하고 VMC를 발급받는다.
DNS 레코드 게시: 로고 파일과 VMC 파일을 HTTPS 서버에 업로드한 후, 위에서 설명한 형식에 맞춰 BIMI TXT 레코드를 DNS에 게시한다.
검증: 레코드 게시 후, 이메일 제공업체가 DNS 레코드를 확인하고 모든 요구사항이 충족되면 로고를 표시하기 시작한다.

지원하는 이메일 클라이언트
2025년 기준으로 BIMI를 지원하는 주요 이메일 서비스 제공업체는 다음과 같다.

Google Workspace (Gmail)
Yahoo Mail
Apple Mail
Fastmail
La Poste
Zone
Comcast
Proofpoint

같이 보기
SPF (Sender Policy Framework)
DKIM (DomainKeys Identified Mail)
DMARC (Domain-based Message Authentication, Reporting, and Conformance)
DNS (Domain Name System)
피싱

외부 링크
BIMI - 공식 웹사이트
