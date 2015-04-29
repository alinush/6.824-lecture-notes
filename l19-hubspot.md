6.824 2015 Lecture 19: HubSpot
==============================

**Note:** These lecture notes were slightly modified from the ones posted on the
6.824 [course website](http://nil.csail.mit.edu/6.824/2015/schedule.html) from 
Spring 2015.

Distributed systems in the real world
-------------------------------------

Who builds distributed systems:
 
 + SaaS market
   - Startups: CustomMade, Instagram, HubSpot
   - Mature: Akamai, Facebook, Twitter
 + Enterprise market
   - Startup: Basho (Riak), Infinio, Hadapt
   - Mature: VMWare, Vertica
 + ...and graduate students

High-level components:
 
 - front-end: load balancing routers
 - handlers, caching, storage, business services
 - infra-services: logging, updates, authentication

Low-level components:

 - RPCs (semantics, failure)
 - coordination (consensus, Paxos)
 - persistence (serialization semantics)
 - caching
 - abstractions (queues, jobs, workflows)

Building the thing
------------------

Business needs will affect scale and architecture

 - dating website core data: OkCupid uses 2 beefy database servers
 - analytics distributed DB: Vertica/Netezza clusters have around 100 nodes
 - mid-size SaaS company: HubSpot uses around 100 single-node DBs or around
   10 node HBase clusters
   + MySQL mostly
 - Akamai, Facebook, Amazon: tens of thousands of machines

Small SaaS startup:

 - early on the best thing is to figure out if you have a good idea that people
   would buy
 - typically use a platform like Heroku, Google App Engine, AWS, Joyent, CloudFoundry

Midsized SaaS:

 - need more control than what PaaS offers
 - scale may enable you to build better solutions more cheaply
 - open source solutions can help you

Mature SaaS:

 - [Jepsen tool](http://aphyr.com/tags/jepsen)
 - "Ensure your design works if scale changes by 10x or 20x; the right solution
    for x often not optimal for 100x", Jeff Dean

How to think about your design:

 - understand what your system needs to do and the semantics
 - understand workload scale then estimate (L2 access time, network latency) and
   plan to understand performance

Running the thing
-----------------

 - "telemetry beats event logging"
   + logs can be hard to understand: getting a good story out is difficult
 - logging: first line of defense, doesn't scale well
   + logs on different machines
   + what if timestamps are useless because clocks are not synced
   + lots of tools around logging
   + having log data in queryable format tends to be very useful 
 - monitoring, telemetry, alerting
   + annotate code with timing and counting events
   + measure how big a memory queue is or how long a request takes and
     you can count it
   + can do telemetry at multiple granularities so we can break long requests
     into smaller pieces and pinpoint problems

Management: command and control
-------------------------------

 - in classroom settings you don't have to set up a bunch of machines
 - as your business scales new machines need to be set up => must automate
 - separate configuration from app
 - HubSpot uses a ZooKeeper like system that allows apps to get config values
 - Maven for dependencies in Java
 - Jenkins for continuous integration testing

Testing
-------

 - automated testing makes it easy to verify newly introduced changes to your code
 - UI testing can be a little harder (simulate clicks, different layout in different browsers)
   + front end changes => must change tests?

Teams
-----

 - people: how do you get together and build the thing
 - analogy: software engineering process is sort of like a distributed system
   with unreliable components.
   + somehow must build reliable software on a reliable schedule
 - gotta take care of your people: culture has to be amenable to people growing,
   learning and failing

Process
-------

 - waterfall: big design upfront and then implement it
 - agile/scrum: don't know the whole solution, need to iterate on designs
 - kanban:
 - lean:

Questions
---------

 - making a big change on fast changing code base
   + if you branch and then merge your changes, chances are the codebase has
     changed drastically
   + you can try to have two different branches deployed such that the new
     branch can be tested in production
 - culture changes with growth
   + need to pay attention to culture and happiness of employees
   + very important to measure happiness
   + having small teams might help because people can own projects
