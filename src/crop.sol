pragma solidity ^0.6.7;

interface ERC20 {
    function transfer(address,uint) external;
    function transferFrom(address,address,uint) external;
    function balanceOf(address) external returns (uint);
}

interface Comptroller {
    function claimComp(address[] calldata holders, address[] calldata cTokens, bool borrowers, bool suppliers) external;
    function compAccrued(address) external returns (uint);
}

contract Vat {
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
    function slip(bytes32 ilk, address usr, int256 wad) external {
        gem[ilk][usr] = add(gem[ilk][usr], wad);
    }
    function flux(bytes32 ilk, address src, address dst, uint256 wad) external {
        gem[ilk][src] = sub(gem[ilk][src], wad);
        gem[ilk][dst] = add(gem[ilk][dst], wad);
    }
}

// receives tokens and shares them among holders
contract CropJoin {
    Vat         public vat;
    bytes32     public ilk;
    ERC20       public gem;
    ERC20       public comp;
    Comptroller public comptroller;
    uint256     public share;

    mapping (address => uint) public owed;

    constructor(address vat_, bytes32 ilk_, address gem_,
                address comp_, address comptroller_) public
    {
        vat = Vat(vat_);
        ilk = ilk_;
        gem = ERC20(gem_);
        comp = ERC20(comp_);
        comptroller = Comptroller(comptroller_);
    }

    // TODO: decimals. usdc/cusdc has 8. comp has 18.
    uint constant WAD = 10 ** 18;
    function add(uint x, uint y) public pure returns (uint z) {
        require((z = x + y) >= x, "ds-math-add-overflow");
    }
    function sub(uint x, uint y) public pure returns (uint z) {
        require((z = x - y) <= x, "ds-math-sub-underflow");
    }
    function mul(uint x, uint y) public pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x, "ds-math-mul-overflow");
    }
    function wmul(uint x, uint y) public pure returns (uint z) {
        z = mul(x, y) / WAD;
    }
    function wdiv(uint x, uint y) public pure returns (uint z) {
        z = mul(x, WAD) / y;
    }

    function balance(address usr) internal view returns (uint) {
        (uint ink,) = vat.urns(ilk, usr);
        return vat.gem(ilk, usr) + ink;
    }

    function crop() internal virtual returns (uint) {
        address[] memory ctokens = new address[](1);
        address[] memory users   = new address[](1);
        ctokens[0] = address(gem);
        users  [0] = address(this);

        uint prev = comp.balanceOf(address(this));
        comptroller.claimComp(users, ctokens, true, true); // TODO: both true? are we borrower or supplier?
        return comp.balanceOf(address(this)) - prev;
    }

    function join(uint256 wad) public {
        uint income = crop();
        uint total  = gem.balanceOf(address(this));
        if (total > 0) share = add(share, wdiv(income, total));

        address usr = msg.sender;
        comp.transfer(msg.sender, sub(wmul(balance(usr), share), owed[usr]));

        gem.transferFrom(usr, address(this), wad);
        vat.slip(ilk, usr, int(wad));
        owed[usr] = wmul(balance(usr), share);
    }

    function exit(uint wad) public {
        uint income = crop();
        uint total  = gem.balanceOf(address(this));
        if (total > 0) share = add(share, wdiv(income, total));

        address usr = msg.sender;
        comp.transfer(msg.sender, sub(wmul(balance(usr), share), owed[usr]));

        vat.slip(ilk, usr, -int(wad));
        owed[usr] = wmul(balance(usr), share);
        gem.transferFrom(address(this), usr, wad);
    }
}
