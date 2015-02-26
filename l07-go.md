Russ Cox's lecture on Go
========================

Why Go?
------

 - an answer to the problems of scalability at Google
   + `10^6+` machines design point
   + it's routine to be running on 1000 machines
   + constantly writing programs that coordinate with each other
     - sometimes MapReduce works, other times it doesn't

Who uses Go at Google
---------------------

 - SPDY proxy for Chrome on mobile devices uses a Go-written _Data Compression Proxy_
 - dl.google.com
 - YouTube MySQL balancer
 - the target is network servers, but it's a great gen. purp. language
 - Bitbucket, bitly, GitHub, Dropbox, MongoDB, Mozilla services, NY Times, etc.

Concurrency
-----------
 
 - "Communicating Sequential Processes", by Hoare, 1978
   + strongly encouraged to read
   + in some sense, a generalization of UNIX pipelines
 - Bell Labs had some languages developed for concurrency in 80's, 90's:
   + Pan, Promela, Newsqueak, Alef, Limbo, Libthread, Concurrent ML
 - Google developed Go in the 2000s

### There's no goroutine IDs
 
 - "There's no goroutine IDs, so I can't kill my threads"
   + This is what channels are for: just tell your thread via a channel to shut itself off
   + Also, it's kind of "antisocial" to kill them.
     - What we mean is that your program is prolly not gonna work very well if you keep killing your threads like that

### Channels vs. Mutexes

 - if you need a mutex, use a mutex
 - if you need condition variable, think about using a channel instead
 - don't communicate by sharing memory, you share memory by communicating

### Network channels

 - it'd be great to have the equivalent for a network channel
 - if you take local abstractions (like channels) and use them in a new
   context like a network, ignoring failure modes (etc), then you're gonna
   run into trouble

Scale of engineering efforts
----------------------------

In 2011, Google had:

 - 5000+ developers 
 - 20+ changes per minute
 - 50% code base changes every month (files? not lines probably)
 - 50 million test cases executed per day
 - single code tree projects

A new language was needed to fix the problems that other languages had with software engineering at this scale

The scale of compilation matters. 
 - When you compile a package A that depends on B, most (all?) languages need to compile B first
 - Go doesn't.
 - Dependencies like these at the scale of Google projects slow down compilation if you use a traditional language
   + gets worse with "deeper" dependencies `A->B->C->D->...`
 - _Example:_ at some point they found a postscript interpreter compiled in a server binary for no reason due to weird deps

### Interfaces vs. inheritance

 - inhertance hierarchies are hard to get right and if you don't they are hard to change later
 - interfaces are much more informal and clearer about who owns and supplies what parts of the program

### Readability and simplicity

 - Dick Gabriel quote:
 - Simplify syntax
 - Avoid cleverness: ternary operators, macros
 - Don't let code writing be like "arguing with your compiler"
 - Don't want to puzzle through code 6 months later

Design criteria
---------------

 - started by Rob Pike, Robert Griesemer and Ken Thompson in late 2007
 - Russ Cox, Ian Lance Taylor joined in mid-2008
 - design by consensus (everyone could veto a feature, if they didn't want it)

### Generics

 - Russ: "Don't use `*list.List`, you almost never need them. Use slices."
   + Generics are not bad, just hard to do right.
     - Early designers for Java generics also agreed and warned Go designers to be careful
       + Seems like they regretted getting into that business

### Enginering tools

 - when you have millions of lines of code, you need mechanical help
   + like changing an API
 - Go designed to be easy to parse (not like C++)
 - standard formatter
 - Means you can't tell a mechanical change from a manual change
   + enables automated rewrites of code

### More automation

 - fix code for API updates
   + early Go versions API changed a lot
   + Google had a rewriter that would fix your code which used the changed APIs
 - renaming struct fields, variables w/ conflict resolution
 - moving packages
 - splitting of packages
 - code cleanup
 - change C code to Go
 - global analysis that figure out what are all the implementors of an interface for instance

State of Go
-----------

 - Go 1.4 released in Decembeer 2014
 - Go 1.5 has toolchain implemented in Go, not in C
   + concurrent GC
   + Go for mobile devices
   + Go on PowerPC, ARM64
 - Lots of people use it
 - Go conferences outside of Google/Go

Q&A
---

 - Go vs C/C++
   + Go is garbage collected, biggest difference, so slower
   + Go can be faster than Java sometimes
   + once you're aware of that, you can write code that
     runs faster than C/C++ code
   + no reason that code that doesn't allocate memory
     shouldn't run as fast as C/C++
 - Goal to use Go outside Google?
   + Yes! Otherwise the language would die?
   + You get a breadth of experts that give you advice and write tools, etc.
     - C++ memory model guy gave feedback on Go memory model
       + Very usefl
   + Not trying to replace anything like language X
     - but they were using C/C++ and didn't want to anymore
     - however Python and Ruby users are switching to Go more
       + Go feels just as light but statically type checked
 - Studies about benefits of Go?
   + not a lot of data collected
 - 
