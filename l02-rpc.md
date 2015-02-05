6.824 2015 Lecture 2: Infrastructure: RPC and threads
=====================================================

**Note:** These lecture notes were slightly modified from the ones posted on the 6.824 
[course website](http://nil.csail.mit.edu/6.824/2015/schedule.html) from Spring 2015.

Remote Procedure Call (RPC)
---------------------------

 - A key piece of distrib sys machinery; all the labs use RPC
 - _Goal:_ easy-to-program network communication
   + hides most details of client/server communication
   + client call is much like ordinary procedure call
   + server handlers are much like ordinary procedures
 - RPC is widely used!

RPC ideally makes net communication look just like an ordinary _function call_:

      Client
      ------
        z = fn(x, y)

      Server
      ------
        fn(x, y) {
          compute
          return z
        }

RPC aims for this level of transparency

### RPC message diagram

      Client                      Server
      ------                      ------
    
              "fn", x, y
      request ---------->

                              compute fn(x, y)

                z = fn(x, y)
               <------------- response

### Software structure

       Client             Server
       ------             ------

      client app         handlers
        stubs           dispatcher
       RPC lib           RPC lib
         net <-----------> net

_Stubs_ are sort of the fake client-side functions that look like the real `f(x, y)` but
they just take care of packaging the arguments, sending them over the
network and ask the server to compute `f(x, y)`. The stub can then 
receive the result over the network and return the value to the client 
code.

Examples from lab 1:

 - `DoJob`
 - `Register`
 
### A few details of RPC

 - _Marshalling:_ format data into packets
   + Tricky for arrays, pointers, objects, etc.
   + Go's RPC library is pretty powerful!
   + some things you cannot pass/marshall: e.g., channels, functions
 - _Binding:_ how does client know who to talk to?
   + Might be a name service -- e.g. DNS
 - _Threads:_
   + Client often has many threads, so `> 1` call outstanding, match up replies to calls
   + Handlers may be slow, so server often runs each in a thread

_RPC problem:_ what to do about failures?

 - e.g. lost packets, broken network, crashed servers, slow servers

What does a failure look like to the client's RPC library?

 - It never sees a response from the server
   + Maybe packet was lost
 - It does *not* know if the server saw the request!
   + Maybe server/net failed just before sending reply

### Simplest scheme: _"at least once"_ behavior

        while true
            send req
            wait up to 10 seconds for reply
            if reply arrives
                return reply
            else
                continue

 - RPC client library waits for response for a while
 - If none arrives, re-send the request
 - Do this a few times
 - Still no response -- return an error to the application

**Q:** is "at least once" easy for applications to cope with?

Simple problem w/ at least once:

 - Occurs with requests that are **not** _side-effect free_
 - Client sends _"deduct $10 from bank account"_ twice because
   it did not hear back for the first one

More subtle problem: what can go wrong with this client program?

 - `Put("k", "v")` overwrites the value at `k` with `v`
 - `Put("key", "value1")` -- an RPC to set key's value in a DB server
 - `Put("key", "value2")` -- client then does a 2nd Put to same key
 
Example:

    Client                              Server
    ------                              ------
                    
    put k, 10
                ----\
                     \
    put k, 20   --------------------->  k <- 20
                       \
                        ------------->  k <- 10

    get k       --------------------->

                    10
                <---------------------

**Note:** This situation where client sends a request, server does some work and 
replies, but the reply is lost occurs frequently and will come up a lot
in labs.

Is at-least-once ever OK?

 - Yes: if it's OK to repeat operations, e.g. read-only op
 - Yes: if application has its own plan for detecting duplicates
   + which you will need for Lab 1

### Better RPC behavior: _"at most once"_

 - _Idea:_ server RPC code detects duplicate requests
   + returns previous reply instead of re-running handler
 - Client includes _unique ID (XID)_ with each request
   + uses same XID for re-send
 - Server checks if XID has been seen before

Example:

        if seen[xid]:
          r = old[xid]
        else
          r = handler()
          old[xid] = r
          seen[xid] = true

Some at-most-once complexities

 - How to ensure XID is unique?
   + big random number?
   + combine unique client ID (ip address?) with sequence #?
 - Server must eventually discard info about old RPCs
   + When is discard safe?
   + _Idea:_
     - unique client IDs
     - per-client RPC sequence numbers
     - client includes _"seen all replies `<= X`"_ with every RPC
       much like TCP sequence #s and ACKs
     - or only allow client one outstanding RPC at a time s.t.
       arrival of `seq+1` allows server to discard all `<= seq`
     - or client agrees to keep retrying for `< 5` minutes
       server discards after 5+ minutes
 - How to handle duplicate request while original is still executing?
   + Server doesn't know reply yet; don't want to run twice
   + _Idea:_ "pending" flag per executing RPC; wait or ignore

What if an at-most-once server crashes?

 - if at-most-once duplicate info in memory, server will forget
   + and accept duplicate requests
 - maybe it should write the duplicate info to disk?
 - maybe replica server should also replicate duplicate info?

### What about _"exactly once"_?
 
 - _at-most-once_ semantics plus unbounded retries plus fault-tolerant service

### Go RPC is "at-most-once"

 - open TCP connection
 - write request to TCP connection
 - TCP may retransmit, but server's TCP will filter out duplicates
 - no retry in Go code (i.e. will NOT create 2nd TCP connection)
 - Go RPC code returns an error if it doesn't get a reply
   + perhaps after a timeout (from TCP)
   + perhaps server didn't see request
   + perhaps server processed request but server/net failed before reply came back

### Go's at-most-once RPC isn't enough for Lab 1

 - it only applies to a single RPC call
 - if worker doesn't respond, the master re-sends to it to another worker
   + but original worker may have not failed, and is working on it too
 - Go RPC can't detect this kind of duplicate
   + No problem in lab 1, which handles at application level
   + In lab 2 you will have to protect against these kinds of duplicates

Threads
-------

 - threads are a fundamental server structuring tool
 - you'll use them a lot in the labs
 - they can be tricky
 - useful with RPC 
 - called goroutines in Go

Thread = "thread of control"
 
 - threads allow one program to (logically) do many things at once
 - the threads share memory
 - each thread includes some per-thread state:
   + program counter, registers, stack

### Threading challenges:

 - sharing data between thread 
   + what if two threads modify same variable at same time?
   + what if one thread reads data another thread is changing?
   + these problems are often called _races_
   + need to protect invariants on shared data (Go: _mutex_)
 - _coordination_ between threads (Go: _channels_)
   + e.g. wait for all Map threads to finish
 - _deadlocks_ 
   + thread 1 is waiting for thread 2
   + thread 2 is waiting for thread 1
   + easy detectable (unlike races)
 - lock granularity
   + goarse-grained `->` little concurrency/parallelism
   + fine-grained `->` lots of concurrency, but race and deadlocks
 - let's look at a toy RPC package to illustrate these problems

Look at today's handout -- `l-rpc.go`
-------------------------------------
Get it [here](l-rpc.go).

 - it's a toy RPC system
 - illustrates threads, mutexes, channels
 - it's a toy
   + assumes connection already open
   + only supports an integer arg, integer reply
   + doesn't deal with errors

#### `struct ToyClient`

 - client RPC state 
 - mutex per `ToyClient`
 - connection to server (e.g. TCP socket)
 - xid -- unique ID per call, to match reply to caller
 - `pending[]` -- multiple threads may call, need to find them
   + channel on which caller is waiting

#### `Call()`

 - application calls `reply := client.Call(procNum, arg)`
 - `procNum` indicates what function to run on server
 - `WriteRequest` knows the format of an RPC msg
   + basically just the arguments turned into bits in a packet
 - **Q:** why the mutex in `Call()`? what does `mu.Lock()` do?
 - **Q:** could we move `xid := tc.xid` outside the critical section?
   + after all, we are not changing anything
   + [See diagram below]
 - **Q:** do we need to `WriteRequest` inside the critical section?
   + note: Go says you are responsible for preventing concurrent map ops
   + that's one reason the update to pending is locked

Diagram:

#### `Listener()`

 - runs as a background thread
 - what is `<-` doing?
 - not quite right that it may need to wait on chan for caller

#### Back to `Call()`...

**Q:** what if reply comes back very quickly?

 - could `Listener()` see reply before `pending[xid]` entry exists?
 - or before caller is waiting for channel?

**Q:** should we put `reply := <-done` inside the critical section?

 - why is it OK outside? after all, two threads use it.

**Q:** why mutex per `ToyClient`, rather than single mutex per whole RPC pkg?

#### Server's `Dispatcher()`

 - note that the Dispatcher echos the xid back to the client
   + so that `Listener` knows which Call to wake up
 - **Q:** why run the handler in a separate thread?
 - **Q:** is it a problem that the dispatcher can reply out of order?

#### `main()`

 - note registering handler in `handlers[]`
 - what will the program print?

When to use shared memory (and locks) vs when to use channels?

 - here is my opinion
 - use channels when you want one thread to explicitly wait for another
   + often wait for a result, or wait for the next request
   + e.g. when client `Call()` waits for `Listener()`
 - use shared memory and locks when the threads are not intentionally
   + directly interacting, but just happen to r/w the same data
   + e.g. when `Call()` uses `tc.xid`

Go's "memory model" requires explicit synchronization to communicate!

This code is not correct:

        var x int
        done := false
        go func() { x = f(...); done = true }
        while done == false { }

It's very tempting to write, but the Go spec says it's undefined
use a channel or `sync.WaitGroup` instead

Study the Go tutorials on _goroutines_ and _channels_.
