6.824 2015 Lecture 15 Spanner
=============================

**Note:** These lecture notes were slightly modified from the ones posted on the
6.824 [course website](http://nil.csail.mit.edu/6.824/2015/schedule.html) from
Spring 2015.

Intro
-----

[Spanner paper, OSDI 2012](http://research.google.com/archive/spanner.html)

 - Shattered old assumption: cannot assume that clocks are tightly synchronized
   + tightly synchronized clocks are now feasible in a global scale distributed
     system: GPS and atomic clocks as independent sources
 - _Data model:_ immutable versioned data
 - built and deployed system in multiple data centers
 - Paxos helps you determine order of events. Why do we still need time?
 - used synchronized time to allow local reads without locks
 - transactions on top of replication
   + two-phase commit across groups of replicas
 - concurrency control
   + strict two phase locking with timestamps
 - Paxos
   + long-lived leader (timed leases)
   + pipelined (multiple proposals in flight)
   + out-of-order commit, in-order apply

Spanner and 'research'
----------------------

 - team is chock-full of PhDs
 - we write research papers when we feel the urge and we have something to say
 - cutting edge development, unbelievable scale, but we are not researchers

Historical context
------------------

[Bigtable paper, OSDI 2006](http://research.google.com/archive/bigtable.html)

 - started development at end of 2003 (6 PhDs)
 - first customer launched on Bigtable mid 2005
 - distributed key-value store
   + single-row transactions
   + later added lazy replication
 - value proposition
   + scale to large numbers
   + automatic resharding
 - Bigtable was one of the progenitors of "NoSQL" or more precisely "of how do
   you store a lot of data without building a database"
 - basic tenets at the time (design assumptions for Bigtable):
   + who needs a database? key-value store suffices
   + who needs SQL? unnecessary for most applications
   + who needs transactions? two-phase commit is too expensive

Why Spanner?
------------

 - found that Bigtable is too hard to use
   + users like the power that SQL database give them
   + engineers shouldn't have to code around
     - the lack of transactions
     - the bugs that manifest due to weak semantics provided by lazy replication
   + programmer productivity matters 

Megastore, started ca. 2006, built on top of Bigtable

 - optimistic concurrency control
 - paxos-based replication
   + no long-lived leader (paxos "election" on every write)
   + every paxos message was written to bigtable
 - broader class of transactions than bigtable
 - SQL-like schema and query languages
 - had consistent replication

Dremel, data analysis at Google, started ca. 2008

 - column-oriented storage and query engine
 - http://research.google.com/pubs/pub36632.html
 - popular because it allowed SQL

Transactions
------------

[Percolator, general purpose transactions](http://research.google.com/pubs/pub36726.html)

 - snapshot isolation: a normal transaction has one commit point (logically
   when you commit, everything happened then)
   + TODO: lookup what this means, because I couldn't write down his explanation
 - built on top of Bigtable
 - users demanded transactions, but we weren't ready to build that into bigtable

Spanner
-------

 - we knew we needed
   + a database
   + SQL
   + consistent replication across data centers
   + general purpose transactions
 - the rest was "merely engineering"

TrueTime came along... (story about how they found out about a guy in NY who
was working on distributed clocks and they realized it could be useful for their
concurrency control)

Globally synchronized clocks
----------------------------

 - spanner behaves like a single-machine database
   + consistent replication: replicas all report the same state
   + external consistency: replicas all report the same order of events
 - nice semantics

Were we wrong with bigtable
---------------------------

Yes, and no:

 - yes for the long-term: didn't know in 2003 what they knew in 2009, didn't have
   the people or the technology
 - no, because lots of people use bigtable at Google

Imagine you are running a startup. What long-term issues can be postponed?

Startup dilemma: 

 - too much time spent on scalable storage => wasted effort => not done in time
   => fail 
 - too little time spent on scalable storage => when they get popular can't scale
   => fail

What do you have the skill/ability/will/vision to do?

 - we could not have built Spanner 10 years ago: or even 5 years ago
 - someone told them they should build transactions in, but they didn't do it 
   because they couldn't at the time

Interesting questions
---------------------

Why has the Bigtable paper had arguably a bigger impact on both the research 
communities and technology communities?

 - research vs. practice

Why do system-researchers insist on building scalable key-value stores (and not
databases)?


Lessons
-------

### Lesson 0

Timing is everything. Except luck trumps timing.

You can't plan timing when the world is changing: design the best you can for
the problems you have in front of you

TrueTime happened due to fortuitous confluence of events and people (i.e. luck).
Same with Bigtable. Spanner's initial design (before 2008) was nowhere near what
Google has now: they had anti-luck until the project was restarted in 2008.

### Lesson 1

Build what you need, and don't overdesign. Don't underdesign either, because
you'll pay for it.

### Lesson 2

Sometimes ignorance really is bliss. Or maybe luck.

If you have blinders on, you can't overreach. If we had known we needed a 
distributed replicated database with external consistency in 2004, we would have 
failed.

### Lesson 3

Your userbase matters.
 
 - bigtable was started when Google `< 2000` employees
   + limited # of products
   + not that many engineers
 - spanner was started when Google was `10K` employees
   + more products
   + many more engineers, many more junior engineers, many more acquired companies
 - productivity of your employees matters

### Wrap up

You can't buy luck. You can't plan for luck. But you can't ignore luck.

You can increase your chances to be lucky:

 - have strong technical skills
 - work on your design sense (find opportunities to learn!)
 - build a strong network of colleagues and friends
 - learn how to work on a team
 - learn what you are good at, and what you are _not_ good at
   + be brutally honest with yourself
   + be willing to ask for help
   + admit when you are wrong
   + people don't like working with people that constantly tell them they are wrong

What Spanner lacks?
-------------------

Maybe disconnected access: Can we build apps that use DBs and can operate offline?

[Disconnected operation in Coda file system](https://www.cs.berkeley.edu/~brewer/cs262b/Coda-TOCS.pdf) work.

6.824 notes
===========

[Spanner: Google's Globally-Distributed Database](papers/spanner.pdf), 
Corbett et al, OSDI 2012

Why this paper?

 - modern, high performance, driven by real-world needs
 - sophisticated use of paxos
 - tackles consistency + performance (will be a big theme)
 - Lab 4 a (hugely) simplified version of Spanner

What are the big ideas?

 - shard management w/ paxos replication
 - high performance despite synchronous WAN replication
 - fast reads by **asking only the nearest replica**
 - consistency despite sharding (this is the real focus)
 - **clever use of time** for consistency
 - distributed transactions

This is a dense paper! I've tried to boil down some of the ideas to simpler 
form.

Sharding
--------

Idea: sharding

 - we've seen this before in FDS
 - the real problem is managing configuration changes
 - Spanner has a more convincing design for this than FDS

Simplified sharding outline (lab 4):

 - replica groups, paxos-replicated
   + paxos log in each replica group
 - master, paxos-replicated
   + assigns shards to groups
   + numbered configurations
 - if master moves a shard, groups eventually see new config
   + `"start handoff Num=7"` op in both groups' paxos logs
   + though perhaps not at the same time
 - `dst` can't finish handoff until it has copies of shard data at majority
   + and can't wait long for possibly-dead minority
   + minority must catch up, so perhaps put shard data in paxos log (!)
 - `"end handoff Num=7"` op in both groups' logs

**Q:** What if a Put is concurrent w/ handoff?

 - client sees new config, sends Put to new group before handoff starts?
 - client has stale view and sends it to old group after handoff?
 - arrives at either during handoff?

**Q:** What if a failure during handoff?
 - e.g. old group thinks shard is handed off
   + but new group fails before it thinks so

**Q:** Can *two* groups think they are serving a shard?

**Q:** Could old group still serve shard if can't hear master?

**Idea:** wide-area synchronous replication

 - _Goal:_ survive single-site disasters
 - _Goal:_ replica near customers
 - _Goal:_ don't lose any updates

Considered impractical until a few years ago

 - paxos too expensive, so maybe primary/backup?
 - if primary waits for ACK from backup
   + 50ms network will limit throughput and cause palpable delay
   + esp if app has to do multiple reads at 50ms each
 - if primary does not wait, it will reply to client before durable
 - danger of split brain; can't make network reliable

What's changed?

 - other site may be only 5 ms away -- San Francisco / Los Angeles
 - faster/cheaper WAN
 - apps written to tolerate delays
   + may make many slow read requests
   + but issue them in parallel
   + maybe time out quickly and try elsewhere, or redundant gets
 - huge # of concurrent clients lets you get hi thruput despite high delay
   + run their requests in parallel
 - people appreciate paxos more and have streamlined variants
   + fewer msgs
     - page 9 of paxos paper: 1 round per op w/ leader + bulk preprepare
     - paper's scheme a little more involved b/c they must ensure
       there's at most one leader
   + read at any replica

Actual performance?

 - Table 3
   + pretend just measuring paxos for writes, read at any replica for reads
     latency
     - why doesn't write latency go up w/ more replicas?
     - why does std dev of latency go down w/ more replicas?
     - r/o a *lot* faster since not a paxos agreement + use closest replica
       throughput
     - why does read throughput go up w/ # replicas?
     - why doesn't write throughput go up?
     - does write thruput seem to be going down?
   + what can we conclude from Table 3?
     - is the system fast? slow?
   + how fast do your paxoses run?
     - mine takes 10 ms per agreement
     - with purely local communication and no disk
     - Spanner paxos might wait for disk write
 - Figure 5
   + `npaxos=5`, all leaders in same zone
   + why does killing a non-leader in each group have no effect?
     for killing all the leaders ("leader-hard")
     - why flat for a few seconds?
     - what causes it to start going up?
     - why does it take 5 to 10 seconds to recover?
     - why is slope *higher* until it rejoins?

Spanner reads from any paxos replica

 - read does *not* involve a paxos agreement
 - just reads the data directly from replica's k/v DB
 - maybe 100x faster -- same room rather than cross-country

**Q:** Could we *write* to just one replica?

**Q:** Is reading from any replica correct?

Example of problem:

 - photo sharing site
 - i have photos
 - i have an ACL (access control list) saying who can see my photos
 - i take my mom out of my ACL, then upload new photo
 - really it's web front ends doing these client reads/writes

Order of events:

 1. W1: I write ACL on group G1 (bare majority), then
 2. W2: I add image on G2 (bare majority), then
 3. mom reads image -- may get old data from lagging G2 replica
 4. mom reads ACL -- may get new data from G1

This system is not acting like a single server!

 - there was not really any point at which the image was
   + present but the ACL hadn't been updated

This problem is caused by a combination of

 * partitioning -- replica groups operate independently
 * cutting corners for performance -- read from any replica

How can we fix this?

 1. Make reads see latest data
    - e.g. full paxos for reads expensive!
 2. Make reads see *consistent* data
    - data as it existed at *some* previous point in time
    - i.e. before #1, between #1 and #2, or after #2
    - this turns out to be much cheaper
    - spanner does this

Here's a super-simplification of spanner's consistency story for r/o clients

 - "snapshot" or "lock-free" reads
 - assume for now that all the clocks agree
 - server (paxos leader) tags each write with the time at which it occurred
 - k/v DB stores *multiple* values for each key,
   + each with a different time
 - reading client picks a time `t`
   + for each read
     - ask relevant replica to do the read at time `t`
 - how does a replica read a key at time `t`?
   + return the stored value with highest time `<= t`
 - but wait, the replica may be behind
   + that is, there may be a write at time `< t`, but replica hasn't seen it
   + so replica must somehow be sure it has seen all writes `<= t`
   + idea: has it seen *any* operation from time `> t`?
     - if yes, and paxos group always agrees on ops in time order,
       it's enough to check/wait for an op with time `> t`
     - that is what spanner does on reads (4.1.3)
 - what time should a reading client pick?
   + using current time may force lagging replicas to wait
   + so perhaps a little in the past
   + client may miss latest updates
   + but at least it will see consistent snapshot
   + in our example, won't see new image w/o also seeing ACL update

How does that fix our ACL/image example?

  1. W1: I write ACL, G1 assigns it time=10, then
  2. W2: I add image, G2 assigns it time=15 (> 10 since clocks agree)
  3. mom picks a time, for example t=14
  4. mom reads ACL t=14 from lagging G1 replica
     - if it hasn't seen paxos agreements up through t=14, it knows to wait
       so it will return G1
  5. mom reads image from G2 at t=14
     - image may have been written on that replica
     - but it will know to *not* return it since image's time is 15
     - other choices of `t` work too.

**Q:** Is it reasonable to assume that different computers' clocks agree?
 
 - Why might they not agree?

**Q:** What may go wrong if servers' clocks don't agree?

A performance problem: reading client may pick time in the future, forcing 
reading replicas to wait to "catch up"

A correctness problem:

 - again, the ACL/image example
 - G1 and G2 disagree about what time it is

Sequence of events:

  1. W1: I write ACL on G1 -- stamped with time=15
  2. W2: I add image on G2 -- stamped with time=10

Now a client read at t=14 will see image but not ACL update

**Q:** Why doesn't spanner just ensure that the clocks are all correct?

- after all, it has all those master GPS / atomic clocks

TrueTime (section 3)
--------------------

 - there is an actual "absolute" time `t_abs`
   + but server clocks are typically off by some unknown amount
   + TrueTime can bound the error
 - so `now()` yields an interval: [earliest,latest]
   + earliest and latest are ordinary scalar times
     - perhaps microseconds since Jan 1 1970
 - `t_abs` is highly likely to be between earliest and latest

**Q:** How does TrueTime choose the interval?

**Q:** Why are GPS time receivers able to avoid this problem?

 - Do they actually avoid it?
 - What about the "atomic clocks"?

Spanner assigns each write a scalar time

 - might not be the actual absolute time
 - but is chosen to ensure consistency

The danger:

 - W1 at G1, G1's interval is [20,30]
   + is any time in that interval OK?
 - then W2 at G2, G2's interval is [11,21]
   + is any time in that interval OK?
 - if they are not careful, might get s1=25 s2=15

So what we want is:

 - if W2 starts after W1 finishes, then `s2 > s1`
 - simplified _"external consistency invariant"_ from 4.1.2
 - causes snapshot reads to see data consistent w/ true order of W1, W2

How does spanner assign times to writes?

 - (again, this is much simplified, see 4.1.2)
 - a write request arrives at paxos leader
 - `s` will be the write's time-stamp
 - leader sets `s` to `TrueTime now().latest`
   + this is "Start" in 4.1.2
 - then leader *delays* until `s < now().earliest`
   + i.e. until `s` is guaranteed to be in the past (compared to absolute time)
   + this is "commit wait" in 4.1.2
 - then leader runs paxos to cause the write to happen
 - then leader replies to client

Does this work for our example?

 - W1 at G1, TrueTime says [20,30]
   + `s1 = 30`
   + commit wait until TrueTime says [31,41]
   + reply to client
 - W2 at G2, TrueTime *must* now say `>= [21,31]`
   + (otherwise TrueTime is broken)
   + s2 = 31
   + commit wait until TrueTime says [32,43]
   + reply to client
 - it does work for this example:
   + the client observed that W1 finished before S2 started,
   + and indeed `s2 > s1`
   + even though G2's TrueTime clock was slow by the most it could be
   + so if my mom sees S2, she is guaranteed to also see W1

Why the "Start" rule?

 - i.e. why choose the time at the end of the TrueTime interval?
 - previous writers waited only until their timestamps were barely `< t_abs`
 - new writer must choose `s` greater than any completed write
 - `t_abs` might be as high as `now().latest`
 - so s = now().latest

Why the "Commit Wait" rule?

 - ensures that `s < t_abs`
 - otherwise write might complete with an s in the future
   + and would let Start rule give too low an `s` to a subsequent write

**Q:** Why commit *wait*; why not immediately write value with chosen time?

 - indirectly forces subsequent write to have high enough s
   + the system has no other way to communicate minimum acceptable next s
     for writes in different replica groups
 - waiting forces writes that some external agent is serializing
   to have monotonically increasing timestamps
 - w/o wait, our example goes back to s1=30 s2=21
 - you could imagine explicit schemes to communicate last write's TS
   to the next write

**Q:** How long is the commit wait?

This answers today's Question: a large TrueTime uncertainty requires a long 
commit wait so Spanner authors are interested in accurate low-uncertainty time

Let's step back

 - why did we get into all this timestamp stuff?
   + our replicas were 100s or 1000s of miles apart (for locality/fault tol)
   + we wanted fast reads from a local replica (no full paxos)
   + our data was partitioned over many replica groups w/ separate clocks
   + we wanted consistency for reads:
     - if W1 then W2, reads don't see W2 but not W1
- it's complex but it makes sense as a
  + high-performance evolution of Lab 3 / Lab 4

Why is this timestamp technique interesting?

 - we want to enforce order -- things that happened in some
   order in real time are ordered the same way by the
   distributed system -- "external consistency"
 - the naive approach requires a central agent, or lots of communication
 - Spanner does the synchronization implicitly via time
   + time can be a form of communication
   + e.g. we agree in advance to meet for dinner at 6:00pm

There's a lot of additional complexity in the paper

 - transactions, two phase commit, two phase locking,
   + schema change, query language, &c
 - some of this we'll see more of later
 - in particular, the problem of ordering events in a
   distributed system will come up a lot, soon

