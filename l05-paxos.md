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
Links:

 - [Paxos Made Simple](papers/paxos-simple.pdf), by Leslie Lamport, 2001
 - [Simple explanations from Quora](https://www.quora.com/Distributed-Systems/What-is-a-simple-explanation-of-the-Paxos-algorithm)
 - [Neat Algorithms - Paxos](http://harry.me/blog/2014/12/27/neat-algorithms-paxos/)
 - [Paxos Replicated State Machines as the Basis of a High-Performance Data Store](http://static.usenix.org/event/nsdi11/tech/full_papers/Bolosky.pdf)
 - [Paxos notes](http://wellquite.org/blog/paxos_notes.html)
 - [Paxos made simple paper review](http://blog.acolyer.org/2015/03/04/paxos-made-simple/)
 - [On some subtleties of Paxos](http://the-paper-trail.org/blog/on-some-subtleties-of-paxos/)

Recall: RSM

 + maintain replicas by executing operations in the same order
 + requires all replicas to agree on the (set and) order of operations

Lab 2 critique

 + primary/backup with viewserver
 + **pro:**
   - conceptually simple
   - just two msgs per op (request, reply)
   - primary can do computation, send result to backup
   - only two k/v servers needed to tolerate one failure
   - works with network partition
 + **con:**
   - ViewServer is a _single point of failure_
   - order can be messy: e.g., new view, data to backup, ack, &c
   - tension if backup is slow / temporarily unavail
     1. primary can wait for backup -- slow
     2. viewserver can declare backup dead -- expensive, hurts fault tolerance

We would like a general-purpose ordering scheme with:

 + no single point of failure
 + graceful handling of slow / intermittent replicas
 + handling of network partitions

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

### What does Paxos provide? How does it work?

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
  2. _Lab 3_: no ViewServer, all replicas use Paxos instead of primary/backup

Replicating either the ViewServer or K/V server with Paxos is similar.

Will look at a sketch of how to do a Paxos-based K/V server.

The **basic idea**:

 - [ Diagram: clients, replicas, log in each replica, K/V layer, Paxos layer]
 - no viewserver
 - three replicas
 - clients can send RPCs to any replica (not just primary)
 - server appends each client op to a replicated *log* of operations
   + `Put`, `Get` (and more later)
 - log entries (instances) are numbered sequentially
 - Paxos ensures agreement on content of each log entry
 - separate Paxos agreement for each of these log entries
   + separate _instance_ of Paxos algorithm is run for log entry #`i`
   + **Q:** Can one log entry be agreed on at the same time with another? What if they depend on one another like `Put(k1, a)` and `Append(k1, b)`?
   + **A:** Yes! They can be agreed upon on the same time.
   + **A:** you can have agreed on log entry #`i` before agreeing on log entry #`i+1`
     - This means the reply associated with the `Get` or `Put` request in log entry `i+1` will
       have to wait for the other log entries to be set (interesting)
 - servers can throw away log entries that all other servers have agreed on (and responded to?)
   + but if a server crashes, the other servers will know to keep their log entries around for when it comes back
 - protocol does **not** require designated proposers or leaders for correctness
   + these only help w/ performance
   + low probability of proposing "livelock" that can be overcome by having proposers wait a random amount of time
 - once a Paxos node agrees on a value it never changes its mind

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
   + e.g., if it is slow
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
     - so any later majority can find out what earlier majority decided (discussed below)

Lab 3B K/V server creates a separate Paxos instance for each client `Put`, `Get` (much harder)

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

 - to distinguish among multiple rounds, e.g., proposer crashes, simul props
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
   + i.e., protocol must not change its mind
   + maybe a different proposer &c, but same value!
   + this allows us to freely start new rounds after crashes &c
 - tricky b/c _"chosen"_ is system-wide property
   + e.g., majority accepts, then proposer crashes
   + `=>` _no node can tell locally that agreement was reached_

So:

 - proposer doesn't send out value with `prepare` (but sends it a bit later)
 - acceptors send back any value they have already accepted
 - if there is one, proposer proposes that value
   + to avoid changing an existing choice
 - if no value already accepted,
   + proposer can propose any value (e.g., a client request)
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
              send decided(n, v') to all

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

        `S1`, `S2`, `S3` 
        [ but `S3` is dead or slow ]

        `S1`: -> starts proposal w/ n=1 v=A
        `S1`: <- p1   <- a1vA    <- dA
        `S2`: <- p1   <- a1vA    <- dA
        `S3`: dead...

        "p1" means Sx receives prepare(n=1)
        "a1vA" means Sx receives accept(n=1, v=A)
        "dA" means Sx receives decided(v=A)

 - S1 and S2 will reply with `prepare_ok(1, 0, null)` to the `p1` message.
 - If `dA` is lost, one of the nodes waiting can run Paxos again and try a new `n` higher than the previous one.
   + the `prepare_ok(2, 1, 'A')` reply will come back,
   + then the node is forced to send `a2vA` and hopefully this time, after the node gets the `accept_ok` message, it
     will send out `dA` messages that won't get lost again
 - a value is said to be chosen when a majority of acceptors in the `accept` handler take the accept branch and accept the value
   + however, not everyone will *know* this, so that's why the `decide` message is sent out

These diagrams are not specific about who the proposer is
 
 - it doesn't really matter
 - the proposers are logically separate from the acceptors
 - we only care about what acceptors saw and replied

Note Paxos only requires a majority of the servers

 - so we can continue even though `S3` was down
 - proposer must not wait forever for any acceptor's response

#### What would happen if network partition?

 - i.e., `S3` was alive and had a proposed value B
 - `S3`'s prepare would not assemble a majority

#### The homework question

How does Paxos ensure that the following sequence of events can't happen? 
What actually happens, and which value is ultimately chosen?

      proposer 1 crashes after sending two accept() requests
      proposer 2 has a different value in mind

      A: p1 a1foo
      B: p1       p2 a2bar
      C: p1 a1foo p2 a2bar

      C's prepare_ok to B really included "foo"
        thus a2foo, and so no problem

**The point:**

 - if the system has already reached agreement, majority will know value
    + in this example, A and C agreed on 'foo'
 - any new majority of prepares will intersect that majority
    - in this example, AC intersects BC in C
 - so subsequent proposer will learn of already-agreed-on value
    - in this example, C will reply with a `prepare_ok(n=2, n_a=1, v_a=foo)` to proposer
 - and subsequent proposer will send already-agreed-on value in `accept` msg
    - in this example, proposer will send `accept(n=2, v=foo)` 

**Example 2** (concurrent proposers):

        A1 starts proposing n=10 by sending prepare(n=10) 
        A1 sends out just one accept v=10
        [ => A1 must have received prepare_ok from majority ]
        A3 starts proposing n=11
          but A1 does not receive its proposal
          [ => A1 never replies to A3 with prepare_ok(n=11, n_a=10, v=10) because it never got the prepare ]
          A3 only has to wait for a majority of proposal responses

        A1: p10 a10v10 
        A2: p10        p11
        A3: p10        p11  a11v11

        A1 and A3 have accepted different values!

What will happen?

 - **Q:** What will `A2` do if it gets `a10v10` accept msg from `A1`?
   - _Recall:_ `a10v10` means `accept(n=10,v=10)` which is sent by proposer after he receives a majority of `<-prepare_ok`'s on `n=10`
   - **A:** A2 will reject because it has a higher `np` from `p11`
 - **Q:** What will `A1` do if it gets `a11v11` accept msg from `A3`?
   - **A:** `A1` will reply `accept_ok` and change its value to 11 because `n = 11 > np = 10`
 - In other words, a value has not been chosen yet because no majority accepted the same value yet with the same proposal number.

What if A3 (2nd proposer) were to crash at this point (and not restart)?
 
 - **TODO:** Not sure which "point" they are referring to.
 - _Case 1:_ If `A3` crashes after proposing `n=11` and after receiving a majority of `prepare_ok`'s but before sending out the other two `accept`'s to `A1` and `A2`, then:
    + `A1` could come back online and send an `accept(n=10,v=10)` to `A2`
    + `A2` will reject because it has a higher `np = 11` (see above and see algorithm)
    + `A1` will repropose with higher `n` and eventually convince both itself and `A2` to accept `v10`
 - _Case 2:_ `A3` crashes after proposing `n=11` and receiving a majority of `prepare_ok`'s and _after_ sending out an `accept` to `A2`
    - `A2` will `accept_ok` on `v11`
    - Now `v11` is chosen: any future majority of `prepare_ok`'s will return `v11`

How about this:

    A1: p10  a10v10               p12
    A2: p10          p11  a11v11  
    A3: p10          p11          p12   a12v10

Has the system agreed to a value at this point?

#### What's the commit point?

 - i.e., exactly when has agreement been reached?
 - i.e., at what point would changing the value be a disaster?
 - after a majority has the same `v_a`? no -- why not? above counterexample
 - after a majority has the same `v_a/n_a`? yes -- why sufficient? sketch:
   + suppose majority has same `v_a/n_a`
   + acceptors will reject `accept()` with lower `n`
   + for any higher `n`: prepare's must have seen our majority `v_a/n_a` (overlap)
   + what if overlap servers saw `prepare(n)` before `accept(v_a, n_a)`?
     - would reject `v_a/n_a`
     - thus wouldn't have a majority yet
     - proposer might be free to choose `v != v_a`

#### Why does the proposer need to pick `v_a` with highest `n_a`?

        A1: p10  a10vA               p12
        A2: p10          p11  a11vB  
        A3: p10          p11  a11vB  p12   a12v??

        n=11 already agreed on vB
        n=12 sees both vA and vB, but must choose vB

Two cases:

  1. There was a majority before `n=11`
     - `n=11`'s prepares would have seen value and re-used it
     - so it's safe for `n=12` to re-use `n=11`'s value
  2. There was not a majority before `n=11`
     - `n=11` might have obtained a majority
     - so it's required for `n=12 `to re-use `n=11`'s value

#### Why does prepare handler check that `n > n_p`?

 - it's taking `max(concurrent n's)`, for accept handler
 - responding to all `prepare()` with `prepare_ok()` would be also fine,
   + but proposers with `n < n_p` would be ignored by `accept()` anyway

#### Why does accept handler check `n >= n_p`?

 - required to ensure agreement
 - there's a unique highest `n` active
 - everyone favors the highest `n`
 - without `n >= n_p` check, you could get this bad scenario:

Scenario:

        A1: p1 p2 a1vA
        A2: p1 p2 a1vA a2vB
        A3: p1 p2      a2vB

#### Why does accept handler update `n_p = n`?

 - required to prevent earlier `n`'s from being accepted
 - node can get `accept(n,v)` even though it never saw `prepare(n)`
 - without `n_p = n`, can get this bad scenario:

Scenario:

        A1: p1    a2vB a1vA p3 a3vA
        A2: p1 p2           p3 a3vA
        A3:    p2 a2vB

#### What if new proposer chooses `n < old proposer`?

 - i.e., if clocks are not synced
 - cannot make progress, though no correctness problem

#### What if an acceptor crashes after receiving accept?

    A1: p1  a1v1
    A2: p1  a1v1 reboot  p2  a2v?
    A3: p1               p2  a2v?
    
    A2 must remember v_a/n_a across reboot! on disk
      might be only intersection with new proposer's majority
      and thus only evidence that already agreed on v1

#### What if an acceptor reboots after sending `prepare_ok`?

 - does it have to remember `n_p` on disk?
 - if `n_p` not remembered, this could happen:

Example:

      `S1`: p10            a10v10
      `S2`: p10 p11 reboot a10v10 a11v11
      `S3`:     p11               a11v11

 - 11's proposer did not see value 10, so 11 proposed its own value
 - but just before that, 10 had been chosen!
 - b/c `S2` did not remember to ignore `a10v10`

#### Can Paxos get stuck?

 - Yes, if there is not a majority that can communicate
 - How about if a majority is available?
   + Possible to livelock: dueling proposers, keep `prepare`'ing higher `n`'s
     - One reason to try electing a leader: reduce chance of dueling proposers
   + With single proposer and reachable majority, should reach consensus
