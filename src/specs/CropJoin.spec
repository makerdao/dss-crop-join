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

ghost stakeSum() returns uint256;

hook Sstore stake[KEY address a] uint256 balance (uint256 old_balance) STORAGE {
    havoc stakeSum assuming stakeSum@new() == stakeSum@old() + (balance - old_balance);
}

rule stakeSum_equals_total(method f) {
    require stakeSum() == total();
    calldataarg arg;
    env e;
    sinvoke f(e, arg);
    assert stakeSum() == total();
}
