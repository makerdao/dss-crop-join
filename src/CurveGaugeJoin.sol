// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2022 Dai Foundation
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

interface LiquidityGaugeLike {
    function crv_token() external view returns (address);
    function lp_token() external view returns (address);
    function minter() external view returns (address);
    function deposit(uint256) external;
    function withdraw(uint256) external;
}

interface LiquidityGaugeMinterLike {
    function mint_for(address,address) external;
}

// Join adapter for the Curve gauge contract
contract CurveGaugeJoinImp is CropJoinImp {

    LiquidityGaugeLike          immutable public pool;
    LiquidityGaugeMinterLike    immutable public minter;

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
        require(LiquidityGaugeLike(pool_).crv_token() == bonus_, "CurveGaugeJoin/bonus-mismatch");
        require(LiquidityGaugeLike(pool_).lp_token() == gem_, "CurveGaugeJoin/gem-mismatch");

        pool = LiquidityGaugeLike(pool_);
        minter = LiquidityGaugeMinterLike(LiquidityGaugeLike(pool_).minter());
    }

    function init() external {
        gem.approve(address(pool), type(uint256).max);
    }

    function nav() public override view returns (uint256) {
        return total;
    }

    function crop() internal override returns (uint256) {
        if (live == 1) {
            minter.mint_for(address(pool), address(this));
        }
        return super.crop();
    }

    function join(address urn, address usr, uint256 val) public override {
        super.join(urn, usr, val);
        if (val > 0) pool.deposit(val);
    }

    function exit(address urn, address usr, uint256 val) public override {
        if (live == 1) {
            if (val > 0) pool.withdraw(val);
        }
        super.exit(urn, usr, val);
    }

    function flee(address urn, address usr, uint256 val) public override {
        if (live == 1) {
            if (val > 0) pool.withdraw(val);
        }
        super.flee(urn, usr, val);
    }
    function cage() override public auth {
        require(live == 1, "CurveGaugeJoin/not-live");

        if (total > 0) pool.withdraw(total);
        live = 0;
    }
    function uncage() external auth {
        require(live == 0, "CurveGaugeJoin/live");

        if (total > 0) pool.deposit(total);
        live = 1;
    }
}
