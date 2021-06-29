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
invariant stakeSum_equals_total2() stakeSum() == total()
