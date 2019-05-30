pragma solidity >=0.4.24 <0.6.0;

import 'zeppelin-solidity/contracts/token/ERC20/StandardToken.sol';
import 'zeppelin-solidity/contracts/math/Math.sol';
import 'zeppelin-solidity/contracts/math/SafeMath.sol';
import 'zeppelin-solidity/contracts/lifecycle/Pausable.sol';
import 'zeppelin-solidity/contracts/ownership/Claimable.sol';
import 'zeppelin-solidity/contracts/token/ERC20/SafeERC20.sol';
import 'zeppelin-solidity/contracts/lifecycle/Destructible.sol';


/* 中国明星币IMO
 * 1、设备激活：转账token，激活账户
 * 2、允许激活账户存入token，经过一段时间可能会得到奖励
 * 3、从一个运营账户扣减token
 * 4、支持账户禁用
 */
contract StarIMOLottery is StandardToken, Pausable, Claimable, Destructible  {
    using SafeMath for uint256;
    using SafeERC20 for StarIMOLottery;

    // 初始的所有明星币账号
    uint256 public operatorPool;                            // 运营账户
    uint256 public rewardPool;                              // 挖矿账户
    uint256 public airDropPool;                             // 空投账户
    uint256 public centralBank;                             // 中央银行，通往中心化数据库枢纽
    uint256 public dailyRewardPool;                         // 每天奖池数量

    // 对明星币账号有操作权限的账号
    mapping (address => uint8) public opsForOperatorPool;   // 运营账户操作账户列表 (0 未激活 1 激活 2 禁用)
    mapping (address => uint8) public opsForRewardPool;     // 挖矿账户操作账户列表 (0 未激活 1 激活 2 禁用)
    mapping (address => uint8) public opsForAirDropPool;    // 空投账户操作账户列表 (0 未激活 1 激活 2 禁用)
    mapping (address => uint8) public opsForCentralBank;    // 中央银行操作账户列表 (0 未激活 1 激活 2 禁用)
    mapping (address => uint8) public activateBox;          // 账户状态 (0 未激活 1 激活 2 禁用 3 转移)
    mapping (address => uint256) public activateTime;       // 账户状态 (0 未激活 1 激活 2 禁用)

    // 对投注账号管理的账号
    address depositAccountOperator;                         // 操作账号状态

    // 运行参数
    uint256 public minimumDeposit;                          // 账号最小的投注金额
    uint256 public maximumDeposit;                          // 账号最大的投注金额
    uint256 public totalDepositNumber;                      // 总的押注的人数
    uint256 public dailyLuckyNumber;                        // 每天多少人得到奖励
    uint256 public currentMask;                             // 当前的掩码
    uint256 public nextDepositIndex;                        // 下一个投注人的序号
    uint256 public lastUpdateMaskBlockNum;                  // 最近一次更新掩码的区块号
    uint256 public dailyBlockNumber;                        // 当前预估每天产生的区块数量
    uint256 public initEthForFans;                          // 激活的时候给粉丝的eth数量
    uint256 public initStarCoin;                            // 激活的时候给粉丝的明星币数量
    uint256 public fansLockDuration;                        // 粉丝要支持明星押入多少秒

    // 中奖相关变量
    mapping (address => uint256) public depositBox;         // 存款箱
    mapping (address => uint256) public depositIndex;       // 存款编号
    mapping (address => uint256) public lastWinBlockNumber; // 最后一次得奖区块号

    // 常量
    uint256 constant SECONDS_ONE_YEAR = 60*60*24*365;       // 一年多少秒

    // 事件
    event WinStarCoin(address indexed _winner, uint256 _value);
    event ToCentralBank(address indexed _depositor, uint256 _value);
    event FromCentralBank(address indexed _receiver, uint256 _value);
    event HeartBeat(address indexed _sender, uint256 _block_number);
    event Activate(address indexed _activator);
    event Deposit(address indexed _depositor, uint256 _amount);
    event WithDraw(address indexed _withdrawor, uint256 _amount);
    event ToDailyRewardPool(uint256 _amount);

    uint256 public rewardScale;

    // 构造函数
    function StarIMOLottery (address _operator, uint256 _minimumDeposit, uint256 _maximumDeposit,
        uint256 _dailyLuckyNumber, uint256  _operatorPool, uint256 _rewardPool, uint256 _airDropPool,
        uint256 _rewardScale) public {

        operatorPool = _operatorPool;
        rewardPool = _rewardPool;
        airDropPool = _airDropPool;
        centralBank = 0;
        dailyRewardPool = 0;

        depositAccountOperator = _operator;
        minimumDeposit = _minimumDeposit;
        maximumDeposit = _maximumDeposit;
        totalDepositNumber = 0;
        dailyLuckyNumber = _dailyLuckyNumber;
        nextDepositIndex = 0;
        currentMask = 31;  // init from 3000 block / 100 person.
        lastUpdateMaskBlockNum = 0;
        dailyBlockNumber = 3000;
        initEthForFans = 2 * 10 ** 18;
        initStarCoin = 1500 * 10 ** 10;

        rewardScale = _rewardScale;
        fansLockDuration = 365 * 24 * 60 * 60; // default lock 180 days.
    }

    // 修饰：只有账号管理账户才能调用
    modifier onlyAccountOperator () {
        require (msg.sender == depositAccountOperator);
        _;
    }

    // 设置账号管理账号
    function setAccountOperator (address _account) public onlyOwner {
        depositAccountOperator = _account;
    }

    // 设置奖励系数
    function setRewardScale (uint256 _rewardScale) public onlyAccountOperator {
        rewardScale = _rewardScale;
    }

    function getRewardScale() public view returns(uint256) {
        return rewardScale;
    }

    // 修饰：只有有效的激活账户才能调用
    modifier onlyActivate () {
        require(activateBox[msg.sender] == 1);
        _;
    }

    // 修改账户激活状态
    function setActivate (address _account, uint8 _status) public onlyAccountOperator {
        activateBox[_account] = _status;
    }

    // 修改激活的时候给粉丝的明星币数量
    function setInitStarCoin (uint256 _amount) public onlyAccountOperator {
        initStarCoin = _amount;
    }

    // 激活的时候给粉丝的明星币数量
    function getInitStarCoin () public view returns(uint256 amount) {
        return initStarCoin;
    }

    // 修饰：只有运营账户才能调用
    modifier onlyOpsForOperatorPool () {
        require(opsForOperatorPool[msg.sender] == 1);
        _;
    }

    // 修改运营账户状态
    function setOpsForOperatorPool (address _operator, uint8 _state) public onlyOwner {
        require(_state <= 2);
        opsForOperatorPool[_operator] = _state;
    }

    // 修饰：只有奖金池账户才能调用
    modifier onlyOpsForRewardPool () {
        require(opsForRewardPool[msg.sender] == 1);
        _;
    }

    // 修改奖金池账户状态
    function setOpsForRewardPool (address _operator, uint8 _state) public onlyOwner {
        require(_state <= 2);
        opsForRewardPool[_operator] = _state;
    }

    // 修饰：只有空投账户才能调用
    modifier onlyOpsForAirDropPool () {
        require(opsForAirDropPool[msg.sender] == 1);
        _;
    }

    // 修改空投账户状态
    function setOpsForAirDropPool (address _operator, uint8 _state) public onlyOwner {
        require(_state <= 2);
        opsForAirDropPool[_operator] = _state;
    }

    // 修饰：只有运营账户才能调用
    modifier onlyOpsForCentralBank () {
        require(opsForCentralBank[msg.sender] == 1);
        _;
    }

    // 修改运营账户状态
    function setOpsForCentralBank (address _operator, uint8 _state) public onlyOwner {
        require(_state <= 2);
        opsForCentralBank[_operator] = _state;
    }


    // 得到激活的时候给粉丝的eth数量
    function getInitEthForFans() public view returns (uint256 ethForFans) {
        return initEthForFans;
    }

    // 得到现在投注的总人数
    function getDailyBlockNumber() public view returns (uint256 blockNumber) {
        return dailyBlockNumber;
    }

    // 得到现在投注的总人数
    function getDepositAccount() public view returns (uint256 deposit) {
        return totalDepositNumber;
    }

    // 得到最近一次更新掩码的区块号
    function getLastUpdateMaskBlockNum() public view returns (uint256 blockNumber) {
        return lastUpdateMaskBlockNum;
    }

    // 得到账号投注金额
    function getDepositAmount(address eth_address) public view returns (uint256 amount) {
        return depositBox[eth_address];
    }

    // 得到账号序号
    function getDepositIndex(address eth_address) public view returns (uint256 index) {
        return depositIndex[eth_address];
    }

    // 得到现在掩码
    function getCurrentMask() public view returns (uint256 mask) {
        return currentMask;
    }

    // 得到最小投注金额
    function getMinimumDeposit() public view returns (uint256 deposit) {
        return minimumDeposit;
    }

    // 得到最大投注金额
    function getMaximumDeposit() public view returns (uint256 deposit) {
        return maximumDeposit;
    }

    // 得到每天获得奖励的人数
    function getDailyLuckyNumber() public view returns (uint256 luckyNumber) {
        return dailyLuckyNumber;
    }

    // 必须有这个匿名payable方法，才可以往合约里面存入ether
    function () public payable {}

    // 修改每天得到奖励人数
    function setDailyLuckyNumber(uint256 _dailyLuckyNumber) public onlyOwner {
        dailyLuckyNumber = _dailyLuckyNumber;
    }

    // 修改激活的时候给粉丝的eth数量
    function setInitEthForFans(uint256 _initEthForFans) public onlyOwner {
        initEthForFans = _initEthForFans;
    }

    // 修改每天产生的区块数量
    function setDailyBlockNumber(uint256 _dailyBlockNumber) public onlyOwner {
        dailyBlockNumber = _dailyBlockNumber;
    }

    // 查询账户激活状态
    function getActivate (address _account) public view returns(uint8 status) {
        return activateBox[_account];
    }

    // 修改账户最小的投注金额
    function setMinimumDeposit (uint256 _minimumDeposit) public onlyOwner {
        require (_minimumDeposit < maximumDeposit);
        minimumDeposit = _minimumDeposit;
    }

    // 修改账户最大的投注金额
    function setMaximumDeposit (uint256 _maximumDeposit) public onlyOwner {
        require (minimumDeposit < _maximumDeposit);
        maximumDeposit = _maximumDeposit;
    }

    /*
     * 账户激活
     * 1、转账一笔初始token给到_account
     * 2、将_account记录为有效的激活账户
     */
    function accountActivate (address _account) public onlyOpsForAirDropPool {
        require (activateBox[_account] == 0);          // 未激活过的账户才可以执行激活
        require (airDropPool >= initStarCoin);
        require (_account != address(0));
        // 从协约的账户中，给粉丝eth
        _account.transfer(initEthForFans);

        // 转账token
        airDropPool = airDropPool.sub(initStarCoin);
        if (depositIndex[_account] == 0) {
            nextDepositIndex = nextDepositIndex + 1;
            depositIndex[_account] = nextDepositIndex;
        }

        depositBox[_account] = initStarCoin;
        totalDepositNumber += 1;

        // 激活账户
        activateBox[_account] = 1;
        activateTime[_account] = now;

        Activate(_account);
    }

    // 存入token
    function deposit (uint256 _amount) public whenNotPaused onlyActivate returns (bool success) {
        require(balances[msg.sender] >= _amount);
        require(depositIndex[msg.sender] > 0);
        require(depositBox[msg.sender].add(_amount) >= minimumDeposit);
        require(depositBox[msg.sender].add(_amount) <= maximumDeposit);

        if (depositBox[msg.sender] < minimumDeposit) {
            totalDepositNumber += 1;
        }
        // 增加本金
        balances[msg.sender] = balances[msg.sender].sub(_amount);
        depositBox[msg.sender] = depositBox[msg.sender].add(_amount);
        return true;
    }

    function updateMask() private {
        uint256 rate = dailyBlockNumber * totalDepositNumber / dailyLuckyNumber;
        uint256 newMask = 1;
        for (uint256 i = 0; i < 30; i++) {
            if (newMask > rate) {
                break;
            } else {
                newMask = newMask * 2;
            }
        }
        currentMask = newMask - 1;
    }

    function heartbeat (uint256 win_number) public whenNotPaused onlyActivate {

        require(depositBox[msg.sender] >= minimumDeposit);
        require(depositBox[msg.sender] <= maximumDeposit);
        require(depositIndex[msg.sender] > 0);
        // 更新掩码每隔100个块
        if (block.number - lastUpdateMaskBlockNum > 100) {
            updateMask();
            lastUpdateMaskBlockNum = block.number;
        }

        if (win_number + 50 < block.number) {
            return;
        }

        if (win_number > block.number) {
            return;
        }

        if (win_number <= lastWinBlockNumber[msg.sender]) {
            return;
        }

        uint256 index = depositIndex[msg.sender];
        bool validWinner = false;
        bytes32 blockHash = blockhash(win_number);

        if ((uint256(blockHash) & currentMask) == (index & currentMask)) {
            validWinner = true;
            lastWinBlockNumber[msg.sender] = win_number;
        }

        if (validWinner) {
            uint256 scale = uint256(blockHash[0] & 0x0f);
            uint256 base = depositBox[msg.sender];
            uint256 wonCoin = base.mul(scale + 1).div(rewardScale);
            if (dailyRewardPool < wonCoin) {
                wonCoin = dailyRewardPool;
            }
            dailyRewardPool = dailyRewardPool.sub(wonCoin);
            balances[msg.sender] = balances[msg.sender].add(wonCoin);
            WinStarCoin(msg.sender, wonCoin);
        }
    }
    
    /*
     * 取出token
     *   _amount=0，表示全部取出
     *   支持部分取出
     */
    function withdraw (uint256 _amount) public whenNotPaused onlyActivate returns (bool success) {

        // 取出token
        if (_amount == 0) {
            // 全部取出
            require ((activateBox[msg.sender] == 3) || (now > activateTime[msg.sender] + fansLockDuration));
            uint256 amount = depositBox[msg.sender];
            depositBox[msg.sender] = 0;
            balances[msg.sender] = balances[msg.sender].add(amount);
            totalDepositNumber = totalDepositNumber - 1;
        }
        else {
            // 部分取出
            assert (depositBox[msg.sender] >= _amount + minimumDeposit);
            depositBox[msg.sender] = depositBox[msg.sender].sub(_amount);
            balances[msg.sender] = balances[msg.sender].add(_amount);
        }
        return true;
    }

    // 拨款到每天的奖池
    function allocateDailyRewardPool(uint256 _tokenAmount) public whenNotPaused onlyOpsForRewardPool {
        require (rewardPool >= _tokenAmount);
        dailyRewardPool = dailyRewardPool.add(_tokenAmount);
        rewardPool = rewardPool.sub(_tokenAmount);
        ToDailyRewardPool(_tokenAmount);
    }

    // 从运营账号转钱出来
    function transferFromOperatorPool (address _account, uint256 _tokenAmount) public whenNotPaused onlyOpsForOperatorPool {
        require (operatorPool >= _tokenAmount);
        operatorPool = operatorPool.sub(_tokenAmount);
        balances[_account] = balances[_account].add(_tokenAmount);
    }

    // 从中央银行账号转钱出来
    function transferFromCentralBank (address _account, uint256 _tokenAmount) public whenNotPaused onlyOpsForCentralBank {
        require (centralBank >= _tokenAmount);
        centralBank = centralBank.sub(_tokenAmount);
        balances[_account] = balances[_account].add(_tokenAmount);
        // 抛出事件给运营监控
        FromCentralBank(_account, _tokenAmount);
    }

    // 存款到运营账户
    function depositToOperatorPool (uint256 _amount) public whenNotPaused returns (bool success) {
        require(balances[msg.sender] >= _amount);
        balances[msg.sender] = balances[msg.sender].sub(_amount);
        operatorPool = operatorPool.add(_amount);
        return true;
    }

    // 存款到挖矿账户
    function depositToRewardPool (uint256 _amount) public whenNotPaused returns (bool success) {
        require(balances[msg.sender] >= _amount);
        balances[msg.sender] = balances[msg.sender].sub(_amount);
        rewardPool = rewardPool.add(_amount);
        return true;
    }

    // 存款到空投账户
    function depositToAirDropPool (uint256 _amount) public whenNotPaused returns (bool success) {
        require(balances[msg.sender] >= _amount);
        balances[msg.sender] = balances[msg.sender].sub(_amount);
        airDropPool = airDropPool.add(_amount);
        return true;
    }

    // 存款到中央银行
    function depositToCentralBank (uint256 _amount) public whenNotPaused returns (bool success) {
        require(balances[msg.sender] >= _amount);
        balances[msg.sender] = balances[msg.sender].sub(_amount);
        centralBank = centralBank.add(_amount);
        // 抛出事件给运营监控
        ToCentralBank(msg.sender, _amount);
        return true;
    }

    // 得到每个币池的数量
    function getOperatorPool() public view returns (uint256 amount) {
        return operatorPool;
    }

    function getRewardPool() public view returns (uint256 amount) {
        return rewardPool;
    }

    function getAirDropPool() public view returns (uint256 amount) {
        return airDropPool;
    }

    function getCentralBank() public view returns (uint256 amount) {
        return centralBank;
    }

    function getDailyRewardPool() public view returns (uint256 amount) {
        return dailyRewardPool;
    }

    // 查询每个操作队列权限
    function getStateOperatorPool(address _account) public view returns (uint256 state) {
        return opsForOperatorPool[_account];
    }

    function getStateRewardPool(address _account) public view returns (uint256 state) {
        return opsForRewardPool[_account];
    }

    function getStateAirDropPool(address _account) public view returns (uint256 state) {
        return opsForAirDropPool[_account];
    }

    function getStateCentralBank(address _account) public view returns (uint256 state) {
        return opsForCentralBank[_account];
    }

    function getAccountOperator() public view returns (address operator_address) {
        return depositAccountOperator;
    }

}
