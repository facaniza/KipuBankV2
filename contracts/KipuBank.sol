// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

    /// @title KipuBank - A blockchain Bank
    /// @author Facundo Alejandro Caniza

/// @notice OpenZeppeling imports
/// @dev Must be imported ReentrancyGuard, IERC20, SafeIERC, Ownable, Pausable and AccesControl
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/// @notice ChainLink Interface import
/// @dev We use data feeds interface
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract KipuBank is ReentrancyGuard, Ownable, Pausable, AccessControl {

    /// @notice Pauser contract rol
    bytes32 public constant PAUSER = keccak256("PAUSER");

    /// @notice Data feeds manager rol
    bytes32 public constant FEED_MANAGER = keccak256("FEED_MANAGER");

    /// @notice Public interface data feeds
    /// @dev We use data feeds of ChainkLink
    AggregatorV3Interface public s_feed;

    /// @notice ERC20 Token address
    /// @dev USDC specific token
    IERC20 immutable i_usdc;    

    /// @notice SafeERC20 interface it is used to expand safe funcionality for IERC20
    /// @dev Expand safe funcionality for IERC20
    using SafeERC20 for IERC20;

    /// @notice Data feed constant refresh for data feed
    /// @dev By convention we use 3600
    uint16 constant HEARTBEAT = 3600;

    /// @notice Conversion decimals constant
    /// @dev We do the sum of ethereum decimals y chainlink decimals, then we substraction of the USDC decimals, it gave us the basis for equalization
    uint constant DECIMAL_FACTOR = 1 * 10 ** 20;

    /// @notice Fixed Transaction threshold 
    uint immutable i_threshold;

    /// @notice Global deposit limite
    /// @dev Keep in mind, global limit will be in USD
    uint immutable i_bankCap;

    ///@notice Total Ether deposited
    /// @dev Total of the contract it is counted in USD
    uint private s_totalContract = 0;

    /// @notice Minimum deposit of Ether to the contract
    /// @dev Will use 1 Gwei as minimun
    uint public constant MIN_DEPOSIT = 1 gwei;

    /// @notice Deposits contract counter
    /// @notice Deposits count toward the contract
    uint128 private s_deposits = 0;

    /// @notice Withdrawal contract counter
    /// @notice Withdrawal count for the contract
    uint128 private s_withdrawal = 0;    

    /// @notice Storage struct that stores a token amount, in different tokens, for each address
    /// @dev In the first mapping we have token address, in the nested mapping we have the holder and their balance
    mapping (address token => mapping (address holder => uint amount)) private s_balances;

    /// @notice Successful deposit made event
    /// @param holder Holder who made the deposit
    /// @param amount The Deposited amount
    event KipuBank_SuccessfulDeposit(address indexed holder, uint amount);

    /// @notice Successful withdrawal made
    /// @param holder The holder who perfomed the withdrawal
    /// @param amount The amount withdrawn
    event KipuBank_SuccessfulWithdrawal(address indexed holder, uint amount);

    /// @notice Feed update event
    /// @param previousFeed Was the previous feed address
    /// @param newFeed The new feed address
    event KipuBank_FeedUpdated(address indexed previousFeed, address indexed newFeed);

    /// @notice Contract pause event
    /// @param pauser The address that paused the contract
    /// @param time The timestamp when was paused
    event KipuBank_ContractPaused(address indexed pauser, uint time);

    /// @notice Contract unpaused event
    /// @param unpauser The address that unpaused the contract
    /// @param time The timestamp when was unpaused
    event KipuBank_ContractUnpaused(address indexed unpauser, uint time);

    /// @notice Ownership transfer event
    /// @param previousOwner The previous owner of the contract
    /// @param newOwner The new owner of the contract
    event KipuBank_TransferredOwner( address indexed previousOwner, address indexed newOwner);

    /// @notice Rol granted event
    /// @param account The account that was granted the new role
    /// @param role The role was granted
    event KipuBank_GrantedRole(address indexed account, bytes32 role);

    /// @notice Role revoked event
    /// @param account The account that was revoked the role
    /// @param role The role that revoked
    event KipuBank_RoleRevoked(address indexed account, bytes32 role);

    /// @notice Withdrawal rejected error 
    /// @param holder The holder that perfomed the withdrawal
    /// @param amount The amount to withdraw
    error KipuBank_RejectedWithdraw(address holder, uint amount);

    /// @notice Exceeding limit error
    /// @param amount The amount that exceeded the limite
    error KipuBank_ExceededLimit(uint amount);

    /// @notice Insufficient funds error
    /// @param holder The holder with insufficient funds
    /// @param amount The amount to withdraw
    error KipuBank_InsufficientsFunds(address holder, uint amount);

    /// @notice Threshold exceeded error
    /// @param amount The amount that exceeds the threshold
    error KipuBank_ExceededThreshold(uint amount);

    /// @notice Zero amount error
    /// @param holder The holder who attempted a transaction with zero value
    error KipuBank_ZeroAmount(address holder);

    /// @notice Invalid threshold error
    /// @param threshold The invalid threshold
    error KipuBank_InvalidThreshold(uint threshold);

    /// @notice Invalid limit error
    /// @param limit The limit that is invalid
    error KipuBank_InvalidLimit(uint limit);

    /// @notice Limit above threshold error
    /// @param threshold The attempted threshold of the contract
    /// @param limit The limit of the contract
    error KipuBank_InvalidInit(uint limit, uint threshold);

    /// @notice Operation not permitted error
    /// @param holder The holder who attempted a non-permitted operation
    error KipuBank_NonPermittedOperation(address holder);

    /// @notice Oracle price error
    /// @param price The incorrect price
    error KipuBank_CommittedOracle(uint price);

    /// @notice Outdated price error
    /// @param price The outdate price
    error KipuBank_OutdatedPrice(uint price);

    /// @notice Invalid address set error
    error KipuBank_InvalidAddress();

    /// @notice Invalid data feed address error
    /// @param newFeed The new data feed provider
    error KipuBank_InvalidFeed(address newFeed);

    /// @notice Non-permitted function access error
    /// @param account The account that attempted to access a non-permitted function
    error KipuBank_NonPermittedAccess(address account);

    /// @notice Non-permitted deposit amount
    /// @param amount The exceeded amount
    error KipuBank_NonPermittedAmount(uint amount);

    /// @notice Amount lower than minimum deposit
    /// @param amount The amount that is below the minimum
    error KipuBank_LowerMinimumAmount(uint amount);

    /// @notice Contract constructor
    /// @param _limit The global limit for the contract
    /// @param _threshold The global threshold for the contract
    /// @param _feed The feed address to use
    /// @param _tokenERC20 The address of the ERC20 token to use
    /// @dev They must be generated at the time of deployment
    constructor(
        uint _limit,
        uint _threshold,
        address _owner,
        address _feed,
        address _tokenERC20
        )
        Ownable(_owner) 
    {
        if(_limit == 0) revert KipuBank_InvalidLimit(_limit);
        if(_threshold == 0) revert KipuBank_InvalidThreshold(_threshold);
        if(_threshold > _limit) revert KipuBank_InvalidInit(_limit, _threshold);
        if(_feed == address(0)) revert KipuBank_InvalidAddress();
        if(_tokenERC20 == address(0)) revert KipuBank_InvalidAddress();
        
        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
        _grantRole(PAUSER, _owner);
        _grantRole(FEED_MANAGER, _owner);

        i_usdc = IERC20(_tokenERC20);
        s_feed = AggregatorV3Interface(_feed);
        i_bankCap = _limit;
        i_threshold = _threshold;
    }

    /// @notice The function receive() is not permitted
    /// @dev The contract should not receive Ether
    receive() external payable { revert KipuBank_NonPermittedOperation(msg.sender); }

    /// @notice The function fallback() is not permitted
    /// @dev The contract should not send data with no autorization
    fallback() external payable { revert KipuBank_NonPermittedOperation(msg.sender); }

    /// @notice Modifier to manage function accesss, only role or owner
    /// @param role The role that have permissions
    modifier onlyOwnerORole(bytes32 role) {
        if(owner() != msg.sender && !hasRole(role, msg.sender)) {
            revert KipuBank_NonPermittedAccess(msg.sender);
        }
        _;
    }    

    /// @notice Modifier to verify deposits
    /// @param _amountUSD The amount to verify
    modifier verifyEthDeposit(uint _amountUSD, uint _amountETH) {
        if(_amountETH < MIN_DEPOSIT) revert KipuBank_LowerMinimumAmount(_amountETH);
        if(_amountUSD == 0) revert KipuBank_ZeroAmount(msg.sender);
        if(_amountUSD + s_totalContract > i_bankCap) revert KipuBank_ExceededLimit(_amountUSD);
        _;
    }

    /// @notice Modifier to verify deposit in USDC
    /// @param _amount Is the amount to verify
    modifier verifyUsdcAmount(uint _amount) {
        if(_amount == 0) revert KipuBank_ZeroAmount(msg.sender);
        if (_amount + s_totalContract > i_bankCap) revert KipuBank_ExceededLimit(_amount);
        _;
    }    

    /// @notice Modifier to verify withdrawal
    /// @param _amount The amount to verify to withdrawal
    /// @dev The threshold only applies to wihtdrawals
    modifier verifyEthWithdraw(uint _amount) {
        uint amountUSD = convertEthInUSD(_amount);
        if(amountUSD == 0) revert KipuBank_ZeroAmount(msg.sender);
        if (amountUSD > i_threshold) revert KipuBank_ExceededThreshold(amountUSD);
        if (_amount > s_balances[address(0)][msg.sender]) revert KipuBank_InsufficientsFunds(msg.sender, amountUSD);
        _;
    }

    /// @notice Modifier to verify withdraws
    /// @param _amount The amount to verify
    /// @dev The threshold only it's applies to withdraws
    modifier verifyWithdrawUSDC(uint _amount) {
        if(_amount == 0) revert KipuBank_ZeroAmount(msg.sender);
        if (_amount > i_threshold) revert KipuBank_ExceededThreshold(_amount);
        if (_amount > s_balances[address(i_usdc)][msg.sender]) revert KipuBank_InsufficientsFunds(msg.sender, _amount);
        _;
    }    

    /// @notice The function to perform the price query using the oracle
    /// @return priceUSD_ It is return the USD Price
    /// @dev We use the ChainLink Oracle
    function chainLinkFeeds() internal view returns(uint priceUSD_) {
        (, int256 ethUSDPrice,, uint256 updateAt,) = s_feed.latestRoundData();
        if( ethUSDPrice <= 0) revert KipuBank_CommittedOracle(uint(ethUSDPrice));
        if(block.timestamp - updateAt > HEARTBEAT) revert KipuBank_OutdatedPrice(uint(ethUSDPrice));

        priceUSD_ = uint(ethUSDPrice);
    }

    /// @notice The function to convert ETH to USDC
    /// @param _amount The entered amount to convert
    /// @return convertedAmount_ The amount converted
    /// @dev The operation perfomed is level the bases
    function convertEthInUSD(uint _amount) internal view returns (uint convertedAmount_) {
            convertedAmount_ = (_amount* chainLinkFeeds()) / DECIMAL_FACTOR;
    }

    /// @notice Private function to perform the ETH withdraw
    /// @param _amount The amount to withdraw
    /// @dev Is updated the state before the transfer, CEI pattern
    /// @dev It is used the NonReentrant OpenZeppelin function
    function _withdrawETH(uint _amount) private nonReentrant verifyEthWithdraw(_amount) {
        uint amountUSD = convertEthInUSD(_amount);
        s_balances[address(0)][msg.sender] -= _amount;
        s_withdrawal++;
        s_totalContract -= amountUSD;
        
        emit KipuBank_SuccessfulWithdrawal(msg.sender, amountUSD);

        (bool success, ) = payable(msg.sender).call{value: _amount}("");
        if (!success) revert KipuBank_RejectedWithdraw(msg.sender, _amount);
    }

    /// @notice Private function to perform the USDC withdraw
    /// @param _amount The amount to withdraw
    /// @dev It is used the NonReentrant OpenZeppelin function
    /// @dev Is updated the state before the transfer, CEI pattern
    /// @dev It is used the SafeIERC20 interface of OpenZeppelin
    function _withdrawUSDC(uint _amount) private nonReentrant verifyWithdrawUSDC(_amount) {
        s_balances[address(i_usdc)][msg.sender] -= _amount;
        s_withdrawal++;
        s_totalContract -= _amount;
        emit KipuBank_SuccessfulWithdrawal(msg.sender, _amount);
        i_usdc.safeTransfer(msg.sender, _amount);
    }

    /// @notice External functoin to perform withdraw in ETH
    /// @param _amount The amount to withdraw
    function withdrawETH(uint _amount) external whenNotPaused {
        _withdrawETH(_amount);
    }
    
    /// @notice External function to withdraw USDC
    /// @param _amount The amount to withdraw
    function withdrawUSDC(uint _amount) external whenNotPaused {
        _withdrawUSDC(_amount);
    } 

    /// @notice Private function to deposit ETH
    /// @param _holder The holder that perfomed the deposit
    /// @param _amountUSD The amount in USD to verify
    /// @param _amountETH The amount in ETH to deposit
    /// @dev A private function is implemented to save gas, calling the data feed
    function _depositETH(address _holder, uint _amountUSD, uint _amountETH) private verifyEthDeposit(_amountUSD, _amountETH) {
        s_balances[address(0)][_holder] += _amountETH;
        s_deposits++;
        s_totalContract += _amountUSD;
        emit KipuBank_SuccessfulDeposit(_holder, _amountUSD);
    }

    /// @notice Function to deposit ETH
    /// @dev Must be payable
    function depositETH() external payable whenNotPaused {
        uint amountETH = msg.value;
        uint amountUSD = convertEthInUSD(amountETH);
        _depositETH(msg.sender, amountUSD, amountETH);
    }

    /// @notice Function to deposit USDC
    /// @dev It is payable and use the verifyUsdcAmount modifier
    /// @dev It is used the SafeIERC20 interface to perform
    /// @dev We need the aprobation of the owner tokens
    function depositarUSDC(uint _amount) external verifyUsdcAmount(_amount) whenNotPaused {
        if ( i_usdc.allowance(msg.sender, address(this)) < _amount ) revert KipuBank_NonPermittedAmount(_amount);
        s_balances[address(i_usdc)][msg.sender] += _amount;
        s_deposits++;
        s_totalContract += _amount;
        emit KipuBank_SuccessfulDeposit(msg.sender, _amount);
        i_usdc.safeTransferFrom(msg.sender, address(this), _amount);
    }

    /// @notice Function to view the balance in USD
    /// @return amount_ The amount of the total balance in USD
    function viewAccountTotalBalance() external view returns (uint amount_) {
        amount_ = convertEthInUSD(s_balances[address(0)][msg.sender]) + s_balances[address(i_usdc)][msg.sender];
    }

    /* 
        # It is unnecessary when having a balanceOf function

    /// @notice Function to view the USDC balance
    /// @return amount_ The amount in USDC
    function viewUsdcBalance() external view returns (uint amount_) {
        amount_ = s_balances[address(i_usdc)][msg.sender];
    }

    /// @notice Function to view the ETH balance
    /// @return amount_ The amount in ETH 
    function viewEthBalance() external view returns (uint amount_) {
        amount_ = s_balances[address(0)][msg.sender];
    }
    */

    /// @notice Function to view the deposits count
    function viewDepositsCount() external view returns (uint) {
        return s_deposits;
    }

    /// @notice Function to view the withdraws count
    function viewWithdrawCount() external view returns (uint) {
        return s_withdrawal;
    }

    /// @notice Function to view the contract balance in USD
    function viewContractBalance() external view returns (uint) {
        return s_totalContract;
    }

    /// @notice Function to transfer the ownership another address
    /// @param _newOwner The address of the new owner of the contract
    /// @dev It is used the onlyOwner modifier
    function transferTheOwnership(address _newOwner) external onlyOwner whenPaused {
        
        address previousOwner = owner();

        _revokeRole(DEFAULT_ADMIN_ROLE, previousOwner);
        _revokeRole(PAUSER, previousOwner);
        _revokeRole(FEED_MANAGER, previousOwner);

        _transferOwnership(_newOwner);

        _grantRole(DEFAULT_ADMIN_ROLE, _newOwner);
        _grantRole(FEED_MANAGER, _newOwner);
        _grantRole(PAUSER, _newOwner);

        emit KipuBank_TransferredOwner(previousOwner, _newOwner);
    }

    /// @notice Function to change the data feeds
    /// @param _newFeed The new data feed address
    /// @dev Only the owner can access this function
    function setFeeds(address _newFeed) external onlyOwnerORole(FEED_MANAGER) whenPaused {
        if (_newFeed == address(0)) revert KipuBank_InvalidAddress();

        try AggregatorV3Interface(_newFeed).latestRoundData() returns (
            uint80, int256 price, uint256, uint256 updateAt, uint80
        ) {
            if(price <= 0) revert KipuBank_InvalidFeed(_newFeed);
            if(block.timestamp - updateAt > HEARTBEAT) revert KipuBank_OutdatedPrice(uint(price));
            
            address previousFeed = address(s_feed);
            s_feed = AggregatorV3Interface(_newFeed);
            emit KipuBank_FeedUpdated(previousFeed, _newFeed);
        } catch {
            revert KipuBank_InvalidFeed(_newFeed);
        }        
    }

    /// @notice Function to pause the contract
    /// @dev Only the owner and the PAUSER role can access this function
    function pauseContract() external onlyOwnerORole(PAUSER) whenNotPaused {
        _pause();
        emit KipuBank_ContractPaused(msg.sender, block.timestamp);
    }

    /// @notice Function to unpause the contract
    /// @dev Only the owner and the PAUSER role can access this function
    function unpauseContract() external onlyOwnerORole(PAUSER) whenPaused {
        _unpause();
        emit KipuBank_ContractUnpaused(msg.sender, block.timestamp);
    }

    /// @notice Function to grant a role
    /// @param account The account is granted with the new role
    /// @param role The role is granted
    function grantRole(bytes32 role, address account) 
    public 
    override 
    onlyOwner 
    {
        super.grantRole(role, account);
        emit KipuBank_GrantedRole(account, role);
    }

    /// @notice Function to revoke a role
    /// @param account The account that is revoked
    /// @param role The role that is revoked
    function revokeRole(bytes32 role, address account) 
    public 
    override
    onlyOwner 
    {
        super.revokeRole(role, account);
        emit KipuBank_RoleRevoked(account, role);
    }

    /// @notice Function to view the contract state
    /// @notice Returns the total contract balance, the bankcap, the threshold and the current data feeds provider
    function viewContractState() external view 
    returns (
        bool isPaused,
        uint totalContract,
        uint limit,
        uint threshold,
        address actualFeed
    )
    {
        return (
            paused(),
            s_totalContract,
            i_bankCap,
            i_threshold,
            address(s_feed)
        );
    }    

    /// @notice Function to view to each tokens funds for holder
    /// @param _holder The holder of the account
    /// @param _token The token to consult
    function balanceOf(address _holder, address _token) external view returns (uint) {
        return s_balances[_token][_holder];
    }

    /// @notice Requiered Override to multiple inheritance
    function supportsInterface(bytes4 interfaceId) 
        public 
        view 
        virtual 
        override(AccessControl) 
        returns (bool) 
    {
        return super.supportsInterface(interfaceId);
    }

}