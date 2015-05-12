6.824 2015 Lecture 23: Bitcoin
==============================

**Note:** These lecture notes were slightly modified from the ones posted on the
6.824 [course website](http://nil.csail.mit.edu/6.824/2015/schedule.html) from 
Spring 2015.

Bitcoin
-------

 - an electronic currency system
 - has a technical side and a financial, economic, social side
 - maybe the 1st thing to ask: is it trying to do something better? is there a
   problem it solves for us?
 - online payments use credit cards, why not just use them?
   + Pluses:
     + They work online
     + Hard for people to steal my credit card (there are laws about how credit
       card companies work so that if your number is stolen, you are protected)
   + Good/Bad:
     - Customer service # on the back allows you to reverse charges
         + this can prevent or create fraud
     - tied to some country's currency
   - Minuses
     - No way for me as a customer or a merchant to independently verify anything
       about a credit card transaction: do you have money, is the CC # valid?
         + it can be good if you don't want people finding out how much money
           you have
     - relies on 3rd parties: great way to charge fees on everything
     - 3% fees
     - settling time is quite long (merchants are not sure they are getting their
       money until after one month)
     - pretty hard to become a credit card merchant
         - credit card companies take a lot of risk by sending money to merchants who
           might not send products to customers, resulting in the credit card
           company having to refund customers
 - For Bitcoin:
   + no 3rd parties are needed (well, not really true anymore)
   + fees are much smaller than 3%
   + the settling time is maybe 10 minutes
   + anyone can become a merchant
 - Bitcoin makes the sequence of transactions verifiable by everyone and agree
   on it `=>` no need to rely on 3rd parties


OneBit
------

 - simple electronic money system
 - it has one server called OneBank
 - each user owns some coins

Design:

    OneBank server

 - onebit xction:
   1. public key of new owner
   2. a hash of the last transfer record of this coin 
   3. a signature done over this record by the private key of last owner
 - bank keeps the list of transactions for each coin
 - `x` transfer the coin to `y`
 - `[T7: from=x, to=y; hash=h(prev tx); sig_x(this)]`
 - `y` transfers the coin to `z`, gets a hamburger from McDonalds
 - `[T8: from y, to=z; hash=h(T7); sig_y(this)]`
 - what can go wrong?
   + if someone transfers a coin to `z` it seems very unlikely that anyone else
     other than `z` can spend that coin: because no one else can sign a new
     transaction with that coin since they don't have `z`'s private key
 - we have to trust one bank to not let users double spend money
   + `y` can also buy a milkshake from Burger King with that same coin if the bank
     helps him
   + `[T8': from y, to=q'; hash=h(T7); sig_y(this)]`
   + the bank can show T8 to McDonalds and T8' to Burget King
   + (I love free food!)
   + as long as McDonalds and Burger King don't talk to each other and verify
     the transaction chain, they won't detect it

Bitcoin block chain
-------------------

 - bitcoin has a single block chain
 - many server: more or less replicas, have copy of entire block chain
 - each block in the block chain looks like this:
   + hash of previous block
   + set of transactions
   + nonce
   + current time
 - xactions have two stages
   + first it is created and sent out to the network
   + then the transaction is incorporated into the block chain

### How are blocks created? Mining

All of the peers in the bitcoin network try to create the next block:

 - each peer takes all transactions that have arrived since the previous block
   was created and try to append a new block with them
 - the rules say that a hash of a block has to be less than a certain number
   (i.e. it has a # of leading of zeros, making it hard to find)
 - each of the bitcoin peers adjust the `nonce` field in the block until they
   get a hash with a certain # of leading zeros
 - the point of this is to make it expensive to create new blocks
   + for a single computer it might take months to find such a nonce
 - the # of leading zeros is adjusted so that on average it takes 10 minutes for
   a new block to be added
   + clients monitor the `currentTime` field in the last 5 transactions or so
     and if they took to little time, they add another zero to # of target zeros
     - everyone obeys the protocol because if they don't the others will either
       reject their block (say if it has the wrong # of zeros or a wrong timestamp)

### The empty block chain

 - "In the beginning there was nothing, and then Satoshi created the first block."
 - "And then people started mining additional blocks, with no transactions."
 - "And then they got mining reward for each mined block."
 - "And that's how users got Bitcoins."
 - "And then they started doing transactions."
 - "And then there was light."

### What does it take to double spend

If a tx is in the block chain, can the system double spend its coins?

 - forking the block chain is the only way to do this
 - can the forks be hidden for long?  
 - if forks happens, miners will pick either one and continue mining
 - when a fork gets longer, everyone switches to it
   + if they stay on the shorter fork, they are likely to be outmined by the others
     and waste work, so they will have incentive to go on the longer one
   + the tx's on the shorter fork get incorporated in the longer one
   + committed tx's can get undone => people usually wait for a few extra blocks
     to be created after a tx's block
 - this is where the 51% rule comes in: if 51% of the computing power is honest
   the protocol works correctly
 - if more than 51% are dishonest, then they'll likely succeed in mining anything
   they want
 - probably the most clever thing about bitcoin: as long as you believe than more
   than half the computing power is not cheating, you can be sure there's no double
   spending

### Good and bad parts of design

 - (+) publicly verifiable log
 - (-) tied to a new currency and it is very volatile
   + lots of people don't use it for this reason
 - (+/-) mining-decentralized trust

Hard to say what will happen:

 - we could be all using it in 30 years
 - or, banks could catch up, and come up with their own verifiable log design
