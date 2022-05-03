// Altura - NFT Swap contract
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/utils/ERC1155HolderUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

import "./interfaces/IAlturaNFTV2.sol";

interface IWETH {
    function deposit() external payable;

    function withdraw(uint256 wad) external;

    function transfer(address to, uint256 value) external returns (bool);
}

contract AlturaNFTFactoryV2 is
    UUPSUpgradeable,
    ERC1155HolderUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 public constant PERCENTS_DIVIDER = 1000;
    uint256 public constant FEE_MAX_PERCENT = 300;
    uint256 public constant DEFAULT_FEE_PERCENT = 40;

    //address public constant wethAddress = 0x094616F0BdFB0b526bD735Bf66Eca0Ad254ca81F; // BSC Testnet
    address public constant wethAddress = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c; // BSC Mainnet

    /* Pairs to swap NFT _id => price */
    struct Item {
        uint256 item_id;
        address collection;
        uint256 token_id;
        address creator;
        address owner;
        uint256 balance;
        address currency;
        uint256 price;
        uint256 royalty;
        uint256 totalSold;
        bool bValid;
    }

    address[] public collections;
    // collection address => creator address
    mapping(address => address) public collectionCreators;
    // token id => Item mapping
    mapping(uint256 => Item) public items;
    uint256 public currentItemId;

    uint256 public totalSold; /* Total NFT token amount sold */
    uint256 public totalEarning; /* Total Plutus Token */
    uint256 public totalSwapped; /* Total swap count */

    mapping(address => uint256) public swapFees; // swap fees (currency => fee) : percent divider = 1000
    address public feeAddress;

    EnumerableSet.AddressSet private _supportedTokens; //payment token (ERC20)

    address public targetAddress;

    struct Offer {
        uint256 item_id;
        address collection;
        uint256 token_id;
        address owner;
        uint256 amount;
        address currency;
        uint256 price;
        uint256 matched;
        uint256 expire;
        bool bValid;
    }
    uint256 public currentOfferId;
    // offer id => offer
    mapping(uint256 => Offer) public offers;
    mapping(uint256 => uint256[]) private _offersByItem; // item id => offer ids

    /** Events */
    event CollectionCreated(address collection_address, address owner, string name, string uri, bool isPublic);
    event ItemListed(
        uint256 id,
        address collection,
        uint256 token_id,
        uint256 amount,
        uint256 price,
        address currency,
        address creator,
        address owner,
        uint256 royalty
    );
    event ItemDelisted(uint256 id, address collection, uint256 token_id);
    event ItemPriceUpdated(uint256 id, address collection, uint256 token_id, uint256 price, address currency);
    event ItemAdded(uint256 id, uint256 amount, uint256 balance);
    event ItemRemoved(uint256 id, uint256 amount, uint256 balance);

    event Swapped(address buyer, address seller, uint256 id, address collection, uint256 token_id, uint256 amount);

    event OfferCreated(
        uint256 id,
        uint256 item_id,
        address collection,
        uint256 token_id,
        uint256 amount,
        uint256 price,
        address currency,
        uint256 expire,
        address creator
    );

    event OfferMatched(
        uint256 id,
        uint256 amount,
        uint256 price,
        address currency,
        uint256 matched,
        address buyer,
        address seller
    );

    event OfferCancelled(uint256 id, uint256 amount);

    function initialize(address _fee) public initializer {
        __Ownable_init();
        __ERC1155Holder_init();
        __ReentrancyGuard_init();

        feeAddress = _fee;
        swapFees[address(0x0)] = 40;
        swapFees[0x8263CD1601FE73C066bf49cc09841f35348e3be0] = 25; //Alutra Token

        createCollection("AlturaNFT", "https://api.alturanft.com/meta/alturanft/", true);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function setFeeAddress(address _address) external onlyOwner {
        require(_address != address(0x0), "invalid address");
        feeAddress = _address;
    }

    function setSwapFeePercent(address currency, uint256 _percent) external onlyOwner {
        require(_percent < FEE_MAX_PERCENT, "too big swap fee");
        swapFees[currency] = _percent;
    }

    function setTarget(address _target) external onlyOwner {
        require(_target != address(0), "!zero address");

        targetAddress = _target;
    }

    function createCollection(
        string memory _name,
        string memory _uri,
        bool bPublic
    ) public returns (address collection) {
        collection = Clones.clone(targetAddress);
        IAlturaNFTV2(collection).initialize(_name, _uri, msg.sender, address(this), bPublic);

        collections.push(collection);
        collectionCreators[collection] = msg.sender;

        emit CollectionCreated(collection, msg.sender, _name, _uri, bPublic);
    }

    function list(
        address _collection,
        uint256 _token_id,
        uint256 _amount,
        uint256 _price,
        address _currency,
        bool _bMint
    ) public {
        require(_price > 0, "invalid price");
        require(_amount > 0, "invalid amount");

        IAlturaNFTV2 nft = IAlturaNFTV2(_collection);
        if (_bMint) {
            require(nft.mint(address(this), _token_id, _amount, "Mint by AluturaNFT"), "mint failed");
        } else {
            nft.safeTransferFrom(msg.sender, address(this), _token_id, _amount, "List");
        }

        currentItemId = currentItemId.add(1);
        items[currentItemId].item_id = currentItemId;
        items[currentItemId].collection = _collection;
        items[currentItemId].token_id = _token_id;
        items[currentItemId].owner = msg.sender;
        items[currentItemId].balance = _amount;
        items[currentItemId].price = _price;
        items[currentItemId].currency = _currency;
        items[currentItemId].bValid = true;

        try nft.creatorOf(_token_id) returns (address creator) {
            items[currentItemId].creator = creator;
            items[currentItemId].royalty = nft.royaltyOf(_token_id);
        } catch (
            bytes memory /*lowLevelData*/
        ) {}

        emit ItemListed(
            currentItemId,
            _collection,
            _token_id,
            _amount,
            _price,
            _currency,
            items[currentItemId].creator,
            msg.sender,
            items[currentItemId].royalty
        );
    }

    function delist(uint256 _id) external {
        require(items[_id].bValid, "invalid Item id");
        require(items[_id].owner == msg.sender || msg.sender == owner(), "only owner can delist");

        IAlturaNFTV2(items[_id].collection).safeTransferFrom(
            address(this),
            items[_id].owner,
            items[_id].token_id,
            items[_id].balance,
            "delist from Altura Marketplace"
        );
        items[_id].balance = 0;
        items[_id].bValid = false;

        emit ItemDelisted(_id, items[_id].collection, items[_id].token_id);
    }

    function addItems(uint256 _id, uint256 _amount) external {
        require(items[_id].bValid, "invalid Item id");
        require(items[_id].owner == msg.sender, "only owner can add items");

        IAlturaNFTV2(items[_id].collection).safeTransferFrom(
            msg.sender,
            address(this),
            items[_id].token_id,
            _amount,
            "add items to Altura Marketplace"
        );
        items[_id].balance = items[_id].balance.add(_amount);

        emit ItemAdded(_id, _amount, items[_id].balance);
    }

    function removeItems(uint256 _id, uint256 _amount) external {
        require(items[_id].bValid, "invalid Item id");
        require(items[_id].owner == msg.sender, "only owner can remove items");

        IAlturaNFTV2(items[_id].collection).safeTransferFrom(
            address(this),
            msg.sender,
            items[_id].token_id,
            _amount,
            "remove items from Altura Marketplace"
        );
        items[_id].balance = items[_id].balance.sub(_amount, "insufficient balance of item");

        emit ItemRemoved(_id, _amount, items[_id].balance);
    }

    function updatePrice(
        uint256 _id,
        address _currency,
        uint256 _price
    ) external {
        require(_price > 0, "invalid new price");
        require(items[_id].bValid, "invalid Item id");
        require(items[_id].owner == msg.sender || msg.sender == owner(), "only owner can update price");

        items[_id].price = _price;
        items[_id].currency = _currency;

        emit ItemPriceUpdated(_id, items[_id].collection, items[_id].token_id, _price, _currency);
    }

    function buy(uint256 _id, uint256 _amount) external payable nonReentrant {
        require(items[_id].bValid, "invalid Item id");
        require(items[_id].balance >= _amount, "insufficient NFT balance");
        require(items[_id].currency != address(0x0) || items[_id].price.mul(_amount) == msg.value, "Invalid amount");

        Item memory item = items[_id];
        uint256 swapFee = swapFees[item.currency];
        if (swapFee == 0x0) {
            swapFee = DEFAULT_FEE_PERCENT;
        }
        uint256 plutusAmount = item.price.mul(_amount);
        uint256 ownerPercent = PERCENTS_DIVIDER.sub(swapFee).sub(item.royalty);

        // transfer Plutus token to admin
        if (item.currency == address(0x0)) {
            if (swapFee > 0) {
                require(
                    _safeTransferBNB(feeAddress, plutusAmount.mul(swapFee).div(PERCENTS_DIVIDER)),
                    "failed to transfer admin fee"
                );
            }
            // transfer Plutus token to creator
            if (item.royalty > 0) {
                require(
                    _safeTransferBNB(item.creator, plutusAmount.mul(item.royalty).div(PERCENTS_DIVIDER)),
                    "failed to transfer creator fee"
                );
            }
            // transfer Plutus token to owner
            require(
                _safeTransferBNB(item.owner, plutusAmount.mul(ownerPercent).div(PERCENTS_DIVIDER)),
                "failed to transfer to owner"
            );
        } else {
            if (swapFee > 0) {
                require(
                    IERC20(item.currency).transferFrom(
                        msg.sender,
                        feeAddress,
                        plutusAmount.mul(swapFee).div(PERCENTS_DIVIDER)
                    ),
                    "failed to transfer admin fee"
                );
            }
            // transfer Plutus token to creator
            if (item.royalty > 0) {
                require(
                    IERC20(item.currency).transferFrom(
                        msg.sender,
                        item.creator,
                        plutusAmount.mul(item.royalty).div(PERCENTS_DIVIDER)
                    ),
                    "failed to transfer creator fee"
                );
            }
            // transfer Plutus token to owner
            require(
                IERC20(item.currency).transferFrom(
                    msg.sender,
                    item.owner,
                    plutusAmount.mul(ownerPercent).div(PERCENTS_DIVIDER)
                ),
                "failed to transfer to owner"
            );
        }

        // transfer NFT token to buyer
        IAlturaNFTV2(items[_id].collection).safeTransferFrom(
            address(this),
            msg.sender,
            item.token_id,
            _amount,
            "buy from Altura Marketplace"
        );

        items[_id].balance = items[_id].balance.sub(_amount);
        items[_id].totalSold = items[_id].totalSold.add(_amount);

        totalSold = totalSold.add(_amount);
        totalEarning = totalEarning.add(plutusAmount);
        totalSwapped = totalSwapped.add(1);

        emit Swapped(msg.sender, item.owner, _id, items[_id].collection, items[_id].token_id, _amount);
    }

    function makeOffer(
        address _collection,
        uint256 _token_id,
        uint256 _amount,
        address _currency,
        uint256 _price,
        uint256 _expire
    ) external {
        require(_price > 0, "invalid price");
        require(_expire > block.timestamp, "invalid expire");
        require(_currency != address(0x0), "not allow native asset");
        require(
            _price.mul(_amount) <= IERC20(_currency).balanceOf(msg.sender) &&
                _price.mul(_amount) <= IERC20(_currency).allowance(msg.sender, address(this)),
            "insufficient balance or allowance"
        );

        currentOfferId = currentOfferId.add(1);
        offers[currentOfferId].collection = _collection;
        offers[currentOfferId].token_id = _token_id;
        offers[currentOfferId].owner = msg.sender;
        offers[currentOfferId].amount = _amount;
        offers[currentOfferId].currency = _currency;
        offers[currentOfferId].price = _price;
        offers[currentOfferId].matched = 0;
        offers[currentOfferId].expire = _expire;
        offers[currentOfferId].bValid = true;

        emit OfferCreated(currentOfferId, 0, _collection, _token_id, _amount, _price, _currency, _expire, msg.sender);
    }

    function acceptOffer(
        uint256 _offerId,
        uint256 _itemId,
        uint256 _amount
    ) external payable nonReentrant {
        Offer memory offer = offers[_offerId];
        require(offer.bValid, "invalid Offer id");
        require(offer.owner != msg.sender, "offer owner can't accept offer");
        require(offer.expire > block.timestamp, "offer expired");
        require(offer.amount.sub(offer.matched) >= _amount, "insufficient offer amount");

        Item memory item = items[_itemId];
        require(item.bValid, "invalid Item id");
        require(item.owner == msg.sender, "item owner can accept offer");
        require(item.balance >= _amount, "insufficient NFT balance");

        uint256 swapFee = swapFees[offer.currency];
        if (swapFee == 0x0) {
            swapFee = DEFAULT_FEE_PERCENT;
        }
        uint256 plutusAmount = offer.price.mul(_amount);
        uint256 ownerPercent = PERCENTS_DIVIDER.sub(swapFee).sub(item.royalty);

        if (swapFee > 0) {
            require(
                IERC20(offer.currency).transferFrom(
                    offer.owner,
                    feeAddress,
                    plutusAmount.mul(swapFee).div(PERCENTS_DIVIDER)
                ),
                "failed to transfer admin fee"
            );
        }
        // transfer Plutus token to creator
        if (item.royalty > 0) {
            require(
                IERC20(offer.currency).transferFrom(
                    offer.owner,
                    item.creator,
                    plutusAmount.mul(item.royalty).div(PERCENTS_DIVIDER)
                ),
                "failed to transfer creator fee"
            );
        }
        // transfer Plutus token to owner
        require(
            IERC20(offer.currency).transferFrom(
                offer.owner,
                item.owner,
                plutusAmount.mul(ownerPercent).div(PERCENTS_DIVIDER)
            ),
            "failed to transfer to owner"
        );

        // transfer NFT token to buyer
        IAlturaNFTV2(offer.collection).safeTransferFrom(
            address(this),
            offer.owner,
            offer.token_id,
            _amount,
            "buy from Altura"
        );

        items[_itemId].balance = items[_itemId].balance.sub(_amount);
        items[_itemId].totalSold = items[_itemId].totalSold.add(_amount);

        offers[_offerId].matched = offers[_offerId].matched.add(_amount);
        offers[_offerId].bValid = offers[_offerId].matched < offers[_offerId].amount;

        totalSold = totalSold.add(_amount);
        totalEarning = totalEarning.add(plutusAmount);
        totalSwapped = totalSwapped.add(1);

        emit Swapped(offer.owner, item.owner, _itemId, offer.collection, offer.token_id, _amount);
        emit OfferMatched(
            _offerId,
            _amount,
            offer.price,
            offer.currency,
            offers[_offerId].matched,
            offer.owner,
            item.owner
        );
    }

    function cancelOffer(uint256 _id, uint256 _amount) external {
        Offer memory offer = offers[_id];
        require(offer.bValid, "invalid Offer id");
        require(offer.owner == msg.sender, "owner can cancel offer");
        require(_amount > 0 && offer.amount >= offer.matched + _amount, "invalid amount");

        uint256 remaining = offer.amount.sub(offer.matched).sub(_amount);
        offers[_id].matched = offers[_id].matched.add(_amount);
        if (remaining == 0) {
            offers[_id].bValid = false;
        }

        emit OfferCancelled(_id, _amount);
    }

    function _safeTransferBNB(address to, uint256 value) internal returns (bool) {
        (bool success, ) = to.call{value: value}(new bytes(0));
        if (!success) {
            IWETH(wethAddress).deposit{value: value}();
            return IERC20(wethAddress).transfer(to, value);
        }
        return success;
    }

    receive() external payable {}

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __gap;
}
