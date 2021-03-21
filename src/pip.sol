import "ds-thing/thing.sol";
import "ds-value/value.sol";

import "./crop.sol";

contract CropValue is DSThing {
    address constant PIP_USDC = 0x77b68899b99b686F415d074278a9a16b336085A0;
    address immutable join;
    constructor(address join_) public {
        join = join_;
    }
    function peek() public returns (bytes32, bool) {
        (bytes32 usdc_price, bool valid) = DSValue(PIP_USDC).peek();
        return (bytes32(wmul(CropJoin(join).nps(), uint256(usdc_price))), valid);
    }
    function read() public returns (bytes32) {
        bytes32 wut; bool haz;
        (wut, haz) = peek();
        require(haz, "haz-not");
        return wut;
    }
}
