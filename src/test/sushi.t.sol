pragma solidity ^0.6.7;
pragma experimental ABIEncoderV2;

import "./base.sol";

import "../sushi.sol";

interface SushiLPLike is ERC20 {
    function mint(address to) external returns (uint256);
    function token0() external view returns (address);
    function token1() external view returns (address);
}

contract MockVat is VatLike {
    mapping (bytes32 => mapping (address => uint)) public override gem;
    function urns(bytes32,address) external override returns (Urn memory) {
        return Urn(0, 0);
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
    function slip(bytes32 ilk, address usr, int256 wad) external override {
        gem[ilk][usr] = add(gem[ilk][usr], wad);
    }
    function flux(bytes32 ilk, address src, address dst, uint256 wad) external override {
        gem[ilk][src] = sub(gem[ilk][src], wad);
        gem[ilk][dst] = add(gem[ilk][dst], wad);
    }
    function hope(address usr) external {}
}

contract CanJoin is CanCall {
    SushiJoin  adapter;
    function can_exit(uint val) public returns (bool) {
        bytes memory call = abi.encodeWithSignature
            ("exit(uint256)", val);
        return can_call(address(adapter), call);
    }
}

contract Usr is CanJoin {
    Hevm hevm;
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
contract SushiTest is TestBase, CanJoin {

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
        log_named_uint("numPools", numPools);
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
        user1.approve(address(adapter), uint(-1));
        adapter.join(lpTokens);
    }
}
