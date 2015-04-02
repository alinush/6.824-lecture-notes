6.824 2015 Lecture 14: Spark
============================

**Note:** These lecture notes were slightly modified from the ones posted on the
6.824 [course website](http://nil.csail.mit.edu/6.824/2015/schedule.html) from
Spring 2015.

Introduction
------------

 - MapReduce benefits:
   + Scales
   + Fault tolerance
   + Strategy dealing with stragglers
     * If a map task is low, MapReduce starts another task on a different
       machine
     * Tasks don't communicate, so easy to have them run twice in parallel
 - MapReduce limitations:
   + very rigid form of computation
   + one map phase, one level of communication between maps and reduce, and the
     reduce phase
   + what if you wanted to build an inverted index **and** then sort it by the
     most popular keyword `=>` you would need two MapReduce jobs
   + so, cannot properly deal with multi-stage, iterative nor interactive jobs

Users needed more complicated computations `=>` Spark

There were previous solutions that tackled different types of computations
individually. Spark's aim was to provide one solution for a general enough model
of computation.

Spark
-----

Hard to do DSM while maintaining scalability and fault tolerance properties.

**RDDs: Resilient Distributed Datasets**

 - a Scala object essentially
 - immutable
 - partitioned across machines

Example (build an RDD of all the lines in a text file that start with "ERROR"):

    lines = textFile("log.txt")
    errors = lines.Fileter(_.startsWith("ERROR"))
    errors.persist()
    errors.count()

RDDs are created by: 

 - by referring to data in external storage
 - by _transforming_ other RDDs
   + like the `Filter` call above

**Actions** kick off a computation on the RDD, like the `count()` call in the 
example.

The `persist()` call tells Spark to hold the RDD in memory, for fast access.

No work is done until the `count()` action is seen and executed (lazy evaluation)
 
 - you can save work by combining all the filters applied before the action
   + faster to read AND filter than to read the file entirely and then do another
     filter pass

Fault tolerance
---------------

Lineage graphs: dependencies between RDDs

    lines (file) 
    
        |
       \|   filter(_.startsWith("ERROR"))

    errors

Machines:

    file = b1 b2 b3 b4 b5

    p1 p2 <-\      p3 p4       p5
    -----          -----       -----
    | M1|   |      |M2 |       |M3 |
    -----   |      -----       -----
    b1 b2 --/      b3 b4       b5

If you lose an RDD's partition like p4 (because M2 failed), you can rebuild it
by tracing through the dependency graph and decide (based on what's already
computed) where to start and what to recompute.

How do you know on what machines to recompute? In this example, `b3` and `b4`
would be replicated on other machines (maybe on `M1` and `M3`), so that's where
you would restart the computation.

Comparison
----------

               |     RDDs                      |     DSM
    -----------*-------------------------------|---------------------------
    reads      | any type / granularity        |  fine-grained
    writes     | only through transformations  |  fine-grained
               |  coarse grained
    faults     | recompute                     |  checkpoint (a la Remus)
    stragglers | restart job on diff. machine  |  ? no good strategy ?

Spark computation expressivity
------------------------------
Spark is pretty general: a lot of existing parallel computation paradigms, like
MapReduce, can be implemented easily on top of it

The reason coarse-grained writes are good enough is because a lot of parallel
algorithms simply apply the same op over all data. 

Partitioning
------------

Can have a custom partitioning function that says "this RDD has 10 partitions,
1st one is all elements starting with `a`, etc.."

If you use your data set multiple times, grouping it properly so that the data
you need sits on the same machine is important.

PageRank example
----------------

Example:

        the "o"'s are webpages
        the arrows are links (sometimes directed, if not just pick a direction)

        1    2
        o<---o <-\
        |\   |   |
        | \  |   |
        |  \ |   |
        *   **   |
        o--->o --/    
        3    4

Algorithm:

 - Start every page with rank 1
 - Everyone splits their rank across their neighbours
   + website 1 will give 0.5 to node 3 and node 4 and receive 0.5 from node 2 
 - Iterate how many times? Until it converges apparently.

Data:
    
    RDD1 'links': (url, links)
     - can compute with a map operation

    RDD2 'ranks': (url, rank)
     - links.join(ranks) -> (url, (links, rank))
     -      .flatMap( 
                    (url, (links, rank))) 
                        =>
                    links.map( l -> (l.dest, rank/n))
                )
     - TODO: not sure why 'rank/n` or how this transformation works
     - store result in RDD3 'contribs'
     - update ranks with contribs
     - ranks = contribs.reduceByKey( _ + _ )

Example of bad allocation, because we'll transfer a lot of data:

        the squares are machines (partitions)

                links                       ranks
        -------------------------       ------------------------
        |(a,...)|(d,...)|(c,...)|       |(d,1)  |(e,5)  |(c,3) |
        |(b,...)|       |(e,...)|       |       |(a,1)  |(b,1) |
        -------------------------       -----------------------
            \                                     /
             \------------\  /-------------------/
                           \/  
                        -------------------------       
                        |(a,...)|(d,...)|       |       
                        |       |       |       |       
                        -------------------------       

Example with partitioning:

                links                       ranks
        -------------------------       ------------------------
        |(a,...)|(e,...)|(e,...)|       |(a,1)  |(c,3)  |(e,3) |
        |(b,...)|(d,...)|       |       |(b,1)  |(d,1)  |      |
        -------------------------       ------------------------


            contribs are easy to compute locally now

Does PageRank need communication at all then? Yes, the `contribs` RDD does a 
`reduceByKey`

TODO: Not sure what it does

Internal representation
-----------------------

RDD methods:

 - `partitions` -- returns a list of partitions
 - `preferredLocations(p)` -- returns the preferred locations of a partition
   + tells you about machines where computation would be faster
 - `dependencies`
   + how you depend on other RDDs
 - `iterator(p, parentIters)`
   + ask an RDD to compute one of its partitions
 - `partitioner`
   + allows you to specify a partitioning function


