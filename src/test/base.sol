pragma solidity ^0.6.7;
pragma experimental ABIEncoderV2;

import "ds-test/test.sol";

interface Hevm {
    function warp(uint256) external;
    function roll(uint256) external;
    function store(address,bytes32,bytes32) external;
    function load(address,bytes32) external returns (bytes32);
}

contract CanCall {
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
}

contract TestBase is DSTest {
    Hevm hevm = Hevm(address(bytes20(uint160(uint256(keccak256('hevm cheat code'))))));

    function assertTrue(bool b, bytes32 err) internal {
        if (!b) {
            emit log_named_bytes32("Fail: ", err);
            assertTrue(b);
        }
    }
    function assertEq(int a, int b, bytes32 err) internal {
        if (a != b) {
            emit log_named_bytes32("Fail: ", err);
            assertEq(a, b);
        }
    }
    function assertEq(uint a, uint b, bytes32 err) internal {
        if (a != b) {
            emit log_named_bytes32("Fail: ", err);
            assertEq(a, b);
        }
    }
    function assertGt(uint a, uint b, bytes32 err) internal {
        if (a <= b) {
            emit log_named_bytes32("Fail: ", err);
            assertGt(a, b);
        }
    }
    function assertGt(uint a, uint b) internal {
        if (a <= b) {
            emit log_bytes32("Error: a > b not satisfied");
            emit log_named_uint("         a", a);
            emit log_named_uint("         b", b);
            fail();
        }
    }
    function assertLt(uint a, uint b, bytes32 err) internal {
        if (a >= b) {
            emit log_named_bytes32("Fail: ", err);
            assertLt(a, b);
        }
    }
    function assertLt(uint a, uint b) internal {
        if (a >= b) {
            emit log_bytes32("Error: a < b not satisfied");
            emit log_named_uint("         a", a);
            emit log_named_uint("         b", b);
            fail();
        }
    }

    function mul(uint x, uint y) public pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x, "ds-math-mul-overflow");
    }
    uint256 constant WAD  = 10 ** 18;
    function wdiv(uint x, uint y) public pure returns (uint z) {
        z = mul(x, WAD) / y;
    }
}
