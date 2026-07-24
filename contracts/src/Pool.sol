// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

contract SimplePool {
    IERC20 public token;
    uint256 public ethReserve;
    uint256 public tokenReserve;
    uint256 public constant FEE = 3;
    uint256 public constant FEE_DENOMINATOR = 1000;

    event LiquidityAdded(address indexed provider, uint256 ethAmount, uint256 tokenAmount);
    event Swapped(address indexed user, uint256 ethIn, uint256 tokenOut);
    event TokenSwapped(address indexed user, uint256 ethOut, uint256 tokenIn);

    constructor(address _token) {
        token = IERC20(_token);
    }

    function addLiquidity(uint256 tokenAmount) external payable {
        if (ethReserve > 0) {
            require(
                msg.value * tokenReserve == tokenAmount * ethReserve,
                "ratio mismatch"
            );
        }
        token.transferFrom(msg.sender, address(this), tokenAmount);
        ethReserve += msg.value;
        tokenReserve += tokenAmount;
        emit LiquidityAdded(msg.sender, msg.value, tokenAmount);
    }

    function swapETHForToken(uint256 minTokensOut) external payable returns (uint256) {
        
        require(msg.value > 0,"no eth sent");
        // 验证不是灰尘交易（无效）
        require(msg.value > 21000,"too small values@!");
        uint256 ethAfterFee= (msg.value * (FEE_DENOMINATOR - FEE)) /FEE_DENOMINATOR;
        uint256 k = ethReserve * tokenReserve ;
        // 这个是计算给池子中用户交换的token储备
        uint256 newTokenReserve = k / (ethReserve + ethAfterFee);
        uint256 tokenOut = tokenReserve - newTokenReserve ;
        require(tokenOut > 0,"insufficent output amount");
        require(tokenOut >= minTokensOut,"slippage exceeded");
        // 中间的差值的手续费都给池子里了 msg.value - ethAfterFee = 手续费
        ethReserve += msg.value;
        tokenReserve -= tokenOut;
        token.transfer(msg.sender,tokenOut);
        emit Swapped(msg.sender, msg.value, tokenOut);
        return tokenOut;
    }

    function swapTokenForETH(uint256 minEthOut,uint256 InToken)  external  returns (uint256) {
        require(InToken > 0,"no token sent");
        // 验证不是灰尘交易（无效）
        require(InToken > 21000,"too small values@!");
        uint256 tokenAfterFee = (InToken * (FEE_DENOMINATOR - FEE)) /FEE_DENOMINATOR;
        uint256 k = ethReserve * tokenReserve ;
        // 这个是计算给池子中用户交换的token储备
        uint256 newEthReserve = k / (tokenReserve + tokenAfterFee);
        uint256 ethOut = ethReserve - newEthReserve ;
        require(ethOut > 0,"insufficent output amount");
        require(ethOut >= minEthOut,"slippage exceeded");
        // 中间的差值的手续费都给池子里了 msg.value - ethAfterFee = 手续费
        tokenReserve += InToken;
        token.transferFrom(msg.sender, address(this),InToken);
        ethReserve -= ethOut;
        //怎么转给msg.sender
        (bool success,) = msg.sender.call{value:ethOut}("");
        require(success ,"eth call fail");
        emit TokenSwapped(msg.sender, ethOut, tokenAfterFee);
        return ethOut;
    }

    
}
