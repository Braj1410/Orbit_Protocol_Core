// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./TLDStorage.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract TLDAuction is OwnableUpgradeable {
    TLDStorage public storageModule;

    mapping(uint256 => Auction) public auctions;

    struct Auction {
        address highestBidder;
        uint256 highestBid;
        uint256 startTime;
        uint256 endTime;
        bool active;
    }

    event AuctionStarted(uint256 indexed tokenId, uint256 startingPrice);
    event BidPlaced(uint256 indexed tokenId, address bidder, uint256 amount);
    event AuctionSettled(
        uint256 indexed tokenId,
        address winner,
        uint256 price
    );

    function initialize(address _storage) public initializer {
        __Ownable_init(msg.sender);
        storageModule = TLDStorage(_storage);
    }

    function startAuction(
        uint256 tokenId,
        uint256 startingPrice
    ) external onlyOwner {
        require(!auctions[tokenId].active, "Auction already active");

        auctions[tokenId] = Auction({
            highestBidder: address(0),
            highestBid: startingPrice,
            startTime: block.timestamp,
            endTime: block.timestamp + 7 days,
            active: true
        });

        emit AuctionStarted(tokenId, startingPrice);
    }

    function bid(uint256 tokenId) external payable {
        Auction storage auction = auctions[tokenId];
        require(auction.active, "Auction not active");
        require(block.timestamp < auction.endTime, "Auction ended");
        require(msg.value > auction.highestBid, "Bid too low");

        if (auction.highestBidder != address(0)) {
            payable(auction.highestBidder).transfer(auction.highestBid);
        }

        auction.highestBidder = _msgSender();
        auction.highestBid = msg.value;

        emit BidPlaced(tokenId, _msgSender(), msg.value);
    }

    function settleAuction(
        uint256 tokenId
    ) external onlyOwner returns (address winner, uint256 price) {
        Auction storage auction = auctions[tokenId];
        require(auction.active, "Auction not active");
        require(block.timestamp >= auction.endTime, "Auction not ended");

        auction.active = false;

        winner = auction.highestBidder;
        price = auction.highestBid;

        emit AuctionSettled(tokenId, winner, price);
    }

    function withdraw() external {
        // In a real implementation, this would be more robust
    }
}
