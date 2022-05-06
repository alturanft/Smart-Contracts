// Altura - LootBox contract
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IAlturaLootboxV2 {
    function initialize(
        string memory _name,
        string memory _uri,
        address _collection,
        address _paymentCollection,
        uint256 _paymentTokenId,
        uint256 _price,
        address _owner
    ) external;

    /**
     * @dev Add tokens which have been minted, and your owned cards
     * @param tokenId. Card id you want to add.
     * @param amount. How many cards you want to add.
     */
    function addToken(uint256 tokenId, uint256 amount) external;

    function addTokenBatch(uint256[] memory tokenIds, uint256[] memory amounts) external;

    function addTokenBatchByMint(
        uint256 count,
        uint256 supply,
        uint256 fee
    ) external;

    /**
        Spin Lootbox with seed and times
     */
    function spin(uint256 userProvidedSeed, uint256 times) external;
}
