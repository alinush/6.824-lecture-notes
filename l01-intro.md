6.824 2015 Lecture 1: Introduction
==================================

**Note:** These lecture notes were slightly modified from the ones posted on the 6.824 [course website](http://nil.csail.mit.edu/6.824/2015/schedule.html) from Spring 2015.

Distributed systems
-------------------

### What is a distributed system?
 - multiple networked cooperating computers
 - _Example:_ Internet E-Mail, Athena file server, Google MapReduce, Dropbox, etc.

### Why distribute?
 - to connect physically separate entities
 - to achieve security via physical isolation
 - to tolerate faults via replication at separate sites
 - to increase performance via parallel CPUs/mem/disk/net

...but:

 - complex, hard to debug
 - new classes of problems, e.g. partial failure (did he accept my e-mail?)
 - Leslie Lamport: _"A distributed system is one in which the failure of a
   computer you didn't even know existed can render your own computer
   unusable."_
 - _Advice:_ don't distribute if a central system will work

### Why take this course?
 - interesting -- hard problems, non-obvious solutions
 - active research area -- lots of progress + big unsolved problems
 - used by real systems -- unlike 10 years ago -- driven by the rise of big Web sites
 - hands-on -- you'll build a real system in the labs

Course structure
----------------

See the course [website](http://pdos.csail.mit.edu/6.824).

### Course components
 - Lectures about big ideas, papers, labs
 - Readings: research papers as case studies
   + please read papers before class
   + paper for today: [MapReduce paper](papers/mapreduce.pdf)
   + each paper has a question for you to answer and one for you to ask (see web site)
   + submit question & answer before class, one or two paragraphs
 - Mid-term quiz in class, and final exam
 - Labs: build increasingly sophisticated fault-tolerant services
   + First lab is due on Monday
 - Project: design and build a distributed system of your choice or the system we pose
   in the last month of the course
   + teams of two or three
   + project meetings with course staff
   + demo in last class meeting

Main topics
-----------

_Example:_

 - a shared file system, so users can cooperate, like Dropbox
   + but this lecture isn't about dropbox specifically
   + just an example goal to get feel for distributed system problems
 - lots of client computers

### Architecture
 - Choice of interfaces
   + Monolithic file server?
   + Block server(s) -> FS logic in clients?
   + Separate naming + file servers?
   + Separate FS + block servers?
 - Single machine room or unified wide area system?
   + Wide-area dramatically more difficult.
 - Client/server or peer-to-peer?
   + Interact w/ performance, security, fault behavior.

### Implementation
 - How do clients/servers communicate?
   + Direct network communication is pretty painful
   + Want to hide network stuff from application logic
 - Most systems organize distribution with some structuring framework(s)
   + RPC, RMI, DSM, MapReduce, etc.

### Performance
 - Distribution can hurt: network b/w and latency bottlenecks
   + Lots of tricks, e.g. caching, threaded servers
 - Distribution can help: parallelism, pick server near client
   + Idea: scalable design
     - We would like performance to scale linearly with the addition of machines
     - `N x` servers `-> N x` total performance
 - Need a way to divide the load by N
    + divide the state by N
      * split by user
      * split by file name
      * "sharding" or "partitioning"
 - Rarely perfect `->` only scales so far
   + Global operations, e.g. search
   + Load imbalance
     - One very active user
     - One very popular file
       + `->` one server 100%, added servers mostly idle
       + `-> N x` servers `->` `1 x` performance

### Fault tolerance
 - Dropbox: ~10,000 servers; [some fail](http://www.datacenterknowledge.com/archives/2013/10/23/how-dropbox-stores-stuff-for-200-million-users/)
 - Can I use my files if there's a failure?
   + Some part of network, some set of servers
 - Maybe: replicate the data on multiple servers
   + Perhaps client sends every operation to both
   + Maybe only needs to wait for one reply
 - _Opportunity:_ operate from two "replicas" independently if partitioned?
 - _Opportunity:_ can 2 servers yield 2x availability **AND** 2x performance?

### Consistency
 - Contract w/ apps/users about meaning of operations
   + e.g. "read yields most recently written value"
   + hard due to partial failure, replication/caching, concurrency
 - _Problem:_ keep replicas identical
   + If one is down, it will miss operations
     * Must be brought up to date after reboot
   + If net is broken, *both* replicas maybe live, and see different ops
     * Delete file, still visible via other replica
     * _"split brain"_ -- usually bad
 - _Problem:_ clients may see updates in different orders
   + Due to caching or replication
   + I make `grades.txt` unreadable, then TA writes grades to it
   + What if the operations run in different order on different replicas?
 - Consistency often hurts performance (communication, blocking)
   + Many systems cut corners -- "relaxed consistency"
   + Shifts burden to applications

Labs
----

Focus: fault tolerance and consistency -- central to distributed systems.

 - lab 1: MapReduce
 - labs 2/3/4: storage servers
   + progressively more sophisticated (tolerate more kinds of faults)
     * progressively harder too!
   + patterned after real systems, e.g. MongoDB
   + Lab 4 has core of a real-world design for 1000s of servers

What you'll learn from the labs:

 - easy to listen to lecture / read paper and think you understand
 - building forces you to really understand
   + _"I hear and I forget, I see and I remember, I do and I understand"_ (Confucius?)
 - you'll have to do some design yourself
   + we supply skeleton, requirements, and tests
   + but we leave you substantial scope to solve problems your own way
 - you'll get experience debugging distributed systems

Test cases simulate failure scenarios:

 - distributed systems are tricky to debug: concurrency and failures
   + many client and servers operating in parallel
   + test cases make servers fail at the "most" inopportune time
 - _think first_ before starting to code!
   + otherwise your solution will be a mess
   + and/or, it will take you a lot of time
 - code review
   + learn from others
   + judge other solutions   

We've tried to ensure that the hard problems have to do w/ distributed systems:

 - not e.g. fighting against language, libraries, etc.
 - thus Go (type-safe, garbage collected, slick RPC library)
 - thus fairly simple services (MapReduce, key/value store)

Lab 1: MapReduce
----------------

 - help you get up to speed on Go and distributed programming
 - first exposure to some fault tolerance 
   + motivation for better fault tolerance in later labs
 - motivating app for many papers
 - popular distributed programming framework 
 - many descendants frameworks 

### Computational model

 - aimed at document processing
   + split doc `-> k1, list<v1>`
   + run `Map(k1, list<v1>)` on each split `-> list<k2, v2>`
   + run `Reduce(k2, list<v2>)` on each partition `-> list<v2>`
   + merge result
 - write a map function and reduce function
   + framework takes care of parallelism, distribution, and fault tolerance
 - some computations are not targeted, such as:
   + anything that updates a document

### Example: `wc`

 - word count
 - In Go's implementation, we have:
   + `func Map(value string) *list.List`
      - the input is _a split_ of the file `wc` is called on
          +  a split is just a partion of the file, as decided
             by MapReduce's splitter (can be customized, etc.)
      - returns a list of _key-value pairs_
          + the key is the word (like 'pen')
          + the value is 1 (to indicate 'pen' occurred once)
      - **Note:** there will be multiple `<'pen', 1>` entries in the list
        if 'pen' shows up more times
   + `func Reduce(key string, values *list.List) string`
      - the input is a key and a list of (all? ) the values mapped to that key in the `Map()` phase
      - so here, we would expect a `Reduce('pen', [1,1,1,1])` call if pen appeared 4 times in the
        input file
          + **TODO**: not clear if it's also possible to get three reduce calls as follows:
              - `Reduce('pen', [1,1]) -> 2` + `Reduce('pen', [1,1]) -> 2`
              - `Reduce('pen', [2,2])`
              - the paper seems to indicate `Reduce`'s return value is just a list of values
                and so it seems that the association of those values with the key 'pen' in this
                case would be lost, which would prevent the 3rd `Reduce('pen')` call 

### Example: `grep`

 - map phase
   + master splits input in `M` partitions
   + calls Map on each partition
     - `map(partition) -> list(k1,v1)`
	 - search partition for word
	 - produce a list with one item if word shows up, `nil` if not
	 - partition results among `R` reducers
 - reduce phase
   + Reduce job collects 1/R output from each Map job
   + all map jobs have completed!
   + `reduce(k1, v1) -> v2`
     * identity function: `v1` in, `v1` out
 - merge phase
   + master merges `R` outputs

### Performance

 - number of jobs: `M x R` map jobs
 - how much speed up do we get on `N` machines?
   + ideally: `N`
   + bottlenecks:
     * stragglers
     * network calls to collect a Reduce partition 
     * network calls to interact with FS
     * disk I/O calls

### Fault tolerance model

 - master is not fault tolerant
   + _assumption:_ this single machine won't fail during running a MapReduce app
   + but many workers, so have to handle their failures
 - assumption: workers are fail stop
   + they fail and stop (e.g., don't send garbled weird packets after a failure)
   + they may reboot
  
#### What kinds of faults might we want to tolerate?

 - network:
   + lost packets
   + duplicated packets
   + temporary network failure
     * server disconnected
     * network partitioned
 - server:
   + server crash+restart   (master versus worker?)
   + server fails permanently  (master versus worker?)
   + all servers fail simultaneously -- power/earthquake
   + bad case: crash mid-way through complex operation
     * what happens if we fail in the middle of map or reduce?
   + bugs -- but not in this course
     * what happens when bug in map or reduce? 
     * same bug in Map over and over?
     * management software kills app
 - malice -- but not in this course

#### Tools for dealing with faults?

 - **retry** -- e.g. if packet is lost, or server crash+restart 
   + packets (TCP) and MapReduce jobs
   + may execute MapReduce job twice: must account for this
 - **replicate** -- e.g. if  one server or part of net has failed
   + next labs
 - **replace** -- for long-term health  
   + e.g., worker

#### Retry jobs

 - network falure: oops execute job twice
   + ok for MapReduce, because `map()/reduce()` produces same output
     - `map()/reduce()` are "functional" or "deterministic"
     - how about intermediate files?
       + atomic rename
 - worker failure: may have executed job or not
   + so, we may execute job more than once!
   + but ok for MapReduce as long as `map()` and `reduce()` functions are deterministic
   + what would make `map() or reduce()` not deterministic?
   + is executing a request twice in general ok? 
     - no. in fact, often not.
     - unhappy customer if you execute one credit card transaction several times
 - adding servers
   + easy in MapReduce -- just tell master
   + hard in general
     - server may have lost state (need to get new state)
	 - server may have rebooted quickly
	   + may need to recognize that to bring server up to date
	   + server may have a new role after reboot (e.g., not the primary)
     - these harder issues you would have to deal with to make the MapReduce master fault tolerant
     - topic of later labs
      
Lab 1 code 
----------

The lab 1 app (see `main/wc.go`):

 - stubs for `map() and reduce()`
 - you fill them out to implement word count (wc)
 - how would you write grep?
  
The lab 1 sequential implementation (see `mapreduce/mapreduce.go`):

 - demo: `run wc.go`
 - code walk through start with `RunSingle()`

The lab 1 worker (see `mapreduce/worker.go`):

 - the remote procedure calls (RPCs) arguments and replies (see `mapreduce/common.go`).
 - Server side of RPC
   + RPC handlers have a particular signature
     - `DoJob`
     - `Shutdown`
 - `RunWorker`
   + `rpcs.Register`: register named handlers -- so Call() can find them
   + `Listen`: create socket on which to listen for RPC requests
     - for distributed implementation, replace "unix" w. "tcp"
     - replace "me" with a `<dns,port>` tuple name
   + `ServeConn`: runs in a separate thread (why?)
     - serve RPC concurrently
	 - a RPC may block
 - Client side of RPC
   + `Register()`
 - `call()` (see `common.go`)
   + make an RPC
   + lab code dials for each request
     - typical code uses a network connection for several requests
       + but, real must be prepared to redial anyway
	   + a network connection failure, doesn't imply a server failure!
 	 - we also do this to introduce failure scenarios easily
	   + intermittent network failures
	   + just loosing the reply, but not the request

The lab 1 master (see mapreduce/master.go)

 - You write it
 - You will have to deal with distributing jobs
 - You will have to deal with worker failures

