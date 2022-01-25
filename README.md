This is a collateral adapter for Dai that allows for the distribution of
rewards given to holders of the collateral.

## Rewards Adapter

We distinguish between `push` and `pull` rewards:

- in `push` rewards, the rewards are sent to holders without their input.
- in `pull` rewards, holders must actively claim their rewards.

`push` rewards are supported by default. In principle any pull-based
token rewards are supported, e.g. Compound `claimComp()` and SNX-staking
`getReward()`, with a little custom claiming logic.

### Usage

Developers need to

1) Override the `crop` function with the logic for claiming the given reward
   token and then return the tokens gained since the last crop. The default
   is the difference in the token balance and will work for push-reward tokens.

2) Override the `nav` function to show the underlying balance of the adapter
   (the Net Asset Valuation). The default is `gem.balanceOf(adapter)`.


Users can `join` and `exit` as with regular adapters. The user receives
their pending rewards on every `join` / `exit` and can use e.g. `join(0)`
to receive their rewards without depositing additional collateral.

There are two additional functions:

- `flee` allows for `exit` without invoking `crop`, in case of some
  issue with the `crop` function.

- `tack` is for transferring `stake` between users, following collateral
  transfers inside the `vat`.


#### `tack`

Collateral can be transferred in [dss] in several ways: simply via
`flux`, but also via `grab` and `frob`. `frob` and `flux` are publically
callable, which means that the rewards for a user may not match their
collateral balance. This is not a problem in itself as it isn't possible
to exit collateral without having the appropriate `stake`, so it isn't
possible to game rewards through e.g. `join($$$); flux(me, me2, $$$); flee($$$)`.

However, recipients of auction proceeds will need the appropriate
`stake` if they wish to exit.  The winner of a collateral auction receives
their collateral via `clip.take`. This increases their collateral
balance, but not their `stake`. `tack` allows this stake to be acquired,
from other users that have an excess of stake.

It isn't strictly necessary to alter the collateral auction contract, as
`tack` can be called by users, but it would be convenient to add a
`tack` after every `flux`:

    vat.flux(ilk, a, b, x);
    join.tack(a, b, x);

Then rewards will continue to accumulate throughout the auction and will
be distributed appropriately to the winner and the CDP owner, with the winner
able to reap their rewards following `take`.


### Terms

- `gem`: the underlying collateral token
- `nav`: Net Asset Valuation, total underlying gems held by adapter
- `nps`: `nav` per stake
- `stake`: gems per user
- `total`: total `stake`
- `bonus`: the reward token, e.g. COMP
- `stock`: last recorded balance of reward token
- `share`: accumulated `bonus` per `gem`
- `crops`: accumulated `bonus` per `gem` per user
