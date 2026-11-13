# Learnable function

- source_key: src_en_tech_0227
- language: en
- domain: tech
- length_bucket: long
- collected_at: 2026-02-22
- url: https://en.wikipedia.org/wiki/Learnable_function

---

A learnable function is a mathematical function that can be learned from data, typically through a machine learning algorithm, to minimize errors and perform a specific task. In the context of statistical learning theory, this refers to a function class where an algorithm can identify a specific function that best approximates the underlying pattern or distribution within the data.
In the domain of database systems, specifically within the emerging field of AI-powered database systems, learnable function is a general concept, representing a paradigm shift where traditional, hard-coded system heuristics are replaced by these parameterized functions. This enables the DBMS to learn, adapt, and govern based on the data it manages. Instead of relying on static rules designed by human experts, database components utilize learnable functions to dynamically adapt to specific data distributions and workloads.

Definition
Fundamentally, a learnable function can be formalized as a mapping 
 
 
 
 f
 :
 
 
 X
 
 
 →
 
 
 Y
 
 
 
 
 {\displaystyle f:{\mathcal {X}}\to {\mathcal {Y}}}
 
, parameterized by a set of weights 
 
 
 
 θ
 
 
 {\displaystyle \theta }
 
. The goal of the learning process is to find the optimal parameters 
 
 
 
 
 θ
 
 ∗
 
 
 
 
 {\displaystyle \theta ^{*}}
 
 that minimize a specific loss function 
 
 
 
 L
 
 
 {\displaystyle L}
 
 over a dataset 
 
 
 
 
 
 D
 
 
 
 
 {\displaystyle {\mathcal {D}}}
 
:

 
 
 
 
 θ
 
 ∗
 
 
 =
 arg
 ⁡
 
 min
 
 θ
 
 
 
 ∑
 
 (
 x
 ,
 y
 )
 ∈
 
 
 D
 
 
 
 
 L
 (
 f
 (
 x
 
 |
 
 θ
 )
 ,
 y
 )
 
 
 {\displaystyle \theta ^{*}=\arg \min _{\theta }\sum _{(x,y)\in {\mathcal {D}}}L(f(x|\theta ),y)}
 

In this framework:

 
 
 
 x
 
 
 {\displaystyle x}
 
 represents the input features (covariates).

 
 
 
 y
 
 
 {\displaystyle y}
 
 represents the target output or label.

 
 
 
 f
 
 
 {\displaystyle f}
 
 is the hypothesis or model (e.g., a linear regression model, a decision tree, or a Neural network).
The "learnability" of the function ensures that as the size of the dataset 
 
 
 
 
 
 D
 
 
 
 
 {\displaystyle {\mathcal {D}}}
 
 increases, the empirical risk converges to the true expected risk, allowing the function to generalize to unseen data.

Formulation in AI-powered Database Systems
In traditional database design, system decisions, such as which index to use, how to order joins, or how to handle transaction conflicts, are governed by static functions, denoted as 
 
 
 
 
 f
 
 s
 t
 a
 t
 i
 c
 
 
 (
 x
 )
 
 
 {\displaystyle f_{static}(x)}
 
. These are typically composed of "if-then" rules and cost models based on general assumptions, e.g., uniform data distribution, established by human engineers.
In the context of AI-powered database systems, 
 
 
 
 
 f
 
 s
 t
 a
 t
 i
 c
 
 
 
 
 {\displaystyle f_{static}}
 
 is replaced by a learnable function 
 
 
 
 
 f
 
 l
 e
 a
 r
 n
 e
 d
 
 
 (
 x
 
 |
 
 θ
 )
 
 
 {\displaystyle f_{learned}(x|\theta )}
 
. This reformulation treats database internals as approximation problems:

Input (
 
 
 
 x
 
 
 {\displaystyle x}
 
): Database states, query syntax, or runtime statistics, e.g., lock contention levels, data cardinality.
Output (
 
 
 
 y
 
 
 {\displaystyle y}
 
): System actions or estimates, e.g., estimated selectivity, optimal concurrency action.
Optimization: The function parameters 
 
 
 
 θ
 
 
 {\displaystyle \theta }
 
 are tuned via methods such as Supervised learning (using query logs) or Reinforcement learning (using runtime feedback).

Implementations in Database Systems
The implementation of learnable functions varies based on the complexity of 
 
 
 
 θ
 
 
 {\displaystyle \theta }
 
 and the inference latency requirements.

Lookup Tables / Discrete Mappings: For low-latency requirements, e.g., concurrency control, 
 
 
 
 f
 (
 x
 
 |
 
 θ
 )
 
 
 {\displaystyle f(x|\theta )}
 
 can be implemented as a learned lookup table where 
 
 
 
 x
 
 
 {\displaystyle x}
 
 is mapped to discrete buckets, and 
 
 
 
 θ
 
 
 {\displaystyle \theta }
 
 represents the stored actions in those buckets.
Classical ML Models: Linear models and Tree-based models (e.g., XGBoost) are often used for cost estimation where interpretability and training speed are balanced.
Deep Learning: Neural networks are employed for high-dimensional mappings, such as cardinality estimation over complex joins, where 
 
 
 
 x
 
 
 {\displaystyle x}
 
 is a vector embedding of the SQL query.

Applications in Learnable Database Components

Learned Concurrency Control
Concurrency Control (CC) algorithms ensure transaction isolation. Traditional algorithms like Two-phase locking (2PL) or Optimistic concurrency control (OCC) perform well in specific scenarios but fail to generalize.
Recent research proposes treating concurrency control as a learnable function.
In such a model, the CC policy can be regarded an agent function:

 
 
 
 F
 :
 {
 s
 }
 →
 {
 a
 }
 
 
 {\displaystyle F:\{s\}\to \{a\}}
 

 
 
 
 s
 
 
 {\displaystyle s}
 
 (State): Features such as data hotness, dependency graph depth, and operation types.

 
 
 
 a
 
 
 {\displaystyle a}
 
 (Action): A combination of conflict detection (e.g., validate read set) and resolution mechanisms (e.g., wait, abort, commit).
Unlike "Classify-then-Assign" approaches which merely select between 2PL and OCC, a learnable function approach can generate hybrid policies by learning the optimal action 
 
 
 
 a
 
 
 {\displaystyle a}
 
 for a specific state 
 
 
 
 s
 
 
 {\displaystyle s}
 
 via Bayesian optimization or generic search, effectively creating a "lookup table" of optimal behaviors that adapts to contention levels.

Learned Query Optimization
In query optimization, the learnable function 
 
 
 
 f
 
 
 {\displaystyle f}
 
 typically replaces the cost model or the cardinality estimator.

Cardinality Estimation: 
 
 
 
 f
 (
 q
 u
 e
 r
 y
 
 |
 
 θ
 )
 →
 r
 o
 w
 _
 c
 o
 u
 n
 t
 
 
 {\displaystyle f(query|\theta )\to row\_count}
 
. Deep learning models can capture correlations between columns that histograms (independence assumption) fail to model.
Cost Modeling: 
 
 
 
 f
 (
 p
 l
 a
 n
 
 |
 
 θ
 )
 →
 l
 a
 t
 e
 n
 c
 y
 
 
 {\displaystyle f(plan|\theta )\to latency}
 
. Learning the latency of physical operators on specific hardware.
The primary advantage of substituting these components with learnable functions is the reduction of estimation errors that propagate during plan enumeration. While traditional optimizers often produce sub-optimal plans due to inaccurate independence assumptions or outdated statistics, learned approaches can optimize for the true runtime metric, e.g., latency, by leveraging historical execution feedback to correct their internal models over time.

Theoretical Perspectives

Learnability vs. Complexity Trade-offs
While learnable functions offer adaptability, they are subject to the No free lunch theorem. A function class 
 
 
 
 
 
 F
 
 
 
 
 {\displaystyle {\mathcal {F}}}
 
 that is too complex, e.g., a large neural network, may overfit to a specific workload history and fail to generalize when the workload drifts (the variance problem). In constrast, a class that is too simple, e.g., linear regression, may fail to capture the non-linear performance characteristics of modern hardware (the bias problem).
This trade-off can be mathematically expressed in the decomposition of risk:

 
 
 
 
 I
 
 P
 
 
 (
 
 
 
 
 f
 ^
 
 
 
 
 n
 
 
 )
 −
 
 inf
 
 f
 ∈
 
 
 
 F
 
 
 
 ∗
 
 
 
 
 
 I
 
 P
 
 
 (
 f
 )
 =
 
 
 
 
 
 I
 
 P
 
 
 (
 
 
 
 
 f
 ^
 
 
 
 
 n
 
 
 )
 −
 
 inf
 
 f
 ∈
 
 
 F
 
 
 
 
 
 I
 
 P
 
 
 (
 f
 )
 
 ⏟
 
 
 
 estimation error
 
 
 +
 
 
 
 
 
 inf
 
 f
 ∈
 
 
 F
 
 
 
 
 
 I
 
 P
 
 
 (
 f
 )
 −
 
 inf
 
 f
 ∈
 
 
 
 F
 
 
 
 ∗
 
 
 
 
 
 I
 
 P
 
 
 (
 f
 )
 
 ⏟
 
 
 
 approximation error
 
 
 
 
 {\displaystyle I_{P}({\hat {f}}_{n})-\inf _{f\in {\mathcal {F}}^{*}}I_{P}(f)=\underbrace {I_{P}({\hat {f}}_{n})-\inf _{f\in {\mathcal {F}}}I_{P}(f)} _{\text{estimation error}}+\underbrace {\inf _{f\in {\mathcal {F}}}I_{P}(f)-\inf _{f\in {\mathcal {F}}^{*}}I_{P}(f)} _{\text{approximation error}}}
 

Effective AI-powered Database systerms must balance the approximation error (using rich models like Neural Networks) against the estimation error (requiring vast amounts of training data and stability).

The Bitter Lesson and Scalability
The move toward learnable functions in databases can be discussed from the perspective of "The Bitter Lesson" by Richard Sutton, which argues that general methods that leverage computation (search and learning) ultimately outperform methods that rely on human knowledge (heuristics).
In databases, a handcrafted cost model (human knowledge) is limited by the designer's foresight. A learnable function, however, scales with the availability of computation and training data (query logs), and hence, theoretically allows the database to asymptotically approach the performance of a theoretically optimal system, often referred to as an oracle machine with perfect information.

History and Development
The study of learnable functions emerged from the intersection of biology and cybernetics in the mid-20th century, specifically driven by the need to understand how organisms adapt to complex environments. Early research focused on perceptron learning algorithms for linear threshold operations and learning in random networks. In the 1960s and 1970s, researchers like Marvin Minsky, Oliver Selfridge, and Seymour Papert laid the groundwork for modern machine learning by contrasting the immense complexity of general Boolean functions against the learnability of specialized classes. Concurrently, classical approximation theories for continuous real-valued functions were further developed to provide mathematical rigor to the concept of function reconstruction. A subsequent formalization occurred in 1973 when Andrzej Ehrenfeucht and Jan Mycielski introduced the concept of 
 
 
 
 k
 
 
 {\displaystyle k}
 
-continuity and addressing functions. Their work on the interpolation of functions over a measure space formalized how a learner can efficiently search for a small number of relevant features within a high-dimensional data input. This perspective has also extended to neuromorphic engineering, where research demonstrates how functional specialization emerges directly from network structure.
In the contemporary landscape of artificial intelligence and database systems, the concept of learnable functions has transitioned from theoretical classification toward the autonomous optimization of core system internals, such as query optimization and concurrency control. A prominent example is the CCaaLF framework, which treats concurrency control as a learnable agent function 
 
 
 
 
 
 F
 
 
 :
 {
 s
 }
 →
 {
 a
 }
 
 
 {\displaystyle {\mathcal {F}}:\{s\}\rightarrow \{a\}}
 
. This function dynamically maps real-time database states to specific conflict-handling actions.

See also
Regularization
Database tuning
Learnable function class
 Filter and refine principle
Automated machine learning

References

External links
Self Driving Database
