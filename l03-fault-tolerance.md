6.824 2015 Lecture 3: Primary/Backup Replication
================================================

**Note:** These lecture notes were slightly modified from the ones posted on the 6.824 
[course website](http://nil.csail.mit.edu/6.824/2015/schedule.html) from Spring 2015.


Today
-----
 - Replication
 - [Remus](papers/remus.pdf) case study
 - Lab 2 introduction

Fault tolerance
---------------
 - We'd like a service that continues despite failures!
 - **Definitions:**
   + _Available_ -- still usable despite [some class of] failures
   + _Correct_ -- act just like a single server to clients
 - Very hard!
 - Very useful!

### Need a failure model: what will we try to cope with?
 - Independent fail-stop computer failure
   + Remus further assumes only one failure at a time
 - Site-wide power failure (and eventual reboot)
 - (Network partition)
 - No bugs, no malice

### Core idea: replication
 - *Two* servers (or more)
 - Each replica keeps state needed for the service
 - If one replica fails, others can continue

### Example: fault-tolerant MapReduce master
 - Lab 1 workers are already fault-tolerant, but not master
 - `[Diagram: M1, M2, workers]`
 - State:
   + worker list
   + which jobs done
   + which workers idle
   + TCP connection state
   + program counter

### Big questions
 - What state to replicate?
 - How does replica get state?
 - When to cut over to backup?
 - Are anomalies visible at cut-over?
 - How to repair / re-integrate?

### Two main approaches:
 1. **State transfer**
    + "Primary" replica executes the service
    + Primary sends [new] state to backups
 2. **Replicated state machine**
    + All replicas execute all operations
    + If same start state &
      same operations &
      same order &
      deterministic &
      _then_ `=>` same end state

### _State transfer_ is simpler
 - But state may be large, slow to transfer
 - _Remus_ uses state transfer

### _Replicated state machine_ can be more efficient
 - If operations are small compared to data
 - But complex, e.g. order on multi-core, determinism
 - Labs use replicated state machines

Remus: High Availability via Asynchronous Virtual Machine Replication, NSDI 2008
--------------------------------------------------------------------------------

### Very ambitious system
 - Whole-system replication
 - Completely _transparent_ to applications and clients
 - High availability for any existing software
 - Would be magic if it worked well!
 - _Failure model:_
    1. Independent hardware faults
    2. Site-wide power failure

### Plan 1 (slow, broken):
 - `[Diagram: app, O/S, Remus underneath]`
 - two machines, primary and backup; plus net and other machines
 - primary runs o/s and application s/w, talks to clients, etc.
 - backup does *not* initially execute o/s, applications, etc.
   + it only executes some Remus code
 - a few times per second:
   + pause primary
   + copy **entire RAM**, registers, disk to backup
   + resume primary
 - if primary fails:
   + start backup executing!

**Q:** Is Plan 1 correct?

 - i.e. does it look just like a single reliable server?

**Q:** What will outside world see if primary fails and replica takes over?

 - Will backup have same state as last visible on primary?
 - Might a client request be lost? executed twice?

**Q:** How to decide if primary has failed?

**Q:** How will clients know to talk to backup rather than primary?

**Q:** What if site-wide power failure?

 - Primary is running some o/s, has a plan for reboot from disk
   "crash-consistent"

**Q:** What if primary fails while sending state to backup?

 - i.e. backup is mid-way through absorbing new state?

**Q:** Is Plan 1 efficient?

 - Can we eliminate the fact that backup *state* trails the primary?
   + Seems very hard!
   + Primary would have to tell backup (and wait) on every instruction.
 - Can we *conceal* the fact that backup's state lags primary?
   + Prevent outside world from *seeing* that backup is behind last primary state
     * e.g. prevent primary sent RPC reply but backup state doesn't reflect that RPC
     * e.g. MapReduce `Register()` RPC, which it would be bad for backup to forget
   + _Idea:_ primary "holds" output until backup state catches up to output point
     * e.g. primary receives RPC request, processes it, creates reply packet,
       but Remus holds reply packet until backup has received corresponding state update

Remus epochs, checkpoints
-------------------------

  1. Primary runs for a while in Epoch 1 (E1), holding E1's output
  2. Primary pauses
  3. Primary copies RAM+disk changes from E1 to local buffer
  4. Primary resumes execution in E2, holding E2's output
  5. Primary sends checkpoint of RAM+disk to backup
  6. Backup copies all to separate RAM, then applies, then ACKs
  7. Primary releases E1's output
  8. Backup applies E1's changes to RAM and disk

If primary fails, backup finishes applying last epoch's disk+RAM,
then starts executing

**Q:** Any externally visible anomalies?

**Q:** What if primary receives + executes a request, crashes before checkpoint?
   backup won't have seen request!
 
 - That's fine as long as primary did not reply to that request: client will just send request again

**Q:** If primary sends a packet, then crashes, is backup guaranteed to have
   state changes implied by that packet?

 - Yes. That's the whole point of keeping the sent network packets buffered until the backup is up to date.

**Q:** What if primary crashes partway through release of output?
must backup re-send? How does it know what to re-send?

**Q:** How does Remus decide it should switch to backup?
 
 - Naive mechanism: If the primary stops talking to the backup, then something went wrong.

**Q:** Are there situations in which Remus will incorrectly activate the backup? i.e. primary is actually alive

 - Network partition...

**Q:** When primary recovers, how does Remus restore replication? Needed, since eventually active ex-backup will itself fail

**Q:** What if *both* fail, e.g. site-wide power failure?

 - RAM content will be lost, but disks will probably survive
 - After power is restored, reboot guest from one of the disks
   + O/S and application recovery code will execute
 - disk must be "crash-consistent"
   + So probably not the backup disk if was in middle of installing checkpoint
 - disk shouldn't reflect any held outputs (... why not?)
   + So probably not the primary's disk if was executing
 - I do not understand this part of the paper (Section 2.5)
   + Seems to be a window during which neither disk could be used if power failed
     - primary writes its disk during epoch
     - meanwhile backup applies last epoch's writes to its disk

**Q:** In what situations will Remus likely have good performance?

**Q:** In what situations will Remus likely have low performance?

**Q:** Should epochs be short or long?

Remus evaluation
----------------
 - _Summary:_ 1/2 to 1/4 native speed
 - Checkpoints are big and take time to send
 - Output hold limits speed at which clients can interact

### Why so slow?
 - Checkpoints are big and take time to generate and send
   + 100ms for SPECweb2005 -- because many pages written
 - So inter-checkpoint intervals must be long
 + So output must be held for quite a while
 + So client interactions are slow
   - Only 10 RPCs per second per client

### How could one get better performance for replication?
 - Big savings possible with application-specific schemes:
   - just send state really needed by application, not all state
   - send state in optimized format, not whole pages
   - send operations if they are smaller than state
 - likely *not* transparent to applications
   - and probably not to clients either

Primary-backup replication in Lab 2
-----------------------------------

### Outline
 - simple k/v database
 - primary and backup
 - replicate by primary sending each operation to backups
 - tolerate network problems, including partition
   + either keep going, correctly
   + or suspend operations until network is repaired
 - allow replacement of failed servers
 - you implement essentially all of this (unlike lab 1)

### _"View server"_ decides who primary `p` and backup `b` are
 - _Main goal:_ avoid "split brain" -- disagreement about who primary is
 - Clients and servers ask view server
 - They don't make independent decisions

### Repair
 - view server can co-opt "idle" server as `b` after old `b` becomes `p`
 - primary initializes new backup's state

### Key points:
  1. Only one primary at a time!
  2. The primary must have the latest state!
   
We will work out some rules to ensure these

### View server

 - Maintains a sequence of "views"

Example:

        view #, primary, backup
        0:      --       --
        1:      S1       --
        2:      S1       S2
        4:      S2       --
        3:      S2       S3

 - Monitors server liveness
   + each server periodically sends a ping RPC (more like a heartbeat)
   + _"dead"_ if missed `N` pings in a row
   + _"live"_ after single ping
 - Can be more than two servers pinging view server
   + if more than two, _"idle"_ servers
 - If primary is dead:
   + new view with previous backup as primary
 - If backup is dead, or no backup
   + new view with previously idle server as backup
 - OK to have a view with just a primary, and no backup
   + But -- if an idle server is available, make it the backup

### How to ensure new primary has up-to-date replica of state?

 - Only promote previous backup
   + i.e. don't make an idle server the primary
 - Backup must remember if it has been initialized by primary
   + If not, don't function as primary even if promoted!

**Q:** Can more than one server think it is primary?

        1: S1, S2
           net broken, so viewserver thinks S1 dead but it's alive
        2: S2, --
        now S1 alive and not aware of view #2, so S1 still thinks it is primary
        AND S2 alive and thinks it is primary
        => split brain, no good

### How to ensure only one server acts as primary?

...even though more than one may *think* it is primary.

_"Acts as"_ `==` executes and responds to client requests

_The basic idea:_

        1: S1 S2
        2: S2 --
        S1 still thinks it is primary
        S1 must forward ops to S2
        S2 thinks S2 is primary
        so S2 must reject S1's forwarded ops

The rules:

  1. Primary in view `i` must have been primary or backup in view `i-1`
  2. Primary must wait for backup to accept each request
     + **Q:** What if there's no backup?
  3. Non-backup must reject forwarded requests
  4. Non-primary must reject direct client requests
  5. Every operation must be before or after state transfer

Example:

        1: S1, S2
           viewserver stops hearing Pings from S1
        2: S2, --
           it may be a while before S2 hears about view #2
        before S2 hears about view #2
          S1 can process ops from clients, S2 will accept forwarded requests
          S2 will reject ops from clients who have heard about view #2
        after S2 hears about view #2
          if S1 receives client request, it will forward, S2 will reject
            so S1 can no longer act as primary
          S1 will send error to client, client will ask viewserver for new view,
             client will re-send to S2
        the true moment of switch-over occurs when S2 hears about view #2

### How can new backup get state?

 - e.g. all the keys and values
 - if S2 is backup in view `i`, but was not in view `i-1`,
   + S2 should ask primary to transfer the complete state

### Rule for state transfer:
 - every operation (`Put/Get/Append`) must be either before or after state xfer
   + `==` state xfer must be atomic w.r.t. operations
 - either
   + op is before, and xferred state reflects op
   + op is after, xferred state doesn't reflect op, primary forwards op after state

**Q:** Does primary need to forward `Get()`'s to backup?

 - After all, `Get()` doesn't change anything, so why does backup need to know?
 - and the extra RPC costs time

**Q:** How could we make primary-only `Get()`'s work?

**Q:** Are there cases when the Lab 2 protocol cannot make forward progress?

 - View service fails
 - Primary fails before backup gets state
 - We will start fixing those in Lab 3

