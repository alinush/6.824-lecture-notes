6.824 2015 Lecture 12: Eventual Consistency
===========================================

**Note:** These lecture notes were slightly modified from the ones posted on the
6.824 [course website](http://nil.csail.mit.edu/6.824/2015/schedule.html) from 
Spring 2015.

Exam
----

 - Bring papers and lecture notes for exam

Eventual consistency
--------------------

 - a set of copies of the data, where applications can use any copy of the data
 - local read/write
 - even if the network breaks, I can still use the local copy
   + _disconnected operation_
 - ad-hoc synchronization
   + laptop, phone, tablet can synchronize amongst each other instead 
     of relying on Internet connection
 - can work with database servers that have different data and synchronize
   with each other
 - similar to Ficus, but Bayou has more sophisticated conflict resolution

### Conflicts

 - what to do about the inevitable conflicts that happen when you allow people
   to write to their local copies and synchronize them later

### Meeting room scheduler

Traditional approach (central server):

        PDA
    |-----------------
    |9am    824 staff     |----------------|
    |--                   |  Server        |
    |10am        -------------> | DB   |   |
    |--                         | 9am  |   |
    |11am                       | 10am |   |
    |--                                    |
    |12pm                                  |
    |--

Not a good approach because it requires everyone to have connectivity to
the server.

Would be nice if you have PDA send appointment to laptop, whoc can then send it
to the server.

        PDA
    |-----------------
    |9am    824 staff     |----------------|
    |--                   |  Server        |
    |10am                       | DB   |   |
    |--                         | 9am  |   | <-----\
    |11am                       | 10am |   |        \
    |--                                    |         |
    |12pm                                  |      laptop
    |--      \                                      /
              \----------------------------------->/

Main idea: Update functions. Instead of the application saying "write this DB
record", the application hands a function that behaves differently based on
what's in the DB.

Example:
    
    if free at 10am
        reserve @10am
    else if free at 9am
        reserve @9am
    else
        reserve

Bayou takes this function from the PDA and gives it to the laptop.

Suppose A and B want the same times:

    A wants: either staff meeting at 10  or 11
    B wants: hiring meeting at 10 or 11

If you simply apply these functions to node A's and B's databases, that's not
enough:

    X syncs with A
    10am staff meeting
    X syncs with B
    11am hiring meeting

    Y syncs with B
    10am hiring meeting
    Y syncs with A
    11am staff meeting

    now X and Y have differing views

`=>` have to execute `A`'s and `B`'s update functions in the same order

**Next idea:** number update functions, so that you can view them as being a log

 - Classic way to order things is to stamp them with numbers and sorting
 - initially let the Bayou update ID be `<time T, nodeId>`
   + possible for time `T` to be the same for two update IDs, but then
     the node IDs will differ (presumably)
 - ordering rules:
   + `a < b` if `a.T < b.T` or `a.T == b.T and a.ID < b.ID`

If we take the previous example:

    <T=10, nodeId=A>, A wants: either staff meeting at 10  or 11
    <T=20, nodeId=B>, B wants: hiring meeting at 10 or 11

    When Y syncs with B and then with A, it'll see A's update occurred earlier
    so it undoes B's update, applies A's and then B's again

We need to be able to roll back and re-execute the log.

Are the updates consistent with causality?

    PDA A adds a meeting
    A synchronizes with B
    B deletes A's meeting

If some 3rd node sees these updates, it would be necessary to have the meeting 
creation timestamp be smaller than the deletion timestamp.

### Lamport logical clock

Each node maintains `T_max`, the highest timestamp this node has ever seen
from itself or from another node.

When a node creates an event and adds it to the log, it picks timestamp `T =
max (T_max + 1, wall clock time)`

 - new timestamps are always higher than timestamps the node has ever seen

### Tentative entries, commit scheme

It's annoying that entries in the calendar are always displayed as tentative
because another (earlier) update could come in and replace it.
 
 - maybe because the new update sender was disconnected for a long time

We're looking for a way to all agree that anything above a certain point in the
log will never change (it's frozen, no one can modify stuff there)

**Bad idea:** One possibility is to have all the replicas exchange summary w/
each other about what they've seen:
 
 - X has seen all A's updates through 20, B's through 17, and C's through 72
   + these are timestamps (logical clocks)
 - we know that X will never create a timestamp less than 72
 - similarly, node Y also has a min timestamp that he will generate next
   + say 30
 - we can take the minimum over all these minimums `min(30, 72) = 30` and
   commit all operations up to that point
 - problem is it requires every node to be up and connected to all other nodes

#### Commit scheme for Bayou

They have one magic node, a primary. Every update that passes through the primary,
the primary stamps it with a _commit sequence number_ (CSN), the actual ordering number
becomes: `<csn, T, node ID>`

 - primary does not wait for earlier updates (with smaller `T`) to arrive first,
   it just timestamps things as they come
 - commit preserves causal order
 - commit does not preserve wall clock order

If you don't have a CSN: `<-, T, nodeID>`. All commited operations are considered
to occur before uncommitted ones. 

**TODO:** not clear what this example was supposed to show

    A's meeting created
    B's meeting created
    B synchronizes with C
    B synchronizes with A
    C synchronizes with primary
    primary applies CSN to A's op, but not B's
    B synchronizes with primary

### Vector timestamps

Synchronization
    
    A has 
        <-, 10, X>
        <-, 20, Y>
        <-, 30, X>
        <-, 40, X>
    B has
        <-, 10, X>
        <-, 20, Y>
        <-, 30, X>

    A syncs with B
         sends a version vector to B describe which updates it has
         from every node
            A: [X 40, Y 20]
            (remember that the timestamps are always increased by senders)
            B: [X 30, Y 20]
            If B compares A's VT with his, he notices that he needs 
            updates by X between timestamp 30 and 40

### A new node joins

Now some VTs will have an entry for some new node Z. For instance, in the previous 
example
    
    A can send [X 40, Y 20, Z 60] to B

We also need a way to remove nodes.

But B won't know if `Z` is newly added or newly deleted?

    Z joins the system
    Z talks to X
    X generates Z's unique node ID
        Z's ID = <Tz, X's node ID>, where Tz is the time Z talked to X
    X sends an update timestamped with <-, Tz, X> that says "new server z"
        Everybody will see this first before seeing Z's updates
            Z's updates have timestamps higher than Tz

 - note that IDs are unbounded in size
    
Forgetting nodes:

    Z's ID = <20, X>
    A syncs -> B
    A has log entry from Z <-, 25, <20, X>>
    B has no VT entry for Z

Now B needs to figure out from A's updates if Z was added or removed

Case 1: If B's VT entry for `X` is less than the timestamp in `Z`'s ID, then
that means that `B` hasn't even seen the creation for `Z`, let alone any updates
from `Z` => `B` should create the entry for `Z` because `Z` is new to `B`

Case 2: If B's VT entry for `X` is higher than the timestamp in `Z`'s ID, (ie.
B has seen updates from `X` after it created `Z`), then B must've seen `Z`'s 
creation `=>` B must have seen a deletion notice

**Q:** If Z's entry is missing from `B` then `Z` (probably?) says `<-, T, Z> bye, T > Tz`

---

Managing Update Conflicts in Bayou, a Weakly Connected Replicated
Storage System Terry, Theimer, Petersen, Demers, Spreitzer, Hauser,
SOSP 95

some material from Flexible Update Propagation for Weakly Consistent
Replication, SOSP 97

Big picture

  Last lecture: file sync, optimistic consistency, detect conflicts
  This lecture:
    automatic conflict resolution
    update functions
    update log
    logical clocks
    eventual consistency

Paper context:

  Early 1990s (like Ficus)
  Dawn of PDAs, laptops, tablets
    H/W clunky but clear potential
    Commercial devices did not have wireless
  No pervasive WiFi or cellular data

Let's build a meeting scheduler
 Only one meeting allowed at a time (one room).
 Each entry has a time and a description.
 We want everyone to end up seeing the same set of entries.

Traditional approach: one server
  Server processes requests one at a time
  Checks for conflicting time, says yes or no
  Updates DB
  Proceeds to next request
  Server implicitly chooses order for concurrent requests

Why aren't we satisfied with central server?
 I want my calendar on my iPhone.
   I.e. database replicated in every node.
   Modify on any node, as well as read.
 Periodic connectivity to net.
 Periodic bluetooth contact with other calendar users.

Straw man 1: merge DBs.
 Similar to iPhone calendar sync, or file sync.
 Might require lots of network b/w.
 What if there's a conflict? IE two meetings at same time.
   iPhone just schedules them both!
   But we want automatic  conflict resolution.

Idea: update functions
  Have update be a function, not a new value.
  Read current state of DB, decide best change.
  E.g. "Meet at 9 if room is free at 9, else 10, else 11."
    Rather than just "Meet at 9"
  Function must be deterministic
    Otherwise nodes will get different answers

Challenge:

  TODO: Define who A,B and X,Y are...
  A: staff meeting at 10:00 or 11:00
  B: hiring meeting at 10:00 or 11:00
  X syncs w/ A, then B
  Y syncs w/ B, then A
  Will X put A's meeting at 10:00, and Y put A's at 11:00?

Goal: eventual consistency
  OK for X and Y to disagree initially
  But after enough syncing, everyone should agree

Idea: ordered update log
  Ordered list of updates at each node.
  DB is result of applying updates in order.
  Syncing == ensure both nodes have same updates in log.

How can nodes agree on update order?
  Update ID: <time T, node ID>
  Assigned by node that creates the update.
  Ordering updates a and b:
    a < b if a.T < b.T or (a.T = b.T and a.ID < b.ID)

Example:
 <10,A>: staff meeting at 10:00 or 11:00
 <20,B>: hiring meeting at 10:00 or 11:00
 What's the correct eventual outcome?
   the result of executing update functions in timestamp order
   staff at 10:00, hiring at 11:00

What's the status before any syncs?
  I.e. content of each node's DB
  A: staff at 10:00
  B: hiring at 10:00
  This is what A/B user will see before syncing.

Now A and B sync with each other
  Both now know the full set of updates
  Can each just run the new update function against its DB?
    A: staff at 10, hiring at 11
    B: hiring at 10, staff at 11
  That's not the right answer!

Roll back and replay
  Re-run all update functions, starting from empty DB
  Since A and B have same set of updates
    they will arrive at same final DB
  We will optimize this in a bit

Displayed calendar entries are "tentative"
  B's user saw hiring at 10, then it changed to hiring at 11
  You never know if there's some <15,C> you haven't yet seen
    That will change your meeting time yet again
    And force re-execution of lots of update functions
  
Will update order be consistent with wall-clock time?
  Maybe A went first (in wall-clock time) with <10,A>
  Node clocks unlikely to be synchronized
  So B could then generates <9,B>
  B's meeting gets priority, even though A asked first
  Not "externally consistent" (Spanner gets this right...)

Will update order be consistent with causality?
  What if A adds a meeting, 
    then B sees it,
    then B deletes A's meeting.
  Perhaps
    <10,A> add
    <9,B> delete -- B's clock is slow
  Now delete will be ordered before add!
    Unlikely to work
    Differs from wall-clock time case b/c system *knew* B had seen the add

Lamport logical clocks
  Want to timestamp events s.t.
    node observes E1, then generates E2, TS(E2) > TS(E1)
  Thus other nodes will order E1 and E2 the same way.
  Each node keeps a clock T
    increments T as real time passes, one second per second
    T = max(T, T'+1) if sees T' from another node
  Note properties:
    E1 then E2 on same node => TS(E1) < TS(E2)
    BUT
    TS(E1) < TS(E2) does not imply E1 came before E2

Logical clock solves add/delete causality example
  When B sees <10,A>,
    B will set its clock to 11, so
    B will generate <11,B> for its delete

Irritating that there could always be a long-delayed update with lower TS
  That can cause the results of my update to change
  Would be nice if updates were eventually "stable"
    => no changes in update order up to that point
    => results can never again change -- you know for sure when your meeting is
    => no need to re-run update function

How about a fully decentralized "commit" scheme?
  You want to know if update <10,A> is stable
  Have sync always send in log order -- "prefix property"
  If you have seen updates w/ TS > 10 from *every* node
    Then you'll never again see one < <10,A>
    So <10,A> is stable
  Spanner does this within a Paxos replica group
  Why doesn't Bayou do something like this?

How does Bayou commit updates, so that they are stable?
 One node designated "primary replica".
 It marks each update it receives with a permanent CSN.
   Commit Sequence Number.
   That update is committed.
   So a complete time stamp is <CSN, local-TS, node-id>
 CSN notifications are exchanged between nodes.
 The CSNs define a total order for committed updates.
   All nodes will eventually agree on it.
   Uncommitted updates come after all committed updates.

Will commit order match tentative order?
  Often yes.
  Syncs send in log order (prefix property)
    Including updates learned from other nodes.
  So if A's update log says
    <-,10,X>
    <-,20,A>
  A will send both to primary, in that order
    Primary will assign CSNs in that order
    Commit order will, in this case, match tentative order

Will commit order always match tentative order?
  No: primary may see newer updates before older ones.
  A has just: <-,10,A> W1
  B has just: <-,20,B> W2
  If C sees both, C's order: W1 W2
  B syncs with primary, gets CSN=5.
  Later A syncs w/ primary, gets CSN=6.
  When C syncs w/ primary, order will change to W2 W1
    <5,20,B> W1
    <6,10,A> W2
  So: committing may change order.
  
Committing allows app to tell users which calendar entries are stable.

Nodes can discard committed updates.
  Instead, keep a copy of the DB as of the highest known CSN.
  Roll back to that DB when replaying tentative update log.
  Never need to roll back farther.
    Prefix property guarantees seen CSN=x => seen CSN<x.
    No changes to update order among committed updates.

How do I sync if I've discarded part of my log?
 Suppose I've discarded all updates with CSNs.
 I keep a copy of the stable DB reflecting just discarded entries.
 When I propagate to node X:
   If node X's highest CSN is less than mine,
     I can send him my stable DB reflecting just committed updates.
     Node X can use my DB as starting point.
     And X can discard all CSN log entries.
     Then play his tentative updates into that DB.
   If node X's highest CSN is greater than mine,
     X doesn't need my DB.

How to sync?
  A sending to B
  Need a quick way for B to tell A what to send
  Committed updates easy: B sends its CSN to A
  What about tentative updates?
  A has:
    <-,10,X>
    <-,20,Y>
    <-,30,X>
    <-,40,X>
  B has:
    <-,10,X>
    <-,20,Y>
    <-,30,X>
  At start of sync, B tells A "X 30, Y 20"
    Sync prefix property means B has all X updates before 30, all Y before 20
  A sends all X's updates after <-,30,X>, all Y's updates after <-,20,X>, &c
  This is a version vector -- it summarize log content
    It's the "F" vector in Figure 4
    A's F: [X:40,Y:20]
    B's F: [X:30,Y:20]

How could we cope with a new server Z joining the system?
  Could it just start generating writes, e.g. <-,1,Z> ?
  And other nodes just start including Z in VVs?
  If A syncs to B, A has <-,10,Z>, but B has no Z in VV
    A should pretend B's VV was [Z:0,...]

What happens when Z retires (leaves the system)?
  We want to stop including Z in VVs!
  How to get out the news that Z is gone?
    Z sends update <-,?,Z> "retiring"
  If you see a retirement update, omit Z from VV
  How to deal with a VV that's missing Z?
  If A has log entries from Z, but B's VV has no Z entry:
    Maybe Z has retired, B knows, A does not
    Maybe Z is new, A knows, B does not
  Could scan both logs, but would be expensive
    And maybe retirement update has committed and dropped from B's log!
  Need a way to disambiguate: Z missing from VV b/c new, or b/c retired?

Bayou's retirement plan
  Z's ID is really <Tz,X>
    X is server Z first contacted
    Tz is X's logical clock
    X issues <-,Tz,X>:"new server Z"
    Z gets a copy of the new server update
      logical clock orders "new server Z" before any of Z's updates
  So, A syncs to B, A has log entries from Z, B's VV has no Z entry
  Z's ID is <20,X>
  One case:
    B's VV: [X:10, ...]
    10 < 20 implies B hasn't yet seen X's "new server Z" update
  Another case:
    B's VV: [X:30, ...]
    20 < 30 implies B once knew about Z, but then saw a retirement update
  More complex case:
    B's VV doesn't even contain an entry for X
    X is itself <-,Tx,W>, maybe B has an entry for W
    So B can decide if X is new or retired (see above)
    If X is new to B, Z must also be new (== B can't have seen X's "new server Z")
    If X is retired, i.e. B saw X's retirement write,
      B must have seen "new server Z" by prefix property,
      so Z missing from B's VV => B knows Z is retired

How did all this work out?
  Replicas, write any copy, and sync are good ideas
    Now used by both user apps *and* multi-site storage systems
  Requirement for p2p interaction when not on Internet is debatable
    iPhone apps seem to work fine by contacting server via cell-phone net
  Central commit server seems reasonable
    I.e. you don't need pure peer-to-peer commit
    Protocol much simpler since central server does all resolution
  Bayou introduced some very influential design ideas
    Update functions
    Ordered update log is the real truth, not the DB
    Allowed general purpose conflict resolution
  Bayou made good use of existing ideas
    Eventual consistency
    Logical clock
