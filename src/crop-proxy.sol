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
    function frob(bytes32, address, address, address, int256, int256) external;
    function hope(address) external;
}

interface EndLike {
    function free(bytes32 ilk) external;
}

interface CropLike {
    function join(address, uint256) external;
    function exit(address, address, uint256) external;
    function flee(address) external;
}

abstract contract Delegate {
    function implementation() internal view virtual returns (address);

    fallback() external {
        address _impl = implementation();
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

contract UrnProxy is Delegate {
    address immutable public logic;

    constructor(address vat) public {
        logic = msg.sender;
        VatLike(vat).hope(msg.sender);
    }

    function implementation() internal view override returns (address) { return CropProxyLogic(logic).urnProxyImplementation(); }
}

contract UrnProxyImp {
    address immutable public logic;

    constructor(address logic_) public {
        logic = logic_;
    }

    function free(address end, bytes32 ilk) external {
        require(msg.sender == logic);
        EndLike(end).free(ilk);
    }
}

contract CropProxyLogic is Delegate {
    mapping (address => uint256) public wards;
    mapping (address => address) public proxy;  // UrnProxy per user
    address logicImplementation;
    address public urnProxyImplementation;

    event Rely(address indexed);
    event Deny(address indexed);
    event SetImplementation(address indexed);
    event SetUrnProxyImplementation(address indexed);

    constructor() public {
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    function implementation() internal view override returns (address) { return logicImplementation; }

    function rely(address usr) public auth { wards[usr] = 1; emit Rely(msg.sender); }
    function deny(address usr) public auth { wards[usr] = 0; emit Deny(msg.sender); }
    modifier auth { require(wards[msg.sender] == 1, "CropJoin/non-authed"); _; }


    function setImplementation(address implementation_) external auth {
        logicImplementation = implementation_;
        emit SetImplementation(implementation_);
    }

    function setUrnProxyImplementation(address implementation_) external auth {
        urnProxyImplementation = implementation_;
        emit SetUrnProxyImplementation(implementation_);
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

    function join(address crop, address urn, uint256 val) external {
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

    function free(address end, bytes32 ilk) external {
        UrnProxyImp(getProxy(msg.sender)).free(end, ilk);
    }
}
