// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

// Interface for ERC677 token standard (transferAndCall)
interface ERC677 {
    function onTokenTransfer(address sender, uint256 amount, bytes calldata data) external;
    function transferAndCall(address receiver, uint amount, bytes calldata data) external returns (bool success);
}

// Interface for standard ERC20 token operations
interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 value) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

/// @title SelfWallet LTD NOF Token  www.selfwallet.io
/// @dev Optimized implementation of NOF token for Tron network
///      with automatic burning of 0.1 token per transaction
///      and network fee payment by contract owner
/// @custom:security-contact support@selfwallet.io
contract NOFToken is IERC20, ERC677 {

    // ERC-20 standard parameters
    string public constant name = "SelfWallet LTD NOF Token";
    string public constant symbol = "NOF";
    uint8 public constant decimals = 1;
    mapping(address => mapping(address => uint256)) public allowance;
    mapping(address => uint256) public balanceOf;
    uint256 public totalSupply;
  
    // Contract owner and configuration
    address public constant owner = 0x40dA45220eF4B5df299409aE83f7d68638A6BFA7;

    // Whitelist threshold and fee settings
    uint256 private constant WHITELIST_THRESHOLD = 10_000_000 * 10 ** 1;
    uint256 private constant BURN_FEE = 1; // 0.10 tokens (in minimum units)
    mapping(address => bool) private noBurnAddresses;
    mapping(address => uint256) public trustedContracts;
    uint256 public exchangeConfigTRX;
    uint256 private totalWithdrawnTRX;

    // Exchange configuration structure
    struct ExchangeConfig {
        uint8 difference;
        uint256 price;
        uint256 minTrade;
        uint256 volume;
        bool allowExchange;
    }

    // Events
    event Exchange(uint256 nofAmount, uint256 incomingTokenAmount);
    event ExchangeTRX(uint256 trxAmount, uint256 nofAmount);
    event ExchangeNOF(uint256 nofAmount, uint256 trxAmount);


    /**
    * @dev Constructor creates 1 million tokens and allocates them to the contract itself
    * With decimals = 1, we multiply by 10 to account for decimal place
    */
    constructor() {
        unchecked {
            uint256 startSupply =  1_000_000 * (10 ** 1);
            totalSupply = startSupply;
            
            balanceOf[address(this)] = startSupply;
            emit Transfer(address(0), address(this), startSupply);

            // Initial exchange configuration
            exchangeConfigTRX =  uint256(0x1400000000000003E800000000000F42400000000000989680FF000000000000);
        }
    }

    /**
    * @dev Verify that the caller is the owner
    */
    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    /**
    * @dev Verify that the caller is a contract
    */
    modifier onlyContract() {
        uint256 size;
        assembly { size := extcodesize(caller()) }
        require(size > 0, "Only contracts allowed");
        _;
    }

    /**
    * @dev Verify that the caller is an account (not a contract)
    */
    modifier onlyAccount() {
        uint256 size;
        assembly { size := extcodesize(caller()) }
        require(size == 0, "Only account allowed");
        _;
    }

    /**
     * @dev Transfer tokens with whitelist checking for burn fee exemption
     * @param to The recipient address
     * @param amount Amount to transfer
     * @return True if transfer is successful
     */
    function transfer(address to, uint256 amount) public returns (bool) 
    {
        require(to != address(0), "Zero address not allowed");
        require(amount > 0, "Amount must be greater than zero");

        uint256 burnAmount = BURN_FEE;

        uint256 loadedSupply = totalSupply;

        if(loadedSupply > WHITELIST_THRESHOLD)
        {
           burnAmount = _isNoBurnAddress(msg.sender)? 0 : BURN_FEE; 
        }
        
        uint256 totalAmount = (amount + burnAmount);
        uint256 cashedBalance = balanceOf[msg.sender];
        require(cashedBalance >= totalAmount, "Insufficient balance");

        unchecked {
            balanceOf[msg.sender] = (cashedBalance - totalAmount);
            balanceOf[to] += amount;
        }

        emit Transfer(msg.sender, to, amount);

        if (burnAmount > 0)
        {
            unchecked {
                totalSupply = (loadedSupply - burnAmount);
            }
            
            emit Transfer(msg.sender, address(0), burnAmount);
        }
        
        if (to == address(this)) 
        {
            _exchangeNOF(msg.sender, amount);
        }
        else
        {
            if(_isContract(to))
            {
                if(_isTrustedContract(to))
                {
                    ERC677(to).onTokenTransfer(msg.sender, amount, "");
                }
            }
        }

        return true;
    }

    /**
     * @dev Set allowance for another address to spend tokens
     * @param spender Address authorized to spend
     * @param value Allowance amount
     * @return True if approval is successful
     */
    function approve(address spender, uint256 value) public returns (bool) 
    {   
        require(spender != address(0), "Zero address not allowed");

        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    /**
     * @dev Transfer tokens from one address to another with allowance check
     * @param from Address to transfer from
     * @param to Address to transfer to
     * @param amount Amount to transfer
     * @return True if transfer is successful
     */
    function transferFrom(address from, address to, uint256 amount) public returns (bool)
    {
        require(to != address(0), "Zero address not allowed");

        uint256 cachedBalanceFrom = balanceOf[from];
        require(cachedBalanceFrom >= amount, "Insufficient balance");

        uint256 cachedAllowance = allowance[from][msg.sender];
        require(cachedAllowance >= amount, "Allowance too low");

        unchecked {
            balanceOf[from] = cachedBalanceFrom - amount; 
            allowance[from][msg.sender] = cachedAllowance - amount;
            balanceOf[to] += amount;
        }

        emit Transfer(from, to, amount);
        return true;
    }

    /**
     * @dev Withdraw TRX according to current account settings
     * Can only be called by the owner
     */
    function withdrawTRX() external onlyOwner 
    {
        ExchangeConfig memory config = _unpackExchangeConfig(exchangeConfigTRX);

        uint256 contractBalance = address(this).balance;
        uint256 cashedWithdrawnTRX = totalWithdrawnTRX;

        uint256 totalReceivedTRX = cashedWithdrawnTRX + contractBalance;

        uint256 newAvailableToWithdraw = (totalReceivedTRX * config.difference) / 100;

        uint256 remainingToWithdraw = 0;
        
        if (newAvailableToWithdraw > cashedWithdrawnTRX) 
        {
            remainingToWithdraw = newAvailableToWithdraw - cashedWithdrawnTRX;
        }

        require(remainingToWithdraw > config.minTrade, "Minimum TRX amount not met");
        require(contractBalance >= remainingToWithdraw, "Not enough TRX in contract");

        payable(owner).transfer(remainingToWithdraw);

        totalWithdrawnTRX = remainingToWithdraw + cashedWithdrawnTRX;
    }

    /**
     * @dev Withdraw TRC20 tokens accidentally sent to the contract
     * @param tokenAddress The token contract address
     * @param amount Amount to withdraw
     * Can only be called by the owner
     */
    function withdrawTRC20(address tokenAddress, uint256 amount) external onlyOwner 
    {
        require(tokenAddress != address(this), "NOF token is not supported");
        require(_isContract(tokenAddress), "The address is not a contract address.");

        IERC20 token = IERC20(tokenAddress);
        uint256 tokenBalance = token.balanceOf(address(this));

        require(tokenBalance >= amount, "Not enough tokens in contract");
        require(token.transfer(owner, amount), "Transfer failed");
    }
    
    /**
     * @dev Create new tokens
     * @param amount Amount of tokens to create
     * Can only be called by the owner
     */
    function mint(uint256 amount) public onlyOwner 
    {
         require(amount > 0, "Amount must be greater than zero");
         _mint(amount);
    }
    
    /**
     * @dev Set entire exchange configuration in a single uint256
     * @param config Packed configuration data
     * Can only be called by the owner
     */
    function setExchangeConfig(uint256 config) external onlyOwner {
        exchangeConfigTRX = config;
    }

    /**
     * @dev Distribute tokens to multiple recipients in one transaction
     * @param recipients Array of recipient addresses
     * @param amount Amount per recipient
     * Can only be called by the owner
     */
    function airdrop(address[] calldata recipients, uint256 amount) external onlyOwner 
    {
        require(amount > 0, "Amount must be greater than zero");
        require(recipients.length > 0, "Recipients array is empty");

        unchecked {
            uint256 totalAmount = amount * recipients.length;
            uint256 cashedBalance = balanceOf[address(this)];

            require(cashedBalance >= totalAmount, "Not enough tokens in contract");

            for (uint256 i = 0; i < recipients.length; ++i) 
            {
                balanceOf[recipients[i]] += amount;
                emit Transfer(address(this), recipients[i], amount);
            }

            balanceOf[address(this)] = (cashedBalance - totalAmount);
        }
    }

    /**
     * @dev Burn tokens from the contract balance
     * @param amount Amount to burn
     * Can only be called by the owner
     */
    function burn(uint256 amount) external onlyOwner 
    {
        require(amount > 0, "Amount must be greater than zero");
        
        uint256 cashedBalance = balanceOf[address(this)];
        
        require(cashedBalance >= amount, "Not enough tokens in contract");

        unchecked {
            balanceOf[address(this)] = (cashedBalance - amount);
            totalSupply -= amount;
        }
        
        emit Transfer(address(this), address(0), amount);
    }

    /**
     * @dev Add address to burn fee exemption list
     * @param account Address to add
     * Can only be called by the owner
     */
    function addNoBurnAddress(address account) external onlyOwner {
        noBurnAddresses[account] = true;
    }

    /**
     * @dev Remove address from burn fee exemption list
     * @param account Address to remove
     * Can only be called by the owner
     */
    function removeNoBurnAddress(address account) external onlyOwner {
        delete noBurnAddresses[account];
    }

    /**
     * @dev Add or update trusted contract
     * @param contractAddress Contract address to add/update
     * @param value Configuration value
     * Can only be called by the owner
     */
    function setTrustedContract(address contractAddress, uint256 value) external onlyOwner {
        require(value > 0, "Value must be greater than zero");
        require(_isContract(contractAddress), "The address is not a contract address.");
        trustedContracts[contractAddress] = value;
    }

    /**
     * @dev Remove trusted contract
     * @param contractAddress Contract address to remove
     * Can only be called by the owner
     */
    function removeTrustedContract(address contractAddress) external onlyOwner {
        delete trustedContracts[contractAddress];
    }

    /**
     * @dev Check if contract is in trusted contracts list
     * @param contractAddress Address to check
     * @return True if contract is trusted
     */
    function _isTrustedContract(address contractAddress) internal view returns (bool) {
        return trustedContracts[contractAddress] != 0;
    }

    /**
     * @dev Check if address is exempt from burn fees
     * @param account Address to check
     * @return True if address is exempt
     */
    function _isNoBurnAddress(address account) internal view returns (bool) {
        return noBurnAddresses[account];
    }

    /**
     * @dev Internal mint function
     * @param amount Amount to mint
     */
    function _mint(uint256 amount) internal 
    {
        unchecked {
            totalSupply += amount;
            balanceOf[address(this)] += amount;
        }
        emit Transfer(address(0), address(this), amount);
    }

    /**
     * @dev Check if address is a contract
     * @param addr Address to check
     * @return True if address is a contract
     */
    function _isContract(address addr) private view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(addr)
        }
        return size > 0;
    }
   
    /**
     * @dev Unpack configuration from uint256
     */
    function _unpackExchangeConfig(uint256 packed) private pure returns (ExchangeConfig memory config) {
        config.difference = uint8(packed >> 248);
        config.price = uint64((packed >> 184) & 0xFFFFFFFFFFFFFFFF);
        config.volume = uint64((packed >> 120) & 0xFFFFFFFFFFFFFFFF);
        config.minTrade = uint64((packed >> 56) & 0xFFFFFFFFFFFFFFFF);
        config.allowExchange = ((packed >> 48) & 0xFF) != 0;
    }

    /**
     * @dev Pack configuration into uint256
     * @param config Configuration to pack
     * @return Packed configuration
     */
   function _packExchangeConfig(ExchangeConfig memory config) private pure returns (uint256) {
    return (uint256(config.difference) << 248) |
           (uint256(config.price) << 184) |
           (uint256(config.volume) << 120) |
           (uint256(config.minTrade) << 56) |
           (config.allowExchange ? 1 << 48 : 0);
    }


    /**
     * @dev Receive function to automatically exchange TRX for NOF tokens
     * Can only be called by regular accounts, not contracts
     */
    receive() external payable onlyAccount
    {
        ExchangeConfig memory config = _unpackExchangeConfig(exchangeConfigTRX);

        require(config.allowExchange, "Exchange TRX on Pause");
        require(msg.value >= config.minTrade, "Minimum TRX amount not met");
        
        uint256 tokenAmount = (msg.value * config.price) / 10_000_000;
        
        _exchangeTRX(msg.sender, tokenAmount, config.volume);

        emit ExchangeTRX(msg.value, tokenAmount);
    }

    /**
     * @dev Function to exchange TRX for a specific amount of NOF tokens
     * @param received Expected amount of NOF tokens to receive
     */
    function exchangeTRX(uint256 received) external payable 
    {
       ExchangeConfig memory config = _unpackExchangeConfig(exchangeConfigTRX);

        require(config.allowExchange, "Exchange TRX on Pause");
        require(msg.value >= config.minTrade, "Minimum TRX amount not met");
        
        uint256 tokenAmount = (msg.value * config.price) / 10_000_000;

        require(tokenAmount == received, "The amount of NOF received did not match");

        _exchangeTRX(msg.sender, tokenAmount, config.volume);

        emit ExchangeTRX(msg.value, tokenAmount);
    }

    /**
     * @dev Internal function to handle TRX to NOF exchange
     * @param to Recipient address
     * @param amount Amount of NOF tokens
     * @param mintAmount Amount to mint if necessary
     */
    function _exchangeTRX(address to, uint256 amount, uint256 mintAmount) internal
    {
        unchecked 
        {
            uint256 cachedBalance = balanceOf[address(this)];

            if(cachedBalance <= amount)
            {
                _mint(amount + mintAmount);
                balanceOf[address(this)] = (cachedBalance + mintAmount);
            }
            else
            {
                 balanceOf[address(this)] = (cachedBalance - amount);
            }
    
            balanceOf[to] += amount;
            emit Transfer(address(this), to, amount);
        }
    }

    

    /**
     * @dev Internal function to handle NOF to TRX exchange
     * @param user User address
     * @param nofAmount Amount of NOF tokens
     */
    function _exchangeNOF(address user, uint256 nofAmount) internal 
    {
        ExchangeConfig memory config = _unpackExchangeConfig(exchangeConfigTRX);

        require(config.allowExchange, "Exchange TRX on Pause");
    
        uint256 trxAmount = (nofAmount * 10_000_000) / config.price;
        uint256 trxToSend = (trxAmount * (100 - config.difference)) / 100;
        
        require(trxToSend > config.minTrade, "Minimum TRX amount not met");

        uint256 contractBalance = address(this).balance;

        require(contractBalance >= trxToSend, "Not enough TRX in contract");

        payable(user).transfer(trxToSend);

        emit ExchangeNOF(nofAmount, trxToSend);
    }

    /**
     * @dev Exchange TRC20 tokens for NOF tokens
     * @param token Token address to exchange
     * @param amount Amount of tokens to exchange
     * Can only be called by accounts, not contracts
     */
    function exchangeTRC20(address token, uint256 amount) external onlyAccount
    {
        uint256 storedConfig = trustedContracts[token];
        require(storedConfig != 0, "For trusted token only: support@selfwallet.io");

        ExchangeConfig memory config = _unpackExchangeConfig(storedConfig);
        require(config.allowExchange, "Exchange for this token is paused");

        uint256 nofAmount = (amount * config.price) / (10 ** config.difference);

        require(nofAmount >= config.minTrade, "Trade amount is too low");

        if(config.volume > 0)
        {
           require(nofAmount <= config.volume, "Not enough liquidity");
        }

        uint256 contractBalance = balanceOf[address(this)];
        require(contractBalance >= nofAmount, "Insufficient NOF balance");

        require(IERC20(token).transferFrom(msg.sender, address(this), amount), "Transfer failed");
        
        balanceOf[address(this)] = (contractBalance - nofAmount);
        balanceOf[msg.sender] += nofAmount;

        if(config.volume > 0)
        {
            config.volume -= nofAmount;
            trustedContracts[msg.sender] = _packExchangeConfig(config);
        }
        
        emit Transfer(address(this), msg.sender, nofAmount);
        emit Exchange(nofAmount, amount);
    }


    /**
     * @dev Transfer tokens and call a function on receiver contract in one transaction
     * @param receiver Receiver address
     * @param amount Amount to transfer
     * @param data Additional data to send
     * @return success True if successful
     * Can only be called by contracts
     */
    function transferAndCall(address receiver, uint amount, bytes calldata data) external onlyContract returns (bool success) 
    {   
        require(!_isTrustedContract(msg.sender), "For trusted contracts only: support@selfwallet.io");
        uint256 cachedBalanceSender = balanceOf[msg.sender];
        require(cachedBalanceSender >= amount, "Insufficient balance");
        unchecked 
        {
            balanceOf[msg.sender] = (cachedBalanceSender - amount);
            balanceOf[receiver] += amount;
        }

       emit Transfer(msg.sender, receiver, amount);
       
       if(_isContract(receiver)) 
       {
            ERC677(receiver).onTokenTransfer(msg.sender, amount, data);
       }
       
        return true;
     }

    /**
     * @dev Callback function for token transfers
     * @param sender Sender address
     * @param amount Amount of tokens
     * @param data Additional data
     * Can only be called by contracts
     */
    function onTokenTransfer(address sender, uint256 amount, bytes calldata data) external onlyContract 
    {
        require(amount > 0, "Amount must be greater than zero");
        require(sender != address(0), "Zero address not allowed");

        uint256 storedConfig = trustedContracts[msg.sender];
        require(storedConfig != 0, "For trusted contracts only: support@selfwallet.io");

        require(!_isContract(sender), "Recipient cannot be a contract");

        ExchangeConfig memory config = _unpackExchangeConfig(storedConfig);
        require(config.allowExchange, "Exchange for this token is paused");

        uint256 nofAmount = (amount * config.price) / (10 ** config.difference);

        require(nofAmount >= config.minTrade, "Trade amount is too low");

        if(config.volume > 0)
        {
           require(nofAmount <= config.volume, "Not enough liquidity");
        }

        if (data.length > 0) 
        {
            uint256 expectedNofAmount = abi.decode(data, (uint256));
            require(nofAmount == expectedNofAmount, "Mismatched exchange amount");
        }

        uint256 contractBalance = balanceOf[address(this)];
        require(contractBalance >= nofAmount, "Insufficient NOF balance");

        balanceOf[address(this)] = (contractBalance - nofAmount);
        balanceOf[sender] += nofAmount;

        if(config.volume > 0)
        {
            config.volume -= nofAmount;
            trustedContracts[msg.sender] = _packExchangeConfig(config);
        }
        
        emit Transfer(address(this), sender, nofAmount);
        emit Exchange(nofAmount, amount);
    }
}