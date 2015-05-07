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
   file and maybe still have it and maybe would be willing to server it to
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
