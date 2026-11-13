# Metal casting simulation

- source_key: src_en_tech_0247
- language: en
- domain: tech
- length_bucket: long
- collected_at: 2026-02-22
- url: https://en.wikipedia.org/wiki/Metal_casting_simulation

---

Casting process simulation is a computational technique used in industry and metallurgy to model and analyze the metal-casting process. This technology allows engineers to predict and visualize the flow of molten metal, crystallization patterns, and potential defects in the casting before the start of the actual production process. By simulating the casting process, manufacturers can optimize mold design, reduce material consumption, and improve the quality of the final product.

History

The theoretical foundations of heat conduction, critically important for casting simulation, were established by Jean-Baptiste Joseph Fourier at the École polytechnique in Paris. His thesis "Analytical Theory of Heat," awarded in 1822, laid the groundwork for all subsequent calculations of heat conduction and heat transfer in solid materials. Additionally, French physicist and engineer Claude-Louis Navier and Irish mathematician and physicist George Gabriel Stokes provided the foundations of fluid dynamics, which led to the development of the Navier-Stokes equations. Adolph Fick, working in the 19th century at the University of Zurich, developed the fundamental equations describing diffusion, published in 1855.
The beginning of simulation in casting started in the 1950s when V. Pashkis used analog computers to predict the movement of the crystallization front. The first use of digital computers to solve problems related to casting was carried out by Dr K. Fursund in 1962, who considered the penetration of steel into a sand mold. A pioneering work by J. G. Hentzel and J. Keverian in 1965 was the two-dimensional simulation of the crystallization of steel castings, using a program developed by General Electric to simulate heat transfer. In 1968, Ole Vestby was the first to use the finite difference method to program a 2D model that evaluated the temperature distribution during welding.
The 1980s marked a significant increase in research and development activities around the topic of casting process simulation with contributions from various international groups, including J. T. Berry and R. D. Pielke in the United States, E. Niyama in Japan, W. Kurz in Lausanne, and F. Durand in Grenoble. An especially important role in advancing this field was played by Professor P. R. Sahm at the Aachen Foundry Institute. Key milestones of this period were the introduction of the "criterion function" by Hansen and Berry in 1980, the Niyama criterion function for the representation of central porosities in 1982, and the proposal of a criterion function for the detection of hot cracks in steel castings by E. Fehlner and P. N. Hansen in 1984. In the late 1980s, the first capabilities for simulating mold filling were developed.
The 1990s focused on the simulation of stresses and strains in castings with significant contributions from Hattel and Hansen in 1990. This decade also saw efforts to predict microstructures and mechanical properties with the pioneering work of I. Svensson and M. Wessen in Sweden.

Principles of casting simulation

The production of casting is one of the most complex and multifaceted processes in metallurgy, requiring careful control and an understanding of a multitude of physical and chemical phenomena. To effectively manage this process and ensure the high quality of the final products, it is essential to have a deep understanding of the interaction of the various casting parameters. In this context, the mathematical modeling of casting acts as a critically important scientific tool, allowing for detailed analysis and optimization of the casting process based on mathematical principles.
Mathematical modeling of casting is a complex process that involves the formulation and solution of mathematical equations that describe physical phenomena such as thermal conductivity, fluid dynamics, phase transformations, among others. To solve these equations, various numerical analysis methods are applied, among which the finite element method (FEM), finite difference method (FDM), and finite volume method (FVM) hold a special place. Each of these methods has its particular characteristics and is applied depending on the specific modeling tasks and the requirements for precision and efficiency in the calculations.
Finite difference method (FDM): This method is based on differential equations of heat and mass transfer, which are approximated using finite difference relationships. The advantage of the FDM is its simplicity and the ability to simplify the solution of multidimensional problems. However, the method has limitations in modeling the boundaries of complex areas and performs poorly for castings with thin walls.
The finite element method and Finite volume method (FVM): Both methods are based on integral equations of heat and mass transfer. They provide a good approximation of the boundaries and allow the use of elements with different discretizations. The main drawbacks are the need for a finite element generator, the complexity of the equations, and large requirements for memory and time resources.
Modifications of the FVM: These methods attempt to combine the simplicity of the FDM with a good approximation of the boundaries of the FEM. They have the potential to improve the approximation of boundaries between different materials and phases.
The analysis of different methods of mathematical modeling of casting processes shows that the finite element method is one of the most reliable and optimal approaches for casting simulation. Despite higher computational resource requirements and complexity in implementation compared to the finite difference method and finite volume method, the FEM provides high accuracy in modeling boundaries, complex geometries, and temperature fields, which is critically important for predicting defects in castings and optimizing casting processes.

Application in production
Computer-aided engineering (CAE) systems for casting processes have long been used by foundries around the world as a "virtual foundry workshop," where it is possible to perform and verify any idea that arises in the minds of designers and technologists. The global market for CAE for casting processes can already be considered established.
Within the structure of the company for the development of the technology of a new casting, a computer-aided design department for casting processes is created, responsible for operating CAE systems for casting processes. Calculations are carried out by specialists of the department according to their job instructions, and interaction with other departments is regulated by technological design instructions.
The process begins with the delivery of the 3D model and drawing of the part to the foundry technologists, who coordinate the casting configuration with the mechanical workshop and determine the margins. Then, the technology is developed in the CAE department and transferred to the foundry workshop for experimental castings. The results are monitored, and if necessary, the castings are examined in the central laboratory of the factory. If defects are detected, an adjustment of the model parameters and the technological process is made in the CAE department, after which the technology is tested again in the workshop.
This cycle is repeated until suitable castings are obtained, after which the technology is considered developed and implemented in mass production.

Software and tools

In the modern foundry industry, software for the simulation of casting processes is widely used. Among the multitude of software solutions available, it is worth mentioning the most prominent and widely used products: Procast, MAGMASOFT, and PoligonSoft.
ProCAST: a casting process modeling system using the finite element method, which provides the joint solution of temperature, hydrodynamics, and deformation problems, along with unique metallurgical capabilities, for all casting processes and casting alloys. In addition to the main aspects of casting production – filling, crystallization, and porosity prediction, ProCAST is capable of predicting the occurrence of deformations and residual stresses in the casting and can be used to analyze processes such as core making, centrifugal casting, lost wax casting, continuous casting.
PoligonSoft: a casting process modeling system using the finite element method. Applicable for modeling almost any casting technology and any casting alloy. For a long time, PoligonSoft was the only casting process modeling system in the world that included a special model for calculating microporosity. To date, this model can be considered the most stable, and the results obtained with its help can satisfy the most demanding users. In many respects, PoligonSoft can be considered the Russian equivalent of the ProCAST system.
MAGMASOFT: a casting process modeling system using the finite difference method. It allows analyzing thermal processes, mold filling, crystallization, and predicting defects in castings. The program includes modules for different casting technologies and helps optimize casting parameters to improve product quality. MAGMASOFT is an effective tool for increasing the productivity and quality of casting production.

Future trends
The simulation of the casting process reflects the user's knowledge, who decides whether the filling system has led to an acceptable result. Optimization suggestions must come from the operator. The main problem is that all processes occur simultaneously and are interconnected: changes in one parameter affect many quality characteristics of the casting.
Autonomous optimization, which began in the late 1980s, uses the simulation tool as a virtual testing ground, changing filling conditions and process parameters to find the optimal solution. This allows evaluating numerous process parameters and their impact on process stability.
It is important to remember that only what can be modeled can be optimized. Optimization does not replace process knowledge or experience. The simulation user must know the objectives and quality criteria necessary to achieve those objectives and formulate specific questions to the program to obtain quantitative solutions.

See also
Alloy – Mixture or metallic solid solution composed of two or more elements
Casting – Manufacturing process in which a liquid is poured into a mold to solidify
Metal – Type of material
Metal casting – Pouring liquid metal into a mold

References

External links
Сasting simulation software
The efficiency of multithreaded computing in casting simulation software
