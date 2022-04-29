// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.6.0 <0.8.0;

import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "./interfaces/IWETH.sol";
import "./interfaces/ICustomRouter.sol";

contract Trigger is Ownable {
    using SafeMath for uint256;

    address private constant wbnb;

    address payable private administrator;
    address private customRouter;

    uint256 private wbnbIn;
    uint256 private minTokenOut;

    address private tokenToBuy;
    address private tokenPaired;

    bool private snipeLock;

    constructor(address _wbnb) public {
        administrator = payable(msg.sender);
        wbnb = _wbnb;
    }

    receive() external payable {
        IWETH(wbnb).deposit{value: msg.value}();
    }

    // Trigger is the smart contract in charge or performing liquidity sniping.
    // Its role is to hold the BNB, perform the swap once ax-50 detect the tx in the mempool and if all checks are passed; then route the tokens sniped to the owner.
    // It requires a first call to configureSnipe in order to be armed. Then, it can snipe on whatever pair no matter the paired token (BUSD / WBNB etc..).
    // This contract uses a custtom router which is a copy of uniswapv2 router but with modified selectors, so that our tx are more difficult to listen than those directly going through the usual router.

    // perform the liquidity sniping
    function snipeListing() external returns (bool success) {
        require(snipeLock == false, "abort abort");
        require(
            IERC20(wbnb).balanceOf(address(this)) >= wbnbIn,
            "meteme plata raton"
        );

        snipeLock = true;
        IERC20(wbnb).approve(customRouter, wbnbIn);

        address[] memory path;
        if (tokenPaired != wbnb) {
            path = new address[](3);
            path[0] = wbnb;
            path[1] = tokenPaired;
            path[2] = tokenToBuy;
        } else {
            path = new address[](2);
            path[0] = wbnb;
            path[1] = tokenToBuy;
        }

        ICustomRouter(customRouter).swapExactTokensForTokens(
            wbnbIn,
            minTokenOut,
            path,
            address(this),
            block.timestamp + 120
        );

        uint256 sellTestAmount = IERC20(tokenToBuy)
            .balanceOf(address(this))
            .div(100);

        IERC20(tokenToBuy).approve(customRouter, sellTestAmount);

        uint[] amounts = ICustomRouter(customRouter).getAmountsOut(
            sellTestAmount,
            [tokenToBuy, tokenPaired]
        );

        ICustomRouter(customRouter).swapExactTokensForTokens(
            sellTestAmount,
            amounts[1].sub(amounts[1].div(10)),
            [tokenToBuy, tokenPaired],
            administrator,
            block.timestamp + 120
        );

        return true;
    }

    function getAdministrator()
        external
        view
        onlyOwner
        returns (address payable)
    {
        return administrator;
    }

    function setAdministrator(address payable _newAdmin)
        external
        onlyOwner
        returns (bool success)
    {
        administrator = _newAdmin;
        return true;
    }

    function getCustomRouter() external view onlyOwner returns (address) {
        return customRouter;
    }

    function setCustomRouter(address _newRouter)
        external
        onlyOwner
        returns (bool success)
    {
        customRouter = _newRouter;
        return true;
    }

    // must be called before sniping
    function configureSnipe(
        address _tokenPaired,
        uint256 _amountIn,
        address _tokenToBuy,
        uint256 _amountOutMin
    ) external onlyOwner returns (bool success) {
        tokenPaired = _tokenPaired;
        wbnbIn = _amountIn;
        tokenToBuy = _tokenToBuy;
        minTokenOut = _amountOutMin;
        snipeLock = false;
        return true;
    }

    function getSnipeConfiguration()
        external
        view
        onlyOwner
        returns (
            address,
            uint256,
            address,
            uint256,
            bool
        )
    {
        return (tokenPaired, wbnbIn, tokenToBuy, minTokenOut, snipeLock);
    }

    // here we precise amount param as certain bep20 tokens uses strange tax system preventing to send back whole balance
    function emmergencyWithdrawToken(address _token, uint256 _amount)
        external
        onlyOwner
        returns (bool success)
    {
        require(
            IERC20(_token).balanceOf(address(this)) >= _amount,
            "not enough tokens in contract"
        );
        IERC20(_token).transfer(administrator, _amount);
        return true;
    }

    // shouldn't be of any use as receive function automatically wrap bnb incoming
    function emmergencyWithdrawBnb() external onlyOwner returns (bool success) {
        require(address(this).balance > 0, "contract has an empty BNB balance");
        administrator.transfer(address(this).balance);
        return true;
    }
}
