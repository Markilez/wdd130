//+------------------------------------------------------------------+
//|                                               MyEnhancedBiDirEA.mq5 |
//|                        Copyright 2025, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.30" // Version incremented for Bi-Directional
#property description "Enhanced Scalper EA (Bi-Directional) with EMA/RSI/ADX signals, ATR SL option, Trailing Stop, Profit Target"

// --- Includes ---
#include <Trade\Trade.mqh> // Using CTrade for easier position modification

// --- Input Parameters ---
input group "Trading Strategy"
input int    MagicNumber    = 9732;            // Unique Magic Number for this EA
input double TakeProfitPoints  = 500.0;         // Take Profit in points
input bool   UseEaDefinedStopLoss = true;      // Use ATR for Stop Loss? (If false, uses StopLossPoints)
input double StopLossPoints    = 500.0;         // Stop Loss in points (only if UseEaDefinedStopLoss=false)
input double AtrMultiplier     = 2.0;           // Multiplier for ATR Stop Loss (if UseEaDefinedStopLoss=true)

input group "Risk Management"
input double Lots              = 0.0;           // Fixed Lot Size (if > 0, overrides Risk Percentage)
input double RiskPercentage    = 1.0;           // Risk percentage of account equity per trade
input int    MaxOpenPositions  = 5;             // Maximum number of TOTAL open positions (Buys + Sells)
input double MaxDrawdownPercentage = 100;       // Max Account Drawdown % (100 = disabled) - Stops NEW trades if hit

input group "Trade Management"
input double ProfitTargetDollars = 50.0;        // Close all trades when total profit reaches this amount ($)
input bool   EnableTrailingStop = true;         // Enable Trailing Stop feature
input double TrailingStopPoints = 100.0;        // Trailing Stop activation distance in points
input double TrailingStepPoints = 10.0;         // Trailing Stop step in points (usually small or 0)

input group "Timing & Cooldown"
input int    TradeCooldownSeconds = 150;        // Minimum time between opening trades
input int    GroupIdleMinutes   = 3;            // Idle time (minutes) after Profit Target is hit

input group "Indicator Settings"
input int    EmaPeriod1        = 50;            // Fast EMA Period
input int    EmaPeriod2        = 200;           // Slow EMA Period
input int    RsiPeriod         = 14;            // RSI Period
input double RsiOverbought     = 70.0;          // RSI Overbought level (Sell if RSI > this)
input double RsiOversold       = 30.0;          // RSI Oversold level (Buy if RSI < this) - Corrected from original code
input int    AtrPeriod         = 14;            // ATR Period (for SL)
input int    AdxPeriod         = 14;            // ADX Period
input double AdxThreshold      = 20.0;          // ADX threshold for trend strength (Trade if ADX > this)
input ENUM_TIMEFRAMES IndicatorTimeframe = PERIOD_CURRENT; // Timeframe for indicators
input ENUM_MA_METHOD  MAType           = MODE_EMA; // Type of Moving Average
input int             AppliedPrice     = PRICE_CLOSE; // Applied price for indicators

input group "Display & Logging"
input bool   ShowEntrySignals  = true;          // Show buy/sell signals on chart
input bool   EnableLogging     = true;          // Enable logging of trade signals and actions

// --- Global Variables ---
// Indicator handles
int emaHandle1 = INVALID_HANDLE;
int emaHandle2 = INVALID_HANDLE;
int rsiHandle = INVALID_HANDLE;
int atrHandle = INVALID_HANDLE;
int adxHandle = INVALID_HANDLE;

// Indicator buffers
double emaBuffer1[], emaBuffer2[], rsiBuffer[], atrBuffer[], adxBuffer[];

// Indicator values from the last completed bar (index 1)
double emaValue1_1, emaValue2_1, rsiValue_1, atrValue_1, adxValue_1;

// Trading variables
CTrade trade;                    // Trading object
datetime lastTradeTime = 0;      // Time of the last opened trade
string currentSymbol;            // Symbol the EA is running on
int numberOfDigits;              // Number of digits after the decimal point for price
int volumeDigits;                // Number of digits after the decimal point for volume
double pointSize;                // Point size
double accountEquityAtStart = 0; // For Max Drawdown check
bool stopTrading = false;        // Flag to stop new trades if drawdown hit
bool groupCompleted = false;     // Flag indicating profit target was hit
datetime groupEndTime = 0;       // Time when the profit target was hit

//+------------------------------------------------------------------+
//| Expert Initialization Function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    currentSymbol = _Symbol;
    numberOfDigits = (int)SymbolInfoInteger(currentSymbol, SYMBOL_DIGITS);
    pointSize = SymbolInfoDouble(currentSymbol, SYMBOL_POINT);

    //--- Determine volume precision
    double volumeStep = SymbolInfoDouble(currentSymbol, SYMBOL_VOLUME_STEP);
    string step_str = DoubleToString(volumeStep);
    int point_pos = StringFind(step_str, ".");
    volumeDigits = (point_pos >= 0) ? StringLen(step_str) - point_pos - 1 : 0;

    //--- Initialize Indicators
    if (!InitializeIndicators()) { return INIT_FAILED; } // Error printed inside function

    //--- Set buffer series direction
    ArraySetAsSeries(emaBuffer1, true);
    ArraySetAsSeries(emaBuffer2, true);
    ArraySetAsSeries(rsiBuffer, true);
    ArraySetAsSeries(atrBuffer, true);
    ArraySetAsSeries(adxBuffer, true);

    //--- Setup CTrade object
    trade.SetExpertMagicNumber(MagicNumber);
    trade.SetTypeFillingBySymbol(currentSymbol);
    trade.SetDeviationInPoints(5); // Allow 5 points slippage

    //--- Initialize Drawdown Check
    if (MaxDrawdownPercentage < 100 && MaxDrawdownPercentage > 0)
    {
        accountEquityAtStart = AccountInfoDouble(ACCOUNT_EQUITY);
        Print("Max Drawdown Check Enabled: ", MaxDrawdownPercentage, "%. Initial Equity: ", accountEquityAtStart);
    }
    else
    {
        Print("Max Drawdown Check Disabled.");
    }

    Print("Enhanced Bi-Directional EA initialized successfully for ", currentSymbol, ". Magic: ", MagicNumber);
    Print("Lot Sizing: ", (Lots > 0 ? DoubleToString(Lots, volumeDigits) + " Lots" : DoubleToString(RiskPercentage, 1) + "% Risk"),
          ", TP: ", DoubleToString(TakeProfitPoints), "pts",
          ", SL: ", (UseEaDefinedStopLoss ? DoubleToString(AtrMultiplier) + "*ATR" : DoubleToString(StopLossPoints) + "pts"));
    Print("Profit Target: $", DoubleToString(ProfitTargetDollars, 2), ", Trailing Stop: ", (EnableTrailingStop ? DoubleToString(TrailingStopPoints) + "pts" : "Disabled"));

    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Initialize Indicators                                          |
//+------------------------------------------------------------------+
bool InitializeIndicators()
{
    emaHandle1 = iMA(currentSymbol, IndicatorTimeframe, EmaPeriod1, 0, MAType, AppliedPrice);
    if (emaHandle1 == INVALID_HANDLE) { Print("Error getting EMA1 handle: ", GetLastError()); return false; }

    emaHandle2 = iMA(currentSymbol, IndicatorTimeframe, EmaPeriod2, 0, MAType, AppliedPrice);
    if (emaHandle2 == INVALID_HANDLE) { Print("Error getting EMA2 handle: ", GetLastError()); return false; }

    rsiHandle = iRSI(currentSymbol, IndicatorTimeframe, RsiPeriod, AppliedPrice);
    if (rsiHandle == INVALID_HANDLE) { Print("Error getting RSI handle: ", GetLastError()); return false; }

    atrHandle = iATR(currentSymbol, IndicatorTimeframe, AtrPeriod);
    if (atrHandle == INVALID_HANDLE) { Print("Error getting ATR handle: ", GetLastError()); return false; }

    adxHandle = iADX(currentSymbol, IndicatorTimeframe, AdxPeriod);
    if (adxHandle == INVALID_HANDLE) { Print("Error getting ADX handle: ", GetLastError()); return false; }

    return true;
}

//+------------------------------------------------------------------+
//| Expert Deinitialization Function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    ReleaseIndicators();
    ObjectsDeleteAll(0, StringFormat("TradeSignal_%s_", currentSymbol));
    Print("Enhanced Bi-Directional EA deinitialized. Reason code: ", reason);
}

//+------------------------------------------------------------------+
//| Release Indicators                                             |
//+------------------------------------------------------------------+
void ReleaseIndicators()
{
    if (emaHandle1 != INVALID_HANDLE) IndicatorRelease(emaHandle1);
    if (emaHandle2 != INVALID_HANDLE) IndicatorRelease(emaHandle2);
    if (rsiHandle != INVALID_HANDLE) IndicatorRelease(rsiHandle);
    if (atrHandle != INVALID_HANDLE) IndicatorRelease(atrHandle);
    if (adxHandle != INVALID_HANDLE) IndicatorRelease(adxHandle);
    if (EnableLogging) Print("Indicator handles released.");
}

//+------------------------------------------------------------------+
//| Expert Tick Function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    if (stopTrading) return;
    if (!IsTradeAllowed()) return;

    //--- Check Max Drawdown
    if (accountEquityAtStart > 0 && CheckMaxDrawdown())
    {
        Print("Maximum drawdown threshold (", MaxDrawdownPercentage, "%) reached. Stopping new trades.");
        stopTrading = true;
        return;
    }

    //--- Calculate indicator values
    if (!CalculateIndicators()) return;

    //--- Manage existing open trades
    ManageOpenTrades();

    //--- Group Idle Check
    if (groupCompleted && TimeCurrent() - groupEndTime < GroupIdleMinutes * 60) return; // Idling
    else if (groupCompleted) // Idle time finished
    {
        groupCompleted = false;
        if (EnableLogging) Print("Group idle time finished. Resuming trade checks.");
    }

    //--- Check for new trade opportunities (Buy or Sell)
    CheckAndOpenTrade();
}

//+------------------------------------------------------------------+
//| Check Maximum Drawdown Threshold                                 |
//+------------------------------------------------------------------+
bool CheckMaxDrawdown()
{
    if (accountEquityAtStart <= 0 || MaxDrawdownPercentage >= 100) return false;
    double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    double drawdown = accountEquityAtStart - currentEquity;
    if (drawdown <= 0) return false;
    double drawdownPercentage = (drawdown / accountEquityAtStart) * 100.0;
    return drawdownPercentage >= MaxDrawdownPercentage;
}

//+------------------------------------------------------------------+
//| Calculate Indicators                                           |
//+------------------------------------------------------------------+
bool CalculateIndicators()
{
    if (CopyBuffer(emaHandle1, 0, 0, 2, emaBuffer1) < 2 || 
        CopyBuffer(emaHandle2, 0, 0, 2, emaBuffer2) < 2 ||
        CopyBuffer(rsiHandle, 0, 0, 2, rsiBuffer) < 2 || 
        CopyBuffer(atrHandle, 0, 0, 2, atrBuffer) < 2 ||
        CopyBuffer(adxHandle, 0, 0, 2, adxBuffer) < 2)
    {
        return false; // Error copying buffers
    }

    // Get values from the last completed bar (index 1)
    emaValue1_1 = emaBuffer1[1];
    emaValue2_1 = emaBuffer2[1];
    rsiValue_1 = rsiBuffer[1];
    atrValue_1 = atrBuffer[1];
    adxValue_1 = adxBuffer[1];

    if (atrValue_1 <= 0) return false; // Check ATR validity

    return true;
}

//+------------------------------------------------------------------+
//| Check Entry Signal (Buy or Sell)                               |
//| Returns: 1 for Buy, -1 for Sell, 0 for No Signal             |
//+------------------------------------------------------------------+
int CheckEntrySignal()
{
    //--- BUY Condition: Fast EMA > Slow EMA, RSI < Oversold Level
    bool buyCondition = (emaValue1_1 > emaValue2_1 &&
                         rsiValue_1 < RsiOversold && // **Buy when Oversold**
                         adxValue_1 > AdxThreshold);

    //--- SELL Condition: Fast EMA < Slow EMA, RSI > Overbought Level
    bool sellCondition = (emaValue1_1 < emaValue2_1 &&
                          rsiValue_1 > RsiOverbought && // **Sell when Overbought**
                          adxValue_1 > AdxThreshold);

    if (buyCondition)
    {
        if (EnableLogging) PrintFormat("%s: Buy Signal Detected (EMA1[1]=%.*f > EMA2[1]=%.*f, RSI[1]=%.2f < %.1f, ADX[1]=%.2f > %.1f)",
                                       currentSymbol, numberOfDigits, emaValue1_1, numberOfDigits, emaValue2_1, rsiValue_1, RsiOversold, adxValue_1, AdxThreshold);
        return 1;
    }
    if (sellCondition)
    {
        if (EnableLogging) PrintFormat("%s: Sell Signal Detected (EMA1[1]=%.*f < EMA2[1]=%.*f, RSI[1]=%.2f > %.1f, ADX[1]=%.2f > %.1f)",
                                       currentSymbol, numberOfDigits, emaValue1_1, numberOfDigits, emaValue2_1, rsiValue_1, RsiOverbought, adxValue_1, AdxThreshold);
        return -1;
    }

    return 0; // No signal
}

//+------------------------------------------------------------------+
//| Check Conditions and Open Trade (Buy or Sell)                  |
//+------------------------------------------------------------------+
void CheckAndOpenTrade()
{
    if (TimeCurrent() - lastTradeTime < TradeCooldownSeconds) return;
    if (CountOpenPositions() >= MaxOpenPositions) return;

    int signalType = CheckEntrySignal();
    if (signalType == 0) return; // No Buy or Sell signal

    //--- Determine order type and prices
    ENUM_ORDER_TYPE orderType;
    double entryPrice, slPrice, tpPrice;
    string comment = "blue dot"; // *** User requested comment ***

    if (signalType == 1) // Buy Signal
    {
        orderType = ORDER_TYPE_BUY;
        entryPrice = SymbolInfoDouble(currentSymbol, SYMBOL_ASK);
        slPrice = entryPrice - (UseEaDefinedStopLoss ? (atrValue_1 * AtrMultiplier) : (StopLossPoints * pointSize));
        tpPrice = entryPrice + (TakeProfitPoints * pointSize);
    }
    else // Sell Signal (signalType == -1)
    {
        orderType = ORDER_TYPE_SELL;
        entryPrice = SymbolInfoDouble(currentSymbol, SYMBOL_BID);
        slPrice = entryPrice + (UseEaDefinedStopLoss ? (atrValue_1 * AtrMultiplier) : (StopLossPoints * pointSize));
        tpPrice = entryPrice - (TakeProfitPoints * pointSize);
    }

    // Validate calculated prices
    if (entryPrice <= 0 || slPrice <= 0 || tpPrice <= 0 || 
        (orderType == ORDER_TYPE_BUY && slPrice >= entryPrice) || 
        (orderType == ORDER_TYPE_SELL && slPrice <= entryPrice))
    {
        PrintFormat("%s: Invalid prices calculated for %s. Entry=%.*f, SL=%.*f, TP=%.*f. Skipping trade.",
                    currentSymbol, EnumToString(orderType), numberOfDigits, entryPrice, numberOfDigits, slPrice, numberOfDigits, tpPrice);
        return;
    }

    //--- Normalize prices
    entryPrice = NormalizeDouble(entryPrice, numberOfDigits);
    slPrice    = NormalizeDouble(slPrice, numberOfDigits);
    tpPrice    = NormalizeDouble(tpPrice, numberOfDigits);

    //--- Calculate Lot Size
    double lotSize = CalculateLotSize(slPrice, orderType);
    if (lotSize <= 0) {
        if (EnableLogging) PrintFormat("%s: Invalid lot size calculated (%.*f) for %s. Cannot open trade.", currentSymbol, volumeDigits, lotSize, EnumToString(orderType));
        return;
    }

    //--- Draw signal on chart
    if (ShowEntrySignals) { DrawEntrySignal(orderType, entryPrice); }

    //--- Send Order Request using CTrade
    if (EnableLogging) PrintFormat("%s: Attempting to %s %. *f lots at %. *f (SL: %.*f, TP: %.*f, Comment: %s)",
                                   currentSymbol, EnumToString(orderType), volumeDigits, lotSize, numberOfDigits, entryPrice, numberOfDigits, slPrice, numberOfDigits, tpPrice, comment);

    bool result = false;
    if (orderType == ORDER_TYPE_BUY)
    {
        result = trade.Buy(lotSize, currentSymbol, entryPrice, slPrice, tpPrice, comment);
    }
    else // ORDER_TYPE_SELL
    {
        result = trade.Sell(lotSize, currentSymbol, entryPrice, slPrice, tpPrice, comment);
    }

    //--- Process result
    if (result)
    {
        if (EnableLogging) PrintFormat("%s: %s order placed successfully. Ticket: %d", currentSymbol, EnumToString(orderType), (int)trade.ResultOrder());
        lastTradeTime = TimeCurrent();
    }
    else
    {
        PrintFormat("%s: %s order failed. Error: %d, Retcode: %d. Comment: %s",
                    currentSymbol, EnumToString(orderType), (int)trade.ResultRetcode(), (int)trade.ResultRetcode(), trade.ResultComment());
    }
}

//+------------------------------------------------------------------+
//| Manage Open Trades (Profit Target, Trailing Stop)              |
//+------------------------------------------------------------------+
void ManageOpenTrades()
{
    double totalProfit = 0;
    int openPositionCount = 0;
    bool profitTargetHit = false;

    //--- Calculate Total Profit & Count Positions
    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if (PositionSelectByTicket(ticket) && PositionGetString(POSITION_SYMBOL) == currentSymbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
        {
            totalProfit += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
            openPositionCount++;
        }
    }

    //--- Check Profit Target ($)
    if (openPositionCount > 0 && ProfitTargetDollars > 0 && totalProfit >= ProfitTargetDollars)
    {
        if (EnableLogging) PrintFormat("%s: Profit Target ($%.2f) hit! Total Profit: $%.2f. Closing all %d positions.",
                                      currentSymbol, ProfitTargetDollars, totalProfit, openPositionCount);
        CloseAllPositions("Profit Target Hit");
        groupCompleted = true;
        groupEndTime = TimeCurrent();
        profitTargetHit = true; // Don't trail immediately after closing
    }

    //--- Manage Trailing Stop (if enabled and profit target not hit this tick)
    if (EnableTrailingStop && !profitTargetHit && openPositionCount > 0)
    {
        for (int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if (PositionSelectByTicket(ticket) && PositionGetString(POSITION_SYMBOL) == currentSymbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
            {
                long positionType = PositionGetInteger(POSITION_TYPE);
                double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
                double currentSl = PositionGetDouble(POSITION_SL);
                double currentTp = PositionGetDouble(POSITION_TP);
                double potentialNewSl = 0;
                bool trail = false;

                if (positionType == POSITION_TYPE_BUY)
                {
                    double currentBid = SymbolInfoDouble(currentSymbol, SYMBOL_BID);
                    if (currentBid <= 0) continue; // Skip if price unavailable
                    potentialNewSl = currentBid - (TrailingStopPoints * pointSize);
                    if (potentialNewSl > openPrice && (currentSl == 0 || potentialNewSl > currentSl) && (currentSl == 0 || potentialNewSl >= currentSl + (TrailingStepPoints * pointSize)))
                    {
                        trail = true;
                    }
                }
                else // POSITION_TYPE_SELL
                {
                    double currentAsk = SymbolInfoDouble(currentSymbol, SYMBOL_ASK);
                    if (currentAsk <= 0) continue; // Skip if price unavailable
                    potentialNewSl = currentAsk + (TrailingStopPoints * pointSize);
                    if (potentialNewSl < openPrice && (currentSl == 0 || potentialNewSl < currentSl) && (currentSl == 0 || potentialNewSl <= currentSl - (TrailingStepPoints * pointSize)))
                    {
                        trail = true;
                    }
                }

                // If trailing condition met, modify SL
                if (trail && potentialNewSl != 0)
                {
                    double normalizedNewSl = NormalizeDouble(potentialNewSl, numberOfDigits);
                    // Prevent setting SL exactly at market price
                    if ((positionType == POSITION_TYPE_BUY && normalizedNewSl >= SymbolInfoDouble(currentSymbol, SYMBOL_BID)) ||
                        (positionType == POSITION_TYPE_SELL && normalizedNewSl <= SymbolInfoDouble(currentSymbol, SYMBOL_ASK)))
                    {
                        if (EnableLogging) PrintFormat("%s: Trailing Stop for ticket %d skipped - calculated SL %.*f too close to current market price.", currentSymbol, ticket, numberOfDigits, normalizedNewSl);
                        continue;
                    }

                    if (EnableLogging) PrintFormat("%s: Trailing Stop triggered for %s Ticket %d. Moving SL from %.*f to %.*f",
                                                   currentSymbol, EnumToString((ENUM_POSITION_TYPE)positionType), ticket, numberOfDigits, currentSl, numberOfDigits, normalizedNewSl);

                    if (!trade.PositionModify(ticket, normalizedNewSl, currentTp))
                    {
                        PrintFormat("%s: Failed to modify SL for ticket %d. Error: %d",
                                    currentSymbol, ticket, (int)trade.ResultRetcode());
                    }
                }
            } // end if position selected & matches
        } // end for loop through positions
    } // end if TrailingStop enabled
}

//+------------------------------------------------------------------+
//| Close All Positions for this EA instance                       |
//+------------------------------------------------------------------+
void CloseAllPositions(string reason = "Close All Request")
{
    int closedCount = 0;
    if (EnableLogging) PrintFormat("%s: Attempting to close all positions (%s)...", currentSymbol, reason);
    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if (PositionSelectByTicket(ticket) && PositionGetString(POSITION_SYMBOL) == currentSymbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
        {
            if (trade.PositionClose(ticket, 5)) { closedCount++; }
            else { PrintFormat("%s: Failed to close position ticket %d. Error: %d", currentSymbol, ticket, (int)trade.ResultRetcode()); }
        }
    }
    if (EnableLogging && closedCount > 0) PrintFormat("%s: Closed %d positions.", currentSymbol, closedCount);
}

//+------------------------------------------------------------------+
//| Draw Entry Signal on Chart                                     |
//+------------------------------------------------------------------+
void DrawEntrySignal(ENUM_ORDER_TYPE orderType, double price)
{
    int arrowCode = (orderType == ORDER_TYPE_BUY) ? 241 : 242; // 241=Up, 242=Down
    color arrowColor = (orderType == ORDER_TYPE_BUY) ? clrDeepSkyBlue : clrMagenta;
    double y_offset = (orderType == ORDER_TYPE_BUY) ? -10 * pointSize : 10 * pointSize;
    datetime barTime = (datetime)SeriesInfoInteger(currentSymbol, _Period, SERIES_LASTBAR_DATE);
    string arrowName = StringFormat("TradeSignal_%s_%s_%d", currentSymbol, EnumToString(orderType), barTime);

    if (ObjectFind(0, arrowName) == -1)
    {
        if (ObjectCreate(0, arrowName, OBJ_ARROW, 0, barTime, price + y_offset))
        {
            ObjectSetInteger(0, arrowName, OBJPROP_COLOR, arrowColor);
            ObjectSetInteger(0, arrowName, OBJPROP_ARROWCODE, arrowCode);
            ObjectSetInteger(0, arrowName, OBJPROP_WIDTH, 1);
            ObjectSetInteger(0, arrowName, OBJPROP_BACK, false);
        }
    }
}

//+------------------------------------------------------------------+
//| Calculate Lot Size Based on Risk % or Fixed Lot                |
//+------------------------------------------------------------------+
double CalculateLotSize(double stopLossPrice, ENUM_ORDER_TYPE orderType)
{
    if (Lots > 0) { return NormalizeLotSize(Lots); }

    double accountEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    if (accountEquity <= 0) { PrintFormat("%s: Cannot calc lot: Account Equity <= 0.", currentSymbol); return 0.0; }

    double entryPrice = (orderType == ORDER_TYPE_BUY) ? SymbolInfoDouble(currentSymbol, SYMBOL_ASK) : SymbolInfoDouble(currentSymbol, SYMBOL_BID);
    if (entryPrice <= 0 || stopLossPrice <= 0) { PrintFormat("%s: Cannot calc lot: Invalid entry (%.*f) or SL price (%.*f).", currentSymbol, numberOfDigits, entryPrice, numberOfDigits, stopLossPrice); return 0.0; }

    double stopLossDistancePoints = (orderType == ORDER_TYPE_BUY) ? (entryPrice - stopLossPrice) / pointSize : (stopLossPrice - entryPrice) / pointSize;

    double spreadPoints = SymbolInfoInteger(currentSymbol, SYMBOL_SPREAD);
    if (stopLossDistancePoints <= spreadPoints * 0.1)
    {
        PrintFormat("%s: Cannot calc lot: SL distance (%.1f points) too small relative to spread (%d) or zero/negative.", currentSymbol, stopLossDistancePoints, spreadPoints);
        return 0.0;
    }

    double riskAmount = accountEquity * (RiskPercentage / 100.0);
    double tickValue = SymbolInfoDouble(currentSymbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(currentSymbol, SYMBOL_TRADE_TICK_SIZE);

    if (tickValue <= 0 || tickSize <= 0) { PrintFormat("%s: Cannot calc lot: Invalid Tick Value (%.4f) or Tick Size (%.*f).", currentSymbol, tickValue, numberOfDigits, tickSize); return 0.0; }

    double valuePerPoint = tickValue / (tickSize / pointSize);
    if (valuePerPoint <= 0) { PrintFormat("%s: Cannot calc lot: Invalid Value Per Point (%.4f) calculated.", currentSymbol, valuePerPoint); return 0.0; }

    double lotSize = riskAmount / (stopLossDistancePoints * valuePerPoint);

    return NormalizeLotSize(lotSize);
}

//+------------------------------------------------------------------+
//| Normalize Lot Size according to symbol limits                  |
//+------------------------------------------------------------------+
double NormalizeLotSize(double lotSize)
{
    double volumeMin = SymbolInfoDouble(currentSymbol, SYMBOL_VOLUME_MIN);
    double volumeMax = SymbolInfoDouble(currentSymbol, SYMBOL_VOLUME_MAX);
    double volumeStep = SymbolInfoDouble(currentSymbol, SYMBOL_VOLUME_STEP);

    if (volumeStep <= 0) { PrintFormat("%s: Invalid SYMBOL_VOLUME_STEP (%.*f). Cannot normalize lot size.", currentSymbol, volumeDigits + 2, volumeStep); return 0.0; }

    lotSize = MathRound(lotSize / volumeStep) * volumeStep;
    lotSize = NormalizeDouble(lotSize, volumeDigits);

    if (lotSize < volumeMin && volumeMin > 0) { lotSize = volumeMin; }
    if (lotSize > volumeMax && volumeMax > 0)
    {
        lotSize = volumeMax;
        if (EnableLogging) PrintFormat("%s: Lot size capped at maximum allowed: %.*f", currentSymbol, volumeDigits, lotSize);
    }
    if (lotSize < volumeMin && volumeMin > 0) { PrintFormat("%s: Final normalized lot size %.*f below minimum %.*f. Cannot trade.", currentSymbol, volumeDigits, lotSize, volumeDigits, volumeMin); return 0.0; }

    return lotSize;
}

//+------------------------------------------------------------------+
//| Count Open Positions for the Current Symbol and Magic Number     |
//+------------------------------------------------------------------+
int CountOpenPositions()
{
    int count = 0;
    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if (PositionSelectByTicket(ticket) && PositionGetString(POSITION_SYMBOL) == currentSymbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
        { count++; }
    }
    return count;
}

//+------------------------------------------------------------------+
//| Check if Algo Trading is Enabled                                |
//+------------------------------------------------------------------+
bool IsTradeAllowed()
{
    if (!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) { Print("TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) is false."); return false; }
    if (!MQLInfoInteger(MQL_TRADE_ALLOWED)) { Print("MQLInfoInteger(MQL_TRADE_ALLOWED) is false. Check Expert Advisor properties -> Common -> Allow algo trading."); return false; }
    return true;
}
//+------------------------------------------------------------------+
