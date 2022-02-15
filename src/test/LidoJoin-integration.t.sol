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

import "./TestBase.sol";
import {ERC20, CropJoin, SynthetixJoinImp} from "../SynthetixJoin.sol";
import {Cropper,CropperImp} from "../Cropper.sol";

interface VatLike {
    function wards(address) external view returns (uint256);
    function rely(address) external;
    function hope(address) external;
    function gem(bytes32, address) external view returns (uint256);
    function flux(bytes32, address, address, uint256) external;
}

interface StakingRewardsLike {
    function rewardsToken() external view returns (address);
    function stakingToken() external view returns (address);
    function stake(uint256) external;
    function withdraw(uint256) external;
    function getReward() external;
    function balanceOf(address) external view returns (uint256);
}

contract Usr {

    Hevm hevm;
    VatLike vat;
    SynthetixJoinImp adapter;
    CropperImp cropper;
    ERC20 gem;

    constructor(Hevm hevm_, SynthetixJoinImp join_, CropperImp cropper_, ERC20 gem_) public {
        hevm = hevm_;
        adapter = join_;
        cropper = cropper_;
        gem = gem_;

        vat = VatLike(address(adapter.vat()));

        gem.approve(address(cropper), uint(-1));

        cropper.getOrCreateProxy(address(this));
    }

    function join(address usr, uint wad) public {
        cropper.join(address(adapter), usr, wad);
    }
    function join(uint wad) public {
        cropper.join(address(adapter), address(this), wad);
    }
    function exit(address usr, uint wad) public {
        cropper.exit(address(adapter), usr, wad);
    }
    function exit(uint wad) public {
        cropper.exit(address(adapter), address(this), wad);
    }
    function proxy() public view returns (address) {
        return cropper.proxy(address(this));
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
    function tokens() public view returns (uint256) {
        return adapter.gem().balanceOf(address(this));
    }
    function bonus() public view returns (uint256) {
        return adapter.bonus().balanceOf(address(this));
    }
    function urn() public view returns (uint256, uint256) {
        return adapter.vat().urns(adapter.ilk(), proxy());
    }
    function reap() public {
        cropper.join(address(adapter), address(this), 0);
    }
    function flee(uint256 amt) public {
        cropper.flee(address(adapter), address(this), amt);
    }
    function giveTokens(ERC20 token, uint256 amount) external {
        // Edge case - balance is already set for some reason
        if (token.balanceOf(address(this)) == amount) return;

        // Solidity-style
        for (uint256 i = 0; i < 20; i++) {
            // Scan the storage for the balance storage slot
            bytes32 prevValue = hevm.load(
                address(token),
                keccak256(abi.encode(address(this), uint256(i)))
            );
            hevm.store(
                address(token),
                keccak256(abi.encode(address(this), uint256(i))),
                bytes32(amount)
            );
            if (token.balanceOf(address(this)) == amount) {
                // Found it
                return;
            } else {
                // Keep going after restoring the original value
                hevm.store(
                    address(token),
                    keccak256(abi.encode(address(this), uint256(i))),
                    prevValue
                );
            }
        }

        // Vyper-style
        for (uint256 i = 0; i < 20; i++) {
            // Scan the storage for the balance storage slot
            bytes32 prevValue = hevm.load(
                address(token),
                keccak256(abi.encode(uint256(i), address(this)))
            );
            hevm.store(
                address(token),
                keccak256(abi.encode(uint256(i), address(this))),
                bytes32(amount)
            );
            if (token.balanceOf(address(this)) == amount) {
                // Found it
                return;
            } else {
                // Keep going after restoring the original value
                hevm.store(
                    address(token),
                    keccak256(abi.encode(uint256(i), address(this))),
                    prevValue
                );
            }
        }
    }

}

// Mainnet tests against Lido rewards for Curve stETH/ETH LP
contract LidoIntegrationTest is TestBase {

    ERC20 gem;
    ERC20 bonus;
    StakingRewardsLike pool;
    VatLike vat;
    bytes32 ilk = "CURVESTETHETH-A";
    SynthetixJoinImp join;
    CropperImp cropper;

    Usr user1;
    Usr user2;
    Usr user3;

    function setUp() public {
        vat = VatLike(0x35D1b3F3D7966A1DFe207aa4514C12a259A0492B);
        gem = ERC20(0x06325440D014e39736583c165C2963BA99fAf14E);        // Curve stETH/ETH LP
        bonus = ERC20(0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32);      // LDO token
        pool = StakingRewardsLike(0x99ac10631F69C753DDb595D074422a0922D9056B);

        // Give this contract admin access on the vat
        giveAuthAccess(address(vat), address(this));

        CropJoin baseJoin = new CropJoin();
        baseJoin.setImplementation(address(new SynthetixJoinImp(address(vat), ilk, address(gem), address(bonus), address(pool))));
        join = SynthetixJoinImp(address(baseJoin));
        join.init();
        Cropper baseCropper = new Cropper();
        baseCropper.setImplementation(address(new CropperImp(address(vat))));
        cropper = CropperImp(address(baseCropper));
        baseJoin.rely(address(cropper));
        baseJoin.deny(address(this));    // Only access should be through cropper
        vat.rely(address(baseJoin));
        assertEq(address(join.pool()), address(pool));
        user1 = new Usr(hevm, join, cropper, gem);
        user2 = new Usr(hevm, join, cropper, gem);
        user3 = new Usr(hevm, join, cropper, gem);

        assertTrue(user1.proxy() != address(0));
        assertTrue(user2.proxy() != address(0));
        assertTrue(user3.proxy() != address(0));

        user1.giveTokens(gem, 100 ether);
        assertEq(gem.balanceOf(address(user1)), 100 ether);
        user2.giveTokens(gem, 100 ether);
        user3.giveTokens(gem, 100 ether);
    }

    function test_join() public {
        user1.join(10 ether);

        assertEq(pool.balanceOf(address(join)), 10 ether);
        assertEq(gem.balanceOf(address(join)), 0 ether);
    }

    function test_join_rewards() public {
        user1.join(10 ether);

        assertEq(pool.balanceOf(address(join)), 10 ether);
        assertEq(gem.balanceOf(address(join)), 0 ether);
        assertEq(bonus.balanceOf(address(join)), 0 ether);
        assertEq(user1.bonus(), 0 ether);

        // Acquire some rewards
        hevm.warp(now + 100 days);
        user1.reap();

        assertEq(pool.balanceOf(address(join)), 10 ether);
        assertEq(gem.balanceOf(address(join)), 0 ether);
        assertEq(bonus.balanceOf(address(join)), 0 ether);
        assertGt(user1.bonus(), 0 ether);
    }

    function test_join_exit() public {
        uint256 origBal = user1.tokens();

        user1.join(10 ether);

        assertEq(pool.balanceOf(address(join)), 10 ether);
        assertEq(gem.balanceOf(address(join)), 0 ether);
        assertEq(user1.tokens(), origBal - 10 ether);

        user1.exit(5 ether);

        assertEq(pool.balanceOf(address(join)), 5 ether);
        assertEq(gem.balanceOf(address(join)), 0 ether);
        assertEq(user1.tokens(), origBal - 5 ether);
    }

    function test_join_exit_rewards() public {
        uint256 origBal = user1.tokens();

        user1.join(10 ether);

        assertEq(pool.balanceOf(address(join)), 10 ether);
        assertEq(gem.balanceOf(address(join)), 0 ether);
        assertEq(user1.tokens(), origBal - 10 ether);
        assertEq(user1.bonus(), 0 ether);

        // Acquire some rewards
        hevm.warp(now + 100 days);
        user1.exit(5 ether);

        assertEq(pool.balanceOf(address(join)), 5 ether);
        assertEq(gem.balanceOf(address(join)), 0 ether);
        assertEq(user1.tokens(), origBal - 5 ether);
        assertGt(user1.bonus(), 0 ether);
    }

    function test_join_exit_none() public {
        uint256 origBal = user1.tokens();

        user1.join(10 ether);

        assertEq(pool.balanceOf(address(join)), 10 ether);
        assertEq(gem.balanceOf(address(join)), 0 ether);
        assertEq(user1.tokens(), origBal - 10 ether);

        user1.exit(0 ether);

        assertEq(pool.balanceOf(address(join)), 10 ether);
        assertEq(gem.balanceOf(address(join)), 0 ether);
        assertEq(user1.tokens(), origBal - 10 ether);
    }

    function test_flee() public {
        uint256 origBal = user1.tokens();

        user1.join(10 ether);

        // Acquire some rewards
        hevm.warp(now + 100 days);

        assertEq(pool.balanceOf(address(join)), 10 ether);
        assertEq(user1.tokens(), origBal - 10 ether);

        user1.flee(10 ether);   // Should exit without rewards

        assertEq(pool.balanceOf(address(join)), 0 ether);
        assertEq(user1.tokens(), origBal);
        assertEq(user1.bonus(), 0 ether);
    }

    function test_cage() public {
        // Re-auth the join to cage it
        giveAuthAccess(address(join), address(this));

        uint256 origBal = user1.tokens();

        user1.join(10 ether);

        // Acquire some rewards
        hevm.warp(now + 100 days);

        assertEq(pool.balanceOf(address(join)), 10 ether);
        assertEq(gem.balanceOf(address(join)), 0 ether);
        assertEq(user1.tokens(), origBal - 10 ether);
        assertEq(CropJoin(address(join)).live(), 1);

        join.cage();

        assertEq(CropJoin(address(join)).live(), 0);
        assertEq(pool.balanceOf(address(join)), 0 ether);
        assertEq(gem.balanceOf(address(join)), 10 ether);
        assertEq(user1.tokens(), origBal - 10 ether);

        // Can get all my gems
        user1.exit(10 ether);

        assertEq(pool.balanceOf(address(join)), 0 ether);
        assertEq(gem.balanceOf(address(join)), 0 ether);
        assertEq(user1.tokens(), origBal);
    }

    function test_cage_uncage() public {
        // Re-auth the join to cage it
        giveAuthAccess(address(join), address(this));

        uint256 origBal = user1.tokens();

        user1.join(10 ether);

        // Acquire some rewards
        hevm.warp(now + 100 days);

        assertEq(pool.balanceOf(address(join)), 10 ether);
        assertEq(gem.balanceOf(address(join)), 0 ether);
        assertEq(user1.tokens(), origBal - 10 ether);
        assertEq(CropJoin(address(join)).live(), 1);

        join.cage();

        assertEq(CropJoin(address(join)).live(), 0);
        assertEq(pool.balanceOf(address(join)), 0 ether);
        assertEq(gem.balanceOf(address(join)), 10 ether);
        assertEq(user1.tokens(), origBal - 10 ether);

        join.uncage();

        assertEq(CropJoin(address(join)).live(), 1);
        assertEq(pool.balanceOf(address(join)), 10 ether);
        assertEq(gem.balanceOf(address(join)), 0 ether);
        assertEq(user1.tokens(), origBal - 10 ether);
    }

    function testFail_uncage() public {
        // Re-auth the join to cage it
        giveAuthAccess(address(join), address(this));

        user1.join(10 ether);

        // Acquire some rewards
        hevm.warp(now + 100 days);

        join.uncage();      // This will fail
    }

    function testFail_cage_join() public {
        // Re-auth the join to cage it
        giveAuthAccess(address(join), address(this));

        join.cage();

        user1.join(10 ether);      // This will fail
    }

}
