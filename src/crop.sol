pragma solidity ^0.6.7;
pragma experimental ABIEncoderV2;

interface ERC20 {
    function balanceOf(address owner) external view returns (uint);
    function transfer(address dst, uint amount) external returns (bool);
    function transferFrom(address src, address dst, uint amount) external returns (bool);
    function approve(address spender, uint amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint);
    function decimals() external returns (uint8);
}

struct Urn {
    uint256 ink;   // Locked Collateral  [wad]
    uint256 art;   // Normalised Debt    [wad]
}

interface VatLike {
    function slip(bytes32 ilk, address usr, int256 wad) external;
    function flux(bytes32 ilk, address src, address dst, uint256 wad) external;
    function  gem(bytes32 ilk, address usr) external returns (uint);
    function urns(bytes32 ilk, address usr) external returns (Urn memory);
}

// receives tokens and shares them among holders
contract CropJoin {
    VatLike     public vat;    // cdp engine
    bytes32     public ilk;    // collateral type
    ERC20       public gem;    // collateral token
    uint256     public dec;    // gem decimals

    uint256     public share;  // crops per gem    [ray]
    uint256     public total;  // total gems       [wad]
    uint256     public stock;  // crop balance     [wad]

    mapping (address => uint) public crops; // crops per user  [wad]
    mapping (address => uint) public stake; // gems per user   [wad]

    ERC20       public bonus;  // rewards token

    constructor(address vat_, bytes32 ilk_, address gem_, address bonus_) public {
        vat = VatLike(vat_);
        ilk = ilk_;
        gem = ERC20(gem_);
        dec = gem.decimals();
        require(dec <= 18);

        bonus = ERC20(bonus_);
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
    uint256 constant RAY  = 10 ** 27;
    function rmul(uint x, uint y) public pure returns (uint z) {
        z = mul(x, y) / RAY;
    }
    function rdiv(uint x, uint y) public pure returns (uint z) {
        z = mul(x, RAY) / y;
    }
    function min(uint x, uint y) internal pure returns (uint z) {
        return x <= y ? x : y;
    }

    // Net Asset Valuation [wad]
    function nav() public virtual returns (uint) {
        uint _nav = gem.balanceOf(address(this));
        return mul(_nav, 10 ** (18 - dec));
    }

    // Net Assets per Share [wad]
    function nps() public returns (uint) {
        if (total == 0) return WAD;
        else return wdiv(nav(), total);
    }

    function crop() internal virtual returns (uint) {
        return sub(bonus.balanceOf(address(this)), stock);
    }

    // decimals: underlying=dec cToken=8 comp=18 gem=18
    function join(uint256 val) public {
        uint wad = wdiv(mul(val, 10 ** (18 - dec)), nps());
        require(int(wad) >= 0);

        if (total > 0) share = add(share, rdiv(crop(), total));

        address usr = msg.sender;
        require(bonus.transfer(msg.sender, sub(rmul(stake[usr], share), crops[usr])));
        stock = bonus.balanceOf(address(this));
        if (wad > 0) {
            require(gem.transferFrom(usr, address(this), val));
            vat.slip(ilk, usr, int(wad));

            total = add(total, wad);
            stake[usr] = add(stake[usr], wad);
        }
        crops[usr] = rmul(stake[usr], share);
    }

    function exit(uint val) public {
        uint wad = wdiv(mul(val, 10 ** (18 - dec)), nps());
        require(int(wad) >= 0);

        if (total > 0) share = add(share, rdiv(crop(), total));

        address usr = msg.sender;
        require(bonus.transfer(msg.sender, sub(rmul(stake[usr], share), crops[usr])));
        stock = bonus.balanceOf(address(this));
        if (wad > 0) {
            require(gem.transfer(usr, val));
            vat.slip(ilk, usr, -int(wad));

            total = sub(total, wad);
            stake[usr] = sub(stake[usr], wad);
        }
        crops[usr] = rmul(stake[usr], share);
    }

    function flee() public {
        address usr = msg.sender;

        uint wad = vat.gem(ilk, usr);
        uint val = wmul(wmul(wad, nps()), 10 ** dec);

        require(gem.transfer(usr, val));
        vat.slip(ilk, usr, -int(wad));

        total = sub(total, wad);
        stake[usr] = sub(stake[usr], wad);
        crops[usr] = rmul(stake[usr], share);
    }

    function tack(address src, address dst, uint wad) public {
        stake[src] = sub(stake[src], wad);
        stake[dst] = add(stake[dst], wad);

        crops[src] = sub(crops[src], rmul(share, wad));
        crops[dst] = add(crops[dst], rmul(share, wad));

        require(stake[src] >= add(vat.gem(ilk, src), vat.urns(ilk, src).ink));
        require(stake[dst] <= add(vat.gem(ilk, dst), vat.urns(ilk, dst).ink));
    }
}
