6.824 2015 Lecture 16: Memcache at Facebook
===========================================

**Note:** These lecture notes were slightly modified from the ones posted on the
6.824 [course website](http://nil.csail.mit.edu/6.824/2015/schedule.html) from 
Spring 2015.

Introduction
------------

Facebook Memcached paper:

 - an experience paper, not a research results paper
 - you can read it as a triumph paper
 - you can read it as a caution paper: what happens when you don't think
   about scalability
 - you can read it as a trade-offs paper

Scaling a webapp
----------------

Initial design for any webapp is a single webserver machine with a DB server
running on it.

Diagram (single machine: webserver and DB server)
    
    Single machine
    -------------------
    | Web app         |
    |                 | 
    |                 |
    |                 |
    |       | DB | <-----> |Disk|
    ------------------

 - eventually they find out they use 100% of the CPU on this machine
 - `top` will tell them the CPU time is going to the web-app


Diagram (multiple webserver machines, single DB machine):
    
    Web app -----
    Web app      \ -----> |DB| <-> Disk
    ...
    Web app             
 
 - next problem they will face is the database will be the bottleneck
   + DB CPU is 100% or disk is 100%
 - say they decide to buy a bunch of DB servers

Diagram:

    Web app             |DB1| <-> Disk  (users A-M)
    Web app             |DB2| <-> Disk  (users N-T)
    ...                 |DB3| <-> Disk  ...
    Web app             ...    

 - now they gotta figure out how to _shard_ the data on the database
 - application software now has to know which DB server to talk to
 - we can no longer have transactions across the whole DB
 - we can no longer have single queries on the entire dataset
   + need to send separate queries to each server
 - you can't push this too far because after a while the shards get very small
   and you get database servers that become hotspots

Next, you notice that most of the operations in the DB are reads (if that's
the case. It is at Facebook.)

 - it turns out you can build a very simple memory cache that can serve half
   a million requests per second
 - then you can remove 90% of the load on the database


Diagram:

    Web app -> |MC| --> |DB1| <-> Disk  (users A-M)
    Web app    |MC|     |DB2| <-> Disk  (users N-T)
    ...         ..      |DB3| <-> Disk  ...
    Web app             ...    

 - the next bottleneck will be database writes, if you keep growing your service

Observation: you could use DB read-only replicas, instead of your own customized
memcache (MC) nodes. Facebook did not do this because they wanted to separate
their caching logic from their DB deployment:

 > It was the best choice given limited engineering
 > resources and time. Additionally, separating our
 > caching layer from our persistence layer allows us to adjust
 > each layer independently as our workload changes

Facebook's use case
-------------------

**Very crucial:** they do not care too much about all their users getting a consistent
view of their system.

The only case when the paper cares about freshness and consistency is when
webapp clients read their own writes.

Their high level picture:

    Regions (data centers):
        Master region (writable)
       ----------------- 
      | Web1 Web2 ...   |
      | MC1  MC2  ...   |
      | DB1  DB2  ... <--- complete copy of all data
       -----------------

        Slave regions (read only)
       ----------------- 
      | Web1 Web2 ...   |
      | MC1  MC2  ...   |
      | DB1  DB2  ... <--- complete copy of all data
       -----------------

The reason for having multiple data centers: parallelism across the globe

 - maybe also for backup purposes (paper doesn't detail too much)

Big lessons
-----------

### Look-aside caching can be tricky

This style of look-aside caching, where the application looks in the cache
to see what's there, is extremely easy to add to an existing system

 - but there are some nasty consistency problems that appear when the caching
   layer is oblivious to what happens in the DB

### Caching is about throughput not latency

It wasn't about reducing latency for the users. They were using the cache to
increase throughput and take the load off the database.

 - no way the DB could've handled the load, which is 10x or 100x more than
   what the DB can access

### They can tolerate stale data

### They want to be able to read their own writes

You'd think this can be easily fixed in the application. Slightly surprised that
this was not fixed by just having the application remembering the writes. Not 
clear why they solved it differently.

### Eventual consistency is good enough

### They have enormous fan-out

Each webpage they serve might generate hundreds and hundreds of reads. A little
bit surprising. So they have to do a bunch of tricks. Issue the reads in parallel.
When a single server does this, it gets a bunch of responses back, and the amount
of buffering in the switches and webservers is limited, so if they're not careful
they can lose packets and thus performance when retrying.

Performance
-----------

 - a lot of content about consistency in the paper
 - but really they were desperate to get performance which led to doing tricks,
   which led to consistency problems
 - performance comes from being able to serve a lot of `Get`'s in parallel

Really only two strategies:

 - partition data
 - replicate data
 - they use both

Partitioning works if keys are roughly all as popular. Otherwise, certain 
partitions would be more popular and lead to hotspots. Replication helps with
handling demand for popular keys. Also, replication helps with requests from
remote places in the world.

You can't simply cache keys in the web app servers, because they would all
fill their memories quickly and you would double-store a lot of data.

Specific problem they dealt with
--------------------------------

Each cluster has a full set of memcache servers and a full set of web servers.
Each web server talks to memcache servers in its own cluster.

### Adding a new cluster

Sometimes, they want to add a new cluster, which will obviously have empty memcache
servers.

 - all webservers in new cluster will always miss on every request and will
   have to go down and contact the DB, which cannot handle the increased load
 - instead of contacting the DB, the new cluster will contact memcache servers
   from other clusters until the new cluster's cache is warmed up

**Q:** what benefit do they get from adding new clusters? instead of increasing
size of existing cluster?

 - one possibility is there are some very popular keys so over-partitioning a 
   cluster won't help with that
 - another possibility could be that it's easier to add more memcache servers
   by adding a new cluster, because of the data movement problem

### Memcache server goes down

If a memcache server goes down, requests are redirected to a gutter server.
The gutter machines will miss a lot initially, but at least it will be caching
the results for the future.

### Homework question:

**Q:** Why aren't gutters invalidated on writes? 

On a write, DB typically sends an invalidate to all the MC servers that might 
have that key. So there's a lot of deletes being sent around to a lot of MC 
servers. Maybe they don't want to overflow the gutter servers with all the deletes.

Note that gutter keys expire after a certain time, to deal with the fact that 
the keys never change.

Not clear what happens if gutter servers go down.

**Q:** Wouldn't it better if the DB server sent the out the new value instead
of invalidate. 
 
 - what's cached in MC, might not be the DB value, but it might be some function
   of the DB value, that the DB layer is not aware of
   + think of how a friend list is stored in a DB versus how it would be stored in MC

### Leases for thundering herds 

One client sends an update to the DB and that gets a popular key invalidated.
So now lots of lots of clients generate Get's into MC, but the key was deleted,
which would lead to lots of DB queries and then lots of caching of the result.

If memcache receives a get for a key that's not present, it will set a lease
on that key and say "you're allowed to go ask the DB for this key, but please
finish doing this in 10 seconds." When subsequent Get's come in, they are told
"no such key, but another guy is getting it, so please wait for him instead of
querying the DB"

The lease is cancelled after 10s or when the owner sets the key.

Each cluster will generate a separate lease.

6.824 notes
===========

    Scaling Memcache at Facebook, by Nishtala et al, NSDI 2013

    why are we reading this paper?
      it's an experience paper, not about new ideas/techniques
      three ways to read it:
        cautionary tale of problems from not taking consistency seriously
        impressive story of super high capacity from mostly-off-the-shelf s/w
        fundamental struggle between performance and consistency
      we can argue with their design, but not their success

    how do web sites scale up with growing load?
      a typical story of evolution over time:
      1. one machine, web server, application, DB
         DB stores on disk, crash recovery, transactions, SQL
         application queries DB, formats, HTML, &c
         but the load grows, your PHP application takes too much CPU time
      2. many web FEs, one shared DB
         an easy change, since web server + app already separate from storage
         FEs are stateless, all sharing (and concurrency control) via DB
         but the load grows; add more FEs; soon single DB server is bottleneck
      3. many web FEs, data sharded over cluster of DBs
         partition data by key over the DBs
           app looks at key (e.g. user), chooses the right DB
         good DB parallelism if no data is super-popular
         painful -- cross-shard transactions and queries probably don't work
           hard to partition too finely
         but DBs are slow, even for reads, why not cache read requests?
      4. many web FEs, many caches for reads, many DBs for writes
         cost-effective b/c read-heavy and memcached 10x faster than a DB
           memcached just an in-memory hash table, very simple
         complex b/c DB and memcacheds can get out of sync
         (next bottleneck will be DB writes -- hard to solve)

    the big facebook infrastructure picture
      lots of users, friend lists, status, posts, likes, photos
        fresh/consistent data apparently not critical
        because humans are tolerant?
      high load: billions of operations per second
        that's 10,000x the throughput of one DB server
      multiple data centers (at least west and east coast)
      each data center -- "region":
        "real" data sharded over MySQL DBs
        memcached layer (mc)
        web servers (clients of memcached)
      each data center's DBs contain full replica
      west coast is master, others are slaves via MySQL async log replication

    how do FB apps use mc?
      read:
        v = get(k) (computes hash(k) to choose mc server)
        if v is nil {
          v = fetch from DB
          set(k, v)
        }
      write:
        v = new value
        send k,v to DB
        delete(k)
      application determines relationship of mc to DB
        mc doesn't know anything about DB
      FB uses mc as a "look-aside" cache
        real data is in the DB
        cached value (if any) should be same as DB

    what does FB store in mc?
      paper does not say
      maybe userID -> name; userID -> friend list; postID -> text; URL -> likes
      basically copies of data from DB

    paper lessons:
      look-aside is much trickier than it looks -- consistency
        paper is trying to integrate mutually-oblivious storage layers
      cache is critical:
        not really about reducing user-visible delay
        mostly about surviving huge load!
        cache misses and failures can create intolerable DB load
      they can tolerate modest staleness: no freshness guarantee
      stale data nevertheless a big headache
        want to avoid unbounded staleness (e.g. missing a delete() entirely)
        want read-your-own-writes
        each performance fix brings a new source of staleness
      huge "fan-out" => parallel fetch, in-cast congestion

    let's talk about performance first
      majority of paper is about avoiding stale data
      but staleness only arose from performance design

    performance comes from parallel get()s by many mc servers
      driven by parallel processing of HTTP requests by many web servers
      two basic parallel strategies for storage: partition vs replication

    will partition or replication yield most mc throughput?
      partition: server i, key k -> mc server hash(k)
      replicate: server i, key k -> mc server hash(i)
      partition is more memory efficient (one copy of each k/v)
      partition works well if no key is very popular
      partition forces each web server to talk to many mc servers (overhead)
      replication works better if a few keys are very popular

    performance and regions (Section 5)

    Q: what is the point of regions -- multiple complete replicas?
       lower RTT to users (east coast, west coast)
       parallel reads of popular data due to replication
       (note DB replicas help only read performance, no write performance)
       maybe hot replica for main site failure?

    Q: why not partition users over regions?
       i.e. why not east-coast users' data in east-coast region, &c
       social net -> not much locality
       very different from e.g. e-mail

    Q: why OK performance despite all writes forced to go to the master region?
       writes would need to be sent to all regions anyway -- replicas
       users probably wait for round-trip to update DB in master region
         only 100ms, not so bad
       users do not wait for all effects of writes to finish
         i.e. for all stale cached values to be deleted
       
    performance within a region (Section 4)

    multiple mc clusters *within* each region
      cluster == complete set of mc cache servers
        i.e. a replica, at least of cached data

    why multiple clusters per region?
      why not add more and more mc servers to a single cluster?
      1. adding mc servers to cluster doesn't help single popular keys
         replicating (one copy per cluster) does help
      2. more mcs in cluster -> each client req talks to more servers
         and more in-cast congestion at requesting web servers
         client requests fetch 20 to 500 keys! over many mc servers
         MUST request them in parallel (otherwise total latency too large)
         so all replies come back at the same time
         network switches, NIC run out of buffers
      3. hard to build network for single big cluster
         uniform client/server access
         so cross-section b/w must be large -- expensive
         two clusters -> 1/2 the cross-section b/w

    but -- replicating is a waste of RAM for less-popular items
      "regional pool" shared by all clusters
      unpopular objects (no need for many copies)
      decided by *type* of object
      frees RAM to replicate more popular objects

    bringing up new mc cluster was a serious performance problem
      new cluster has 0% hit rate
      if clients use it, will generate big spike in DB load
        if ordinarily 1% miss rate, and (let's say) 2 clusters,
          adding "cold" third cluster will causes misses for 33% of ops.
        i.e. 30x spike in DB load!
      thus the clients of new cluster first get() from existing cluster (4.3)
        and set() into new cluster
        basically lazy copy of existing cluster to new cluster
      better 2x load on existing cluster than 30x load on DB

    important practical networking problems:
      n^2 TCP connections is too much state
        thus UDP for client get()s
      UDP is not reliable or ordered
        thus TCP for client set()s
        and mcrouter to reduce n in n^2
      small request per packet is not efficient (for TCP or UDP)
        per-packet overhead (interrupt &c) is too high
        thus mcrouter batches many requests into each packet
        
    mc server failure?
      can't have DB servers handle the misses -- too much load
      can't shift load to one other mc server -- too much
      can't re-partition all data -- time consuming
      Gutter -- pool of idle servers, clients only use after mc server fails

    The Question:
      why don't clients send invalidates to Gutter servers?
      my guess: would double delete() traffic
        and send too many delete()s to small gutter pool
        since any key might be in the gutter pool

    thundering herd
      one client updates DB and delete()s a key
      lots of clients get() but miss
        they all fetch from DB
        they all set()
      not good: needless DB load
      mc gives just the first missing client a "lease"
        lease = permission to refresh from DB
        mc tells others "try get() again in a few milliseconds"
      effect: only one client reads the DB and does set()
        others re-try get() later and hopefully hit

    let's talk about consistency now

    the big truth
      hard to get both consistency (== freshness) and performance
      performance for reads = many copies
      many copies = hard to keep them equal

    what is their consistency goal?
      *not* read sees latest write
        since not guaranteed across clusters
      more like "not more than a few seconds stale"
        i.e. eventual
      *and* writers see their own writes
        read-your-own-writes is a big driving force

    first, how are DB replicas kept consistent across regions?
      one region is master
      master DBs distribute log of updates to DBs in slave regions
      slave DBs apply
      slave DBs are complete replicas (not caches)
      DB replication delay can be considerable (many seconds)

    how do we feel about the consistency of the DB replication scheme?
      good: eventual consistency, b/c single ordered write stream
      bad: longish replication delay -> stale reads

    how do they keep mc content consistent w/ DB content?
      1. DBs send invalidates (delete()s) to all mc servers that might cache
         + Do they wait for ACK? I'm guessing no.
      2. writing client also invalidates mc in local cluster
         for read-your-writes

    why did they have consistency problems in mc?
      client code to copy DB to mc wasn't atomic:
        1. writes: DB update ... mc delete()
        2. read miss: DB read ... mc set()
      so *concurrent* clients had races

    what were the races and fixes?

    Race 1: one client's cached get(k) replaces another client's updated k
      k not in cache
      C1: MC::get(k), misses
      C1: v = read k from DB
        C2: updates k in DB
        C2: and DB calls MC::delete(k) -- k is not cached, so does nothing
      C1: set(k, v)
      now mc has stale data, delete(k) has already happened
      will stay stale indefinitely, until key is next written
      solved with leases -- C1 gets a lease, but C2's delete() invalidates lease,
        so mc ignores C1's set
        key still missing, so next reader will refresh it from DB

    Race 2: updating(k) in cold cluster, but getting stale k from warm cluster 
      during cold cluster warm-up
      remember clients try get() in warm cluster, copy to cold cluster
      k starts with value v1
      C1: updates k to v2 in DB
      C1: delete(k) -- in cold cluster
      C2: get(k), miss -- in cold cluster
      C2: v1 = get(k) from warm cluster, hits
      C2: set(k, v1) into cold cluster
      now mc has stale v1, but delete() has already happened
        will stay stale indefinitely, until key is next written
      solved with two-second hold-off, just used on cold clusters
        after C1 delete(), cold ignores set()s for two seconds
        by then, delete() will propagate via DB to warm cluster

    Race 3: writing to master region, but reading stale from local
      k starts with value v1
      C1: is in a slave region
      C1: updates k=v2 in master DB
      C1: delete(k) -- local region
      C1: get(k), miss
      C1: read local DB  -- sees v1, not v2!
      later, v2 arrives from master DB
      solved by "remote mark"
        C1 delete() marks key "remote"
        get()/miss yields "remote"
          tells C1 to read from *master* region
        "remote" cleared when new data arrives from master region

    Q: aren't all these problems caused by clients copying DB data to mc?
       why not instead have DB send new values to mc, so clients only read mc?
         then there would be no racing client updates &c, just ordered writes
    A:
      1. DB doesn't generally know how to compute values for mc
         generally client app code computes them from DB results,
           i.e. mc content is often not simply a literal DB record
      2. would increase read-your-own writes delay
      3. DB doesn't know what's cached, would end up sending lots
         of values for keys that aren't cached

    PNUTS does take this alternate approach of master-updates-all-copies

    FB/mc lessons for storage system designers?
      cache is vital to throughput survival, not just a latency tweak
      need flexible tools for controlling partition vs replication
      need better ideas for integrating storage layers with consistency
