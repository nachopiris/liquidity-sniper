pragma solidity >=0.6.0 <0.8.0;

interface ICustomRouter {
    function swapExactTokensForTokens(
        uint256[] calldata amounts,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;

    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);
}
