// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";

import { OptionsBuilder } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oapp/libs/OptionsBuilder.sol";
import { SendParam, MessagingFee } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/interfaces/IOFT.sol";
import { MessagingReceipt } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { OFTReceipt } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import { OFTMsgCodec } from "@layerzerolabs/oft-evm/contracts/libs/OFTMsgCodec.sol";
import { OFTComposeMsgCodec } from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";
import { TestHelperOz5 } from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { RemoteHopV2Tempo } from "src/contracts/hop/RemoteHopV2Tempo.sol";
import { HopMessage } from "src/contracts/interfaces/IHopV2.sol";
import { IHopComposer } from "src/contracts/interfaces/IHopComposer.sol";

import { ITIP20 } from "tempo-std/interfaces/ITIP20.sol";
import { ITIP20Factory } from "tempo-std/interfaces/ITIP20Factory.sol";
import { ITIP20RolesAuth } from "tempo-std/interfaces/ITIP20RolesAuth.sol";
import { StdPrecompiles } from "tempo-std/StdPrecompiles.sol";
import { StdTokens } from "tempo-std/StdTokens.sol";

import { OFTMock } from "@layerzerolabs/oft-evm/test/mocks/OFTMock.sol";
import { OFTAdapter } from "@layerzerolabs/oft-evm/contracts/OFTAdapter.sol";
import { OFT } from "@layerzerolabs/oft-evm/contracts/OFT.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/// @notice Mock TIP20 OFT Adapter that uses mint/burn for cross-chain transfers
/// @dev Mimics FraxOFTMintableAdapterUpgradeableTIP20 behavior for testing
/// @dev Architecture: Tempo side uses this adapter wrapping TIP20, other chains use OFT
contract TIP20OFTAdapterMock is OFTAdapter {
    constructor(
        address _token,
        address _lzEndpoint,
        address _delegate
    ) OFTAdapter(_token, _lzEndpoint, _delegate) Ownable(_delegate) {}

    /// @dev Override _debit to burn tokens instead of locking them
    function _debit(
        address _from,
        uint256 _amountLD,
        uint256 _minAmountLD,
        uint32 _dstEid
    ) internal override returns (uint256 amountSentLD, uint256 amountReceivedLD) {
        (amountSentLD, amountReceivedLD) = _debitView(_amountLD, _minAmountLD, _dstEid);

        // Pull tokens from sender and burn them (TIP20 style)
        ITIP20(address(innerToken)).transferFrom(_from, address(this), amountSentLD);
        ITIP20(address(innerToken)).burn(amountSentLD);
    }

    /// @dev Override _credit to mint tokens instead of unlocking them
    function _credit(
        address _to,
        uint256 _amountLD,
        uint32 /*_srcEid*/
    ) internal override returns (uint256 amountReceivedLD) {
        // Mint tokens to recipient (TIP20 style)
        ITIP20(address(innerToken)).mint(_to, _amountLD);
        return _amountLD;
    }
}

/// @notice Mock OFT (full token, not adapter) that uses mint/burn for cross-chain transfers
/// @dev Mimics FraxOFTUpgradeableTempo behavior for testing
/// @dev Architecture: Tempo side uses this OFT (mint/burn), other chains use FraxOFTMintableAdapterUpgradeable
contract TempoOFTMock is OFT {
    constructor(
        string memory _name,
        string memory _symbol,
        address _lzEndpoint,
        address _delegate
    ) OFT(_name, _symbol, _lzEndpoint, _delegate) Ownable(_delegate) {}

    /// @dev Mint tokens (for testing)
    function mint(address _to, uint256 _amount) external {
        _mint(_to, _amount);
    }

    /// @dev Burn tokens (for testing)
    function burn(address _from, uint256 _amount) external {
        _burn(_from, _amount);
    }
}

/// @notice Test HopComposer for testing local transfers with compose
contract TestHopComposer is IHopComposer {
    event Composed(uint32 srcEid, bytes32 srcAddress, address oft, uint256 amount, bytes composeMsg);

    function hopCompose(
        uint32 _srcEid,
        bytes32 _srcAddress,
        address _oft,
        uint256 _amount,
        bytes memory _data
    ) external override {
        emit Composed(_srcEid, _srcAddress, _oft, _amount, _data);
    }
}

/// @notice Tempo test helpers for precompiles (precompiles are real in special foundry)
abstract contract TempoTestHelpers is Test {
    /// @dev Set user's gas token via TIP_FEE_MANAGER precompile
    function _setUserGasToken(address user, address token) internal {
        vm.prank(user);
        StdPrecompiles.TIP_FEE_MANAGER.setUserToken(token);
    }

    /// @dev Grant ISSUER_ROLE on a TIP20 token to an address
    function _grantIssuerRole(address token, address account) internal {
        bytes32 issuerRole = ITIP20(token).ISSUER_ROLE();
        ITIP20RolesAuth(token).grantRole(issuerRole, account);
    }

    /// @dev Grant PATH_USD ISSUER_ROLE to an address
    function _grantPathUsdIssuerRole(address account) internal {
        _grantIssuerRole(StdTokens.PATH_USD_ADDRESS, account);
    }

    /// @dev Create a TIP20 token via factory precompile with issuer role granted to caller
    function _createTIP20(string memory name, string memory symbol, bytes32 salt) internal returns (ITIP20 token) {
        token = ITIP20(
            ITIP20Factory(address(StdPrecompiles.TIP20_FACTORY)).createToken(
                name,
                symbol,
                "USD",
                ITIP20(StdTokens.PATH_USD_ADDRESS),
                address(this),
                salt
            )
        );
        // Grant ISSUER_ROLE to test contract for minting
        ITIP20RolesAuth(address(token)).grantRole(token.ISSUER_ROLE(), address(this));
    }

    /// @dev Create a TIP20 token with a DEX pair via precompile
    function _createTIP20WithDexPair(
        string memory name,
        string memory symbol,
        bytes32 salt
    ) internal returns (ITIP20 token) {
        token = _createTIP20(name, symbol, salt);
        StdPrecompiles.STABLECOIN_DEX.createPair(address(token));
    }

    /// @dev Add liquidity to DEX precompile by placing both bid and ask orders
    function _addDexLiquidity(address token, uint256 amount) internal {
        address liquidityProvider = address(0x1111);

        // Mint both PATH_USD and the token for the liquidity provider
        ITIP20(StdTokens.PATH_USD_ADDRESS).mint(liquidityProvider, amount * 2);
        ITIP20(token).mint(liquidityProvider, amount * 2);

        vm.startPrank(liquidityProvider);

        // Place bid order: buy token with PATH_USD (allows selling token for PATH_USD)
        ITIP20(StdTokens.PATH_USD_ADDRESS).approve(address(StdPrecompiles.STABLECOIN_DEX), amount * 2);
        StdPrecompiles.STABLECOIN_DEX.place(token, uint128(amount), true, 0);

        // Place ask order: sell token for PATH_USD (allows buying token with PATH_USD)
        ITIP20(token).approve(address(StdPrecompiles.STABLECOIN_DEX), amount * 2);
        StdPrecompiles.STABLECOIN_DEX.place(token, uint128(amount), false, 0);

        vm.stopPrank();
    }
}
