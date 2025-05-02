//+------------------------------------------------------------------+
//|                EnhancedPriceActionScalperPro.mq5                 |
//|                        Copyright 2025, MetaQuotes Software Corp. |
//|                                       https://www.mql5.com       |
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window

// Input Parameters
input group "==== Risk Management ===="
input double TakeProfit = 300;              // Take Profit in points (1:3 ratio)
input double StopLoss = 300;                // Stop Loss in points (1:3 ratio)
input bool UseEAStopLoss = true;            // Use EA-based stop loss
input double UserDefinedStopLoss = 0;       // User-defined stop loss (0 = use EA-based stop loss)
input double RiskPercentage = 1.0;          // Risk percentage of account balance
input double UserLotSize = 0.20;            // User-defined lot size
input int MagicNumber = 78101;              // Unique Magic Number for this EA
input int MaxOpenPositions = 3;             // Max open positions per pair
input double IndividualMaxLoss = 1000.0;       // Maximum loss threshold per position
input double IndividualMaxProfit = 30.0;    // Maximum profit threshold per position

input group "==== Trading Rules ===="
input ENUM_TIMEFRAMES TimeFrame = PERIOD_M5; // Main trading timeframe
input int TradeCooldownSeconds = 30;         // Trade cooldown period
input int SupportResistanceLookback = 30;    // S/R lookback
input double PinBarThreshold = 0.6;          // Pin bar ratio threshold
input int InsideBarLookback = 2;             // Inside bar lookback
input double VolumeSpikeMultiplier = 2.0;    // Volume spike multiplier
input bool RequireCloseConfirmation = true;  // Require candle close confirmation

input group "==== CCI Filter ===="
input int CCIPeriod = 14;                    // CCI period
input double CCITrendThreshold = 100;        // CCI threshold
input bool UseCCIFilter = true;              // Enable CCI filter

input group "==== Fibonacci Settings ===="
input ENUM_TIMEFRAMES FibTimeframe = PERIOD_M15; // Fibonacci analysis timeframe
input int FibLookback = 100;                 // Fibonacci lookback period
input bool UseFibonacci = true;              // Enable Fibonacci filter
input double FibRetracementLevel = 0.618;    // Key retracement level (0.382, 0.5, 0.618)
input double FibExtensionLevel = 1.618;      // Key extension level (1.272, 1.414, 1.618)

input group "==== Trendline Settings ===="
input int TrendlineLookback = 100;           // Trendline lookback period
input int MinTouchPoints = 3;                // Minimum touch points for valid trendline
input bool UseTrendlines = true;             // Enable trendline filter

input group "==== Profit Protection ===="
input double LockInProfitThreshold = 7;      // Lock profit threshold ($)
input double TrailingStopDistance = 30;      // Trailing stop distance (points)
input double MinStopDistance = 50;           // Minimum SL distance above entry (points)
input bool EnableTrailingStop = true;         // Enable trailing stop

input group "==== Visual Settings ===="
input color BuySignalColor = clrDodgerBlue;  // Buy signal arrow color
input color SellSignalColor = clrRed;        // Sell signal arrow color
input int ArrowSize = 2;                     // Signal arrow size

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
double trendlineSlope = 0;
double trendlineIntercept = 0;
bool uptrend = false;
bool downtrend = false;
double fibLevels[];                          // Array to store Fibonacci levels
string currentSymbol = _Symbol;              // Current symbol being processed

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
    
    // Initialize Fibonacci levels array
    ArrayResize(fibLevels, 5); // 0.382, 0.5, 0.618, 1.272, 1.618

    Print("EA initialized successfully on chart ID: ", chartId);
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert Deinitialization Function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    IndicatorRelease(cciHandle);
    ObjectsDeleteAll(0, -1, OBJ_ARROW); // Delete all signal arrows
    Print("EA deinitialized with reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert Tick Function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Process all symbols available in Market Watch
    for(int s = 0; s < SymbolsTotal(true); s++)
    {
        currentSymbol = SymbolName(s, true);
        
        // Skip if symbol is not visible in Market Watch
        if(!SymbolInfoInteger(currentSymbol, SYMBOL_VISIBLE)) continue;
        
        // Update indicators and check trading conditions for each symbol
        UpdateDailyProfitLoss();
        if(IsNewBar(currentSymbol, TimeFrame))
        {
            CalculateSupportResistance(currentSymbol);
            CalculateTrendline(currentSymbol);
            if(UseFibonacci) CalculateFibonacciLevels(currentSymbol);
        }

        // Check trading conditions
        if(CheckTradingAllowed() && 
           CheckTradeConditions(currentSymbol) && 
           CountOpenPositions(currentSymbol) < MaxOpenPositions)
        {
            OpenTrade(currentSymbol);
        }

        ManageOpenTrades(currentSymbol);
    }
}

//+------------------------------------------------------------------+
//| Calculate Fibonacci Levels                                       |
//+------------------------------------------------------------------+
void CalculateFibonacciLevels(string symbol)
{
    double high = iHigh(symbol, FibTimeframe, iHighest(symbol, FibTimeframe, MODE_HIGH, FibLookback, 1));
    double low = iLow(symbol, FibTimeframe, iLowest(symbol, FibTimeframe, MODE_LOW, FibLookback, 1));
    double range = high - low;

    // Calculate key Fibonacci levels
    fibLevels[0] = high - range * 0.382;  // 38.2% retracement
    fibLevels[1] = high - range * 0.5;     // 50% retracement
    fibLevels[2] = high - range * 0.618;  // 61.8% retracement
    fibLevels[3] = high + range * 0.272;   // 127.2% extension
    fibLevels[4] = high + range * 0.618;  // 161.8% extension

    // Print Fibonacci levels for debugging
    Print(symbol, " Fibonacci Levels - 38.2%: ", fibLevels[0], 
          " 50%: ", fibLevels[1], " 61.8%: ", fibLevels[2],
          " 127.2%: ", fibLevels[3], " 161.8%: ", fibLevels[4]);
}

//+------------------------------------------------------------------+
//| Check if price is near Fibonacci level                          |
//+------------------------------------------------------------------+
bool IsNearFibLevel(string symbol, bool isRetracement)
{
    double currentPrice = iClose(symbol, TimeFrame, 0);
    double threshold = 10 * SymbolInfoDouble(symbol, SYMBOL_POINT);
    
    if(isRetracement)
    {
        // Check if price is near key retracement levels (38.2%, 50%, 61.8%)
        for(int i = 0; i < 3; i++)
        {
            if(MathAbs(currentPrice - fibLevels[i]) <= threshold)
                return true;
        }
    }
    else
    {
        // Check if price is near key extension levels (127.2%, 161.8%)
        for(int i = 3; i < 5; i++)
        {
            if(MathAbs(currentPrice - fibLevels[i]) <= threshold)
                return true;
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Calculate Trendline                                             |
//+------------------------------------------------------------------+
void CalculateTrendline(string symbol)
{
    double prices[];
    ArrayResize(prices, TrendlineLookback);
    ArraySetAsSeries(prices, true);

    CopyClose(symbol, TimeFrame, 0, TrendlineLookback, prices);

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
           HistoryDealGetInteger(ticket, DEAL_MAGIC) == MagicNumber)
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

    return true;
}

//+------------------------------------------------------------------+
//| Calculate Support and Resistance Levels                          |
//+------------------------------------------------------------------+
void CalculateSupportResistance(string symbol)
{
    double highs[], lows[];
    ArraySetAsSeries(highs, true);
    ArraySetAsSeries(lows, true);

    CopyHigh(symbol, TimeFrame, 0, SupportResistanceLookback, highs);
    CopyLow(symbol, TimeFrame, 0, SupportResistanceLookback, lows);

    lastHigh = highs[ArrayMaximum(highs)];
    lastLow = lows[ArrayMinimum(lows)];

    supportLevel = iLow(symbol, TimeFrame, iLowest(symbol, TimeFrame, MODE_LOW, 5, 1));
    resistanceLevel = iHigh(symbol, TimeFrame, iHighest(symbol, TimeFrame, MODE_HIGH, 5, 1));

    Print(symbol, " Updated S/R Levels - Support: ", supportLevel, " Resistance: ", resistanceLevel);
}

//+------------------------------------------------------------------+
//| Check for New Bar                                                |
//+------------------------------------------------------------------+
bool IsNewBar(string symbol, ENUM_TIMEFRAMES timeframe)
{
    static datetime lastBarTime = 0;
    datetime currentBarTime = iTime(symbol, timeframe, 0);

    if(lastBarTime != currentBarTime)
    {
        lastBarTime = currentBarTime;
        return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| Check Trade Conditions with Multiple Filters                     |
//+------------------------------------------------------------------+
bool CheckTradeConditions(string symbol)
{
    double currentPrice = iClose(symbol, TimeFrame, 0);
    double currentVolume = iVolume(symbol, TimeFrame, 0);
    double avgVolume = iMA(symbol, TimeFrame, 20, 0, MODE_SMA, VOLUME_TICK);

    // CCI Filter
    double cci[], cciPrev[];
    CopyBuffer(cciHandle, 0, 0, 2, cci);
    ArraySetAsSeries(cci, true);

    bool cciBuySignal = (cci[0] > -CCITrendThreshold && cci[0] > cci[1]);
    bool cciSellSignal = (cci[0] < CCITrendThreshold && cci[0] < cci[1]);

    // Fibonacci Filter
    bool fibBuySignal = UseFibonacci ? IsNearFibLevel(symbol, true) && currentPrice > fibLevels[2] : true;
    bool fibSellSignal = UseFibonacci ? IsNearFibLevel(symbol, true) && currentPrice < fibLevels[2] : true;

    // Trendline Filter
    bool trendlineBuySignal = uptrend && currentPrice > (trendlineSlope * 0 + trendlineIntercept);
    bool trendlineSellSignal = downtrend && currentPrice < (trendlineSlope * 0 + trendlineIntercept);

    // Price Action Signals
    bool priceActionBuySignal = (CheckPinBar(symbol, true) || CheckInsideBarBreakout(symbol, true)) && 
                               currentPrice > supportLevel;
    bool priceActionSellSignal = (CheckPinBar(symbol, false) || CheckInsideBarBreakout(symbol, false)) && 
                                currentPrice < resistanceLevel;

    // Volume Filter
    bool volumeFilter = currentVolume > avgVolume * VolumeSpikeMultiplier;

    // Confirmation Filter
    bool confirmationFilter = RequireCloseConfirmation ? 
                            (priceActionBuySignal ? ConfirmBuySignal(symbol) : ConfirmSellSignal(symbol)) : 
                            true;

    // Combined Buy Conditions
    bool buyCondition = priceActionBuySignal && volumeFilter && confirmationFilter &&
                       ((UseCCIFilter && cciBuySignal) || !UseCCIFilter) &&
                       ((UseFibonacci && fibBuySignal) || !UseFibonacci) &&
                       ((UseTrendlines && trendlineBuySignal) || !UseTrendlines);

    // Combined Sell Conditions
    bool sellCondition = priceActionSellSignal && volumeFilter && confirmationFilter &&
                        ((UseCCIFilter && cciSellSignal) || !UseCCIFilter) &&
                        ((UseFibonacci && fibSellSignal) || !UseFibonacci) &&
                        ((UseTrendlines && trendlineSellSignal) || !UseTrendlines);

    // Draw signal arrows
    if(buyCondition) CreateSignalArrow(symbol, TimeCurrent(), iLow(symbol, TimeFrame, 0), "BuySignal_"+symbol, BuySignalColor);
    if(sellCondition) CreateSignalArrow(symbol, TimeCurrent(), iHigh(symbol, TimeFrame, 0), "SellSignal_"+symbol, SellSignalColor);

    return buyCondition || sellCondition;
}

//+------------------------------------------------------------------+
//| Confirm Buy/Sell Signals                                         |
//+------------------------------------------------------------------+
bool ConfirmBuySignal(string symbol)
{
    return iClose(symbol, TimeFrame, 0) > iClose(symbol, TimeFrame, 1);
}

bool ConfirmSellSignal(string symbol)
{
    return iClose(symbol, TimeFrame, 0) < iClose(symbol, TimeFrame, 1);
}

//+------------------------------------------------------------------+
//| Check for Valid Pin Bar Pattern                                  |
//+------------------------------------------------------------------+
bool CheckPinBar(string symbol, bool isBuySignal)
{
    double open = iOpen(symbol, TimeFrame, 0);
    double high = iHigh(symbol, TimeFrame, 0);
    double low = iLow(symbol, TimeFrame, 0);
    double close = iClose(symbol, TimeFrame, 0);
    
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
bool CheckInsideBarBreakout(string symbol, bool isBuySignal)
{
    double motherHigh = iHigh(symbol, TimeFrame, 1);
    double motherLow = iLow(symbol, TimeFrame, 1);
    
    bool isInsideBar = true;
    for(int i = 2; i <= InsideBarLookback; i++)
    {
        if(iHigh(symbol, TimeFrame, i) > motherHigh || iLow(symbol, TimeFrame, i) < motherLow)
        {
            isInsideBar = false;
            break;
        }
    }
    
    if(!isInsideBar) return false;
    
    if(isBuySignal) return iHigh(symbol, TimeFrame, 0) > motherHigh;
    else return iLow(symbol, TimeFrame, 0) < motherLow;
}

//+------------------------------------------------------------------+
//| Create Signal Arrow                                              |
//+------------------------------------------------------------------+
void CreateSignalArrow(string symbol, datetime time, double price, string name, color clr)
{
    if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
    
    ObjectCreate(0, name, OBJ_ARROW, 0, time, price);
    ObjectSetInteger(0, name, OBJPROP_ARROWCODE, 241);
    ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
    ObjectSetInteger(0, name, OBJPROP_WIDTH, ArrowSize);
    ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
    ChartRedraw();
}

//+------------------------------------------------------------------+
//| Open Trade Function                                              |
//+------------------------------------------------------------------+
void OpenTrade(string symbol)
{
    if(TimeCurrent() - lastTradeTime < TradeCooldownSeconds) return;
    if(CountOpenPositionsInDirection(symbol, CheckPinBar(symbol, true) || CheckInsideBarBreakout(symbol, true)) > 0) return;

    double price, sl, tp;
    ENUM_ORDER_TYPE orderType;
    bool isBuySignal = CheckPinBar(symbol, true) || CheckInsideBarBreakout(symbol, true);
    
    // Set initial price, SL, and TP according to the trade direction
    if(isBuySignal)
    {
        price = NormalizeDouble(SymbolInfoDouble(symbol, SYMBOL_ASK), _Digits);
        if(UseEAStopLoss)
            sl = NormalizeDouble(price - StopLoss * SymbolInfoDouble(symbol, SYMBOL_POINT), _Digits);
        else if(UserDefinedStopLoss > 0)
            sl = NormalizeDouble(price - UserDefinedStopLoss * SymbolInfoDouble(symbol, SYMBOL_POINT), _Digits);
        else
            sl = 0;

        // Use Fibonacci extension for TP if enabled
        if(UseFibonacci)
            tp = NormalizeDouble(fibLevels[4], _Digits); // 161.8% extension
        else
            tp = NormalizeDouble(price + TakeProfit * SymbolInfoDouble(symbol, SYMBOL_POINT), _Digits);
            
        orderType = ORDER_TYPE_BUY;
    }
    else
    {
        price = NormalizeDouble(SymbolInfoDouble(symbol, SYMBOL_BID), _Digits);
        if(UseEAStopLoss)
            sl = NormalizeDouble(price + StopLoss * SymbolInfoDouble(symbol, SYMBOL_POINT), _Digits);
        else if(UserDefinedStopLoss > 0)
            sl = NormalizeDouble(price + UserDefinedStopLoss * SymbolInfoDouble(symbol, SYMBOL_POINT), _Digits);
        else
            sl = 0;

        // Use Fibonacci extension for TP if enabled
        if(UseFibonacci)
            tp = NormalizeDouble(fibLevels[3], _Digits); // 127.2% extension
        else
            tp = NormalizeDouble(price - TakeProfit * SymbolInfoDouble(symbol, SYMBOL_POINT), _Digits);
            
        orderType = ORDER_TYPE_SELL;
    }

    // Create a trade request
    MqlTradeRequest request = {};
    MqlTradeResult result = {};

    request.action = TRADE_ACTION_DEAL;
    request.symbol = symbol;
    request.volume = CalculateLotSize(symbol);
    request.price = price;
    request.sl = (sl > 0) ? sl : 0;
    request.tp = (tp > 0) ? tp : 0;
    request.type = orderType;
    request.type_filling = ORDER_FILLING_FOK;
    request.magic = MagicNumber;
    request.comment = "FibScalperPro";

    // Send the trading request
    if(!OrderSend(request, result))
    {
        Print("OrderSend failed for ", symbol, ", error code: ", GetLastError());
    }
    else if(result.retcode != TRADE_RETCODE_DONE)
    {
        Print("Trade request failed for ", symbol, ", retcode: ", result.retcode);
    }
    else
    {
        Print("Trade opened successfully for ", symbol, ", ticket: ", result.order);
        lastTradeTime = TimeCurrent();
        bestPrice = price;
        isProfitsLocked = false;
    }
}

//+------------------------------------------------------------------+
//| Count Open Positions in Direction                                |
//+------------------------------------------------------------------+
int CountOpenPositionsInDirection(string symbol, bool isBuySignal)
{
    int count = 0; 
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket) && 
           PositionGetString(POSITION_SYMBOL) == symbol && 
           PositionGetInteger(POSITION_MAGIC) == MagicNumber)
        {
            if((isBuySignal && PositionGetInteger(POSITION_TYPE) == ORDER_TYPE_BUY) ||
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
double CalculateLotSize(string symbol)
{
    if(UserLotSize > 0) return UserLotSize;

    double accountEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    double riskAmount = accountEquity * (RiskPercentage / 100);
    double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
    double pointValue = tickValue / SymbolInfoDouble(symbol, SYMBOL_POINT);
    
    double effectiveStopLoss = UseEAStopLoss ? StopLoss : (UserDefinedStopLoss > 0 ? UserDefinedStopLoss : StopLoss);
    double lotSize = riskAmount / (effectiveStopLoss * pointValue);
    
    double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
    
    lotSize = MathRound(lotSize / lotStep) * lotStep;
    return MathMin(MathMax(lotSize, minLot), maxLot);
}

//+------------------------------------------------------------------+
//| Count Open Positions                                             |
//+------------------------------------------------------------------+
int CountOpenPositions(string symbol)
{
    int count = 0; 
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket) && 
           PositionGetString(POSITION_SYMBOL) == symbol && 
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
void ManageOpenTrades(string symbol)
{
    for(int i = 0; i < PositionsTotal(); i++)
    {
        ulong ticket = PositionGetTicket(i);
        if(!PositionSelectByTicket(ticket) || 
           PositionGetString(POSITION_SYMBOL) != symbol || 
           PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;

        double currentPrice = PositionGetInteger(POSITION_TYPE) == ORDER_TYPE_BUY ? 
                             SymbolInfoDouble(symbol, SYMBOL_BID) : 
                             SymbolInfoDouble(symbol, SYMBOL_ASK);
        double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
        double currentSL = PositionGetDouble(POSITION_SL);
        double positionProfit = PositionGetDouble(POSITION_PROFIT);
        
        // Check for individual position profit/loss thresholds
        double individualLoss = -positionProfit; // Since profit can be negative
        double individualProfit = positionProfit;

        if(individualLoss >= IndividualMaxLoss || individualProfit >= IndividualMaxProfit)
        {
            // Close position if limits are reached
            MqlTradeRequest closeRequest = {};
            MqlTradeResult closeResult = {};
            closeRequest.action = TRADE_ACTION_DEAL;
            closeRequest.symbol = symbol;
            closeRequest.volume = PositionGetDouble(POSITION_VOLUME);
            closeRequest.type = (PositionGetInteger(POSITION_TYPE) == ORDER_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
            closeRequest.position = ticket;
            closeRequest.comment = "Closed due to threshold trigger";
            if(!OrderSend(closeRequest, closeResult) || closeResult.retcode != TRADE_RETCODE_DONE)
            {
                Print("Failed to close position for ", symbol, ", error code: ", GetLastError());
            }
            continue; // Move to the next position
        }

        // Calculate minimum allowed stop level
        double minStopLevel = openPrice + (PositionGetInteger(POSITION_TYPE) == ORDER_TYPE_BUY ? 
                                          MinStopDistance * SymbolInfoDouble(symbol, SYMBOL_POINT) : 
                                          -MinStopDistance * SymbolInfoDouble(symbol, SYMBOL_POINT));
        
        // Lock in profits if threshold reached
        if(!isProfitsLocked && positionProfit >= LockInProfitThreshold)
        {
            double newSL = PositionGetInteger(POSITION_TYPE) == ORDER_TYPE_BUY ?
                           currentPrice - TrailingStopDistance * SymbolInfoDouble(symbol, SYMBOL_POINT) :
                           currentPrice + TrailingStopDistance * SymbolInfoDouble(symbol, SYMBOL_POINT);
            
            // Ensure SL is at least MinStopDistance from entry
            if((PositionGetInteger(POSITION_TYPE) == ORDER_TYPE_BUY && newSL < minStopLevel) ||
               (PositionGetInteger(POSITION_TYPE) == ORDER_TYPE_SELL && newSL > minStopLevel))
            {
                newSL = minStopLevel;
            }

            MqlTradeRequest modifyRequest = {};
            MqlTradeResult modifyResult = {};
            modifyRequest.action = TRADE_ACTION_SLTP;
            modifyRequest.position = ticket;
            modifyRequest.sl = NormalizeDouble(newSL, _Digits);

            if(!OrderSend(modifyRequest, modifyResult))
            {
                Print("Failed to modify SL for profit lock on ", symbol, ", error code: ", GetLastError());
            }
            else
            {
                isProfitsLocked = true;
                Print("Profits locked for ", symbol, ", ticket: ", ticket);
            }
        }

        // Apply trailing stop if enabled and profits locked
        if(EnableTrailingStop && isProfitsLocked)
        {
            double trailPrice = PositionGetInteger(POSITION_TYPE) == ORDER_TYPE_BUY ?
                               currentPrice - TrailingStopDistance * SymbolInfoDouble(symbol, SYMBOL_POINT) :
                               currentPrice + TrailingStopDistance * SymbolInfoDouble(symbol, SYMBOL_POINT);
            
            // Ensure trail stop is at least MinStopDistance from entry
            if((PositionGetInteger(POSITION_TYPE) == ORDER_TYPE_BUY && trailPrice < minStopLevel) ||
               (PositionGetInteger(POSITION_TYPE) == ORDER_TYPE_SELL && trailPrice > minStopLevel))
            {
                trailPrice = minStopLevel;
            }

            if((PositionGetInteger(POSITION_TYPE) == ORDER_TYPE_BUY && trailPrice > currentSL) ||
               (PositionGetInteger(POSITION_TYPE) == ORDER_TYPE_SELL && trailPrice < currentSL))
            {
                MqlTradeRequest modifyRequest = {};
                MqlTradeResult modifyResult = {};
                modifyRequest.action = TRADE_ACTION_SLTP;
                modifyRequest.position = ticket;
                modifyRequest.sl = NormalizeDouble(trailPrice, _Digits);

                if(!OrderSend(modifyRequest, modifyResult))
                {
                    Print("Failed to modify trailing stop on ", symbol, ", error code: ", GetLastError());
                }
                else
                {
                    Print("Trailing stop updated for ", symbol, ", ticket: ", ticket);
                }
            }
        }
    }
}
//+------------------------------------------------------------------+
