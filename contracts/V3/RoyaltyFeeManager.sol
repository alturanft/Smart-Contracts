// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IERC165Upgradeable, IERC2981Upgradeable} from "@openzeppelin/contracts-upgradeable/interfaces/IERC2981Upgradeable.sol";

import {IRoyaltyFeeManager} from "./interfaces/IRoyaltyFeeManager.sol";

/**
 * @title RoyaltyFeeManager
 * @notice It handles the logic to check and transfer royalty fees (if any).
 */
contract RoyaltyFeeManager is IRoyaltyFeeManager, OwnableUpgradeable {
    // https://eips.ethereum.org/EIPS/eip-2981
    bytes4 public constant INTERFACE_ID_ERC2981 = 0x2a55205a;

    struct FeeInfo {
        address setter;
        address receiver;
        uint256 fee;
    }

    // Limit (if enforced for fee royalty in percentage (10,000 = 100%)
    uint256 public royaltyFeeLimit;

    mapping(address => FeeInfo) private _royaltyFeeInfoCollection;

    event NewRoyaltyFeeLimit(uint256 royaltyFeeLimit);
    event RoyaltyFeeUpdate(address indexed collection, address indexed setter, address indexed receiver, uint256 fee);

    /**
     * @notice initializer
     * @param _royaltyFeeLimit new royalty fee limit (500 = 5%, 1,000 = 10%)
     */
    function initialize(uint256 _royaltyFeeLimit) public initializer {
        __Ownable_init();

        require(_royaltyFeeLimit <= 5000, "Owner: Royalty fee limit too high");
        royaltyFeeLimit = _royaltyFeeLimit;
    }

    /**
     * @notice Update royalty info for collection
     * @param _royaltyFeeLimit new royalty fee limit (500 = 5%, 1,000 = 10%)
     */
    function updateRoyaltyFeeLimit(uint256 _royaltyFeeLimit) external override onlyOwner {
        require(_royaltyFeeLimit <= 5000, "Owner: Royalty fee limit too high");
        royaltyFeeLimit = _royaltyFeeLimit;

        emit NewRoyaltyFeeLimit(_royaltyFeeLimit);
    }

    /**
     * @notice Update royalty info for collection
     * @param collection address of the NFT contract
     * @param setter address that sets the receiver
     * @param receiver receiver for the royalty fee
     * @param fee fee (500 = 5%, 1,000 = 10%)
     */
    function updateRoyaltyInfoForCollection(
        address collection,
        address setter,
        address receiver,
        uint256 fee
    ) external override onlyOwner {
        require(fee <= royaltyFeeLimit, "Registry: Royalty fee too high");
        _royaltyFeeInfoCollection[collection] = FeeInfo({setter: setter, receiver: receiver, fee: fee});

        emit RoyaltyFeeUpdate(collection, setter, receiver, fee);
    }

    /**
     * @notice Calculate royalty info for a collection address and a sale gross amount
     * @param collection collection address
     * @param amount amount
     * @return receiver address and amount received by royalty recipient
     */
    function royaltyInfo(address collection, uint256 amount) public view override returns (address, uint256) {
        return (
            _royaltyFeeInfoCollection[collection].receiver,
            (amount * _royaltyFeeInfoCollection[collection].fee) / 10000
        );
    }

    /**
     * @notice View royalty info for a collection address
     * @param collection collection address
     */
    function royaltyFeeInfoCollection(address collection)
        external
        view
        override
        returns (
            address,
            address,
            uint256
        )
    {
        return (
            _royaltyFeeInfoCollection[collection].setter,
            _royaltyFeeInfoCollection[collection].receiver,
            _royaltyFeeInfoCollection[collection].fee
        );
    }

    /**
     * @notice Calculate royalty fee and get recipient
     * @param collection address of the NFT contract
     * @param tokenId tokenId
     * @param amount amount to transfer
     */
    function calculateRoyaltyFeeAndGetRecipient(
        address collection,
        uint256 tokenId,
        uint256 amount
    ) external view override returns (address, uint256) {
        // 1. Check if there is a royalty info in the system
        (address receiver, uint256 royaltyAmount) = royaltyInfo(collection, amount);

        // 2. If the receiver is address(0), fee is null, check if it supports the ERC2981 interface
        if ((receiver == address(0)) || (royaltyAmount == 0)) {
            if (IERC165Upgradeable(collection).supportsInterface(INTERFACE_ID_ERC2981)) {
                (receiver, royaltyAmount) = IERC2981Upgradeable(collection).royaltyInfo(tokenId, amount);
            }
        }
        return (receiver, royaltyAmount);
    }
}
