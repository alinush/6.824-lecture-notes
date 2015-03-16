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

Q2 2013
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

**Answer:**  
