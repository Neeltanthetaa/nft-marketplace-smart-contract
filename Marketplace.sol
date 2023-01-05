// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./ERC20.sol";
import "./NFTCollection.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "hardhat/console.sol"; //For debugging only

contract Marketplace is IERC721Receiver {
    function getTimestamp() public view returns(uint256) {
        return block.timestamp;
    }

    // Name of the marketplace
    string public name;

    // Index of auctions
    uint256 public index = 0;

    // Structure to define auction properties
    struct Auction {
        uint256 index; // Auction Index
        address addressNFTCollection; // Address of the ERC721 NFT Collection contract
        address addressPaymentToken; // Address of the ERC20 Payment Token contract
        uint256 nftId; // NFT Id
        address creator; // Creator of the Auction
        address payable currentBidOwner; // Address of the highest bider
        uint256 currentBidPrice; // Current highest bid for the auction
        uint256 endAuction; // Timestamp for the end day&time of the auction
        uint256 bidCount; // Number of bid placed on the auction
    }

    struct MarketItem {
        address addressNFTCollection; 
        address addressPaymentToken;
        uint256 nftId;
        bool isListed;
        uint256 listPrice;
        address payable seller;
    }

    mapping(address => mapping(uint256 => MarketItem)) getMarketItem;

    // List and unlist item function
    // To list item, _listPrice should be non-zero
    // To unlist item, _listPrice should be zero
    function listNFT(
        address _addressNFTCollection,
        address _addressPaymentToken,
        uint256 _nftId,
        uint256 _listPrice
    ) public {
        require(
            isContract(_addressNFTCollection),
            "Invalid NFT Collection contract address"
        );
        require(
            isContract(_addressPaymentToken),
            "Invalid Payment Token contract address"
        );

        // Getting auction id if it exsists
        uint256 _auctionId = getAuctionId[_addressNFTCollection][_nftId];

        // Check whether auction is going on or not
        require(
            getAuctionStatusFromId(_auctionId) == false && allAuctions[_auctionId].currentBidOwner == address(0),
            "Can't list the item while auction is going on."
        );

        // Get NFT collection contract
        NFTCollection nftCollection = NFTCollection(_addressNFTCollection);

        // Make sure the sender that wants to create a new auction
        // for a specific NFT is the owner of this NFT
        require(
            nftCollection.ownerOf(_nftId) == msg.sender || nftCollection.ownerOf(_nftId) == address(this),
            "Caller/Marketplace is not the owner of the NFT"
        );

        // Make sure the owner of the NFT approved that the MarketPlace contract
        // is allowed to change ownership of the NFT
        require(
            nftCollection.getApproved(_nftId) == address(this),
            "Require NFT ownership transfer approval"
        );

        // Unlist item from marketplace
        if(nftCollection.ownerOf(_nftId) == address(this) && _listPrice == 0 && getMarketItem[_addressNFTCollection][_nftId].isListed == true) {
            require(nftCollection.transferNFTFrom(address(this), msg.sender, _nftId));
            getMarketItem[_addressNFTCollection][_nftId].isListed = false;
            getMarketItem[_addressNFTCollection][_nftId].listPrice = 0;
        } else {
            // Check if the initial list price is > 0
            require(_listPrice > 0, "List price must be > 0");

            // If NFT is not already in the marketplace, transfer it to marketplace
            if(nftCollection.ownerOf(_nftId) == msg.sender) {
                // Lock NFT in Marketplace contract
                require(nftCollection.transferNFTFrom(msg.sender, address(this), _nftId));   
            }
        
            // Mark the item as listed
            getMarketItem[_addressNFTCollection][_nftId].addressNFTCollection = _addressNFTCollection;
            getMarketItem[_addressNFTCollection][_nftId].addressPaymentToken = _addressPaymentToken;
            getMarketItem[_addressNFTCollection][_nftId].nftId = _nftId;
            getMarketItem[_addressNFTCollection][_nftId].seller = payable(msg.sender);
            getMarketItem[_addressNFTCollection][_nftId].isListed = true;
            getMarketItem[_addressNFTCollection][_nftId].listPrice = _listPrice;
        }
    }

    // Buy NFT from the Marketplace
    function buyNFT(
        address _addressNFTCollection,
        uint256 _nftId,
        uint256 _payment
    ) external {
        // Check item is listed or not
        require(getMarketItem[_addressNFTCollection][_nftId].isListed == true, "Item isn't listed yet.");

        // check correct price is given or not
        require(getMarketItem[_addressNFTCollection][_nftId].listPrice == _payment, "Buy price must be equal to list price.");

        // get ERC20 token contract
        ERC20 paymentToken = ERC20(getMarketItem[_addressNFTCollection][_nftId].addressPaymentToken);

        // Transfer token
        require(
            paymentToken.transferFrom(payable(msg.sender), payable(getMarketItem[_addressNFTCollection][_nftId].seller), _payment),
            "Tranfer of payment token failed"
        );

        // Get NFT collection contract
        NFTCollection nftCollection = NFTCollection(
            getMarketItem[_addressNFTCollection][_nftId].addressNFTCollection
        );

        // Transfer NFT from marketplace contract to buyer
        require(
            nftCollection.transferNFTFrom(
                address(this),
                msg.sender,
                _nftId
            ),
            "Transfer of NFT failed."
        );

        // Reset market item
        getMarketItem[_addressNFTCollection][_nftId].isListed = false;
        getMarketItem[_addressNFTCollection][_nftId].listPrice = 0;
    }

    // Get auction id from nft collection address and nft id
    mapping(address => mapping(uint256 => uint256)) public getAuctionId;
    
    // Get auction status of an NFT
    // true - auction is open
    // false - auction is closed
    function getAuctionStatusFromNFT(address _addressNFTCollection, uint256 _nftId) public view returns(bool) {
        uint256 _auctionIndex = getAuctionId[_addressNFTCollection][_nftId];

        return getAuctionStatusFromId(_auctionIndex);
    }

    // Get auction status of an Auction
    // true - auction is open
    // false - auction is closed
    function getAuctionStatusFromId(uint256 _auctionIndex) public view returns(bool) {
        if(block.timestamp >= allAuctions[_auctionIndex].endAuction) {
            return false;
        } else {
            return true;
        }
    }

    // Get list of all open auctions
    function getOpenAuctions() public view returns(Auction[] memory) {
        uint256 _totalOpenAuctions;
        for(uint256 _i=0; _i<index; _i++) {
            if(getAuctionStatusFromId(_i) == true) {
                ++_totalOpenAuctions;
            }
        }

        Auction[] memory _openAuctions = new Auction[](_totalOpenAuctions);

        uint256 _j;
        for(uint256 _i=0; _i<index; _i++) {
            if(getAuctionStatusFromId(_i) == true) {
                _openAuctions[_j] = allAuctions[_i];
                ++_j;
            }
        }

        return _openAuctions;
    }

    // Structure to define a bidder
    struct Bidder {
        address userAddress;
        uint256 userBid;
        uint256 bidTime;
        bool hasAlreadyBid;
    }

    // Structure to define all bidders of an auction
    struct Bidders {
        address[] bidders;
        mapping(address => Bidder) getBid;
    }

    // Mapping from auction index to list of all bidders
    mapping(uint256 => Bidders) getBidders;

    // Array will all auctions
    Auction[] public allAuctions;

    // Public event to notify that a new auction has been created
    event NewAuction(
        uint256 index,
        address addressNFTCollection,
        address addressPaymentToken,
        uint256 nftId,
        address mintedBy,
        address currentBidOwner,
        uint256 currentBidPrice,
        uint256 endAuction,
        uint256 bidCount
    );

    // Public event to notify that a new bid has been placed
    event NewBidOnAuction(uint256 auctionIndex, uint256 newBid);

    // Public event to notif that winner of an
    // auction claim for his reward
    event NFTClaimed(uint256 auctionIndex, uint256 nftId, address claimedBy);

    // Public event to notify that the creator of
    // an auction claimed for his money
    event TokensClaimed(uint256 auctionIndex, uint256 nftId, address claimedBy);

    // Public event to notify that an NFT has been refunded to the
    // creator of an auction
    event NFTRefunded(uint256 auctionIndex, uint256 nftId, address claimedBy);

    // constructor of the contract
    constructor() {
        name = "Uday Marketplace";
    }

    /**
     * Get bid count from auction index
     * @param _auctionIndex: Index of the auction
     */
    function getBidCount(uint256 _auctionIndex) public view returns(uint256) {
        return allAuctions[_auctionIndex].bidCount;
    }

    /**
     * Check if a specific address is
     * a contract address
     * @param _addr: address to verify
     */
    function isContract(address _addr) private view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(_addr)
        }
        return size > 0;
    }

    /**
     * Create a new auction of a specific NFT
     * @param _addressNFTCollection address of the ERC721 NFT collection contract
     * @param _addressPaymentToken address of the ERC20 payment token contract
     * @param _nftId Id of the NFT for sale
     * @param _initialBid Inital bid decided by the creator of the auction
     * @param _endAuction Timestamp with the end date and time of the auction
     */
    function createAuction(
        address _addressNFTCollection,
        address _addressPaymentToken,
        uint256 _nftId,
        uint256 _initialBid,
        uint256 _endAuction
    ) external returns (uint256) {
        //Check is addresses are valid
        require(
            isContract(_addressNFTCollection),
            "Invalid NFT Collection contract address"
        );
        require(
            isContract(_addressPaymentToken),
            "Invalid Payment Token contract address"
        );

        // Check if the endAuction time is valid
        require(_endAuction > block.timestamp, "Invalid end date for auction");

        // Check if the initial bid price is > 0
        require(_initialBid > 0, "Invalid initial bid price");

        // Get NFT collection contract
        NFTCollection nftCollection = NFTCollection(_addressNFTCollection);

        // Make sure the sender that wants to create a new auction
        // for a specific NFT is the owner of this NFT
        require(
            nftCollection.ownerOf(_nftId) == msg.sender,
            "Caller is not the owner of the NFT"
        );

        // Make sure the owner of the NFT approved that the MarketPlace contract
        // is allowed to change ownership of the NFT
        require(
            nftCollection.getApproved(_nftId) == address(this),
            "Require NFT ownership transfer approval"
        );

        // Lock NFT in Marketplace contract
        require(nftCollection.transferNFTFrom(msg.sender, address(this), _nftId));

        //Casting from address to address payable
        address payable currentBidOwner = payable(address(0));

        // increment auction sequence
        index = index + 1;

        // Create new Auction object
        Auction memory newAuction = Auction({
            index: index,
            addressNFTCollection: _addressNFTCollection,
            addressPaymentToken: _addressPaymentToken,
            nftId: _nftId,
            creator: msg.sender,
            currentBidOwner: currentBidOwner,
            currentBidPrice: _initialBid,
            endAuction: _endAuction,
            bidCount: 0
        });

        //update list
        allAuctions.push(newAuction);

        // Trigger event and return index of new auction
        emit NewAuction(
            index,
            _addressNFTCollection,
            _addressPaymentToken,
            _nftId,
            msg.sender,
            currentBidOwner,
            _initialBid,
            _endAuction,
            0
        );

        // Setting a mapping to get auction ID from NFT
        getAuctionId[_addressNFTCollection][_nftId] = index - 1;

        return index;
    }

    // Cancel Auction function
    function cancelAuction(uint256 _auctionIndex) external {
        require(getAuctionStatusFromId(_auctionIndex) == true, "Auction isn't going on.");
        require(allAuctions[_auctionIndex].creator == msg.sender, "Only auction creator can cancel the auction.");

        Auction storage auction = allAuctions[_auctionIndex];

        if(auction.currentBidOwner != address(0)) {
            // get ERC20 token contract
            ERC20 paymentToken = ERC20(auction.addressPaymentToken);

            // Pay token back to the bidder
            require(
                paymentToken.transfer(
                auction.currentBidOwner,
                auction.currentBidPrice
            ), "Token transfer failed");
        }

        // Get NFT collection contract
        NFTCollection nftCollection = NFTCollection(
            auction.addressNFTCollection
        );

        // Transfer NFT from marketplace contract to auction creator
        require(
            nftCollection.transferNFTFrom(
                address(this),
                auction.creator,
                auction.nftId
            ),
            "Transfer of NFT failed."
        );
        
        // Update auction
        auction.endAuction = 0;
    }

    /**
     * Check if an auction is open
     * @param _auctionIndex Index of the auction
     */
    function isOpen(uint256 _auctionIndex) public view returns (bool) {
        Auction storage auction = allAuctions[_auctionIndex];
        if (block.timestamp >= auction.endAuction) return false;
        return true;
    }

    /**
     * Return the address of the current highest bider
     * for a specific auction
     * @param _auctionIndex Index of the auction
     */
    function getCurrentBidOwner(uint256 _auctionIndex)
        public
        view
        returns (address)
    {
        require(_auctionIndex < allAuctions.length, "Invalid auction index");
        return allAuctions[_auctionIndex].currentBidOwner;
    }

    /**
     * Return the current highest bid price
     * for a specific auction
     * @param _auctionIndex Index of the auction
     */
    function getCurrentBid(uint256 _auctionIndex)
        public
        view
        returns (uint256)
    {
        require(_auctionIndex < allAuctions.length, "Invalid auction index");
        return allAuctions[_auctionIndex].currentBidPrice;
    }

    /**
     * Place new bid on a specific auction
     * @param _auctionIndex Index of auction
     * @param _newBid New bid price
     */
    function bid(uint256 _auctionIndex, uint256 _newBid)
        external
        returns (bool)
    {
        require(_auctionIndex < allAuctions.length, "Invalid auction index");
        Auction storage auction = allAuctions[_auctionIndex];

        // check if auction is still open
        require(isOpen(_auctionIndex), "Auction is not open");

        // check if new bid price is higher than the current one
        require(
            _newBid > auction.currentBidPrice,
            "New bid price must be higher than the current bid"
        );

        // check if new bider is not the owner
        require(
            msg.sender != auction.creator,
            "Creator of the auction cannot place new bid"
        );

        // get ERC20 token contract
        ERC20 paymentToken = ERC20(auction.addressPaymentToken);

        // new bid is better than current bid!
        // transfer token from new bider account to the marketplace account
        // to lock the tokens
        require(
            paymentToken.transferFrom(msg.sender, address(this), _newBid),
            "Tranfer of token failed"
        );

        // new bid is valid so must refund the current bid owner (if there is one!)
        if (auction.bidCount > 0) {
            paymentToken.transfer(
                auction.currentBidOwner,
                auction.currentBidPrice
            );
        }

        // update auction info
        address payable newBidOwner = payable(msg.sender);
        auction.currentBidOwner = newBidOwner;
        auction.currentBidPrice = _newBid;
        auction.bidCount++;

        if(getBidders[_auctionIndex].getBid[msg.sender].hasAlreadyBid == false) {
            getBidders[_auctionIndex].getBid[msg.sender].userAddress = msg.sender;
            getBidders[_auctionIndex].getBid[msg.sender].hasAlreadyBid = true;
            getBidders[_auctionIndex].getBid[msg.sender].userBid = _newBid;
            getBidders[_auctionIndex].getBid[msg.sender].bidTime = block.timestamp;
            getBidders[_auctionIndex].bidders.push(msg.sender);
        } else {
            getBidders[_auctionIndex].getBid[msg.sender].userBid = _newBid;
            getBidders[_auctionIndex].getBid[msg.sender].bidTime = block.timestamp;
        }

        // Trigger public event
        emit NewBidOnAuction(_auctionIndex, _newBid);

        return true;
    }

    /**
     * Get all bidders of an auction
     * @param _auctionIndex Index of auction
     */
    function getAllBidders(uint256 _auctionIndex) public view returns(Bidder[] memory) {
        Bidder[] memory _allBidders = new Bidder[](getBidders[_auctionIndex].bidders.length);

        for(uint256 _i=0; _i<getBidders[_auctionIndex].bidders.length; _i++) {
            _allBidders[_i].userAddress = getBidders[_auctionIndex].getBid[ getBidders[_auctionIndex].bidders[_i] ].userAddress;
            _allBidders[_i].userBid = getBidders[_auctionIndex].getBid[ getBidders[_auctionIndex].bidders[_i] ].userBid;
            _allBidders[_i].bidTime = getBidders[_auctionIndex].getBid[ getBidders[_auctionIndex].bidders[_i] ].bidTime;
            _allBidders[_i].hasAlreadyBid = getBidders[_auctionIndex].getBid[ getBidders[_auctionIndex].bidders[_i] ].hasAlreadyBid;
        }

        return _allBidders;
    }

    /**
     * Function used by the winner of an auction
     * to withdraw his NFT.
     * When the NFT is withdrawn, the creator of the
     * auction will receive the payment tokens in his wallet
     * @param _auctionIndex Index of auction
     */
    function claimNFT(uint256 _auctionIndex) external {
        require(_auctionIndex < allAuctions.length, "Invalid auction index");

        // Check if the auction is closed
        require(!isOpen(_auctionIndex), "Auction is still open");

        // Get auction
        Auction storage auction = allAuctions[_auctionIndex];

        // Check if the caller is the winner of the auction
        require(
            auction.currentBidOwner == msg.sender,
            "NFT can be claimed only by the current bid owner"
        );

        // Get NFT collection contract
        NFTCollection nftCollection = NFTCollection(
            auction.addressNFTCollection
        );
        // Transfer NFT from marketplace contract
        // to the winner address
        require(
            nftCollection.transferNFTFrom(
                address(this),
                auction.currentBidOwner,
                _auctionIndex
            )
        );

        // Get ERC20 Payment token contract
        ERC20 paymentToken = ERC20(auction.addressPaymentToken);
        // Transfer locked token from the marketplace
        // contract to the auction creator address
        require(
            paymentToken.transfer(auction.creator, auction.currentBidPrice)
        );

        emit NFTClaimed(_auctionIndex, auction.nftId, msg.sender);
    }

    /**
     * Function used by the creator of an auction
     * to withdraw his tokens when the auction is closed
     * When the Token are withdrawn, the winned of the
     * auction will receive the NFT in his walled
     * @param _auctionIndex Index of the auction
     */
    function claimToken(uint256 _auctionIndex) external {
        require(_auctionIndex < allAuctions.length, "Invalid auction index"); // XXX Optimize

        // Check if the auction is closed
        require(!isOpen(_auctionIndex), "Auction is still open");

        // Get auction
        Auction storage auction = allAuctions[_auctionIndex];

        // Check if the caller is the creator of the auction
        require(
            auction.creator == msg.sender,
            "Tokens can be claimed only by the creator of the auction"
        );

        // Get NFT Collection contract
        NFTCollection nftCollection = NFTCollection(
            auction.addressNFTCollection
        );
        // Transfer NFT from marketplace contract
        // to the winned of the auction
        nftCollection.transferFrom(
            address(this),
            auction.currentBidOwner,
            auction.nftId
        );

        // Get ERC20 Payment token contract
        ERC20 paymentToken = ERC20(auction.addressPaymentToken);
        // Transfer locked tokens from the market place contract
        // to the wallet of the creator of the auction
        paymentToken.transfer(auction.creator, auction.currentBidPrice);

        emit TokensClaimed(_auctionIndex, auction.nftId, msg.sender);
    }

    /**
     * Function used by the creator of an auction
     * to get his NFT back in case the auction is closed
     * but there is no bider to make the NFT won't stay locked
     * in the contract
     * @param _auctionIndex Index of the auction
     */
    function refund(uint256 _auctionIndex) external {
        require(_auctionIndex < allAuctions.length, "Invalid auction index");

        // Check if the auction is closed
        require(!isOpen(_auctionIndex), "Auction is still open");

        // Get auction
        Auction storage auction = allAuctions[_auctionIndex];

        // Check if the caller is the creator of the auction
        require(
            auction.creator == msg.sender,
            "Tokens can be claimed only by the creator of the auction"
        );

        require(
            auction.currentBidOwner == address(0),
            "Existing bider for this auction"
        );

        // Get NFT Collection contract
        NFTCollection nftCollection = NFTCollection(
            auction.addressNFTCollection
        );
        // Transfer NFT back from marketplace contract
        // to the creator of the auction
        nftCollection.transferFrom(
            address(this),
            auction.creator,
            auction.nftId
        );

        emit NFTRefunded(_auctionIndex, auction.nftId, msg.sender);
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }
}