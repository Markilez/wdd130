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
input int MagicNumber = 8866;
input int MaxOpenPositions = 5;
input double LockInProfitThreshold = 2;           
input double MaxDrawdownPercentage = 10;           
input bool EnableMaxDrawdownAlerts = true;

// User-defined lot size option
input group "==== Lot Size Management ====";
input bool UseUserDefinedLotSize = false; // True to use user-defined lot size
input double UserDefinedLotSize = 0.1; // Default lot size if using user-defined option

input group "==== Trading Parameters ====";
input ENUM_TIMEFRAMES TimeFrame = PERIOD_H1;
input ENUM_TIMEFRAMES TrendTimeFrame = PERIOD_H4; // Multi-timeframe trend confirmation
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
input double EngulfingThreshold = 0.5;
input double HammerThreshold = 0.3;
input double MinimumBodySize = 0.0001;           

input group "==== Trailing Stop ====";
input bool UseTrailingStop = true;
input double TrailingStopATRMultiplier = 0.70;      
input double TrailingStepPoints = 10;

// Global variables
int cciHandle = INVALID_HANDLE;
int atrHandle = INVALID_HANDLE;
double supportLevel = 0.0, resistanceLevel = 0.0;
double dailyEquityHigh = 0.0;
datetime lastTradeTime = 0;
bool isProfitsLocked = false;
double currentATR = 0.0;
double lastPositionSize = 0.0; // Track the last position size
bool lastTradeWasLoss = false; // Track if the last trade was a loss

// Visual settings
color BuySignalColor = clrGreen; // Color for buy signals
color SellSignalColor = clrRed;   // Color for sell signals
int ArrowSize = 2;                // Size of the arrows for signals
bool EnableLogging = true;         // Enable logging of events
bool EnableAlerts = true;          // Enable alerts
double ReverseClosePercentage = 50; // Percentage for partial close on reversal

// EMA Handles
int ema200Handle = INVALID_HANDLE;
int ema800Handle = INVALID_HANDLE;
int ema1200Handle = INVALID_HANDLE;

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
void OpenTrade(bool isBuy, double lotSize);
double CalculateLotSize(double atrStop);
void ManageOpenTrades();
bool IsNewsImpact();
bool IsMarketFavorable();
double GetCurrentMA();
double GetEMA(int period);
bool IsVolumeValid();
bool CheckBreakout();

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   cciHandle = iCCI(_Symbol, TimeFrame, CCIPeriod, PRICE_TYPICAL);
   atrHandle = iATR(_Symbol, TimeFrame, ATRPeriod);
   ema200Handle = iMA(_Symbol, TrendTimeFrame, 200, 0, MODE_EMA, PRICE_CLOSE);
   ema800Handle = iMA(_Symbol, TrendTimeFrame, 800, 0, MODE_EMA, PRICE_CLOSE);
   ema1200Handle = iMA(_Symbol, TrendTimeFrame, 1200, 0, MODE_EMA, PRICE_CLOSE);
   
   if (cciHandle == INVALID_HANDLE || atrHandle == INVALID_HANDLE || 
       ema200Handle == INVALID_HANDLE || ema800Handle == INVALID_HANDLE || ema1200Handle == INVALID_HANDLE)
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
   if (ema200Handle != INVALID_HANDLE) IndicatorRelease(ema200Handle);
   if (ema800Handle != INVALID_HANDLE) IndicatorRelease(ema800Handle);
   if (ema1200Handle != INVALID_HANDLE) IndicatorRelease(ema1200Handle);
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
      if (EnableLogging) Print("Trade conditions met, attempting to open trades.");
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
   if (EnableLogging) Print("S/R levels updated: Support = ", supportLevel, ", Resistance = ", resistanceLevel);
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
   bool volumeFilter = IsVolumeValid();
   
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
   
   // Breakout confirmation
   bool breakoutConfirmation = CheckBreakout();

   // Confirmation for both
   bool confirmation = true;
   if (RequireCloseConfirmation)
   {
      if (buySignal) confirmation = ConfirmBuySignal();
      if (sellSignal) confirmation = ConfirmSellSignal();
   }
   
   return ((buySignal && volumeFilter && cciFilter && breakoutConfirmation && confirmation) ||
           (sellSignal && volumeFilter && cciFilter && breakoutConfirmation && confirmation));
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

   // Determine position size
   double positionSize;
   if (UseUserDefinedLotSize)
   {
      positionSize = UserDefinedLotSize; // Use user-defined lot size
   }
   else
   {
      // Calculate lot size based on last trade outcome
      positionSize = lastTradeWasLoss ? lastPositionSize * 2 : CalculateLotSize(currentATR * StopLossATRMultiplier);
   }

   // Ensure no simultaneous trades
   if (totalPositions == 0) 
   {
      if (buySignal && CheckTradingAllowed())
      {
         OpenTrade(true, positionSize);
      }
      if (sellSignal && CheckTradingAllowed())
      {
         OpenTrade(false, positionSize);
      }
   }
   else if (totalPositions < MaxOpenPositions)
   {
      // Open additional positions for strong signals
      if (buySignal && CheckTradingAllowed())
      {
         OpenTrade(true, positionSize);
      }
      if (sellSignal && CheckTradingAllowed())
      {
         OpenTrade(false, positionSize);
      }
   }
}

//+------------------------------------------------------------------+
//| Open individual trade (buy or sell)                              |
//+------------------------------------------------------------------+
void OpenTrade(bool isBuy, double lotSize)
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
   request.volume = lotSize;
   request.price = price;
   request.sl = sl;
   request.tp = tp;
   request.type = type;
   request.type_filling = ORDER_FILLING_FOK;
   request.magic = MagicNumber;
   request.comment = "Weichai";

   if (!OrderSend(request, result))
   {
      Print("OrderSend failed: ", GetLastError());
      lastTradeWasLoss = true; // Mark as loss if order fails
   }
   else if (result.retcode != TRADE_RETCODE_DONE)
   {
      Print("Trade failed: ", result.retcode);
      lastTradeWasLoss = true; // Mark as loss if trade fails
   }
   else
   {
      lastTradeTime = TimeCurrent();
      lastPositionSize = lotSize; // Track the last position size
      isProfitsLocked = false;
      lastTradeWasLoss = false; // Reset loss flag on successful trade
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
         double trailLevel = (type == POSITION_TYPE_BUY) ? 
                             (currentPrice - currentATR * TrailingStopATRMultiplier) : 
                             (currentPrice + currentATR * TrailingStopATRMultiplier);
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
   double currentPrice = iClose(_Symbol, TimeFrame, 0);
   double ema200 = GetEMA(200);
   double ema800 = GetEMA(800);
   double ema1200 = GetEMA(1200);

   // Favorable conditions: price above all EMAs for buy, below all EMAs for sell
   if (currentPrice > ema200 && currentPrice > ema800 && currentPrice > ema1200)
   {
      return true; // Favorable for buying
   }
   else if (currentPrice < ema200 && currentPrice < ema800 && currentPrice < ema1200)
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
//| Get EMA value for a given period                                  |
//+------------------------------------------------------------------+
double GetEMA(int period)
{
   double emaBuffer[];
   if (CopyBuffer(iMA(_Symbol, TimeFrame, period, 0, MODE_EMA, PRICE_CLOSE), 0, 0, 1, emaBuffer) > 0)
   {
      return emaBuffer[0];
   }
   return 0.0; // Default if failed to get EMA
}

//+------------------------------------------------------------------+
//| Validate volume for trades                                        |
//+------------------------------------------------------------------+
bool IsVolumeValid()
{
   double currVol = iVolume(_Symbol, TimeFrame, 0);
   double avgVol = iMA(_Symbol, TimeFrame, 20, 0, MODE_SMA, VOLUME_TICK);
   return currVol > (avgVol * VolumeSpikeMultiplier);
}

//+------------------------------------------------------------------+
//| Check for breakout confirmation at support/resistance levels     |
//+------------------------------------------------------------------+
bool CheckBreakout()
{
   double closePrice = iClose(_Symbol, TimeFrame, 0);
   if (closePrice > resistanceLevel)
   {
      return true; // Breakout above resistance
   }
   else if (closePrice < supportLevel)
   {
      return true; // Breakout below support
   }
   return false; // No breakout
}

//+------------------------------------------------------------------+
//| Entry point                                                      |
//+------------------------------------------------------------------+
void OnTimer()
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
