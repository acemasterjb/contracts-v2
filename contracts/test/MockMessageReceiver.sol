//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.2;
import "hardhat/console.sol";

interface IHopMessenger {
    function getCrossChainSender() external returns (address);
    function getCrossChainChainId() external returns (uint256);
}

contract MockMessageReceiver {
    IHopMessenger public messenger;

    uint256 public result;
    address public msgSender;
    address public xDomainSender;
    uint256 public xDomainChainId;

    constructor(IHopMessenger _messenger) {
        messenger = _messenger;
    }

    function setResult(uint256 _result) external payable {
        result = _result;
        msgSender = msg.sender;
        xDomainSender = messenger.getCrossChainSender();
        xDomainChainId = messenger.getCrossChainChainId();
    }
}
