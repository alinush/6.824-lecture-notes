Distributed Systems Engineering notes (6.824, Spring 2015)
==========================================================

Lecture notes from 6.824, taught by [Prof. Robert T. Morris](http://pdos.csail.mit.edu/rtm/). These lecture notes are slightly modified from the ones posted on the 6.824 [course website](http://nil.csail.mit.edu/6.824/2015/schedule.html).

 * Lecture 1: [Introduction](l01-intro.html): distributed system definition, motivations, architecture, implementation, performance, fault-tolerance, consistency, MapReduce 
 * Lecture 2: [Remote Procedure Calls (RPCs)](l02-rpc.html): RPC overview, marshalling, binding, threads, "at-least-once", "at-most-once", "exactly once", Go's RPC, thread synchronization
 * Lecture 3: [Fault tolerance](l03-fault-tolerance.html): primary-backup replication, state transfer, "split-brain", Remus (NSDI 2008),  
 * Lecture 4: [Flat datacenter storage](l04-more-primary-backup.html): flat datacenter storage
 * Lecture 5: [Paxos](l05-paxos.html): Paxos, a consensus algorithm
   + [Paxos algorithm description](paxos-algorithm.html)
 * Lecture 6: [Raft](l06-raft.html): Raft, a more understandable consensus algorithm
 * Lecture 7: **Google Go** _guest lecture_ by Russ Cox
 * Lecture 8: [Harp](l08-harp.html): distributed file system
 * Lecture 9: [IVY](l09-dist-comp-seq-consistency.html): Ivy, a distributed shared memory system

**TODO:** add [papers](papers/)
