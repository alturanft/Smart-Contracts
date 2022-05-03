// Altura - NFT Factory contract
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "./interfaces/IAlturaERC1155.sol";

contract AlturaNFTFactoryV3 is Initializable, OwnableUpgradeable {
    address public targetAddress;
    address[] public collections;
    // collection address => creator address
    mapping(address => address) public collectionCreators;

    /** Events */
    event CollectionCreated(address collection_address, address owner, string name, string uri, bool isPublic);

    function initialize(address _target) public initializer {
        __Ownable_init();

        targetAddress = _target;
        createCollection("AlturaNFT", "https://api.alturanft.com/meta/alturanft/", true);
    }

    function createCollection(
        string memory _name,
        string memory _uri,
        bool bPublic
    ) public returns (address collection) {
        collection = _clone(targetAddress);
        IAlturaERC1155(collection).initialize(_name, _uri, msg.sender, bPublic);

        collections.push(collection);
        collectionCreators[collection] = msg.sender;

        emit CollectionCreated(collection, msg.sender, _name, _uri, bPublic);
    }

    function _clone(address target) internal returns (address) {
        return Clones.clone(target);
    }

    function setTarget(address _target) external onlyOwner {
        require(_target != address(0), "!zero address");

        targetAddress = _target;
    }

    receive() external payable {
        revert();
    }
}
