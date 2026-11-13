# 슬라이딩 윈도

- source_key: src_ko_tech_0280
- language: ko
- domain: tech
- length_bucket: medium
- collected_at: 2026-02-22
- url: https://ko.wikipedia.org/wiki/%EC%8A%AC%EB%9D%BC%EC%9D%B4%EB%94%A9_%EC%9C%88%EB%8F%84

---

슬라이딩 윈도(Sliding window)는 두 개의 네트워크 호스트간의 패킷의 흐름을 제어하기 위한 방법이다.
TCP와 같이 데이터의 전달을 보증하는 프로토콜에서는 패킷 하나 하나가 정상적으로 전달되었음을 알리는 확인 신호(acknowledgement, 이하 ACK)를 받아야하며, 만약 패킷이 중도에 잘못되었거나 분실되어 확인받지 못하는 경우, 해당 패킷을 재전송해야하는 필요가 있다. 슬라이딩 윈도는 일단 '윈도(메모리 버퍼의 일정 영역)'에 포함되는 모든 패킷을 전송하고, 그 패킷들의 전달이 확인되는대로 이 윈도를 옆으로 옮김(slide)으로서 그 다음 패킷들을 전송하는 방식이다.
슬라이딩 윈도는 아직 확인을 받지 않고도 여러 패킷을 보내는 것을 가능케 하기 때문에, 매번 전송한 패킷에 대해 확인을 받아야만 그 다음 패킷을 전송하는 방법(stop-and-wait)을 사용하는 것보다 훨씬 네트워크를 효율적으로 사용할 수 있다.

설명
일단 전송되는 패킷들에겐 일련번호(sequence number)가 매겨지게 된다. 가령 전송하고자하는 
 
 
 
 n
 
 
 {\displaystyle n}
 
개의 패킷이 있다고 하면 [1, 2, ..., n]와 같이 일련번호를 매길 수 있다.
송신자(sender)는 다음의 세 가지 변수를 관리한다.

SWS (send window size) - 윈도 크기
LAR (last acknowledgement received) - 마지막으로 확인받은 패킷의 번호
LFS (last frame sent) - 마지막으로 보낸 패킷의 번호
그렇다면 송신자의 윈도는 [(LAR+1), ... , (LAR+SWS)]가 된다. 송신자는 이 윈도에 포함되는 모든 패킷들을 전송하고, 수신자로부터 ACK가 올때까지 기다린다. LFS는 LAR+SWS가 된다. 아무 문제가 없었다면 수신자로부터 LAR+1의 ACK를 가장 먼저 받게 된다. 그렇다면 송신자는 LAR을 갱신하고, 그렇게되면 LAR+SWS도 그만큼 증가하기 때문에 그 다음 패킷을 보낼 수 있게 된다.
또 만약 어느 패킷에 대해 ACK를 받지 못한 경우, 송신자는 일정시간을 기다린 후, 확인받지 못한 패킷을 재전송한다. 이미 현재의 윈도에 해당되는 패킷을 모두 보냈는데 ACK를 받지 못해 윈도를 이동시키지 못하고 있다면 필요한 ACK가 오기까지 기다려야 한다.
수신자(receiver)도 윈도를 따로 운용한다. 수신자는 다음의 세 가지 변수를 관리한다.

RWS (receive window size) - 윈도 크기
LAF (last acceptable frame) - 수신할 수 있는 마지막의 패킷의 번호
LFR (last frame received) - 마지막으로 수신한 패킷의 번호
송신자와 비슷하게 수신자도 LAF와 LFR을 갱신하여 윈도를 이동시키며 패킷들을 접수한다. 받는 패킷들에 대한 ACK를 보내주는 것이 수신자의 역할이다. 수신자가 보내는 ACK는 마지막으로 도착한 패킷에 대한 ACK가 아니고, 연속적으로 도착한 패킷중의 가장 마지막 패킷에 대한 ACK이다. 예를 들어 1, 2, 3, 4, 6, 7의 패킷이 순서대로 도착하였다면, 수신자는 그 7번의 패킷을 받아 버퍼에 저장하고, 4번의 패킷에 대한 ACK를 송신자에게 보낸다. 만약 그 다음에 도착하는 패킷이 5번이라면, 수신자는 그제서야 7번의 패킷에 대한 ACK를 송신자에게 보내게 된다.
만약 윈도에 포함되지 않는 패킷이 도착하면, 수신자는 단순히 이 패킷을 버린다.
결론적으로 데이터의 전송이 되는 동안 아래의 두 가지 부등식이 항상 성립하여야한다.

 
 
 
 L
 F
 S
 −
 L
 A
 R
 ≤
 S
 W
 S
 
 
 {\displaystyle LFS-LAR\leq SWS}
 

 
 
 
 L
 A
 F
 −
 L
 F
 R
 ≤
 R
 W
 S
 
 
 {\displaystyle LAF-LFR\leq RWS}
 

네트워크의 상황에 따라 송신자나 수신자는 각자의 윈도 크기(SWS, RWS)를 조절할 수도 있다.

외부 링크
RFC 1323 - TCP Extensions for High Performance
TCP window scaling and broken routers, 2004
Sliding Window Demo 보관됨 2011-03-11 - 웨이백 머신 (Flash required)
Sliding Window Demo (Shockwave required)
TCP Sliding Window simulation (interactive animation) 보관됨 2022-07-26 - 웨이백 머신
