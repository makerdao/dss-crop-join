pragma solidity 0.6.12;

import "./base.sol";

import "../sushi.sol";

interface SushiLPLike is ERC20 {
    function mint(address to) external returns (uint256);
    function token0() external view returns (address);
    function token1() external view returns (address);
}

contract MockVat {
    mapping (bytes32 => mapping (address => uint)) public gem;
    function urns(bytes32,address) external returns (uint256, uint256) {
        return (0, 0);
    }
    function add(uint x, int y) internal pure returns (uint z) {
        z = x + uint(y);
        require(y >= 0 || z <= x, "vat/add-fail");
        require(y <= 0 || z >= x, "vat/add-fail");
    }
    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x, "vat/add-fail");
    }
    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x, "vat/sub-fail");
    }
    function slip(bytes32 ilk, address usr, int256 wad) external {
        gem[ilk][usr] = add(gem[ilk][usr], wad);
    }
    function flux(bytes32 ilk, address src, address dst, uint256 wad) external {
        gem[ilk][src] = sub(gem[ilk][src], wad);
        gem[ilk][dst] = add(gem[ilk][dst], wad);
    }
    function hope(address usr) external {}
}

contract Usr {
    Hevm hevm;
    SushiJoin adapter;
    SushiLPLike pair;
    ERC20 wbtc;
    ERC20 weth;
    constructor(Hevm hevm_, SushiJoin join_, SushiLPLike pair_) public {
        hevm = hevm_;
        adapter = join_;
        pair = pair_;
        wbtc = ERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
        weth = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    }
    function approve(address usr, uint256 amount) public {
        pair.approve(usr, amount);
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
    function set_wbtc(uint val) internal {
        hevm.store(
            address(wbtc),
            keccak256(abi.encode(address(this), uint256(0))),
            bytes32(uint(val))
        );
    }
    function set_weth(uint val) internal {
        hevm.store(
            address(weth),
            keccak256(abi.encode(address(this), uint256(3))),
            bytes32(uint(val))
        );
    }
    function mintLPTokens(uint wbtcVal, uint wethVal) public {
        set_wbtc(wbtcVal);
        set_weth(wethVal);
        wbtc.transfer(address(pair), wbtcVal);
        weth.transfer(address(pair), wethVal);
        pair.mint(address(this));
    }
    function getLPBalance() public view returns (uint256) {
        return pair.balanceOf(address(this));
    }
}

// Mainnet tests against SushiSwap
contract SushiTest is TestBase {

    SushiLPLike pair;
    ERC20 sushi;
    MasterChefLike masterchef;
    MockVat vat;
    address self;
    bytes32 ilk = "SUSHIWBTCETH-A";
    SushiJoin join;
    Usr user1;
    Usr user2;

    function setUp() public {
        self = address(this);
        vat = new MockVat();

        pair = SushiLPLike(0xCEfF51756c56CeFFCA006cD410B03FFC46dd3a58);
        sushi = ERC20(0x6B3595068778DD592e39A122f4f5a5cF09C90fE2);
        masterchef = MasterChefLike(0xc2EdaD668740f1aA35E4D8f227fB8E17dcA888Cd);

        uint numPools = masterchef.poolLength();
        uint pid = uint(-1);
        for (uint i = 0; i < numPools; i++) {
            (address lpToken,,,) = masterchef.poolInfo(i);
            if (lpToken == address(pair)) {
                pid = i;

                break;
            }
        }
        assertTrue(pid != uint(-1));

        join = new SushiJoin(address(vat), ilk, address(pair), address(sushi), address(masterchef), pid);
        user1 = new Usr(hevm, join, pair);
        user2 = new Usr(hevm, join, pair);
        user1.mintLPTokens(10**8, 10 ether);
        user2.mintLPTokens(10**8, 10 ether);

        assertTrue(user1.getLPBalance() > 0);
        assertTrue(user2.getLPBalance() > 0);

        //hevm.roll(block.number + 10);
    }

    function test_join() public {
        uint256 lpTokens = user1.getLPBalance();
        user1.approve(address(join), uint(-1));

        assertEq(pair.balanceOf(address(join)), 0);
        uint256 rewardsBal = pair.balanceOf(address(masterchef));

        user1.join(lpTokens);

        assertEq(pair.balanceOf(address(join)), 0);
        assertEq(pair.balanceOf(address(masterchef)) - rewardsBal, lpTokens);
    }

    function test_exit() public {
        uint256 lpTokens = user1.getLPBalance();
        user1.approve(address(join), uint(-1));

        uint256 rewardsBal = pair.balanceOf(address(masterchef));

        user1.join(lpTokens);
        user1.exit(lpTokens);

        assertEq(user1.getLPBalance(), lpTokens);
        assertEq(pair.balanceOf(address(masterchef)) - rewardsBal, 0);
    }

    function test_rewards() public {
        uint256 lpTokens = user1.getLPBalance();
        user1.approve(address(join), uint(-1));
        user1.join(lpTokens);

        assertEq(sushi.balanceOf(address(user1)), 0);
        assertEq(sushi.balanceOf(address(join)), 0);

        hevm.roll(block.number + 100);

        // Trigger a crop into the join adapter
        user2.exit(0);

        uint256 rewardsSushi = sushi.balanceOf(address(join));
        uint256 roundingError = 10;
        assertEq(sushi.balanceOf(address(user1)), 0);
        assertEq(sushi.balanceOf(address(user2)), 0);
        assertTrue(rewardsSushi > 0);

        // Exit just the rewards to user1
        user1.exit(0);
        assertTrue(sushi.balanceOf(address(user1)) >= rewardsSushi - roundingError);
        assertEq(sushi.balanceOf(address(user2)), 0);
        assertTrue(sushi.balanceOf(address(join)) <= roundingError);

        // Pull out the LP tokens
        user1.exit(lpTokens);
        assertTrue(sushi.balanceOf(address(user1)) >= rewardsSushi - roundingError);
        assertEq(user1.getLPBalance(), lpTokens);
    }

    function test_cage() public {
        uint256 lpTokens1 = user1.getLPBalance();
        user1.approve(address(join), uint(-1));
        user1.join(lpTokens1);

        uint256 lpTokens2 = user2.getLPBalance();
        user2.approve(address(join), uint(-1));
        user2.join(lpTokens2);

        hevm.roll(block.number + 100);

        user2.exit(lpTokens2);
        assertEq(user2.getLPBalance(), lpTokens2);

        hevm.roll(block.number + 200);

        // Emergency situation -- need to cage
        join.cage();

        assertEq(pair.balanceOf(address(join)), lpTokens1);
        assertEq(pair.balanceOf(address(join)), join.total());

        user1.flee();

        assertEq(pair.balanceOf(address(join)), 0);
        assertEq(user1.getLPBalance(), lpTokens1);
    }

    function testFail_cage_join() public {
        join.cage();
        uint256 lpTokens = user1.getLPBalance();
        user1.approve(address(join), uint(-1));
        user1.join(lpTokens);
    }
}
