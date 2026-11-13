# Software

- source_key: src_en_tech_0203
- language: en
- domain: tech
- length_bucket: long
- collected_at: 2026-02-22
- url: https://en.wikipedia.org/wiki/Software

---

Software consists of computer programs that instruct the execution of a computer. Software also includes design documents and specifications.
The history of software is closely tied to the development of digital computers in the mid-20th century. Early programs were written in the machine language specific to the hardware. The introduction of high-level programming languages in 1958 allowed for more human-readable instructions, making software development easier and more portable across different computer architectures. Software in a programming language is run through a compiler or interpreter to execute on the architecture's hardware. Over time, software has become complex, owing to developments in networking, operating systems, and databases.
Software can generally be categorized into two main types:

operating systems, which manage hardware resources and provide services for applications
application software, which performs specific tasks for users
The rise of cloud computing has introduced the new software delivery model Software as a Service (SaaS). In SaaS, applications are hosted by a provider and accessed over the Internet.
The process of developing software involves several stages. The stages include software design, programming, testing, release, and maintenance. Software quality assurance and security are critical aspects of software development, as bugs and security vulnerabilities can lead to system failures and security breaches. Additionally, legal issues such as software licenses and intellectual property rights play a significant role in the distribution of software products.

History

]]
The first use of the word software to describe computer programs is credited to mathematician John Wilder Tukey in 1958. The first programmable computers, which appeared at the end of the 1940s, were programmed in machine language. Machine language is difficult to debug and not portable across different computers. Initially, hardware resources were more expensive than human resources. As programs became complex, programmer productivity became the bottleneck. The introduction of high-level programming languages in 1958 hid the details of the hardware and expressed the underlying algorithms into the code. Early languages include Fortran, Lisp, and COBOL.

Types

There are two main types of software:

Operating systems are "the layer of software that manages a computer's resources for its users and their applications". There are three main purposes that an operating system fulfills:
Allocating resources between different applications, deciding when they will receive central processing unit (CPU) time or space in memory.
Providing an interface that abstracts the details of accessing hardware details (like physical memory) to make things easier for programmers.
Offering common services, such as an interface for accessing network and disk devices. This enables an application to be run on different hardware without needing to be rewritten.
Application software runs on top of the operating system and uses the computer's resources to perform a task. There are many different types of application software because the range of tasks that can be performed with modern computers is so large. Applications account for most software and require the environment provided by an operating system, and often other applications, in order to function.

Software can also be categorized by how it is deployed. Traditional applications are purchased with a perpetual license for a specific version of the software, downloaded, and run on hardware belonging to the purchaser. The rise of the Internet and cloud computing enabled a new model, software as a service (SaaS), in which the provider hosts the software (usually built on top of rented infrastructure or platforms) and provides the use of the software to customers, often in exchange for a subscription fee. By 2023, SaaS products—which are usually delivered via a web application—had become the primary method that companies deliver applications.

Software development and maintenance

Software companies aim to deliver a high-quality product on time and under budget. A challenge is that software development effort estimation is often inaccurate. Software development begins by conceiving the project, evaluating its feasibility, analyzing the business requirements, and making a software design. Most software projects speed up their development by reusing or incorporating existing software, either in the form of commercial off-the-shelf (COTS) or open-source software. Software quality assurance is typically a combination of manual code review by other engineers and automated software testing. Due to time constraints, testing cannot cover all aspects of the software's intended functionality, so developers often focus on the most critical functionality. Formal methods are used in some safety-critical systems to prove the correctness of code, while user acceptance testing helps to ensure that the product meets customer expectations. There are a variety of software development methodologies, which vary from completing all steps in order to concurrent and iterative models. Software development is driven by requirements taken from prospective users, as opposed to maintenance, which is driven by events such as a change request.
Frequently, software is released in an incomplete state when the development team runs out of time or funding. Despite testing and quality assurance, virtually all software contains bugs where the system does not work as intended. Post-release software maintenance is necessary to remediate these bugs when they are found and keep the software working as the environment changes over time. New features are often added after the release. Over time, the level of maintenance becomes increasingly restricted before being cut off entirely when the product is withdrawn from the market. As software ages, it becomes known as legacy software and can remain in use for decades, even if there is no one left who knows how to fix it. Over the lifetime of the product, software maintenance is estimated to comprise 75 percent or more of the total development cost.
Completing a software project involves various forms of expertise, not just in software programmers but also testing, documentation writing, project management, graphic design, user experience, user support, marketing, and fundraising.

Quality and security

Software quality is defined as meeting the stated requirements as well as customer expectations. Quality is an overarching term that can refer to a code's correct and efficient behavior, its reusability and portability, or the ease of modification. It is usually more cost-effective to build quality into the product from the beginning rather than try to add it later in the development process. Higher quality code will reduce lifetime cost to both suppliers and customers as it is more reliable and easier to maintain. Software failures in safety-critical systems may result in serious harm, including injury or death. By some estimates, the cost of poor quality software can be as high as 20 to 40 percent of sales. Despite developers' goal of delivering a product that works entirely as intended, virtually all software contains bugs.
The rise of the Internet also greatly increased the need for computer security as it enabled malicious actors to conduct cyberattacks remotely. If a bug creates a security risk, it is called a vulnerability. Software patches are often released to fix identified vulnerabilities, but those that remain unknown (zero days) as well as those that have not been patched are still liable for exploitation. Vulnerabilities vary in their ability to be exploited by malicious actors, and the actual risk is dependent on the nature of the vulnerability as well as the value of the surrounding system. Although some vulnerabilities can only be used for denial of service attacks that compromise a system's availability, others allow the attacker to inject and run their own code (called malware), without the user being aware of it. To thwart cyberattacks, all software in the system must be designed to withstand and recover from external attack. Despite efforts to ensure security, a significant fraction of computers are infected with malware.

Encoding and execution

Programming languages

Programming languages are the format in which software is written. Since the 1950s, thousands of different programming languages have been invented; some have been in use for decades, while others have fallen into disuse. Some definitions classify machine code—the exact instructions directly implemented by the hardware—and assembly language—a more human-readable alternative to machine code whose statements can be translated one-to-one into machine code—as programming languages. Programs written in the high-level programming languages used to create software share a few main characteristics: knowledge of machine code is not necessary to write them, they can be ported to other computer systems, and they are more concise and human-readable than machine code. They must be both human-readable and capable of being translated into unambiguous instructions for computer hardware.

Compilation, interpretation, and execution
The invention of high-level programming languages was simultaneous with the compilers needed to translate them automatically into machine code. Most programs do not contain all the resources needed to run them and rely on external libraries. Part of the compiler's function is to link these files in such a way that the program can be executed by the hardware. Once compiled, the program can be saved as an object file and the loader (part of the operating system) can take this saved file and execute it as a process on the computer hardware. Some programming languages use an interpreter instead of a compiler. An interpreter converts the program into machine code at run time, which makes them 10 to 100 times slower than compiled programming languages.

Legal issues

Liability

Software is often released with the knowledge that it is incomplete or contains bugs. Purchasers knowingly buy it in this state, which has led to a legal regime where liability for software products is significantly curtailed compared to other products.

Licenses

Since the mid-1970s, software and its source code have been protected by copyright law that vests the owner with the exclusive right to copy the code. The underlying ideas or algorithms are not protected by copyright law, but are sometimes treated as a trade secret and concealed by such methods as non-disclosure agreements. A software copyright is often owned by the person or company that financed or made the software (depending on their contracts with employees or contractors who helped to write it). Some software is in the public domain and has no restrictions on who can use it, copy or share it, or modify it; a notable example is software written by the United States Government. Free and open-source software also allow free use, sharing, and modification, perhaps with a few specified conditions. The use of some software is governed by an agreement (software license) written by the copyright holder and imposed on the user. Proprietary software is usually sold under a restrictive license that limits its use and sharing. Some free software licenses require that modified versions must be released under the same license, which prevents the software from being sold
or distributed under proprietary restrictions.

Patents

Patents give an inventor an exclusive, time-limited license for a novel product or process. Ideas about what software could accomplish are not protected by law and concrete implementations are instead covered by copyright law. In some countries, a requirement for the claimed invention to have an effect on the physical world may also be part of the requirements for a software patent to be held valid. Software patents have been historically controversial. Before the 1998 case State Street Bank & Trust Co. v. Signature Financial Group, Inc., software patents were generally not recognized in the United States. In that case, the Supreme Court decided that business processes could be patented. Patent applications are complex and costly, and lawsuits involving patents can drive up the cost of products. Unlike copyrights, patents generally only apply in the jurisdiction where they were issued.

Impact

Engineer Capers Jones writes that "computers and software are making profound changes to every aspect of human life: education, work, warfare, entertainment, medicine, law, and everything else". It has become ubiquitous in everyday life in developed countries. In many cases, software augments the functionality of existing technologies such as household appliances and elevators. Software also spawned entirely new technologies such as the Internet, video games, mobile phones, and GPS. New methods of communication, including email, forums, blogs, microblogging, wikis, and social media, were enabled by the Internet. Massive amounts of knowledge exceeding any paper-based library are now available with a quick web search. Most creative professionals have switched to software-based tools such as computer-aided design, 3D modeling, digital image editing, and computer animation. Almost every complex device is controlled by software.

References

Sources
