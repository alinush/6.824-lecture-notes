6.824 2015 Lecture 18: Amazon's Dynamo keystore
===============================================

**Note:** These lecture notes were slightly modified from the ones posted on the
6.824 [course website](http://nil.csail.mit.edu/6.824/2015/schedule.html) from 
Spring 2015.

Dynamo
------
 
 - eventually consistent
 - considerably less consistent than PNUTS or Spanner
 - successful open source projects like Cassandra that have built upon the
   ideas of Dynamo

Design
------
 
 - really worried about their service level agreements (SLA)
   + internal SLAs, say between webserver and storage system
 - worried about _worst-case_ perf., not average perf.
 - they want 99.9th percentile of delay `< 300ms`
   + not very clear how this requirement worked itself in the design
   + what choices were made to satisfy this?
 - supposed to deal w/ constant failures
   + entire data center offline
 - they need the system to be always writeable
   + `=>` no single master

Diagram:

    Datacenter

        Frontend            Dynamo server
        server
                            Dynamo server
        Frontend
        server              Dynamo server

                            Dynamo server

 - Guess: amazon has quite a lot of data centers and no one of them are
   primary or backup, then even if a datacenter goes down only a small
   fraction of your system is down
   + much more natural to, instead of replicating every record everywhere, to
     just replicate it on 2 or 3 data centers
 - design of Dynamo is not really data-center oriented
 - difference from PNUTS is that there's nothing about locality in their design
   + they don't worry about it: no copy of data is made to be near every client
 - they need the wide area network to work really well

Details
-------

 - always writeable `=>` no single master `=>` different puts on different
   servers `=>` conflicting updates
 - where should puts go and where should gets go so that they are likely to see
   data written by puts

### Consistent hashing

 - you hash the key and it tells you what server to put/get it from
 - hash output space is a ring/circle
 - every key's hash is a point on this circle
 - every node's hash is also a point
 - `=>` a key will be between nodes or on a node in the circle
 - node closest to key on the circle (clockwise) is the key's _coordinator_
 - if key is replicated `N` times, then the `N` successor nodes (clockwise)
   after the key store the key
 - even with random choice of node IDs, consistent hashing doesn't uniformly
   spread the keys across nodes
   + the # of keys on a node is proportional to the gap between that node
     and its predecessor
   + the distribution of gaps is pretty wide
 - to make up for this, virtual nodes are used
   + each physical node is made up of a certain # of virtual nodes, proportional
     to the perf/capacity of the physical node

Preference lists:

 - suppose you have nodes A, B, C, D, E, F and key `k` that hashes before node A
 - this key `k` should have 3 copies stored at A, B and C, if `N = 3`
 - request could go to the first node A, which could be down
   + or it could go to the first node A, which would try to replicate 
     it on node B and C, which could be down
   + `=>` this first node would replicate on nodes D and E
   + `=>` more than `N` nodes that could have the data
   + `=>` remember all these nodes in a _preference list_
 - request for `k` goes to the first node in the preference list
 - that node acts as a coordinator for the request and reads/writes the key
   on all other nodes
 - sloppy quorums, 
    + `N` the # of nodes the coordinator sends the request to
    + `R` the # of nodes the coordinator waits for data to come back on a get
    + `W` the # of nodes the coordinator waits for data to write on on a put
 - if there are no failures, the coordinator kind of acts like a master
 - if there are failures the sloppy quorum makes sure data is persisted, but
   inconsistencies can be created 
 - Trouble: because there aren't any real quorums, gets can miss the most recent
   puts
 - you can have nodes A, B, C store some put on state data, an nodes D, E, F
   store another put on data
   + the coordinator among D, E, F knows the data is out-of-place and stores
     a flag to indicate it should be passed to A, B, C (_hinted hand-off_)

Conflicts
---------

 - figure 3 in the paper
 - when there are 2 conflicting versions, client code has to be able to 
   reconcile them
 - dynamo uses version vectors just like [Ficus](l11-ficus.html)
   + `[a: 1] -> [a: 1, b: 3]`
   + `[a: 1] -> [a: 1, c: 3]`
   + `[a:1, b:3, c: 0]` and `[a:1, b:0, c:3]` conflicts
 - Dynamo is weaker than Bayou
 - both have a story for how to reconcile conflicted version
   - In dynamo we just have the two conflicting pieces of data, but we don't have
     the ops that were applied to the state (like remove/add smth from shopping cart)
   - Bayou has the log of the ops
 - PNUTS had atomic operation support like a `test-and-set-write` op
   + nothing like that in Dynamo
   + the only way to do that in Dynamo is to be able to merge two conflicting 
     versions

Performance
-----------

 - _Question to always ask about version vectors:_ What happens when the version
   vectors get too large?
   + they delete entries for nodes that have been modified a long time ago
     - `v1 = [a:1, b:7] -> v1' = [b:7]`
     - what can go wrong? if `[b:7]` is updated to `v2 = [b:8]` then
       `v2` will conflict with `v1`, even though it was derived directly from
       it, so the application will get some _false_ merges
 - they like that they can adjust `N, R, W` to get different trade-offs 
   + standard `3,2,2`
   + `3, 3, 1 -> ` write quickly but not very durably, reads are rare
   + `3, 1, 3 -> ` writes are slow, but reads are quite fast
 - the average delays are 5-10ms, much smaller than PNUTS or memcached
   + too small relative to speed-of-light across datacenters
   + but not clear where the data centers were, and what the workloads were
