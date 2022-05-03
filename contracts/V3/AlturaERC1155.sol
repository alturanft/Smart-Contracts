// Altura ERC1155 token
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/interfaces/IERC2981Upgradeable.sol";
import "./interfaces/IAlturaERC1155.sol";

contract AlturaERC1155 is ERC1155Upgradeable, AccessControlEnumerableUpgradeable, IERC2981Upgradeable, IAlturaERC1155 {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes4 private constant _INTERFACE_ID_ERC2981 = 0x2a55205a;
    uint256 public constant PERCENTS_DIVIDER = 1000;
    uint256 public constant FEE_MAX_PERCENT = 300;

    address public owner;
    string public name;
    bool public isPublic;
    uint256 public items;

    event ItemAdded(uint256 id, uint256 maxSupply, uint256 supply);
    event ItemsAdded(uint256 from, uint256 count, uint256 supply);

    mapping(uint256 => address) private _creators;
    mapping(uint256 => uint256) private _royalties;
    mapping(uint256 => uint256) public totalSupply;
    mapping(uint256 => uint256) public circulatingSupply;

    /**
		Initialize from Swap contract
	 */
    function initialize(
        string memory _name,
        string memory _uri,
        address _creator,
        bool _public
    ) external override initializer {
        __ERC1155_init(_uri);
        __AccessControlEnumerable_init();

        __AlturaERC1155_init_unchained(_name, _creator, _public);
    }

    function __AlturaERC1155_init_unchained(
        string memory _name,
        address _creator,
        bool _public
    ) internal initializer {
        name = _name;
        owner = _creator;
        isPublic = _public;

        _setupRole(DEFAULT_ADMIN_ROLE, _creator);
        _setupRole(MINTER_ROLE, _creator);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC1155Upgradeable, AccessControlEnumerableUpgradeable, IERC165Upgradeable)
        returns (bool)
    {
        return type(IERC2981Upgradeable).interfaceId == interfaceId || super.supportsInterface(interfaceId);
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
    ) external override {
        require(hasRole(MINTER_ROLE, msg.sender) || isPublic, "Only minter can add item");
        require(maxSupply > 0, "Maximum supply can not be 0");
        require(supply <= maxSupply, "Supply can not be greater than Maximum supply");
        require(_fee < FEE_MAX_PERCENT, "Too big creator fee");

        items = items + 1;
        totalSupply[items] = maxSupply;
        circulatingSupply[items] = supply;

        _creators[items] = msg.sender;
        _royalties[items] = _fee;

        if (supply > 0) {
            _mint(msg.sender, items, supply, "");
        }

        emit ItemAdded(items, maxSupply, supply);
    }

    /**
     * Create Multiple Cards - Only Minters
     */
    function addItems(uint256 count, uint256 _fee) external override {
        require(hasRole(MINTER_ROLE, msg.sender) || isPublic, "!minter");
        require(count > 0, "!zero count");
        require(_fee < FEE_MAX_PERCENT, "too big fee");

        uint256 from = items + 1;
        for (uint256 i = 0; i < count; i++) {
            items = items + 1;
            totalSupply[items] = 1;
            circulatingSupply[items] = 1;
            _creators[items] = msg.sender;
            _royalties[items] = _fee;

            _mint(msg.sender, items, 1, "");
        }

        emit ItemsAdded(from, count, 1);
    }

    /**
     *	Mint - Only Minters or cretors
     */
    function mint(
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) public returns (bool) {
        require(hasRole(MINTER_ROLE, msg.sender) || creatorOf(id) == msg.sender, "!minter");
        require(circulatingSupply[id] + amount <= totalSupply[id], "Total supply reached.");

        circulatingSupply[id] = circulatingSupply[id] + amount;
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

    function royaltyInfo(uint256 _tokenId, uint256 _salePrice)
        external
        view
        override
        returns (address receiver, uint256 royaltyAmount)
    {
        return (creatorOf(_tokenId), ((_salePrice * royaltyOf(_tokenId)) / PERCENTS_DIVIDER));
    }

    modifier onlyOwner() {
        require(owner == _msgSender(), "!owner");
        _;
    }

    uint256[50] private __gap;
}
