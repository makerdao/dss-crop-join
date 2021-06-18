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
import "../crop-manager.sol";
import {MockVat, Token} from "./crop-unit.t.sol";

contract Usr {

    CropJoin adapter;
    CropJoinManagerImp manager;

    constructor(CropJoin adapter_, CropJoinManagerImp manager_) public {
        adapter = adapter_;
        manager = manager_;
    }

    function approve(address coin, address usr) public {
        Token(coin).approve(usr, uint(-1));
    }
    function join(address usr, uint wad) public {
        manager.join(address(adapter), usr, wad);
    }
    function join(uint wad) public {
        manager.join(address(adapter), address(this), wad);
    }
    function exit(address usr, uint wad) public {
        manager.exit(address(adapter), usr, wad);
    }
    function exit(uint wad) public {
        manager.exit(address(adapter), address(this), wad);
    }
    function proxy() public view returns (address) {
        return manager.proxy(address(this));
    }
    function crops() public view returns (uint256) {
        return adapter.crops(proxy());
    }
    function stake() public view returns (uint256) {
        return adapter.stake(proxy());
    }
    function gems() public view returns (uint256) {
        return adapter.vat().gem(adapter.ilk(), proxy());
    }
    function urn() public view returns (uint256, uint256) {
        return adapter.vat().urns(adapter.ilk(), proxy());
    }
    function dai() public view returns (uint256) {
        return adapter.vat().dai(address(this));
    }
    function reap() public {
        manager.join(address(adapter), address(this), 0);
    }
    function flee() public {
        manager.flee(address(adapter));
    }
    function frob(int256 dink, int256 dart) public {
        manager.frob(address(adapter), address(this), address(this), address(this), dink, dart);
    }
    function frob(address u, address v, address w, int256 dink, int256 dart) public {
        manager.frob(address(adapter), u, v, w, dink, dart);
    }
    function flux(address src, address dst, uint256 wad) public {
        manager.flux(address(adapter), src, dst, wad);
    }
    function quit(address dst) public {
        manager.quit(adapter.ilk(), dst);
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
    function can_exit(address usr, uint val) public returns (bool) {
        bytes memory call = abi.encodeWithSignature
            ("exit(address,address,uint256)", address(adapter), usr, val);
        return can_call(address(manager), call);
    }
}

contract CropJoinManagerTest is TestBase {

    Token               gem;
    Token               bonus;
    MockVat             vat;
    address             self;
    bytes32             ilk = "TOKEN-A";
    CropJoin            adapter;
    CropJoinManagerImp  manager;

    function setUp() public virtual {
        self = address(this);
        gem = new Token(6, 1000 * 1e6);
        bonus = new Token(18, 0);
        vat = new MockVat();
        adapter = new CropJoin(address(vat), ilk, address(gem), address(bonus));
        CropJoinManager base = new CropJoinManager();
        base.setImplementation(address(new CropJoinManagerImp(address(vat))));
        manager = CropJoinManagerImp(address(base));

        adapter.rely(address(manager));
        adapter.deny(address(this));    // Only access should be through manager
    }

    function init_user() internal returns (Usr a, Usr b) {
        return init_user(200 * 1e6);
    }
    function init_user(uint cash) internal returns (Usr a, Usr b) {
        a = new Usr(adapter, manager);
        b = new Usr(adapter, manager);

        gem.transfer(address(a), cash);
        gem.transfer(address(b), cash);

        a.approve(address(gem), address(manager));
        b.approve(address(gem), address(manager));
    }

    function reward(address usr, uint wad) internal virtual {
        bonus.mint(usr, wad);
    }

    function test_make_proxy() public {
        assertEq(manager.proxy(address(this)), address(0));
        manager.join(address(adapter), address(this), 0);
        assertTrue(manager.proxy(address(this)) != address(0));
    }

    function test_join_exit_self() public {
        (Usr a,) = init_user();
        a.join(10 * 1e6);
        assertEq(gem.balanceOf(address(a)), 190 * 1e6);
        assertEq(gem.balanceOf(address(adapter)), 10 * 1e6);
        assertEq(bonus.balanceOf(address(a)), 0);
        assertEq(a.gems(), 10 * 1e18);
        assertEq(a.stake(), 10 * 1e18);
        reward(address(adapter), 50 * 1e18);
        a.exit(10 * 1e6);
        assertEq(gem.balanceOf(address(a)), 200 * 1e6);
        assertEq(gem.balanceOf(address(adapter)), 0);
        assertEq(bonus.balanceOf(address(a)), 50 * 1e18);
        assertEq(a.gems(), 0);
        assertEq(a.stake(), 0);
    }

    function test_join_other1() public {
        (Usr a, Usr b) = init_user();
        a.join(10 * 1e6);
        assertEq(gem.balanceOf(address(a)), 190 * 1e6);
        assertEq(gem.balanceOf(address(adapter)), 10 * 1e6);
        assertEq(a.gems(), 10 * 1e18);
        assertEq(a.stake(), 10 * 1e18);
        reward(address(adapter), 50 * 1e18);
        b.join(address(a), 20 * 1e6);
        assertEq(gem.balanceOf(address(a)), 190 * 1e6);
        assertEq(gem.balanceOf(address(adapter)), 30 * 1e6);
        assertEq(a.gems(), 30 * 1e18);
        assertEq(a.stake(), 30 * 1e18);
        assertEq(bonus.balanceOf(address(a)), 50 * 1e18);
    }

    function test_join_other2() public {
        (Usr a, Usr b) = init_user();

        assertEq(gem.balanceOf(address(a)), 200e6);
        assertEq(gem.balanceOf(address(b)), 200e6);

        // User A sends some gems + rewards to User B
        a.join(address(b), 100e6);
        reward(address(adapter), 50e18);
        assertEq(a.stake(), 0);
        assertEq(a.crops(), 0);
        assertEq(a.gems(), 0);
        assertEq(b.stake(), 100e18);
        assertEq(b.crops(), 0);
        assertEq(b.gems(), 100e18);

        // B can take all the rewards
        b.reap();
        assertEq(a.crops(), 0);
        assertEq(b.crops(), 50e18);
        assertEq(bonus.balanceOf(address(a)), 0);
        assertEq(bonus.balanceOf(address(b)), 50e18);
        
        // B withdraws to A (rewards also go to A)
        reward(address(adapter), 50e18);
        b.exit(address(a), 100e6);
        assertEq(gem.balanceOf(address(a)), 200e6);
        assertEq(gem.balanceOf(address(b)), 200e6);
        assertEq(a.crops(), 0);
        assertEq(b.crops(), 0);
        assertEq(bonus.balanceOf(address(a)), 50e18);
        assertEq(bonus.balanceOf(address(b)), 50e18);
    }

    function test_frob() public {
        (Usr a,) = init_user();
        a.join(100 * 1e6);
        a.frob(100 * 1e18, 50 * 1e18);
        (uint256 ink, uint256 art) = a.urn();
        assertEq(ink, 100 * 1e18);
        assertEq(art, 50 * 1e18);
        assertEq(a.dai(), 50 * 1e45);
        assertEq(a.gems(), 0);
        a.frob(-100 * 1e18, -50 * 1e18);
        (ink, art) = a.urn();
        assertEq(ink, 0);
        assertEq(art, 0);
        assertEq(a.dai(), 0);
        assertEq(a.gems(), 100 * 1e18);
    }

    // Non-msg.sender frobs should be disallowed for now
    function testFail_frob1() public {
        (Usr a,) = init_user();
        a.join(100 * 1e6);
        a.frob(address(this), address(a), address(a), 100 * 1e18, 50 * 1e18);
    }
    function testFail_frob2() public {
        (Usr a,) = init_user();
        a.join(100 * 1e6);
        a.frob(address(a), address(this), address(a), 100 * 1e18, 50 * 1e18);
    }
    function testFail_frob3() public {
        (Usr a,) = init_user();
        a.join(100 * 1e6);
        a.frob(address(a), address(a), address(this), 100 * 1e18, 50 * 1e18);
    }

    function test_flux() public {
        (Usr a, Usr b) = init_user();
        a.join(100 * 1e6);
        assertEq(a.gems(), 100 * 1e18);
        assertEq(a.stake(), 100 * 1e18);
        a.flux(address(a), address(b), 100 * 1e18);
        assertEq(b.gems(), 100 * 1e18);
        assertEq(b.stake(), 100 * 1e18);
        b.exit(100 * 1e6);
        assertEq(b.gems(), 0);
        assertEq(b.stake(), 0);
        assertEq(gem.balanceOf(address(b)), 300 * 1e6);
    }

    // Non-msg.sender srcs for flux should be disallowed for now
    function testFail_flux() public {
        (Usr a, Usr b) = init_user();
        b.join(100 * 1e6);
        a.flux(address(b), address(a), 100 * 1e18);
    }

    function test_simple_multi_user() public {
        (Usr a, Usr b) = init_user();

        a.join(60 * 1e6);
        b.join(40 * 1e6);

        reward(address(adapter), 50 * 1e18);

        a.join(0);
        assertEq(bonus.balanceOf(address(a)), 30 * 1e18);
        assertEq(bonus.balanceOf(address(b)),  0 * 1e18);

        b.join(0);
        assertEq(bonus.balanceOf(address(a)), 30 * 1e18);
        assertEq(bonus.balanceOf(address(b)), 20 * 1e18);
    }
    function test_simple_multi_reap() public {
        (Usr a, Usr b) = init_user();

        a.join(60 * 1e6);
        b.join(40 * 1e6);

        reward(address(adapter), 50 * 1e18);

        a.join(0);
        assertEq(bonus.balanceOf(address(a)), 30 * 1e18);
        assertEq(bonus.balanceOf(address(b)),  0 * 1e18);

        b.join(0);
        assertEq(bonus.balanceOf(address(a)), 30 * 1e18);
        assertEq(bonus.balanceOf(address(b)), 20 * 1e18);

        a.join(0); b.reap();
        assertEq(bonus.balanceOf(address(a)), 30 * 1e18);
        assertEq(bonus.balanceOf(address(b)), 20 * 1e18);
    }
    function test_complex_scenario() public {
        (Usr a, Usr b) = init_user();

        a.join(60 * 1e6);
        b.join(40 * 1e6);

        reward(address(adapter), 50 * 1e18);

        a.join(0);
        assertEq(bonus.balanceOf(address(a)), 30 * 1e18);
        assertEq(bonus.balanceOf(address(b)),  0 * 1e18);

        b.join(0);
        assertEq(bonus.balanceOf(address(a)), 30 * 1e18);
        assertEq(bonus.balanceOf(address(b)), 20 * 1e18);

        a.join(0); b.reap();
        assertEq(bonus.balanceOf(address(a)), 30 * 1e18);
        assertEq(bonus.balanceOf(address(b)), 20 * 1e18);

        reward(address(adapter), 50 * 1e18);
        a.join(20 * 1e6);
        a.join(0); b.reap();
        assertEq(bonus.balanceOf(address(a)), 60 * 1e18);
        assertEq(bonus.balanceOf(address(b)), 40 * 1e18);

        reward(address(adapter), 30 * 1e18);
        a.join(0); b.reap();
        assertEq(bonus.balanceOf(address(a)), 80 * 1e18);
        assertEq(bonus.balanceOf(address(b)), 50 * 1e18);

        b.exit(20 * 1e6);
    }
}
