Q1 2014
=======

1. MapReduce
------------

### [Question 1](qs/q1-2014/q14-1-1.png)

**Answer:** The Map jobs are ran in parallel and once they are done, the reduce jobs are ran in parallel as well.

You can imagine implementing the `wc` example by having the `Map` calls doing `Put()` and `Get()` calls to store and increment the counts for the words. `Increment(w)` would be `c = Get(w); Put(w, c+1)`. However, this will be bound to have race conditions when two `Map()` calls increment the count for the same word `w`:

    Map1: c1 = Get(w) 
    Map2: c1 = Get(w)
    // note that they both get the same count
    Map1: Put(w, c1+1)
    Map2: Put(w, c1+1)

If the count were `c` before the two calls executed, then it will be `c+1` instead of `c+2` after they finished.

2. Non-determ. and repl. state mach.
------------------------------------

### [Question 2](qs/q1-2014/q14-2-2.png)

**Answer:** In my lab 3, whenever agreement is reached for a certain paxos instance, a Decided message is broadcast to everyone and waited upon for receipt confirmation by everyone. The timestamp can be included in this message. When to generate it? Before a Prepare call. If the proposer's value was the accepted value, then his timestamp is used. If it was another's proposer's value, then the timestamp included with that value should be used.

The problem with this is that you could have a Put(a, v2) decide at log entry i+1, before a Put(a, v1) had a chance to decide at log entry i, so then a later Put() would have an earlier timestamp than an earlier Put(), which would be incorrect

A different approach would be to start two agreements for a Put(), one with a timestamp and one for the actual Put(). The problem with this approach is the interleaving of these agreements for two Put() requests will mess things up?

It seems that the only way to get this to work is to make sure that everything is decided up to seq. i before you propose and accept the Put() at seq i+1, then you can use the Decided timestamping approach. 

Not quite replicated state machines
-----------------------------------

### [Question 3](qs/q1-2014/q14-3-3.pdf)

Q: What does `PutHash(k, v)` do?
A: returns old `db[k]` and sets new `db[k] = hash(db[k] + v)`. Can be used to chain all values for a key together. Useful when testing apparently

Example:

    `Put(a, 'lol')`
    `PutHash(a, 'sd') -> lol`
    `Get(a)` -> hash('lol' + 'sd')


Answer:

                                Primary                         Backup
       c1 - PutHash(a,v1) ->       |S1                            |S2
                |                  |db[a]=v0                      |db[a]=v0
                |                  |     -- fwd op -->            |
                |                  |                              | execs op =>
                |                  |                              |db[a]=h(v0|v1)
                |                  |                              |dups[reqid]=v0 
                |                  |       x-- op reply fails --  | 
                |                  |           due to net fail    |
                |                  |                              |
                \                  |S1                            |S2
                 |                 |db[a]=v0                      |db[a]=h(v0|v1)      
       c2 - PutHash(a,v2) ->       |                              |
                 |                 |     -- fwd op -->            | execs op =>        
                 |                 |                              |db[a]=h(h(v0|v1)|v2)
                 |                 |                              |
                 |                 |   <-- reply goes back to S1  |
                 |                 |       and S1 replies to c2   |
                 |                 |                              |
                /                  |db[a]=h(h(v0|v1)|v2)          |
                |---------->       |S1                            |S2
                                   |                              | fails!!
                                   | no duplicate info at         |
                                   | S1 about c1's requst         |
                                   | so it'll be reeexecuted      |
                                   |                              |
                                   |                              |

Flat datacenter storage
-----------------------

### [Question 4](qs/q1-2014/q14-4-4.png)

**Answer:** This is silly: If Ben's design returns to the client after hearing from JUST one server, then the blob's size is NOT REALLY extended: i.e. there are still servers that don't know about that new size. So when the client will contact them with a write to tract n-1 just after ExtendBlobSize(n), a bunch of these writes will fail because the servers will return an out-of-bounds error.

Literally, ANY application that calls extend and then write will fail.

**Their answer:** If two separate clients try to extend the size of the blob by 1 tract (paper doesn't make it clear if you specify new size or additional size), and they talk to different servers and both reply "Extended successfully" back, then when the two clients will write this newly added tract, they will overwrite each other's writes, instead of writing separately to tract `n+1` and `n+2` (assuming `n` was the size of the blob before extending).

### [Question 5](qs/q1-2014/q14-4-5.png)

**Answer:** Seems like it must reply ABORT to a PREPARE request `r1` when there's another request `r0` that has successfully prepared.

Paxos
----

### [Question 6](qs/q1-2014/q14-5-6.png)

**Answer:** This is wrong, because acceptors could accept a value that's never been proposed.

Diagram:
    
    px -- means server received prepare(n=1)
    axvy -- means server received accept(n=x, v=y)
    dx  -- means server received decided(v=x)

    S1: starts proposal loop w/ n = 1

    S1: p1       |              offiline for a while ...
    S2: p1       |    reboot => na = np = 1, va=nil     | p2 |  a1v<nil> | d<nil>
    S3:     p1   |    reboot => na = np = 1, va=nil     | p2 |  a1v<nil> | d<nil>

**Their answer:**

    S1: p1        p2    a2v2
    S2: p1  a1v1                p3 (np=3)  reboot, restore(np=na=3)  p4 (S2 replies w/ na=3,v=1)     a4v1
    S3: p1        p2    a2v2                                         p4 (S3 replies w/ na=2,v=2)     a4v1

### [Question 7](qs/q1-2014/q14-5-7.png)

**Answer:** Not linearizable because:

    C1 sends a Get() to S1
    S1 starts Paxos for that Get() at seq 0
    C2 sends a Put() to S2
    S1 starts Paxos for that Put(a, "1") at seq 1
    S1 gets consensus for the Put(a, "1") at seq 1
    S1 returns success to to C2
    C2 issues another Put(a, "2"), but it goes to S2
    S2 starts Paxos for that Put(a, "2") at seq 0
    S2 gets agreement for that Put(a, "2") at seq 0
        it won over C1/S1's Get() at seq 0
    Now the earlier Put() is at seq 1 and the later Put() is at seq 0
     => not linearizable

### [Question 8](qs/q1-2014/q14-5-8.png)

**Answer:** No EPaxos this semester.

Spanner
-------

### [Question 9](qs/q1-2014/q14-6-9.png)

**Answer:** TODO for Quiz 2

Harp
----

### [Question 10](qs/q1-2014/q14-7-10.png)

**Answer:**

    A. True
    B. False
    C. True
    D. True
    E. False

Q2 2014
=======

Memory models
-------------

### Question 1

**Answer:** world

### Question 2

**Answer**: 

 - hello
 - world
 - never ending loop because read to done doesn't have to observe the write in the thread

### Question 3

**Answer**: Go's memory model is more similar to release consistency, whereas Ivy's is sequential consistency => if you don't use locks/channels in Go to synchronize reads/writes, then funny things will happen

### Question 4

**Answer:**
In TreadMarks, the program would loop infinitely, because there's no acquire on a lock for the `done` variable => no one can inform the `done` reader than done has been set to true.

### Question 5

**Answer:**
Adding a lock around the write and the read to `done` is enough. Or not clear... does causal consistency give you previous writes that did not contribute to the write to `done`? If it does not, then you also need to include the write to `a` under the lock.
For efficiency, something like a semaphore can be used to make sure the write happens before the read.

Ficus
-----

### Question 6

**Answer:**
H4 will have the latest VT [1,1,0,0] so it will print 2 for both cat's

### Question 7

**Answer:**
[1,1,0,0]

### Question 8

**Answer:**
[1,0,0,0]

### Question 9

**Answer:**

    h1: f=1, [1,0,0,0] ->h2                                f=3 [2,0,0,0]                  ->h4
    h2:                     [1,0,0,0] f=2 [1,1,0,0] ->h4
    h3:
    h4:                                                    [1,1,0,0] cat f [prints 2]         conflict on f b.c. [2,0,0,0] and [1,1,0,0]

### Question 10 through 22


**Answer:** TODO: Next quiz!

Q1 2013
=======

Paxos
-----

### Question 1

Why is decide phase in Paxos unnecessary?

**Answer:**

 - Because any other Paxos peer can learn the agreed upon value by starting a proposal loop. He will Prepare(n) and get replies with na's and va's set that will contain the accepted value.
 - The agreement/consensus of paxos does NOT depend on the decided phase: it's a property of the whole system (i.e. have a majority of acceptors accepted the same value `v`?)
   + The agreement/consensus can be learned _without_ doing a decided phase

### Question 2


**Answer:**


    S1 starts proposal w/ n=1 and v=A
    S2 starts proposal w/ n=2 and v=B

    S1: p1 p2   rejected a1   
    S2: p1 p2   rejected a1    
    S3: p1 p2   rejected a1

    S1 did not reach agreement after 1st round
    S1 restarts proposal w/ n=3 and v=A

    S1: p1 p2   rejected a1  |  p3    rejected a2
    S2: p1 p2   rejected a1  |  p3    rejected a2
    S3: p1 p2   rejected a1  |  p3    rejected a2

    S2 does not reach agreement after 1st round

Flat datacenter storage
-----------------------

### Question 3

**Answer:** If the failed tractserver is replaced with just ONE server from the empty pool that is strictly worse than replacing it with multiple already live servers, because it is faster to write to more servers at the same time than writing to a single server.

Spanner
-------

### Question 4-6

TODO: next quiz

Distributed Shared Memory
-------------------------

### Question 7

**Answer:** write diffs fixed the write amplification problem, where writing one byte on a page resulted in sending the whole page to a reader. Thus, since there's no such problem in byte-IVY (i.e. writing a byte means sending a byte to a reader), the answer is no.


### Question 8

**Answer:** LRC fixed the false sharing problem, where if two processes wrote different variables on the same page, that page would be bounced back and forth between the two processes, even though the two processes never needed to hear about each other's changes (they did not share those variables)

This question can be answered in two ways:

1. If you reasonable assume that the smallest variable is a byte (which is true on today's computers), then when two processes write the same page they are writing the same variable and the sharing is _true_. There can't be any false sharing by "construction" so to speak. Thus, LRC is not needed.

2. If you consider variables that are smaller than a byte (which is cuckoo), then maybe there's an argument for how LRC can help with false sharing within a 1-byte page with 2 4-bit variables or with 4 2-bit variables, etc.

CBCAST
------

Scenario:

    sX - sends X to all
    rX - receives message X, does not deliver to app yet
    dX - delivers X to app


    M1: sX            sZ
    M2:     rX dY sY
    M3:

### Question 9

    X -- [1,0,0]
    Y -- [1,1,0]
    Z -- [2,0,0] if M1 didn't get Y yet
         [2,0,1] if M1 got Y

### Question 10

Can M3 get msgs in the following orders?

    X Y Z - yes [0,0,0] -> [1,0,0] -> [1,1,0] -> [2,1,0]
    X Z Y - yes [0,0,0] -> [1,0,0] -> [2,0,0] -> [2,1,0]
    Y X Z - no  [0,0,0] cannot go to [1,1,0] must wait for X
    Y Z X - no same as before
    Z X Y - nope
    Z Y X - nope

Lab 2
-----

    P:S0    B:S1
    S1 has copy of S0 state
    S0 and S1 have been processing requests
    ...
    S0 fwds req to S1, but S0's rpclib returns an error indicating no reply from S1
    S0 did not hear of any view change from viewserver

### Question 11

Can S0 execute the request and return a success to client?

**Answer:** That could be a recipe for disaster, because S1 could have failed and the viewserver could be in the middle of realizing this. If S0 executes the op and replies and if S1 really went down and did not have a chance to replicate, then we could create an inconsistent state. If S1 comes back quickly enough and the view remains the same, then S1 missed this op. Once S1 becomes primary, it will not have the op => inconsistency.

### Question 12

**Answer:**  According to our lab specs, no. The client calls are NOT allowed to fail, so if S0 tells the client 'sorry boss, no can't do...' then the client will have to shrug its shoulders and pretend like the op succeeded: the spec doesn't allow it to fail.

In a realistic world, the client can return an error code to the caller and the caller can retry the client call. So S0 could return a failure to the client, like a timeout.

**Their answer:** Their angle was that the backup could have executed the primary's replicate op, but the reply got lost. And so if the primary tells the client it has failed, that would be incorrect. And now the primary and the backup are not replicas anymore. I guess I didn't even look that far because I assumed informing the client of a failure would be unacceptable since he won't know how to handle it. However, the client could just retry again.

### Question 13

**Answer:** 

    C1 sends op to S1
    S1 starts agreement for the op at seq# i
    S1 replies to C1 when it gets agreement for op at seq #i
    Reply gets lost
    C1 retries, sends op to S2
    S2 starts agreement for the op at seq #j, j != i (because maybe S2 did not take part in S1's agreement at seq# i, maybe it was partitioned)
    S2 gets agreement
    S2 replies to C1
    C1 gets reply

    ...

    Now servers have the same op twice in the log at seq #i and #j

    If this is an Append() op, then we create an inconsistent state

Q2 2013
=======

Lab 4
-----

### Question 1

TODO for quiz 2

Bayou
-----

### Question 2

TODO for quiz 2

### Question 3

TODO for quiz 2

### Question 4

TODO for quiz 2

### Question 

Dynamo
------

### Question 5

TODO for quiz 2

Two phase commit or Paxos
-------------------------

### Question 6

TODO for quiz 2

Argus
-----

### Question 7

TODO for quiz 2

MapReduce
---------

### Question 8

TODO for quiz 2

### Question 9

TODO for quiz 2

Bitcoin
-------

### Question 10

TODO for quiz 2

Memcached at Facebook
---------------------

### Question 11

TODO for quiz 2 

### Question 12

TODO for quiz 2
