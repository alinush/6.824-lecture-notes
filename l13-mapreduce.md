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

Output of reduce is stored in GFS `=>` reduce otuput is written across the network.
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
 - number of keys `<` # of reduce workers
 - network bandwidth (need to buy more "network" too, as we buy more machines)
   + a really important problem

The answer: certainly get some scaling, but not infinite (limited by network)

Fault tolerance
---------------

Challenge: if you run big jobs on 1000s of computers, you are sure to get some
failures. So cannot simply restart whole computation. Must just redo failed machine's
work.

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
