6.824 2014 Lecture 5: Paxos
===========================

From Paxos Made Simple, by Leslie Lamport, 2001

starting a new group of lectures on stronger fault tolerance
  today:
    cleaner approach to replication: RSM via Paxos
    Lab 3
  subsequent lectures:
    how to use Paxos to build systems (Harp, EPaxos, Spanner)
  administrivia: Russ Cox, Go lecture on Thursday
    submit your questions early, so we can get them to Russ

recall: RSM
  maintain replicas by executing operations in the same order
  requires all replicas to agree on the (set and) order of operations

Lab 2 critique
  primary/backup with viewserver
  pro:
    conceptually simple
    just two msgs per op (request, reply)
    primary can do computation, send result to bkup
    only two k/v servers needed to tolerate one failure
  con:
    viewserver is single point of failure
    order can be messy, e.g. new view, data to backup, ack, &c
    tension if backup is slow / temporarily unavail
      1. primary can wait for backup -- slow
      2. viewserver can declare backup dead -- expensive, hurts fault tolerance

we would like a general-purpose ordering scheme with:
  no single point of failure
  graceful handling of slow / intermittent replicas

Paxos will be a key building block for this
  some number of nodes participate in an instance of Paxos
  each node knows the address of every other node for that instance
  each instance of Paxos can reach consensus on at most one value
    typically, a system uses many instances of Paxos
    each instance usually decides one operation
  assumptions: asynchronous, non-Byzantine

what does Paxos provide?
  "black-box" interface to a Paxos instance, on each node:
    propose a value (e.g., operation)
    check what value has been decided, if any
    [ lab 3a: src/paxos/paxos.go: Start, Status ]
  correctness:
    if agreement reached, all agreeing nodes see same value
  fault-tolerance:
    can tolerate non-reachability of a minority of nodes
    (correctness implies they won't agree at all)
  liveness:
    a majority must be alive and able to communicate reliably
    (minorities are not live)

how to build a system using Paxos?
  1. primary/backup like lab2, but use Paxos to replicate the viewserver
     [ next Tuesday's lecture will be about such a system ]
  2. lab3: no viewserver, all replicas use Paxos instead of primary/backup

  replicating either the viewserver or k/v server with Paxos is similar
  will look at a sketch of how to do a Paxos-based k/v server

the basic idea:
  [diagram: clients, replicas, log in each replica, k/v layer, paxos layer]
  no viewserver
  three replicas
  clients can send RPCs to any replica (not just primary)
  server appends each client op to a replicated *log* of operations
    Put, Get (and more later)
  numbered log entries -- instances -- seq
  Paxos agreement on content of each log entry

example:
  client sends Put(a,b) to S1
  S1 picks a log entry 3
  S1 uses Paxos to get all servers to agree that entry 3 holds Put(a,b)
  
example:
  client sends Get(a) to S2
  S2 picks log entry 4
  S2 uses Paxos to get all servers to agree that entry 4 holds Get(a)
  S2 scans log up to entry 4 to find latest Put(a,...)
  S2 replies with that value
  (S2 can cache content of DB up through last log scan)
  
why a log?
  why not require all replicas to agree on each op in lock-step?
  allows one replica to fall behind, then catch up
    e.g. if it is slow
    other replicas do not have to wait
  allows one replica to crash and catch up
    if it keeps state on disk
    can replay missed operations
  allows pipelining/overlap of agreement
    agreement turns out to require multiple message rounds

what about agreement -- we need all replicas to have same op in each log slot
  provided by Paxos, as we will see next

agreement is hard (1):
  may be multiple proposals for the op in a particular log slot
  Sx may initially hear of one, Sy may hear of another
  clearly one must later change its mind
  thus: multiple rounds, tentative initially
  how do we know when agreement is permanent -- no longer tentative?

agreement is hard (2):
  if S1 and S2 agree, and S3 and S4 don't respond, are we done?
  agreement has to be able to complete even w/ failed servers
  we can't distinguish failed server from network partition
  so maybe S3/S4 are partitioned have "agreed" on a different operation!

two main ideas in Paxos:
  1. many rounds may be required but they will converge on one value
  2. a majority is required for agreement -- prevent "split brain"
     a key point: any two majorities overlap
     so any later majority will share at least one server w/ any earlier majority
     so any later majority can find out what earlier majority decided

Lab 3B k/v server creates a separate Paxos instance for each client Put, Get
  rest of lecture focuses on agreement for a specific instance

Paxos sketch
  each node consists of three logical entities:
    proposer
    acceptor
    learner
  each proposer wants to get agreement on its value
    could try to use a "designated leader" to avoid dueling proposers
    OK to have multiple proposers, so leader election can be approximate
  proposer contacts acceptors, tries to assemble a majority
    if a majority respond, we're done
  in our k/v server example, roughly:
    proposer gets RPC from client, proposes operation
    acceptors are internal to Paxos, help decide consensus
    learner figures out what operation was decided to run, responds to client

broken strawman: can we do Paxos in a single round?
  acceptor "accepts" the first value that it hears from proposer
  when is consensus reached?
    can we take the value with the most votes?
    no, need a majority of accepts for the same value: floor(n/2)+1
    otherwise, consensus on 2 different values (lossy/partitioned network)
  problem:
    suppose we have 3 servers: S1, S2, S3
    what if each server proposes + accepts its own value?
      no majority, stuck
      but maybe we can detect this situation and recover?
    worse: S3 crashes -> we may have reached majority, but will never know
  need a way for acceptors to change their mind, if no consensus reached yet

basic Paxos exchange:
 proposer        acceptors
     prepare(n) ->
  <- prepare_ok(n, n_a, v_a)
     accept(n, v') ->
  <- accept_ok(n)
     decided(v') ->

why n?
  to distinguish among multiple rounds, e.g. proposer crashes, simul props
  want later rounds to supersede earlier ones
  numbers allow us to compare early/late
  n values must be unique and roughly follow time
  n = <time, server ID>
    e.g., ID can be server's IP address
  "round" is the same as "proposal" but completely different from "instance"
    round/proposal numbers are WITHIN a particular instance

definition: server S accepts n/v
  it responded accept_ok to accept(n, v)

definition: n/v is chosen
  a majority of servers accepted n/v

the crucial property:
  if a value was chosen, any subsequent choice must be the same value
    i.e. protocol must not change its mind
    maybe a different proposer &c, but same value!
    this allows us to freely start new rounds after crashes &c
  tricky b/c "chosen" is system-wide property
    e.g. majority accepts, then proposer crashes
    no node can tell locally that agreement was reached

so:
  proposer doesn't send out value with prepare
  acceptors send back any value they have already accepted
  if there is one, proposer proposes that value
    to avoid changing an existing choice
  if no value already accepted,
    proposer can propose any value (e.g. a client request)
  proposer must get prepare_ok from majority
    to guarantee intersection with any previous majority,
    to guarantee proposer hears of any previously chosen value

now the protocol -- see the handout

proposer(v):
  choose n, unique and higher than any n seen so far
  send prepare(n) to all servers including self
  if prepare_ok(n, n_a, v_a) from majority:
    v' = v_a with highest n_a; choose own v otherwise
    send accept(n, v') to all
    if accept_ok(n) from majority:
      send decided(v') to all

acceptor state:
  must persist across reboots
  n_p (highest prepare seen)
  n_a, v_a (highest accept seen)

acceptor's prepare(n) handler:
  if n > n_p
    n_p = n
    reply prepare_ok(n, n_a, v_a)

acceptor's accept(n, v) handler:
  if n >= n_p
    n_p = n
    n_a = n
    v_a = v
    reply accept_ok(n)

example 1 (normal operation):
  S1, S2, S3
  but S3 is dead or slow
  S1 starts proposal, n=1 v=A
S1: p1    a1vA    dA
S2: p1    a1vA    dA
S3: dead...
"p1" means Sx receives prepare(n=1) 
"a1vA" means Sx receives accept(n=1, v=A)
"dA" means Sx receives decided(v=A)
these diagrams are not specific about who the proposer is
  it doesn't really matter
  the proposers are logically separate from the acceptors
  we only care about what acceptors saw and replied

Note Paxos only requires a majority of the servers
  so we can continue even though S3 was down
  proposer must not wait forever for any acceptor's response

What would happen if network partition?
  I.e. S3 was alive and had a proposed value B
  S3's prepare would not assemble a majority

the homework question:
  How does Paxos ensure that the following sequence of events can't
  happen? What actually happens, and which value is ultimately chosen?
  proposer 1 crashes after sending two accepts
  proposer 2 has a different value in mind
  A: p1 a1foo
  B: p1       p2 a2bar
  C: p1 a1foo p2 a2bar
  C's prepare_ok to B really included "foo"
    thus a2foo, and so no problem
  the point:
    if the system has already reached agreement, majority will know value
    any new majority of prepares will intersect that majority
    so subsequent proposer will learn of already-agreed-on value
    and send it in accept msgs

example 2 (concurrent proposers):
A1 starts proposing n=10
A1 sends out just one accept v=10
A3 starts proposing n=11
  but A1 does not receive its proposal
  A3 only has to wait for a majority of proposal responses
A1: p10 a10v10 
A2: p10        p11
A3: p10        p11  a11v11
A1 and A3 have accepted different values!
what will happen?
  what will A2 do if it gets a10v10 accept msg from A1?
  what will A1 do if it gets a11v11 accept msg from A3?
what if A3 were to crash at this point (and not restart)?

how about this:
A1: p10  a10v10               p12
A2: p10          p11  a11v11  
A3: p10          p11          p12   a12v10
has the system agreed to a value at this point?

what's the commit point?
  i.e. exactly when has agreement been reached?
  i.e. at what point would changing the value be a disaster?
  after a majority has the same v_a? no -- why not?  above counterexample
  after a majority has the same v_a/n_a? yes -- why sufficient?  sketch:
    suppose majority has same v_a/n_a
    acceptors will reject accept() with lower n
    for any higher n: prepare's must have seen our majority v_a/n_a (overlap)
    what if overlap servers saw prepare(n) before accept(v_a, n_a)?
      would reject v_a/n_a
      thus wouldn't have a majority yet
      proposer might be free to choose v != v_a

why does the proposer need to pick v_a with highest n_a?
A1: p10  a10vA               p12
A2: p10          p11  a11vB  
A3: p10          p11  a11vB  p12   a12v??
n=11 already agreed on vB
n=12 sees both vA and vB, but must choose vB
why: two cases:
  1. there was a majority before n=11
     n=11's prepares would have seen value and re-used it
     so it's safe for n=12 to re-use n=11's value
  2. there was not a majority before n=11
     n=11 might have obtained a majority
     so it's required for n=12 to re-use n=11's value

why does prepare handler check that n > n_p?
  it's taking max(concurrent n's), for accept handler
  responding to all prepare() with prepare_ok() would be also fine,
    but proposers with n < n_p would be ignored by accept() anyway

why does accept handler check n >= n_p?
  required to ensure agreement
  there's a unique highest n active
  everyone favors the highest n
  w/o n >= n_p check, you could get this bad scenario:
  A1: p1 p2 a1vA
  A2: p1 p2 a1vA a2vB
  A3: p1 p2      a2vB

why does accept handler update n_p = n?
  required to prevent earlier n's from being accepted
  node can get accept(n,v) even though it never saw prepare(n)
  without n_p = n, can get this bad scenario:
  A1: p1    a2vB a1vA p3 a3vA
  A2: p1 p2           p3 a3vA
  A3:    p2 a2vB

what if new proposer chooses n < old proposer?
  i.e. if clocks are not synced
  cannot make progress, though no correctness problem

what if an acceptor crashes after receiving accept?
A1: p1  a1v1
A2: p1  a1v1 reboot  p2  a2v?
A3: p1               p2  a2v?
A2 must remember v_a/n_a across reboot! on disk
  might be only intersection with new proposer's majority
  and thus only evidence that already agreed on v1

what if an acceptor reboots after sending prepare_ok?
  does it have to remember n_p on disk?
  if n_p not remembered, this could happen:
  S1: p10            a10v10
  S2: p10 p11 reboot a10v10 a11v11
  S3:     p11               a11v11
  11's proposer did not see value 10, so 11 proposed its own value
  but just before that, 10 had been chosen!
  b/c S2 did not remember to ignore a10v10

can Paxos get stuck?
  yes, if there is not a majority that can communicate
  how about if a majority is available?
    possible to livelock: dueling proposers, keep prepare'ing higher n's
      one reason to try electing a leader: reduce chance of dueling proposers
    with single proposer and reachable majority, should reach consensus
