# Service level

- source_key: src_en_support_0269
- language: en
- domain: support
- length_bucket: long
- collected_at: 2026-02-22
- url: https://en.wikipedia.org/wiki/Service_level

---

Service level measures the performance of a system, service or supply. Certain goals are defined and the service level gives the percentage to which those goals should be achieved.
Examples of service level:

Percentage of calls answered in a call center
Percentage of customers waiting less than a given fixed time
Percentage of customers that do not experience a stockout
Percentage of all parts of an order being fulfilled completely
Use of a safety stock to ensure that a target percentage of orders can be met in full and on time.
The term "service level" is used in supply-chain management and in inventory management to measure the performance of inventory replenishment policies. Under consideration, from the optimal solution of such a model also the optimal size of back orders can be derived. A back order is an order placed for an item which is out-of-stock and awaiting fulfillment. Unfortunately, this optimization approach requires that the planner knows the optimal value of the back order costs. As these costs are difficult to quantify in practice, the logistical performance of an inventory node in a supply network is measured with the help of technical performance measures. The target values of these measures are set by the decision maker.

Definitions and typology
Several definitions of service levels are used in the literature as well as in practice. These may differ not only with respect to their scope and to the number of considered products but also with respect to the time interval they are related to. These performance measures are the key performance indicators (KPI) of an inventory node which must be regularly monitored. If the controlling of the performance of an inventory node is neglected, the decision maker will not be able to optimize the processes within a supply chain.

α service level (type 1)
The α service level is an event-oriented performance criterion. It measures the probability that all customer orders arriving within a given time interval will be completely delivered from stock on hand, i.e. without delay.
Two versions are discussed in the literature differing with respect to the time interval within which the customers arrive. With reference to a demand period, α denotes the probability that an arbitrarily arriving customer order will be completely served from stock on hand, i.e. without an inventory-related waiting time (period 
 
 
 
 
 α
 
 p
 
 
 
 
 {\displaystyle \alpha _{p}}
 
 service level):

 
 
 
 
 α
 
 p
 
 
 =
 P
 r
 o
 b
 {
 P
 e
 r
 i
 o
 d
 
 d
 e
 m
 a
 n
 d
 ≤
 
 
 I
 n
 v
 e
 n
 t
 o
 r
 y
 
 o
 n
 
 h
 a
 n
 d
 
 a
 t
 
 t
 h
 e
 
 b
 e
 g
 i
 n
 n
 i
 n
 g
 
 o
 f
 
 a
 
 p
 e
 r
 i
 o
 d
 
 }
 
 
 {\displaystyle \alpha _{p}=Prob\{Period~demand\leq \;{Inventory~on~hand~at~the~beginning~of~a~period}\}}
 
.
In order to determine the safety stock that guarantees a target 
 
 
 
 
 α
 
 p
 
 
 
 
 {\displaystyle \alpha _{p}}
 
 service level, the stationary probability distribution of the inventory on hand must be known. This version of α is also called the ready rate.
If an order cycle is considered as the standard period of reference, then α denotes the probability of no stockout within an order cycle which is equal to the proportion of all order cycles with no stockouts (cycle 
 
 
 
 
 α
 
 c
 
 
 
 
 {\displaystyle \alpha _{c}}
 
 service level):

 
 
 
 
 α
 
 c
 
 
 =
 P
 r
 o
 b
 {
 D
 e
 m
 a
 n
 d
 
 d
 u
 r
 i
 n
 g
 
 r
 e
 p
 l
 e
 n
 i
 s
 h
 m
 e
 n
 t
 
 l
 e
 a
 d
 
 t
 i
 m
 e
 ≤
 I
 n
 v
 e
 n
 t
 o
 r
 y
 
 o
 n
 
 h
 a
 n
 d
 
 a
 t
 
 t
 h
 e
 
 b
 e
 g
 i
 n
 n
 i
 n
 g
 
 o
 f
 
 t
 h
 e
 
 l
 e
 a
 d
 
 t
 i
 m
 e
 }
 
 
 {\displaystyle \alpha _{c}=Prob\{Demand~during~replenishment~lead~time\leq Inventory~on~hand~at~the~beginning~of~the~lead~time\}}
 

This second definition, which is often used in operations management textbooks, is based on the idea of not running out of stock during the time between re-ordering and order arrival (the leadtime). That is, the probability of demand during that leadtime being less than or equal to the amount of stock you had left when you ordered. It assumes your reorder point is positive, that orders are in unit increments and inventory is monitored continuously so you cannot stock out prior to reordering.

β service level (type 2)
The β service level is a quantity-oriented performance measure describing the proportion of total demand within a reference period which is delivered without delay from stock on hand:

 
 
 
 β
 =
 1
 −
 
 
 
 E
 x
 p
 e
 c
 t
 e
 d
 
 b
 a
 c
 k
 o
 r
 d
 e
 r
 s
 
 p
 e
 r
 
 t
 i
 m
 e
 
 p
 e
 r
 i
 o
 d
 
 
 E
 x
 p
 e
 c
 t
 e
 d
 
 p
 e
 r
 i
 o
 d
 
 d
 e
 m
 a
 n
 d
 
 
 
 
 
 {\displaystyle \beta =1-{\frac {Expected~backorders~per~time~period}{Expected~period~demand}}}
 

This is equal to the probability that an arbitrary demand unit is delivered without delay. This approach usually involves calculating a loss integral, whose values are tabulated for the normal distribution.
Because, contrary to the variations of the 
 
 
 
 α
 
 
 {\displaystyle \alpha }
 
 service level, the

 
 
 
 β
 
 
 {\displaystyle \beta }
 
 service level does not only reflect the stockout event but also the
amount backordered, it is widely used in industrial practice.
Also, by the definitions, comparing service levels we have 
 
 
 
 α
 ≤
 β
 
 
 {\displaystyle \alpha \leq \beta }
 
 whenever the probability of zero demand equals 0.

γ service level
The γ service level, a time- and quantity-related performance criterion, serves to reflect not only the amount of backorders but also the waiting times of the demands backordered. The γ service level is defined as follows:

 
 
 
 γ
 =
 1
 −
 
 
 
 E
 x
 p
 e
 c
 t
 e
 d
 
 b
 a
 c
 k
 o
 r
 d
 e
 r
 
 l
 e
 v
 e
 l
 
 p
 e
 r
 
 t
 i
 m
 e
 
 p
 e
 r
 i
 o
 d
 
 
 E
 x
 p
 e
 c
 t
 e
 d
 
 p
 e
 r
 i
 o
 d
 
 d
 e
 m
 a
 n
 d
 
 
 
 
 
 {\displaystyle \gamma =1-{\frac {Expected~backorder~level~per~time~period}{Expected~period~demand}}}
 

The γ service level is rarely used in industrial practice.

Service rate
In business, service rate is a performance metric used to measure the customer service in a supply organization. One example of a service rate measures the number of units filled as a percentage of the total ordered and is known as fill rate. Fill rate is different from service level. If a customer orders 1000 units, and their supplier can only provide 900 units of that order, their fill rate is 90%.
In statistics, notably in queuing theory, service rate denotes the rate at which customers are being served in a system. It is the reciprocal of the service time. For example, a supermarket cash desk with an average service time of 30 seconds per customer would have an average service rate of 2 per minute. In statistics the Greek letter 
 
 
 
 μ
 
 
 {\displaystyle \mu }
 
 is used for the service rate.

Terminology
The term "Service Level Agreement" (SLA) is frequently used for all aspects of a service level, but in more precise use one may distinguish:

Service Level Indicator (SLI): measures of service level, like availability (uptime);
Service Level Objective (SLO): objectives based on these indicators, like 99.95% availability;
Service Level Agreement (SLA): contract based on these objectives; a sample clause may be "if availability is 99% to 99.95% in a given month, the customer gets 10% off their monthly bill".
SLIs form the basis of SLOs, which in turn form the basis of SLAs. If an SLO is missed, customers will typically receive a credit or rebate, as stipulated by the SLA. A missed SLO is sometimes casually referred to as an SLA violation, but this is actually within the scope of the SLA; if an SLA itself is violated (e.g., by not giving a rebate for a missed SLO), it is instead likely to result in a court case for breach of contract.

See also
Inventory
Inventory optimization
Service level agreement (SLA)
Service level indicator (SLI)
Service level objective (SLO)
Service level requirement (SLR)
Stockout

References

Further reading
Tempelmeier, Horst, Inventory Management in Supply Networks, Norderstedt (Books on Demand) 2006, ISBN 3-8334-5373-7
How to calculate Fill Rate and On-time In-full Inventory Metrics
