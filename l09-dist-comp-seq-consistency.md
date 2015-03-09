6.824 2015 Lecture 9: DSM and Sequential Consistency
=====================================================

**Note:** These lecture notes were slightly modified from the ones posted on the 6.824 
[course website](http://nil.csail.mit.edu/6.824/2015/schedule.html) from Spring 2015.

**Topic:** Distributed computing

 - parallel computing on distributed machines
 - 4 papers on how to use a collection of machines to solve big computational problems
   +  we already read one of them: MapReduce
 - 3 other papers (IVY, TreadMarks, and Spark)
   + two provide a general-purpose memory model
   + Spark is in MapReduce style

Distributed Shared Memory (DSM) programming model
-------------------------------------------------

 - Adopt the same programming model that multiprocessors offer
 - Programmers can use locks and shared memory
   + Programmers are familiar with this model
   + e.g., like goroutines sharing memory 
 - General purpose
   + e.g., no restrictions like with MapReduce
 - Applications that run on a multiprocessor can run on IVY/TreadMarks 

**Challenge:** distributed systems don't have physical shared memory

 - On a network of cheap machines
   + [diagram: LAN, machines w/ RAM, MGR]

Diagram:
 
        *----------*   *----------*   *----------*
        |          |   |          |   |          |
        |          |   |          |   |          |
        |          |   |          |   |          |
        *-----*----*   *-----*----*   *-----*----*
              |              |              |
      --------*--------------*--------------*-------- LAN

Diagram:

             M0             M1
        *----------*   *----------*   
        | M0 acces |   | x x x x  |   
        |----------|   |----------|
        | x x x x  |   | M1 acces |   
        *-----*----*   *-----*----*   
              |              |        
      --------*--------------*------- LAN

      The 'xxxxx' pages are not accesible locally,
      they have to be fetched via the network

**Approach:**

 - Simulate shared memory using hardware support for virtual memory 
 - General idea illustrated with 2 machines:
   + Part of the address space maps a part of M0's physical memory
     - On M0 it maps to the M0's physical page
     - On M1 it maps to not present 
   + Part of the address space maps a part of M1's physical memory
     - On M0 it maps to not present
	 - On M1 it maps to its physical memory
 - A thread of the application on M1 may refer to an address that lives on M0
   + If thread LD/ST to that "shared" address, M1's hardware will take a page fault
     - Because page is mapped as not present
   + OS propagates page fault to DSM runtime
   + DSM runtime can fetch page from M0
   + DSM on M0, maps page not present, and sends page to M1
   + DSM on M1 receives it from M0, copies it somewhere in memory (say address 4096)
   + DSM on M1 maps the shared address to physical address 4096
   + DSM returns from page fault handler
   + Hardware retries LD/ST
 - Runs threaded code w/o modification
   + e.g. matrix multiply, physical simulation, sort

**Challenges:**

 - How to implement it efficiently?
   + IVY and Treadmarks
 - How to provide fault tolerance?
   + Many DSMs [punt](https://www.google.com/search?q=punt&oq=punt) on this
   + Some DSM checkpoint the whole memory periodically
   + We will return to this when talking about Spark

**Correctness: coherence**

 - We need to articulate what is correctness before optimizing performance
   + Optimizations should preserve correctness
 - Less obvious than it may seem!
   + Choice trades off between performance and programmer-friendliness
   + Huge factor in many designs
   + More in next lecture 
 - Today's paper assumes a simple model
   + The distributed memory should behave like a single memory
   + Load/stores much like put/gets in labs 2-4

<a name="example-1"></a>
**Example 1:**

      x and y start out = 0

      M0:
        x = 1
        if y == 0:
          print yes
      M1:
        y = 1
        if x == 0:
          print yes

      Can they both print "yes"?

Naive distributed shared memory

<a name="diagram-1"></a>
**Diagram 1:**

 - M0, M1, M2, LAN
 - each machine has a local copy of all of memory
 - read: from local memory
 - write: send update msg to each other host (but don't wait)
 - fast: never waits for communication

Does this naive memory work well?

 - What will it do with [Example 1](#example-1)?
   + It can fail because M0 and M1 could not see the 
     writes by the time their `if` statements are reached
     so they will both print _yes_.
 - Naive distributed memory is fast but incorrect

Diagram (broken scheme):

             M0
        *----------*   *----------*   *----------*
        |          |   |          |   |          |
        |        ------------------------> wAx   |
        |        ----------> wAx  |   |          |
        *-----*----*   *-----*----*   *-----*----*
              |              |              |
      --------*--------------*--------------*-------- LAN

 - M0 does write locally and tells other machines about the 
   write after it has done it
 - imagine what output you would get instead of 9, if each
   machine was running a program that incremented the value
   at address A 3 times

Coherence = _sequential consistency_

 + "Read sees _most recent_ write" is not clear enough when you
   have multiple processes
 + Need to nail down correctness a bit more precisely 
 + Sequential consistency means:
   - The result of any execution is the same as if 
     + the operations of all the processors were executed in some sequential order (total order)
     + and the operations of each individual processor appear in this sequence 
       in the order specified by its program 
       - (if P says A before B, you can't have B; A; show up in that seq. order)
     + and read sees last write in total order
 + There must be some total order of operations such that
   1. Each machine's instructions appear in-order in the order
   2. All machines see results consistent with that order
      - i.e. reads see most recent write in the order
 + Behavior of a single shared memory

Would sequential consistency cause our example to get the intuitive result?

Sequence:

      M0: Wx1 Ry?
      M1: Wy1 Rx?

 - The system is required to merge these into one order,
   and to maintain the order of each machine's operations.
 - So there are a few possibilities:
   + `Wx1 Ry0 Wy1 Rx1`
   + `Wx1 Wy1 Ry1 Rx1`
   + `Wx1 Wy1 Rx1 Ry1`
   + others too, but all symmetric?
 - What is forbidden?
   + `Wx1 Ry0 Wy1 Rx0` -- Rx0 read didn't see preceding Wx1 write (naive system did this)
   + `Ry0 Wy1 Rx0 Wx1` -- M0's instructions out of order (some CPUs do this)

Go's memory consistency model

 - What is Go's semantics for the example?
 - Go would allow both goroutines to print "yes"!
 - Go race detector wouldn't like the example program anyway
 - Programmer is *required* to use locks/channels to get sensible semantics
 - Go doesn't require the hardware/DSM to implement strict consistency
 - More about weaker consistency on Thursday

Example:

    x = 1
    y = 2

 - Go's memory model tells you if thread A will see the write to x if it has seen the write to y
    + In Go, there's no guarantee x's write will be seen if y was written

A simple implementation of sequential consistency

A straightforward way to get sequential consistency: Just have
a manager in between the two or three machines that interleaves
their instructions

        *----------*   *----------*   
        |          |   |          |   
        |          |   |          |   
        |          |   |          |   
        *-----*----*   *-----*----*   
              |              |        
      --------*--------------*--------
                     |
                     |
               *----------*
               | inter-   |
               | leaver   |
               |          |
               *-----*----*
                     |
                    -*-
                    \ /
                     .
                    RAM

<a name="diagram-2"></a>
**Diagram 2:**

        *----------*   *----------*   
        |          |   |          |   
        |          |   |          |   
        |          |   |          |   
        *-----*----*   *-----*----*   
              |              |        
      --------*--------------*--------
                     |
                     |
               *----------*
               |          |
               |          |
               |          |
               *-----*----*
                     |
                    -*-
                    \ /
                     .
                    RAM

 - single memory server
 - each machine sends r/w ops to server, in order, waiting for reply
 - server picks order among waiting ops
 - server executes one by one, sending replies
 - big ideas:
   + if people just read some data, we can replicate it on all of them
   + if someone writes data, we need to prevent other people from writing it
     - so we take the page out of those other people's memory
  
This simple implementation will be slow

 - single server will get overloaded
 - no local cache, so all operations wait for server

Which brings us to **IVY**

 - IVY: Integrated shared Virtual memory at Yale
 - Memory Coherence in Shared Virtual Memory Systems, Li and Hudak, PODC 1986

IVY big picture

<a name="diagram-3"></a>

      [diagram: M0 w/ a few pages of mem, M1 w/ a few pages, LAN]

 - Operates on pages of memory, stored in machine DRAM (no mem server)
 - Each page present in each machine's virtual address space
 - On each a machine, a page might be invalid, read-only, or read-write
 - Uses VM hardware to intercept reads/writes

Invariant:

 - A page is either:
   + Read/write on one machine, invalid on all others; or
   + Read/only on $\geq 1$ machines, read/write on none
 - Read fault on an invalid page:
   + Demote R/W (if any) to R/O
   + Copy page
   + Mark local copy R/O
 - Write fault on an R/O page:
   + Invalidate all copies
   + Mark local copy R/W
  
IVY allows multiple reader copies between writes

 - For speed -- local reads are fast
 - No need to force an order for reads that occur between two writes
 - Let them occur concurrently -- a copy of the page at each reader

Why crucial to invalidate all copies before write?

 - Once a write completes, all subsequent reads *must* see new data
 - Otherwise we break our example, and don't get sequential consistency

How does IVY do on the example?

 - I.e. could both M0 and M1 print "yes"?
 - If M0 sees y == 0,
   + M1 hasn't done ites write to y (no stale data == reads see prior writes),
   + M1 hasn't read x (each machine in order),
   + M1 must see x == 1 (no stale data == reads see prior writes).

Message types:

 + [don't list these on board, just for reference]
 - RQ read query (reader to manager (MGR))
 - RF read forward (MGR to owner)
 - RD read data (owner to reader)
 - RC read confirm (reader to MGR)
 - &c

(see [ivy-code.txt](code/ivy-code.txt) on web site)

Scenario 1: M0 has writeable copy, M1 wants to read

**Diagram 3:**

      [time diagram: M 0 1]

  0. M1 tries to read gets a page fault
     + b.c. page must have been marked invalid since
       M0 has it for R/W (see invariant described earlier)
  1. M1 sends RQ to MGR
  2. MGR sends RF to M0, MGR adds M1 to `copy_set`
     + What is `copy_set`?
     + "The `copy_set` field lists all processors that have copies of the page. 
       This allows an invalidation operation to be performed without using
       broadcast."
  3. M0 marks page as $access = read$, sends RD to M1
  5. M1 marks $access = read$, sends RC to MGR

Scenario 2: now M2 wants to write

**Diagram 4:**

      [time diagram: M 0 1 2]

  0. Page fault on M2
  1. M2 sends WQ to MGR
  2. MGR sends IV to copy_set (i.e. M1)
  3. M1 sends IC msg to MGR
  4. MGR sends WF to M0, sets owner=M2, copy_set={}
  5. M0 sends WD to M2, access=none
  6. M2 marks r/w, sends WC to MGR

**Q:** What if two machines want to write the same page at the same time?

**Q:** What if one machine reads just as ownership is changing hands?

Does IVY provide strict consistency?

 - no: MGR might process two STs in order opposite to issue time
 - no: ST may take a long time to revoke read access on other machines
   + so LDs may get old data long after the ST issues

What if there were no IC message?

**TODO:** What is IC?

 - (this is the new Question)
 - i.e. MGR didn't wait for holders of copies to ACK?

No WC?

**TODO:** What is WC?

 - (this used to be The Question)
 - e.g. MGR unlocked after sending WF to M0?
 - MGR would send subsequent RF, WF to M2 (new owner)
 - What if such a WF/RF arrived at M2 before WD?
   + No problem! M2 has `ptable[p].lock` locked until it gets WD
 - RC + `info[p].lock` prevents RF from being overtaken by a WF
 - so it's not clear why WC is needed!
   + but I am not confident in this conclusion

What if there were no RC message?

 - i.e. MGR unlocked after sending RF?
 - could RF be overtaken by subsequent WF?
 - or by a subsequent IV?

In what situations will IVY perform well?

 1. Page read by many machines, written by none
 2. Page written by just one machine at a time, not used at all by others

Cool that IVY moves pages around in response to changing use patterns

Will page size of e.g. 4096 bytes be good or bad?

 - good if spatial locality, i.e. program looks at large blocks of data
 - bad if program writes just a few bytes in a page
   + subsequent readers copy whole page just to get a few new bytes
 - bad if false sharing
   + i.e. two unrelated variables on the same page
     - and at least one is frequently written
   + page will bounce between different machines
     - even read-only users of a non-changing variable will get invalidations
   + even though those computers never use the same location

What about IVY's performance?

 - after all, the point was speedup via parallelism

What's the best we could hope for in terms of performance?

 - $N \times$ faster on N machines

What might prevent us from getting $N \times$ speedup?

 - Application is inherently non-scalable
   + Can't be split into parallel activities
 - Application communicates too many bytes
   + So network prevents more machines yielding more performance
 - Too many small reads/writes to shared pages
   + Even if # bytes is small, IVY makes this expensive

How well do they do?

 - Figure 4: near-linear for PDE (partial derivative equations)
 - Figure 6: very sub-linear for sort
   + sorting a huge array involves moving a lot of data
   + almost certain to move all data over the network at least once
 - Figure 7: near-linear for matrix multiply
 - in general, you end up being limited by network throughput
   for instance when reading a lot of pages

Why did sort do poorly?

 - Here's my guess
 - N machines, data in 2*N partitions
 - Phase 1: Local sort of 2*N partitions for N machines
 - Phase 2: 2N-1 merge-splits; each round sends all data over network
 - Phase 1 probably gets linear speedup
 - Phase 2 probably does not -- limited by LAN speed
   + also more machines may mean more rounds
 - So for small # machines, local sort dominates, more machines helps
 - For large # machines, communication dominates, more machines don't help
 - Also, more machines shifts from n*log(n) local sort to n^2 bubble-ish short

How could one speed up IVY?

 - next lecture: relax the consistency model
   + allow multiple writers to same page!

Paper intro says DSM subsumes RPC -- is that true?

 - When would DSM be better than RPC?
   + More transparent. Easier to program.
 - When would RPC be better?
   + Isolation. Control over communication. Tolerate latency.
   + Portability. Define your own semantics.
   + Abstraction?
 - Might you still want RPC in your DSM system? For efficient sleep/wakeup?

Known problems in Section 3.1 pseudo-code

 - Fault handlers must wait for owner to send `p` before confirming to manager
 - Deadlock if owner has page R/O and takes write fault
   + Worrisome that no clear order `ptable[p].lock` vs `info[p].lock`
   + TODO: Whaaaat?
 - Write server / manager must set `owner = request_node`
 - Manager parts of fault handlers don't ask owner for the page
 - Does processing of the invalidate request hold `ptable[p].lock?`
   + probably can't -- deadlock
