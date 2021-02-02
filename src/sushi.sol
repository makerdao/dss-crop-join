pragma solidity ^0.6.7;
pragma experimental ABIEncoderV2;

import "./crop.sol";

interface MasterChefLike {
    function deposit(uint256 _pid, uint256 _amount) external;
    function withdraw(uint256 _pid, uint256 _amount) external;
    function poolInfo(uint256 _pid) external view returns (address, uint256, uint256, uint256);
    function poolLength() external view returns (uint256);
    function sushi() external view returns (address);
    function emergencyWithdraw(uint256 _pid) external;
}

contract SushiJoin is CropJoin {

    // --- Auth ---
    mapping (address => uint) public wards;
    function rely(address usr) external auth { wards[usr] = 1; }
    function deny(address usr) external auth { wards[usr] = 0; }
    modifier auth {
        require(wards[msg.sender] == 1, "GemJoin/not-authorized");
        _;
    }

    MasterChefLike immutable public masterchef;
    uint256 immutable public pid;
    uint256 public live = 1;

    constructor(address vat_, bytes32 ilk_, address gem_, address bonus_, address masterchef_, uint256 pid_)
        public
        CropJoin(vat_, ilk_, gem_, bonus_)
    {
        (address lpToken,,,) = MasterChefLike(masterchef_).poolInfo(pid_);
        require(lpToken == gem_, "SushiJoin/pid-does-not-match-gem");
        require(MasterChefLike(masterchef_).sushi() == bonus_, "SushiJoin/bonus-does-not-match-sushi");

        masterchef = MasterChefLike(masterchef_);
        pid = pid_;

        ERC20(gem_).approve(masterchef_, uint(-1));
        wards[msg.sender] = 1;
    }
    function nav() public override returns (uint256) {
        return total;
    }
    function crop() internal override returns (uint256) {
        // withdraw of 0 will give us only the rewards
        masterchef.withdraw(pid, 0);
        return super.crop();
    }
    function join(uint256 val) public override {
        require(live == 1, "SushiJoin/not-live");
        super.join(val);
        masterchef.deposit(pid, val);
    }
    function exit(uint256 val) public override {
        if (live == 1) {
            masterchef.withdraw(pid, val);
        }
        super.exit(val);
    }
    function flee() public override {
        if (live == 1) {
            uint val = vat.gem(ilk, msg.sender);
            masterchef.withdraw(pid, val);
        }
        super.flee();
    }
    function cage() external auth {
        masterchef.emergencyWithdraw(pid);
        live = 0;
    }
}
