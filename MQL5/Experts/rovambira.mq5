//+------------------------------------------------------------------+
//|                 Enhanced EA with ATR and Confirmation            |
//+------------------------------------------------------------------+
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

// Input parameters
input group "==== Risk Management ====";
input double RiskRewardRatio=2.5;
input double StopLossATRMultiplier=0.8;          // ATR-based stop loss multiplier
input double RiskPercentage=1.0;                 // Risk per trade in %
input double UserLotSize=0.20;                  // Fixed lot size (0 for auto)
input int MagicNumber=488466;
input int MaxOpenPositions=5;
input double LockInProfitThreshold=2;           // $ profit to lock in
input double MaxProfitPerPosition=100;           // Max profit per position
input double ReverseClosePercentage=50;          // % of TP to reverse
input double MaxDrawdownPercentage=10;           // Max account drawdown %

input group "==== Trading Parameters ====";
input ENUM_TIMEFRAMES TimeFrame=PERIOD_H1;
input int SupportResistanceLookback=50;
input int TradeCooldownSeconds=60;               // Cooldown period in seconds
input bool RequireCloseConfirmation=true;
input int ATRPeriod=14;                          // ATR period
input double VolumeSpikeMultiplier=1.5;
input bool AvoidNews=false;                      // Avoid trading during news
input double NewsImpactThreshold=2.0;           // Minimum news impact to avoid trading

input group "==== Indicator Settings ====";
input int CCIPeriod=14;
input bool UseCCIFilter=true;
input double CCITrendThreshold=100;
input double PinBarThreshold=0.3;
input int InsideBarLookback=50;
input double MinimumBodySize=0.0001;            // Minimum body size for clearer signals

// Additional Pattern Settings
input double EngulfingThreshold=0.5;             // Engulfing pattern threshold
input double HammerThreshold=0.3;                // Hammer pattern threshold
input double ShootingStarThreshold=0.3;          // Shooting star threshold

input group "==== Trailing Stop ====";
input bool UseTrailingStop=true;
input double TrailingStopATRMultiplier=0.70;      // ATR-based trailing
input double TrailingStepPoints=10;

input group "==== Visual Settings ====";
input bool ShowEntrySignals=true;
input bool EnableLogging=true;
input bool EnableAlerts=true;
color BuySignalColor=clrGreen;
color SellSignalColor=clrRed;
int ArrowSize=2;

// Global variables
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
   cciHandle = iCCI(_Symbol, TimeFrame, CCIPeriod, PRICE_TYPICAL);
   atrHandle = iATR(_Symbol, TimeFrame, ATRPeriod);
   
   if (cciHandle == INVALID_HANDLE || atrHandle == INVALID_HANDLE)
   {
      Print("Failed to create indicator handles");
      return(INIT_FAILED);
   }

   // Initialize daily equity tracking
   dailyEquityHigh = AccountInfoDouble(ACCOUNT_EQUITY);
   dailyEquityLow = dailyEquityHigh;

   if (EnableLogging) Print("EA initialized successfully");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if (cciHandle != INVALID_HANDLE) IndicatorRelease(cciHandle);
   if (atrHandle != INVALID_HANDLE) IndicatorRelease(atrHandle);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Update ATR value
   UpdateATR();
   
   if (IsNewBar())
   {
      CalculateSupportResistance();
   }

   if (CheckTradeConditions() && 
       CountOpenPositions() < MaxOpenPositions && 
       CheckTradingAllowed())
   {
      if (ShowEntrySignals) DrawEntrySignal();
      OpenTrade();
   }

   ManageOpenTrades();
}

//+------------------------------------------------------------------+
//| Update ATR value                                                 |
//+------------------------------------------------------------------+
void UpdateATR()
{
   double atrBuffer[];
   if (CopyBuffer(atrHandle, 0, 0, 1, atrBuffer) > 0)
   {
      currentATR = atrBuffer[0];
   }
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
//| Calculate support/resistance levels                              |
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
   
   if (EnableLogging) Print("S/R Updated - Support: ", supportLevel, " Resistance: ", resistanceLevel);
}

//+------------------------------------------------------------------+
//| Check all trade conditions                                       |
//+------------------------------------------------------------------+
bool CheckTradeConditions()
{
   // Get current price and indicators
   double closePrice = iClose(_Symbol, TimeFrame, 0);
   
   // Pattern detection
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
   
   // Close confirmation
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
//| Draw entry signals on chart                                      |
//+------------------------------------------------------------------+
void DrawEntrySignal()
{
   static datetime lastSignalTime = 0;
   if (TimeCurrent() == lastSignalTime) return;
   lastSignalTime = TimeCurrent();

   bool isBuy = CheckPinBar(true) || CheckInsideBarBreakout(true);
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
   
   double bodySize = close - open;
   double upperWick = high - MathMax(open, close);
   double lowerWick = MathMin(open, close) - low;
   
   if (isBuy)
      return (close > open) && (lowerWick >= bodySize * PinBarThreshold) && (upperWick <= bodySize * 0.5) && (bodySize > MinimumBodySize);
   else
      return (close < open) && (upperWick >= bodySize * PinBarThreshold) && (lowerWick <= bodySize * 0.5) && (bodySize > MinimumBodySize);
}

//+------------------------------------------------------------------+
//| Check Inside Bar breakout                                        |
//+------------------------------------------------------------------+
bool CheckInsideBarBreakout(bool isBuy)
{
   double motherHigh = iHigh(_Symbol, TimeFrame, 1);
   double motherLow = iLow(_Symbol, TimeFrame, 1);
   
   // Check if previous bars are inside the mother bar
   for (int i = 2; i <= InsideBarLookback; i++)
   {
      if (iHigh(_Symbol, TimeFrame, i) > motherHigh || iLow(_Symbol, TimeFrame, i) < motherLow)
         return false;
   }
   
   // Check breakout direction
   return isBuy ? (iHigh(_Symbol, TimeFrame, 0) > motherHigh) : (iLow(_Symbol, TimeFrame, 0) < motherLow);
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
   double prevBodySize = MathAbs(close1 - open1);
   
   if (isBuy)
      return (close0 > open0) && (close1 < open1) && (close0 > open1) && (open0 < close1); // Bullish engulfing
   else
      return (close0 < open0) && (close1 > open1) && (close0 < open1) && (open0 > close1); // Bearish engulfing
}

//+------------------------------------------------------------------+
//| Check for Hammer pattern                                           |
//+------------------------------------------------------------------+
bool CheckHammer(bool isBuy)
{
   double open = iOpen(_Symbol, TimeFrame, 0);
   double close = iClose(_Symbol, TimeFrame, 0);
   double high = iHigh(_Symbol, TimeFrame, 0);
   double low = iLow(_Symbol, TimeFrame, 0);
   
   double bodySize = MathAbs(close - open);
   double lowerWick = open > close ? open - low : close - low;
   double upperWick = high - MathMax(open, close);

   if (isBuy)
      return (lowerWick >= bodySize * HammerThreshold) && (upperWick <= bodySize * 0.5);
   else
      return (upperWick >= bodySize * HammerThreshold) && (lowerWick <= bodySize * 0.5);
}

//+------------------------------------------------------------------+
//| Confirmation functions                                             |
//+------------------------------------------------------------------+
bool ConfirmBuySignal()
{
   return iClose(_Symbol, TimeFrame, 0) > iClose(_Symbol, TimeFrame, 1);
}

bool ConfirmSellSignal()
{
   return iClose(_Symbol, TimeFrame, 0) < iClose(_Symbol, TimeFrame, 1);
}

//+------------------------------------------------------------------+
//| Open trade with proper risk management                            |
//+------------------------------------------------------------------+
void OpenTrade()
{
   if (TimeCurrent() - lastTradeTime < TradeCooldownSeconds) return;

   bool isBuy = CheckPinBar(true) || CheckInsideBarBreakout(true) || CheckEngulfing(true) || CheckHammer(true);
   bool isSell = CheckPinBar(false) || CheckInsideBarBreakout(false) || CheckEngulfing(false) || CheckHammer(false);

   // Check if there are existing positions in the same direction
   if (CountOpenPositionsInDirection(isBuy) > 0) return;
   if (CountOpenPositionsInDirection(isSell) > 0) return;

   double price, sl, tp;
   ENUM_ORDER_TYPE orderType;
   double atrStop = currentATR * StopLossATRMultiplier;
   double atrTP = atrStop * RiskRewardRatio;

   if (isBuy)
   {
      price = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_ASK), _Digits);
      sl = NormalizeDouble(price - atrStop, _Digits);
      tp = NormalizeDouble(price + atrTP, _Digits);
      orderType = ORDER_TYPE_BUY;
   }
   else if (isSell)
   {
      price = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_BID), _Digits);
      sl = NormalizeDouble(price + atrStop, _Digits);
      tp = NormalizeDouble(price - atrTP, _Digits);
      orderType = ORDER_TYPE_SELL;
   }
   else
   {
      return; // No valid trade signal
   }

   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = CalculateLotSize(atrStop);
   request.price = price;
   request.sl = sl;
   request.tp = tp;
   request.type = orderType;
   request.type_filling = ORDER_FILLING_FOK;
   request.magic = MagicNumber;
   request.comment = "Riot";

   if (!OrderSend(request, result))
      Print("OrderSend failed: ", GetLastError());
   else if (result.retcode != TRADE_RETCODE_DONE)
      Print("Trade failed: ", result.retcode);
   else
   {
      lastTradeTime = TimeCurrent();
      isProfitsLocked = false;
      if (EnableAlerts) Alert("Trade opened at ", price);
   }
}

//+------------------------------------------------------------------+
//| Manage open positions with trailing stops etc.                    |
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

      // Check max profit per position
      if (MaxProfitPerPosition > 0 && currentProfit >= MaxProfitPerPosition)
      {
         ClosePosition(ticket);
         continue;
      }

      // Lock in profits
      if (!isProfitsLocked && currentProfit >= LockInProfitThreshold)
      {
         double newSL = (type == POSITION_TYPE_BUY) ? currentPrice - currentATR * StopLossATRMultiplier : currentPrice + currentATR * StopLossATRMultiplier;
         SetStopLoss(ticket, newSL);
         isProfitsLocked = true;
      }

      // Trailing stop
      if (UseTrailingStop)
      {
         double trailLevel = (type == POSITION_TYPE_BUY) ? currentPrice - currentATR * TrailingStopATRMultiplier : currentPrice + currentATR * TrailingStopATRMultiplier;
         
         if ((type == POSITION_TYPE_BUY && trailLevel > currentSL && trailLevel > openPrice) ||
             (type == POSITION_TYPE_SELL && trailLevel < currentSL && trailLevel < openPrice))
         {
            SetStopLoss(ticket, trailLevel);
         }
      }

      // Partial close at reversal point
      if (ReverseClosePercentage > 0 && currentTP != 0)
      {
         double totalDistance = (type == POSITION_TYPE_BUY) ? (currentTP - openPrice) : (openPrice - currentTP);
         double currentDistance = (type == POSITION_TYPE_BUY) ? (currentPrice - openPrice) : (openPrice - currentPrice);
         
         if (currentDistance >= totalDistance * (ReverseClosePercentage / 100.0))
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
//| Position counting functions                                      |
//+------------------------------------------------------------------+
int CountOpenPositions()
{
   int count = 0;
   for (int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if (!PositionSelectByTicket(ticket)) continue;
      if (PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      count++;
   }
   return count;
}

int CountOpenPositionsInDirection(bool isBuy)
{
      int count = 0;
   for (int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if (!PositionSelectByTicket(ticket)) continue;
      if (PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      if (PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      
      int type = (int)PositionGetInteger(POSITION_TYPE);
      if (isBuy && type == POSITION_TYPE_BUY) count++;
      if (!isBuy && type == POSITION_TYPE_SELL) count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| Calculate position size with ATR-based risk                      |
//+------------------------------------------------------------------+
double CalculateLotSize(double atrStop)
{
   if (UserLotSize > 0) return UserLotSize;
   
   double riskAmount = AccountInfoDouble(ACCOUNT_EQUITY) * (RiskPercentage / 100);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double lotSize = riskAmount / (atrStop / _Point * tickValue);
   
   // Normalize to broker requirements
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   lotSize = MathRound(lotSize / lotStep) * lotStep;
   return MathMin(MathMax(lotSize, minLot), maxLot);
}

//+------------------------------------------------------------------+
//| Check if trading is allowed (drawdown control)                   |
//+------------------------------------------------------------------+
bool CheckTradingAllowed()
{
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   if (currentEquity < dailyEquityHigh * (1 - MaxDrawdownPercentage / 100))
   {
      if (EnableLogging) Print("Max drawdown reached - trading suspended");
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Helper function to modify stop loss                              |
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
   return result.retcode == TRADE_RETCODE_DONE;
}

//+------------------------------------------------------------------+
//| Close specified position                                         |
//+------------------------------------------------------------------+
void ClosePosition(ulong ticket)
{
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   request.action = TRADE_ACTION_DEAL;
   request.position = ticket;
   request.volume = PositionGetDouble(POSITION_VOLUME);
   request.symbol = PositionGetString(POSITION_SYMBOL);
   request.type = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 
                  ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   
   if (!OrderSend(request, result))
      Print("Close position failed: ", GetLastError());
}

//+------------------------------------------------------------------+
//| Check for news impact (placeholder)                                |
//+------------------------------------------------------------------+
bool IsNewsImpact()
{
   // Implement news checking logic based on economic calendar API or custom logic
   // For demonstration, return false (no news impact)
   return false;
}

//+------------------------------------------------------------------+
//| Main function to check all conditions and execute trades         |
//+------------------------------------------------------------------+
void CheckTradeExecution()
{
   if (AvoidNews && IsNewsImpact())
   {
      if (EnableLogging) Print("Trade execution avoided due to news impact.");
      return;
   }

   // Call OnTick to process trading logic
   OnTick();
}

//+------------------------------------------------------------------+
//| Entry point                                                      |
//+------------------------------------------------------------------
void OnTimer()
{
   CheckTradeExecution();
}

