//+------------------------------------------------------------------+
//|                 Enhanced EA with ATR and Confirmation            |
//+------------------------------------------------------------------+
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

// Input parameters
input group "==== Risk Management ====";
input double RiskRewardRatio = 2.5;
input double StopLossATRMultiplier = 0.8;          
input double RiskPercentage = 1.0;                 
input double UserLotSize = 0.20;                  
input int MagicNumber = 8866;
input int MaxOpenPositions = 5;
input double LockInProfitThreshold = 2;           
input double MaxProfitPerPosition = 100;           
input double ReverseClosePercentage = 50;          
input double MaxDrawdownPercentage = 10;           
input bool EnableMaxDrawdownAlerts = true;

input group "==== Trading Parameters ====";
input ENUM_TIMEFRAMES TimeFrame = PERIOD_H1;
input int SupportResistanceLookback = 50;
input int TradeCooldownSeconds = 60;               
input bool RequireCloseConfirmation = true;
input int ATRPeriod = 14;                          
input double VolumeSpikeMultiplier = 1.5;
input bool AvoidNews = false;                      
input double NewsImpactThreshold = 2.0;           
input int MAPeriod = 50; // Moving Average Period
input ENUM_MA_METHOD MAMethod = MODE_SMA; // Moving Average Method

input group "==== Indicator Settings ====";
input int CCIPeriod = 14;
input bool UseCCIFilter = true;
input double CCITrendThreshold = 100;
input double PinBarThreshold = 0.3;
input int InsideBarLookback = 50;
input double MinimumBodySize = 0.0001;           

input group "==== Pattern Settings ====";
input double EngulfingThreshold = 0.5;
input double HammerThreshold = 0.3;
input double ShootingStarThreshold = 0.3;

input group "==== Trailing Stop ====";
input bool UseTrailingStop = true;
input double TrailingStopATRMultiplier = 0.70;      
input double TrailingStepPoints = 10;

input group "==== Visual Settings ====";
input bool ShowEntrySignals = true;
input bool EnableLogging = true;
input bool EnableAlerts = true;
color BuySignalColor = clrGreen;
color SellSignalColor = clrRed;
int ArrowSize = 2;

// Global variables
int cciHandle = INVALID_HANDLE;
int atrHandle = INVALID_HANDLE;
double supportLevel = 0.0, resistanceLevel = 0.0;
double dailyEquityHigh = 0.0;
datetime lastTradeTime = 0;
bool isProfitsLocked = false;
double currentATR = 0.0;

//+------------------------------------------------------------------+
//| Function declarations                                            |
//+------------------------------------------------------------------+
void UpdateATR();
bool IsNewBar();
void CalculateSupportResistance();
bool CheckTradeConditions();
int CountOpenPositions();
bool CheckTradingAllowed();
void DrawEntrySignal();
void OpenTrades();
bool SetStopLoss(ulong ticket, double newSL);
void ClosePosition(ulong ticket);
bool CheckPinBar(bool isBuy);
bool CheckEngulfing(bool isBuy);
bool CheckHammer(bool isBuy);
bool ConfirmBuySignal();
bool ConfirmSellSignal();
void OpenTrade(bool isBuy);
double CalculateLotSize(double atrStop);
void ManageOpenTrades();
bool IsNewsImpact();
bool IsMarketFavorable();
double GetCurrentMA();

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   cciHandle = iCCI(_Symbol, TimeFrame, CCIPeriod, PRICE_TYPICAL);
   atrHandle = iATR(_Symbol, TimeFrame, ATRPeriod);
   
   if (cciHandle == INVALID_HANDLE || atrHandle == INVALID_HANDLE)
   {
      Print("Failed to create indicator handles");
      return (INIT_FAILED);
   }
   dailyEquityHigh = AccountInfoDouble(ACCOUNT_EQUITY);
   if (EnableLogging) Print("EA initialized");
   return (INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Cleanup                                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if (cciHandle != INVALID_HANDLE) IndicatorRelease(cciHandle);
   if (atrHandle != INVALID_HANDLE) IndicatorRelease(atrHandle);
}

//+------------------------------------------------------------------+
//| Main tick function                                               |
//+------------------------------------------------------------------+
void OnTick()
{
   UpdateATR();
   if (IsNewBar()) CalculateSupportResistance();

   if (IsMarketFavorable() && 
       CheckTradeConditions() && 
       CountOpenPositions() < MaxOpenPositions && 
       CheckTradingAllowed())
   {
      if (ShowEntrySignals) DrawEntrySignal();
      OpenTrades();
   }

   ManageOpenTrades();
}

//+------------------------------------------------------------------+
//| Update ATR value                                                 |
//+------------------------------------------------------------------+
void UpdateATR()
{
   double buffer[];
   if (CopyBuffer(atrHandle, 0, 0, 1, buffer) > 0)
      currentATR = buffer[0];
}

//+------------------------------------------------------------------+
//| Check if new bar formed                                          |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   static datetime lastBarTime = 0;
   datetime currentBarTime = iTime(_Symbol, TimeFrame, 0);
   if (currentBarTime != lastBarTime)
   {
      lastBarTime = currentBarTime;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Calculate support/resistance levels                               |
//+------------------------------------------------------------------+
void CalculateSupportResistance()
{
   double highs[], lows[];
   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(lows, true);
   if (CopyHigh(_Symbol, TimeFrame, 0, SupportResistanceLookback, highs) <= 0 ||
       CopyLow(_Symbol, TimeFrame, 0, SupportResistanceLookback, lows) <= 0)
   {
      if (EnableLogging) Print("Failed to copy price data");
      return;
   }
   resistanceLevel = highs[ArrayMaximum(highs)];
   supportLevel = lows[ArrayMinimum(lows)];
   if (EnableLogging) Print("S/R levels updated");
}

//+------------------------------------------------------------------+
//| Check all trade conditions                                       |
//+------------------------------------------------------------------+
bool CheckTradeConditions()
{
   double closePrice = iClose(_Symbol, TimeFrame, 0);
   
   bool buySignal = CheckPinBar(true) || CheckEngulfing(true) || CheckHammer(true);
   bool sellSignal = CheckPinBar(false) || CheckEngulfing(false) || CheckHammer(false);
   
   // Price relative to S/R
   buySignal = buySignal && (closePrice > supportLevel);
   sellSignal = sellSignal && (closePrice < resistanceLevel);
   
   // Volume filter
   double currVol = iVolume(_Symbol, TimeFrame, 0);
   double avgVol = iMA(_Symbol, TimeFrame, 20, 0, MODE_SMA, VOLUME_TICK);
   bool volumeFilter = currVol > (avgVol * VolumeSpikeMultiplier);
   
   // CCI filter
   bool cciFilter = true;
   if (UseCCIFilter)
   {
      double cciBuffer[];
      if (CopyBuffer(cciHandle, 0, 0, 2, cciBuffer) < 2)
      {
         if (EnableLogging) Print("Failed to copy CCI data");
         return false;
      }
      ArraySetAsSeries(cciBuffer, true);
      cciFilter = (buySignal && cciBuffer[0] > -CCITrendThreshold && cciBuffer[0] > cciBuffer[1]) ||
                  (sellSignal && cciBuffer[0] < CCITrendThreshold && cciBuffer[0] < cciBuffer[1]);
   }
   
   // Confirmation for both
   bool confirmation = true;
   if (RequireCloseConfirmation)
   {
      if (buySignal) confirmation = ConfirmBuySignal();
      if (sellSignal) confirmation = ConfirmSellSignal();
   }
   
   return ((buySignal && volumeFilter && cciFilter && confirmation) ||
           (sellSignal && volumeFilter && cciFilter && confirmation));
}

//+------------------------------------------------------------------+
//| Draw signals on chart                                            |
//+------------------------------------------------------------------+
void DrawEntrySignal()
{
   static datetime lastSignalTime = 0;
   if (TimeCurrent() == lastSignalTime) return;
   lastSignalTime = TimeCurrent();

   bool isBuy = CheckPinBar(true);
   string arrowName = "Signal_" + TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS);
   
   if (ObjectFind(0, arrowName) == -1)
   {
      ObjectCreate(0, arrowName, OBJ_ARROW, 0, TimeCurrent(), iClose(_Symbol, TimeFrame, 0));
      ObjectSetInteger(0, arrowName, OBJPROP_COLOR, isBuy ? BuySignalColor : SellSignalColor);
      ObjectSetInteger(0, arrowName, OBJPROP_ARROWCODE, isBuy ? 233 : 234);
      ObjectSetInteger(0, arrowName, OBJPROP_WIDTH, ArrowSize);
   }
}

//+------------------------------------------------------------------+
//| Check for Pin Bar pattern                                        |
//+------------------------------------------------------------------+
bool CheckPinBar(bool isBuy)
{
   double open = iOpen(_Symbol, TimeFrame, 0);
   double high = iHigh(_Symbol, TimeFrame, 0);
   double low = iLow(_Symbol, TimeFrame, 0);
   double close = iClose(_Symbol, TimeFrame, 0);
   
   double bodySize = MathAbs(close - open);
   double upperWick = high - MathMax(open, close);
   double lowerWick = MathMin(open, close) - low;

   if (bodySize < MinimumBodySize) return false;

   if (isBuy)
      return (close > open) && (lowerWick >= bodySize * PinBarThreshold) && (upperWick <= bodySize * 0.5);
   else
      return (close < open) && (upperWick >= bodySize * PinBarThreshold) && (lowerWick <= bodySize * 0.5);
}

//+------------------------------------------------------------------+
//| Check for Engulfing pattern                                      |
//+------------------------------------------------------------------+
bool CheckEngulfing(bool isBuy)
{
   double open1 = iOpen(_Symbol, TimeFrame, 1);
   double close1 = iClose(_Symbol, TimeFrame, 1);
   double open0 = iOpen(_Symbol, TimeFrame, 0);
   double close0 = iClose(_Symbol, TimeFrame, 0);

   double bodySize = MathAbs(close0 - open0);
   if (bodySize < MinimumBodySize) return false;

   if (isBuy)
      return (close0 > open0) && (close1 < open1) && (close0 > open1) && (open0 < close1);
   else
      return (close0 < open0) && (close1 > open1) && (close0 < open1) && (open0 > close1);
}

//+------------------------------------------------------------------+
//| Check for Hammer pattern                                         |
//+------------------------------------------------------------------+
bool CheckHammer(bool isBuy)
{
   double open = iOpen(_Symbol, TimeFrame, 0);
   double close = iClose(_Symbol, TimeFrame, 0);
   double high = iHigh(_Symbol, TimeFrame, 0);
   double low = iLow(_Symbol, TimeFrame, 0);
   
   double bodySize = MathAbs(close - open);
   if (bodySize < MinimumBodySize) return false;

   double lowerWick = open > close ? open - low : close - low;
   double upperWick = high - MathMax(open, close);

   if (isBuy)
      return (lowerWick >= bodySize * HammerThreshold) && (upperWick <= bodySize * 0.5);
   else
      return (upperWick >= bodySize * HammerThreshold) && (lowerWick <= bodySize * 0.5);
}

//+------------------------------------------------------------------+
//| Confirm buy signal                                               |
//+------------------------------------------------------------------+
bool ConfirmBuySignal()
{
   return iClose(_Symbol, TimeFrame, 0) > iClose(_Symbol, TimeFrame, 1);
}

//+------------------------------------------------------------------+
//| Confirm sell signal                                              |
//+------------------------------------------------------------------+
bool ConfirmSellSignal()
{
   return iClose(_Symbol, TimeFrame, 0) < iClose(_Symbol, TimeFrame, 1);
}

//+------------------------------------------------------------------+
//| Open trades (both buy and sell if signals)                      |
//+------------------------------------------------------------------+
void OpenTrades()
{
   int totalPositions = CountOpenPositions();

   bool buySignal = CheckPinBar(true) || CheckEngulfing(true) || CheckHammer(true);
   bool sellSignal = CheckPinBar(false) || CheckEngulfing(false) || CheckHammer(false);

   // Ensure no simultaneous trades
   if (totalPositions == 0) 
   {
      if (buySignal && CheckTradingAllowed())
      {
         OpenTrade(true);
      }
      if (sellSignal && CheckTradingAllowed())
      {
         OpenTrade(false);
      }
   }
}

//+------------------------------------------------------------------+
//| Open individual trade (buy or sell)                              |
//+------------------------------------------------------------------+
void OpenTrade(bool isBuy)
{
   double price, sl, tp;
   ENUM_ORDER_TYPE type;

   double atrStop = currentATR * StopLossATRMultiplier;
   double atrTP = atrStop * RiskRewardRatio;

   if (isBuy)
   {
      price = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_ASK), _Digits);
      sl = NormalizeDouble(price - atrStop, _Digits);
      tp = NormalizeDouble(price + atrTP, _Digits);
      type = ORDER_TYPE_BUY;
   }
   else
   {
      price = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_BID), _Digits);
      sl = NormalizeDouble(price + atrStop, _Digits);
      tp = NormalizeDouble(price - atrTP, _Digits);
      type = ORDER_TYPE_SELL;
   }

   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = CalculateLotSize(atrStop);
   request.price = price;
   request.sl = sl;
   request.tp = tp;
   request.type = type;
   request.type_filling = ORDER_FILLING_FOK;
   request.magic = MagicNumber;
   request.comment = "Money Maker";

   if (!OrderSend(request, result))
      Print("OrderSend failed: ", GetLastError());
   else if (result.retcode != TRADE_RETCODE_DONE)
      Print("Trade failed: ", result.retcode);
   else
   {
      lastTradeTime = TimeCurrent();
      isProfitsLocked = false;
      if (EnableAlerts) Alert("Trade opened at ", DoubleToString(price, _Digits));
   }
}

//+------------------------------------------------------------------+
//| Manage open trades: trailing, partial close, lock profits        |
//+------------------------------------------------------------------+
void ManageOpenTrades()
{
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (!PositionSelectByTicket(ticket)) continue;
      if (PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;

      string symbol = PositionGetString(POSITION_SYMBOL);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentProfit = PositionGetDouble(POSITION_PROFIT);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);
      int type = (int)PositionGetInteger(POSITION_TYPE);
      double currentPrice = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(symbol, SYMBOL_BID) : SymbolInfoDouble(symbol, SYMBOL_ASK);

      // Lock profits
      if (!isProfitsLocked && currentProfit >= LockInProfitThreshold)
      {
         double newSL = (type == POSITION_TYPE_BUY) ? (currentPrice - currentATR * StopLossATRMultiplier) : (currentPrice + currentATR * StopLossATRMultiplier);
         SetStopLoss(ticket, newSL);
         isProfitsLocked = true;
      }

      // Trailing stop
      if (UseTrailingStop)
      {
         double trailLevel = (type == POSITION_TYPE_BUY) ? (currentPrice - currentATR * TrailingStopATRMultiplier) : (currentPrice + currentATR * TrailingStopATRMultiplier);
         if ((type == POSITION_TYPE_BUY && trailLevel > currentSL && trailLevel > openPrice) ||
             (type == POSITION_TYPE_SELL && trailLevel < currentSL && trailLevel < openPrice))
         {
            SetStopLoss(ticket, trailLevel);
         }
      }

      // Partial close on reversal
      if (ReverseClosePercentage > 0 && currentTP > 0)
      {
         double totalDistance = (type == POSITION_TYPE_BUY) ? (currentTP - openPrice) : (openPrice - currentTP);
         double currentDistance = (type == POSITION_TYPE_BUY) ? (currentPrice - openPrice) : (openPrice - currentPrice);
         if (currentDistance >= totalDistance * (ReverseClosePercentage / 100))
         {
            if ((type == POSITION_TYPE_BUY && currentPrice < PositionGetDouble(POSITION_PRICE_CURRENT)) ||
                (type == POSITION_TYPE_SELL && currentPrice > PositionGetDouble(POSITION_PRICE_CURRENT)))
            {
               ClosePosition(ticket);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Count total open positions                                       |
//+------------------------------------------------------------------+
int CountOpenPositions()
{
   int total = 0;
   for (int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if (!PositionSelectByTicket(ticket)) continue;
      if (PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      total++;
   }
   return total;
}

//+------------------------------------------------------------------+
//| Calculate position size based on ATR risk                        |
//+------------------------------------------------------------------+
double CalculateLotSize(double atrStop)
{
   if (UserLotSize > 0) return UserLotSize;
   double riskAmount = AccountInfoDouble(ACCOUNT_EQUITY) * (RiskPercentage / 100);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double lotSize = riskAmount / (atrStop / _Point * tickValue);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lotSize = MathRound(lotSize / lotStep) * lotStep;
   return MathMin(MathMax(lotSize, minLot), maxLot);
}

//+------------------------------------------------------------------+
//| Check if trading is allowed based on drawdown                    |
//+------------------------------------------------------------------+
bool CheckTradingAllowed()
{
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   if (currentEquity < dailyEquityHigh * (1 - MaxDrawdownPercentage / 100))
   {
      if (EnableLogging) Print("Max drawdown reached");
      if (EnableMaxDrawdownAlerts) Alert("Max drawdown reached. Current equity: ", DoubleToString(currentEquity, 2));
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Set stop loss for position                                       |
//+------------------------------------------------------------------+
bool SetStopLoss(ulong ticket, double newSL)
{
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   request.action = TRADE_ACTION_SLTP;
   request.position = ticket;
   request.sl = newSL;
   if (!OrderSend(request, result))
   {
      Print("Failed to modify SL: ", GetLastError());
      return false;
   }
   return (result.retcode == TRADE_RETCODE_DONE);
}

//+------------------------------------------------------------------+
//| Close position                                                   |
//+------------------------------------------------------------------+
void ClosePosition(ulong ticket)
{
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   request.action = TRADE_ACTION_DEAL;
   request.position = ticket;
   request.volume = PositionGetDouble(POSITION_VOLUME);
   request.symbol = PositionGetString(POSITION_SYMBOL);
   request.type = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;

   if (!OrderSend(request, result))
      Print("Failed to close position: ", GetLastError());
}

//+------------------------------------------------------------------+
//| Placeholder for news impact check                                |
//+------------------------------------------------------------------+
bool IsNewsImpact()
{
   // Placeholder logic for checking news events
   return false; // Always return false for now
}

//+------------------------------------------------------------------+
//| Check if the market conditions are favorable                     |
//+------------------------------------------------------------------+
bool IsMarketFavorable()
{
   double currentMA = GetCurrentMA();
   double currentPrice = iClose(_Symbol, TimeFrame, 0);

   // Favorable conditions: price above MA for buy, below MA for sell
   if (currentPrice > currentMA)
   {
      return true; // Favorable for buying
   }
   else if (currentPrice < currentMA)
   {
      return true; // Favorable for selling
   }
   return false; // Not favorable
}

//+------------------------------------------------------------------+
//| Get current Moving Average value                                  |
//+------------------------------------------------------------------+
double GetCurrentMA()
{
   double maBuffer[];
   if (CopyBuffer(iMA(_Symbol, TimeFrame, MAPeriod, 0, MAMethod, PRICE_CLOSE), 0, 0, 1, maBuffer) > 0)
   {
      return maBuffer[0];
   }
   return 0.0; // Default if failed to get MA
}

//+------------------------------------------------------------------+
//| Main function to execute trades                                   |
//+------------------------------------------------------------------+
void CheckTradeExecution()
{
   if (AvoidNews && IsNewsImpact())
   {
      if (EnableLogging) Print("Avoiding trade due to news");
      return;
   }

   // Allow both buy and sell trades based on signals
   OpenTrades(); 
}

//+------------------------------------------------------------------+
//| Entry point                                                      |
//+------------------------------------------------------------------+
void OnTimer()
{
   CheckTradeExecution();
}

