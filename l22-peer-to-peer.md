6.824 2015 Lecture 22: Peer to peer system
==========================================

**Note:** These lecture notes were slightly modified from the ones posted on the
6.824 [course website](http://nil.csail.mit.edu/6.824/2015/schedule.html) from 
Spring 2015.

P2P systems
-----------

 - Today: look at peer-to-peer (P2P) systems like Bittorrent and Chord
 - classic implementation of file sharing services: users talk to a centralized 
   server to download file
 - it should be possible for users to talk to each other to get files
 - the peer-to-peer dream: no centralized components, just built out of people's
   computers

Why P2P?
--------

 - **(+)** spreads the work of serving the files over a huge # of PCs
 - **(+)** might be easier to deploy than a centralized system
   - no one has to buy a centralized server with a lot of bandwidth and storage
 - **(+)** if you play your card rights, the # of resources should scale naturally
   with the # of users => less chance of overload
 - **(+)** no centralized server => less chance to fail (harder to attack with
   DoS)
 - `=>` so many advantages! Why does anyone build non-P2P systems?
 - **(-)** it takes a sophisticated design to lookup a file in a system of a 
   million users `<=>` finding stuff is hard (can't just ask a DB)
 - **(-)** user computers are not as reliable as servers in a datacenter. users
   take their computers offline, etc.
 - **(-)** some P2P systems are open (BitTorrent) but some are closed, where only 
   say Amazon's computer are participating in this scheme (sort of like Dynamo).
   + `=>` in open systems, there will be malicious users `=>` easy to attack

The result is that P2P software has certain niches that you find it in

 - systems where there's a lot of data, like online video services
 - chat systems
 - in settings where having a central server is not _natural_ like Bitcoin 
   + it would be nice for DNS to be decentralized for instance
 - _seems_ like the dominant use has been to serve illegal files

BitTorrent
----------

### Pre-DHT BitTorrent

Diagram:

     ---        ---
    | W |      | T |
     ---        ---
    /\         /\
    | click on /  .torrent file
    \         /
     ---/----        ---  
    | C |  <------> | C |
     ---             --- 

 - client goes to a webserver and downloads a .torrent file
 - torrent file stores the hash of the data and the address of a tracker
 - the tracker keeps a record of all the clients who have downloaded this 
   file and maybe still have it and maybe would be willing to serve it to
   other clients
 - client contacts tracker, asks about other clients
 - the huge gain here is that the file is transfered between the clients 
   directly, and the webserver and tracker aren't incurring too much cost

### DHT-based BitTorrent (Trackerless torrents)

 - tracker is a single point of failure
 - can fix this by replicating them or having extra trackers
 - the users who download the file also form a giant distributed key value
   store (a DHT)
 - clients still have to talk to the original web server to get the `infohash`
   of the file it wants to download
 - it uses it as a key to do a lookup in the DHT
 - the values are IP addresses of other clients who have the files
 - this really replaces the tracker
 - how to find an entry node in the DHT? Maybe the client has some well known
   nodes hardcoded
 - _maybe_ the DHT is more reliable and less vulnerable to legal (subpoena) and 
   technical attacks
 - BitTorrent is fantastically popular: tens of millions of users `=>` giant DHT,
   however, most torrents are backed by real trackers

How did DHTs start?
-------------------

 - a bunch of research 15 years ago on how to build DHTs
 - point was to harness the millions of computers on the Internet to provide
   something that was close to a database
 - the interface is very simple: `Put(k, v), Get(k)`
   + hope is that puts are reflected in gets (after a while)
 - in practice it is hard to build consistent systems
 - little guarantees about availability of data and consistency
   + system does not guarantee to keep your data when you do a `Put()`
 - still difficult to build, even with these weak guarantees

DHT designs
-----------

1. Flood everyone with Get's when you want to get a key
 - `=>` system can't handle too much load
2. Suppose everyone agreed to the whole list of nodes in the DHT. 
 - Then you can have some hashing convention that hashes a key to an exact node
   and lookups are efficient.
 - Critical that all agree otherwise A sends put to X and B sends get to Y for the
   same key `k`
 - The real problem is that it's hard to keep tables up to date and
   accurate.

What we want:

 - We're looking for a system where each node only has to know about a few 
   other nodes.
 - We don't want the node to send too many messages to do a lookup
 - the rough approach that all DHT take is to define a global data structure
   that is layered across nodes
 - Bad idea: organize all nodes as a binary tree, data is stored in leaf nodes
   such that lower keys are in the left most nodes
   + all traffic goes through root (bad) => if root goes down, partition
   + how can we replace nodes that go down?

Chord
-----

 - numbers in a circular ID space (like integers modulo p) from 0 to 2^160 - 1
 - each node picks a random ID in this space as its node ID
 - the keys have identifiers in this space, and we want the identifiers to have a 
   uniform distribution, because we use it to map the key to a node identifier 
   `=>` use a hash on the actual keys to get their identifier
 - the node responsible for a key is the first _closest_ node to that key in
   a clockwise direction: known as its **successor**
   + closeness `= |node ID - key ID|`

Slow but correct scheme:

 - through some sort of hocus-pocus, every node just has to know about its own
   successor (say, node 2's successor is node 18, etc)
 - we can always do a lookup starting at every node simply by following these
   successor pointers
   + this is called _routing_
   + all about forwarding a lookup message to a node further one the ring
 - this is slow, with millions of nodes could be sending millions of messages
   for a single lookup
 - need time logarithmic in the total # of nodes in the DHT
   `=>` each hop has to be able to compute the distance between it and any target key
 - in Chord, every node has a _finger table_ of 160 entries
 - the finger table of node `n` has entry `i`:
   + `f[i] = successor(n + 2^i)`
   + `=>` the 159th entry will point to some node `n + 2^159` roughly halfway across the ID
     space
 - each hop is on the order of 50 milliseconds, if the hops are halfway around
   the world
   + `=>` around 1 second to go through 20 nodes `=>` some applications might
     not take this well (BitTorrent is okay, because it only stores IPs in the
     DHT)
 - when nodes join, they get a copy of the entry node's fingerprint
   + not accurate for the new node, but good enough
   + `=>` have to correct the table `=>` for the `i`th entry do a lookup for
     `n+2^i` and set `f[i]` to the address of the node that replied
 - every lookup is likely to encounter a dead node and timeouts take a long time
 - the churn in BitTorrent is quite high
   + 10 million people participate this hour, the next hour there will be other
     10 million people `=>` hard to keep finger table updated
 - `log n` lookup time is not that great
 - finger tables are only used to speed up lookups
 - each node must correctly know its successor for Chord to be correct
   + so that Gets by one node see the Puts by another node
 - when a node first joins, it does a lookup on its own identifier to find 
   its successor
   + `--> 10 -- [new node 15] --> 20 -->`
   + 15 sets its successor pointer to 20
   + so far no one is doing lookups
   + 15 isn't really part of the system until 10 knows about it
   + every node periodically asks its successor who they think their predecessor is
     + `10: hey 20, who's your predecessor?`
     + `20: my predecessor is 15`
     + `10: oh, thought it was me, so let me set 15 as my successor then`
     + `15: oh, hi 10, thanks for adding me as your sucessor, let me add you
        as my predecessor`
     + this is called stabilization

Example:

    10 -> 20

    12, 18 join

    10 -> 20, 12->20, 18->20, 20->18

    10 -> 18, 18->10, 18->20, 20->18, 12 ->18

    10 -> 18,18->20, 20->18, 12 ->18, 18->12

    10 -> 12, 12->10 12->18, 18->12, 18->20, 20->18

 - when a node gets a closer predecessor, it transfers keys that would be closer
   to its predecessor there

If nodes fail, can we do lookups correctly?

 - suppose an intermediate node fails in the lookup procedure, then the initiating
   node can simply pick another
 - towards the end of the lookup process, finger tables are not used anymore. 
   instead successor pointers are followed `=>` if a node fails then the lookup cannot
   proceed `=>` nodes must remember successors of their successors to be able
   to proceed
 - the probability of a partition occurring is low on the Internet


6.824 2015 original notes

    Lecture outline:
      peer-to-peer (P2P)
      BitTorrent
      DHTs
      Chord

    Peer-to-peer
      [user computers, files, direct xfers]
      users computers talk directly to each other to implement service
        in contrast to user computers talking to central servers
      could be closed or open
      examples:
        skype, video and music players, file sharing

    Why might P2P be a win?
      spreads network/caching costs over users
      absence of server may mean:
        easier to deploy
        less chance of overload
        single failure won't wreck the whole system
        harder to attack

    Why don't all Internet services use P2P?
      can be hard to find data items over millions of users
      user computers not as reliable than managed servers
      if open, can be attacked via evil participants

    The result is that P2P has some successful niches:
      Client-client video/music, where serving costs are high
      Chat (user to user anyway; privacy and control)
      Popular data but owning organization has no money
      No natural single owner or controller (Bitcoin)
      Illegal file sharing

    Example: classic BitTorrent
      a cooperative download system, very popular!
      user clicks on download link for e.g. latest Linux kernel distribution
        gets torrent file w/ content hash and IP address of tracker
      user's BT client talks to tracker
        tracker tells it list of other user clients w/ downloaded file
      user't BT client talks to one or more client's w/ the file
      user's BT client tells tracker it has a copy now too
      user's BT client serves the file to others for a while
      the point:
        provides huge download b/w w/o expensive server/link

    BitTorrent can also use a DHT instead of / as well as a tracker
      this is the topic of today's readings
      BT clients cooperatively implement a giant key/value store
      "distributed hash table"
      the key is the file content hash ("infohash")
      the value is the IP address of a client willing to serve the file
        Kademlia can store multiple values for a key
      client does get(infohash) to find other clients willing to serve
        and put(infohash, self) to register itself as willing to serve
      client also joins the DHT to help implement it

    Why might the DHT be a win for BitTorrent?
      single giant tracker, less fragmented than many trackers
        so clients more likely to find each other
      maybe a classic tracker too exposed to legal &c attacks
      it's not clear that BitTorrent depends heavily on the DHT
        mostly a backup for classic trackers?

    How do DHTs work?

    Scalable DHT lookup:
      Key/value store spread over millions of nodes
      Typical DHT interface:
        put(key, value)
        get(key) -> value
      loose consistency; likely that get(k) sees put(k), but no guarantee
      loose guarantees about keeping data alive

    Why is it hard?
      Millions of participating nodes
      Could broadcast/flood request -- but too many messages
      Every node could know about every other node
        Then hashing is easy
        But keeping a million-node table up to date is hard
      We want modest state, and modest number of messages/lookup

    Basic idea
      Impose a data structure (e.g. tree) over the nodes
        Each node has references to only a few other nodes
      Lookups traverse the data structure -- "routing"
        I.e. hop from node to node
      DHT should route get() to same node as previous put()

    Example: The "Chord" peer-to-peer lookup system
      By Stoica, Morris, Karger, Kaashoek and Balakrishnan; 2001

    Chord's ID-space topology
      Ring: All IDs are 160-bit numbers, viewed in a ring.
      Each node has an ID, randomly chosen

    Assignment of key IDs to node IDs?
      Key stored on first node whose ID is equal to or greater than key ID.
        Closeness is defined as the "clockwise distance"
      If node and key IDs are uniform, we get reasonable load balance.
      So keys IDs should be hashes (e.g. bittorrent infohash)

    Basic routing -- correct but slow
      Query is at some node.
      Node needs to forward the query to a node "closer" to key.
        If we keep moving query closer, eventually we'll win.
      Each node knows its "successor" on the ring.
        n.lookup(k):
          if n < k <= n.successor
            return n.successor
          else
            forward to n.successor
      I.e. forward query in a clockwise direction until done
      n.successor must be correct!
        otherwise we may skip over the responsible node
        and get(k) won't see data inserted by put(k)

    Forwarding through successor is slow
      Data structure is a linked list: O(n)
      Can we make it more like a binary search?
        Need to be able to halve the distance at each step.

    log(n) "finger table" routing:
      Keep track of nodes exponentially further away:
        New state: f[i] contains successor of n + 2^i
        n.lookup(k):
          if n < k <= n.successor:
            return successor
          else:
            n' = closest_preceding_node(k) -- in f[]
            forward to n'

    for a six-bit system, maybe node 8's looks like this:
      0: 14
      1: 14
      2: 14
      3: 21
      4: 32
      5: 42

    Why do lookups now take log(n) hops?
      One of the fingers must take you roughly half-way to target

    There's a binary lookup tree rooted at every node
      Threaded through other nodes' finger tables
      This is *better* than simply arranging the nodes in a single tree
        Every node acts as a root, so there's no root hotspot
        But a lot more state in total

    Is log(n) fast or slow?
      For a million nodes it's 20 hops.
      If each hop takes 50 ms, lookups take a second.
      If each hop has 10% chance of failure, it's a couple of timeouts.
      So in practice log(n) is better than O(n) but not great.

    How does a new node acquire correct tables?
      General approach:
        Assume system starts out w/ correct routing tables.
        Use routing tables to help the new node find information.
        Add new node in a way that maintains correctness.
      New node m:
        Sends a lookup for its own key, to any existing node.
          This yields m.successor
        m asks its successor for its entire finger table.
      At this point the new node can forward queries correctly
      Tweaks its own finger table in background
        By looking up each m + 2^i

    Does routing *to* new node m now work?
      If m doesn't do anything,
        lookup will go to where it would have gone before m joined.
        I.e. to m's predecessor.
        Which will return its n.successor -- which is not m.
      So, for correctness, m's predecessor needs to set successor to m.
        Each node keeps track of its current predecessor.
        When m joins, tells its successor that its predecessor has changed.
        Periodically ask your successor who its predecessor is:
          If that node is closer to you, switch to that guy.
        So if we have x m y
          x.successor will be y (now incorrect)
          y.predecessor will be m
          x will ask its x.successor for predecessor
            x learns about m
            sets x.successor to m
            tells m "x is your predecessor"
            called "stabilization"
      Correct successors are sufficient for correct lookups!

    What about concurrent joins?
      Two new nodes with very close ids, might have same successor.
      Example:
        Initially 40 then 70
        50 and 60 join concurrently
        at first 40, 50, and 60 think their successor is 70!
        which means lookups for e.g. 45 will yield 70, not 50
        after one stabilization, 40 and 50 will learn about 60
        then 40 will learn about 50

    To maintain log(n) lookups as nodes join,
      Every one periodically looks up each finger (each n + 2^i)

    Chord's routing is conceptually similar to Kademlia's
      Finger table similar to bucket levels
        Both halve the metric distance for each step
        Both are about speed and can be imprecise
      n.successor similar to Kademlia's requirement that
        each node know of all the nodes that are very close in xor-space
        in both cases care is needed to ensure that different lookups
          for same key converge on exactly the same node

    What about node failures?
      Assume nodes fail w/o warning. Strictly harder than graceful departure.
      Two issues:
        Other nodes' routing tables refer to dead node.
        Dead node's predecessor has no successor.
      If you try to route via dead node, detect timeout, treat as empty table entry.
        I.e. route to numerically closer entry instead.
      For dead successor
        Failed node might have been just before key ID!
          So we need to know what its n.successor was
        Maintain a _list_ of successors: r successors.
        Lookup answer is first live successor >= key
          or forward to *any* successor < key

    Kademlia has a faster plan for this
      send alpha (or k) lookup RPCs in parallel, to different nodes
      send more lookups as previous ones return info about nodes closer to key
      single non-responsive node won't cause lookup to suffer a timeout

    Dealing with unreachable nodes during routing is extremely important
      "Churn" is very high in open p2p networks
      People close their laptops, move WiFi APs, &c pretty often
      Measurement of Bittorrent/Kademlia suggest lookups are not very fast

    Geographical/network locality -- reducing lookup time
      Lookup takes log(n) messages.
        But they are to random nodes on the Internet!
        Will often be very far away.
      Can we route through nodes close to us on underlying network?
      This boils down to whether we have choices:
        If multiple correct next hops, we can try to choose closest.

    Idea:
      to fill a finger table entry, collect multiple nodes near n+2^i on ring
      perhaps by asking successor to n+2^i for its r successors
      use lowest-ping one as i'th finger table entry

    What's the effect?
      Individual hops are lower latency.
      But less and less choice (lower node density) as you get close in ID space.
      So last few hops likely to be very long. 
      Though if you are reading, and any replica will do,
        you still have choice even at the end.

    What about security?
      Self-authenticating data, e.g. key = SHA1(value)
        So DHT node can't forge data
        Of course it's annoying to have immutable data...
      Can someone cause millions of made-up hosts to join?
        They don't exist, so routing will break?
        Don't believe new node unless it responds to ping, w/ random token.
      Can a DHT node claim that data doesn't exist?
        Yes, though perhaps you can check other replicas
      Can a host join w/ IDs chosen to sit under every replica?
        Or "join" many times, so it is most of the DHT nodes?
        Maybe you can require (and check) that node ID = SHA1(IP address)

    Why not just keep complete routing tables?
      So you can always route in one hop?
      Danger in large systems: timeouts or cost of keeping tables up to date.

    How to manage data?
      Here is the most popular plan.
      DHT doesn't guarantee durable storage
        So whoever inserted must re-insert periodically if they care
        May want to automatically expire if data goes stale (bittorrent)
      DHT does replicate each key/value item
        On the nodes with IDs closest to the key, where looks will find them
        Replication can help spread lookup load as well as tolerate faults
      When a node joins:
        successor moves some keys to it
      When a node fails:
        successor probably already has a replica
        but r'th successor now needs a copy

    Retrospective
      DHTs seem very promising for finding data in large p2p systems
        Decentralization seems good for load, fault tolerance
      But: the security problems are difficult
      But: churn is a serious problem, particularly if log(n) is big
      So DHTs have not had the impact that many hoped for
