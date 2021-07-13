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

import "./TestBase.sol";
import {CompoundJoin,ERC20,CToken,Comptroller,Strategy,CompStrat} from "../CompoundJoin.sol";
import {CropManager,CropManagerImp} from "../CropManager.sol";

interface VatLike {
    function wards(address) external view returns (uint256);
    function rely(address) external;
    function hope(address) external;
    function gem(bytes32, address) external view returns (uint256);
    function flux(bytes32, address, address, uint256) external;
}

contract ComptrollerStorage {
    struct Market {
        bool isListed;
        uint collateralFactorMantissa;
        mapping(address => bool) accountMembership;
        bool isComped;
    }
    mapping(address => Market) public markets;
}

contract Usr {

    Hevm hevm;
    VatLike vat;
    CompoundJoin adapter;
    CropManagerImp manager;
    ERC20 gem;

    constructor(Hevm hevm_, CompoundJoin join_, CropManagerImp manager_, ERC20 gem_) public {
        hevm = hevm_;
        adapter = join_;
        manager = manager_;
        gem = gem_;

        vat = VatLike(address(adapter.vat()));

        gem.approve(address(manager), uint(-1));

        manager.getOrCreateProxy(address(this));
    }

    function join(address usr, uint wad) public {
        manager.join(address(adapter), usr, wad);
    }
    function join(uint wad) public {
        manager.join(address(adapter), address(this), wad);
    }
    function exit(address usr, uint wad) public {
        manager.exit(address(adapter), usr, wad);
    }
    function exit(uint wad) public {
        manager.exit(address(adapter), address(this), wad);
    }
    function proxy() public view returns (address) {
        return CropManager(address(manager)).proxy(address(this));
    }
    function crops() public view returns (uint256) {
        return adapter.crops(proxy());
    }
    function stake() public view returns (uint256) {
        return adapter.stake(proxy());
    }
    function gems() public view returns (uint256) {
        return adapter.vat().gem(adapter.ilk(), proxy());
    }
    function urn() public view returns (uint256, uint256) {
        return adapter.vat().urns(adapter.ilk(), proxy());
    }
    function bonus() public view returns (uint256) {
        return adapter.bonus().balanceOf(address(this));
    }
    function balance() public view returns (uint256) {
        return adapter.gem().balanceOf(address(this));
    }
    function reap() public {
        manager.join(address(adapter), address(this), 0);
    }
    function flee() public {
        manager.flee(address(adapter));
    }
    function flux(address src, address dst, uint256 wad) public {
        manager.flux(address(adapter), src, dst, wad);
    }
    function giveTokens(ERC20 token, uint256 amount) public {
        // Edge case - balance is already set for some reason
        if (token.balanceOf(address(this)) == amount) return;

        for (uint256 i = 0; i < 200; i++) {
            // Scan the storage for the balance storage slot
            bytes32 prevValue = hevm.load(
                address(token),
                keccak256(abi.encode(address(this), uint256(i)))
            );
            hevm.store(
                address(token),
                keccak256(abi.encode(address(this), uint256(i))),
                bytes32(amount)
            );
            if (token.balanceOf(address(this)) == amount) {
                // Found it
                return;
            } else {
                // Keep going after restoring the original value
                hevm.store(
                    address(token),
                    keccak256(abi.encode(address(this), uint256(i))),
                    prevValue
                );
            }
        }
    }
    function hope(address usr) public {
        vat.hope(usr);
    }

}

contract Troll {
    Token comp;
    constructor(address comp_) public {
        comp = Token(comp_);
    }
    mapping (address => uint) public compAccrued;
    function reward(address usr, uint wad) public {
        compAccrued[usr] += wad;
    }
    function claimComp(address[] memory, address[] memory, bool, bool) public {
        comp.mint(msg.sender, compAccrued[msg.sender]);
        compAccrued[msg.sender] = 0;
    }
    function claimComp() public {
        comp.mint(msg.sender, compAccrued[msg.sender]);
        compAccrued[msg.sender] = 0;
    }
    function enterMarkets(address[] memory ctokens) public returns (uint[] memory) {
        comp; ctokens;
        uint[] memory err = new uint[](1);
        err[0] = 0;
        return err;
    }
    function compBorrowerIndex(address c, address b) public returns (uint) {}
    function mintAllowed(address ctoken, address minter, uint256 mintAmount) public returns (uint) {}
    function getBlockNumber() public view returns (uint) {
        return block.number;
    }
    function getAccountLiquidity(address) external returns (uint,uint,uint) {}
    function liquidateBorrowAllowed(
        address cTokenBorrowed,
        address cTokenCollateral,
        address liquidator,
        address borrower,
        uint repayAmount) external returns (uint) {}
}

// Here we run some tests against the real Compound on mainnet
contract CompoundIntegrationTest is TestBase {

    Token usdc;
    CToken cusdc;
    Token comp;
    Troll troll;
    VatLike vat;
    CompoundJoin adapter;
    CropManagerImp manager;
    CompStrat strategy;
    address self;
    bytes32 ilk = "USDC-C";

    function setUp() public {
        self = address(this);

        vat = VatLike(0x35D1b3F3D7966A1DFe207aa4514C12a259A0492B);
        usdc = Token(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
        cusdc = CToken(0x39AA39c021dfbaE8faC545936693aC917d5E7563);
        comp = Token(0xc00e94Cb662C3520282E6f5717214004A7f26888);
        troll = Troll(0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B);

        // Give this contract admin access on the vat
        giveAuthAccess(address(vat), address(this));

        strategy = new CompStrat( address(usdc)
                                , address(cusdc)
                                , address(comp)
                                , address(troll)
                                , 10 ** usdc.decimals()
                                );
        adapter = new CompoundJoin( address(vat)
                              , ilk
                              , address(usdc)
                              , address(comp)
                              , address(strategy)
                              );
        CropManager base = new CropManager();
        base.setImplementation(address(new CropManagerImp(address(vat))));
        manager = CropManagerImp(address(base));
        adapter.rely(address(manager));
        adapter.deny(address(this));    // Only access should be through manager
        vat.rely(address(adapter));
        strategy.rely(address(adapter));
        strategy.tune(0.675e18, 0.674e18);

        // give ourselves some usdc
        giveTokens(address(usdc), 1000 * 1e6);

        hevm.roll(block.number + 10);

        usdc.approve(address(manager), uint(-1));
        usdc.approve(address(strategy), uint(-1));
    }


    function init_user() internal returns (Usr a, Usr b) {
        return init_user(200 * 1e6);
    }
    function init_user(uint256 cash) internal returns (Usr a, Usr b) {
        a = new Usr(hevm, adapter, manager, ERC20(address(usdc)));
        b = new Usr(hevm, adapter, manager, ERC20(address(usdc)));

        usdc.transfer(address(a), cash);
        usdc.transfer(address(b), cash);
    }

    function can_exit(uint val) public returns (bool) {
        bytes memory call = abi.encodeWithSignature
            ("exit(uint256)", val);
        return can_call(address(adapter), call);
    }
    function can_wind(uint borrow, uint n, uint loan) public returns (bool) {
        bytes memory call = abi.encodeWithSignature
            ("wind(uint256,uint256,uint256)", borrow, n, loan);
        return can_call(address(strategy), call);
    }
    function can_unwind(uint repay, uint n, uint exit_, uint loan_) public returns (bool) {
        bytes memory call = abi.encodeWithSignature
            ("unwind(uint256,uint256,uint256,uint256)", repay, n, exit_, loan_);
        return can_call(address(strategy), call);
    }
    function can_unwind_exit(uint val) public returns (bool) {
        return can_unwind_exit(val, 0);
    }
    function can_unwind_exit(uint val, uint loan) public returns (bool) {
        return can_unwind(0, 1, val, loan);
    }
    function can_unwind(uint repay, uint n) public returns (bool) {
        return can_unwind(repay, n, 0, 0);
    }

    function get_s() internal returns (uint256 cf) {
        require(CToken(address(cusdc)).accrueInterest() == 0);
        return CToken(address(cusdc)).balanceOfUnderlying(address(strategy));
    }
    function get_b() internal returns (uint256 cf) {
        require(CToken(address(cusdc)).accrueInterest() == 0);
        return CToken(address(cusdc)).borrowBalanceStored(address(strategy));
    }
    function get_cf() internal returns (uint256 cf) {
        require(CToken(address(cusdc)).accrueInterest() == 0);
        cf = wdiv(CToken(address(cusdc)).borrowBalanceStored(address(strategy)),
                  CToken(address(cusdc)).balanceOfUnderlying(address(strategy)));
    }

    function test_underlying() public {
        assertEq(CToken(address(cusdc)).underlying(), address(usdc));
    }

    function reward(uint256 tic) internal {
        log_named_uint("=== tic ==>", tic);
        // accrue ~tic day of rewards
        hevm.warp(block.timestamp + tic);
        // unneeded?
        hevm.roll(block.number + tic / 15);
    }

    function test_reward_unwound() public {
        (Usr a,) = init_user();
        assertEq(comp.balanceOf(address(a)), 0 ether);

        a.join(100 * 1e6);
        assertEq(comp.balanceOf(address(a)), 0 ether);

        strategy.wind(0, 0, 0);

        reward(1 days);

        a.join(0);
        assertGt(comp.balanceOf(address(a)), 0 ether);
    }

    function test_reward_wound() public {
        (Usr a,) = init_user();
        assertEq(comp.balanceOf(address(a)), 0 ether);

        a.join(100 * 1e6);
        assertEq(comp.balanceOf(address(a)), 0 ether);

        strategy.wind(50 * 10**6, 0, 0);

        reward(1 days);

        a.join(0);
        assertGt(comp.balanceOf(address(a)), 0 ether);

        assertLt(get_cf(), strategy.maxf());
        assertLt(get_cf(), strategy.minf());
    }

    function test_reward_wound_fully() public {
        (Usr a,) = init_user();
        assertEq(comp.balanceOf(address(a)), 0 ether);

        a.join(100 * 1e6);
        assertEq(comp.balanceOf(address(a)), 0 ether);

        strategy.wind(0, 5, 0);

        reward(1 days);

        a.join(0);
        assertGt(comp.balanceOf(address(a)), 0 ether);

        assertLt(get_cf(), strategy.maxf(), "cf < maxf");
        assertGt(get_cf(), strategy.minf(), "cf > minf");
    }

    function test_wind_unwind() public {
        require(CToken(address(cusdc)).accrueInterest() == 0);
        (Usr a,) = init_user();
        assertEq(comp.balanceOf(address(a)), 0 ether);

        a.join(100 * 1e6);
        assertEq(comp.balanceOf(address(a)), 0 ether);

        strategy.wind(0, 5, 0);

        reward(1 days);

        assertLt(get_cf(), strategy.maxf(), "under target");
        assertGt(get_cf(), strategy.minf(), "over minimum");

        log_named_uint("cf", get_cf());
        reward(1000 days);
        log_named_uint("cf", get_cf());

        assertGt(get_cf(), strategy.maxf(), "over target after interest");

        // unwind is used for deleveraging our position. Here we have
        // gone over the target due to accumulated interest, so we
        // unwind to bring us back under the target leverage.
        assertTrue( can_unwind(0, 1), "able to unwind if over target");
        strategy.unwind(0, 1, 0, 0);

        assertLt(get_cf(), 0.676e18, "near target post unwind");
        assertGt(get_cf(), 0.674e18, "over minimum post unwind");
    }

    function test_unwind_multiple() public {
        manager.join(address(adapter), address(this), 100e6);
        strategy.wind(0, 5, 0);

        set_cf(0.72e18);
        strategy.unwind(0, 1, 0, 0);
        log_named_uint("cf", get_cf());
        strategy.unwind(0, 1, 0, 0);
        log_named_uint("cf", get_cf());
        strategy.unwind(0, 1, 0, 0);
        log_named_uint("cf", get_cf());
        strategy.unwind(0, 1, 0, 0);
        log_named_uint("cf", get_cf());
        assertGt(get_cf(), 0.674e18);
        assertLt(get_cf(), 0.675e18);

        set_cf(0.72e18);
        strategy.unwind(0, 8, 0, 0);
        log_named_uint("cf", get_cf());
        assertGt(get_cf(), 0.674e18);
        assertLt(get_cf(), 0.675e18);
    }

    // if utilisation ends up over the limit we will need to use a loan
    // to unwind
    function test_unwind_over_limit() public {
        // we need a loan of
        //   L / s0 >= (u - cf) / (cf * (1 - u) * (1 - cf))
        manager.join(address(adapter), address(this), 100e6);
        strategy.wind(0, 5, 0);
        set_cf(0.77e18);
        log_named_uint("cf", get_cf());

        uint cf = 0.75e18;
        uint u = get_cf();
        uint Lmin = wmul(100e6, wdiv(sub(u, cf), wmul(wmul(cf, 1e18 - u), 1e18 - cf)));
        log_named_uint("s", get_s());
        log_named_uint("b", get_s());
        log_named_uint("L", Lmin);

        assertTrue(!can_unwind(0, 1, 0, 0), "can't unwind without a loan");
        assertTrue(!can_unwind(0, 1, 0, Lmin - 1e2), "can't unwind without enough loan");
        assertTrue( can_unwind(0, 1, 0, Lmin), "can unwind with sufficient loan");
    }

    function test_unwind_under_limit() public {
        manager.join(address(adapter), address(this), 100e6);
        strategy.wind(0, 5, 0);
        set_cf(0.673e18);
        log_named_uint("cf", get_cf());
        assertTrue(!can_unwind(0, 1, 0, 0));
        // todo: minimum exit amount
    }

    function test_flash_wind_necessary_loan() public {
        // given nav s0, we can calculate the minimum loan L needed to
        // effect a wind up to a given u',
        //
        //   L/s0 >= (u'/cf - 1 + u' - u*u'/cf) / [(1 - u') * (1 - u)]
        //
        // e.g. for u=0, u'=0.675, L/s0 ~= 1.77
        //
        // we can also write the maximum u' for a given L,
        //
        //   u' <= (1 + (1 - u) * L / s0) / (1 + (1 - u) * (L / s0 + 1 / cf))
        //
        // and the borrow to directly achieve a given u'
        //
        //   x = s0 (1 / (1 - u') - 1 / (1 - u))
        //
        // e.g. for u=0, u'=0.675, x/s0 ~= 2.0769
        //
        // here we test the u' that we achieve with given L

        (Usr a,) = init_user();
        a.join(100 * 1e6);

        assertTrue(!can_wind(207.69 * 1e6, 0, 176 * 1e6), "insufficient loan");
        assertTrue( can_wind(207.69 * 1e6, 0, 177 * 1e6), "sufficient loan");

        strategy.wind(207.69 * 1e6, 0, 177 * 1e6);
        log_named_uint("cf", get_cf());
        assertGt(get_cf(), 0.674e18);
        assertLt(get_cf(), 0.675e18);
    }

    function test_flash_wind_sufficient_loan() public {
        // we can also have wind determine the maximum borrow itself
        (Usr a,) = init_user();
        a.giveTokens(ERC20(address(usdc)), 900e6);

        a.join(100 * 1e6);
        strategy.wind(0, 1, 200 * 1e6);
        log_named_uint("cf", get_cf());
        assertGt(get_cf(), 0.673e18);
        assertLt(get_cf(), 0.675e18);

        return;
        a.join(100 * 1e6);
        logs("200");
        strategy.wind(0, 1, 200 * 1e6);
        log_named_uint("cf", get_cf());

        a.join(100 * 1e6);
        logs("100");
        strategy.wind(0, 1, 100 * 1e6);
        log_named_uint("cf", get_cf());

        a.join(100 * 1e6);
        logs("100");
        strategy.wind(0, 1, 100 * 1e6);
        log_named_uint("cf", get_cf());

        a.join(100 * 1e6);
        logs("150");
        strategy.wind(0, 1, 150 * 1e6);
        log_named_uint("cf", get_cf());

        a.join(100 * 1e6);
        logs("175");
        strategy.wind(0, 1, 175 * 1e6);
        log_named_uint("cf", get_cf());

        assertGt(get_cf(), 0.673e18);
        assertLt(get_cf(), 0.675e18);
    }
    // compare gas costs of a flash loan wind and a iteration wind
    function test_wind_gas_flash() public {
        (Usr a,) = init_user();

        a.join(100 * 1e6);
        uint256 gas_before = gasleft();
        strategy.wind(0, 1, 200 * 1e6);
        uint256 gas_after = gasleft();
        log_named_uint("s ", get_s());
        log_named_uint("b ", get_b());
        log_named_uint("s + b", get_s() + get_b());
        log_named_uint("cf", get_cf());
        assertGt(get_cf(), 0.673e18);
        assertLt(get_cf(), 0.675e18);
        log_named_uint("gas", gas_before - gas_after);
    }
    function test_wind_gas_iteration() public {
        (Usr a,) = init_user();

        a.join(100 * 1e6);
        uint256 gas_before = gasleft();
        strategy.wind(0, 5, 0);
        uint256 gas_after = gasleft();

        assertGt(get_cf(), 0.673e18);
        assertLt(get_cf(), 0.675e18);
        log_named_uint("s ", get_s());
        log_named_uint("b ", get_b());
        log_named_uint("s + b", get_s() + get_b());
        log_named_uint("cf", get_cf());
        log_named_uint("gas", gas_before - gas_after);
    }
    function test_wind_gas_partial_loan() public {
        (Usr a,) = init_user();

        a.join(100 * 1e6);
        uint256 gas_before = gasleft();
        strategy.wind(0, 3, 50e6);
        uint256 gas_after = gasleft();

        assertGt(get_cf(), 0.673e18);
        assertLt(get_cf(), 0.675e18);
        log_named_uint("s ", get_s());
        log_named_uint("b ", get_b());
        log_named_uint("s + b", get_s() + get_b());
        log_named_uint("cf", get_cf());
        log_named_uint("gas", gas_before - gas_after);
    }

    function set_cf(uint256 cf) internal {
        uint256 nav = adapter.nav();

        // desired supply and borrow in terms of underlying
        uint256 x = cusdc.exchangeRateCurrent();
        uint256 s = (nav * 1e18 / (1e18 - cf)) / 1e12;
        uint256 b = s * cf / 1e18 - 1;

        log_named_uint("nav  ", nav);
        log_named_uint("new s", s);
        log_named_uint("new b", b);
        log_named_uint("set u", cf);

        //set_usdc(address(strategy), 0);
        // cusdc.accountTokens
        hevm.store(
            address(cusdc),
            keccak256(abi.encode(address(strategy), uint256(15))),
            bytes32((s * 1e18) / x)
        );
        // cusdc.accountBorrows.principal
        hevm.store(
            address(cusdc),
            keccak256(abi.encode(address(strategy), uint256(17))),
            bytes32(b)
        );
        // cusdc.accountBorrows.interestIndex
        hevm.store(
            address(cusdc),
            bytes32(uint(keccak256(abi.encode(address(strategy), uint256(17)))) + 1),
            bytes32(cusdc.borrowIndex())
        );

        log_named_uint("new u", get_cf());
        log_named_uint("nav  ", adapter.nav());
    }

    // simple test of `cage` where we set the target leverage to zero
    // and then seek to withdraw all of the collateral
    function test_cage_single_user() public {
        manager.join(address(adapter), address(this), 100 * 1e6);
        strategy.wind(0, 1, 0);
        set_cf(0.6745e18);

        // log("unwind 1");
        // strategy.unwind(0, 6, 0, 0);

        set_cf(0.675e18);

        // this causes a sub overflow unless we use zsub
        // strategy.tune(0.673e18, 0);

        strategy.tune(0, 0);

        assertEq(usdc.balanceOf(address(this)),  900 * 1e6);
        strategy.unwind(0, 3, 100 * 1e6, 0);
        assertEq(usdc.balanceOf(address(this)), 1000 * 1e6);
    }
    // test of `cage` with two users, where the strategy is unwound
    // by a third party and the two users then exit separately
    function test_cage_multi_user() public {
        cage_multi_user(60 * 1e6, 40 * 1e6, 200 * 1e6);
    }
    // the same test but fuzzing over various ranges:
    //   - uint32 is up to $4.5k
    //   - uint40 is up to $1.1m
    //   - uint48 is up to $280m, but we cap it at $50m due to liquidity
    function test_cage_multi_user_small(uint32 a_join, uint32 b_join) public {
        if (a_join < 100e6 || b_join < 100e6) return;
        cage_multi_user(a_join, b_join, uint32(-1));
    }
    function test_cage_multi_user_medium(uint40 a_join, uint40 b_join) public {
        if (a_join < uint32(-1) || b_join < uint32(-1)) return;
        cage_multi_user(a_join, b_join, uint40(-1));
    }
    function test_cage_multi_user_large(uint48 a_join, uint48 b_join) public {
        if (a_join < uint40(-1) || b_join < uint40(-1)) return;
        if (a_join > 50e6 * 1e6 || b_join > 50e6 * 1e6) return;
        cage_multi_user(a_join, b_join, uint48(-1));
    }

    function cage_multi_user(uint a_join, uint b_join, uint cash) public {
        // this would truncate to whole usdc amounts, but there don't
        // seem to be any failures for that
        // a_join = a_join / 1e6 * 1e6;
        // b_join = b_join / 1e6 * 1e6;

        log_named_decimal_uint("a_join", a_join, 6);
        log_named_decimal_uint("b_join", b_join, 6);
        (Usr a, Usr b) = init_user(cash);
        assertEq(usdc.balanceOf(address(a)), cash);
        assertEq(usdc.balanceOf(address(b)), cash);
        a.join(a_join);
        b.join(b_join);

        assertEq(usdc.balanceOf(address(a)), cash - a_join);
        assertEq(usdc.balanceOf(address(b)), cash - b_join);

        strategy.wind(0, 6, 0);
        reward(30 days);
        strategy.tune(0, 0);

        strategy.unwind(0, 6, 0, 0);

        //a.unwind_exit(a_join);
        //b.unwind_exit(b_join);

        assertEq(usdc.balanceOf(address(a)), cash);
        assertEq(usdc.balanceOf(address(b)), cash);
    }
    // wind / unwind make the underlying unavailable as it is deposited
    // into the ctoken. In order to exit we will have to free up some
    // underlying.
    function wound_unwind_exit(bool loan) public {
        manager.join(address(adapter), address(this), 100 * 1e6);

        assertEq(comp.balanceOf(self), 0 ether, "no initial rewards");

        set_cf(0.675e18);

        assertTrue(get_cf() < strategy.maxf(), "cf under target");
        assertTrue(get_cf() > strategy.minf(), "cf over minimum");

        // we can't exit as there is no available usdc
        assertTrue(!can_exit(10 * 1e6), "cannot 10% exit initially");

        // however we can exit with unwind
        assertTrue( can_unwind_exit(14.7 * 1e6), "ok exit with 14.7%");
        assertTrue(!can_unwind_exit(14.9 * 1e6), "no exit with 14.9%");

        if (loan) {
            // with a loan we can exit an extra (L * (1 - u) / u) ~= 0.481L
            assertTrue( can_unwind_exit(19.5 * 1e6, 10 * 1e6), "ok loan exit");
            assertTrue(!can_unwind_exit(19.7 * 1e6, 10 * 1e6), "no loan exit");

            log_named_uint("s ", CToken(address(cusdc)).balanceOfUnderlying(address(strategy)));
            log_named_uint("b ", CToken(address(cusdc)).borrowBalanceStored(address(strategy)));
            log_named_uint("u ", get_cf());

            uint prev = usdc.balanceOf(address(this));
            //adapter.unwind(0, 1, 10 * 1e6,  10 * 1e6);
            assertEq(usdc.balanceOf(address(this)) - prev, 10 * 1e6);

            log_named_uint("s'", CToken(address(cusdc)).balanceOfUnderlying(address(strategy)));
            log_named_uint("b'", CToken(address(cusdc)).borrowBalanceStored(address(strategy)));
            log_named_uint("u'", get_cf());

        } else {
            log_named_uint("s ", CToken(address(cusdc)).balanceOfUnderlying(address(strategy)));
            log_named_uint("b ", CToken(address(cusdc)).borrowBalanceStored(address(strategy)));
            log_named_uint("u ", get_cf());

            uint prev = usdc.balanceOf(address(this));
            //adapter.unwind(0, 1, 10 * 1e6, 0);
            assertEq(usdc.balanceOf(address(this)) - prev, 10 * 1e6);

            log_named_uint("s'", CToken(address(cusdc)).balanceOfUnderlying(address(strategy)));
            log_named_uint("b'", CToken(address(cusdc)).borrowBalanceStored(address(strategy)));
            log_named_uint("u'", get_cf());
        }
    }
    function test_unwind_exit() public {
        wound_unwind_exit(false);
    }
    function test_unwind_exit_with_loan() public {
        wound_unwind_exit(true);
    }
    function test_unwind_full_exit() public {
        manager.join(address(adapter), address(this), 100 * 1e6);
        set_cf(0.675e18);

        // we can unwind in a single cycle using a loan
        //adapter.unwind(0, 1, 100e6 - 1e4, 177 * 1e6);

        manager.join(address(adapter), address(this), 100 * 1e6);
        set_cf(0.675e18);

        // or we can unwind by iteration without a loan
        //adapter.unwind(0, 6, 100e6 - 1e4, 0);
    }
    function test_unwind_gas_flash() public {
        manager.join(address(adapter), address(this), 100 * 1e6);
        set_cf(0.675e18);
        uint gas_before = gasleft();
        strategy.unwind(0, 1, 100e6 - 1e4, 177e6);
        uint gas_after = gasleft();

        assertGt(get_cf(), 0.674e18);
        assertLt(get_cf(), 0.675e18);
        log_named_uint("s ", get_s());
        log_named_uint("b ", get_b());
        log_named_uint("s + b", get_s() + get_b());
        log_named_uint("cf", get_cf());
        log_named_uint("gas", gas_before - gas_after);
    }
    function test_unwind_gas_iteration() public {
        manager.join(address(adapter), address(this), 100 * 1e6);
        set_cf(0.675e18);
        uint gas_before = gasleft();
        strategy.unwind(0, 5, 100e6 - 1e4, 0);
        uint gas_after = gasleft();

        assertGt(get_cf(), 0.674e18);
        assertLt(get_cf(), 0.675e18);
        log_named_uint("s ", get_s());
        log_named_uint("b ", get_b());
        log_named_uint("s + b", get_s() + get_b());
        log_named_uint("cf", get_cf());
        log_named_uint("gas", gas_before - gas_after);
    }
    function test_unwind_gas_shallow() public {
        // we can withdraw a fraction of the pool without loans or
        // iterations
        manager.join(address(adapter), address(this), 100 * 1e6);
        set_cf(0.675e18);
        uint gas_before = gasleft();
        strategy.unwind(0, 1, 14e6, 0);
        uint gas_after = gasleft();

        assertGt(get_cf(), 0.674e18);
        assertLt(get_cf(), 0.675e18);
        log_named_uint("s ", get_s());
        log_named_uint("b ", get_b());
        log_named_uint("s + b", get_s() + get_b());
        log_named_uint("cf", get_cf());
        log_named_uint("gas", gas_before - gas_after);
    }

    // The nav of the adapter will drop over time, due to interest
    // accrual, check that this is well behaved.
    function test_nav_drop_with_interest() public {
        require(CToken(address(cusdc)).accrueInterest() == 0);
        (Usr a,) = init_user();

        manager.join(address(adapter), address(this), 600 * 1e6);

        assertEq(usdc.balanceOf(address(a)), 200 * 1e6);
        a.join(100 * 1e6);
        assertEq(usdc.balanceOf(address(a)), 100 * 1e6);
        assertEq(adapter.nps(), 1 ether, "initial nps is 1");

        log_named_uint("nps before wind   ", adapter.nps());
        strategy.wind(0, 5, 0);

        assertGt(get_cf(), 0.673e18, "near minimum");
        assertLt(get_cf(), 0.675e18, "under target");

        log_named_uint("nps before interest", adapter.nps());
        reward(100 days);
        assertLt(adapter.nps(), 1e18, "nps falls after interest");
        log_named_uint("nps after interest ", adapter.nps());

        assertEq(usdc.balanceOf(address(a)), 100 * 1e6, "usdc before exit");
        assertEq(adapter.stake(address(a)), 100 ether, "balance before exit");

        uint max_usdc = mul(adapter.nps(), adapter.stake(address(a))) / 1e30;
        logs("===");
        log_named_uint("max usdc    ", max_usdc);
        log_named_uint("adapter.balance", adapter.stake(address(a)));
        log_named_uint("vat.gem     ", vat.gem(adapter.ilk(), address(a)));
        log_named_uint("usdc        ", usdc.balanceOf(address(strategy)));
        log_named_uint("cf", get_cf());
        logs("exit ===");
        //a.unwind_exit(max_usdc);
        log_named_uint("nps after exit     ", adapter.nps());
        log_named_uint("adapter.balance", adapter.stake(address(a)));
        log_named_uint("adapter.balance", adapter.stake(address(a)) / 1e12);
        log_named_uint("vat.gem     ", vat.gem(adapter.ilk(), address(a)));
        log_named_uint("usdc        ", usdc.balanceOf(address(strategy)));
        log_named_uint("cf", get_cf());
        assertLt(usdc.balanceOf(address(a)), 200 * 1e6, "less usdc after");
        assertGt(usdc.balanceOf(address(a)), 199 * 1e6, "less usdc after");

        assertLt(adapter.stake(address(a)), 1e18/1e6, "zero balance after full exit");
    }
    function test_nav_drop_with_liquidation() public {
        require(CToken(address(cusdc)).accrueInterest() == 0);
        enable_seize(address(this));

        (Usr a,) = init_user();

        manager.join(address(adapter), address(this), 600 * 1e6);

        assertEq(usdc.balanceOf(address(a)), 200 * 1e6);
        a.join(100 * 1e6);
        assertEq(usdc.balanceOf(address(a)), 100 * 1e6);

        logs("wind===");
        strategy.wind(0, 5, 0);

        assertGt(get_cf(), 0.673e18, "near minimum");
        assertLt(get_cf(), 0.675e18, "under target");

        uint liquidity; uint shortfall; uint supp; uint borr;
        supp = CToken(address(cusdc)).balanceOfUnderlying(address(strategy));
        borr = CToken(address(cusdc)).borrowBalanceStored(address(strategy));
        (, liquidity, shortfall) =
            troll.getAccountLiquidity(address(strategy));
        log_named_uint("cf  ", get_cf());
        log_named_uint("s  ", supp);
        log_named_uint("b  ", borr);
        log_named_uint("liquidity", liquidity);
        log_named_uint("shortfall", shortfall);

        uint nps_before = adapter.nps();
        logs("time...===");
        reward(5000 days);
        assertLt(adapter.nps(), nps_before, "nps falls after interest");

        supp = CToken(address(cusdc)).balanceOfUnderlying(address(strategy));
        borr = CToken(address(cusdc)).borrowBalanceStored(address(strategy));
        (, liquidity, shortfall) =
            troll.getAccountLiquidity(address(strategy));
        log_named_uint("cf' ", get_cf());
        log_named_uint("s' ", supp);
        log_named_uint("b' ", borr);
        log_named_uint("liquidity", liquidity);
        log_named_uint("shortfall", shortfall);

        cusdc.approve(address(cusdc), uint(-1));
        usdc.approve(address(cusdc), uint(-1));
        log_named_uint("allowance", cusdc.allowance(address(this), address(cusdc)));
        giveTokens(address(usdc), 1000e6);
        log_named_uint("usdc ", usdc.balanceOf(address(this)));
        log_named_uint("cusdc", cusdc.balanceOf(address(this)));
        require(cusdc.mint(100e6) == 0);
        logs("mint===");
        log_named_uint("usdc ", usdc.balanceOf(address(this)));
        log_named_uint("cusdc", cusdc.balanceOf(address(this)));
        logs("liquidate===");
        return;
        // liquidation is not possible for cusdc-cusdc pairs, as it is
        // blocked by a re-entrancy guard????
        uint repay = 20;  // units of underlying
        assertTrue(!can_call( address(cusdc)
                            , abi.encodeWithSignature(
                                "liquidateBorrow(address,uint256,address)",
                                address(strategy), repay, CToken(address(cusdc)))),
                  "can't perform liquidation");
        cusdc.liquidateBorrow(address(strategy), repay, CToken(address(cusdc)));

        supp = CToken(address(cusdc)).balanceOfUnderlying(address(strategy));
        borr = CToken(address(cusdc)).borrowBalanceStored(address(strategy));
        (, liquidity, shortfall) =
            troll.getAccountLiquidity(address(strategy));
        log_named_uint("cf' ", get_cf());
        log_named_uint("s' ", supp);
        log_named_uint("b' ", borr);
        log_named_uint("liquidity", liquidity);
        log_named_uint("shortfall", shortfall);

        // check how long it would take for us to get to 100% utilisation
        reward(30 * 365 days);
        log_named_uint("cf' ", get_cf());
        assertGt(get_cf(), 1e18, "cf > 1");
    }

    // allow the test contract to seize collateral from a borrower
    // (normally only cTokens can do this). This allows us to mock
    // liquidations.
    function enable_seize(address usr) internal {
        hevm.store(
            address(troll),
            keccak256(abi.encode(usr, uint256(9))),
            bytes32(uint256(1))
        );
    }
    // comptroller expects this to be available if we're pretending to
    // be a cToken
    function comptroller() external returns (address) {
        return address(troll);
    }
    function test_enable_seize() public {
        ComptrollerStorage stroll = ComptrollerStorage(address(troll));
        bool isListed;
        (isListed,,) = stroll.markets(address(this));
        assertTrue(!isListed);

        enable_seize(address(this));

        (isListed,,) = stroll.markets(address(this));
        assertTrue(isListed);
    }
    function test_can_seize() public {
        enable_seize(address(this));

        manager.join(address(adapter), address(this), 100 * 1e6);
        strategy.wind(0, 4, 0);

        uint seize = 100 * 1e8;

        uint cusdc_before = cusdc.balanceOf(address(strategy));
        assertEq(cusdc.balanceOf(address(this)), 0, "no cusdc before");

        uint s = CToken(address(cusdc)).seize(address(this), address(strategy), seize);
        assertEq(s, 0, "seize successful");

        uint cusdc_after = cusdc.balanceOf(address(strategy));
        assertEq(cusdc.balanceOf(address(this)), seize, "cusdc after");
        assertEq(cusdc_before - cusdc_after, seize, "join supply decreased");
    }
    function test_nav_drop_with_seizure() public {
        enable_seize(address(this));

        (Usr a,) = init_user();

        manager.join(address(adapter), address(this), 600 * 1e6);
        a.join(100 * 1e6);
        log_named_uint("nps", adapter.nps());
        log_named_uint("usdc ", usdc.balanceOf(address(strategy)));
        log_named_uint("cusdc", cusdc.balanceOf(address(strategy)));

        logs("wind===");
        strategy.wind(0, 5, 0);
        log_named_uint("nps", adapter.nps());
        log_named_uint("cf", get_cf());
        log_named_uint("adapter usdc ", usdc.balanceOf(address(strategy)));
        log_named_uint("adapter cusdc", cusdc.balanceOf(address(strategy)));
        log_named_uint("adapter nav  ", adapter.nav());
        log_named_uint("a max usdc    ", mul(adapter.stake(address(a)), adapter.nps()) / 1e18);

        assertGt(get_cf(), 0.673e18, "near minimum");
        assertLt(get_cf(), 0.675e18, "under target");

        logs("seize===");
        uint seize = 350 * 1e6 * 1e18 / cusdc.exchangeRateCurrent();
        log_named_uint("seize", seize);
        uint s = CToken(address(cusdc)).seize(address(this), address(strategy), seize);
        assertEq(s, 0, "seize successful");
        log_named_uint("nps", adapter.nps());
        log_named_uint("cf", get_cf());
        log_named_uint("adapter usdc ", usdc.balanceOf(address(strategy)));
        log_named_uint("adapter cusdc", cusdc.balanceOf(address(strategy)));
        log_named_uint("adapter nav  ", adapter.nav());
        log_named_uint("a max usdc    ", mul(adapter.stake(address(a)), adapter.nps()) / 1e18);

        assertLt(adapter.nav(), 350 * 1e18, "nav is halved");
    }
}
