// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "../utils/Ownable.sol";
import "./TLDStorage.sol";

/**
 * @title TLDAuctionModule
 * @notice Handles TLD auctions for expired domains
 * @dev Separate module to reduce main contract size
 */
contract TLDAuctionModule is Ownable {
    struct TLDAuction {
        uint256 startTime;
        uint256 endTime;
        uint256 startingPrice;
        uint256 currentBid;
        address currentBidder;
        bool settled;
    }

    // Auction configuration
    uint256 public constant AUCTION_DURATION = 7 days;
    uint256 public constant MIN_BID_INCREMENT = 0.05 ether;
    uint256 public constant AUCTION_EXTENSION = 10 minutes;

    // State
    mapping(uint256 => TLDAuction) public auctions;
    mapping(address => uint256) public pendingReturns;

    TLDStorage public immutable storage_;
    address public factory;

    // Events
    event AuctionStarted(
        uint256 indexed tokenId,
        uint256 startTime,
        uint256 endTime,
        uint256 startingPrice
    );

    event BidPlaced(
        uint256 indexed tokenId,
        address indexed bidder,
        uint256 amount
    );

    event AuctionSettled(
        uint256 indexed tokenId,
        address indexed winner,
        uint256 finalPrice
    );

    event AuctionCancelled(uint256 indexed tokenId);

    modifier onlyFactory() {
        require(msg.sender == factory, "Only factory");
        _;
    }

    constructor(address _storage) {
        storage_ = TLDStorage(_storage);
    }

    function setFactory(address _factory) external onlyOwner {
        factory = _factory;
    }

    /**
     * @notice Start an auction for an expired TLD
     */
    function startAuction(
        uint256 tokenId,
        uint256 startingPrice
    ) external onlyFactory returns (bool) {
        require(auctions[tokenId].startTime == 0, "Auction exists");

        TLD memory tld = storage_.getTLD(tokenId);
        require(!tld.isActive, "TLD is active");

        auctions[tokenId] = TLDAuction({
            startTime: block.timestamp,
            endTime: block.timestamp + AUCTION_DURATION,
            startingPrice: startingPrice,
            currentBid: 0,
            currentBidder: address(0),
            settled: false
        });

        emit AuctionStarted(
            tokenId,
            block.timestamp,
            block.timestamp + AUCTION_DURATION,
            startingPrice
        );
        return true;
    }

    /**
     * @notice Place a bid on an ongoing auction
     */
    function bid(uint256 tokenId) external payable {
        TLDAuction storage auction = auctions[tokenId];

        require(auction.startTime > 0, "No auction");
        require(block.timestamp < auction.endTime, "Auction ended");
        require(!auction.settled, "Already settled");

        uint256 minBid = auction.currentBid > 0
            ? auction.currentBid + MIN_BID_INCREMENT
            : auction.startingPrice;

        require(msg.value >= minBid, "Bid too low");

        // Return previous bid
        if (auction.currentBidder != address(0)) {
            pendingReturns[auction.currentBidder] += auction.currentBid;
        }

        auction.currentBid = msg.value;
        auction.currentBidder = msg.sender;

        // Extend auction if bid is near the end
        if (auction.endTime - block.timestamp < AUCTION_EXTENSION) {
            auction.endTime = block.timestamp + AUCTION_EXTENSION;
        }

        emit BidPlaced(tokenId, msg.sender, msg.value);
    }

    /**
     * @notice Settle a completed auction
     */
    function settleAuction(
        uint256 tokenId
    ) external returns (address winner, uint256 price) {
        TLDAuction storage auction = auctions[tokenId];

        require(auction.startTime > 0, "No auction");
        require(block.timestamp >= auction.endTime, "Auction ongoing");
        require(!auction.settled, "Already settled");

        auction.settled = true;
        winner = auction.currentBidder;
        price = auction.currentBid;

        if (winner != address(0)) {
            emit AuctionSettled(tokenId, winner, price);
        } else {
            emit AuctionCancelled(tokenId);
        }

        return (winner, price);
    }

    /**
     * @notice Withdraw pending returns from outbid auctions
     */
    function withdraw() external {
        uint256 amount = pendingReturns[msg.sender];
        require(amount > 0, "Nothing to withdraw");

        pendingReturns[msg.sender] = 0;

        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Transfer failed");
    }

    /**
     * @notice Cancel an auction (owner only)
     */
    function cancelAuction(uint256 tokenId) external onlyOwner {
        TLDAuction storage auction = auctions[tokenId];
        require(!auction.settled, "Already settled");

        if (auction.currentBidder != address(0)) {
            pendingReturns[auction.currentBidder] += auction.currentBid;
        }

        auction.settled = true;
        emit AuctionCancelled(tokenId);
    }

    /**
     * @notice Check if an auction is active
     */
    function isAuctionActive(uint256 tokenId) external view returns (bool) {
        TLDAuction memory auction = auctions[tokenId];
        return
            auction.startTime > 0 &&
            block.timestamp < auction.endTime &&
            !auction.settled;
    }

    /**
     * @notice Get auction details
     */
    function getAuction(
        uint256 tokenId
    ) external view returns (TLDAuction memory) {
        return auctions[tokenId];
    }
}
