6.824 2015 Lecture 17: PNUTS
============================

**Note:** These lecture notes were slightly modified from the ones posted on the
6.824 [course website](http://nil.csail.mit.edu/6.824/2015/schedule.html) from 
Spring 2015.

PNUTS
=====

 - a solution to the same problem Spanner and memcached solved
 - PNUTS is a more-principled designed than the memcache Facebook design
   + "it was actually designed"
 - make reads fast
 - upside: web applications are able to do fast local reads due to replication
 - downside: writes will be slow, because they need to be replicated
 - because writes have to be distributed to all the regions, there will
   be a fundamental delay between when writes happen and when the updates
   actually propagate
   + `=>` potential for stale reads
 - if there's data that could be updated by concurrent clients, there will
   be a problem with multiple writes
   + need all regions to see our writes in the same order

Diagram:

    Region R1                        Region R2
    ---------                        ---------

     W1 Mesage broker                 W1 Message broker
     W2     (replicated)              W2     (replicated)
     W3                               W3
     ..         Tablet controller     ..         Tablet controller
                    (replicated)                     (replicated)
        
        Router1 Router2 ...              Router1 Router2 ...     

        SU1 SU2 SU3 ...                  SU1 SU2 SU3 ...

        
 - each region has its own set of webservers
 - each region stores all data
 - each table in a region is partitioned among storage units (SUs)
 - routers know the partitioning
 - each SU has a disk

Updates
-------

 - each record in PNUTS has its own master region through which all writes have
   to go
   + different than memcache at facebook, they had a master region for _all_
     records
   + in PNUTS every record has a different master
   + Note: a record is just a row in a table (and has an extra field that
     stores its master)
 - updating records that are in regions far away from the user will take longer
   of course
 - how does the webserver know where to send the update?
   + contact one of the routers
   + router looks at the key, knows it's stored in say SU3
   + find out from SU3 that a different region `r2` has the master copy
     - doesn't know which SU at `r2` the record is at
   + contact one of the routers in `r2`
   + router tells you the SU to store it at
   + the SU then needs to send out the update to all the other regions
   + the SU sends the update to the message brokers
     - not clear if SU applies the update to its own disk before
   + the message broker writes a copy of the update to the disk
     because it is _committing_ to actually sending the update everywhere
     - important because we don't want a failed server to result in partially 
       propagating the update
   + the MB will send it out to other MBs at other sites 
   + somehow the web app needs to find out that the write completes
     - not clear who sends the ACK back
     - seems that the MB replies back to the webserver app as soon as it 
       commits the update to the disk
   + asynchronous writes because, from POV of webapp, write is done when MB has
     written it to its disk
   + why isn't the MB a bottleneck? It has to write a lot of stuff:
     - different applications have a different message broker
     - MB may be able to do much more batching of the writes
     - maybe also MB writes are also less complex than normal database writes
       where you have to modify Btrees, maybe go through a file system, etc.
   + because they funnel all the writes through some MB they get some 
     semantics for writes

Write semantics
---------------

### Write order to single records

    Name        Where       What
    ----        -----       ----
    Alice       home        asleep
    Bob         

 - Alice writes where record which has 3 columns (Name, Where, What)
 - Alice's application says `write(what=awake)`
   + write goes through PNUTS
 - Alice's application says `write(where=work)`
   + write goes through PNUTS
 - useful semantics given by PNUTS
   + other people in different regions might see
     - alice at home asleep
     - alice at home awake
     - alice at work awake
   + other people won't see a view of the record inconsistent with the order of
     the writes
     - alice at work asleep
   + kind of the main consistency semantics provided by PNUTS
   + a result of sequencing the writes through the MBs
   + paper calls this _per-record timeline consistency_
   + note that their model restricts them to only have transactions on a 
     single record basis

### When would you care about stale data?
 
 - after you added something to your shopping cart, you would expect to see it
   there

Reads vs. staleness

        read-any(key) -> fast read, just executes the read on the SU and does
                       not wait for any writes to propagate

        read-critical(key, ver) -> returns the read record where ver(record) >= ver
         - useful for reading your own writes
         - true when you have one webpage in a single tab
         - if you update your shopping cart in one tab, then the other tab
           will not be aware of that version number from the first tab

        read-latest(key) -> will always go to the master copy and read the latest
                          data there

### Writes, atomic updates

Example: increment a counter in a record
    
        test-and-set-write(ver, key, newvalue) -> always gets sent to the master
            region for the key. look at the version and if it matches provided
            one then update the record with the new value
            
            // implementing v[k]++
            while true:
                (x, v) = read-latest(k)
                if test-and-set-write(k, v, x+1)
                    break

Question of the day
-------------------

Alice comes back from spring break and she:

 - removes her mom from her ACL
 - posts spring break photos

Can her mom see her photos due to out-of-order writes?

If Alice has all the photos her mom can see in a single record, then no.

    Alice   |   ACL     | List of photos
    -------- ----------- ----------------
                mom         p7, p99

Assuming the code her mom is executing reads the full record (ACL + photos) when
doing the check, and doesn't first read the ACL, wait a while and then read
the photos

Failures
--------

If webapp server fails in the middle of doing a bunch of writes, then only
partial info would have been written to PNUTS, possibly leading to corruption.

 - no transactions for multiple writes

If SU crashes and reboots, it can recover from disk and MB can keep retrying it

What happens when SU loses its disk? It needs to recover the data.

 - the paper says the SU will clone its data from a SU from another region
   + main challenge is that updates are being sent by MBs to records that
     are being copied
   + either updates go to source of copy, or destination of copy remembers the
     update
   + ultimately they both need to have the update in the end

Performance
-----------

Evaluation mostly focuses on latency and not on throughput. Maybe this is
specific to their needs.

Not clear how they can support millions of users with MBs that can only do
hundreds of writes per second.

Why is it taking them 75ms to do a local update, where everyone is in the same
region?
 
 - computation, disk, network?
 - 75ms is enormous for a write in a DB

6.824 notes
===========

Brian F. Cooper, Raghu Ramakrishnan, Utkarsh Srivastava, Adam
Silberstein, Philip Bohannon, Hans-Arno Jacobsen, Nick Puz, Daniel
Weaver and Ramana Yerneni. PNUTS: Yahoo!'s Hosted Data Serving
Platform. Proceedings of VLDB, 2008.

Why this paper?

 - same basic goals as Facebook/memcache paper, more principled design
 - multi-region is very challenging -- 100ms network delays
 - conscious trade-off between consistency and performance

What is PNUTS' overall goal?

Diagram:
    
    [world, browsers, data centers]

 - overall story similar to that of Spanner and Facebook/memcache
 - data centers ("regions") all over the world
 - web applications, e.g. mail, shopping, social net
   + each app probably runs at all regions
 - PNUTS keeps state for apps
   + per-user: profile, shopping cart, friend list
   + per-item: book popularity, user comments
 - app might need any piece of data at any data center
 - need to handle lots of concurrent updates to different data
   + e.g. lots of users must be able to add items to shopping cart at same time
     thus 1000s of PNUTS servers
 - 1000s of servers => crashes must be frequent

Overview
--------

Diagram:
    
    3 regions, browsers, web apps, tablet ctlrs, routers, storage units, MBs]

 - each region has all data
 - each table partitioned by key over storage units
   + tablet servers + routers know the partition plan

Why replicas of all data at multiple regions?

 - multiple regions -> each user's data geographically close to user
 - multiple complete replicas -> maybe survive entire region failure
 - complete replicas -> read anything quickly
   + since some data used by many users / many regions
   + once you have multiple regions, fast reads are very important

What are the drawbacks of a copy at each region?

 - updates will be slow, need to contact every region
 - local reads will probably be stale
 - updates from multiple regions need to be sorted out
   + keep replicas identical
   + avoid order anomalies
   + don't lose updates (e.g. read-modify-write for counter)
 - disk space probably not an issue for their uses

What is the data and query model?

 - basically key/value
 - reads/writes probably by column
   + so a write might replace just one column, not whole record
 - range scan for ordered tables

How do updates work?

 - app server gets web request, needs to write data in PNUTS
 - need to update every region!
 - why not just have app logic send update to every region?
   + what if app crashes after updating only some regions?
   + what if concurrent updates to same record?

PNUTS has a "record master" for each record

 - all updates must go through that region
   + each record has a hidden column indicating region of record master
 - responsible storage unit executes updates one at a time per record
 - tells MB to broadcast update to all regions
 - per-record master probably better than Facebook/memcache master region

So the complete update story (some guesswork):

App wants to update some columns of a record, knows key

  1. app sends key and update to local SU1
  2. SU1 looks up record master for key: SI2
  3. SU1 sends update request to router at SI2
  4. router at SI2 forwards update to local SU2 for key
  6. SU2 sends update to local Message Broker (MB)
  7. MB stores on disk + backup MB, sends vers # to original app
     how does MB know the vers #? maybe SU2 told it
     or perhaps SU2 (not MB) replies to original app
  8. MB sends update to router at every region
  9. every region updates local copy

Puzzles:

 - 3.2.1 says MB is commit point
   + i.e. MB writes to log on two disks, keeps trying to deliver
     why isn't MB disk a terrible bottleneck?
 - does update go to MB then SU2? or SU2 then MB? or SU2, MB, SU2?
   + maybe MB then SU2, since MB is commit point
   + maybe SU2 then MB, since SU2 has to check it's the record's master
     and perhaps pick the new version number, tho maybe not needed
 - who replies to client w/ new version #?

All writes are multi-region and thus slow -- why does it make sense?

 - application waits for MB commit but not propagation ("asynchronous")
 - master likely to be local (they claim 80% of the time)
   + so MB commit will often be quick
   + and app/user will often see its own writes soon
 - still, eval says 300ms if master is remote!
 - down side: readers at non-master regions may see stale data

How does a read-only query execute?

 - multiple kinds of reads (section 2.2) -- why?
 - application gets to choose how consistent
 - `read-any(k)`
   + read from local SU
   + might return stale data (even if you just wrote!)
   + why: app wants speed but doesn't care about freshness
 - `read-critical(k, required_version)`
   + maybe read from local SU if it has vers >= required_version
   + otherwise read from master SU?
   + why: app wants to see its own write
 - `read-latest(k)`
   + always read from master SU (? "if local copy too stale")
   + slow if master is remote!
   + why: app needs fresh data

What if app needs to increment a counter stored in a record?

 - app reads old value, increments locally, writes new value
 - what if the local read produced stale data?
 - what if read was OK, but concurrent updates?

`test-and-set-write(version#, new value)` gives you atomic update to one record
 - master rejects the write if current version # != version#
 - so if concurrent updates, one will lose and retry 

`TestAndSet` example:

      while(1):
        (x, ver) = read-latest(k)
        if(t-a-s-w(k, ver, x+1))
          break

The Question
------------

 - how does PNUTS cope with Example 1 (page 2)
 - Initially Alice's mother is in Alice's ACL, so mother can see photos
   1. Alice removes her mother from ACL
   2. Alice posts spring-break photos
 - could her mother see update #2 but not update #1?
   + esp if mother uses different region than Alice
     or if Alice does the updates from different regions
 - ACL and photo list must be in the same record
   + since PNUTS guarantees order only for updates to same record
 - Alice sends updates to her record's master region in order
   + master region broadcasts via MB in order
   + MB tells other regions to apply updates in order
 - What if Alice's mother:
   - reads the old ACL, that includes mother
   - reads the new photo list
   - answer: just one read of Alice's record, has both ACL and photo list
     + if record doesn't have new ACL, order says it can't have new photos either
 - How could a storage system get this wrong?
   + No ordering through single master (e.g. Dynamo)

How to change record's master if no failures?

 - e.g. I move from Boston to LA
 - perhaps just update the record, via old master?
   + since ID of master region is stored in the record
 - old master announces change over MB
 - a few subsequent updates might go to the old master
   + it will reject them, app retries and finds new master?

What if we wanted to do bank transfers?

 - from one account (record) to another
 - can `t-a-s-w` be used for this?
 - multi-record updates are not atomic
   + other readers can see intermediate state
   + other writers are not locked out
 - multi-record reads are not atomic
   + might read one account before xfer, other account after xfer

Is lack of general transactions a problem for web applications?

- maybe not, if programmers know to expect it

What about tolerating failures?

App server crashes midway through a set of updates

 - not a transaction, so only some of writes will happen
 - but master SU/MB either did or didn't get each write
   + so each write happens at all regions, or none

SU down briefly, or network temporarily broken/lossy

 - (I'm guessing here, could be wrong)
 - MB keeps trying until SU acks
   + SU shouldn't ACK until safely on disk

SU loses disk contents, or doesn't automatically reboot 

 - can apps read from remote regions?
   + paper doesn't say
 - need to restore disk content from SUs at other regions
   1. subscribe to MB feed, and save them for now
   2. copy content from SU at another region
   3. replay saved MB updates
 - Puzzle: 
   + how to ensure we didn't miss any MB updates for this SU?
     - e.g. subscribe to MB at time=100, but source SU only saw through 90?
   + will replay apply updates twice? is that harmful?
   + paper mentions sending checkpoint message through MB
     - maybe fetch copy as of when the checkpoint arrived
     - and only replay after the checkpoint
     - BUT no ordering among MB streams from multiple regions

MB crashes after accepting update

 - logs to disks on two MB servers before ACKing
 - recovery looks at log, (re)sends logged msgs
 - record master SU maybe re-sends an update if MB crash before ACK
   + maybe record version #s will allow SUs to ignore duplicate

MB is a neat idea

 - atomic: updates all replicas, or none
   + rather than app server updating replicas (crash...)
 - reliable: keeps trying, to cope with temporarily SU/region failure
 - async: apps don't have to wait for write to complete, good for WAN
 - ordered: keeps replicas identical even w/ multiple writers

Record's master region loses network connection

 - can other regions designate a replacement RM?
   + no: original RM's MB may have logged updates, only some sent out
 - do other regions have to wait indefinitely? yes
   + this is one price of ordered updates / strict-ish consistency

Evaluation
----------

Evaluation focuses on latency and scaling, not throughput

5.2: time for an insert while busy

 - depends on how far away Record Master is
 - RM local: 75.6 ms
 - RM nearby: 131.5 ms
 - RM other coast: 315.5 ms

What is 5.2 measuring? from what to what?

 - maybe web server starts insert, to RM replies w/ new version?
 - not time for MB to propagate to all regions
   + since then local RM wouldn't be `< remote`

Why 75 ms?

Is it 75 ms of network speed-of-light delay?

 - no: local

Is the 75 ms mostly queuing, waiting for other client's operations?

 - no: they imply 100 clients was max that didn't cause delay to rise

End of 5.2 suggests 40 ms of 75 ms in in SU

 - how could it take 40 ms?
   + each key/value is one file?
   + creating a file takes 3 disk writes (directory, inode, content)?
 - what's the other 35 ms?
   + MB disk write?

But only 33 ms (not 75) for "ordered table" (MySQL/Innodb)

 - closer to the one or two disk write we'd expect

5.3 / Figure 3: effect of increasing request rate

 - what do we expect for graph w/ x-axis req rate, y-axis latency?
   + system has some inherent capacity, e.g. total disk seeks/second
   + for lower rates, constant latency
   + for higher rates, queue grows rapidly, avg latency blows up
 - blow-up should be near max capacity of h/w
   + e.g. # disk arms / seek time
 - we don't see that in Figure 3
   + apparently their clients were not able to generate too much load
   + end of 5.3 says clients too slow
   + at >= 75 ms/op, 300 clients -> about 4000/sec
 - text says max possible rate was about 3000/second
   + 10% writes, so 300 writes/second
   + 5 SU per region, so 60 writes/SU/second
   + about right if each write does a random disk I/O
   + but you'll need lots of SUs for millions of active users

Stepping back, what were PNUTS key design decisions?

  1. replication of all data at multiple regions
     - fast reads, slow writes
  2. relaxed consistency -- stale reads
     - b/c writes are slow
  3. only single-row transactions w/ test-and-set-write
  4. sequence all writes thru master region
     + pro: keeps replicas identical,
       enforces serial order on updates,
       easy to reason about
     + con: slow, no progress if master region disconnected

Next: Dynamo, a very different design

 - async replication, but no master
 - eventual consistency
 - always allow updates
 - tree of versions if network partitions
 - readers must reconcile versions
