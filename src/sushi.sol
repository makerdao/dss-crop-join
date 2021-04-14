pragma solidity 0.6.12;

import "./crop.sol";

interface MasterChefLike {
    function pendingSushi(uint256 _pid, address _user) external view returns (uint256);
    function userInfo(uint256 _pid, address _user) external view returns (uint256, uint256);
    function deposit(uint256 _pid, uint256 _amount) external;
    function withdraw(uint256 _pid, uint256 _amount) external;
    function poolInfo(uint256 _pid) external view returns (address, uint256, uint256, uint256);
    function poolLength() external view returns (uint256);
    function sushi() external view returns (address);
    function emergencyWithdraw(uint256 _pid) external;
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
    uint256         immutable public pid;
    bool                      public live;

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);

    /**
        @param vat_         MCD_VAT DSS core accounting module
        @param ilk_         Collateral type
        @param gem_         The collateral LP token address
        @param bonus_       The SUSHI token contract address.
        @param masterchef_  The SushiSwap MCV1 contract address.
        @param pid_         The index of the sushi pool.
    */
    constructor(address vat_, bytes32 ilk_, address gem_, address bonus_, address masterchef_, uint256 pid_)
        public
        CropJoin(vat_, ilk_, gem_, bonus_)
    {
        (address lpToken, uint256 allocPoint,,) = MasterChefLike(masterchef_).poolInfo(pid_);
        require(lpToken == gem_, "SushiJoin/pid-does-not-match-gem");
        require(MasterChefLike(masterchef_).sushi() == bonus_, "SushiJoin/bonus-does-not-match-sushi");
        require(allocPoint > 0, "SushiJoin/pool-not-active");

        masterchef = MasterChefLike(masterchef_);
        pid = pid_;

        ERC20(gem_).approve(masterchef_, uint256(-1));
        wards[msg.sender] = 1;
        live = true;
    }

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

    function join(uint256 val) public override {
        require(live, "SushiJoin/not-live");
        super.join(val);
        masterchef.deposit(pid, val);
    }

    function exit(uint256 val) public override {
        if (live) {
            masterchef.withdraw(pid, val);
        }
        super.exit(val);
    }

    function flee() public override {
        if (live) {
            uint256 val = vat.gem(ilk, msg.sender);
            masterchef.withdraw(pid, val);
        }
        super.flee();
    }

    function cage() external auth {
        masterchef.emergencyWithdraw(pid);
        live = false;
    }
}
