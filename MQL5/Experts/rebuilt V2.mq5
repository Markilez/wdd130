//+------------------------------------------------------------------+
//|                EnhancedPriceActionScalperProCombined.mq5       |
//|                        Copyright 2025                            |
//|                                       https://www.mql5.com       |
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window

// Input Parameters
input group "==== Risk Management ===="
input double RiskRewardRatio = 3.0;          // Risk-Reward Ratio (1:3)
input double TakeProfit = 10500;                // Take Profit in points (1:3 ratio)
input double StopLoss = 3000;                  // Stop Loss in points
input bool UseEAStopLoss = true;              // Use EA-based stop loss
input double UserDefinedStopLoss = 0;         // User-defined stop loss (0 = use EA-based stop loss)
input double RiskPercentage = 1.0;            // Risk percentage of account balance
input double UserLotSize = 0.20;              // User-defined lot size
input int MagicNumber = 4586;                 // Unique Magic Number
input int MaxOpenPositions = 5;               // Maximum open positions
input double LockInProfitThreshold = 20;       // Lock-in profit threshold ($)
input double MaxLossThreshold = 100;           // Maximum loss threshold ($)
input double IndividualMaxLoss = 3.0;         // Maximum loss threshold per position
input double IndividualMaxProfit = 9.0;       // Maximum profit threshold per position

input group "==== Trading Rules ===="
input ENUM_TIMEFRAMES TimeFrame = PERIOD_H1;  // Trading timeframe
input int TradeCooldownSeconds = 60;           // Cooldown period between trades
input int SupportResistanceLookback = 50;      // Bars for S/R levels
input double PinBarThreshold = 0.6;            // Pin bar ratio threshold
input int InsideBarLookback = 3;               // Bars for inside bars
input double VolumeSpikeMultiplier = 2.0;      // Volume spike multiplier
input bool RequireCloseConfirmation = true;    // Require candle close confirmation

input group "==== CCI Filter ===="
input int CCIPeriod = 14;                     // CCI period
input double CCITrendThreshold = 100;          // CCI threshold
input bool UseCCIFilter = true;                // Enable CCI filter

input group "==== Moving Average Settings ===="
input int MA_Period = 50;                     // MA period
input ENUM_MA_METHOD MA_Method = MODE_SMA;    // MA method
input color MA_Color = clrGold;                // MA color
input bool UseMABreakout = true;              // Enable MA breakout filter

input group "==== Fibonacci Settings ===="
input ENUM_TIMEFRAMES FibTimeframe = PERIOD_M15; // Fibonacci analysis timeframe
input int FibLookback = 100;                   // Fibonacci lookback period
input bool UseFibonacci = true;                // Enable Fibonacci filter
input double FibRetracementLevel = 0.618;      // Key retracement level (0.382, 0.5, 0.618)
input double FibExtensionLevel = 1.618;        // Key extension level (1.272, 1.414, 1.618)

input group "==== Trendline Settings ===="
input int TrendlineLookback = 100;             // Trendline lookback period
input int MinTouchPoints = 3;                  // Minimum touch points for valid trendline
input bool UseTrendlines = true;               // Enable trendline filter

input group "==== Profit Protection ===="
input double TrailingStopDistance = 150;        // Trailing stop distance (points)
input double MinStopDistance = 100;              // Minimum SL distance above entry (points)
input bool EnableTrailingStop = true;          // Enable trailing stop

input group "==== Visual Settings ===="
input color BuySignalColor = clrDodgerBlue;    // Buy signal arrow color
input color SellSignalColor = clrRed;           // Sell signal arrow color
input int ArrowSize = 2;                        // Signal arrow size
input bool EnableLogging = true;                // Enable logging for debugging

// Global Variables
long chartId;
datetime lastTradeTime = 0;
bool isProfitsLocked = false;
double supportLevel = 0;
double resistanceLevel = 0;
int cciHandle;
int maHandle; // Handle for the Moving Average
double fibLevels[5]; // Array to store Fibonacci levels

//+------------------------------------------------------------------+
//| Expert Initialization Function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    chartId = ChartID();
    // Initialize indicators
    cciHandle = iCCI(NULL, TimeFrame, CCIPeriod, PRICE_TYPICAL);
    maHandle = iMA(NULL, TimeFrame, MA_Period, 0, MA_Method, PRICE_CLOSE); // Initialize Moving Average

    // Initialize Fibonacci levels array
    ArrayResize(fibLevels, 5);

    Print("EA initialized successfully on chart ID: ", chartId);
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert Deinitialization Function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    IndicatorRelease(cciHandle);
    IndicatorRelease(maHandle); // Release Moving Average
    ObjectsDeleteAll(0, -1, OBJ_ARROW); // Delete all signal arrows
    Print("EA deinitialized with reason: ", reason);
}

//+------------------------------------------------------------------+
//| Check if a new bar has formed                                   |
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
//| Count Open Positions                                             |
//+------------------------------------------------------------------+
int CountOpenPositions()
{
    int count = 0; 
    for (int i = 0; i < PositionsTotal(); i++)
    {
        ulong ticket = PositionGetTicket(i);
        if (PositionSelectByTicket(ticket) && 
            PositionGetInteger(POSITION_MAGIC) == MagicNumber)
        {
            count++;
        }
    }
    return count;
}

//+------------------------------------------------------------------+
//| Expert Tick Function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Update indicators and levels for new bars
    if (IsNewBar())
    {
        CalculateSupportResistance();
        CalculateFibonacciLevels();
    }

    // Check trade conditions with full indicator confirmation
    if (CheckTradeConditions() && 
        CountOpenPositions() < MaxOpenPositions &&
        CheckTradingAllowed())
    {
        OpenTrade();
    }

    // Manage open positions
    ManageOpenTrades();
}

//+------------------------------------------------------------------+
//| Calculate Fibonacci Levels                                       |
//+------------------------------------------------------------------+
void CalculateFibonacciLevels()
{
    double high = iHigh(NULL, FibTimeframe, iHighest(NULL, FibTimeframe, MODE_HIGH, FibLookback, 0));
    double low = iLow(NULL, FibTimeframe, iLowest(NULL, FibTimeframe, MODE_LOW, FibLookback, 0));
    double range = high - low;

    // Calculate key Fibonacci levels
    fibLevels[0] = high - range * 0.382;  
    fibLevels[1] = high - range * 0.5;     
    fibLevels[2] = high - range * 0.618;  
    fibLevels[3] = high + range * 0.272;   
    fibLevels[4] = high + range * 0.618;  
}

//+------------------------------------------------------------------+
//| Check trading is allowed                                         |
//+------------------------------------------------------------------+
bool CheckTradingAllowed()
{
    if (TimeCurrent() - lastTradeTime < TradeCooldownSeconds)
    {
        Print("In cooldown period");
        return false;
    }
    return true;
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

    resistanceLevel = highs[ArrayMaximum(highs)];
    supportLevel = lows[ArrayMinimum(lows)];

    Print("Updated S/R Levels - Support: ", supportLevel, " Resistance: ", resistanceLevel);
}

//+------------------------------------------------------------------+
//| Check Trade Conditions                                           |
//+------------------------------------------------------------------+
bool CheckTradeConditions()
{
    double currentPrice = iClose(NULL, TimeFrame, 0);

    // Price Action Signals
    bool priceActionBuySignal = (CheckPinBar(true) || CheckInsideBarBreakout(true)) && 
                                 currentPrice > supportLevel;
    bool priceActionSellSignal = (CheckPinBar(false) || CheckInsideBarBreakout(false)) && 
                                  currentPrice < resistanceLevel;

    // CCI Filter
    double cci[];
    if (CopyBuffer(cciHandle, 0, 0, 2, cci) < 0)
    {
        Print("Failed to copy CCI buffer. Error: ", GetLastError());
        return false;
    }
    ArraySetAsSeries(cci, true);

    bool cciBuySignal = (cci[0] > -CCITrendThreshold && cci[0] > cci[1]);
    bool cciSellSignal = (cci[0] < CCITrendThreshold && cci[0] < cci[1]);

    // Moving Average Indicator
    double maValue = iMA(NULL, TimeFrame, MA_Period, 0, MA_Method, PRICE_CLOSE);
    bool maBuySignal = UseMABreakout ? currentPrice > maValue : true;
    bool maSellSignal = UseMABreakout ? currentPrice < maValue : true;

    // Volume Filter
    double currentVolume = iVolume(NULL, TimeFrame, 0);
    double avgVolume = iMA(NULL, TimeFrame, 20, 0, MODE_SMA, VOLUME_TICK);
    bool volumeFilter = currentVolume > avgVolume * VolumeSpikeMultiplier;

    // Confirmation Filter
    bool confirmationFilter = RequireCloseConfirmation ? 
                              (priceActionBuySignal ? ConfirmBuySignal() : ConfirmSellSignal()) : 
                              true;

    // Combined Conditions
    bool buyCondition = priceActionBuySignal && volumeFilter && confirmationFilter && cciBuySignal && maBuySignal;
    bool sellCondition = priceActionSellSignal && volumeFilter && confirmationFilter && cciSellSignal && maSellSignal;

    if (EnableLogging)
    {
        Print("Buy Conditions: ", buyCondition);
        Print("Sell Conditions: ", sellCondition);
    }

    return buyCondition || sellCondition;
}

//+------------------------------------------------------------------+
//| Confirm Buy Signal                                              |
//+------------------------------------------------------------------+
bool ConfirmBuySignal() {
    return iClose(NULL, TimeFrame, 0) > iClose(NULL, TimeFrame, 1);
}

bool ConfirmSellSignal() {
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
    
    if(isBuySignal)
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
    for(int i = 2; i <= InsideBarLookback; i++)
    {
        if(iHigh(NULL, TimeFrame, i) > motherHigh || iLow(NULL, TimeFrame, i) < motherLow)
        {
            isInsideBar = false;
            break;
        }
    }
    
    if(!isInsideBar) return false;
    
    return isBuySignal ? (iHigh(NULL, TimeFrame, 0) > motherHigh) : (iLow(NULL, TimeFrame, 0) < motherLow);
}

//+------------------------------------------------------------------+
//| Open Trade Function                                              |
//+------------------------------------------------------------------+
void OpenTrade()
{
    if (TimeCurrent() - lastTradeTime < TradeCooldownSeconds) return; // Check cooldown

    double price, sl, tp;
    ENUM_ORDER_TYPE orderType;
    bool isBuySignal = CheckPinBar(true) || CheckInsideBarBreakout(true);
    
    // Set initial price, SL, and TP according to the trade direction
    if (isBuySignal)
    {
        price = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_ASK), _Digits);
        if (UseEAStopLoss)
            sl = NormalizeDouble(price - StopLoss * _Point, _Digits);
        else if (UserDefinedStopLoss > 0)
            sl = NormalizeDouble(price - UserDefinedStopLoss * _Point, _Digits);
        else
            sl = 0;

        tp = NormalizeDouble(price + TakeProfit * _Point, _Digits);
        orderType = ORDER_TYPE_BUY;
    }
    else
    {
        price = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_BID), _Digits);
        if (UseEAStopLoss)
            sl = NormalizeDouble(price + StopLoss * _Point, _Digits);
        else if (UserDefinedStopLoss > 0)
            sl = NormalizeDouble(price + UserDefinedStopLoss * _Point, _Digits);
        else
            sl = 0;

        tp = NormalizeDouble(price - TakeProfit * _Point, _Digits);
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
    request.comment = "CombinedEA Trade";

    // Send the trading request
    if (!OrderSend(request, result))
    {
        Print("OrderSend failed for ", _Symbol, ", error code: ", GetLastError());
    }
    else if (result.retcode != TRADE_RETCODE_DONE)
    {
        Print("Trade request failed for ", _Symbol, ", retcode: ", result.retcode);
    }
    else
    {
        Print("Trade opened successfully for ", _Symbol, ", ticket: ", result.order);
        lastTradeTime = TimeCurrent();
        isProfitsLocked = false;
    }
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
    double pointValue = tickValue / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    
    double effectiveStopLoss = UseEAStopLoss ? StopLoss : (UserDefinedStopLoss > 0 ? UserDefinedStopLoss : StopLoss);
    double lotSize = riskAmount / (effectiveStopLoss * pointValue);
    
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    
    lotSize = MathRound(lotSize / lotStep) * lotStep;
    return MathMin(MathMax(lotSize, minLot), maxLot);
}

//+------------------------------------------------------------------+
//| Manage Open Trades with Improved Logic                           |
//+------------------------------------------------------------------+
void ManageOpenTrades()
{
    for (int i = 0; i < PositionsTotal(); i++)
    {
        ulong ticket = PositionGetTicket(i);
        if (!PositionSelectByTicket(ticket) || 
            PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;

        double currentPrice = PositionGetInteger(POSITION_TYPE) == ORDER_TYPE_BUY ? 
                              SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
                              SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        double positionProfit = PositionGetDouble(POSITION_PROFIT);

        // Check for individual loss and profit thresholds
        if (positionProfit <= -IndividualMaxLoss || positionProfit >= IndividualMaxProfit)
        {
            ClosePosition(ticket);
            continue; // Move to the next position
        }

        // Lock in profits if threshold reached
        if (!isProfitsLocked && positionProfit >= LockInProfitThreshold)
        {
            double newSL = PositionGetInteger(POSITION_TYPE) == ORDER_TYPE_BUY ?
                           currentPrice - TrailingStopDistance * SymbolInfoDouble(_Symbol, SYMBOL_POINT) :
                           currentPrice + TrailingStopDistance * SymbolInfoDouble(_Symbol, SYMBOL_POINT);

            // Get current SL to prevent moving it backward
            double currentSL = PositionGetDouble(POSITION_SL);
            // Only update the SL if it's in the right direction
            if ((PositionGetInteger(POSITION_TYPE) == ORDER_TYPE_BUY && newSL > currentSL) ||
                (PositionGetInteger(POSITION_TYPE) == ORDER_TYPE_SELL && newSL < currentSL))
            {
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
        }

        // Apply trailing stop if enabled
        if (EnableTrailingStop)
        {
            double trailPrice = PositionGetInteger(POSITION_TYPE) == ORDER_TYPE_BUY ?
                                currentPrice - TrailingStopDistance * SymbolInfoDouble(_Symbol, SYMBOL_POINT) :
                                currentPrice + TrailingStopDistance * SymbolInfoDouble(_Symbol, SYMBOL_POINT);

            // Get current SL to prevent moving it backward
            double currentSL = PositionGetDouble(POSITION_SL);
            // Only update trailing stop if it moves in favor
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
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Close Position Function                                          |
//+------------------------------------------------------------------+
void ClosePosition(ulong ticket)
{
    MqlTradeRequest request = {};
    MqlTradeResult result = {};
    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = PositionGetDouble(POSITION_VOLUME);
    request.type = (PositionGetInteger(POSITION_TYPE) == ORDER_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
    request.position = ticket;

    if (!OrderSend(request, result))
    {
        Print("Failed to close position, error code: ", GetLastError());
    }
}

//+------------------------------------------------------------------+