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
import {CropJoin} from "../crop.sol";
import "../crop-proxy.sol";

contract MockVat {
    mapping (bytes32 => mapping (address => uint)) public gem;
    function urns(bytes32,address) external returns (uint256, uint256) {
        return (0, 0);
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
    function slip(bytes32 ilk, address usr, int256 wad) external {
        gem[ilk][usr] = add(gem[ilk][usr], wad);
    }
    function flux(bytes32 ilk, address src, address dst, uint256 wad) external {
        gem[ilk][src] = sub(gem[ilk][src], wad);
        gem[ilk][dst] = add(gem[ilk][dst], wad);
    }
    function hope(address usr) external {}
}

contract Token {
    uint8 public decimals;
    mapping (address => uint) public balanceOf;
    mapping (address => mapping (address => uint)) public allowance;
    constructor(uint8 dec, uint wad) public {
        decimals = dec;
        balanceOf[msg.sender] = wad;
    }
    function transfer(address usr, uint wad) public returns (bool) {
        require(balanceOf[msg.sender] >= wad, "transfer/insufficient");
        balanceOf[msg.sender] -= wad;
        balanceOf[usr] += wad;
        return true;
    }
    function transferFrom(address src, address dst, uint wad) public returns (bool) {
        require(balanceOf[src] >= wad, "transferFrom/insufficient");
        if (src != msg.sender && allowance[src][msg.sender] != uint(-1)) {
            require(allowance[src][msg.sender] >= wad, "transferFrom/insufficient-approval");
            allowance[src][msg.sender] = allowance[src][msg.sender] - wad;
        }
        balanceOf[src] -= wad;
        balanceOf[dst] += wad;
        return true;
    }
    function mint(address dst, uint wad) public returns (uint) {
        balanceOf[dst] += wad;
    }
    function approve(address usr, uint wad) public returns (bool) {
        allowance[msg.sender][usr] = wad;
    }
    function mint(uint wad) public returns (uint) {
        mint(msg.sender, wad);
    }
}

contract Usr {

    CropJoin adapter;
    CropProxyLogicImp proxyLogic;

    constructor(CropJoin adapter_, CropProxyLogicImp proxyLogic_) public {
        adapter = adapter_;
        proxyLogic = proxyLogic_;
    }

    function approve(address coin, address usr) public {
        Token(coin).approve(usr, uint(-1));
    }
    function join(address usr, uint wad) public {
        proxyLogic.join(address(adapter), usr, wad);
    }
    function join(uint wad) public {
        proxyLogic.join(address(adapter), address(this), wad);
    }
    function exit(address usr, uint wad) public {
        proxyLogic.exit(address(adapter), usr, wad);
    }
    function exit(uint wad) public {
        proxyLogic.exit(address(adapter), address(this), wad);
    }
    function proxy() public view returns (address) {
        return proxyLogic.proxy(address(this));
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
    function reap() public {
        proxyLogic.join(address(adapter), address(this), 0);
    }
    function flee() public {
        proxyLogic.flee(address(adapter));
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
        return can_call(address(proxyLogic), call);
    }
}

contract CropProxyUnitTest is TestBase {

    Token               gem;
    Token               bonus;
    MockVat             vat;
    address             self;
    bytes32             ilk = "TOKEN-A";
    CropJoin            adapter;
    CropProxyLogicImp   proxyLogic;

    function setUp() public virtual {
        self = address(this);
        gem = new Token(6, 1000 * 1e6);
        bonus = new Token(18, 0);
        vat = new MockVat();
        adapter = new CropJoin(address(vat), ilk, address(gem), address(bonus));
        CropProxyLogic base = new CropProxyLogic();
        base.setImplementation(address(new CropProxyLogicImp(address(vat))));
        proxyLogic = CropProxyLogicImp(address(base));

        adapter.rely(address(proxyLogic));
        adapter.deny(address(this));    // Only access should be through proxyLogic
    }

    function init_user() internal returns (Usr a, Usr b) {
        return init_user(200 * 1e6);
    }
    function init_user(uint cash) internal returns (Usr a, Usr b) {
        a = new Usr(adapter, proxyLogic);
        b = new Usr(adapter, proxyLogic);

        gem.transfer(address(a), cash);
        gem.transfer(address(b), cash);

        a.approve(address(gem), address(proxyLogic));
        b.approve(address(gem), address(proxyLogic));
    }

    function reward(address usr, uint wad) internal virtual {
        bonus.mint(usr, wad);
    }

    function test_reward() public virtual {
        reward(self, 100 ether);
        assertEq(bonus.balanceOf(self), 100 ether);
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

    function test_join_other() public {
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
}
