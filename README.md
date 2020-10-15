This is a collateral adapter for Dai that allows for the distribution of
rewards given to holders of the collateral.

This adapter is then used to implement a leveraged cUSDC strategy,
depositing the underlying USDC collateral into Compound and farming COMP.

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
`stake` if they wish to exit.  The winner of a collateral auction claims
their collateral via `flip.deal`. This increases their collateral
balance, but not their `stake`. `tack` allows this stake to be acquired,
from other users that have an excess of stake.

It isn't strictly necessary to alter the collateral auction contract, as
`tack` can be called by users, but it would be convenient to add a
`tack` after every `flux`:

    vat.flux(ilk, a, b, x);
    join.tack(a, b, x);

Then rewards will continue to accumulate throughout the auction and will
be distributed appropriately to the winner and the CDP owner, with the winner
able to reap their rewards following `deal`.


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


## cUSDC Strategy

Compound allows supplying and borrowing against the same asset. COMP is
distributed according to the total amount borrowed and supplied. This allows
for a low risk strategy: supply USDC and then borrow USDC against it. We will
continually lose USDC to interest, but this is more than offset by COMP income.

Given an initial supply `s0` (the amount of underlying USDC in the adapter),
and a USDC Collateral Factor of 75% `cf = 0.75`, we can supply a maximum of

    s = s0 / (1 - cf)

i.e. `s = 4 * s0` for USDC, where the amount borrowed `b = s * cf` and
the utlisation `u = b / s = cf`.

The real value of the underlying collateral, our Net Asset Valuation, is
given by

    nav = g + s - b

where `g` accounts for any underlying that remains in the contract.


### `wind`

In order to approach this supply it is necessary to go through several
rounds of `mint` / `borrow`, as we cannot exceed `cf` at any point. The
maximum amount that can be borrowed in each round is given by

    x <= cf * s - b

Which will achieve a new utilisation `u'` of

    u' = cf / (1 + cf - u)

We can reduce the number of rounds necessary by providing a loan `L`, then

    x1 <= cf * (s + L) - b

but we must also remain under our target collateral factor `tf` after
paying back any loan

    x2 <= (tf * s - b) / (1 - tf)

therefore

    x <= min(x1, x2)

Wind performs this calculation for each round of borrowing, ensuring
that we never exceed our target utilisation.

We can determine the minimum necessary loan to achieve a target
utilisation in a single round given an initial `(s, b) = (s0, 0)`,

    L / s0 >= (u' / cf - 1 + u') / (1 - u')

e.g. for `u' = 0.675` (90% of cf), we require a loan of 177% of the
collateral amount.

    L / s0 >= 1.77


### `unwind`

Our utilisation will increase over time due to interest, and if we
exceed `u > cf` we may be subject to compound liquidation. To lower the
utlisation we must go through rounds of `redeem` / `repay`, with the
maximum redeem amount given by

    x <= L + s - b / cf

We must also redeem an extra amount `e` if we are to allow a user to
`exit`, giving a minimum redeem amount of

    x >= (b - s * u' + e * u') / (1 - u')

We have three different regimes depending on the value of `u'`, if we
are to have only one redeem / repay round. When `u > cf`, then `u' <= cf`
and

    L / s0 >= (u / cf - 1) / ((1 - u) * (1 - cf))
              + (e / s0) * cf / (1 - cf)

i.e. we must always provide a loan.

When `tf < u < cf`, then `u' < u' and

    L / s0 >= (u / cf - 1) / (1 - u)
              + (e / s0) * u / (1 - u)

i.e. a loan is necessary for

    e / s0 >= 1 / u - 1 / cf

and our maximum exit is given by

    e / s0 <= 1 / u - 1 / cf + (L / s0) * (1 - u) / u

Finally when `u < tf`, `u' = tf` and

    L / s0 >= (u / cf - 1 + u - u * tf / cf) / ((1 - u) * (1 - tf))
              + (e / s0) * tf / (1 - tf)

Then for a full exit of all of the underlying collateral, `e / s0 = 1`,
from `u = 0.675, cf = 0.75`, we again find that we need a 177% loan,

    L / s0 >= 1.77

Without a loan we are limited to

    e / s0 <= 1 / tf - 1 / cf

or 14.8% of the underlying collateral for `tf = 0.675`. Adding further
rounds will allow for larger exits and smaller loans.


### Risks

- Liquidation
- Compound Governance
- Compound
