pragma solidity ^0.6.7;
pragma experimental ABIEncoderV2;

import "./crop.sol";

interface CToken is ERC20 {
    function admin() external returns (address);
    function pendingAdmin() external returns (address);
    function comptroller() external returns (address);
    function interestRateModel() external returns (address);
    function initialExchangeRateMantissa() external returns (uint);
    function reserveFactorMantissa() external returns (uint);
    function accrualBlockNumber() external returns (uint);
    function borrowIndex() external returns (uint);
    function totalBorrows() external returns (uint);
    function totalReserves() external returns (uint);
    function totalSupply() external returns (uint);
    function accountTokens(address) external returns (uint);
    function transferAllowances(address,address) external returns (uint);

    function balanceOfUnderlying(address owner) external returns (uint);
    function getAccountSnapshot(address account) external view returns (uint, uint, uint, uint);
    function borrowRatePerBlock() external view returns (uint);
    function supplyRatePerBlock() external view returns (uint);
    function totalBorrowsCurrent() external returns (uint);
    function borrowBalanceCurrent(address account) external returns (uint);
    function borrowBalanceStored(address account) external view returns (uint);
    function exchangeRateCurrent() external returns (uint);
    function exchangeRateStored() external view returns (uint);
    function getCash() external view returns (uint);
    function accrueInterest() external returns (uint);
    function seize(address liquidator, address borrower, uint seizeTokens) external returns (uint);

    function mint(uint mintAmount) external returns (uint);
    function redeem(uint redeemTokens) external returns (uint);
    function redeemUnderlying(uint redeemAmount) external returns (uint);
    function borrow(uint borrowAmount) external returns (uint);
    function repayBorrow(uint repayAmount) external returns (uint);
    function repayBorrowBehalf(address borrower, uint repayAmount) external returns (uint);
    function liquidateBorrow(address borrower, uint repayAmount, CToken cTokenCollateral) external returns (uint);
}

interface Comptroller {
    function enterMarkets(address[] calldata cTokens) external returns (uint[] memory);
    function claimComp(address[] calldata holders, address[] calldata cTokens, bool borrowers, bool suppliers) external;
    function compAccrued(address) external returns (uint);
    function compBorrowerIndex(address,address) external returns (uint);
    function compSupplierIndex(address,address) external returns (uint);
    function seizeAllowed(
        address cTokenCollateral,
        address cTokenBorrowed,
        address liquidator,
        address borrower,
        uint seizeTokens) external returns (uint);
    function getAccountLiquidity(address) external returns (uint,uint,uint);
}

interface Strategy {
    function nav() external returns (uint);
    function harvest() external;
    function join(uint) external;
    function exit(uint) external;
    // temporary
    function wind(uint,uint,uint) external;
    function unwind(uint,uint,uint,uint) external;
    function cgem() external returns (address);
    function maxf() external returns (uint256);
    function minf() external returns (uint256);
}

contract USDCJoin is CropJoin {
    Strategy public strategy;
    constructor(address vat_, bytes32 ilk_, address gem_, address comp_, address strategy_)
        public
        CropJoin(vat_, ilk_, gem_, comp_)
    {
        strategy = Strategy(strategy_);
        gem.approve(strategy_, uint(-1));
    }
    function nav() public override returns (uint) {
        uint _nav = add(strategy.nav(), gem.balanceOf(address(this)));
        return mul(_nav, 10 ** (18 - dec));
    }
    function crop() internal override returns (uint) {
        strategy.harvest();
        return super.crop();
    }
    function join(uint val) public override {
        super.join(val);
        strategy.join(val);
    }
    function exit(uint val) public override {
        strategy.exit(val);
        super.exit(val);
    }
    function flee() public override {
        address usr = msg.sender;
        uint wad = vat.gem(ilk, usr);
        uint val = wmul(wmul(wad, nps()), 10 ** dec);
        strategy.exit(val);
        super.flee();
    }

    // todo: remove?
    function wind(uint borrow_, uint loops_, uint loan_) external {
        strategy.wind(borrow_, loops_, loan_);
    }
    function unwind(uint repay_, uint loops_, uint exit_, uint loan_) external {
        strategy.unwind(repay_, loops_, exit_, loan_);
    }
    function cgem() external returns (address) {
        return strategy.cgem();
    }
    function maxf() external returns (uint256) {
        return strategy.maxf();
    }
    function minf() external returns (uint256) {
        return strategy.minf();
    }
}

contract CompStrat {
    ERC20       public gem;    // collateral token
    CToken      public cgem;
    CToken      public comp;
    Comptroller public comptroller;

    uint256 public cf   = 0.75   ether;  // usdc max collateral factor
    uint256 public maxf = 0.675  ether;  // maximum collateral factor  (90%)
    uint256 public minf = 0.674  ether;  // minimum collateral factor  (85%)

    constructor(address gem_, address cgem_, address comp_, address comptroller_)
        public
    {
        wards[msg.sender] = 1;

        gem  = ERC20(gem_);
        cgem = CToken(cgem_);
        comp = CToken(comp_);
        comptroller = Comptroller(comptroller_);

        gem.approve(address(cgem), uint(-1));

        address[] memory ctokens = new address[](1);
        ctokens[0] = address(cgem);
        uint256[] memory errors = new uint[](1);
        errors = comptroller.enterMarkets(ctokens);
        require(errors[0] == 0);
    }

    function add(uint x, uint y) public pure returns (uint z) {
        require((z = x + y) >= x, "ds-math-add-overflow");
    }
    function sub(uint x, uint y) public pure returns (uint z) {
        require((z = x - y) <= x, "ds-math-sub-underflow");
    }
    function mul(uint x, uint y) public pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x, "ds-math-mul-overflow");
    }
    uint256 constant WAD  = 10 ** 18;
    function wmul(uint x, uint y) public pure returns (uint z) {
        z = mul(x, y) / WAD;
    }
    function wdiv(uint x, uint y) public pure returns (uint z) {
        z = mul(x, WAD) / y;
    }
    function min(uint x, uint y) internal pure returns (uint z) {
        return x <= y ? x : y;
    }

    function nav() public returns (uint) {
        uint _nav = add(gem.balanceOf(address(this)),
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
    mapping (address => uint) public wards;
    function rely(address usr) external auth { wards[usr] = 1; }
    function deny(address usr) external auth { wards[usr] = 0; }
    modifier auth {
        require(wards[msg.sender] == 1, "GemJoin/not-authorized");
        _;
    }

    function join(uint256 val) public auth {
        gem.transferFrom(msg.sender, address(this), val);
    }
    function exit(uint256 val) public auth {
        gem.transfer(msg.sender, val);
    }

    // TODO: `cage`
    //        - bypass `crop`
    //        - set target to 0

    // borrow_: how much underlying to borrow (dec decimals)
    // loops_:  how many times to repeat a max borrow loop before the
    //          specified borrow/mint
    // loan_:  how much underlying to lend to the contract for this
    //         transaction
    function wind(uint borrow_, uint loops_, uint loan_) external {
        require(cgem.accrueInterest() == 0);
        if (loan_ > 0) {
            require(gem.transferFrom(msg.sender, address(this), loan_));
        }
        uint gems = gem.balanceOf(address(this));
        if (gems > 0) {
            require(cgem.mint(gems) == 0);
        }

        for (uint i=0; i < loops_; i++) {
            uint s = cgem.balanceOfUnderlying(address(this));
            uint b = cgem.borrowBalanceStored(address(this));
            uint x1 = sub(wmul(s, cf), b);
            uint x2 = wdiv(sub(wmul(sub(s, loan_), minf), b),
                           sub(1e18, minf));
            uint max_borrow = min(x1, x2);
            if (max_borrow > 0) {
                require(cgem.borrow(max_borrow) == 0);
                require(cgem.mint(max_borrow) == 0);
            }
        }
        if (borrow_ > 0) {
            require(cgem.borrow(borrow_) == 0);
            require(cgem.mint(borrow_) == 0);
        }
        if (loan_ > 0) {
            require(cgem.redeemUnderlying(loan_) == 0);
            require(gem.transfer(msg.sender, loan_));
        }

        uint u = wdiv(cgem.borrowBalanceStored(address(this)),
                      cgem.balanceOfUnderlying(address(this)));
        require(u < maxf);
    }
    // repay_: how much underlying to repay (dec decimals)
    // loops_: how many times to repeat a max repay loop before the
    //         specified redeem/repay
    // exit_:  how much underlying to remove following unwind
    // loan_:  how much underlying to lend to the contract for this
    //         transaction
    function unwind(uint repay_, uint loops_, uint exit_, uint loan_) external {
        require(cgem.accrueInterest() == 0);
        uint u = wdiv(cgem.borrowBalanceStored(address(this)),
                      cgem.balanceOfUnderlying(address(this)));
        if (loan_ > 0) {
            require(gem.transferFrom(msg.sender, address(this), loan_));
        }
        require(cgem.mint(gem.balanceOf(address(this))) == 0);

        for (uint i=0; i < loops_; i++) {
            uint s = cgem.balanceOfUnderlying(address(this));
            uint b = cgem.borrowBalanceStored(address(this));
            uint x1 = wdiv(sub(wmul(s, cf), b), cf);
            uint x2 = wdiv(sub(add(b, wmul(exit_, maxf)),
                               wmul(sub(s, loan_), maxf)),
                           sub(1e18, maxf));
            uint max_repay = min(x1, x2);
            if (max_repay > 0) {
                require(cgem.redeemUnderlying(max_repay) == 0);
                require(cgem.repayBorrow(max_repay) == 0);
            }
        }
        if (repay_ > 0) {
            require(cgem.redeemUnderlying(repay_) == 0);
            require(cgem.repayBorrow(repay_) == 0);
        }
        if (exit_ > 0 || loan_ > 0) {
            require(cgem.redeemUnderlying(add(exit_, loan_)) == 0);
        }
        if (loan_ > 0) {
            require(gem.transfer(msg.sender, loan_));
        }
        if (exit_ > 0) {
            exit(exit_);
        }

        uint u_ = wdiv(cgem.borrowBalanceStored(address(this)),
                       cgem.balanceOfUnderlying(address(this)));
        bool ramping = u  < minf && u_ > u && u_ < maxf;
        bool damping = u  > maxf && u_ < u && u_ > minf;
        bool tamping = u_ > minf && u_ < maxf;
        require(ramping || damping || tamping);
    }
}
