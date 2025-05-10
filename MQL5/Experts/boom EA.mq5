//+------------------------------------------------------------------+
//| Short-Only ATR EA with Confirmation                              |
//+------------------------------------------------------------------+
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

// Input parameters
input group "==== Risk Management ====";
input double RiskRewardRatio=6.0;
input double StopLossATRMultiplier=1.5;          
input double RiskPercentage=80.0;                
input double UserLotSize=0.20;                  
input int MagicNumber=11144;
input int MaxOpenPositions=5;
input double LockInProfitThreshold=2;            
input double MaxProfitPerPosition=100;           
input double ReverseClosePercentage=50;          
input double MaxDrawdownPercentage=10;           

input group "==== Trading Parameters ====";
input ENUM_TIMEFRAMES TimeFrame=PERIOD_H1;
input int SupportResistanceLookback=50;
input int TradeCooldownSeconds=60;
input bool RequireCloseConfirmation=true;
input int ATRPeriod=14;                          
input double VolumeSpikeMultiplier=1.5;

input group "==== Indicator Settings ====";
input int CCIPeriod=14;
input bool UseCCIFilter=true;
input double CCITrendThreshold=100;
input double PinBarThreshold=0.3;
input int InsideBarLookback=50;

input group "==== Trailing Stop ====";
input bool UseTrailingStop=true;
input double TrailingStopATRMultiplier=0.70;    
input double TrailingStepPoints=10;

input group "==== Visual Settings ====";
input bool ShowEntrySignals=true;
input bool EnableLogging=true;
input bool EnableAlerts=true;
color SellSignalColor=clrRed;
int ArrowSize=2;

// Global variables (declare only once)
int cciHandle=INVALID_HANDLE;
int atrHandle=INVALID_HANDLE;
double supportLevel=0.0, resistanceLevel=0.0;
double dailyEquityHigh=0.0, dailyEquityLow=0.0;
datetime lastTradeTime=0;
bool isProfitsLocked=false;
double currentATR=0.0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize indicators
   cciHandle=iCCI(_Symbol,TimeFrame,CCIPeriod,PRICE_TYPICAL);
   atrHandle=iATR(_Symbol,TimeFrame,ATRPeriod);
   
   if(cciHandle==INVALID_HANDLE || atrHandle==INVALID_HANDLE)
   {
      Print("Failed to create indicator handles");
      return(INIT_FAILED);
   }

   // Initialize daily equity tracking
   dailyEquityHigh=AccountInfoDouble(ACCOUNT_EQUITY);
   dailyEquityLow=dailyEquityHigh;

   if(EnableLogging) Print("EA initialized successfully");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Deinitialize indicators                                            |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(cciHandle!=INVALID_HANDLE) IndicatorRelease(cciHandle);
   if(atrHandle!=INVALID_HANDLE) IndicatorRelease(atrHandle);
}

//+------------------------------------------------------------------+
//| Main tick function                                                 |
//+------------------------------------------------------------------+
void OnTick()
{
   UpdateATR();

   if(IsNewBar())
      CalculateSupportResistance();

   if(CheckSellConditions() && 
      CountOpenPositions()<MaxOpenPositions && 
      CheckTradingAllowed())
   {
      if(ShowEntrySignals) DrawEntrySignal();
      OpenSellTrade(); // only open sell trades
   }

   ManageOpenTrades();
}

//+------------------------------------------------------------------+
//| Update ATR value                                                   |
//+------------------------------------------------------------------+
void UpdateATR()
{
   double atrBuffer[];
   if(CopyBuffer(atrHandle,0,0,1,atrBuffer)>0)
      currentATR=atrBuffer[0];
}

//+------------------------------------------------------------------+
//| Check if new bar formed                                              |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   static datetime lastBarTime=0;
   datetime currentBarTime=iTime(_Symbol,TimeFrame,0);
   if(currentBarTime!=lastBarTime)
   {
      lastBarTime=currentBarTime;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Calculate support/resistance levels                                  |
//+------------------------------------------------------------------+
void CalculateSupportResistance()
{
   double highs[], lows[];
   ArraySetAsSeries(highs,true);
   ArraySetAsSeries(lows,true);

   if(CopyHigh(_Symbol,TimeFrame,0,SupportResistanceLookback,highs)<=0 || 
      CopyLow(_Symbol,TimeFrame,0,SupportResistanceLookback,lows)<=0)
   {
      if(EnableLogging) Print("Failed to copy price data");
      return;
   }

   resistanceLevel=highs[ArrayMaximum(highs)];
   supportLevel=lows[ArrayMinimum(lows)];

   if(EnableLogging) Print("S/R Updated - Support: ",supportLevel," Resistance: ",resistanceLevel);
}

//+------------------------------------------------------------------+
//| Check sell conditions only (for short trades)                          |
//+------------------------------------------------------------------+
bool CheckSellConditions()
{
   double closePrice=iClose(_Symbol,TimeFrame,0);
   
   // Pattern detection (sell only)
   bool sellSignal=CheckPinBar(false) || CheckInsideBarBreakout(false);
   
   // Price must be below resistance
   sellSignal=sellSignal && (closePrice<resistanceLevel);
   
   // Volume filter
   double currVol=iVolume(_Symbol,TimeFrame,0);
   double avgVol=iMA(_Symbol,TimeFrame,20,0,MODE_SMA,VOLUME_TICK);
   bool volumeFilter=currVol>(avgVol*VolumeSpikeMultiplier);
   
   // CCI filter
   bool cciFilter=true;
   if(UseCCIFilter)
   {
      double cciBuffer[];
      if(CopyBuffer(cciHandle,0,0,2,cciBuffer)<2)
      {
         if(EnableLogging) Print("Failed to copy CCI data");
         return false;
      }
      ArraySetAsSeries(cciBuffer,true);
      cciFilter=(cciBuffer[0]<-CCITrendThreshold) && (cciBuffer[0]<cciBuffer[1]);
   }
   
   // Close confirmation
   bool confirmation=true;
   if(RequireCloseConfirmation)
   {
      confirmation=ConfirmSellSignal();
   }

   return (sellSignal && volumeFilter && cciFilter && confirmation);
}

//+------------------------------------------------------------------+
//| Draw entry signals on chart                                      |
//+------------------------------------------------------------------+
void DrawEntrySignal()
{
   static datetime lastSignalTime=0;
   if(TimeCurrent()==lastSignalTime) return;
   lastSignalTime=TimeCurrent();

   string arrowName="Signal_"+TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS);
   
   if(ObjectFind(0,arrowName)==-1)
   {
      ObjectCreate(0,arrowName,OBJ_ARROW,0,TimeCurrent(),iClose(_Symbol,TimeFrame,0));
      ObjectSetInteger(0,arrowName,OBJPROP_COLOR,SellSignalColor);
      ObjectSetInteger(0,arrowName,OBJPROP_ARROWCODE,234);
      ObjectSetInteger(0,arrowName,OBJPROP_WIDTH,ArrowSize);
   }
}

//+------------------------------------------------------------------+
//| Check for Sell Pin Bar pattern                                       |
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
   
   return (close<open) && (upperWick>=bodySize*PinBarThreshold) && (lowerWick<bodySize*0.5);
}

//+------------------------------------------------------------------+
//| Check Inside Bar breakout (sell only)                                |
//+------------------------------------------------------------------+
bool CheckInsideBarBreakout(bool isBuy)
{
   double motherHigh=iHigh(_Symbol,TimeFrame,1);
   double motherLow=iLow(_Symbol,TimeFrame,1);
   
   for(int i=2;i<=InsideBarLookback;i++)
   {
      if(iHigh(_Symbol,TimeFrame,i)>motherHigh || iLow(_Symbol,TimeFrame,i)<motherLow)
         return false;
   }
   
   return (iLow(_Symbol,TimeFrame,0)<motherLow);
}

//+------------------------------------------------------------------+
//| Confirm sell signal                                                   |
//+------------------------------------------------------------------+
bool ConfirmSellSignal()
{
   return iClose(_Symbol,TimeFrame,0)<iClose(_Symbol,TimeFrame,1);
}

//+------------------------------------------------------------------+
//| Open sell trade with proper risk management                      |
//+------------------------------------------------------------------+
void OpenSellTrade()
{
   if(TimeCurrent()-lastTradeTime<TradeCooldownSeconds) return;

   double price=NormalizeDouble(SymbolInfoDouble(_Symbol,SYMBOL_BID),_Digits);
   double atrStop=currentATR*StopLossATRMultiplier;
   double atrTP=atrStop*RiskRewardRatio;
   double sl=NormalizeDouble(price+atrStop,_Digits);
   double tp=NormalizeDouble(price-atrTP,_Digits);

   MqlTradeRequest request={};
   MqlTradeResult result={};
   request.action=TRADE_ACTION_DEAL;
   request.symbol=_Symbol;
   request.volume=CalculateLotSize(atrStop);
   request.price=price;
   request.sl=sl;
   request.tp=tp;
   request.type=ORDER_TYPE_SELL;
   request.type_filling=ORDER_FILLING_FOK;
   request.magic=MagicNumber;
   request.comment="Short-Only ATR EA";

   if(!OrderSend(request,result))
      Print("OrderSend failed: ",GetLastError());
   else if(result.retcode!=TRADE_RETCODE_DONE)
      Print("Trade failed: ",result.retcode);
   else
   {
      lastTradeTime=TimeCurrent();
      isProfitsLocked=false;
      if(EnableAlerts) Alert("Sell order opened at ",price);
   }
}

//+------------------------------------------------------------------+
//| Manage open positions (sell only)                                   |
//+------------------------------------------------------------------+
void ManageOpenTrades()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;
      if(PositionGetInteger(POSITION_TYPE)!=POSITION_TYPE_SELL) continue;

      double openPrice=PositionGetDouble(POSITION_PRICE_OPEN);
      double currentProfit=PositionGetDouble(POSITION_PROFIT);
      double currentSL=PositionGetDouble(POSITION_SL);
      double currentTP=PositionGetDouble(POSITION_TP);
      double currentPrice=SymbolInfoDouble(_Symbol,SYMBOL_BID);

      // Check max profit per position
      if(MaxProfitPerPosition>0 && currentProfit>=MaxProfitPerPosition)
      {
         ClosePosition(ticket);
         continue;
      }

      // Lock in profits
      if(!isProfitsLocked && currentProfit>=LockInProfitThreshold)
      {
         double newSL=currentPrice+currentATR*StopLossATRMultiplier;
         SetStopLoss(ticket,newSL);
         isProfitsLocked=true;
      }

      // Trailing stop
      if(UseTrailingStop)
      {
         double trailLevel=currentPrice+currentATR*TrailingStopATRMultiplier;
         if(trailLevel<currentSL && trailLevel<openPrice)
         {
            SetStopLoss(ticket,trailLevel);
         }
      }

      // Partial close at reversal point
      if(ReverseClosePercentage>0 && currentTP!=0)
      {
         double totalDistance=openPrice-currentTP;
         double currentDistance=openPrice-currentPrice;
         
         if(currentDistance>=totalDistance*(ReverseClosePercentage/100.0))
         {
            if(currentPrice>PositionGetDouble(POSITION_PRICE_CURRENT))
            {
               ClosePosition(ticket);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Position count functions                                              |
//+------------------------------------------------------------------+
int CountOpenPositions()
{
   int count=0;
   for(int i=0;i<PositionsTotal();i++)
   {
      ulong ticket=PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;
      count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| Calculate lot size based on ATR risk                                |
//+------------------------------------------------------------------+
double CalculateLotSize(double atrStop)
{
   if(UserLotSize>0) return UserLotSize;

   double riskAmount=AccountInfoDouble(ACCOUNT_EQUITY)*(RiskPercentage/100);
   double tickValue=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double lotSize=riskAmount/(atrStop/_Point*tickValue);

   double minLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double lotStep=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);

   lotSize=MathRound(lotSize/lotStep)*lotStep;
   return MathMin(MathMax(lotSize,minLot),maxLot);
}

//+------------------------------------------------------------------+
//| Check trading allowed based on drawdown                            |
//+------------------------------------------------------------------+
bool CheckTradingAllowed()
{
   double currentEquity=AccountInfoDouble(ACCOUNT_EQUITY);
   if(currentEquity<dailyEquityHigh*(1-MaxDrawdownPercentage/100))
   {
      if(EnableLogging) Print("Max drawdown reached - trading suspended");
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Helper to set stop loss                                               |
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
      Print("Failed to modify SL: ",GetLastError());
      return false;
   }
   return result.retcode==TRADE_RETCODE_DONE;
}

//+------------------------------------------------------------------+
//| Close position                                                      |
//+------------------------------------------------------------------+
void ClosePosition(ulong ticket)
{
   MqlTradeRequest request={};
   MqlTradeResult result={};
   request.action=TRADE_ACTION_DEAL;
   request.position=ticket;
   request.volume=PositionGetDouble(POSITION_VOLUME);
   request.symbol=PositionGetString(POSITION_SYMBOL);
   request.type=ORDER_TYPE_BUY; // close a sell order with a buy

   if(!OrderSend(request,result))
      Print("Close position failed: ",GetLastError());
}