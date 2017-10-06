pragma solidity ^0.4.15;

/****************
*
*  Test contract for tesing libraries on networks
*
*****************/

import "./InteractiveCrowdsaleLib.sol";
import "./CrowdsaleToken.sol";

contract InteractiveCrowdsaleTestContract {
  using InteractiveCrowdsaleLib for InteractiveCrowdsaleLib.InteractiveCrowdsaleStorage;

  InteractiveCrowdsaleLib.InteractiveCrowdsaleStorage sale;

  function InteractiveCrowdsaleTestContract(
    address owner,
    uint256[] saleData,
    uint256 fallbackExchangeRate,
    uint256 capAmountInCents,
    uint256 endWithdrawlTime,
    uint256 endTime,
    uint8 percentBurn,
    CrowdsaleToken token)
  {
  	sale.init(owner, saleData, fallbackExchangeRate, capAmountInCents, endWithdrawlTime, endTime, percentBurn, token);
  }

  // fallback function can be used to buy tokens
  function () payable {
    //receivePurchase();
  }

  // function receivePurchase() payable returns (bool) {
  // 	return sale.receivePurchase(msg.value);
  // }

  // function registerUser(address _registrant) returns (bool) {
  //   return sale.registerUser(_registrant);
  // }

  // function registerUsers(address[] _registrants) returns (bool) {
  //   return sale.registerUsers(_registrants);
  // }

  // function unregisterUser(address _registrant) returns (bool) {
  //   return sale.unregisterUser(_registrant);
  // }

  // function unregisterUsers(address _registrants) returns (bool) {
  //   return sale.unregisterUser(_registrants);
  // }

  // function isRegistered(address _registrant) constant returns (bool) {
  //   return sale.isRegistered[_registrant];
  // }

  function withdrawTokens() returns (bool) {
    return sale.withdrawTokens();
  }

  function withdrawLeftoverWei() returns (bool) {
    return sale.withdrawLeftoverWei();
  }

  function withdrawOwnerEth() returns (bool) {
  	return sale.withdrawOwnerEth();
  }

  function crowdsaleActive() constant returns (bool) {
  	return sale.crowdsaleActive();
  }

  function crowdsaleEnded() constant returns (bool) {
  	return sale.crowdsaleEnded();
  }

  function setTokenExchangeRate(uint256 _exchangeRate) returns (bool) {
    return sale.setTokenExchangeRate(_exchangeRate);
  }

  function setTokens() returns (bool) {
    return sale.setTokens();
  }

  function getOwner() constant returns (address) {
    return sale.base.owner;
  }

  function getTokensPerEth() constant returns (uint256) {
    return sale.base.tokensPerEth;
  }

  function getExchangeRate() constant returns (uint256) {
    return sale.base.exchangeRate;
  }

  function getCapAmount() constant returns (uint256) {
    return sale.base.capAmount;
  }

  function getStartTime() constant returns (uint256) {
    return sale.base.startTime;
  }

  function getEndTime() constant returns (uint256) {
    return sale.base.endTime;
  }

  function getEthRaised() constant returns (uint256) {
    return sale.base.ownerBalance;
  }

  function getContribution(address _buyer) constant returns (uint256) {
    return sale.base.hasContributed[_buyer];
  }

  function getTokenPurchase(address _buyer) constant returns (uint256) {
    return sale.base.withdrawTokensMap[_buyer];
  }

  function getLeftoverWei(address _buyer) constant returns (uint256) {
    return sale.base.leftoverWei[_buyer];
  }

  // function getSaleData(uint256 timestamp) constant returns (uint256[3]) {
  //   return sale.getSaleData(timestamp);
  // }

  // function getTokensSold() constant returns (uint256) {
  //   return sale.getTokensSold();
  // }

  function getPercentBurn() constant returns (uint256) {
    return sale.base.percentBurn;
  }

  // function getAddressCap() constant returns (uint256) {
  //   return sale.addressCap;
  // }

  // function getNumRegistered() constant returns (uint256) {
  //   return sale.numRegistered;
  // }
}
