MapReduce
---------

Computation model, remember:

 - input file is split `M` ways, 
 - each split is sent to a `Map`,
 - each `Map()` returns a list of key-value pairs
   - map1 outputs {(k1, v1), (k2, v2)}
   - map2 outputs {(k1, v3), (k3, v4)}
 - key value pairs from `Map` calls are merged
 - reduce is called on each key and its values
   - reduce1 input is {(k1, {v1,v3})}
   - reduce2 input is {(k2, {v2})}
   - reduce3 input is {(k3, {v4})}
 - can you have a reduce job start before all maps are finished?
   - seems like it (see [here](https://ercoppa.github.io/HadoopInternals/AnatomyMapReduceJob.html))
   - actually seems like not (see [here](https://stackoverflow.com/questions/11672676/when-do-reduce-tasks-start-in-hadoop)
   - the reduce for key `k` can work on an iterator for 
     the list of values associated with `k`
     + instead of receiving the full list
   - as more map calls finish the iterator will have more 
     values to return for that key

RPCs
----

 - _at least once:_ send RPC req., wait for reply, retry if no reply
   + RPC calls are repeated `=>` needs side-effect free RPCs to work correctly
   + ordering can be messed up: `send(req1); send(req2); ack(req2); Nack(req1);
     resend(req1); ack(req1)`
     - `req1` was sent before `req2` but was executed after `req2`
 - _at most once:_ send RPC req. with XID, server executes RPC, remembers it by
   its XID, never executes it again if it receives it again (just replies with 
   remembered result)
   + no retries
   + discarding XIDs at the server side can be tricky
 - _exactly once:_ at most once, + retries, + fault tolerance (to ensure no
   corruption and hence _exactly once_ semantics)

Primary-backup replication
--------------------------

Strategies: 

 - state-transfer (transfer new state to backup, ala Remus)
 - replicated state machine (transfer ops to backups, ala Lab 2/3) 

P/B replication

 - Clients ask viewserver who primary is when they start up
 - Clients find out about view changes using `ErrWrongServer` replies
   to their RPC
   + They then query view server for new view

View changes:

 - If primary is dead...
   + If there's a backup...
     - Promote backup!
   + If there's no backup
     - Stall until primary comes back up
     - **DO NOT** accept an idle as a backup and then make backup primary
 - If backup is dead...
   + If there's an idle
     - Make it a backup!
   + If there's no idle
     - That's fine, we can work without a backup!
 - cannot change view until primary ACKs current view
   + primary ACK tells view server that primary copied the data on the backup
     - this way the view server knows that promoting the backup to primary
       is safe and can thus change the view

Views

 - more than two servers at a time might think they are backups
 - `P:S1, B:S2 and VS`
   + `P:S1` cannot reach `VS` anymore
   + `VS` promotes `S2` to primary
   + Thus, both think they are primaries
   + What happens when `S1` receives a `Get` RPC from a client?
     - It still thinks it's primary!
     - `=>` primary must forward **all** requests to backup
     - this way primary finds out if it's not primary anymore

Problem

 - view server fails => clients cannot make progress
   + Only if they need to contact the viewserver?
 - primary fails before backup had a chance to get the full DB => cannot make
   progress (or will break consistency)

Remus
-----

 - replicates entire machine state (RAM, disk, CPU registers, etc.)
 - primary receives a client request, does some work
 - primary is paused
 - primary sends state change to backup
 - primary **waits** for backup to acknowledge having received everything
 - primary does not reply to clients until backup has received new state
 - backup tells primary it's done copying
 - primary resumes and replies to client 

**TODO:** Harp, understand how primary forwards ops to backups and/or witnesses.
what happens when some of them fail, etc.

Flat data center storage
------------------------

Blob ID + tract # are mapped to a tract entry. In FDS, there are `O(n^2)` tract entries. 3 servers per entry. All possible combinations. Why?

 - Why `O(n^2)`? We want replication => need 2 servers per TLT entry
   + simple, but slow recovery: `n` entries, TLT entry `i`: server `i`, sever `i+1`
     - when a server `i` fails, only 2 others have its data
         + `i-1` and `i+1`
   + better: have `O(n^2)` entries so that every pair occurs in the TLT
     - when a disk `i` fails, it occurs in `n-1` pairs 
       with `n-1` other servers
         + can use this to copy data from `n-1` disks at the same time
         + disk `i` is replaced by **multiple** other disk
           + so we can read and write multiple disks at the same time while
             restoring
     - the problem: if a 2nd disk fails at the same time, then we lose data
         + because there will be no way to get the data for the pair
           formed by these two failed disks
   + even better: `O(n^2)` entries, all pairs of servers, and 
     for every pair, if doing k-level replication (`k > 2`), we add
     k-2 randomly picked servers to each entry's pair

But how are tracts mapped on disk? 

 - For now assume a dictionary/btree structure. 
 - When replacing a failed server, how is data transfer done? 
   + Is it just copied from the other servers in the TLT entry?
     - Yes!
   + How is a replacement picked? 
     - Randomly
     - Multiple replacements are picked, for each entry where the failed disk
       appeared
   + Is the replacement server moved from its old TLT entry to the new one, or
     is it also left in the old TLT entry as well?
     - Figure 2 from paper suggests it is left in the old TLT entry as well

Paxos
-----

**TODO:** Try to understand why `np`/`na` are needed and what happened if one of
them was not used.

Once a value was _chosen_ (`<=>` a majority of nodes accepted that value), then
no other different value can be re-chosen. Why?
 
 - any new proposer's `Prepare` will need a majority of `PREPARE_OK`'s to 
   move forward
 - any majority of peers will contain at least _one guy_ who has accepted the
   chosen value
   + again value was chosen `=>` a majority accepted it `=>` any other majority
     will contain at least one guy who accepted that value (properties of
     majority)
 - as a result, at least one of the `PREPARE_OK` replies will include an `na/va`
   pair with the chosen value
 - thus, the proposer can only propose the chosen value


**TODO:** Raft, all of it.

Go's memory model
-----------------

The actual Go memory model is as follows:
A read r of a variable v is allowed to observe a write w to v if both of the following hold:

 1. r does not happen before w.
 2. There is no other write w to v that happens after w but before r.

To guarantee that a read r of a variable v observes a particular write w to v, ensure that w is the
only write r is allowed to observe. That is, r is guaranteed to observe w if both of the following
hold:

 1. w happens before r.
 2. Any other write to the shared variable v either happens before w or after r.

This pair of conditions is stronger than the first pair; it requires that there are no other writes
happening concurrently with w or r.

Within a single goroutine, there is no concurrency, so the two definitions are equivalent: a read r
observes the value written by the most recent write w to v. When multiple goroutines access a
shared variable v, they must use synchronization events to establish happens-before conditions
that ensure reads observe the desired writes.

**TODO:** Write amplification vs. false sharing

**TODO:** TreadMarks: lazy release consistency (different than ERC) + causal consistency

**TODO:** Causal consistency: Does it ensure previous writes that did NOT contribute to current write
B
are also made visible?
 
 - Q1 2009, Question 11 seems to suggest yes.

**TODO:** Vector timestamps and causal consistency

**TODO:** Sequential consistency is going to be on the exam!

**TODO:** The AnalogicFS paper, read it very carefully and understand it fully; it will definitely show up on the final.
