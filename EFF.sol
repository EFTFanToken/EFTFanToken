//SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "./DividendDistributor.sol";

contract EFF is IERC20, Ownable {
    using SafeMath for uint256;

    address WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address DEAD = 0x000000000000000000000000000000000000dEaD;
    address ZERO = 0x0000000000000000000000000000000000000000;

    address public REWARD = 0xB72962568345253f71A18318D67E13A282b187E6;
    address public BURN = 0xB72962568345253f71A18318D67E13A282b187E6;
    address public LOTTERY = 0x2170Ed0880ac9A755fd29B2688956BD959F933F8;

    string constant _name = "EFT Fan Token";
    string constant _symbol = "$EFF";
    uint8 constant _decimals = 9;

    uint256 _totalSupply = 100000000000 * (10**_decimals);

    mapping(address => uint256) _balances;
    mapping(address => mapping(address => uint256)) _allowances;

    mapping(address => bool) isFeeExempt;
    mapping(address => bool) isDividendExempt;
    // allowed users to do transactions before trading enable
    mapping(address => bool) isAuthorized;
    mapping(address => bool) isBlacklist;
    mapping(address => bool) isMaxWalletExempt;
    mapping(address => bool) isMaxTxExempt;
    mapping(address => bool) isTimelockExempt;

    // buy fees
    uint256 public buyRewardFee = 4;
    uint256 public buyMarketingFee = 3;
    uint256 public buyLiquidityFee = 2;
    uint256 public buyBurnFee = 1;
    uint256 public buyBuyBackFee = 1;
    uint256 public buyStakePoolFee = 0;
    uint256 public buyGameFee = 0;
    uint256 public buyLotteryFee = 1;
    uint256 public buyTotalFees = 12;
    // sell fees
    uint256 public sellRewardFee = 4;
    uint256 public sellMarketingFee = 3;
    uint256 public sellLiquidityFee = 2;
    uint256 public sellBurnFee = 1;
    uint256 public sellBuyBackFee = 1;
    uint256 public sellStakePoolFee = 0;
    uint256 public sellGameFee = 0;
    uint256 public sellLotteryFee = 1;
    uint256 public sellTotalFees = 12;

    address public marketingFeeReceiver;
    address public lotteryFeeReceiver;
    address public stakePoolAddress;
    address public gameWallet;

    // swap percentage
    uint256 public rewardSwap = 4;
    uint256 public marketingSwap = 3;
    uint256 public liquiditySwap = 2;
    uint256 public lotterySwap = 1;
    uint256 public burnSwap = 1;
    uint256 public totalSwap = 11;

    IUniswapV2Router02 public router;
    address public pair;

    bool public tradingOpen = false;

    uint256 public sellTaxMultiplier = 1;

    DividendDistributor public dividendTracker;

    uint256 distributorGas = 500000;

    bool public coolDownEnabled = true;
    uint256 public cooldownTimerInterval = 86400;
    mapping(address => uint256) private cooldownTimer;

    event AutoLiquify(uint256 amountBNB, uint256 amountBOG);
    event ChangeRewardTracker(address token);
    event IncludeInReward(address holder);

    bool public swapEnabled = true;
    uint256 public swapThreshold = (_totalSupply * 1) / 1000; // 0.1% of supply
    uint256 public maxWalletTokens = (_totalSupply * 10) / 1000;
    uint256 public maxTxAmount = (_totalSupply * 5) / 1000; // 0.5% of supply

    bool inSwap;
    modifier swapping() {
        inSwap = true;
        _;
        inSwap = false;
    }

    constructor() {
        router = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);
        pair = IUniswapV2Factory(router.factory()).createPair(
            WBNB,
            address(this)
        );
        _allowances[address(this)][address(router)] = type(uint256).max;

        dividendTracker = new DividendDistributor(address(router), REWARD);

        isFeeExempt[msg.sender] = true;

        isDividendExempt[pair] = true;
        isDividendExempt[address(this)] = true;
        isDividendExempt[DEAD] = true;

        isAuthorized[owner()] = true;

        isMaxTxExempt[owner()] = true;
        isMaxTxExempt[pair] = true;
        isMaxTxExempt[address(this)] = true;

        isMaxWalletExempt[owner()] = true;
        isMaxWalletExempt[pair] = true;
        isMaxWalletExempt[address(this)] = true;

        marketingFeeReceiver = 0xaBd50D22A9665E7adA7E7799d40E126C164F5c15;
        stakePoolAddress = 0x9c55657ED2DFAb5988281DD5204A91743713b902;
        lotteryFeeReceiver = 0xeffE48E632C21482c462e92ad3625f0a099e3c22;
        gameWallet = 0x920ad869B16b8a569B8980179F2E7850F447B56a;

        _balances[msg.sender] = _totalSupply;
        emit Transfer(address(0), msg.sender, _totalSupply);
    }

    receive() external payable {}

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function name() public pure returns (string memory) {
        return _name;
    }

    function symbol() public pure returns (string memory) {
        return _symbol;
    }

    function decimals() public pure returns (uint8) {
        return _decimals;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    // tracker dashboard functions
    function getHolderDetails(address holder)
        public
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        return dividendTracker.getHolderDetails(holder);
    }

    function getLastProcessedIndex() public view returns (uint256) {
        return dividendTracker.getLastProcessedIndex();
    }

    function getNumberOfTokenHolders() public view returns (uint256) {
        return dividendTracker.getNumberOfTokenHolders();
    }

    function totalDistributedRewards() public view returns (uint256) {
        return dividendTracker.totalDistributedRewards();
    }

    function allowance(address holder, address spender)
        external
        view
        override
        returns (uint256)
    {
        return _allowances[holder][spender];
    }

    function approve(address spender, uint256 amount)
        public
        override
        returns (bool)
    {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function approveMax(address spender) external returns (bool) {
        return approve(spender, type(uint256).max);
    }

    function transfer(address recipient, uint256 amount)
        external
        override
        returns (bool)
    {
        return _transferFrom(msg.sender, recipient, amount);
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external override returns (bool) {
        if (_allowances[sender][msg.sender] != type(uint256).max) {
            _allowances[sender][msg.sender] = _allowances[sender][msg.sender]
                .sub(amount, "Insufficient Allowance");
        }

        return _transferFrom(sender, recipient, amount);
    }

    function _transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) internal returns (bool) {
        require(
            !isBlacklist[sender] && !isBlacklist[recipient],
            "Blacklisted users"
        );
        if (inSwap) {
            return _basicTransfer(sender, recipient, amount);
        }

        if (!isAuthorized[sender]) {
            require(tradingOpen, "Trading not open yet");
        }
        if (!isMaxTxExempt[sender]) {
            require(amount <= maxTxAmount, "Max Transaction Amount exceed");
        }
        if (coolDownEnabled && sender == pair) {
            cooldownTimer[recipient] = block.timestamp + cooldownTimerInterval;
        }
        if (!isMaxWalletExempt[recipient]) {
            uint256 balanceAfterTransfer = amount.add(_balances[recipient]);
            require(
                balanceAfterTransfer <= maxWalletTokens,
                "Max Wallet Amount exceed"
            );
        }
        if (shouldSwapBack()) {
            swapBackInBnb();
        }

        //Exchange tokens
        _balances[sender] = _balances[sender].sub(
            amount,
            "Insufficient Balance"
        );

        uint256 amountReceived = shouldTakeFee(sender, recipient)
            ? takeFee(sender, amount, recipient)
            : amount;
        _balances[recipient] = _balances[recipient].add(amountReceived);

        // Dividend tracker
        if (!isDividendExempt[sender]) {
            try dividendTracker.setShare(sender, _balances[sender]) {} catch {}
        }

        if (!isDividendExempt[recipient]) {
            try
                dividendTracker.setShare(recipient, _balances[recipient])
            {} catch {}
        }

        try dividendTracker.process(distributorGas) {} catch {}

        emit Transfer(sender, recipient, amountReceived);
        return true;
    }

    function _basicTransfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal returns (bool) {
        _balances[sender] = _balances[sender].sub(
            amount,
            "Insufficient Balance"
        );
        _balances[recipient] = _balances[recipient].add(amount);
        emit Transfer(sender, recipient, amount);
        return true;
    }

    function shouldTakeFee(address sender, address to)
        internal
        view
        returns (bool)
    {
        if (isFeeExempt[sender] || isFeeExempt[to]) {
            return false;
        } else {
            return true;
        }
    }

    function takeFee(
        address sender,
        uint256 amount,
        address to
    ) internal returns (uint256) {
        uint256 feeAmount = 0;
        uint256 gamePoolToken = 0;
        uint256 stakePoolToken = 0;
        if (to == pair) {
            feeAmount = amount.mul(sellTotalFees).div(100);
            if (coolDownEnabled && !isTimelockExempt[sender]) {
                feeAmount = feeAmount.mul(sellTaxMultiplier);
            }
            if (sellGameFee > 0) {
                gamePoolToken = feeAmount.mul(sellGameFee).div(sellTotalFees);
                _balances[gameWallet] = _balances[gameWallet].add(
                    gamePoolToken
                );
                emit Transfer(sender, gameWallet, gamePoolToken);
            }
            if (sellStakePoolFee > 0) {
                stakePoolToken = feeAmount.mul(sellStakePoolFee).div(
                    sellTotalFees
                );
                _balances[stakePoolAddress] = _balances[stakePoolAddress].add(
                    stakePoolToken
                );
                emit Transfer(sender, stakePoolAddress, stakePoolToken);
            }
        } else {
            feeAmount = amount.mul(buyTotalFees).div(100);
            if (buyGameFee > 0) {
                gamePoolToken = feeAmount.mul(buyGameFee).div(buyTotalFees);
                _balances[gameWallet] = _balances[gameWallet].add(
                    gamePoolToken
                );
                emit Transfer(sender, gameWallet, gamePoolToken);
            }
            if (buyStakePoolFee > 0) {
                stakePoolToken = feeAmount.mul(buyStakePoolFee).div(
                    buyTotalFees
                );
                _balances[stakePoolAddress] = _balances[stakePoolAddress].add(
                    stakePoolToken
                );
                emit Transfer(sender, stakePoolAddress, stakePoolToken);
            }
        }
        uint256 tokensToContract = feeAmount.sub(gamePoolToken).sub(
            stakePoolToken
        );
        _balances[address(this)] = _balances[address(this)].add(
            tokensToContract
        );
        emit Transfer(sender, address(this), tokensToContract);

        return amount.sub(feeAmount);
    }

    function shouldSwapBack() internal view returns (bool) {
        return
            msg.sender != pair &&
            !inSwap &&
            swapEnabled &&
            tradingOpen &&
            _balances[address(this)] >= swapThreshold;
    }

    function clearStuckBalance(uint256 amountPercentage) external onlyOwner {
        uint256 amountBNB = address(this).balance;
        payable(msg.sender).transfer((amountBNB * amountPercentage) / 100);
    }

    function getBep20Tokens(address _tokenAddress, uint256 amount)
        external
        onlyOwner
    {
        require(
            IERC20(_tokenAddress).balanceOf(address(this)) >= amount,
            "No Enough Tokens"
        );
        IERC20(_tokenAddress).transfer(msg.sender, amount);
    }

    function updateBuyFees(
        uint256 reward,
        uint256 marketing,
        uint256 liquidity,
        uint256 burn,
        uint256 staking,
        uint256 buyBack,
        uint256 gamePool,
        uint256 lottery
    ) public onlyOwner {
        buyRewardFee = reward;
        buyMarketingFee = marketing;
        buyLiquidityFee = liquidity;
        buyBurnFee = burn;
        buyStakePoolFee = staking;
        buyBuyBackFee = buyBack;
        buyGameFee = gamePool;
        buyLotteryFee = lottery;
        buyTotalFees = reward.add(marketing).add(liquidity).add(burn).add(
            staking
        );
        buyTotalFees = buyTotalFees.add(buyBack).add(gamePool).add(lottery);

        require(buyTotalFees <= 25, "Fees can not be greater than 25%");
    }

    function updateSellFees(
        uint256 reward,
        uint256 marketing,
        uint256 liquidity,
        uint256 burn,
        uint256 staking,
        uint256 buyBack,
        uint256 gamePool,
        uint256 lottery
    ) public onlyOwner {
        sellRewardFee = reward;
        sellMarketingFee = marketing;
        sellLiquidityFee = liquidity;
        sellBurnFee = burn;
        sellStakePoolFee = staking;
        sellBuyBackFee = buyBack;
        sellGameFee = gamePool;
        sellLotteryFee = lottery;
        sellTotalFees = reward.add(marketing).add(liquidity).add(burn).add(
            staking
        );
        sellTotalFees = buyTotalFees.add(buyBack).add(gamePool).add(lottery);

        require(sellTotalFees <= 25, "Fees can not be greater than 25%");
    }

    // update swap percentages
    function updateSwapPercentages(
        uint256 reward,
        uint256 marketing,
        uint256 liquidity,
        uint256 burn,
        uint256 lottery
    ) public onlyOwner {
        rewardSwap = reward;
        marketingSwap = marketing;
        liquiditySwap = liquidity;
        burnSwap = burn;
        lotterySwap = lottery;
        totalSwap = reward.add(marketing).add(liquidity).add(burn).add(lottery);
    }

    // switch Trading
    function enableTrading(bool _status) public onlyOwner {
        tradingOpen = _status;
    }

    function whitelistPreSale(address _preSale) public onlyOwner {
        isFeeExempt[_preSale] = true;
        isDividendExempt[_preSale] = true;
        isAuthorized[_preSale] = true;
        isMaxWalletExempt[_preSale] = true;
    }

    // manual claim for the greedy humans
    function ___claimRewards(bool tryAll) public {
        dividendTracker.claimDividend();
        if (tryAll) {
            try dividendTracker.process(distributorGas) {} catch {}
        }
    }

    // manually clear the queue
    function claimProcess() public {
        try dividendTracker.process(distributorGas) {} catch {}
    }

    function blackListWallets(address wallet, bool _status) public onlyOwner {
        isBlacklist[wallet] = _status;
    }

    function isBlacklisted(address _wallet) public view returns (bool) {
        return isBlacklist[_wallet];
    }

    function isRewardExclude(address _wallet) public view returns (bool) {
        return isDividendExempt[_wallet];
    }

    function isFeeExclude(address _wallet) public view returns (bool) {
        return isFeeExempt[_wallet];
    }

    function isMaxWalletExclude(address _wallet) public view returns (bool) {
        return isMaxWalletExempt[_wallet];
    }

    function isMaxTxExcluded(address _wallet) public view returns (bool) {
        return isMaxTxExempt[_wallet];
    }

    function setIsMaxTxExempt(address holder, bool exempt) external onlyOwner {
        isMaxTxExempt[holder] = exempt;
    }

    function setMaxTxAmount(uint256 amount) external onlyOwner {
        maxTxAmount = amount * (10**9);
    }

    function isExemptTimeLock(address _wallet) public view returns (bool) {
        return isTimelockExempt[_wallet];
    }

    function changeSellCoolDownTime(uint256 _time) public onlyOwner {
        cooldownTimerInterval = _time;
    }

    function enableSellCollDown(bool _status) public onlyOwner {
        coolDownEnabled = _status;
    }

    function exemptTimeLock(address wallet, bool _status) public onlyOwner {
        isTimelockExempt[wallet] = _status;
    }

    function swapBackInBnb() internal swapping {
        uint256 contractTokenBalance = _balances[address(this)];
        uint256 tokensToLiquidity = contractTokenBalance.mul(liquiditySwap).div(
            totalSwap
        );
        uint256 lotteryAndMarketingFee = marketingSwap.add(lotterySwap);
        uint256 tokensToMarketingAndLottery = contractTokenBalance
            .mul(lotteryAndMarketingFee)
            .div(totalSwap);
        uint256 tokensForRewardAndBurn = contractTokenBalance
            .sub(tokensToLiquidity)
            .sub(tokensToMarketingAndLottery);

        if (tokensForRewardAndBurn > 0) {
            if (REWARD == BURN) {
                swapTokensForTokens(tokensForRewardAndBurn, REWARD);
                uint256 swappedTokensAmount = IERC20(REWARD).balanceOf(
                    address(this)
                );
                uint256 rewardAndBurnFee = rewardSwap.add(burnSwap);
                uint256 tokensToBurn = swappedTokensAmount.mul(burnSwap).div(
                    rewardAndBurnFee
                );
                if (tokensToBurn > 0) {
                    // send burn token
                    try
                        IERC20(REWARD).transfer(address(DEAD), tokensToBurn)
                    {} catch {}
                }

                uint256 tokensToReward = swappedTokensAmount.sub(tokensToBurn);
                if (tokensToReward > 0) {
                    // send token to reward
                    IERC20(REWARD).transfer(
                        address(dividendTracker),
                        tokensToReward
                    );
                    try dividendTracker.deposit(tokensToReward) {} catch {}
                }
            } else {
                uint256 rewardAndBurnFee = rewardSwap.add(burnSwap);
                uint256 tokensToBurn = tokensForRewardAndBurn.mul(burnSwap).div(
                    rewardAndBurnFee
                );
                uint256 tokensToReward = tokensForRewardAndBurn.sub(
                    tokensToBurn
                );

                if (tokensToBurn > 0) {
                    swapTokensForTokens(tokensToBurn, BURN);
                    uint256 swappedTokensAmountBurn = IERC20(BURN).balanceOf(
                        address(this)
                    );
                    // send burn token
                    try
                        IERC20(BURN).transfer(
                            address(DEAD),
                            swappedTokensAmountBurn
                        )
                    {} catch {}
                }

                if (tokensToReward > 0) {
                    swapTokensForTokens(tokensToBurn, REWARD);
                    uint256 swappedTokensAmount = IERC20(REWARD).balanceOf(
                        address(this)
                    );
                    // send token to reward
                    IERC20(REWARD).transfer(
                        address(dividendTracker),
                        swappedTokensAmount
                    );
                    try dividendTracker.deposit(tokensToReward) {} catch {}
                }
            }
        }

        if (tokensToMarketingAndLottery > 0) {
            swapTokensForTokens(tokensToMarketingAndLottery, LOTTERY);
            uint256 swappedTokensAmount = IERC20(LOTTERY).balanceOf(
                address(this)
            );

            uint256 tokensToMarketing = swappedTokensAmount
                .mul(marketingSwap)
                .div(lotteryAndMarketingFee);
            uint256 tokensToLottery = swappedTokensAmount.sub(
                tokensToMarketing
            );

            if (tokensToMarketing > 0) {
                try
                    IERC20(LOTTERY).transfer(
                        marketingFeeReceiver,
                        tokensToMarketing
                    )
                {} catch {}
            }
            if (tokensToLottery > 0) {
                try
                    IERC20(LOTTERY).transfer(
                        lotteryFeeReceiver,
                        tokensToLottery
                    )
                {} catch {}
            }
        }

        if (tokensToLiquidity > 0) {
            // add liquidity
            swapAndLiquify(tokensToLiquidity);
        }
    }

    function swapAndLiquify(uint256 tokens) private {
        // split the contract balance into halves
        uint256 half = tokens.div(2);
        uint256 otherHalf = tokens.sub(half);

        // capture the contract's current ETH balance.
        // this is so that we can capture exactly the amount of ETH that the
        // swap creates, and not make the liquidity event include any ETH that
        // has been manually sent to the contract
        uint256 initialBalance = address(this).balance;

        // swap tokens for ETH
        swapTokensForEth(half); // <- this breaks the ETH -> HATE swap when swap+liquify is triggered

        // how much ETH did we just swap into?
        uint256 newBalance = address(this).balance.sub(initialBalance);

        // add liquidity to uniswap
        addLiquidity(otherHalf, newBalance);

        emit AutoLiquify(newBalance, otherHalf);
    }

    function swapTokensForEth(uint256 tokenAmount) private {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = router.WETH();
        _approve(address(this), address(router), tokenAmount);
        // make the swap
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
    }

    function swapTokensForTokens(uint256 tokenAmount, address tokenToSwap)
        private
    {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](3);
        path[0] = address(this);
        path[1] = router.WETH();
        path[2] = tokenToSwap;
        _approve(address(this), address(router), tokenAmount);
        // make the swap
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of tokens
            path,
            address(this),
            block.timestamp
        );
    }

    function addLiquidity(uint256 tokenAmount, uint256 bnbAmount) private {
        _approve(address(this), address(router), tokenAmount);

        // add the liquidity
        router.addLiquidityETH{value: bnbAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            address(this),
            block.timestamp
        );
    }

    function setIsDividendExempt(address holder, bool exempt)
        external
        onlyOwner
    {
        require(holder != address(this) && holder != pair);
        isDividendExempt[holder] = exempt;
        if (exempt) {
            dividendTracker.setShare(holder, 0);
        } else {
            dividendTracker.setShare(holder, _balances[holder]);
        }
    }

    function setIsFeeExempt(address holder, bool exempt) external onlyOwner {
        isFeeExempt[holder] = exempt;
    }

    function setIsMaxWalletExempt(address holder, bool exempt)
        external
        onlyOwner
    {
        isMaxWalletExempt[holder] = exempt;
    }

    function addAuthorizedWallets(address holder, bool exempt)
        external
        onlyOwner
    {
        isAuthorized[holder] = exempt;
    }

    function setMarketingWallet(address _marketingFeeReceiver)
        external
        onlyOwner
    {
        marketingFeeReceiver = _marketingFeeReceiver;
    }

    function setLotteryWallet(address _lotteryFeeReceiver) external onlyOwner {
        lotteryFeeReceiver = _lotteryFeeReceiver;
    }

    function setGamePoolAddress(address _gameWallet) external onlyOwner {
        gameWallet = _gameWallet;
    }

    function setStakePoolAddress(address _stakePool) external onlyOwner {
        stakePoolAddress = _stakePool;
    }

    function changeBuyBackAndBurnToken(address _tokenAddress)
        external
        onlyOwner
    {
        BURN = _tokenAddress;
    }

    function changeLotteryAndMarketingToken(address _tokenAddress)
        external
        onlyOwner
    {
        LOTTERY = _tokenAddress;
    }

    function setMaxWalletToken(uint256 amount) external onlyOwner {
        maxWalletTokens = amount * (10**9);
    }

    function changeSellFeeMultiplier(uint256 amount) external onlyOwner {
        sellTaxMultiplier = amount;
    }

    function setSwapBackSettings(bool _enabled, uint256 _amount)
        external
        onlyOwner
    {
        swapEnabled = _enabled;
        swapThreshold = _amount;
    }

    function setDistributionCriteria(
        uint256 _minPeriod,
        uint256 _minDistribution
    ) external onlyOwner {
        dividendTracker.setDistributionCriteria(_minPeriod, _minDistribution);
    }

    function setDistributorSettings(uint256 gas) external onlyOwner {
        require(gas < 750000);
        distributorGas = gas;
    }

    function purgeBeforeSwitch() public onlyOwner {
        dividendTracker.purge(msg.sender);
    }

    function includeMeinRewards() public {
        require(
            !isDividendExempt[msg.sender],
            "You are not allowed to get rewards"
        );
        try
            dividendTracker.setShare(msg.sender, _balances[msg.sender])
        {} catch {}

        emit IncludeInReward(msg.sender);
    }

    function switchToken(address rewardToken, bool isIncludeHolders)
        public
        onlyOwner
    {
        require(rewardToken != WBNB, "Can not reward BNB in this tracker");
        REWARD = rewardToken;
        // get current shareholders list
        address[] memory currentHolders = dividendTracker.getShareHoldersList();
        dividendTracker = new DividendDistributor(address(router), rewardToken);
        if (isIncludeHolders) {
            // add old share holders to new tracker
            for (uint256 i = 0; i < currentHolders.length; i++) {
                try
                    dividendTracker.setShare(
                        currentHolders[i],
                        _balances[currentHolders[i]]
                    )
                {} catch {}
            }
        }

        emit ChangeRewardTracker(rewardToken);
    }
}
