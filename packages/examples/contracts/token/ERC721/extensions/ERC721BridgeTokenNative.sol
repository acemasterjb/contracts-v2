// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./../../../interfaces/IERC721BridgeNative.sol";
import "../ERC721Bridge.sol";

abstract contract ERC721BridgeNative is ERC721Bridge {

    uint256 public immutable minTokenIndex;
    uint256 public immutable maxTokenIndex;

    constructor(
        string memory _name,
        string memory _symbol,
        uint256[] memory _supportedChainIds,
        address _messengerAddress,
        uint256 _minTokenIndex,
        uint256 _maxTokenIndex
    )
        ERC721Bridge(
            _name,
            _symbol,
            _supportedChainIds,
            _messengerAddress
        )
    {
        require(_minTokenIndex <= _maxTokenIndex, "ERC721BN: minTokenIndex must be less than maxTokenIndex");
        require(_maxTokenIndex <= type(uint96).max, "ERC721BN: maxTokenIndex must be less than 2**96 - 1");
        minTokenIndex = _minTokenIndex;
        maxTokenIndex = _maxTokenIndex;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IERC721BridgeNative).interfaceId || super.supportsInterface(interfaceId);
    }

    function isHub(uint256 tokenId) public view override returns (bool) {
        (, uint96 tokenIndex) = decodeTokenId(tokenId);
        bool isSpoke = minTokenIndex ==  maxTokenIndex;
        bool isTokenOnHub = (
            tokenIndex >= minTokenIndex &&
            tokenIndex <= maxTokenIndex
        );
        return !isSpoke && isTokenOnHub;
    }
}