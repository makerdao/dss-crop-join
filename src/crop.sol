pragma solidity ^0.6.7;

interface ERC20 {
    function balanceOf(address owner) external view returns (uint);
    function transfer(address dst, uint amount) external returns (bool);
    function transferFrom(address src, address dst, uint amount) external returns (bool);
    function approve(address spender, uint amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint);
    function decimals() external returns (uint8);
}

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
}

interface VatLike {
    function slip(bytes32 ilk, address usr, int256 wad) external;
    function flux(bytes32 ilk, address src, address dst, uint256 wad) external;
}

contract MockVat is VatLike {
    struct Urn {
        uint256 ink;   // Locked Collateral  [wad]
        uint256 art;   // Normalised Debt    [wad]
    }
    mapping (bytes32 => mapping (address => Urn )) public urns;
    mapping (bytes32 => mapping (address => uint)) public gem;
    function add(uint x, int y) internal pure returns (uint z) {
        z = x + uint(y);
        require(y >= 0 || z <= x);
        require(y <= 0 || z >= x);
    }
    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x);
    }
    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x);
    }
    function slip(bytes32 ilk, address usr, int256 wad) external override {
        gem[ilk][usr] = add(gem[ilk][usr], wad);
    }
    function flux(bytes32 ilk, address src, address dst, uint256 wad) external override {
        gem[ilk][src] = sub(gem[ilk][src], wad);
        gem[ilk][dst] = add(gem[ilk][dst], wad);
    }
}

// receives tokens and shares them among holders
contract CropJoin {
    VatLike     public vat;
    bytes32     public ilk;
    ERC20       public gem;
    uint256     public dec;

    CToken      public cgem;
    ERC20       public comp;
    Comptroller public comptroller;

    uint256     public share;  // crops per gem
    uint256     public total;  // total gems
    uint256     public stock;  // crop balance

    mapping (address => uint) public crops;   // crops per user
    mapping (address => uint) public balance; // gems per user

    constructor(address vat_, bytes32 ilk_, address gem_,
                address cgem_, address comp_, address comptroller_) public
    {
        vat = VatLike(vat_);
        ilk = ilk_;
        gem = ERC20(gem_);
        dec = gem.decimals();
        require(dec <= 18);

        cgem = CToken(cgem_);
        comp = ERC20(comp_);
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

    function crop() internal virtual returns (uint) {
        address[] memory ctokens = new address[](1);
        address[] memory users   = new address[](1);
        ctokens[0] = address(cgem);
        users  [0] = address(this);

        comptroller.claimComp(users, ctokens, true, true);
        return sub(comp.balanceOf(address(this)), stock);
    }

    // decimals: underlying=dec cToken=8 comp=18 gem=18
    function join(uint256 val) public {
        uint wad = mul(val, 10 ** (18 - dec));
        require(int(wad) >= 0);

        if (total > 0) share = add(share, wdiv(crop(), total));

        address usr = msg.sender;
        require(comp.transfer(msg.sender, sub(wmul(balance[usr], share), crops[usr])));
        stock = comp.balanceOf(address(this));
        if (wad > 0) {
            require(gem.transferFrom(usr, address(this), val));
            vat.slip(ilk, usr, int(wad));
            total = add(total, wad);
            balance[usr] = add(balance[usr], wad);
        }
        crops[usr] = wmul(balance[usr], share);
    }

    function exit(uint val) public {
        uint wad = mul(val, 10 ** (18 - dec));
        require(wad <= 2 ** 255);

        if (total > 0) share = add(share, wdiv(crop(), total));

        address usr = msg.sender;
        require(comp.transfer(msg.sender, sub(wmul(balance[usr], share), crops[usr])));
        stock = comp.balanceOf(address(this));
        if (wad > 0) {
            require(gem.transfer(usr, val));
            vat.slip(ilk, usr, -int(wad));

            total = sub(total, wad);
            balance[usr] = sub(balance[usr], wad);
        }
        crops[usr] = wmul(balance[usr], share);
    }

    function flee(uint wad) public {
        address usr = msg.sender;

        require(gem.transfer(usr, wad));
        vat.slip(ilk, usr, -int(wad));

        total = sub(total, wad);
        balance[usr] = sub(balance[usr], wad);
        crops[usr] = wmul(balance[usr], share);
    }

    // todo: tests, simple mock
    // todo: tests, mainnet fork
    // todo: flash loan alternative to wind - check gas of wind

    // todo: compound liquidations
    // liquidation:
    //   - cTokens are seized from our supply
    //   - balanceOfUnderlying decreases.
    //   - borrowBalance also decreases,
    //   - now under 100% utilization
    //   - less underlying than before => usdc amount down
    //   - user balances / total must be scaled down
    //   - oracle must report lower price

    // todo: doesn't interest accumulation reduce the value of the gem?
    // todo: demonstrate with a test
    // interest:
    //   - supply / borrow nets interest rate
    //   - comp income offsets interest
    //   - comp goes direct to users
    //   - total usdc in adapter must be decreasing over time
    //   - have to constantly adjust balances / total downwards
    //     - balance[usr]      <-- scaling factor
    //     - total             <-- scaling factor
    //     - vat.gem, vat.ink  <-- spot adjustment
    //   - same / similar process to liquidation (?)

    // todo: update cd on each wind / unwind?
    uint256 public cf   = 0.75   ether;  // usdc max collateral factor
    uint256 public maxf = 0.675  ether;  // maximum collateral factor  (90%)
    uint256 public minf = 0.6375 ether;  // minimum collateral factor  (85%)

    // borrow_: how much underlying to borrow (dec decimals)
    // n: how many times to repeat a max borrow loop before the
    //    specified borrow/mint
    function wind(uint borrow_, uint n) public {
        require(cgem.accrueInterest() == 0);
        require(cgem.mint(gem.balanceOf(address(this))) == 0);
        uint max_borrow;
        for (uint i=0; i < n; i++) {
            max_borrow = sub(wmul(cgem.balanceOfUnderlying(address(this)), cf),
                             cgem.borrowBalanceStored(address(this)));
            require(cgem.borrow(max_borrow) == 0);
            require(cgem.mint(max_borrow) == 0);
        }
        require(cgem.borrow(borrow_) == 0);
        require(cgem.mint(borrow_) == 0);
        uint u = wdiv(cgem.borrowBalanceStored(address(this)),
                      cgem.balanceOfUnderlying(address(this)));
        require(u < maxf);
    }
    // repay_:  how much underlying to repay (dec decimals)
    // n: how many times to repeat a max repay loop before the
    //    specified redeem/repay
    function unwind(uint repay_, uint n) public {
        require(cgem.accrueInterest() == 0);
        require(cgem.mint(gem.balanceOf(address(this))) == 0);
        uint u = wdiv(cgem.borrowBalanceStored(address(this)),
                      cgem.balanceOfUnderlying(address(this)));
        require(u > maxf);

        uint max_repay;
        for (uint i=0; i < n ; i++) {
            max_repay = sub(cgem.balanceOfUnderlying(address(this)),
                            wdiv(cgem.borrowBalanceStored(address(this)), cf));
            require(cgem.redeemUnderlying(max_repay) == 0);
            require(cgem.repayBorrow(max_repay) == 0);
        }
        require(cgem.redeemUnderlying(repay_) == 0);
        require(cgem.repayBorrow(repay_) == 0);
        uint u_ = wdiv(cgem.borrowBalanceStored(address(this)),
                       cgem.balanceOfUnderlying(address(this)));
        require(u_ < u);
        require(u_ > minf);
    }

    function pour(uint val, uint loan) public {
        require(cgem.accrueInterest() == 0);

        require(gem.transferFrom(msg.sender, address(this), loan));
        require(cgem.mint(loan) == 0);

        uint s = cgem.balanceOfUnderlying(address(this));
        uint b = cgem.borrowBalanceStored(address(this));
        uint r = wdiv(sub(wmul(s, cf), b), cf);  // ensure rounding down
        require(cgem.redeemUnderlying(r) == 0);
        require(cgem.repayBorrow(r) == 0);
        require(cgem.redeemUnderlying(add(val, loan)) == 0);
        uint u = wdiv(cgem.borrowBalanceStored(address(this)),
                      cgem.balanceOfUnderlying(address(this)));
        require(u < maxf);
        exit(val);

        require(gem.transfer(msg.sender, loan));
    }
    function pour(uint val) public {
        pour(val, 0);
    }
}
