// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/IERC165Upgradeable.sol";
import {IERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/interfaces/IERC721Upgradeable.sol";
import {IERC1155Upgradeable} from "@openzeppelin/contracts-upgradeable/interfaces/IERC1155Upgradeable.sol";

import {ITransferManagerNFT} from "./interfaces/ITransferManagerNFT.sol";

/**
 * @title TransferManagerNFT
 * @notice It selects the NFT transfer manager based on a collection address.
 */
contract TransferManagerNFT is ITransferManagerNFT, OwnableUpgradeable {
    // ERC721 interfaceID
    bytes4 public constant INTERFACE_ID_ERC721 = 0x80ac58cd;
    // ERC1155 interfaceID
    bytes4 public constant INTERFACE_ID_ERC1155 = 0xd9b67a26;

    // Map collection address to transfer manager address
    mapping(address => address) public transferManagerSelectorForCollection;

    event CollectionTransferManagerAdded(address indexed collection, address indexed transferManager);
    event CollectionTransferManagerRemoved(address indexed collection);

    /**
     * @notice initializer
     */
    function initialize() public initializer {
        __Ownable_init();
    }

    /**
     * @notice Add a transfer manager for a collection
     * @param collection collection address to add specific transfer rule
     * @dev It is meant to be used for exceptions only (e.g., CryptoKitties)
     */
    function addCollectionTransferManager(address collection, address transferManager) external onlyOwner {
        require(collection != address(0), "Owner: Collection cannot be null address");
        require(transferManager != address(0), "Owner: TransferManager cannot be null address");

        transferManagerSelectorForCollection[collection] = transferManager;

        emit CollectionTransferManagerAdded(collection, transferManager);
    }

    /**
     * @notice Remove a transfer manager for a collection
     * @param collection collection address to remove exception
     */
    function removeCollectionTransferManager(address collection) external onlyOwner {
        require(
            transferManagerSelectorForCollection[collection] != address(0),
            "Owner: Collection has no transfer manager"
        );

        // Set it to the address(0)
        transferManagerSelectorForCollection[collection] = address(0);

        emit CollectionTransferManagerRemoved(collection);
    }

    /**
     * @notice Transfer ERC1155 token(s)
     * @param collection address of the collection
     * @param from address of the sender
     * @param to address of the recipient
     * @param tokenId tokenId
     * @param amount amount of tokens (1 and more for ERC1155)
     */
    function transferNonFungibleToken(
        address collection,
        address from,
        address to,
        uint256 tokenId,
        uint256 amount
    ) external override {
        // Assign transfer manager (if any)
        address transferManager = transferManagerSelectorForCollection[collection];

        if (transferManager == address(0)) {
            if (IERC165Upgradeable(collection).supportsInterface(INTERFACE_ID_ERC721)) {
                IERC721Upgradeable(collection).safeTransferFrom(from, to, tokenId);
            } else if (IERC165Upgradeable(collection).supportsInterface(INTERFACE_ID_ERC1155)) {
                IERC1155Upgradeable(collection).safeTransferFrom(from, to, tokenId, amount, "");
            }
        } else {
            ITransferManagerNFT(transferManager).transferNonFungibleToken(collection, from, to, tokenId, amount);
        }
    }
}
