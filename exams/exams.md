**TODO:** Harp, understand how primary forwards ops to backups and/or witnesses. What happens when some of them fail, etc.

**TODO:** Flat data center storage. Blob ID + tract # are mapped to a tract entry. In FDS there are `O(n^2)` tract entries. 3 servers per entry. All possible combinations. Why?

 - Why `O(n^2)`? We want replication => need 2 servers per TLT entry
   + simple, but slow recovery: `n` entries, TLT entry `i`: server `i`, sever `i+1`
     - when a server `i` fails, only 2 others have its data
         + `i-1` and `i+1`
   + better: have `O(n^2)` entries so that every pair occurs in the TLT
     - when a disk `i` fails, it occurs in `n-1` pairs 
       with other `n-1` servers
         + can use this to copy data from `n-1` disks at the same time
     - the problem: if a 2nd disk fails at the same time, then we lose data
         + because there will be no way to get the data for the pair
           formed by these two failed disks
   + even better: `O(n^2)` entries, all pairs of servers, and 
     for every pair, if doing k-level replication (`k > 2`), we add
     k-2 randomly picked servers to each entry's pair

 - But how are they mapped on disk? 
   + For now assume a dictionary/btree structure. 
 - When replacing a failed server, how is data transfer done? 
   + Is it just copied from the other servers in the TLT entry? 
   + How is a replacement picked? (Randomly apparently) 
   + Is the replacement server moved from its old TLT entry to the new one, or is it also left in the old TLT entry as well?
     - Figure 2 from paper suggests it is left in the old TLT entry

**TODO:** Primary backup replication, remind yourself when view is allowed to change.

**TODO:** Paxos, try to understand why np/na are needed and what happened if one of them was not used.

**TODO:** Raft, all of it.

**TODO:** Go's memory model

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
are also made visible?
 
 - Q1 2009, Question 11 seems to suggest yes.

**TODO:** Vector timestamps and causal consistency

**TODO:** Map reduce computation model, remember:

 - input file is split M ways, 
 - each split is sent to a `Map`,
 - each `Map()` returns a list of key-value pairs
   - map1 outputs {(k1, v1), (k2, v2)}
   - map2 outputs {(k1, v3), (k3, v4)}
 - key value pairs from `Map` calls are merged
 - reduce is called on each key and its values
   - reduce1 input is {(k1, {v1,v3})}
   - reduce2 input is {(k2, {v2})}
   - reduce3 input is {(k3, {v4})}


**TODO:** Sequential consistency is going to be on the exam!

**TODO:** The AnalogicFS paper, read it very carefully and understand it fully; it will definitely show up on the final.
