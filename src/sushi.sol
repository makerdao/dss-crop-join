pragma solidity ^0.6.7;
pragma experimental ABIEncoderV2;

import "./crop.sol";

interface MasterChefLike {
    function deposit(uint256 _pid, uint256 _amount) external;
    function withdraw(uint256 _pid, uint256 _amount) external;
    function poolInfo(uint256 _pid) external view returns (address, uint256, uint256, uint256);
}

contract SushiJoin is CropJoin {
    MasterChefLike immutable masterchef;
    uint256 immutable pid;
    constructor(address vat_, bytes32 ilk_, address gem_, address bonus_, address masterchef_, uint256 pid_)
        public
        CropJoin(vat_, ilk_, gem_, bonus_)
    {
        (address lpToken,,,) = MasterChefLike(masterchef_).poolInfo(pid_);
        require(lpToken == bonus_, "SushiJoin/pid-does-not-match-bonus");

        masterchef = MasterChefLike(masterchef_);
        pid = pid_;
    }
    function crop() internal override returns (uint256) {
        // Unforunately there is no getRewards() function so we have to withdraw then deposit
        // This will leave all the bonus tokens in the join adapter
        masterchef.withdraw(pid, total);
        masterchef.deposit(pid, total);
        return super.crop();
    }
    function join(uint256 val) public override {
        super.join(val);
        masterchef.deposit(pid, val);
    }
    function exit(uint256 val) public override {
        masterchef.withdraw(pid, val);
        super.exit(val);
    }
    function flee() public override {
        uint val = vat.gem(ilk, msg.sender);
        masterchef.withdraw(pid, val);
        super.flee();
    }
}
