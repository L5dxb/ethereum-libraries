pragma solidity ^0.4.15;

/**
 * @title InteractiveCrowdsaleLib
 * @author Majoolr.io
 *
 * version 1.0.0
 * Copyright (c) 2017 Majoolr, LLC
 * The MIT License (MIT)
 * https://github.com/Majoolr/ethereum-libraries/blob/master/LICENSE
 *
 * The InteractiveCrowdsale Library provides functionality to create a initial coin offering
 * for a standard token sale with high supply where there is a direct ether to
 * token transfer.
 *
 * Majoolr provides smart contract services and security reviews for contract
 * deployments in addition to working on open source projects in the Ethereum
 * community. Our purpose is to test, document, and deploy reusable code onto the
 * blockchain and improve both security and usability. We also educate non-profits,
 * schools, and other community members about the application of blockchain
 * technology. For further information: majoolr.io
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
 * OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 * IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
 * CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
 * TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
 * SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

import "./BasicMathLib.sol";
import "./TokenLib.sol";
import "./CrowdsaleLib.sol";
import "./LinkedListLib.sol";

library InteractiveCrowdsaleLib {
  using BasicMathLib for uint256;
  using LinkedListLib for LinkedListLib.LinkedList;
  using CrowdsaleLib for CrowdsaleLib.CrowdsaleStorage;

  uint256 constant NULL = 0;
  uint256 constant HEAD = 0;
  bool constant PREV = false;
  bool constant NEXT = true;

  struct InteractiveCrowdsaleStorage {

  	CrowdsaleLib.CrowdsaleStorage base; // base storage from CrowdsaleLib

  	// List of personal caps, sorted from smallest to largest (from LinkedListLib)
  	LinkedListLib.LinkedList capsList;

  	uint256 endWithdrawlTime;   // time when manual withdrawls are no longer allowed

  	mapping (address => uint256) personalCaps;    // the cap that each address has submitted

  	mapping (uint256 => address[]) capAddresses;  // each address that has submitted at a certain valuation

  }

  // Indicates when a bidder submits a bid to the crowdsale
  event LogBidAccepted(address indexed bidder, uint256 amount, uint256 personalCap);

  // Indicates when a bidder manually withdraws their bid from the crowdsale
  event LogBidWithdrawn(address indexed bidder, uint256 amount, uint256 personalCap);

  // Indicates when a bid is removed by the automated bid removal process
  event LogBidRemoved(address indexed bidder, uint256 amount, uint256 personalCap);

  // Generic Error Msg Event
  event LogErrorMsg(uint256 amount, string Msg);

  // Indicates when the price of the token changes
  event LogTokenPriceChange(uint256 amount, string Msg);


  /// @dev Called by a crowdsale contract upon creation.
  /// @param self Stored crowdsale from crowdsale contract
  /// @param _owner Address of crowdsale owner
  /// @param _saleData Array of 3 item arrays such that, in each 3 element
  /// array index-0 is timestamp, index-1 is price in cents at that time,
  /// index-2 is address purchase cap at that time, 0 if no address cap
  /// @param _fallbackExchangeRate Exchange rate of cents/ETH
  /// @param _capAmountInCents Total to be raised in cents
  /// @param _endTime Timestamp of sale end time
  /// @param _percentBurn Percentage of extra tokens to burn
  /// @param _token Token being sold
  function init(InteractiveCrowdsaleStorage storage self,
                address _owner,
                uint256[] _saleData,
                uint256 _fallbackExchangeRate,
                uint256 _capAmountInCents,
                uint256 _endWithdrawlTime,
                uint256 _endTime,
                uint8 _percentBurn,
                CrowdsaleToken _token)
  {
  	self.base.init(_owner,
                _saleData,
                _fallbackExchangeRate,
                _capAmountInCents,
                _endTime,
                _percentBurn,
                _token);

  	self.endWithdrawlTime = _endWithdrawlTime;
  }

  /// @dev Called when an address wants to submit bid to the sale
  /// @param self Stored crowdsale from crowdsale contract
  /// @param _amount amound of wei that the buyer is sending
  /// @param _personalCap the total crowdsale valuation (wei) that the bidder is comfortable with
  /// @param _listPredict prediction of where the cap will go in the linked list
  /// @return true on succesful bid
  function submitBid(InteractiveCrowdsaleStorage storage self, uint256 _amount, uint256 _personalCap, uint256 _listPredict) public returns (bool) {
  	require(msg.sender != self.base.owner);
  	require(self.base.validPurchase());
  	require(self.personalCaps[msg.sender] == 0);
  	require(_personalCap >= self.base.ownerBalance + _amount);
  	require((_personalCap % 100000000000000000000) == 0);      // personal valuations need to be in multiples of 100 ETH
    require(self.capsList.getAdjacent(_listPredict,NEXT) != 0);  //prediction must already be an entry in the list

  	require((self.base.ownerBalance + _amount) <= self.base.capAmount);

  	// if the token price increase interval has passed, update the current day and change the token price
  	if ((self.base.milestoneTimes.length > self.base.currentMilestone + 1) &&
        (now > self.base.milestoneTimes[self.base.currentMilestone + 1]))
    {
        while((self.base.milestoneTimes.length > self.base.currentMilestone + 1) &&
              (now > self.base.milestoneTimes[self.base.currentMilestone + 1]))
        {
          self.base.currentMilestone += 1;
        }

        self.base.changeTokenPrice(self.base.saleData[self.base.milestoneTimes[self.base.currentMilestone]][0]);
        LogTokenPriceChange(self.base.tokensPerEth,"Token Price has changed!");
    }

    // calculate number of tokens purchased
    uint256 numTokens; //number of tokens that will be purchased
    uint256 zeros; //for calculating token
    uint256 remainder = 0; //temp calc holder for division remainder for leftover wei and then later for tokens remaining for the owner
    bool err;
    uint256 result;

    // Find the number of tokens as a function in wei
    (err,result) = _amount.times(self.base.tokensPerEth);
    require(!err);

    if(self.base.tokenDecimals <= 18){
      zeros = 10**(18-uint256(self.base.tokenDecimals));
      numTokens = result/zeros;
      remainder = result % zeros;
    } else {
      zeros = 10**(uint256(self.base.tokenDecimals)-18);
      numTokens = result*zeros;
    }

    self.base.leftoverWei[msg.sender] += remainder;

    // can't overflow because it is under the cap
    self.base.hasContributed[msg.sender] += _amount-remainder;

    require(numTokens <= self.base.token.balanceOf(this));

    // calculate the amout of ether in the owners balance and "deposit" it
    self.base.ownerBalance = self.base.ownerBalance + (_amount - remainder);

    // can't overflow because it will be under the cap
    self.base.withdrawTokensMap[msg.sender] += numTokens;

    //subtract tokens from owner's share
    (err,remainder) = self.base.withdrawTokensMap[self.base.owner].minus(numTokens);
    require(!err);
    self.base.withdrawTokensMap[self.base.owner] = remainder;

    // add the bid to the sorted caps list
    uint256 listSpot;
    listSpot = self.capsList.getSortedSpot(_listPredict,_personalCap,NEXT);
    self.capsList.insert(listSpot,_personalCap,PREV);

    // add the cap to the address caps mapping
    self.personalCaps[msg.sender] = _personalCap;

    // add the bidders address to the array of addresses that have submitted at the same cap
    self.capAddresses[_personalCap].push(msg.sender);

    LogBidAccepted(msg.sender, _amount-remainder, _personalCap);

    autoWithdrawBids(self);
  }


  /// @dev Called when an address wants to manually withdraw their bid from the sale. puts their wei in the LeftoverWei mapping
  /// @return true on succesful withdrawl
  function withdrawBid(InteractiveCrowdsaleStorage storage self) public returns (bool) {
  	// The sender has to have already bid on the sale
  	require(self.personalCaps[msg.sender] > 0);
  	// cannot withdraw after compulsory withdraw period is over
  	require(now < self.endWithdrawlTime);

  	// Removing the entry from the linked list returns the key of the removed entry, so make sure that was succesful
  	assert(self.capsList.remove(self.personalCaps[msg.sender]) == self.personalCaps[msg.sender]);

  	// Put the sender's contributed wei into the leftoverWei mapping for later withdrawl
  	self.base.leftoverWei[msg.sender] = self.base.hasContributed[msg.sender];

  	// subtract the bid from the balance of the owner
  	self.base.ownerBalance -= self.base.hasContributed[msg.sender];

  	// return bought tokens to the owners pool and remove tokens from the bidders pool
  	self.base.withdrawTokensMap[self.base.owner] += self.base.withdrawTokensMap[msg.sender];
  	self.base.withdrawTokensMap[msg.sender] = 0;

  	for (uint256 i = 0; i < self.capAddresses[self.personalCaps[msg.sender]].length; i++ ) {
  		if ( self.capAddresses[self.personalCaps[msg.sender]][i] == msg.sender) {
  			self.capAddresses[self.personalCaps[msg.sender]][i] = 0;
  		}
  	}

	LogBidWithdrawn(msg.sender, self.base.hasContributed[msg.sender], self.personalCaps[msg.sender]);  	

	// reset the bidder's contribution and personal cap to zero
	self.base.hasContributed[msg.sender] = 0;
	self.personalCaps[msg.sender] = 0;
  }

  /// @dev function that automatically removes bids that have personal caps lower than the total sale valuation
  /// @return true when all withdrawls have succeeded
  function autoWithdrawBids(InteractiveCrowdsaleStorage storage self) internal returns (bool) {
  	
  	while (self.capsList.getAdjacent(HEAD,NEXT) < self.base.ownerBalance) {
	  	uint256 lowestCap = self.capsList.getAdjacent(HEAD,NEXT);
	  	uint256 contributionSum;
	  	uint256 numAddresses;

	  	for (uint256 i = 0; i < self.capAddresses[lowestCap].length; i++ ) {
	  		if (self.capAddresses[lowestCap][i] != 0) {
	  			contributionSum += self.base.hasContributed[self.capAddresses[lowestCap][i]];
	  			numAddresses++;
	  		}
	  	}

	  	if ((self.base.ownerBalance - contributionSum) >= lowestCap) {
	  		for (i = 0; i < self.capAddresses[lowestCap].length; i++ ) {
	  			if (self.capAddresses[lowestCap][i] != 0) {

		  			self.base.leftoverWei[self.capAddresses[lowestCap][i]] = self.base.hasContributed[self.capAddresses[lowestCap][i]];
		  			
		  			// subtract the bid from the balance of the owner
		  			self.base.ownerBalance -= self.base.hasContributed[self.capAddresses[lowestCap][i]];

		  			// return bought tokens to the owners pool and remove tokens from the bidders pool
		  			self.base.withdrawTokensMap[self.base.owner] += self.base.withdrawTokensMap[self.capAddresses[lowestCap][i]];
		  			self.base.withdrawTokensMap[self.capAddresses[lowestCap][i]] = 0;

		  			// reset the bidder's contribution and personal cap to zero
					self.base.hasContributed[self.capAddresses[lowestCap][i]] = 0;
					self.personalCaps[self.capAddresses[lowestCap][i]] = 0;

					// remove the address from the records and remove the minimal cap from the list
		  			self.capAddresses[lowestCap][i] = 0;
		  			self.capsList.remove(lowestCap);
		  		}
	  		}
	  	} else {
	  		uint256 q;

	  		// calculate the fraction of each minimal valuation bidders ether and tokens to refund
	  		q = (self.base.ownerBalance*100 - lowestCap*100)/(contributionSum);

	  		for (i = 0; i < self.capAddresses[lowestCap].length; i++ ) {
	  			if (self.capAddresses[lowestCap][i] != 0) {
	  				// calculate the portion that this address has to take out of their bid
	  				uint256 refundAmount = (q*self.base.hasContributed[self.capAddresses[lowestCap][i]])/100;
	  				
	  				// subtract that amount from the total valuation
	  				self.base.ownerBalance -= refundAmount;

	  				// refund that amount of wei to the address
	  				self.base.leftoverWei[self.capAddresses[lowestCap][i]] += refundAmount;

	  				// subtract that amount the address' contribution
	  				self.base.hasContributed[self.capAddresses[lowestCap][i]] -= refundAmount;

	  				// calculate the amount of tokens left after the refund
	  				self.base.withdrawTokensMap[self.base.owner] += (q*(self.base.withdrawTokensMap[self.capAddresses[lowestCap][i]]))/100;
	  				self.base.withdrawTokensMap[self.capAddresses[lowestCap][i]] = ((100-q)*(self.base.withdrawTokensMap[self.capAddresses[lowestCap][i]]))/100;
	  			}
	  		}
	  	}
	}
  }




   /*Functions "inherited" from CrowdsaleLib library*/

  function setTokenExchangeRate(InteractiveCrowdsaleStorage storage self, uint256 _exchangeRate) returns (bool) {
    return self.base.setTokenExchangeRate(_exchangeRate);
  }

  function setTokens(InteractiveCrowdsaleStorage storage self) returns (bool) {
    return self.base.setTokens();
  }

  function withdrawTokens(InteractiveCrowdsaleStorage storage self) returns (bool) {
  	require(now > self.base.endTime);

    return self.base.withdrawTokens();
  }

  function withdrawLeftoverWei(InteractiveCrowdsaleStorage storage self) returns (bool) {
    return self.base.withdrawLeftoverWei();
  }

  function withdrawOwnerEth(InteractiveCrowdsaleStorage storage self) returns (bool) {
    return self.base.withdrawOwnerEth();
  }

  function crowdsaleActive(InteractiveCrowdsaleStorage storage self) constant returns (bool) {
    return self.base.crowdsaleActive();
  }

  function crowdsaleEnded(InteractiveCrowdsaleStorage storage self) constant returns (bool) {
    return self.base.crowdsaleEnded();
  }

  function validPurchase(InteractiveCrowdsaleStorage storage self) constant returns (bool) {
    return self.base.validPurchase();
  }
}
