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

import "./crop.sol";

interface MasterChefLike {
    function pendingSushi(uint256 pid, address user) external view returns (uint256);
    function userInfo(uint256 pid, address user) external view returns (uint256 amount, uint256 rewardDebt);
    function deposit(uint256 pid, uint256 amount, address to) external;
    function withdraw(uint256 pid, uint256 amount, address to) external;
    function harvest(uint256 pid, address to) external;
    function poolInfo(uint256 pid) external view returns (uint128 accSushiPerShare, uint64 lastRewardBlock, uint64 allocPoint);
    function lpToken(uint256 pid) external view returns (address);
    function poolLength() external view returns (uint256);
    function SUSHI() external view returns (address);
    function migrator() external view returns (address);
    function owner() external view returns (address);
    function rewarder(uint256) external view returns (address);
    function emergencyWithdraw(uint256 pid, address to) external;
    function transferOwnership(address newOwner, bool direct, bool renounce) external;
    function setMigrator(address) external;
    function set(uint256 pid, uint256 allocPoint, address rewarder, bool overwrite) external;
}

interface TimelockLike {
    function queuedTransactions(bytes32) external view returns (bool);
    function queueTransaction(address,uint256,string memory,bytes memory,uint256) external;
    function executeTransaction(address,uint256,string memory,bytes memory,uint256) payable external;
    function delay() external view returns (uint256);
}

contract SushiJoin is CropJoin {

    // --- Auth ---
    mapping (address => uint256) public wards;
    function rely(address usr) external auth {
        wards[usr] = 1;
        emit Rely(usr);
    }
    function deny(address usr) external auth {
        wards[usr] = 0;
        emit Deny(usr);
    }
    modifier auth {
        require(wards[msg.sender] == 1, "SushiJoin/not-authorized");
        _;
    }

    MasterChefLike  immutable public masterchef;
    address                   public initialMigrator;
    address                   public initialRewarder;
    TimelockLike              public timelockOwner;
    uint256                   public pid;
    bool                      public live;

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event File(bytes32 indexed what, uint256 data);
    event File(bytes32 indexed what, address data);

    /**
        @param vat_                 MCD_VAT DSS core accounting module
        @param ilk_                 Collateral type
        @param gem_                 The collateral LP token address
        @param bonus_               The SUSHI token contract address.
        @param masterchef_          The SushiSwap MCV1 contract address.
        @param pid_                 The index of the sushi pool.
        @param initialMigrator_     The expected value of the migration contract.
        @param timelockOwner_       The expected timelock owner address.
    */
    constructor(
        address vat_,
        bytes32 ilk_,
        address gem_,
        address bonus_,
        address masterchef_,
        uint256 pid_,
        address initialMigrator_,
        address initialRewarder_,
        address timelockOwner_
    )
        public
        CropJoin(vat_, ilk_, gem_, bonus_)
    {
        // Sanity checks
        address lpToken = MasterChefLike(masterchef_).lpToken(pid_);
        (,, uint64 allocPoint) = MasterChefLike(masterchef_).poolInfo(pid_);
        require(lpToken == gem_, "SushiJoin/pid-does-not-match-gem");
        require(MasterChefLike(masterchef_).SUSHI() == bonus_, "SushiJoin/bonus-does-not-match-sushi");
        require(allocPoint > 0, "SushiJoin/pool-not-active");
        require(MasterChefLike(masterchef_).migrator() == initialMigrator_, "SushiJoin/migrator-mismatch");
        require(MasterChefLike(masterchef_).rewarder(pid_) == initialRewarder_, "SushiJoin/rewarder-mismatch");
        require(MasterChefLike(masterchef_).owner() == timelockOwner_, "SushiJoin/owner-mismatch");

        masterchef = MasterChefLike(masterchef_);
        initialMigrator = initialMigrator_;
        initialRewarder = initialRewarder_;
        timelockOwner = TimelockLike(timelockOwner_);
        pid = pid_;

        ERC20(gem_).approve(masterchef_, uint256(-1));
        wards[msg.sender] = 1;
        live = true;
    }

    // --- Administration ---
    function file(bytes32 what, uint256 data) external auth {
        if (what == "pid") pid = data;
        else revert("SushiJoin/file-unrecognized-param");
        emit File(what, data);
    }
    function file(bytes32 what, address data) external auth {
        if (what == "initialMigrator") initialMigrator = data;
        else if (what == "initialRewarder") initialRewarder = data;
        else if (what == "timelockOwner") timelockOwner = TimelockLike(data);
        else revert("SushiJoin/file-unrecognized-param");
        emit File(what, data);
    }

    // Ignore gems that have been directly transferred
    function nav() public override returns (uint256) {
        return total;
    }

    function crop() internal override returns (uint256) {
        if (live) {
            // This can possibly fail if no rewards are owed, but that doesn't really matter
            try masterchef.harvest(pid, address(this)) {} catch {}
        }
        return super.crop();
    }

    function join(address usr, uint256 val) public override {
        require(live, "SushiJoin/not-live");
        super.join(usr, val);
        masterchef.deposit(pid, val, address(this));
    }

    function exit(address usr, uint256 val) public override {
        if (live) {
            masterchef.withdraw(pid, val, address(this));
        }
        super.exit(usr, val);
    }

    function flee() public override {
        if (live) {
            uint256 val = vat.gem(ilk, msg.sender);
            masterchef.withdraw(pid, val, address(this));
        }
        super.flee();
    }
    function cage() external {
        require(live, "SushiJoin/not-live");

        // Allow caging if any assumptions change
        require(
            wards[msg.sender] == 1 ||
            masterchef.migrator() != initialMigrator ||
            masterchef.rewarder(pid) != initialRewarder ||
            masterchef.owner() != address(timelockOwner)
        , "SushiJoin/not-authorized");

        _cage();
    }
    function cage(uint256 value, string memory signature, bytes memory data, uint256 eta) external {
        require(live, "SushiJoin/not-live");

        // Verify the queued transaction is targetting one of the dangerous functions on Masterchef
        bytes memory callData;
        if (bytes(signature).length == 0) {
            callData = data;
        } else {
            callData = abi.encodePacked(bytes4(keccak256(bytes(signature))), data);
        }
        require(callData.length >= 4, "SushiJoin/invalid-calldata");
        bytes4 selector = bytes4(
            (uint32(uint8(callData[0])) << 24) |
            (uint32(uint8(callData[1])) << 16) |
            (uint32(uint8(callData[2])) << 8) |
            (uint32(uint8(callData[3])))
        );
        require(
            selector == MasterChefLike.transferOwnership.selector ||
            selector == MasterChefLike.setMigrator.selector ||
            selector == MasterChefLike.set.selector
        , "SushiJoin/wrong-function");
        if (selector == MasterChefLike.set.selector) {
            uint8 overwrite = uint8(callData[131]) & 0x1;
            require(overwrite == 1, "SushiJoin/bad-overwrite");
        }
        bytes32 txHash = keccak256(abi.encode(masterchef, value, signature, data, eta));
        require(timelockOwner.queuedTransactions(txHash), "SushiJoin/invalid-hash");

        _cage();
    }
    function _cage() internal {
        masterchef.emergencyWithdraw(pid, address(this));
        live = false;
    }
    function uncage() external auth {
        masterchef.deposit(pid, total, address(this));
        live = true;
    }
}
