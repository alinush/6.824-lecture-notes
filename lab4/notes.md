Lab 4: Part A
=============

Details
-------

Partition/shard keys over a set of replica groups. Each replica group handles
puts and gets for a # of shards. Groups operate in parllel => higher system
throughput.

Components:
 
 - a set of replica groups
   + each replica group is responsible for a subset of the shards
 - a shardmaster
   + decides which replica group should serve each shard
   + configuration changes over time
   + clients contact shard master, find replica group
   + replica groups consult the master, to find out what shards to serve
   + single-service, replicated using Paxos

All replica group members must agree an whether Get/Put happened before/after a reconfiguration `=>` store Put/Get/Append + reconfigurations in Paxos log

Reasonable to assume each replica group is always available (because of Paxos replication) `=>` simpler than primary/backup replication when primary goes down and still thinks it's primary

Shardmaster
-----------

 - manages a _sequence of numbered configurations_
   + `config = set of {replica group}, assignment of shards to {replica group}`
 - RPC interface
   + `Join(gid, servers)`
      - takes a replica group ID and an array of servers for that group
      - adds the new replica group 
      - rebalances the shards across all replicas
      - returns a new configuration that includes the new replica group
   + `Leave(gid)`
      - takes a replica group ID
      - removes that replica group
      - rebalances the shards across all remaining replicas
   + `Move(shardno, gid)`
      - takes a shard # and a replica group ID
      - reassigns the shard from its current replica group to the specified 
        replica group
      - subsequent `Join`'s or `Leave`'s can undo the work done by `Move`
        because they rebalance
   + `Query(configno)`
      - returns the configuration with that number
      - if `configno == -1` or `configno` is bigger than the biggest known
        config number, then return the latest configuration
      - `Query(-1)` should reflect every Join, Leave or Move that completed before
        the `Query(-1)` RPC was sent
 - rebalancing should divide the shards as evenly as possible among the
   groups and move as few shards (not data?) as possible in the process
   + `=>` only move shard from one group to another "wisely"
 - **No need for duplicate detection**, in practice you would need to!
 - the first configuration has #0, contains _no groups_, all shards assigned
   to GID 0 (an invalid GID)
 - typically much more shards than groups

Hints
-----


Lab 4: Part B
=============

Notes
-----

We supply you with client.go code that sends each RPC to the replica group responsible for the RPC's key. It re-tries if the replica group says it is not responsible for the key; in that case, the client code asks the shard master for the latest configuration and tries again. You'll have to modify client.go as part of your support for dealing with duplicate client RPCs, much as in the kvpaxos lab.

**TODO:** Xid's across different replica groups? How do those work? We can execute
an op on one replica group and be told "wrong" replica, when we take that op
to another group we don't ever want to be told "duplicate op", just because
we talked to another replica.

Plan
----

Clients's transaction ID (xid) should be `<clerkID, shardNo, seqNo>`, where `seqNo`
autoincrements, so that when we transfer shards from one group to another, the xids  
of the ops for the transferred shards will not conflict with existing xids on
the other group.

When configuration doesn't change, things stay simple, even when servers go down:

 - clients find out which GID to contact
 - clients send Op to GID
 - GID agree on Op using paxos
   + if a GID server goes down, that's fine, we have paxos 

Hints
-----

**Hint:** your server will need to periodically check with the shardmaster to
see if there's a new configuration; do this in `tick()`.

**TODO:** If there was a configuration change, could we have picked it up too late?
What if we serviced requests?

**Hint:** you should have a function whose job it is to examine recent entries
in the Paxos log and apply them to the state of the shardkv server. Don't
directly update the stored key/value database in the Put/Append/Get handlers;
instead, attempt to append a Put, Append, or Get operation to the Paxos log, and
then call your log-reading function to find out what happened (e.g., perhaps a
reconfiguration was entered in the log just before the Put/Append/Get).

**TODO:** Right now I only applyLog when I receive a Get. Gotta be sure I can 
reconfigure in the middle of a `Get` request.

**Hint:** your server should respond with an `ErrWrongGroup` error to a client RPC
with a key that the server isn't responsible for (i.e. for a key whose shard is
not assigned to the server's group). Make sure your Get/Put/Append handlers make
this decision correctly in the face of a concurrent re-configuration.

 - seems like you can only check what shard you are responsible for at log apply
   time
 - `=>` ops must wait

**Hint:** process re-configurations one at a time, in order.

**Hint:** during re-configuration, replica groups will have to send each other
the keys and values for some shards.

**TODO:** What if servers go down during this? Can I still agree on ops during this? Seems like it.

 - maybe we can share the keys and values via the log?

**Hint:** When the test fails, check for gob error (e.g. "rpc: writing response:
gob: type not registered for interface ...") in the log because go doesn't
consider the error fatal, although it is fatal for the lab.

**Hint:** Be careful about implementing at-most-once semantic for RPC. When a
server sends shards to another, the server needs to send the clients state as
well. Think about how the receiver of the shards should update its own clients
state. Is it ok for the receiver to replace its clients state with the received
one?

**TODO:** What is this client state?? Is it the XIDs associated with the log ops?
I think they mean the lastXid[clerkID] map. Servers in G1 could have lastXid[c, shard] = i
and servers in G2 could have lastXid[c, shard] = j. 

**Hint:** Think about how should the shardkv client and server deal with
ErrWrongGroup. Should the client change the sequence number if it receives
ErrWrongGroup? Should the server update the client state if it returns
ErrWrongGroup when executing a Get/Put request?

**TODO:** This gets to my question from the "Notes" section...

**Hint:** After a server has moved to a new view, it can leave the shards that
it is not owning in the new view undeleted. This will simplify the server
implementation.

**Hint:** Think about when it is ok for a server to give shards to the other
server during view change.

**TODO:** Before applying the new configuration change?

Algorithm
---------
