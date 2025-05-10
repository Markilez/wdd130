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
input double TrailingStopPoints = 50;       // Trailing distance in points
input double TrailingStep = 10;              // Minimum SL move in points
input double MaxProfitPerPosition = 0;       // Max profit target per position ($)
input double ReverseClosePercentage = 50;    // Percentage of TP to reach before enabling reversal close

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
double supportLevel=0, resistanceLevel=0;
int cciHandle;
int ema13Handle, ema50Handle, ema200Handle;
double dailyEquityHigh, dailyEquityLow;
double TakeProfitPoints;
datetime lastSignalBarTime = 0;
datetime lastBarTime = 0;

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    chartId=ChartID();
    dailyEquityHigh=AccountInfoDouble(ACCOUNT_EQUITY);
    dailyEquityLow=dailyEquityHigh;

    TakeProfitPoints=StopLoss*RiskRewardRatio;

    cciHandle=iCCI(NULL,TimeFrame,CCIPeriod,PRICE_TYPICAL);
    if(cciHandle==INVALID_HANDLE)
    {
        Print("Failed to initialize CCI handle");
        return INIT_FAILED;
    }

    // Initialize EMA handles
    ema13Handle = iMA(NULL, TimeFrame, EMA13_Period, 0, MODE_EMA, PRICE_CLOSE);
    ema50Handle = iMA(NULL, TimeFrame, EMA50_Period, 0, MODE_EMA, PRICE_CLOSE);
    ema200Handle = iMA(NULL, TimeFrame, EMA200_Period, 0, MODE_EMA, PRICE_CLOSE);

    if(ema13Handle == INVALID_HANDLE || ema50Handle == INVALID_HANDLE || ema200Handle == INVALID_HANDLE)
    {
        Print("Failed to initialize EMA handles");
        return INIT_FAILED;
    }

    lastBarTime = iTime(NULL, TimeFrame, 0);

    Print("EA initialized, TP in points: ", TakeProfitPoints);
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Deinitialization                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if(cciHandle != INVALID_HANDLE) IndicatorRelease(cciHandle);
    if(ema13Handle != INVALID_HANDLE) IndicatorRelease(ema13Handle);
    if(ema50Handle != INVALID_HANDLE) IndicatorRelease(ema50Handle);
    if(ema200Handle != INVALID_HANDLE) IndicatorRelease(ema200Handle);

    // Corrected ObjectsDeleteAll call
    ObjectsDeleteAll(chartId, -1, OBJ_ARROW);
}

//+------------------------------------------------------------------+
//| Main Tick Handler                                                |
//+------------------------------------------------------------------+
void OnTick()
{
    if(IsNewBar())
        CalculateSupportResistance();

    if(CheckTradingAllowed() && CountOpenPositions() < MaxOpenPositions)
    {
        if(CheckTradeConditions())
        {
            if(ShowEntrySignals)
                DrawEntrySignal();

            OpenTrade();
        }
    }

    ManageOpenTrades();
}

//+------------------------------------------------------------------+
//| Check trade conditions with filters                              |
//+------------------------------------------------------------------+
bool CheckTradeConditions()
{
    int requiredBars = MathMax(SupportResistanceLookback, MathMax(EMA200_Period, MathMax(CCIPeriod, InsideBarLookback + 2)));
    if (Bars(NULL, TimeFrame) < requiredBars)
    {
        if (EnableLogging) Print("Not enough bars (", Bars(NULL, TimeFrame), ") for indicator calculations. Required: ", requiredBars);
        return false;
    }

    double open = iOpen(NULL, TimeFrame, 0);
    double high = iHigh(NULL, TimeFrame, 0);
    double low = iLow(NULL, TimeFrame, 0);
    double close = iClose(NULL, TimeFrame, 0);

    bool buySignal = (CheckPinBar(true) || CheckInsideBarBreakout(true)) && close > supportLevel;
    bool sellSignal= (CheckPinBar(false) || CheckInsideBarBreakout(false)) && close < resistanceLevel;

    if (!buySignal && !sellSignal) return false;

    double currVol=iVolume(NULL,TimeFrame,0);
    double avgVol=iMA(NULL,TimeFrame,20,0,MODE_SMA,VOLUME_TICK);
    bool volumeFilter=currVol>avgVol*VolumeSpikeMultiplier;

    bool cciFilter=true;
    if(UseCCIFilter)
    {
        double cci[];
        if(CopyBuffer(cciHandle,0,0,2,cci)<2)
        {
            Print("Failed to copy CCI buffer");
            return false;
        }
        ArraySetAsSeries(cci,true);
        cciFilter = (buySignal && cci[0] > -CCITrendThreshold && cci[0] > cci[1]) ||
                    (sellSignal && cci[0] < CCITrendThreshold && cci[0] < cci[1]);
    }

    bool emaFilter = true;
    if(UseEMAFilter)
    {
        double ema13[], ema50[], ema200[];
        if(CopyBuffer(ema13Handle, 0, 0, 1, ema13) < 1 ||
           CopyBuffer(ema50Handle, 0, 0, 1, ema50) < 1 ||
           CopyBuffer(ema200Handle, 0, 0, 1, ema200) < 1)
        {
            Print("Failed to copy EMA buffers");
            return false;
        }
        ArraySetAsSeries(ema13, true);
        ArraySetAsSeries(ema50, true);
        ArraySetAsSeries(ema200, true);

        double currentPrice = close;

        if (buySignal)
        {
            emaFilter = (currentPrice > ema13[0] &&
                         ema13[0] > ema50[0] &&
                         ema50[0] > ema200[0]);
        }
        else if (sellSignal)
        {
            emaFilter = (currentPrice < ema13[0] &&
                         ema13[0] < ema50[0] &&
                         ema50[0] < ema200[0]);
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
    {
        if (EnableLogging) Print("Trade cooldown in effect");
        return;
    }

    bool isBuy=CheckPinBar(true) || CheckInsideBarBreakout(true);
    if(CountOpenPositionsInDirection(isBuy)>0)
    {
        if (EnableLogging) Print("Position in same direction already exists");
        return;
    }

    double price, sl, tp;
    ENUM_ORDER_TYPE orderType;

    if(isBuy)
    {
        price=NormalizeDouble(SymbolInfoDouble(_Symbol,SYMBOL_ASK),_Digits);
        sl=NormalizeDouble(price - StopLoss*_Point,_Digits);
        tp=NormalizeDouble(price + TakeProfitPoints*_Point,_Digits);
        orderType=ORDER_TYPE_BUY;
    }
    else
    {
        price=NormalizeDouble(SymbolInfoDouble(_Symbol,SYMBOL_BID),_Digits);
        sl=NormalizeDouble(price + StopLoss*_Point,_Digits);
        tp=NormalizeDouble(price - TakeProfitPoints*_Point,_Digits);
        orderType=ORDER_TYPE_SELL;
    }

    MqlTradeRequest request={};
    MqlTradeResult result={};
    request.action=TRADE_ACTION_DEAL;
    request.symbol=_Symbol;
    request.volume=CalculateLotSize();
    request.price=price;
    request.sl=sl;
    request.tp=tp;
    request.type=orderType;
    request.type_filling=ORDER_FILLING_FOK;
    request.magic=MagicNumber;
    request.comment="Rock&Roll";

    if(!OrderSend(request,result))
    {
        Print("Order send failed. Error: ", GetLastError());
    }
    else if(result.retcode!=TRADE_RETCODE_DONE)
    {
        Print("Trade failed. Return code: ", result.retcode);
    }
    else
    {
        lastTradeTime=TimeCurrent();
        if(EnableAlerts) Alert(_Symbol, " Trade opened: ", EnumToString(orderType), " at ", price);
        if(EnableLogging) Print(_Symbol, " Trade opened: ", EnumToString(orderType), " at ", price, " SL: ", sl, " TP: ", tp, " Volume: ", request.volume);
    }
}

//+------------------------------------------------------------------+
//| Manage SL, TP, proactive trailing, and profit/loss management    |
//+------------------------------------------------------------------+
void ManageOpenTrades()
{
    for(int i=PositionsTotal()-1;i>=0;i--)
    {
        ulong ticket=PositionGetTicket(i);
        if(!PositionSelectByTicket(ticket) || PositionGetInteger(POSITION_MAGIC)!=MagicNumber || PositionGetString(POSITION_SYMBOL)!=_Symbol)
            continue;

        ENUM_POSITION_TYPE type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        double currentPrice=(type==POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol,SYMBOL_BID) : SymbolInfoDouble(_Symbol,SYMBOL_ASK);
        double profit=PositionGetDouble(POSITION_PROFIT);
        double sl=PositionGetDouble(POSITION_SL);
        double tp=PositionGetDouble(POSITION_TP);
        double openPrice=PositionGetDouble(POSITION_PRICE_OPEN);

        if (MaxProfitPerPosition > 0 && profit >= MaxProfitPerPosition)
        {
            if (EnableLogging) Print("Closing position ", ticket, " due to max profit reached: ", profit);
            ClosePosition(ticket);
            continue;
        }

        if (MaxLossThreshold > 0 && profit <= -MaxLossThreshold)
        {
            if (EnableLogging) Print("Closing position ", ticket, " due to max loss reached: ", profit);
            ClosePosition(ticket);
            continue;
        }

        if(LockInProfitThreshold > 0 && profit >= LockInProfitThreshold)
        {
            double newSL;
            if (type == POSITION_TYPE_BUY)
            {
                newSL = MathMax(sl, openPrice + TrailingStep*_Point);
                newSL = NormalizeDouble(newSL, _Digits);
                if (newSL > sl)
                {
                     SetStopLoss(ticket, newSL);
                }
            }
            else
            {
                newSL = MathMin(sl, openPrice - TrailingStep*_Point);
                newSL = NormalizeDouble(newSL, _Digits);
                 if (newSL < sl)
                 {
                    SetStopLoss(ticket, newSL);
                 }
            }
        }

        if(TrailingStopPoints>0)
        {
            double newSL;
            bool modified = false;
            if(type==POSITION_TYPE_BUY)
            {
                double trailSL=currentPrice - TrailingStopPoints*_Point;
                newSL = NormalizeDouble(trailSL, _Digits);
                if(newSL > sl && newSL > openPrice)
                {
                    if(newSL >= sl + TrailingStep*_Point)
                    {
                       SetStopLoss(ticket,newSL);
                       modified = true;
                    }
                }
            }
            else
            {
                double trailSL=currentPrice + TrailingStopPoints*_Point;
                newSL = NormalizeDouble(trailSL, _Digits);
                if(newSL < sl && newSL < openPrice)
                {
                    if(newSL <= sl - TrailingStep*_Point)
                    {
                        SetStopLoss(ticket,newSL);
                        modified = true;
                    }
                }
            }
            if (modified) continue;
        }

        if (ReverseClosePercentage > 0 && TakeProfitPoints > 0)
        {
             double targetProfitInPoints = TakeProfitPoints;
             double priceLevelForReverseCheck;

             if (type == POSITION_TYPE_BUY)
             {
                 priceLevelForReverseCheck = openPrice + targetProfitInPoints * (ReverseClosePercentage / 100.0) * _Point;
                 if (PositionGetDouble(POSITION_PRICE_CURRENT) >= priceLevelForReverseCheck && currentPrice < priceLevelForReverseCheck)
                 {
                     if (EnableLogging) Print("Closing position ", ticket, " due to reversal after reaching ", ReverseClosePercentage, "% of TP");
                     ClosePosition(ticket);
                     continue;
                 }
             }
             else
             {
                 priceLevelForReverseCheck = openPrice - targetProfitInPoints * (ReverseClosePercentage / 100.0) * _Point;
                 if (PositionGetDouble(POSITION_PRICE_CURRENT) <= priceLevelForReverseCheck && currentPrice > priceLevelForReverseCheck)
                 {
                      if (EnableLogging) Print("Closing position ", ticket, " due to reversal after reaching ", ReverseClosePercentage, "% of TP");
                      ClosePosition(ticket);
                      continue;
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
    if (PositionGetDouble(POSITION_SL) == newSL)
    {
        return true;
    }

    MqlTradeRequest request={};
    MqlTradeResult result={};
    request.action=TRADE_ACTION_SLTP;
    request.position=ticket;
    request.sl=newSL;
    request.tp = PositionGetDouble(POSITION_TP);

    if(!OrderSend(request,result))
    {
        Print("Failed to modify SL for ticket ", ticket, ". Error: ", GetLastError());
        return false;
    }
    if(result.retcode!=TRADE_RETCODE_DONE)
    {
        Print("Failed to modify SL for ticket ", ticket, ". Return code: ", result.retcode);
        return false;
    }
    if (EnableLogging) Print("Successfully modified SL for ticket ", ticket, " to ", newSL);
    return true;
}

//+------------------------------------------------------------------+
//| Close position helper                                            |
//+------------------------------------------------------------------+
void ClosePosition(ulong ticket)
{
    MqlTradeRequest request={};
    MqlTradeResult result={};
    request.action=TRADE_ACTION_DEAL;
    request.symbol=_Symbol;
    request.volume=PositionGetDouble(POSITION_VOLUME);
    request.type=(PositionGetInteger(POSITION_TYPE)==ORDER_TYPE_BUY)?ORDER_TYPE_SELL:ORDER_TYPE_BUY;
    request.position=ticket;
    request.price = (request.type == ORDER_TYPE_SELL) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    request.magic = MagicNumber;
    request.comment = "Closed by EA";

    if(!OrderSend(request,result))
    {
        Print("Close position failed for ticket ", ticket, ". Error: ", GetLastError());
    }
    else if(result.retcode!=TRADE_RETCODE_DONE)
    {
        Print("Close position failed for ticket ", ticket, ". Return code: ", result.retcode);
    }
    else
    {
        if (EnableAlerts) Alert(_Symbol, " Position closed for ticket ", ticket);
        if (EnableLogging) Print(_Symbol, " Position closed for ticket ", ticket, " at ", request.price);
    }
}

//+------------------------------------------------------------------+
//| Utility functions                                               |
//+------------------------------------------------------------------+
bool IsNewBar()
{
    datetime currentBarTime=iTime(NULL,TimeFrame,0);
    if(lastBarTime!=currentBarTime)
    {
        MqlDateTime lastBarDate, currentBarDate;
        TimeToStruct(lastBarTime, lastBarDate);
        TimeToStruct(currentBarTime, currentBarDate);
        
        if (lastBarDate.day != currentBarDate.day)
        {
             dailyEquityHigh = AccountInfoDouble(ACCOUNT_EQUITY);
             dailyEquityLow = dailyEquityHigh;
             if (EnableLogging) Print("New day detected. Daily Equity High/Low reset. New High: ", dailyEquityHigh);
        }
        lastBarTime=currentBarTime;
        return true;
    }
    return false;
}

void CalculateSupportResistance()
{
    double highs[], lows[];
    ArraySetAsSeries(highs,true);
    ArraySetAsSeries(lows,true);
    if (Bars(NULL, TimeFrame) < SupportResistanceLookback)
    {
        if (EnableLogging) Print("Not enough bars to calculate S/R");
        return;
    }
    CopyHigh(NULL,TimeFrame,0,SupportResistanceLookback,highs);
    CopyLow(NULL,TimeFrame,0,SupportResistanceLookback,lows);
    resistanceLevel=highs[ArrayMaximum(highs)];
    supportLevel=lows[ArrayMinimum(lows)];
    if(EnableLogging)
        Print("S/R updated: S=",supportLevel," R=",resistanceLevel);
}

bool CheckPinBar(bool isBuySignal)
{
    if (Bars(NULL, TimeFrame) < 2) return false;

    double open=iOpen(NULL,TimeFrame,0);
    double high=iHigh(NULL,TimeFrame,0);
    double low=iLow(NULL,TimeFrame,0);
    double close=iClose(NULL,TimeFrame,0);
    double bodySize=MathAbs(close-open);
    double upperWick=high-MathMax(open,close);
    double lowerWick=MathMin(open,close)-low;
    double totalRange = high - low;

    if (totalRange <= 0) return false;

    if(isBuySignal)
    {
        return (close >= open) &&
               (lowerWick >= totalRange * PinBarThreshold) &&
               (upperWick <= totalRange * (1.0 - PinBarThreshold));
    }
    else
    {
        return (close <= open) &&
               (upperWick >= totalRange * PinBarThreshold) &&
               (lowerWick <= totalRange * (1.0 - PinBarThreshold));
    }
}

bool CheckInsideBarBreakout(bool isBuySignal)
{
    if (Bars(NULL, TimeFrame) < InsideBarLookback + 2) return false;

    double motherHigh=iHigh(NULL,TimeFrame,1);
    double motherLow=iLow(NULL,TimeFrame,1);
    bool isInside=true;
    for(int i=2;i<=InsideBarLookback + 1;i++)
    {
        if(iHigh(NULL,TimeFrame,i)>motherHigh || iLow(NULL,TimeFrame,i)<motherLow)
        {
            isInside=false;
            break;
        }
    }
    if(!isInside) return false;

    double currentHigh = iHigh(NULL, TimeFrame, 0);
    double currentLow = iLow(NULL, TimeFrame, 0);
    double currentClose = iClose(NULL, TimeFrame, 0);

    if (isBuySignal)
    {
        return (currentHigh > motherHigh) && (!RequireCloseConfirmation || currentClose > motherHigh);
    }
    else
    {
        return (currentLow < motherLow) && (!RequireCloseConfirmation || currentClose < motherLow);
    }
}

bool ConfirmBuySignal()
{
    if (Bars(NULL, TimeFrame) < 2) return false;
    return iClose(NULL,TimeFrame,0)>iClose(NULL,TimeFrame,1);
}

bool ConfirmSellSignal()
{
    if (Bars(NULL, TimeFrame) < 2) return false;
    return iClose(NULL,TimeFrame,0)<iClose(NULL,TimeFrame,1);
}

void DrawEntrySignal()
{
    datetime currentBarTime = iTime(NULL, TimeFrame, 0);
    if (currentBarTime == lastSignalBarTime) return;

    bool isBuy = (CheckPinBar(true) || CheckInsideBarBreakout(true)) && CheckTradeConditions();
    bool isSell = (CheckPinBar(false) || CheckInsideBarBreakout(false)) && CheckTradeConditions();

    if (!isBuy && !isSell) return;

    string arrowName="TradeSignal_"+TimeToString(currentBarTime,TIME_DATE|TIME_MINUTES)+"_"+_Symbol;
    int arrowCode=isBuy?241:242;
    color arrowColor=isBuy?BuySignalColor:SellSignalColor;

    string prevArrowName="TradeSignal_"+TimeToString(lastSignalBarTime,TIME_DATE|TIME_MINUTES)+"_"+_Symbol;
    if (ObjectFind(0, prevArrowName) != -1)
    {
        ObjectDelete(0, prevArrowName);
    }

    if (ObjectFind(0, arrowName) != -1)
    {
        ObjectDelete(0, arrowName);
    }

    double arrowPrice = isBuy ? iLow(NULL, TimeFrame, 0) - _Point*10 : iHigh(NULL, TimeFrame, 0) + _Point*10;
    if(ObjectCreate(0,arrowName,OBJ_ARROW,0,currentBarTime,arrowPrice))
    {
        ObjectSetInteger(0,arrowName,OBJPROP_COLOR,arrowColor);
        ObjectSetInteger(0,arrowName,OBJPROP_ARROWCODE,arrowCode);
        ObjectSetInteger(0,arrowName,OBJPROP_WIDTH,ArrowSize);
        ObjectSetInteger(0, arrowName, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, arrowName, OBJPROP_HIDDEN, false);
        ObjectSetInteger(0, arrowName, OBJPROP_ZORDER, 0);

        if (EnableLogging) Print("Drawing signal: ", arrowName, " at ", currentBarTime);
    }
    else
    {
         Print("Failed to create arrow object: ", arrowName, ". Error: ", GetLastError());
    }

    lastSignalBarTime = currentBarTime;
}

int CountOpenPositionsInDirection(bool isBuySignal)
{
    int count=0;
    for(int i=PositionsTotal()-1;i>=0;i--)
    {
        ulong ticket=PositionGetTicket(i);
        if(PositionSelectByTicket(ticket))
        {
            if(PositionGetString(POSITION_SYMBOL)==_Symbol &&
               PositionGetInteger(POSITION_MAGIC)==MagicNumber)
            {
                if((isBuySignal && PositionGetInteger(POSITION_TYPE)==ORDER_TYPE_BUY) ||
                   (!isBuySignal && PositionGetInteger(POSITION_TYPE)==ORDER_TYPE_SELL))
                    count++;
            }
        }
    }
    return count;
}

double CalculateLotSize()
{
    if(UserLotSize>0) return UserLotSize;

    double accountEquity=AccountInfoDouble(ACCOUNT_EQUITY);
    double riskAmount=accountEquity*(RiskPercentage/100.0);

    double pointValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    if (pointValue <= 0)
    {
         pointValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE) / SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
         if (SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT) != AccountInfoString(ACCOUNT_CURRENCY))
         {
             if (EnableLogging) Print("Warning: Using approximated point value. Profit currency differs from account currency.");
         }
    }

    double stopLossValue = StopLoss * pointValue;

    if (stopLossValue <= 0)
    {
        Print("Cannot calculate lot size: Stop Loss value is zero or negative (", stopLossValue, "). Check StopLoss setting or symbol info.");
        return 0;
    }

    double lotSize=riskAmount/stopLossValue;

    double minLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
    double maxLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
    double lotStep=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);

    lotSize=MathRound(lotSize/lotStep)*lotStep;
    lotSize=MathMax(lotSize,minLot);
    lotSize=MathMin(lotSize,maxLot);

    if (lotSize <= 0)
    {
        if (EnableLogging) Print("Calculated lot size is zero or negative (", lotSize, "). Using minimum lot size (", minLot, ").");
        lotSize = minLot;
    }

    if (EnableLogging) Print("Calculated Lot Size: ", lotSize, " (Risk %: ", RiskPercentage, ", SL Points: ", StopLoss, ", Risk Amount: ", riskAmount, ", SL Value: ", stopLossValue, ")");
    return lotSize;
}

int CountOpenPositions()
{
    int count=0;
    for(int i=PositionsTotal()-1;i>=0;i--)
    {
        ulong ticket=PositionGetTicket(i);
        if(PositionSelectByTicket(ticket))
        {
            if(PositionGetString(POSITION_SYMBOL)==_Symbol &&
               PositionGetInteger(POSITION_MAGIC)==MagicNumber)
                count++;
        }
    }
    return count;
}

bool CheckTradingAllowed()
{
    double currentEquity=AccountInfoDouble(ACCOUNT_EQUITY);
    dailyEquityHigh = MathMax(dailyEquityHigh, currentEquity);
    dailyEquityLow = MathMin(dailyEquityLow, currentEquity);

    if(MaxDrawdownPercentage > 0 && currentEquity<dailyEquityHigh*(1-MaxDrawdownPercentage/100.0))
    {
        if (EnableLogging) Print("Trading disabled: Max drawdown exceeded (Current Equity: ", currentEquity, ", Daily High: ", dailyEquityHigh, ", Drawdown Limit: ", dailyEquityHigh*(1-MaxDrawdownPercentage/100.0), ")");
        return false;
    }

    if (MaxLossThreshold > 0 && (dailyEquityHigh - currentEquity) >= MaxLossThreshold)
    {
        if (EnableLogging) Print("Trading disabled: Daily loss threshold reached (Current Loss: ", (dailyEquityHigh - currentEquity), ", Threshold: ", MaxLossThreshold, ")");
         return false;
    }

    return true;
}
//+------------------------------------------------------------------+
