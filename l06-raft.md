6.824 2015 Lecture 6: Raft
==========================

**Note:** These lecture notes were slightly modified from the ones posted on the 6.824 
[course website](http://nil.csail.mit.edu/6.824/2015/schedule.html) from Spring 2015.

This lecture: Raft
------------------

 + larger topic is fault tolerance via replicated state machines
 + Raft -- a much more complete design than straight Paxos

Raft overview:

      clients -> leader -> followers -> logs -> execution

### Raft vs Paxos?

 - Our use of Paxos:
   + agrees separately on each client operation
 - Raft:
   + agrees on each new leader (and on tail of log)
   + agreement not required for most client operations
   + Raft is Paxos optimized for log appends (more or less)
 - why Raft-style leader?
   + no *dueling proposers* (unless leader fails)
     - leader just tells other people what to do
   + fewer messages, less complexity (unless leader fails)
   + well-defined notion of one log being more complete than another
     - simplifies switching leaders (and maybe crash recovery)
     - very hard to find a solution for this in Paxos because logs have "holes"

### What about understandability?

 - you must decide for yourself
 - straight Paxos is simpler than Raft
 - but straight Paxos is too simple for practical replication
   + everyone extends it in their own way
   + and ends up with something more or less like Raft
 - Paxos+log+leader probably not simpler than Raft
   + though presumably depends on which Paxos variant you choose

Is more direct use of Paxos (like Lab 3) ever a win?

 - i.e. is a Raft-style leader ever a bad idea?
 - geographically spread peers
 - a single leader would be far from some clients
 - some peers would be slow to other peers (Paxos tolerates lag)

Let's start w/ Raft w/ no leader change

 - for now, reliable leader
 - followers may be slow or unreachable (but they do not lose state)
 - what do we want?
    1. tolerate a *minority of failed followers*
    2. live followers and dead followers *converge on same log*
       since replication requires same order of execution
    3. *execute only when entry cannot be lost* (committed)
       since cannot easily undo execution or reply to client
 - idea for ensuring identical log:
   + leader sends _log entry_, _index_, and info about *previous* entry
   + client can reject (e.g I don't have previous entry!)
   + leader backs up for that follower, sends earlier entries
     - leader forces followers' logs to be identical to leader's
 - idea for execution:
   + idea #1 means leader knows follower is identical up to some point
   + once a majority are identical up to a point,
     - leader sends that out as commit point,
     - everyone can execute through that point,
     - leader can reply to clients

### What to do if the leader crashes?

 - other servers time out (no AppendEntries "heart-beats" for a while)
 - if other servers are missing heartbeats they start to suspect 
   the leader is down
   + can't really know _for sure_ leader is down/up on a network
 - choose a new leader!
 - Raft divides time into terms
 - most terms have a leader

### What are the dangers in transition to a new leader?

 - two leaders
 - no leader
 - might forget an executed log entry
 - logs might end up different (diverge)

Talk about leader election first, then log consistency at term boundary

### How to ensure at most one leader in a term?

 - (look at Figure 2, RequestVote RPC, and Rules for Servers)
 - leader must get votes from a majority of servers
 - **Rule:** server can cast only one vote per term
 - thus at most one server can think it has won
 - why a majority?
   + the answer is always the same!
   + "requiring a majority means not requiring a minority essentially"
   + allows fault tolerance (failure of minority doesn't impede progress)
   + prevents split brain (at most one candidate can get a majority)
   + ensures overlap (at least one in majority has every previously committed log entry)

Could election fail to choose any leader?

 + Yes!
   - >= 3 candidates split the vote evenly
     or even # of live servers, two candidates each get half

### What happens after an election in which no-one gets majority?

 - timeout, increment term, new election
 - when a server decides it might wants to be a candidate it 
   first waits a random delay and only if it doesn't hear from anyone else
   then it becomes a candidate
 - higher term takes precedence, candidates for older terms quit
 - Note: timeout must be longer than it takes to complete election!
 - Note: this means some terms may have no leader, no log entries

### How does Raft reduce chances of election failure due to split vote?

 - each server delays a random amount of time before starting candidacy
 - why is the random delay useful?
   + [see diagram of times at which servers' delays expire]
   + one will choose lowest random delay
   + hopefully enough time to elect before next delay expires
   + this idea comes up often in distributed systems

Diagram:

                20 ms                   50 ms             80 ms
    |-------------*-----------------------*-----------------*-----------|
                  S1                     S2                S3

### How to choose the random delay range?

 - too short: 2nd candidate starts before first finishes
 - too long: system sits idle for too long after leader fails
 - a rough guide:
   + suppose it takes 10ms to complete an unopposed election
   + and there are five servers
   + we want delays to be separated by (say) 20ms
   + so random delay from 0 to 100 ms
   + plus a few multiples of leader heartbeat interval

Remember this random delay idea!

 + it's a classic scheme for decentralized soft election; e.g. ethernet

Raft's elections follow a common pattern: separation of safety from progress

 - *Hard* mechanisms ensure `< 2` leaders in one term
   + Problem: elections can fail (e.g. 3-way split)
 - Solution: always safe to start a new election in a new term
   + Poblem: repeated elections can prevent any work getting done
 - Solution: *soft* mechanisms reduce probability of wasted elections
   + heartbeat from leader (remind servers not to start election)
   + timeout period (don't start election too soon)
   + random delays (give one leader time to be elected)

**Remember:** there's a way to split the problem into "safety/correctness" concerns and "liveness/performance" concerns

### What if old leader isn't aware a new one is elected?

 - perhaps b/c old leader didn't see election messages
 - new leader means a majority of servers have incremented currentTerm
   + so old leader (w/ old term) can't get majority for AppendEntries
   + though a minority may accept old server's log entries...
   + so logs may diverge at end of old term...

Now let's switch topics to **data handling** at term boundaries

What do we want to ensure?

 - each server executes the same client cmds, in the same order
   + i.e. if any server executes, then no server executes something
     else for that log entry
 - as long as single leader, we've already seen it makes logs identical
   what about when leader changes?

What's the danger?
  
Leader of term 3 crashed while sending `AppendEntries`

    S1: 3
    S2: 3 3
    S3: 3 3
    S2 and S3 might have executed; does Raft preserve it?
  
May be a series of crashes, e.g.

    S1: 3
    S2: 3 3 (new leader) 4
    S3: 3 3                (new leader) 5

Thus different entries for the same index!

Roll-back is a big hammer -- forces leader's log on everyone

 - in above examples, whoever is elected imposes log on everyone
 - Example:
   + S3 is chosen as new leader for term 6
   + S3 wants to send out a new entry (in term 6)
     + `AppendEntries` says previous entry must have term 5
   + S2 replies false (`AppendEntries` step 2)
   + S3 decrements `nextIndex[S2]`
   + S3 sends `AppendEntries` for the op w/ term=5, saying prev has term=3
   + S2 deletes op from term 4 (`AppendEntries` step 3) and replaces with op for term 5 from S3
     (and S1 rejects b/c it doesn't have anything in that entry)
     + S2 sets op for term 6 as well

Ok, leader will force its own log on followers

 + but that's not enough!
 + can roll-back delete an executed entry?

When is a log entry executed?

 + when leader advances `commitIndex/leaderCommit`
 + when a majority match the leader up through this point

Could new leader roll back executed entries from end of previous term?

 + i.e. could an executed entry be missing from the new leader's log?
 + Raft needs to ensure new leader's log contains every potentially executed entry
 + i.e. must forbid election of server who might be missing an executed entry

What are the election rules?

 + Figure 2 says only vote if candidate's log "at least as up to date"
 + So leader will be _at least as up to date_ as a majority

What does "at least as up to date" mean?

Could it mean log is >= length? No, example:

    S1: 5, (leader) 6, (crash + leader) 7,
    S2: 5                                  (leader) 8  
    S3: 5                                           8

 - first, could this scenario happen? how?
   + S1 leader in epoch 6; crash+reboot; leader in epoch 7; crash and stay down
     - both times it crashed after only appending to its own log
   + S2 leader in epoch 8, only S2+S3 alive, then crash
 - who should be next leader?
   + S1 has longest log, but entry 8 is committed !!!
     - Raft adopts leader's log, so S1 as leader -> un-commit entry 8
     - this would be incorrect since S2 may have replied to client
   + so new leader can only be one of S2 or S3
   + i.e. the rule cannot be simply "longest log"

End of 5.4.1 explains "at least as up to date" voting rule

 - compare last entry
 - higher term wins
 - if equal terms, longer log wins

So:

 - S1 can't get any vote from S2 or S3, since `7 < 8`
 - S1 will vote for either S2 or S3, since `8 > 7`
 - S1's operations from terms 6 and 7 will be discarded!
   + ok since no majority -> not executed -> no client reply

The point:

 - "at least as up to date" rule causes new leader to have all executed
   entries in its log
 - so new leader won't roll back any executed operation
 - similar to Paxos: new round ends up using chosen value (if any) of prev round

The question: Figure 7, which of a/d/f could be elected?

 - i.e. majority of votes from "less up to date" servers?

The most subtle thing about Raft (figure 8)

Figure 8:

    S1 1, L 2,    ,      L 4,
    S2 1,   2,    ,      \A/,
    S3 1,   <-------- 2 <-| ,
    S4 1,    ,    ,         ,
    S5 1,    , L 3,         , L will erase all 2's

 - not 100% true that a log entry on a majority is committed
   + i.e. will never be forgotten
 - Figure 8:
   + S1 was leader in term 2, sends out two copies of 2
   + S5 leader in term 3
   + S1 leader in term 4, sends one more copy of 2 (b/c S3 rejected op 4)
   + what if S5 now becomes leader?
     - S5 can get a majority (w/o S1)
     - S5 will roll back 2 and replace it with 3
   + could 2 have executed?
     - it is on a majority...
     - so could S1 have mentioned it in leaderCommit after majority?
     - no! very end of Figure 2 says "log[N].term == currentTerm"
     - and S1 was in term 4 when sending 3rd copy of 2
   + what's Raft's actual commit point?
     - bottom-right of page 310
     - "committed once the leader that created the entry has replicated on majority"
     - and commit point of one entry commits all before it
       + which is how 2 *could* have committed if S1 hadn't lost leadership

Another topic: configuration change (Section 6)

 - configuration = set of servers
 - how does Raft change the set of servers?
 - e.g. every few years might want to retire some, add some
 - or move all at once to an entirely new set of server
 - or increase/decrease the number of servers

How might a *broken* configuration change work?

 - each server has the list of servers in the current config
 - change configuation by changing lists, one by one
 - example: want to replace S3 with S4
   + S1: 1,2,3  1,2,4
   + S2: 1,2,3  1,2,3
   + S3: 1,2,3  1,2,3
   + S4: 1,2,4  1,2,4
 - OOPS!
   + now *two* disjoint group/leaders can form:
     - S2 and S3 (who know nothing of new config)
     - S1 and S4
   + both can process client requests, so split brain

### Raft configuration change

 - **Idea:** "join consensus" stage that includes *both* old and new configuration
 - leader of old group logs entry that switches to joint consensus
   + during joint consensus, leader separately logs in old and new
     - i.e. *two* log and *two* agreements on each log entry
     - this will force new servers to catch up
       and force new and old logs to be the same
 - after majority of old and new have switched to joint consensus,
   + leader logs entry that switches to final configuration

Example (which won't make sense because it's not properly illustrated in the original notes):

      S1: 1,2,3  1,2,3+1,2,4
      S2: 1,2,3
      S3: 1,2,3
      S4:        1,2,3+1,2,4

 - if crash but new leader didn't see the switch to joint consensus,
   + then old group will continue, no switch, but that's OK
 - if crash and new leader did see the switch to joint consensus,
   + it will complete the configuration change

### Performance

 - no numbers on how fast it can process requests
 - what are the bottlenecks likely to be?
 - disk:
   + need to write disk for client data durability, and for protocol promises
   + write per client request? so 100 per second?
   + could probably batch and get 10,000 to 100,000
 - net: a few message exchanges per client request
   + 10s of microseconds for local LAN message exchange?
   + so 100,000 per second?

_Next week:_ use of a Raft-like protocol in a complex application
