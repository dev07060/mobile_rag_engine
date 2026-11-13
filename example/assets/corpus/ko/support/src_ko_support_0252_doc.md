# 명령어 인터프리터

- source_key: src_ko_support_0252
- language: ko
- domain: support
- length_bucket: short
- collected_at: 2026-02-22
- url: https://ko.wikipedia.org/wiki/%EB%AA%85%EB%A0%B9%EC%96%B4_%EC%9D%B8%ED%84%B0%ED%94%84%EB%A6%AC%ED%84%B0

---

명령어 인터프리터(command-line interpreter, command-line processor, command language interpreter)는 운영 체제나 프로그래밍 언어의 환경에서 해석하는 입력된 명령어를 읽고 실행하는 컴퓨터 프로그램이다. 줄 단위의 명령어를 읽어 들인다고 하여 명령줄 인터프리터 또는 명령행 인터프리터라고도 한다.

특징
명령어 인터프리터는 사용자 또는 명령어 파일로부터 명령어를 읽어들인 후, 명령어를 하나 이상의 시스템 호출로 변환함으로써 그것을 실행한다.
그에 따라 명령어 인터프리터는 실행에 제약을 받기 때문에, 커널에 포함되지 않는다.

시스템 호출
명령어 인터프리터 또는 셸을 통해 입력된 명령을 수행하는 과정에서 새로운 프로세스를 시작하기 위해서는 시스템 호출을 해야 한다. 예를 들어 유닉스 시스템에서는 새로운 프로세스를 시작하기 위해 exec 시스템 호출 이후 fork 시스템 호출이 뒤따른다. exec 호출이 호출 프로세스 위로 다른 실행가능한 새로운 프로세스를 띄우는 동안, fork 호출은 현재 실행 중인 프로세스를 복제한다.

같이 보기
명령줄 인터페이스
셸
컴퓨터 터미널
명령줄 변수
일괄 처리
배치 파일
스크립트 언어
