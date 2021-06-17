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

interface VatLike {
    function live() external view returns (uint256);
    function urns(bytes32, address) external returns (uint256, uint256);
    function fork(bytes32, address, address, int256, int256) external;
    function frob(bytes32, address, address, address, int256, int256) external;
    function hope(address) external;
    function nope(address) external;
}

interface CropLike {
    function gem() external view returns (address);
    function join(address, uint256) external;
    function exit(address, address, uint256) external;
    function flee(address) external;
}

interface TokenLike {
    function transferFrom(address, address, uint256) external;
}

contract UrnProxy {
    address immutable public vat;
    address public owner;

    constructor(address vat_) public {
        owner = msg.sender;
        vat = vat_;
        VatLike(vat_).hope(msg.sender);
    }

    function migrate(address newOwner) external {
        require(msg.sender == owner, "UrnProxy/not-owner");
        VatLike(vat).hope(newOwner);
        VatLike(vat).nope(owner);
        owner = newOwner;
    }
}

contract CropProxyLogic {
    mapping (address => uint256) public wards;
    mapping (address => address) public proxy;  // UrnProxy per user
    address public implementation;

    event Rely(address indexed);
    event Deny(address indexed);
    event SetImplementation(address indexed);

    constructor() public {
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    function rely(address usr) public auth { wards[usr] = 1; emit Rely(msg.sender); }
    function deny(address usr) public auth { wards[usr] = 0; emit Deny(msg.sender); }
    modifier auth { require(wards[msg.sender] == 1, "CropProxyLogic/non-authed"); _; }


    function setImplementation(address implementation_) external auth {
        implementation = implementation_;
        emit SetImplementation(implementation_);
    }

    fallback() external {
        address _impl = implementation;
        require(_impl != address(0));

        assembly {
            let ptr := mload(0x40)
            calldatacopy(ptr, 0, calldatasize())
            let result := delegatecall(gas(), _impl, ptr, calldatasize(), 0, 0)
            let size := returndatasize()
            returndatacopy(ptr, 0, size)

            switch result
            case 0 { revert(ptr, size) }
            default { return(ptr, size) }
        }
    }
}

contract CropProxyLogicImp {
    bytes32 slot0;
    mapping (address => address) public proxy;  // UrnProxy per user

    address public immutable vat;
    constructor(address vat_) public {
        vat = vat_;
    }

    function getProxy(address usr) internal returns (address urp) {
        urp = proxy[usr];
        if (urp == address(0)) {
            urp = proxy[usr] = address(new UrnProxy(address(vat)));
        }
    }

    function toInt(uint256 x) internal pure returns (int256 y) {
        y = int256(x);
        require(y >= 0);
    }

    function join(address crop, address urn, uint256 val) external {
        TokenLike(CropLike(crop).gem()).transferFrom(msg.sender, address(this), val);
        CropLike(crop).join(getProxy(urn), val);
    }

    function exit(address crop, address usr, uint256 val) external {
        CropLike(crop).exit(getProxy(msg.sender), usr, val);
    }

    function flee(address crop) external {
        CropLike(crop).flee(getProxy(msg.sender));
    }

    function frob(bytes32 ilk, int256 dink, int256 dart) external {
        address urp = getProxy(msg.sender);
        VatLike(vat).frob(ilk, urp, urp, msg.sender, dink, dart);
    }

    function quit(bytes32 ilk, address dst) external {
        require(VatLike(vat).live() == 0, "CropProxyLogic/vat-still-live");

        address urp = getProxy(msg.sender);
        (uint256 ink, uint256 art) = VatLike(vat).urns(ilk, urp);
        VatLike(vat).fork(
            ilk,
            urp,
            dst,
            toInt(ink),
            toInt(art)
        );
    }
}
