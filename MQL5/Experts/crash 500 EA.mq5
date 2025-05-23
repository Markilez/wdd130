//+------------------------------------------------------------------+
//|                  EnhancedPriceActionScalperEA.mq5                |
//|                        Copyright 2025, MetaQuotes Software Corp. |
//|                                       https://www.mql5.com       |
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window

// Input Parameters
input group "==== Risk Management ===="
input double TakeProfit = 1500;               // Take Profit in points
input double StopLoss = 1000;                 // Stop Loss in points
input bool UseEAStopLoss = false;             // Use EA-based stop loss
input double UserDefinedStopLoss = 1500;       // User-defined stop loss (0 = use EA-based stop loss)
input double RiskPercentage = 1.0;           // Risk percentage of account balance
input double UserLotSize = 0.20;            // User-defined lot size
input int MagicNumber = 10012;                // Unique Magic Number for this EA
input int MaxOpenPositions = 3;              // Max open positions
input double MaxLossPerPosition = 3;        // Max loss per position ($)
input double MaxProfitPerPosition = 2;     // Max profit per position ($)

input group "==== Trading Rules ===="
input ENUM_TIMEFRAMES TimeFrame = PERIOD_M5; // Timeframe
input int TradeCooldownSeconds = 3;         // Trade cooldown period
input int SupportResistanceLookback = 30;    // S/R lookback
input double PinBarThreshold = 0.6;          // Pin bar ratio threshold
input int InsideBarLookback = 2;             // Inside bar lookback
input double VolumeSpikeMultiplier = 2.0;    // Volume spike multiplier
input bool RequireCloseConfirmation = true;  // Require candle close confirmation

input group "==== CCI Filter ===="
input int CCIPeriod = 14;                    // CCI period
input double CCITrendThreshold = 100;        // CCI threshold
input bool UseCCIFilter = true;              // Enable CCI filter

input group "==== Profit Protection ===="
input double LockInProfitThreshold = 1;      // Lock profit threshold ($)
input double TrailingStopDistance = 300;      // Trailing stop distance (points)
input double MinStopDistance = 3000;           // Minimum SL distance above entry (points)
input bool EnableTrailingStop = true;        // Enable trailing stop
input double BreakEvenAmount = 1;           // Breakeven amount in $

// Global Variables
long chartId;
datetime lastTradeTime = 0;
double bestPrice = 0.0;
bool isProfitsLocked = true;
double lastHigh = 0;
double lastLow = 0;
double supportLevel = 1;
double resistanceLevel = 1;
int cciHandle;

//+------------------------------------------------------------------+
//| Expert Initialization Function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    chartId = ChartID();
    cciHandle = iCCI(NULL, TimeFrame, CCIPeriod, PRICE_TYPICAL);
    CalculateSupportResistance();
    Print("EA initialized successfully on chart ID: ", chartId);
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert Deinitialization Function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    IndicatorRelease(cciHandle);
    Print("EA deinitialized with reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert Tick Function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    if (ChartID() != chartId) return;

    if (IsNewBar()) CalculateSupportResistance();

    if (CheckTradingAllowed() && CheckTradeConditions() && CountOpenPositions() < MaxOpenPositions)
    {
        OpenTrade();
    }

    ManageOpenTrades();
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
//| Check Trade Conditions with CCI Filter                           |
//+------------------------------------------------------------------+
bool CheckTradeConditions()
{
    double currentPrice = iClose(NULL, TimeFrame, 0);
    double currentVolume = iVolume(NULL, TimeFrame, 0);
    double avgVolume = iMA(NULL, TimeFrame, 20, 0, MODE_SMA, VOLUME_TICK);
    
    double cci[], cciPrev[];
    CopyBuffer(cciHandle, 0, 0, 2, cci);
    ArraySetAsSeries(cci, true);
    
    bool cciBuySignal = (cci[0] > -CCITrendThreshold && cci[0] > cci[1]);
    bool cciSellSignal = (cci[0] < CCITrendThreshold && cci[0] < cci[1]);
    
    bool buyCondition = (CheckPinBar(true) || CheckInsideBarBreakout(true)) && 
                       currentPrice > supportLevel && 
                       currentVolume > avgVolume * VolumeSpikeMultiplier &&
                       (RequireCloseConfirmation ? ConfirmBuySignal() : true) &&
                       (!UseCCIFilter || cciBuySignal);
    
    bool sellCondition = (CheckPinBar(false) || CheckInsideBarBreakout(false)) && 
                        currentPrice < resistanceLevel && 
                        currentVolume > avgVolume * VolumeSpikeMultiplier &&
                        (RequireCloseConfirmation ? ConfirmSellSignal() : true) &&
                        (!UseCCIFilter || cciSellSignal);

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

    if (isBuySignal)
    {
        price = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_ASK), _Digits);
        if(UseEAStopLoss)
            sl = NormalizeDouble(price - StopLoss * _Point, _Digits);
        else if(UserDefinedStopLoss > 0)
            sl = NormalizeDouble(price - UserDefinedStopLoss * _Point, _Digits);
        else
            sl = 0;
        
        tp = NormalizeDouble(price + TakeProfit * _Point, _Digits);
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
            
        tp = NormalizeDouble(price - TakeProfit * _Point, _Digits);
        orderType = ORDER_TYPE_SELL;
    }

    MqlTradeRequest request = {};
    MqlTradeResult result = {};

    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = CalculateLotSize();
    request.price = price;
    if(sl > 0) request.sl = sl;
    if(tp > 0) request.tp = tp;
    request.type = orderType;
    request.type_filling = ORDER_FILLING_FOK;
    request.magic = MagicNumber;

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
        
        // Calculate minimum allowed stop level (entry price ± MinStopDistance)
        double minStopLevel = openPrice + (PositionGetInteger(POSITION_TYPE) == ORDER_TYPE_BUY ? 
                                          MinStopDistance * _Point : 
                                          -MinStopDistance * _Point);
        
        // Check per-position profit/loss limits
        if (positionProfit >= MaxProfitPerPosition || positionProfit <= -MaxLossPerPosition)
        {
            ClosePosition(ticket);
            continue;
        }
        
        // Calculate breakeven level in dollars
        double breakevenLevel = openPrice + (PositionGetInteger(POSITION_TYPE) == ORDER_TYPE_BUY ? 
                                           BreakEvenAmount / (PositionGetDouble(POSITION_VOLUME) * 100000) : 
                                           -BreakEvenAmount / (PositionGetDouble(POSITION_VOLUME) * 100000));
        
        // Move to breakeven when price reaches breakeven level
        if ((PositionGetInteger(POSITION_TYPE) == ORDER_TYPE_BUY && currentPrice >= breakevenLevel && currentSL < openPrice) ||
            (PositionGetInteger(POSITION_TYPE) == ORDER_TYPE_SELL && currentPrice <= breakevenLevel && currentSL > openPrice))
        {
            double newSL = openPrice;
            
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
                Print("Failed to move SL to breakeven, error code: ", GetLastError());
            }
            else
            {
                Print("SL moved to breakeven for ticket: ", ticket);
            }
        }
        
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

            // Only trail if price is above entry (for longs) or below entry (for shorts)
            if ((PositionGetInteger(POSITION_TYPE) == ORDER_TYPE_BUY && currentPrice > openPrice && trailPrice > currentSL) ||
                (PositionGetInteger(POSITION_TYPE) == ORDER_TYPE_SELL && currentPrice < openPrice && trailPrice < currentSL))
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
//| Close Position                                                   |
//+------------------------------------------------------------------+
void ClosePosition(ulong ticket)
{
    MqlTradeRequest request = {};
    MqlTradeResult result = {};
    
    request.action = TRADE_ACTION_DEAL;
    request.position = ticket;
    request.symbol = PositionGetString(POSITION_SYMBOL);
    request.volume = PositionGetDouble(POSITION_VOLUME);
    request.type = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
    request.price = (request.type == ORDER_TYPE_SELL) ? SymbolInfoDouble(request.symbol, SYMBOL_BID) : SymbolInfoDouble(request.symbol, SYMBOL_ASK);
    request.deviation = 5;
    request.magic = MagicNumber;
    request.type_filling = ORDER_FILLING_FOK;
    
    if (!OrderSend(request, result))
    {
        Print("Failed to close position, error code: ", GetLastError());
    }
    else
    {
        Print("Position closed due to profit/loss limit, ticket: ", ticket);
    }
}
//+------------------------------------------------------------------+
