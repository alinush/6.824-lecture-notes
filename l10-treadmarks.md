6.824 2015 Lecture 10: Consistency
==================================

**Note:** These lecture notes were slightly modified from the ones posted on the 6.824 
[course website](http://nil.csail.mit.edu/6.824/2015/schedule.html) from Spring 2015.

**Today:** consistency

 - Lazy release consistency
 - Using lazy consistency to get performance
 - Consistency = meaning of concurrent reads and writes
 - Less obvious than it may seem!
 - Choice trades off between performance and programmer-friendliness
   + Huge factor in many designs
 - [Today's paper](papers/keleher-treadmarks.pdf): a case study

Many systems have storage/memory w/ concurrent readers and writers

 - Multiprocessors, databases, AFS, labs
 - You often want to improve in ways that risk changing behavior:
   + add caching
   + split over multiple servers
   + replicate for fault tolerance
 - How do we know if an optimization is correct?
 - We need a way to think about correct execution of distributed programs
 - Most of these ideas from multiprocessors and databases 20/30 years ago

How can we write correct distributed programs w/ shared storage?

 - Memory system promises to behave according to certain rules
 - We write programs assuming those rules
 - Rules are a "consistency model"
 - Contract between memory system and programmer

What makes a good consistency model?

 - There are no "right" or "wrong" models
 - A model may make it harder or easier to program
   + i.e. lead to more or less intuitive results
 - A model may be harder or easier to implement efficiently
 - Also application dependent
   + e.g. Web pages vs memory

Some consistency models:

 - Spanner: external consistency  (behaves like a single machine)
 - Database world: strict serializability, serializability, snap-shot isolation, read-committed
 - Distributed file systems: open-to-close consistency
 - Computer architects: TSO (total store ordering), release consistency, etc.
 - Concurrency theory: sequential consistency, linearizability
 - Similar ideas, but sometimes slightly different meaning

DSM is a good place to start to study consistency

 - Simple interface: read and write of memory locations
 - Consistency well developed in architecture community

Example:

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

Performance of DSM is limited by memory consistency

 - With sequential consistency, M0's write must be visible to M1 before M0 can execute read
   + Otherwise both M0 and M1 can read 0 and print "yes"
   + (Second "forbidden" example)
 - Thus operations will take a while in a distributed system
   + And they have to be done one by one

Treadmarks high level goals?

 - Better DSM performance
 - Run existing parallel code (multithreaded)
   + this code already has locks
   + TreadMarks will run each thread/process on a separate machine and
     let it access the DSM.
   + TreadMarks takes advantage that the code already uses locking

What specific problems with previous DSM are they trying to fix?

 - **false sharing:** two machines r/w different vars on same page
   + m1 writes x, m2 writes y
   + m1 writes x, m2 just reads y
   + **Q:** what does IVY do in this situation?
   + **A:** Ivy will bounce the page between x and y back and forth
 - **Write amplification:** a 1-byte write turns into a whole-page transfer

**First Goal:** eliminate write amplification

 - don't send whole page, just written bytes

### Big idea: write diffs (to fix write amplification)

Example: 

    m1 and m2 both have x's page as readable
    m1 writes x
                m2 just reads x

 - on M1 write fault:
   + tell other hosts to invalidate but _keep hidden copy_
   + M1 makes hidden copy as well
   + M1 marks the page as R/W
 - on M2 read fault:
   + M2 asks M1 for recent modifications
   + M1 "diffs" current page against hidden copy
   + M1 send diffs to M2
   + M2 applies diffs to its hidden copy
   + M2 marks the page as read-only
   + M1 marks the page as read-only

**Q:** Do write diffs provide sequential consistency?

 - At most one writeable copy, so writes are ordered
 - No writing while any copy is readable, so no stale reads
 - Readable copies are up to date, so no stale reads
 - Still sequentially consistent

**Q:** Do write diffs help with false sharing?  
**A:** No, they help with write amplification

Next goal: allow multiple readers+writers to cope with false sharing

 - our solution needs to allow two machines to write the same page
 - `=>` don't invalidate others when a machine writes
 - `=>` don't demote writers to r/o when another machine reads
 - `=>` multiple *different* copies of a page!
   + which should a reader look at?
 - diffs help: can merge writes to same page
 - but when to send the diffs?
   + no invalidations -> no page faults -> what triggers sending diffs

...so we come to _release consistency_

### Big idea: (eager) release consistency (RC)

 - _Again:_ what should trigger sending diffs?
 - Seems like we should be sending the diffs when someone reads the data
   that was changed. How can we tell someone's reading the data if we
   won't get a read fault because we did not invalidate other people's
   pages when it was written by one person?
 - no-one should read data w/o holding a lock!
   + so let's assume a lock server
 - send out write diffs on release (unlock)
   + to *all* machines with a copy of the written page(s)

Example:

    lock()
    x = 1
    unlock() --> diffs all pages, to detect all the writes since
                 the last unlock
             --> sends diffs to *all* machines

**Q:** Why detect all writes since the last `unlock()` and not the last `lock()`?

**A:** See causal consistency discussion below.

Example 1 (RC and false sharing)

    x and y are on the same page
    ax -- acquire lock x
    rx -- release lock x

    M0: a1 for(...) x++ r1
    M1: a2 for(...) y++ r2  a1 print x, y r1

What does RC do?

 - M0 and M1 both get cached writeable copy of the page
 - when they release, each computes diffs against original page
 - `M1`'s `a1` causes it to wait until `M0`'s `r1` release
   + so M1 will see M0's writes

**Q:** What is the performance benefit of RC?

 - What does IVY do with Example 1?
   + if `x` and `y` are on the same page, page is bounced back between `M0` and `M1`
 - multiple machines can have copies of a page, even when 1 or more writes
   + `=>` no bouncing of pages due to false sharing
   + `=>` read copies can co-exist with writers

**Q:** Is RC sequentially consistent? No!

 - in SC, a read sees the latest write
 - M1 won't see M0's writes until M0 releases a lock
   + i.e. M1 can see a stale copy of x, which wasn't allowed under seq const
 - so machines can temporarily disagree on memory contents
 - if you always lock:
   + locks force order `->` no stale reads `->` like sequential consistency

**Q:** What if you don't lock?

 - Reads can return stale data
 - Concurrent writes to same var -> trouble

**Q:** Does RC make sense without write diffs?

 - Probably not: diffs needed to reconcile concurrent writes to same page

### Big idea: lazy release consistency (LRC)

 - one problem is that when we `unlock()` we update everybody,
   but not everyone might need the changed data
 - only send write diffs to next acquirer of released lock
   + (i.e. when someone calls `lock()` and they need updates to the 
      data)
 - lazier than RC in two ways:
   + release does nothing, so maybe defer work to future release
   + sends write diffs just to acquirer, not everyone

Example 2 (lazyness)

    x and y on same page (otherwise IVY avoids copy too)

    M0: a1 x=1 r1
    M1:           a2 y=1 r2
    M2:                     a1 print x,y r1

What does LRC do?

 + M2 asks the lock manager who the previous holder of lock 1 was
   + it was M1
 + M2 only asks previous holder of lock 1 for write diffs
 + M2 does not see M1's modification to `y`, even though on same page
   - because it did not acquire lock 2 using `a2`

What does RC do?

 + RC would have broadcast all changes on `x` and `y` to everyone

What does IVY do?

 + IVY would invalidate pages and ensure only the writer has a write-only
   copy
 + on reads, the written page is turned to read only and the data is 
   fetched by the readers

**Q:** What's the performance win from LRC?

 - if you don't acquire lock on object, you don't see updates to it
 - `=>` if you use just some vars on a page, you don't see writes to others
 - `=>` less network traffic

**Q:** Does LRC provide the same consistency model as RC?

 - **No!** LRC hides some writes that RC reveals
 - Note: if you use locks correctly, then you should not notice the differences
   between (E)RC and LRC
 - in above example, RC reveals `y=1` to M2, LRC does not reveal
   + because RC broadcasts changes on a lock release
 - so `"M2: print x, y"` might print fresh data for RC, stale for LRC
   + depends on whether print is before/after M1's release

**Q:** Is LRC a win over IVY if each variable on a separate page?

 - IVY doesn't move data until the program tries to read it
   + So Ivy is pretty lazy already
 - Robert: TreadMarks is only worth it pages are big
 - Or a win over IVY plus write diffs?

Do we think all threaded/locking code will work with LRC?

 - Do all programs lock every shared variable they read?
 - Paper doesn't quite say, but strongly implies "no"!

Example 3 (causal anomaly)

    M0: a1 x=1 r1
    M1:             a1 a2 y=x r2 r1
    M2:                               a2 print x, y r2

What's the potential problem here?

 - Counter-intuitive that M2 might see y=1 but x=0
   + because M2 didn't acquire lock 1, it could not get
     the changes to `x`

A violation of "causal consistency":

 - If write W1 contributed to write W2, everyone sees W1 before W2
  

Example 4 (there's an argument that this is _natural cod_):
    
    M0: x=7    a1 y=&x r1
    M1:                     a1 a2 z=y r2 r1  
    M2:                                       a2 print *z r2

In example 4, it's not clear if M2 will learn from M1 the writes that M0 also did
and contributed to `y=&x`.

 - for instance, if `x` was 1 before it was changed by M0, will M2 see this when it prints `*z`

TreadMarks provides **causal consistency**:

 - when you acquire a lock,
 - you see all writes by previous holder
 - and all writes previous holder saw 

How to track what writes contributed to a write?

 - Number each machine's releases -- "interval" numbers
 - Each machine tracks highest write it has seen from each other machine
   + highest write = the interval # of the last write that machine is aware of
   + a "Vector Timestamp"
 - Tag each release with current VT
 - On acquire, tell previous holder your VT
   + difference indicates which writes need to be sent
 - (annotate previous example)
 - when can you throw diffs away?
   + seems like you need to globally know what everyone knows about
   + see "Garbage Collection" section from paper

VTs order writes to same variable by different machines:

    M0: a1 x=1 r1  a2 y=9 r2
    M1:              a1 x=2 r1
    M2:                           a1 a2 z = x + y r2 r1

    M2 is going to hear "x=1" from M0, and "x=2" from M1.
    TODO: what about y?

How does M2 know what to do?

Could the VTs for two values of the same variable not be ordered?

    M0: a1 x=1 r1
    M1:              a2 x=2 r2
    M2:                           a1 a2 print x r2 r1

### Summary of programmer rules / system guarantees

  1. Each shared variable protected by some lock
  2. Lock before writing a shared variable to order writes to same var., 
     otherwise "latest value" not well defined
  3. Lock before reading a shared variable to get the latest version
  4. If no lock for read, guaranteed to see values that
     contributed to the variables you did lock

Example of when LRC might work too hard.

    M0: a2 z=99 r2  a1 x=1 r1
    M1:                            a1 y=x r1

TreadMarks will send `z` to M1, because it comes before `x=1` in VT order.

 - Assuming x and z are on the same page.
 - Even if on different pages, M1 must invalidate z's page.
 - But M1 doesn't use z.
 - How could a system understand that z isn't needed?
   + Require locking of all data you read
   + `=>` Relax the causal part of the LRC model

**Q:** Could TreadMarks work without using VM page protection?

 - it uses VM to
   + detect writes to avoid making hidden copies (for diffs) if not needed
   + detect reads to pages => know whether to fetch a diff
 - neither is really crucial
 - so TM doesn't depend on VM as much as IVY does
   + IVY used VM faults to decide what data has to be moved, and when
   + TM uses acquire()/release() and diffs for that purpose

### Performance?

Figure 3 shows mostly good scaling

 - is that the same as "good"?
 - though apparently Water does lots of locking / sharing

How close are they to best possible performance?

 - maybe Figure 5 implies there is only about 20% fat to be cut

Does LRC beat previous DSM schemes?

 - they only compare against their own straw-man eager realease consistency (ERC)
   + not against best known prior work
 - Figure 9 suggests not much win, even for Water

### Has DSM been successful?

 - clusters of cooperating machines are hugely successful
 - DSM not so much
   + main justification is transparency for existing threaded code
   + that's not interesting for new apps
   + and transparency makes it hard to get high performance
 - MapReduce or message-passing or shared storage more common than DSM
