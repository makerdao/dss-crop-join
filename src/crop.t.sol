pragma solidity ^0.6.7;

import "ds-test/test.sol";

import "./crop.sol";

contract Token {
    mapping (address => uint) public balanceOf;
    constructor(uint wad) public {
        balanceOf[msg.sender] = wad;
    }
    function transfer(address usr, uint wad) public {
        require(balanceOf[msg.sender] >= wad, "transfer/insufficient");
        balanceOf[msg.sender] -= wad;
        balanceOf[usr] += wad;
    }
    function transferFrom(address src, address dst, uint wad) public {
        require(balanceOf[src] >= wad, "transferFrom/insufficient");
        balanceOf[src] -= wad;
        balanceOf[dst] += wad;
    }
}

contract Troll is Token(0) {
    uint256 public rewards;
    function reward(uint val) public {
        rewards += val;
    }
    function claimComp(address[] memory, address[] memory, bool, bool) public {
        balanceOf[msg.sender] += rewards;
        rewards = 0;
    }
    function claimComp() public {
        balanceOf[msg.sender] += rewards;
        rewards = 0;
    }
}

contract CropTest is DSTest {
    function assertEq(int a, int b, bytes32 err) internal {
        if (a != b) {
            emit log_named_bytes32("Fail: ", err);
            assertEq(a, b);
        }
    }
    function assertEq(uint a, uint b, bytes32 err) internal {
        if (a != b) {
            emit log_named_bytes32("Fail: ", err);
            assertEq(a, b);
        }
    }

    Token    usdc;
    Troll    comp;
    Vat      vat;
    CropJoin join;
    address  self;
    bytes32  ilk = "cusdc";

    function setUp() public {
        self = address(this);
        usdc = new Token(1000 ether);
        comp = new Troll();
        vat  = new Vat();
        join = new CropJoin( address(vat)
                           , ilk
                           , address(usdc)
                           , address(comp)
                           , address(comp)
                           );
    }

    function test_simple_multi_user() public {
        Usr a = new Usr(join);
        Usr b = new Usr(join);
        usdc.transfer(address(a), 200 ether);
        usdc.transfer(address(b), 200 ether);

        a.join(60 ether);
        b.join(40 ether);

        comp.reward(50 ether);

        a.join(0);
        assertEq(comp.balanceOf(address(a)), 30 ether);
        assertEq(comp.balanceOf(address(b)),  0 ether);

        b.join(0);
        assertEq(comp.balanceOf(address(a)), 30 ether);
        assertEq(comp.balanceOf(address(b)), 20 ether);
    }
    function test_simple_multi_reap() public {
        Usr a = new Usr(join);
        Usr b = new Usr(join);
        usdc.transfer(address(a), 200 ether);
        usdc.transfer(address(b), 200 ether);

        a.join(60 ether);
        b.join(40 ether);

        comp.reward(50 ether);

        a.join(0);
        assertEq(comp.balanceOf(address(a)), 30 ether);
        assertEq(comp.balanceOf(address(b)),  0 ether);

        b.join(0);
        assertEq(comp.balanceOf(address(a)), 30 ether);
        assertEq(comp.balanceOf(address(b)), 20 ether);

        a.join(0); b.reap();
        assertEq(comp.balanceOf(address(a)), 30 ether);
        assertEq(comp.balanceOf(address(b)), 20 ether);
    }
    function test_simple_join_exit() public {
        join.join(100 ether);
        assertEq(comp.balanceOf(self), 0 ether, "no initial rewards");

        comp.reward(10 ether);
        join.join(0);
        assertEq(comp.balanceOf(self), 10 ether, "rewards increase with reap");

        join.join(100 ether);
        assertEq(comp.balanceOf(self), 10 ether, "rewards invariant over join");

        join.exit(200 ether);
        assertEq(comp.balanceOf(self), 10 ether, "rewards invariant over exit");

        join.join(50 ether);

        assertEq(comp.balanceOf(self), 10 ether);
        comp.reward(10 ether);
        join.join(10 ether);
        assertEq(comp.balanceOf(self), 20 ether);
    }
    function test_complex_scenario() public {
        Usr a = new Usr(join);
        Usr b = new Usr(join);
        usdc.transfer(address(a), 200 ether);
        usdc.transfer(address(b), 200 ether);

        a.join(60 ether);
        b.join(40 ether);

        comp.reward(50 ether);

        a.join(0);
        assertEq(comp.balanceOf(address(a)), 30 ether);
        assertEq(comp.balanceOf(address(b)),  0 ether);

        b.join(0);
        assertEq(comp.balanceOf(address(a)), 30 ether);
        assertEq(comp.balanceOf(address(b)), 20 ether);

        a.join(0); b.reap();
        assertEq(comp.balanceOf(address(a)), 30 ether);
        assertEq(comp.balanceOf(address(b)), 20 ether);

        comp.reward(50 ether);
        a.join(20 ether);
        a.join(0); b.reap();
        assertEq(comp.balanceOf(address(a)), 60 ether);
        assertEq(comp.balanceOf(address(b)), 40 ether);

        comp.reward(30 ether);
        a.join(0); b.reap();
        assertEq(comp.balanceOf(address(a)), 80 ether);
        assertEq(comp.balanceOf(address(b)), 50 ether);

        b.exit(20 ether);
    }

    // a user's balance can be altered with vat.flux, check that this
    // can only be disadvantageous
    function test_flux_transfer() public {
        Usr a = new Usr(join);
        Usr b = new Usr(join);
        usdc.transfer(address(a), 200 ether);

        a.join(100 ether);
        comp.reward(50 ether);

        a.join(0);
        assertEq(comp.balanceOf(address(a)), 50 ether);
        assertEq(comp.balanceOf(address(b)),  0 ether);

        comp.reward(50 ether);
        vat.flux(ilk, address(a), address(b), 50 ether);
        b.join(0);
        assertEq(comp.balanceOf(address(b)),  0 ether, "if nonzero we have a problem");
    }

    // flee is an emergency exit with no rewards, check that these are
    // not given out
    function test_flee() public {
        join.join(100 ether);
        assertEq(comp.balanceOf(self), 0 ether, "no initial rewards");

        comp.reward(10 ether);
        join.join(0);
        assertEq(comp.balanceOf(self), 10 ether, "rewards increase with reap");

        comp.reward(10 ether);
        join.exit(50 ether);
        assertEq(comp.balanceOf(self), 20 ether, "rewards increase with exit");

        comp.reward(10 ether);
        join.flee(50 ether);
        assertEq(comp.balanceOf(self), 20 ether, "rewards invariant over flee");
    }
}

contract Usr {
    CropJoin j;
    constructor(CropJoin join_) public {
        j = join_;
    }
    function join(uint wad) public {
        j.join(wad);
    }
    function exit(uint wad) public {
        j.exit(wad);
    }
    function reap() public {
        j.join(0);
    }
}
