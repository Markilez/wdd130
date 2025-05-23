//+------------------------------------------------------------------+
//|                  EnhancedPriceActionScalperEA.mq5               |
//|                        Copyright 2025, MetaQuotes Software Corp. |
//|                                       https://www.mql5.com       |
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window

// Input Parameters
input group "==== Risk Management ===="
input double TakeProfit = 300;              // Take Profit in points (1:3 ratio)
input double StopLoss = 100;                // Stop Loss in points (1:3 ratio)
input bool UseEAStopLoss = true;            // Use EA-based stop loss
input double UserDefinedStopLoss = 0;       // User-defined stop loss (0 = use EA-based stop loss)
input double RiskPercentage = 1.0;           // Risk percentage of account balance
input double UserLotSize = 0.20;             // User-defined lot size
input int MagicNumber = 10101;               // Unique Magic Number for this EA
input int MaxOpenPositions = 3;              // Max open positions
input double IndividualMaxLoss = 20.0;       // Maximum loss threshold per position
input double IndividualMaxProfit = 30.0;     // Maximum profit threshold per position

input group "==== Trading Rules ===="
input ENUM_TIMEFRAMES TimeFrame = PERIOD_M5; // Timeframe
input int TradeCooldownSeconds = 30;          // Trade cooldown period
input int SupportResistanceLookback = 30;     // S/R lookback
input double PinBarThreshold = 0.6;           // Pin bar ratio threshold
input int InsideBarLookback = 2;              // Inside bar lookback
input double VolumeSpikeMultiplier = 2.0;     // Volume spike multiplier
input bool RequireCloseConfirmation = true;   // Require candle close confirmation

input group "==== CCI Filter ===="
input int CCIPeriod = 14;                     // CCI period
input double CCITrendThreshold = 100;         // CCI threshold
input bool UseCCIFilter = true;               // Enable CCI filter

input group "==== Bollinger Bands ===="
input int BandsPeriod = 50;                   // Bollinger Bands period
input double BandsDeviation = 2.0;            // Bollinger Bands deviation
input bool UseBollingerBands = true;          // Enable Bollinger Bands filter
input bool UseMiddleBandForTP = true;         // Use middle band for TP
input double CustomTPDistance = 0;            // Custom TP distance (0 = use middle band)

input group "==== Trendline Settings ===="
input int TrendlineLookback = 100;            // Trendline lookback period
input int MinTouchPoints = 3;                 // Minimum touch points for valid trendline
input bool UseTrendlines = true;              // Enable trendline filter

input group "==== Profit Protection ===="
input double LockInProfitThreshold = 7;       // Lock profit threshold ($)
input double TrailingStopDistance = 30;       // Trailing stop distance (points)
input double MinStopDistance = 10;            // Minimum SL distance above entry (points)
input bool EnableTrailingStop = true;         // Enable trailing stop

// Global Variables
long chartId;
datetime lastTradeTime = 0;
double bestPrice = 0.0;
bool isProfitsLocked = false;
double lastHigh = 0;
double lastLow = 0;
double supportLevel = 0;
double resistanceLevel = 0;
double dailyEquityHigh;
double dailyEquityLow;
double dailyProfit = 0;
double dailyLoss = 0;
int cciHandle;
int bandsHandle;
double upperBand[], middleBand[], lowerBand[];
double trendlineSlope = 0;
double trendlineIntercept = 0;
bool uptrend = false;
bool downtrend = false;

//+------------------------------------------------------------------+
//| Expert Initialization Function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    chartId = ChartID();
    dailyEquityHigh = AccountInfoDouble(ACCOUNT_EQUITY);
    dailyEquityLow = dailyEquityHigh;
    dailyProfit = 0;
    dailyLoss = 0;

    // Initialize indicators
    cciHandle = iCCI(NULL, TimeFrame, CCIPeriod, PRICE_TYPICAL);
    bandsHandle = iBands(NULL, TimeFrame, BandsPeriod, 0, BandsDeviation, PRICE_CLOSE);

    ArraySetAsSeries(upperBand, true);
    ArraySetAsSeries(middleBand, true);
    ArraySetAsSeries(lowerBand, true);

    CalculateSupportResistance();
    CalculateTrendline();

    Print("EA initialized successfully on chart ID: ", chartId);
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert Deinitialization Function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    IndicatorRelease(cciHandle);
    IndicatorRelease(bandsHandle);
    Print("EA deinitialized with reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert Tick Function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    if (ChartID() != chartId) return;

    UpdateDailyProfitLoss();
    if (IsNewBar())
    {
        CalculateSupportResistance();
        CalculateTrendline();
        UpdateBollingerBands();
    }

    // Check trading conditions
    if (CheckTradingAllowed() && CheckTradeConditions() && CountOpenPositions() < MaxOpenPositions)
    {
        OpenTrade();
    }

    ManageOpenTrades();
}

//+------------------------------------------------------------------+
//| Update Bollinger Bands data                                      |
//+------------------------------------------------------------------+
void UpdateBollingerBands()
{
    CopyBuffer(bandsHandle, 0, 0, 3, upperBand);
    CopyBuffer(bandsHandle, 1, 0, 3, middleBand);
    CopyBuffer(bandsHandle, 2, 0, 3, lowerBand);
}

//+------------------------------------------------------------------+
//| Calculate Trendline                                              |
//+------------------------------------------------------------------+
void CalculateTrendline()
{
    double prices[];
    ArrayResize(prices, TrendlineLookback);
    ArraySetAsSeries(prices, true);

    CopyClose(NULL, TimeFrame, 0, TrendlineLookback, prices);

    // Find significant highs and lows for trendline calculation
    int touchPoints = 0;
    double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;

    // Check for uptrend (higher lows)
    for(int i = 2; i < TrendlineLookback - 1; i++)
    {
        if(prices[i] < prices[i-1] && prices[i] < prices[i+1]) // Found a low
        {
            sumX += i;
            sumY += prices[i];
            sumXY += i * prices[i];
            sumX2 += i * i;
            touchPoints++;
        }
    }

    if(touchPoints >= MinTouchPoints)
    {
        // Calculate trendline parameters (y = slope*x + intercept)
        double denominator = touchPoints * sumX2 - sumX * sumX;
        if(denominator != 0)
        {
            trendlineSlope = (touchPoints * sumXY - sumX * sumY) / denominator;
            trendlineIntercept = (sumY - trendlineSlope * sumX) / touchPoints;
            uptrend = trendlineSlope > 0;
            downtrend = trendlineSlope < 0;
            return;
        }
    }

    // If no uptrend, check for downtrend (lower highs)
    touchPoints = 0;
    sumX = sumY = sumXY = sumX2 = 0;

    for(int i = 2; i < TrendlineLookback - 1; i++)
    {
        if(prices[i] > prices[i-1] && prices[i] > prices[i+1]) // Found a high
        {
            sumX += i;
            sumY += prices[i];
            sumXY += i * prices[i];
            sumX2 += i * i;
            touchPoints++;
        }
    }

    if(touchPoints >= MinTouchPoints)
    {
        double denominator = touchPoints * sumX2 - sumX * sumX;
        if(denominator != 0)
        {
            trendlineSlope = (touchPoints * sumXY - sumX * sumY) / denominator;
            trendlineIntercept = (sumY - trendlineSlope * sumX) / touchPoints;
            uptrend = trendlineSlope > 0;
            downtrend = trendlineSlope < 0;
            return;
        }
    }

    // No clear trend
    uptrend = false;
    downtrend = false;
}

//+------------------------------------------------------------------+
//| Check if price is near Bollinger Band                            |
//+------------------------------------------------------------------+
bool IsNearBand(bool isLowerBand)
{
    double currentPrice = iClose(NULL, TimeFrame, 0);
    double bandValue = isLowerBand ? lowerBand[0] : upperBand[0];
    double distance = MathAbs(currentPrice - bandValue);
    double threshold = 10 * _Point; // 10 pips threshold

    return distance <= threshold;
}

//+------------------------------------------------------------------+
//| Update daily profit/loss tracking                                |
//+------------------------------------------------------------------+
void UpdateDailyProfitLoss()
{
    double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    if(currentEquity > dailyEquityHigh) dailyEquityHigh = currentEquity;
    if(currentEquity < dailyEquityLow) dailyEquityLow = currentEquity;

    // Calculate daily profit/loss from closed positions
    dailyProfit = 0;
    dailyLoss = 0;
    HistorySelect(TimeCurrent() - 86400, TimeCurrent());

    for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = HistoryDealGetTicket(i);
        if(HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_OUT &&
           HistoryDealGetInteger(ticket, DEAL_MAGIC) == MagicNumber &&
           HistoryDealGetString(ticket, DEAL_SYMBOL) == _Symbol)
        {
            double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
            if(profit > 0) dailyProfit += profit;
            else dailyLoss += MathAbs(profit);
        }
    }
}

//+------------------------------------------------------------------+
//| Check if trading is allowed                                      |
//+------------------------------------------------------------------+
bool CheckTradingAllowed()
{
    if(TimeCurrent() - lastTradeTime < TradeCooldownSeconds)
    {
        Print("In cooldown period");
        return false;
    }

    return true; // Removed individual max thresholds check for simplicity
}

//+------------------------------------------------------------------+
//| Calculate Support and Resistance Levels                          |
//+------------------------------------------------------------------+
void CalculateSupportResistance()
{
    double highs[], lows[];
    ArraySetAsSeries(highs, true);
    ArraySetAsSeries(lows, true);

    CopyHigh(NULL, TimeFrame, 0, SupportResistanceLookback, highs);
    CopyLow(NULL, TimeFrame, 0, SupportResistanceLookback, lows);

    lastHigh = highs[ArrayMaximum(highs)];
    lastLow = lows[ArrayMinimum(lows)];

    supportLevel = iLow(NULL, TimeFrame, iLowest(NULL, TimeFrame, MODE_LOW, 5, 1));
    resistanceLevel = iHigh(NULL, TimeFrame, iHighest(NULL, TimeFrame, MODE_HIGH, 5, 1));

    Print("Updated S/R Levels - Support: ", supportLevel, " Resistance: ", resistanceLevel);
}

//+------------------------------------------------------------------+
//| Check for New Bar                                                |
//+------------------------------------------------------------------+
bool IsNewBar()
{
    static datetime lastBarTime = 0;
    datetime currentBarTime = iTime(NULL, TimeFrame, 0);

    if (lastBarTime != currentBarTime)
    {
        lastBarTime = currentBarTime;
        return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| Check Trade Conditions with Multiple Filters                     |
//+------------------------------------------------------------------+
bool CheckTradeConditions()
{
    double currentPrice = iClose(NULL, TimeFrame, 0);
    double currentVolume = iVolume(NULL, TimeFrame, 0);
    double avgVolume = iMA(NULL, TimeFrame, 20, 0, MODE_SMA, VOLUME_TICK);

    // CCI Filter
    double cci[], cciPrev[];
    CopyBuffer(cciHandle, 0, 0, 2, cci);
    ArraySetAsSeries(cci, true);

    bool cciBuySignal = (cci[0] > -CCITrendThreshold && cci[0] > cci[1]);
    bool cciSellSignal = (cci[0] < CCITrendThreshold && cci[0] < cci[1]);

    // Bollinger Bands Filter
    bool bandsBuySignal = IsNearBand(true) && currentPrice > lowerBand[0];
    bool bandsSellSignal = IsNearBand(false) && currentPrice < upperBand[0];

    // Trendline Filter
    bool trendlineBuySignal = uptrend && currentPrice > (trendlineSlope * 0 + trendlineIntercept);
    bool trendlineSellSignal = downtrend && currentPrice < (trendlineSlope * 0 + trendlineIntercept);

    // Price Action Signals
    bool priceActionBuySignal = (CheckPinBar(true) || CheckInsideBarBreakout(true)) && 
                               currentPrice > supportLevel;
    bool priceActionSellSignal = (CheckPinBar(false) || CheckInsideBarBreakout(false)) && 
                                currentPrice < resistanceLevel;

    // Volume Filter
    bool volumeFilter = currentVolume > avgVolume * VolumeSpikeMultiplier;

    // Confirmation Filter
    bool confirmationFilter = RequireCloseConfirmation ? 
                            (priceActionBuySignal ? ConfirmBuySignal() : ConfirmSellSignal()) : 
                            true;

    // Combined Buy Conditions
    bool buyCondition = priceActionBuySignal && volumeFilter && confirmationFilter &&
                       ((UseCCIFilter && cciBuySignal) || !UseCCIFilter) &&
                       ((UseBollingerBands && bandsBuySignal) || !UseBollingerBands) &&
                       ((UseTrendlines && trendlineBuySignal) || !UseTrendlines);

    // Combined Sell Conditions
    bool sellCondition = priceActionSellSignal && volumeFilter && confirmationFilter &&
                        ((UseCCIFilter && cciSellSignal) || !UseCCIFilter) &&
                        ((UseBollingerBands && bandsSellSignal) || !UseBollingerBands) &&
                        ((UseTrendlines && trendlineSellSignal) || !UseTrendlines);

    return buyCondition || sellCondition;
}

//+------------------------------------------------------------------+
//| Confirm Buy/Sell Signals                                         |
//+------------------------------------------------------------------+
bool ConfirmBuySignal()
{
    return iClose(NULL, TimeFrame, 0) > iClose(NULL, TimeFrame, 1);
}

bool ConfirmSellSignal()
{
    return iClose(NULL, TimeFrame, 0) < iClose(NULL, TimeFrame, 1);
}

//+------------------------------------------------------------------+
//| Check for Valid Pin Bar Pattern                                  |
//+------------------------------------------------------------------+
bool CheckPinBar(bool isBuySignal)
{
    double open = iOpen(NULL, TimeFrame, 0);
    double high = iHigh(NULL, TimeFrame, 0);
    double low = iLow(NULL, TimeFrame, 0);
    double close = iClose(NULL, TimeFrame, 0);
    
    double bodySize = MathAbs(close - open);
    double upperWick = high - MathMax(open, close);
    double lowerWick = MathMin(open, close) - low;
    
    if (isBuySignal)
    {
        return (close > open) && (lowerWick >= bodySize * PinBarThreshold) && (upperWick < bodySize * 0.5);
    }
    else
    {
        return (close < open) && (upperWick >= bodySize * PinBarThreshold) && (lowerWick < bodySize * 0.5);
    }
}

//+------------------------------------------------------------------+
//| Check for Inside Bar Breakout                                    |
//+------------------------------------------------------------------+
bool CheckInsideBarBreakout(bool isBuySignal)
{
    double motherHigh = iHigh(NULL, TimeFrame, 1);
    double motherLow = iLow(NULL, TimeFrame, 1);
    
    bool isInsideBar = true;
    for (int i = 2; i <= InsideBarLookback; i++)
    {
        if (iHigh(NULL, TimeFrame, i) > motherHigh || iLow(NULL, TimeFrame, i) < motherLow)
        {
            isInsideBar = false;
            break;
        }
    }
    
    if (!isInsideBar) return false;
    
    if (isBuySignal) return iHigh(NULL, TimeFrame, 0) > motherHigh;
    else return iLow(NULL, TimeFrame, 0) < motherLow;
}

//+------------------------------------------------------------------+
//| Open Trade Function                                              |
//+------------------------------------------------------------------+
void OpenTrade()
{
    if (TimeCurrent() - lastTradeTime < TradeCooldownSeconds) return;
    if (CountOpenPositionsInDirection(CheckPinBar(true) || CheckInsideBarBreakout(true)) > 0) return;

    double price, sl, tp;
    ENUM_ORDER_TYPE orderType;
    bool isBuySignal = CheckPinBar(true) || CheckInsideBarBreakout(true);
    
    // Set initial price, SL, and TP according to the trade direction
    if (isBuySignal)
    {
        price = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_ASK), _Digits);
        if(UseEAStopLoss)
            sl = NormalizeDouble(price - StopLoss * _Point, _Digits);
        else if(UserDefinedStopLoss > 0)
            sl = NormalizeDouble(price - UserDefinedStopLoss * _Point, _Digits);
        else
            sl = 0;

        tp = NormalizeDouble(price + TakeProfit * _Point, _Digits);  // TP for buyers
        orderType = ORDER_TYPE_BUY;
    }
    else
    {
        price = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_BID), _Digits);
        if(UseEAStopLoss)
            sl = NormalizeDouble(price + StopLoss * _Point, _Digits);
        else if(UserDefinedStopLoss > 0)
            sl = NormalizeDouble(price + UserDefinedStopLoss * _Point, _Digits);
        else
            sl = 0;

        tp = NormalizeDouble(price - TakeProfit * _Point, _Digits);  // TP for sellers
        orderType = ORDER_TYPE_SELL;
    }

    // Create a trade request
    MqlTradeRequest request = {};
    MqlTradeResult result = {};

    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = CalculateLotSize();
    request.price = price;
    request.sl = (sl > 0) ? sl : 0;
    request.tp = (tp > 0) ? tp : 0;
    request.type = orderType;
    request.type_filling = ORDER_FILLING_FOK;
    request.magic = MagicNumber;
    request.comment = "MultiStep"; // Trade comment

    // Send the trading request
    if (!OrderSend(request, result))
    {
        Print("OrderSend failed, error code: ", GetLastError());
    }
    else if (result.retcode != TRADE_RETCODE_DONE)
    {
        Print("Trade request failed, retcode: ", result.retcode);
    }
    else
    {
        Print("Trade opened successfully, ticket: ", result.order);
        lastTradeTime = TimeCurrent();
        bestPrice = price;
        isProfitsLocked = false;
    }
}

//+------------------------------------------------------------------+
//| Count Open Positions in Direction                                |
//+------------------------------------------------------------------+
int CountOpenPositionsInDirection(bool isBuySignal)
{
    int count = 0; 
    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if (PositionSelectByTicket(ticket) && 
            PositionGetString(POSITION_SYMBOL) == _Symbol && 
            PositionGetInteger(POSITION_MAGIC) == MagicNumber)
        {
            if ((isBuySignal && PositionGetInteger(POSITION_TYPE) == ORDER_TYPE_BUY) ||
                (!isBuySignal && PositionGetInteger(POSITION_TYPE) == ORDER_TYPE_SELL))
            {
                count++;
            }
        }
    }
    return count;
}

//+------------------------------------------------------------------+
//| Calculate Lot Size                                               |
//+------------------------------------------------------------------+
double CalculateLotSize()
{
    if (UserLotSize > 0) return UserLotSize;

    double accountEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    double riskAmount = accountEquity * (RiskPercentage / 100);
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double pointValue = tickValue / _Point;
    
    double effectiveStopLoss = UseEAStopLoss ? StopLoss : (UserDefinedStopLoss > 0 ? UserDefinedStopLoss : StopLoss);
    double lotSize = riskAmount / (effectiveStopLoss * pointValue);
    
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    
    lotSize = MathRound(lotSize / lotStep) * lotStep;
    return MathMin(MathMax(lotSize, minLot), maxLot);
}

//+------------------------------------------------------------------+
//| Count Open Positions                                             |
//+------------------------------------------------------------------+
int CountOpenPositions()
{
    int count = 0; 
    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if (PositionSelectByTicket(ticket) && 
            PositionGetString(POSITION_SYMBOL) == _Symbol && 
            PositionGetInteger(POSITION_MAGIC) == MagicNumber)
        {
            count++;
        }
    }
    return count;
}

//+------------------------------------------------------------------+
//| Manage Open Trades with Improved Stop Logic                      |
//+------------------------------------------------------------------+
void ManageOpenTrades()
{
    for (int i = 0; i < PositionsTotal(); i++)
    {
        ulong ticket = PositionGetTicket(i);
        if (!PositionSelectByTicket(ticket) || PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;

        double currentPrice = PositionGetInteger(POSITION_TYPE) == ORDER_TYPE_BUY ? 
                             SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
                             SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
        double currentSL = PositionGetDouble(POSITION_SL);
        double positionProfit = PositionGetDouble(POSITION_PROFIT);
        
        // Check for individual position profit/loss thresholds
        double individualLoss = -positionProfit; // Since profit can be negative
        double individualProfit = positionProfit;

        if (individualLoss >= IndividualMaxLoss || individualProfit >= IndividualMaxProfit)
        {
            // Close position if limits are reached
            MqlTradeRequest closeRequest = {};
            MqlTradeResult closeResult = {};
            closeRequest.action = TRADE_ACTION_DEAL;
            closeRequest.symbol = _Symbol;
            closeRequest.volume = PositionGetDouble(POSITION_VOLUME);
            closeRequest.type = (PositionGetInteger(POSITION_TYPE) == ORDER_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
            closeRequest.position = ticket;
            closeRequest.comment = "Closed due to threshold trigger";
            if (!OrderSend(closeRequest, closeResult) || closeResult.retcode != TRADE_RETCODE_DONE)
            {
                Print("Failed to close position, error code: ", GetLastError());
            }
            continue; // Move to the next position
        }

        // Calculate minimum allowed stop level
        double minStopLevel = openPrice + (PositionGetInteger(POSITION_TYPE) == ORDER_TYPE_BUY ? 
                                          MinStopDistance * _Point : 
                                          -MinStopDistance * _Point);
        
        // Lock in profits if threshold reached
        if (!isProfitsLocked && positionProfit >= LockInProfitThreshold)
        {
            double newSL = PositionGetInteger(POSITION_TYPE) == ORDER_TYPE_BUY ?
                           currentPrice - TrailingStopDistance * _Point :
                           currentPrice + TrailingStopDistance * _Point;
            
            // Ensure SL is at least MinStopDistance from entry
            if ((PositionGetInteger(POSITION_TYPE) == ORDER_TYPE_BUY && newSL < minStopLevel) ||
                (PositionGetInteger(POSITION_TYPE) == ORDER_TYPE_SELL && newSL > minStopLevel))
            {
                newSL = minStopLevel;
            }

            MqlTradeRequest modifyRequest = {};
            MqlTradeResult modifyResult = {};
            modifyRequest.action = TRADE_ACTION_SLTP;
            modifyRequest.position = ticket;
            modifyRequest.sl = NormalizeDouble(newSL, _Digits);

            if (!OrderSend(modifyRequest, modifyResult))
            {
                Print("Failed to modify SL for profit lock, error code: ", GetLastError());
            }
            else
            {
                isProfitsLocked = true;
                Print("Profits locked for ticket: ", ticket);
            }
        }

        // Apply trailing stop if enabled and profits locked
        if (EnableTrailingStop && isProfitsLocked)
        {
            double trailPrice = PositionGetInteger(POSITION_TYPE) == ORDER_TYPE_BUY ?
                               currentPrice - TrailingStopDistance * _Point :
                               currentPrice + TrailingStopDistance * _Point;
            
            // Ensure trail stop is at least MinStopDistance from entry
            if ((PositionGetInteger(POSITION_TYPE) == ORDER_TYPE_BUY && trailPrice < minStopLevel) ||
                (PositionGetInteger(POSITION_TYPE) == ORDER_TYPE_SELL && trailPrice > minStopLevel))
            {
                trailPrice = minStopLevel;
            }

            if ((PositionGetInteger(POSITION_TYPE) == ORDER_TYPE_BUY && trailPrice > currentSL) ||
                (PositionGetInteger(POSITION_TYPE) == ORDER_TYPE_SELL && trailPrice < currentSL))
            {
                MqlTradeRequest modifyRequest = {};
                MqlTradeResult modifyResult = {};
                modifyRequest.action = TRADE_ACTION_SLTP;
                modifyRequest.position = ticket;
                modifyRequest.sl = NormalizeDouble(trailPrice, _Digits);

                if (!OrderSend(modifyRequest, modifyResult))
                {
                    Print("Failed to modify trailing stop, error code: ", GetLastError());
                }
                else
                {
                    Print("Trailing stop updated for ticket: ", ticket);
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| End of the Expert Advisor Definition                             |
//+------------------------------------------------------------------+