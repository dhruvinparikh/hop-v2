## Specification
### RemoteHop
**Purpose:** User wants to move [(s)frxUSD, (s)frxETH, FXS, FPI] from chain A to chain B via LZ.
1. User sends OFT to RemoteHop on Chain A
   - If `Chain B == Fraxtal`
        1. Chain A RemoteHop sends OFT to recipient on Fraxtal
   - If `Chain B != Fraxtal`
       1. Chain A RemoteHop sends OFT to Fraxtal Remotehop
        2. Fraxtal Remotehop sends OFT to recipient on chain B.

## How to use
### Interfaces
```Solidity
interface IERC20 {
    function approve(address spender, uint256 amount) external;
}
interface IOFT {
    function token() external view returns (address);
}

interface IRemoteHop {
        function quote(
        address _oft,
        uint32 _dstEid,
        bytes32 _recipient,
        uint256 _amountLD,
        uint128 _dstGas,
        bytes memory _data
    ) external view returns (uint256 fee);
    function sendOFT(
        address _oft,
        uint32 _dstEid,
        bytes32 _recipient,
        uint256 _amountLD,
        uint128 _dstGas,
        bytes memory _data
    ) external payable;
}
```

### RemoteHop
```Solidity
// Ethereum WFRAX => (Fraxtal) => Arbitrum WFRAX

// OFT address found @ https://docs.frax.com/protocol/crosschain/addresses
address remoteHop = 0xFd3B410b82a00B2651b42A13837204c5e3D92e27; // See deployed contracts below
address oft = 0x04ACaF8D2865c0714F79da09645C13FD2888977f; // WFRAX OFT
uint32 dstEid = 30110; // Arbitrum
bytes32 recipient = bytes32(uint256(uint160(0xb0E1650A9760e0f383174af042091fc544b8356f))); // example
uint256 amountLD = 1e18;
uint128 dstGas = 0;
bytes memory data = "";

// 1. Quote cost of send
uint256 fee = IRemoteHop(remoteHop).quote(oft, dstEid, recipient, amountLD, dstGas, data);

// 2. Approve OFT underlying token to be transferred to the remoteHop 
IERC20(IOFT(oft).token()).approve(remoteHop, amountLD);

// 3. Send the OFT to destination
IRemoteHop(remoteHop).sendOFT{value: fee}(oft, dstEid, recipient, amountLD, dstGas, data);
```

## Deployed Contracts
### HopV2 Mainnet
| Chain | `Hop` | `RemoteAdmin` |
| --- | --- | --- |
| Fraxtal | [`0xe8Cd13de17CeC6FCd9dD5E0a1465Da240f951536`](https://fraxscan.com/address/0xe8Cd13de17CeC6FCd9dD5E0a1465Da240f951536) | [`0xDC3369C18Ff9C077B803C98b6260a186aDE9A426`](https://fraxscan.com/address/0xDC3369C18Ff9C077B803C98b6260a186aDE9A426) |
| Arbitrum | [`0xf307Ad241E1035062Ed11F444740f108B8D036a6`](https://arbiscan.io/address/0xf307Ad241E1035062Ed11F444740f108B8D036a6) | [`0x03047fA366900b4cBf5E8F9FEEce97553f20370e`](https://arbiscan.io/address/0x03047fA366900b4cBf5E8F9FEEce97553f20370e) |
| Base | [`0x22beDD55A0D29Eb31e75C70F54fADa7Ca94339B9`](https://basescan.org/address/0x22beDD55A0D29Eb31e75C70F54fADa7Ca94339B9) | [`0xF333d66C7e47053b96bC153Bfdfaa05c8BEe7307`](https://basescan.org/address/0xF333d66C7e47053b96bC153Bfdfaa05c8BEe7307) |
| Ethereum | [`0xFd3B410b82a00B2651b42A13837204c5e3D92e27`](https://etherscan.io/address/0xFd3B410b82a00B2651b42A13837204c5e3D92e27) | [`0xa2db46c06e0B643A926ef60d1fEB744A7385a593`](https://etherscan.io/address/0xa2db46c06e0B643A926ef60d1fEB744A7385a593) |
