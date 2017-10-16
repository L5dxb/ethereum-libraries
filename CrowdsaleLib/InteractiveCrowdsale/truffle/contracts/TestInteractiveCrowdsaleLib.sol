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
import "./TestCrowdsaleLib.sol";
import "./LinkedListLib.sol";

library TestInteractiveCrowdsaleLib {
  using BasicMathLib for uint256;
  using LinkedListLib for LinkedListLib.LinkedList;
  using TestCrowdsaleLib for TestCrowdsaleLib.CrowdsaleStorage;

  uint256 constant NULL = 0;
  uint256 constant HEAD = 0;
  bool constant PREV = false;
  bool constant NEXT = true;

  struct InteractiveCrowdsaleStorage {

  	TestCrowdsaleLib.CrowdsaleStorage base; // base storage from CrowdsaleLib

  	// List of personal valuations, sorted from smallest to largest (from LinkedListLib)
  	LinkedListLib.LinkedList valuationsList;

  	uint256 endWithdrawlTime;   // time when manual withdrawls are no longer allowed

  	mapping (address => uint256) personalValuations;    // the valuation that each address has submitted

  	mapping (uint256 => address[]) valuationAddresses;  // each address that has submitted at a certain valuation

  }

  // Indicates when a bidder submits a bid to the crowdsale
  event LogBidAccepted(address indexed bidder, uint256 amount, uint256 personalValuation);

  // Indicates when a bidder manually withdraws their bid from the crowdsale
  event LogBidWithdrawn(address indexed bidder, uint256 amount, uint256 personalValuation);

  // Indicates when a bid is removed by the automated bid removal process
  event LogBidRemoved(address indexed bidder, uint256 personalValuation);

  // Generic Error Msg Event
  event LogErrorMsg(uint256 amount, string Msg);

  // Indicates when the price of the token changes
  event LogTokenPriceChange(uint256 amount, string Msg);


  /// @dev Called by a crowdsale contract upon creation.
  /// @param self Stored crowdsale from crowdsale contract
  /// @param _owner Address of crowdsale owner
  /// @param _saleData Array of 3 item arrays such that, in each 3 element
  /// array index-0 is timestamp, index-1 is price in cents at that time
  /// index-2 is address purchase valuation at that time, 0 if no address valuation
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

    require(_endWithdrawlTime < _endTime);
  	self.endWithdrawlTime = _endWithdrawlTime;
  }

  /// @dev Called when an address wants to submit bid to the sale
  /// @param self Stored crowdsale from crowdsale contract
  /// @param _amount amound of wei that the buyer is sending
  /// @param _personalValuation the total crowdsale valuation (wei) that the bidder is comfortable with
  /// @param _listPredict prediction of where the valuation will go in the linked list
  /// @return true on succesful bid
  function submitBid(InteractiveCrowdsaleStorage storage self, uint256 _amount, uint256 _personalValuation, uint256 _listPredict, uint256 _currtime) returns (bool) {
  	require(msg.sender != self.base.owner);
  	require(self.base.validPurchase(_currtime));
  	require(self.personalValuations[msg.sender] == 0);   // bidder can't have already bid
  	require(_personalValuation >= self.base.ownerBalance + _amount);    // The personal valuation submitted must be greater than the current valuation plus the bid
  	require((_personalValuation % 100000000000000000000) == 0);      // personal valuations need to be in multiples of 100 ETH
    //require(self.valuationsList.getAdjacent(_listPredict,NEXT) != 0);  // prediction must already be an entry in the list

  	require((self.base.ownerBalance + _amount) <= self.base.capAmount);  // bid must not exceed the total raise cap of the sale

  	// if the token price increase interval has passed, update the current day and change the token price
  	if ((self.base.milestoneTimes.length > self.base.currentMilestone + 1) &&
        (_currtime > self.base.milestoneTimes[self.base.currentMilestone + 1]))
    {
        while((self.base.milestoneTimes.length > self.base.currentMilestone + 1) &&
              (_currtime > self.base.milestoneTimes[self.base.currentMilestone + 1]))
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
      remainder = result % zeros;     // extra wei leftover from the division
    } else {
      zeros = 10**(uint256(self.base.tokenDecimals)-18);
      numTokens = result*zeros;
    }

    // add the division's leftoverWei to the bidders available wei to withdraw
    self.base.leftoverWei[msg.sender] += remainder;

    // add the bid to bidder's contribution amount.  can't overflow because it is under the cap
    self.base.hasContributed[msg.sender] += _amount-remainder;

    // make sure there are enough tokens available to satisfy the bid
    require(numTokens <= self.base.withdrawTokensMap[self.base.owner]);

    // calculate the amout of ether in the owners balance and "deposit" it
    self.base.ownerBalance = self.base.ownerBalance + (_amount - remainder);

    // add tokens to the bidders purchase.  can't overflow because it will be under the cap
    self.base.withdrawTokensMap[msg.sender] += numTokens;

    //subtract tokens from owner's share
    (err,remainder) = self.base.withdrawTokensMap[self.base.owner].minus(numTokens);
    require(!err);
    self.base.withdrawTokensMap[self.base.owner] = remainder;

    // add the bid to the sorted valuations list
    uint256 listSpot;
    listSpot = self.valuationsList.getSortedSpot(_listPredict,_personalValuation,NEXT);
    LogErrorMsg(listSpot, "SPOT");

    self.valuationsList.insert(listSpot,_personalValuation,PREV);

    // add the valuation to the address => valuations mapping
    self.personalValuations[msg.sender] = _personalValuation;

    // add the bidders address to the array of addresses that have submitted at the same valuation
    self.valuationAddresses[_personalValuation].push(msg.sender);

    LogBidAccepted(msg.sender, _amount-remainder, _personalValuation);

    autoWithdrawBids(self);    // run algorithm to remove bids with minimal personal Valuations
  }


  /// @dev Called when an address wants to manually withdraw their bid from the sale. puts their wei in the LeftoverWei mapping
  /// @return true on succesful withdrawl
  function withdrawBid(InteractiveCrowdsaleStorage storage self, uint256 _currtime) public returns (bool) {
  	// The sender has to have already bid on the sale
  	require(self.personalValuations[msg.sender] > 0);
  	// cannot withdraw after compulsory withdraw period is over
  	require(_currtime < self.endWithdrawlTime);

  	// Removing the entry from the linked list returns the key of the removed entry, so make sure that was succesful
  	assert(self.valuationsList.remove(self.personalValuations[msg.sender]) == self.personalValuations[msg.sender]);

  	// Put the sender's contributed wei into the leftoverWei mapping for later withdrawl
  	self.base.leftoverWei[msg.sender] += self.base.hasContributed[msg.sender];

  	// subtract the bid from the balance of the owner
  	self.base.ownerBalance -= self.base.hasContributed[msg.sender];

  	// return bought tokens to the owners pool and remove tokens from the bidders pool
  	self.base.withdrawTokensMap[self.base.owner] += self.base.withdrawTokensMap[msg.sender];
  	self.base.withdrawTokensMap[msg.sender] = 0;

    // iterate through the array of addresses at a certain valuation and remove the bidder's address who is withdrawing their bid
  	for (uint256 i = 0; i < self.valuationAddresses[self.personalValuations[msg.sender]].length; i++ ) {
  		if ( self.valuationAddresses[self.personalValuations[msg.sender]][i] == msg.sender) {
  			self.valuationAddresses[self.personalValuations[msg.sender]][i] = 0;
  		}
  	}

	  LogBidWithdrawn(msg.sender, self.base.hasContributed[msg.sender], self.personalValuations[msg.sender]);

	  // reset the bidder's contribution and personal valuation to zero
	  self.base.hasContributed[msg.sender] = 0;
	  self.personalValuations[msg.sender] = 0;
  }

  /// @dev function that automatically removes bids that have personal valuations lower than the total sale valuation
  /// @return true when all withdrawls have succeeded
  function autoWithdrawBids(InteractiveCrowdsaleStorage storage self) internal returns (bool) {
  	
  	while (self.valuationsList.getAdjacent(HEAD,NEXT) < self.base.ownerBalance) {
      // the first entry in the personal valuations list is the smallest
	  	uint256 lowestValuation = self.valuationsList.getAdjacent(HEAD,NEXT);
	  	uint256 contributionSum;  // sum of all contributions at the lowest valuation
	  	uint256 numAddresses;     // total addresses who have submitted at that valuation
      address refundAddress;    // used in the loop to indicate the current address being refunded

      // calculate the sum of all contributions at a valuation and the number of bidders who have submitted at that valuation
	  	for (uint256 i = 0; i < self.valuationAddresses[lowestValuation].length; i++ ) {
	  		if (self.valuationAddresses[lowestValuation][i] != 0) {
	  			contributionSum += self.base.hasContributed[self.valuationAddresses[lowestValuation][i]];
	  			numAddresses++;
	  		}
	  	}

      // If removing all those bids still doesn't cause the total valuation to drop below the lowest valuation, remove all the bids and repeat
	  	if ((self.base.ownerBalance - contributionSum) >= lowestValuation) {
        // iterate through all the addresses at the lowest valuation and remove their bids
	  		for (i = 0; i < self.valuationAddresses[lowestValuation].length; i++ ) {
          // if an entry in the address array is 0, it means it was already removed, so only remove active addresses
	  			if (self.valuationAddresses[lowestValuation][i] != 0) {
            refundAddress = self.valuationAddresses[lowestValuation][i];  // current bidder being withdrawn and refunded

            // refund the bidder's contribution
		  			self.base.leftoverWei[refundAddress] += self.base.hasContributed[refundAddress];
		  			
		  			// subtract the bid from the balance of the owner (total valuation)
		  			self.base.ownerBalance -= self.base.hasContributed[refundAddress];

		  			// return bought tokens to the owners pool and remove tokens from the bidders pool
		  			self.base.withdrawTokensMap[self.base.owner] += self.base.withdrawTokensMap[refundAddress];
		  			self.base.withdrawTokensMap[refundAddress] = 0;

		  			// reset the bidder's contribution and personal valuation to zero
					  self.base.hasContributed[refundAddress] = 0;
					  self.personalValuations[refundAddress] = 0;

					  // remove the address from the records and remove the minimal valuation from the list
		  			self.valuationAddresses[lowestValuation][i] = 0;
		  			require(self.valuationsList.remove(lowestValuation) != 0);

            LogBidRemoved(refundAddress, lowestValuation);
		  		}
	  		}
	  	} else {
	  		uint256 q;

	  		// calculate the fraction of each minimal valuation bidders ether and tokens to refund
	  		q = (self.base.ownerBalance*100 - lowestValuation*100)/(contributionSum);

        // iterate through the addresses who have contributed at that valuation and refund them the correct proportion of their bid to get the lowest valuation greater than the total valuation
	  		for (i = 0; i < self.valuationAddresses[lowestValuation].length; i++ ) {
	  			if (self.valuationAddresses[lowestValuation][i] != 0) {
            refundAddress = self.valuationAddresses[lowestValuation][i];
	  				// calculate the portion that this address has to take out of their bid
	  				uint256 refundAmount = (q*self.base.hasContributed[refundAddress])/100;
	  				
	  				// subtract that amount from the total valuation
	  				self.base.ownerBalance -= refundAmount;

	  				// refund that amount of wei to the address
	  				self.base.leftoverWei[refundAddress] += refundAmount;

	  				// subtract that amount the address' contribution
	  				self.base.hasContributed[refundAddress] -= refundAmount;

	  				// calculate the amount of tokens left after the refund
	  				self.base.withdrawTokensMap[self.base.owner] += (q*(self.base.withdrawTokensMap[refundAddress]))/100;
	  				self.base.withdrawTokensMap[refundAddress] = ((100-q)*(self.base.withdrawTokensMap[refundAddress]))/100;
	  			}
	  		}
	  	}
	  }
    return true;
  }




   /*Functions "inherited" from CrowdsaleLib library*/

  function setTokenExchangeRate(InteractiveCrowdsaleStorage storage self, uint256 _exchangeRate, uint256 _currtime) returns (bool) {
    return self.base.setTokenExchangeRate(_exchangeRate, _currtime);
  }

  function setTokens(InteractiveCrowdsaleStorage storage self) internal returns (bool) {
    return self.base.setTokens();
  }

  function withdrawTokens(InteractiveCrowdsaleStorage storage self, uint256 _currtime) internal returns (bool) {
  	require(_currtime > self.base.endTime);

    return self.base.withdrawTokens(_currtime);
  }

  function withdrawLeftoverWei(InteractiveCrowdsaleStorage storage self) internal returns (bool) {
    return self.base.withdrawLeftoverWei();
  }

  function withdrawOwnerEth(InteractiveCrowdsaleStorage storage self, uint256 _currtime) internal returns (bool) {
    return self.base.withdrawOwnerEth(_currtime);
  }

  function crowdsaleActive(InteractiveCrowdsaleStorage storage self, uint256 _currtime) internal constant returns (bool) {
    return self.base.crowdsaleActive(_currtime);
  }

  function crowdsaleEnded(InteractiveCrowdsaleStorage storage self, uint256 _currtime) internal constant returns (bool) {
    return self.base.crowdsaleEnded(_currtime);
  }

  function getPersonalValuation(InteractiveCrowdsaleStorage storage self, address _bidder) internal constant returns (uint256) {
    return self.personalValuations[_bidder];
  }

  function isBidderAtValuation(InteractiveCrowdsaleStorage storage self, uint256 _valuation, address _bidder) internal constant returns (bool) {
    for (uint256 i = 0; i < self.valuationAddresses[_valuation].length; i++) {
      if (self.valuationAddresses[_valuation][i] == _bidder) {
        return true;
      }
    }

    return false;
  }

  function isValuationInList(InteractiveCrowdsaleStorage storage self, uint256 _valuation) internal constant returns (bool) {
    return self.valuationsList.nodeExists(_valuation);
  }

  function getSizeOfValuations(InteractiveCrowdsaleStorage storage self) internal constant returns (uint256) {
    return self.valuationsList.sizeOf();
  }

  function getSaleData(InteractiveCrowdsaleStorage storage self, uint256 _timestamp) internal constant returns (uint256[3]) {
    return self.base.getSaleData(_timestamp);
  }

  function getTokensSold(InteractiveCrowdsaleStorage storage self) internal constant returns (uint256) {
    return self.base.getTokensSold();
  }

}
