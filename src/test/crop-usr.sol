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

import "../crop.sol";

interface Approvable {
    function approve(address, uint256) external;
}

contract CropUsr {

    VatAbstract vat;
    CropJoin cropJoin;

    constructor(CropJoin join_) public {
        cropJoin = join_;

        vat = VatAbstract(address(cropJoin.vat()));
    }

    function approve(address coin, address usr) public {
        Approvable(coin).approve(usr, uint(-1));
    }
    function join(address usr, uint wad) public {
        cropJoin.join(usr, wad);
    }
    function join(uint wad) public {
        cropJoin.join(address(this), wad);
    }
    function exit(address usr, uint wad) public {
        cropJoin.exit(usr, wad);
    }
    function exit(uint wad) public {
        cropJoin.exit(address(this), wad);
    }
    function crops() public view returns (uint256) {
        return cropJoin.crops(address(this));
    }
    function stake() public view returns (uint256) {
        return cropJoin.stake(address(this));
    }
    function gems() public view returns (uint256) {
        return vat.gem(cropJoin.ilk(), address(this));
    }
    function bonusBalance() public view returns (uint256) {
        return cropJoin.bonus().balanceOf(address(this));
    }
    function reap() public {
        cropJoin.join(address(this), 0);
    }
    function flee() public {
        cropJoin.flee();
    }
    function tack(address src, address dst, uint256 wad) public {
        cropJoin.tack(src, dst, wad);
    }
    function hope(address usr) public {
        vat.hope(usr);
    }
    function try_call(address addr, bytes calldata data) external returns (bool) {
        bytes memory _data = data;
        assembly {
            let ok := call(gas(), addr, 0, add(_data, 0x20), mload(_data), 0, 0)
            let free := mload(0x40)
            mstore(free, ok)
            mstore(0x40, add(free, 32))
            revert(free, 32)
        }
    }
    function can_call(address addr, bytes memory data) internal returns (bool) {
        (bool ok, bytes memory success) = address(this).call(
                                            abi.encodeWithSignature(
                                                "try_call(address,bytes)"
                                                , addr
                                                , data
                                                ));
        ok = abi.decode(success, (bool));
        if (ok) return true;
    }
    function can_exit(uint val) public returns (bool) {
        bytes memory call = abi.encodeWithSignature
            ("exit(address,uint256)", address(this), val);
        return can_call(address(cropJoin), call);
    }
}
