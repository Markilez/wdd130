//+------------------------------------------------------------------+
//|                 Fully Fixed EA for Any Symbol                     |
//+------------------------------------------------------------------+
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

// Input parameters
input ENUM_TIMEFRAMES TimeFrame=PERIOD_H1;       // Chart timeframe
input double RiskRewardRatio=3.0;
input double StopLoss=300;                       // in points
input double RiskPercentage=1.0;                 // risk per trade in %
input double UserLotSize=0.20;                   // 0 means auto lot sizing
input int MagicNumber=78690;                     // magic number
input int MaxOpenPositions=5;                    

// Support/Resistance lookback
input int SupportResistanceLookback=50;

// Volume spike filter
input double VolumeSpikeMultiplier=1.5;

// CCI indicator parameters
input int CCIPeriod=14;                            // declare missing
input bool UseCCIFilter=true;
input double CCITrendThreshold=100;

// Pattern detection
input double PinBarThreshold=0.3;
input int InsideBarLookback=50;
input bool RequireCloseConfirmation=true;

// Trailing and lock-in
input double LockInProfitThreshold=20;             // in profit units
input double MaxProfitPerPosition=100;             // in profit units
input double ReverseClosePercentage=50;            // percentage

// Drawing signals
input bool ShowEntrySignals=true;

// Alerts
input bool EnableLogging=true;
input bool EnableAlerts=true;

// Trailing stop
input double TrailingStopPoints=50;                // in points
input double TrailingStep=10;                      // in points

// Drawdown control
input double MaxDrawdownPercentage=10;             // max drawdown in %

// Trade cooldown
input int TradeCooldownSeconds=60; // seconds between trades

// Colors for signals
color BuySignalColor=clrGreen;
color SellSignalColor=clrRed;
int ArrowSize=2;

// Declare indicator handle
// (already declared)

// Internal variables
int cciHandle=INVALID_HANDLE;
double supportLevel=0.0;
double resistanceLevel=0.0;
double dailyEquityHigh=0.0;
double dailyEquityLow=0.0;
datetime lastTradeTime=0;
bool isProfitsLocked=false;
double TakeProfitPoints=0.0;

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   cciHandle=iCCI(_Symbol,TimeFrame,CCIPeriod,PRICE_TYPICAL);
   if(cciHandle==INVALID_HANDLE)
   {
      Print("Failed to create CCI handle");
      return(INIT_FAILED);
   }

   TakeProfitPoints=StopLoss*RiskRewardRatio;

   // Initialize daily high/low for drawdown control
   dailyEquityHigh=AccountInfoDouble(ACCOUNT_EQUITY);
   dailyEquityLow=dailyEquityHigh;

   if(EnableLogging) Print("EA initialized");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Deinitialization                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(cciHandle!=INVALID_HANDLE)
      IndicatorRelease(cciHandle);
}

//+------------------------------------------------------------------+
//| Main tick                                                        |
//+------------------------------------------------------------------+
void OnTick()
{
   if(IsNewBar())
   {
      CalculateSupportResistance();
   }

   if(CheckTradeConditions() && CountOpenPositions()<MaxOpenPositions && CheckTradingAllowed())
   {
      if(ShowEntrySignals)
         DrawEntrySignal();

      OpenTrade();
   }

   ManageOpenTrades();
}

//+------------------------------------------------------------------+
//| Check if a new bar formed                                          |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   static datetime last_time=0;
   datetime current_time=iTime(_Symbol,TimeFrame,0);
   if(current_time!=last_time)
   {
      last_time=current_time;
      return(true);
   }
   return(false);
}

//+------------------------------------------------------------------+
//| Calculate support and resistance levels                            |
//+------------------------------------------------------------------+
void CalculateSupportResistance()
{
   double highs[], lows[];
   ArraySetAsSeries(highs,true);
   ArraySetAsSeries(lows,true);

   int copiedHigh=CopyHigh(_Symbol,TimeFrame,0,SupportResistanceLookback,highs);
   int copiedLow=CopyLow(_Symbol,TimeFrame,0,SupportResistanceLookback,lows);
   if(copiedHigh<=0 || copiedLow<=0)
   {
      if(EnableLogging) Print("CopyHigh or CopyLow failed");
      return;
   }
   int maxIdx=ArrayMaximum(highs,0,0);
   int minIdx=ArrayMinimum(lows,0,0);
   resistanceLevel=highs[maxIdx];
   supportLevel=lows[minIdx];

   if(EnableLogging)
      Print("Support=",supportLevel," Resistance=",resistanceLevel);
}

//+------------------------------------------------------------------+
//| Check trade conditions                                              |
//+------------------------------------------------------------------+
bool CheckTradeConditions()
{
   double closePrice=iClose(_Symbol,TimeFrame,0);
   bool buySignal=CheckPinBar(true) || CheckInsideBarBreakout(true);
   bool sellSignal=CheckPinBar(false) || CheckInsideBarBreakout(false);

   buySignal=buySignal && (closePrice > supportLevel);
   sellSignal=sellSignal && (closePrice < resistanceLevel);

   // Volume spike filter
   double currVol=iVolume(_Symbol,TimeFrame,0);
   double avgVol=iMA(_Symbol,TimeFrame,20,0,MODE_SMA,VOLUME_TICK);
   bool volumeFilter=currVol > avgVol * VolumeSpikeMultiplier;

   // CCI filter
   bool cciFilter=true;
   if(UseCCIFilter)
   {
      double cciBuffer[];
      int copied=CopyBuffer(cciHandle,0,0,2,cciBuffer);
      if(copied<2)
      {
         if(EnableLogging) Print("Failed to copy CCI buffer");
         return(false);
      }
      ArraySetAsSeries(cciBuffer,true);
      cciFilter= (buySignal && cciBuffer[0]>-CCITrendThreshold && cciBuffer[0]>cciBuffer[1]) ||
                 (sellSignal && cciBuffer[0]<CCITrendThreshold && cciBuffer[0]<cciBuffer[1]);
   }

   bool confirmation=true;
   if(RequireCloseConfirmation)
      confirmation=buySignal?ConfirmBuySignal():ConfirmSellSignal();

   return((buySignal && volumeFilter && confirmation && cciFilter) ||
          (sellSignal && volumeFilter && confirmation && cciFilter));
}

//+------------------------------------------------------------------+
//| Draw entry signals                                                |
//+------------------------------------------------------------------+
void DrawEntrySignal()
{
   static datetime lastSignalTime=0;
   if(TimeCurrent()==lastSignalTime)
      return;
   lastSignalTime=TimeCurrent();

   bool isBuy=CheckPinBar(true) || CheckInsideBarBreakout(true);
   string arrowName="TradeSignal_"+TimeToString(TimeCurrent(),TIME_DATE|TIME_MINUTES);
   int arrowCode=isBuy?233:234; // Up/Down arrows
   color arrowColor=isBuy?BuySignalColor:SellSignalColor;

   if(ObjectFind(0,arrowName)==-1)
   {
      ObjectCreate(0,arrowName,OBJ_ARROW,0,TimeCurrent(),iClose(_Symbol,TimeFrame,0));
      ObjectSetInteger(0,arrowName,OBJPROP_COLOR,arrowColor);
      ObjectSetInteger(0,arrowName,OBJPROP_ARROWCODE,arrowCode);
      ObjectSetInteger(0,arrowName,OBJPROP_WIDTH,ArrowSize);
   }
}

//+------------------------------------------------------------------+
//| Check for Pin Bar pattern                                              |
//+------------------------------------------------------------------+
bool CheckPinBar(bool isBuy)
{
   double open=iOpen(_Symbol,TimeFrame,0);
   double high=iHigh(_Symbol,TimeFrame,0);
   double low=iLow(_Symbol,TimeFrame,0);
   double close=iClose(_Symbol,TimeFrame,0);
   double bodySize=MathAbs(close-open);
   double upperWick=high-MathMax(open,close);
   double lowerWick=MathMin(open,close)-low;

   if(isBuy)
      return (close>open) && (lowerWick >= bodySize*PinBarThreshold) && (upperWick < bodySize*0.5);
   else
      return (close<open) && (upperWick >= bodySize*PinBarThreshold) && (lowerWick < bodySize*0.5);
}

//+------------------------------------------------------------------+
//| Check Inside Bar breakout pattern                                    |
//+------------------------------------------------------------------+
bool CheckInsideBarBreakout(bool isBuy)
{
   double motherHigh=iHigh(_Symbol,TimeFrame,1);
   double motherLow=iLow(_Symbol,TimeFrame,1);
   bool isInside=true;
   for(int i=2; i<=InsideBarLookback; i++)
   {
      if(iHigh(_Symbol,TimeFrame,i) > motherHigh || iLow(_Symbol,TimeFrame,i) < motherLow)
      {
         isInside=false;
         break;
      }
   }
   if(!isInside) return(false);
   return isBuy ? (iHigh(_Symbol,TimeFrame,0) > motherHigh) : (iLow(_Symbol,TimeFrame,0) < motherLow);
}

//+------------------------------------------------------------------+
//| Confirmation functions                                              |
//+------------------------------------------------------------------+
bool ConfirmBuySignal()
{
   return iClose(_Symbol,TimeFrame,0) > iClose(_Symbol,TimeFrame,1);
}
bool ConfirmSellSignal()
{
   return iClose(_Symbol,TimeFrame,0) < iClose(_Symbol,TimeFrame,1);
}

//+------------------------------------------------------------------+
//| Open trade function                                                 |
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
      Print("Order send failed, error ",GetLastError());
   else if(result.retcode!=TRADE_RETCODE_DONE)
      Print("Trade failed, retcode ",result.retcode);
   else
   {
      lastTradeTime=TimeCurrent();
      isProfitsLocked=false;
      if(EnableAlerts) Alert("Trade opened");
   }
}

//+------------------------------------------------------------------+
//| Manage open trades: SL, TP, trailing, max profit, reversal        |
//+------------------------------------------------------------------+
void ManageOpenTrades()
{
   for(int i=0; i<PositionsTotal(); i++)
   {
      ulong ticket=PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;

      if(PositionGetInteger(POSITION_MAGIC)!=MagicNumber)
         continue;

      string symbol=PositionGetString(POSITION_SYMBOL);
      double openPrice=PositionGetDouble(POSITION_PRICE_OPEN);
      double volume=PositionGetDouble(POSITION_VOLUME);
      int type=PositionGetInteger(POSITION_TYPE);
      double currentPrice=(type==POSITION_TYPE_BUY)?SymbolInfoDouble(symbol,SYMBOL_BID):SymbolInfoDouble(symbol,SYMBOL_ASK);
      double profit=PositionGetDouble(POSITION_PROFIT);
      double sl=PositionGetDouble(POSITION_SL);
      double tp=PositionGetDouble(POSITION_TP);

      // Max profit
      if(MaxProfitPerPosition>0 && profit>=MaxProfitPerPosition)
      {
         Print("Closing position ",ticket," max profit");
         ClosePosition(ticket);
         continue;
      }

      // Lock profits
      if(!isProfitsLocked && profit>=LockInProfitThreshold)
      {
         double newSL=(type==POSITION_TYPE_BUY)?currentPrice - StopLoss*_Point:currentPrice + StopLoss*_Point;
         SetStopLoss(ticket,newSL);
         isProfitsLocked=true;
      }

      // Trailing stop
      if(TrailingStopPoints>0)
      {
         if(type==POSITION_TYPE_BUY)
         {
            double trailSL=currentPrice - TrailingStopPoints*_Point;
            if(trailSL > sl && trailSL > openPrice)
               SetStopLoss(ticket,trailSL);
         }
         else
         {
            double trailSL=currentPrice + TrailingStopPoints*_Point;
            if(trailSL < sl && trailSL < openPrice)
               SetStopLoss(ticket,trailSL);
         }
      }

      // Reversal at 50%
      if(ReverseClosePercentage>0 && tp>0)
      {
         double totalDistance=(type==POSITION_TYPE_BUY)?(tp - openPrice):(openPrice - tp);
         double currentDistance=(type==POSITION_TYPE_BUY)?(currentPrice - openPrice):(openPrice - currentPrice);
         if(currentDistance >= totalDistance*ReverseClosePercentage/100.0)
         {
            if((type==POSITION_TYPE_BUY && currentPrice < PositionGetDouble(POSITION_PRICE_CURRENT)) ||
               (type==POSITION_TYPE_SELL && currentPrice > PositionGetDouble(POSITION_PRICE_CURRENT)))
            {
               Print("Reversing position ",ticket);
               ClosePosition(ticket);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Set stop loss for position                                              |
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
      Print("Failed to set SL for ",ticket," error ",GetLastError());
      return(false);
   }
   if(result.retcode!=TRADE_RETCODE_DONE)
   {
      Print("Set SL retcode: ",result.retcode);
      return(false);
   }
   return(true);
}

//+------------------------------------------------------------------+
//| Close position                                              |
//+------------------------------------------------------------------+
void ClosePosition(ulong ticket)
{
   MqlTradeRequest request={};
   MqlTradeResult result={};
   request.action=TRADE_ACTION_DEAL;
   request.symbol=_Symbol;
   request.volume=PositionGetDouble(POSITION_VOLUME);
   int type=PositionGetInteger(POSITION_TYPE);
   request.type=(type==POSITION_TYPE_BUY)?ORDER_TYPE_SELL:ORDER_TYPE_BUY;
   request.position=ticket;

   if(!OrderSend(request,result))
      Print("Close position failed ",ticket," error ",GetLastError());
   else if(result.retcode!=TRADE_RETCODE_DONE)
      Print("Close retcode: ",result.retcode);
}

//+------------------------------------------------------------------+
//| Count total open positions                                         |
//+------------------------------------------------------------------+
int CountOpenPositions()
{
   int count=0;
   for(int i=0; i<PositionsTotal(); i++)
   {
      ulong ticket=PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;
      if(PositionGetInteger(POSITION_MAGIC)!=MagicNumber)
         continue;
      count++;
   }
   return(count);
}

//+------------------------------------------------------------------+
//| Count open positions in a specific direction                         |
//+------------------------------------------------------------------+
int CountOpenPositionsInDirection(bool isBuy)
{
   int count=0;
   for(int i=0; i<PositionsTotal(); i++)
   {
      ulong ticket=PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;
      if(PositionGetInteger(POSITION_MAGIC)!=MagicNumber)
         continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol)
         continue;
      int type=PositionGetInteger(POSITION_TYPE);
      if(isBuy && type==POSITION_TYPE_BUY)
         count++;
      if(!isBuy && type==POSITION_TYPE_SELL)
         count++;
   }
   return(count);
}

//+------------------------------------------------------------------+
//| Calculate lot size based on risk                                      |
//+------------------------------------------------------------------+
double CalculateLotSize()
{
   if(UserLotSize>0)
      return(UserLotSize);
   double accountEquity=AccountInfoDouble(ACCOUNT_EQUITY);
   double riskAmount=accountEquity*(RiskPercentage/100);
   double lotSize=riskAmount/(StopLoss*_Point);
   double minLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double lotStep=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   lotSize=MathRound(lotSize/lotStep)*lotStep;
   return(MathMin(MathMax(lotSize,minLot),maxLot));
}

//+------------------------------------------------------------------+
//| Check if trading is allowed (drawdown)                          |
//+------------------------------------------------------------------+
bool CheckTradingAllowed()
{
   double currentEquity=AccountInfoDouble(ACCOUNT_EQUITY);
   if(currentEquity<dailyEquityHigh*(1-MaxDrawdownPercentage/100))
   {
      if(EnableLogging) Print("Max drawdown exceeded");
      return(false);
   }
   return(true);
}