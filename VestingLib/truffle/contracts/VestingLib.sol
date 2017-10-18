pragma solidity ^0.4.15;

/**
 * @title VestingLib
 * @author Majoolr.io
 *
 * version 1.0.0
 * Copyright (c) 2017 Majoolr, LLC
 * The MIT License (MIT)
 * https://github.com/Majoolr/ethereum-libraries/blob/master/LICENSE
 *
 * Library for vesting tokens to a group of addresses.  The library only handles
 * one token at a time, with a linear vesting schedule for a set period of time
 *
 * Majoolr works on open source projects in the Ethereum community with the
 * purpose of testing, documenting, and deploying reusable code onto the
 * blockchain to improve security and usability of smart contracts. Majoolr
 * also strives to educate non-profits, schools, and other community members
 * about the application of blockchain technology.
 * For further information: majoolr.io, aragon.one
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
import "./CrowdsaleToken.sol";

library VestingLib {
  using BasicMathLib for uint256;

  struct VestingStorage {
    address owner;

    uint256 totalSupply;     // total supply of ETH or tokens
    uint256 contractBalace;  // current balance of the contract
    bool isToken;            // false for ETH, true for token

    uint256 startTime;       // timestamp when vesting starts
    uint256 endTime;         // timestamp when vesting is complete

    uint256 numRegistered;   // number of addresses registered for the vesting

    uint256 timeInterval;    // interval between vesting 
    uint256 percentReleased; // percentage of the total released every interval

    mapping (address => bool) isRegistered;   // indicates if a address is registered in the system

    mapping (address => uint256) hasWithdrawn;   // shows how much an address has already withdrawn from the vesting contract
  }

  // Generic Error message, error code and string
  event LogErrorMsg(uint256 amount, string Msg);

  // Logs when a user is registered in the system for vesting
  event LogUserRegistered(address registrant);

  // Logs when a user is unregistered from the system
  event LogUserUnRegistered(address registrant);

  // Logs when a user replaces themselves with a different beneficiary
  event LogRegistrationReplaced(address currentRegistrant, address newRegistrant, uint256 amountWithdrawn);

  // Logs when a user withdraws their ETH from vesting
  event LogETHWithdrawn(address beneficiary, uint256 amount);

  // Logs when a user withdraws their tokens from the contract
  event LogTokensWithdrawn(address beneficiary, uint256 amount);

  /// @dev Called by the token vesting contract upon creation.
  /// @param self Stored token from token contract
  /// @param _owner the owner of the vesting contract
  /// @param _isToken indicates if the vesting is for tokens or ETH
  /// @param _startTime the start time of the vesting (UNIX timestamp)
  /// @param _endTime the end time of the vesting     (UNIX timestamp)
  /// @param _numReleases number of times during vesting that the contract releases coins
  function init(VestingStorage storage self,
                address _owner,
                bool _isToken,
                uint256 _startTime,
                uint256 _endTime,
                uint256 _numReleases)
  {
    require(self.owner == 0);
    require(self.totalSupply == 0);
    require(_owner != 0);
    require(_startTime > now);
    require(_endTime > _startTime);
    require(_numReleases > 0);
    require(100%_numReleases == 0);      // needs to divide to an whole number percentage

    self.owner = _owner;
    self.isToken = _isToken;
    self.startTime = _startTime;
    self.endTime = _endTime;
    self.timeInterval = (_endTime - _startTime)/_numReleases;
    self.percentReleased = 100/_numReleases;
  }

  /// @dev function owner has to call before the sale starts to initialize the ETH balance of the contract.
  /// @param self Stored vesting from vesting contract
  /// @param _balance the balance that is being vested.  msg.value from the contract call. 
  function initializeETHBalance(VestingStorage storage self, uint256 _balance) internal returns (bool) {
    require(msg.sender == self.owner);
    require(now < self.startTime);
    require(_balance != 0);
    require(!self.isToken);
    require(self.totalSupply == 0);

    self.totalSupply = _balance;
    self.contractBalace = _balance;

    return true;
  }

  /// @dev function owner has to call before the sale starts to initialize the token balance of the contract.
  /// @param self Stored vesting from vesting contract
  /// @param _balance the balance that is being vested.  owner has to have sent tokens to the contract before calling this function
  function initializeTokenBalance(VestingStorage storage self, CrowdsaleToken token, uint256 _balance) internal returns (bool) {
    require(msg.sender == self.owner);
    require(now < self.startTime);
    require(_balance != 0);
    require(self.isToken);
    require(token.balanceOf(this) == _balance);
    require(self.totalSupply == 0);

    self.totalSupply = _balance;
    self.contractBalace = _balance;

    return true;
  }

  /// @dev register user function. can only be called by the owner
  /// puts their address in the registered mapping and increments the numRegistered
  /// @param self Stored vesting from vesting contract
  /// @param _registrant address to be registered for the vesting
  function registerUser(VestingStorage storage self, address _registrant) internal returns (bool) {
    require((msg.sender == self.owner) || (msg.sender == address(this)));
    // if the change interval is 0, then registration is allowed throughout the vesting since a cap doesn't need to be calculated
    if (now >= self.startTime - 1 days) {
      LogErrorMsg(0,"Can only register users earlier than 1 day before the vesting!");
      return false;
    }
    if(self.isRegistered[_registrant]) {
      LogErrorMsg(0,"Registrant address is already registered for the vesting!");
      return false;
    }

    uint256 result;
    bool err;

    self.isRegistered[_registrant] = true;
    (err,result) = self.numRegistered.plus(1);
    require(!err);
    self.numRegistered = result;

    LogUserRegistered(_registrant);

    return true;
  }

  /// @dev registers multiple users at the same time
  /// @param self Stored vesting from vesting contract
  /// @param _registrants addresses to register for the vesting
  function registerUsers(VestingStorage storage self, address[] _registrants) internal returns (bool) {
    require(msg.sender == self.owner);
    bool ok;

    for (uint256 i = 0; i < _registrants.length; i++) {
      ok = registerUser(self,_registrants[i]);
    }
    return ok;
  }

  /// @dev Cancels a user's registration status can only be called by the owner when a user cancels their registration.
  /// sets their address field in the registered mapping to false and decrements the numRegistered
  /// @param self Stored vesting from vesting contract
  function unregisterUser(VestingStorage storage self, address _registrant) internal returns (bool) {
    require((msg.sender == self.owner) || (msg.sender == address(this)));
    if (now >= self.startTime - 1 days) {
      LogErrorMsg(0, "Can only register and unregister users earlier than 1 days before the vesting!");
      return false;
    }
    if(!self.isRegistered[_registrant]) {
      LogErrorMsg(0, "Registrant address not registered for the vesting!");
      return false;
    }

    uint256 result;
    bool err;

    self.isRegistered[_registrant] = false;
    (err,result) = self.numRegistered.minus(1);
    require(!err);
    self.numRegistered = result;

    LogUserUnRegistered(_registrant);

    return true;
  }

  /// @dev unregisters multiple users at the same time
  /// @param self Stored vesting from vesting contract
  /// @param _registrants addresses to unregister for the vesting
  function unregisterUsers(VestingStorage storage self, address[] _registrants) internal returns (bool) {
    require(msg.sender == self.owner);
    bool ok;

    for (uint256 i = 0; i < _registrants.length; i++) {
      ok = unregisterUser(self,_registrants[i]);
    }
    return ok;
  }

  /// @dev allows a participant to replace themselves in the vesting schedule with a new address
  /// @param self Stored vesting from vesting contract
  /// @param _replacementRegistrant new address to replace the caller with
  function swapRegistration(VestingStorage storage self, address _replacementRegistrant) internal returns (bool) {
    require(self.isRegistered[msg.sender]);
    require(!self.isRegistered[_replacementRegistrant]);
    require(_replacementRegistrant != 0);

    self.isRegistered[_replacementRegistrant] = true;

    self.hasWithdrawn[_replacementRegistrant] = self.hasWithdrawn[msg.sender];

    self.isRegistered[msg.sender] = false;

    LogRegistrationReplaced(msg.sender, _replacementRegistrant, self.hasWithdrawn[_replacementRegistrant]);

    return true;

  }

  /// @dev calculates the number of tokens or ETH available for the sender to withdraw
  /// @param self Stored vesting from vesting contract
  /// @param _beneficiary the sender, who will be withdrawing their balance
  function calculateWithdrawal(VestingStorage storage self, address _beneficiary) internal returns (uint256) {
    require(_beneficiary != 0);

    // figure out how many intervals have passed since the start
    uint256 numIntervals = (now-self.startTime)/self.timeInterval;

    // multiply that by the percentage released every interval
    // calculate the amount of ETH released in total by this time
    uint256 totalETHReleased = (numIntervals*self.percentReleased)*self.totalSupply/100;

    // divide that by the number of registered addresses to find the total amount available to withdraw per user from the beginning of the vesting
    // subtract what has already been withdrawn from that amount to get the amount available to withdraw right now
    uint256 userWithdrawlAmount = (totalETHReleased/self.numRegistered) - self.hasWithdrawn[_beneficiary];

    return userWithdrawlAmount;
  }

  /// @dev allows participants to withdraw their vested ETH
  /// @param self Stored vesting from vesting contract
  function withdrawETH(VestingStorage storage self) internal returns (bool) {
    require(now > self.startTime && now < self.endTime);
    require(self.isRegistered[msg.sender]);
    require(!self.isToken);

    // calculate the amount of ETH that is available to withdraw right now
    uint256 amount = calculateWithdrawal(self, msg.sender);
    require(amount > 0);

    // update the amount that the sender has withdrawn
    self.hasWithdrawn[msg.sender] += amount;

    // subtract the withdrawl from the contract's balance
    uint256 newBalance;
    bool err;
    (err,newBalance) = self.contractBalace.minus(amount);
    require(!err);

    self.contractBalace = newBalance;

    // transfer ETH to the sender
    msg.sender.transfer(amount);

    LogETHWithdrawn(msg.sender,amount);

  }

  /// @dev allows participants to withdraw their vested tokens
  /// @param self Stored vesting from vesting contract
  /// @param token the token contract that is being withdrawn
  function withdrawTokens(VestingStorage storage self,CrowdsaleToken token) internal returns (bool) {
    require(now > self.startTime && now < self.endTime);
    require(self.isRegistered[msg.sender]);
    require(self.isToken);

    // calculate the amount of ETH that is available to withdraw right now
    uint256 amount = calculateWithdrawal(self, msg.sender);
    require(amount > 0);

    // update the amount that the sender has withdrawn
    self.hasWithdrawn[msg.sender] += amount;

    // subtract the withdrawl from the contract's balance
    uint256 newBalance;
    bool err;
    (err,newBalance) = self.contractBalace.minus(amount);
    require(!err);

    self.contractBalace = newBalance;

    // transfer tokens to the sender
    bool ok = token.transfer(msg.sender,amount);
    require(ok);

    LogTokensWithdrawn(msg.sender,amount);

  }

}