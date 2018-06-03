6.824 Practical Byzantine Fault Tolerance (2012 modified notes)
===============================================================

We've considered many fault-tolerance protocols
 
 - have always assumed "fail-stop" failures -- like power failure
 - i.e. servers follow the protocol
 - hard enough: crash vs network down; network partition

Can one handle a larger class of failures?
 
 - buggy servers, that compute incorrectly rather than stopping?
 - servers that *don't* follow the protocol?
 - servers that have been modified by an attacker?
 - often called "Byzantine" faults

The PBFT paper's approach:

 - replicated state machine
 - assumes $2f+1$ of $3f+1$ are non-faulty
 - use voting to select the right results
 - not as easy as it might sound

Let's assume the worst case:

 - a single attacker controls the $f$ faulty replicas
 - and is actively trying to break the system
 - if we can handle this, we can handle bugs in f replicas too

What are the attacker's powers?

 - supplies the code that faulty replicas run
 - knows the code the non-faulty replicas are running
 - knows the faulty replicas' crypto keys
 - can read network messages
 - can temporarily force messages to be delayed via DoS
    + specifically, can delay messages from up to $f$ replicas

What faults *can't* happen?
 
 - no more than f out of 3f+1 replicas can be faulty
 - no client failure -- clients never do anything bad
 - no guessing of crypto keys or breaking of cryptography

Example use scenario:

    RM:
      echo A > grade
      echo B > grade
      tell YM "the grade file is ready"
    YM:
      cat grade

A faulty system could:
 
 - totally make up the file contents
 - execute write("A") but ignore write("B")
 - show "B" to RM and "A" to YM
 - execute write("B") only only some of the replicas

Bad BFT designs
---------------

Let's try to design our own byzantine-fault-tolerant RSM

 - start simple (and broken), work towards paper's design

### Design 1: Wait for all servers

 - client, $n$ servers
 - client sends request to all of them
 - client waits for all $n$ to reply
 - client only proceeds if all $n$ agree

What's wrong with design 1?

 - not fault-tolerant: one faulty replica can stop progress by disagreeing

### Design 2: Wait for $f+1$ out of $2f+1$

 - let's have replicas vote
 - $2f+1$ servers, assume no more than $f$ are faulty
 - client waits for $f+1$ matching replies
    + if only $f$ are faulty, and network works eventually, must get them!

What's wrong with design 2's 2f+1?

 - not safe: $f+1$ matching replies might be from $f$ malicious nodes and just 1 good (because the other $f$ nodes are delayed)
    + so maybe only one good node got the operation!
    - in other words, client can't wait for replies from the last $f$ replicas
       + they might be faulty, never going to reply
       - so must be able to make a decision after $n-f$ replies (i.e., $f+1$ since $n=2f+1$)
       - but $f$ of the first $f+1$ replies might be from faulty replicas!
         - i.e., $f+1$ is not enough to vote: waiting for $f+1$ of $2f+1$ doesn't ensure that majority of good nodes executed
 - *next* operation `op2` also waits for $f+1$
    + might *not* include that one good node that saw `op1`
 - Example:
    + $S_1$ $S_2$ $S_3$ ($S_1$ is bad)
    + everyone hears and replies to write("A")
    + $S_1$ and $S_2$ reply to write("B"), but $S_3$ misses it
       + client can't wait for $S_3$ since it may be the one faulty server
    + $S_1$ and $S_3$ reply to read(), but $S_2$ misses it
    + so read() yields "A"
 - Result: client tricked into accepting a reply based on out-of-date state
    + e.g. TA reads A instead of B from grades file

### Design 3: Wait for $2f+1$ out of $3f+1$

 - $3f+1$ servers, of which at most $f$ are faulty
 - client waits for $2f+1$ matching replies
    + $f$ bad nodes plus a majority of the good nodes
    + so all sets of $2f+1$ overlap in at least one good node
 - Example:
    + $S_1$ $S_2$ $S_3$ $S_4$ ($S_1$ is bad)
    + everyone hears write("A")
    + $S_1$, $S_2$, $S_3$ hears write("B"), $S_4$ misses it
    - now the read()
       + client will wait for $2f+1=3$ matching replies
       + $S_1$ and $S_4$ will reply "A"
       - $S_2$ and $S_3$ will reply "B"
    - client doesn't know what to believe (neither is $2f+1$)
       + but it is guaranteed to see there's a problem
 - so client can *detect* that some good nodes missed an operation
    + we'll see how to repair in a bit
 
What about handling multiple clients?

 - non-faulty replicas must process operations in the same order!

Let's have a primary to pick order for concurrent client requests

 - but we have to worry about a faulty primary

What can a faulty primary do?

  1. send wrong result to client
  2. different ops to different replicas
  3. ignore a client op

General approach to handling faulty primary

  1. replicas send results direct to client
  2. replicas exchange info about ops sent by primary
  3. clients notify replicas of each operation, as well as primary
     each replica watches progress of each operation
     if no progress, force change of primary

Can a replica execute an operation when it first receives it from primary?

  - No: maybe primary gave different ops to different replicas
  - if we execute before we're sure, we've wrecked the replica's state
  - `=>` need 2nd round of messages to make sure all good replicas got the same op

### Design 4: Almost PBFT (no view change) 

 - $3f+1$ servers, one is primary, $f$ faulty, primary might be faulty
 - client sends request to primary **AND** to each replica
 - primary chooses next op and op #
 - primary sends `PRE-PREPARE(op, n)` to replicas
 - each replica sends `PREPARE(op, n)` to all replicas
 - if replica gets matching `PREPARE(op, n)` from `2f+1` replicas (including itself) and $n$ is the next operation #
    + execute the operation, possibly modifying state
    + send reply to client
 - Otherwise, keep waiting
 - client is happy when it gets $f+1$ matching replies

[??]

       REQ  PRE-P  PREPARE  REPLY
     C
    S0
    S1
    S2
    S3

Remember our strategy:

 + primary follows protocol => progress
 + no progress => replicas detect and force change of primary

If the primary is non-faulty, can faulty replicas prevent correct progress?

 - they can't forge primary msgs
 - they can delay msgs, but not forever
 - they can do nothing (i.e., not execute the protocol): but they aren't needed for $2f+1$ matching PREPAREs
 - they can send correct PREPAREs
    + and DoS $f$ good replicas to prevent them from hearing ops
    + but those replicas will eventually hear the ops from the primary
    + **TODO:** Eh?
 - worst outcome: delays

If the primary is faulty, will replicas detect any problem? Or can primary cause undetectable problem?

 - primary can't forge client ops -- signed
 - it can't ignore client ops -- client sends to all replicas
 - it can try to send in different order to different replicas,
    + or try to trick replicas into thinking an op has been processed even though it hasn't
    - **TODO:** Define processed!
 - Will replicas detect such an attack?

Results of the primary sending diff ops to diff replicas?

 - Case 1: all good nodes get $2f+1$ matching PREPAREs
    - Did they all get the same op?
    - Yes, everyone who got $2f+1$ matching PREPAREs must have gotten same op
       + since any two sets of $2f+1$ share at least one good server who will not equivocate about op
    - Result: all good nodes will execute op, client happy!
 - Case 2: $\ge f+1$ good nodes get $2f+1$ matching PREPARES
    - again, no disagreement possible
    - result: $f+1$ good nodes will execute op, client happy
    - **BUT** up to $f$ good nodes don't execute
       + can they be used to effectively roll back the op?
       + i.e., send the write("B") to $f+1$, send read() to remaining $f$
       - no: won't be able to find $2f+1$ replicas with old state
         + **TODO:** i.e., read() won't be able to get $2f+1$ matching PREPAREs for the same $n$ because $f+1$ replicas have advanced to $n+1$, so attacker is left with $f$ good replicas and $f$ bad ones, which is less than $2f+1$
       - so not enough PREPAREs
 - Case 3: $< f+1$ good nodes get $2f+1$ matching PREPAREs
    - result: client never gets a reply
    - result: system will stop, since $f+1$ stuck waiting for this op
      + **TODO:** Eh?

How to resume operation after faulty primary?

 - need a _view change_ to choose new primary
 - (this view change only chooses primary; no notion of set of live servers)

When does a replica ask for a view change?
 
 - if it sees a client op but doesn't see $2f+1$ matching PREPAREs (after some timeout period)

Is it OK to trigger a view change if just one replica asks?

 - No: faulty replicas might cause constant view changes

For now, let's defer the question of how many replicas must ask for a view change.
 
Who is the next primary?

 - need to make sure faulty replicas can't always make themselves next primary
 - view number $v$
 - primary is $v \bmod n$
 - so primary rotates among servers
 - at most $f$ faulty primaries in a row

### View change design 1 (not correct)

 - replicas send `VIEW-CHANGE` requests to *new* primary
 - new primary waits for enough view-change requests
 - new primary announces view change w/ `NEW-VIEW`
    + includes the `VIEW-CHANGE` requests
    + as proof that enough replicas wanted to change views
 - new primary starts numbering operations at last $n$ it saw + 1

Will all non-faulty replicas agree about operation numbering across view change?

Problem:

 - I saw $2f+1$ PREPAREs for operation $n$, so I executed it
 - new primary did not, so it did not execute it
 - maybe new primary didn't even see the PRE-PREPARE for operation n
   + old primary may never have sent PRE-PREPARE to next primary
 - thus new primary may start numbering at $n$, yielding two different op #n


Can new primary ask all replicas for set of operations they have executed?

 - doesn't work: new primary can only wait for $2f+1$ replies
   + faulty replicas may reply, so new primary may not wait for me

Solution:

 - don't execute operation until sure a new primary will hear about it
 - add a third phase: `PRE-PREPARE`, `PREPARE`, then `COMMIT`
 - **only execute after commit**

### Final design: PBFT operation protocol

 - client sends op to primary
    + **TODO:** And other replicas too, no? Or how do replicas know when to change primary who doesn't pre-prepare anything?
 - primary sends `PRE-PREPARE(op, n)` to all
 - all send `PREPARE(op, n)` to all
 - after replica receives $2f+1$ matching `PREPARE(op, n)`
    + send `COMMIT(op, n)` to all
 - after receiving $2f+1$ matching `COMMIT(op, n)`
    + execute op

### View change design 2 (correct)

 - each replica sends new primary $2f+1$ PREPAREs for recent ops
 - new primary waits for $2f+1$ `VIEW-CHANGE` requests
 - new primary sends `NEW-VIEW` msg to all replicas with
    - complete set of `VIEW-CHANGE` msgs
    - list of every op for which some VIEW-CHANGE contained 2f+1 PREPAREs
    - i.e., list of final ops from last view

 - If a replica executes an op, will new primary know of that op?
 - replica only executed after receiving $2f+1$ COMMITS
 - maybe $f$ of those were lies, from faulty replicas, who won't tell new primary
 - but $f+1$ COMMITs were from replicas that got $2f+1$ matching PREPAREs
 - new primary waits for view-change requests from $2f+1$ replicas
    + ignoring the f faulty nodes
    + $f+1$ sent COMMITs, $f+1$ sent VIEW-CHANGE
    - must overlap

Can the new primary omit some of the reported recent operations?

 - no, NEW-VIEW must include signed VIEW-CHANGE messages

Paper also discusses

 - checkpoints and logs to help good nodes recover
 - various cryptographic optimizations
 - optimizations to reduce # of msgs in common case
 - fast read-only operations

What are the consequences of more than $f$ corrupt servers?

 - can the system recover?

What if the client is corrupt?

Suppose an attacker can corrupt one of the servers

 - exploits a bug, or steals a password, or has physical access, &c
 - why can't the attacker corrupt them all?
