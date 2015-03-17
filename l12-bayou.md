6.824 2015 Lecture 12: Eventual Consistency
===========================================

**Note:** These lecture notes were slightly modified from the ones posted on the
6.824 [course website](http://nil.csail.mit.edu/6.824/2015/schedule.html) from 
Spring 2015.

Exam
----

 - Bring papers and lecture notes for exam

Bayou: Eventual consistency
----------------------------

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

### Update functions

**Main idea:** Update functions. Instead of the application saying "write this DB
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

### Numbering updates

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

6.824 notes
===========

[Managing Update Conflicts in Bayou, a Weakly Connected Replicated Storage 
System](papers/bayou-conflicts) Terry, Theimer, Petersen, Demers, Spreitzer, 
Hauser, SOSP 95

Some material from Flexible Update Propagation for Weakly Consistent
Replication, SOSP 97
