pragma solidity 0.6.12;

import "dss-interfaces/Interfaces.sol";

import "./base.sol";
import "../sushi.sol";

interface SushiLPLike is ERC20 {
    function mint(address to) external returns (uint256);
    function token0() external view returns (address);
    function token1() external view returns (address);
}

contract Usr {

    Hevm hevm;
    VatAbstract vat;
    SushiJoin adapter;
    SushiLPLike pair;
    ERC20 wbtc;
    ERC20 weth;
    MasterChefLike masterchef;
    uint256 pid;

    constructor(Hevm hevm_, SushiJoin join_, SushiLPLike pair_) public {
        hevm = hevm_;
        adapter = join_;
        pair = pair_;

        vat = VatAbstract(address(adapter.vat()));
        masterchef = adapter.masterchef();
        wbtc = ERC20(pair.token0());
        weth = ERC20(pair.token1());
        pid = adapter.pid();

        pair.approve(address(adapter), uint(-1));
        pair.approve(address(masterchef), uint(-1));
    }

    function join(uint wad) public {
        adapter.join(wad);
    }
    function exit(uint wad) public {
        adapter.exit(wad);
    }
    function crops() public view returns (uint256) {
        return adapter.crops(address(this));
    }
    function stake() public view returns (uint256) {
        return adapter.stake(address(this));
    }
    function gems() public view returns (uint256) {
        return vat.gem(adapter.ilk(), address(this));
    }
    function masterchefRewards() public view returns (uint256) {
        return masterchef.pendingSushi(adapter.pid(), address(this));
    }
    function sushi() public view returns (uint256) {
        return adapter.bonus().balanceOf(address(this));
    }
    function reap() public {
        adapter.join(0);
    }
    function flee() public {
        adapter.flee();
    }
    function tack(address src, address dst, uint256 wad) public {
        adapter.tack(src, dst, wad);
    }
    function set_wbtc(uint val) internal {
        hevm.store(
            address(wbtc),
            keccak256(abi.encode(address(this), uint256(0))),
            bytes32(uint(val))
        );
    }
    function set_weth(uint val) internal {
        hevm.store(
            address(weth),
            keccak256(abi.encode(address(this), uint256(3))),
            bytes32(uint(val))
        );
    }
    function mintLPTokens(uint wbtcVal, uint wethVal) public {
        set_wbtc(wbtcVal);
        set_weth(wethVal);
        wbtc.transfer(address(pair), wbtcVal);
        weth.transfer(address(pair), wethVal);
        pair.mint(address(this));
    }
    function getLPBalance() public view returns (uint256) {
        return pair.balanceOf(address(this));
    }
    function depositMasterchef(uint256 amount) public {
        masterchef.deposit(pid, amount);
    }
    function withdrawMasterchef(uint256 amount) public {
        masterchef.withdraw(pid, amount);
    }
    function getMasterchefDepositAmount() public view returns (uint256 amount) {
        (amount,) = masterchef.userInfo(pid, address(this));
    }
    function hope(address usr) public {
        vat.hope(usr);
    }

}

// Mainnet tests against SushiSwap
contract SushiIntegrationTest is TestBase {

    SushiLPLike pair;
    ERC20 sushi;
    MasterChefLike masterchef;
    VatAbstract vat;
    bytes32 ilk = "SUSHIWBTCETH-A";
    SushiJoin join;

    Usr user1;
    Usr user2;
    Usr user3;

    uint256 dust = 100; // Small amount to account for division rounding errors

    function setUp() public {
        vat = VatAbstract(0x35D1b3F3D7966A1DFe207aa4514C12a259A0492B);
        pair = SushiLPLike(0xCEfF51756c56CeFFCA006cD410B03FFC46dd3a58);
        sushi = ERC20(0x6B3595068778DD592e39A122f4f5a5cF09C90fE2);
        masterchef = MasterChefLike(0xc2EdaD668740f1aA35E4D8f227fB8E17dcA888Cd);

        // Give this contract admin access on the vat
        hevm.store(
            address(vat),
            keccak256(abi.encode(address(this), uint256(0))),
            bytes32(uint256(1))
        );
        assertEq(vat.wards(address(this)), 1);

        // Find the pid for the given pair
        uint numPools = masterchef.poolLength();
        uint pid = uint(-1);
        for (uint i = 0; i < numPools; i++) {
            (address lpToken,,,) = masterchef.poolInfo(i);
            if (lpToken == address(pair)) {
                pid = i;

                break;
            }
        }
        assertTrue(pid != uint(-1));

        join = new SushiJoin(address(vat), ilk, address(pair), address(sushi), address(masterchef), pid);
        vat.rely(address(join));
        user1 = new Usr(hevm, join, pair);
        user2 = new Usr(hevm, join, pair);
        user3 = new Usr(hevm, join, pair);
        user1.mintLPTokens(10**8, 10 ether);
        user2.mintLPTokens(10**8, 10 ether);
        user3.mintLPTokens(10**8, 10 ether);

        assertTrue(user1.getLPBalance() > 0);
        assertTrue(user2.getLPBalance() > 0);
        assertTrue(user3.getLPBalance() > 0);
    }

    function unclaimedAdapterRewards() public view returns (uint256) {
        return masterchef.pendingSushi(join.pid(), address(join));
    }

    function masterchefDepositAmount() public view returns (uint256 joinAmount) {
        (joinAmount,) = masterchef.userInfo(join.pid(), address(join));
    }

    // Low level actions
    function doJoin(Usr usr, uint256 amount) public {
        assertTrue(amount <= usr.getLPBalance());
        assertTrue(join.live());

        uint256 pstock = join.stock();
        uint256 pshare = join.share();
        uint256 ptotal = join.total();
        uint256 pstake = usr.stake();
        uint256 pcrops = usr.crops();
        uint256 pgems = usr.gems();
        uint256 psushi = usr.sushi();
        uint256 punclaimedRewards = unclaimedAdapterRewards();

        assertEq(masterchefDepositAmount(), join.total());

        usr.join(amount);

        uint256 sushiToUser = 0;
        if (ptotal > 0) {
            uint256 newCrops = rmul(pstake, pshare + rdiv(punclaimedRewards, ptotal));
            if (newCrops > pcrops) sushiToUser = newCrops - pcrops;
        }
        assertEq(usr.sushi(), psushi + sushiToUser);
        if (join.total() > 0) {
            assertEq(join.stock(), pstock + punclaimedRewards - sushiToUser);
        } else {
            assertTrue(join.stock() <= 1);  // May be a slight rounding error
        }
        assertEq(join.total(), ptotal + amount);
        assertEq(usr.stake(), pstake + amount);
        assertEq(usr.crops(), rmulup(usr.stake(), join.share()));
        assertEq(usr.gems(), pgems + amount);
        assertEq(pair.balanceOf(address(join)), 0);
        assertEq(unclaimedAdapterRewards(), 0);
        assertEq(masterchefDepositAmount(), join.total());
        if (ptotal > 0) {
            assertEq(join.share(), pshare + rdiv(punclaimedRewards, ptotal));
        } else {
            assertEq(join.share(), pshare);
        }
    }
    function doExit(Usr usr, uint256 amount) public {
        assertTrue(amount <= usr.gems());

        uint256 pstock = join.stock();
        uint256 pshare = join.share();
        uint256 ptotal = join.total();
        uint256 pstake = usr.stake();
        uint256 pcrops = usr.crops();
        uint256 pgems = usr.gems();
        uint256 psushi = usr.sushi();
        uint256 punclaimedRewards = unclaimedAdapterRewards();

        if (join.live()) {
            assertEq(masterchefDepositAmount(), join.total());
        } else {
            assertEq(pair.balanceOf(address(join)), join.total());
        }

        usr.exit(amount);

        assertEq(join.total(), ptotal - amount);
        assertEq(usr.stake(), pstake - amount);
        assertEq(usr.crops(), rmulup(usr.stake(), join.share()));
        assertEq(usr.gems(), pgems - amount);
        if (join.live()) {
            uint256 sushiToUser = 0;
            if (ptotal > 0) {
                uint256 newCrops = rmul(pstake, pshare + rdiv(punclaimedRewards, ptotal));
                if (newCrops > pcrops) sushiToUser = newCrops - pcrops;
            }
            assertEq(usr.sushi(), psushi + sushiToUser);
            if (join.total() > 0) {
                assertEq(join.stock(), pstock + punclaimedRewards - sushiToUser);
            } else {
                assertTrue(join.stock() <= dust);  // May be a slight rounding error
            }
            if (ptotal > 0) {
                assertEq(join.share(), pshare + rdiv(punclaimedRewards, ptotal));
            } else {
                assertEq(join.share(), pshare);
            }
            assertEq(masterchefDepositAmount(), join.total());
            assertEq(pair.balanceOf(address(join)), 0);
            assertEq(unclaimedAdapterRewards(), 0);
        } else {
            assertEq(join.stock(), pstock);
            assertEq(join.share(), pshare);
            assertEq(masterchefDepositAmount(), 0);
            assertEq(pair.balanceOf(address(join)), join.total());
            assertEq(unclaimedAdapterRewards(), punclaimedRewards);
            assertEq(usr.sushi(), psushi);
        }
    }
    function doFlee(Usr usr) public {
        uint256 amount = usr.gems();

        uint256 pstock = join.stock();
        uint256 pshare = join.share();
        uint256 ptotal = join.total();
        uint256 psushi = usr.sushi();
        uint256 punclaimedRewards = unclaimedAdapterRewards();

        if (join.live()) {
            assertEq(masterchefDepositAmount(), join.total());
        } else {
            assertEq(pair.balanceOf(address(join)), join.total());
        }

        usr.flee();

        assertEq(join.total(), ptotal - amount);
        assertEq(usr.stake(), 0);
        assertEq(usr.crops(), 0);
        assertEq(usr.gems(), 0);
        if (join.live()) {
            assertEq(masterchefDepositAmount(), join.total());
            assertEq(pair.balanceOf(address(join)), 0);
        } else {
            assertEq(masterchefDepositAmount(), 0);
            assertEq(pair.balanceOf(address(join)), join.total());
        }
        assertEq(join.stock(), pstock);
        assertEq(join.share(), pshare);
        assertEq(unclaimedAdapterRewards(), punclaimedRewards);
        assertEq(usr.sushi(), psushi);
    }
    function doCage() public {
        uint256 prewards = sushi.balanceOf(address(join));

        assertEq(pair.balanceOf(address(join)), 0);

        join.cage();

        // Should not take the rewards, only the actual LP token
        assertEq(unclaimedAdapterRewards(), 0);
        assertEq(sushi.balanceOf(address(join)), prewards);
        assertEq(pair.balanceOf(address(join)), join.total());
    }

    // High level scenarios

    // Simple join and exit with 1 user
    function basic(uint256 amount) public {
        doJoin(user1, amount);
        doExit(user1, amount);
    }

    // Join and exit, but with a delay in between to collect rewards with 1 user
    function rewards1(uint256 amount, uint256 blocksToWait) public {
        doJoin(user1, amount);

        // Allow rewards to collect
        hevm.roll(block.number + blocksToWait);

        doExit(user1, amount);
    }

    // Join and exit, but with a delay in between to collect rewards with 2 users
    function rewards2(uint256 amount1, uint256 amount2, uint256 blocksToWait) public {
        doJoin(user1, amount1);
        doJoin(user2, amount2);

        hevm.roll(block.number + blocksToWait);

        doExit(user1, amount1);
        doExit(user2, amount2);
    }

    // Join and partial exit, but with a delay in between to collect rewards with 2 users
    function prewards2(uint256 amount1, uint256 amount2, uint256 blocksToWait) public {
        doJoin(user1, amount1);
        doJoin(user2, amount2);

        hevm.roll(block.number + blocksToWait);

        doExit(user1, amount1 / 2);
        doExit(user2, amount2 / 2);
    }

    // Multiple delays with partial withdraws
    function multi2(uint256 amount1, uint256 amount2, uint256 wait1, uint256 wait2, uint256 wait3) public {
        doJoin(user1, amount1);

        hevm.roll(block.number + wait1);

        doJoin(user2, amount2);

        hevm.roll(block.number + wait2);

        doExit(user1, amount1 / 4);

        hevm.roll(block.number + wait3);

        doExit(user2, amount2 / 3);
    }

    function test_basic_all() public {
        basic(user1.getLPBalance());
    }

    function test_basic_zero() public {
        basic(0);
    }

    function test_basic_fuzz(uint256 amount) public {
        basic(amount % user1.getLPBalance());
    }

    function test_rewards1_all() public {
        rewards1(user1.getLPBalance(), 100);
    }

    function test_rewards1_zero() public {
        rewards1(0, 100);

        // Be extra safe, should not be getting any rewards out
        assertEq(user1.sushi(), 0);
    }

    function test_rewards1_fuzz(uint256 amount, uint256 blocks) public {
        rewards1(amount % user1.getLPBalance(), blocks % 100000);
    }

    function test_rewards2_all() public {
        rewards2(user1.getLPBalance(), user2.getLPBalance(), 100);
    }

    function test_rewards2_fuzz(uint256 amount1, uint256 amount2, uint256 blocks) public {
        rewards2(amount1 % user1.getLPBalance(), amount2 % user2.getLPBalance(), blocks % 100000);
    }

    function test_prewards2_all() public {
        prewards2(user1.getLPBalance(), user2.getLPBalance(), 100);
    }

    function test_prewards2_fuzz(uint256 amount1, uint256 amount2, uint256 blocks) public {
        prewards2(amount1 % user1.getLPBalance(), amount2 % user2.getLPBalance(), blocks % 100000);
    }

    function test_multi2_all() public {
        multi2(user1.getLPBalance(), user2.getLPBalance(), 50, 126, 1);
    }

    function test_multi2_fuzz(uint256 amount1, uint256 amount2, uint256 wait1, uint256 wait2, uint256 wait3) public {
        multi2(amount1 % user1.getLPBalance(), amount2 % user2.getLPBalance(), wait1 % 100000, wait2 % 100000, wait3 % 100000);
    }

    function test_flee() public {
        doJoin(user1, user1.getLPBalance());
        doJoin(user2, user2.getLPBalance() / 4);
        doFlee(user1);
    }

    function testFail_cant_steal_rewards() public {
        uint256 amount = user1.getLPBalance();
        doJoin(user1, amount);

        hevm.roll(block.number + 100);

        // user2 has no stake and so should not be able to take user1's rewards
        user2.tack(address(user1), address(user2), amount);
    }

    function test_auction_take_rewards() public {
        uint256 amount1 = user1.getLPBalance();
        uint256 amount2 = user2.getLPBalance();
        user1.join(amount1);

        hevm.roll(block.number + 100);

        // user2 takes user1's gems (via auction or something)
        user1.hope(address(this));
        vat.flux(ilk, address(user1), address(user2), amount1);

        // user2 should be able to take the rewards as well
        user2.tack(address(user1), address(user2), amount1);
        user2.exit(amount1);

        assertEq(user2.getLPBalance(), amount1 + amount2);
        assertTrue(user2.sushi() > 0);
    }

    function test_cage() public {
        uint256 amount1 = user1.getLPBalance();
        uint256 amount2 = user2.getLPBalance();
        doJoin(user1, amount1);
        doJoin(user2, amount2);

        hevm.roll(block.number + 100);

        doExit(user2, amount2 / 4);
        assertEq(join.total(), amount1 + amount2 - (amount2 / 4));
        assertEq(user2.getLPBalance(), amount2 / 4);

        hevm.roll(block.number + 200);

        // Emergency situation -- need to cage
        doCage();

        assertEq(pair.balanceOf(address(join)), amount1 + amount2 - (amount2 / 4));
        assertEq(pair.balanceOf(address(join)), join.total());

        doFlee(user1);

        assertEq(pair.balanceOf(address(join)), amount2 - (amount2 / 4));
        assertEq(user1.getLPBalance(), amount1);

        doExit(user2, amount2 / 2);

        assertEq(pair.balanceOf(address(join)), amount2 - (amount2 / 4) - (amount2 / 2));
        assertEq(user2.getLPBalance(), (amount2 / 4) + (amount2 / 2));
    }

    function testFail_cage_join() public {
        doCage();
        user1.join(user1.getLPBalance());
    }

    function test_complex_fuzz(uint256 nruns, uint256 _seed) public {
        nruns = nruns % 100;
        seed = _seed;

        Usr[3] memory users = [user1, user2, user3];

        for (uint256 i = 0; i < nruns; i++) {
            hevm.roll(block.number + rand() % 100);

            uint256 action = rand() % 4;
            uint256 u = rand() % 3;
            Usr user = users[u];
            if (action == 0) {
                // Join
                if (user.getLPBalance() == 0) continue;

                uint256 amount = rand() % (user.getLPBalance() + 1);
                log_named_uint("user", u);
                log_named_string("action", "join");
                log_named_uint("amount", amount);
                doJoin(user, amount);
            } else if (action == 1) {
                // Exit
                if (user.gems() == 0) continue;

                if (rand() % 4 == 0) {
                    // 25% chance of flee
                    log_named_uint("user", u);
                    log_named_string("action", "flee");
                    doFlee(user);
                } else {
                    uint256 amount = rand() % (user.gems() + 1);
                    log_named_uint("user", u);
                    log_named_string("action", "exit");
                    log_named_uint("amount", amount);
                    doExit(user, amount);
                }
            } else if (action == 2) {
                // Simulate 3rd party user submitting LP tokens directly to the masterchef
                if (user.getLPBalance() == 0) continue;

                uint256 amount = rand() % (user.getLPBalance() + 1);
                log_named_uint("user", u);
                log_named_string("action", "directDeposit");
                log_named_uint("amount", amount);
                user.depositMasterchef(amount);
            } else if (action == 3) {
                // Simulate 3rd party withdrawl
                if (user.getMasterchefDepositAmount() == 0) continue;

                uint256 amount = rand() % (user.getMasterchefDepositAmount() + 1);
                log_named_uint("user", u);
                log_named_string("action", "directWithdrawl");
                log_named_uint("amount", amount);
                user.withdrawMasterchef(amount);
            }
        }
    }

}
