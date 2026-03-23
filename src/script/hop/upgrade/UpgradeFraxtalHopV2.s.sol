pragma solidity ^0.8.0;

import { UpgradeHopV2 } from "src/script/hop/upgrade/UpgradeHopV2.s.sol";
import { FraxtalHopV201 } from "src/contracts/hop/FraxtalHopV201.sol";

contract UpgradeFraxtalHopV2 is UpgradeHopV2 {
    function setUp() public override {
        hop = 0x00000000e18aFc20Afe54d4B2C8688bB60c06B36;
        super.setUp();
    }

    function deployImplementation() internal override {
        vm.startBroadcast();

        newImplementation = address(
            new FraxtalHopV201{ salt: 0x4e59b44847b379578588920ca78fbf26c0b4956c0128eea54b3b9ce0580200c0 }()
        );
        require(newImplementation == 0x000000005eeDC6EB7B1711563E70edAAB996ed29, "Unexpected implementation address");

        vm.stopBroadcast();
    }
}
