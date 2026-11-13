# F-0 정답 라벨 표본 40개 (세션 판독, 사람 검수 아님)

- 질의와 구절은 위키백과 문서에서 옮긴 문장이다(CC BY-SA 4.0). 문서별 URL과 `revision_id`는 `wiki_article_sources_manifest_v1.json`에 있다.
- 표본: `wiki_article_chunk_gold_seed_v1.jsonl` 400행(전부 positive)에서 언어별 20개, `random.Random(20261113)`으로 뽑았다.
- 판정은 세션(Claude)이 읽고 적은 것이다. **사람 검수가 아니다.** 사용자가 훑어보고 다르게 보는 줄을 고쳐 주면 그 결과를 사람 검수로 적는다.
- 기준: O = 정답 구절이 질의의 답이다. △ = 관련은 있지만 답의 일부이거나 더 맞는 구절이 따로 있다. X = 정답 구절이 질의의 답이 아니다(실제 답은 대개 질의 문장이 있는 다른 곳).
- 질의 모양: 틀 문장 = "What are the key concepts and features of X?" / "X의 핵심 개념과 주요 특징을 설명해줘". 문장 복사(n번째) = 문서 본문의 n번째 문장을 120자까지 자른 것. 정답 구절은 질의와 관계없이 항상 문서에서 길이 조건(35~220자)을 통과한 첫 문장이다(`generate_evalset_seed.py`의 `snippets[0]`).
- 위치: 본문(메타데이터 머리말 뒤)에서 정답 구절과 질의 문장이 시작하는 글자 위치. -1은 질의가 본문 문장이 아니라는 뜻이다. 청크는 최대 500자다.

| # | 언어 | 질의 모양 | 문서 | 질의 | 정답으로 표시된 구절 | 판정 | 이유 | 위치(정답/질의) |
|---|---|---|---|---|---|---|---|---|
| 1 | en | 틀 문장 | Service recovery paradox | What are the key concepts and features of Service recovery paradox? | The main reason behind this thinking is that successful recovery of a faulty service increases the assurance and confidence from the customer. | △ | 정의 문장이 아니라 셋째 문장("이렇게 보는 주된 이유…")이다. 관련은 있지만 개념 설명으로는 약하다. | 251/-1 |
| 2 | en | 문장 복사(3번째) | Government | Government is a means by which organizational policies are enforced, as well as a mechanism for determining policy. | A government is the system or group of people governing an organized community, generally a state. | △ | 둘 다 정부의 정의지만 질의 문장(정책을 집행하는 수단)의 내용은 정답 구절에 없다. | 0/219 |
| 3 | en | 문장 복사(3번째) | Information technology | Information technology is an application of computer science and computer engineering. | Information technology (IT) is the study or use of computers, telecommunication systems and other devices to create, process, store, retrieve and transmit information. | △ | 둘 다 IT 정의. 질의 내용(컴퓨터 과학의 응용)은 정답 구절에 없다. | 0/344 |
| 4 | en | 틀 문장 | Computer science in sport | What are the key concepts and features of Computer science in sport? | Computer science plays a very important role in modern sports. | △ | "스포츠에서 중요한 역할을 한다"뿐이라 개념·특징의 답으로 약하다. | 0/-1 |
| 5 | en | 틀 문장 | Health information technology | What are the key concepts and features of Health information technology? | Health information technology (HIT) is health technology, particularly information technology, applied to health and health care. | O | 정의 문장. | 0/-1 |
| 6 | en | 문장 복사(3번째) | Learnable function | This enables the DBMS to learn, adapt, and govern based on the data it manages. | A learnable function is a mathematical function that can be learned from data, typically through a machine learning algorithm, to minimize errors and perform a specific task. | X | 질의는 DBMS가 데이터로 학습한다는 내용, 정답은 learnable function의 정의. | 0/657 |
| 7 | en | 틀 문장 | Virtual assistant | What are the key concepts and features of Virtual assistant? | A virtual assistant (VA) is a software agent that can perform a range of tasks or services for a user based on user input, such as commands or questions, including verbal ones. | O | 정의 문장. | 0/-1 |
| 8 | en | 문장 복사(1번째) | IT service management | Information technology service management (ITSM) are the activities performed by an organization to design, build, deliv | Information technology service management (ITSM) are the activities performed by an organization to design, build, deliver, operate and control IT services offered to customers. | O | 질의가 정답 문장 그대로(앞 120자). | 0/0 |
| 9 | en | 문장 복사(3번째) | Call centre | It is expected that artificial intelligence-based chatbots will significantly impact call centre jobs and will increase  | An inbound call centre is operated by a company to administer incoming product or service support or information inquiries from consumers. | X | 질의는 AI 챗봇이 콜센터 일자리에 줄 영향, 정답은 인바운드 콜센터 정의. | 242/1285 |
| 10 | en | 틀 문장 | Programmer | What are the key concepts and features of Programmer? | A programmer, computer programmer or coder is an author of computer source code – someone with skill in computer programming. | O | 정의 문장. | 0/-1 |
| 11 | en | 틀 문장 | Investment | What are the key concepts and features of Investment? | Investment is traditionally defined as the "commitment of resources into something expected to gain value over time". | O | 정의 문장. | 0/-1 |
| 12 | en | 틀 문장 | Class struggle | What are the key concepts and features of Class struggle? | Commonly cited historical examples of class antagonists are slavemasters and slaves, feudal lords and serfs, landowners and tenants, and capitalists and workers. | △ | 계급 대립의 역사적 예시. 개념 설명의 일부다. | 293/-1 |
| 13 | en | 틀 문장 | Operational continuity | What are the key concepts and features of Operational continuity? | Operational continuity refers to the ability of a system to continue working despite damages, losses, or critical events. | O | 정의 문장. | 0/-1 |
| 14 | en | 틀 문장 | Comparative politics | What are the key concepts and features of Comparative politics? | Comparative politics is a field in political science characterized either by the use of the comparative method or other empirical methods to explore politics both within and between countries. | O | 정의 문장. | 0/-1 |
| 15 | en | 문장 복사(3번째) | Metal casting simulation | By simulating the casting process, manufacturers can optimize mold design, reduce material consumption, and improve the  | Casting process simulation is a computational technique used in industry and metallurgy to model and analyze the metal-casting process. | X | 질의는 시뮬레이션의 이점(금형 최적화 등), 정답은 시뮬레이션의 정의. | 0/334 |
| 16 | en | 문장 복사(1번째) | Virtual assistant | A virtual assistant (VA) is a software agent that can perform a range of tasks or services for a user based on user inpu | A virtual assistant (VA) is a software agent that can perform a range of tasks or services for a user based on user input, such as commands or questions, including verbal ones. | O | 질의가 정답 문장 그대로. | 0/0 |
| 17 | en | 문장 복사(1번째) | Media center application | A media center application, or simply media center, is a type of multimedia and technological convergence software that  | A media center application, or simply media center, is a type of multimedia and technological convergence software that is designed to be used on a large screen like a television or a projector. | O | 질의가 정답 문장 그대로. | 0/0 |
| 18 | en | 틀 문장 | Customer experience | What are the key concepts and features of Customer experience? | Different dimensions of customer experience include senses, emotions, feelings, perceptions, cognitive evaluations, involvement, memories, as well as spiritual components, and behavioral intentions. | O | 고객 경험의 구성 차원 나열. "특징" 질문의 답으로 맞다. | 225/-1 |
| 19 | en | 틀 문장 | Computer program | What are the key concepts and features of Computer program? | A computer program is a sequence or set of instructions in a programming language for a computer to execute. | O | 정의 문장. | 0/-1 |
| 20 | en | 틀 문장 | Software-defined storage | What are the key concepts and features of Software-defined storage? | Software-defined storage (SDS) is a marketing term for computer data storage software for policy-based provisioning and management of data storage independent of the underlying hardware. | O | 정의 문장. | 0/-1 |
| 21 | ko | 문장 복사(1번째) | 정보 디자인 | 정보 디자인(情報 design)은 정보를 구성하여 효율적으로 사용할 수 있게 하는 디자인 기술 및 업무를 말한다. | 정보 디자인(情報 design)은 정보를 구성하여 효율적으로 사용할 수 있게 하는 디자인 기술 및 업무를 말한다. | O | 질의가 정답 문장 그대로. | 0/0 |
| 22 | ko | 문장 복사(3번째) | 19대 미래성장동력 | 자동차와 운전자 그리고 주변환경과 교통인프라 등을 유기적으로 연결하여 다양한 서비스 제공 | 19대 미래성장동력은 대한민국 미래창조과학부가 선정한 19가지 산업이다. | X | 질의는 스마트 자동차 항목의 설명, 정답은 19대 미래성장동력 전체의 정의. | 0/224 |
| 23 | ko | 문장 복사(3번째) | 허가 | 다만, 허가는 제한을 해제하여 적법한 권리행사를 가능하게 하여주는 행위이므로 형성적 행위의 성질을 가지며, 이러한 점에서 허가와 특허의 구분은 상대화되어 가고 있다고 보는 견해가 있다. | 허가(許可 )는 행정청이 법령에 의한 일반적·상대적 금지(부작위의무)를 특정한 경우에 해제하여 적법하게 일정한 사실행위 또는 법률행위를 할 수 있도록 자유를 회복시켜 주는 행정행위를 말한다. | X | 질의는 허가의 성질에 대한 학설, 정답은 허가의 정의. | 0/174 |
| 24 | ko | 문장 복사(1번째) | 명령어 (컴퓨팅) | 명령어(命令語, instruction or instructions)는 특정 작업을 수행하기 위한 컴퓨터 프로그램의 구체적이고 명확한 지침이다. | 명령어(命令語, instruction or instructions)는 특정 작업을 수행하기 위한 컴퓨터 프로그램의 구체적이고 명확한 지침이다. | O | 질의가 정답 문장 그대로. | 0/0 |
| 25 | ko | 문장 복사(3번째) | 프레임버퍼 | 인메모리 비트맵을 컴퓨터 모니터에 출력 가능한 비디오 신호로 변환한다. | 프레임버퍼(framebuffer) 또는 프레임스토어(framestore)는 비디오 디스플레이를 구동하는 비트맵이 담겨있는 랜덤 액세스 메모리(RAM)의 한 부분이다. | △ | 둘 다 프레임버퍼 관련이지만 질의(비트맵을 비디오 신호로 변환)는 정답 구절에 없다. | 0/173 |
| 26 | ko | 문장 복사(3번째) | 미리 보기 | 위지윅 환경이 아닌 곳에서는 미리 보기 기능이 매우 중요한데, 문법 오류 등의 수정 등을 빠르게 할 수 있기 때문이다. | 미리 보기(Preview)는 최종 형태로 생산되기 전 문서를 표시하기 위한 컴퓨팅 기능이다. | X | 질의는 위지윅이 아닌 환경에서 미리 보기가 중요한 이유, 정답은 미리 보기 정의. | 0/183 |
| 27 | ko | 문장 복사(3번째) | 육군비전 2050 | 위 3가지 개념 육군 중 마지막인 30년 후 개념군에 속하는 개념서로 미래의 과학기술 혁명 및 미래의 국제 질서 및 사회·자연환경의 변화와 미래 전쟁의 양상 등 미래 모습의 전 분야를 전망하였을 때 기대되는 미래 육 | 육군비전 2050(영어: Army vision 2050)은 20~30년 후 미래의 개념 육군의 모습으로, 장래의 실현 가능성보다는 육군 구성원들의 희망과 낙관적 상상력에 바탕을 둔 담론적·탐색적 수준의 개념서이다. | △ | 둘 다 개념서의 성격을 말한다. 질의의 세부(30년 후 개념군)는 정답에 없다. | 0/228 |
| 28 | ko | 문장 복사(3번째) | 디지털플랫폼정부 | 2022년 1월 2일 윤석열 후보는 기자회견에서 새해 첫 공약으로 '디지털플랫폼정부' 공약을 발표했다. | 디지털플랫폼정부는 최신 디지털 기술을 활용하여 다양한 데이터를 통합하고 연계하고 분석하는 디지털 플랫폼을 기반으로 국민과 기업과 정부가 함께 사회 문제를 해결하고 새로운 가치를 창출하는 정부를 구현하기 위한 윤석열 정부의 정책이다. | X | 질의는 공약 발표 일자, 정답은 정책 정의. | 0/233 |
| 29 | ko | 문장 복사(1번째) | 경항모불가론 | 경항모불가론(輕航母四不可)은 2019년 한국이 항공모함 보유를 발표함과 동시에 한국의 안보 환경에는 경항공모함은 미흡하다는 담론이다. | 경항모불가론(輕航母四不可)은 2019년 한국이 항공모함 보유를 발표함과 동시에 한국의 안보 환경에는 경항공모함은 미흡하다는 담론이다. | O | 질의가 정답 문장 그대로. | 0/0 |
| 30 | ko | 문장 복사(1번째) | 사회 서비스 | 사회 서비스(social service) 또는 사회 복지 사업은 일반적으로 소외 계층을 포함하는 특정 집단에 지원과 도움을 제공하기 위한 다양한 공공 서비스이다. | 사회 서비스(social service) 또는 사회 복지 사업은 일반적으로 소외 계층을 포함하는 특정 집단에 지원과 도움을 제공하기 위한 다양한 공공 서비스이다. | O | 질의가 정답 문장 그대로. | 0/0 |
| 31 | ko | 문장 복사(3번째) | 해외직구 | 또한 해외직구를 자주 이용하는 소비자들을 해외직구족이라고도 부른다. | 해외직구(海外直購)란 인터넷 쇼핑몰을 통해 '해외에서 직접 구매'하는 소비행위를 의미하는 신조어이다. | X | 질의는 "해외직구족"이라는 말, 정답은 해외직구 정의. | 0/157 |
| 32 | ko | 틀 문장 | 콘솔 애플리케이션 | 콘솔 애플리케이션의 핵심 개념과 주요 특징을 설명해줘 | 콘솔 애플리케이션(console application) 또는 명령줄 프로그램은 텍스트 터미널, 일부 운영체제(유닉스, 도스 등)의 명령줄 인터페이스와 같은 텍스트 전용 사용자 인터페이스를 통해 사용하도록 설계된 컴퓨터 프로그램(응용 프로그램 또는 유틸리티)이다. | O | 정의 문장. | 0/-1 |
| 33 | ko | 틀 문장 | 상태 표시줄 | 상태 표시줄의 핵심 개념과 주요 특징을 설명해줘 | 상태 표시줄(status bar)은 일반적으로 창의 하단에 위치하며 정보 영역을 제공하는 그래픽 제어 요소이다. | O | 정의 문장. | 0/-1 |
| 34 | ko | 문장 복사(1번째) | 노동 인구 | 거시경제학에서 노동 인구(勞動人口, workforce) 또는 노동력은 일하는 사람(즉, 고용된 사람)과 일자리를 찾는 사람(즉, 실업자)의 합을 의미한다. | 거시경제학에서 노동 인구(勞動人口, workforce) 또는 노동력은 일하는 사람(즉, 고용된 사람)과 일자리를 찾는 사람(즉, 실업자)의 합을 의미한다. | O | 질의가 정답 문장 그대로. | 0/0 |
| 35 | ko | 틀 문장 | 정보통신기술 | 정보통신기술의 핵심 개념과 주요 특징을 설명해줘 | 시·공간의 장벽을 무너뜨리고, 언제 어디서나 통신을 이용해 소통을 가능하게 하는 정보통신기술의 특징은 다음과 같은 공통점을 가지고 있다. | △ | "특징은 다음과 같은 공통점을 가진다"는 도입 문장. 특징 목록 자체는 다른 곳에 있다. | 232/-1 |
| 36 | ko | 틀 문장 | 투자신탁 | 투자신탁의 핵심 개념과 주요 특징을 설명해줘 | 투자신탁(投資信託)은 여러 투자자의 자금을 모아 펀드를 만들어 투자를 행하는 소위 집합투자조직(collective investment scheme)이다. | O | 정의 문장. | 0/-1 |
| 37 | ko | 문장 복사(3번째) | 정보 혁명 | 이러한 의미에서 단지 기술혁신·경영혁신의 범위를 훨씬 넘는 것이며 역사적 산업혁명의 의의를 지닌다고 할 수 있다. | 정보 혁명(情報革命, Information revolution)은 전자계산기에 의한 정보의 처리를 중심으로 하고, 나아가서 자동제어·통신기술 등의 광범위한 기술혁신 및 오퍼레이션 리서치·인간공학(人間工學)·경영공학 등에 의해서 이루어지는 경영혁신을 말한다. | X | 질의는 정보 혁명의 역사적 의의, 정답은 정의. | 0/256 |
| 38 | ko | 문장 복사(1번째) | 헬프 데스크 | 헬프 데스크(Help desk)는 일반적으로 전자 또는 컴퓨터 문제에 대한 지원과 정보를 제공하는 부서 또는 사람이다. | 헬프 데스크(Help desk)는 일반적으로 전자 또는 컴퓨터 문제에 대한 지원과 정보를 제공하는 부서 또는 사람이다. | O | 질의가 정답 문장 그대로. | 0/0 |
| 39 | ko | 틀 문장 | 한국정보산업연합회 | 한국정보산업연합회의 핵심 개념과 주요 특징을 설명해줘 | 한국정보산업연합회(The Federation of Korean Information Industries, FKII)는 정보 및 통신 기술을 통한 산업의 지식정보화, 기업경영의 디지털화, 산업간 융합화를 촉진하기 위하여 설립된 민간단체이다. | O | 정의 문장. | 0/-1 |
| 40 | ko | 문장 복사(3번째) | 실적주의 | 실적을 중시하는 관리임용 제도가 최초로 발생한 곳은 고대 중국 진나라, 한나라 왕조이다. | 실적주의 또는 실적제, 실적체제, 실적주의 체제(實績主義, 實績制, 實績體制, 實績主義體制, 영어: merit system)는 공무원을 능력, 성적, 자격 등의 실적에 기초하여 임용하는 제도이다. | X | 질의는 실적주의의 기원(진·한), 정답은 정의. | 0/170 |

## 집계

| 질의 모양 | O | △ | X | 계 |
|---|---|---|---|---|
| 틀 문장 | 13 | 4 | 0 | 17 |
| 문장 복사(1번째) | 9 | 0 | 0 | 9 |
| 문장 복사(3번째) | 0 | 4 | 10 | 14 |
| 전체 | 22 | 8 | 10 | 40 |

언어별: en O 12 / △ 5 / X 3, ko O 10 / △ 3 / X 7
