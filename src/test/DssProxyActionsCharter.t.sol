pragma solidity ^0.6.12;

import "ds-test/test.sol";

import "../DssProxyActionsCharter.sol";
import {Charter, CharterImp} from "../Charter.sol";
import {CdpRegistry} from "../CdpRegistry.sol";
import {ManagedGemJoin} from "lib/dss-gem-joins/src/join-managed.sol";

import {DssDeployTestBase} from "dss-deploy/DssDeploy.t.base.sol";
import {WBTC} from "dss-gem-joins/tokens/WBTC.sol";
import {DSValue} from "ds-value/value.sol";
import {ProxyRegistry, DSProxyFactory, DSProxy} from "proxy-registry/ProxyRegistry.sol";
import {WETH9_} from "ds-weth/weth9.sol";

interface HevmStoreLike {
    function store(address, bytes32, bytes32) external;
}

contract MockCdpManager {
    uint256 public cdpi;

    function open(bytes32, address) public returns (uint256) {
        cdpi = cdpi + 1;
        return cdpi;
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

    function quit(uint256, address) public {
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

    function roll(uint256, uint256, uint256) public {
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
    CharterImp charter;
    MockCdpManager cdpManager;
    CdpRegistry cdpRegistry;
    address charterProxy;

    ManagedGemJoin ethManagedJoin;
    ManagedGemJoin wbtcJoin;
    WBTC wbtc;
    DSValue pipWBTC;
    ProxyRegistry registry;
    WETH9_ realWeth;

    function cheat_cage() public {
        HevmStoreLike(address(hevm)).store(address(vat), bytes32(uint256(10)), bytes32(uint256(0)));
    }

    function setUp() public override {
        super.setUp();
        deployKeepAuth();

        // Create a real WETH token and replace it with a new adapter in the vat
        realWeth = new WETH9_();
        this.deny(address(vat), address(ethJoin));
        ethManagedJoin = new ManagedGemJoin(address(vat), "ETH", address(realWeth));
        this.rely(address(vat), address(ethManagedJoin));

        // Add a token collateral
        wbtc = new WBTC(1000 * 10 ** 8);
        wbtcJoin = new ManagedGemJoin(address(vat), "WBTC", address(wbtc));

        pipWBTC = new DSValue();
        dssDeploy.deployCollateralFlip("WBTC", address(wbtcJoin), address(pipWBTC));
        pipWBTC.poke(bytes32(uint256(50 ether))); // Price 50 DAI = 1 WBTC (in precision 18)
        this.file(address(spotter), "WBTC", "mat", uint256(1500000000 ether)); // Liquidation ratio 150%
        this.file(address(vat), bytes32("WBTC"), bytes32("line"), uint256(10000 * 10 ** 45));
        spotter.poke("WBTC");
        (,,uint256 spot,,) = vat.ilks("WBTC");
        assertEq(spot, 50 * RAY * RAY / 1500000000 ether);

        // Deploy Charter
        Charter base = new Charter();
        base.setImplementation(address(new CharterImp(address(vat), address(vow), address(spotter))));
        charter = CharterImp(address(base));

        ethManagedJoin.rely(address(charter));
        ethManagedJoin.deny(address(this));    // Only access should be through charter
        wbtcJoin.rely(address(charter));
        wbtcJoin.deny(address(this));    // Only access should be through charter

        // Deploy cdp registry
        cdpManager = new MockCdpManager();
        cdpRegistry = new CdpRegistry(address(cdpManager));

        // Deploy proxy factory and create a proxy
        DSProxyFactory factory = new DSProxyFactory();
        registry = new ProxyRegistry(address(factory));
        dssProxyActions = address(new DssProxyActionsCharter(address(vat), address(charter), address(cdpRegistry)));
        dssProxyActionsEnd = address(new DssProxyActionsEndCharter(address(vat), address(charter), address(cdpRegistry)));
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
    }

    function testLockGem() public {
        uint256 cdp = this.open("WBTC", address(proxy));
        wbtc.approve(address(proxy), 2 * 10 ** 8);
        assertEq(ink("WBTC", charterProxy), 0);
        uint256 prevBalance = wbtc.balanceOf(address(this));
        this.lockGem(address(wbtcJoin), cdp, 2 * 10 ** 8);
        assertEq(ink("WBTC", charterProxy), 2 ether);
        assertEq(wbtc.balanceOf(address(this)), prevBalance - 2 * 10 ** 8);
    }

    function testFreeETH() public {
        uint256 cdp = this.open("ETH", address(proxy));
        uint256 initialBalance = address(this).balance;
        this.lockETH{value: 2 ether}(address(ethManagedJoin), cdp);
        this.freeETH(address(ethManagedJoin), cdp, 1 ether);
        assertEq(ink("ETH", charterProxy), 1 ether);
        assertEq(address(this).balance, initialBalance - 1 ether);
    }

    function testFreeGem() public {
        uint256 cdp = this.open("WBTC", address(proxy));
        wbtc.approve(address(proxy), 2 * 10 ** 8);
        assertEq(ink("WBTC", charterProxy), 0);
        uint256 prevBalance = wbtc.balanceOf(address(this));
        this.lockGem(address(wbtcJoin), cdp, 2 * 10 ** 8);
        this.freeGem(address(wbtcJoin), cdp, 1 * 10 ** 8);
        assertEq(ink("WBTC", charterProxy),  1 ether);
        assertEq(wbtc.balanceOf(address(this)), prevBalance - 1 * 10 ** 8);
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

    function testDrawWithFee() public {
        charter.file("ETH", "gate", 0);
        charter.file("ETH", "Nib", 1.0 * 1e16); // one percent

        uint256 cdp = this.open("ETH", address(proxy));
        this.lockETH{value: 2 ether}(address(ethManagedJoin), cdp);
        assertEq(dai.balanceOf(address(this)), 0);
        this.draw(address(jug), address(daiJoin), cdp, 300 ether);
        assertEq(dai.balanceOf(address(this)), 300 ether);
        assertEq(vat.dai(address(vow)), 3030303030303030303040000000000000000000000000); // (300 / 0.99) * 0.01
        assertEq(art("ETH", charterProxy), 303030303030303030304); // (300 / 0.99)
    }

    function test_fuzz_drawWithFee(uint256 rate, uint256 Nib, uint256 wad, uint256 vatDai) public {
        HevmStoreLike(address(hevm)).store(
            address(vat),
            keccak256(abi.encode(address(this), uint256(0))),
            bytes32(uint256(1))
        );
        vat.file("Line", uint256(-1));
        vat.file("ETH", "line", uint256(-1));

        rate = rate % 1_000;
        rate = (rate == 0 ? 1 : rate) * RAY / 10_000;
        vat.fold("ETH", address(0), int256(rate)); // Between RAY/10000 to RAY/10

        charter.file("ETH", "gate", 0);

        Nib = Nib % 1_000;
        Nib = (Nib == 0 ? 1 : Nib) * WAD / 10_000;
        charter.file("ETH", "Nib", Nib); // Between 0.001% and 10%

        wad = wad % 100_000;
        wad = (wad == 0 ? 1 : wad) * 10_000 * WAD; // Between 10K and 1B

        vatDai = (wad / ((vatDai % 8) + 2)) * RAY; // Between wad/10 and wad/2
        HevmStoreLike(address(hevm)).store(
            address(vat),
            keccak256(abi.encode(address(proxy), uint256(5))),
            bytes32(uint256(vatDai))
        );
        assertEq(vat.dai(address(proxy)), vatDai);
        assertEq(dai.balanceOf(address(this)), 0);

        uint256 draw = wad - (vatDai / RAY);
        uint256 cdp = this.open("ETH", address(proxy));
        this.lockETH{value: wad / 150}(address(ethManagedJoin), cdp);
        assertEq(dai.balanceOf(address(this)), 0);
        this.draw(address(jug), address(daiJoin), cdp, wad);
        assertEq(dai.balanceOf(address(this)), wad);
        assertEqApprox(vat.dai(address(vow)), draw * RAY * Nib / (WAD - Nib), RAD / 100);
        uint256 art_ = art("ETH", charterProxy);
        assertEqApprox(art_, (draw + draw * Nib / WAD) * RAY / (RAY + rate), art_ / 100);
        assertLt(vat.dai(address(proxy)), RAD / 1000); // There should remain just dust
    }

    function testDrawAfterDripWithFee() public {
        charter.file("ETH", "gate", 1);
        charter.file("ETH", address(proxy), "nib", 5.0 * 1e16); // five percent
        charter.file("ETH", address(proxy), "uline", 320 * 10 ** 45);

        this.file(address(jug), bytes32("ETH"), bytes32("duty"), uint256(1.05 * 10 ** 27));
        hevm.warp(now + 1);
        jug.drip("ETH");

        uint256 cdp = this.open("ETH", address(proxy));
        this.lockETH{value: 2 ether}(address(ethManagedJoin), cdp);
        assertEq(dai.balanceOf(address(this)), 0);
        this.draw(address(jug), address(daiJoin), cdp, 300 ether);
        assertEq(dai.balanceOf(address(this)), 300 ether);
        assertEq(vat.dai(address(vow)) / RAY, 15789473684210526315); // (300 / 0.95) * 0.05
        assertEq(vat.dai(address(vow)) / RAY, 15789473684210526315); // (300 / 0.95) * 0.05
        assertEq(art("ETH", charterProxy), mul(300 ether, RAY) / (0.95 * 1.05 * 10 ** 27) + 1); // Extra wei due rounding
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

    function testLockETHAndDrawWithFee() public {
        charter.file("ETH", "gate", 0);
        charter.file("ETH", "Nib", 2.0 * 1e16); // two percent

        uint256 cdp = this.open("ETH", address(proxy));
        uint256 initialBalance = address(this).balance;
        assertEq(ink("ETH", charterProxy), 0);
        assertEq(dai.balanceOf(address(this)), 0);
        this.lockETHAndDraw{value: 2 ether}(address(jug), address(ethManagedJoin), address(daiJoin), cdp, 300 ether);
        assertEq(ink("ETH", charterProxy), 2 ether);
        assertEq(dai.balanceOf(address(this)), 300 ether);
        assertEq(vat.dai(address(vow)), 6122448979591836734700000000000000000000000000); // (300 / 0.98 ) * 0.02
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

    function testLockGemAndDrawWithFee() public {
        charter.file("WBTC", "gate", 0);
        charter.file("WBTC", "Nib", 1.0 * 1e16); // one percent

        uint256 cdp = this.open("WBTC", address(proxy));
        wbtc.approve(address(proxy), 3 * 10 ** 8);
        assertEq(ink("WBTC", charterProxy), 0);
        uint256 prevBalance = wbtc.balanceOf(address(this));
        this.lockGemAndDraw(address(jug), address(wbtcJoin), address(daiJoin), cdp, 3 * 10 ** 8, 50 ether);
        assertEq(ink("WBTC", charterProxy), 3 ether);
        assertEq(dai.balanceOf(address(this)), 50 ether);
        assertEq(vat.dai(address(vow)), 505050505050505050510000000000000000000000000); // (50 / 0.99) * 0.01
        assertEq(wbtc.balanceOf(address(this)), prevBalance - 3 * 10 ** 8);
    }

    function testWipeAndFreeETH() public {
        uint256 cdp = this.open("ETH", address(proxy));
        uint256 initialBalance = address(this).balance;
        this.lockETHAndDraw{value: 2 ether}(address(jug), address(ethManagedJoin), address(daiJoin), cdp, 300 ether);
        dai.approve(address(proxy), 250 ether);
        this.wipeAndFreeETH(address(ethManagedJoin), address(daiJoin), cdp, 1.5 ether, 250 ether);
        assertEq(ink("ETH", charterProxy), 0.5 ether);
        assertEq(art("ETH", charterProxy), 50 ether);
        assertEq(dai.balanceOf(address(this)), 50 ether);
        assertEq(address(this).balance, initialBalance - 0.5 ether);
    }

    function testWipeAllAndFreeETH() public {
        uint256 cdp = this.open("ETH", address(proxy));
        uint256 initialBalance = address(this).balance;
        this.lockETHAndDraw{value: 2 ether}(address(jug), address(ethManagedJoin), address(daiJoin), cdp, 300 ether);
        dai.approve(address(proxy), 300 ether);
        this.wipeAllAndFreeETH(address(ethManagedJoin), address(daiJoin), cdp, 1.5 ether);
        assertEq(ink("ETH", charterProxy), 0.5 ether);
        assertEq(art("ETH", charterProxy), 0);
        assertEq(dai.balanceOf(address(this)), 0);
        assertEq(address(this).balance, initialBalance - 0.5 ether);
    }

    function testWipeAndFreeGem() public {
        uint256 cdp = this.open("WBTC", address(proxy));
        wbtc.approve(address(proxy), 2 * 10 ** 8);
        uint256 prevBalance = wbtc.balanceOf(address(this));
        this.lockGemAndDraw(address(jug), address(wbtcJoin), address(daiJoin), cdp, 2 * 10 ** 8, 10 ether);
        dai.approve(address(proxy), 8 ether);
        this.wipeAndFreeGem(address(wbtcJoin), address(daiJoin), cdp, 1.5 * 10 ** 8, 8 ether);
        assertEq(ink("WBTC", charterProxy), 0.5 ether);
        assertEq(art("WBTC", charterProxy), 2 ether);
        assertEq(dai.balanceOf(address(this)), 2 ether);
        assertEq(wbtc.balanceOf(address(this)), prevBalance - 0.5 * 10 ** 8);
    }

    function testWipeAllAndFreeGem() public {
        uint256 cdp = this.open("WBTC", address(proxy));
        wbtc.approve(address(proxy), 2 * 10 ** 8);
        uint256 prevBalance = wbtc.balanceOf(address(this));
        this.lockGemAndDraw(address(jug), address(wbtcJoin), address(daiJoin), cdp, 2 * 10 ** 8, 10 ether);
        dai.approve(address(proxy), 10 ether);
        this.wipeAllAndFreeGem(address(wbtcJoin), address(daiJoin), cdp, 1.5 * 10 ** 8);
        assertEq(ink("WBTC", charterProxy), 0.5 ether);
        assertEq(art("WBTC", charterProxy), 0);
        assertEq(dai.balanceOf(address(this)), 0);
        assertEq(wbtc.balanceOf(address(this)), prevBalance - 0.5 * 10 ** 8);
    }

    function testRoll() public {
        charter.file("ETH", "gate", 1);
        charter.file("ETH", address(proxy), "uline", 1000 * 10 ** 45);
        charter.file("WBTC", "gate", 1);
        charter.file("WBTC", address(proxy), "uline", 1000 * 10 ** 45);
        charter.file("ETH", "WBTC", address(proxy), address(proxy), "rollable", 1);

        // set different rates per ilk
        this.file(address(jug), bytes32("ETH"), bytes32("duty"), uint256(1.05 * 10 ** 27));
        this.file(address(jug), bytes32("WBTC"), bytes32("duty"), uint256(1.03 * 10 ** 27));
        hevm.warp(now + 1);
        jug.drip("ETH");
        jug.drip("WBTC");

        uint256 cdpEth = this.open("ETH", address(proxy));
        uint256 cdpWbtc = this.open("WBTC", address(proxy));

        this.lockETHAndDraw{value: 2 ether}(address(jug), address(ethManagedJoin), address(daiJoin), cdpEth, 100 ether);
        wbtc.approve(address(proxy), 1 * 10 ** 8);
        this.lockGemAndDraw(address(jug), address(wbtcJoin), address(daiJoin), cdpWbtc, 1 * 10 ** 8, 5 ether);

        uint256 artEthBefore = art("ETH", charterProxy);
        assertEq(artEthBefore, mul(100 ether, RAY) / (1.05 * 10 ** 27) + 1); // 1 dart unit added in draw
        uint256 artWbtcBefore = art("WBTC", charterProxy);
        assertEq(artWbtcBefore, mul(5 ether, RAY) / (1.03 * 10 ** 27));
        assertLt(vat.dai(address(proxy)), RAD / 1000000); // There should remain just dust

        this.roll(cdpEth, cdpWbtc, 5 ether);

        assertEq(art("ETH", charterProxy), artEthBefore - mul(5 ether, RAY) / (1.05 * 10 ** 27));
        assertEq(art("WBTC", charterProxy), artWbtcBefore + mul(5 ether, RAY) / (1.03 * 10 ** 27));
        assertLt(vat.dai(address(proxy)), RAD / 1000000); // There should remain just dust
    }

    function testHopeNope() public {
        assertEq(vat.can(address(proxy), address(123)), 0);
        this.hope(address(vat), address(123));
        assertEq(vat.can(address(proxy), address(123)), 1);
        this.nope(address(vat), address(123));
        assertEq(vat.can(address(proxy), address(123)), 0);
    }

    function testQuit() public {
        uint256 cdp = this.open("ETH", address(proxy));
        this.lockETHAndDraw{value: 1 ether}(address(jug), address(ethManagedJoin), address(daiJoin), cdp, 50 ether);

        assertEq(ink("ETH", charterProxy), 1 ether);
        assertEq(art("ETH", charterProxy), 50 ether);
        assertEq(ink("ETH", address(proxy)), 0);
        assertEq(art("ETH", address(proxy)), 0);

        cheat_cage();
        this.hope(address(vat), address(charter));
        this.quit(cdp, address(proxy));

        assertEq(ink("ETH", charterProxy), 0);
        assertEq(art("ETH", charterProxy), 0);
        assertEq(ink("ETH", address(proxy)), 1 ether);
        assertEq(art("ETH", address(proxy)), 50 ether);
    }

    function testExitEth() public {
        uint256 cdp = this.open("ETH", address(proxy));
        realWeth.deposit{value: 1 ether}();
        realWeth.approve(address(charter), uint256(-1));
        charter.join(address(ethManagedJoin), address(proxy), 1 ether);
        assertEq(vat.gem("ETH", address(this)), 0);
        assertEq(vat.gem("ETH", charterProxy), 1 ether);

        uint256 prevBalance = address(this).balance;
        this.exitETH(address(ethManagedJoin), cdp, 1 ether);
        assertEq(vat.gem("ETH", address(this)), 0);
        assertEq(vat.gem("ETH", charterProxy), 0);
        assertEq(address(this).balance, prevBalance + 1 ether);
    }

    function testExitGem() public {
        uint256 cdp = this.open("WBTC", address(proxy));
        wbtc.approve(address(charter), 2 * 10 ** 8);
        charter.join(address(wbtcJoin), address(proxy), 2 * 10 ** 8);
        assertEq(vat.gem("WBTC", address(this)), 0);
        assertEq(vat.gem("WBTC", charterProxy), 2 ether);

        uint256 prevBalance = wbtc.balanceOf(address(this));
        this.exitGem(address(wbtcJoin), cdp, 2 * 10 ** 8);
        assertEq(vat.gem("WBTC", address(this)), 0);
        assertEq(vat.gem("WBTC", charterProxy), 0);
        assertEq(wbtc.balanceOf(address(this)), prevBalance + 2 * 10 ** 8);
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

        uint256 prevBalanceETH = address(this).balance;
        this.end_freeETH(address(ethManagedJoin), address(end), cdpEth);
        (inkV, artV) = vat.urns("ETH", charterProxy);
        assertEq(inkV, 0);
        assertEq(artV, 0);
        uint256 remainInkVal = 2 ether - 300 * end.tag("ETH") / 10 ** 9; // 2 ETH (deposited) - 300 DAI debt * ETH cage price
        assertEq(address(this).balance, prevBalanceETH + remainInkVal);

        uint256 prevBalanceWBTC = wbtc.balanceOf(address(this));
        this.end_freeGem(address(wbtcJoin), address(end), cdpWbtc);
        (inkV, artV) = vat.urns("WBTC", charterProxy);
        assertEq(inkV, 0);
        assertEq(artV, 0);
        remainInkVal = (1 ether - 5 * end.tag("WBTC") / 10 ** 9) / 10 ** 10; // 1 WBTC (deposited) - 5 DAI debt * WBTC cage price
        assertEq(wbtc.balanceOf(address(this)), prevBalanceWBTC + remainInkVal);

        end.thaw();

        end.flow("ETH");
        end.flow("WBTC");

        dai.approve(address(proxy), 305 ether);
        this.end_pack(address(daiJoin), address(end), 305 ether);

        this.end_cashETH(address(ethManagedJoin), address(end), 305 ether);
        this.end_cashGem(address(wbtcJoin), address(end), 305 ether);

        assertEq(address(this).balance, prevBalanceETH + 2 ether - 1); // (-1 rounding)
        assertEq(wbtc.balanceOf(address(this)), prevBalanceWBTC + 1 * 10 ** 8 - 1); // (-1 rounding)
    }

    receive() external payable {}
}
