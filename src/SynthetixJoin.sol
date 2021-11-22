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

import "./CropJoin.sol";

interface StakingRewardsLike {
    function rewardsToken() external view returns (address);
    function stakingToken() external view returns (address);
    function stake(uint256) external;
    function withdraw(uint256) external;
    function getReward() external;
}

// Join adapter for the Synthetix Staking Rewards contract (used by Uniswap V2, LIDO, etc)
contract SynthetixJoinImp is CropJoinImp {

    StakingRewardsLike immutable public pool;

    /**
        @param vat_                 MCD_VAT DSS core accounting module
        @param ilk_                 Collateral type
        @param gem_                 The collateral LP token address
        @param bonus_               The rewards token contract address.
        @param pool_                The staking rewards pool.
    */
    constructor(
        address vat_,
        bytes32 ilk_,
        address gem_,
        address bonus_,
        address pool_
    )
        public
        CropJoinImp(vat_, ilk_, gem_, bonus_)
    {
        // Sanity checks
        require(StakingRewardsLike(pool_).rewardsToken() == bonus_, "SynthetixJoin/bonus-mismatch");
        require(StakingRewardsLike(pool_).stakingToken() == gem_, "SynthetixJoin/gem-mismatch");

        pool = StakingRewardsLike(pool_);
    }

    function init() external {
        gem.approve(address(pool), type(uint256).max);
    }

    function nav() public override view returns (uint256) {
        return total;
    }

    function crop() internal override returns (uint256) {
        if (live == 1) {
            pool.getReward();
        }
        return super.crop();
    }

    function join(address urn, address usr, uint256 val) public override {
        super.join(urn, usr, val);
        if (val > 0) pool.stake(val);
    }

    function exit(address urn, address usr, uint256 val) public override {
        if (live == 1) {
            if (val > 0) pool.withdraw(val);
        }
        super.exit(urn, usr, val);
    }

    function flee(address urn, address usr) public override {
        if (live == 1) {
            uint256 val = vat.gem(ilk, urn);
            if (val > 0) pool.withdraw(val);
        }
        super.flee(urn, usr);
    }
    function cage() override public auth {
        require(live == 1, "SynthetixJoin/not-live");

        if (total > 0) pool.withdraw(total);
        live = 0;
    }
    function uncage() external auth {
        require(live == 0, "SynthetixJoin/live");

        if (total > 0) pool.stake(total);
        live = 1;
    }
}
