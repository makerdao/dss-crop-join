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
    function approve(address usr, uint wad) public {
    }
}

contract Troll {
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
    bytes32  ilk = "usdc-c";

    function setUp() public virtual {
        self  = address(this);
        usdc  = new Token(6, 1000 * 1e6);
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

    function init_user() internal returns (Usr a, Usr b) {
        a = new Usr(join);
        b = new Usr(join);

        usdc.transfer(address(a), 200 * 1e6);
        usdc.transfer(address(b), 200 * 1e6);

        a.approve(address(usdc), address(join));
        b.approve(address(usdc), address(join));
    }

    function test_simple_multi_user() public {
        (Usr a, Usr b) = init_user();

        a.join(60 * 1e6);
        b.join(40 * 1e6);

        troll.reward(50 * 1e18);

        a.join(0);
        assertEq(comp.balanceOf(address(a)), 30 * 1e18);
        assertEq(comp.balanceOf(address(b)),  0 * 1e18);

        b.join(0);
        assertEq(comp.balanceOf(address(a)), 30 * 1e18);
        assertEq(comp.balanceOf(address(b)), 20 * 1e18);
    }
    function test_simple_multi_reap() public {
        (Usr a, Usr b) = init_user();

        a.join(60 * 1e6);
        b.join(40 * 1e6);

        troll.reward(50 * 1e18);

        a.join(0);
        assertEq(comp.balanceOf(address(a)), 30 * 1e18);
        assertEq(comp.balanceOf(address(b)),  0 * 1e18);

        b.join(0);
        assertEq(comp.balanceOf(address(a)), 30 * 1e18);
        assertEq(comp.balanceOf(address(b)), 20 * 1e18);

        a.join(0); b.reap();
        assertEq(comp.balanceOf(address(a)), 30 * 1e18);
        assertEq(comp.balanceOf(address(b)), 20 * 1e18);
    }
    function test_simple_join_exit() public {
        join.join(100 * 1e6);
        assertEq(comp.balanceOf(self), 0 * 1e18, "no initial rewards");

        troll.reward(10 * 1e18);
        join.join(0);
        assertEq(comp.balanceOf(self), 10 * 1e18, "rewards increase with reap");

        join.join(100 * 1e6);
        assertEq(comp.balanceOf(self), 10 * 1e18, "rewards invariant over join");

        join.exit(200 * 1e6);
        assertEq(comp.balanceOf(self), 10 * 1e18, "rewards invariant over exit");

        join.join(50 * 1e6);

        assertEq(comp.balanceOf(self), 10 * 1e18);
        troll.reward(10 * 1e18);
        join.join(10 * 1e6);
        assertEq(comp.balanceOf(self), 20 * 1e18);
    }
    function test_complex_scenario() public {
        (Usr a, Usr b) = init_user();

        a.join(60 * 1e6);
        b.join(40 * 1e6);

        troll.reward(50 * 1e18);

        a.join(0);
        assertEq(comp.balanceOf(address(a)), 30 * 1e18);
        assertEq(comp.balanceOf(address(b)),  0 * 1e18);

        b.join(0);
        assertEq(comp.balanceOf(address(a)), 30 * 1e18);
        assertEq(comp.balanceOf(address(b)), 20 * 1e18);

        a.join(0); b.reap();
        assertEq(comp.balanceOf(address(a)), 30 * 1e18);
        assertEq(comp.balanceOf(address(b)), 20 * 1e18);

        troll.reward(50 * 1e18);
        a.join(20 * 1e6);
        a.join(0); b.reap();
        assertEq(comp.balanceOf(address(a)), 60 * 1e18);
        assertEq(comp.balanceOf(address(b)), 40 * 1e18);

        troll.reward(30 * 1e18);
        a.join(0); b.reap();
        assertEq(comp.balanceOf(address(a)), 80 * 1e18);
        assertEq(comp.balanceOf(address(b)), 50 * 1e18);

        b.exit(20 * 1e6);
    }

    // a user's balance can be altered with vat.flux, check that this
    // can only be disadvantageous
    function test_flux_transfer() public {
        (Usr a, Usr b) = init_user();

        a.join(100 * 1e6);
        troll.reward(50 * 1e18);

        a.join(0);
        assertEq(comp.balanceOf(address(a)), 50 * 1e18);
        assertEq(comp.balanceOf(address(b)),  0 * 1e18);

        troll.reward(50 * 1e18);
        vat.flux(ilk, address(a), address(b), 50 * 1e18);
        b.join(0);
        assertEq(comp.balanceOf(address(b)),  0 * 1e18, "if nonzero we have a problem");
    }

    // flee is an emergency exit with no rewards, check that these are
    // not given out
    function test_flee() public {
        join.join(100 * 1e6);
        assertEq(comp.balanceOf(self), 0 * 1e18, "no initial rewards");

        troll.reward(10 * 1e18);
        join.join(0);
        assertEq(comp.balanceOf(self), 10 * 1e18, "rewards increase with reap");

        troll.reward(10 * 1e18);
        join.exit(50 * 1e6);
        assertEq(comp.balanceOf(self), 20 * 1e18, "rewards increase with exit");

        troll.reward(10 * 1e18);
        join.flee(50 * 1e6);
        assertEq(comp.balanceOf(self), 20 * 1e18, "rewards invariant over flee");
    }
}

interface Hevm {
    function warp(uint256) external;
    function store(address,bytes32,bytes32) external;
}

contract CompTest is CropTest {
    Hevm hevm = Hevm(address(bytes20(uint160(uint256(keccak256('hevm cheat code'))))));

    function setUp() public override {
        self = address(this);
        vat  = new MockVat();

        usdc  =  Token(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
        cusdc =  Token(0x39AA39c021dfbaE8faC545936693aC917d5E7563);
        comp  =  Token(0xc00e94Cb662C3520282E6f5717214004A7f26888);
        troll =  Troll(0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B);

        join = new CropJoin( address(vat)
                           , ilk
                           , address(usdc)
                           , address(cusdc)
                           , address(comp)
                           , address(troll)
                           );

        // give ourselves some usdc
        hevm.store(
            address(usdc),
            keccak256(abi.encode(address(this), uint256(9))),
            bytes32(uint(1000 * 1e6))
        );
    }

    function test_setup() public {
        assertEq(usdc.balanceOf(self), 1000 * 1e6, "hack the usdc");
    }

    function test_join() public {
        usdc.approve(address(join), uint(-1));
        join.join(100 * 1e6);
    }
}

contract Usr {
    CropJoin j;
    constructor(CropJoin join_) public {
        j = join_;
    }
    function approve(address coin, address usr) public {
        Token(coin).approve(usr, uint(-1));
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
