// SPDX-License-Identifier: AGPL-3.0-or-later

/// DssProxyActions.sol

// Copyright (C) 2018-2020 Maker Ecosystem Growth Holdings, INC.

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

interface GemLike {
    function approve(address, uint256) external;
    function transfer(address, uint256) external;
    function transferFrom(address, address, uint256) external;
    function deposit() external payable;
    function withdraw(uint256) external;
}

interface CropManagerLike {
    function vat() external view returns (address);
    function getOrCreateProxy(address) external returns (address);
    function join(address, address, uint256) external;
    function exit(address, address, uint256) external;
    function frob(address, address, address, address, int256, int256) external;
    function quit(bytes32 ilk, address dst) external;
}

interface VatLike {
    function can(address, address) external view returns (uint256);
    function ilks(bytes32) external view returns (uint256, uint256, uint256, uint256, uint256);
    function dai(address) external view returns (uint256);
    function urns(bytes32, address) external view returns (uint256, uint256);
    function hope(address) external;
    function nope(address) external;
    function flux(bytes32, address, address, uint256) external;
}

interface GemJoinLike {
    function dec() external returns (uint256);
    function gem() external returns (GemLike);
    function ilk() external returns (bytes32);
}

interface DaiJoinLike {
    function vat() external returns (VatLike);
    function dai() external returns (GemLike);
    function join(address, uint256) external payable;
    function exit(address, uint256) external;
}

interface EndLike {
    function fix(bytes32) external view returns (uint256);
    function cash(bytes32, uint256) external;
    function free(bytes32) external;
    function pack(uint256) external;
    function skim(bytes32, address) external;
}

interface JugLike {
    function drip(bytes32) external returns (uint256);
}

interface HopeLike {
    function hope(address) external;
    function nope(address) external;
}

// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
// WARNING: These functions meant to be used as a a library for a DSProxy. Some are unsafe if you call them directly.
// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

contract Common {
    uint256 constant WAD = 10 ** 18;
    uint256 constant RAY = 10 ** 27;

    // Internal functions

    function _mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x, "mul-overflow");
    }

    // Public functions

    function daiJoin_join(address daiJoin, uint256 wad) public {
        GemLike dai = DaiJoinLike(daiJoin).dai();
        // Gets DAI from the user's wallet
        dai.transferFrom(msg.sender, address(this), wad);
        // Approves adapter to take the DAI amount
        dai.approve(daiJoin, wad);
        // Joins DAI into the vat
        DaiJoinLike(daiJoin).join(address(this), wad);
    }
}

contract DssProxyActionsCrop is Common {
    // Internal functions

    function _sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x, "sub-overflow");
    }

    function _toInt256(uint256 x) internal pure returns (int256 y) {
        y = int256(x);
        require(y >= 0, "int-overflow");
    }

    function _toRad(uint256 wad) internal pure returns (uint256 rad) {
        rad = _mul(wad, 10 ** 27);
    }

    function _convertTo18(address gemJoin, uint256 amt) internal returns (uint256 wad) {
        // For those collaterals that have less than 18 decimals precision we
        //   need to do the conversion before passing to frob function
        // Adapters will automatically handle the difference of precision
        wad = _mul(
            amt,
            10 ** (18 - GemJoinLike(gemJoin).dec())
        );
    }

    function _getDrawDart(
        address vat,
        address jug,
        bytes32 ilk,
        uint256 wad
    )  internal returns (int256 dart) {
        // Updates stability fee rate
        uint256 rate = JugLike(jug).drip(ilk);

        // Gets DAI balance of the urn in the vat
        uint256 dai = VatLike(vat).dai(address(this));

        // If there was already enough DAI in the vat balance,
        //    just exits it without adding more debt
        uint256 rad = _mul(wad, RAY);
        if (dai < rad) {
            uint256 toDraw = rad - dai; // dai < rad
            // Calculates the needed dart so together with the existing dai in the vat is enough to exit wad amount of DAI tokens
            dart = _toInt256(toDraw / rate);
            // This is neeeded due lack of precision. It might need to sum an extra dart wei (for the given DAI wad amount)
            dart = _mul(uint256(dart), rate) < toDraw ? dart + 1 : dart;
        }
    }

    function _getWipeDart(
        address vat,
        uint256 dai,
        address urp,
        bytes32 ilk
    ) internal view returns (int256 dart) {
        // Gets actual rate from the vat
        (, uint256 rate,,,) = VatLike(vat).ilks(ilk);
        // Gets actual art value of the urn
        (, uint256 art) = VatLike(vat).urns(ilk, urp);

        // Uses the whole dai balance in the vat to reduce the debt
        dart = _toInt256(dai / rate);
        // Checks the calculated dart is not higher than urn.art (total debt),
        //    otherwise uses its value
        dart = uint256(dart) <= art ? - dart : - _toInt256(art);
    }

    function _getWipeAllWad(
        address vat,
        address urp,
        bytes32 ilk
    ) internal view returns (uint256 wad) {
        // Gets actual rate from the vat
        (, uint256 rate,,,) = VatLike(vat).ilks(ilk);
        // Gets actual art value of the urn
        (, uint256 art) = VatLike(vat).urns(ilk, urp);

        uint256 rad = _sub(_mul(art, rate), VatLike(vat).dai(address(this)));
        wad = rad / RAY;

        // If the rad precision has some dust, it will need to request for 1 extra wad wei
        wad = _mul(wad, RAY) < rad ? wad + 1 : wad;
    }

    function _frob(
        address mgr,
        address crop,
        int256 dink,
        int256 dart
    ) internal {
        CropManagerLike(mgr).frob(crop, address(this), address(this), address(this), dink, dart);
    }

    function _ethJoin_join(address mgr, address ethJoin) internal {
        GemLike gem = GemJoinLike(ethJoin).gem();
        // Wraps ETH in WETH
        gem.deposit{value: msg.value}();
        // Approves adapter to take the WETH amount
        gem.approve(mgr, msg.value);
        // Joins WETH collateral into the vat
        CropManagerLike(mgr).join(ethJoin, address(this), msg.value);
    }

    function _gemJoin_join(address mgr, address gemJoin, uint256 amt) internal {
        GemLike gem = GemJoinLike(gemJoin).gem();
        // Gets token from the user's wallet
        gem.transferFrom(msg.sender, address(this), amt);
        // Approves adapter to take the token amount
        gem.approve(mgr, amt);
        // Joins token collateral into the vat
        CropManagerLike(mgr).join(gemJoin, address(this), amt);
    }

    // Public functions

    function transfer(address gem, address dst, uint256 amt) external {
        GemLike(gem).transfer(dst, amt);
    }

    function hope(
        address obj,
        address usr
    ) external {
        HopeLike(obj).hope(usr);
    }

    function nope(
        address obj,
        address usr
    ) external {
        HopeLike(obj).nope(usr);
    }

    function quit(
        address mgr,
        bytes32 ilk,
        address dst
    ) external {
        CropManagerLike(mgr).quit(ilk, dst);
    }

    function lockETH(
        address mgr,
        address ethJoin
    ) external payable {
        // Receives ETH amount, converts it to WETH and joins it into the vat
        _ethJoin_join(mgr, ethJoin);
        // Locks WETH amount into the CDP
        _frob(mgr, GemJoinLike(ethJoin).ilk(), _toInt256(msg.value), 0);
    }

    function lockGem(
        address mgr,
        address gemJoin,
        uint256 amt
    ) external {
        // Takes token amount from user's wallet and joins into the vat
        _gemJoin_join(mgr, gemJoin, amt);
        // Locks token amount into the CDP
        _frob(mgr, GemJoinLike(gemJoin).ilk(), _toInt256(_convertTo18(gemJoin, amt)), 0);
    }

    function freeETH(
        address mgr,
        address ethJoin,
        uint256 wad
    ) external {
        // Unlocks WETH amount from the CDP
        _frob(mgr, GemJoinLike(ethJoin).ilk(), -_toInt256(wad), 0);
        // Exits WETH amount to proxy address as a token
        CropManagerLike(mgr).exit(ethJoin, address(this), wad);
        // Converts WETH to ETH
        GemJoinLike(ethJoin).gem().withdraw(wad);
        // Sends ETH back to the user's wallet
        msg.sender.transfer(wad);
    }

    function freeGem(
        address mgr,
        address gemJoin,
        uint256 amt
    ) external {
        // Unlocks token amount from the CDP
        _frob(mgr, GemJoinLike(gemJoin).ilk(), -_toInt256(_convertTo18(gemJoin, amt)), 0);
        // Exits token amount to the user's wallet as a token
        CropManagerLike(mgr).exit(gemJoin, msg.sender, amt);
    }

    function exitETH(
        address mgr,
        address ethJoin,
        uint256 wad
    ) external {
        // Exits WETH amount to proxy address as a token
        CropManagerLike(mgr).exit(ethJoin, address(this), wad);
        // Converts WETH to ETH
        GemJoinLike(ethJoin).gem().withdraw(wad);
        // Sends ETH back to the user's wallet
        msg.sender.transfer(wad);
    }

    function exitGem(
        address mgr,
        address gemJoin,
        uint256 amt
    ) external {
        // Exits token amount to the user's wallet as a token
        CropManagerLike(mgr).exit(gemJoin, msg.sender, amt);
    }

    function draw(
        address mgr,
        bytes32 ilk,
        address jug,
        address daiJoin,
        uint256 wad
    ) external {
        address vat = CropManagerLike(mgr).vat();

        // Generates debt in the CDP
        _frob(mgr, ilk, 0, _getDrawDart(mgr, vat, jug, ilk, wad));
        // Allows adapter to access to proxy's DAI balance in the vat
        if (VatLike(vat).can(address(this), address(daiJoin)) == 0) {
            VatLike(vat).hope(daiJoin);
        }
        // Exits DAI to the user's wallet as a token
        DaiJoinLike(daiJoin).exit(msg.sender, wad);
    }

    function wipe(
        address mgr,
        bytes32 ilk,
        address daiJoin,
        uint256 wad
    ) external {
        address vat = CropManagerLike(mgr).vat();

        // Joins DAI amount into the vat
        daiJoin_join(daiJoin, wad);
        // Allows manager to access to proxy's DAI balance in the vat
        VatLike(vat).hope(mgr);
        // Paybacks debt to the CDP
        _frob(
            mgr,
            ilk,
            0,
            _getWipeDart(
                vat,
                VatLike(vat).dai(address(this)),
                CropManagerLike(mgr).getOrCreateProxy(address(this)),
                ilk
            )
        );
        // Denies manager's to access to proxy's DAI balance in the vat after execution
        VatLike(vat).nope(mgr);
    }

    function wipeAll(
        address mgr,
        bytes32 ilk,
        address daiJoin
    ) external {
        address vat = CropManagerLike(mgr).vat();
        address urp = CropManagerLike(mgr).getOrCreateProxy(address(this));
        (, uint256 art) = VatLike(vat).urns(ilk, urp);

        // Joins DAI amount into the vat
        daiJoin_join(daiJoin, _getWipeAllWad(vat, urp, ilk));
        // Allows manager to access to proxy's DAI balance in the vat
        VatLike(vat).hope(mgr);
        // Paybacks debt to the CDP
        _frob(mgr, ilk, 0, -_toInt256(art));
        // Denies manager to access to proxy's DAI balance in the vat after execution
        VatLike(vat).nope(mgr);
    }

    function lockETHAndDraw(
        address mgr,
        address jug,
        address ethJoin,
        address daiJoin,
        uint256 wadD
    ) external payable {
        address vat = CropManagerLike(mgr).vat();
        bytes32 ilk = GemJoinLike(ethJoin).ilk();

        // Receives ETH amount, converts it to WETH and joins it into the vat
        _ethJoin_join(mgr, ethJoin);
        // Locks WETH amount into the CDP and generates debt
        _frob(
            mgr,
            ilk,
            _toInt256(msg.value),
            _getDrawDart(
                mgr,
                vat,
                jug,
                ilk,
                wadD
            )
        );
        // Allows adapter to access to proxy's DAI balance in the vat
        if (VatLike(vat).can(address(this), address(daiJoin)) == 0) {
            VatLike(vat).hope(daiJoin);
        }
        // Exits DAI to the user's wallet as a token
        DaiJoinLike(daiJoin).exit(msg.sender, wadD);
    }

    function lockGemAndDraw(
        address mgr,
        address jug,
        address gemJoin,
        address daiJoin,
        uint256 amtC,
        uint256 wadD
    ) external {
        address vat = CropManagerLike(mgr).vat();
        bytes32 ilk = GemJoinLike(gemJoin).ilk();

        // Takes token amount from user's wallet and joins into the vat
        _gemJoin_join(mgr, gemJoin, amtC);
        // Locks token amount into the CDP and generates debt
        _frob(
            mgr,
            ilk,
            _toInt256(_convertTo18(gemJoin, amtC)),
            _getDrawDart(
                mgr,
                vat,
                jug,
                ilk,
                wadD
            )
        );
        // Allows adapter to access to proxy's DAI balance in the vat
        if (VatLike(vat).can(address(this), address(daiJoin)) == 0) {
            VatLike(vat).hope(daiJoin);
        }
        // Exits DAI to the user's wallet as a token
        DaiJoinLike(daiJoin).exit(msg.sender, wadD);
    }

    function wipeAndFreeETH(
        address mgr,
        address ethJoin,
        address daiJoin,
        uint256 wadC,
        uint256 wadD
    ) external {
        address vat = CropManagerLike(mgr).vat();
        bytes32 ilk = GemJoinLike(ethJoin).ilk();

        // Joins DAI amount into the vat
        daiJoin_join(daiJoin, wadD);
        // Allows manager to access to proxy's DAI balance in the vat
        VatLike(vat).hope(mgr);
        // Paybacks debt to the CDP and unlocks WETH amount from it
        _frob(
            mgr,
            ilk,
            -_toInt256(wadC),
            _getWipeDart(
                vat,
                VatLike(vat).dai(address(this)),
                CropManagerLike(mgr).getOrCreateProxy(address(this)),
                ilk
            )
        );
        // Denies manager to access to proxy's DAI balance in the vat after execution
        VatLike(vat).nope(mgr);
        // Exits WETH amount to proxy address as a token
        CropManagerLike(mgr).exit(ethJoin, address(this), wadC);
        // Converts WETH to ETH
        GemJoinLike(ethJoin).gem().withdraw(wadC);
        // Sends ETH back to the user's wallet
        msg.sender.transfer(wadC);
    }

    function wipeAllAndFreeETH(
        address mgr,
        address ethJoin,
        address daiJoin,
        uint256 wadC
    ) external {
        address vat = CropManagerLike(mgr).vat();
        address urp = CropManagerLike(mgr).getOrCreateProxy(address(this));
        bytes32 ilk = GemJoinLike(ethJoin).ilk();
        (, uint256 art) = VatLike(vat).urns(ilk, urp);

        // Joins DAI amount into the vat
        daiJoin_join(daiJoin, _getWipeAllWad(vat, urp, ilk));
        // Allows manager to access to proxy's DAI balance in the vat
        VatLike(vat).hope(mgr);
        // Paybacks debt to the CDP and unlocks WETH amount from it
        _frob(mgr, ilk, -_toInt256(wadC), -_toInt256(art));
        // Denies manager to access to proxy's DAI balance in the vat after execution
        VatLike(vat).nope(mgr);
        // Exits WETH amount to proxy address as a token
        CropManagerLike(mgr).exit(ethJoin, address(this), wadC);
        // Converts WETH to ETH
        GemJoinLike(ethJoin).gem().withdraw(wadC);
        // Sends ETH back to the user's wallet
        msg.sender.transfer(wadC);
    }

    function wipeAndFreeGem(
        address mgr,
        address gemJoin,
        address daiJoin,
        uint256 amtC,
        uint256 wadD
    ) external {
        address vat = CropManagerLike(mgr).vat();
        bytes32 ilk = GemJoinLike(gemJoin).ilk();

        // Joins DAI amount into the vat
        daiJoin_join(daiJoin, wadD);
        // Allows manager to access to proxy's DAI balance in the vat
        VatLike(vat).hope(mgr);
        // Paybacks debt to the CDP and unlocks token amount from it
        _frob(
            mgr,
            ilk,
            -_toInt256(_convertTo18(gemJoin, amtC)),
            _getWipeDart(
                vat,
                VatLike(vat).dai(address(this)),
                CropManagerLike(mgr).getOrCreateProxy(address(this)),
                ilk
            )
        );
        // Denies manager to access to proxy's DAI balance in the vat after execution
        VatLike(vat).nope(mgr);
        // Exits token amount to the user's wallet as a token
        CropManagerLike(mgr).exit(gemJoin, msg.sender, amtC);
    }

    function wipeAllAndFreeGem(
        address mgr,
        address gemJoin,
        address daiJoin,
        uint256 amtC
    ) external {
        address vat = CropManagerLike(mgr).vat();
        address urp = CropManagerLike(mgr).getOrCreateProxy(address(this));
        bytes32 ilk = GemJoinLike(gemJoin).ilk();
        (, uint256 art) = VatLike(vat).urns(ilk, urp);

        // Joins DAI amount into the vat
        daiJoin_join(daiJoin, _getWipeAllWad(vat, urp, ilk));
        // Allows manager to access to proxy's DAI balance in the vat
        VatLike(vat).hope(mgr);
        // Paybacks debt to the CDP and unlocks token amount from it
        _frob(mgr, ilk, -_toInt256(_convertTo18(gemJoin, amtC)), -_toInt256(art));
        // Denies manager to access to proxy's DAI balance in the vat after execution
        VatLike(vat).nope(mgr);
        // Exits token amount to the user's wallet as a token
        CropManagerLike(mgr).exit(gemJoin, msg.sender, amtC);
    }
}

contract DssProxyActionsEndCrop is Common {
    // Internal functions

    function _free(
        address mgr,
        address end,
        bytes32 ilk
    ) internal returns (uint256 ink) {
        VatLike vat = VatLike(CropManagerLike(mgr).vat());
        address urp = CropManagerLike(mgr).getOrCreateProxy(address(this));
        uint256 art;
        (ink, art) = vat.urns(ilk, urp);

        // If CDP still has debt, it needs to be paid
        if (art > 0) {
            EndLike(end).skim(ilk, urp);
            (ink,) = vat.urns(ilk, urp);
        }
        // Approves the manager to transfer the position to proxy's address in the vat
        vat.hope(mgr);
        // Transfers position from CDP to the proxy address
        CropManagerLike(mgr).quit(ilk, address(this));
        // Denies manager to access to proxy's position in the vat after execution
        vat.nope(mgr);
        // Frees the position and recovers the collateral in the vat registry
        EndLike(end).free(ilk);
        // Fluxs to the proxy's manager proxy, so it can be pulled out with the managed gem join
        VatLike(vat).flux(
            ilk,
            address(this),
            urp,
            ink
        );
    }

    // Public functions
    function freeETH(
        address mgr,
        address ethJoin,
        address end
    ) external {
        bytes32 ilk = GemJoinLike(ethJoin).ilk();

        // Frees the position through the end contract
        uint256 wad = _free(mgr, end, ilk);
        // Exits WETH amount to proxy address as a token
        CropManagerLike(mgr).exit(ethJoin, address(this), wad);
        // Converts WETH to ETH
        GemJoinLike(ethJoin).gem().withdraw(wad);
        // Sends ETH back to the user's wallet
        msg.sender.transfer(wad);
    }

    function freeGem(
        address mgr,
        address gemJoin,
        address end
    ) external {
        bytes32 ilk = GemJoinLike(gemJoin).ilk();

        // Frees the position through the end contract
        uint256 wad = _free(mgr, end, ilk);
        // Exits token amount to the user's wallet as a token
        uint256 amt = wad / 10 ** (18 - GemJoinLike(gemJoin).dec());
        CropManagerLike(mgr).exit(gemJoin, msg.sender, amt);
    }

    function pack(
        address daiJoin,
        address end,
        uint256 wad
    ) external {
        VatLike vat = DaiJoinLike(daiJoin).vat();

        // Joins DAI amount into the vat
        daiJoin_join(daiJoin, wad);
        // Approves the end to take out DAI from the proxy's balance in the vat
        if (vat.can(address(this), address(end)) == 0) {
            vat.hope(end);
        }
        EndLike(end).pack(wad);
    }

    function cashETH(
        address mgr,
        address ethJoin,
        address end,
        bytes32 ilk,
        uint256 wad
    ) external {
        EndLike(end).cash(ilk, wad);
        uint256 wadC = _mul(wad, EndLike(end).fix(ilk)) / RAY;
        // Flux to the proxy's UrnProxy in manager, so it can be pulled out with the managed gem join
        VatLike(CropManagerLike(mgr).vat()).flux(
            ilk,
            address(this),
            CropManagerLike(mgr).getOrCreateProxy(address(this)),
            wadC
        );
        // Exits WETH amount to proxy address as a token
        CropManagerLike(mgr).exit(ethJoin, address(this), wadC);
        // Converts WETH to ETH
        GemJoinLike(ethJoin).gem().withdraw(wadC);
        // Sends ETH back to the user's wallet
        msg.sender.transfer(wadC);
    }

    function cashGem(
        address mgr,
        address gemJoin,
        address end,
        bytes32 ilk,
        uint256 wad
    ) external {
        EndLike(end).cash(ilk, wad);
        uint256 wadC = _mul(wad, EndLike(end).fix(ilk)) / RAY;
        // Flux to the proxy's UrnProxy in manager, so it can be pulled out with the managed gem join
        VatLike(CropManagerLike(mgr).vat()).flux(
            ilk,
            address(this),
            CropManagerLike(mgr).getOrCreateProxy(address(this)),
            wadC
        );
        // Exits token amount to the user's wallet as a token
        uint256 amt = wadC / 10 ** (18 - GemJoinLike(gemJoin).dec());
        CropManagerLike(mgr).exit(gemJoin, msg.sender, amt);
    }
}