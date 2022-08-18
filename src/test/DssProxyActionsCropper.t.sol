pragma solidity ^0.6.12;

import "ds-test/test.sol";

import "../DssProxyActionsCropper.sol";
import {Cropper, CropperImp} from "../Cropper.sol";
import {CdpRegistry} from "dss-cdp-registry/CdpRegistry.sol";
import {CropJoin, CropJoinImp} from "../CropJoin.sol";

import {Token} from "./TestBase.sol";
import {DssDeployTestBase} from "dss-deploy/DssDeploy.t.base.sol";
import {DSValue} from "ds-value/value.sol";
import {ProxyRegistry, DSProxyFactory, DSProxy} from "proxy-registry/ProxyRegistry.sol";
import {WETH9_} from "ds-weth/weth9.sol";

contract MockCdpManager {
    uint256 public cdpi;

    function open(bytes32, address) public returns (uint256) {
        cdpi = cdpi + 1;
        return cdpi;
    }
}

contract User {
    DSProxy public proxy;
    address public dssProxyActionsEnd;

    receive() external payable {}

    constructor(ProxyRegistry registry, address _dssProxyActionsEnd) public {
        proxy = DSProxy(registry.build());
        dssProxyActionsEnd = _dssProxyActionsEnd;
    }

    function approve(address token, address usr, uint256 amount) public {
        Token(token).approve(usr, amount);
    }

    function end_pack(address a, address b, uint256 c) public {
        proxy.execute(dssProxyActionsEnd, abi.encodeWithSignature("pack(address,address,uint256)", a, b, c));
    }

    function end_cashETH(address a, address b, uint256 c) public {
        proxy.execute(dssProxyActionsEnd, abi.encodeWithSignature("cashETH(address,address,uint256)", a, b, c));
    }

    function end_cashGem(address a, address b, uint256 c) public {
        proxy.execute(dssProxyActionsEnd, abi.encodeWithSignature("cashGem(address,address,uint256)", a, b, c));
    }
}

contract ProxyCalls {
    DSProxy proxy;
    address dssProxyActions;
    address dssProxyActionsEnd;

    function transfer(address, address, uint256) public {
        proxy.execute(dssProxyActions, msg.data);
    }

    function open(bytes32, address) public returns (uint256 cdp) {
        bytes memory response = proxy.execute(dssProxyActions, msg.data);
        assembly {
            cdp := mload(add(response, 0x20))
        }
    }

    function hope(address, address) public {
        proxy.execute(dssProxyActions, msg.data);
    }

    function nope(address, address) public {
        proxy.execute(dssProxyActions, msg.data);
    }

    function daiJoin_join(address, address, uint256) public {
        proxy.execute(dssProxyActions, msg.data);
    }

    function lockETH(address, uint256) public payable {
        (bool success,) = address(proxy).call{value: msg.value}(
            abi.encodeWithSignature("execute(address,bytes)", dssProxyActions, msg.data)
        );
        require(success, "");
    }

    function lockGem(address, uint256, uint256) public {
        proxy.execute(dssProxyActions, msg.data);
    }

    function freeETH(address, uint256, uint256) public {
        proxy.execute(dssProxyActions, msg.data);
    }

    function freeGem(address, uint256, uint256) public {
        proxy.execute(dssProxyActions, msg.data);
    }

    function exitETH(address, uint256, uint256) public {
        proxy.execute(dssProxyActions, msg.data);
    }

    function exitGem(address, uint256, uint256) public {
        proxy.execute(dssProxyActions, msg.data);
    }

    function fleeETH(address, uint256, uint256) public {
        proxy.execute(dssProxyActions, msg.data);
    }

    function fleeGem(address, uint256, uint256) public {
        proxy.execute(dssProxyActions, msg.data);
    }

    function draw(address, address, uint256, uint256) public {
        proxy.execute(dssProxyActions, msg.data);
    }

    function wipe(address, uint256, uint256) public {
        proxy.execute(dssProxyActions, msg.data);
    }

    function wipeAll(address, uint256) public {
        proxy.execute(dssProxyActions, msg.data);
    }

    function lockETHAndDraw(address, address, address, uint256, uint256) public payable {
        (bool success,) = address(proxy).call{value: msg.value}(
            abi.encodeWithSignature("execute(address,bytes)", dssProxyActions, msg.data)
        );
        require(success, "");
    }

    function openLockETHAndDraw(address, address, address, bytes32, uint256) public payable returns (uint256 cdp) {
        address payable target = address(proxy);
        bytes memory data = abi.encodeWithSignature("execute(address,bytes)", dssProxyActions, msg.data);
        assembly {
            let succeeded := call(sub(gas(), 5000), target, callvalue(), add(data, 0x20), mload(data), 0, 0)
            let size := returndatasize()
            let response := mload(0x40)
            mstore(0x40, add(response, and(add(add(size, 0x20), 0x1f), not(0x1f))))
            mstore(response, size)
            returndatacopy(add(response, 0x20), 0, size)

            cdp := mload(add(response, 0x60))

            switch iszero(succeeded)
            case 1 {
            // throw if delegatecall failed
                revert(add(response, 0x20), size)
            }
        }
    }

    function lockGemAndDraw(address, address, address, uint256, uint256, uint256) public {
        proxy.execute(dssProxyActions, msg.data);
    }

    function openLockGemAndDraw(address, address, address, bytes32, uint256, uint256) public returns (uint256 cdp) {
        bytes memory response = proxy.execute(dssProxyActions, msg.data);
        assembly {
            cdp := mload(add(response, 0x20))
        }
    }

    function wipeAndFreeETH(address, address, uint256, uint256, uint256) public {
        proxy.execute(dssProxyActions, msg.data);
    }

    function wipeAllAndFreeETH(address, address, uint256, uint256) public {
        proxy.execute(dssProxyActions, msg.data);
    }

    function wipeAndFreeGem(address, address, uint256, uint256, uint256) public {
        proxy.execute(dssProxyActions, msg.data);
    }

    function wipeAllAndFreeGem(address, address, uint256, uint256) public {
        proxy.execute(dssProxyActions, msg.data);
    }

    function crop(address, uint256) public {
        proxy.execute(dssProxyActions, msg.data);
    }

    function end_freeETH(address a, address b, uint256 c) public {
        proxy.execute(dssProxyActionsEnd, abi.encodeWithSignature("freeETH(address,address,uint256)", a, b, c));
    }

    function end_freeGem(address a, address b, uint256 c) public {
        proxy.execute(dssProxyActionsEnd, abi.encodeWithSignature("freeGem(address,address,uint256)", a, b, c));
    }

    function end_pack(address a, address b, uint256 c) public {
        proxy.execute(dssProxyActionsEnd, abi.encodeWithSignature("pack(address,address,uint256)", a, b, c));
    }

    function end_cashETH(address a, address b, uint256 c) public {
        proxy.execute(dssProxyActionsEnd, abi.encodeWithSignature("cashETH(address,address,uint256)", a, b, c));
    }

    function end_cashGem(address a, address b, uint256 c) public {
        proxy.execute(dssProxyActionsEnd, abi.encodeWithSignature("cashGem(address,address,uint256)", a, b, c));
    }
}

contract DssProxyActionsTest is DssDeployTestBase, ProxyCalls {
    CropperImp charter;
    MockCdpManager cdpManager;
    CdpRegistry cdpRegistry;
    address charterProxy;

    CropJoinImp ethManagedJoin;
    CropJoinImp wbtcJoin;
    Token wbtc;
    DSValue pipWBTC;
    ProxyRegistry registry;
    WETH9_ realWeth;
    Token bonus;

    function reward(address usr, uint256 wad) internal virtual {
        bonus.mint(usr, wad);
        assertEq(bonus.balanceOf(address(usr)), wad);
        assertEq(bonus.balanceOf(address(proxy)), 0);
    }
    
    function assertProxyRewarded(address gemJoin, uint256 wad) internal virtual {
        assertEq(bonus.balanceOf(address(gemJoin)), 0);
        assertEq(bonus.balanceOf(address(proxy)), wad);
    }

    function setUp() public override {
        super.setUp();
        deployKeepAuth();

        // Create bonus token
        bonus = new Token(12, 0);

        // Create a real WETH token and replace it with a new adapter in the vat
        realWeth = new WETH9_();
        this.deny(address(vat), address(ethJoin));
        CropJoin ethBaseJoin = new CropJoin();
        ethBaseJoin.setImplementation(address(new CropJoinImp(address(vat), "ETH", address(realWeth), address(bonus))));
        ethManagedJoin = CropJoinImp(address(ethBaseJoin));
        this.rely(address(vat), address(ethManagedJoin));

        // Add a token collateral
        wbtc = new Token(8, 1000 * 10 ** 8);
        CropJoin wbtcBaseJoin = new CropJoin();
        wbtcBaseJoin.setImplementation(address(new CropJoinImp(address(vat), "WBTC", address(wbtc), address(bonus))));
        wbtcJoin = CropJoinImp(address(wbtcBaseJoin));

        pipWBTC = new DSValue();
        dssDeploy.deployCollateralFlip("WBTC", address(wbtcJoin), address(pipWBTC));
        pipWBTC.poke(bytes32(uint256(50 ether))); // Price 50 DAI = 1 WBTC (in precision 18)
        this.file(address(spotter), "WBTC", "mat", uint256(1500000000 ether)); // Liquidation ratio 150%
        this.file(address(vat), bytes32("WBTC"), bytes32("line"), uint256(10000 * 10 ** 45));
        spotter.poke("WBTC");
        (,,uint256 spot,,) = vat.ilks("WBTC");
        assertEq(spot, 50 * RAY * RAY / 1500000000 ether);

        // Deploy Cropper
        Cropper base = new Cropper();
        base.setImplementation(address(new CropperImp(address(vat))));
        charter = CropperImp(address(base));

        CropJoin(address(ethManagedJoin)).rely(address(charter));
        CropJoin(address(ethManagedJoin)).deny(address(this));    // Only access should be through charter
        CropJoin(address(wbtcJoin)).rely(address(charter));
        CropJoin(address(wbtcJoin)).deny(address(this));    // Only access should be through charter

        // Deploy cdp registry
        cdpManager = new MockCdpManager();
        cdpRegistry = new CdpRegistry(address(cdpManager));

        // Deploy proxy factory and create a proxy
        DSProxyFactory factory = new DSProxyFactory();
        registry = new ProxyRegistry(address(factory));
        dssProxyActions = address(new DssProxyActionsCropper(address(vat), address(charter), address(cdpRegistry)));
        dssProxyActionsEnd = address(new DssProxyActionsEndCropper(address(vat), address(charter), address(cdpRegistry)));
        proxy = DSProxy(registry.build());
        charterProxy = charter.getOrCreateProxy(address(proxy));
    }

    function ink(bytes32 ilk, address urn) public view returns (uint256 inkV) {
        (inkV,) = vat.urns(ilk, urn);
    }

    function art(bytes32 ilk, address urn) public view returns (uint256 artV) {
        (,artV) = vat.urns(ilk, urn);
    }

    function assertEqApprox(uint256 _a, uint256 _b, uint256 _tolerance) internal {
        uint256 a = _a;
        uint256 b = _b;
        if (a < b) {
            uint256 tmp = a;
            a = b;
            b = tmp;
        }
        if (a - b > _tolerance) {
            emit log_bytes32("Error: Wrong `uint' value");
            emit log_named_uint("  Expected", _b);
            emit log_named_uint("    Actual", _a);
            fail();
        }
    }

    function testTransfer() public {
        wbtc.transfer(address(proxy), 10);
        assertEq(wbtc.balanceOf(address(proxy)), 10);
        assertEq(wbtc.balanceOf(address(123)), 0);
        this.transfer(address(wbtc), address(123), 4);
        assertEq(wbtc.balanceOf(address(proxy)), 6);
        assertEq(wbtc.balanceOf(address(123)), 4);
    }

    function testLockETH() public {
        uint256 cdp = this.open("ETH", address(proxy));
        uint256 initialBalance = address(this).balance;
        assertEq(ink("ETH", charterProxy), 0);
        this.lockETH{value: 2 ether}(address(ethManagedJoin), cdp);
        assertEq(ink("ETH", charterProxy), 2 ether);
        assertEq(address(this).balance, initialBalance - 2 ether);
        reward(address(ethManagedJoin), 100 * 10 ** 12);
        this.lockETH{value: 0}(address(ethManagedJoin), cdp);
        assertProxyRewarded(address(ethManagedJoin), 100 * 10 ** 12);
    }

    function testLockGem() public {
        uint256 cdp = this.open("WBTC", address(proxy));
        wbtc.approve(address(proxy), 2 * 10 ** 8);
        assertEq(ink("WBTC", charterProxy), 0);
        uint256 prevBalance = wbtc.balanceOf(address(this));
        this.lockGem(address(wbtcJoin), cdp, 2 * 10 ** 8);
        assertEq(ink("WBTC", charterProxy), 2 ether);
        assertEq(wbtc.balanceOf(address(this)), prevBalance - 2 * 10 ** 8);
        reward(address(wbtcJoin), 100 * 10 ** 12);
        this.lockGem(address(wbtcJoin), cdp, 0);
        assertProxyRewarded(address(wbtcJoin), 100 * 10 ** 12);
    }

    function testFreeETH() public {
        uint256 cdp = this.open("ETH", address(proxy));
        uint256 initialBalance = address(this).balance;
        this.lockETH{value: 2 ether}(address(ethManagedJoin), cdp);
        reward(address(ethManagedJoin), 100 * 10 ** 12);
        this.freeETH(address(ethManagedJoin), cdp, 1 ether);
        assertEq(ink("ETH", charterProxy), 1 ether);
        assertEq(address(this).balance, initialBalance - 1 ether);
        assertProxyRewarded(address(ethManagedJoin), 100 * 10 ** 12);
    }

    function testFreeGem() public {
        uint256 cdp = this.open("WBTC", address(proxy));
        wbtc.approve(address(proxy), 2 * 10 ** 8);
        assertEq(ink("WBTC", charterProxy), 0);
        uint256 prevBalance = wbtc.balanceOf(address(this));
        this.lockGem(address(wbtcJoin), cdp, 2 * 10 ** 8);
        reward(address(wbtcJoin), 100 * 10 ** 12);
        this.freeGem(address(wbtcJoin), cdp, 1 * 10 ** 8);
        assertEq(ink("WBTC", charterProxy),  1 ether);
        assertEq(wbtc.balanceOf(address(this)), prevBalance - 1 * 10 ** 8);
        assertProxyRewarded(address(wbtcJoin), 100 * 10 ** 12);
    }

    function testDraw() public {
        uint256 cdp = this.open("ETH", address(proxy));
        this.lockETH{value: 2 ether}(address(ethManagedJoin), cdp);
        assertEq(dai.balanceOf(address(this)), 0);
        this.draw(address(jug), address(daiJoin), cdp, 300 ether);
        assertEq(dai.balanceOf(address(this)), 300 ether);
        assertEq(art("ETH", charterProxy), 300 ether);
    }

    function testDrawAfterDrip() public {
        this.file(address(jug), bytes32("ETH"), bytes32("duty"), uint256(1.05 * 10 ** 27));
        hevm.warp(now + 1);
        jug.drip("ETH");

        uint256 cdp = this.open("ETH", address(proxy));
        this.lockETH{value: 2 ether}(address(ethManagedJoin), cdp);
        assertEq(dai.balanceOf(address(this)), 0);
        this.draw(address(jug), address(daiJoin), cdp, 300 ether);
        assertEq(dai.balanceOf(address(this)), 300 ether);
        assertEq(art("ETH", charterProxy), mul(300 ether, RAY) / (1.05 * 10 ** 27) + 1); // Extra wei due rounding
    }

    function testWipe() public {
        uint256 cdp = this.open("ETH", address(proxy));
        this.lockETH{value: 2 ether}(address(ethManagedJoin), cdp);
        this.draw(address(jug), address(daiJoin), cdp, 300 ether);
        dai.approve(address(proxy), 100 ether);
        this.wipe(address(daiJoin), cdp, 100 ether);
        assertEq(dai.balanceOf(address(this)), 200 ether);
        assertEq(art("ETH", charterProxy), 200 ether);
    }

    function testWipeAll() public {
        uint256 cdp = this.open("ETH", address(proxy));
        this.lockETH{value: 2 ether}(address(ethManagedJoin), cdp);
        this.draw(address(jug), address(daiJoin), cdp, 300 ether);
        dai.approve(address(proxy), 300 ether);
        this.wipeAll(address(daiJoin), cdp);
        assertEq(dai.balanceOf(address(this)), 0);
        assertEq(art("ETH", charterProxy), 0);
    }

    function testWipeAllWhileDaiExists() public {
        uint256 cdpEth = this.open("ETH", address(proxy));
        uint256 cdpWbtc = this.open("WBTC", address(proxy));

        this.lockETH{value: 2 ether}(address(ethManagedJoin), cdpEth);
        this.draw(address(jug), address(daiJoin), cdpEth, 300 ether);

        // draw dai from another vault and deposit it back so the dai in the vat exceeds the eth vault's debt
        wbtc.approve(address(proxy), 1000 * 10 ** 8);
        this.lockGem(address(wbtcJoin), cdpWbtc, 1000 * 10 ** 8);
        this.draw(address(jug), address(daiJoin), cdpWbtc, 1000 ether);
        dai.approve(address(proxy), 1000 ether);
        this.daiJoin_join(address(daiJoin), address(proxy), 1000 ether);

        this.wipeAll(address(daiJoin), cdpEth);
        assertEq(dai.balanceOf(address(this)), 300 ether);
        assertEq(art("ETH", charterProxy), 0);
    }

    function testWipeAfterDrip() public {
        this.file(address(jug), bytes32("ETH"), bytes32("duty"), uint256(1.05 * 10 ** 27));
        hevm.warp(now + 1);
        jug.drip("ETH");

        uint256 cdp = this.open("ETH", address(proxy));
        this.lockETH{value: 2 ether}(address(ethManagedJoin), cdp);
        this.draw(address(jug), address(daiJoin), cdp, 300 ether);
        dai.approve(address(proxy), 100 ether);
        this.wipe(address(daiJoin), cdp, 100 ether);
        assertEq(dai.balanceOf(address(this)), 200 ether);
        assertEq(art("ETH", charterProxy), mul(200 ether, RAY) / (1.05 * 10 ** 27) + 1);
    }

    function testWipeAllAfterDrip() public {
        this.file(address(jug), bytes32("ETH"), bytes32("duty"), uint256(1.05 * 10 ** 27));
        hevm.warp(now + 1);
        jug.drip("ETH");
        uint256 cdp = this.open("ETH", address(proxy));
        this.lockETH{value: 2 ether}(address(ethManagedJoin), cdp);
        this.draw(address(jug), address(daiJoin), cdp, 300 ether);
        dai.approve(address(proxy), 300 ether);
        this.wipe(address(daiJoin), cdp, 300 ether);
        assertEq(dai.balanceOf(address(this)), 0);
        assertEq(art("ETH", charterProxy), 0);
    }

    function testWipeAllAfterDrip2() public {
        this.file(address(jug), bytes32("ETH"), bytes32("duty"), uint256(1.05 * 10 ** 27));
        hevm.warp(now + 1);
        jug.drip("ETH");
        uint256 times = 30;
        uint256 cdp = this.open("ETH", address(proxy));
        this.lockETH{value: 2 ether * times}(address(ethManagedJoin), cdp);
        for (uint256 i = 0; i < times; i++) {
            this.draw(address(jug), address(daiJoin), cdp, 300 ether);
        }
        dai.approve(address(proxy), 300 ether * times);
        this.wipe(address(daiJoin), cdp, 300 ether * times);
        assertEq(dai.balanceOf(address(this)), 0);
        assertEq(art("ETH", charterProxy), 0);
    }

    function testLockETHAndDraw() public {
        uint256 cdp = this.open("ETH", address(proxy));
        uint256 initialBalance = address(this).balance;
        assertEq(ink("ETH", charterProxy), 0);
        assertEq(dai.balanceOf(address(this)), 0);
        this.lockETHAndDraw{value: 2 ether}(address(jug), address(ethManagedJoin), address(daiJoin), cdp, 300 ether);
        assertEq(ink("ETH", charterProxy), 2 ether);
        assertEq(dai.balanceOf(address(this)), 300 ether);
        assertEq(address(this).balance, initialBalance - 2 ether);
        reward(address(ethManagedJoin), 100 * 10 ** 12);
        this.lockETHAndDraw{value: 0}(address(jug), address(ethManagedJoin), address(daiJoin), cdp, 0);
        assertProxyRewarded(address(ethManagedJoin), 100 * 10 ** 12);
    }

    function testOpenLockETHAndDraw() public {
        uint256 initialBalance = address(this).balance;
        assertEq(dai.balanceOf(address(this)), 0);
        uint256 cdp = this.openLockETHAndDraw{value: 2 ether}(address(jug), address(ethManagedJoin), address(daiJoin), "ETH", 300 ether);
        assertEq(cdpRegistry.owns(cdp), address(proxy));
        assertEq(ink("ETH", charterProxy), 2 ether);
        assertEq(dai.balanceOf(address(this)), 300 ether);
        assertEq(address(this).balance, initialBalance - 2 ether);
    }

    function testLockGemAndDraw() public {
        uint256 cdp = this.open("WBTC", address(proxy));
        wbtc.approve(address(proxy), 3 * 10 ** 8);
        assertEq(ink("WBTC", charterProxy), 0);
        uint256 prevBalance = wbtc.balanceOf(address(this));
        this.lockGemAndDraw(address(jug), address(wbtcJoin), address(daiJoin), cdp, 3 * 10 ** 8, 50 ether);
        assertEq(ink("WBTC", charterProxy), 3 ether);
        assertEq(dai.balanceOf(address(this)), 50 ether);
        assertEq(wbtc.balanceOf(address(this)), prevBalance - 3 * 10 ** 8);
        reward(address(wbtcJoin), 100 * 10 ** 12);
        this.lockGemAndDraw(address(jug), address(wbtcJoin), address(daiJoin), cdp, 0, 0);
        assertEq(bonus.balanceOf(address(wbtcJoin)), 1);
        assertEq(bonus.balanceOf(address(proxy)), 100 * 10 ** 12 - 1);
    }

    function testOpenLockGemAndDraw() public {
        wbtc.approve(address(proxy), 2 ether);
        assertEq(dai.balanceOf(charterProxy), 0);
        uint256 prevBalance = wbtc.balanceOf(address(this));
        uint256 cdp = this.openLockGemAndDraw(address(jug), address(wbtcJoin), address(daiJoin), "WBTC", 2 * 10 ** 8, 10 ether);
        assertEq(cdpRegistry.owns(cdp), address(proxy));
        assertEq(ink("WBTC", charterProxy), 2 ether);
        assertEq(dai.balanceOf(address(this)), 10 ether);
        assertEq(wbtc.balanceOf(address(this)), prevBalance - 2 * 10 ** 8);
    }

    function testWipeAndFreeETH() public {
        uint256 cdp = this.open("ETH", address(proxy));
        uint256 initialBalance = address(this).balance;
        this.lockETHAndDraw{value: 2 ether}(address(jug), address(ethManagedJoin), address(daiJoin), cdp, 300 ether);
        dai.approve(address(proxy), 250 ether);
        reward(address(ethManagedJoin), 100 * 10 ** 12);
        this.wipeAndFreeETH(address(ethManagedJoin), address(daiJoin), cdp, 1.5 ether, 250 ether);
        assertEq(ink("ETH", charterProxy), 0.5 ether);
        assertEq(art("ETH", charterProxy), 50 ether);
        assertEq(dai.balanceOf(address(this)), 50 ether);
        assertEq(address(this).balance, initialBalance - 0.5 ether);
        assertProxyRewarded(address(ethManagedJoin), 100 * 10 ** 12);
    }

    function testWipeAllAndFreeETH() public {
        uint256 cdp = this.open("ETH", address(proxy));
        uint256 initialBalance = address(this).balance;
        this.lockETHAndDraw{value: 2 ether}(address(jug), address(ethManagedJoin), address(daiJoin), cdp, 300 ether);
        dai.approve(address(proxy), 300 ether);
        reward(address(ethManagedJoin), 100 * 10 ** 12);
        this.wipeAllAndFreeETH(address(ethManagedJoin), address(daiJoin), cdp, 1.5 ether);
        assertEq(ink("ETH", charterProxy), 0.5 ether);
        assertEq(art("ETH", charterProxy), 0);
        assertEq(dai.balanceOf(address(this)), 0);
        assertEq(address(this).balance, initialBalance - 0.5 ether);
        assertProxyRewarded(address(ethManagedJoin), 100 * 10 ** 12);
    }

    function testWipeAndFreeGem() public {
        uint256 cdp = this.open("WBTC", address(proxy));
        wbtc.approve(address(proxy), 2 * 10 ** 8);
        uint256 prevBalance = wbtc.balanceOf(address(this));
        this.lockGemAndDraw(address(jug), address(wbtcJoin), address(daiJoin), cdp, 2 * 10 ** 8, 10 ether);
        reward(address(wbtcJoin), 100 * 10 ** 12);
        dai.approve(address(proxy), 8 ether);
        this.wipeAndFreeGem(address(wbtcJoin), address(daiJoin), cdp, 1.5 * 10 ** 8, 8 ether);
        assertEq(ink("WBTC", charterProxy), 0.5 ether);
        assertEq(art("WBTC", charterProxy), 2 ether);
        assertEq(dai.balanceOf(address(this)), 2 ether);
        assertEq(wbtc.balanceOf(address(this)), prevBalance - 0.5 * 10 ** 8);
        assertProxyRewarded(address(wbtcJoin), 100 * 10 ** 12);
    }

    function testWipeAllAndFreeGem() public {
        uint256 cdp = this.open("WBTC", address(proxy));
        wbtc.approve(address(proxy), 2 * 10 ** 8);
        uint256 prevBalance = wbtc.balanceOf(address(this));
        this.lockGemAndDraw(address(jug), address(wbtcJoin), address(daiJoin), cdp, 2 * 10 ** 8, 10 ether);
        reward(address(wbtcJoin), 100 * 10 ** 12);
        dai.approve(address(proxy), 10 ether);
        this.wipeAllAndFreeGem(address(wbtcJoin), address(daiJoin), cdp, 1.5 * 10 ** 8);
        assertEq(ink("WBTC", charterProxy), 0.5 ether);
        assertEq(art("WBTC", charterProxy), 0);
        assertEq(dai.balanceOf(address(this)), 0);
        assertEq(wbtc.balanceOf(address(this)), prevBalance - 0.5 * 10 ** 8);
        assertProxyRewarded(address(wbtcJoin), 100 * 10 ** 12);
    }

    function testHopeNope() public {
        assertEq(vat.can(address(proxy), address(123)), 0);
        this.hope(address(vat), address(123));
        assertEq(vat.can(address(proxy), address(123)), 1);
        this.nope(address(vat), address(123));
        assertEq(vat.can(address(proxy), address(123)), 0);
    }

    function testExitEth() public {
        uint256 cdp = this.open("ETH", address(proxy));
        realWeth.deposit{value: 1 ether}();
        realWeth.approve(address(charter), uint256(-1));
        charter.join(address(ethManagedJoin), address(proxy), 1 ether);
        assertEq(vat.gem("ETH", address(this)), 0);
        assertEq(vat.gem("ETH", charterProxy), 1 ether);

        reward(address(ethManagedJoin), 100 * 10 ** 12);
        uint256 prevBalance = address(this).balance;
        this.exitETH(address(ethManagedJoin), cdp, 1 ether);
        assertEq(vat.gem("ETH", address(this)), 0);
        assertEq(vat.gem("ETH", charterProxy), 0);
        assertEq(address(this).balance, prevBalance + 1 ether);
        assertProxyRewarded(address(ethManagedJoin), 100 * 10 ** 12);
    }

    function testExitGem() public {
        uint256 cdp = this.open("WBTC", address(proxy));
        wbtc.approve(address(charter), 2 * 10 ** 8);
        charter.join(address(wbtcJoin), address(proxy), 2 * 10 ** 8);
        assertEq(vat.gem("WBTC", address(this)), 0);
        assertEq(vat.gem("WBTC", charterProxy), 2 ether);

        reward(address(wbtcJoin), 100 * 10 ** 12);
        uint256 prevBalance = wbtc.balanceOf(address(this));
        this.exitGem(address(wbtcJoin), cdp, 2 * 10 ** 8);
        assertEq(vat.gem("WBTC", address(this)), 0);
        assertEq(vat.gem("WBTC", charterProxy), 0);
        assertEq(wbtc.balanceOf(address(this)), prevBalance + 2 * 10 ** 8);
        assertProxyRewarded(address(wbtcJoin), 100 * 10 ** 12);
    }

    function testFleeEth() public {
        uint256 cdp = this.open("ETH", address(proxy));
        realWeth.deposit{value: 1 ether}();
        realWeth.approve(address(charter), uint256(-1));
        charter.join(address(ethManagedJoin), address(proxy), 1 ether);
        assertEq(vat.gem("ETH", address(this)), 0);
        assertEq(vat.gem("ETH", charterProxy), 1 ether);

        reward(address(ethManagedJoin), 100 * 10 ** 12);
        uint256 prevBalance = address(this).balance;
        this.fleeETH(address(ethManagedJoin), cdp, 1 ether);
        assertEq(vat.gem("ETH", address(this)), 0);
        assertEq(vat.gem("ETH", charterProxy), 0);
        assertEq(address(this).balance, prevBalance + 1 ether);

        assertEq(bonus.balanceOf(address(ethManagedJoin)), 100 * 10 ** 12);
        assertEq(bonus.balanceOf(address(proxy)), 0);
    }

        function testFleeGem() public {
        uint256 cdp = this.open("WBTC", address(proxy));
        wbtc.approve(address(charter), 2 * 10 ** 8);
        charter.join(address(wbtcJoin), address(proxy), 2 * 10 ** 8);
        assertEq(vat.gem("WBTC", address(this)), 0);
        assertEq(vat.gem("WBTC", charterProxy), 2 ether);

        reward(address(wbtcJoin), 100 * 10 ** 12);
        uint256 prevBalance = wbtc.balanceOf(address(this));
        this.fleeGem(address(wbtcJoin), cdp, 2 * 10 ** 8);
        assertEq(vat.gem("WBTC", address(this)), 0);
        assertEq(vat.gem("WBTC", charterProxy), 0);
        assertEq(wbtc.balanceOf(address(this)), prevBalance + 2 * 10 ** 8);

        assertEq(bonus.balanceOf(address(wbtcJoin)), 100 * 10 ** 12);
        assertEq(bonus.balanceOf(address(proxy)), 0);
    }

    function testCrop() public {
        uint256 cdp = this.open("ETH", address(proxy));
        uint256 initialBalance = address(this).balance;
        assertEq(ink("ETH", charterProxy), 0);
        this.lockETH{value: 2 ether}(address(ethManagedJoin), cdp);
        assertEq(ink("ETH", charterProxy), 2 ether);
        assertEq(address(this).balance, initialBalance - 2 ether);

        reward(address(ethManagedJoin), 100 * 10 ** 12);
        this.crop(address(ethManagedJoin), cdp);
        assertEq(bonus.balanceOf(address(ethManagedJoin)), 0);
        assertEq(bonus.balanceOf(address(proxy)), 0);
        assertEq(bonus.balanceOf(address(this)), 100 * 10 ** 12);
    }

    function testEnd() public {
        uint256 cdpEth = this.open("ETH", address(proxy));
        uint256 cdpWbtc = this.open("WBTC", address(proxy));

        this.lockETHAndDraw{value: 2 ether}(address(jug), address(ethManagedJoin), address(daiJoin), cdpEth, 300 ether);
        wbtc.approve(address(proxy), 1 * 10 ** 8);
        this.lockGemAndDraw(address(jug), address(wbtcJoin), address(daiJoin), cdpWbtc, 1 * 10 ** 8, 5 ether);

        this.cage(address(end));
        end.cage("ETH");
        end.cage("WBTC");

        (uint256 inkV, uint256 artV) = vat.urns("ETH", charterProxy);
        assertEq(inkV, 2 ether);
        assertEq(artV, 300 ether);

        (inkV, artV) = vat.urns("WBTC", charterProxy);
        assertEq(inkV, 1 ether);
        assertEq(artV, 5 ether);

        reward(address(ethManagedJoin), 100 * 10 ** 12);
        reward(address(wbtcJoin), 100 * 10 ** 12);
        uint256 prevBalanceETH = address(this).balance;
        this.end_freeETH(address(ethManagedJoin), address(end), cdpEth);
        (inkV, artV) = vat.urns("ETH", charterProxy);
        assertEq(inkV, 0);
        assertEq(artV, 0);
        uint256 remainInkVal = 2 ether - 300 * end.tag("ETH") / 10 ** 9; // 2 ETH (deposited) - 300 DAI debt * ETH cage price
        assertEq(address(this).balance, prevBalanceETH + remainInkVal);
        assertProxyRewarded(address(ethManagedJoin), 100 * 10 ** 12);

        uint256 prevBalanceWBTC = wbtc.balanceOf(address(this));
        this.end_freeGem(address(wbtcJoin), address(end), cdpWbtc);
        (inkV, artV) = vat.urns("WBTC", charterProxy);
        assertEq(inkV, 0);
        assertEq(artV, 0);
        remainInkVal = (1 ether - 5 * end.tag("WBTC") / 10 ** 9) / 10 ** 10; // 1 WBTC (deposited) - 5 DAI debt * WBTC cage price
        assertEq(wbtc.balanceOf(address(this)), prevBalanceWBTC + remainInkVal);
        assertProxyRewarded(address(ethManagedJoin), 200 * 10 ** 12);

        end.thaw();

        end.flow("ETH");
        end.flow("WBTC");

        User user = new User(registry, dssProxyActionsEnd);

        // move dai to user so he can redeem it for collateral
        dai.transfer(address(user), 305 ether);

        user.approve(address(dai), address(user.proxy()), 305 ether);
        user.end_pack(address(daiJoin), address(end), 305 ether);

        // tack stake from the skimmed vaults to End
        ethManagedJoin.tack(charterProxy, address(end), ethManagedJoin.stake(charterProxy));
        wbtcJoin.tack(charterProxy, address(end), wbtcJoin.stake(charterProxy));

        user.end_cashETH(address(ethManagedJoin), address(end), 305 ether);
        user.end_cashGem(address(wbtcJoin), address(end), 305 ether);

        // TODO: align this
        //assertEq(address(user).balance, 2 ether - 1); // (-1 rounding)
        //assertEq(wbtc.balanceOf(address(user)), 1 * 10 ** 8 - 1); // (-1 rounding)
    }

    receive() external payable {}
}
