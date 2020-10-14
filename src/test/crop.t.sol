pragma solidity ^0.6.7;
pragma experimental ABIEncoderV2;

import "./base.sol";

import "../cjoin.sol";

contract MockVat is VatLike {
    mapping (bytes32 => mapping (address => uint)) public override gem;
    function urns(bytes32,address) external override returns (Urn memory) {
        return Urn(0, 0);
    }
    function add(uint x, int y) internal pure returns (uint z) {
        z = x + uint(y);
        require(y >= 0 || z <= x);
        require(y <= 0 || z >= x);
    }
    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x);
    }
    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x);
    }
    function slip(bytes32 ilk, address usr, int256 wad) external override {
        gem[ilk][usr] = add(gem[ilk][usr], wad);
    }
    function flux(bytes32 ilk, address src, address dst, uint256 wad) external override {
        gem[ilk][src] = sub(gem[ilk][src], wad);
        gem[ilk][dst] = add(gem[ilk][dst], wad);
    }
}

contract Token {
    uint8 public decimals;
    mapping (address => uint) public balanceOf;
    mapping (address => mapping (address => uint)) public allowance;
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
    function mint(uint wad) public returns (uint) {
        mint(msg.sender, wad);
    }
}

contract cToken is Token {
    constructor(uint8 dec, uint wad) Token(dec, wad) public {}
    function underlying() public returns (address a) {}
    function balanceOfUnderlying(address owner) external returns (uint) {}
    function borrowBalanceStored(address account) external view returns (uint) {}
    function borrowBalanceCurrent(address account) external view returns (uint) {}
    function accrueInterest() external returns (uint) {}
    function seize(address liquidator, address borrower, uint seizeTokens) external returns (uint) {}
    function liquidateBorrow(address borrower, uint repayAmount, CToken cTokenCollateral) external returns (uint) {}
    function getAccountLiquidity(address account) public view returns (uint, uint, uint) {}
    function exchangeRateCurrent() external returns (uint) {}
    function borrowIndex() external returns (uint) {}
}

contract Troll {
    Token comp;
    constructor(address comp_) public {
        comp = Token(comp_);
    }
    mapping (address => uint) public compAccrued;
    function reward(address usr, uint wad) public {
        compAccrued[usr] += wad;
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
    function getAccountLiquidity(address) external returns (uint,uint,uint) {}
    function liquidateBorrowAllowed(
        address cTokenBorrowed,
        address cTokenCollateral,
        address liquidator,
        address borrower,
        uint repayAmount) external returns (uint) {}
}

contract ComptrollerStorage {
    struct Market {
        bool isListed;
        uint collateralFactorMantissa;
        mapping(address => bool) accountMembership;
        bool isComped;
    }
    mapping(address => Market) public markets;
}

contract CanJoin is CanCall {
    USDCJoin adapter;
    function can_exit(uint val) public returns (bool) {
        bytes memory call = abi.encodeWithSignature
            ("exit(uint256)", val);
        return can_call(address(adapter), call);
    }
    function can_wind(uint borrow, uint n, uint loan) public returns (bool) {
        bytes memory call = abi.encodeWithSignature
            ("wind(uint256,uint256,uint256)", borrow, n, loan);
        return can_call(address(adapter), call);
    }
    function can_unwind(uint repay, uint n, uint exit_, uint loan_) public returns (bool) {
        bytes memory call = abi.encodeWithSignature
            ("unwind(uint256,uint256,uint256,uint256)", repay, n, exit_, loan_);
        return can_call(address(adapter), call);
    }
    function can_unwind_exit(uint val) public returns (bool) {
        return can_unwind_exit(val, 0);
    }
    function can_unwind_exit(uint val, uint loan) public returns (bool) {
        return can_unwind(0, 1, val, loan);
    }
    function can_unwind(uint repay, uint n) public returns (bool) {
        return can_unwind(repay, n, 0, 0);
    }
}

contract Usr is CanJoin {
    constructor(USDCJoin join_) public {
        adapter = join_;
    }
    function approve(address coin, address usr) public {
        Token(coin).approve(usr, uint(-1));
    }
    function join(uint wad) public {
        adapter.join(wad);
    }
    function exit(uint wad) public {
        adapter.exit(wad);
    }
    function reap() public {
        adapter.join(0);
    }
    function flee() public {
        adapter.flee();
    }
    function unwind_exit(uint wad) public {
        adapter.unwind(0, 1, wad, 0);
    }
    function liquidateBorrow(address borrower, uint repayAmount) external
        returns (uint)
    {
        CToken ctoken = CToken(adapter.cgem());
        return ctoken.liquidateBorrow(borrower, repayAmount, ctoken);
    }
}

contract CropTestBase is TestBase, CanJoin {
    Token    usdc;
    cToken   cusdc;
    Token    comp;
    Troll    troll;
    MockVat  vat;
    address  self;
    bytes32  ilk = "usdc-c";

    function set_usdc(address usr, uint val) internal {
        hevm.store(
            address(usdc),
            keccak256(abi.encode(usr, uint256(9))),
            bytes32(uint(val))
        );
    }

    function init_user() internal returns (Usr a, Usr b) {
        a = new Usr(adapter);
        b = new Usr(adapter);

        usdc.transfer(address(a), 200 * 1e6);
        usdc.transfer(address(b), 200 * 1e6);

        a.approve(address(usdc), address(adapter));
        b.approve(address(usdc), address(adapter));
    }
}

// Here we test the basics of the adapter with push rewards
// and a mock vat
contract SimpleCropTest is CropTestBase {
    function setUp() public virtual {
        self  = address(this);
        usdc  = new Token(6, 1000 * 1e6);
        cusdc = new cToken(8,  0);
        comp  = new Token(18, 0);
        troll = new Troll(address(comp));
        vat   = new MockVat();
        adapter = new USDCJoin( address(vat)
                              , ilk
                              , address(usdc)
                              , address(cusdc)
                              , address(comp)
                              , address(troll)
                              );
    }

    function reward(address usr, uint wad) internal virtual {
        comp.mint(usr, wad);
    }

    function test_reward() public virtual {
        reward(self, 100 ether);
        assertEq(comp.balanceOf(self), 100 ether);
    }

    function test_simple_multi_user() public {
        (Usr a, Usr b) = init_user();

        a.join(60 * 1e6);
        b.join(40 * 1e6);

        reward(address(adapter), 50 * 1e18);

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

        reward(address(adapter), 50 * 1e18);

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
        usdc.approve(address(adapter), uint(-1));

        adapter.join(100 * 1e6);
        assertEq(comp.balanceOf(self), 0 * 1e18, "no initial rewards");

        reward(address(adapter), 10 * 1e18);
        adapter.join(0); adapter.join(0);  // have to do it twice for some comptroller reason
        assertEq(comp.balanceOf(self), 10 * 1e18, "rewards increase with reap");

        adapter.join(100 * 1e6);
        assertEq(comp.balanceOf(self), 10 * 1e18, "rewards invariant over join");

        adapter.exit(200 * 1e6);
        assertEq(comp.balanceOf(self), 10 * 1e18, "rewards invariant over exit");

        adapter.join(50 * 1e6);

        assertEq(comp.balanceOf(self), 10 * 1e18);
        reward(address(adapter), 10 * 1e18);
        adapter.join(10 * 1e6);
        assertEq(comp.balanceOf(self), 20 * 1e18);
    }
    function test_complex_scenario() public {
        (Usr a, Usr b) = init_user();

        a.join(60 * 1e6);
        b.join(40 * 1e6);

        reward(address(adapter), 50 * 1e18);

        a.join(0);
        assertEq(comp.balanceOf(address(a)), 30 * 1e18);
        assertEq(comp.balanceOf(address(b)),  0 * 1e18);

        b.join(0);
        assertEq(comp.balanceOf(address(a)), 30 * 1e18);
        assertEq(comp.balanceOf(address(b)), 20 * 1e18);

        a.join(0); b.reap();
        assertEq(comp.balanceOf(address(a)), 30 * 1e18);
        assertEq(comp.balanceOf(address(b)), 20 * 1e18);

        reward(address(adapter), 50 * 1e18);
        a.join(20 * 1e6);
        a.join(0); b.reap();
        assertEq(comp.balanceOf(address(a)), 60 * 1e18);
        assertEq(comp.balanceOf(address(b)), 40 * 1e18);

        reward(address(adapter), 30 * 1e18);
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
        reward(address(adapter), 50 * 1e18);

        a.join(0); a.join(0); // have to do it twice for some comptroller reason
        assertEq(comp.balanceOf(address(a)), 50 * 1e18, "rewards increase with reap");

        reward(address(adapter), 50 * 1e18);
        vat.flux(ilk, address(a), address(b), 50 * 1e18);
        b.join(0);
        assertEq(comp.balanceOf(address(b)),  0 * 1e18, "if nonzero we have a problem");
    }
    // if the users's balance has been altered with flux, check that
    // all parties can still exit
    function test_flux_exit() public {
        (Usr a, Usr b) = init_user();

        a.join(100 * 1e6);
        reward(address(adapter), 50 * 1e18);

        a.join(0); a.join(0); // have to do it twice for some comptroller reason
        assertEq(comp.balanceOf(address(a)), 50 * 1e18, "rewards increase with reap");

        reward(address(adapter), 50 * 1e18);
        vat.flux(ilk, address(a), address(b), 50 * 1e18);

        assertEq(usdc.balanceOf(address(a)), 100e6,  "a balance before exit");
        assertEq(adapter.stake(address(a)),     100e18, "a join balance before");
        a.exit(50 * 1e6);
        assertEq(usdc.balanceOf(address(a)), 150e6,  "a balance after exit");
        assertEq(adapter.stake(address(a)),      50e18, "a join balance after");

        assertEq(usdc.balanceOf(address(b)), 200e6,  "b balance before exit");
        assertEq(adapter.stake(address(b)),       0e18, "b join balance before");
        adapter.tack(address(a), address(b),     50e18);
        b.flee();
        assertEq(usdc.balanceOf(address(b)), 250e6,  "b balance after exit");
        assertEq(adapter.stake(address(b)),       0e18, "b join balance after");
    }
    function test_reap_after_flux() public {
        (Usr a, Usr b) = init_user();

        a.join(100 * 1e6);
        reward(address(adapter), 50 * 1e18);

        a.join(0); a.join(0); // have to do it twice for some comptroller reason
        assertEq(comp.balanceOf(address(a)), 50 * 1e18, "rewards increase with reap");

        assertTrue( a.can_exit( 50e6), "can exit before flux");
        vat.flux(ilk, address(a), address(b), 100e18);
        reward(address(adapter), 50e18);

        // if x gems are transferred from a to b, a will continue to earn
        // rewards on x, while b will not earn anything on x, until we
        // reset balances with `tack`
        assertTrue(!a.can_exit(100e6), "can't full exit after flux");
        assertEq(adapter.stake(address(a)),     100e18);
        a.exit(0);

        assertEq(comp.balanceOf(address(a)), 100e18, "can claim remaining rewards");

        reward(address(adapter), 50e18);
        a.exit(0);

        assertEq(comp.balanceOf(address(a)), 150e18, "rewards continue to accrue");

        assertEq(adapter.stake(address(a)),     100e18, "balance is unchanged");

        adapter.tack(address(a), address(b),    100e18);
        reward(address(adapter), 50e18);
        a.exit(0);

        assertEq(comp.balanceOf(address(a)), 150e18, "rewards no longer increase");

        assertEq(adapter.stake(address(a)),       0e18, "balance is zeroed");
        assertEq(comp.balanceOf(address(b)),   0e18, "b has no rewards yet");
        b.join(0);
        assertEq(comp.balanceOf(address(b)),  50e18, "b now receives rewards");
    }

    // flee is an emergency exit with no rewards, check that these are
    // not given out
    function test_flee() public {
        usdc.approve(address(adapter), uint(-1));

        adapter.join(100 * 1e6);
        assertEq(comp.balanceOf(self), 0 * 1e18, "no initial rewards");

        reward(address(adapter), 10 * 1e18);
        adapter.join(0); adapter.join(0);  // have to do it twice for some comptroller reason
        assertEq(comp.balanceOf(self), 10 * 1e18, "rewards increase with reap");

        reward(address(adapter), 10 * 1e18);
        adapter.exit(50 * 1e6);
        assertEq(comp.balanceOf(self), 20 * 1e18, "rewards increase with exit");

        reward(address(adapter), 10 * 1e18);
        assertEq(usdc.balanceOf(self),  950e6, "balance before flee");
        adapter.flee();
        assertEq(comp.balanceOf(self), 20 * 1e18, "rewards invariant over flee");
        assertEq(usdc.balanceOf(self), 1000e6, "balance after flee");
    }

    function test_tack() public {
        /*
           A user's pending rewards, assuming no further crop income, is
           given by

               stake[usr] * share - crops[usr]

           After join/exit we set

               crops[usr] = stake[usr] * share

           Such that the pending rewards are zero.

           With `tack` we transfer stake from one user to another, but
           we must ensure that we also either (a) transfer crops or
           (b) reap the rewards concurrently.

           Here we check that tack accounts for rewards appropriately,
           regardless of whether we use (a) or (b).
        */
        (Usr a, Usr b) = init_user();

        // concurrent reap
        a.join(100e6);
        reward(address(adapter), 50e18);

        a.join(0);
        vat.flux(ilk, address(a), address(b), 100e18);
        adapter.tack(address(a), address(b), 100e18);
        b.join(0);

        reward(address(adapter), 50e18);
        a.exit(0);
        b.exit(100e6);
        assertEq(comp.balanceOf(address(a)), 50e18, "a rewards");
        assertEq(comp.balanceOf(address(b)), 50e18, "b rewards");

        // crop transfer
        a.join(100e6);
        reward(address(adapter), 50e18);

        // a doesn't reap their rewards before flux so all their pending
        // rewards go to b
        vat.flux(ilk, address(a), address(b), 100e18);
        adapter.tack(address(a), address(b), 100e18);

        reward(address(adapter), 50e18);
        a.exit(0);
        b.exit(100e6);
        assertEq(comp.balanceOf(address(a)),  50e18, "a rewards alt");
        assertEq(comp.balanceOf(address(b)), 150e18, "b rewards alt");
    }
}

// Here we use a mock cToken, comptroller and vat
contract CropTest is SimpleCropTest {
    function setUp() public override virtual {
        self  = address(this);
        usdc  = new Token(6, 1000 * 1e6);
        cusdc = new cToken(8,  0);
        comp  = new Token(18, 0);
        troll = new Troll(address(comp));
        vat   = new MockVat();
        adapter = new USDCJoin( address(vat)
                              , ilk
                              , address(usdc)
                              , address(cusdc)
                              , address(comp)
                              , address(troll)
                              );
    }

    function reward(address usr, uint wad) internal override {
        troll.reward(usr, wad);
    }

    function test_reward() public override {
        reward(self, 100 ether);
        assertEq(troll.compAccrued(self), 100 ether);
    }
}

// Here we run the basic CropTest tests against mainnet, overriding
// the Comptroller to accrue us COMP on demand
contract CompTest is SimpleCropTest {
    function setUp() public override {
        self = address(this);
        vat  = new MockVat();

        usdc  =  Token(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
        cusdc =  cToken(0x39AA39c021dfbaE8faC545936693aC917d5E7563);
        comp  =  Token(0xc00e94Cb662C3520282E6f5717214004A7f26888);
        troll =  Troll(0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B);

        adapter = new USDCJoin( address(vat)
                              , ilk
                              , address(usdc)
                              , address(cusdc)
                              , address(comp)
                              , address(troll)
                              );

        // give ourselves some usdc
        set_usdc(address(this), 1000e6);

        hevm.roll(block.number + 10);
    }

    function reward(address usr, uint wad) internal override {
        // override compAccrued in the comptroller
        uint old = uint(hevm.load(
            address(troll),
            keccak256(abi.encode(usr, uint256(20)))
        ));
        hevm.store(
            address(troll),
            keccak256(abi.encode(usr, uint256(20))),
            bytes32(old + wad)
        );
    }
    function test_reward() public override {
        reward(self, 100 ether);
        assertEq(troll.compAccrued(self), 100 ether);
    }

    function test_borrower_index() public {
        assertEq(troll.compBorrowerIndex(address(cusdc), address(adapter)), 0);
    }

    function test_setup() public {
        assertEq(usdc.balanceOf(self), 1000 * 1e6, "hack the usdc");
    }

    function test_block_number() public {
        assertEq(troll.getBlockNumber(), block.number);
    }

    function test_join() public {
        usdc.approve(address(adapter), uint(-1));
        adapter.join(100 * 1e6);
    }
}

// Here we run some tests against the real Compound on mainnet
contract RealCompTest is CropTestBase {
    function setUp() public {
        self = address(this);
        vat  = new MockVat();

        usdc  =  Token(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
        cusdc =  cToken(0x39AA39c021dfbaE8faC545936693aC917d5E7563);
        comp  =  Token(0xc00e94Cb662C3520282E6f5717214004A7f26888);
        troll =  Troll(0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B);

        adapter = new USDCJoin( address(vat)
                              , ilk
                              , address(usdc)
                              , address(cusdc)
                              , address(comp)
                              , address(troll)
                              );

        // give ourselves some usdc
        set_usdc(address(this), 1000e6);

        hevm.roll(block.number + 10);

        usdc.approve(address(adapter), uint(-1));
    }

    function get_s() internal returns (uint256 cf) {
        require(cToken(address(cusdc)).accrueInterest() == 0);
        return cToken(address(cusdc)).balanceOfUnderlying(address(adapter));
    }
    function get_b() internal returns (uint256 cf) {
        require(cToken(address(cusdc)).accrueInterest() == 0);
        return cToken(address(cusdc)).borrowBalanceStored(address(adapter));
    }
    function get_cf() internal returns (uint256 cf) {
        require(cToken(address(cusdc)).accrueInterest() == 0);
        cf = wdiv(cToken(address(cusdc)).borrowBalanceStored(address(adapter)),
                  cToken(address(cusdc)).balanceOfUnderlying(address(adapter)));
    }

    function test_underlying() public {
        assertEq(cToken(address(cusdc)).underlying(), address(usdc));
    }

    function reward(uint256 tic) internal {
        log_named_uint("== elapse", tic);
        // accrue ~1 day of rewards
        hevm.warp(block.timestamp + tic);
        // unneeded?
        hevm.roll(block.number + tic / 15);
    }

    function test_reward_unwound() public {
        (Usr a,) = init_user();
        assertEq(comp.balanceOf(address(a)), 0 ether);

        a.join(100 * 1e6);
        assertEq(comp.balanceOf(address(a)), 0 ether);

        adapter.wind(0, 0, 0);

        reward(1 days);

        a.join(0);
        // ~ 0.012 COMP per year
        assertGt(comp.balanceOf(address(a)), 0.000025 ether);
        assertLt(comp.balanceOf(address(a)), 0.000045 ether);
    }

    function test_reward_wound() public {
        (Usr a,) = init_user();
        assertEq(comp.balanceOf(address(a)), 0 ether);

        a.join(100 * 1e6);
        assertEq(comp.balanceOf(address(a)), 0 ether);

        adapter.wind(50 * 10**6, 0, 0);

        reward(1 days);

        a.join(0);
        // ~ 0.035 COMP per year
        assertGt(comp.balanceOf(address(a)), 0.00008 ether);
        assertLt(comp.balanceOf(address(a)), 0.00011 ether);

        assertLt(get_cf(), adapter.maxf());
        assertLt(get_cf(), adapter.minf());
    }

    function test_reward_wound_fully() public {
        (Usr a,) = init_user();
        assertEq(comp.balanceOf(address(a)), 0 ether);

        a.join(100 * 1e6);
        assertEq(comp.balanceOf(address(a)), 0 ether);

        adapter.wind(0, 4, 0);

        reward(1 days);

        a.join(0);
        // ~ 0.11 COMP per year
        assertGt(comp.balanceOf(address(a)), 0.00015 ether);
        assertLt(comp.balanceOf(address(a)), 0.00035 ether);

        assertLt(get_cf(), adapter.maxf(), "cf < maxf");
        assertGt(get_cf(), adapter.minf(), "cf > minf");
    }

    function test_wind_unwind() public {
        require(cToken(address(cusdc)).accrueInterest() == 0);
        (Usr a,) = init_user();
        assertEq(comp.balanceOf(address(a)), 0 ether);

        a.join(100 * 1e6);
        assertEq(comp.balanceOf(address(a)), 0 ether);

        adapter.wind(0, 4, 0);

        reward(1 days);

        assertLt(get_cf(), adapter.maxf(), "under target");
        assertGt(get_cf(), adapter.minf(), "over minimum");

        log_named_uint("cf", get_cf());
        reward(1000 days);
        log_named_uint("cf", get_cf());

        assertGt(get_cf(), adapter.maxf(), "over target after interest");

        // unwind is used for deleveraging our position. Here we have
        // gone over the target due to accumulated interest, so we
        // unwind to bring us back under the target leverage.
        assertTrue( can_unwind(0, 1), "able to unwind if over target");
        adapter.unwind(0, 1, 0, 0);

        assertLt(get_cf(), adapter.maxf(), "under target post unwind");
        assertGt(get_cf(), adapter.minf(), "over minimum post unwind");
    }

    function test_unwind_multiple() public {
        adapter.join(100e6);

        set_cf(0.72e18);
        adapter.unwind(0, 1, 0, 0);
        log_named_uint("cf", get_cf());
        adapter.unwind(0, 1, 0, 0);
        log_named_uint("cf", get_cf());
        adapter.unwind(0, 1, 0, 0);
        log_named_uint("cf", get_cf());
        adapter.unwind(0, 1, 0, 0);
        log_named_uint("cf", get_cf());
        assertGt(get_cf(), 0.674e18);
        assertLt(get_cf(), 0.675e18);

        set_cf(0.72e18);
        adapter.unwind(0, 4, 0, 0);
        log_named_uint("cf", get_cf());
        assertGt(get_cf(), 0.674e18);
        assertLt(get_cf(), 0.675e18);
    }

    function test_flash_wind_necessary_loan() public {
        // given nav s0, we can calculate the minimum loan L needed to
        // effect a wind up to a given u',
        //
        //   L/s0 >= (u'/cf - 1 + u' - u*u'/cf) / [(1 - u') * (1 - u)]
        //
        // e.g. for u=0, u'=0.675, L/s0 ~= 1.77
        //
        // we can also write the maximum u' for a given L,
        //
        //   u' <= (1 + (1 - u) * L / s0) / (1 + (1 - u) * (L / s0 + 1 / cf))
        //
        // and the borrow to directly achieve a given u'
        //
        //   x = s0 (1 / (1 - u') - 1 / (1 - u))
        //
        // e.g. for u=0, u'=0.675, x/s0 ~= 2.0769
        //
        // here we test the u' that we achieve with given L

        (Usr a,) = init_user();
        a.join(100 * 1e6);

        assertTrue(!can_wind(207.69 * 1e6, 0, 176 * 1e6), "insufficient loan");
        assertTrue( can_wind(207.69 * 1e6, 0, 177 * 1e6), "sufficient loan");

        adapter.wind(207.69 * 1e6, 0, 177 * 1e6);
        log_named_uint("cf", get_cf());
        assertGt(get_cf(), 0.674e18);
        assertLt(get_cf(), 0.675e18);
    }

    function test_flash_wind_sufficient_loan() public {
        // we can also have wind determine the maximum borrow itself
        (Usr a,) = init_user();
        set_usdc(address(a), 900e6);

        a.join(100 * 1e6);
        adapter.wind(0, 1, 200 * 1e6);
        log_named_uint("cf", get_cf());
        assertGt(get_cf(), 0.674e18);
        assertLt(get_cf(), 0.675e18);

        a.join(100 * 1e6);
        logs("200");
        adapter.wind(0, 1, 200 * 1e6);
        log_named_uint("cf", get_cf());

        a.join(100 * 1e6);
        logs("100");
        adapter.wind(0, 1, 100 * 1e6);
        log_named_uint("cf", get_cf());

        a.join(100 * 1e6);
        logs("100");
        adapter.wind(0, 1, 100 * 1e6);
        log_named_uint("cf", get_cf());

        a.join(100 * 1e6);
        logs("150");
        adapter.wind(0, 1, 150 * 1e6);
        log_named_uint("cf", get_cf());

        a.join(100 * 1e6);
        logs("175");
        adapter.wind(0, 1, 175 * 1e6);
        log_named_uint("cf", get_cf());

        assertGt(get_cf(), 0.674e18);
        assertLt(get_cf(), 0.675e18);
    }
    // compare gas costs of a flash loan wind and a iteration wind
    function test_wind_gas_flash() public {
        (Usr a,) = init_user();

        a.join(100 * 1e6);
        uint gas_before = gasleft();
        adapter.wind(0, 1, 200 * 1e6);
        uint gas_after = gasleft();
        log_named_uint("s ", get_s());
        log_named_uint("b ", get_b());
        log_named_uint("s + b", get_s() + get_b());
        log_named_uint("cf", get_cf());
        assertGt(get_cf(), 0.674e18);
        assertLt(get_cf(), 0.675e18);
        log_named_uint("gas", gas_before - gas_after);
    }
    function test_wind_gas_iteration() public {
        (Usr a,) = init_user();

        a.join(100 * 1e6);
        uint gas_before = gasleft();
        adapter.wind(0, 5, 0);
        uint gas_after = gasleft();

        assertGt(get_cf(), 0.674e18);
        assertLt(get_cf(), 0.675e18);
        log_named_uint("s ", get_s());
        log_named_uint("b ", get_b());
        log_named_uint("s + b", get_s() + get_b());
        log_named_uint("cf", get_cf());
        log_named_uint("gas", gas_before - gas_after);
    }
    function test_wind_gas_partial_loan() public {
        (Usr a,) = init_user();

        a.join(100 * 1e6);
        uint gas_before = gasleft();
        adapter.wind(0, 3, 50e6);
        uint gas_after = gasleft();

        assertGt(get_cf(), 0.674e18);
        assertLt(get_cf(), 0.675e18);
        log_named_uint("s ", get_s());
        log_named_uint("b ", get_b());
        log_named_uint("s + b", get_s() + get_b());
        log_named_uint("cf", get_cf());
        log_named_uint("gas", gas_before - gas_after);
    }

    function set_cf(uint cf) internal {
        uint nav = adapter.nav();

        // desired supply and borrow in terms of underlying
        uint x = cusdc.exchangeRateCurrent();
        uint s = (nav * 1e18 / (1e18 - cf)) / 1e12;
        uint b = s * cf / 1e18 - 1;

        log_named_uint("nav  ", nav);
        log_named_uint("new s", s);
        log_named_uint("new b", b);
        log_named_uint("set u", cf);

        set_usdc(address(adapter), 0);
        // cusdc.accountTokens
        hevm.store(
            address(cusdc),
            keccak256(abi.encode(address(adapter), uint256(15))),
            bytes32((s * 1e18) / x)
        );
        // cusdc.accountBorrows.principal
        hevm.store(
            address(cusdc),
            keccak256(abi.encode(address(adapter), uint256(17))),
            bytes32(b)
        );
        // cusdc.accountBorrows.interestIndex
        hevm.store(
            address(cusdc),
            bytes32(uint(keccak256(abi.encode(address(adapter), uint256(17)))) + 1),
            bytes32(cusdc.borrowIndex())
        );

        log_named_uint("new u", get_cf());
        log_named_uint("nav  ", adapter.nav());
    }

    // wind / unwind make the underlying unavailable as it is deposited
    // into the ctoken. In order to exit we will have to free up some
    // underlying.
    function wound_unwind_exit(bool loan) public {
        adapter.join(100 * 1e6);

        assertEq(comp.balanceOf(self), 0 ether, "no initial rewards");

        set_cf(0.675e18);

        assertTrue(get_cf() < adapter.maxf(), "cf under target");
        assertTrue(get_cf() > adapter.minf(), "cf over minimum");

        // we can't exit as there is no available usdc
        assertTrue(!can_exit(10 * 1e6), "cannot 10% exit initially");

        // however we can exit with unwind
        assertTrue( can_unwind_exit(14.7 * 1e6), "ok exit with 14.7%");
        assertTrue(!can_unwind_exit(14.9 * 1e6), "no exit with 14.9%");

        if (loan) {
            // with a loan we can exit an extra (L * (1 - u) / u) ~= 0.481L
            assertTrue( can_unwind_exit(19.5 * 1e6, 10 * 1e6), "ok loan exit");
            assertTrue(!can_unwind_exit(19.7 * 1e6, 10 * 1e6), "no loan exit");

            log_named_uint("s ", CToken(address(cusdc)).balanceOfUnderlying(address(adapter)));
            log_named_uint("b ", CToken(address(cusdc)).borrowBalanceStored(address(adapter)));
            log_named_uint("u ", get_cf());

            uint prev = usdc.balanceOf(address(this));
            adapter.unwind(0, 1, 10 * 1e6,  10 * 1e6);
            assertEq(usdc.balanceOf(address(this)) - prev, 10 * 1e6);

            log_named_uint("s'", CToken(address(cusdc)).balanceOfUnderlying(address(adapter)));
            log_named_uint("b'", CToken(address(cusdc)).borrowBalanceStored(address(adapter)));
            log_named_uint("u'", get_cf());

        } else {
            log_named_uint("s ", CToken(address(cusdc)).balanceOfUnderlying(address(adapter)));
            log_named_uint("b ", CToken(address(cusdc)).borrowBalanceStored(address(adapter)));
            log_named_uint("u ", get_cf());

            uint prev = usdc.balanceOf(address(this));
            adapter.unwind(0, 1, 10 * 1e6, 0);
            assertEq(usdc.balanceOf(address(this)) - prev, 10 * 1e6);

            log_named_uint("s'", CToken(address(cusdc)).balanceOfUnderlying(address(adapter)));
            log_named_uint("b'", CToken(address(cusdc)).borrowBalanceStored(address(adapter)));
            log_named_uint("u'", get_cf());
        }
    }
    function test_unwind_exit() public {
        wound_unwind_exit(false);
    }
    function test_unwind_exit_with_loan() public {
        wound_unwind_exit(true);
    }
    function test_unwind_full_exit() public {
        adapter.join(100 * 1e6);
        set_cf(0.675e18);

        // we can unwind in a single cycle using a loan
        adapter.unwind(0, 1, 100e6 - 1e4, 177 * 1e6);

        adapter.join(100 * 1e6);
        set_cf(0.675e18);

        // or we can unwind by iteration without a loan
        adapter.unwind(0, 6, 100e6 - 1e4, 0);
    }
    function test_unwind_gas_flash() public {
        adapter.join(100 * 1e6);
        set_cf(0.675e18);
        uint gas_before = gasleft();
        adapter.unwind(0, 1, 100e6 - 1e4, 177e6);
        uint gas_after = gasleft();

        assertGt(get_cf(), 0.674e18);
        assertLt(get_cf(), 0.675e18);
        log_named_uint("s ", get_s());
        log_named_uint("b ", get_b());
        log_named_uint("s + b", get_s() + get_b());
        log_named_uint("cf", get_cf());
        log_named_uint("gas", gas_before - gas_after);
    }
    function test_unwind_gas_iteration() public {
        adapter.join(100 * 1e6);
        set_cf(0.675e18);
        uint gas_before = gasleft();
        adapter.unwind(0, 5, 100e6 - 1e4, 0);
        uint gas_after = gasleft();

        assertGt(get_cf(), 0.674e18);
        assertLt(get_cf(), 0.675e18);
        log_named_uint("s ", get_s());
        log_named_uint("b ", get_b());
        log_named_uint("s + b", get_s() + get_b());
        log_named_uint("cf", get_cf());
        log_named_uint("gas", gas_before - gas_after);
    }
    function test_unwind_gas_shallow() public {
        // we can withdraw a fraction of the pool without loans or
        // iterations
        adapter.join(100 * 1e6);
        set_cf(0.675e18);
        uint gas_before = gasleft();
        adapter.unwind(0, 1, 14e6, 0);
        uint gas_after = gasleft();

        assertGt(get_cf(), 0.674e18);
        assertLt(get_cf(), 0.675e18);
        log_named_uint("s ", get_s());
        log_named_uint("b ", get_b());
        log_named_uint("s + b", get_s() + get_b());
        log_named_uint("cf", get_cf());
        log_named_uint("gas", gas_before - gas_after);
    }

    // The nav of the adapter will drop over time, due to interest
    // accrual, check that this is well behaved.
    function test_nav_drop_with_interest() public {
        require(cToken(address(cusdc)).accrueInterest() == 0);
        (Usr a,) = init_user();

        adapter.join(600 * 1e6);

        assertEq(usdc.balanceOf(address(a)), 200 * 1e6);
        a.join(100 * 1e6);
        assertEq(usdc.balanceOf(address(a)), 100 * 1e6);
        assertEq(adapter.nps(), 1 ether, "initial nps is 1");

        log_named_uint("nps before wind   ", adapter.nps());
        adapter.wind(0, 4, 0);

        assertLt(get_cf(), adapter.maxf(), "under target");
        assertGt(get_cf(), adapter.minf(), "over minimum");

        log_named_uint("nps before interest", adapter.nps());
        reward(100 days);
        assertLt(adapter.nps(), 1e18, "nps falls after interest");
        log_named_uint("nps after interest ", adapter.nps());

        assertEq(usdc.balanceOf(address(a)), 100 * 1e6, "usdc before exit");
        assertEq(adapter.stake(address(a)), 100 ether, "balance before exit");

        uint max_usdc = mul(adapter.nps(), adapter.stake(address(a))) / 1e30;
        logs("===");
        log_named_uint("max usdc    ", max_usdc);
        log_named_uint("adapter.balance", adapter.stake(address(a)));
        log_named_uint("vat.gem     ", vat.gem(adapter.ilk(), address(a)));
        log_named_uint("usdc        ", usdc.balanceOf(address(adapter)));
        log_named_uint("cf", get_cf());
        logs("exit ===");
        a.unwind_exit(max_usdc);
        log_named_uint("nps after exit     ", adapter.nps());
        log_named_uint("adapter.balance", adapter.stake(address(a)));
        log_named_uint("adapter.balance", adapter.stake(address(a)) / 1e12);
        log_named_uint("vat.gem     ", vat.gem(adapter.ilk(), address(a)));
        log_named_uint("usdc        ", usdc.balanceOf(address(adapter)));
        log_named_uint("cf", get_cf());
        assertLt(usdc.balanceOf(address(a)), 200 * 1e6, "less usdc after");
        assertGt(usdc.balanceOf(address(a)), 199 * 1e6, "less usdc after");

        assertLt(adapter.stake(address(a)), 1e18/1e6, "zero balance after full exit");
    }
    function test_nav_drop_with_liquidation() public {
        require(cToken(address(cusdc)).accrueInterest() == 0);
        enable_seize(address(this));

        (Usr a,) = init_user();

        adapter.join(600 * 1e6);

        assertEq(usdc.balanceOf(address(a)), 200 * 1e6);
        a.join(100 * 1e6);
        assertEq(usdc.balanceOf(address(a)), 100 * 1e6);

        logs("wind===");
        adapter.wind(0, 4, 0);

        assertLt(get_cf(), adapter.maxf(), "under target");
        assertGt(get_cf(), adapter.minf(), "over minimum");

        uint liquidity; uint shortfall; uint supp; uint borr;
        supp = CToken(address(cusdc)).balanceOfUnderlying(address(adapter));
        borr = CToken(address(cusdc)).borrowBalanceStored(address(adapter));
        (, liquidity, shortfall) =
            troll.getAccountLiquidity(address(adapter));
        log_named_uint("cf  ", get_cf());
        log_named_uint("s  ", supp);
        log_named_uint("b  ", borr);
        log_named_uint("liquidity", liquidity);
        log_named_uint("shortfall", shortfall);

        uint nps_before = adapter.nps();
        logs("time...===");
        reward(5000 days);
        assertLt(adapter.nps(), nps_before, "nps falls after interest");

        supp = CToken(address(cusdc)).balanceOfUnderlying(address(adapter));
        borr = CToken(address(cusdc)).borrowBalanceStored(address(adapter));
        (, liquidity, shortfall) =
            troll.getAccountLiquidity(address(adapter));
        log_named_uint("cf' ", get_cf());
        log_named_uint("s' ", supp);
        log_named_uint("b' ", borr);
        log_named_uint("liquidity", liquidity);
        log_named_uint("shortfall", shortfall);

        cusdc.approve(address(cusdc), uint(-1));
        usdc.approve(address(cusdc), uint(-1));
        log_named_uint("allowance", cusdc.allowance(address(this), address(cusdc)));
        set_usdc(address(this), 1000e6);
        log_named_uint("usdc ", usdc.balanceOf(address(this)));
        log_named_uint("cusdc", cusdc.balanceOf(address(this)));
        require(cusdc.mint(100e6) == 0);
        logs("mint===");
        log_named_uint("usdc ", usdc.balanceOf(address(this)));
        log_named_uint("cusdc", cusdc.balanceOf(address(this)));
        logs("liquidate===");
        return;
        // liquidation is not possible for cusdc-cusdc pairs, as it is
        // blocked by a re-entrancy guard????
        uint repay = 20;  // units of underlying
        assertTrue(!can_call( address(cusdc)
                            , abi.encodeWithSignature(
                                "liquidateBorrow(address,uint256,address)",
                                address(adapter), repay, CToken(address(cusdc)))),
                  "can't perform liquidation");
        cusdc.liquidateBorrow(address(adapter), repay, CToken(address(cusdc)));

        supp = CToken(address(cusdc)).balanceOfUnderlying(address(adapter));
        borr = CToken(address(cusdc)).borrowBalanceStored(address(adapter));
        (, liquidity, shortfall) =
            troll.getAccountLiquidity(address(adapter));
        log_named_uint("cf' ", get_cf());
        log_named_uint("s' ", supp);
        log_named_uint("b' ", borr);
        log_named_uint("liquidity", liquidity);
        log_named_uint("shortfall", shortfall);

        // check how long it would take for us to get to 100% utilisation
        reward(30 * 365 days);
        log_named_uint("cf' ", get_cf());
        assertGt(get_cf(), 1e18, "cf > 1");
    }

    // allow the test contract to seize collateral from a borrower
    // (normally only cTokens can do this). This allows us to mock
    // liquidations.
    function enable_seize(address usr) internal {
        hevm.store(
            address(troll),
            keccak256(abi.encode(usr, uint256(9))),
            bytes32(uint256(1))
        );
    }
    // comptroller expects this to be available if we're pretending to
    // be a cToken
    function comptroller() external returns (address) {
        return address(troll);
    }
    function test_enable_seize() public {
        ComptrollerStorage stroll = ComptrollerStorage(address(troll));
        bool isListed;
        (isListed,,) = stroll.markets(address(this));
        assertTrue(!isListed);

        enable_seize(address(this));

        (isListed,,) = stroll.markets(address(this));
        assertTrue(isListed);
    }
    function test_can_seize() public {
        enable_seize(address(this));

        adapter.join(100 * 1e6);
        adapter.wind(0, 4, 0);

        uint seize = 100 * 1e8;

        uint cusdc_before = cusdc.balanceOf(address(adapter));
        assertEq(cusdc.balanceOf(address(this)), 0, "no cusdc before");

        uint s = CToken(address(cusdc)).seize(address(this), address(adapter), seize);
        assertEq(s, 0, "seize successful");

        uint cusdc_after = cusdc.balanceOf(address(adapter));
        assertEq(cusdc.balanceOf(address(this)), seize, "cusdc after");
        assertEq(cusdc_before - cusdc_after, seize, "join supply decreased");
    }
    function test_nav_drop_with_seizure() public {
        enable_seize(address(this));

        (Usr a,) = init_user();

        adapter.join(600 * 1e6);
        a.join(100 * 1e6);
        log_named_uint("nps", adapter.nps());
        log_named_uint("usdc ", usdc.balanceOf(address(adapter)));
        log_named_uint("cusdc", cusdc.balanceOf(address(adapter)));

        logs("wind===");
        adapter.wind(0, 4, 0);
        log_named_uint("nps", adapter.nps());
        log_named_uint("cf", get_cf());
        log_named_uint("adapter usdc ", usdc.balanceOf(address(adapter)));
        log_named_uint("adapter cusdc", cusdc.balanceOf(address(adapter)));
        log_named_uint("adapter nav  ", adapter.nav());
        log_named_uint("a max usdc    ", mul(adapter.stake(address(a)), adapter.nps()) / 1e18);

        assertLt(get_cf(), adapter.maxf(), "under target");
        assertGt(get_cf(), adapter.minf(), "over minimum");

        logs("seize===");
        uint seize = 350 * 1e6 * 1e18 / cusdc.exchangeRateCurrent();
        log_named_uint("seize", seize);
        uint s = CToken(address(cusdc)).seize(address(this), address(adapter), seize);
        assertEq(s, 0, "seize successful");
        log_named_uint("nps", adapter.nps());
        log_named_uint("cf", get_cf());
        log_named_uint("adapter usdc ", usdc.balanceOf(address(adapter)));
        log_named_uint("adapter cusdc", cusdc.balanceOf(address(adapter)));
        log_named_uint("adapter nav  ", adapter.nav());
        log_named_uint("a max usdc    ", mul(adapter.stake(address(a)), adapter.nps()) / 1e18);

        assertLt(adapter.nav(), 350 * 1e18, "nav is halved");
    }
}
