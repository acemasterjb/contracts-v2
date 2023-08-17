// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "../../ERC5164/MessageReceiver.sol";
import "../../ERC5164/IMessageDispatcher.sol";

/// @dev An example contract demonstrating cross-chain messaging with a ERC5164 messenger such as the Hop Core Messenger.
contract MultichainGreeter is MessageReceiver {
    address public hopMessenger;
    string public greeting;

    event GreetingSent(string newGreeting, uint256 toChainId, address to);
    event GreetingSet(string newGreeting, bytes32 messageId, uint256 fromChainId, address from);

    function setMessenger(address connector) external {
        require(hopMessenger == address(0), "Messenger already set");
        hopMessenger = connector;
    }

    // ✉️ Send a greeting to the paired cross-chain Greeter contract ✉️
    function sendGreeting(uint256 toChainId, address to, string memory newGreeting) external payable {
        // Get the encoded the cross-chain message
        bytes memory data = abi.encodeWithSignature(
            "setGreeting(string)",
            newGreeting
        );

        // Call the ERC-5164 method `dispatchMessage` on the messenger contract
        IMessageDispatcher(hopMessenger).dispatchMessage{value: msg.value}(
            toChainId,
            to,
            data
        );
    }

    // 📬 Receive a greeting from a cross-chain sender 📬
    function setGreeting(string memory newGreeting) external {

        // `_crossChainContext()` from the imported `MessageReceiver` contract returns the ERC-5164
        // message metadata used for validating the cross-chain sender and tracking the message.
        (bytes32 messageId, uint256 fromChainId, address from) = _crossChainContext();

        // 🔒 Example cross-chain sender validation 🔒
        // require(fromChainId == crossChainGreeterChainId, "Invalid crossChainGreeterChainId");
        // require(from == crossChainGreeter, "Invalid crossChainGreeter");

        emit GreetingSet(newGreeting, messageId, fromChainId, from);
        greeting = newGreeting;
    }
}
