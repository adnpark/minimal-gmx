// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Vault is ReentrancyGuard {
    struct Position {
        uint256 size; // 해당 포지션의 전체 사이즈
        uint256 collateral; // 담보 토큰 수량
        uint256 averagePrice; // 해당 포지션의 평균 가격(진입가격인듯?)
        uint256 entryFundingRate; // TODO: what is this? 
        uint256 reserveAmount;  // TODO: what is this? 담보물의 
        int256 realisedPnl;
        uint256 lastIncreasedTime; // 마지막으로 increase한 시간
    }

    bool public includeAmmPrice = true;
    bool public useSwapPricing = false; // TODO: What is this?

    // reservedAmounts tracks the number of tokens reserved for open leverage positions
    mapping (address => uint256) public override reservedAmounts;

    // guaranteedUsd tracks the amount of USD that is "guaranteed" by opened leverage positions
    // this value is used to calculate the redemption values for selling of USDG
    // this is an estimated amount, it is possible for the actual guaranteed value to be lower
    // in the case of sudden price decreases, the guaranteed value should be corrected
    // after liquidations are carried out
    mapping (address => uint256) public override guaranteedUsd;

    // positions tracks all open positions
    mapping(bytes32 => Position) public positions;

    event IncreasePosition(
        bytes32 key,
        address account,
        address collateralToken,
        address indexToken,
        uint256 collateralDelta,
        uint256 sizeDelta,
        bool isLong,
        uint256 price,
        uint256 fee
    );
    event DecreasePosition(
        bytes32 key,
        address account,
        address collateralToken,
        address indexToken,
        uint256 collateralDelta,
        uint256 sizeDelta,
        bool isLong,
        uint256 price,
        uint256 fee
    );
    event LiquidatePosition(
        bytes32 key,
        address account,
        address collateralToken,
        address indexToken,
        bool isLong,
        uint256 size,
        uint256 collateral,
        uint256 reserveAmount,
        int256 realisedPnl,
        uint256 markPrice
    );

    /**
     * 
     */
    function increasePosition(address _account, address _collateralToken, address _indexToken, uint256 _sizeDelta, bool _isLong) external nonReentrant {
        /**
            1. updateCumulativeFundingRate 
            2. get position key with parameters
            3. get price from indexToken
            
         */
         // TODO: add validation rules


         updateCumulativeFundingRate(_collateralToken, _indexToken);
         
         // 동일 담보, 동일 인덱스, 동일 포지션이면 같은 키를 가진다. 
         bytes32 key = getPositionKey(_account, _collateralToken, _indexToken, _isLong);
         Position storage position = positions[key];
         
         // Long 포지션이면 index 토큰의 최대가격, Short 포지션이면 최소가격을 가져온다.
         uint256 price = isLong ? getMaxPrice(_indexToken) : getMinPrice(_indexToken);

        // position을 처음생성한다면 가져온 price가 averagePrice가 됨
         if (position.size == 0) {
            position.averagePrice = price;
         }

        if (position.size > 0 && _sizeDelta > 0 ) {
            position.averagePrice = getNextAveragePrice(_indexToken, position.size, position.averagePrice, _isLong, price, _sizeDelta, position.lastIncreasedTime);
        }

        uint256 fee = _collectMarginFees(_account, _collateralToken, _indexToken, _isLong, _sizeDelta, position.size, position.entryFundingRate);
        uint256 collateralDelta = _transferIn(_collateralToken);
        uint256 collateralDeltaUsd = tokenToUsdMin(_collateralToken, collateralDelta);

        position.collateral = position.collateral + collateralDelta - fee;
        position.entryFundingRate = getEntryFundingRate(_collateralToken, _indexToken, _isLong); // TODO: funding rate에 대한 개념은 다시 잡자
        position.size = position.size + _sizeDelta;
        position.lastIncreasedTime = block.timestamp;

        require(position.size > 0, "Vault: position size cannot be zero");
        validateLiquidation(_account, _collateralToken, _indexToken, _isLong, true);

        // reserve tokens to pay profits on the position -> TODO: 이 코멘트도 이해가 안되네
        uint256 reserveDelta = usdToTokenMax(_collateralToken, _sizeDelta);
        position.reserveAmount = position.reserveAmount + reserveDelta;
        _increaseReservedAmount(_collateralToken, reserveDelta); // TODO: 담보 토큰의 현재 가격 기준으로 토큰 수량을 계산해서 더해준다? 그냥 담보물 더한것만큼 그냥 더해주면 안되나? 다른 이유가 있나본데?
        

        // TODO: 여기도 이해가 잘안됨...
        if (_isLong) {
            // guaranteedUsd stores the sum of (position.size - position.collateral) for all positions
            // if a fee is charged on the collateral then guaranteedUsd should be increased by that fee amount
            // since (position.size - position.collateral) would have increased by `fee`
            _increaseGuaranteedUsd(_collateralToken, _sizeDelta.add(fee));
            _decreaseGuaranteedUsd(_collateralToken, collateralDeltaUsd);
            // treat the deposited collateral as part of the pool
            _increasePoolAmount(_collateralToken, collateralDelta);
            // fees need to be deducted from the pool since fees are deducted from position.collateral
            // and collateral is treated as part of the pool
            _decreasePoolAmount(_collateralToken, usdToTokenMin(_collateralToken, fee));
        } else {
            if (globalShortSizes[_indexToken] == 0) {
                globalShortAveragePrices[_indexToken] = price;
            } else {
                globalShortAveragePrices[_indexToken] = getNextGlobalShortAveragePrice(_indexToken, price, _sizeDelta);
            }

            _increaseGlobalShortSize(_indexToken, _sizeDelta);
        }

        emit IncreasePosition(key, _account, _collateralToken, _indexToken, collateralDeltaUsd, _sizeDelta, _isLong, price, fee);
        emit UpdatePosition(key, position.size, position.collateral, position.averagePrice, position.entryFundingRate, position.reserveAmount, position.realisedPnl, price);
    }        

    function decreasePosition() external nonReentrant {

    }

    // TODO: why is this function public?
    function updateCumulativeFundingRate() public {
        
    }

    function getPositionKey(address _account, address _collateralToken, address _indexToken, bool _isLong) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_account, _collateralToken, _indexToken, _isLong));
    }

    function getMaxPrice(address _token) public override view returns (uint256) {
        return IVaultPriceFeed(priceFeed).getPrice(_token, true, includeAmmPrice, useSwapPricing);
    }

    function getMinPrice(address _token) public override view returns (uint256) {
        return IVaultPriceFeed(priceFeed).getPrice(_token, false, includeAmmPrice, useSwapPricing);
    }

    // priceFeed에서 min price를 가져와서 token의 tokenAmount 에 해당하는 usd 가치를 계산함
    function tokenToUsdMin(address _token, uint256 _tokenAmount) public override view returns (uint256) {
        if (_tokenAmount == 0) { return 0; }
        uint256 price = getMinPrice(_token);
        uint256 decimals = tokenDecimals[_token];
        return _tokenAmount.mul(price).div(10 ** decimals);
    }


    function usdToTokenMax(address _token, uint256 _usdAmount) public view returns (uint256) {
        if (_usdAmount == 0) { return 0; }
        return usdToToken(_token, _usdAmount, getMinPrice(_token));
    }

    function usdToTokenMin(address _token, uint256 _usdAmount) public view returns (uint256) {
        if (_usdAmount == 0) { return 0; }
        return usdToToken(_token, _usdAmount, getMaxPrice(_token));
    }

    // 입력받은 price 기준으로 주어진 usdAmount가 얼만큼의 tokenAmount인지 계산함 (tokenToUsd와 반대)
    function usdToToken(address _token, uint256 _usdAmount, uint256 _price) public view returns (uint256) {
        if (_usdAmount == 0) { return 0; }
        uint256 decimals = tokenDecimals[_token];
        return _usdAmount * (10 ** decimals) / _price;
    }

    // 단순히 vault 컨트랙트의 token balance를 트래킹함. tokenBalances[_token]로 트래킹을 하기 때문에 abusing은 불가능할듯
    function _transferIn(address _token) private returns (uint256) {
        uint256 prevBalance = tokenBalances[_token];
        uint256 nextBalance = IERC20(_token).balanceOf(address(this));
        tokenBalances[_token] = nextBalance;

        return nextBalance.sub(prevBalance);
    }

    // 토큰을 실제로 transfer out 하면서 동시에 해당 토큰만큼 tokenBalances를 갱신함
    function _transferOut(address _token, uint256 _amount, address _receiver) private {
        IERC20(_token).safeTransfer(_receiver, _amount);
        tokenBalances[_token] = IERC20(_token).balanceOf(address(this));
    }

    function _increaseGuaranteedUsd(address _token, uint256 _usdAmount) private {
        guaranteedUsd[_token] = guaranteedUsd[_token].add(_usdAmount);
        emit IncreaseGuaranteedUsd(_token, _usdAmount);
    }

    function _decreaseGuaranteedUsd(address _token, uint256 _usdAmount) private {
        guaranteedUsd[_token] = guaranteedUsd[_token].sub(_usdAmount);
        emit DecreaseGuaranteedUsd(_token, _usdAmount);
    }
}