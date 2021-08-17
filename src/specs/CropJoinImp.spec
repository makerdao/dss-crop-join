// certoraRun ../CropJoin.sol:CropJoinImp ./DSToken1.sol ./DSToken2.sol ./Vat.sol --link CropJoinImp:vat=Vat --verify CropJoinImp:CropJoinImp.spec --rule_sanity

using DSToken1 as bonusToken

methods {
    vat() returns address envfree
    ilk() returns bytes32 envfree
    gem() returns address envfree
    dec() returns uint256 envfree
    bonus() returns address envfree
    share() returns uint256 envfree
    total() returns uint256 envfree
    stock() returns uint256 envfree
    crops(address) returns uint256 envfree
    stake(address) returns uint256 envfree
    nav() returns uint256 envfree
    nps() returns uint256 envfree

    bonusToken.balanceOf(address) returns (uint256) envfree

    balanceOf(address) returns (uint256) => DISPATCHER(true)
    transfer(address,uint256) => DISPATCHER(true)
    transferFrom(address,address,uint256) => DISPATCHER(true)
    decimals() => DISPATCHER(true)
}

ghost stakeSum() returns uint256 {
    init_state axiom stakeSum() == 0;
}
hook Sstore stake[KEY address a] uint256 balance (uint256 old_balance) STORAGE {
    havoc stakeSum assuming stakeSum@new() == stakeSum@old() + (balance - old_balance);
}

// For derived classes that override crop(), this may require modification to compute the correct value.
ghost crop() returns uint256;
hook Sstore stock uint256 stockValue (uint256 old_stockValue) STORAGE {
    havoc crop assuming crop@new() == (crop@old() + old_stockValue) - stockValue;
}
hook Sstore bonusToken.(slot 3)[KEY address a] uint256 balance (uint256 old_balance) STORAGE {
    havoc crop assuming (a == currentContract => crop@new() == (crop@old() + balance) - old_balance) && (a != currentContract => crop@new() == crop@old());
}

// invariants also check the desired property on the constructor
invariant stakeSum_equals_total() stakeSum() == total()

rule crop_is_correct_init() {
    env e;
    calldataarg args;
    require bonus() == bonusToken;
    require stock() == 0;
    constructor(e, args);
    require crop() == bonusToken.balanceOf(currentContract);
    assert  crop() == bonusToken.balanceOf(currentContract) - stock();
}

rule crop_is_correct_preserve(method f, env e, calldataarg args) filtered { f -> !f.isFallback } {
    require bonusToken == bonus() => crop() == bonusToken.balanceOf(currentContract) - stock();
    f(e, args);
    assert  bonusToken == bonus() => crop() == bonusToken.balanceOf(currentContract) - stock();
}

//rule fallback_always_reverts(method f, env e, calldataarg args) filtered { f -> f.isFallback } {
//    f(e, args);
//    assert lastReverted;
//}

// This rule establishes the validity of a method for calculating how much
// bonus token can be exited to usr from urn.
rule rewards_calculation(address urn, address usr) {
    require usr != currentContract;
    require bonusToken == bonus();
    require crop() == bonusToken.balanceOf(currentContract) - stock();  // invariant when bonusToken == bonus()

    uint256 yield = 0;
    uint256 _share = share();
    uint256 _total = total();
    if (_total > 0) {
        _share = _share + crop() * 10^27 / _total;
    }
    uint256 last = crops(urn);
    uint256 curr = stake(urn) * _share / 10^27;
    if (curr > last) yield = curr - last;

    uint256 usrBonusBal_pre = bonusToken.balanceOf(usr);
    env e;
    join(e, urn, usr, 0);

    uint256 usrBonusBal_post = bonusToken.balanceOf(usr);
    assert yield == usrBonusBal_post - usrBonusBal_pre;
}

rule tack_success_behavior(address src, address dst, uint256 wad) {
    require bonusToken == bonus();
    require crop() == bonusToken.balanceOf(currentContract) - stock();  // invariant when bonusToken == bonus()

    require src != currentContract;
    require dst != currentContract;

    uint256 srcStake_pre = stake(src);
    uint256 dstStake_pre = stake(dst);

    uint256 initShare = share();
    uint256 initStock = stock();
    uint256 initBonusBal = bonusToken.balanceOf(currentContract);

    // TODO: this code duplication sucks. Is there a way to avoid it? (can do at least partially via ghosts)
    uint256 srcYield_pre = 0;
    uint256 _share = share();
    uint256 _total = total();
    if (_total > 0) {
        _share = _share + crop() * 10^27 / _total;
    }
    uint256 last = crops(src);
    uint256 curr = stake(src) * _share / 10^27;
    if (curr > last) srcYield_pre = curr - last;

    uint256 dstYield_pre = 0;
    // _share and _total can be reused as they are urn-independent
    uint256 last2 = crops(dst);
    uint256 curr2 = stake(dst) * _share / 10^27;
    if (curr2 > last2) dstYield_pre = curr2 - last2;

    env e;
    tack(e, src, dst, wad);

    uint256 srcStake_post = stake(src);
    uint256 dstStake_post = stake(dst);

    // tack should not change any of these values
    assert _total == total();
    assert initShare == share();
    assert initStock == stock();
    assert initBonusBal == bonusToken.balanceOf(currentContract);

    // The assertions above allow us to reuse _share
    uint256 srcYield_post = 0;
    uint256 last3 = crops(src);
    uint256 curr3 = stake(src) * _share / 10^27;
    if (curr3 > last3) srcYield_post = curr3 - last3;

    uint256 dstYield_post = 0;
    uint256 last4 = crops(dst);
    uint256 curr4 = stake(dst) * _share / 10^27;
    if (curr4 > last4) dstYield_post = curr4 - last4;

    if (src == dst) {
        // stake is unchanged
        assert srcStake_pre == srcStake_post;

        // rewards are unchanged
        assert srcYield_pre == dstYield_post;
    } else {
        // The "ideal" behavior, with infinite numerical precision, would be:
        //
        //          src  dst  tack(src, dst, wad)  src                    dst
        //   stake  S_s  S_d  ------------------>  S_s - wad              S_d + wad
        // rewards  R_s  R_d  ------------------>  R_s * (1 - wad / S_s)  R_d + R_s * wad / S_s

        // wad stake is transferred from src to dst
        assert srcStake_post == srcStake_pre - wad && dstStake_post == dstStake_pre + wad;

        // rewards transferred proportionally to amount of stake transferred
        // TODO: account for rounding errors, this should fail at the moment
//        assert srcYield_post == srcYield_pre * (10^18 * (srcYield_pre - wad) / srcYield_pre);
//        assert dstYield_post == dstYield_pre + srcYield_pre * wad / srcYield_pre;
    }
}
