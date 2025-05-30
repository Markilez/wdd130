//+------------------------------------------------------------------+
//|                EnhancedPriceActionScalperPro.mq5               |
//|                        Copyright 2025                            |
//|                                       https://www.mql5.com       |
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window

// Input Parameters
input group "==== Risk Management ===="
input double RiskRewardRatio = 3.0;          // Risk-Reward Ratio
input double StopLoss = 300;                 // Stop Loss in points
input double RiskPercentage = 1.0;           // Risk % of account
input double UserLotSize = 0.20;             // Lot size
input int MagicNumber = 5860;                // Magic number
input int MaxOpenPositions = 5;              // Max open positions
input double LockInProfitThreshold = 20;     // Lock profit threshold ($)
input double MaxLossThreshold = 100;         // Max loss threshold ($)
input double MaxDrawdownPercentage = 10;     // Max drawdown %
input double TrailingStopPoints = 50;        // Trailing distance in points
input double TrailingStep = 10;              // Minimum SL move in points

// Trading Rules
input group "==== Trading Rules ===="
input ENUM_TIMEFRAMES TimeFrame = PERIOD_H1;
input int TradeCooldownSeconds = 60;
input int SupportResistanceLookback = 50;
input double PinBarThreshold = 0.6;
input int InsideBarLookback = 3;
input double VolumeSpikeMultiplier = 1.5;
input bool RequireCloseConfirmation = true;

// CCI Filter
input group "==== CCI Filter ===="
input int CCIPeriod = 14;
input double CCITrendThreshold = 100;
input bool UseCCIFilter = true;

// EMA Filters
input group "==== EMA Filters ===="
input int EMA13_Period = 13;
input int EMA50_Period = 50;
input int EMA200_Period = 200;
input bool UseEMAFilter = true;

// Visual & Alerts
input group "==== Visual & Alert Settings ===="
input bool ShowEntrySignals = true;
input bool EnableAlerts = true;
input bool EnableLogging = true;
input color BuySignalColor = clrDodgerBlue;
input color SellSignalColor = clrRed;
input int ArrowSize = 2;

// Global variables
long chartId;
datetime lastTradeTime=0;
bool isProfitsLocked=false;
double supportLevel=0, resistanceLevel=0;
int cciHandle;
int ema13Handle, ema50Handle, ema200Handle;
double dailyEquityHigh, dailyEquityLow;
double TakeProfit; // in points
string currentSymbol; // Track current symbol for multi-pair compatibility

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    chartId=ChartID();
    currentSymbol = _Symbol; // Store current symbol
    dailyEquityHigh=AccountInfoDouble(ACCOUNT_EQUITY);
    dailyEquityLow=dailyEquityHigh;

    TakeProfit=StopLoss*RiskRewardRatio; // in points

    // Initialize indicators for current symbol
    if(!InitializeIndicators())
        return INIT_FAILED;

    Print("EA initialized for ", currentSymbol, ", TP in points: ", TakeProfit);
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Initialize indicators for current symbol                          |
//+------------------------------------------------------------------+
bool InitializeIndicators()
{
    // Release any existing handles first
    if(cciHandle != INVALID_HANDLE) IndicatorRelease(cciHandle);
    if(ema13Handle != INVALID_HANDLE) IndicatorRelease(ema13Handle);
    if(ema50Handle != INVALID_HANDLE) IndicatorRelease(ema50Handle);
    if(ema200Handle != INVALID_HANDLE) IndicatorRelease(ema200Handle);

    // Initialize new handles
    cciHandle=iCCI(currentSymbol,TimeFrame,CCIPeriod,PRICE_TYPICAL);
    ema13Handle = iMA(currentSymbol, TimeFrame, EMA13_Period, 0, MODE_EMA, PRICE_CLOSE);
    ema50Handle = iMA(currentSymbol, TimeFrame, EMA50_Period, 0, MODE_EMA, PRICE_CLOSE);
    ema200Handle = iMA(currentSymbol, TimeFrame, EMA200_Period, 0, MODE_EMA, PRICE_CLOSE);

    if(cciHandle==INVALID_HANDLE || ema13Handle == INVALID_HANDLE || 
       ema50Handle == INVALID_HANDLE || ema200Handle == INVALID_HANDLE)
    {
        Print("Failed to initialize indicators for ", currentSymbol);
        return false;
    }
    return true;
}

//+------------------------------------------------------------------+
//| Main Tick Handler                                                |
//+------------------------------------------------------------------+
void OnTick()
{
    // Check if symbol changed (for multi-pair operation)
    if(_Symbol != currentSymbol)
    {
        currentSymbol = _Symbol;
        if(!InitializeIndicators())
            return;
    }

    if(IsNewBar())
        CalculateSupportResistance();

    if(CheckTradeConditions() && CountOpenPositions()<MaxOpenPositions && CheckTradingAllowed())
    {
        if(ShowEntrySignals)
            DrawEntrySignal();

        OpenTrade();
    }

    ManageOpenTrades();
}

//+------------------------------------------------------------------+
//| Check trade conditions with filters                              |
//+------------------------------------------------------------------+
bool CheckTradeConditions()
{
    // Check minimum bars required
    int requiredBars = MathMax(SupportResistanceLookback, MathMax(EMA200_Period, MathMax(CCIPeriod, InsideBarLookback + 2)));
    if (Bars(currentSymbol, TimeFrame) < requiredBars)
    {
        if (EnableLogging) Print("Not enough bars for ", currentSymbol, " (", Bars(currentSymbol, TimeFrame), "). Required: ", requiredBars);
        return false;
    }

    double close = iClose(currentSymbol, TimeFrame, 0);
    bool buySignal = (CheckPinBar(true) || CheckInsideBarBreakout(true)) && close > supportLevel;
    bool sellSignal = (CheckPinBar(false) || CheckInsideBarBreakout(false)) && close < resistanceLevel;

    if (!buySignal && !sellSignal) return false;

    // Volume filter
    double currVol = iVolume(currentSymbol, TimeFrame, 0);
    double avgVol = iMA(currentSymbol, TimeFrame, 20, 0, MODE_SMA, VOLUME_TICK);
    bool volumeFilter = currVol > avgVol * VolumeSpikeMultiplier;

    // CCI filter
    bool cciFilter = true;
    if(UseCCIFilter)
    {
        double cci[];
        if(CopyBuffer(cciHandle, 0, 0, 2, cci) < 2)
        {
            Print("Failed to copy CCI buffer for ", currentSymbol);
            return false;
        }
        ArraySetAsSeries(cci, true);
        cciFilter = (buySignal && cci[0] > -CCITrendThreshold && cci[0] > cci[1]) ||
                    (sellSignal && cci[0] < CCITrendThreshold && cci[0] < cci[1]);
    }

    // EMA filter
    bool emaFilter = true;
    if(UseEMAFilter)
    {
        double ema13[], ema50[], ema200[];
        if(CopyBuffer(ema13Handle, 0, 0, 1, ema13) < 1 ||
           CopyBuffer(ema50Handle, 0, 0, 1, ema50) < 1 ||
           CopyBuffer(ema200Handle, 0, 0, 1, ema200) < 1)
        {
            Print("Failed to copy EMA buffers for ", currentSymbol);
            return false;
        }
        ArraySetAsSeries(ema13, true);
        ArraySetAsSeries(ema50, true);
        ArraySetAsSeries(ema200, true);

        double currentPrice = close;

        if (buySignal)
        {
            emaFilter = (currentPrice > ema13[0] && ema13[0] > ema50[0] && ema50[0] > ema200[0]);
        }
        else if (sellSignal)
        {
            emaFilter = (currentPrice < ema13[0] && ema13[0] < ema50[0] && ema50[0] < ema200[0]);
        }
    }

    bool confirmation = !RequireCloseConfirmation || (buySignal ? ConfirmBuySignal() : ConfirmSellSignal());

    if (buySignal)
    {
        return volumeFilter && confirmation && cciFilter && emaFilter;
    }
    else if (sellSignal)
    {
        return volumeFilter && confirmation && cciFilter && emaFilter;
    }

    return false;
}

//+------------------------------------------------------------------+
//| Open trade with TP at entry                                      |
//+------------------------------------------------------------------+
void OpenTrade()
{
    if(TimeCurrent() - lastTradeTime < TradeCooldownSeconds)
        return;

    bool isBuy = CheckPinBar(true) || CheckInsideBarBreakout(true);
    if(CountOpenPositionsInDirection(isBuy) > 0)
        return;

    double price, sl, tp;
    ENUM_ORDER_TYPE orderType;

    if(isBuy)
    {
        price = NormalizeDouble(SymbolInfoDouble(currentSymbol, SYMBOL_ASK), _Digits);
        sl = NormalizeDouble(price - StopLoss * _Point, _Digits);
        tp = NormalizeDouble(price + TakeProfit * _Point, _Digits);
        orderType = ORDER_TYPE_BUY;
    }
    else
    {
        price = NormalizeDouble(SymbolInfoDouble(currentSymbol, SYMBOL_BID), _Digits);
        sl = NormalizeDouble(price + StopLoss * _Point, _Digits);
        tp = NormalizeDouble(price - TakeProfit * _Point, _Digits);
        orderType = ORDER_TYPE_SELL;
    }

    MqlTradeRequest request={};
    MqlTradeResult result={};
    request.action = TRADE_ACTION_DEAL;
    request.symbol = currentSymbol;
    request.volume = CalculateLotSize();
    request.price = price;
    request.sl = sl;
    request.tp = tp;
    request.type = orderType;
    request.type_filling = ORDER_FILLING_FOK;
    request.magic = MagicNumber;
    request.comment = "EA Trade";

    if(!OrderSend(request, result))
    {
        Print("Order send failed for ", currentSymbol, ". Error: ", GetLastError());
    }
    else if(result.retcode != TRADE_RETCODE_DONE)
    {
        Print("Trade failed for ", currentSymbol, ". Return code: ", result.retcode);
    }
    else
    {
        lastTradeTime = TimeCurrent();
        isProfitsLocked = false;
        if(EnableAlerts) Alert("Trade opened on ", currentSymbol);
        if(EnableLogging) Print("Trade opened on ", currentSymbol, " at ", price);
    }
}

//+------------------------------------------------------------------+
//| Manage SL, TP, proactive trailing                                |
//+------------------------------------------------------------------+
void ManageOpenTrades()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(!PositionSelectByTicket(ticket) || PositionGetInteger(POSITION_MAGIC) != MagicNumber)
            continue;

        string positionSymbol = PositionGetString(POSITION_SYMBOL);
        ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        double currentPrice = (type == POSITION_TYPE_BUY) ? 
                             SymbolInfoDouble(positionSymbol, SYMBOL_BID) : 
                             SymbolInfoDouble(positionSymbol, SYMBOL_ASK);
        double profit = PositionGetDouble(POSITION_PROFIT);
        double sl = PositionGetDouble(POSITION_SL);
        double tp = PositionGetDouble(POSITION_TP);
        double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);

        // Lock profits once threshold reached
        if(!isProfitsLocked && profit >= LockInProfitThreshold)
        {
            double newSL = (type == POSITION_TYPE_BUY) ? 
                         currentPrice - StopLoss * _Point : 
                         currentPrice + StopLoss * _Point;
            SetStopLoss(ticket, newSL);
            isProfitsLocked = true;
        }

        // Proactive trailing stop
        if(TrailingStopPoints > 0)
        {
            double newSL;
            if(type == POSITION_TYPE_BUY)
            {
                double trailSL = currentPrice - TrailingStopPoints * _Point;
                if(trailSL > sl && trailSL > openPrice && trailSL >= sl + TrailingStep * _Point)
                {
                    newSL = trailSL;
                    SetStopLoss(ticket, newSL);
                }
            }
            else
            {
                double trailSL = currentPrice + TrailingStopPoints * _Point;
                if(trailSL < sl && trailSL < openPrice && trailSL <= sl - TrailingStep * _Point)
                {
                    newSL = trailSL;
                    SetStopLoss(ticket, newSL);
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Set stop loss for a position                                     |
//+------------------------------------------------------------------+
bool SetStopLoss(ulong ticket, double newSL)
{
    MqlTradeRequest request={};
    MqlTradeResult result={};
    request.action = TRADE_ACTION_SLTP;
    request.position = ticket;
    request.sl = newSL;
    request.tp = PositionGetDouble(POSITION_TP); // Preserve existing TP
    
    if(!OrderSend(request, result))
    {
        Print("Failed to modify SL for ticket ", ticket, ". Error: ", GetLastError());
        return false;
    }
    if(result.retcode != TRADE_RETCODE_DONE)
    {
        Print("Failed to modify SL for ticket ", ticket, ". Return code: ", result.retcode);
        return false;
    }
    return true;
}

//+------------------------------------------------------------------+
//| Close position helper                                            |
//+------------------------------------------------------------------+
void ClosePosition(ulong ticket)
{
    if(!PositionSelectByTicket(ticket)) return;
    
    string positionSymbol = PositionGetString(POSITION_SYMBOL);
    ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
    
    MqlTradeRequest request={};
    MqlTradeResult result={};
    request.action = TRADE_ACTION_DEAL;
    request.symbol = positionSymbol;
    request.volume = PositionGetDouble(POSITION_VOLUME);
    request.type = (type == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
    request.position = ticket;
    request.price = (type == POSITION_TYPE_BUY) ? 
                   SymbolInfoDouble(positionSymbol, SYMBOL_BID) : 
                   SymbolInfoDouble(positionSymbol, SYMBOL_ASK);
    
    if(!OrderSend(request, result))
    {
        Print("Close position failed for ticket ", ticket, " on ", positionSymbol, ". Error: ", GetLastError());
    }
    else if(result.retcode != TRADE_RETCODE_DONE)
    {
        Print("Close position failed for ticket ", ticket, " on ", positionSymbol, ". Return code: ", result.retcode);
    }
    else
    {
        if(EnableLogging) Print("Position closed for ticket ", ticket, " on ", positionSymbol);
    }
}

//+------------------------------------------------------------------+
//| Utility functions                                               |
//+------------------------------------------------------------------+
bool IsNewBar()
{
    static datetime lastBarTime = 0;
    datetime currentBarTime = iTime(currentSymbol, TimeFrame, 0);
    if(lastBarTime != currentBarTime)
    {
        lastBarTime = currentBarTime;
        return true;
    }
    return false;
}

void CalculateSupportResistance()
{
    double highs[], lows[];
    ArraySetAsSeries(highs, true);
    ArraySetAsSeries(lows, true);
    CopyHigh(currentSymbol, TimeFrame, 0, SupportResistanceLookback, highs);
    CopyLow(currentSymbol, TimeFrame, 0, SupportResistanceLookback, lows);
    resistanceLevel = highs[ArrayMaximum(highs)];
    supportLevel = lows[ArrayMinimum(lows)];
    if(EnableLogging)
        Print("S/R updated for ", currentSymbol, ": S=", supportLevel, " R=", resistanceLevel);
}

bool CheckPinBar(bool isBuySignal)
{
    double open = iOpen(currentSymbol, TimeFrame, 0);
    double high = iHigh(currentSymbol, TimeFrame, 0);
    double low = iLow(currentSymbol, TimeFrame, 0);
    double close = iClose(currentSymbol, TimeFrame, 0);
    double bodySize = MathAbs(close - open);
    double upperWick = high - MathMax(open, close);
    double lowerWick = MathMin(open, close) - low;
    
    if(isBuySignal)
        return (close > open) && (lowerWick >= bodySize * PinBarThreshold) && (upperWick < bodySize * 0.5);
    else
        return (close < open) && (upperWick >= bodySize * PinBarThreshold) && (lowerWick < bodySize * 0.5);
}

bool CheckInsideBarBreakout(bool isBuySignal)
{
    double motherHigh = iHigh(currentSymbol, TimeFrame, 1);
    double motherLow = iLow(currentSymbol, TimeFrame, 1);
    
    for(int i = 2; i <= InsideBarLookback; i++)
    {
        if(iHigh(currentSymbol, TimeFrame, i) > motherHigh || iLow(currentSymbol, TimeFrame, i) < motherLow)
            return false;
    }
    
    return isBuySignal ? (iHigh(currentSymbol, TimeFrame, 0) > motherHigh) : 
                         (iLow(currentSymbol, TimeFrame, 0) < motherLow);
}

bool ConfirmBuySignal() { return iClose(currentSymbol, TimeFrame, 0) > iClose(currentSymbol, TimeFrame, 1); }
bool ConfirmSellSignal() { return iClose(currentSymbol, TimeFrame, 0) < iClose(currentSymbol, TimeFrame, 1); }

void DrawEntrySignal()
{
    static datetime lastSignalTime = 0;
    if(TimeCurrent() == lastSignalTime) return;
    lastSignalTime = TimeCurrent();
    
    bool isBuy = (CheckPinBar(true) || CheckInsideBarBreakout(true)) && CheckTradeConditions();
    string arrowName = "TradeSignal_" + currentSymbol + "_" + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES);
    
    if(ObjectFind(0, arrowName) == -1)
    {
        double arrowPrice = isBuy ? 
                          iLow(currentSymbol, TimeFrame, 0) - 10 * _Point : 
                          iHigh(currentSymbol, TimeFrame, 0) + 10 * _Point;
        
        if(ObjectCreate(0, arrowName, OBJ_ARROW, 0, TimeCurrent(), arrowPrice))
        {
            ObjectSetInteger(0, arrowName, OBJPROP_COLOR, isBuy ? BuySignalColor : SellSignalColor);
            ObjectSetInteger(0, arrowName, OBJPROP_ARROWCODE, isBuy ? 241 : 242);
            ObjectSetInteger(0, arrowName, OBJPROP_WIDTH, ArrowSize);
        }
    }
}

int CountOpenPositionsInDirection(bool isBuySignal)
{
    int count = 0;
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket) &&
           PositionGetString(POSITION_SYMBOL) == currentSymbol &&
           PositionGetInteger(POSITION_MAGIC) == MagicNumber)
        {
            if((isBuySignal && PositionGetInteger(POSITION_TYPE) == ORDER_TYPE_BUY) ||
               (!isBuySignal && PositionGetInteger(POSITION_TYPE) == ORDER_TYPE_SELL))
                count++;
        }
    }
    return count;
}

double CalculateLotSize()
{
    if(UserLotSize > 0) return UserLotSize;
    
    double accountEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    double riskAmount = accountEquity * (RiskPercentage / 100);
    double tickValue = SymbolInfoDouble(currentSymbol, SYMBOL_TRADE_TICK_VALUE);
    
    if(tickValue <= 0)
    {
        // Fallback calculation for symbols without tick value
        tickValue = SymbolInfoDouble(currentSymbol, SYMBOL_TRADE_TICK_SIZE) / 
                   SymbolInfoDouble(currentSymbol, SYMBOL_TRADE_CONTRACT_SIZE);
    }
    
    double lotSize = riskAmount / (StopLoss * _Point * tickValue);
    
    double minLot = SymbolInfoDouble(currentSymbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(currentSymbol, SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(currentSymbol, SYMBOL_VOLUME_STEP);
    
    lotSize = MathRound(lotSize / lotStep) * lotStep;
    lotSize = MathMax(MathMin(lotSize, maxLot), minLot);
    
    return lotSize;
}

int CountOpenPositions()
{
    int count = 0;
    for(int i = 0; i < PositionsTotal(); i++)
    {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket) &&
           PositionGetString(POSITION_SYMBOL) == currentSymbol &&
           PositionGetInteger(POSITION_MAGIC) == MagicNumber)
            count++;
    }
    return count;
}

bool CheckTradingAllowed()
{
    double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    dailyEquityHigh = MathMax(dailyEquityHigh, currentEquity);
    dailyEquityLow = MathMin(dailyEquityLow, currentEquity);
    
    if(MaxDrawdownPercentage > 0 && currentEquity < dailyEquityHigh * (1 - MaxDrawdownPercentage / 100))
    {
        if(EnableLogging) Print("Trading disabled: Max drawdown exceeded on ", currentSymbol);
        return false;
    }
    
    if(MaxLossThreshold > 0 && (dailyEquityHigh - currentEquity) >= MaxLossThreshold)
    {
        if(EnableLogging) Print("Trading disabled: Max loss threshold reached on ", currentSymbol);
        return false;
    }
    
    return true;
}
//+------------------------------------------------------------------+
