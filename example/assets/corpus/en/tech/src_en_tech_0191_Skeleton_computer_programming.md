# Skeleton (computer programming)

- source_key: src_en_tech_0191
- language: en
- domain: tech
- length_bucket: long
- collected_at: 2026-02-22
- url: https://en.wikipedia.org/wiki/Skeleton_(computer_programming)

---

Skeleton programming is a style of computer programming based on simple high-level program structures and so called dummy code. Program skeletons resemble pseudocode, but allow parsing, compilation and testing of the code. Dummy code is inserted in a program skeleton to simulate processing and avoid compilation error messages. It may involve empty function declarations, or functions that return a correct result only for a simple test case where the expected response of the code is known.
Skeleton programming facilitates a top-down design approach, where a partially functional system with complete high-level structures is designed and coded, and this system is then progressively expanded to fulfill the requirements of the project. Program skeletons are also sometimes used for high-level descriptions of algorithms. A program skeleton may also be utilized as a template that reflects syntax and structures commonly used in a wide class of problems.
Skeleton programs are utilized in the template method design pattern used in object-oriented programming. In object-oriented programming, dummy code corresponds to an abstract method, a method stub or a mock object. In the Java remote method invocation (Java RMI) nomenclature, a stub communicates on the client-side with a skeleton on the server-side.
A class skeleton is an outline of a class that is used in software engineering. It contains a description of the class's roles, and describes the purposes of the variables and methods, but does not implement them. The class is later implemented from the skeleton. The skeleton can also be known as either an interface or an abstract class, with languages that follow a polymorphic paradigm.

Background
Modern software is often complicated due to a host of reasons. This can mean that not just a single programmer can develop it, or that other modules or parts have to be separately imported. The programs can also be too complex on their own, some with multiple methods accessing a single variable at the same time or even generating pixels for displays. Skeleton code is used to assist programmers to develop their code with the fewest errors during the time of compilation.
Skeleton code is most commonly found in parallel programming, but is also applied in other situations, like documentation in programming languages. This helps to simplify the core functionality of a potentially confusing method. It can also be used to allow for a small function within a larger program to operate without full functionality temporarily.
This method of programming is easier than writing a complete function, as these skeleton functions do not have to include main functionalities and can instead be hardcoded to use during development. They usually involve syntactically correct code to introduce the method, as well as comments to indicate the operation of the program. This is not always necessary to call a piece of text skeleton code.

Relation to pseudocode

Pseudocode is most commonly found when developing the structure of a new piece of software. It is a plain English portrayal of a particular function within a larger system, or can even be a representation of a whole program. Pseudocode is similar to skeleton programming, however deviates in the fact that pseudocode is primarily an informal method of programming. Dummy code is also very similar to this, where code is used simply as a placeholder, or to signify the intended existence of a method in a class or interface.
Computer programmers are extremely dependent on pseudocode, so much so that it has a measurable impact on their psyche. A typical programmer is so conditioned with the idea of writing simplified code in some manner, be it by writing pseudocode or skeleton code, or even just by drawing a diagram, that this has a measurable impact on how well they can write their final implementation. This has been found over a number of applications, with different programmers working in different languages and varied programming paradigms.
This method of program design is also most often done on pen and paper, further moving the text from what is actually to be implemented. Skeleton programming mimics this, but differs in the way that it is commonly written in an integrated development environment, or text editors. This assists the further development of the program after the initial design stage. Skeleton programs also allow for simplistic functions to operate, if run.

Implementation
Skeleton programming can be implemented in a range of different programming applications.

Programming language documentation
Most, if not all programming languages have skeleton code used to assist in the definition of all built-in functions and methods. This provides a simple means for newer programmers to understand the syntax and intended implementation of the written methods.
Java, an object oriented language, focuses heavily on a structured documentation page with completely separated methods for each object part of Java's packages. Object oriented languages focus on a hierarchy based structure to their implementations, rather than a simple top-down approach found in other languages. ‘Objects’ store data and variables in them, allowing for a typically more efficient program to be written. These objects have individual functions that can access internal variables, known as methods.
Each method is defined in the same format, with the name of the method as well as the syntax to be used in an integrated development environment clearly visible at the top of a block. With Java's focus on scope, data types and inheritance, this syntax is extremely useful for new, if not all programmers. This is followed by an in-depth explanation of the operation of the method, with errors below.
Python has a similar approach to document its in-built methods, however mimics the language's lack of fixation on scope and data types. This documentation has the syntax of each method, along with a short description and an example of the typical use of the method or function. The skeleton code provided in the example gives programmers a good understanding of the function at a quick glance.

Class definition
Classes written by third-party developers, primarily as a part of libraries, also showcase their programming in the form of skeleton code. This helps to inform any that are new to the library as to how the functions and methods operate. P5.Js uses this format on their documentation page to explain the intended use of certain included functions. This is different to the programming language documentation however, using skeleton code to display parameters rather than all possible uses of the method.
Natural Language Interfaces (NLIs) are most typically found in situations where programmers attempt to take an input, usually colloquially termed (without the use of programming language specific jargon) and use this to create a program or a method. An implementation of this uses a small set of skeleton code to imply the function running in the background.
Other forms of NLIs use different forms of input, ranging from other users speaking different languages, to gesture based input to produce a very similar result. With programming languages being developed and written primarily in English, people speaking other languages find it hard to develop new software. NLIs have been used in some studies to assist people in these situations. The study showed classes written in Java through the use of NLIs. This removed the need for learning syntactical rules, however meant that the class was written using a basic set of skeleton code.

Polymorphism-based definitions
Polymorphism is an ideology that follows with the object-oriented programming paradigm, where methods can be overridden or overloaded (methods with the same name in a child class which will take priority over a method written in a parent class). The definition of methods is based on a skeleton framework defined by the syntax of the language.
Very similar to class implementation, skeleton code can be used to define the methods that are part of an interface. An interface is essentially a blueprint of a class, which allows for strict object oriented languages (such as Java) to use classes from different packages without the need to fully understand the internal functions. Interfaces simply define the methods that have to be present within the class, allowing anyone else to use the methods or implement the class for their personal needs

An abstract class is almost the same as a class implementation, however depending on the language, at least one method is defined as abstract. This implies that any children of this class (any classes that extend or implement) need to have a method defined for this. Abstract classes have a very similar definition style to interfaces, however a keyword ‘abstract’ is typically used to identify the fact that it needs to be implemented in child classes.

These examples use the Java syntax.

Parallel programming
Parallel programming is the operation of multiple functions simultaneously most commonly used to increase efficiency. These are typically the hardest types of programs to develop, due to their complexity and interconnectedness with the hardware in question as well. Many developers have attempted to write programs with this core functionality, however this has been met by varied results.
Algorithmic skeleton frameworks are used in parallel programming to abstractly describe the methods in question for later development. The frameworks are not limited to a single type, and each of these types have different purposes to increase the efficiency of the developer's program. These can be categorised into three main types: data-parallel, task-parallel and resolution.

Data-parallel
These skeleton algorithms are used to develop programs that work on large data based software, usually identifying the connections between data for later use. Data parallel algorithms include ‘maps’, ‘forks’ and ‘reduces’ or ‘scans’.

‘Maps’ are the most commonly used data parallel algorithms, and typically involve a single operation completed on a large set of data. To increase efficiency, a number of data sets have this operation applied to them simultaneously, before the data is structured together again at the end.
‘Forks’ are similar to ‘maps’ but they use a different operation for certain data types. This is known as multiple data parallelism.
‘Reduces’ or ‘scans’ are used to apply prefixes to a set of data, before then applying an operation upon the data. These are different to ‘maps’ as they have a set of partial results during the runtime of the method itself.

Task-parallel
These operations, as their name suggests, work on tasks. Each type of algorithm under this is different due to a change in the behaviour between tasks. Task parallel algorithms include ‘sequentials’, ‘farms’, ‘pipes’, ‘if’, ‘for’ and ‘while’.

‘Sequential’ closes and terminates a nested set of skeleton algorithms. The methods and programs that are part of the skeletons are included as terminating aspects of the program, before closing.
‘Farms’ are known as a group of tasks, a worker, or as a master or slave of another function. It completes the given tasks by replicating the tasks over multiple threads and running these concurrently. This divides the load for a specific thread, effectively creating a master / slave relationship between the threads.
‘Pipes’ are the more traditional forms of algorithms, where each method or function is run in a sequence. This follows the order in which the programmer has written their code. This is made parallel by computing varied tasks on a set of data, typically input, simultaneously to improve performance and speed. Each simultaneous computation is known as a stage. The pipe algorithm can be nested, where one is within another, each splitting up responsibilities to increase speed and also the number of stages.
‘If’ gives the program a conditional split of tasks, where a set of skeleton code is split into two main sections. A conditional statement is given to the program, therefore giving it a specified algorithm to follow.
‘For’ operates a task a number of times, both specified by the programmer, allowing for a more efficient set of code. The number of times that the code runs is a preset value, indicating that at runtime, this cannot be changed. It must complete the task the number of times given.
‘While’ is an algorithm very similar to the operation of a ‘for’ algorithm, where a task is completed a number of times. However, in ‘while’ algorithms, the program computes the task a number of times before a conditional statement is met. This means that the ‘while’ algorithm can perform its task a different number of times for each time it is run.

Resolution skeletons
These skeletons are very different to the typical skeletons found above. ‘Resolution’ algorithms use a combination of methods to solve a specified problem. The algorithm's given problem can be a “family of problems”. There are two main types of these skeletons, ‘divide and conquer’ or ‘brand and bound’.

‘Divide and conquer’ uses a map skeleton as its basis, combining this with a while skeleton to solve the problem. In map algorithms, functions on data are applied simultaneously. In ‘divide and conquer’ the set of data provided has a function applied to it using the map skeleton, however this can be applied recursively using the ‘while’ algorithm. The ‘while’ is only broken when the entire problem is solved.
‘Branch and bound’ is an algorithm that also uses map algorithms, however instead of applying the ‘while’ algorithm to run the tasks simultaneously, this algorithm splits the tasks into branches. Each branch has a specific purpose, or ‘bound’, where the conditional statement will cause it to stop.

References
