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
input int MagicNumber = 5840;                 // Magic number
input int MaxOpenPositions = 5;                // Max open positions
input double LockInProfitThreshold = 20;       // Lock profit threshold ($)
input double MaxLossThreshold = 100;           // Max loss threshold ($)
input double MaxDrawdownPercentage = 10;       // Max drawdown %
input double TrailingStopPoints = 50;          // Trailing distance in points
input double TrailingStep = 10;                // Minimum SL move in points
input double MaxProfitPerPosition = 100.0;     // Maximum profit per position in $
input double ReverseClosePercentage = 50.0;    // Percentage of TP to reverse and close

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
double dailyEquityHigh, dailyEquityLow;
double TakeProfitPoints; // in points

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    chartId=ChartID();
    dailyEquityHigh=AccountInfoDouble(ACCOUNT_EQUITY);
    dailyEquityLow=dailyEquityHigh;

    TakeProfitPoints=StopLoss*RiskRewardRatio; // in points

    cciHandle=iCCI(NULL,TimeFrame,CCIPeriod,PRICE_TYPICAL);
    if(cciHandle==INVALID_HANDLE)
    {
        Print("Failed to initialize CCI handle");
        return INIT_FAILED;
    }

    Print("EA initialized, TP in points: ", TakeProfitPoints);
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Main Tick Handler                                                |
//+------------------------------------------------------------------+
void OnTick()
{
    if(IsNewBar())
        CalculateSupportResistance();

    if(CheckTradeConditions() && CountOpenPositions()<MaxOpenPositions && CheckTradingAllowed())
    {
        if(ShowEntrySignals)
            DrawEntrySignal();

        OpenTrade();
    }

    ManageOpenTrades(); // SL, TP, trailing, max profit, reverse close
}

//+------------------------------------------------------------------+
//| Check trade conditions with filters                                |
//+------------------------------------------------------------------+
bool CheckTradeConditions()
{
    bool buySignal = (CheckPinBar(true) || CheckInsideBarBreakout(true)) && iClose(NULL,TimeFrame,0)>supportLevel;
    bool sellSignal= (CheckPinBar(false) || CheckInsideBarBreakout(false)) && iClose(NULL,TimeFrame,0)<resistanceLevel;

    double currVol=iVolume(NULL,TimeFrame,0);
    double avgVol=iMA(NULL,TimeFrame,20,0,MODE_SMA,VOLUME_TICK);
    bool volumeFilter=currVol>avgVol*VolumeSpikeMultiplier;

    bool cciFilter=true;
    if(UseCCIFilter)
    {
        double cci[];
        if(CopyBuffer(cciHandle,0,0,2,cci)<0)
        {
            Print("Failed to copy CCI buffer");
            return false;
        }
        ArraySetAsSeries(cci,true);
        cciFilter = (buySignal && cci[0]>-CCITrendThreshold && cci[0]>cci[1]) ||
                    (sellSignal && cci[0]<CCITrendThreshold && cci[0]<cci[1]);
    }

    bool confirmation = !RequireCloseConfirmation || (buySignal ? ConfirmBuySignal() : ConfirmSellSignal());

    return (buySignal && volumeFilter && confirmation && cciFilter) ||
           (sellSignal && volumeFilter && confirmation && cciFilter);
}

//+------------------------------------------------------------------+
//| Open trade with TP at entry                                         |
//+------------------------------------------------------------------+
void OpenTrade()
{
    if(TimeCurrent() - lastTradeTime < TradeCooldownSeconds)
        return;

    bool isBuy=CheckPinBar(true) || CheckInsideBarBreakout(true);
    if(CountOpenPositionsInDirection(isBuy)>0)
        return;

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
    request.comment="Enhanced EA";

    if(!OrderSend(request,result))
        Print("Order send failed");
    else if(result.retcode!=TRADE_RETCODE_DONE)
        Print("Trade failed");
    else
    {
        lastTradeTime=TimeCurrent();
        isProfitsLocked=false;
        if(EnableAlerts) Alert("Trade opened");
    }
}

//+------------------------------------------------------------------+
//| Manage SL, TP, proactive trailing, max profit, reverse close      |
//+------------------------------------------------------------------+
void ManageOpenTrades()
{
    for(int i=0;i<PositionsTotal();i++)
    {
        ulong ticket=PositionGetTicket(i);
        if(!PositionSelectByTicket(ticket) || PositionGetInteger(POSITION_MAGIC)!=MagicNumber)
            continue;

        ENUM_POSITION_TYPE type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        double currentPrice=(type==POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol,SYMBOL_BID) : SymbolInfoDouble(_Symbol,SYMBOL_ASK);
        double profit=PositionGetDouble(POSITION_PROFIT);
        double sl=PositionGetDouble(POSITION_SL);
        double tp=PositionGetDouble(POSITION_TP);
        double openPrice=PositionGetDouble(POSITION_PRICE_OPEN);
        double volume = PositionGetDouble(POSITION_VOLUME);

        // Max profit per position
        if(MaxProfitPerPosition > 0 && profit >= MaxProfitPerPosition)
        {
            Print("Closing position ", ticket, " due to max profit reached: ", profit);
            ClosePosition(ticket);
            continue; // Move to the next position
        }

        // Lock profits once threshold reached
        if(!isProfitsLocked && profit>=LockInProfitThreshold)
        {
            double newSL=(type==POSITION_TYPE_BUY) ? currentPrice - StopLoss*_Point : currentPrice + StopLoss*_Point;
            SetStopLoss(ticket,newSL);
            isProfitsLocked=true;
        }

        // Proactive trailing stop
        if(TrailingStopPoints>0)
        {
            double newSL;
            if(type==POSITION_TYPE_BUY)
            {
                double trailSL=currentPrice - TrailingStopPoints*_Point;
                // Only move SL if it's a profitable move and greater than current SL
                if(trailSL > sl && trailSL > openPrice)
                {
                    // Ensure the move is at least TrailingStep
                    if(trailSL >= sl + TrailingStep*_Point)
                    {
                       newSL=trailSL;
                       SetStopLoss(ticket,newSL);
                    }
                }
            }
            else // Sell position
            {
                double trailSL=currentPrice + TrailingStopPoints*_Point;
                 // Only move SL if it's a profitable move and less than current SL
                if(trailSL < sl && trailSL < openPrice)
                {
                    // Ensure the move is at least TrailingStep
                     if(trailSL <= sl - TrailingStep*_Point)
                     {
                        newSL=trailSL;
                        SetStopLoss(ticket,newSL);
                     }
                }
            }
        }

        // Close trade when price reverses after reaching 50% towards TP
        if (ReverseClosePercentage > 0 && tp != 0)
        {
            double distanceToTP = (type == POSITION_TYPE_BUY) ? (tp - openPrice) : (openPrice - tp);
            double currentDistance = (type == POSITION_TYPE_BUY) ? (currentPrice - openPrice) : (openPrice - currentPrice);

            if (currentDistance >= distanceToTP * (ReverseClosePercentage / 100.0))
            {
                // Price has moved at least ReverseClosePercentage towards TP
                if (type == POSITION_TYPE_BUY)
                {
                    // Check if price is reversing (moving away from TP)
                    if (currentPrice < PositionGetDouble(POSITION_PRICE_CURRENT)) // Assuming POSITION_PRICE_CURRENT is from the previous tick
                    {
                        Print("Closing position ", ticket, " due to reversal after reaching ", ReverseClosePercentage, "% of TP");
                        ClosePosition(ticket);
                        continue; // Move to the next position
                    }
                }
                else // Sell position
                {
                    // Check if price is reversing (moving away from TP)
                    if (currentPrice > PositionGetDouble(POSITION_PRICE_CURRENT)) // Assuming POSITION_PRICE_CURRENT is from the previous tick
                    {
                        Print("Closing position ", ticket, " due to reversal after reaching ", ReverseClosePercentage, "% of TP");
                        ClosePosition(ticket);
                        continue; // Move to the next position
                    }
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Set stop loss for a position                                         |
//+------------------------------------------------------------------+
bool SetStopLoss(ulong ticket, double newSL)
{
    MqlTradeRequest request={};
    MqlTradeResult result={};
    request.action=TRADE_ACTION_SLTP;
    request.position=ticket;
    request.sl=newSL;
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
    return true;
}

//+------------------------------------------------------------------+
//| Close position helper                                              |
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
    if(!OrderSend(request,result))
        Print("Close position failed for ticket ", ticket, ". Error: ", GetLastError());
    else if(result.retcode!=TRADE_RETCODE_DONE)
        Print("Close position failed for ticket ", ticket, ". Return code: ", result.retcode);
}


//+------------------------------------------------------------------+
//| Utility functions                                                 |
//+------------------------------------------------------------------+
bool IsNewBar()
{
    static datetime lastBarTime=0;
    datetime currentBarTime=iTime(NULL,TimeFrame,0);
    if(lastBarTime!=currentBarTime)
    {
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
    CopyHigh(NULL,TimeFrame,0,SupportResistanceLookback,highs);
    CopyLow(NULL,TimeFrame,0,SupportResistanceLookback,lows);
    resistanceLevel=highs[ArrayMaximum(highs)];
    supportLevel=lows[ArrayMinimum(lows)];
    if(EnableLogging)
        Print("S/R updated: S=",supportLevel," R=",resistanceLevel);
}
bool CheckPinBar(bool isBuySignal)
{
    double open=iOpen(NULL,TimeFrame,0);
    double high=iHigh(NULL,TimeFrame,0);
    double low=iLow(NULL,TimeFrame,0);
    double close=iClose(NULL,TimeFrame,0);
    double bodySize=MathAbs(close-open);
    double upperWick=high-MathMax(open,close);
    double lowerWick=MathMin(open,close)-low;
    if(isBuySignal)
        return (close>open)&&(lowerWick>=bodySize*PinBarThreshold)&&(upperWick<bodySize*0.5);
    else
        return (close<open)&&(upperWick>=bodySize*PinBarThreshold)&&(lowerWick<bodySize*0.5);
}
bool CheckInsideBarBreakout(bool isBuySignal)
{
    double motherHigh=iHigh(NULL,TimeFrame,1);
    double motherLow=iLow(NULL,TimeFrame,1);
    bool isInside=true;
    for(int i=2;i<=InsideBarLookback;i++)
    {
        if(iHigh(NULL,TimeFrame,i)>motherHigh || iLow(NULL,TimeFrame,i)<motherLow)
        {
            isInside=false;
            break;
        }
    }
    if(!isInside) return false;
    return isBuySignal ? (iHigh(NULL,TimeFrame,0)>motherHigh) : (iLow(NULL,TimeFrame,0)<motherLow);
}
bool ConfirmBuySignal() { return iClose(NULL,TimeFrame,0)>iClose(NULL,TimeFrame,1); }
bool ConfirmSellSignal() { return iClose(NULL,TimeFrame,0)<iClose(NULL,TimeFrame,1); }
void DrawEntrySignal()
{
    static datetime lastSignalTime=0;
    if(TimeCurrent()==lastSignalTime) return;
    lastSignalTime=TimeCurrent();
    string arrowName="TradeSignal_"+TimeToString(TimeCurrent(),TIME_DATE|TIME_MINUTES);
    bool isBuy=CheckPinBar(true)||CheckInsideBarBreakout(true);
    int arrowCode=isBuy?241:242;
    color arrowColor=isBuy?BuySignalColor:SellSignalColor;
    if(ObjectFind(0,arrowName)==-1)
    {
        ObjectCreate(0,arrowName,OBJ_ARROW,0,TimeCurrent(),iClose(NULL,TimeFrame,0));
        ObjectSetInteger(0,arrowName,OBJPROP_COLOR,arrowColor);
        ObjectSetInteger(0,arrowName,OBJPROP_ARROWCODE,arrowCode);
        ObjectSetInteger(0,arrowName,OBJPROP_WIDTH,ArrowSize);
    }
}
int CountOpenPositionsInDirection(bool isBuySignal)
{
    int count=0;
    for(int i=PositionsTotal()-1;i>=0;i--)
    {
        ulong ticket=PositionGetTicket(i);
        if(PositionSelectByTicket(ticket) &&
           PositionGetString(POSITION_SYMBOL)==_Symbol &&
           PositionGetInteger(POSITION_MAGIC)==MagicNumber)
        {
            if((isBuySignal && PositionGetInteger(POSITION_TYPE)==ORDER_TYPE_BUY) ||
               (!isBuySignal && PositionGetInteger(POSITION_TYPE)==ORDER_TYPE_SELL))
                count++;
        }
    }
    return count;
}
double CalculateLotSize()
{
    if(UserLotSize>0) return UserLotSize;
    double accountEquity=AccountInfoDouble(ACCOUNT_EQUITY);
    double riskAmount=accountEquity*(RiskPercentage/100);
    double lotSize=riskAmount/(StopLoss*_Point);
    double minLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
    double maxLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
    double lotStep=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
    lotSize=MathRound(lotSize/lotStep)*lotStep;
    return MathMin(MathMax(lotSize,minLot),maxLot);
}
int CountOpenPositions()
{
    int count=0;
    for(int i=0;i<PositionsTotal();i++)
    {
        ulong ticket=PositionGetTicket(i);
        if(PositionSelectByTicket(ticket) &&
           PositionGetString(POSITION_SYMBOL)==_Symbol &&
           PositionGetInteger(POSITION_MAGIC)==MagicNumber)
            count++;
    }
    return count;
}
bool CheckTradingAllowed()
{
    double currentEquity=AccountInfoDouble(ACCOUNT_EQUITY);
    if(currentEquity<dailyEquityHigh*(1-MaxDrawdownPercentage/100))
    {
        Print("Max drawdown exceeded");
        return false;
    }
    return true;
}