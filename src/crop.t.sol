pragma solidity ^0.6.7;

import "ds-test/test.sol";

import "./crop.sol";

contract Token {
    uint8 public decimals;
    mapping (address => uint) public balanceOf;
    constructor(uint8 dec, uint wad) public {
        decimals = dec;
        balanceOf[msg.sender] = wad;
    }
    function transfer(address usr, uint wad) public returns (bool) {
        require(balanceOf[msg.sender] >= wad, "transfer/insufficient");
        balanceOf[msg.sender] -= wad;
        balanceOf[usr] += wad;
        return true;
    }
    function transferFrom(address src, address dst, uint wad) public returns (bool) {
        require(balanceOf[src] >= wad, "transferFrom/insufficient");
        balanceOf[src] -= wad;
        balanceOf[dst] += wad;
        return true;
    }
    function mint(address dst, uint wad) public {
        balanceOf[dst] += wad;
    }
}

contract Troll is Token(18, 0) {
    Token comp;
    constructor(address comp_) public {
        comp = Token(comp_);
    }
    uint256 public rewards;
    function reward(uint val) public {
        rewards += val;
    }
    function claimComp(address[] memory, address[] memory, bool, bool) public {
        comp.mint(msg.sender, rewards);
        rewards = 0;
    }
    function claimComp() public {
        comp.mint(msg.sender, rewards);
        rewards = 0;
    }
    function enterMarkets(address[] memory _) public {}
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
    Token    cusdc;
    Token    comp;
    Troll    troll;
    MockVat  vat;
    CropJoin join;
    address  self;
    bytes32  ilk = "cusdc";

    function setUp() public {
        self  = address(this);
        usdc  = new Token(6, 1000 ether);
        cusdc = new Token(8,  0);
        comp  = new Token(18, 0);
        troll = new Troll(address(comp));
        vat   = new MockVat();
        join  = new CropJoin( address(vat)
                            , ilk
                            , address(usdc)
                            , address(cusdc)
                            , address(comp)
                            , address(troll)
                            );
    }

    function test_simple_multi_user() public {
        Usr a = new Usr(join);
        Usr b = new Usr(join);
        usdc.transfer(address(a), 200 ether);
        usdc.transfer(address(b), 200 ether);

        a.join(60 ether);
        b.join(40 ether);

        troll.reward(50 ether);

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

        troll.reward(50 ether);

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

        troll.reward(10 ether);
        join.join(0);
        assertEq(comp.balanceOf(self), 10 ether, "rewards increase with reap");

        join.join(100 ether);
        assertEq(comp.balanceOf(self), 10 ether, "rewards invariant over join");

        join.exit(200 ether);
        assertEq(comp.balanceOf(self), 10 ether, "rewards invariant over exit");

        join.join(50 ether);

        assertEq(comp.balanceOf(self), 10 ether);
        troll.reward(10 ether);
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

        troll.reward(50 ether);

        a.join(0);
        assertEq(comp.balanceOf(address(a)), 30 ether);
        assertEq(comp.balanceOf(address(b)),  0 ether);

        b.join(0);
        assertEq(comp.balanceOf(address(a)), 30 ether);
        assertEq(comp.balanceOf(address(b)), 20 ether);

        a.join(0); b.reap();
        assertEq(comp.balanceOf(address(a)), 30 ether);
        assertEq(comp.balanceOf(address(b)), 20 ether);

        troll.reward(50 ether);
        a.join(20 ether);
        a.join(0); b.reap();
        assertEq(comp.balanceOf(address(a)), 60 ether);
        assertEq(comp.balanceOf(address(b)), 40 ether);

        troll.reward(30 ether);
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
        troll.reward(50 ether);

        a.join(0);
        assertEq(comp.balanceOf(address(a)), 50 ether);
        assertEq(comp.balanceOf(address(b)),  0 ether);

        troll.reward(50 ether);
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
