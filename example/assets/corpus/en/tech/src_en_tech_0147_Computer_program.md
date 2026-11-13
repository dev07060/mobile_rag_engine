# Computer program

- source_key: src_en_tech_0147
- language: en
- domain: tech
- length_bucket: long
- collected_at: 2026-02-22
- url: https://en.wikipedia.org/wiki/Computer_program

---

A computer program is a sequence or set of instructions in a programming language for a computer to execute. It is one component of software, which also includes documentation and other intangible components.
A computer program in its human-readable form is called source code. Source code needs another computer program to execute because computers can only execute their native machine instructions. Therefore, source code may be translated to machine instructions using a compiler written for the language. (Assembly language programs are translated using an assembler.) The resulting file is called an executable. Alternatively, source code may execute within an interpreter written for the language.
If the executable is requested for execution, then the operating system loads it into memory and starts a process. The central processing unit will soon switch to this process so it can fetch, decode, and then execute each machine instruction.
If the source code is requested for execution, then the operating system loads the corresponding interpreter into memory and starts a process. The interpreter then loads the source code into memory to translate and execute each statement. Running the source code is slower than running an executable. Moreover, the interpreter must be installed on the computer.

Example computer program
The "Hello, World!" program is used to illustrate a language's basic syntax. The syntax of the language BASIC (1964) was intentionally limited to make the language easy to learn. For example, variables are not declared before being used. Also, variables are automatically initialized to zero. Here is an example computer program, in Basic, to average a list of numbers:

Once the mechanics of basic computer programming are learned, more sophisticated and powerful languages are available to build large computer systems.

History

Improvements in software development are the result of improvements in computer hardware. At each stage in hardware's history, the task of computer programming changed dramatically.

Analytical Engine

In 1837, Jacquard's loom inspired Charles Babbage to attempt to build the Analytical Engine.
The names of the components of the calculating device were borrowed from the textile industry. In the textile industry, yarn was brought from the store to be milled. The device had a store which consisted of memory to hold 1,000 numbers of 50 decimal digits each. Numbers from the store were transferred to the mill for processing. The engine was programmed using two sets of perforated cards. One set directed the operation and the other set inputted the variables. However, the thousands of cogged wheels and gears never fully worked together.
Ada Lovelace worked for Charles Babbage to create a description of the Analytical Engine (1843). The description contained Note G which completely detailed a method for calculating Bernoulli numbers using the Analytical Engine. This note is recognized by some historians as the world's first computer program.

Universal Turing machine

In 1936, Alan Turing introduced the Universal Turing machine, a theoretical device that can model every computation.
It is a finite-state machine that has an infinitely long read/write tape. The machine can move the tape back and forth, changing its contents as it performs an algorithm. The machine starts in the initial state, goes through a sequence of steps, and halts when it encounters the halt state. All present-day computers are Turing complete.

ENIAC

The Electronic Numerical Integrator And Computer (ENIAC) was built between July 1943 and Fall 1945. It was a Turing complete, general-purpose computer that used 17,468 vacuum tubes to create the circuits. At its core, it was a series of Pascalines wired together. Its 40 units weighed 30 tons, occupied 1,800 square feet (167 m2), and consumed $650 per hour (in 1940s currency) in electricity when idle. It had 20 base-10 accumulators. Programming the ENIAC took up to two months. Three function tables were on wheels and needed to be rolled to fixed function panels. Function tables were connected to function panels by plugging heavy black cables into plugboards. Each function table had 728 rotating knobs. Programming the ENIAC also involved setting some of the 3,000 switches. Debugging a program took a week. It ran from 1947 until 1955 at Aberdeen Proving Ground, calculating hydrogen bomb parameters, predicting weather patterns, and producing firing tables to aim artillery guns.

Stored-program computers
Instead of plugging in cords and turning switches, a stored-program computer loads its instructions into memory just like it loads its data into memory. As a result, the computer could be programmed quickly and perform calculations at very fast speeds. Presper Eckert and John Mauchly built the ENIAC. The two engineers introduced the stored-program concept in a three-page memo dated February 1944. Later, in September 1944, John von Neumann began working on the ENIAC project. On June 30, 1945, von Neumann published the First Draft of a Report on the EDVAC, which equated the structures of the computer with the structures of the human brain. The design became known as the von Neumann architecture. The architecture was simultaneously deployed in the constructions of the EDVAC and EDSAC computers in 1949.
The IBM System/360 (1964) was a family of computers, each having the same instruction set architecture. The Model 20 was the smallest and least expensive. Customers could upgrade and retain the same application software. The Model 195 was the most premium. Each System/360 model featured multiprogramming—having multiple processes in memory at once. When one process was waiting for input/output, another could compute.
IBM planned for each model to be programmed using PL/I. A committee was formed that included COBOL, FORTRAN and ALGOL programmers. The purpose was to develop a language that was comprehensive, easy to use, extendible, and would replace COBOL and FORTRAN. The result was a large and complex language that took a long time to compile.

Computers manufactured until the 1970s had front-panel switches for manual programming. The computer program was written on paper for reference. An instruction was represented by a configuration of on/off settings. After setting the configuration, an execute button was pressed. This process was then repeated. Computer programs also were automatically inputted via paper tape, punched cards or magnetic-tape. After the medium was loaded, the starting address was set via switches, and the execute button was pressed.

Very Large Scale Integration

A major milestone in software development was the invention of the Very Large Scale Integration (VLSI) circuit (1964).
Robert Noyce, co-founder of Fairchild Semiconductor (1957) and Intel (1968), achieved a technological improvement to refine the production of field-effect transistors (1963). The goal is to alter the electrical resistivity and conductivity of a semiconductor junction. First, naturally occurring silicate minerals are converted into polysilicon rods using the Siemens process. The Czochralski process then converts the rods into a monocrystalline silicon, boule crystal. The crystal is then thinly sliced to form a wafer substrate. The planar process of photolithography then integrates unipolar transistors, capacitors, diodes, and resistors onto the wafer to build a matrix of metal–oxide–semiconductor (MOS) transistors. The MOS transistor is the primary component in integrated circuit chips.
Originally, integrated circuit chips had their function set during manufacturing. During the 1960s, controlling the electrical flow migrated to programming a matrix of read-only memory (ROM). The matrix resembled a two-dimensional array of fuses. The process to embed instructions onto the matrix was to burn out the unneeded connections. There were so many connections, firmware programmers wrote a computer program on another chip to oversee the burning. The technology became known as Programmable ROM. In 1971, Intel installed the computer program onto the chip and named it the Intel 4004 microprocessor.

The terms microprocessor and central processing unit (CPU) are now used interchangeably. However, CPUs predate microprocessors. For example, the IBM System/360 (1964) had a CPU made from circuit boards containing discrete components on ceramic substrates.

x86 series

In 1978, the modern software development environment began when Intel upgraded the Intel 8080 to the Intel 8086. Intel simplified the Intel 8086 to manufacture the cheaper Intel 8088. IBM embraced the Intel 8088 when they entered the personal computer market (1981). As consumer demand for personal computers increased, so did Intel's microprocessor development. The succession of development is known as the x86 series. The x86 assembly language is a family of backward-compatible machine instructions. Machine instructions created in earlier microprocessors were retained throughout microprocessor upgrades. This enabled consumers to purchase new computers without having to purchase new application software. The major categories of instructions are:

Memory instructions to set and access numbers and strings in random-access memory.
Integer arithmetic logic unit (ALU) instructions to perform the primary arithmetic operations on integers.
Floating point ALU instructions to perform the primary arithmetic operations on real numbers.
Call stack instructions to push and pop words needed to allocate memory and interface with functions.
Single instruction, multiple data (SIMD) instructions to increase speed when multiple processors are available to perform the same algorithm on an array of data.

Changing programming environment

VLSI circuits enabled the programming environment to advance from a computer terminal (until the 1990s) to a graphical user interface (GUI) computer. Computer terminals limited programmers to a single shell running in a command-line environment. During the 1970s, full-screen source code editing became possible through a text-based user interface. Regardless of the technology available, the goal is to program in a programming language.

Programming paradigms and languages
Programming language features exist to provide building blocks to be combined to express programming ideals. Ideally, a programming language should:

express ideas directly in the code.
express independent ideas independently.
express relationships among ideas directly in the code.
combine ideas freely.
combine ideas only where combinations make sense.
express simple ideas simply.
The programming style of a programming language to provide these building blocks may be categorized into programming paradigms. For example, different paradigms may differentiate:

procedural languages, functional languages, and logical languages.
different levels of data abstraction.
different levels of class hierarchy.
different levels of input datatypes, as in container types and generic programming.
Each of these programming styles has contributed to the synthesis of different programming languages.
A programming language is a set of keywords, symbols, identifiers, and rules by which programmers can communicate instructions to the computer. They follow a set of rules called a syntax.

Keywords are reserved words to form declarations and statements.
Symbols are characters to form operations, assignments, control flow, and delimiters.
Identifiers are words created by programmers to form constants, variable names, structure names, and function names.
Syntax Rules are defined in the Backus–Naur form.
Programming languages get their basis from formal languages. The purpose of defining a solution in terms of its formal language is to generate an algorithm to solve the underlining problem. An algorithm is a sequence of simple instructions that solve a problem.

Generations of programming language

The evolution of programming languages began when the EDSAC (1949) used the first stored computer program in its von Neumann architecture. Programming the EDSAC was in the first generation of programming language.

The first generation of programming language is machine language. Machine language requires the programmer to enter instructions using instruction numbers called machine code. For example, the ADD operation on the PDP-11 has instruction number 24576.
The second generation of programming language is assembly language. Assembly language allows the programmer to use mnemonic instructions instead of remembering instruction numbers. An assembler translates each assembly language mnemonic into its machine language number. For example, on the PDP-11, the operation 24576 can be referenced as ADD R0,R0 in the source code. The four basic arithmetic operations have assembly instructions like ADD, SUB, MUL, and DIV. Computers also have instructions like DW (Define Word) to reserve memory cells. Then the MOV instruction can copy integers between registers and memory.
The basic structure of an assembly language statement is a label, operation, operand, and comment.
Labels allow the programmer to work with variable names. The assembler will later translate labels into physical memory addresses.
Operations allow the programmer to work with mnemonics. The assembler will later translate mnemonics into instruction numbers.
Operands tell the assembler which data the operation will process.
Comments allow the programmer to articulate a narrative because the instructions alone are vague.
The key characteristic of an assembly language program is it forms a one-to-one mapping to its corresponding machine language target.
The third generation of programming language uses compilers and interpreters to execute computer programs. The distinguishing feature of a third generation language is its independence from particular hardware. Early languages include FORTAN (1958), COBOL (1959), ALGOL (1960), and BASIC (1964). In 1973, the C programming language emerged as a high-level language that produced efficient machine language instructions. Whereas third-generation languages historically generated many machine instructions for each statement, C has statements that may generate a single machine instruction. Moreover, an optimizing compiler might overrule the programmer and produce fewer machine instructions than statements. Today, an entire paradigm of languages fill the imperative, third generation spectrum.
The fourth generation of programming language emphasizes what output results are desired, rather than how programming statements should be constructed. Declarative languages attempt to limit side effects and allow programmers to write code with relatively few errors. One popular fourth generation language is called Structured Query Language (SQL). Database developers no longer need to process each database record one at a time. Also, a simple select statement can generate output records without having to understand how they are retrieved.

Imperative languages

Imperative languages specify a sequential algorithm using declarations, expressions, and statements:

A declaration introduces a variable name to the computer program and assigns it to a datatype – for example: var x: integer;
An expression yields a value – for example: 2 + 2 yields 4
A statement might assign an expression to a variable or use the value of a variable to alter the program's control flow – for example: x := 2 + 2; if x = 4 then do_something();

Fortran
FORTRAN (1958) was unveiled as "The IBM Mathematical FORmula TRANslating system". It was designed for scientific calculations, without string handling facilities. Along with declarations, expressions, and statements, it supported:

arrays.
subroutines.
"do" loops.
It succeeded because:

programming and debugging costs were below computer running costs.
it was supported by IBM.
applications at the time were scientific.
However, non-IBM vendors also wrote Fortran compilers, but with a syntax that would likely fail IBM's compiler. The American National Standards Institute (ANSI) developed the first Fortran standard in 1966. In 1978, Fortran 77 became the standard until 1991. Fortran 90 supports:

records.
pointers to arrays.

COBOL
COBOL (1959) stands for "COmmon Business Oriented Language". Fortran manipulated symbols. It was soon realized that symbols did not need to be numbers, so strings were introduced. The US Department of Defense influenced COBOL's development, with Grace Hopper being a major contributor. The statements were English-like and verbose. The goal was to design a language so managers could read the programs. However, the lack of structured statements hindered this goal.
COBOL's development was tightly controlled, so dialects did not emerge to require ANSI standards. As a consequence, it was not changed for 15 years until 1974. The 1990s version did make consequential changes, like object-oriented programming.

Algol
ALGOL (1960) stands for "ALGOrithmic Language". It had a profound influence on programming language design. Emerging from a committee of European and American programming language experts, it used standard mathematical notation and had a readable, structured design. Algol was first to define its syntax using the Backus–Naur form. This led to syntax-directed compilers. It added features like:

block structure, where variables were local to their block.
arrays with variable bounds.
"for" loops.
functions.
recursion.
Algol's direct descendants include Pascal, Modula-2, Ada, Delphi and Oberon on one branch. On another branch the descendants include C, C++ and Java.

Basic
BASIC (1964) stands for "Beginner's All-Purpose Symbolic Instruction Code". It was developed at Dartmouth College for all of their students to learn. If a student did not go on to a more powerful language, the student would still remember Basic. A Basic interpreter was installed in the microcomputers manufactured in the late 1970s. As the microcomputer industry grew, so did the language.
Basic pioneered the interactive session. It offered operating system commands within its environment:

The 'new' command created an empty slate.
Statements evaluated immediately.
Statements could be programmed by preceding them with line numbers.
The 'list' command displayed the program.
The 'run' command executed the program.
However, the Basic syntax was too simple for large programs. Recent dialects added structure and object-oriented extensions. Microsoft's Visual Basic is still widely used and produces a graphical user interface.

C
C programming language (1973) got its name because the language BCPL was replaced with B, and AT&T Bell Labs called the next version "C". Its purpose was to write the UNIX operating system. C is a relatively small language, making it easy to write compilers. Its growth mirrored the hardware growth in the 1980s. Its growth also was because it has the facilities of assembly language, but it uses a high-level syntax. It added advanced features like:

inline assembler
arithmetic on pointers
pointers to functions
bit operations
freely combining complex operators

C allows the programmer to control which region of memory data is to be stored. Global variables and static variables require the fewest clock cycles to store. The stack is automatically used for the standard variable declarations. Heap memory is returned to a pointer variable from the malloc() function.

The global and static data region is located just above the program region. (The program region is technically called the text region. It is where machine instructions are stored.)
The global and static data region is technically two regions. One region is called the initialized data segment, where variables declared with default values are stored. The other region is called the block started by segment, where variables declared without default values are stored.
Variables stored in the global and static data region have their addresses set at compile time. They retain their values throughout the life of the process.
The global and static region stores the global variables that are declared on top of (outside) the main() function. Global variables are visible to main() and every other function in the source code.
On the other hand, variable declarations inside of main(), other functions, or within { } block delimiters are local variables. Local variables also include formal parameter variables. Parameter variables are enclosed within the parenthesis of a function definition. Parameters provide an interface to the function.
Local variables declared using the static prefix are also stored in the global and static data region. Unlike global variables, static variables are only visible within the function or block. Static variables always retain their value. An example usage would be the function int increment_counter(){static int counter = 0; counter++; return counter;}
The stack region is a contiguous block of memory located near the top memory address. Variables placed in the stack are populated from top to bottom. A stack pointer is a special-purpose register that keeps track of the last memory address populated. Variables are placed into the stack via the assembly language PUSH instruction. Therefore, the addresses of these variables are set during runtime. The method for stack variables to lose their scope is via the POP instruction.
Local variables declared without the static prefix, including formal parameter variables, are called automatic variables and are stored in the stack. They are visible inside the function or block and lose their scope upon exiting the function or block.
The heap region is located below the stack. It is populated from the bottom to the top. The operating system manages the heap using a heap pointer and a list of allocated memory blocks. Like the stack, the addresses of heap variables are set during runtime. An out of memory error occurs when the heap pointer and the stack pointer meet.
C provides the malloc() library function to allocate heap memory. Populating the heap with data is an additional copy function. Variables stored in the heap are economically passed to functions using pointers. Without pointers, the entire block of data would have to be passed to the function via the stack.

C++
In the 1970s, software engineers needed language support to break large projects down into modules. One obvious feature was to decompose large projects physically into separate files. A less obvious feature was to decompose large projects logically into abstract data types. At the time, languages supported concrete (scalar) datatypes like integer numbers, floating-point numbers, and strings of characters. Abstract datatypes are structures of concrete datatypes, with a new name assigned. For example, a list of integers could be called integer_list.
In object-oriented jargon, abstract datatypes are called classes. However, a class is only a definition; no memory is allocated. When memory is allocated to a class and bound to an identifier, it is called an object.
Object-oriented imperative languages developed by combining the need for classes and the need for safe functional programming. A function, in an object-oriented language, is assigned to a class. An assigned function is then referred to as a method, member function, or operation. Object-oriented programming is executing operations on objects.
Object-oriented languages support a syntax to model subset/superset relationships. In set theory, an element of a subset inherits all the attributes contained in the superset. For example, a student is a person. Therefore, the set of students is a subset of the set of persons. As a result, students inherit all the attributes common to all persons. Additionally, students have unique attributes that other people do not have. Object-oriented languages model subset/superset relationships using inheritance. Object-oriented programming became the dominant language paradigm by the late 1990s.
C++ (1985) was originally called "C with Classes". It was designed to expand C's capabilities by adding the object-oriented facilities of the language Simula.
An object-oriented module is composed of two files. The definitions file is called the header file. Here is a C++ header file for the GRADE class in a simple school application:

A constructor operation is a function with the same name as the class name. It is executed when the calling operation executes the new statement.
A module's other file is the source file. Here is a C++ source file for the GRADE class in a simple school application:

Here is a C++ header file for the PERSON class in a simple school application:

Here is a C++ source file for the PERSON class in a simple school application:

Here is a C++ header file for the STUDENT class in a simple school application:

Here is a C++ source file for the STUDENT class in a simple school application:

Here is a driver program for demonstration:

Here is a makefile to compile everything:

Declarative languages

Imperative languages have one major criticism: assigning an expression to a non-local variable may produce an unintended side effect. Declarative languages generally omit the assignment statement and the control flow. They describe what computation should be performed and not how to compute it. Two broad categories of declarative languages are functional languages and logical languages.
The principle behind a functional language is to use lambda calculus as a guide for a well defined semantic. In mathematics, a function is a rule that maps elements from an expression to a range of values. Consider the function:
times_10(x) = 10 * x
The expression 10 * x is mapped by the function times_10() to a range of values. One value happens to be 20. This occurs when x is 2. So, the application of the function is mathematically written as:
times_10(2) = 20
A functional language compiler will not store this value in a variable. Instead, it will push the value onto the computer's stack before setting the program counter back to the calling function. The calling function will then pop the value from the stack.
Imperative languages do support functions. Therefore, functional programming can be achieved in an imperative language, if the programmer uses discipline. However, a functional language will force this discipline onto the programmer through its syntax. Functional languages have a syntax tailored to emphasize the what.
A functional program is developed with a set of primitive functions followed by a single driver function. Consider the snippet:
function max( a, b ){/* code omitted */}
function min( a, b ){/* code omitted */}
function range( a, b, c ) {

return max( a, max( b, c ) ) - min( a, min( b, c ) );
}
The primitives are max() and min(). The driver function is range(). Executing:
put( range( 10, 4, 7) ); will output 6.
Functional languages are used in computer science research to explore new language features. Moreover, their lack of side-effects have made them popular in parallel programming and concurrent programming. However, application developers prefer the object-oriented features of imperative languages.

Lisp
Lisp (1958) stands for "LISt Processor". It is tailored to process lists. A full structure of the data is formed by building lists of lists. In memory, a tree data structure is built. Internally, the tree structure lends nicely for recursive functions. The syntax to build a tree is to enclose the space-separated elements within parenthesis. The following is a list of three elements. The first two elements are themselves lists of two elements:
((A B) (HELLO WORLD) 94)
Lisp has functions to extract and reconstruct elements. The function head() returns a list containing the first element in the list. The function tail() returns a list containing everything but the first element. The function cons() returns a list that is the concatenation of other lists. Therefore, the following expression will return the list x:
cons(head(x), tail(x))
One drawback of Lisp is when many functions are nested, the parentheses may look confusing. Modern Lisp environments help ensure parenthesis match. As an aside, Lisp does support the imperative language operations of the assignment statement and goto loops. Also, Lisp is not concerned with the datatype of the elements at compile time. Instead, it assigns (and may reassign) the datatypes at runtime. Assigning the datatype at runtime is called dynamic binding. Whereas dynamic binding increases the language's flexibility, programming errors may linger until late in the software development process.
Writing large, reliable, and readable Lisp programs requires forethought. If properly planned, the program may be much shorter than an equivalent imperative language program. Lisp is widely used in artificial intelligence. However, its usage has been accepted only because it has imperative language operations, making unintended side-effects possible.

ML
ML (1973) stands for "Meta Language". ML checks to make sure only data of the same type are compared with one another. For example, this function has one input parameter (an integer) and returns an integer:

ML is not parenthesis-eccentric like Lisp. The following is an application of times_10():

times_10 2

It returns "20 : int". (Both the results and the datatype are returned.)
Like Lisp, ML is tailored to process lists. Unlike Lisp, each element is the same datatype. Moreover, ML assigns the datatype of an element at compile time. Assigning the datatype at compile time is called static binding. Static binding increases reliability because the compiler checks the context of variables before they are used.

Prolog
Prolog (1972) stands for "PROgramming in LOGic". It is a logic programming language, based on formal logic. The language was developed by Alain Colmerauer and Philippe Roussel in Marseille, France. It is an implementation of Selective Linear Definite clause resolution, pioneered by Robert Kowalski and others at the University of Edinburgh.
The building blocks of a Prolog program are facts and rules. Here is a simple example:

After all the facts and rules are entered, then a question can be asked:

Will Tom eat Jerry?

The following example shows how Prolog will convert a letter grade to its numeric value:

Here is a comprehensive example:
1) All dragons billow fire, or equivalently, a thing billows fire if the thing is a dragon:

2) A creature billows fire if one of its parents billows fire:

3) A thing X is a parent of a thing Y if X is the mother of Y or X is the father of Y:

4) A thing is a creature if the thing is a dragon:

5) Norberta is a dragon, and Puff is a creature. Norberta is the mother of Puff.

Rule (2) is a recursive (inductive) definition. It can be understood declaratively, without the need to understand how it is executed.
Rule (3) shows how functions are represented by using relations. Here, the mother and father functions ensure that every individual has only one mother and only one father.
Prolog is an untyped language. Nonetheless, inheritance can be represented by using predicates. Rule (4) asserts that a creature is a superclass of a dragon.
Questions are answered using backward reasoning. Given the question:

Prolog generates two answers :

Practical applications for Prolog are knowledge representation and problem solving in artificial intelligence.

Object-oriented programming
Object-oriented programming is a programming method to execute operations (functions) on objects. The basic idea is to group the characteristics of a phenomenon into an object container and give the container a name. The operations on the phenomenon are also grouped into the container. Object-oriented programming developed by combining the need for containers and the need for safe functional programming. This programming method need not be confined to an object-oriented language. In an object-oriented language, an object container is called a class. In a non-object-oriented language, a data structure (which is also known as a record) may become an object container. To turn a data structure into an object container, operations need to be written specifically for the structure. The resulting structure is called an abstract datatype. However, inheritance will be missing. Nonetheless, this shortcoming can be overcome.
Here is a C programming language header file for the GRADE abstract datatype in a simple school application:

The grade_new() function performs the same algorithm as the C++ constructor operation.
Here is a C programming language source file for the GRADE abstract datatype in a simple school application:

In the constructor, the function calloc() is used instead of malloc() because each memory cell will be set to zero.
Here is a C programming language header file for the PERSON abstract datatype in a simple school application:

Here is a C programming language source file for the PERSON abstract datatype in a simple school application:

Here is a C programming language header file for the STUDENT abstract datatype in a simple school application:

Here is a C programming language source file for the STUDENT abstract datatype in a simple school application:

Here is a driver program for demonstration:

Here is a makefile to compile everything:

The formal strategy to build object-oriented objects is to:

Identify the objects. Most likely these will be nouns.
Identify each object's attributes. What helps to describe the object?
Identify each object's actions. Most likely these will be verbs.
Identify the relationships from object to object. Most likely these will be verbs.
For example:

A person is a human identified by a name.
A grade is an achievement identified by a letter.
A student is a person who earns a grade.

Syntax and semantics

The syntax of a computer program is a list of production rules which form its grammar. A programming language's grammar correctly places its declarations, expressions, and statements. Complementing the syntax of a language are its semantics. The semantics describe the meanings attached to various syntactic constructs. A syntactic construct may need a semantic description because a production rule may have an invalid interpretation. Also, different languages might have the same syntax; however, their behaviors may be different.
The syntax of a language is formally described by listing the production rules. Whereas the syntax of a natural language is extremely complicated, a subset of the English language can have this production rule listing:

a sentence is made up of a noun-phrase followed by a verb-phrase;
a noun-phrase is made up of an article followed by an adjective followed by a noun;
a verb-phrase is made up of a verb followed by a noun-phrase;
an article is 'the';
an adjective is 'big' or
an adjective is 'small';
a noun is 'cat' or
a noun is 'mouse';
a verb is 'eats';
The words in bold-face are known as non-terminals. The words in 'single quotes' are known as terminals.
From this production rule listing, complete sentences may be formed using a series of replacements. The process is to replace non-terminals with either a valid non-terminal or a valid terminal. The replacement process repeats until only terminals remain. One valid sentence is:

sentence
noun-phrase verb-phrase
article adjective noun verb-phrase
the adjective noun verb-phrase
the big noun verb-phrase
the big cat verb-phrase
the big cat verb noun-phrase
the big cat eats noun-phrase
the big cat eats article adjective noun
the big cat eats the adjective noun
the big cat eats the small noun
the big cat eats the small mouse
However, another combination results in an invalid sentence:

the small mouse eats the big cat
Therefore, a semantic is necessary to correctly describe the meaning of an eat activity.
One production rule listing method is called the Backus–Naur form (BNF). BNF describes the syntax of a language and itself has a syntax. This recursive definition is an example of a metalanguage. The syntax of BNF includes:

::= which translates to is made up of a[n] when a non-terminal is to its right. It translates to is when a terminal is to its right.
| which translates to or.
< and > which surround non-terminals.
Using BNF, a subset of the English language can have this production rule listing:

Using BNF, a signed-integer has the production rule listing:

Notice the recursive production rule:

This allows for an infinite number of possibilities. Therefore, a semantic is necessary to describe a limitation of the number of digits.
Notice the leading zero possibility in the production rules:

Therefore, a semantic is necessary to describe that leading zeros need to be ignored.
Two formal methods are available to describe semantics. They are denotational semantics and axiomatic semantics.

Software engineering and computer programming

Software engineering is a variety of techniques to produce quality computer programs. Computer programming is the process of writing or editing source code. In a formal environment, a systems analyst will gather information from managers about all the organization's processes to automate. This professional then prepares a detailed plan for the new or modified system. The plan is analogous to an architect's blueprint.

Performance objectives
The systems analyst has the objective to deliver the right information to the right person at the right time. The critical factors to achieve this objective are:

The quality of the output. Is the output useful for decision-making?
The accuracy of the output. Does it reflect the true situation?
The format of the output. Is the output easily understood?
The speed of the output. Time-sensitive information is important when communicating with the customer in real time.

Cost objectives
Achieving performance objectives should be balanced with all of the costs, including:

Development costs.
Uniqueness costs. A reusable system may be expensive. However, it might be preferred over a limited-use system.
Hardware costs.
Operating costs.
Applying a systems development process will mitigate the axiom: the later in the process an error is detected, the more expensive it is to correct.

Waterfall model
The waterfall model is an implementation of a systems development process. As the waterfall label implies, the basic phases overlap each other:

The investigation phase is to understand the underlying problem.
The analysis phase is to understand the possible solutions.
The design phase is to plan the best solution.
The implementation phase is to program the best solution.
The maintenance phase lasts throughout the life of the system. Changes to the system after it is deployed may be necessary. Faults may exist, including specification faults, design faults, or coding faults. Improvements may be necessary. Adaption may be necessary to react to a changing environment.

Computer programmer
A computer programmer is a specialist responsible for writing or modifying the source code to implement the detailed plan. A programming team is likely to be needed because most systems are too large to be completed by a single programmer. However, adding programmers to a project may not shorten the completion time. Instead, it may lower the quality of the system. To be effective, program modules need to be defined and distributed to team members. Also, team members must interact with one another in a meaningful and effective way.
Computer programmers may be programming in the small: programming within a single module. Chances are a module will execute modules located in other source code files. Therefore, computer programmers may be programming in the large: programming modules so they will effectively couple with each other. Programming-in-the-large includes contributing to the application programming interface (API).

Program modules
Modular programming is a technique to refine imperative language programs. Refined programs may reduce the software size, separate responsibilities, and thereby mitigate software aging. A program module is a sequence of statements that are bounded within a block and together identified by a name. Modules have a function, context, and logic:

The function of a module is what it does.
The context of a module are the elements being performed upon.
The logic of a module is how it performs the function.
The module's name should be derived first by its function, then by its context. Its logic should not be part of the name. For example, function compute_square_root( x ) or function compute_square_root_integer( i : integer ) are appropriate module names. However, function compute_square_root_by_division( x ) is not.
The degree of interaction within a module is its level of cohesion. Cohesion is a judgment of the relationship between a module's name and its function. The degree of interaction between modules is the level of coupling. Coupling is a judgement of the relationship between a module's context and the elements being performed upon.

Cohesion
The levels of cohesion from worst to best are:

Coincidental Cohesion: A module has coincidental cohesion if it performs multiple functions, and the functions are completely unrelated. For example, function read_sales_record_print_next_line_convert_to_float(). Coincidental cohesion occurs in practice if management enforces silly rules. For example, "Every module will have between 35 and 50 executable statements."
Logical Cohesion: A module has logical cohesion if it has available a series of functions, but only one of them is executed. For example, function perform_arithmetic( perform_addition, a, b ).
Temporal Cohesion: A module has temporal cohesion if it performs functions related to time. One example, function initialize_variables_and_open_files(). Another example, stage_one(), stage_two(), ...
Procedural Cohesion: A module has procedural cohesion if it performs multiple loosely related functions. For example, function read_part_number_update_employee_record().
Communicational Cohesion: A module has communicational cohesion if it performs multiple closely related functions. For example, function read_part_number_update_sales_record().
Informational Cohesion: A module has informational cohesion if it performs multiple functions, but each function has its own entry and exit points. Moreover, the functions share the same data structure. Object-oriented classes work at this level.
Functional Cohesion: a module has functional cohesion if it achieves a single goal working only on local variables. Moreover, it may be reusable in other contexts.

Coupling
The levels of coupling from worst to best are:

Content Coupling: A module has content coupling if it modifies a local variable of another function. COBOL used to do this with the alter verb.
Common Coupling: A module has common coupling if it modifies a global variable.
Control Coupling: A module has control coupling if another module can modify its control flow. For example, perform_arithmetic( perform_addition, a, b ). Instead, control should be on the makeup of the returned object.
Stamp Coupling: A module has stamp coupling if an element of a data structure passed as a parameter is modified. Object-oriented classes work at this level.
 Data Coupling: A module has data coupling if all of its input parameters are needed and none of them are modified. Moreover, the result of the function is returned as a single object.

Data flow analysis

Data flow analysis is a design method used to achieve modules of functional cohesion and data coupling. The input to the method is a data-flow diagram. A data-flow diagram is a set of ovals representing modules. Each module's name is displayed inside its oval. Modules may be at the executable level or the function level.
The diagram also has arrows connecting modules to each other. Arrows pointing into modules represent a set of inputs. Each module should have only one arrow pointing out from it to represent its single output object. (Optionally, an additional exception arrow points out.) A daisy chain of ovals will convey an entire algorithm. The input modules should start the diagram. The input modules should connect to the transform modules. The transform modules should connect to the output modules.

Functional categories

Computer programs may be categorized along functional lines. The main functional categories are application software and system software. System software includes the operating system, which couples computer hardware with application software. The purpose of the operating system is to provide an environment where application software executes in a convenient and efficient manner. Both application software and system software execute utility programs. At the hardware level, a microcode program controls the circuits throughout the central processing unit.

Application software

Application software is the key to unlocking the potential of the computer system. Enterprise application software bundles accounting, personnel, customer, and vendor applications. Examples include enterprise resource planning, customer relationship management, and supply chain management software.
Enterprise applications may be developed in-house as a one-of-a-kind proprietary software. Alternatively, they may be purchased as off-the-shelf software. Purchased software may be modified to provide custom software. If the application is customized, then either the company's resources are used or the resources are outsourced. Outsourced software development may be from the original software vendor or a third-party developer.
The potential advantages of in-house software are features and reports may be developed exactly to specification. Management may also be involved in the development process and offer a level of control. Management may decide to counteract a competitor's new initiative or implement a customer or vendor requirement. A merger or acquisition may necessitate enterprise software changes. The potential disadvantages of in-house software are time and resource costs may be extensive. Furthermore, risks concerning features and performance may be looming.
The potential advantages of off-the-shelf software are upfront costs are identifiable, the basic needs should be fulfilled, and its performance and reliability have a track record. The potential disadvantages of off-the-shelf software are it may have unnecessary features that confuse end users, it may lack features the enterprise needs, and the data flow may not match the enterprise's work processes.

Application service provider
One approach to economically obtaining a customized enterprise application is through an application service provider. Specialty companies provide hardware, custom software, and end-user support. They may speed the development of new applications because they possess skilled information system staff. The biggest advantage is it frees in-house resources from staffing and managing complex computer projects. Many application service providers target small, fast-growing companies with limited information system resources. On the other hand, larger companies with major systems will likely have their technical infrastructure in place. One risk is having to trust an external organization with sensitive information. Another risk is having to trust the provider's infrastructure reliability.

Operating system

An operating system is the low-level software that supports a computer's basic functions, such as scheduling processes and controlling peripherals.
In the 1950s, the programmer, who was also the operator, would write a program and run it. After the program finished executing, the output may have been printed, or it may have been punched onto paper tape or cards for later processing. More often than not the program did not work. The programmer then looked at the console lights and fiddled with the console switches. If less fortunate, a memory printout was made for further study. In the 1960s, programmers reduced the amount of wasted time by automating the operator's job. A program called an operating system was kept in the computer at all times.
The term operating system may refer to two levels of software. The operating system may refer to the kernel program that manages the processes, memory, and devices. More broadly, the operating system may refer to the entire package of the central software. The package includes a kernel program, command-line interpreter, graphical user interface, utility programs, and editor.

Kernel Program

The kernel's main purpose is to manage the limited resources of a computer:

The kernel program should perform process scheduling, which is also known as a context switch. The kernel creates a process control block when a computer program is selected for execution. However, an executing program gets exclusive access to the central processing unit only for a time slice. To provide each user with the appearance of continuous access, the kernel quickly preempts each process control block to execute another one. The goal for system developers is to minimize dispatch latency.

The kernel program should perform memory management.
When the kernel initially loads an executable into memory, it divides the address space logically into regions. The kernel maintains a master-region table and many per-process-region (pregion) tables—one for each running process. These tables constitute the virtual address space. The master-region table is used to determine where its contents are located in physical memory. The pregion tables allow each process to have its own program (text) pregion, data pregion, and stack pregion.
The program pregion stores machine instructions. Since machine instructions do not change, the program pregion may be shared by many processes of the same executable.
To save time and memory, the kernel may load only blocks of execution instructions from the disk drive, not the entire execution file completely.
The kernel is responsible for translating virtual addresses into physical addresses. The kernel may request data from the memory controller and, instead, receive a page fault. If so, the kernel accesses the memory management unit to populate the physical data region and translate the address.
The kernel allocates memory from the heap upon request by a process. When the process is finished with the memory, the process may request for it to be freed. If the process exits without requesting all allocated memory to be freed, then the kernel performs garbage collection to free the memory.
The kernel also ensures that a process only accesses its own memory, and not that of the kernel or other processes.
The kernel program should perform file system management. The kernel has instructions to create, retrieve, update, and delete files.
The kernel program should perform device management. The kernel provides programs to standardize and simplify the interface to the mouse, keyboard, disk drives, printers, and other devices. Moreover, the kernel should arbitrate access to a device if two processes request it at the same time.
The kernel program should perform network management. The kernel transmits and receives packets on behalf of processes. One key service is to find an efficient route to the target system.
The kernel program should provide system level functions for programmers to use.
Programmers access files through a relatively simple interface that in turn executes a relatively complicated low-level I/O interface. The low-level interface includes file creation, file descriptors, file seeking, physical reading, and physical writing.
Programmers create processes through a relatively simple interface that in turn executes a relatively complicated low-level interface.
Programmers perform date/time arithmetic through a relatively simple interface that in turn executes a relatively complicated low-level time interface.
The kernel program should provide a communication channel between executing processes. For a large software system, it may be desirable to engineer the system into smaller processes. Processes may communicate with one another by sending and receiving signals.
Originally, operating systems were programmed in assembly; however, modern operating systems are typically written in higher-level languages like C, Objective-C, and Swift.

Utility program
A utility is a program that aids system administration and software execution. An operating system typically provides utilities to check hardware such as storage, memory, speakers, and printers. A utility may optimize the performance of a storage device. System utilities monitor hardware and network performance and may trigger an alert when a metric is outside the nominal range. A utility may compress files to reduce storage space and network transmission time. A utility may sort and merge data sets or detect computer viruses.

Microcode program

A microcode program is the bottom-level interpreter that controls the datapath of software-driven computers.
(Advances in hardware have migrated these operations to hardware execution circuits.) Microcode instructions allow the programmer to more easily implement the digital logic level—the computer's real hardware. The digital logic level is the boundary between computer science and computer engineering.
A logic gate is a tiny transistor that can return one of two signals: on or off.

Having one transistor forms the NOT gate.
Connecting two transistors in series forms the NAND gate.
Connecting two transistors in parallel forms the NOR gate.
Connecting a NOT gate to a NAND gate forms the AND gate.
Connecting a NOT gate to a NOR gate forms the OR gate.
These five gates form the building blocks of binary algebra—the digital logic functions of the computer.
Microcode instructions are mnemonics programmers may use to execute digital logic functions instead of forming them in binary algebra. They are stored in a central processing unit's (CPU) control store.
These hardware-level instructions move data throughout the data path.
The micro-instruction cycle begins when the microsequencer uses its microprogram counter to fetch the next machine instruction from random-access memory. The next step is to decode the machine instruction by selecting the proper output line to the hardware module.
The final step is to execute the instruction using the hardware module's set of gates.

Instructions to perform arithmetic are passed through an arithmetic logic unit (ALU). The ALU has circuits to perform elementary operations to add, shift, and compare integers. By combining and looping the elementary operations through the ALU, the CPU performs its complex arithmetic.
Microcode instructions move data between the CPU and the memory controller. Memory controller microcode instructions manipulate two registers. The memory address register is used to access each memory cell's address. The memory data register is used to set and read each cell's contents.

Notes

References
