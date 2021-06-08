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

contract CropperIntegrationTest is TestBase {
    Token gem;
    Token bonus;
    CropJoin join;
    CropClipper cropper;
    bytes32 constant ILK = "GEM-A";

    VatAbstract vat;
    DogAbstract dog;

    function setUp() public {
        vat = VatAbstract(0x35D1b3F3D7966A1DFe207aa4514C12a259A0492B);
        dog = DogAbstract(0x135954d155898D42C90D2a57824C690e0c7BEf1B);

        // Give this contract admin access on the vat
        hevm.store(
            address(vat),
            keccak256(abi.encode(address(this), uint256(0))),
            bytes32(uint256(1))
        );
        assertEq(vat.wards(address(this)), 1);

        // Initialize GEM-A in the Vat
        vat.init(ILK);
    }

    function test_kick() public {
//        cropper.kick(tab, lot, usr, address(this));
    }

    function test_take_all() public {}
    function test_take_return_collateral() public {}
    function test_take_multiple_calls() public {}
    function test_yank() public {}
}
