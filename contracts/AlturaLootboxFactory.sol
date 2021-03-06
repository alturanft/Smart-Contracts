// Altura - LootBox Factory contract
// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.4;


import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "./AlturaLootbox.sol";

contract AlturaLootboxFactory is UUPSUpgradeable, OwnableUpgradeable {
    using SafeMath for uint256;
	
	/** Create Lootbox fee (BNB) */
	uint256 public creatingFee;
	address public feeAddress;

	address[] public boxes;
	// collection address => creator address
	mapping(address => address) public boxCreators;
	

	/** Events */
    event LootboxCreated(address box_address, address owner, string name, address paymentToken, uint256 paymentTokenId, uint256 price);
    event FeeUpdated(uint256 old_fee, uint256 new_fee);

	function initialize(address _feeAddress) public initializer {
		__Ownable_init();

		creatingFee = 0 ether;
		feeAddress = _feeAddress;
    }

	function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

	/** Create Lootbox */
	function createLootbox(string memory _name, 
		string memory _uri,
		address _paymentCollection,
		uint256 _paymentTokenId, 
		uint256 _price) external  payable {
		
		require(msg.value >= creatingFee, "insufficient fee");
		if(creatingFee > 0) payable(feeAddress).transfer(creatingFee);
		
		uint256 remain = uint256(msg.value).sub(creatingFee);
		if(remain > 0) payable(msg.sender).transfer(remain);

		bytes memory bytecode = type(AlturaLootbox).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(_name, _paymentCollection, block.timestamp));
        address lootbox;
		assembly {
            lootbox := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        AlturaLootbox(lootbox).initialize(_name, _uri, _paymentCollection, _paymentTokenId, _price, msg.sender);
		boxes.push(lootbox);
		boxCreators[lootbox] = msg.sender;

		emit LootboxCreated(lootbox, msg.sender, _name, _paymentCollection, _paymentTokenId, _price);
	}


	/** Update Creating fee */
	function updateCreatingFee(uint256 _fee) public onlyOwner {
        uint256 oldFee = creatingFee;
		creatingFee = _fee;
		emit FeeUpdated(oldFee, _fee);
    }

	function updateFeeAddress(address _feeAddress) public onlyOwner {
        feeAddress = _feeAddress;
    }

	/** Withdraw BNB to admin address */
	function withdrawBNB() public onlyOwner {
		uint balance = address(this).balance;
		require(balance > 0, "insufficient balance");
		payable(msg.sender).transfer(balance);
	}

	receive() external payable {}
}