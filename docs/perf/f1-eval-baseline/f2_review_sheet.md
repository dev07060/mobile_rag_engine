# F-2 1단계 질의 40개 검수표

- 위키 문서의 정답 구절은 위키백과 문장이다(CC BY-SA 4.0). 문서별 URL과 `revision_id`는 `example/assets/evalsets/f1/f1_sources_manifest_v1.json`에 있다.
- 작성: 세션 초안(`author: session_draft`). **아직 사람 검수 전이다.** 검수한 줄은 `session_draft+human_review`로 바꾼다.
- 질의는 정답 구절을 보면서 썼다. 낱말이 새어 들어가지 않았는지는 아래 겹침 값으로만 확인했다.
- 겹침 = 질의의 BM25 토큰 중 정답 구절(문서)에도 있는 비율. 엔진의 `tokenize_for_bm25`로 셌다(`rust_builder/rust/src/api/eval_dump.rs`). 유형은 정답 구절 겹침으로 정했다: 0이면 안 겹침, 0.5 미만이면 일부, 0.5 이상이면 많이.
- 문서: 짧은 문서 16개는 세션이 쓴 것이고(`example/assets/corpus/f1_short/`), 위키 문서는 80개 묶음의 것이다(CC BY-SA).
- 봐 주실 것: (1) 질문이 자연스러운가(특히 한국어), (2) 정답 구절이 그 질문의 답인가, (3) 답 없는 질문이 정말 문서에 답이 없는가.

| id | 언어 | 유형 | 문서 | 질의 | 정답 구절 | 겹침 (구절 / 문서) | 겹친 토큰 | 검수 |
|---|---|---|---|---|---|---|---|---|
| f1q-001 | en | 안 겹침 | Pulse Tracker FAQ: Battery and Sync | My phone is dead every morning. How can I stop that? | If you do not need sleep data, turn off Sleep Tracking under Settings > Tracking and the overnight drain drops to under 3 percent. | 0.00 / 0.50 | 없음 | |
| f1q-002 | en | 안 겹침 | Memo: Design Team Offsite | Who needs to know about my peanut intolerance before the retreat, and what's the deadline? | Tell Mina by March 27 if you have a food allergy or follow a vegetarian diet. | 0.00 / 0.36 | 없음 | |
| f1q-003 | en | 많이 겹침(대조군) | AeroPure 300 Air Purifier: Filter Care | Can the HEPA filter be washed? | The HEPA filter cannot be washed. | 0.83 / 0.83 | be, filter, hepa, the, wash | |
| f1q-004 | en | 일부 겹침 | Northwind Goods Return and Refund Policy | How long until I get my money back after sending the parcel? | Once the warehouse receives your parcel, the refund is issued to the original payment method within five business days. | 0.18 / 0.18 | parcel, the | |
| f1q-005 | en | 안 겹침 | IT Helpdesk: VPN Connection Problems | On hotel Wi-Fi my VPN says connected yet intranet pages stay blank. What should I change? | Disconnect, open the client settings, and switch the protocol from Automatic to TCP. | 0.00 / 0.38 | 없음 | |
| f1q-006 | en | 많이 겹침(대조군) | Note to self: sourdough starter | What do pink or orange streaks in the starter mean? | Pink or orange streaks mean it has spoiled and must be thrown away. | 0.50 / 0.80 | mean, or, orang, pink, streak | |
| f1q-007 | en | 일부 겹침 | Move-out checklist (apartment 4B) | When will I get my deposit back after moving out? | The security deposit is returned within 21 days, minus any deductions, to the bank account on the lease. | 0.11 / 0.33 | deposit | |
| f1q-008 | en | 안 겹침 | Ledgerly 2.3 Release Notes | Moving cash from savings to checking used to show up twice in my sums. Is that fixed? | Totals no longer double-count transfers between two of your own accounts. | 0.00 / 0.25 | 없음 | |
| f1q-009 | ko | 일부 겹침 | 본사 주차 등록 FAQ | 정규직 주차 요금은 월 얼마를 급여에서 공제해? | 정규직은 월 3만 원을 급여에서 공제하고, 계약직과 인턴은 무료입니다. | 0.44 / 0.56 | 공제, 규직, 급여, 급여에서, 에서, 여에, 월, 정규 | |
| f1q-010 | ko | 안 겹침 | 재택근무 운영 지침 (2026년 하반기) | 홈오피스 책상 장비 살 때 회사가 돈을 보태 줘? | 집에서 쓰는 모니터나 의자 구입비는 연 20만 원까지 복지 포인트로 지원합니다. | 0.00 / 0.07 | 없음 | |
| f1q-011 | ko | 안 겹침 | 클린웨이브 식기세척기 사용 설명서 | 그릇 씻는 기계 거름망은 얼마나 자주 손질해? | 바닥의 원통형 필터는 일주일에 한 번 시계 반대 방향으로 돌려 빼낸 뒤 흐르는 물에 헹궈 주세요. | 0.00 / 0.00 | 없음 | |
| f1q-012 | ko | 많이 겹침(대조군) | 국내 출장비 정산 규정 | 출장 식비 영수증은 제출해야 해? | 식비는 하루 3만 원을 정액으로 지급하며 영수증은 제출하지 않는다. | 0.55 / 0.64 | 수증, 식비, 영수, 영수증은, 제출, 증은 | |
| f1q-013 | ko | 안 겹침 | 사내 프린터 문제 해결 | 복합기 안에 A4가 끼어서 안 나와. 어떻게 꺼내? | 앞쪽 덮개를 열고 초록색 손잡이를 아래로 내린 뒤, 종이를 양손으로 천천히 당겨 빼세요. | 0.00 / 0.14 | 없음 | |
| f1q-014 | ko | 일부 겹침 | 관리사무소 공지 | 103동 승강기 점검은 언제야? | 103동 승강기는 11월 24일(월) 오후 1시부터 두 시간 동안 멈춥니다. | 0.30 / 0.50 | 103동, 강기, 승강 | |
| f1q-015 | ko | 많이 겹침(대조군) | 햇살소아청소년과 진료 안내 | 예방접종은 무슨 요일 오후에 해? | 예방접종은 수요일과 금요일 오후에만 합니다. | 0.73 / 0.73 | 방접, 예방, 예방접종은, 오후, 요일, 접종, 종은, 후에 | |
| f1q-016 | ko | 일부 겹침 | 노트잇 백업과 복원 | 비밀번호 걸어 둔 메모를 새 폰으로 옮길 수 있어? | 암호를 건 메모는 암호를 기억해야만 복원됩니다. | 0.06 / 0.31 | 메모 | |
| f1q-017 | en | 안 겹침 | Electronic assessment | Year British exam board began on-screen grading? | Early adopters include the University of Cambridge Local Examinations Syndicate, (which operates under the brand name Cambridge Assessment) which conducted its first major test of e-marking in November 2000. | 0.00 / 0.62 | 없음 | |
| f1q-018 | en | 많이 겹침(대조군) | Perpetual war | Which historian said calling the war on terror a crusade made it part of an endless conflict? | Andrew Bacevich described Bush's naming of the war on terror as a crusade as something which does not make the war separate, rather something that shows that it is part of an "eternal war." | 0.62 / 0.94 | an, crusad, it, of, on, part, terror, the, war, which | |
| f1q-019 | en | 안 겹침 | Emerging market | Which Spanish bank's analysts coined a label for big, quickly expanding developing economies? | In November 2010, BBVA Research introduced a new economic concept, to identify key (i.e. large and fast growing) emerging markets. | 0.00 / 0.67 | 없음 | |
| f1q-020 | en | 많이 겹침(대조군) | Collegial body | Which collegial body is explicitly provided for in the French Constitution? | France: The Council of Ministers is the only collegial body explicitly provided for in the Constitution. | 0.82 / 0.91 | bodi, collegi, constitut, explicit, for, in, is, provid, the | |
| f1q-021 | en | 일부 겹침 | Virtual assistant | What was the name of the chatbot an airline used on its website before modern assistants? | Previous generations of virtual assistants often worked on websites, such as Alaska Airlines' Ask Jenn, or on interactive voice response (IVR) systems such as American Airlines' IVR by Nuance. | 0.33 / 1.00 | airlin, assist, of, on, websit | |
| f1q-022 | en | 일부 겹침 | User profile | What two items appear on every member's page across sites like Facebook? | Universally, all social networking platforms display an individual's profile picture and an "about me" page that allows for self-expression. | 0.08 / 0.58 | page | |
| f1q-023 | en | 안 겹침 | Bond credit rating | What's the slang name for risky debt below the safe tier? | Bonds that are not rated as investment-grade bonds are known as high yield bonds or more derisively as junk bonds. | 0.00 / 0.50 | 없음 | |
| f1q-024 | en | 일부 겹침 | Citizenship | Which agreement created EU citizenship? | The Maastricht Treaty introduced the concept of citizenship of the European Union. | 0.20 / 1.00 | citizenship | |
| f1q-025 | ko | 안 겹침 | 프레임버퍼 | 액정 화면은 왜 규격 밖 영상 입력을 보여 주지 못해? | LCD는 디스플레이 신호를 디지털 방식으로 샘플링해야 하므로(전자빔을 에뮬레이션함), 범위를 벗어난 신호는 모니터에 물리적으로 표시될 수 없다. | 0.00 / 0.29 | 없음 | |
| f1q-026 | ko | 일부 겹침 | 어음 | 만기 전에 받을 돈을 은행에 넘기고 미리 현금으로 바꾸는 걸 뭐라고 해? | 어음의 만기일 이전에 은행 또는 기타 금융사에 이를 양도하고 일정한 이자 및 수수료를 차감한 잔액을 현금으로 받는 어음의 현금화 방법을 어음의 할인이라고 한다. | 0.35 / 0.39 | 금으, 라고, 만기, 으로, 은행, 전에, 현금, 현금으로 | |
| f1q-027 | ko | 안 겹침 | 디지털 암흑기 | 옛 전쟁 때 바닷속 함정이 주고받은 비밀 전문을 수많은 PC를 엮어 풀었다는 얘기가 있어? | 예를 들어, 제2차 세계 대전 당시 잠수함의 전술 메시지 중 하나에 사용된 기계식 암호를 해독하는 데에는 분산 컴퓨팅 프로젝트의 계산 능력이 필요했다. | 0.00 / 0.20 | 없음 | |
| f1q-028 | ko | 많이 겹침(대조군) | 증명 보조기 | 정리 증명기 박물관은 무엇을 보존하기 위한 이니셔티브야? | 정리 증명기 박물관은 중요한 문화/과학적 인공물인 정리 증명 시스템의 향후 분석을 위해 소스를 보존하기 위한 이니셔티브이다. | 0.77 / 0.77 | 관은, 니셔, 명기, 물관, 박물, 박물관은, 보존, 보존하기, 셔티, 위한, 이니, 정리, 존하, 증명, 증명기, 티브, 하기 | |
| f1q-029 | ko | 안 겹침 | 컴퓨터 프로그램 | 함수형 언어는 왜 여러 일을 한꺼번에 돌리는 코드에 즐겨 쓰여? | 또한, 부작용이 없기 때문에 병렬 컴퓨팅 및 동시 프로그래밍에서 인기를 얻었다. | 0.00 / 0.67 | 없음 | |
| f1q-030 | ko | 안 겹침 | 뇌-컴퓨터 인터페이스 | 머리에 쓰기만 하는 뇌파 장치는 칼을 대는 방식에 비해 뭐가 떨어져? | 비침습적인 EEG는 수술이 불필요하며 착용이 굉장히 간편함에도 불구하고, 침습적 BCI보다 공간 해상도가 낮으며 두개골이 고주파를 흡수하기 때문에 신호가 퍼지고 뭉개진다는 단점이 있다. | 0.00 / 0.57 | 없음 | |
| f1q-031 | ko | 많이 겹침(대조군) | 정보 디자인 | 정보 아키텍처는 어떤 것을 포함하는 개념이야? | 정보 아키텍처 (information architecture)는 정보 시스템, 데이터베이스, 자료 구조의 디자인과 데이터 모델링, 프로세스 분석을 포함하는 개념이다. | 0.62 / 0.69 | 개념, 념이, 아키, 정보, 키텍, 텍처, 포함, 포함하는, 하는, 함하 | |
| f1q-032 | ko | 일부 겹침 | 비즈니스 애널리틱스 | 한국HP가 고객사에 붙여 주겠다고 한 사람은 누구야? | 한국HP는 이번 서비스로 도출된 데이터를 분석할 수 있는 전문 분석가를 제공하고, 고객사와 협의해 특정 활동, 시스템, 시간대별 서비스를 지원할 예정이다. | 0.17 / 0.39 | 객사, 고객, 한국 | |
| f1q-033 | en | 답 없음 | – | What is the warranty period for the AeroPure 300? | (답 없음) | – | – | |
| f1q-034 | en | 답 없음 | – | Can I bring my dog to the design team offsite? | (답 없음) | – | – | |
| f1q-035 | en | 답 없음 | – | How much does Ledgerly Premium cost per month? | (답 없음) | – | – | |
| f1q-036 | en | 답 없음 | – | Does the Pulse Tracker watch work underwater while swimming? | (답 없음) | – | – | |
| f1q-037 | ko | 답 없음 | – | 재택근무하는 날 점심 식대도 지원돼? | (답 없음) | – | – | |
| f1q-038 | ko | 답 없음 | – | 햇살소아청소년과에 주차할 곳이 있어? | (답 없음) | – | – | |
| f1q-039 | ko | 답 없음 | – | 노트잇을 컴퓨터에서도 쓸 수 있어? | (답 없음) | – | – | |
| f1q-040 | ko | 답 없음 | – | 해외 출장 숙박비 한도는 얼마야? | (답 없음) | – | – | |
