Lab 3: Part A
=============

Details
-------
 - An application calls `Make(peers,me)` to create a Paxos peer.
   + The `peers` argument contains the ports of all the peers (including this one), 
   + The `me` argument is the index of this peer in the peers array. 
 - `Start(seq,v)` asks Paxos to start agreement on instance seq, with proposed value v; 
   + `Start()` should return immediately, without waiting for agreement to complete. 
   + The application calls `Status(seq)` to find out whether the Paxos peer thinks the instance 
     has reached agreement, 
     - and if so what the agreed value is. 
 - `Status()` should consult the local Paxos peer's state and return immediately; 
   + it should not communicate with other peers. 
   + the application may call `Status()` for old instances (but see the discussion of `Done()` below).
 - implementation should be able to **make progress on agreement for multiple instances at the same time**. 
   + if application peers call `Start()` with different sequence numbers at about the same time, 
     your implementation should run the Paxos protocol concurrently for all of them. 
   + you should not wait for agreement to complete for instance `i` before starting the protocol 
     for instance `i+1`. Each instance should have its own separate execution of the Paxos protocol.
 - long-running Paxos-based server must forget about instances that are no longer needed, 
   + free the memory storing information about those instances
   + an instance is needed if the application still wants to be able to call `Status()` for it
     - or if another Paxos peer may not yet have reached agreement on that instance
   + when a particular peer application will no longer need to call `Status()` for any instance 
     `<= x`, it should call `Done(x)`. 
     - that Paxos peer can't yet discard the instances, b/c. some other Paxos peer might not yet 
        have agreed to the instance. 
     - so each Paxos peer should tell each other peer the highest `Done()` argument supplied by 
       its local application. 
     - each Paxos peer will then have a `Done()` value from each other peer. 
       + it should find the minimum, and discard all instances with sequence numbers `<= that
         minimum`. 
       + The `Min()` method returns this minimum sequence number plus one.
     - it's OK for your Paxos to piggyback the `Done()` value in the agreement protocol packets; 
       + that is, it's OK for peer P1 to only learn P2's latest `Done()` value the next time that 
         P2 sends an agreement message to P1. 
       + If `Start()` is called with a sequence number less than `Min()`, the `Start()` call should 
         be ignored. 
       + If `Status()` is called with a sequence number less than `Min()`, `Status()`
         should return `Forgotten`.

Plan
----
Here's a reasonable plan of attack:

 1. Add elements to the Paxos struct in `paxos.go` to hold the state you'll need, according 
    to the lecture pseudo-code. 
    - You'll need to define a struct to hold information about each agreement instance.
 2. Define RPC argument/reply type(s) for Paxos protocol messages, based on the lecture pseudo-code.
    - The RPCs must include the sequence number for the agreement instance to which they refer.
    - Remember the field names in the RPC structures must start with capital letters.
 3. Write a proposer function that drives the Paxos protocol for an instance, and RPC handlers that
    implement acceptors. 
    - Start a proposer function in its own thread for each instance, as needed (e.g. in `Start()`).
 4. At this point you should be able to pass the first few tests.
 5. Now implement forgetting.

Hints
-----

**Done:** more than one Paxos instance may be executing at a given time, and they may be Start()ed and/or decided out of order (e.g. seq 10 may be decided before seq 5).
 
 - before acting on log entry #`i`, wait for log entries `< i` to be decided

**Done:** in order to pass tests assuming unreliable network, your paxos should call the local acceptor through a function call rather than RPC.

**Hint:** remember that multiple application peers may call Start() on the same instance, perhaps with different proposed values. An application may even call Start() for an instance that has already been decided (maybe because it could race when issuing a NoOp for a hole in the log).

**Hint:** think about how your paxos will forget (discard) information about old instances before you start writing code. Each Paxos peer will need to store instance information in some data structure that allows individual instance records to be deleted (so that the Go garbage collector can free / re-use the memory).

**Hint:** you do not need to write code to handle the situation where a Paxos peer needs to re-start after a crash. If one of your Paxos peers crashes, it will never be re-started.

**Hint:** have each Paxos peer start a thread per un-decided instance whose job is to eventually drive the instance to agreement, by acting as a proposer.

**Hint:** a single Paxos peer may be acting simultaneously as acceptor and proposer for the same instance. Keep these two activities as separate as possible.

**Hint:** a proposer needs a way to choose a higher proposal number than any seen so far. This is a reasonable exception to the rule that proposer and acceptor should be separate. It may also be useful for the propose RPC handler to return the highest known proposal number if it rejects an RPC, to help the caller pick a higher one next time. The px.me value will be different in each Paxos peer, so you can use px.me to help ensure that proposal numbers are unique.

**Hint:** figure out the minimum number of messages Paxos should use when reaching agreement in non-failure cases and make your implementation use that minimum.

**Hint:** the tester calls Kill() when it wants your Paxos to shut down; Kill() sets px.dead. You should check px.dead in any loops you have that might run for a while, and break out of the loop if px.dead is true. It's particularly important to do this in any long-running threads you create.

Lab 3: Part B
=============

Notes
-----

 - kvpaxos replicas should stay identical; 
   + the only exception is that some replicas may lag others if they are 
     not reachable. 
 - if replica isn't reachable for a while, but then starts being reachable `=>`
   should eventually catch up (learn about operations that it missed)
 - kvpaxos client code **should try different replicas it knows about** until one responds
 - **kvpaxos replica that is part of a majority** which can reach each other 
   _should be able to serve client requests_
 - **provide sequential consistency** to applications that use its client interface. 
   + completed application calls to the `Clerk.Get()`, `Clerk.Put()`, and `Clerk.Append()` 
     methods in `kvpaxos/client.go` must appear to have affected all replicas in the same 
     order and have **at-most-once semantics**
   + A `Clerk.Get()` should see the value written by the most recent `Clerk.Put()` or 
     `Clerk.Append()` (in that order) to the same key. 
   + One consequence of this is that
     you must ensure that each application call to `Clerk.Put()` or `Clerk.Append()` 
     must appear in that order just once (i.e., write the key/value database just once), 
     even though internally your `client.go` may have to send RPCs multiple times until 
     it finds a kvpaxos server replica that replies.

Plan
----

Here's a reasonable plan:

 1. Fill in the `Op` struct in `server.go` with the "value" information that kvpaxos will 
    use Paxos to agree on, for each client request. 
    + `Op` field names must start with capital letters. 
    + You should use `Op` structs as the agreed-on values 
      - for example, you should pass `Op` structs to `Paxos.Start()`.
      - Go's RPC can marshall/unmarshall `Op` structs
      - the call to `gob.Register()` in `StartServer()` teaches it how.
 2. Implement the `PutAppend()` handler in server.go.
    + it should enter a `Put` or `Append` `Op` in the Paxos log (i.e., use Paxos to allocate a 
      Paxos instance, whose value includes the key and value (so that other kvpaxoses know 
      about the `Put()` or `Append()`)). 
    + An `Append` Paxos log entry should contain the `Append`'s 
      arguments, but not the resulting value, since the result might be large.
 3. Implement a `Get()` handler. 
    + It should enter a `Get` `Op` in the Paxos log, and then "interpret" 
      the log before that point to make sure its key/value database reflects all recent `Put()`s.
 4. Add code to cope with duplicate client requests
    + including situations where:
      - the client sends a request to one kvpaxos replica, 
      - client times out waiting for a reply, 
      - client re-sends the request to a different replica. 
    + the client request should execute just once. 
    + make sure that your scheme for duplicate detection **frees server memory quickly** 
      - for example, by having the client tell the servers which RPCs it has heard a reply for
        + it's OK to piggyback this information on the next client request

Hints
-----

**Hint:** your server should try to assign the next available Paxos instance (sequence number) to each incoming client RPC. However, some other kvpaxos replica may also be trying to use that instance for a different client's operation. So the kvpaxos server has to be prepared to try different instances.

**Hint:** your kvpaxos servers should not directly communicate; they should only interact with each other through the Paxos log.

**Hint:** as in Lab 2, you will need to uniquely identify client operations to ensure that they execute just once. Also as in Lab 2, you can assume that each clerk has only one outstanding `Put`,`Get`, or `Append`.

**Hint:** a kvpaxos server should not complete a `Get()` RPC if it is not part of a majority (so that it does not serve stale data). This means that each `Get()` (as well as each `Put()` and `Append()`) must involve Paxos agreement.

**Hint:** don't forget to call the Paxos `Done()` method when a kvpaxos has processed an instance and will no longer need it or any previous instance.

**Hint:** your code will need to wait for Paxos instances to complete agreement. The only way to do this is to periodically call `Status()`, sleeping between calls. How long to sleep? A good plan is to check quickly at first, and then more slowly:

      to := 10 * time.Millisecond
      for {
        status, _ := kv.px.Status(seq)
        if status == paxos.Decided {
          ...
          return 
        }
        time.Sleep(to)
        if to < 10 * time.Second {
          to *= 2
        }
      }

**Hint:** if one of your kvpaxos servers falls behind (i.e. did not participate in the agreement for some instance), it will later need to find out what (if anything) was agreed to. A reasonable way to to this is to call `Start()`, which will either discover the previously agreed-to value, or cause agreement to happen. Think about what value would be reasonable to pass to `Start()` in this situation.
 
 - So we would need a `NoOp` for this, In case the fallen-behind node who wanted to discover previously agreed-to value actually succeeds in proposing one

**[DONE] Hint:** When the test fails, check for gob error (e.g. "rpc: writing response: gob: type not registered for interface ...") in the log because go doesn't consider the error fatal, although it is fatal for the lab.

Algorithm
---------

Each KVP server has a copy of the DB and of the log

**Note:** We will _not_ reimplement a log, because we should not have to! 
The log is already implicitly implemented in the `paxos` library from Part A. And a server will know how much of the log it can apply to its local DB by calling `Min()` on its Paxos peer.

**Q:** What's the high-level algorithm  
**A:** A sketch:

 - Client sends a request to one of the Paxos servers
 - Each server has a `nextSeq` number that it _thinks_ the next request should get
   + it's possible that servers are out of date on this number due to partitioning, delays, etc.
     - S1 and S2 both start with seq #0
     - S1 gets request from C1
     - S2 gets request from C2
     - S1 and S2 will both propose the same seq. number
 - Server `S` creates an `Op` `op` from the request and calls `Paxos.Start(nextSeq, op)` to get other
   peers to agree on this op
   + problem is they might not agree because they are also trying to get their own `Op` to be agreed
     upon
 - If all (majority) agree, that's fine and dandy
   + **TODO:** Note that once a majority agrees there could still be a minority
     that needs to find out. How will they do it?
     - The proposer `S` who got the majority to agree will not finish his `Start()` loop
       until everyone receives the `Decided` message, so it seems that we do not need
       to do anything?
       + But what if that proposer `S` is down and there is still a majority up that can
         inform the minority about the agreement?
         - seems like the minority would need to ask about the status
 - If they do not agree with `S`'s value (i.e. `S`'s proposal failed), then `S` needs to
   retry with a different `nextSeq` number.
   + at this point `S` can definitely increment his `nextSeq` number because he knows 
     a value was agreed on 
   + what should be `nextSeq` number that `S` picks if he fails proposing?
     - seems like it should just be the next one?

**Q:** Do we need to apply the log to the DB?  
**A:** Yes, from the memory test cases and from the Piazza answers.

**Q:** When do we apply the log to the DB?  
**A:** Seems like we can call `Paxos.Min()` and see which log entries everyone agreed on **AND everyone HAS** and apply those to our DB?

 - however we have to be careful to keep the Paxos inst./seq. number the same, even after applying those entries
   just so we don't end up handling older Paxos agreements with the same seq. number

**Q:** Duplicate detection?  
**A:** Only one outstanding client call `=>` next client call can refer to previous call's XID and tell the server to get rid of it?
