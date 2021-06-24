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
    function pendingSushi(uint256 _pid, address _user) external view returns (uint256);
    function userInfo(uint256 _pid, address _user) external view returns (uint256 _amount, uint256 _rewardDebt);
    function deposit(uint256 _pid, uint256 _amount, address _to) external;
    function withdraw(uint256 _pid, uint256 _amount, address _to) external;
    function harvest(uint256 _pid, address _to) external;
    function poolInfo(uint256 _pid) external view returns (uint128 _accSushiPerShare, uint64 _lastRewardBlock, uint64 _allocPoint);
    function lpToken(uint256 _pid) external view returns (address);
    function poolLength() external view returns (uint256);
    function SUSHI() external view returns (address);
    function migrator() external view returns (address);
    function owner() external view returns (address);
    function rewarder(uint256) external view returns (address);
    function emergencyWithdraw(uint256 _pid, address _to) external;
    function transferOwnership(address _newOwner, bool _direct, bool _renounce) external;
    function setMigrator(address) external;
    function set(uint256 _pid, uint256 _allocPoint, address _rewarder, bool _overwrite) external;
    function add(uint256 _allocPoint, address _lpToken, address _rewarder) external;
}

interface TimelockLike {
    function queuedTransactions(bytes32) external view returns (bool);
    function queueTransaction(address,uint256,string memory,bytes memory,uint256) external;
    function executeTransaction(address,uint256,string memory,bytes memory,uint256) payable external;
    function delay() external view returns (uint256);
    function admin() external view returns (address);
}

contract SushiJoin is CropJoin {
    MasterChefLike  immutable public masterchef;
    address                   public migrator;
    address                   public rewarder;
    TimelockLike              public timelock;
    uint256         immutable public pid;
    bool                      public live;

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event File(bytes32 indexed what, address data);

    /**
        @param vat_                 MCD_VAT DSS core accounting module
        @param ilk_                 Collateral type
        @param gem_                 The collateral LP token address
        @param bonus_               The SUSHI token contract address.
        @param masterchef_          The SushiSwap MCV1 contract address.
        @param pid_                 The index of the sushi pool.
        @param migrator_            The expected value of the migration field.
        @param rewarder_            The expected value of the rewarder field.
        @param timelock_            The expected value of the owner field. Also needs to be an instance of Timelock.
    */
    constructor(
        address vat_,
        bytes32 ilk_,
        address gem_,
        address bonus_,
        address masterchef_,
        uint256 pid_,
        address migrator_,
        address rewarder_,
        address timelock_
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
        require(MasterChefLike(masterchef_).migrator() == migrator_, "SushiJoin/migrator-mismatch");
        require(MasterChefLike(masterchef_).rewarder(pid_) == rewarder_, "SushiJoin/rewarder-mismatch");
        require(MasterChefLike(masterchef_).owner() == timelock_, "SushiJoin/owner-mismatch");

        masterchef = MasterChefLike(masterchef_);
        migrator = migrator_;
        rewarder = rewarder_;
        timelock = TimelockLike(timelock_);
        pid = pid_;

        ERC20(gem_).approve(masterchef_, uint256(-1));
        live = true;
    }

    // --- Administration ---
    function file(bytes32 what, address data) external auth {
        if (what == "migrator") migrator = data;
        else if (what == "rewarder") rewarder = data;
        else if (what == "timelock") timelock = TimelockLike(data);
        else revert("SushiJoin/file-unrecognized-param");
        emit File(what, data);
    }

    // Ignore gems that have been directly transferred
    function nav() public override returns (uint256) {
        return total;
    }

    function crop() internal override returns (uint256) {
        if (live) {
            // This can possibly fail if no rewards are owed, but that doesn't really matter as we wouldn't get any rewards anyways
            try masterchef.harvest(pid, address(this)) {} catch {}
        }
        return super.crop();
    }

    function join(address urn, address usr, uint256 val) public override {
        require(live, "SushiJoin/not-live");
        super.join(usr, usr, val);
        masterchef.deposit(pid, val, address(this));
    }

    function exit(address urn, address usr, uint256 val) public override {
        if (live) {
            masterchef.withdraw(pid, val, address(this));
        }
        super.exit(urn, usr, val);
    }

    function flee(address urn) public override {
        if (live) {
            uint256 val = vat.gem(ilk, msg.sender);
            masterchef.withdraw(pid, val, address(this));
        }
        super.flee(urn);
    }
    function cage() external {
        require(live, "SushiJoin/not-live");

        // Allow caging if any assumptions change
        require(
            wards[msg.sender] == 1 ||
            masterchef.migrator() != migrator ||
            masterchef.rewarder(pid) != rewarder ||
            masterchef.owner() != address(timelock)
        , "SushiJoin/not-authorized");

        _cage();
    }
    function cage(uint256 value, string calldata signature, bytes calldata data, uint256 eta) external {
        require(live, "SushiJoin/not-live");

        // Verify the queued transaction is targetting one of the dangerous functions on Masterchef
        bytes memory callData;
        bytes memory argData;
        if (bytes(signature).length == 0) {
            callData = data;
            argData = new bytes(data.length - 4);
            for (uint256 i = 4; i < data.length; i++) {
                argData[i - 4] = data[i];
            }
        } else {
            callData = abi.encodePacked(bytes4(keccak256(bytes(signature))), data);
            argData = data;
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
            (uint256 _pid, , address _rewarder, bool _overwrite) = abi.decode(argData, (uint256, uint256, address, bool));
            require(pid == _pid && _overwrite && _rewarder != rewarder, "SushiJoin/set-invalid-arguments");
        }
        bytes32 txHash = keccak256(abi.encode(masterchef, value, signature, data, eta));
        require(timelock.queuedTransactions(txHash), "SushiJoin/invalid-hash");

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
