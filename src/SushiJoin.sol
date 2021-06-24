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

import "./CropJoin.sol";

interface MasterChefLike {
    function pendingSushi(uint256 _pid, address _user) external view returns (uint256);
    function userInfo(uint256 _pid, address _user) external view returns (uint256, uint256);
    function deposit(uint256 _pid, uint256 _amount) external;
    function withdraw(uint256 _pid, uint256 _amount) external;
    function poolInfo(uint256 _pid) external view returns (address, uint256, uint256, uint256);
    function poolLength() external view returns (uint256);
    function sushi() external view returns (address);
    function migrator() external view returns (address);
    function owner() external view returns (address);
    function emergencyWithdraw(uint256 _pid) external;
    function transferOwnership(address newOwner) external;
    function setMigrator(uint256 _pid) external;
}

interface TimelockLike {
    function queuedTransactions(bytes32) external view returns (bool);
    function queueTransaction(address,uint256,string memory,bytes memory,uint256) external;
    function delay() external view returns (uint256);
}

contract SushiJoin is CropJoin {
    MasterChefLike  immutable public masterchef;
    address                   public initialMigrator;
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
        address timelockOwner_
    )
        public
        CropJoin(vat_, ilk_, gem_, bonus_)
    {
        // Sanity checks
        (address lpToken, uint256 allocPoint,,) = MasterChefLike(masterchef_).poolInfo(pid_);
        require(lpToken == gem_, "SushiJoin/pid-does-not-match-gem");
        require(MasterChefLike(masterchef_).sushi() == bonus_, "SushiJoin/bonus-does-not-match-sushi");
        require(allocPoint > 0, "SushiJoin/pool-not-active");
        require(MasterChefLike(masterchef_).migrator() == initialMigrator_, "SushiJoin/migrator-mismatch");
        require(MasterChefLike(masterchef_).owner() == timelockOwner_, "SushiJoin/owner-mismatch");

        masterchef = MasterChefLike(masterchef_);
        initialMigrator = initialMigrator_;
        timelockOwner = TimelockLike(timelockOwner_);
        pid = pid_;

        ERC20(gem_).approve(masterchef_, uint256(-1));
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
            // withdraw of 0 will give us only the rewards
            masterchef.withdraw(pid, 0);
        }
        return super.crop();
    }

    function join(address urn, address usr, uint256 val) public override {
        require(live, "SushiJoin/not-live");
        super.join(urn, usr, val);
        masterchef.deposit(pid, val);
    }

    function exit(address urn, address usr, uint256 val) public override {
        if (live) {
            masterchef.withdraw(pid, val);
        }
        super.exit(urn, usr, val);
    }

    function flee(address urn, address usr) public override {
        if (live) {
            uint256 val = vat.gem(ilk, msg.sender);
            masterchef.withdraw(pid, val);
        }
        super.flee(urn, usr);
    }
    function cage() external {
        require(live, "SushiJoin/not-live");

        // Allow caging if any assumptions change
        require(
            wards[msg.sender] == 1 ||
            masterchef.migrator() != initialMigrator ||
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
            selector == MasterChefLike.setMigrator.selector
        , "SushiJoin/wrong-function");
        bytes32 txHash = keccak256(abi.encode(masterchef, value, signature, data, eta));
        require(timelockOwner.queuedTransactions(txHash), "SushiJoin/invalid-hash");

        _cage();
    }
    function _cage() internal {
        masterchef.emergencyWithdraw(pid);
        live = false;
    }
    function uncage() external auth {
        masterchef.deposit(pid, total);
        live = true;
    }
}
