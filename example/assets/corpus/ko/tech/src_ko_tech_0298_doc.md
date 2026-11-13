# 논리 연산

- source_key: src_ko_tech_0298
- language: ko
- domain: tech
- length_bucket: medium
- collected_at: 2026-02-22
- url: https://ko.wikipedia.org/wiki/%EB%85%BC%EB%A6%AC_%EC%97%B0%EC%82%B0

---

논리 연산(logical operation, logical connective) 혹은 불 연산(boolean operation)은 참, 거짓 두 가지 원소(진리값으로 불림)만 존재하는 집합(환으로 불림)에서의 연산이다.
논리합(OR, ∨), 논리곱(AND, ∧), 부정(NOT, ~/¬), 배타적 논리합(XOR, ⊕), 명제, 동치 등이 있다.
수학이나 논리학 또는 컴퓨터 과학의 프로그래밍 언어 등에서 사용한다. 프로그래밍 언어에서는 비트 연산이라고도 한다.

연산 법칙
논리합=
 
 
 
 ∨
 
 
 {\displaystyle \lor }
 
, 논리곱=
 
 
 
 ∧
 
 
 {\displaystyle \land }
 
, 부정=
 
 
 
 ¬
 
 
 {\displaystyle \lnot }
 
이라고 할 때 아래와 같은 법칙이 성립한다.

멱등 법칙

 
 
 
 A
 ∨
 A
 =
 A
 
 
 {\displaystyle A\lor A=A}
 

 
 
 
 A
 ∧
 A
 =
 A
 
 
 {\displaystyle A\land A=A}
 

교환 법칙

 
 
 
 A
 ∨
 B
 =
 B
 ∨
 A
 
 
 {\displaystyle A\lor B=B\lor A}
 

 
 
 
 A
 ∧
 B
 =
 B
 ∧
 A
 
 
 {\displaystyle A\land B=B\land A}
 

결합 법칙

 
 
 
 A
 ∨
 (
 B
 ∨
 C
 )
 =
 (
 A
 ∨
 B
 )
 ∨
 C
 
 
 {\displaystyle A\lor (B\lor C)=(A\lor B)\lor C}
 

 
 
 
 A
 ∧
 (
 B
 ∧
 C
 )
 =
 (
 A
 ∧
 B
 )
 ∧
 C
 
 
 {\displaystyle A\land (B\land C)=(A\land B)\land C}
 

분배 법칙

 
 
 
 A
 ∨
 (
 B
 ∧
 C
 )
 =
 (
 A
 ∨
 B
 )
 ∧
 (
 A
 ∨
 C
 )
 
 
 {\displaystyle A\lor (B\land C)=(A\lor B)\land (A\lor C)}
 

 
 
 
 A
 ∧
 (
 B
 ∨
 C
 )
 =
 (
 A
 ∧
 B
 )
 ∨
 (
 A
 ∧
 C
 )
 
 
 {\displaystyle A\land (B\lor C)=(A\land B)\lor (A\land C)}
 

흡수 법칙

 
 
 
 A
 ∨
 (
 A
 ∧
 B
 )
 =
 A
 
 
 {\displaystyle A\lor (A\land B)=A}
 

 
 
 
 A
 ∧
 (
 A
 ∨
 B
 )
 =
 A
 
 
 {\displaystyle A\land (A\lor B)=A}
 

드 모르간의 법칙

 
 
 
 ¬
 (
 A
 ∨
 B
 )
 =
 (
 ¬
 A
 )
 ∧
 (
 ¬
 B
 )
 
 
 {\displaystyle \lnot (A\lor B)=(\lnot A)\land (\lnot B)}
 

 
 
 
 ¬
 (
 A
 ∧
 B
 )
 =
 (
 ¬
 A
 )
 ∨
 (
 ¬
 B
 )
 
 
 {\displaystyle \lnot (A\land B)=(\lnot A)\lor (\lnot B)}
 

기타

 
 
 
 A
 ∨
 0
 =
 A
 
 
 {\displaystyle A\lor 0=A}
 

 
 
 
 A
 ∧
 0
 =
 0
 
 
 {\displaystyle A\land 0=0}
 

 
 
 
 A
 ∨
 1
 =
 1
 
 
 {\displaystyle A\lor 1=1}
 

 
 
 
 A
 ∧
 1
 =
 A
 
 
 {\displaystyle A\land 1=A}
 

 
 
 
 A
 ∨
 (
 ¬
 A
 )
 =
 1
 
 
 {\displaystyle A\lor (\lnot A)=1}
 

 
 
 
 A
 ∧
 (
 ¬
 A
 )
 =
 0
 
 
 {\displaystyle A\land (\lnot A)=0}
 

 
 
 
 ¬
 (
 ¬
 A
 )
 =
 A
 
 
 {\displaystyle \lnot (\lnot A)=A}
 

같이 보기
벤 다이어그램
드 모르간의 법칙
진리값
수학
논리학
프로그래밍 언어
논리 회로
이진불연산
