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

interface VatLike {
    function hope(address) external;
    function urns(bytes32, address) external view returns (uint256, uint256);
    function gem(bytes32, address) external view returns (uint256);
    function slip(bytes32, address, int256) external;
    function flux(bytes32, address, address, uint256) external;
    function frob(bytes32, address, address, address, int256, int256) external;
}

interface ERC20 {
    function balanceOf(address owner) external view returns (uint256);
    function transfer(address dst, uint256 amount) external returns (bool);
    function transferFrom(address src, address dst, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function decimals() external returns (uint8);
}

contract UrnProxy {
    constructor(address vat) public {
        VatLike(vat).hope(msg.sender);
    }
}

// receives tokens and shares them among holders
contract CropJoin {

    VatLike     public immutable vat;    // cdp engine
    bytes32     public immutable ilk;    // collateral type
    ERC20       public immutable gem;    // collateral token
    uint256     public immutable dec;    // gem decimals
    ERC20       public immutable bonus;  // rewards token

    uint256     public share;  // crops per gem    [ray]
    uint256     public total;  // total gems       [wad]
    uint256     public stock;  // crop balance     [wad]

    mapping (address => uint256) public crops;  // crops per user  [wad]
    mapping (address => uint256) public stake;  // gems per user   [wad]
    mapping (address => address) public proxy;  // UrnProxy per user

    uint256 immutable internal to18ConversionFactor;
    uint256 immutable internal toGemConversionFactor;

    // --- Events ---
    event Join(uint256 val);
    event Exit(uint256 val);
    event Flee();
    event Tack(address indexed src, address indexed dst, uint256 wad);

    constructor(address vat_, bytes32 ilk_, address gem_, address bonus_) public {
        vat = VatLike(vat_);
        ilk = ilk_;
        gem = ERC20(gem_);
        uint256 dec_ = ERC20(gem_).decimals();
        require(dec_ <= 18);
        dec = dec_;
        to18ConversionFactor = 10 ** (18 - dec_);
        toGemConversionFactor = 10 ** dec_;

        bonus = ERC20(bonus_);
    }

    function add(uint256 x, uint256 y) public pure returns (uint256 z) {
        require((z = x + y) >= x, "ds-math-add-overflow");
    }
    function sub(uint256 x, uint256 y) public pure returns (uint256 z) {
        require((z = x - y) <= x, "ds-math-sub-underflow");
    }
    function mul(uint256 x, uint256 y) public pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x, "ds-math-mul-overflow");
    }
    function divup(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = add(x, sub(y, 1)) / y;
    }
    uint256 constant WAD  = 10 ** 18;
    function wmul(uint256 x, uint256 y) public pure returns (uint256 z) {
        z = mul(x, y) / WAD;
    }
    function wdiv(uint256 x, uint256 y) public pure returns (uint256 z) {
        z = mul(x, WAD) / y;
    }
    function wdivup(uint256 x, uint256 y) public pure returns (uint256 z) {
        z = divup(mul(x, WAD), y);
    }
    uint256 constant RAY  = 10 ** 27;
    function rmul(uint256 x, uint256 y) public pure returns (uint256 z) {
        z = mul(x, y) / RAY;
    }
    function rmulup(uint256 x, uint256 y) public pure returns (uint256 z) {
        z = divup(mul(x, y), RAY);
    }
    function rdiv(uint256 x, uint256 y) public pure returns (uint256 z) {
        z = mul(x, RAY) / y;
    }

    // Net Asset Valuation [wad]
    function nav() public virtual returns (uint256) {
        uint256 _nav = gem.balanceOf(address(this));
        return mul(_nav, to18ConversionFactor);
    }

    // Net Assets per Share [wad]
    function nps() public returns (uint256) {
        if (total == 0) return WAD;
        else return wdiv(nav(), total);
    }

    function crop() internal virtual returns (uint256) {
        return sub(bonus.balanceOf(address(this)), stock);
    }

    function harvest(address from, address to) internal {
        if (total > 0) share = add(share, rdiv(crop(), total));

        uint256 last = crops[from];
        uint256 curr = rmul(stake[from], share);
        if (curr > last) require(bonus.transfer(to, curr - last));
        stock = bonus.balanceOf(address(this));
    }

    function join(address urn, uint256 val) public virtual {
        address urp = proxy[urn];
        if (urp == address(0)) {
            urp = address(new UrnProxy(address(vat)));
        }
        harvest(urp, urn);
        if (val > 0) {
            uint256 wad = wdiv(mul(val, to18ConversionFactor), nps());

            // Overflow check for int256(wad) cast below
            // Also enforces a non-zero wad
            require(int256(wad) > 0);

            require(gem.transferFrom(msg.sender, address(this), val));
            vat.slip(ilk, urp, int256(wad));

            total = add(total, wad);
            stake[urp] = add(stake[urp], wad);
        }
        crops[urp] = rmulup(stake[urp], share);
        emit Join(val);
    }

    function exit(address guy, uint256 val) public virtual {
        address urp = proxy[msg.sender];
        require(urp != address(0), "CropJoin/no-urn-proxy");
        harvest(urp, guy);
        if (val > 0) {
            uint256 wad = wdivup(mul(val, to18ConversionFactor), nps());

            // Overflow check for int256(wad) cast below
            // Also enforces a non-zero wad
            require(int256(wad) > 0);

            require(gem.transfer(guy, val));
            vat.slip(ilk, urp, -int256(wad));

            total = sub(total, wad);
            stake[urp] = sub(stake[urp], wad);
        }
        crops[urp] = rmulup(stake[urp], share);
        emit Exit(val);
    }

    function flee() public virtual {
        address urp = proxy[msg.sender];
        require(urp != address(0), "CropJoin/no-urn-proxy");

        uint256 wad = vat.gem(ilk, urp);
        require(wad <= 2 ** 255);
        uint256 val = wmul(wmul(wad, nps()), toGemConversionFactor);

        require(gem.transfer(msg.sender, val));
        vat.slip(ilk, urp, -int256(wad));

        total = sub(total, wad);
        stake[urp] = sub(stake[urp], wad);
        crops[urp] = rmulup(stake[urp], share);

        emit Flee();
    }

    function tack(address src, address dst, uint256 wad) public {
        uint256 ss = stake[src];
        stake[src] = sub(ss, wad);
        stake[dst] = add(stake[dst], wad);

        uint256 cs     = crops[src];
        uint256 dcrops = mul(cs, wad) / ss;

        // safe since dcrops <= crops[src]
        crops[src] = cs - dcrops;
        crops[dst] = add(crops[dst], dcrops);

        (uint256 ink,) = vat.urns(ilk, src);
        require(stake[src] >= add(vat.gem(ilk, src), ink));
        (ink,) = vat.urns(ilk, dst);
        require(stake[dst] <= add(vat.gem(ilk, dst), ink));

        emit Tack(src, dst, wad);
    }

    // If someone has received gems and stake e.g. through liquidations,
    // they must gather them into an UrnProxy. An UrnProxy can be created
    // for an arbitrary address by calling join(addr, 0). Like exit(),
    // gather() uses msg.sender. msg.sender must vat.hope(adapter).
    // Could in principle write a version to work with a debt position
    // as well but it's probably not needed.
    function gather() public {
        address urp   = proxy[msg.sender];
        require(urp  != address(0), "CropJoin/no-urn-proxy");
        uint256 gems  = vat.gem(ilk, msg.sender);
        uint256 steak = stake[msg.sender];
        uint256 wad   = gems > steak ? steak : gems;
        vat.flux(ilk, msg.sender, urp, wad);
        stake[msg.sender] = sub(steak, wad);
        stake[urp]        = add(stake[urp], wad);
    }

    // msg.sender must vat.hope(adapter)
    function frob(int256 dink, int256 dart) external {
        address urp = proxy[msg.sender];
        require(urp != address(0), "CropJoin/no-urn-proxy");
        vat.frob(ilk, urp, urp, msg.sender, dink, dart);
    }
}
