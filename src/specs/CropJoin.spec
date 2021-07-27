methods {
    rely(address)
    deny(address)
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
    uint256 srcRewards_pre = srcStake_pre * share() / 10^27 - crops(src);
    uint256 dstRewards_pre = dstStake_pre * share() / 10^27 - crops(dst);

    env e;
    tack(e, src, dst, wad);

    uint256 srcStake_post = stake(src);
    uint256 dstStake_post = stake(dst);
    uint256 srcRewards_post = srcStake_post * share() / 10^27 - crops(src);
    uint256 dstRewards_post = dstStake_post * share() / 10^27 - crops(dst);

    if (src == dst) {
        // stake is unchanged
        assert srcStake_pre == srcStake_post;

        // rewards are unchanged
        assert srcRewards_pre == srcRewards_post;
    } else {
        // wad stake is transferred from src to dst
        assert srcStake_post == srcStake_pre - wad && dstStake_post == dstStake_pre + wad;

        // the fraction of src's rewards corresponding to the fraction that wad is of
        // src's initial stake has been transferred to dst
        uint256 approx_srcRewards_post = srcRewards_pre * srcStake_post / srcStake_pre;
        assert srcRewards_post <= approx_srcRewards_post + 5 && srcRewards_post >= approx_srcRewards_post - 5;
//        assert dstRewards_post == dstRewards_pre + srcRewards_pre * wad / srcStake_pre;
    }
}
