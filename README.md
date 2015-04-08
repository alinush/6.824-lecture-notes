Distributed Systems Engineering notes (6.824, Spring 2015)
==========================================================

Lectures
--------

Lecture notes from 6.824, taught by [Prof. Robert T. Morris](http://pdos.csail.mit.edu/rtm/). These lecture notes are slightly modified from the ones posted on the 6.824 [course website](http://nil.csail.mit.edu/6.824/2015/schedule.html).

 * Lecture 1: [Introduction](l01-intro.html): distributed system definition, motivations, architecture, implementation, performance, fault-tolerance, consistency, MapReduce 
 * Lecture 2: [Remote Procedure Calls (RPCs)](l02-rpc.html): RPC overview, marshalling, binding, threads, "at-least-once", "at-most-once", "exactly once", Go's RPC, thread synchronization
 * Lecture 3: [Fault tolerance](l03-fault-tolerance.html): primary-backup replication, state transfer, "split-brain", Remus (NSDI 2008),  
 * Lecture 4: [Flat datacenter storage](l04-more-primary-backup.html): flat datacenter storage
 * Lecture 5: [Paxos](l05-paxos.html): Paxos, a consensus algorithm
    + [Paxos algorithm description](paxos-algorithm.html)
 * Lecture 6: [Raft](l06-raft.html): Raft, a more understandable consensus algorithm
 * Lecture 7: **Google Go** [_guest lecture_](l07-go.html) by Russ Cox
 * Lecture 8: [Harp](l08-harp.html): distributed file system
 * Lecture 9: [IVY](l09-dist-comp-seq-consistency.html): distributed shared memory, sequential consistency
 * Lecture 10: [TreadMarks](l10-treadmarks.html): userspace distributed shared memory system, vector timestamps, release consistency (lazy/eager), false sharing, write amplification
 * Lecture 11: [Ficus](l11-ficus.html): optimistic concurrency control, vector timestamps, conflict resolution
 * Lecture 12: [Bayou](l12-bayou.html): disconnected operation, eventual consistency, Bayou
 * Lecture 13: [MapReduce](l13-mapreduce.html): MapReduce, scalability, performance
 * Lecture 14: **Spark** [_guest lecture_](l14-spark.html) by Matei Zaharia: Resilient Distributed Datasets, Spark
 * Lecture 15: **Spanner** [_guest lecture_](l15-spanner.html) by Wilson Hsieh, Google: Spanner, distributed database, clock skew

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
 17. [Argus](papers/argus88.pdf)
 18. [Kademlia](papers/kademlia.pdf)
 19. [Bitcoin](papers/bitcoin.pdf)
 20. [AnalogicFS](papers/katabi-analogicfs.pdf)

Quizzes
-------

Prep for quiz 1 [here](exams/quiz1/quiz1.html)
