// Altura - NFT Auction contract
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/utils/ERC1155HolderUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

interface IWETH {
    function deposit() external payable;

    function withdraw(uint256 wad) external;

    function transfer(address to, uint256 value) external returns (bool);
}

interface IAlturaNFT {
    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes calldata data
    ) external;

    function mint(
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) external returns (bool);

    function balanceOf(address account, uint256 id) external view returns (uint256);

    function creatorOf(uint256 id) external view returns (address);

    function royaltyOf(uint256 id) external view returns (uint256);
}

contract AlturaNFTAuction is UUPSUpgradeable, ERC1155HolderUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 public constant PERCENTS_DIVIDER = 1000;
    uint256 public constant FEE_MAX_PERCENT = 500;
    uint256 public constant DEFAULT_FEE_PERCENT = 40;

    address public constant wethAddress = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c; // BSC Mainnet

    /* Auctions _id => price */
    struct Auction {
        address collectionId;
        uint256 tokenId;
        address creator;
        address owner;
        bool isUnlimitied;
        uint256 startTime;
        uint256 endTime;
        uint256 startPrice;
        address currency;
        uint256 royalty;
        bool active;
        bool finalized;
    }

    // Bid struct to hold bidder and amount
    struct Bid {
        address payable from;
        address currency;
        uint256 amount;
        bool active;
    }

    // auction id => Item mapping
    mapping(uint256 => Auction) public auctions;
    uint256 public currentAuctionId;

    // Mapping from auction index to user bids
    mapping(uint256 => Bid[]) public auctionBids;

    // Mapping from owner to a list of owned auctions
    mapping(address => uint256[]) public ownedAuctions;
    mapping(uint256 => mapping(address => uint256)) public auctionUserBids;

    uint256 public totalSold; /* Total NFT token amount sold */
    uint256 public totalEarning; /* Total Plutus Token */
    uint256 public totalSwapped; /* Total swap count */

    mapping(address => uint256) public swapFees; // swap fees (currency => fee) : percent divider = 1000
    address public feeAddress;

    /** Events */
    event AuctionCreated(uint256 id, Auction auction);
    event AuctionCancelled(uint256 id);
    event AuctionFinalized(uint256 id, uint256 bidIdx);

    event NewBid(address from, uint256 auctionId, uint256 price, address currency, uint256 bidIndex);
    event BidCancelled(uint256 auctionId, uint256 bidIndex);

    function initialize(address _fee) public initializer {
        __Ownable_init();
        __ERC1155Holder_init();
        __ReentrancyGuard_init();

        feeAddress = _fee;
        swapFees[address(0x0)] = 40;
        swapFees[0x8263CD1601FE73C066bf49cc09841f35348e3be0] = 25; //Alutra Token
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

    function createAuction(
        address _collectionId,
        uint256 _tokenId,
        address _currency,
        uint256 _startPrice,
        uint256 _startTime,
        uint256 _endTime,
        bool _isUnlimited
    ) public onlyTokenOwner(_collectionId, _tokenId) {
        currentAuctionId = currentAuctionId.add(1);
        Auction memory newAuction;
        newAuction.collectionId = _collectionId;
        newAuction.tokenId = _tokenId;
        newAuction.startPrice = _startPrice;
        newAuction.currency = _currency;
        newAuction.startTime = _startTime;
        newAuction.endTime = _endTime;
        newAuction.isUnlimitied = _isUnlimited;
        newAuction.owner = msg.sender;
        newAuction.active = true;
        newAuction.finalized = false;

        IAlturaNFT nft = IAlturaNFT(_collectionId);

        try nft.creatorOf(_tokenId) returns (address creator) {
            newAuction.creator = creator;
            newAuction.royalty = nft.royaltyOf(_tokenId);
        } catch (
            bytes memory /*lowLevelData*/
        ) {}

        auctions[currentAuctionId] = newAuction;
        ownedAuctions[msg.sender].push(currentAuctionId);

        nft.safeTransferFrom(msg.sender, address(this), _tokenId, 1, "create auction");

        emit AuctionCreated(currentAuctionId, newAuction);
    }

    /**
     * @dev Cancels an ongoing auction by the owner
     * @dev Deed is transfered back to the auction owner
     * @dev Bidder is refunded with the initial amount
     * @param _auctionId uint ID of the created auction
     */
    function cancelAuction(uint256 _auctionId) public onlyAuctionOwner(_auctionId) nonReentrant {
        Auction memory myAuction = auctions[_auctionId];
        uint256 bidsLength = auctionBids[_auctionId].length;

        require(msg.sender == owner() || bidsLength == 0, "bid already started");
        require(myAuction.active, "already cancelled");

        if (bidsLength > 0) {
            // refund latest bid
            Bid memory lastBid = auctionBids[_auctionId][bidsLength - 1];
            require(
                _safeTransferTokenOrBNB(lastBid.currency, lastBid.from, lastBid.amount),
                "refund to last bidder failed"
            );
        }
        // approve and transfer from this contract to auction owner
        IAlturaNFT(myAuction.collectionId).safeTransferFrom(
            address(this),
            myAuction.owner,
            myAuction.tokenId,
            1,
            "cancel auction"
        );

        auctions[_auctionId].active = false;
        auctions[_auctionId].finalized = true;

        emit AuctionCancelled(_auctionId);
    }

    /**
     * @dev Finalized an ended auction
     * @dev The auction should be ended, and there should be at least one bid
     * @dev On success Deed is transfered to bidder and auction owner gets the amount
     * @param _auctionId uint ID of the created auction
     */
    function finalizeAuction(uint256 _auctionId, uint256 _bidIdx) public {
        Auction storage myAuction = auctions[_auctionId];
        uint256 bidsLength = auctionBids[_auctionId].length;

        require(myAuction.active, "auction is not active");

        // 1. if auction not ended just revert
        require(
            msg.sender == owner() || myAuction.isUnlimitied || block.timestamp >= myAuction.endTime,
            "auction is not ended"
        );
        require(msg.sender == myAuction.owner || msg.sender == owner(), "only auction owner can finalize");

        // if there are no bids cancel
        if (bidsLength == 0) {
            cancelAuction(_auctionId);
        } else {
            uint256 lastBidIndex = 0;
            if (!myAuction.isUnlimitied) {
                lastBidIndex = bidsLength - 1;
                Bid memory lastBid = auctionBids[_auctionId][lastBidIndex];

                if (lastBid.amount > 0) {
                    _distributeBid(
                        myAuction.collectionId,
                        myAuction.tokenId,
                        lastBid.currency,
                        _msgSender(),
                        lastBid.amount
                    );
                    IAlturaNFT(myAuction.collectionId).safeTransferFrom(
                        address(this),
                        lastBid.from,
                        myAuction.tokenId,
                        1,
                        "finalize auction"
                    );
                }
            } else {
                require(_bidIdx < auctionBids[_auctionId].length, "invalid bid index");
                lastBidIndex = _bidIdx;
                Bid storage choosenBid = auctionBids[_auctionId][lastBidIndex];
                require(choosenBid.active && choosenBid.amount > 0, "selected bid is not active");

                _distributeBid(
                    myAuction.collectionId,
                    myAuction.tokenId,
                    choosenBid.currency,
                    _msgSender(),
                    choosenBid.amount
                );
                IAlturaNFT(myAuction.collectionId).safeTransferFrom(
                    address(this),
                    choosenBid.from,
                    myAuction.tokenId,
                    1,
                    "finalize auction"
                );

                choosenBid.active = false;
            }

            myAuction.active = false;
            myAuction.finalized = true;
            emit AuctionFinalized(_auctionId, lastBidIndex);
        }
    }

    function _distributeBid(
        address collection,
        uint256 tokenId,
        address paymentToken,
        address to,
        uint256 amount
    ) internal {
        address _creator = IAlturaNFT(collection).creatorOf(tokenId);
        uint256 royalties = IAlturaNFT(collection).royaltyOf(tokenId);
        // % commission cut
        uint256 swapFee = swapFees[paymentToken];
        if (swapFee == 0x0) {
            swapFee = DEFAULT_FEE_PERCENT;
        }

        uint256 _commissionValue = amount.mul(swapFee).div(PERCENTS_DIVIDER);
        uint256 _royalties = (amount.sub(_commissionValue)).mul(royalties).div(PERCENTS_DIVIDER);
        uint256 _sellerValue = amount.sub(_commissionValue).sub(_royalties);

        if (paymentToken == address(0x0)) {
            require(_safeTransferBNB(to, _sellerValue), "transfer to seller failed");
            if (_commissionValue > 0) _safeTransferBNB(feeAddress, _commissionValue);
            if (_royalties > 0) _safeTransferBNB(_creator, _royalties);
        } else {
            require(IERC20(paymentToken).transfer(to, _sellerValue), "transfer to seller failed");
            if (_commissionValue > 0) require(IERC20(paymentToken).transfer(feeAddress, _commissionValue));
            if (_royalties > 0) require(IERC20(paymentToken).transfer(_creator, _royalties));
        }
    }

    /**
     *  Bidder sends bid on an auction
     *  Auction should be active and not ended
     * @param _id uint256 ID of the created auction
     * @param amount uint256 amount of bid
     */
    function placeBid(
        uint256 _id,
        address currency,
        uint256 amount
    ) public payable {
        // owner can't bid on their auctions
        Auction storage myAuction = auctions[_id];
        require(myAuction.active, "Auction is not acitve");
        require(myAuction.owner != _msgSender(), "owner can not bid");
        require(myAuction.isUnlimitied || myAuction.currency == currency, "Only OpenBid supports custom Token Payment");

        // Check already placed bid
        uint256 bidIndex = auctionUserBids[_id][_msgSender()];
        if (bidIndex > 0) {
            if (auctionBids[_id][bidIndex - 1].active) {
                require(auctionBids[_id][bidIndex - 1].currency == currency, "not matched with old bid");
            }
        }

        uint256 tempAmount = myAuction.startPrice;
        // if auction is timelimited auction
        if (!myAuction.isUnlimitied) {
            require(block.timestamp < myAuction.endTime, "auction is over");
            require(block.timestamp >= myAuction.startTime, "auction is not started");

            // check if bid amount is bigger than lastBid
            if (getBidsLength(_id) > 0) {
                Bid memory lastBid = auctionBids[_id][getBidsLength(_id).sub(1)];
                tempAmount = lastBid.amount;

                if (lastBid.from != _msgSender()) {
                    require(amount > tempAmount, "TOO_SMALL_AMOUNT");

                    // refund last bid
                    require(
                        _safeTransferTokenOrBNB(lastBid.currency, lastBid.from, lastBid.amount),
                        "refund to last bidder failed"
                    );
                }
            } else {
                require(amount > tempAmount, "amount is smaller than start price");
            }
        }

        // transfer Payment Token to Auction contract from bidder
        if (myAuction.currency == address(0x0)) {
            require(amount == msg.value, "INVALID_BNB_VALUE");
        } else {
            IERC20(myAuction.currency).transferFrom(_msgSender(), address(this), amount);
        }

        // check already placed bid
        // timelimted auction => lasted bid
        if (bidIndex > 0 && auctionBids[_id][bidIndex - 1].active) {
            auctionBids[_id][bidIndex - 1].amount = auctionBids[_id][bidIndex - 1].amount.add(amount);
            emit NewBid(_msgSender(), _id, auctionBids[_id][bidIndex - 1].amount, currency, bidIndex - 1);
        } else {
            // add bid to Store
            Bid memory newBid;
            newBid.from = payable(_msgSender());
            newBid.currency = currency;
            newBid.amount = amount;
            newBid.active = true;

            auctionBids[_id].push(newBid);

            bidIndex = getBidsLength(_id).sub(1);
            auctionUserBids[_id][_msgSender()] = getBidsLength(_id);

            emit NewBid(_msgSender(), _id, amount, currency, bidIndex);
        }
    }

    /**
     *  Bidder withdraw Bid
     *  Bid should be active
     *  TimedAuction: Bidder can withdraw only after Auction ended and decided winning bid
     *  OpenBid:  Bidder can withdraw anytime
     * @param _id uint256 ID of the created auction
     */
    function cancelBid(uint256 _id) public nonReentrant {
        Auction storage myAuction = auctions[_id];
        require(myAuction.isUnlimitied, "only cancel free bid");

        uint256 bidIndex = auctionUserBids[_id][_msgSender()];
        require(bidIndex > 0, "invalid bid");

        Bid storage bid = auctionBids[_id][bidIndex - 1];

        require(bid.from == _msgSender(), "not owner");
        require(bid.active, "bid is not active");

        // If this auction is open bid, bidder can withdraw anytime
        IERC20(bid.currency).transfer(_msgSender(), bid.amount);

        // close Bid item
        bid.active = false;

        emit BidCancelled(_id, bidIndex);
    }

    function _safeTransferBNB(address to, uint256 value) internal returns (bool) {
        (bool success, ) = to.call{value: value}(new bytes(0));
        if (!success) {
            IWETH(wethAddress).deposit{value: value}();
            return IERC20(wethAddress).transfer(to, value);
        }
        return success;
    }

    function _safeTransferTokenOrBNB(
        address currency,
        address to,
        uint256 value
    ) internal returns (bool) {
        if (currency == address(0x0)) {
            (bool success, ) = to.call{value: value}(new bytes(0));
            if (!success) {
                IWETH(wethAddress).deposit{value: value}();
                return IERC20(wethAddress).transfer(to, value);
            }
            return success;
        } else {
            bool result = IERC20(currency).transfer(to, value);
            return result;
        }
    }

    /**
     * @dev Gets the length of auctions
     * @return uint representing the auction count
     */
    function getAuctionsLength() public view returns (uint256) {
        return currentAuctionId;
    }

    /**
     * @dev Gets the bid counts of a given auction
     * @param _auctionId uint ID of the auction
     */
    function getBidsLength(uint256 _auctionId) public view returns (uint256) {
        return auctionBids[_auctionId].length;
    }

    /**
     * @dev Gets an array of owned auctions
     * @param _owner address of the auction owner
     */
    function getOwnedAuctions(address _owner) public view returns (uint256[] memory) {
        uint256[] memory ownedAllAuctions = ownedAuctions[_owner];
        return ownedAllAuctions;
    }

    /**
     * @dev Gets an array of owned auctions
     * @param _auctionId uint of the auction owner
     * @return amount uint256, address of last bidder
     */
    function getLastBid(uint256 _auctionId) public view returns (uint256, address) {
        uint256 bidsLength = auctionBids[_auctionId].length;
        // if there are bids refund the last bid
        if (bidsLength >= 0) {
            Bid memory lastBid = auctionBids[_auctionId][bidsLength - 1];
            return (lastBid.amount, lastBid.from);
        }
        return (0, address(0));
    }

    /**
     * @dev Gets the total number of auctions owned by an address
     * @param _owner address of the owner
     * @return uint total number of auctions
     */
    function getOwnedAuctionsLength(address _owner) public view returns (uint256) {
        return ownedAuctions[_owner].length;
    }

    function isBNBAuction(uint256 _auctionId) public view returns (bool) {
        return auctions[_auctionId].currency == address(0x0);
    }

    receive() external payable {}

    modifier onlyAuctionOwner(uint256 _auctionId) {
        require(auctions[_auctionId].owner == msg.sender || msg.sender == owner(), "only auction owner");
        _;
    }

    modifier onlyTokenOwner(address _collectionId, uint256 _tokenId) {
        require(IAlturaNFT(_collectionId).balanceOf(msg.sender, _tokenId) > 0, "only token owner");
        _;
    }
}
