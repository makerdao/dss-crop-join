// Copyright (C) Rain <rainbreak@riseup.net>
// Copyright (C) 2020 Maker Ecosystem Growth Holdings, INC.
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

import "lib/dss-interfaces/src/dapp/DSPauseAbstract.sol";
import "lib/dss-interfaces/src/dss/CatAbstract.sol";
import "lib/dss-interfaces/src/dss/FlipAbstract.sol";
import "lib/dss-interfaces/src/dss/FlipperMomAbstract.sol";
import "lib/dss-interfaces/src/dss/IlkRegistryAbstract.sol";
import "lib/dss-interfaces/src/dss/GemJoinAbstract.sol";
import "lib/dss-interfaces/src/dss/JugAbstract.sol";
import "lib/dss-interfaces/src/dss/MedianAbstract.sol";
import "lib/dss-interfaces/src/dss/OsmAbstract.sol";
import "lib/dss-interfaces/src/dss/OsmMomAbstract.sol";
import "lib/dss-interfaces/src/dss/SpotAbstract.sol";
import "lib/dss-interfaces/src/dss/VatAbstract.sol";
import "lib/dss-interfaces/src/dss/ChainlogAbstract.sol";

import "./pip.sol";
import "./wind.sol";

interface FlipFab {
    function newFlip(address,address,bytes32) external returns (address);
}

contract SpellAction {
    // MAINNET ADDRESSES
    //
    // The contracts in this list should correspond to MCD core contracts, verify
    //  against the current release list at:
    //     https://changelog.makerdao.com/releases/mainnet/1.1.4/contracts.json
    ChainlogAbstract constant CHANGELOG = ChainlogAbstract(0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F);

    address constant FLIP_FAB        = 0x4ACdbe9dd0d00b36eC2050E805012b8Fc9974f2b;

    address constant CUSDC       = 0x39AA39c021dfbaE8faC545936693aC917d5E7563;
    address constant COMPTROLLER = 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B;
    bytes32 constant ILK = "USDC-C";

    // Decimals & precision
    uint256 constant THOUSAND = 10 ** 3;
    uint256 constant MILLION  = 10 ** 6;
    uint256 constant WAD      = 10 ** 18;
    uint256 constant RAY      = 10 ** 27;
    uint256 constant RAD      = 10 ** 45;

    // Many of the settings that change weekly rely on the rate accumulator
    // described at https://docs.makerdao.com/smart-contract-modules/rates-module
    // To check this yourself, use the following rate calculation (example 8%):
    //
    // $ bc -l <<< 'scale=27; e( l(1.08)/(60 * 60 * 24 * 365) )'
    //
    // A table of rates can be found at
    //    https://ipfs.io/ipfs/QmefQMseb3AiTapiAKKexdKHig8wroKuZbmLtPLv4u2YwW
    uint256 constant FOUR_PERCENT_RATE = 1000000001243680656318820312;

    function execute() external {
        address MCD_VAT      = CHANGELOG.getAddress("MCD_VAT");
        address MCD_CAT      = CHANGELOG.getAddress("MCD_CAT");
        address MCD_JUG      = CHANGELOG.getAddress("MCD_JUG");
        address MCD_SPOT     = CHANGELOG.getAddress("MCD_SPOT");
        address MCD_END      = CHANGELOG.getAddress("MCD_END");
        address FLIPPER_MOM  = CHANGELOG.getAddress("FLIPPER_MOM");
        //address OSM_MOM      = CHANGELOG.getAddress("OSM_MOM");
        address ILK_REGISTRY = CHANGELOG.getAddress("ILK_REGISTRY");
        address USDC         = CHANGELOG.getAddress("USDC");
        address COMP         = CHANGELOG.getAddress("COMP");

        // set up adapter, flipper and pip
        address MCD_JOIN_USDC_C = address(new USDCJoin( MCD_VAT
                                         , ILK
                                         , USDC
                                         , CUSDC
                                         , COMP
                                         , COMPTROLLER
                                         ));
        address MCD_FLIP_USDC_C = FlipFab(FLIP_FAB).newFlip(MCD_VAT, MCD_CAT, ILK);
        address PIP_USDC_C = address(new CropValue(MCD_JOIN_USDC_C));

        // Add USDC-C contracts to the changelog
        CHANGELOG.setAddress("CUSDC", CUSDC);
        CHANGELOG.setAddress("MCD_JOIN_USDC_C", MCD_JOIN_USDC_C);
        CHANGELOG.setAddress("MCD_FLIP_USDC_C", MCD_FLIP_USDC_C);
        CHANGELOG.setAddress("PIP_USDC_C", PIP_USDC_C);

        CHANGELOG.setVersion("1.1.5"); // TODO:??

        // Sanity checks
        require(MCD_JOIN_USDC_C != 0x0000000000000000000000000000000000000000, "join not created");
        require(MCD_FLIP_USDC_C != 0x0000000000000000000000000000000000000000, "flip not created");
        require(PIP_USDC_C      != 0x0000000000000000000000000000000000000000, "pip not created");

        require(GemJoinAbstract(MCD_JOIN_USDC_C).vat() == MCD_VAT, "join-vat-not-match");
        require(GemJoinAbstract(MCD_JOIN_USDC_C).ilk() == ILK, "join-ilk-not-match");
        require(GemJoinAbstract(MCD_JOIN_USDC_C).gem() == USDC, "join-gem-not-match");
        require(GemJoinAbstract(MCD_JOIN_USDC_C).dec() == 6, "join-dec-not-match");
        require(FlipAbstract(MCD_FLIP_USDC_C).vat() == MCD_VAT, "flip-vat-not-match");
        require(FlipAbstract(MCD_FLIP_USDC_C).cat() == MCD_CAT, "flip-cat-not-match");
        require(FlipAbstract(MCD_FLIP_USDC_C).ilk() == ILK, "flip-ilk-not-match");

        // Set the USDC-C PIP in the Spotter
        SpotAbstract(MCD_SPOT).file(ILK, "pip", PIP_USDC_C);

        // Set the USDC-C Flipper in the Cat
        CatAbstract(MCD_CAT).file(ILK, "flip", MCD_FLIP_USDC_C);

        // Init USDC-C ilk in Vat & Jug
        VatAbstract(MCD_VAT).init(ILK);
        JugAbstract(MCD_JUG).init(ILK);

        // Allow USDC-C Join to modify Vat registry
        VatAbstract(MCD_VAT).rely(MCD_JOIN_USDC_C);
        // Allow the USDC-C Flipper to reduce the Cat litterbox on deal()
        CatAbstract(MCD_CAT).rely(MCD_FLIP_USDC_C);
        // Allow Cat to kick auctions in USDC-C Flipper
        FlipAbstract(MCD_FLIP_USDC_C).rely(MCD_CAT);
        // Allow End to yank auctions in USDC-C Flipper
        FlipAbstract(MCD_FLIP_USDC_C).rely(MCD_END);
        // Allow FlipperMom to access to the USDC-C Flipper
        FlipAbstract(MCD_FLIP_USDC_C).rely(FLIPPER_MOM);
        // Disallow Cat to kick auctions in USDC-C Flipper
        // !!!!!!!! Only for certain collaterals that do not trigger liquidations like USDC-A)
        // TODO: disable auctions?
        FlipperMomAbstract(FLIPPER_MOM).deny(MCD_FLIP_USDC_C);

        // Set the global debt ceiling
        VatAbstract(MCD_VAT).file("Line", 1_468_750_000 * RAD);
        // Set the USDC-C debt ceiling
        VatAbstract(MCD_VAT).file(ILK, "line", 5 * MILLION * RAD);
        // Set the USDC-C dust
        VatAbstract(MCD_VAT).file(ILK, "dust", 100 * RAD);
        // Set the Lot size
        CatAbstract(MCD_CAT).file(ILK, "dunk", 50 * THOUSAND * RAD);
        // Set the USDC-C liquidation penalty (e.g. 13% => X = 113)
        CatAbstract(MCD_CAT).file(ILK, "chop", 113 * WAD / 100);
        // Set the USDC-C stability fee (e.g. 1% = 1000000000315522921573372069)
        JugAbstract(MCD_JUG).file(ILK, "duty", FOUR_PERCENT_RATE);
        // Set the USDC-C percentage between bids (e.g. 3% => X = 103)
        FlipAbstract(MCD_FLIP_USDC_C).file("beg", 103 * WAD / 100);
        // Set the USDC-C time max time between bids
        FlipAbstract(MCD_FLIP_USDC_C).file("ttl", 6 hours);
        // Set the USDC-C max auction duration to
        FlipAbstract(MCD_FLIP_USDC_C).file("tau", 6 hours);
        // Set the USDC-C min collateralization ratio (e.g. 150% => X = 150)
        SpotAbstract(MCD_SPOT).file(ILK, "mat", 101 * RAY / 100);

        // Update USDC-C spot value in Vat
        SpotAbstract(MCD_SPOT).poke(ILK);

        // Add new ilk to the IlkRegistry
        IlkRegistryAbstract(ILK_REGISTRY).add(MCD_JOIN_USDC_C);
    }
}

contract DssSpell {
    DSPauseAbstract public pause =
        DSPauseAbstract(0xbE286431454714F511008713973d3B053A2d38f3);
    address         public action;
    bytes32         public tag;
    uint256         public eta;
    bytes           public sig;
    uint256         public expiration;
    bool            public done;

    // Provides a descriptive tag for bot consumption
    // This should be modified weekly to provide a summary of the actions
    // Hash: seth keccak -- "$(wget https://raw.githubusercontent.com/makerdao/community/a67032a357000839ae08c7523abcf9888c8cca3a/governance/votes/Executive%20vote%20-%20November%2013%2C%202020.md -q -O - 2>/dev/null)"
    string constant public description =
        "2020-xx-yy MakerDAO Executive Spell | Hash: 0xTODO";

    constructor() public {
        sig = abi.encodeWithSignature("execute()");
        action = address(new SpellAction());
        bytes32 _tag;
        address _action = action;
        assembly { _tag := extcodehash(_action) }
        tag = _tag;
        expiration = now + 30 days;
    }

    modifier officeHours {
        uint day = (now / 1 days + 3) % 7;
        require(day < 5, "Can only be cast on a weekday");
        uint hour = now / 1 hours % 24;
        require(hour >= 14 && hour < 21, "Outside office hours");
        _;
    }

    function schedule() public {
        require(now <= expiration, "This contract has expired");
        require(eta == 0, "This spell has already been scheduled");
        eta = now + DSPauseAbstract(pause).delay();
        pause.plot(action, tag, sig, eta);
    }

    function cast() public {
        require(!done, "spell-already-cast");
        done = true;
        pause.exec(action, tag, sig, eta);
    }
}
