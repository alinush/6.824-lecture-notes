Distributed Systems Engineering notes (6.824, Spring 2015)
==========================================================

Lectures
--------

Lecture notes from 6.824, taught by [Prof. Robert T. Morris](http://pdos.csail.mit.edu/rtm/). These lecture notes are slightly modified from the ones posted on the 6.824 [course website](http://nil.csail.mit.edu/6.824/2015/schedule.html).

 * Lecture 1: [Introduction](l01-intro.html): distributed system definition, motivations, architecture, implementation, performance, fault-tolerance, consistency, MapReduce 
 * Lecture 2: [Remote Procedure Calls (RPCs)](l02-rpc.html): RPC overview, marshalling, binding, threads, "at-least-once", "at-most-once", "exactly once", Go's RPC, thread synchronization
 * Lecture 3: [Fault tolerance](l03-fault-tolerance.html): primary-backup replication, state transfer, "split-brain", Remus (NSDI 2008),  
 * Lecture 4: [Flat datacenter storage](l04-more-primary-backup.html): flat datacenter storage, bisection bandwidth, striping
 * Lecture 5: [Paxos](l05-paxos.html): Paxos, consensus algorithms
    + [Paxos algorithm description](paxos-algorithm.html)
 * Lecture 6: [Raft](l06-raft.html): Raft, a more understandable consensus algorithm
 * Lecture 7: **Google Go** [_guest lecture_](l07-go.html) by Russ Cox
 * Lecture 8: [Harp](l08-harp.html): distributed file system, "the UPS trick", witnesses
 * Lecture 9: [IVY](l09-dist-comp-seq-consistency.html): distributed shared memory, sequential consistency
 * Lecture 10: [TreadMarks](l10-treadmarks.html): userspace distributed shared memory system, vector timestamps, release consistency (lazy/eager), false sharing, write amplification
 * Lecture 11: [Ficus](l11-ficus.html): optimistic concurrency control, vector timestamps, conflict resolution
 * Lecture 12: [Bayou](l12-bayou.html): disconnected operation, eventual consistency, Bayou
 * Lecture 13: [MapReduce](l13-mapreduce.html): MapReduce, scalability, performance
 * Lecture 14: **Spark** [_guest lecture_](l14-spark.html) by Matei Zaharia: Resilient Distributed Datasets, Spark
 * Lecture 15: **Spanner** [_guest lecture_](l15-spanner.html) by Wilson Hsieh, Google: Spanner, distributed database, clock skew
 * Lecture 16: [Memcache at Facebook](l16-memcached.html): web app scalability, look-aside caches, Memcache
 * Lecture 17: [PNUTS Yahoo!](l17-pnuts.html): distributed key-value store, atomic writes
 * Lecture 18: [Dynamo](l18-dynamo.html): distributed key-value store, eventual consistency
 * Lecture 19: **HubSpot** [_guest lecture_](l19-hubspot.html)
 * Lecture 20: [Two phase commit (2PC)](l20-argus.html): two-phase commit, Argus
 * Lecture 21: [Optimistic concurrency control](l21-thor.html)
 * Lecture 22: [Peer-to-peer, trackerless Bittorrent and DHTs](l22-peer-to-peer.html): Chord, routing
 * Lecture 23: [Bitcoin](l23-bitcoin.html): verifiable public ledgers, proof-of-work, double spending

Lectures form other years
-------------------------

 * [Practical Byzantine Fault Tolerance (PBFT)](extra/pbft.html)
    + Other years: [[2012]](original-notes/pbft-2012.txt), [[2011]](original-notes/pbft-2011.txt), [[2010]](original-notes/pbft-2010.txt), [[2009]](original-notes/pbft-2009.txt), [[2001]](original-notes/pbft-2001.txt), [[PPT]](original-notes/pbft.ppt)

Labs
----

 - Lab 1: MapReduce, [[assign]](lab1/index.html)
 - Lab 2: A fault-tolerant key/value service, [[assign]](lab2/index.html), [[notes]](lab2/notes.html)
 - Lab 3: Paxos-based Key/Value Service, [[assign]](lab3/index.html), [[notes]](lab3/notes.html)
 - Lab 4: Sharded Key/Value Service, [[assign]](lab4/index.html), [[notes]](lab4/notes.html)
 - Lab 5: Persistent Key/Value Service, [[assign]](lab5/index.html)

Papers
------

Papers we read in 6.824 ([directory here](papers/)):

 1. [MapReduce](papers/mapreduce.pdf)
 2. [Remus](papers/remus.pdf)
 3. [Flat datacenter storage](papers/fds.pdf)
 4. [Paxos](papers/paxos-simple.pdf)
 5. [Raft](papers/raft-atc14.pdf)
 6. [Harp](papers/bliskov-harp.pdf)
 7. [Shared virtual memory](papers/li-dsm.pdf)
 8. [TreadMarks](papers/keleher-treadmarks.pdf)
 9. [Ficus](papers/ficus.pdf)
 10. [Bayou](papers/bayou-conflicts.pdf)
 11. [Spark](papers/zaharia-spark.pdf)
 12. [Spanner](papers/spanner.pdf)
 13. [Memcached at Facebook](papers/memcache-fb.pdf)
 14. [PNUTS](papers/cooper-pnuts.pdf)
 15. [Dynamo](papers/dynamo.pdf)
 16. [Akamai](papers/akamai.pdf)
 17. [Argus](papers/argus88.pdf), [Guardians and actions](papers/guardians-and-actions-liskov.pdf)
 18. [Kademlia](papers/kademlia.pdf)
 19. [Bitcoin](papers/bitcoin.pdf)
 20. [AnalogicFS](papers/katabi-analogicfs.pdf)

Other papers:

 1. [Impossibility of Distributed Consensus with One Faulty Process](papers/flp.pdf)
    + See page 5, slide 10 [here](stumbled/flp-consensus.pdf) to understand Lemma 1 (commutativity) faster
    + See [this article here](http://the-paper-trail.org/blog/a-brief-tour-of-flp-impossibility/) for an alternative explanation.
 1. [Practical Byzantine Fault Tolerance (PBFT)](papers/pbft.pdf)
    + See [discussion here on PBFT](http://the-paper-trail.org/blog/barbara-liskovs-turing-award-and-byzantine-fault-tolerance/#more-211).

Stumbled upon
-------------

 1. [A brief history of consensus, 2PC and transaction commit](http://betathoughts.blogspot.com/2007/06/brief-history-of-consensus-2pc-and.html)
 1. [Distributed systems theory for the distributed systems engineer](http://the-paper-trail.org/blog/distributed-systems-theory-for-the-distributed-systems-engineer/)
 1. [Distributed Systems: For fun and Profit](http://book.mixu.net/distsys/)
 1. [You can't choose CA out of CAP](https://codahale.com/you-cant-sacrifice-partition-tolerance/), or "You can't sacrifice partition tolerance"
 1. [Notes on distributed systems for young bloods](https://www.somethingsimilar.com/2013/01/14/notes-on-distributed-systems-for-young-bloods/)
 1. [Paxos Explained From Scratch](stumbled/paxos-explained-from-scratch.pdf)

Quizzes
-------

Prep for quiz 1 [here](exams/quiz1/quiz1.html)
