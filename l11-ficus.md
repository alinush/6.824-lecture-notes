6.824 2015 Lecture 15: Optimism, Causality, Vector Timestamps
=============================================================

**Note:** These lecture notes were slightly modified from the ones posted on the 6.824 
[course website](http://nil.csail.mit.edu/6.824/2015/schedule.html) from Spring 2015.

Consistency so far:

 - _Concurrency_ forces us to to think about meaning of reads/writes
 - _Sequential consistency:_ everyone sees same read/write order (IVY)
 - _Release consistency:_ everyone sees writes in unlock order (TreadMarks)

Sequential and release consistency are slow:

 - in general, must ask before each operation
 - IVY: read faults and write faults -> ask manager
 - TreadMarks: acquire and release -> ask lock manager
 - Can we get better performance by weakening consistency?

Paxos:

 - Also slow; several messages to reach agreement.
   + More than IVY+TreadMarks
 - Also, "low" availability
   + If no majority, no progress.
 - Not suitable for disconnected operation. 

Optimistic Concurrency Control
------------------------------

 - Do the operation now (e.g., read/write cached copy)
 - Check if it was OK later
 - Recover if not OK

A simple example -- optimistic peer-to-peer chat

 - We each have a computer attached to internet
 - When I type something, send msg. to each participant
 - Recv msg -> add to end of chat window

Diagram:
    
    m0              m1              m2 
    \             /\              /\
     \------------/               /
      \                          /
       \------------------------/


Do we care about message ordering for chat?

 - Network may deliver in different order at different participants
 - Joe: The answer is 40
 - Fred: No, it's 41
 - Alice: That's correct
 - Maybe Sam sees different order:
   + Joe: 40
   + Alice: That's correct

What went wrong in this example?

 - Alice "computed" her message based on certain inputs
 - Sam can only interpret if he has seen those inputs too

Suppose this is an auction chat program:

    Joe         Fred        Alice

    $10 -->
                20
              <-- -->  

                     <-- winner is $20

If there were a 4th person, Sam:

    Joe         Fred        Alice               Sam

    $10 -->                                   sees $10
                20  
              <-- -->                         does not see $20 

                     <-- winner is $20 -->    sees winner is $20

So to Sam this might not make sense. His problem is that Sam didn't know
what Alice knew when she sent her message.

**Definition:** `x` causally precedes `y`

 - `x` precedes `y` if:
   + M0 does `x`, then M0 does `y`
   + M0 does `x`, M0 sends msg to M1, M1 does `y`
 - [transitive closure](https://en.wikipedia.org/wiki/Transitive_closure)
 - `x` and `y` are generally writes, or msgs, or file versions
 - also "`y` causally depends on `x`"

**Definition:** causal consistency

 - if `x` causally precedes `y`, everyone sees `x` before `y`

Pros, cons:

 - Pro: no single master
 - Con: not a total order on events

### Slow implementation of causal consistency

 - Unique ID for every msg
 - Node keeps set of all msg IDs received -- "history"
 - When sending `m`, send current history set, too
 - Receiver delays incoming msg `m` until has received everything in `m`'s set

History sets will grow huge -- can we abbreviate?

 - Each node numbers its msgs 1, 2, 3, &c
 - Deliver each node's msgs in order
 - Then history need only include latest # seen from each node
   + H1/4 implies saw 1, 2, 3 also
 - This notation doesn't grow over time, unlike history sets
 - Called a _Vector Timestamp_ or _Version Vector_

### Vector Timestamp

 - Each node numbers its own actions (sent msgs, in this case)
 - VT is a vector of numbers, one slot per node
 - Each message sent out with a VT
 - `VT[i]=x =>` sender had seen all msgs from node `i` up through `#x`
 - the assumption here is that a node broadcasts messages to all
   other nodes (since we're trying to replicate a system effectively)
 - have to know how many nodes there are in the whole system
   + otherwise, complicated
 - VTs get very large when you have thousands of machines

VT comparisons

 - to answer "should msg A be displayed before msg B?"
 - let `a` and `b` denote the VTs associated with msgs `A` and `B`
 - we can reason about causality (i.e. is `a < b` or are they concurrent `a || b`)
 - four situations: `a < b, a || b`
 - `a < b` if two conditions hold:
   1. For all hosts `i`:
     - `a[i] <= b[i]`
         + i.e. `a` summarizes a proper prefix of `b`
         + i.e. either
              - `b`'s sender and `a`'s sender have both seen the same # of messages from host `i`
              - `b`'s sender has seen more recent message from host `i` than `a`'s sender has seen
   2. *AND* there exists `j, s.t. a[j] < b[j]`
     - i.e. `a` causally precedes `b`
         + `b`'s sender has _definitely_ seen more recent message from host `i` than `a`'s sender has seen
 - `a || b` if:
   + exists i,j: `a[i] < b[i]` and `a[j] > b[j]`
   + i.e. neither summarizes a prefix of the other
   + i.e. neither causally precedes the other
     - this is because, as we said before, there's no total order

Many systems use VT variants, but for somewhat different purposes

 - TreadMarks, Ficus, Bayou, Dynamo, &c
 - compact way to say _"I've seen everyone's updates up to this point"_
 - compact way to agree whether event `x` preceded event `y`
 - I am pretending there's one fundamental principle here
   + but it's only true if you stand fairly far back

### CBCAST -- "causal broadcast" protocol

 - General-purpose ordering protocol, useful for peer-to-peer chat
 - From Cornell Isis research project
 - Key property:
   + Delivers messages to individual nodes in causal order
   + If `a` causally precedes `b`, CBCAST delivers `a` first

[diagram: node, msg buf, VC, chat app]

        APP         ^
             |      |
        -----|------|-----------
            \ /     |  CBCAST
             .   
        ---------      vector
        | m3    |      clock
        ---------      VT 
        | wait  |
        ---------
        | m1    |


 - Each node keeps a local vector clock, `VC`
   + `VCi[j] = k` means node `i` has seen all msgs from `j` up through message `k`
   + Summarizes what the application has also seen
 - `send(m)` at node `i`:
   + `VCi[i] += 1`
   + `broadcast(m, i, VCi)`
 - on `receive(m, i, mv)` at node `j`:
   + `j`'s CBCAST library buffers the message
   + release to application only when:
     - `mv <= VCj`, except `mv[i] = VCj[i] + 1`
     - i.e. node `j` has seen every msg that causally precedes `m`
       `VCj[i] = mv[i]`
     - so msgs will reflect receipt of `m`

Code:
    
    on receive(message m, node i, timestamp v):
        release when:
            this node's vector clock VT >= v EXCEPT FOR v[i] = VT[i] + 1

Example:

        All VCs start <0,0,0>
        M0 sends msg1 w/ <1,0,0>
        M1 receives msg1 w/ <1,0,0>
        M1 sends msg2 w/ <1,1,0>
        M2 receives msg2 w/ <1,1,0> -- must delay because don't have msg1
        M2 receives msg1 w/ <1,0,0> -- can process, unblocks other msg

Why fast?

 - No central manager, no global order
 - If no causal dependencies, CBCAST doesn't delay messages
 - Example:
   + `M0 sends <1,0>`
   + `M1 sends <0,1>`
   + Receivers are allowed to deliver in either order

Causal consistency still allows more surprises than sequential

 - Sam can still see:
   + Joe: 40
   + Fred: 41
   + Bob: 42
   + Alice: That's correct
 - Did she mean 42 or 41?
 - Causal consistency only says Alice's msg will be delivered after
   + all msgs she had seen when she sent it
 - *Not* that it will be delivered before all msgs she hadn't seen
   + `=>` if CBCAST present `x` and then `y` that does *not* imply `x` happened before `y` necessarily

TreadMarks uses VTs to order writes to same variable by different machines:

      M0: a1 x=1 r1    a2 y=9 r2
      M1:              a1 x=2 r1
      M2:                           a1 a2 z=x+y r2 r1

      Could M2 hear x=2 from M1, then x=1 from M0?
      How does M2 know what to do?

VTs are often used for optimistic updating of replicated data

 - Everyone has a copy, anyone can write
 - Don't want IVY-style MGR or locking: network delays, failures
 - Need to sync replicas, accept only "newest" data, detect conflicts
 - File sync (Ficus, Coda, Rumor)
 - Distributed DBs (Amazon Dynamo, Voldemort, Riak)

File synchronization -- e.g. Ficus
----------------------------------

 - Multiple computers have a copy of all files
 - Each can modify its local copy
 - Merge changes later -- optimistic
 - fie synchronization with disconnected operation support
   + two people edit the same file on two different airplanes :)
   + when they get back online, server needs to detect this
   + ...and solve it
   + ...and not lose updates (lazy server can just throw away
     one set of changes)

Scenario:

 - user has files replicated at work, at home, on laptop
 - hosts may be off, on airplane, &c -- not always on Internet
 - work on `H1` for a while, sync changes to `H2`
 - work on `H2`, sync changes to `H3`
 - work on `H3`, sync to `H1`
 - **Overall goal:** push changes around to keep machines identical

Constraint: No Lost Updates

 - Only OK for sync to copy version `x2` over version `x1` if
   + `x2` includes all updates that are in `x1`.

Example 1:

      Focus on a single file

      H1: f=1 \----------\
      H2:      \->  f=2   \               /--> ???
      H3:                  \-> tell H2 --/

      What is the right thing to do?
      Is it enough to simply take file with latest modification time?
      Yes in this case, as long as you carry them along correctly.
        I.e. H3 remembers mtime assigned by H1, not mtime of sync.
       

Example 2:

       mtime = 10 | mtime = 20 | mtime = 25
                        
      H1: f=1 --\       f=2              /-->
      H2:        \-->             f=0 --/
      H3: 

      H2's mtime will be bigger.

      Should the file synchronizer use "0" and discard "2"?
        No! They were conflicting changes. We need to detect this case.
        Modification times are not enough by themselves

What if there were concurrent updates?

 - So that neither version includes the other's updates?
 - Copying would then lose one of the updates
 - So sync doesn't copy, declares a "conflict"
 - Conflicts are a necessary consequence of optimistic writes

How to decide if one version contains all of another's updates?

 - We could record each file's entire modification history.
 - List of hostname/localtime pairs.
 - And carry history along when synchronizing between hosts.
 - For example 1:   `H2: H1/T1,H2/T2   H3: H1/T1`
 - For example 2:   `H1: H1/T1,H1/T2   H2: H1/T1,H2/T3`
 - Then its easy to decide if version `x` supersedes version `y`:
   + If `y`'s history is a prefix of `x`'s history.

We can use VTs to compress these histories!

 - Each host remembers a VT per file
 - Number each host's writes to a file (or assign wall-clock times)
 - Just remember # of last write from each host
 - `VT[i]=x` => file version includes all of host `i`'s updates through `#x`

VTs for Example 1:

 - After H1's change: `v1=<1,0,0>`
 - After H2's change: `v2=<1,1,0>`
 - `v1 < v2`, so H2 ignores H3's copy (no conflict since `<`)
 - `v2 > v1`, so H1/H3 would accept H2's copy (again no conflict)

VTs for Example 2:

 - After H1's first change: `v1=<1,0,0>`
 - After H1's second change: `v2=<2,0,0>`
 - After H2's change: `v3=<1,1,0>`
 - v3 neither `<` nor `>` v1
   + thus neither has seen all the other's updates
   + thus there's a conflict

What if there *are* conflicting updates?

 - VTs can detect them, but then what?
 - Depends on the application.
 - _Easy:_ mailbox file with distinct immutable messages, just union.
 - _Medium:_ changes to different lines of a C source file (diff+patch).
 - _Hard:_ changes to the same line of C source.
 - Reconciliation must be done manually for the hard cases.
 - Today's paper is all about reconciling conflicts

How to think about VTs for file synchronization?

 - They detect whether there was a serial order of versions
 - I.e. when I modified the file, had I already seen your modification?
   + If yes, no conflict
   + If no, conflict
 - Or:
   + A VT summarizes a file's complete version history
   + There's no conflict if your version is a prefix of my version

What about file deletion?

 - Can H1 just forget a file's VT if it deletes the file?
   + No: when H1 syncs w/ H2, it will look like H2 has a new file.
 - H1 must remember deleted files' VTs.
 - Treat delete like a file modification.
   + `H1: f=1  ->H2 `
   + `H2:           del  ->H1`
   + second sync sees `H1:<1,0> H2<1,1>`, so delete wins at H1
 - There can be delete/write conflicts
   + `H1: f=1  ->H2  f=2`
   + `H2:            del  ->H1`
   + `H1:<2,0> vs H2:<1,1> -- conflict`
   + Is it OK to delete at H1?

How to delete the VTs of deleted files?

Is it enough to wait until all hosts have seen the delete msg?

 - Sync would carry, for deleted files, set of hosts who have seen del

"Wait until everyone has seen delete" doesn't work:

 - `H1:                           ->H3        forget`
 - `H2: f=1 ->H1,H3 del,seen ->H1                   ->H1`
 - `H3:                             seen ->H1`
 - `H2 needs to re-tell H1 about f, deletion, and f's VT`
   + H2 doesn't know that H3 has seen the delete
   + So H3 might synchronize with H1 and it *would* then tell H1 of f
   + It would be illegal for to to disappear on H1 and re-appear
 - So -- this scheme doesn't allow hosts to forget reliably

Diagram:

                     | Phase 1              | Phase 2               | Phase 3 (forget f's VT)
    H1: del f  \     | seen f  -\->         | done f  -\->          |
    H2:         \--> | seen f  -/-> (bcast) | done f  -/-> (bcast)  |
    H3:         |--> | seen f  -\->         | done f  -\->          |

Working VT GC scheme from Ficus replicated file system

 - _Phase 1:_ accumulate set of nodes that have seen delete
   + terminates when == complete set of nodes
 - _Phase 2:_ accumulate set of nodes that have completed Phase 1
   + when == all nodes, can totally forget the file
 - If H1 then syncs against H2,
   + H2 must be in Phase 2, or completed Phase 2
   + if in Phase 2, H2 knows H1 once saw the delete, so need not tell H1 abt file
   + if H2 has completed Phase 2, it doesn't know about the file either

A classic problem with VTs:

 - Many hosts -> big VTs
 - Easy for VT to be bigger than the data!
 - No very satisfying solution

Many file synchronizers don't use VTs -- e.g. Unison, rsync

 - File modification times enough if only two parties, or star
 - Need to remember "modified since last sync"
 - VTs needed if you want any-to-any sync with > 2 hosts

Summary
-------
 - Replication + optimistic updates for speed, high availability
 - Causal consistency yields sane order of optimistic updates (CBCAST)
 - Causal ordering detects conflicting updates
 - Vector Timestamps compactly summarize update histories

