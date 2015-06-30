6.824 2015 Lecture 20: Argus
============================

**Note:** These lecture notes were slightly modified from the ones posted on the
6.824 [course website](http://nil.csail.mit.edu/6.824/2015/schedule.html) from 
Spring 2015.

Atomic commit: two-phase commit
-------------------------------

 - how to use two-phase commit for distributed transactions
 - Argus

You have a bunch of computers that do different things (not replicas). Like
two computers, one stores events for people in A-L, another for people in M-Z.
If you want to create an event for Alice and Mike you need to interact with
both servers and make sure that the event is either created on both or on 
neither.

The challenges are _crashes_ and _network failures_ which inject ambiguities (
not responding cause of crash or network failure?)

In Ivy and TreadMarks if one of the machines crashed it had no way to recover.
We also saw MapReduce and Spark which had a story for crash recovery.

Code:

    schedule(u1 user, u2 user, t time):
        ok1 = reserve(u1, t)    # reserve for the 1st user
        ok2 = reserve(u2, t)    # reserve for the 2nd user

        # Tricky: if the 1st reserve succeeded and the 2nd didn't => trouble
        # We'd like to deal with this in the following way:

        if ok1 and ok2
            commit
        else
            abort

        # One bad way to make this work is to let the servers chit-chat and
        # make sure they both committed.
        # At no stage in a transaction like this can the servers finish
        #   - S1: I'll do it if you do it
        #   - S2: I'll do it if you do it
        #   - S1: I'll do it if you do it
        #   - S2: I'll do it if you do it
        # (sounds like the two generals problem?)

### Idea 1: tentative changes

    reserve(u user, t time):
        if u[t] = free          # if user's calendar is free at time t
            tent[t] = taken     # ...then tenatively schedule
    commit:
        copy tent[t] to u[t]
    abort:
        discard tent[t]

### Idea 2: single machine/entity (transaction coordinator) decides

    client           TC      A       B
        \-------------------->
        \---------------------------->
                             |       |
        <--------------------/       |
        <----------------------------/
                        ------------
        ----- GO ----> |            |
                     | |            |
        <------------/ |            |
                        ------------
Properties:

 - state: unknown, committed, aborted
 - if any thinks "committed", then none think "aborted"
 - if any think "aborted", then none think "committed"

Two-phase commit (2PC)
----------------------

Used frequently in real distributed databases.

    client          TC          A           B
                        .
                        .
                        .
        ---- GO ---->                             --\
                       prepare                      |
                    ------------>                   |
                    ------------------------>       | Phase 1
                       yes/no   |           |       |
                    <-----------/           |       |
                    <-----------------------/     --/

                       commit/abort
                    ------------>                 --\
                    ------------------------>       | Phase 2
        commit/abort                                |
      <-------------                              --/


`Prepare` asks "are you still alive and willing to commit this transaction?"

 - servers may say no
 - servers may be unreachable

### Termination protocol

 - maybe the TC has a timeout while it's waiting for the yes/no response to 
   one or more prepare messages
   + at this point, it can abort the transaction, because no one has started
     a commit (since the TC did not send it, since it was waiting on yes/no)
 - B times out while waiting for prepare message
   + `=>` B hasn't replied to prepare `=>` TC hasn't sent commit to the 
     participants `=>` TC can send abort
 - B times out waiting for commit/abort after saying _no_ to prepare
   + `=>` B can abort because it knows the TC will abort everyone 
 - B times out waiting for commit/abort after saying _yes_ to prepare
   + `=>` B said yes to TC and TC could have received `yes` from everyone else (or not)
     `=>` outcome can be either commit or abort `=>` B has to wait
   + there are some lucky cases in which `B` could decide to abort/commit if 
     `A` tells it via another channel

Does this waiting make 2PC impractical? People are split up?

What about reboots? If one of the participants said yes to a prepare, it has to
remember that across reboots or crashes, so that it can be able to finish the
transaction (commit or abort).

 - in the calendar example, it would also need to remember the tentative schedule
   in `tent[]`
 - extra note: since in the diagram the TC did not wait for ACKs on commit/abort
   the participants need to persist their locks around the transaction so that
   they don't do a subsequent transaction before this one is finished

What happens if TC crashes in the middle of sending commits?
 
 - it has to remember all committed/non-committed transactions

Resemblance to Paxos?

 - Paxos is a way to build highly available systems by replication (all servers
   have all data and are doing the same thing)
   + Paxos system can proceed even if some of the servers are down
 - 2PC you cannot make progress even if just one server is down
   + each server is doing a _different thing_ (want every server to do its own
     part in a transaction)
 - While 2PC helps a set of servers reach agreement, it it not fault tolerant
   or available (it cannot proceed when servers are down)
 - You might think you can do the calendar scheduling with Paxos by having both
   servers agree on the schedule op. However, while agreeing on the op will work
   committing the op will not: what if one server's user is busy during the
   scheduled time, it cannot commit the op. While the other one might be able
   to. Paxos doesn't help solve that conflict.

Atomic distributed transactions: write your transaction code without thinking
about what other transactions could be going on

Bank example:

    T1:
        addToBal(x, 1)
        addToBal(y, -1)

        # Need this to be a transaction to implement a transfer correctly

    T2:
        tmp1 = getBal(x)
        tmp2 = getBal(y)

        print(tmp1, tmp2)

        # We cannot have the execution of T1 interleave with the execution of
        # T2. T2 had better see both addToBal calls or no addToBal calls from T1

This is called _serializability_: The effect of running a bunch of transactions
is the same as if they were run in some sequential order (no interleaving allowed:
exec first half of T1, exec first half of T2, finish second half of T1, finish T2).

One way to implement transactions is to use locks for each data record that are
acquired before a transaction begins operating on those records and holds them
until it commits or aborts. This is called **two-phase locking**.

Deadlock can occur if T1 acquires x and then y while T2 acquires y and then x.
Database systems for instance have ways to deal with this::
 
 - timeout on acquiring locks and retry
 - only allow transactions to acquire locks in a certain order
 - perform deadlock detection if single-machine setup

Nobody ever likes to use 2PC.

 - because of the waiting/blocking issue when a server times out waiting for
   a commit/abort after having said "no" to a prepare

When participants acquire locks they are holding them across multiple RTTs 
in the network because you have to wait for the commit message.

Argus
-----

 - the cool thing is that it attempts to absorb as much of the nitty-gritty junk
   of distributed systems programming inside the language
 - the desire was to have a clean story for handling RPC failures 
 - Argus sets up a framework where RPC failures can be handled cleanly
   + does all the bookkeeping required to rollback the transactions
 - Argus has to know about the data in order to be able to rollback
   + it needs to create tentative updates and so on 

6.824 notes
===========

    6.824 2015 Lecture 20: Two-Phase Commmit

    Topics:
      distributed commit, two-phase commit
      distributed transactions
      Argus -- language for distributed programming

    Distributed commit:
      A bunch of computers are cooperating on some task, e.g. bank transfer
      Each computer has a different role, e.g. src and dst bank account
      Want to ensure atomicity: all execute, or none execute
        "distributed transaction"
      Challenges: crashes and network failures

    Example:
      calendar system, each user has a calendar
      want to schedule meetings with multiple participants
      one server holds calendars of users A-M, another server holds N-Z
      [diagram: client, two servers]
      sched(u1, u2, t):
        begin_transaction
          ok1 = reserve(u1, t)
          ok2 = reserve(u2, t)
          if ok1 and ok2:
            commit
          else
            abort
        end_transaction
      the reserve() calls are RPCs to the two calendar servers
      We want both to reserve, or both not to reserve.
      What if 1st reserve() returns true, and then:
        2nd reserve() returns false (time not available)
        2nd reserve() doesn't return (lost RPC msg, u2's server crashes)
        2nd reserve() returns but then crashes
        client fails before 2nd reserve()
      We need a "distributed commit protocol"

    Idea: tentative changes, later commit or undo (abort)
      reserve_handler(u, t):
        if u[t] is free:
          temp_u[t] = taken -- A TEMPORARY VERSION
          return true
        else:
          return false
      commit_handler():
        copy temp_u[t] to real u[t]
      abort_handler():
        discard temp_u[t]

    Idea: single entity decides whether to commit
      to prevent any chance of disagreement
      let's call it the Transaction Coordinator (TC)
      [time diagram: client, TC, A, B]
      client sends RPCs to A, B
      on end_transaction, client sends "go" to TC
      TC/A/B execute distributed commit protocol...
      TC reports "commit" or "abort" to client

    We want two properties for distributed commit protocol:
      TC, A, and B start in state "unknown"
        each can move to state "abort" or "commit"
        but then each never changes mind
      Correctness:
        if any commit, none abort
        if any abort, none commit
      Performance:
        (since doing nothing is correct...)
        if no failures, and A and B can commit, then commit.
        if failures, come to some conclusion ASAP.

    We're going to develop a protocol called "two-phase commit"
      Used by distributed databases for multi-server transactions
      And by Spanner and Argus

    Two-phase commit without failures:
      [time diagram: client, TC, A, B]
      client sends reserve() RPCs to A, B
      client sends "go" to TC
      TC sends "prepare" messages to A and B.
      A and B respond, saying whether they're willing to commit.
        Respond "yes" if haven't crashed, timed out, &c.
      If both say "yes", TC sends "commit" messages.
      If either says "no", TC sends "abort" messages.
      A/B "decide to commit" if they get a commit message.
        I.e. they actually modify the user's calendar.

    Why is this correct so far?
      Neither can commit unless they both agreed.
      Crucial that neither changes mind after responding to prepare
        Not even if failure

    What about failures?
      Network broken/lossy
      Server crashes
      Both visible as timeout when expecting a message.
        
    Where do hosts wait for messages?
      1) TC waits for yes/no.
      2) A and B wait for prepare and commit/abort.

    Termination protocol summary:
      TC t/o for yes/no -> abort
      B t/o for prepare, -> abort
      B t/o for commit/abort, B voted no -> abort
      B t/o for commit/abort, B voted yes -> block

    TC timeout while waiting for yes/no from A/B.
      TC has not sent any "commit" messages.
      So TC can safely abort, and send "abort" messages.

    A/B timeout while waiting for prepare from TC
      have not yet responded to prepare
      so can abort
      respond "no" to future prepare

    A/B timeout while waiting for commit/abort from TC.
      Let's talk about just B (A is symmetric).
      If B voted "no", it can unilaterally abort.
      So what if B voted "yes"?
      Can B unilaterally decide to abort?
        No! TC might have gotten "yes" from both,
        and sent out "commit" to A, but crashed before sending to B.
        So then A would commit and B would abort: incorrect.
      B can't unilaterally commit, either:
        A might have voted "no".

    If B voted "yes", it must "block": wait for TC decision.

    What if B crashes and restarts?
      If B sent "yes" before crash, B must remember!
        --- this is today's question
      Can't change to "no" (and thus abort) after restart
      Since TC may have seen previous yes and told A to commit
      Thus:
        B must remember on disk before saying "yes", including modified data.
        B reboots, disk says "yes" but no "commit", must ask TC.
        If TC says "commit", copy modified data to real data.

    What if TC crashes and restarts?
      If TC might have sent "commit" or "abort" before crash, TC must remember!
        And repeat that if anyone asks (i.e. if A/B/client didn't get msg).
        Thus TC must write "commit" to disk before sending commit msgs.
      Can't change mind since A/B/client have already acted.

    This protocol is called "two-phase commit".
      What properties does it have?
      * All hosts that decide reach the same decision.
      * No commit unless everyone says "yes".
      * TC failure can make servers block until repair.

    What about concurrent transactions?
      We realy want atomic distributed transactions,
        not just single atomic commit.
      x and y are bank balances
      x and y start out as $10
      T1 is doing a transfer of $1 from x to y
      T1:
        add(x, 1)  -- server A
        add(y, -1) -- server B
      T2:
        tmp1 = get(x)
        tmp2 = get(y)
        print tmp1, tmp2

    Problem:
      what if T2 runs between the two add() RPCs?
      then T2 will print 11, 10
      money will have been created!
      T2 should print 10,10 or 9,11

    The traditional approach is to provide "serializability"
      results should be as if transactions ran one at a time in some order
      either T1, then T2; or T2, then T1
      
    Why serializability?
      it allows transaction code to ignore the possibility of concurrency
      just write the transaction to take system from one legal state to another
      internally, the transaction can temporarily violate invariants
        but serializability guarantess no-one will notice

    One way to implement serializabilty is with "two-phase locking"
      this is what Argus does
      each database record has a lock
      the lock is stored at the server that stores the record
        no need for a central lock server
      each use of a record automatically acquires the record's lock
        thus add() handler implicitly acquires lock when it uses record x or y
      locks are held until *after* commit or abort 

    Why hold locks until after commit/abort?
      why not release as soon as done with the record?
      e.g. why not have T2 release x's lock after first get()?
        T1 could then execute between T2's get()s
        T2 would print 10,9
        but that is not a serializable execution: neither T1;T2 nor T2;T1
      
    2PC perspective
      Used in sharded DBs when a transaction uses data on multiple shards
      But it has a bad reputation:
        slow because of multiple phases / message exchanges
        locks are held over the prepare/commit exchanges
        TC crash can cause indefinite blocking, with locks held
      Thus usually used only in a single small domain
        E.g. not between banks, not between airlines, not over wide area

    Paxos and two-phase commit solve different problems!
      Use Paxos to high availability by replicating
        i.e. to be able to operate when some servers are crashed
        the servers must have identical state
      Use 2PC when each participant does something different
        And *all* of them must do their part
      2PC does not help availability
        since all servers must be up to get anything done
      Paxos does not ensure that all servers do something
        since only a majority have to be alive

    What if you want high availability *and* distributed commit?
      [diagram]
      Each "server" should be a Paxos-replicated service
      And the TC should be Paxos-replicated
      Run two-phase commit where each participant is a replicated service
      Then you can tolerate failures and still make progress
      This is what Spanner does (for update transactions)

    Case study: Argus

    Argus's big ideas:
      Language support for distributed programs
        Very cool: language abstracts away ugly parts of distrib systems
        Aimed at different servers doing different jobs, cooperating
      Easy fault tolerance:
        Transactional updates
        So crash results in entire transaction un-done, not partial update
      Easy persistence ("stable"):
        Ordinary variables automatically persisted to disk
        Automatic crash recovery
      Easy concurrency:
        Implicit locking of language objects
      Easy RPC model:
        Method calls transparently turned into RPCs
        RPC failure largely hidden via transactions, two-phase commit

    We've seen the fundamental problem before
      What to do if *part* of a distributed computation crashes?
      IVY/Treadmarks had no answer
      MR/Spark could re-execute *part* of computation, for big data

    Picture
      "guardian" is like an RPC server
        has state (variables) and handlers
      "handler" is an RPC handler
        reads and writes local variables
      "action" is a distributed atomic transaction
      action on A
        A RPC to B
          B RPC to C
        A RPC to D
      A finishes action
        prepare msgs to B, C, D
        commit msgs to B, C, D

    The style is to send RPC to where the data is
      Not to fetch the data
      Argus is not a storage system

    Look at bank example
      page 309 (and 306): bank transfer

    Points to notice
      stable keyword (programmer never writes to disk &c)
      atomic keyword (programmer almost never locks/unlocks)
      enter topaction (in transfer)
      coenter (in transfer)
      RPCs are hidden (e.g. f.withdraw())
      RPC error handling hidden (just aborts)

    what if deposit account doesn't exist?
      but f.withdraw(from) has already been called?
      how to un-do?
      what's the guardian state when withdraw() handler returns?
        lock, temporary version, just in memory

    what if an audit runs during a transfer?
      how does the audit not see the tentative new balances?

    if a guardian crashes and reboots, what happens to its locks?
      can it just forget about pre-crash locks?

    subactions
      each RPC is actually a sub-action
      the RPC can fail or abort w/o aborting surrounding action
      this lets actions e.g. try one server, then another
      if RPC reply lost, subaction will abort, undo
        much cleaner than e.g. Go RPC

    is Argus's implicit locking the right thing?
      very convenient!
      don't have to worry about forgetting to lock!
      (though deadlocks are easy)
      databases work (and worked) this way; it's a sucessful idea

    is transactions + RPC + 2PC a good design point?
      programmability pro:
        very easy to get nice fault tolerance semantics
      performance con:
        lots of msgs and disk writes
        2PC and 2PL hold locks for a while, block if failure

    is Argus's language integration the right thing?
      i.e. persisting and locking language objects
      it looks very convenient (and it is)
      but it turns out to be even more valuable have relational tables
        people like queries/joins/&c over tables, rows, columns
        that is, people like a storage abstraction!
      maybe there is a better language-based scheme waiting to be found

