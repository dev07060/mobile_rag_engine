# E1 질문 검수표

질문 120개는 세션이 쓴 초안이다. 2026-11-14 세션이 원문과 대조해 판정을 적었고(아래 검수 메모), 같은 날 사용자가 이 판정을 확정했다. 그래서 작성자는 120개 모두 `session_draft+human_review`다. 판정은 `OK` 106개, `고침` 14개(질문 13, 정답 구절 1), `빼기` 0개다. 고친 질문은 [`scripts/e1/e1_queries_v1_spec.py`](../../../scripts/e1/e1_queries_v1_spec.py)에 반영했고, 아래 표는 고친 뒤의 질문·구절과 다시 잰 결과다. 판정 칸에는 고치기 전 값을 남겼다.

열: 의도(쓴 의도) / 잰 등급(엔진 BM25 토큰 겹침) / 문서 종류 / 조정·확인 / KoEn 기본값(0.2)과 0.5/0.5의 결과(O 맞음, X 틀림, 검수 반영 뒤 실행). 답 없는 질문은 KoEn 기본값의 1위 문서를 적었다.

| id | 언어 | 의도 | 잰 등급 | 문서 | 절반 | KoEn 0.2 / 0.5 | 질문 | 정답 문서와 구절 | 판정 |
|---|---|---|---|---|---|---|---|---|---|
| e1q-001 | en | lexical | high | gnome | check | O / O | How do I restore a file from the Trash? | `gnome_en_files_recover`: If your deleted file is there, click on it and select Restore From Trash. | OK |
| e1q-002 | en | lexical | partial | gnome | tune | O / O | How do I stop the screen from dimming itself? | `gnome_en_power_whydim`: Switch the Dim Screen switch to off in the Power Saving Options section. | OK |
| e1q-003 | en | lexical | high | gnome | check | O / O | How do I print on both sides of each sheet of paper? | `gnome_en_printing_2sided`: To print on both sides of each sheet of paper | OK |
| e1q-004 | en | lexical | high | gnome | check | O / O | How do I connect to a hidden wireless network? | `gnome_en_net_wireless_hidden`: Press the menu button in the top-right corner of the window and select Connect to Hidden Network | OK |
| e1q-005 | en | lexical | partial | gnome | check | O / O | How do I adjust the color temperature of the screen with Night Light? | `gnome_en_display_night_light`: Use the slider to adjust the Color Temperature to be more warm or less warm. | OK |
| e1q-006 | en | lexical | partial | gnome | tune | O / O | How close to the computer should the Bluetooth device be? | `gnome_en_bluetooth_connect_device`: place it within 5-10 meters (about 16-33 feet) of your computer | OK |
| e1q-007 | en | lexical | partial | gnome | check | O / O | What is the keyboard shortcut to lock the screen? | `gnome_en_keyboard_shortcuts_set`: Lock screen Super+L | OK |
| e1q-008 | en | paraphrase | partial | gnome | tune | X / X | How do I delete a file for good without it going to the trash first? | `gnome_en_files_delete`: Press and hold the Shift key, then press the Delete key on your keyboard. | 고침(질문). 전: I want to get rid of something right away without it going to the bin first. How? |
| e1q-009 | en | paraphrase | partial | gnome | check | X / X | Is there any way to bring back something I wiped for good? | `gnome_en_files_recover`: There are a number of recovery tools available that are sometimes able to recover files that were permanently deleted. | OK |
| e1q-010 | en | paraphrase | partial | gnome | check | O / O | Can my laptop go to sleep by itself with different timing when it is unplugged? | `gnome_en_power_autosuspend`: Different intervals can be specified for running on battery or plugged in. | OK |
| e1q-011 | en | paraphrase | partial | gnome | tune | X / O | Does the display use a lot of my laptop's battery? | `gnome_en_power_batterylife`: Powering the screen accounts for a significant fraction of a laptop power consumption. | 고침(질문). 전: What eats the most energy on a notebook? |
| e1q-012 | en | paraphrase | none | gnome | check | X / O | My Wi-Fi shows full bars, so why are downloads still slow? | `gnome_en_net_wireless_connect`: A stronger connection to a wireless network does not necessarily mean that you have a faster internet connection | OK |
| e1q-013 | en | paraphrase | partial | gnome | check | O / O | Does hiding my Wi-Fi network name make it more secure? | `gnome_en_net_wireless_hidden`: In practice, this is not the case; the network is slightly harder to find but it is still detectable. | 고침(질문). 전: Does making my router's name invisible keep strangers out? |
| e1q-014 | en | paraphrase | none | gnome | tune | O / O | A huge document keeps coming out and won't stop. What can I do as a last resort? | `gnome_en_printing_cancel_job`: remove the paper from the printer’s paper input tray | OK |
| e1q-015 | en | paraphrase | partial | gnome | check | O / O | Can I mute the browser but keep my music playing? | `gnome_en_sound_volume`: You can change the volume for one application and leave the volume for others unchanged. | OK |
| e1q-016 | en | paraphrase | none | gnome | tune | X / X | Which things in my home directory don't need copying to an external drive? | `gnome_en_backup_how`: Files that you can recreate easily. | OK |
| e1q-017 | en | paraphrase | partial | gnome | tune | O / O | How do I attach a document to a mail straight from the file browser? | `gnome_en_files_share`: Right-click the file and select Send to | OK |
| e1q-018 | en | paraphrase | partial | gnome | tune | O / O | How can I make my own key combo that opens a music app? | `gnome_en_keyboard_shortcuts_set`: if you wanted the shortcut to open Rhythmbox, you could name it Music and use the rhythmbox command | OK |
| e1q-019 | en | lexical | high | own | check | O / O | How many devices does a single Lumo Hub support? | `e1_own_en_01`: A single Lumo Hub supports up to 50 devices. | OK |
| e1q-020 | en | lexical | high | own | tune | O / O | Is Android 9 still supported? | `e1_own_en_02`: Android 9 is no longer supported. The minimum is now Android 10. | OK |
| e1q-021 | en | lexical | high | own | tune | O / O | Does the hub connect to 5 GHz networks? | `e1_own_en_03`: The hub only connects to 2.4 GHz networks. | OK |
| e1q-022 | en | lexical | high | own | tune | O / O | How much does Lumo Plus cost per month? | `e1_own_en_04`: Lumo Plus costs $3.99 per month or $39 per year | OK |
| e1q-023 | en | lexical | partial | own | tune | O / O | What is the daily allowance for meals? | `e1_own_en_07`: Meals are covered by a daily allowance of $60. | OK |
| e1q-024 | en | lexical | high | own | tune | O / O | When does the on-call rotation change? | `e1_own_en_08`: The on-call rotation changes every Monday at 10:00. | OK |
| e1q-025 | en | lexical | high | own | tune | O / O | How many weeks of paid parental leave do employees get? | `e1_own_en_11`: get 16 weeks of fully paid parental leave | OK |
| e1q-026 | en | lexical | high | own | check | O / O | Where do I install the Gatekeep VPN client from? | `e1_own_en_10`: Install the Gatekeep VPN client from the Self Service app. | OK |
| e1q-027 | en | paraphrase | none | own | check | O / O | Will my lamps still follow their timers if my broadband goes out? | `e1_own_en_01`: Switches, schedules and scenes run on the hub itself, so they keep working during an internet outage. | OK |
| e1q-028 | en | paraphrase | partial | own | tune | O / O | How do I factory reset the hub? | `e1_own_en_01`: Hold the button on the back of the hub for 10 seconds until the ring light turns amber. | 고침(질문). 전: How do I wipe the hub back to how it came out of the box? |
| e1q-029 | en | paraphrase | partial | own | check | O / O | Can my bedroom lights turn on gradually before my alarm goes off? | `e1_own_en_02`: Sunrise Wake: bedroom lights fade in over 15, 30 or 45 minutes before your alarm. | 고침(질문). 전: Can the lamps where I sleep slowly brighten before I have to get up? |
| e1q-030 | en | paraphrase | partial | own | check | O / O | The little light on my hub is glowing red without flashing. What went wrong? | `e1_own_en_03`: Solid red: the Wi-Fi password was wrong. | OK |
| e1q-031 | en | paraphrase | partial | own | tune | O / O | How long are recordings kept if I don't pay for anything? | `e1_own_en_04`: without Plus, clips are kept for 24 hours | OK |
| e1q-032 | en | paraphrase | partial | own | check | O / O | If I close my profile, how soon is everything erased? | `e1_own_en_05`: all data, including saved clips, is erased within 30 days | OK |
| e1q-033 | en | paraphrase | none | own | tune | O / O | How accurate are the electricity estimates for lamps? | `e1_own_en_06`: so bulb figures can be off by about 10 percent | OK |
| e1q-034 | en | paraphrase | partial | own | check | X / O | I came back from a trip seven weeks ago and haven't filed my costs. What now? | `e1_own_en_07`: Reports submitted later need written approval from your director. | OK |
| e1q-035 | en | paraphrase | none | own | tune | X / X | I got woken by an alert at 3 a.m. Do I get anything for that? | `e1_own_en_08`: If you were paged between midnight and 6:00, you may take the next morning off. | OK |
| e1q-036 | en | paraphrase | none | own | check | X / X | Why was the Atlas go-live pushed back? | `e1_own_en_09`: Two payment-provider fixes are not ready. | OK |
| e1q-037 | en | paraphrase | partial | own | tune | O / O | My work computer got stolen. How fast must I tell someone? | `e1_own_en_10`: Lost or stolen laptops must be reported to it-help within one hour. | OK |
| e1q-038 | en | paraphrase | none | own | tune | X / O | I typed my login into a fake page by mistake. What should I do? | `e1_own_en_12`: If you already entered your password, change it immediately and tell the security team within one hour. | OK |
| e1q-039 | en | lexical | high | pdf | check | O / O | From which annual reporting periods must an entity apply IFRS 17? | `e1_pdf_eng`: An entity shall apply IFRS 17 for annual reporting periods beginning on or after 1 January 2023. | OK |
| e1q-040 | en | lexical | high | pdf | tune | O / O | Can contracts issued more than one year apart be in the same group? | `e1_pdf_eng`: An entity shall not include contracts issued more than one year apart in the same group. | OK |
| e1q-041 | en | lexical | partial | pdf | check | O / O | What does the contractual service margin represent? | `e1_pdf_eng`: represents the unearned proﬁt the entity will recognise as it provides insurance contract services in the future | OK |
| e1q-042 | en | lexical | high | pdf | check | O / O | When is an insurance contract onerous at the date of initial recognition? | `e1_pdf_eng`: An insurance contract is onerous at the date of initial recognition if the fulfilment cash flows allocated to the contract | OK |
| e1q-043 | en | lexical | partial | pdf | tune | X / X | What is the definition of an insurance contract? | `e1_pdf_eng`: A contract under which one party (the issuer) accepts significant insurance risk from another party (the policyholder) | OK |
| e1q-044 | en | paraphrase | partial | pdf | check | X / X | When may an insurer use the simplified method for short policies? | `e1_pdf_eng`: the coverage period of each contract in the group (including insurance contract services arising from all premiums within the contract boundary determined at that date applying paragraph 34) is one year or less | OK |
| e1q-045 | en | paraphrase | partial | pdf | check | O / O | Do expected premiums from future renewals count in the current contract's liability? | `e1_pdf_eng`: An entity shall not recognise as a liability or as an asset any amounts relating to expected premiums or expected claims outside the boundary of the insurance contract. | 고침(질문). 전: Should money tied to future policies beyond the current agreement go on the balance sheet? |
| e1q-046 | en | no_answer | – | – | tune | 1위 `e1_own_en_03` | What is the warranty period for the Lumo Hub? | (답 없음) | OK |
| e1q-047 | en | no_answer | – | – | tune | 1위 `e1_own_en_04` | How do I change the language of the Lumo app? | (답 없음) | OK |
| e1q-048 | en | no_answer | – | – | check | 1위 `e1_own_en_01` | Can I control Lumo lights from a smartwatch? | (답 없음) | OK |
| e1q-049 | en | no_answer | – | – | check | 1위 `e1_own_en_09` | What is the dress code for client meetings? | (답 없음) | OK |
| e1q-050 | en | no_answer | – | – | tune | 1위 `e1_own_en_11` | How many sick days do employees get per year? | (답 없음) | OK |
| e1q-051 | en | no_answer | – | – | check | 1위 `e1_pdf_eng` | What is the company's 401(k) matching rate? | (답 없음) | OK |
| e1q-052 | en | no_answer | – | – | tune | 1위 `e1_own_en_02` | What time does the office close on Fridays? | (답 없음) | OK |
| e1q-053 | en | no_answer | – | – | check | 1위 `e1_own_en_10` | How do I turn on two-factor authentication for my work account? | (답 없음) | OK |
| e1q-054 | en | no_answer | – | – | check | 1위 `e1_pdf_eng` | Is there free parking at the office? | (답 없음) | OK |
| e1q-055 | en | no_answer | – | – | tune | 1위 `gnome_en_display_night_light` | How do I calibrate the colors of my monitor? | (답 없음) | OK |
| e1q-056 | en | no_answer | – | – | check | 1위 `e1_own_en_06` | How do I export my Lumo energy data to a spreadsheet? | (답 없음) | OK |
| e1q-057 | en | no_answer | – | – | tune | 1위 `e1_own_en_08` | When is the next company all-hands meeting? | (답 없음) | OK |
| e1q-058 | en | no_answer | – | – | tune | 1위 `e1_own_en_01` | How do I reset my Lumo account password? | (답 없음) | OK |
| e1q-059 | en | no_answer | – | – | check | 1위 `e1_own_en_09` | Will Atlas launch with a mobile app? | (답 없음) | OK |
| e1q-060 | en | no_answer | – | – | check | 1위 `gnome_en_printing_cancel_job` | How do I clear a paper jam in the printer? | (답 없음) | OK |
| e1q-061 | ko | lexical | partial | gnome | tune | O / O | 파일 이름을 바꾸려면 어떤 키를 누르나요? | `gnome_ko_files_rename`: 파일을 선택한 후 F2키를 누릅니다 | OK |
| e1q-062 | ko | lexical | partial | gnome | check | O / O | 파일 사용 내역 기간은 어떤 값 중에서 선택하나요? | `gnome_ko_privacy_history_recent_off`: 1일, 7일, 30일, 계속 중 하나를 선택합니다. | OK |
| e1q-063 | ko | lexical | partial | gnome | tune | O / O | 알림 목록은 어떤 키를 누르면 나타나나요? | `gnome_ko_shell_notifications`: 시계를 누르거나 Super+V 키를 누르면 나타납니다. | OK |
| e1q-064 | ko | lexical | high | gnome | tune | O / O | 하드 디스크 자체 상태 검사 도구 이름이 뭐예요? | `gnome_ko_disk_check`: 하드 디스크는 자체 상태 검사 도구 SMART(자체 감시, 분석, 보고 기술)가 있어 | 고침(질문). 전: 하드 디스크의 SMART 상태 검사 도구는 무엇인가요? |
| e1q-065 | ko | lexical | partial | gnome | check | O / O | 해상도를 바꾸면 되돌리기 전에 새 설정을 몇 초 동안 적용하나요? | `gnome_ko_look_resolution`: 되돌리기 전에 20초 동안 새 설정을 적용합니다. | OK |
| e1q-066 | ko | lexical | partial | gnome | check | O / O | 계정 형식이 표준이면 자동 로그인 설정을 바꿀 수 있나요? | `gnome_ko_user_autologin`: 이 설정을 바꿀 수 없습니다. 이 설정을 바꿔줄 수 있는 시스템 관리자에게 연락합니다. | OK |
| e1q-067 | ko | lexical | partial | gnome | check | O / O | 미디어 카드 읽기 장치는 어떤 카드를 읽나요? | `gnome_ko_hardware_cardreader`: SD, MMC, SM, MS, CF 등 기타 저장소 미디어 카드 읽기 장치가 붙어있습니다 | OK |
| e1q-068 | ko | paraphrase | partial | gnome | check | O / O | 파일명에 쓰면 안 되는 기호가 뭐야? | `gnome_ko_files_rename`: 파일 이름에는 /(슬래시) 문자를 제외하고 어떤 문자든 사용할 수 있습니다. | OK |
| e1q-069 | ko | paraphrase | partial | gnome | tune | O / O | 폴더 경로까지 합쳐서 너무 길면 저장이 안 될 수도 있어? | `gnome_ko_files_rename`: 255 글자 제한은 파일 이름과 파일 경로 모두(이를테면, /home/cheolsoo/Documents/work/business-proposals/… )에 해당하기에 가능하다면 긴 파일 이름 및 긴 폴더 이름을 피해야 합니다. | 고침(구절). 전: 어떤 파일 시스템에서는 파일 이름의 길이가 255 글자를 넘을 수 없습니다. |
| e1q-070 | ko | paraphrase | none | gnome | tune | X / O | 다른 사람 로그인 비번을 내가 대신 바꿀 수 있어? | `gnome_ko_user_changepassword`: 여러분의 계정이 아닌 사용자 계정을 편집하려면 관리자 권한이 필요합니다. | OK |
| e1q-071 | ko | paraphrase | none | gnome | tune | X / O | 가족이 같이 쓰는 PC에 동생 전용 공간을 따로 만들고 싶어 | `gnome_ko_user_add`: 컴퓨터에 여러 사용자 계정을 추가할 수 있습니다. | OK |
| e1q-072 | ko | paraphrase | none | gnome | tune | O / O | PC가 잠겨 있을 때 메시지 미리보기가 안 보이게 하려면? | `gnome_ko_shell_notifications`: 잠금 화면 알림 스위치를 끕니다. | OK |
| e1q-073 | ko | paraphrase | partial | gnome | tune | O / O | USB 마이크를 새로 샀는데 따로 설정해야 돼? | `gnome_ko_sound_usemic`: USB 마이크로폰은 별도의 오디오 장치로 동작하며, 어떤 마이크로폰을 기본으로 사용할 지 지정해야합니다. | 고침(질문). 전: USB로 꽂는 녹음 장비를 새로 샀는데 따로 해 줘야 할 게 있어? |
| e1q-074 | ko | paraphrase | partial | gnome | check | O / O | 디스크 프로그램 잘못 만지면 데이터 날아가? | `gnome_ko_disk_partitions`: 이 유틸리티로 디스크의 데이터를 완전히 지울 수 있습니다. | 고침(질문). 전: 저장 장치 관리 도구를 잘못 쓰면 자료가 날아갈 수도 있어? |
| e1q-075 | ko | paraphrase | none | gnome | tune | X / X | 와이파이로 붙는 복합기도 저절로 잡히나요? | `gnome_ko_printing_setup`: 프린터를 네트워크에 연결했다면 자동으로 설정하지 않습니다. | OK |
| e1q-076 | ko | paraphrase | none | gnome | tune | X / O | 바탕화면을 내가 찍은 걸로 하고 싶어 | `gnome_ko_look_background`: 를 눌러 가지고 있는 사진 중 하나를 활용할 수 있습니다 | OK |
| e1q-077 | ko | paraphrase | partial | gnome | tune | O / O | 구글 계정을 연동하면 메일이나 일정 앱도 같이 쓸 수 있어? | `gnome_ko_accounts_add`: 전자메일 클라이언트, 달력, 기타 관련 프로그램을 설정합니다. | OK |
| e1q-078 | ko | paraphrase | none | gnome | check | O / X | 저장장치가 곧 망가질 것 같다는 경고가 떴어. 어떻게 해? | `gnome_ko_disk_check`: 만약 문제가 생겼다면 컴퓨터 또는 하드디스크를 전문가에게 맏겨 추가 진단 또는 수리를 진행하는 것이 좋습니다. | OK |
| e1q-079 | ko | lexical | partial | own | check | O / O | 은행 거래내역은 하루에 몇 번 자동으로 가져오나요? | `e1_own_ko_01`: 하루 네 번(오전 6시, 낮 12시, 오후 6시, 자정) 자동으로 가져옵니다 | OK |
| e1q-080 | ko | lexical | partial | own | check | O / O | 가족 공유는 최대 몇 명까지 함께 쓰나요? | `e1_own_ko_01`: 가족 공유를 켜면 최대 4명이 하나의 가계부를 함께 씁니다. | OK |
| e1q-081 | ko | lexical | partial | own | tune | O / O | 오류 코드 E205는 무슨 뜻인가요? | `e1_own_ko_03`: 오류 코드 E205 인증서 유효기간이 지났습니다. | OK |
| e1q-082 | ko | lexical | high | own | tune | O / O | 프리미엄 요금은 월 얼마인가요? | `e1_own_ko_04`: 프리미엄 요금은 월 2,900원, 1년 결제 시 29,000원입니다. | OK |
| e1q-083 | ko | lexical | partial | own | tune | O / O | 출장 일비는 하루 얼마인가요? | `e1_own_ko_07`: 일비: 하루 3만 원(식비 포함). | OK |
| e1q-084 | ko | lexical | partial | own | tune | O / O | 재택근무 코어타임은 몇 시부터 몇 시까지인가요? | `e1_own_ko_08`: 코어타임은 오전 10시부터 오후 4시까지입니다. | OK |
| e1q-085 | ko | lexical | high | own | tune | O / O | 연차는 반차로 몇 시간 단위로 쓰나요? | `e1_own_ko_11`: 연차는 하루 또는 반차(4시간) 단위로 씁니다. | OK |
| e1q-086 | ko | lexical | high | own | check | O / O | 비밀번호는 며칠마다 바꿔야 하나요? | `e1_own_ko_12`: 비밀번호는 90일마다 바꿔야 합니다. | OK |
| e1q-087 | ko | paraphrase | none | own | tune | O / O | 옛날 아이폰에서도 최신 가계부 앱을 받을 수 있나요? | `e1_own_ko_02`: 3.0부터 iOS 16 이상이 필요합니다. | OK |
| e1q-088 | ko | paraphrase | partial | own | check | O / O | 할부가 두 번 찍혀 있던데 해결됐어? | `e1_own_ko_02`: 월말에 할부 결제가 두 번 집계되던 문제를 고쳤습니다. | 고침(질문). 전: 나눠서 낸 결제가 이번 달에 중복으로 잡혀 있던데 해결됐어? |
| e1q-089 | ko | paraphrase | none | own | tune | X / X | 한밤중에 보니 카드 쓴 기록 몇 개가 안 보여요 | `e1_own_ko_03`: 은행 점검 시간(대부분 밤 11시 30분부터 새벽 0시 30분까지)에는 일부 내역이 빠질 수 있습니다. | OK |
| e1q-090 | ko | paraphrase | none | own | check | O / O | 유료 결제를 그만두려면 어디서 취소하나요? | `e1_own_ko_04`: 구독 해지는 앱이 아니라 앱스토어나 구글 플레이의 구독 관리에서 합니다. | OK |
| e1q-091 | ko | paraphrase | none | own | check | O / O | 회원을 그만두면 내 기록은 언제 완전히 없어져? | `e1_own_ko_05`: 거래내역과 영수증 사진은 30일 동안 보관한 뒤 파기합니다. | OK |
| e1q-092 | ko | paraphrase | partial | own | check | O / O | 엑셀 파일로 뽑을 때 찍어 둔 영수증 이미지도 같이 들어가? | `e1_own_ko_06`: 영수증 사진은 포함되지 않습니다. | OK |
| e1q-093 | ko | paraphrase | partial | own | tune | O / O | 폰을 바꿨는데 예전 가계부를 그대로 볼 수 있어? | `e1_own_ko_01`: 새 휴대폰에서 같은 계정으로 로그인하면 그대로 보입니다. | OK |
| e1q-094 | ko | paraphrase | none | own | check | X / O | 내 차를 몰고 지방에 다녀오면 기름값은 얼마나 받아? | `e1_own_ko_07`: 자가용을 쓰면 1km당 250원을 지급합니다. | OK |
| e1q-095 | ko | paraphrase | none | own | check | X / O | 들어온 지 한 달 됐는데 집에서 일해도 되나요? | `e1_own_ko_08`: 입사 후 3개월 수습 기간에는 재택근무를 신청할 수 없습니다. | OK |
| e1q-096 | ko | paraphrase | none | own | check | O / O | 신규 서비스 오픈이 왜 늦춰졌어? | `e1_own_ko_09`: 결제 대행사 연동 심사가 끝나지 않았기 때문이다. | OK |
| e1q-097 | ko | paraphrase | partial | own | check | O / O | 회사 컴퓨터에 USB 꽂아도 돼? | `e1_own_ko_10`: USB 저장장치: 기본 차단. | 고침(질문). 전: 업무 PC에 이동식 메모리를 꽂아도 돼? |
| e1q-098 | ko | paraphrase | none | own | check | X / O | 올해 못 쓴 휴가를 내년에 쓸 수 있나? | `e1_own_ko_11`: 쓰지 않은 연차는 다음 해로 넘어가지 않습니다. | OK |
| e1q-099 | ko | lexical | high | pdf | tune | O / O | 2025년 1~3월 보이스피싱 피해액은 얼마인가요? | `e1_pdf_kor`: 보이스피싱은 2025년 1~3월 발생 건수 5,878건, 총 피해액 3,116억 원으로 집계된 | OK |
| e1q-100 | ko | lexical | high | pdf | tune | O / O | 군을 겨냥한 사이버공격 시도는 총 몇 회였나요? | `e1_pdf_kor`: 군을 겨냥한 사이버공격 시도는 2020년부터 2024년 8월까지 총 5만6,034회로 제시되었고 | OK |
| e1q-101 | ko | lexical | high | pdf | check | O / O | 군 보안 규정 위반은 최근 5년간 몇 명인가요? | `e1_pdf_kor`: 군 보안 규정 위반은 최근 5년간 3,922명 수준으로 | OK |
| e1q-102 | ko | lexical | partial | pdf | check | O / O | 스미싱은 무엇의 합성어인가요? | `e1_pdf_kor`: 스미싱: 문자메시지(SMS)와 피싱(phishing)의 합성어로 | OK |
| e1q-103 | ko | lexical | high | pdf | check | O / O | 2025년 7월 기준 군 병력은 몇 명 수준인가요? | `e1_pdf_kor`: 2025년 7월 기준 군 병력이 45만 명 수준으로 감소했다는 | OK |
| e1q-104 | ko | paraphrase | partial | pdf | tune | O / O | 설 보너스 준다는 문자로 군인을 속인 일이 실제로 있었어? | `e1_pdf_kor`: “명절휴가비 지급 안내”와 함께 ‘지급내역 확인’ 링크를 보내는 스미싱 문자가 유포되었고 | OK |
| e1q-105 | ko | paraphrase | partial | pdf | check | O / O | 약관 동의할 때 내용을 제대로 읽어 보는 십대는 얼마나 돼? | `e1_pdf_kor`: 동의 내용을 실제로 확인하는 비율은 성인 55%, 청소년 37%에 그쳤다는 | OK |
| e1q-106 | ko | no_answer | – | – | tune | 1위 `e1_own_ko_01` | 모아가계부에 주식 계좌도 연결할 수 있나요? | (답 없음) | OK |
| e1q-107 | ko | no_answer | – | – | check | 1위 `e1_own_ko_01` | 모아가계부 다크 모드는 어떻게 켜나요? | (답 없음) | OK |
| e1q-108 | ko | no_answer | – | – | check | 1위 `e1_own_ko_07` | 출장 가기 전에 경비를 미리 받을 수 있나요? | (답 없음) | 고침(질문). 전: 해외 출장 숙박비 한도는 얼마인가요? |
| e1q-109 | ko | no_answer | – | – | tune | 1위 `e1_own_ko_11` | 경조사 휴가는 며칠인가요? | (답 없음) | OK |
| e1q-110 | ko | no_answer | – | – | tune | 1위 `e1_own_ko_12` | 사내 식당은 몇 시에 여나요? | (답 없음) | OK |
| e1q-111 | ko | no_answer | – | – | check | 1위 `gnome_ko_hardware_cardreader` | 법인카드를 잃어버리면 어떻게 신고하나요? | (답 없음) | OK |
| e1q-112 | ko | no_answer | – | – | tune | 1위 `gnome_ko_printing_setup` | 프린터 잉크 잔량은 어디서 확인하나요? | (답 없음) | OK |
| e1q-113 | ko | no_answer | – | – | check | 1위 `e1_own_ko_01` | 모아가계부 고객센터 전화번호는 뭐예요? | (답 없음) | OK |
| e1q-114 | ko | no_answer | – | – | check | 1위 `e1_own_ko_05` | 회사 건강검진은 언제 받나요? | (답 없음) | OK |
| e1q-115 | ko | no_answer | – | – | tune | 1위 `e1_own_ko_09` | 회의실 예약은 어떻게 하나요? | (답 없음) | OK |
| e1q-116 | ko | no_answer | – | – | check | 1위 `e1_own_ko_04` | 주차 지원금은 한 달에 얼마인가요? | (답 없음) | OK |
| e1q-117 | ko | no_answer | – | – | tune | 1위 `e1_own_ko_01` | 가계부 위젯 크기를 바꾸려면? | (답 없음) | OK |
| e1q-118 | ko | no_answer | – | – | tune | 1위 `e1_own_ko_07` | 출장 일정이 주말에 걸리면 휴일 근무로 인정되나요? | (답 없음) | 고침(질문). 전: 출장 갈 때 택시비도 정산되나요? |
| e1q-119 | ko | no_answer | – | – | check | 1위 `e1_own_ko_12` | 사내 동호회 지원금은 얼마인가요? | (답 없음) | OK |
| e1q-120 | ko | no_answer | – | – | check | 1위 `e1_own_ko_03` | 모아가계부 앱을 열 때 잠금 비밀번호를 걸 수 있나요? | (답 없음) | OK |

## 검수 메모 (2026-11-14, 세션 검수 · 같은 날 사용자 확정)

판정은 원문(직접 쓴 문서 24개, GNOME 30쪽, PDF 2개를 pdftotext로 뽑은 글)과 대조해서 적었다. 겹침은 엔진 `tokenize_for_bm25`를 그대로 옮겨 쟀고, `e1_overlap_v1.json`의 90줄을 모두 똑같이 재현했다. 아래 "새 겹침"은 바꾼 질문·구절로 다시 잰 값이다. 사용자가 확정해 작성자를 `session_draft+human_review`로 바꿨다.

### 고친 이유

| id | 이유 | 새 겹침 (등급) |
|---|---|---|
| e1q-008 | "something … the bin"이 막연하다. GNOME 사용자는 trash라고 한다 | 0.15 (partial, 그대로) |
| e1q-011 | 질문은 "가장 많이(most)"인데 구절은 "상당한 부분(significant fraction)"이다. 구절이 질문에 답하지 못한다 | 0.22 (partial, 그대로) |
| e1q-013 | "router's name invisible"은 실제로 쓰지 않는 말. 보통 "hide my Wi-Fi name"이라고 한다 | 0.18 (none → partial) |
| e1q-028 | 실제 사용자는 "factory reset"이라고 한다 | 0.33 (partial, 그대로) |
| e1q-029 | "the lamps where I sleep"은 침실 조명을 일부러 피한 말 | 0.36 (partial, 그대로) |
| e1q-045 | "future policies beyond the current agreement"는 뜻이 흐리다 | 0.33 (partial, 그대로) |
| e1q-064 | 질문이 답(SMART)을 이미 담고 있다 | 0.50 (partial → high) |
| e1q-069 | 질문은 경로 길이를 묻는데, 구절은 파일 이름 길이만 말한다. 경로 얘기는 바로 다음 문장에 있다 | 0.12 (none → partial) |
| e1q-073 | "USB로 꽂는 녹음 장비"는 'USB 마이크'를 일부러 피한 말 | 0.33 (none → partial) |
| e1q-074 | "저장 장치 관리 도구"는 실제로 쓰지 않는 말. GNOME에서는 '디스크' 프로그램이다 | 0.24 (none → partial) |
| e1q-088 | 한국어 사용자는 거의 다 '할부'라고 한다 | 0.23 (partial, 그대로) |
| e1q-097 | '이동식 메모리'보다 'USB'가 자연스럽다 | 0.10 (none → partial) |
| e1q-108 | 영어 출장 규정(`e1_own_en_07`)에 "Hotel bookings above $220 per night need approval"이 있다. 국내·해외 구분이 없고, 같은 가상 회사라면 답이 있는 셈이다 | 답 없음 |
| e1q-118 | 국내 출장 규정이 교통비로 KTX·시외버스·자가용만 적고 있어서, 택시는 "안 된다"는 답으로도 읽힌다. 답이 없다고 보기 어렵다 | 답 없음 |

새 답 없음 질문 두 개(108, 118)는 코퍼스 56개 문서 전체(PDF 포함)에서 '선급·가지급·미리 받·advance', '주말·휴일·weekend·holiday'를 찾아 답이 없음을 확인했다.

### OK로 두되 알아 둘 것

- **같은 규칙이 다른 언어 문서에도 있다.** 034(늦은 경비 보고 → 30일, 임원 승인)는 `e1_own_ko_07`에, 037(노트북 분실 → 1시간 안에 신고)은 `e1_own_ko_12`에 같은 내용이 있다. 정답이 구절 단위라, KoEn이 한국어 청크를 가져오면 답을 찾고도 틀림으로 세진다.
- **001**: `gnome_en_files_delete`에도 휴지통에서 되살리는 얘기가 있다(방법은 없음).
- **016**: 구절은 백업에서 빼도 되는 세 가지 중 하나다(다른 둘은 다른 곳에 이미 백업한 파일, 휴지통). 답의 일부지만 질문에 맞는 답이다.
- **032**: 30일 뒤 지우지만 백업은 35일 더 남는다. 질문 "how soon is everything erased"의 답으로는 충분하다.
- **070**: 같은 문서의 "사용자 암호를 잊었다면 관리자 권한을 지닌 사용자가 암호를 바꿔줄 수 있습니다."도 답이다. 다른 청크에 있으면 정답을 찾고도 틀림으로 세질 수 있다.
- **104**: 문서에는 '설'이 없고 "2024년 2월 … 명절휴가비"만 있다. 2024년 설이 2월 10일이라 맞는 말이다.
- **050**(병가 일수): `e1_own_ko_11`에 아파서 쉴 때의 신청 절차가 있지만 일수는 없다. 답 없음 맞음.
- **056**(Lumo 에너지 → 스프레드시트), **107**(모아가계부 다크 모드): 다른 제품 문서(`e1_own_ko_06` 엑셀 내보내기, `gnome_ko_look_background` 어두운 모양새)가 강한 오답 유인이다. 질문이 제품 이름을 대고 있어서 답 없음 맞음.

### 다른 낱말로 쓴 질문 50개에 대한 판단

- 50개 중 **11개를 고쳤다**(질문 10개: 008, 011, 013, 028, 029, 045, 073, 074, 088, 097 / 구절 1개: 069). 011과 045는 질문과 구절이 어긋나거나 뜻이 흐려서 고쳤고, 나머지 8개는 "문서 낱말을 피하느라 실제로는 안 쓰는 말이 됐다"는 이유다.
- 자연스럽게 고치면 **`none` 27개 중 5개(013, 069, 073, 074, 097)가 `partial`로 올라간다.** 실제 사용자는 UI에 보이는 이름(trash, USB, 할부, factory reset)을 그대로 쓰는 경우가 많기 때문이다.
- 나머지 40개는 실제로 할 법한 말이다. 특히 한국어 own 문서 질문(089, 094, 095, 098 등)은 문서 낱말과 안 겹치면서도 자연스럽다.
- 0.5/0.5의 이득이 이 유형에서 나왔으므로, **고친 뒤 다시 재면 이득이 조금 줄 수 있다.** 고친 11개 중 KoEn 0.5/0.5에서 기본값보다 나아졌던 것은 029와 073이다(X → O). 008, 011, 013, 045, 074는 두 무게 모두 틀렸고, 나머지 4개는 둘 다 맞혔다.
