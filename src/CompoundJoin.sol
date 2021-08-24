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

interface CTokenLike is ERC20 {
    function admin() external returns (address);
    function pendingAdmin() external returns (address);
    function comptroller() external returns (address);
    function interestRateModel() external returns (address);
    function initialExchangeRateMantissa() external returns (uint256);
    function reserveFactorMantissa() external returns (uint256);
    function accrualBlockNumber() external returns (uint256);
    function borrowIndex() external returns (uint256);
    function totalBorrows() external returns (uint256);
    function totalReserves() external returns (uint256);
    function totalSupply() external returns (uint256);
    function accountTokens(address) external returns (uint256);
    function transferAllowances(address,address) external returns (uint256);

    function balanceOfUnderlying(address owner) external returns (uint256);
    function underlying() external view returns (address);
    function getAccountSnapshot(address account) external view returns (uint256, uint256, uint256, uint256);
    function borrowRatePerBlock() external view returns (uint256);
    function supplyRatePerBlock() external view returns (uint256);
    function totalBorrowsCurrent() external returns (uint256);
    function borrowBalanceCurrent(address account) external returns (uint256);
    function borrowBalanceStored(address account) external view returns (uint256);
    function exchangeRateCurrent() external returns (uint256);
    function exchangeRateStored() external view returns (uint256);
    function getCash() external view returns (uint256);
    function accrueInterest() external returns (uint256);
    function seize(address liquidator, address borrower, uint256 seizeTokens) external returns (uint256);

    function mint(uint256 mintAmount) external returns (uint256);
    function redeem(uint256 redeemTokens) external returns (uint256);
    function redeemUnderlying(uint256 redeemAmount) external returns (uint256);
    function borrow(uint256 borrowAmount) external returns (uint256);
    function repayBorrow(uint256 repayAmount) external returns (uint256);
    function repayBorrowBehalf(address borrower, uint256 repayAmount) external returns (uint256);
    function liquidateBorrow(address borrower, uint256 repayAmount, CTokenLike cTokenCollateral) external returns (uint256);
}

interface ComptrollerLike {
    function enterMarkets(address[] calldata cTokens) external returns (uint256[] memory);
    function claimComp(address[] calldata holders, address[] calldata cTokens, bool borrowers, bool suppliers) external;
    function compAccrued(address) external returns (uint256);
    function compBorrowerIndex(address,address) external returns (uint256);
    function compSupplierIndex(address,address) external returns (uint256);
    function seizeAllowed(
        address cTokenCollateral,
        address cTokenBorrowed,
        address liquidator,
        address borrower,
        uint256 seizeTokens) external returns (uint256);
    function getAccountLiquidity(address) external returns (uint256,uint256,uint256);
    function markets(address) external returns (bool,uint256,bool);
}

contract CompoundJoinImp is CropJoinImp {
    CTokenLike      immutable public cgem;
    ComptrollerLike           public comptroller;
    uint256                   public minf = 0;  // minimum target collateral factor [wad]
    uint256                   public maxf = 0;  // maximum target collateral factor [wad]
    uint256                   public dust = 0;  // value (in gems) below which to stop looping

    // --- Events ---
    event File(bytes32 indexed what, address data);
    event File(bytes32 indexed what, uint256 data);

    /**
        @param vat_                 MCD_VAT DSS core accounting module
        @param ilk_                 Collateral type
        @param gem_                 The collateral LP token address
        @param comp_                The COMP token contract address.
        @param cgem_                The cToken which the underlying token is the gem.
        @param comptroller_         The Compound Comptroller address.
    */
    constructor(
        address vat_,
        bytes32 ilk_,
        address gem_,
        address comp_,
        address cgem_,
        address comptroller_
    )
        public
        CropJoinImp(vat_, ilk_, gem_, comp_)
    {
        // Sanity checks
        require(CTokenLike(cgem_).comptroller() == comptroller_, "CompoundJoin/comptroller-mismatch");
        require(CTokenLike(cgem_).underlying() == gem_, "CompoundJoin/underlying-mismatch");

        cgem = CTokenLike(cgem_);
        comptroller = ComptrollerLike(comptroller_);

        ERC20(gem_).approve(cgem_, type(uint256).max);

        address[] memory ctokens = new address[](1);
        ctokens[0] = cgem_;
        uint256[] memory errors = new uint256[](1);
        errors = comptroller.enterMarkets(ctokens);
        require(errors[0] == 0);
    }

    // --- Math ---
    function zsub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        return sub(x, min(x, y));
    }
    function min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        return x <= y ? x : y;
    }

    // --- Administration ---
    function file(bytes32 what, address data) external auth {
        if (what == "comptroller") comptroller = ComptrollerLike(data);
        else revert("CompoundJoin/file-unrecognized-param");
        emit File(what, data);
    }
    function file(bytes32 what, uint256 data) external auth {
        if (what == "minf") require((minf = data) <= WAD, "CompoundJoin/bad-value");
        else if (what == "maxf") require((maxf = data) <= WAD, "CompoundJoin/bad-value");
        else if (what == "dust") dust = data;
        else revert("CompoundJoin/file-unrecognized-param");
        emit File(what, data);
    }

    function nav() public override returns (uint256) {
        return mul(
            add(
                gem.balanceOf(address(this)),
                sub(
                    cgem.balanceOfUnderlying(address(this)),
                    cgem.borrowBalanceCurrent(address(this))
                )
            ),
            to18ConversionFactor
        );
    }

    function crop() internal override returns (uint256) {
        address[] memory ctokens = new address[](1);
        address[] memory users   = new address[](1);
        ctokens[0] = address(cgem);
        users  [0] = address(this);

        comptroller.claimComp(users, ctokens, true, true);

        return super.crop();
    }

    function join(address urn, address usr, uint256 val) public override {
        super.join(urn, usr, val);
        require(cgem.mint(val) == 0);
    }

    function exit(address urn, address usr, uint256 val) public override {
        require(cgem.redeemUnderlying(val) == 0);
        super.exit(urn, usr, val);
    }

    function flee(address urn, address usr) public override {
        uint256 wad = vat.gem(ilk, urn);
        uint256 val = wmul(wmul(wad, nps()), toGemConversionFactor);
        require(cgem.redeemUnderlying(val) == 0);
        super.flee(urn, usr);
    }

    // --- Recursive Leverage Controls (Used by Keeper) ---

    // borrow_: how much underlying to borrow (dec decimals)
    // loops_:  how many times to repeat a max borrow loop before the
    //          specified borrow/mint
    // loan_:  how much underlying to lend to the contract for this
    //         transaction
    function wind(uint256 borrow_, uint256 loops_, uint256 loan_) external {
        require(cgem.accrueInterest() == 0);
        if (loan_ > 0) {
            require(gem.transferFrom(msg.sender, address(this), loan_));
        }
        uint256 gems = gem.balanceOf(address(this));
        if (gems > 0) {
            require(cgem.mint(gems) == 0);
        }
        (,uint256 cf,) = comptroller.markets(address(cgem));

        for (uint256 i=0; i < loops_; i++) {
            uint256 s = cgem.balanceOfUnderlying(address(this));
            uint256 b = cgem.borrowBalanceStored(address(this));
            // math overflow if
            //   - b / (s + L) > cf  [insufficient loan to unwind]
            //   - minf > 1e18       [bad configuration]
            //   - minf < u          [can't wind over minf]
            uint256 x1 = sub(wmul(s, cf), b);
            uint256 x2 = wdiv(sub(wmul(sub(s, loan_), minf), b),
                           sub(1e18, minf));
            uint256 max_borrow = min(x1, x2);
            if (max_borrow < dust) break;
            require(cgem.borrow(max_borrow) == 0);
            require(cgem.mint(max_borrow) == 0);
        }
        if (borrow_ > 0) {
            require(cgem.borrow(borrow_) == 0);
            require(cgem.mint(borrow_) == 0);
        }
        if (loan_ > 0) {
            require(cgem.redeemUnderlying(loan_) == 0);
            require(gem.transfer(msg.sender, loan_));
        }

        uint256 u = wdiv(cgem.borrowBalanceStored(address(this)),
                      cgem.balanceOfUnderlying(address(this)));
        require(u < maxf, "bad-wind");
    }
    // repay_: how much underlying to repay (dec decimals)
    // loops_: how many times to repeat a max repay loop before the
    //         specified redeem/repay
    // exit_:  how much underlying to remove following unwind
    // loan_:  how much underlying to lend to the contract for this
    //         transaction
    function unwind(uint256 repay_, uint256 loops_, uint256 exit_, uint256 loan_) external {
        require(cgem.accrueInterest() == 0);
        uint256 u = wdiv(cgem.borrowBalanceStored(address(this)),
                      cgem.balanceOfUnderlying(address(this)));
        if (loan_ > 0) {
            require(gem.transferFrom(msg.sender, address(this), loan_));
        }
        require(cgem.mint(gem.balanceOf(address(this))) == 0, "failed-mint");
        (,uint256 cf,) = comptroller.markets(address(cgem));

        for (uint256 i=0; i < loops_; i++) {
            uint256 s = cgem.balanceOfUnderlying(address(this));
            uint256 b = cgem.borrowBalanceStored(address(this));
            // math overflow if
            //   - [insufficient loan to unwind]
            //   - [insufficient loan for exit]
            //   - [bad configuration]
            uint256 x1 = wdiv(sub(wmul(s, cf), b), cf);
            uint256 x2 = wdiv(zsub(add(b, wmul(exit_, maxf)),
                               wmul(sub(s, loan_), maxf)),
                           sub(1e18, maxf));
            uint256 max_repay = min(x1, x2);
            if (max_repay < dust) break;
            require(cgem.redeemUnderlying(max_repay) == 0, "failed-redeem");
            require(cgem.repayBorrow(max_repay) == 0, "failed-repay");
        }
        if (repay_ > 0) {
            require(cgem.redeemUnderlying(repay_) == 0, "failed-redeem");
            require(cgem.repayBorrow(repay_) == 0, "failed-repay");
        }
        if (exit_ > 0 || loan_ > 0) {
            require(cgem.redeemUnderlying(add(exit_, loan_)) == 0, "failed-redeem");
        }
        if (loan_ > 0) {
            require(gem.transfer(msg.sender, loan_), "failed-transfer");
        }
        //if (exit_ > 0) {
        //    exit(exit_);
        //}

        uint256 nb = cgem.balanceOfUnderlying(address(this));
        uint256 u_ = nb > 0 ? wdiv(cgem.borrowBalanceStored(address(this)), nb) : 0;
        bool ramping = u  <  minf && u_ > u && u_ < maxf;
        bool damping = u  >  maxf && u_ < u && u_ > minf;
        bool tamping = u_ >= minf && u_ <= maxf;
        require(ramping || damping || tamping, "bad-unwind");
    }
}
