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
    Token gem;
    Token bonus;
    CropJoin join;
    CropClipper cropper;
    Pip pip;
    Abacus abacus;
    bytes32 constant ILK = "GEM-A";

    VatAbstract  vat;
    DogAbstract  dog;
    SpotAbstract spotter;

    function setUp() public {
        vat     =  VatAbstract(0x35D1b3F3D7966A1DFe207aa4514C12a259A0492B);
        dog     =  DogAbstract(0x135954d155898D42C90D2a57824C690e0c7BEf1B);
        spotter = SpotAbstract(0x65C79fcB50Ca1594B025960e539eD7A9a6D434A3);

        // Give this contract admin access on the vat
        giveAuthAccess(address(vat), address(this));
        assertEq(vat.wards(address(this)), 1);

        // Initialize GEM-A in the Vat
        vat.init(ILK);

        // Give this contract admin access on the spotter
        giveAuthAccess(address(spotter), address(this));
        assertEq(spotter.wards(address(this)), 1);

        // Initialize price feed
        pip = new Pip();
        pip.set(WAD);  // Initial price of $1 per gem
        spotter.file(ILK, "pip", address(pip));
        spotter.file(ILK, "mat", 15 * RAY / 10);  // 150% collateralization ratio
        spotter.poke(ILK);

        gem     = new Token(18, 10**6 * WAD);
        bonus   = new Token(18, 10**6 * WAD);
        join    = new CropJoin(address(vat), ILK, address(gem), address(bonus));
        cropper = new CropClipper(address(vat), address(spotter), address(dog), address(join));
        cropper.rely(address(dog));

        // Set up pricing
        Abacus abacus = new Abacus();
        abacus.set(pip.val());
        cropper.file("calc", address(abacus));
    }

    function test_kick() public {
//        cropper.kick(tab, lot, usr, address(this));
    }

    function test_bark() public {}
    function test_take_all() public {}
    function test_take_return_collateral() public {}
    function test_take_multiple_calls() public {}
    function test_yank() public {}
}
