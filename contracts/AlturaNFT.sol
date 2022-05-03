// Altura NFT token
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract AlturaNFT is ERC1155, AccessControl {
    using SafeMath for uint256;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    uint256 public constant PERCENTS_DIVIDER = 1000;
    uint256 public constant FEE_MAX_PERCENT = 300;

    string public name;
    bool public isPublic;
    uint256 public items;
    address public factory;
    address public owner;

    event ItemAdded(uint256 id, uint256 maxSupply, uint256 supply);
    event ItemsAdded(uint256 from, uint256 count, uint256 supply);

    mapping(uint256 => address) private _creators;
    mapping(uint256 => uint256) private _royalties;
    mapping(uint256 => uint256) public totalSupply;
    mapping(uint256 => uint256) public circulatingSupply;

    constructor() public ERC1155("") {
        factory = msg.sender;
    }

    /**
		Initialize from Swap contract
	 */
    function initialize(
        string memory _name,
        string memory _uri,
        address creator,
        bool bPublic
    ) external {
        require(msg.sender == factory, "Only for factory");
        _setURI(_uri);
        name = _name;
        owner = creator;
        isPublic = bPublic;

        _setupRole(DEFAULT_ADMIN_ROLE, owner);
        _setupRole(MINTER_ROLE, owner);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC1155, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    /**
		Change Collection URI
	 */
    function setURI(string memory newuri) public onlyOwner {
        _setURI(newuri);
    }

    /**
		Change Collection Name
	 */
    function setName(string memory newname) public onlyOwner {
        name = newname;
    }

    /**
		Create Card - Only Minters
	 */
    function addItem(
        uint256 maxSupply,
        uint256 supply,
        uint256 _fee
    ) public returns (uint256) {
        require(hasRole(MINTER_ROLE, msg.sender) || isPublic, "Only minter can add item");
        require(maxSupply > 0, "Maximum supply can not be 0");
        require(supply <= maxSupply, "Supply can not be greater than Maximum supply");
        require(_fee < FEE_MAX_PERCENT, "Too big creator fee");

        items = items.add(1);
        totalSupply[items] = maxSupply;
        circulatingSupply[items] = supply;

        _creators[items] = msg.sender;
        _royalties[items] = _fee;

        if (supply > 0) {
            _mint(msg.sender, items, supply, "");
        }

        emit ItemAdded(items, maxSupply, supply);
        return items;
    }

    /**
		Create Multiple Cards - Only Minters
	 */
    function addItems(uint256 count, uint256 _fee) public {
        require(hasRole(MINTER_ROLE, msg.sender) || isPublic, "Only minter can add item");
        require(count > 0, "Item cound can not be 0");
        require(_fee < FEE_MAX_PERCENT, "Too big creator fee");

        uint256 from = items.add(1);
        for (uint256 i = 0; i < count; i++) {
            items = items.add(1);
            totalSupply[items] = 1;
            circulatingSupply[items] = 1;
            _creators[items] = msg.sender;
            _royalties[items] = _fee;

            _mint(msg.sender, items, 1, "");
        }

        emit ItemsAdded(from, count, 1);
    }

    /**
		Mint - Only Minters or cretors
	 */
    function mint(
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) public returns (bool) {
        require(hasRole(MINTER_ROLE, msg.sender) || creatorOf(id) == msg.sender, "Only minter or creator can mint");
        require(circulatingSupply[id].add(amount) <= totalSupply[id], "Total supply reached.");

        circulatingSupply[id] = circulatingSupply[id].add(amount);
        _mint(to, id, amount, data);
        return true;
    }

    receive() external payable {
        revert();
    }

    function creatorOf(uint256 id) public view returns (address) {
        return _creators[id];
    }

    function royaltyOf(uint256 id) public view returns (uint256) {
        return _royalties[id];
    }

    modifier onlyOwner() {
        require(owner == _msgSender(), "caller is not the owner");
        _;
    }
}
