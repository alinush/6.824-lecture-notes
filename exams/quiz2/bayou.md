2012, Quiz 1
------------

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

2014, Quiz 2
------------

