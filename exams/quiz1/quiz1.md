Q1 2014
=======

1. MapReduce
------------

### [Question 1](qs/q14-1-1.png)

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

### [Question 2](qs/q14-2-2.png)

**Answer:** In my lab 3, whenever agreement is reached for a certain paxos instance, a Decided message is broadcast to everyone and waited upon for receipt confirmation by everyone. The timestamp can be included in this message. When to generate it? Before a Prepare call. If the proposer's value was the accepted value, then his timestamp is used. If it was another's proposer's value, then the timestamp included with that value should be used.

The problem with this is that you could have a Put(a, v2) decide at log entry i+1, before a Put(a, v1) had a chance to decide at log entry i, so then a later Put() would have an earlier timestamp than an earlier Put(), which would be incorrect

A different approach would be to start two agreements for a Put(), one with a timestamp and one for the actual Put(). The problem with this approach is the interleaving of these agreements for two Put() requests will mess things up?

It seems that the only way to get this to work is to make sure that everything is decided up to seq. i before you propose and accept the Put() at seq i+1, then you can use the Decided timestamping approach. 

Not quite replicated state machines
-----------------------------------

### [Question 3](qs/q14-3-3.pdf)

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

### [Question 4](qs/q14-4-4.png)


