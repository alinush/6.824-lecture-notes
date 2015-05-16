2009, Quiz 1
============

Bayou
-----

### Question 4

If David syncs with the primary first, or if David's logical timestamp is higher
that MIT Daycare's (either due to the clock or node ID being higher) and they
sync and then one of them talks to the primary.

2010, Quiz 1
============

Bayou
-----

### Question 7

A: a1t0
B:      b1t1
C:           c1t2

B syncs with C, C commits with S => b1 commits first
A syncs with B => A's tentative schedule is: a1t0 b1t1 
A syncs with S => A's schedule changes to: b1t1 a1t0

2011, Quiz 1
============

Bayou
-----

### Question 4

The logical clock scheme would work better than using real-time clocks when
those real time clocks are out of sync:

N1 real time clock says 9:00am (actual time is 9:00am)
N2 real time clock says 10:00am (actual time is 9:00am)

If N1 sends an update of a file F to N2, then N2 will ignore it because its clock
is too far ahead.

### Question 5

Conflict resolution. Resolving update conflicts.

### Question 6

A: a1   
B:    b1

B commits with S => b1 gets 1
B syncs with A => a1, b1
A syncs with S => updates get reordered b1, a1

### Question 7

A: a1
B:    b1
C:       c1

pairwise sync (A-B, B-C)

A: a1, b1
B: a1, b1, c1
C: b1, c1

A creates a1
B syncs with A,
B creates b1 after a1
C syncs with B
C creates c1 after b1

C syncs first with S => b1 gets CSN 1, c1 gets CSN 2
B syncs first with S => b1 is already synced and a1 gets CSN 3 (weird)

Their answer: server i reserves a room for 10/11/12pm w/ TS i after syncing with 
server (i-1), which did the same before him.

### Question 8

The guy with the highest node ID will see all of its updates constantly being
rescheduled everytime he syncs with someone. A lot of his updates could fail as
a result?

2012, Quiz 1
============

Bayou
-----

### Question 3

If Victor sends just his update to the primary and Vera's didnt make it there yet, 
then Victor wins: his update gets the smaller CSN. If Victor sends both updates
to the primary, then the primary will given them CSNs in order, and Vera's update
will get the 1st CSN => Vera wins. I think the way Bayou works will have Victor
send both of his updated to the primary => vera wins

### Question 4

Write `x` has vv: `[s1: 1, s2: 2]`
Write `y` has vv: `[s1: 2, s2: 1]`

### Question 5

In Bayou, it would not be okay: the reason we used logical clocks was so that
all servers apply the tentative updates in the same order.

...but the primary actually orders/commits updates in the order they arrive, so
it seems that it shouldn't matter how clients apply their tentative updates. They
will end up disagreeing more often with this scheme, but ultimately, the primary
will make sure they all agree up to the last committed update.

2013, Quiz 2
============

Bayou
-----

### Question 2

A: Neha, [-, 1, A]
A: Robert [-, 2, A]
N: Charles [-, 1, N]
A <-> N

Yes. Say their node IDs are A and N, s.t. A < N, Then they will all display:

Neha, Charles, Robert

Because N's update will be after A's Neha update but before A's Robert update.
1 < 2 and A < N.

### Question 3

If no seats are reserved, then the only seat assignment that is possible is 
Neha, Charles, Robert.

If the question refers to all _committed_ seat assignments that are possible,
then the Neha and Robert need to maintain their causal ordering, while Charles
can be anywhere in between them, depending on what time N syncs with S.

### Question 4

Either one could be right. If Agent Ack (or another agent) committed on S, then
seat 1 is reserved (because seats are reserved in order). If no agent committed
on S, then Professor Strongly Consistent has a point: Agent Ack could be the
first one to commit on S and get the professor seat #1. The remaining question
is if Agent Ack can reach the primary S.

Oh fudge, Sack != Ack. Poor name choosing...

2014, Quiz 2
============

Bayou
-----

### Question 10

H2's local timestamp starts at 0 and H2 synchronized with H1, whose update had
timestamp 1 => H2's local timestamp will be updated to 1 => H2's update timestamp
will be updated to 2

### Question 11

After synchronizing with S:

H1: [1, 1, H1]
H2: [2, 2, H2]

Not sure if the central server S also updates H1/H2's logical clocks. I don't
think so.

Fudge... H3 != H1

H3 syncs with S => H3 gets [1, 1, H3]
H1 talks to H2 => H2 gets [-, 2, H2]
H2 syncs with S => H2 gets [2, 2, H2]
H1 syncs with S => H1 gets [3, 1, H1]

Still disagreeing with their answer (H2 gets CSN 3 and H1 gets CSN 2). For some
reason, they assume H1 gets there first. Oh... and it does, because H1 synced
with H2, and H2 syncs with S first, but will include H1's update as the first
one.

### Question 12

Setup:
H3 synced with S => 10am Ben committed
H2 synced with S => 11am Alice committed
H1 synced with S => 10am Bob was rejected. Maybe it goes to 12pm?

Actions:
H4 syncs with H2 => H4's clock becomes 2
H4 syncs with H3 => H4's clock stays 2. H3's clock becomes 2?\

After syncing with H2, H4 gets 10am Ben, 11am Alice
After syncing with H3, who's behind, calendar stays the same.

### Question 13

Bayou was developed so that users can operate in offline mode. Paxos wouldn't work
here at all when a majority of user's nodes are offline. If the question asked
about using Paxos to replicate the primary, then sure, yes, go ahead. But
using paxos to have the client's machines agree on their operations' order will
not work well.

