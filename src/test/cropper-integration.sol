// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2021 Dai Foundation
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.
pragma solidity 0.6.12;

import "./base.sol";
import {CropJoin} from "../crop.sol";
import {CropJoinManager,CropJoinManagerImp} from "../crop-manager.sol";
import {CropClipper} from "../cropper.sol";
import {Usr} from './crop-manager-unit.sol';

interface VatLike {
    function wards(address) external view returns (uint256);
    function rely(address) external;
    function deny(address) external;
    function can(address, address) external view returns (uint256);
    function hope(address) external;
    function nope(address) external;
    function ilks(bytes32) external view returns (uint256, uint256, uint256, uint256, uint256);
    function urns(bytes32, address) external view returns (uint256, uint256);
    function gem(bytes32, address) external view returns (uint256);
    function dai(address) external view returns (uint256);
    function sin(address) external view returns (uint256);
    function debt() external view returns (uint256);
    function vice() external view returns (uint256);
    function Line() external view returns (uint256);
    function live() external view returns (uint256);
    function init(bytes32) external;
    function file(bytes32, uint256) external;
    function file(bytes32, bytes32, uint256) external;
    function cage() external;
    function slip(bytes32, address, int256) external;
    function flux(bytes32, address, address, uint256) external;
    function move(address, address, uint256) external;
    function frob(bytes32, address, address, address, int256, int256) external;
    function fork(bytes32, address, address, int256, int256) external;
    function grab(bytes32, address, address, address, int256, int256) external;
    function heal(uint256) external;
    function suck(address, address, uint256) external;
    function fold(bytes32, address, int256) external;
}

interface DogLike {
    function wards(address) external view returns (uint256);
    function rely(address) external;
    function deny(address) external;
    function vat() external view returns (address);
    function ilks(bytes32) external view returns (address,uint256,uint256,uint256);
    function vow() external view returns (address);
    function live() external view returns (uint256);
    function Hole() external view returns (uint256);
    function Dirt() external view returns (uint256);
    function file(bytes32,address) external;
    function file(bytes32,uint256) external;
    function file(bytes32,bytes32,uint256) external;
    function file(bytes32,bytes32,address) external;
    function chop(bytes32) external view returns (uint256);
    function bark(bytes32,address,address) external returns (uint256);
    function digs(bytes32,uint256) external;
    function cage() external;
}

interface SpotLike {
    function wards(address) external view returns (uint256);
    function rely(address) external;
    function deny(address) external;
    function ilks(bytes32) external view returns (address, uint256);
    function vat() external view returns (address);
    function par() external view returns (uint256);
    function live() external view returns (uint256);
    function file(bytes32, bytes32, address) external;
    function file(bytes32, uint256) external;
    function file(bytes32, bytes32, uint256) external;
    function poke(bytes32) external;
    function cage() external;
}

contract Pip {
    uint256 public val;
    function set(uint256 val_) external {
        val = val_;
    }
    function peek() external returns (bytes32, bool) {
        return (bytes32(val), true);
    }
}

contract Abacus is Pip {
    function price(uint256, uint256) external view returns (uint256) {
        return val;
    }
}

contract CropperIntegrationTest is TestBase {
    
    Token gem;
    Token bonus;
    CropJoin join;
    CropJoinManagerImp manager;
    CropClipper cropper;
    Pip pip;
    Abacus abacus;
    bytes32 constant ILK = "GEM-A";

    Usr usr;

    VatLike  vat;
    DogLike  dog;
    SpotLike spotter;

    uint256 constant RAD = 10**45;

    function setUp() public {
        vat     =  VatLike(0x35D1b3F3D7966A1DFe207aa4514C12a259A0492B);
        dog     =  DogLike(0x135954d155898D42C90D2a57824C690e0c7BEf1B);
        spotter = SpotLike(0x65C79fcB50Ca1594B025960e539eD7A9a6D434A3);

        giveAuthAccess(address(vat),     address(this));
        giveAuthAccess(address(dog),     address(this));
        giveAuthAccess(address(spotter), address(this));

        // Initialize GEM-A in the Vat
        vat.init(ILK);

        vat.file(ILK, "line", 10**6 * RAD);
        vat.file("Line", add(vat.Line(), 10**6 * RAD));  // Ensure there is room in the global debt ceiling

        // Initialize price feed
        pip = new Pip();
        pip.set(WAD);  // Initial price of $1 per gem
        spotter.file(ILK, "pip", address(pip));
        spotter.file(ILK, "mat", 2 * RAY);  // 200% collateralization ratio
        spotter.poke(ILK);

        gem     = new Token(18, 10**6 * WAD);
        bonus   = new Token(18, 10**6 * WAD);
        join    = new CropJoin(address(vat), ILK, address(gem), address(bonus));
        CropJoinManager base = new CropJoinManager();
        base.setImplementation(address(new CropJoinManagerImp(address(vat))));
        manager = CropJoinManagerImp(address(base));
        cropper = new CropClipper(address(vat), address(spotter), address(dog), address(join), address(manager));

        // Auth setup
        cropper.rely(address(dog));
        dog.rely(address(cropper));
        vat.rely(address(join));
        join.rely(address(manager));
        join.deny(address(this));    // Only access should be through manager

        // Initialize GEM-A in the Dog
        dog.file(ILK, "hole", 10**6 * RAD);
        dog.file("Hole", add(dog.Hole(), 10**6 * RAD));
        dog.file(ILK, "clip", address(cropper));
        dog.file(ILK, "chop", 110 * WAD / 100);

        // Set up pricing
        abacus = new Abacus();
        abacus.set(mul(pip.val(), 10**9));
        cropper.file("calc", address(abacus));

        // Create Vault
        usr = new Usr(join, manager);
        gem.transfer(address(usr), 10**3 * WAD);
        usr.approve(address(gem), address(manager));
        usr.join(10**3 * WAD);
        usr.frob(int256(10**3 * WAD), int256(500 * WAD));  // Draw maximum possible debt

        // Accrue rewards
        bonus.transfer(address(join), 10**4 * WAD);  // 10 bonus tokens per joined gem

        // Draw some DAI for this contract for bidding on auctions.
        // This conveniently provisions an UrnProxy for the test contract as well.
        gem.approve(address(manager), uint256(-1));
        manager.join(address(join), address(this), 10**4 * WAD);
        manager.frob(address(join), address(this), address(this), address(this), int256(10**4 * WAD), int256(1000 * WAD));

        // Hope the cropper so we can bid.
        vat.hope(address(cropper));

        // Simulate fee collection; usr's Vault becomes unsafe.
        vat.fold(ILK, cropper.vow(), int256(RAY / 5));
    }

    function test_kick_via_bark() public {
        assertEq(usr.stake(), 10**3 * WAD);
        assertEq(join.stake(address(cropper)), 0);
        dog.bark(ILK, usr.proxy(), address(this));
        assertEq(usr.stake(), 0);
        assertEq(join.stake(address(cropper)), 10**3 * WAD);
    }

    function test_take_all() public {
        address urp = CropJoinManager(address(manager)).proxy(address(this));
        uint256 initialStake    = join.stake(urp);
        uint256 initialGemBal   = gem.balanceOf(address(this));

        uint256 id = dog.bark(ILK, usr.proxy(), address(this));

        // User gets the outstanding rewards on liquidation
        assertEq(bonus.balanceOf(address(usr)), 10**4 * WAD);

        // Quarter of a DAI per gem--this means the total value of collateral is 250 DAI,
        // which is less than the tab. Thus we'll purchase 100% of the collateral.
        uint256 price = 25 * RAY / 100;
        abacus.set(price);

        // Assert that the statement above is indeed true.
        (, uint256 tab, uint256 lot,,,) = cropper.sales(id);
        assertTrue(mul(lot, price) < tab);

        // Ensure that we have enough DAI to cover our purchase.
        assertTrue(mul(lot, price) < vat.dai(address(this)));

        bytes memory emptyBytes;
        cropper.take(id, lot, price, address(this), emptyBytes);

        (, tab, lot,,,) = cropper.sales(id);
        assertEq(tab, 0);
        assertEq(lot, 0);

        // The collateral has been transferred to us.
        assertEq(join.stake(urp), add(10**3 * WAD, initialStake));

        // We can exit, withdrawing the full reward (10^4 bonus tokens), without needing to tack.
        manager.exit(address(join), address(this), 10**3 * WAD);
        assertEq(join.stake(urp), initialStake);
        assertEq(gem.balanceOf(address(this)), add(initialGemBal, 10**3 * WAD));
    }

    function test_take_return_collateral() public {
        address urp = CropJoinManager(address(manager)).proxy(address(this));
        uint256 initialStake    = join.stake(urp);
        uint256 initialGemBal   = gem.balanceOf(address(this));

        uint256 id = dog.bark(ILK, usr.proxy(), address(this));

        // User gets the outstanding rewards on liquidation
        assertEq(bonus.balanceOf(address(usr)), 10**4 * WAD);

        // One DAI per gem; will be able to fully cover tab, leaving leftover collateral.
        uint256 price = RAY;
        abacus.set(price);

        // Assert that the statement above is indeed true.
        (, uint256 tab, uint256 lot,,,) = cropper.sales(id);
        assertTrue(mul(lot, price) > tab);

        // Ensure that we have enough DAI to cover our purchase.
        assertTrue(tab < vat.dai(address(this)));

        uint256 expectedPurchaseSize = tab / price;

        bytes memory emptyBytes;
        cropper.take(id, lot, price, address(this), emptyBytes);

        (, tab, lot,,,) = cropper.sales(id);
        assertEq(tab, 0);
        assertEq(lot, 0);

        // The collateral has been transferred to us.
        assertEq(join.stake(urp), add(expectedPurchaseSize, initialStake));

        // The remainder returned to the liquidated Vault.
        uint256 collateralReturned = sub(10**3 * WAD, expectedPurchaseSize);
        assertEq(usr.stake(), collateralReturned);

        // We can exit, withdrawing the appropriate fraction of the reward, without needing to tack.
        manager.exit(address(join), address(this), expectedPurchaseSize);
        assertEq(join.stake(urp), initialStake);
        assertEq(gem.balanceOf(address(this)), add(initialGemBal, expectedPurchaseSize));

        // Liquidated urn can exit and get its fair share of rewards as well.
        usr.exit(address(usr), collateralReturned);
        assertEq(usr.stake(), 0);
        assertEq(gem.balanceOf(address(usr)), collateralReturned);
    }

    function test_yank() public {
        address urp = CropJoinManager(address(manager)).proxy(address(this));
        uint256 initialStake    = join.stake(urp);
        uint256 initialGemBal   = gem.balanceOf(address(this));

        uint256 id = dog.bark(ILK, usr.proxy(), address(this));

        cropper.yank(id);

        // The collateral has been transferred to this contract specifically--
        // yank gets called by the End, which has no UrnProxy.
        assertEq(join.stake(address(this)), 10**3 * WAD);

        // We can exit if we flux and tack to our UrnProxy.
        vat.flux(ILK, address(this), urp, 10**3 * WAD);
        join.tack(address(this), urp, 10**3 * WAD);
        assertEq(join.stake(urp), add(10**3 * WAD, initialStake));
        manager.exit(address(join), address(this), 10**3 * WAD);
        assertEq(join.stake(urp), initialStake);
        assertEq(gem.balanceOf(address(this)), add(initialGemBal, 10**3 * WAD));
    }
}