pragma solidity >=0.4.24 <0.6.0;

import './StarIMOLottery.sol';
import 'zeppelin-solidity/contracts/token/ERC20/CappedToken.sol';
import 'zeppelin-solidity/contracts/token/ERC20/PausableToken.sol';
import 'zeppelin-solidity/contracts/token/ERC20/DetailedERC20.sol';

/*
 * 明星币合约
 * 1、CappedToken 拥有者可以增发token(mint)，但token总量有上限(cap)
 * 2、PausableToken 拥有者可以暂停所有交易功能
 * 3、StarIMOLottery
 *    设备激活：转账token，激活账户
 *    允许激活账户存入token，可以获得随机奖励
 *    支持账户禁用
 */

contract StarCoinLottery is PausableToken, StarIMOLottery, DetailedERC20  {
    /*
	 *  明星币合约
	 *  totalSupply 初始token发行量，存在发布者账户上
	 *  cap         token发行总量不能超过cap
	 *  profitRate  年利率，百分比。传入8是年利率8%
	 *  name        token名称
	 *  decimals    token位数，建议18位（位数太小的话，会出现利息小于0无法取出）
	 *  symbol      token符号
	 *  operator    运营账户
	 */
    function StarCoinLottery(string _name, uint8 _decimals, string _symbol, address _operator,
        uint256 _minimum_deposit, uint256 _maximum_deposit, uint256 _dailyLuckyNumber, uint256  _operatorPool,
        uint256 _rewardPool, uint256 _airDropPool, uint256 _rewardScale) public
        StarIMOLottery(_operator, _minimum_deposit, _maximum_deposit, _dailyLuckyNumber,  _operatorPool, _rewardPool,
            _airDropPool, _rewardScale)
        DetailedERC20(_name, _symbol, _decimals) {}
}
