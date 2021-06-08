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
import "../crop.sol";
import "../cropper.sol";

contract CropperIntegrationTest is TestBase {
    function test_kick() public {}
    function test_take_all() public {}
    function test_take_return_collateral() public {}
    function test_take_multiple_calls() public {}
    function test_yank() public {}
}
