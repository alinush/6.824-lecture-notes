**TODO:** Harp, understand how primary forwards ops to backups and/or witnesses. What happens when some of them fail, etc.

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
