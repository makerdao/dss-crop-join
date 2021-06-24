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
import "../CropJoin.sol";

contract MockVat {
    struct Urn {
        uint256 ink;   // Locked Collateral  [wad]
        uint256 art;   // Normalised Debt    [wad]
    }
    mapping (bytes32 => mapping (address => uint256)) public gem;
    mapping (bytes32 => mapping (address => Urn)) public urns;
    mapping (address => uint256) public dai;
    uint256 public live = 1;
    function add(uint256 x, int256 y) internal pure returns (uint256 z) {
        z = x + uint256(y);
        require(y >= 0 || z <= x, "vat/add-fail");
        require(y <= 0 || z >= x, "vat/add-fail");
    }
    function sub(uint256 x, int256 y) internal pure returns (uint256 z) {
        z = x - uint256(y);
        require(y <= 0 || z <= x, "vat/sub-fail");
        require(y >= 0 || z >= x, "vat/sub-fail");
    }
    function add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x, "vat/add-fail");
    }
    function sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x, "vat/sub-fail");
    }
    function slip(bytes32 ilk, address usr, int256 wad) external {
        gem[ilk][usr] = add(gem[ilk][usr], wad);
    }
    function frob(bytes32 ilk, address u, address v, address w, int256 dink, int256 dart) external {
        Urn storage urn = urns[ilk][u];
        urn.ink = add(urn.ink, dink);
        urn.art = add(urn.art, dart);
        gem[ilk][v] = sub(gem[ilk][v], dink);
        dai[w] = add(dai[w], dart * 10**27);
    }
    function fork(bytes32 ilk, address src, address dst, int256 dink, int256 dart) external {
        Urn storage u = urns[ilk][src];
        Urn storage v = urns[ilk][dst];

        u.ink = sub(u.ink, dink);
        u.art = sub(u.art, dart);
        v.ink = add(v.ink, dink);
        v.art = add(v.art, dart);
    }
    function flux(bytes32 ilk, address src, address dst, uint256 wad) external {
        gem[ilk][src] = sub(gem[ilk][src], wad);
        gem[ilk][dst] = add(gem[ilk][dst], wad);
    }
    function hope(address usr) external {}
    function cage() external {
        live = 0;
    }
}

contract Usr {

    CropJoin adapter;

    constructor(CropJoin adapter_) public {
        adapter = adapter_;
    }

    function approve(address coin, address usr) public {
        Token(coin).approve(usr, uint256(-1));
    }
    function join(address usr, uint256 wad) public {
        adapter.join(usr, usr, wad);
    }
    function join(uint256 wad) public {
        adapter.join(address(this), address(this), wad);
    }
    function exit(address urn, address usr, uint256 wad) public {
        adapter.exit(urn, usr, wad);
    }
    function crops() public view returns (uint256) {
        return adapter.crops(address(this));
    }
    function stake() public view returns (uint256) {
        return adapter.stake(address(this));
    }
    function reap() public {
        adapter.join(address(this), address(this), 0);
    }
    function flee(address urn, address usr) public {
        adapter.flee(urn, usr);
    }
    function tack(address src, address dst, uint256 wad) public {
        adapter.tack(src, dst, wad);
    }
    function hope(address vat, address usr) public {
        MockVat(vat).hope(usr);
    }

    function try_call(address addr, bytes calldata data) external returns (bool) {
        bytes memory _data = data;
        assembly {
            let ok := call(gas(), addr, 0, add(_data, 0x20), mload(_data), 0, 0)
            let free := mload(0x40)
            mstore(free, ok)
            mstore(0x40, add(free, 32))
            revert(free, 32)
        }
    }
    function can_call(address addr, bytes memory data) internal returns (bool) {
        (bool ok, bytes memory success) = address(this).call(
                                            abi.encodeWithSignature(
                                                "try_call(address,bytes)"
                                                , addr
                                                , data
                                                ));
        ok = abi.decode(success, (bool));
        if (ok) return true;
    }
    function can_exit(address urn, address usr, uint256 val) public returns (bool) {
        bytes memory call = abi.encodeWithSignature
            ("exit(address,address,uint256)", urn, usr, val);
        return can_call(address(adapter), call);
    }
}

contract CropUnitTest is TestBase {

    Token     gem;
    Token     bonus;
    MockVat   vat;
    address   self;
    bytes32   ilk = "TOKEN-A";
    CropJoin  adapter;

    function setUp() public virtual {
        self = address(this);
        gem = new Token(6, 1000 * 1e6);
        bonus = new Token(18, 0);
        vat = new MockVat();
        adapter = new CropJoin(address(vat), ilk, address(gem), address(bonus));
    }

    function init_user() internal returns (Usr a, Usr b) {
        return init_user(200 * 1e6);
    }
    function init_user(uint256 cash) internal returns (Usr a, Usr b) {
        a = new Usr(adapter);
        b = new Usr(adapter);
        adapter.rely(address(a));
        adapter.rely(address(b));

        gem.transfer(address(a), cash);
        gem.transfer(address(b), cash);

        a.approve(address(gem), address(adapter));
        b.approve(address(gem), address(adapter));

        a.hope(address(vat), address(this));
    }

    function reward(address usr, uint256 wad) internal virtual {
        bonus.mint(usr, wad);
    }

    function test_reward() public virtual {
        reward(self, 100 ether);
        assertEq(bonus.balanceOf(self), 100 ether);
    }

    function test_simple_multi_user() public {
        (Usr a, Usr b) = init_user();

        a.join(60 * 1e6);
        b.join(40 * 1e6);

        reward(address(adapter), 50 * 1e18);

        a.join(0);
        assertEq(bonus.balanceOf(address(a)), 30 * 1e18);
        assertEq(bonus.balanceOf(address(b)),  0 * 1e18);

        b.join(0);
        assertEq(bonus.balanceOf(address(a)), 30 * 1e18);
        assertEq(bonus.balanceOf(address(b)), 20 * 1e18);
    }
    function test_simple_multi_reap() public {
        (Usr a, Usr b) = init_user();

        a.join(60 * 1e6);
        b.join(40 * 1e6);

        reward(address(adapter), 50 * 1e18);

        a.join(0);
        assertEq(bonus.balanceOf(address(a)), 30 * 1e18);
        assertEq(bonus.balanceOf(address(b)),  0 * 1e18);

        b.join(0);
        assertEq(bonus.balanceOf(address(a)), 30 * 1e18);
        assertEq(bonus.balanceOf(address(b)), 20 * 1e18);

        a.join(0); b.reap();
        assertEq(bonus.balanceOf(address(a)), 30 * 1e18);
        assertEq(bonus.balanceOf(address(b)), 20 * 1e18);
    }
    function test_simple_join_exit() public {
        gem.approve(address(adapter), uint256(-1));

        adapter.join(address(this), address(this), 100 * 1e6);
        assertEq(bonus.balanceOf(self), 0 * 1e18, "no initial rewards");

        reward(address(adapter), 10 * 1e18);
        adapter.join(address(this), address(this), 0);
        assertEq(bonus.balanceOf(self), 10 * 1e18, "rewards increase with reap");

        adapter.join(address(this), address(this), 100 * 1e6);
        assertEq(bonus.balanceOf(self), 10 * 1e18, "rewards invariant over join");

        adapter.exit(address(this), address(this), 200 * 1e6);
        assertEq(bonus.balanceOf(self), 10 * 1e18, "rewards invariant over exit");

        adapter.join(address(this), address(this), 50 * 1e6);

        assertEq(bonus.balanceOf(self), 10 * 1e18);
        reward(address(adapter), 10 * 1e18);
        adapter.join(address(this), address(this), 10 * 1e6);
        assertEq(bonus.balanceOf(self), 20 * 1e18);
    }
    function test_complex_scenario() public {
        (Usr a, Usr b) = init_user();

        a.join(60 * 1e6);
        b.join(40 * 1e6);

        reward(address(adapter), 50 * 1e18);

        a.join(0);
        assertEq(bonus.balanceOf(address(a)), 30 * 1e18);
        assertEq(bonus.balanceOf(address(b)),  0 * 1e18);

        b.join(0);
        assertEq(bonus.balanceOf(address(a)), 30 * 1e18);
        assertEq(bonus.balanceOf(address(b)), 20 * 1e18);

        a.join(0); b.reap();
        assertEq(bonus.balanceOf(address(a)), 30 * 1e18);
        assertEq(bonus.balanceOf(address(b)), 20 * 1e18);

        reward(address(adapter), 50 * 1e18);
        a.join(20 * 1e6);
        a.join(0); b.reap();
        assertEq(bonus.balanceOf(address(a)), 60 * 1e18);
        assertEq(bonus.balanceOf(address(b)), 40 * 1e18);

        reward(address(adapter), 30 * 1e18);
        a.join(0); b.reap();
        assertEq(bonus.balanceOf(address(a)), 80 * 1e18);
        assertEq(bonus.balanceOf(address(b)), 50 * 1e18);

        b.exit(address(b), address(b), 20 * 1e6);
    }

    // a user's balance can be altered with vat.flux, check that this
    // can only be disadvantageous
    function test_flux_transfer() public {
        (Usr a, Usr b) = init_user();

        a.join(100 * 1e6);
        reward(address(adapter), 50 * 1e18);

        a.join(0);
        assertEq(bonus.balanceOf(address(a)), 50 * 1e18, "rewards increase with reap");

        reward(address(adapter), 50 * 1e18);
        vat.flux(ilk, address(a), address(b), 50 * 1e18);
        b.join(0);
        assertEq(bonus.balanceOf(address(b)),  0 * 1e18, "if nonzero we have a problem");
    }
    // if the users's balance has been altered with flux, check that
    // all parties can still exit
    function test_flux_exit() public {
        (Usr a, Usr b) = init_user();

        a.join(100 * 1e6);
        reward(address(adapter), 50 * 1e18);

        a.join(0);
        assertEq(bonus.balanceOf(address(a)), 50 * 1e18, "rewards increase with reap");

        reward(address(adapter), 50 * 1e18);
        vat.flux(ilk, address(a), address(b), 50 * 1e18);

        assertEq(gem.balanceOf(address(a)), 100e6,  "a balance before exit");
        assertEq(adapter.stake(address(a)),     100e18, "a join balance before");
        a.exit(address(a), address(a), 50 * 1e6);
        assertEq(gem.balanceOf(address(a)), 150e6,  "a balance after exit");
        assertEq(adapter.stake(address(a)),      50e18, "a join balance after");

        assertEq(gem.balanceOf(address(b)), 200e6,  "b balance before exit");
        assertEq(adapter.stake(address(b)),       0e18, "b join balance before");
        adapter.tack(address(a), address(b),     50e18);
        b.flee(address(b), address(b));
        assertEq(gem.balanceOf(address(b)), 250e6,  "b balance after exit");
        assertEq(adapter.stake(address(b)),       0e18, "b join balance after");
    }
    function test_reap_after_flux() public {
        (Usr a, Usr b) = init_user();

        a.join(100 * 1e6);
        reward(address(adapter), 50 * 1e18);

        a.join(0);
        assertEq(bonus.balanceOf(address(a)), 50 * 1e18, "rewards increase with reap");

        assertTrue( a.can_exit(address(a), address(a), 50e6), "can exit before flux");
        vat.flux(ilk, address(a), address(b), 100e18);
        reward(address(adapter), 50e18);

        // if x gems are transferred from a to b, a will continue to earn
        // rewards on x, while b will not earn anything on x, until we
        // reset balances with `tack`
        assertTrue(!a.can_exit(address(a), address(a), 100e6), "can't full exit after flux");
        assertEq(adapter.stake(address(a)),     100e18);
        a.exit(address(a), address(a), 0);

        assertEq(bonus.balanceOf(address(a)), 100e18, "can claim remaining rewards");

        reward(address(adapter), 50e18);
        a.exit(address(a), address(a), 0);

        assertEq(bonus.balanceOf(address(a)), 150e18, "rewards continue to accrue");

        assertEq(adapter.stake(address(a)),     100e18, "balance is unchanged");

        adapter.tack(address(a), address(b),    100e18);
        reward(address(adapter), 50e18);
        a.exit(address(a), address(a), 0);

        assertEq(bonus.balanceOf(address(a)), 150e18, "rewards no longer increase");

        assertEq(adapter.stake(address(a)),       0e18, "balance is zeroed");
        assertEq(bonus.balanceOf(address(b)),   0e18, "b has no rewards yet");
        b.join(0);
        assertEq(bonus.balanceOf(address(b)),  50e18, "b now receives rewards");
    }

    // flee is an emergency exit with no rewards, check that these are
    // not given out
    function test_flee() public {
        gem.approve(address(adapter), uint256(-1));

        adapter.join(address(this), address(this), 100 * 1e6);
        assertEq(bonus.balanceOf(self), 0 * 1e18, "no initial rewards");

        reward(address(adapter), 10 * 1e18);
        adapter.join(address(this), address(this), 0);
        assertEq(bonus.balanceOf(self), 10 * 1e18, "rewards increase with reap");

        reward(address(adapter), 10 * 1e18);
        adapter.exit(address(this), address(this), 50 * 1e6);
        assertEq(bonus.balanceOf(self), 20 * 1e18, "rewards increase with exit");

        reward(address(adapter), 10 * 1e18);
        assertEq(gem.balanceOf(self),  950e6, "balance before flee");
        adapter.flee(address(this), address(this));
        assertEq(bonus.balanceOf(self), 20 * 1e18, "rewards invariant over flee");
        assertEq(gem.balanceOf(self), 1000e6, "balance after flee");
    }

    function test_tack() public {
        /*
           A user's pending rewards, assuming no further crop income, is
           given by
               stake[usr] * share - crops[usr]
           After join/exit we set
               crops[usr] = stake[usr] * share
           Such that the pending rewards are zero.
           With `tack` we transfer stake from one user to another, but
           we must ensure that we also either (a) transfer crops or
           (b) reap the rewards concurrently.
           Here we check that tack accounts for rewards appropriately,
           regardless of whether we use (a) or (b).
        */
        (Usr a, Usr b) = init_user();

        // concurrent reap
        a.join(100e6);
        reward(address(adapter), 50e18);

        a.join(0);
        vat.flux(ilk, address(a), address(b), 100e18);
        adapter.tack(address(a), address(b), 100e18);
        b.join(0);

        reward(address(adapter), 50e18);
        a.exit(address(a), address(a), 0);
        b.exit(address(b), address(b), 100e6);
        assertEq(bonus.balanceOf(address(a)), 50e18, "a rewards");
        assertEq(bonus.balanceOf(address(b)), 50e18, "b rewards");

        // crop transfer
        a.join(100e6);
        reward(address(adapter), 50e18);

        // a doesn't reap their rewards before flux so all their pending
        // rewards go to b
        vat.flux(ilk, address(a), address(b), 100e18);
        adapter.tack(address(a), address(b), 100e18);

        reward(address(adapter), 50e18);
        a.exit(address(a), address(a), 0);
        b.exit(address(b), address(b), 100e6);
        assertEq(bonus.balanceOf(address(a)),  50e18, "a rewards alt");
        assertEq(bonus.balanceOf(address(b)), 150e18, "b rewards alt");
    }

    function test_join_other() public {
        (Usr a, Usr b) = init_user();

        assertEq(gem.balanceOf(address(a)), 200e6);
        assertEq(gem.balanceOf(address(b)), 200e6);

        // User A sends some gems + rewards to User B
        a.join(address(b), 100e6);
        reward(address(adapter), 50e18);
        assertEq(a.stake(), 0);
        assertEq(a.crops(), 0);
        assertEq(vat.gem(ilk, address(a)), 0);
        assertEq(b.stake(), 100e18);
        assertEq(b.crops(), 0);
        assertEq(vat.gem(ilk, address(b)), 100e18);

        // B can take all the rewards
        b.reap();
        assertEq(a.crops(), 0);
        assertEq(b.crops(), 50e18);
        assertEq(bonus.balanceOf(address(a)), 0);
        assertEq(bonus.balanceOf(address(b)), 50e18);
        
        // B withdraws to A (rewards also go to A)
        reward(address(adapter), 50e18);
        b.exit(address(b), address(a), 100e6);
        assertEq(gem.balanceOf(address(a)), 200e6);
        assertEq(gem.balanceOf(address(b)), 200e6);
        assertEq(a.crops(), 0);
        assertEq(b.crops(), 0);
        assertEq(bonus.balanceOf(address(a)), 50e18);
        assertEq(bonus.balanceOf(address(b)), 50e18);
    }
    
    function test_tack_share_differs() public {
        /*
            If share (cumulative bonus tokens per stake) changes, this affects
            the adjustment that must be done to the crops of the src and dst
            addresses in tack. Specifically:

            crops[src] <-- crops[src] * (stake[src] - wad) / stake[src]
            crops[dst] <-- crops[dst] + crops[src] * wad / stake[src]

            where all RHS quantities are evaluated immediately prior to the call
            to tack. It can be verified that this transfers pending rewards from
            src to dst proportional to the fraction of src's stake that is
            transferred.
        */
        (Usr a, Usr b) = init_user();  // each has 200 * 10^6 gem

        a.join(100e6);
        reward(address(adapter), 50e18);  // a has 50e18 pending rewards

        b.join(100e6);  // modifies share

        // half of a's internal gem transferred to b w/o a reaping
        vat.flux(ilk, address(a), address(b), 50e18);

        assertEq(adapter.stake(address(a)), 100e18);
        assertEq(adapter.stake(address(b)), 100e18);
        assertEq(adapter.crops(address(a)), 0);
        assertEq(adapter.crops(address(b)), 50e18);
        adapter.tack(address(a), address(b), 50e18);
        assertEq(adapter.stake(address(a)),  50e18);
        assertEq(adapter.stake(address(b)), 150e18);
        assertEq(adapter.crops(address(a)), 0);
        assertEq(adapter.crops(address(b)), 50e18);

        // both collect rewards, which are now split equally

        assertEq(bonus.balanceOf(address(a)), 0);
        a.exit(address(a), address(a), 0);
        assertEq(bonus.balanceOf(address(a)), 25e18);

        assertEq(bonus.balanceOf(address(b)), 0);
        b.exit(address(b), address(b), 0);
        assertEq(bonus.balanceOf(address(b)), 25e18);

        // That wasn't too interesting since crops(a) started at zero.
        // Let's do some more operations with a non-zero share value.

        // 1/4 or 50e18 to a, 3/4 or 150e18 to b
        reward(address(adapter), 200e18);  // make it Rain

        b.join(100e6);  // modifies share
        assertEq(adapter.share(), 15 * RAY / 10);  // share is ray(1.5)

        // transfer 3/5 of a's internal gem to b w/o a reaping
        vat.flux(ilk, address(a), address(b), 30e18);

        assertEq(adapter.stake(address(a)),  50e18);
        assertEq(adapter.stake(address(b)), 250e18);
        assertEq(adapter.crops(address(a)),  25e18);
        assertEq(adapter.crops(address(b)), 375e18);
        adapter.tack(address(a), address(b), 30e18);
        assertEq(adapter.stake(address(a)),  20e18);
        assertEq(adapter.stake(address(b)), 280e18);
        assertEq(adapter.crops(address(a)),  10e18);
        assertEq(adapter.crops(address(b)), 390e18);

        // when a exits, they get 2/5 of 50e18, i.e. 20e18
        uint256 preBonusBal = bonus.balanceOf(address(a));
        a.exit(address(a), address(a), 0);
        uint256 diff = sub(bonus.balanceOf(address(a)), preBonusBal);
        assertEq(diff, 20e18);

        // when b exits, they get the 3/5 of 50e18 rewards transferred from a
        preBonusBal = bonus.balanceOf(address(b));
        b.exit(address(b), address(b), 0);
        diff = sub(bonus.balanceOf(address(b)), preBonusBal);
        assertEq(diff, 30e18);

        // ensure both a and b can exit completely, with their full stakes

        uint256 preGemBal = gem.balanceOf(address(a));
        preBonusBal = bonus.balanceOf(address(a));
        a.exit(address(a), address(a), 20e6);
        diff = sub(gem.balanceOf(address(a)), preGemBal);
        assertEq(diff, 20e6);
        assertEq(adapter.stake(address(a)), 0);
        assertEq(bonus.balanceOf(address(a)), preBonusBal);

        preGemBal = gem.balanceOf(address(b));
        preBonusBal = bonus.balanceOf(address(b));
        b.exit(address(b), address(b), 280e6);
        diff = sub(gem.balanceOf(address(b)), preGemBal);
        assertEq(diff, 280e6);
        assertEq(adapter.stake(address(b)), 0);
        assertEq(bonus.balanceOf(address(b)), preBonusBal);
    }
}
