pragma solidity ^0.8.0;

import { UpgradeHopV2 } from "src/script/hop/upgrade/UpgradeHopV2.s.sol";
import { RemoteHopV201 } from "src/contracts/hop/RemoteHopV201.sol";

contract UpgradeRemoteHopV2 is UpgradeHopV2 {
    function setUp() public override {
        hop = 0x0000006D38568b00B457580b734e0076C62de659;
        super.setUp();
    }

    function deployImplementation() internal override {
        vm.startBroadcast();

        newImplementation = address(
            new RemoteHopV201{ salt: 0x4e59b44847b379578588920ca78fbf26c0b4956ca4f920277adcd56bbb0400c0 }()
        );
        require(newImplementation == 0x00000000b859B05c1Ffe829E06C12e220A1aeC30, "Unexpected implementation address");

        vm.stopBroadcast();
    }
}
