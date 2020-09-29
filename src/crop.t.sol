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
    function mint(address dst, uint wad) public returns (uint) {
        balanceOf[dst] += wad;
    }
    function approve(address usr, uint wad) public returns (bool) {
    }
}

abstract contract cToken is Token {
    function underlying() public returns (address a) {}
}

contract Troll {
    Token comp;
    constructor(address comp_) public {
        comp = Token(comp_);
    }
    mapping (address => uint) public compAccrued;
    function reward(address usr, uint wad) public {
        compAccrued[usr] = wad;
    }
    function claimComp(address[] memory, address[] memory, bool, bool) public {
        comp.mint(msg.sender, compAccrued[msg.sender]);
        compAccrued[msg.sender] = 0;
    }
    function claimComp() public {
        comp.mint(msg.sender, compAccrued[msg.sender]);
        compAccrued[msg.sender] = 0;
    }
    function enterMarkets(address[] memory ctokens) public returns (uint[] memory) {
        comp; ctokens;
        uint[] memory err = new uint[](1);
        err[0] = 0;
        return err;
    }
    function compBorrowerIndex(address c, address b) public returns (uint) {}
    function mintAllowed(address ctoken, address minter, uint256 mintAmount) public returns (uint) {}
    function getBlockNumber() public view returns (uint) {
        return block.number;
    }
}


contract CropTestBase is DSTest {
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

    function init_user() internal returns (Usr a, Usr b) {
        a = new Usr(join);
        b = new Usr(join);

        usdc.transfer(address(a), 200 * 1e6);
        usdc.transfer(address(b), 200 * 1e6);

        a.approve(address(usdc), address(join));
        b.approve(address(usdc), address(join));
    }
}

contract CropTest is CropTestBase {
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

    function reward(address usr, uint wad) internal virtual {
        troll.reward(usr, wad);
    }

    function test_reward() public {
        reward(self, 100 ether);
        assertEq(troll.compAccrued(self), 100 ether);
    }

    function test_simple_multi_user() public {
        (Usr a, Usr b) = init_user();

        a.join(60 * 1e6);
        b.join(40 * 1e6);

        reward(address(join), 50 * 1e18);

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

        reward(address(join), 50 * 1e18);

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
        usdc.approve(address(join), uint(-1));

        join.join(100 * 1e6);
        assertEq(comp.balanceOf(self), 0 * 1e18, "no initial rewards");

        reward(address(join), 10 * 1e18);
        join.join(0); join.join(0);  // have to do it twice for some comptroller reason
        assertEq(comp.balanceOf(self), 10 * 1e18, "rewards increase with reap");

        join.join(100 * 1e6);
        assertEq(comp.balanceOf(self), 10 * 1e18, "rewards invariant over join");

        join.exit(200 * 1e6);
        assertEq(comp.balanceOf(self), 10 * 1e18, "rewards invariant over exit");

        join.join(50 * 1e6);

        assertEq(comp.balanceOf(self), 10 * 1e18);
        reward(address(join), 10 * 1e18);
        join.join(10 * 1e6);
        assertEq(comp.balanceOf(self), 20 * 1e18);
    }
    function test_complex_scenario() public {
        (Usr a, Usr b) = init_user();

        a.join(60 * 1e6);
        b.join(40 * 1e6);

        reward(address(join), 50 * 1e18);

        a.join(0);
        assertEq(comp.balanceOf(address(a)), 30 * 1e18);
        assertEq(comp.balanceOf(address(b)),  0 * 1e18);

        b.join(0);
        assertEq(comp.balanceOf(address(a)), 30 * 1e18);
        assertEq(comp.balanceOf(address(b)), 20 * 1e18);

        a.join(0); b.reap();
        assertEq(comp.balanceOf(address(a)), 30 * 1e18);
        assertEq(comp.balanceOf(address(b)), 20 * 1e18);

        reward(address(join), 50 * 1e18);
        a.join(20 * 1e6);
        a.join(0); b.reap();
        assertEq(comp.balanceOf(address(a)), 60 * 1e18);
        assertEq(comp.balanceOf(address(b)), 40 * 1e18);

        reward(address(join), 30 * 1e18);
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
        reward(address(join), 50 * 1e18);

        a.join(0); a.join(0); // have to do it twice for some comptroller reason
        assertEq(comp.balanceOf(address(a)), 50 * 1e18, "rewards increase with reap");

        reward(address(join), 50 * 1e18);
        vat.flux(ilk, address(a), address(b), 50 * 1e18);
        b.join(0);
        assertEq(comp.balanceOf(address(b)),  0 * 1e18, "if nonzero we have a problem");
    }

    // flee is an emergency exit with no rewards, check that these are
    // not given out
    function test_flee() public {
        usdc.approve(address(join), uint(-1));

        join.join(100 * 1e6);
        assertEq(comp.balanceOf(self), 0 * 1e18, "no initial rewards");

        reward(address(join), 10 * 1e18);
        join.join(0); join.join(0);  // have to do it twice for some comptroller reason
        assertEq(comp.balanceOf(self), 10 * 1e18, "rewards increase with reap");

        reward(address(join), 10 * 1e18);
        join.exit(50 * 1e6);
        assertEq(comp.balanceOf(self), 20 * 1e18, "rewards increase with exit");

        reward(address(join), 10 * 1e18);
        join.flee(50 * 1e6);
        assertEq(comp.balanceOf(self), 20 * 1e18, "rewards invariant over flee");
    }
}

interface Hevm {
    function warp(uint256) external;
    function roll(uint256) external;
    function store(address,bytes32,bytes32) external;
}


// Here we run the basic CropTest tests against mainnet, overriding
// the Comptroller to accrue us COMP on demand
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

        hevm.roll(block.number + 10);
    }

    function reward(address usr, uint wad) internal override {
        // override compAccrued in the comptroller
        hevm.store(
            address(troll),
            keccak256(abi.encode(usr, uint256(20))),
            bytes32(wad)
        );
    }

    function test_borrower_index() public {
        assertEq(troll.compBorrowerIndex(address(cusdc), address(join)), 0);
    }

    function test_setup() public {
        assertEq(usdc.balanceOf(self), 1000 * 1e6, "hack the usdc");
    }

    function test_block_number() public {
        assertEq(troll.getBlockNumber(), block.number);
    }

    function test_join() public {
        usdc.approve(address(join), uint(-1));
        join.join(100 * 1e6);
    }
}

// Here we run some tests against the real Compound on mainnet
contract RealCompTest is CropTestBase {
    Hevm hevm = Hevm(address(bytes20(uint160(uint256(keccak256('hevm cheat code'))))));

    function setUp() public {
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

        hevm.roll(block.number + 10);
    }

    function test_underlying() public {
        assertEq(cToken(address(cusdc)).underlying(), address(usdc));
    }

    function reward() internal {
        // accrue ~1 day of rewards
        hevm.warp(block.timestamp + 60 * 60 * 24);
        // unneeded?
        hevm.roll(block.number + 5760);
    }

    function test_reward_unwound() public {
        (Usr a, Usr b) = init_user();
        assertEq(comp.balanceOf(address(a)), 0 ether);

        a.join(100 * 1e6);
        assertEq(comp.balanceOf(address(a)), 0 ether);

        join.wind(0, 0);

        reward();

        a.join(0);
        // ~ 1.5 COMP per year
        assert(comp.balanceOf(address(a)) > 0.00003 ether);
    }

    function test_reward_wound() public {
        (Usr a, Usr b) = init_user();
        assertEq(comp.balanceOf(address(a)), 0 ether);

        a.join(100 * 1e6);
        assertEq(comp.balanceOf(address(a)), 0 ether);

        join.wind(50 * 10**6, 0);

        reward();

        a.join(0);
        // try removing this line:
        assertEq(comp.balanceOf(address(a)), 10 ether);
        // ???
        assertTrue(comp.balanceOf(address(a)) > 0.00004 ether);
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
