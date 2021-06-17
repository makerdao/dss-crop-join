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
import "dss-interfaces/Interfaces.sol";

import "./base.sol";
import "./crop-usr.sol";
import "./token.sol";
import "../crop.sol";
import "../cropper.sol";

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
    function test_kick() public {}
    Token gem;
    Token bonus;
    CropJoin join;
    CropClipper cropper;
    Pip pip;
    Abacus abacus;
    bytes32 constant ILK = "GEM-A";

    CropUsr usr;

    VatAbstract  vat;
    DogAbstract  dog;
    SpotAbstract spotter;

    uint256 constant RAD = 10**45;

    function setUp() public {
        vat     =  VatAbstract(0x35D1b3F3D7966A1DFe207aa4514C12a259A0492B);
        dog     =  DogAbstract(0x135954d155898D42C90D2a57824C690e0c7BEf1B);
        spotter = SpotAbstract(0x65C79fcB50Ca1594B025960e539eD7A9a6D434A3);

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
        cropper = new CropClipper(address(vat), address(spotter), address(dog), address(join));

        // Auth setup
        cropper.rely(address(dog));
        dog.rely(address(cropper));
        vat.rely(address(join));

        // Initialize GEM-A in the Dog
        dog.file(ILK, "hole", 10**6 * RAD);
        dog.file("Hole", add(dog.Hole(), 10**6 * RAD));
        dog.file(ILK, "clip", address(cropper));
        dog.file(ILK, "chop", 110 * WAD / 100);

        // Set up pricing
        abacus = new Abacus();
        abacus.set(pip.val());
        cropper.file("calc", address(abacus));

        // Create Vault
        usr = new CropUsr(join);
        gem.transfer(address(usr), 10**3 * WAD);
        usr.join(10**3 * WAD);
        usr.frob(int256(10**3 * WAD), int256(500 * WAD));  // Draw maximum possible debt

        // Accrue rewards
        bonus.transfer(address(join), 10**4 * WAD);  // 10 bonus tokens per joined gem

        // Simulate fee collection; usr's Vault becomes unsafe.
        vat.fold(ILK, cropper.vow(), int256(RAY / 5));
    }

    function test_kick_via_bark() public {
        assertEq(usr.stake(), 10**3 * WAD);
        assertEq(join.stake(address(cropper)), 0);
        dog.bark(ILK, usr.urp(), address(this));
        assertEq(usr.stake(), 0);
        assertEq(join.stake(address(cropper)), 10**3 * WAD);
    }
}