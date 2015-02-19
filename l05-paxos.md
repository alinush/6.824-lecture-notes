6.824 2015 Lecture 5: Paxos
===========================

**Note:** These lecture notes were slightly modified from the ones posted on the 6.824 
[course website](http://nil.csail.mit.edu/6.824/2015/schedule.html) from Spring 2015.

Intro
-----

Starting a new group of lectures on stronger fault tolerance

 + Today:
   - cleaner approach to replication: RSM via Paxos
   - Lab 3
 + Subsequent lectures:
   + How to use Paxos to build systems (Harp, EPaxos, Spanner)

Paxos
-----
From [Paxos Made Simple](paxos.pdf), by Leslie Lamport, 2001

Recall: RSM

 + maintain replicas by executing operations in the same order
 + requires all replicas to agree on the (set and) order of operations

Lab 2 critique

 + primary/backup with viewserver
 + **pro:**
   - conceptually simple
   - just two msgs per op (request, reply)
   - primary can do computation, send result to bkup
   - only two k/v servers needed to tolerate one failure
 + **con:**
   - viewserver is single point of failure
   - order can be messy, e.g. new view, data to backup, ack, &c
   - tension if backup is slow / temporarily unavail
     1. primary can wait for backup -- slow
     2. viewserver can declare backup dead -- expensive, hurts fault tolerance

We would like a general-purpose ordering scheme with:

 + no single point of failure
 + graceful handling of slow / intermittent replicas

**Paxos** will be a key building block for this.

 - some number of nodes participate in _an instance of Paxos_
   + **Q:** What is this _instance_?
   + **A:** _"Each new command requires a separate Paxos agreement, which the
     paper calls an instance. So the database replicas might agree that the
     first command to execute is 'command one', and they use Paxos to agree
     on that. Then that instance of Paxos is done. A while later another
     client sends 'command two'; the replicas start up an entirely separate
     instance of Paxos to agree on this second client command.'_ --RTM
 - each node knows the address of every other node for that instance
 - each instance of Paxos can reach consensus on at most one value
    typically, a system uses many instances of Paxos
    each instance usually decides one operation
  assumptions: asynchronous, non-Byzantine

### What does Paxos provide?

 - **"black-box"** interface to a Paxos instance, on each node:
   + Propose a value (e.g., operation)
   + Check what value has been decided, if any
   + [ Lab 3A: `src/paxos/paxos.go`: Start, Status ]
 - **Correctness:**
   + if agreement reached, all agreeing nodes see same value
 - **Fault-tolerance:**
   + can tolerate non-reachability of a minority of nodes
     (correctness implies they won't agree at all)
 - **Liveness:**
   + a majority must be alive and able to communicate reliably
     (minorities are not live)

### How to build a system using Paxos?

  1. Primary/Backup like Lab 2, but use Paxos to replicate the ViewServer
     - [ next Tuesday's lecture will be about such a system ]
  2. Lab 3: no ViewServer, all replicas use Paxos instead of primary/backup

Replicating either the ViewServer or K/V server with Paxos is similar.

Will look at a sketch of how to do a Paxos-based K/V server.

The **basic idea**:

 - [ Diagram: clients, replicas, log in each replica, K/V layer, Paxos layer]
 - no viewserver
 - three replicas
 - clients can send RPCs to any replica (not just primary)
 - server appends each client op to a replicated *log* of operations
   + `Put`, `Get` (and more later)
 - numbered log entries -- instances -- seq
   + **TODO:** Is this trying to say log entries are numbered sequentially?
 - Paxos agreement on content of each log entry
 - **TODO** Ask question about concurrency here? Can one log entry be agreed on at the same time with another? What if they depend on one another like `Put(k1, a)` and `Append(k1, b)`?

Example:

 - client sends `Put(a, b)` to `S1`
 - `S1` picks a log entry 3
 - `S1` uses Paxos to get all servers to agree that entry 3 holds `Put(a,b)`
  
Example:
 
 - client sends `Get(a)` to `S2`
 - `S2` picks log entry 4
 - `S2` uses Paxos to get all servers to agree that entry 4 holds `Get(a)`
 - `S2` scans log up to entry 4 to find latest `Put(a, ...)`
   + **TODO:** `O(n)` worst case for doing a `Get` because you can have `Put` followed by a gazillion `PutAppend`'s (or you can have just one `Put` stored way back?).
     - Can the replicas index their log? I suppose. If they all store it fully.
 - `S2` replies with that value
   + `S2` can cache content of DB up through last log scan
  
#### Q: Why a log?

 - Why not require all replicas to agree on each op in lock-step?
 - Allows one replica to fall behind, then catch up
   + e.g. if it is slow
   + other replicas do not have to wait
 - Allows one replica to crash and catch up
   + if it keeps state on disk
   + can replay missed operations
 - Allows pipelining/overlap of agreement
   + agreement turns out to require multiple message rounds

#### Q: What about agreement -- we need all replicas to have same op in each log slot

 - Provided by Paxos, as we will see next

_Agreement is hard (1):_

 - May be multiple proposals for the op in a particular log slot
 - `Sx` (server `x`) may initially hear of one, `Sy` may hear of another
 - Clearly one must later change its mind
 - Thus: multiple rounds, tentative initially
 - How do we know when agreement is permanent -- no longer tentative?

_Agreement is hard (2):_

 - **TODO:** If `S1` and `S2` agree, and `S3` and `S4` don't respond, are we done?
 - Agreement has to be able to complete even w/ failed servers
 - We can't distinguish failed server from network partition
 - So maybe `S3`/`S4` are partitioned have "agreed" on a different operation!

Two **main ideas** in Paxos:

  1. Many rounds may be required but they will converge on one value
  2. A majority is required for agreement -- prevent "split brain"
     - *Key point*: any two majorities overlap
     - so any later majority will share at least one server w/ any earlier majority
     - so any later majority can find out what earlier majority decided
       + **TODO:** How?

Lab 3B K/V server creates a separate Paxos instance for each client `Put`, `Get`

 - rest of lecture focuses on agreement for a specific instance

Paxos sketch
------------

 + each node consists of three logical entities:
   - **proposer**
   - **acceptor**
   - **learner**
 + each proposer wants to get agreement on its value
   - could try to use a "designated leader" to avoid dueling proposers
   - OK to have multiple proposers, so leader election can be approximate
 + proposer contacts acceptors, tries to assemble a majority
   - if a majority respond, we're done
 + in our K/V server example, roughly:
   - proposer gets RPC from client, proposes operation
   - acceptors are internal to Paxos, help decide consensus
   - learner figures out what operation was decided to run, responds to client

_Broken strawman:_ can we do Paxos in a single round?

 - acceptor "accepts" the first value that it hears from proposer
 - when is consensus reached?
   + can we take the value with the most votes?
   + no, need a majority of accepts for the same value: `floor(n/2)+1`
   + otherwise, consensus on 2 different values (lossy/partitioned network)
 - _Problem:_
   + suppose we have 3 servers: `S1`, `S2`, `S3`
   + what if each server proposes + accepts its own value?
     - no majority, stuck
     - but maybe we can detect this situation and recover?
   + _Worse:_ `S3` crashes `->` we may have reached majority, but we'll never know
 - need a way for acceptors to change their mind, if no consensus reached yet

### Basic Paxos exchange

         proposer          acceptors

               prepare(n) ->
            <- prepare_ok(n, n_a, v_a)

               accept(n, v') ->
            <- accept_ok(n)

               decided(v') ->

### Why `n`?

 - to distinguish among multiple rounds, e.g. proposer crashes, simul props
 - want later rounds to supersede earlier ones
 - numbers allow us to compare early/late
 - `n` values must be unique and roughly follow time
 - `n = <time, server ID>`
   + e.g., ID can be server's IP address
 - _"round"_ is the same as _"proposal"_ but completely different from "instance"
   + round/proposal numbers are _WITHIN_ a particular instance

**Definition:** server S _accepts_ `n/v`

 - it responded `accept_ok` to `accept(n, v)`

**Definition:** `n/v` is _chosen_
 - a majority of servers accepted `n/v`

The **crucial property:**

 - if a value was chosen, any subsequent choice must be the same value
   + i.e. protocol must not change its mind
   + maybe a different proposer &c, but same value!
   + this allows us to freely start new rounds after crashes &c
 - tricky b/c _"chosen"_ is system-wide property
   + e.g. majority accepts, then proposer crashes
     - **TODO:** What happens here?
   + _no node can tell locally that agreement was reached_

So:

 - proposer doesn't send out value with `prepare`
   + **TODO:** How is any value accepted by an acceptor then?
 - acceptors send back any value they have already accepted
 - if there is one, proposer proposes that value
   + to avoid changing an existing choice
 - if no value already accepted,
   + proposer can propose any value (e.g. a client request)
 - proposer must get `prepare_ok` from majority
   + to guarantee intersection with any previous majority,
   + to guarantee proposer hears of any previously chosen value

### Now the protocol -- see the handout

        proposer(v):
          choose n, unique and higher than any n seen so far
          send prepare(n) to all servers including self
          if prepare_ok(n, n_a, v_a) from majority:
            v' = v_a with highest n_a; choose own v otherwise
            send accept(n, v') to all
            if accept_ok(n) from majority:
              send decided(v') to all

        acceptor state:
          must persist across reboots
          n_p (highest prepare seen)
          n_a, v_a (highest accept seen)

        acceptor's prepare(n) handler:
          if n > n_p
            n_p = n
            reply prepare_ok(n, n_a, v_a)
          else
            reply prepare_reject

        acceptor's accept(n, v) handler:
          if n >= n_p
            n_p = n
            n_a = n
            v_a = v
            reply accept_ok(n)
          else
            reply accept_reject

**Example 1** (normal operation):

        `S1`, `S2`, `S3` but `S3` is dead or slow

        `S1`: -> starts proposal w/ n=1 v=A 
        `S1`: <- p1   <- a1vA    <- dA
        `S2`: <- p1   <- a1vA    <- dA
        `S3`: dead...

        "p1" means Sx receives prepare(n=1) 
        "a1vA" means Sx receives accept(n=1, v=A)
        "dA" means Sx receives decided(v=A)

These diagrams are not specific about who the proposer is
 
 - it doesn't really matter
 - the proposers are logically separate from the acceptors
 - we only care about what acceptors saw and replied

Note Paxos only requires a majority of the servers

 - so we can continue even though `S3` was down
 - proposer must not wait forever for any acceptor's response

What would happen if network partition?

 - I.e. `S3` was alive and had a proposed value B
 - `S3`'s prepare would not assemble a majority

_The homework question:_ How does Paxos ensure that the following sequence of events can't
happen? What actually happens, and which value is ultimately chosen?

      proposer 1 crashes after sending two accepts
      proposer 2 has a different value in mind
      A: p1 a1foo
      B: p1       p2 a2bar
      C: p1 a1foo p2 a2bar
      C's prepare_ok to B really included "foo"
        thus a2foo, and so no problem

**The point:**

 - if the system has already reached agreement, majority will know value
 - any new majority of prepares will intersect that majority
 - so subsequent proposer will learn of already-agreed-on value
 - and send it in accept msgs

**Example 2** (concurrent proposers):

        A1 starts proposing n=10
            TODO: is this propose or prepare? p1 means prepare(n=1)
        A1 sends out just one accept v=10
        A3 starts proposing n=11
          but A1 does not receive its proposal
          A3 only has to wait for a majority of proposal responses
        A1: p10 a10v10 
        A2: p10        p11
        A3: p10        p11  a11v11
        A1 and A3 have accepted different values!

What will happen?

 - what will `A2` do if it gets `a10v10` accept msg from `A1`?
   + **TODO:** Is this accept\_ok the propose or prepare\_ok the prepare
     - `a10v10` means `accept(n=10,v=10)` which happens after `prepare->` and `<-prepare_ok`
 - what will `A1` do if it gets `a11v11` accept msg from `A3`?

What if A3 were to crash at this point (and not restart)?

How about this:

    A1: p10  a10v10               p12
    A2: p10          p11  a11v11  
    A3: p10          p11          p12   a12v10

Has the system agreed to a value at this point?

What's the commit point?

 - i.e. exactly when has agreement been reached?
 - i.e. at what point would changing the value be a disaster?
 - after a majority has the same `v_a`? no -- why not? above counterexample
 - after a majority has the same `v_a/n_a`? yes -- why sufficient? sketch:
   + suppose majority has same `v_a/n_a`
   + acceptors will reject `accept()` with lower `n`
   + for any higher `n`: prepare's must have seen our majority `v_a/n_a` (overlap)
   + what if overlap servers saw `prepare(n)` before `accept(v_a, n_a)`?
     - would reject `v_a/n_a`
     - thus wouldn't have a majority yet
     - proposer might be free to choose `v != v_a`

Why does the proposer need to pick `v_a` with highest `n_a`?

        A1: p10  a10vA               p12
        A2: p10          p11  a11vB  
        A3: p10          p11  a11vB  p12   a12v??
        n=11 already agreed on vB
        n=12 sees both vA and vB, but must choose vB

Why: Two cases:

  1. There was a majority before `n=11`
     - `n=11`'s prepares would have seen value and re-used it
     - so it's safe for `n=12` to re-use `n=11`'s value
  2. There was not a majority before `n=11`
     - `n=11` might have obtained a majority
     - so it's required for `n=12 `to re-use `n=11`'s value

Why does prepare handler check that `n > n_p`?

 - it's taking `max(concurrent n's)`, for accept handler
 - responding to all `prepare()` with `prepare_ok()` would be also fine,
   + but proposers with `n < n_p` would be ignored by `accept()` anyway

Why does accept handler check `n >= n_p`?

 - required to ensure agreement
 - there's a unique highest `n` active
 - everyone favors the highest `n`
 - without `n >= n_p` check, you could get this bad scenario:

Scenario:

        A1: p1 p2 a1vA
        A2: p1 p2 a1vA a2vB
        A3: p1 p2      a2vB

Why does accept handler update `n_p = n`?

 - required to prevent earlier `n`'s from being accepted
 - node can get `accept(n,v)` even though it never saw `prepare(n)`
 - without `n_p = n`, can get this bad scenario:

Scenario:

        A1: p1    a2vB a1vA p3 a3vA
        A2: p1 p2           p3 a3vA
        A3:    p2 a2vB

What if new proposer chooses `n < old proposer`?

 - i.e. if clocks are not synced
 - cannot make progress, though no correctness problem

What if an acceptor crashes after receiving accept?

    A1: p1  a1v1
    A2: p1  a1v1 reboot  p2  a2v?
    A3: p1               p2  a2v?
    
    A2 must remember v_a/n_a across reboot! on disk
      might be only intersection with new proposer's majority
      and thus only evidence that already agreed on v1

What if an acceptor reboots after sending `prepare_ok`?

 - does it have to remember n_p on disk?
 - if n_p not remembered, this could happen:

Example:

      `S1`: p10            a10v10
      `S2`: p10 p11 reboot a10v10 a11v11
      `S3`:     p11               a11v11

 - 11's proposer did not see value 10, so 11 proposed its own value
 - but just before that, 10 had been chosen!
 - b/c `S2` did not remember to ignore `a10v10`

Can Paxos get stuck?

 - Yes, if there is not a majority that can communicate
 - How about if a majority is available?
   + Possible to livelock: dueling proposers, keep `prepare`'ing higher `n`'s
     - One reason to try electing a leader: reduce chance of dueling proposers
   + With single proposer and reachable majority, should reach consensus
