pragma solidity ^0.8.0;

struct HopMessage {
    uint32 srcEid;
    uint32 dstEid;
    uint128 dstGas;
    bytes32 sender;
    bytes32 recipient;
    bytes data;
}

struct RouteFee {
    /// @dev Admin-set fee for the Fraxtal onward leg, in Fraxtal native units (FRAX).
    ///      When non-zero, this overrides the source-chain quoteHop estimate.
    uint256 fraxtalOnwardFee;
    /// @dev Block timestamp when the route fee was last updated.
    uint64 lastUpdated;
    /// @dev Whether this route fee override is active.
    bool active;
}

interface IHopV2 {
    // Mutable funcs

    function sendOFT(address _oft, uint32 _dstEid, bytes32 _recipient, uint256 _amountLD) external payable;

    function sendOFT(
        address _oft,
        uint32 _dstEid,
        bytes32 _recipient,
        uint256 _amountLD,
        uint128 _dstGas,
        bytes memory _data
    ) external payable;

    // views

    function quote(
        address _oft,
        uint32 _dstEid,
        bytes32 _recipient,
        uint256 _amountLD,
        uint128 _dstGas,
        bytes memory _data
    ) external view returns (uint256 fee);

    function quoteHop(uint32 _dstEid, uint128 _dstGas, bytes memory _data) external view returns (uint256 fee);

    // Admin

    function pauseOn() external;
    function pauseOff() external;
    function setApprovedOft(address _oft, bool _isApproved) external;
    function setNumDVNs(uint32 _numDVNs) external;
    function setHopFee(uint256 _hopFee) external;
    function setExecutorOptions(uint32 eid, bytes memory _options) external;
    function setRemoteHop(uint32 _eid, address _remoteHop) external;
    function setRemoteHop(uint32 _eid, bytes32 _remoteHop) external;
    function recover(address _target, uint256 _value, bytes memory _data) external;
    function setMessageProcessed(address _oft, uint32 _srcEid, uint64 _nonce, bytes32 _composeFrom) external;

    /// @notice Set the admin-managed route fee override for a destination EID.
    /// @dev When active, this fee replaces the source-chain quoteHop estimate.
    ///      The fee is denominated in Fraxtal native units (FRAX) and is used
    ///      to fund the lzCompose value for the second leg.
    function setRouteFee(uint32 _dstEid, uint256 _fraxtalOnwardFee, bool _active) external;

    /// @notice Set the maximum native spend allowed per message on FraxtalHopV2.
    /// @dev Zero disables the cap. Non-zero prevents a single message from draining
    ///      the shared FraxtalHub balance if fee accounting is wrong.
    function setMaxSpendPerMessage(uint256 _max) external;

    // Storage views
    function localEid() external view returns (uint32);
    function endpoint() external view returns (address);
    function paused() external view returns (bool);
    function approvedOft(address oft) external view returns (bool isApproved);
    function messageProcessed(bytes32 message) external view returns (bool isProcessed);
    function remoteHop(uint32 eid) external view returns (bytes32 hop);
    function numDVNs() external view returns (uint32);
    function hopFee() external view returns (uint256);
    function executorOptions(uint32 eid) external view returns (bytes memory);
    function EXECUTOR() external view returns (address);
    function DVN() external view returns (address);
    function TREASURY() external view returns (address);
    function routeFees(uint32 dstEid) external view returns (RouteFee memory);
    function maxSpendPerMessage() external view returns (uint256);
}
