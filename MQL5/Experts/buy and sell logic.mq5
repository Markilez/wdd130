//+------------------------------------------------------------------+
//|                  EnhancedPriceActionScalperEA.mq5                |
//|                        Copyright 2025, MetaQuotes Software Corp. |
//|                                       https://www.mql5.com       |
//+------------------------------------------------------------------+
#property strict
#include <Trade\Trade.mqh>

// Input Parameters
input group "==== Risk Management ===="
input double TakeProfit = 500;               // Take Profit in points
input double StopLoss = 300;                 // Stop Loss in points
input bool UseEAStopLoss = true;             // Use EA-based stop loss
input double RiskPercentage = 1.0;           // Risk percentage of account balance
input double UserLotSize = 0.20;             // User-defined lot size
input int MagicNumber = 100001;                // Unique Magic Number for this EA
input int MaxOpenPositions = 3;              // Max open positions
input double MaxLossPerPosition = 7;        // Max loss per position ($)
input double MaxProfitPerPosition = 10;      // Max profit per position ($)

input group "==== Trading Rules ===="
input ENUM_TIMEFRAMES TimeFrame = PERIOD_M5; // Timeframe
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

input group "==== Profit Protection ===="
input double LockInProfitThreshold = 7;      // Lock profit threshold ($)
input double TrailingStopDistance = 30;      // Trailing stop distance (points)
input double MinStopDistance = 70;           // Minimum SL distance above entry (points)
input bool EnableTrailingStop = true;        // Enable trailing stop
input double BreakEvenAmount = 5;           // Breakeven amount in $

// Global Variables
CTrade trade;
long chartId;
datetime lastTradeTime = 0;
double bestPrice = 0.0;
bool isProfitsLocked = false;
double lastHigh = 0;
double lastLow = 0;
double supportLevel = 0;
double resistanceLevel = 0;
int cciHandle;

//+------------------------------------------------------------------+
//| Expert Initialization Function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    chartId = ChartID();
    cciHandle = iCCI(NULL, TimeFrame, CCIPeriod, PRICE_TYPICAL);
    trade.SetExpertMagicNumber(MagicNumber);
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
        else
            sl = 0;
            
        tp = NormalizeDouble(price - TakeProfit * _Point, _Digits);
        orderType = ORDER_TYPE_SELL;
    }

    double lotSize = CalculateLotSize();
    
    if(trade.PositionOpen(_Symbol, orderType, lotSize, price, sl, tp))
    {
        Print("Trade opened successfully");
        lastTradeTime = TimeCurrent();
        bestPrice = price;
        isProfitsLocked = false;
    }
    else
    {
        Print("Failed to open trade, error: ", GetLastError());
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
            if ((isBuySignal && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ||
                (!isBuySignal && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL))
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
    
    double lotSize = riskAmount / (StopLoss * pointValue);
    
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

        double currentPrice = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 
                             SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
                             SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
        double currentSL = PositionGetDouble(POSITION_SL);
        double positionProfit = PositionGetDouble(POSITION_PROFIT);
        
        // Check per-position profit/loss limits
        if (positionProfit >= MaxProfitPerPosition || positionProfit <= -MaxLossPerPosition)
        {
            trade.PositionClose(ticket);
            continue;
        }
        
        // Calculate breakeven level in dollars
        double breakevenLevel = openPrice + (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 
                                           BreakEvenAmount / (PositionGetDouble(POSITION_VOLUME) * 100000) : 
                                           -BreakEvenAmount / (PositionGetDouble(POSITION_VOLUME) * 100000));
        
        // Move to breakeven when price reaches breakeven level
        if ((PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY && currentPrice >= breakevenLevel && currentSL < openPrice) ||
            (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL && currentPrice <= breakevenLevel && currentSL > openPrice))
        {
            double newSL = openPrice;
            
            // Ensure SL is at least MinStopDistance from entry
            if ((PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY && newSL < (openPrice - MinStopDistance * _Point)) ||
                (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL && newSL > (openPrice + MinStopDistance * _Point)))
            {
                newSL = openPrice + (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 
                                    -MinStopDistance * _Point : 
                                    MinStopDistance * _Point);
            }

            if(!trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP)))
            {
                Print("Failed to move SL to breakeven, error: ", GetLastError());
            }
        }
        
        // Lock in profits if threshold reached
        if (!isProfitsLocked && positionProfit >= LockInProfitThreshold)
        {
            double newSL = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ?
                           currentPrice - TrailingStopDistance * _Point :
                           currentPrice + TrailingStopDistance * _Point;
            
            // Ensure SL is at least MinStopDistance from entry
            if ((PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY && newSL < (openPrice - MinStopDistance * _Point)) ||
                (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL && newSL > (openPrice + MinStopDistance * _Point)))
            {
                newSL = openPrice + (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 
                                    -MinStopDistance * _Point : 
                                    MinStopDistance * _Point);
            }

            if(!trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP)))
            {
                Print("Failed to modify SL for profit lock, error: ", GetLastError());
            }
            else
            {
                isProfitsLocked = true;
            }
        }

        // Apply trailing stop if enabled and profits locked
        if (EnableTrailingStop && isProfitsLocked)
        {
            double trailPrice = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ?
                               currentPrice - TrailingStopDistance * _Point :
                               currentPrice + TrailingStopDistance * _Point;
            
            // Only trail if price is above entry (for longs) or below entry (for shorts)
            if ((PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY && currentPrice > openPrice && trailPrice > currentSL) ||
                (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL && currentPrice < openPrice && trailPrice < currentSL))
            {
                if(!trade.PositionModify(ticket, trailPrice, PositionGetDouble(POSITION_TP)))
                {
                    Print("Failed to modify trailing stop, error: ", GetLastError());
                }
            }
        }
    }
}
//+------------------------------------------------------------------+
