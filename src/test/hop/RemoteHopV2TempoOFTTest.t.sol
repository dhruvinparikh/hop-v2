// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import { OptionsBuilder } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oapp/libs/OptionsBuilder.sol";
import { OFTMsgCodec } from "@layerzerolabs/oft-evm/contracts/libs/OFTMsgCodec.sol";
import { OFTComposeMsgCodec } from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";
import { TestHelperOz5 } from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { RemoteHopV2Tempo } from "src/contracts/hop/RemoteHopV2Tempo.sol";
import { HopMessage } from "src/contracts/interfaces/IHopV2.sol";

import { StdTokens } from "tempo-std/StdTokens.sol";

import { TempoOFTMock, TestHopComposer, TempoTestHelpers } from "./RemoteHopV2TempoTestBase.t.sol";

/// @title RemoteHopV2TempoOFTTest
/// @notice Tests for RemoteHopV2Tempo with OFT (not adapter) pattern
/// @dev Architecture: Tempo side uses FraxOFTUpgradeableTempo (mint/burn OFT),
///      other chains use FraxOFTMintableAdapterUpgradeable (adapter wrapping ERC20)
contract RemoteHopV2TempoOFTTest is TestHelperOz5, TempoTestHelpers {
    using OptionsBuilder for bytes;

    RemoteHopV2Tempo remoteHopTempo;
    TempoOFTMock tempoOft; // Full OFT on Tempo (mint/burn)

    address proxyAdmin = makeAddr("proxyAdmin");
    address[] approvedOfts;

    uint32 constant TEMPO_EID = 1;
    uint32 constant FRAXTAL_EID = 2;

    address fraxtalHop = address(0x123);

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    uint256 initialBalance = 100e18;

    function setUp() public virtual override {
        vm.deal(alice, 1000 ether);
        vm.deal(bob, 1000 ether);

        // Grant PATH_USD issuer role for minting in tests (precompile is real)
        _grantPathUsdIssuerRole(address(this));

        // Setup LayerZero endpoints using TestHelperOz5
        address[] memory altTokens = new address[](2);
        altTokens[0] = StdTokens.PATH_USD_ADDRESS; // Tempo uses PATH_USD as native
        altTokens[1] = address(0); // Fraxtal uses native ETH

        super.setUp();
        createEndpoints(2, LibraryType.UltraLightNode, altTokens);

        // Deploy TempoOFTMock - full OFT with mint/burn (mimics FraxOFTUpgradeableTempo)
        tempoOft = TempoOFTMock(
            _deployOApp(
                type(TempoOFTMock).creationCode,
                abi.encode("Tempo OFT", "TOFT", address(endpoints[TEMPO_EID]), address(this))
            )
        );

        approvedOfts.push(address(tempoOft));

        // Deploy RemoteHopV2Tempo
        remoteHopTempo = _deployRemoteHopV2Tempo();

        // Mint OFT tokens to test users
        tempoOft.mint(alice, initialBalance);
        tempoOft.mint(bob, initialBalance);
        StdTokens.PATH_USD.mint(alice, 1_000_000e6);
        StdTokens.PATH_USD.mint(bob, 1_000_000e6);

        // Set user gas tokens via TIP_FEE_MANAGER precompile
        _setUserGasToken(alice, StdTokens.PATH_USD_ADDRESS);
        _setUserGasToken(bob, StdTokens.PATH_USD_ADDRESS);

        // Configure peer for Fraxtal (30_255 = FRAXTAL_EID in production)
        tempoOft.setPeer(30_255, OFTMsgCodec.addressToBytes32(address(0x999)));
    }

    function _deployRemoteHopV2Tempo() internal returns (RemoteHopV2Tempo) {
        address endpointAddr = address(endpoints[TEMPO_EID]);

        RemoteHopV2Tempo implementation = new RemoteHopV2Tempo(endpointAddr);

        bytes memory initializeArgs = abi.encodeWithSignature(
            "initialize(uint32,address,bytes32,uint32,address,address,address,address[])",
            TEMPO_EID,
            endpointAddr,
            OFTMsgCodec.addressToBytes32(fraxtalHop),
            2,
            address(0x1),
            address(0x2),
            address(0x3),
            approvedOfts
        );

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            proxyAdmin,
            initializeArgs
        );

        return RemoteHopV2Tempo(payable(address(proxy)));
    }

    // ============ Initialization Tests ============

    function test_OFT_Initialization() public view {
        assertEq(remoteHopTempo.localEid(), TEMPO_EID, "Local EID should be set");
        assertTrue(remoteHopTempo.approvedOft(address(tempoOft)), "Tempo OFT should be approved");
    }

    // ============ SendOFT Tests ============

    function test_OFT_SendOFT_RevertsWhenMsgValueNonZero() public {
        address oft = address(tempoOft);

        vm.startPrank(alice);
        tempoOft.approve(address(remoteHopTempo), 1e18);
        StdTokens.PATH_USD.approve(address(remoteHopTempo), 1000e6);

        vm.expectRevert(abi.encodeWithSelector(RemoteHopV2Tempo.MsgValueNotZero.selector, 1 ether));
        remoteHopTempo.sendOFT{ value: 1 ether }(oft, 30_255, bytes32(uint256(uint160(bob))), 1e18, 0, "");
        vm.stopPrank();
    }

    function test_OFT_SendOFT_LocalTransfer() public {
        address oft = address(tempoOft);
        address recipient = address(0x456);

        vm.startPrank(alice);
        tempoOft.approve(address(remoteHopTempo), 1e18);

        remoteHopTempo.sendOFT{ value: 0 }(oft, TEMPO_EID, bytes32(uint256(uint160(recipient))), 1e18, 0, "");
        vm.stopPrank();

        assertEq(tempoOft.balanceOf(recipient), 1e18, "Recipient should receive OFT tokens");
    }

    function test_OFT_SendOFT_LocalTransferWithCompose() public {
        address oft = address(tempoOft);
        TestHopComposer composer = new TestHopComposer();

        vm.startPrank(alice);
        tempoOft.approve(address(remoteHopTempo), 1e18);

        bytes memory data = "test data";

        vm.expectEmit(true, true, true, true);
        emit TestHopComposer.Composed(TEMPO_EID, bytes32(uint256(uint160(alice))), oft, 1e18, data);

        remoteHopTempo.sendOFT{ value: 0 }(oft, TEMPO_EID, bytes32(uint256(uint160(address(composer)))), 1e18, 0, data);
        vm.stopPrank();

        assertEq(tempoOft.balanceOf(address(composer)), 1e18, "Composer should receive OFT tokens");
    }

    // ============ LzCompose Tests ============

    function test_OFT_LzCompose_SendLocal_WithoutData() public {
        address oft = address(tempoOft);
        address recipient = address(0x456);

        // Fund the hop with OFT tokens
        tempoOft.mint(address(remoteHopTempo), 1e18);

        bytes memory composeMsg = abi.encode(
            HopMessage({
                srcEid: 30_255,
                dstEid: TEMPO_EID,
                dstGas: 0,
                sender: bytes32(uint256(uint160(address(0x123)))),
                recipient: bytes32(uint256(uint160(recipient))),
                data: ""
            })
        );
        composeMsg = abi.encodePacked(OFTMsgCodec.addressToBytes32(fraxtalHop), composeMsg);
        bytes memory message = OFTComposeMsgCodec.encode(0, 30_255, 1e18, composeMsg);

        vm.prank(address(endpoints[TEMPO_EID]));
        remoteHopTempo.lzCompose(oft, bytes32(0), message, address(0), "");

        assertEq(tempoOft.balanceOf(recipient), 1e18, "Recipient should receive OFT tokens");
    }

    function test_OFT_LzCompose_SendLocal_WithData() public {
        address oft = address(tempoOft);
        TestHopComposer composer = new TestHopComposer();

        tempoOft.mint(address(remoteHopTempo), 1e18);

        bytes memory data = "Hello Remote";
        bytes memory composeMsg = abi.encode(
            HopMessage({
                srcEid: 30_255,
                dstEid: TEMPO_EID,
                dstGas: 0,
                sender: bytes32(uint256(uint160(address(0x123)))),
                recipient: bytes32(uint256(uint160(address(composer)))),
                data: data
            })
        );
        composeMsg = abi.encodePacked(OFTMsgCodec.addressToBytes32(fraxtalHop), composeMsg);
        bytes memory message = OFTComposeMsgCodec.encode(0, 30_255, 1e18, composeMsg);

        vm.expectEmit(true, true, true, true);
        emit TestHopComposer.Composed(30_255, bytes32(uint256(uint160(address(0x123)))), oft, 1e18, data);

        vm.prank(address(endpoints[TEMPO_EID]));
        remoteHopTempo.lzCompose(oft, bytes32(0), message, address(0), "");

        assertEq(tempoOft.balanceOf(address(composer)), 1e18, "Composer should receive OFT tokens");
    }

    // ============ Quote Tests ============

    function test_OFT_QuoteTempo_LocalDestinationReturnsZero() public view {
        address oft = address(tempoOft);
        uint256 fee = remoteHopTempo.quoteTempo(oft, TEMPO_EID, bytes32(uint256(uint160(bob))), 1e18, 0, "");
        assertEq(fee, 0, "Local transfers should have zero fee");
    }

    function test_OFT_Quote_LocalDestination() public view {
        address oft = address(tempoOft);
        uint256 fee = remoteHopTempo.quote(oft, TEMPO_EID, bytes32(uint256(uint160(bob))), 1e18, 0, "");
        assertEq(fee, 0, "Local transfers should have zero fee");
    }

    // ============ RemoveDust Tests ============

    function test_OFT_RemoveDust() public view {
        address oft = address(tempoOft);
        uint256 amount = 1.123456789123456789e18;
        uint256 cleaned = remoteHopTempo.removeDust(oft, amount);
        assertTrue(cleaned <= amount, "Cleaned amount should be <= original");
    }
}
