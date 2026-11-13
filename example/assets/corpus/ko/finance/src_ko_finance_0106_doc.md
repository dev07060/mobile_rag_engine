# 알고리즘 트레이딩

- source_key: src_ko_finance_0106
- language: ko
- domain: finance
- length_bucket: medium
- collected_at: 2026-02-22
- url: https://ko.wikipedia.org/wiki/%EC%95%8C%EA%B3%A0%EB%A6%AC%EC%A6%98_%ED%8A%B8%EB%A0%88%EC%9D%B4%EB%94%A9

---

알고리즘 트레이딩(영어: algorithmic trading)은 컴퓨터 프로그램을 이용, 일정한 논리구조(알고리즘)에 따라 증권, 파생상품, 외환 등 유동성 자산을 자동으로 거래하는 매매 방식이다.

용어
알고리즘 트레이딩은 시스템 매매, 시스템 트레이딩 또는 프로그램 매매라는 명칭으로도 널리 알려져 있다. 이 중 '프로그램 매매'는 선물시장과 연계한 차익거래 즉 선물과 현물중 상대적으로 고평가 된 것을 팔고 동시에 가격이 낮은 쪽을 사는 알고리즘 매매를 뜻하는 좁은 뜻으로 사용되는 경우가 많다. 이를 '지수차익거래'라고 하는데, 이것은 알고리즘 매매의 가장 일반적인 부류일 뿐 가능한 수많은 알고리즘 중 하나일 뿐이므로 프로그램 매매라는 어휘를 차익거래에만 따로 사용하는 것은 옳지 않다.

개요
알고리즘 트레이딩은 컴퓨터를 이용하여 자산의 가격과 추세, 거래량 등을 분석하여 컴퓨터 프로그램이 매수 혹은 매도를 알아서 수행하는 거래이다.
주로 헤지펀드, 뮤추얼펀드와 같은 전문 기관에서 이루어졌으나, 2000년 이후부터 예스트레이더(Yes Trader), 사이보스트레이더(Cybos Trader), 메타트레이더(Meta Trader)와 같은 알고리즘 트레이딩 소프트웨어와 알고리즘 트레이딩을 위한 프로그래밍 언어가 일반 대중들에게도 소개되면서 제한적이나마 알고리즘 트레이딩의 이용자층이 생겨났다. 2022년 현재 키움증권 openAPI를 이용한 알고리즘 매매를 이용하는 개인들이 많아 지고 있다.

알고리즘 트레이딩의 전략
알고리즘 트레이딩은 대표적으로 다음 두 거래방식을 이용한다.

기술적 분석 기반 거래
차익거래

기술적 분석 기반 거래
기술적 분석 기반 거래는 기술적 지표(Technical Indicator)나 일정 기간 동안의 정보를 담고있는 캔들(Candle)에 의존해 거래를 한다. 기술적 분석 기반 전략은 크게 두 가지로 구분할 수 있다.

추세 추종 전략(Trend Following Strategy)
역추세 전략(Counter-Trend Strategy)

추세 추종 전략
추세 추종 전략은 중장기적으로 형성된 추세가 앞으로도 유지될 것이라고 기대하고, 그 추세의 방향과 같은 방향으로 포지션을 구축하는 전략이다. 추세 추종 전략에서는 이동평균선(Moving Average Line), MACD(Moving Average Convergence and Divergence), RSI(Relative Strength Index)와 같은 기술적 지표를 이용한다. 대표적인 추세 추종 전략으로는 이동평균선 교차 전략이 있다.
추세 추종 전략에 기본은 이동평균선의 정배열부터 시작이다. 정배열 상태에서 많은 거래량이 동반된 강한 상승 이후 우상향을 한다면 추세의 시작이라고 할 수 있다.

역추세 전략
역추세 전략은 단기적 혹은 중기적으로 추세와는 반대로 가격이 움직일 것을 기대하고, 지금까지의 짧은 추세의 방향과는 반대 방향으로 포지션을 구축하는 전략이다. 역추세 전략은 일정 기간 동안 주가가 형성한 가격 범위대를 이용해 과열 혹은 침체를 판단한다. 여기서 일정 기간은 대체로 짧은 기간이며 거래 방식은 스캘핑(Scalping)이 대다수를 차지한다. 역추세 전략에서는 캔들에 내포된 저가나 고가를 이용하기도 하고 RSI, Stochastic Oscillator, 이격도, Bollinger Band와 같은 기술적 지표를 이용하기도 한다.

차익거래
차익거래는 시장이 정상적인 상태에서 벗어났다가 다시 되돌아올 것을 기대하며 시장 간의 혹은 상품 간의 가격 괴리를 이용하는 거래방식이다. 이 거래방식에서는 고빈도매매(HFT,High Frequency Trading)가 이용되기도 한다. 알고리즘 트레이딩에서 일컫는 차익거래는 대체로 통계적 차익거래(Statistical Arbitrage)이다.

통계적 차익거래
통계적 차익거래는 두 시장 혹은 두 종목 간의 가격 차이인 스프레드(Spread)를 통계적으로 분석해, 통계적으로 유의미한 스프레드 범위를 벗어났을 때 스프레드가 가정된 정상 범위로 돌아올 것을 기대하고 포지션을 구축하는 전략이다. 통계적 차익거래에는 페어트레이딩(Pairs Trading)과 프로그램 매매 등이 있다.

페어트레이딩
페어트레이딩은 일반적으로 두 종목 간의 스프레드를 이용한다. 이 거래 전략은 스프레드가 통계적으로 유의미한 범위를 이탈했을 때 정상범위로 돌아올 것을 기대하고 포지션을 구축한다. 여기서 포지션을 구축할 때는 서로 반대 방향의 포지션을 지니게 해야하며, 이 때 적절한 헤지(Hedge)를 통해 현재 스프레드 값과 정상 범위일 때의 스프레드 값 만큼의 차익을 얻는다. 스프레드가 평균으로 돌아올 것을 이용하기 때문에 평균-회귀 전략(Mean-Reversion Strategy)이라고도 불린다. 다음은 페어트레이딩을 하기 위한 절차이다.

두 종목 X와 Y의 데이터를 구한다.
두 종목의 표준화 값을 이용해 스프레드의 정상성(Stationary)의 존재 여부를 파악한다. 정상성 검증으로는 DF Test(Dickey Fuller Test)나 ADF Test(Agumented Dickey Fuller Test)를 이용할 수 있다.
Test의 통계량을 검정통계량과 비교해 정상성 여부를 판단한다.
정상성이 확보되면 OLS(Ordinary Least Square), TLS(Total Least Square) 등의 방법을 이용해 헤지를 하기 위한 변동성 계수인 베타 계수(Beta Coefficient)를 구한다. 대안으로 자기상관계수를 최저로 만드는 베타, 평균을 0으로 만드는 베타, CAPM에서 등장하는 체계적 위험을 판단하는 베타를 이용할 수도 있다.
베타 계수를 구했다면 종목 X와 Y에 대해서 X-b*Y (단 b는 헤지를 위한 베타 계수)의 평균과 표준편차를 이용해 표준화(정규화)시켜 Z값을 산출한다. 여기서 Z는 표준정규분포를 따르므로 평균이 0이고 분산 1인 확률변수이다.
유의미하다고 생각되는 Z값을 조건으로 페어트레이딩을 실시한다. 여기서 베타 계수를 이용해 헤지를 정확히 해야만 추세성분은 최소화할 수 있다.
Z값이 스프레드의 평균이 되는 지점에서 포지션을 청산한다. 대안으로 스프레드가 정상 범위로 돌아올 때 이익 정도와 손실 정도를 임의로 정할 수 있다.

참고 문헌
Dark Pools: The Rise of the Machine Traders and the Rigging of the U.S. Stock Market by Scott Patterson (Jun 25, 2013)
When genius failed: The rise and fall of Long-Term Capital Management. Lowenstein, R. Random House, 2000
Algorithmic Trading: Winning Strategies and Their Rationale by Ernie Chan (May 28, 2013)
Algorithmic Trading and DMA: An introduction to direct access trading strategies by Barry Johnson (Feb 17, 2010)
Inside the Black Box: A Simple Guide to Quantitative and High Frequency Trading by Rishi K. Narang (Mar 25, 2013)
Quantitative Trading: How to Build Your Own Algorithmic Trading Business by Ernie Chan (Nov 17, 2008)
High-Frequency Trading: A Practical Guide to Algorithmic Strategies and Trading Systems by Irene Aldridge (Apr 22, 2013)
Quantitative Investing: Strategies to exploit stock market anomalies for all investors by Fred Piard (Aug 26, 2013)

같이 보기
전자거래 플랫폼(온라인거래 플랫폼)
