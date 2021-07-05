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

interface CToken is ERC20 {
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
    function liquidateBorrow(address borrower, uint256 repayAmount, CToken cTokenCollateral) external returns (uint256);
}

interface Comptroller {
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
}

interface Strategy {
    function nav() external returns (uint256);
    function harvest() external;
    function join(uint256) external;
    function exit(uint256) external;
    // temporary
    function wind(uint256,uint256,uint256) external;
    function unwind(uint256,uint256,uint256,uint256) external;
    function cgem() external returns (address);
    function maxf() external returns (uint256);
    function minf() external returns (uint256);
}

contract CompoundJoin is CropJoin {

    Strategy public immutable strategy;

    constructor(address vat_, bytes32 ilk_, address gem_, address comp_, address strategy_)
        public
        CropJoin(vat_, ilk_, gem_, comp_)
    {
        strategy = Strategy(strategy_);
        ERC20(gem_).approve(strategy_, type(uint256).max);
    }
    function nav() public override returns (uint256) {
        uint256 _nav = add(strategy.nav(), gem.balanceOf(address(this)));
        return mul(_nav, to18ConversionFactor);
    }
    function crop() internal override returns (uint256) {
        strategy.harvest();
        return super.crop();
    }
    function join(address urn, address usr, uint256 val) public override {
        super.join(urn, usr, val);
        strategy.join(val);
    }
    function exit(address urn, address usr, uint256 val) public override {
        strategy.exit(val);
        super.exit(urn, usr, val);
    }
    function flee(address urn, address usr) public override {
        uint256 wad = vat.gem(ilk, urn);
        uint256 val = wmul(wmul(wad, nps()), toGemConversionFactor);
        strategy.exit(val);
        super.flee(urn, usr);
    }

    // todo: remove?
    // need to deal with instances of adapter.unwind in tests
    /*function unwind(uint256 repay_, uint256 loops_, uint256 exit_, uint256 loan_) external {
        gem.transferFrom(msg.sender, address(this), loan_);
        strategy.unwind(repay_, loops_, exit_, loan_);
        super.exit(exit_);
        gem.transfer(msg.sender, loan_);
    }*/
}

contract CompStrat {
    ERC20       public immutable gem;
    CToken      public immutable cgem;
    CToken      public immutable comp;
    Comptroller public immutable comptroller;
    uint256     public immutable dust;  // value (in gems) below which to stop looping

    uint256 public cf   = 0;  // ctoken max collateral factor       [wad]
    uint256 public maxf = 0;  // maximum target collateral factor   [wad]
    uint256 public minf = 0;  // minimum target collateral factor   [wad]

    constructor(address gem_, address cgem_, address comp_, address comptroller_, uint256 dust_)
        public
    {
        wards[msg.sender] = 1;

        gem  = ERC20(gem_);
        cgem = CToken(cgem_);
        comp = CToken(comp_);
        comptroller = Comptroller(comptroller_);
        dust = dust_;

        ERC20(gem_).approve(cgem_, type(uint256).max);

        address[] memory ctokens = new address[](1);
        ctokens[0] = cgem_;
        uint256[] memory errors = new uint256[](1);
        errors = Comptroller(comptroller_).enterMarkets(ctokens);
        require(errors[0] == 0);
    }

    function add(uint256 x, uint256 y) public pure returns (uint256 z) {
        require((z = x + y) >= x, "ds-math-add-overflow");
    }
    function sub(uint256 x, uint256 y) public pure returns (uint256 z) {
        require((z = x - y) <= x, "ds-math-sub-underflow");
    }
    function zsub(uint256 x, uint256 y) public pure returns (uint256 z) {
        return sub(x, min(x, y));
    }
    function mul(uint256 x, uint256 y) public pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x, "ds-math-mul-overflow");
    }
    uint256 constant WAD  = 10 ** 18;
    function wmul(uint256 x, uint256 y) public pure returns (uint256 z) {
        z = mul(x, y) / WAD;
    }
    function wdiv(uint256 x, uint256 y) public pure returns (uint256 z) {
        z = mul(x, WAD) / y;
    }
    function min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        return x <= y ? x : y;
    }

    function nav() public returns (uint256) {
        uint256 _nav = add(gem.balanceOf(address(this)),
                        sub(cgem.balanceOfUnderlying(address(this)),
                            cgem.borrowBalanceCurrent(address(this))));
        return _nav;
    }

    function harvest() external auth {
        address[] memory ctokens = new address[](1);
        address[] memory users   = new address[](1);
        ctokens[0] = address(cgem);
        users  [0] = address(this);

        comptroller.claimComp(users, ctokens, true, true);
        comp.transfer(msg.sender, comp.balanceOf(address(this)));
    }

    // --- Auth ---
    mapping (address => uint256) public wards;
    function rely(address usr) external auth { wards[usr] = 1; }
    function deny(address usr) external auth { wards[usr] = 0; }
    modifier auth {
        require(wards[msg.sender] == 1, "CompStrat/not-authorized");
        _;
    }

    function join(uint256 val) public auth {
        gem.transferFrom(msg.sender, address(this), val);
    }
    function exit(uint256 val) public auth {
        gem.transfer(msg.sender, val);
    }

    function tune(uint256 cf_, uint256 maxf_, uint256 minf_) external auth {
        cf   = cf_;
        maxf = maxf_;
        minf = minf_;
    }

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

        for (uint256 i=0; i < loops_; i++) {
            uint256 s = cgem.balanceOfUnderlying(address(this));
            uint256 b = cgem.borrowBalanceStored(address(this));
            // math overflow if
            //   - [insufficient loan to unwind]
            //   - [insufficient loan for exit]
            //   - [bad configuration]
            uint256 x1 = wdiv(sub(wmul(s, cf), b), cf);
            uint256 x2 = wdiv(this.zsub(add(b, wmul(exit_, maxf)),
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
        if (exit_ > 0) {
            exit(exit_);
        }

        uint256 u_ = wdiv(cgem.borrowBalanceStored(address(this)),
                       cgem.balanceOfUnderlying(address(this)));
        bool ramping = u  <  minf && u_ > u && u_ < maxf;
        bool damping = u  >  maxf && u_ < u && u_ > minf;
        bool tamping = u_ >= minf && u_ <= maxf;
        require(ramping || damping || tamping, "bad-unwind");
    }
}
