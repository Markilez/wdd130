//+------------------------------------------------------------------+
//|                                                      AutoScalperEA.mq5 |
//|                        Copyright 2025, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property strict
#property version   "2.00"
#property description "Automated Scalping EA with EMA/RSI Strategy"
#property description "Includes advanced risk management and auto-trading"

// Trading Parameters
input group "Trading Parameters"
input double TakeProfit = 1000;              // Take Profit in points
input double StopLoss = 1000;                // Stop Loss in points
input int EmaPeriod1 = 50;                   // Fast EMA Period (9-25 for scalping)
input int EmaPeriod2 = 200;                  // Slow EMA Period (50-200 for trend)
input int RsiPeriod = 14;                    // RSI Period (7-14 for scalping)
input double RsiOverbought = 70.0;           // RSI Overbought level (70-80)
input double RsiOversold = 30.0;             // RSI Oversold level (20-30)
input int MagicNumber = 1921;               // Unique Magic Number
input int MaxOpenPositions = 3;              // Maximum simultaneous trades (1-5)
input int TradeCooldownSeconds = 60;         // Seconds between trades (30-120)
input bool EnableVirtualStops = false;        // Use virtual stop loss
input string TradeComment = "AutoScalperV2"; // Trade comment

// Money Management
input group "Money Management"
input double RiskPercentage = 1.0;           // Risk % per trade (0.5-2%)
input double FixedLotSize = 0.001;            // Fixed lot size (0=auto)
input double MaxDailyLossPercent = 5.0;     // Max daily loss % (0=off)
input double MaxDrawdownPercent = 15.0;     // Max account drawdown % (0=off)

// Advanced Features
input group "Advanced Features"
input bool EnableTrailingStop = false;        // Enable trailing stops
input double TrailingStopDistance = 500;    // Points from price (100-1000)
input double TrailingStep = 50;             // Step size (10-100)
input bool EnableBreakEven = true;          // Move SL to breakeven
input double BreakEvenAt = 300;             // Points profit to activate (100-500)
input bool UseTimeFilter = false;            // Filter by trading hours
input string TradingStartTime = "00:00";    // Start time (HH:MM)
input string TradingEndTime = "23:59";      // End time (HH:MM)

// Global Variables
int emaHandle1, emaHandle2, rsiHandle;
double emaBuffer1[], emaBuffer2[], rsiBuffer[];
datetime lastTradeTime = 0;
double dailyEquityHigh, dailyEquityLow;
bool tradingAllowed = true;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize indicators
   emaHandle1 = iMA(_Symbol, _Period, EmaPeriod1, 0, MODE_EMA, PRICE_CLOSE);
   emaHandle2 = iMA(_Symbol, _Period, EmaPeriod2, 0, MODE_EMA, PRICE_CLOSE);
   rsiHandle = iRSI(_Symbol, _Period, RsiPeriod, PRICE_CLOSE);
   
   if(emaHandle1==INVALID_HANDLE || emaHandle2==INVALID_HANDLE || rsiHandle==INVALID_HANDLE)
   {
      Alert("Error creating indicators - ", GetLastError());
      return INIT_FAILED;
   }
   
   ArraySetAsSeries(emaBuffer1, true);
   ArraySetAsSeries(emaBuffer2, true);
   ArraySetAsSeries(rsiBuffer, true);
   
   // Initialize daily tracking
   dailyEquityHigh = AccountInfoDouble(ACCOUNT_EQUITY);
   dailyEquityLow = dailyEquityHigh;
   
   Print("AutoScalper EA initialized successfully");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Release indicators
   if(emaHandle1 != INVALID_HANDLE) IndicatorRelease(emaHandle1);
   if(emaHandle2 != INVALID_HANDLE) IndicatorRelease(emaHandle2);
   if(rsiHandle != INVALID_HANDLE) IndicatorRelease(rsiHandle);
   
   Print("EA deinitialized with reason: ", reason);
}

//+------------------------------------------------------------------+
//| Parse time string in HH:MM format                                |
//+------------------------------------------------------------------+
bool ParseTimeString(const string timeStr, int &hour, int &minute)
{
   string parts[];
   if(StringSplit(timeStr, ':', parts) != 2) return false;
   
   hour = (int)StringToInteger(parts[0]);
   minute = (int)StringToInteger(parts[1]);
   
   return (hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59);
}

//+------------------------------------------------------------------+
//| Check if current time is within trading hours                   |
//+------------------------------------------------------------------+
bool IsTradingTime()
{
   int startHour = 0, startMinute = 0;
   int endHour = 0, endMinute = 0;
   
   if(!ParseTimeString(TradingStartTime, startHour, startMinute) || 
      !ParseTimeString(TradingEndTime, endHour, endMinute))
   {
      Print("Invalid time format in TradingStartTime/TradingEndTime");
      return false;
   }
   
   MqlDateTime currentTime;
   TimeToStruct(TimeCurrent(), currentTime);
   
   int currentMinutes = currentTime.hour * 60 + currentTime.min;
   int startMinutes = startHour * 60 + startMinute;
   int endMinutes = endHour * 60 + endMinute;
   
   return (currentMinutes >= startMinutes && currentMinutes <= endMinutes);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Update equity tracking
   UpdateEquityTracking();
   
   // Check global trading conditions
   if(!CheckGlobalTradingConditions())
   {
      if(tradingAllowed) Print("Trading halted by risk management");
      tradingAllowed = false;
      return;
   }
   tradingAllowed = true;
   
   // Check trading hours
   if(UseTimeFilter && !IsTradingTime()) return;
   
   // Refresh indicators
   if(!RefreshIndicators()) return;
   
   // Manage open positions
   ManagePositions();
   
   // Check for new trade opportunities
   if(CountOpenPositions() < MaxOpenPositions && 
      (TimeCurrent() - lastTradeTime) >= TradeCooldownSeconds)
   {
      CheckForTradeSignal();
   }
}

//+------------------------------------------------------------------+
//| Update equity tracking                                           |
//+------------------------------------------------------------------+
void UpdateEquityTracking()
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   MqlDateTime today;
   TimeToStruct(TimeCurrent(), today);
   
   static int lastDay = -1;
   if(today.day != lastDay)
   {
      dailyEquityHigh = equity;
      dailyEquityLow = equity;
      lastDay = today.day;
   }
   else
   {
      dailyEquityHigh = MathMax(dailyEquityHigh, equity);
      dailyEquityLow = MathMin(dailyEquityLow, equity);
   }
}

//+------------------------------------------------------------------+
//| Check global trading conditions                                  |
//+------------------------------------------------------------------+
bool CheckGlobalTradingConditions()
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   
   // Daily loss check
   if(MaxDailyLossPercent > 0 && equity < dailyEquityHigh * (1 - MaxDailyLossPercent/100))
   {
      Print("Daily loss limit reached: ", MaxDailyLossPercent,"%");
      return false;
   }
   
   // Account drawdown check
   if(MaxDrawdownPercent > 0 && equity < balance * (1 - MaxDrawdownPercent/100))
   {
      Print("Max drawdown reached: ", MaxDrawdownPercent,"%");
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Refresh indicator buffers                                        |
//+------------------------------------------------------------------+
bool RefreshIndicators()
{
   if(CopyBuffer(emaHandle1, 0, 0, 3, emaBuffer1) < 3 ||
      CopyBuffer(emaHandle2, 0, 0, 3, emaBuffer2) < 3 ||
      CopyBuffer(rsiHandle, 0, 0, 3, rsiBuffer) < 3)
   {
      Print("Error copying indicator buffers: ", GetLastError());
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Check for trade signals                                          |
//+------------------------------------------------------------------+
void CheckForTradeSignal()
{
   // Get current price and indicators
   double currentPrice = iClose(_Symbol, _Period, 0);
   double emaFast = emaBuffer1[0];
   double emaSlow = emaBuffer2[0];
   double rsi = rsiBuffer[0];
   double emaFastPrev = emaBuffer1[1];
   double emaSlowPrev = emaBuffer2[1];
   
   // Bullish signal: Price crosses above both EMAs and RSI not overbought
   bool buySignal = currentPrice > emaFast && 
                    currentPrice > emaSlow && 
                    emaFast > emaSlow &&
                    rsi < RsiOverbought &&
                    CheckBullishCandle();
   
   // Bearish signal: Price crosses below both EMAs and RSI not oversold
   bool sellSignal = currentPrice < emaFast && 
                     currentPrice < emaSlow && 
                     emaFast < emaSlow &&
                     rsi > RsiOversold &&
                     CheckBearishCandle();
   
   if(buySignal) OpenPosition(ORDER_TYPE_BUY);
   else if(sellSignal) OpenPosition(ORDER_TYPE_SELL);
}

//+------------------------------------------------------------------+
//| Check for bullish candle pattern                                 |
//+------------------------------------------------------------------+
bool CheckBullishCandle()
{
   double open = iOpen(_Symbol, _Period, 0);
   double close = iClose(_Symbol, _Period, 0);
   double prevOpen = iOpen(_Symbol, _Period, 1);
   double prevClose = iClose(_Symbol, _Period, 1);
   
   // Basic engulfing pattern
   return (prevClose < prevOpen && close > open && close > prevOpen && open < prevClose);
}

//+------------------------------------------------------------------+
//| Check for bearish candle pattern                                 |
//+------------------------------------------------------------------+
bool CheckBearishCandle()
{
   double open = iOpen(_Symbol, _Period, 0);
   double close = iClose(_Symbol, _Period, 0);
   double prevOpen = iOpen(_Symbol, _Period, 1);
   double prevClose = iClose(_Symbol, _Period, 1);
   
   // Basic engulfing pattern
   return (prevClose > prevOpen && close < open && close < prevOpen && open > prevClose);
}

//+------------------------------------------------------------------+
//| Open new position                                                |
//+------------------------------------------------------------------+
void OpenPosition(ENUM_ORDER_TYPE orderType)
{
   // Calculate entry price
   double price = (orderType == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) 
                                                : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   // Calculate stop loss and take profit
   double sl = (orderType == ORDER_TYPE_BUY) ? price - StopLoss * _Point 
                                             : price + StopLoss * _Point;
   double tp = (orderType == ORDER_TYPE_BUY) ? price + TakeProfit * _Point 
                                             : price - TakeProfit * _Point;
   
   // Calculate lot size
   double lotSize = (FixedLotSize > 0) ? FixedLotSize : CalculateAutoLotSize(sl, price, orderType);
   lotSize = NormalizeLotSize(lotSize);
   if(lotSize <= 0) return;
   
   // Prepare trade request
   MqlTradeRequest request = {};
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = lotSize;
   request.type = orderType;
   request.price = price;
   request.sl = (EnableVirtualStops) ? 0 : sl; // Use 0 for virtual stops
   request.tp = tp;
   request.deviation = 10;
   request.magic = MagicNumber;
   request.comment = TradeComment + (EnableVirtualStops ? (":" + DoubleToString(sl, _Digits)) : "");
   request.type_filling = ORDER_FILLING_FOK;
   
   // Send trade request
   MqlTradeResult result = {};
   if(!OrderSend(request, result))
   {
      Print("OrderSend failed: ", GetLastError());
      return;
   }
   
   if(result.retcode != TRADE_RETCODE_DONE)
   {
      Print("Trade failed: ", result.retcode);
      return;
   }
   
   // Success
   lastTradeTime = TimeCurrent();
   Print("Position opened: ", EnumToString(orderType), 
         " Lots: ", lotSize, 
         " Price: ", price, 
         " SL: ", sl, 
         " TP: ", tp);
         
   // Draw arrow on chart
   DrawEntryArrow(orderType, price);
}

//+------------------------------------------------------------------+
//| Calculate automatic lot size based on risk                       |
//+------------------------------------------------------------------+
double CalculateAutoLotSize(double slPrice, double entryPrice, ENUM_ORDER_TYPE orderType)
{
   double riskAmount = AccountInfoDouble(ACCOUNT_EQUITY) * (RiskPercentage/100);
   double slDistance = MathAbs(entryPrice - slPrice);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double pointValue = tickValue / (tickSize / _Point);
   
   return riskAmount / (slDistance * pointValue);
}

//+------------------------------------------------------------------+
//| Normalize lot size to broker requirements                        |
//+------------------------------------------------------------------+
double NormalizeLotSize(double lots)
{
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   lots = MathMax(minLot, MathMin(maxLot, lots));
   lots = MathRound(lots / lotStep) * lotStep;
   
   return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
//| Count open positions for this EA                                 |
//+------------------------------------------------------------------+
int CountOpenPositions()
{
   int count = 0;
   for(int i=0; i<PositionsTotal(); i++)
   {
      if(PositionGetTicket(i) && 
         PositionGetString(POSITION_SYMBOL) == _Symbol && 
         PositionGetInteger(POSITION_MAGIC) == MagicNumber)
      {
         count++;
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Manage open positions (trailing stops, breakeven)                |
//+------------------------------------------------------------------+
void ManagePositions()
{
   for(int i=0; i<PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket) || 
         PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;
         
      // Handle virtual stop loss
      if(EnableVirtualStops)
         CheckVirtualStopLoss(ticket);
         
      // Handle trailing stop
      if(EnableTrailingStop)
         UpdateTrailingStop(ticket);
         
      // Handle break-even
      if(EnableBreakEven)
         UpdateBreakEven(ticket);
   }
}

//+------------------------------------------------------------------+
//| Check virtual stop loss conditions                               |
//+------------------------------------------------------------------+
void CheckVirtualStopLoss(ulong ticket)
{
   string comment = PositionGetString(POSITION_COMMENT);
   if(StringFind(comment, ":") == -1) return;
   
   double virtualSl = StringToDouble(StringSubstr(comment, StringFind(comment, ":")+1));
   double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
   
   if((PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY && currentPrice <= virtualSl) ||
      (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL && currentPrice >= virtualSl))
   {
      ClosePosition(ticket, "Virtual SL triggered");
   }
}

//+------------------------------------------------------------------+
//| Update trailing stop for position                                |
//+------------------------------------------------------------------+
void UpdateTrailingStop(ulong ticket)
{
   double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double currentSl = PositionGetDouble(POSITION_SL);
   double newSl = currentSl;
   
   if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
   {
      // Calculate new stop level
      double potentialSl = currentPrice - TrailingStopDistance * _Point;
      if(potentialSl > openPrice && potentialSl > currentSl)
      {
         newSl = potentialSl;
      }
   }
   else // SELL position
   {
      // Calculate new stop level
      double potentialSl = currentPrice + TrailingStopDistance * _Point;
      if(potentialSl < openPrice && (potentialSl < currentSl || currentSl == 0))
      {
         newSl = potentialSl;
      }
   }
   
   // Modify if needed
   if(newSl != currentSl)
   {
      ModifyStopLoss(ticket, newSl);
   }
}

//+------------------------------------------------------------------+
//| Update break-even stop for position                              |
//+------------------------------------------------------------------+
void UpdateBreakEven(ulong ticket)
{
   double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double currentSl = PositionGetDouble(POSITION_SL);
   
   if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
   {
      if(currentPrice >= openPrice + BreakEvenAt * _Point && 
         (currentSl < openPrice || currentSl == 0))
      {
         ModifyStopLoss(ticket, openPrice + 5 * _Point); // Small buffer
      }
   }
   else // SELL position
   {
      if(currentPrice <= openPrice - BreakEvenAt * _Point && 
         (currentSl > openPrice || currentSl == 0))
      {
         ModifyStopLoss(ticket, openPrice - 5 * _Point); // Small buffer
      }
   }
}

//+------------------------------------------------------------------+
//| Modify position's stop loss                                      |
//+------------------------------------------------------------------+
void ModifyStopLoss(ulong ticket, double newSl)
{
   MqlTradeRequest request = {};
   request.action = TRADE_ACTION_SLTP;
   request.position = ticket;
   request.symbol = PositionGetString(POSITION_SYMBOL);
   request.sl = newSl;
   request.tp = PositionGetDouble(POSITION_TP);
   request.magic = MagicNumber;
   
   MqlTradeResult result = {};
   if(!OrderSend(request, result))
   {
      Print("ModifyStopLoss failed: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| Close specified position                                         |
//+------------------------------------------------------------------+
void ClosePosition(ulong ticket, string reason)
{
   if(!PositionSelectByTicket(ticket)) return;
   
   MqlTradeRequest request = {};
   request.action = TRADE_ACTION_DEAL;
   request.position = ticket;
   request.symbol = PositionGetString(POSITION_SYMBOL);
   request.volume = PositionGetDouble(POSITION_VOLUME);
   request.deviation = 10;
   request.magic = MagicNumber;
   request.type_filling = ORDER_FILLING_FOK;
   
   if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
   {
      request.type = ORDER_TYPE_SELL;
      request.price = SymbolInfoDouble(request.symbol, SYMBOL_BID);
   }
   else // SELL
   {
      request.type = ORDER_TYPE_BUY;
      request.price = SymbolInfoDouble(request.symbol, SYMBOL_ASK);
   }
   
   MqlTradeResult result = {};
   if(!OrderSend(request, result))
   {
      Print("ClosePosition failed: ", GetLastError());
   }
   else
   {
      Print("Position closed: ", ticket, " Reason: ", reason);
   }
}

//+------------------------------------------------------------------+
//| Draw entry arrow on chart                                        |
//+------------------------------------------------------------------+
void DrawEntryArrow(ENUM_ORDER_TYPE orderType, double price)
{
   string arrowName = "Entry_" + IntegerToString(TimeCurrent());
   int arrowCode = (orderType == ORDER_TYPE_BUY) ? 241 : 242;
   color arrowColor = (orderType == ORDER_TYPE_BUY) ? clrDodgerBlue : clrOrangeRed;
   
   if(ObjectCreate(0, arrowName, OBJ_ARROW, 0, TimeCurrent(), price))
   {
      ObjectSetInteger(0, arrowName, OBJPROP_COLOR, arrowColor);
      ObjectSetInteger(0, arrowName, OBJPROP_ARROWCODE, arrowCode);
      ObjectSetInteger(0, arrowName, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, arrowName, OBJPROP_BACK, false);
   }
}
//+------------------------------------------------------------------+
