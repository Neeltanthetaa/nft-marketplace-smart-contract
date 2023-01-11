// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "hardhat/console.sol";

contract NFTMarketplace is ReentrancyGuard {
    string public marketplaceName;

    constructor() {
        marketplaceName = "Uday Marketplace";
    }

    struct Nft {
        address collection;
        uint256 id;
        address payment;
        address payable seller;
    }

    struct MarketItem {
        uint256 index;
        Nft nft;
        uint256 listPrice;
        bool isListed;
    }

    struct AuctionItem {
        uint256 index;
        Nft nft;
        uint256 bidPrice;
        uint256 startTime;
        uint256 endTime;
        address payable currentBidOwner;
        uint256 currentBidPrice;
        bool onAuction;
    }

    struct Bid {
        address bidOwner;
        uint256 bidPrice;
        uint256 bidTime;
    }

    uint256 public totalMarketItems;
    uint256 public totalAuctionItems;

    mapping(uint256 => MarketItem) public getMarketItems;
    mapping(uint256 => AuctionItem) public getAuctionItems;
    mapping(uint256 => mapping(uint256 => Bid)) public getBids;
    mapping(uint256 => uint256) public getBidders;

    mapping(address => mapping(uint256 => uint256)) public getMarketIndex;
    mapping(address => mapping(uint256 => uint256)) public getAuctionIndex;
    
    // if _payment = address(0), token is listed on ethereum
    // if _listPrice = 0, token will be unlisted
    function setListing(
        address _collection, 
        uint256 _id,
        address _payment,
        uint256 _listPrice
    ) public {
        // Getting Auction Index
        uint256 auctionIndex = getAuctionIndex[_collection][_id];

        // Fetch Auction Item
        AuctionItem memory auctionItem = getAuctionItems[auctionIndex];

        // Cancel Auction
        if(auctionItem.onAuction == true) {
            // Check if Auction has ended
            require(block.timestamp < auctionItem.endTime, "Auction can only be claimed now.");

            // Return All Bids
            if(auctionItem.currentBidOwner != address(0)) {
                if(auctionItem.nft.payment == address(0)) {
                    payable(auctionItem.currentBidOwner).transfer(auctionItem.currentBidPrice);
                } else {
                    IERC20 Pay = IERC20(auctionItem.nft.payment);
                    Pay.transferFrom(auctionItem.currentBidOwner, address(this), auctionItem.currentBidPrice);
                }
            }
        
            // Update Auction
            getAuctionItems[auctionIndex] = AuctionItem(
                {   
                    index : auctionIndex,
                    nft: Nft(
                        {
                            collection : _collection,
                            id : _id,
                            payment : address(0),
                            seller : payable(address(0))
                        }
                    ),
                    bidPrice : 0,
                    startTime : 0,
                    endTime : 0,
                    currentBidOwner : payable(address(0)),
                    currentBidPrice : 0,
                    onAuction : false
                }
            );

            // Setting Get Auction Index
            getAuctionIndex[_collection][_id] = 0;
        }
        
        // Getting Market Index
        uint256 marketIndex = getMarketIndex[_collection][_id];

        // Setting Market Index
        if(marketIndex == 0) {
            totalMarketItems += 1;
            marketIndex = totalMarketItems;
        } else {
            require(getMarketItems[marketIndex].nft.seller == msg.sender, "Only seller can call this function.");
        }

        // Getting NFT
        IERC721 Item = IERC721(_collection);

        // Transferring Ownership
        if(Item.ownerOf(_id) != address(this)) {
            Item.transferFrom(msg.sender, address(this), _id);
        }

        // Set Listing Status
        bool _isListed;
        address _seller;
        if(_listPrice == 0) {
            Item.transferFrom(address(this), msg.sender, _id);
            _isListed = false;
            _seller = address(0);
        } else {
            _isListed = true;
            _seller = msg.sender;
        }
        
        // Update Listing
        getMarketItems[marketIndex] = MarketItem(
            {   
                index : marketIndex,
                nft: Nft(
                    {
                        collection : _collection,
                        id : _id,
                        payment : _payment,
                        seller : payable(_seller)
                    }
                ),
                listPrice : _listPrice,
                isListed : _isListed
            }
        );

        // Setting Get Market Index
        if(_isListed == true) {
            getMarketIndex[_collection][_id] = marketIndex;
        } else {
            getMarketIndex[_collection][_id] = 0;
        }
        
    }

    // Buy a Listed Item
    function buyListing(
        address _collection, 
        uint256 _id
    ) public payable {
        // Getting Market Index
        uint256 marketIndex = getMarketIndex[_collection][_id];

        // Getting Market Item
        MarketItem memory marketItem = getMarketItems[marketIndex];

        // Check Listing
        require(marketItem.isListed == true, "Item isn't listed.");

        // Transferring Payment
        if(marketItem.nft.payment == address(0)) {
            require(msg.value == marketItem.listPrice, "Payment Transfer Failed");
            payable(marketItem.nft.seller).transfer(msg.value);
        } else {
            IERC20 Pay = IERC20(marketItem.nft.payment);
            Pay.transferFrom(msg.sender, marketItem.nft.seller, marketItem.listPrice);
        }

        // Transferring NFT
        IERC721 Item = IERC721(_collection);
        Item.transferFrom(address(this), msg.sender, _id);

        // Update Listing
        getMarketItems[marketIndex] = MarketItem(
            {   
                index : marketIndex,
                nft: Nft(
                    {
                        collection : _collection,
                        id : _id,
                        payment : address(0),
                        seller : payable(0)
                    }
                ),
                listPrice : 0,
                isListed : false
            }
        );

        // Setting Get Market Index
        getMarketIndex[_collection][_id] = 0;
    }

    // if _payment = address(0), token is auctioned on ethereum
    // if _bidPrice = 0, token will be unauctioned
    function setAuction(
        address _collection, 
        uint256 _id,
        address _payment,
        uint256 _bidPrice,
        uint256 _startTime,
        uint256 _endTime
    ) public {
        // Getting Market Index
        uint256 marketIndex = getMarketIndex[_collection][_id];

        // Check Market Listing
        MarketItem memory marketItem = getMarketItems[marketIndex];

        // Cancel Listing
        if(marketItem.isListed == true) {
            require(marketItem.nft.seller == msg.sender, "Only Seller can Cancel Listing.");

            // Update Listing
            getMarketItems[marketIndex] = MarketItem(
                {   
                    index : marketIndex,
                    nft: Nft(
                        {
                            collection : _collection,
                            id : _id,
                            payment : address(0),
                            seller : payable(address(0))
                        }
                    ),
                    listPrice : 0,
                    isListed : false
                }
            ); 

            // Setting Get Market Index
            getMarketIndex[_collection][_id] = 0;
        }

        // Getting Auction Index
        uint256 auctionIndex = getAuctionIndex[_collection][_id];

        // Setting Auction Index
        if(auctionIndex == 0) {
            totalAuctionItems += 1;
            auctionIndex = totalAuctionItems;
        } else {
            require(getAuctionItems[auctionIndex].nft.seller == msg.sender, "Only Seller can call this function.");
        }

        // Getting NFT
        IERC721 Item = IERC721(_collection);

        // Transferring Ownership
        if(Item.ownerOf(_id) != address(this)) {
            Item.transferFrom(msg.sender, address(this), _id);
        }

        // Set Auction Status
        bool _onAuction;
        address _seller;
        if(_bidPrice == 0) {
            // Reset Auction Index On Cancellation
            AuctionItem memory auctionItem = getAuctionItems[auctionIndex];

            // Return Previous Bid
            if(auctionItem.currentBidOwner != address(0)) {
                if(auctionItem.nft.payment == address(0)) {
                    payable(auctionItem.currentBidOwner).transfer(auctionItem.currentBidPrice);
                } else {
                    IERC20 Pay = IERC20(auctionItem.nft.payment);
                    Pay.transferFrom(address(this), auctionItem.currentBidOwner, auctionItem.currentBidPrice);
                }
            }

            // Transferring NFT
            Item.transferFrom(address(this), msg.sender, _id);

            // Resetting Variables
            _startTime = 0;
            _endTime = 0;
            _onAuction = false;
            _seller = address(0);
        } else {
            _onAuction = true;
            _seller = msg.sender;
        }

        // Update Auction
        getAuctionItems[auctionIndex] = AuctionItem(
            {   
                index : auctionIndex,
                nft: Nft(
                    {
                        collection : _collection,
                        id : _id,
                        payment : _payment,
                        seller : payable(_seller)
                    }
                ),
                bidPrice : _bidPrice,
                startTime : _startTime,
                endTime : _endTime,
                currentBidOwner : payable(address(0)),
                currentBidPrice : _bidPrice,
                onAuction : _onAuction
            }
        );

        // Setting Get Auction Index
        if(_onAuction == true) {
            getAuctionIndex[_collection][_id] = auctionIndex;
        } else {
            getAuctionIndex[_collection][_id] = 0;
        }
    }

    // Make A Bid
    function makeBid(
        address _collection, 
        uint256 _id,
        uint256 _bid
    ) public payable {
        // Getting Auction Index
        uint256 auctionIndex = getAuctionIndex[_collection][_id];

        // Getting Auction Item
        AuctionItem memory auctionItem = getAuctionItems[auctionIndex];

        // Check Auction
        require(auctionItem.onAuction == true, "Item isn't on Auction.");
        require(block.timestamp >= auctionItem.startTime, "Auction hasn't started yet.");
        require(block.timestamp < auctionItem.endTime, "Auction has ended.");

        // New Bid Price
        uint256 _currentBidPrice;

        // Transferring Payment
        if(auctionItem.nft.payment == address(0)) {
            require(msg.value > auctionItem.currentBidPrice, "Payment Transfer Failed");
        
            // Return Previous Bid
            if(auctionItem.currentBidOwner != address(0)) {
                payable(auctionItem.currentBidOwner).transfer(auctionItem.currentBidPrice);
            }

            // Make New Bid
            _currentBidPrice = msg.value;

            // Push Bidder
            uint256 bidders = getBidders[auctionIndex];
            getBids[auctionIndex][bidders] = Bid(
                {
                    bidOwner : msg.sender,
                    bidPrice : msg.value,
                    bidTime : block.timestamp
                }
            );
            getBidders[auctionIndex] += 1;
        } else {
            require(_bid > auctionItem.currentBidPrice, "Payment Transfer Failed");
            
            // Return Previous Bid
            IERC20 Pay = IERC20(auctionItem.nft.payment);
            if(auctionItem.currentBidOwner != address(0)) {
                Pay.transferFrom(address(this), auctionItem.currentBidOwner, auctionItem.currentBidPrice);
            }

            // Make New Bid
            Pay.transferFrom(msg.sender, address(this), _bid);
            _currentBidPrice = _bid;

            // Push Bidder
            uint256 bidders = getBidders[auctionIndex];
            getBids[auctionIndex][bidders] = Bid(
                {
                    bidOwner : msg.sender,
                    bidPrice : _bid,
                    bidTime : block.timestamp
                }
            );
            getBidders[auctionIndex] += 1;
        }
        
        // Update Auction
        getAuctionItems[auctionIndex] = AuctionItem(
            {   
                index : auctionIndex,
                nft: Nft(
                    {
                        collection : _collection,
                        id : _id,
                        payment : auctionItem.nft.payment,
                        seller : auctionItem.nft.seller
                    }
                ),
                bidPrice : auctionItem.bidPrice,
                startTime : auctionItem.startTime,
                endTime : auctionItem.endTime,
                currentBidOwner : payable(msg.sender),
                currentBidPrice : _currentBidPrice,
                onAuction : true
            }
        );
    }

    // Transfer NFT & Bid after auction ends
    function claimAuction(
        address _collection, 
        uint256 _id
    ) public payable {
        // Getting Auction Index
        uint256 auctionIndex = getAuctionIndex[_collection][_id];

        // Getting Auction Item
        AuctionItem memory auctionItem = getAuctionItems[auctionIndex];

        // Check Auction
        require(auctionItem.onAuction == true, "Item isn't on Auction.");
        require(block.timestamp > auctionItem.endTime, "Auction hasn't ended yet.");

        // Getting Collection
        IERC721 Item = IERC721(_collection);

        if(auctionItem.currentBidOwner == address(0)) {
            // Transferring NFT
            Item.transferFrom(address(this), auctionItem.nft.seller, _id);
        } else {
            // Transferring Payment
            if(auctionItem.nft.payment == address(0)) {
                payable(auctionItem.nft.seller).transfer(auctionItem.currentBidPrice);
            } else {
                IERC20 Pay = IERC20(auctionItem.nft.payment);
                Pay.transferFrom(address(this), auctionItem.currentBidOwner, auctionItem.currentBidPrice);
            }

            // Transferring NFT
            Item.transferFrom(address(this), auctionItem.currentBidOwner, _id);
        }

        // Update Auction
        getAuctionItems[auctionIndex] = AuctionItem(
            {   
                index : auctionIndex,
                nft: Nft(
                    {
                        collection : _collection,
                        id : _id,
                        payment : address(0),
                        seller : payable(address(0))
                    }
                ),
                bidPrice : 0,
                startTime : 0,
                endTime : 0,
                currentBidOwner : payable(address(0)),
                currentBidPrice : 0,
                onAuction : false
            }
        );

        // Setting Get Auction Index
        getAuctionIndex[_collection][_id] = 0;
    }

    // Get All Listed Items
    function getAllListedItems() public view returns(MarketItem[] memory) {
        uint256 totalListedItems = 0;

        for(uint256 _i = 1; _i <= totalMarketItems; _i++) {
            if(getMarketItems[_i].isListed == true) {
                totalListedItems++;
            }
        }

        MarketItem[] memory allListedItems = new MarketItem[](totalListedItems);

        for(uint256 _i = 1; _i <= totalListedItems; _i++) {
            allListedItems[_i - 1] = getMarketItems[_i];
        }

        return allListedItems;
    }

    // Get All Open Auction Items
    function getAllOpenAuctionItems() public view returns(AuctionItem[] memory) {
        uint256 totalOpenAuctionItems = 0;

        for(uint256 _i = 1; _i <= totalAuctionItems; _i++) {
            if(getAuctionItems[_i].onAuction == true) {
                totalOpenAuctionItems++;
            }
        }

        AuctionItem[] memory allOpenAuctionItems = new AuctionItem[](totalOpenAuctionItems);

        for(uint256 _i = 1; _i <= totalAuctionItems; _i++) {
            if(getAuctionItems[_i].onAuction == true) {
                allOpenAuctionItems[_i - 1] = getAuctionItems[_i];
            }
        }

        return allOpenAuctionItems;
    }

    // Get All Listed Items By Address
    function getMarketItemsByAddress(address _address) public view returns(MarketItem[] memory) {
        uint256 totalListedItems = 0;

        for(uint256 _i = 1; _i <= totalMarketItems; _i++) {
            if(getMarketItems[_i].isListed == true && getMarketItems[_i].nft.seller == _address) {
                totalListedItems++;
            }
        }

        MarketItem[] memory allListedItems = new MarketItem[](totalListedItems);

        for(uint256 _i = 1; _i <= totalMarketItems; _i++) {
            if(getMarketItems[_i].isListed == true && getMarketItems[_i].nft.seller == _address) {
                allListedItems[_i - 1] = getMarketItems[_i];
            }
        }

        return allListedItems;
    }

    // Get All Open Auction Items By Address
    function getAllOpenAuctionItemsByAddress(address _address) public view returns(AuctionItem[] memory) {
        uint256 totalOpenAuctionItems = 0;

        for(uint256 _i = 1; _i <= totalAuctionItems; _i++) {
            if(getAuctionItems[_i].onAuction == true && getAuctionItems[_i].nft.seller == _address) {
                totalOpenAuctionItems++;
            }
        }

        AuctionItem[] memory allOpenAuctionItems = new AuctionItem[](totalOpenAuctionItems);

        for(uint256 _i = 1; _i <= totalAuctionItems; _i++) {
            if(getAuctionItems[_i].onAuction == true && getAuctionItems[_i].nft.seller == _address) {
                allOpenAuctionItems[_i - 1] = getAuctionItems[_i];
            }
        }

        return allOpenAuctionItems;
    }

    // Get all bids of an auction
    function getAllBids(address _collection, uint256 _id) public view returns(Bid[] memory) {
        uint256 auctionIndex = getAuctionIndex[_collection][_id];

        Bid[] memory allBids = new Bid[](getBidders[auctionIndex]);

        for(uint256 _i = 0; _i < getBidders[auctionIndex]; _i++) {
            allBids[_i] = getBids[auctionIndex][_i];
        }

        return allBids;
    }
}