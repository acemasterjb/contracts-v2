//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./NativeTransporter.sol";

interface ISpokeNativeTransporter {
    function receiveCommitment(uint256 fromChainId, bytes32 commitment) external payable;
}

contract HubNativeTransporter is NativeTransporter {
    /* events */
    event CommitmentRelayed(
        uint256 indexed fromChainId,
        uint256 toChainId,
        bytes32 indexed commitment,
        uint256 commitmentFees,
        uint256 relayWindowStart,
        address indexed relayer
    );

    event CommitmentForwarded(
        bytes32 indexed commitment,
        uint256 indexed fromChainId,
        uint256 indexed toChainId
    );
    event ConfigUpdated();
    event FeePaid(address indexed to, uint256 amount, uint256 feesCollected);
    event ExcessFeesSkimmed(uint256 excessFees);

    /* constants */
    uint256 constant BASIS_POINTS = 10_000;

    /* config */
    mapping(address => uint256) private chainIdForSpoke;
    mapping(uint256 => address) private spokeForChainId;
    mapping(uint256 => uint256) private exitTimeForChainId;
    address public excessFeesRecipient;
    uint256 public targetBalance;
    uint256 public pendingFeeBatchSize;
    uint256 public relayWindow = 12 hours;
    uint256 public maxBundleFee;
    uint256 public maxBundleFeeBPS;

    mapping(uint256 => address) public feeTokens;

    /* state */
    uint256 public virtualBalance;

    constructor(
        address _excessFeesRecipient,
        uint256 _targetBalance,
        uint256 _maxBundleFee,
        uint256 _maxBundleFeeBPS
    ) {
        excessFeesRecipient = _excessFeesRecipient;
        targetBalance = _targetBalance;
        maxBundleFee = _maxBundleFee;
        maxBundleFeeBPS = _maxBundleFeeBPS;
    }

    receive() external payable {}

    function transportCommitment(uint256 toChainId, bytes32 commitment) external payable {
        address spokeConnector = getSpokeConnector(toChainId);
        ISpokeNativeTransporter spokeTransporter = ISpokeNativeTransporter(spokeConnector);
        
        emit CommitmentTransported(toChainId, commitment);

        uint256 fromChainId = getChainId();
        spokeTransporter.receiveCommitment{value: msg.value}(fromChainId, commitment); // Forward value for message fee
    }

    function receiveOrForwardCommitment(
        bytes32 commitment,
        uint256 commitmentFees,
        uint256 toChainId,
        uint256 commitTime
    )
        external
        payable
    {
        uint256 fromChainId = getSpokeChainId(msg.sender);

        if (toChainId == getChainId()) {
            _setProvenCommitment(fromChainId, commitment);
        } else {
            address spokeConnector = getSpokeConnector(toChainId);
            ISpokeNativeTransporter spokeTransporter = ISpokeNativeTransporter(spokeConnector);
            
            emit CommitmentForwarded(commitment, fromChainId, toChainId);
            // Forward value for cross-chain message fee
            spokeTransporter.receiveCommitment{value: msg.value}(fromChainId, commitment);
        }

        // Pay relayer
        uint256 relayWindowStart = commitTime + getSpokeExitTime(fromChainId);
        emit CommitmentProven(
            fromChainId,
            commitment
        );

        emit CommitmentRelayed(
            fromChainId,
            toChainId,
            commitment,
            commitmentFees,
            relayWindowStart,
            tx.origin
        );
        _payFee(tx.origin, fromChainId, relayWindowStart, commitmentFees);
    }

    function transfer(address to, uint256 amount) internal virtual {
        (bool success, ) = to.call{value: amount}("");
        if (!success) revert TransferFailed(to, amount);
    }

    function skimExcessFees() external onlyOwner {
        uint256 balance = getBalance();
        if (targetBalance > balance) revert PoolNotFull(balance, targetBalance);
        uint256 excessBalance = balance - targetBalance;

        virtualBalance -= excessBalance;

        emit ExcessFeesSkimmed(excessBalance);

        transfer(excessFeesRecipient, excessBalance);
    }

    /* setters */

    function setSpokeTransporter(
        uint256 chainId,
        address spoke,
        uint256 exitTime
    )
        external
        onlyOwner
    {
        if (chainId == 0) revert NoZeroChainId();
        if (spoke == address(0)) revert NoZeroAddress(); 
        if (exitTime == 0) revert NoZeroExitTime();

        chainIdForSpoke[spoke] = chainId;
        spokeForChainId[chainId] = spoke;
        exitTimeForChainId[chainId] = exitTime;
    }

    function setExcessFeeRecipient(address _excessFeesRecipient) external onlyOwner {
        if (_excessFeesRecipient == address(0)) revert NoZeroAddress();

        excessFeesRecipient = _excessFeesRecipient;
        emit ConfigUpdated();
    }

    function setTargetBalanceSize(uint256 _targetBalance) external onlyOwner {
        targetBalance = _targetBalance;

        emit ConfigUpdated();
    }

    // @notice When lowering pendingFeeBatchSize, the Spoke pendingFeeBatchSize should be lowered first and
    // all fees should be exited before lowering pendingFeeBatchSize on the Hub.
    // @notice When raising pendingFeeBatchSize, both the Hub and Spoke pendingFeeBatchSize can be set at the
    // same time.
    function setPendingFeeBatchSize(uint256 _pendingFeeBatchSize) external onlyOwner {
        uint256 balance = getBalance();
        uint256 pendingAmount = virtualBalance - balance; // ToDo: Handle balance greater than fee pool
        if (_pendingFeeBatchSize < pendingAmount) revert PendingFeeBatchSizeTooLow(_pendingFeeBatchSize);

        pendingFeeBatchSize = _pendingFeeBatchSize;

        emit ConfigUpdated();
    }

    function setRelayWindow(uint256 _relayWindow) external onlyOwner {
        if (_relayWindow == 0) revert NoZeroRelayWindow();
        relayWindow = _relayWindow;
        emit ConfigUpdated();
    }

    function setMaxBundleFee(uint256 _maxBundleFee) external onlyOwner {
        maxBundleFee = _maxBundleFee;
        emit ConfigUpdated();
    }

    function setMaxBundleFeeBPS(uint256 _maxBundleFeeBPS) external onlyOwner {
        maxBundleFeeBPS = _maxBundleFeeBPS;
        emit ConfigUpdated();
    }

    /* getters */

    function getSpokeConnector(uint256 chainId) public view returns (address) {
        address spoke = spokeForChainId[chainId];
        if (spoke == address(0)) {
            revert InvalidRoute(chainId);
        }
        return spoke;
    }

    function getSpokeChainId(address bridge) public view returns (uint256) {
        uint256 chainId = chainIdForSpoke[bridge];
        if (chainId == 0) {
            revert InvalidBridgeCaller(bridge);
        }
        return chainId;
    }

    function getSpokeExitTime(uint256 chainId) public view returns (uint256) {
        uint256 exitTime = exitTimeForChainId[chainId];
        if (exitTime == 0) {
            revert InvalidChainId(chainId);
        }
        return exitTime;
    }

    function getBalance() private view returns (uint256) {
        // ToDo: Handle ERC20
        return address(this).balance;
    }

    function getRelayReward(uint256 relayWindowStart, uint256 feesCollected) public view returns (uint256) {
        return (block.timestamp - relayWindowStart) * feesCollected / relayWindow;
    }

    /*
     * Internal functions
     */
    function _payFee(address to, uint256 fromChainId, uint256 relayWindowStart, uint256 feesCollected) internal {
        address feeToken = feeTokens[fromChainId];
        if (feeToken != address(0)) {
            // ToDo: Use explicit address for ETH
            revert(); // ToDO: Handle ERC20 fees
        }

        uint256 relayReward = 0;
        if (block.timestamp >= relayWindowStart) {
            relayReward = getRelayReward(relayWindowStart, feesCollected);
        } else {
            return;
        }

        uint256 maxFee = feesCollected * maxBundleFeeBPS / BASIS_POINTS;
        if (maxFee > maxBundleFee) maxFee = maxBundleFee;
        if (relayReward > maxFee) relayReward = maxFee;

        uint256 balance = getBalance();
        uint256 pendingAmount = virtualBalance + feesCollected - balance;
        if (pendingAmount > pendingFeeBatchSize) {
            revert PendingFeesTooHigh(pendingAmount, pendingFeeBatchSize);
        }

        virtualBalance = virtualBalance + feesCollected - relayReward;

        emit FeePaid(to, relayReward, feesCollected);

        transfer(to, relayReward);
    }
}
