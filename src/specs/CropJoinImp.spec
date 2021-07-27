// certoraRun ../CropJoin.sol:CropJoinImp ./DSToken.sol --link CropJoinImp:bonus=DSToken --verify CropJoinImp:CropJoinImp.spec --rule_sanity

using DSToken as token

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
    join(address, address, uint256)
    exit(address, address, uint256)
    flee(address, address)
    tack(address, address, uint256)
    token.balanceOf(address) returns (uint256) envfree
}

ghost stakeSum() returns uint256 {
    init_state axiom stakeSum() == 0;
}

hook Sstore stake[KEY address a] uint256 balance (uint256 old_balance) STORAGE {
    havoc stakeSum assuming stakeSum@new() == stakeSum@old() + (balance - old_balance);
}

// invariants also check the desired property on the constructor
invariant stakeSum_equals_total() stakeSum() == total()

rule tack_success_behavior(address src, address dst, uint256 wad) {
    uint256 srcStake_pre = stake(src);
    uint256 dstStake_pre = stake(dst);

    require token == bonus();

    uint256 srcBonusBal_pre = token.balanceOf(src);
    uint256 dstBonusBal_pre = token.balanceOf(dst);

    env e;
    storage initState = lastStorage;

    join(e, src, src, 0);
    join(e, dst, dst, 0);

    uint256 srcRewards_pre = token.balanceOf(src) - srcBonusBal_pre;
    uint256 dstRewards_pre = token.balanceOf(dst) - dstBonusBal_pre;

    tack(e, src, dst, wad) at initState;

    uint256 srcStake_post = stake(src);
    uint256 dstStake_post = stake(dst);

    uint256 srcBonusBal_post = token.balanceOf(src);
    uint256 dstBonusBal_post = token.balanceOf(dst);

    join(e, src, src, 0);
    join(e, dst, dst, 0);

    uint256 srcRewards_post = token.balanceOf(src) - srcBonusBal_post;
    uint256 dstRewards_post = token.balanceOf(dst) - dstBonusBal_post;

    if (src == dst) {
        // stake is unchanged
        assert srcStake_pre == srcStake_post;

        // rewards are unchanged
        assert srcRewards_pre == srcRewards_post;
    } else {
        // The "ideal" behavior, with infinite numerical precision, would be:
        //
        //          src  dst  tack(src, dst, wad)  src               dst
        //   stake  S_s  S_d  ------------------>  S_s - wad         S_d + wad
        // rewards  R_s  R_d  ------------------>  R_s(1 - wad/S_s)  R_d + R_s * wad / S_s

        // wad stake is transferred from src to dst
        assert srcStake_post == srcStake_pre - wad && dstStake_post == dstStake_pre + wad;

        // rewards transferred proportionally to amount of stake transferred
        // TODO: account for rounding errors, this should fail at the moment
        assert srcRewards_post == srcRewards_pre * (srcStake_pre - wad) / srcStake_pre;
        assert dstRewards_post == dstRewards_pre + srcRewards_pre * wad / srcStake_pre;
    }
}
