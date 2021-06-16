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

import "dss-interfaces/Interfaces.sol";

import "./base.sol";
import "../crop.sol";

contract MockVat {
    mapping (bytes32 => mapping (address => uint)) public gem;
    function urns(bytes32,address) external returns (uint256, uint256) {
        return (0, 0);
    }
    function add(uint x, int y) internal pure returns (uint z) {
        z = x + uint(y);
        require(y >= 0 || z <= x, "vat/add-fail");
        require(y <= 0 || z >= x, "vat/add-fail");
    }
    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x, "vat/add-fail");
    }
    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x, "vat/sub-fail");
    }
    function slip(bytes32 ilk, address usr, int256 wad) external {
        gem[ilk][usr] = add(gem[ilk][usr], wad);
    }
    function flux(bytes32 ilk, address src, address dst, uint256 wad) external {
        gem[ilk][src] = sub(gem[ilk][src], wad);
        gem[ilk][dst] = add(gem[ilk][dst], wad);
    }
    function hope(address usr) external {}

    bytes32 expect_frob_ilk;
    address expect_frob_u;
    address expect_frob_v;
    address expect_frob_w;
    int256  expect_frob_dink;
    int256  expect_frob_dart;
    function expect_frob(bytes32 ilk, address u, address v, address w, int256 dink, int256 dart) public {
        expect_frob_ilk  = ilk;
        expect_frob_u    = u;
        expect_frob_v    = v;
        expect_frob_w    = w;
        expect_frob_dink = dink;
        expect_frob_dart = dart;
    }
    function frob(bytes32 ilk, address u, address v, address w, int256 dink, int256 dart) public view {
        require(expect_frob_ilk  == ilk);
        require(expect_frob_u    == u);
        require(expect_frob_v    == v);
        require(expect_frob_w    == w);
        require(expect_frob_dink == dink);
        require(expect_frob_dart == dart);
    }
}

contract MockEnd {
    address public immutable vat;
    bytes32 public expect_ilk;
    constructor(address _vat) public {
        vat = _vat;
    }
    function expect_free(bytes32 ilk) external {
        expect_ilk = ilk;
    }
    function free(bytes32 ilk) external {
        require(ilk == expect_ilk);
    }
}

contract Token {
    uint8 public decimals;
    mapping (address => uint) public balanceOf;
    mapping (address => mapping (address => uint)) public allowance;
    constructor(uint8 dec, uint wad) public {
        decimals = dec;
        balanceOf[msg.sender] = wad;
    }
    function transfer(address usr, uint wad) public returns (bool) {
        require(balanceOf[msg.sender] >= wad, "transfer/insufficient");
        balanceOf[msg.sender] -= wad;
        balanceOf[usr] += wad;
        return true;
    }
    function transferFrom(address src, address dst, uint wad) public returns (bool) {
        require(balanceOf[src] >= wad, "transferFrom/insufficient");
        balanceOf[src] -= wad;
        balanceOf[dst] += wad;
        return true;
    }
    function mint(address dst, uint wad) public returns (uint) {
        balanceOf[dst] += wad;
    }
    function approve(address usr, uint wad) public returns (bool) {
    }
    function mint(uint wad) public returns (uint) {
        mint(msg.sender, wad);
    }
}

contract Usr {

    CropJoin adapter;
    address public urp;  // UrnProxy of user

    constructor(CropJoin adapter_) public {
        adapter = adapter_;
        adapter_.join(address(this), 0);  // Create UrnProxy
        urp = adapter_.proxy(address(this));
    }

    function approve(address coin, address usr) public {
        Token(coin).approve(usr, uint(-1));
    }
    function join(address usr, uint wad) public {
        adapter.join(usr, wad);
    }
    function join(uint wad) public {
        adapter.join(address(this), wad);
    }
    function exit(address usr, uint wad) public {
        adapter.exit(usr, wad);
    }
    function exit(uint wad) public {
        adapter.exit(address(this), wad);
    }
    function crops() public view returns (uint256) {
        return adapter.crops(urp);
    }
    function stake() public view returns (uint256) {
        return adapter.stake(urp);
    }
    function reap() public {
        adapter.join(address(this), 0);
    }
    function flee() public {
        adapter.flee();
    }
    function tack(address src, address dst, uint256 wad) public {
        adapter.tack(src, dst, wad);
    }
    function hope(address vat, address usr) public {
        MockVat(vat).hope(usr);
    }
    function frob(int256 dink, int256 dart) public {
        adapter.frob(dink, dart);
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
    function can_exit(uint val) public returns (bool) {
        bytes memory call = abi.encodeWithSignature
            ("exit(address,uint256)", address(this), val);
        return can_call(address(adapter), call);
    }
}

contract CropUnitTest is TestBase {

    Token     gem;
    Token     bonus;
    MockVat   vat;
    MockEnd   end;
    address   self;
    bytes32   ilk = "TOKEN-A";
    CropJoin  adapter;

    function setUp() public virtual {
        self = address(this);
        gem = new Token(6, 1000 * 1e6);
        bonus = new Token(18, 0);
        vat = new MockVat();
        end = new MockEnd(address(vat));
        adapter = new CropJoin(address(vat), ilk, address(gem), address(bonus));
        adapter.file("end", address(end));
    }

    function init_user() internal returns (Usr a, Usr b) {
        return init_user(200 * 1e6);
    }
    function init_user(uint cash) internal returns (Usr a, Usr b) {
        a = new Usr(adapter);
        b = new Usr(adapter);

        gem.transfer(address(a), cash);
        gem.transfer(address(b), cash);

        a.approve(address(gem), address(adapter));
        b.approve(address(gem), address(adapter));

        a.hope(address(vat), address(this));
    }

    function reward(address usr, uint wad) internal virtual {
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
        gem.approve(address(adapter), uint(-1));

        adapter.join(address(this), 100 * 1e6);
        assertEq(bonus.balanceOf(self), 0 * 1e18, "no initial rewards");

        reward(address(adapter), 10 * 1e18);
        adapter.join(address(this), 0);
        assertEq(bonus.balanceOf(self), 10 * 1e18, "rewards increase with reap");

        adapter.join(address(this), 100 * 1e6);
        assertEq(bonus.balanceOf(self), 10 * 1e18, "rewards invariant over join");

        adapter.exit(address(this), 200 * 1e6);
        assertEq(bonus.balanceOf(self), 10 * 1e18, "rewards invariant over exit");

        adapter.join(address(this), 50 * 1e6);

        assertEq(bonus.balanceOf(self), 10 * 1e18);
        reward(address(adapter), 10 * 1e18);
        adapter.join(address(this), 10 * 1e6);
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

        b.exit(20 * 1e6);
    }

    // a user's balance can be altered with vat.flux, check that this
    // can only be disadvantageous
    // In the new design, users themselves cannot flux, but since permissioned contracts
    // might still do so, this test is retained.
    function test_flux_transfer() public {
        (Usr a, Usr b) = init_user();

        a.join(100 * 1e6);
        reward(address(adapter), 50 * 1e18);

        a.join(0);
        assertEq(bonus.balanceOf(address(a)), 50 * 1e18, "rewards increase with reap");

        reward(address(adapter), 50 * 1e18);
        vat.flux(ilk, a.urp(), b.urp(), 50 * 1e18);
        b.join(0);
        assertEq(bonus.balanceOf(address(b)),  0 * 1e18, "if nonzero we have a problem");
    }
    // if the users's balance has been altered with flux, check that
    // all parties can still exit
    // In the new design, users themselves cannot flux, but since permissioned contracts
    // might still do so, this test is retained.
    function test_flux_exit() public {
        (Usr a, Usr b) = init_user();

        a.join(100 * 1e6);
        reward(address(adapter), 50 * 1e18);

        a.join(0);
        assertEq(bonus.balanceOf(address(a)), 50 * 1e18, "rewards increase with reap");

        reward(address(adapter), 50 * 1e18);
        vat.flux(ilk, a.urp(), b.urp(), 50 * 1e18);

        assertEq(gem.balanceOf(address(a)), 100e6,  "a balance before exit");
        assertEq(a.stake(),                 100e18, "a join balance before");
        a.exit(50 * 1e6);
        assertEq(gem.balanceOf(address(a)), 150e6,  "a balance after exit");
        assertEq(a.stake(),                 50e18,  "a join balance after");

        assertEq(gem.balanceOf(address(b)), 200e6,  "b balance before exit");
        assertEq(b.stake(),                0e18,   "b join balance before");
        adapter.tack(a.urp(), b.urp(),      50e18);
        b.flee();
        assertEq(gem.balanceOf(address(b)), 250e6,  "b balance after exit");
        assertEq(b.stake(),                 0e18, "b join balance after");
    }
    // In the new design, users themselves cannot flux, but since permissioned contracts
    // might still do so, this test is retained.
    function test_reap_after_flux() public {
        (Usr a, Usr b) = init_user();

        a.join(100 * 1e6);
        reward(address(adapter), 50 * 1e18);

        a.join(0);
        assertEq(bonus.balanceOf(address(a)), 50 * 1e18, "rewards increase with reap");

        assertTrue( a.can_exit( 50e6), "can exit before flux");
        vat.flux(ilk, a.urp(), b.urp(), 100e18);
        reward(address(adapter), 50e18);

        // if x gems are transferred from a to b, a will continue to earn
        // rewards on x, while b will not earn anything on x, until we
        // reset balances with `tack`
        assertTrue(!a.can_exit(100e6), "can't fully exit after flux");
        assertEq(a.stake(), 100e18);
        a.exit(0);

        assertEq(bonus.balanceOf(address(a)), 100e18, "can claim remaining rewards");

        reward(address(adapter), 50e18);
        a.exit(0);

        assertEq(bonus.balanceOf(address(a)), 150e18, "rewards continue to accrue");

        assertEq(a.stake(), 100e18, "balance is unchanged");

        adapter.tack(a.urp(), b.urp(), 100e18);
        reward(address(adapter), 50e18);
        a.exit(0);

        assertEq(bonus.balanceOf(address(a)), 150e18, "rewards no longer increase");

        assertEq(a.stake(), 0e18, "balance is zeroed");
        assertEq(bonus.balanceOf(address(b)),  0e18, "b has no rewards yet");
        b.join(0);
        assertEq(bonus.balanceOf(address(b)), 50e18, "b now receives rewards");
    }

    // flee is an emergency exit with no rewards, check that these are
    // not given out
    function test_flee() public {
        gem.approve(address(adapter), uint(-1));

        adapter.join(address(this), 100 * 1e6);
        assertEq(bonus.balanceOf(self), 0 * 1e18, "no initial rewards");

        reward(address(adapter), 10 * 1e18);
        adapter.join(address(this), 0);
        assertEq(bonus.balanceOf(self), 10 * 1e18, "rewards increase with reap");

        reward(address(adapter), 10 * 1e18);
        adapter.exit(address(this), 50 * 1e6);
        assertEq(bonus.balanceOf(self), 20 * 1e18, "rewards increase with exit");

        reward(address(adapter), 10 * 1e18);
        assertEq(gem.balanceOf(self),  950e6, "balance before flee");
        adapter.flee();
        assertEq(bonus.balanceOf(self), 20 * 1e18, "rewards invariant over flee");
        assertEq(gem.balanceOf(self), 1000e6, "balance after flee");
        assertEq(adapter.total(), 0);
        address urp = adapter.proxy(address(this));
        assertEq(vat.gem(ilk, urp),  0);
        assertEq(adapter.stake(urp), 0);
        assertEq(adapter.crops(urp), 0);
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
        vat.flux(ilk, a.urp(), b.urp(), 100e18);
        adapter.tack(a.urp(), b.urp(), 100e18);
        b.join(0);

        reward(address(adapter), 50e18);
        a.exit(0);
        b.exit(100e6);
        assertEq(bonus.balanceOf(address(a)), 50e18, "a rewards");
        assertEq(bonus.balanceOf(address(b)), 50e18, "b rewards");

        // crop transfer
        a.join(100e6);
        reward(address(adapter), 50e18);

        // a doesn't reap their rewards before flux so all their pending
        // rewards go to b
        vat.flux(ilk, a.urp(), b.urp(), 100e18);
        adapter.tack(a.urp(), b.urp(), 100e18);

        reward(address(adapter), 50e18);
        a.exit(0);
        b.exit(100e6);
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
        assertEq(vat.gem(ilk, a.urp()), 0);
        assertEq(b.stake(), 100e18);
        assertEq(b.crops(), 0);
        assertEq(vat.gem(ilk, b.urp()), 100e18);

        // B can take all the rewards
        b.reap();
        assertEq(a.crops(), 0);
        assertEq(b.crops(), 50e18);
        assertEq(bonus.balanceOf(address(a)), 0);
        assertEq(bonus.balanceOf(address(b)), 50e18);
        
        // B withdraws to A (rewards also go to A)
        reward(address(adapter), 50e18);
        b.exit(address(a), 100e6);
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
        vat.flux(ilk, a.urp(), b.urp(), 50e18);

        assertEq(a.stake(), 100e18);
        assertEq(b.stake(), 100e18);
        assertEq(a.crops(),   0   );
        assertEq(b.crops(),  50e18);
        adapter.tack(a.urp(), b.urp(), 50e18);
        assertEq(a.stake(),  50e18);
        assertEq(b.stake(), 150e18);
        assertEq(a.crops(),   0   );
        assertEq(b.crops(),  50e18);

        // both collect rewards, which are now split equally

        assertEq(bonus.balanceOf(address(a)), 0);
        a.exit(0);
        assertEq(bonus.balanceOf(address(a)), 25e18);

        assertEq(bonus.balanceOf(address(b)), 0);
        b.exit(0);
        assertEq(bonus.balanceOf(address(b)), 25e18);

        // That wasn't too interesting since a.crops() started at zero.
        // Let's do some more operations with a non-zero share value.

        // 1/4 or 50e18 to a, 3/4 or 150e18 to b
        reward(address(adapter), 200e18);  // make it Rain

        b.join(100e6);  // modifies share
        assertEq(adapter.share(), 15 * RAY / 10);  // share is ray(1.5)

        // transfer 3/5 of a's internal gem to b w/o a reaping
        vat.flux(ilk, a.urp(), b.urp(), 30e18);

        assertEq(a.stake(),  50e18);
        assertEq(b.stake(), 250e18);
        assertEq(a.crops(),  25e18);
        assertEq(b.crops(), 375e18);
        adapter.tack(a.urp(), b.urp(), 30e18);
        assertEq(a.stake(),  20e18);
        assertEq(b.stake(), 280e18);
        assertEq(a.crops(),  10e18);
        assertEq(b.crops(), 390e18);

        // when a exits, they get 2/5 of 50e18, i.e. 20e18
        uint256 preBonusBal = bonus.balanceOf(address(a));
        a.exit(0);
        uint256 diff = sub(bonus.balanceOf(address(a)), preBonusBal);
        assertEq(diff, 20e18);

        // when b exits, they get the 3/5 of 50e18 rewards transferred from a
        preBonusBal = bonus.balanceOf(address(b));
        b.exit(0);
        diff = sub(bonus.balanceOf(address(b)), preBonusBal);
        assertEq(diff, 30e18);

        // ensure both a and b can exit completely, with their full stakes

        uint256 preGemBal = gem.balanceOf(address(a));
        preBonusBal = bonus.balanceOf(address(a));
        a.exit(20e6);
        diff = sub(gem.balanceOf(address(a)), preGemBal);
        assertEq(diff, 20e6);
        assertEq(a.stake(), 0);
        assertEq(bonus.balanceOf(address(a)), preBonusBal);

        preGemBal = gem.balanceOf(address(b));
        preBonusBal = bonus.balanceOf(address(b));
        b.exit(280e6);
        diff = sub(gem.balanceOf(address(b)), preGemBal);
        assertEq(diff, 280e6);
        assertEq(b.stake(), 0);
        assertEq(bonus.balanceOf(address(b)), preBonusBal);
    }

    function test_frob() public {
        (Usr a,) = init_user();
        vat.expect_frob(ilk, a.urp(), a.urp(), address(a), 10e18, 5e18);
        a.frob(10e18, 5e18);
    }

    function test_free() public {
        adapter.join(address(this), 0);  // set up UrnProxy
        end.expect_free(adapter.ilk());
        adapter.free();
    }

    function testFail_free_no_urp() public {
        end.expect_free(adapter.ilk());
        adapter.free();
    }

    function testFail_UrnProxy_free_wrong_caller() public {
        adapter.join(address(this), 0);  // set up UrnProxy
        end.expect_free(adapter.ilk());
        UrnProxy(adapter.proxy(address(this))).free(EndLike(address(end)), ilk);  // send must be creator of UrnProxy
    }

    function testFail_file_bad_end() public {
        MockEnd fin = new MockEnd(address(0));
        adapter.file("end", address(fin));
    }
}
