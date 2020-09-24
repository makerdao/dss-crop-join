pragma solidity ^0.6.7;

interface ERC20 {
    function transfer(address,uint) external returns (bool);
    function transferFrom(address,address,uint) external returns (bool);
    function balanceOf(address) external returns (uint);
    function approve(address,uint) external returns (bool);
    function decimals() external returns (uint8);
}

interface CToken is ERC20 {
    function balanceOfUnderlying(address owner) external returns (uint);
    function borrowBalanceCurrent(address account) external returns (uint);
    function borrowBalanceStored(address account) external returns (uint);
    function exchangeRateCurrent() external returns (uint);
    function accrueInterest() external returns (uint);

    function mint(uint mintAmount) external returns (uint);
    function redeem(uint redeemTokens) external returns (uint);
    function redeemUnderlying(uint redeemAmount) external returns (uint);
    function borrow(uint borrowAmount) external returns (uint);
    function repayBorrow(uint repayAmount) external returns (uint);
}

interface Comptroller {
    function enterMarkets(address[] calldata cTokens) external returns (uint[] memory);
    function claimComp(address[] calldata holders, address[] calldata cTokens, bool borrowers, bool suppliers) external;
    function compAccrued(address) external returns (uint);
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
        require(10 ** dec == BASE);

        cgem = CToken(cgem_);
        comp = ERC20(comp_);
        comptroller = Comptroller(comptroller_);

        // address[] memory ctokens = new address[](1);
        // ctokens[0] = address(cgem_);
        // comptroller.enterMarkets(ctokens);
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
    uint256 constant BASE = 10 ** 6;
    function wmul(uint x, uint y) public pure returns (uint z) {
        z = mul(x, y) / WAD;
    }
    function wdiv(uint x, uint y) public pure returns (uint z) {
        z = mul(x, WAD) / y;
    }
    function ddiv(uint x, uint y) public pure returns (uint z) {
        z = mul(x, BASE) / y;
    }

    function crop() internal virtual returns (uint) {
        address[] memory ctokens = new address[](1);
        address[] memory users   = new address[](1);
        ctokens[0] = address(cgem);
        users  [0] = address(this);

        uint prev = comp.balanceOf(address(this));
        comptroller.claimComp(users, ctokens, true, true);
        return comp.balanceOf(address(this)) - prev;
    }

    // usdc:  6 decimals
    // cusdc: 8 decimals
    // comp: 18 decimals
    // gem:  18 decimals
    function join(uint256 val) public {
        uint wad = mul(val, 10 ** (18 - dec));
        require(int(wad) >= 0);

        if (total > 0) share = add(share, wdiv(crop(), total));

        address usr = msg.sender;
        require(comp.transfer(msg.sender, sub(wmul(balance[usr], share), crops[usr])));
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
        if (wad > 0) {
            require(gem.transferFrom(address(this), usr, val));
            vat.slip(ilk, usr, -int(wad));

            total = sub(total, wad);
            balance[usr] = sub(balance[usr], wad);
        }
        crops[usr] = wmul(balance[usr], share);
    }

    function flee(uint wad) public {
        address usr = msg.sender;

        require(gem.transferFrom(address(this), usr, wad));
        vat.slip(ilk, usr, -int(wad));

        total = sub(total, wad);
        balance[usr] = sub(balance[usr], wad);
        crops[usr] = wmul(balance[usr], share);
    }

    // move to constructor
    function init() public {
        address[] memory ctokens = new address[](1);
        ctokens[0] = address(cgem);
        comptroller.enterMarkets(ctokens);
    }
    // todo: math, ctoken decimals
    //       cUSDC 8 USDC 6
    // oneCTokenInUnderlying = exchangeRateCurrent
    //                       / (1 * 10 ^ (18 + underlyingDecimals - cTokenDecimals))
    // todo: tests, simple mock
    // todo: tests, mainnet fork

    // todo: ctoken.accrueInterest() first, then use borrowBalanceStored

    // borrow_: how much underlying to borrow (6 decimals)
    // n: how many times to repeat a max borrow loop before the
    //    specified borrow/mint
    function wind(uint borrow_, uint n) public {
        cgem.mint(gem.balanceOf(address(this)));
        uint max_borrow;
        for (uint i=0; i < n; i++) {
            max_borrow = sub(wmul(cgem.balanceOfUnderlying(address(this)), 0.75 ether),
                             cgem.borrowBalanceCurrent(address(this)));
            require(cgem.borrow(max_borrow) == 0);
            require(cgem.mint(max_borrow) == 0);
        }
        require(cgem.borrow(borrow_) == 0);
        require(cgem.mint(borrow_) == 0);
        uint u = wdiv(cgem.borrowBalanceCurrent(address(this)),  // todo: correct div decimals
                      cgem.balanceOfUnderlying(address(this)));
        require(u < 0.675 ether); // 90% utilization. TODO: dynamic collateral factor?
    }
    // repay_: how much underlying to repay (6 decimals)
    // n: how many times to repeat a max repay loop before the
    //    specified redeem/repay
    function unwind(uint repay_, uint n) public {
        cgem.mint(gem.balanceOf(address(this)));
        uint u = wdiv(cgem.borrowBalanceCurrent(address(this)),
                      cgem.balanceOfUnderlying(address(this)));
        require(u > 0.675 ether); // 90% utilization

        uint max_repay;
        for (uint i=0; i < n; i++) {
            max_repay = sub(cgem.balanceOfUnderlying(address(this)),
                            wdiv(cgem.borrowBalanceCurrent(address(this)),
                                 0.75 ether));
            require(cgem.redeemUnderlying(max_repay) == 0);
            require(cgem.repayBorrow(max_repay) == 0);
        }
        require(cgem.redeemUnderlying(repay_) == 0);
        require(cgem.repayBorrow(repay_) == 0);
        uint u_ = wdiv(cgem.borrowBalanceCurrent(address(this)),
                       cgem.balanceOfUnderlying(address(this)));
        require(u_ < u);  // 88% utilization
    }
}
