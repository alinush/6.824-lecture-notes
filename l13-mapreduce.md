6.824 2015 Lecture 13: MapReduce
================================

**Note:** These lecture notes were slightly modified from the ones posted on the
6.824 [course website](http://nil.csail.mit.edu/6.824/2015/schedule.html) from 
Spring 2015.

Intro
-----

 - 2nd trip to this paper, talk more about fault tolerance
   + See [first lecture](l01-intro.html)
 - a real triumph of simplicity for the programmer
 - clever design tricks to get good performance

Example: Building an inverted index
-----------------------------------

 - you need an inverted index for a search index
 - maps keywords to documents they are found in

Example:

    doc 31: I am Alex
    doc 32: Alex at 8 am

The output that we want, is an index: for each word in the input, we want
a list of every place that word occurred (document + offset):

    alex: 31/2, 32/0 ...
    am:   31/1, 32/3 ...

The actual map/reduce functions for building an inverted index:

    map(doc file)
        split doc into words
        for each word
            emit(word, {doc #, offset})

    reduce(word string, occurrences list<doc #, offset>)
        emit(word, sorted list of ocurrences by doc # and then by offset)

Input files
-----------

In MapReduce, the input is stored in GFS (Google's file system)

    Input, M splits, one    R reduce tasks
    map function for each 
    split

    ---------               ---------------------------------
    |       |               |   |   | * |           |   |   |
    ---------               ----------|----------------------
    |       |               |   |   | * |           |   |   |
    ---------               ----------|----------------------
    |       |               |   |   | * |           |   |   |
    ---------               ----------|----------------------
    |       |               .   .   . |  
    ---------               .   .   .  \
    |       |               .   .   .   \-----> data for a single reduce task
    ---------               .   .   .           is all the data in the column
    |       |               .   .   .
    ---------               .   .   .
    |       |               .   .   .
    ---------               .   .   .

What happens if the column of data for a reduce worker not fitting in memory?
Seems like it would go to disk.

Note that a single reduce call happens for every unique keyword. So, in our 
inverted index example, this would mean a single reduce call for the keyword
"the" which would appear probably a billion times in a large collection of 
documents. Thus, this will take a while. MapReduce cannot parallelize the work
in a reduce call (lost opportunity for certain reduce functions that are 
composable, like f(reduce(k, l1), reduce(k, l2)) = reduce(k, l1+l2) ).
 
 - I think _combiner functions_ mentioned in the paper, can alleviate this issue

Performance
-----------

 - it's all about data movement
   + pushing terrabytes of data across a cluster
   + 1000 machines
     - can maybe push data to RAM (1GB/s) at 1000 GB/s
     - can maybe push data to disk (100MB/s) at 100 GB/s
     - network can run at 1Gbit/s = 100MB/s on a machine
         + for 1000 machine, the wiring is expensive and costs you speed
         + network is usually a tree with servers at the leaves and bigger
           switches in the internal nodes
         + bottleneck is root switch, which runs at 18GB/s at Google
     - thus, network can only push data at 18GB/s `=>` _bottleneck_

Design insights
---------------

Need to cope with the network problem.

Distributed Shared Memory (DSM) is very flexible in that any machine can write
memory on any location in (distributed) memory. The problem is that you end up
w/ very bandwidth inefficient and latency sensitive systems. If you allow arbitrary
reads/writes to data you end up with a bunch of latency-sensitive small data
movements across the network.

DSM makes fault tolerance quite difficult, when a single machine dies, because
each machine can do whatever it wants (read or write any mem. loc.), so it's 
hard to checkpoint the system.

**Key ideas:** 

 - `Map()` and `Reduce()` work on local data only.
 - `Map()` and `Reduce()` only operate on big pieces of data
   + to amortize network cost of sending
 - very little interaction between parts of the system
   + maps cannot talk to each other
   + reduces cannot talk to each other
   + maps and reduces cannot talk to each other
     - other than the implicit communication of sending the mapped data to
       the reduce functions
 - give programmer abstract control over the network communication
   + some control over how keys are mapped into the reduce partitions

Input is typically stored striped (64MB chunks) in GFS, over a lot of disks and 
machines.

 - gotta be clever, because this would imply that Map tasks are limited by
   network bandwidth

MapReduce takes advantage of GFS knowledge, to actually run the map tasks locally
on the GFS machines where the file chunks are stored. `=>` increase bandwitdh
to maps from 18GB/s to 100GB/s

Intermediate map files generated by map are also stored locally. Downside is that
there's a single copy of the data on that one machine and the reduce worker has
to talk to it only `=>` limited bandwidth.

 - if the machine stops or crashes, the data is lost, have to restart map

Data in GFS is actually replicated (2 or 3 copies), and this gives MapReduce 
a choice of 2-3 servers that it can run every map task on.

 - good for load/balancing (MR master can move slow map tasks to other machines)
   + don't get this benefit for reduce tasks

Output of reduce is stored in GFS `=>` reduce output is written across the network.
`=>` total output of MapReduce system is 18GB/s, if that's your cross-section
bandwidth.

QOTD
----

How soon can reduce start after map emitted some data?

Morris: As soon as a column is filled with data `<=>` as soon as all the maps
are finished.

Apparently, you could do it as soon as a map task emits a keyword, by feeding
values as they are generated in the reduce task's iterator, but performance
can be tricky to achieve in that case.

Does MapReduce scale well?
--------------------------

One of the big benefit of a distributed system, is that you _might_ be able
to speed it up by just buying more machines. Cheaper to buy machines than to
pay programmers.

`nx` hardware => `nx` performance?, `n > 1`

As we grow # of machines (10 fold), and input size stays constant `=>` input 
size has to be decreased (10 fold). Smaller splits (10x smaller).

If we have millions of machines, the splits can be kilobytes in size `=>` network
latency will kill our performance.

You can't have more reduce workers than you have keys.

Scalability is limited by

 - map split size
 - number of keys `>=` # of reduce workers
 - network bandwidth (need to buy more "network" too, as we buy more machines)
   + a really important problem

The answer: certainly get some scaling, but not infinite (limited by network)

Fault tolerance
---------------

Challenge: if you run big jobs on 1000s of computers, you are sure to get some
failures. So cannot simply restart whole computation. Must just redo failed
machine's work.

Difficult to achieve for DSM, easier for MapReduce.

Assuming independent failures (also because maps/reduces are independent)

If worker failed:

 - can just restart
 - can save intermediate output and resume after failure

If maps fail, we have to rerun it, because it stores its output on the same machine,
which is done. Master knows what the map was working on, so it can just restart.

If a reduce worker crashes, because they store their output on GFS, on replicated
different servers. We have a good chance of not having to recompute, if the
reduce worker finished.

Paper's performance eval
------------------------

Figure 2 in paper. Why does the bandwidth take 60 seconds to achieve 30GB/s?

The MR job has 1800 mappers, and some _poor_ master that has to give work to each
one. So maybe the master takes a while to contact everyone.

Why only 30GB/s? These are map tasks so no network overhead. Maybe the CPU is the
limit? Unlikely. Seems like this is a disk bandwidth issue. 30GB/s / 1800 machines
`=>` 17MB/s per disk

Figure 3 in paper. 800 secs for sorting 1TB of data `=>` 1.25GB/s sort throughput

One thing to notice is that the terrabyte of data fits in the memory of the 
1800 machines. 

On a single machine with enough memory, Morris extrapolated that it would take
around 30,000 seconds to sort 1TB of data (takes 2500secs to sort 100GB)

Middle graph says they are only able to move data across the network at 5GB/s.
Simply moving 1TB of data will take 200 seconds. And MapReduces moves it more than
once: from maps to reduce, from reduce to GFS (multiple times for replication)

_Important insight:_ Computation involves moving data. Not just CPU cycles.

6.824 original notes
====================

        Why MapReduce?
          Second look for fault tolerance and performance
          Starting point in current enthusiasm for big cluster computing
          A triumph of simplicity for programmer
          Bulk orientation well matched to cluster with slow network
          Very influential, inspired many successors (Hadoop, Spark, &c)

        Cluster computing for Big Data
          1000 computers + disks
          a LAN
          split up data+computation among machines
          communicate as needed
          similar to DSM vision but much bigger, no desire for compatibilty

        Example: inverted index
          e.g. index terabytes of web pages for a search engine
          Input:
            A collection of documents, e.g. crawled copy of entire web
            doc 31: i am alex
            doc 32: alex at 8 am
          Output:
            alex: 31/3 32/1 ...
            am: 31/2 32/4 ...
          Map(document file i):
            split into words
            for each offset j
              emit key=word[j] value=i/j
          Reduce(word, list of d/o)
            emit word, sorted list of d/o

        Diagram:
          * input partitioned into M splits on GFS: A, B, C, ...
          * Maps read local split, produce R local intermediate files (A0, A1 .. AR)
          * Reduce # = hash(key) % R
          * Reduce task i fetches Ai, Bi, Ci -- from every Map worker
          * Sort the fetched files to bring same key together
          * Call Reduce function on each key's values
          * Write output to GFS
          * Master controls all:
            Map task list
            Reduce task list
            Location of intermediate data (which Map worker ran which Map task)

        Notice:
          Input is huge -- terabytes
          Info from all parts of input contributes to each output index entry
            So terabytes must be communicated between machines
          Output is huge -- terabytes

        The main challenge: communication bottleneck
          Three kinds of data movement needed:
            Read huge input
            Move huge intermediate data
            Store huge output
          How fast can one move data?
            RAM: 1000*1 GB/sec =    1000 GB/sec
            disk: 1000*0.1 GB/sec =  100 GB/sec
            net cross-section:        10 GB/sec
          Explain host link b/w vs net cross-section b/w

        How to cope with communication bottleneck
          Locality: split storage and computation the same way, onto same machines
            Because disk and RAM are faster than the network
          Batching: move megabytes at a time, not e.g. little key/value puts/gets
            Because network latency is a worse problem than network throughput
          Programming: let the developer indicate how data should move between machines
            Because the most powerful solutions lie with application structure
            
        The big programming idea in MapReduce is the key-driven shuffle
          Map function implicitly specifies what and where data is moved -- with keys
          Programmer can control movement, but isn't burdened with details
          Programs are pretty constrained to help with communication:
            Map can only read the local split of input data, for locality and simplicity
            Just one batch shuffle per computation
            Reduce can only look at one key, for locality and simplicity

        Where does MapReduce input come from?
          Input is striped+replicated over GFS in 64 MB chunks
          But in fact Map always reads from a local disk
            They run the Maps on the GFS server that holds the data
          Tradeoff:
            Good: Map can read at disk speed, much faster than reading over net from GFS server
            Bad: only two or three choices of where a given Map can run
                 potential problem for load balance, stragglers

        Where does MapReduce store intermediate data?
          On the local disk of the Map server (not in GFS)
          Tradeoff:
            Good: local disk write is faster than writing over network to GFS server
            Bad: only one copy, potential problem for fault-tolerance and load-balance

        Where does MapReduce store output?
          In GFS, replicated, separate file per Reduce task
          So output requires network communication -- slow
          The reason: output can then be used as input for subsequent MapReduce

        The Question: How soon after it receives the first file of
          intermediate data can a reduce worker start calling the application's
          Reduce function?

        Why does MapReduce postpone choice of which worker runs a Reduce?
          After all, might run faster if Map output directly streamed to reduce worker
          Dynamic load balance!
          If fixed in advance, one machine 2x slower -> 2x delay for whole computation
            and maybe the rest of the cluster idle/wasted half the time

        Will MR scale?
          Will buying 2x machines yield 1/2 the run-time, indefinitely?
          Map calls probably scale
            2x machines -> each Map's input 1/2 as big -> done in 1/2 the time
            but: input may not be infinitely partitionable
            but: tiny input and intermediate files have high overhead
          Reduce calls probably scale
            2x machines -> each handles 1/2 as many keys -> done in 1/2 the time
            but: can't have more workers than keys
            but: limited if some keys have more values than others
              e.g. "the" has vast number of values for inverted index
              so 2x machines -> no faster, since limited by key w/ most values
          Network may limit scaling, if large intermediate data
            Must spend money on faster core switches as well as more machines
            Not easy -- a hot R+D area now
          Stragglers are a problem, if one machine is slow, or load imbalance
            Can't solve imbalance w/ more machines
          Start-up time is about a minute!!!
            Can't reduce that no matter how many machines you buy (probably makes it worse)
          More machines -> more failures

        Now let's talk about fault tolerance
          The challenge: paper says one server failure per job!
          Too frequent for whole-job restart to be attractive

        The main idea: Map and Reduce are deterministic and functional,
            so MapReduce can deal with failures by re-executing
          Often a choice:
            Re-execute big tasks, or
            Save output, replicate, use small tasks
          Best tradeoff depends on frequency of failures and expense of communication

        What if a worker fails while running Map?
          Can we restart just that Map on another machine?
            Yes: GFS keeps copy of each input split on 3 machines
          Master knows, tells Reduce workers where to find intermediate files

        If a Map finishes, then that worker fails, do we need to re-run that Map?
          Intermediate output now inaccessible on worker's local disk.
          Thus need to re-run Map elsewhere *unless* all Reduce workers have
            already fetched that Map's output.

        What if Map had started to produce output, then crashed:
          Will some Reduces see Map's output twice?
          And thus produce e.g. word counts that are too high?

        What if a worker fails while running Reduce?
          Where can a replacement worker find Reduce input?
          If a Reduce finishes, then worker fails, do we need to re-run?
            No: Reduce output is stored+replicated in GFS.

        Load balance
          What if some Map machines are faster than others?
            Or some input splits take longer to process?
          Don't want lots of idle machines and lots of work left to do!
          Solution: many more input splits than machines
          Master hands out more Map tasks as machines finish
          Thus faster machines do bigger share of work
          But there's a constraint:
            Want to run Map task on machine that stores input data
            GFS keeps 3 replicas of each input data split
            So only three efficient choices of where to run each Map task

        Stragglers
          Often one machine is slow at finishing very last task
            h/w or s/w wedged, overloaded with some other work
          Load balance only balances newly assigned tasks
          Solution: always schedule multiple copies of very last tasks!

        How many Map/Reduce tasks vs workers should we have?
          They use M = 10x number of workers, R = 2x.
          More => finer grained load balance.
          More => less redundant work for straggler reduction.
          More => spread tasks of failed worker over more machines, re-execute faster.
          More => overlap Map and shuffle, shuffle and Reduce.
          Less => big intermediate files w/ less overhead.
          M and R also maybe constrained by how data is striped in GFS.
            e.g. 64 MByte GFS chunks means M needs to total data size / 64 MBytes

        Let's look at paper's performance evaluation

        Figure 2 / Section 5.2
          Text search for rare 3-char pattern, just Map, no shuffle or reduce
          One terabyte of input
          1800 machines
          Figure 2 x-axis is time, y-axis is input read rate
          60 seconds of start-up time are *omitted*! (copying program, opening input files)
          Why does it take so long (60 seconds) to reach the peak rate?
          Why does it go up to 30,000 MB/s? Why not 3,000 or 300,000?
            That's 17 MB/sec per server.
            What limits the peak rate?

        Figure 3(a) / Section 5.3
          sorting a terabyte
          Should we be impressed by 800 seconds?
          Top graph -- Input rate
            Why peak of 10,000 MB/s?
            Why less than Figure 2's 30,000 MB/s? (writes disk)
            Why does read phase last abt 100 seconds?
          Middle graph -- Shuffle rate
            How is shuffle able to start before Map phase finishes? (more map tasks than workers)
            Why does it peak at 5,000 MB/s? (??? net cross-sec b/w abt 18 GB/s)
            Why a gap, then starts again? (runs some Reduce tasks, then fetches more)
            Why is the 2nd bump lower than first? (maybe competing w/ overlapped output writes)
          Lower graph -- Reduce output rate
            How can reduces start before shuffle has finished? (again, shuffle gets all files for some tasks)
            Why is output rate so much lower than input rate? (net rather than disk; writes twice to GFS)
            Why the gap between apparent end of output and vertical "Done" line? (stragglers?)

        What should we buy if we wanted sort to run faster?
          Let's guess how much each resource limits performance.
          Reading input from disk: 30 GB/sec = 33 seconds (Figure 2)
          Map computation: between zero and 150 seconds (Figure 3(a) top)
          Writing intermediate to disk: ? (maybe 30 Gb/sec = 33 seconds)
          Map->Reduce across net: 5 GB/sec = 200 seconds
          Local sort: 2*100 seconds (gap in Figure 3(a) middle)
          Writing output to GFS twice: 2.5 GB/sec = 400 seconds
          Stragglers: 150 seconds? (Figure 3(a) bottom tail)
          The answer: the network accounts for 600 of 850 seconds

        Is it disappointing that sort harnesses only a small fraction of cluster CPU power?
          After all, only 200 of 800 seconds were spent sorting.
          If all they did was sort, they should sell CPUs/disks and buy a faster network.

        Modern data centers have relatively faster networks
          e.g. FDS's 5.5 terabits/sec cross-section b/w vs MR paper's 150 gigabits/sec
          while CPUs are only modestly faster than in MR paper
          so today bottleneck might have shifted away from net, towards CPU

        For what applications *doesn't* MapReduce work well?
          Small updates (re-run whole computation?)
          Small unpredictable reads (neither Map nor Reduce can choose input)
          Multiple shuffles (can use multiple MR but not very efficient)
            In general, data-flow graphs with more than two stages
          Iteration (e.g. page-rank)

        MapReduce retrospective
          Single-handedly made big cluster computation popular
            (though coincident with big datacenters, cheap machines, data-oriented companies)
          Hadoop is still very popular
          Inspired better successors (Spark, DryadLINQ, &c)
