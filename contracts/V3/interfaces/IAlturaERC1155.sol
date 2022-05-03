// Altura ERC1155 token
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IAlturaERC1155 {
    /**
		Initialize from Swap contract
	 */
    function initialize(
        string memory _name,
        string memory _uri,
        address _creator,
        bool _public
    ) external;

    /**
		Create Card - Only Minters
	 */
    function addItem(
        uint256 maxSupply,
        uint256 supply,
        uint256 _fee
    ) external;

    /**
     * Create Multiple Cards - Only Minters
     */
    function addItems(uint256 count, uint256 _fee) external;
}
