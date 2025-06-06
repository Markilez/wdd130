//+------------------------------------------------------------------+
//|                                                      MyExpert.mq5 |
//|                        Copyright 2025, MetaQuotes Software Corp. |
//|                                       https://www.mql5.com       |
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window

// Input Parameters
input double TakeProfit = 500;            // Take Profit in points
input double StopLoss = 500;              // Stop Loss in points
input int EmaPeriod1 = 50;                // 50 EMA Period
input int EmaPeriod2 = 200;               // 200 EMA Period
input int RsiPeriod = 14;                 // RSI Period
input double RsiOverbought = 70;          // RSI Overbought level
input double RsiOversold = 25;            // RSI Oversold level (adjusted from 30)
input int AtrPeriod = 14;                 // ATR Period
input int AdxPeriod = 14;                 // ADX Period
input double AdxThreshold = 20;           // ADX threshold for trend strength (adjusted from 25)
input double RiskPercentage = 1.0;        // Risk percentage of account balance
input double UserLotSize = 0.20;          // User-defined lot size (set to 0 to use default 0.001)
input int MagicNumber = 105906;             // Unique Magic Number for this EA
input bool ShowEntrySignals = true;       // Show buy/sell signals on chart
input bool EnableLogging = true;          // Enable logging of trade signals
input bool UseEaDefinedStopLoss = true;   // Enable/disable EA-defined stop loss
input int MaxOpenPositions = 5;           // Maximum number of open positions
input double ProfitTarget = 5;           // Profit target in dollars
input double LockInProfitThreshold = 20;  // Lock-in profit threshold in dollars
input int TrailingStopDelaySeconds = 300; // Delay in seconds before trailing stop is activated
input double TrailingStop = 20;           // Trailing Stop in points
input bool EnableTrailingStop = true;     // Enable or disable trailing stop feature
input int TradeCooldownSeconds = 150;     // Cooldown period between trades in seconds
input double MaxDrawdownPercentage = 10;  // Maximum drawdown threshold (in percentage)
input int GroupIdleMinutes = 3;           // Idle time after completing a group of trades
input int MinHoldPeriodSeconds = 300;     // Minimum holding period before closing a trade

// Global Variables
double emaValue1, emaValue2, rsiValue, atrValue, adxValue;
int emaHandle1, emaHandle2, rsiHandle, atrHandle, adxHandle;
long chartId; // Store the chart ID
datetime lastTradeTime = 0; // Time of the last trade
double lastLotSize = 0.001; // Last used lot size
double accountEquityAtStart; // Account equity at the start of trading
bool groupCompleted = true; // Flag to indicate if a group of trades is completed
datetime groupEndTime = 0; // Time when the group of trades was completed

//+------------------------------------------------------------------+
//| Expert Initialization Function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    chartId = ChartID();
    if (!InitializeIndicators())
    {
        Print("Failed to initialize indicators.");
        return INIT_FAILED;
    }

    accountEquityAtStart = AccountInfoDouble(ACCOUNT_EQUITY);
    Print("EA initialized successfully on chart ID: ", chartId);
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert Deinitialization Function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    ReleaseIndicators();
    Print("EA deinitialized with reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert Tick Function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    if (ChartID() != chartId)
    {
        Print("EA is running on a different chart. Exiting OnTick().");
        return;
    }

    if (CheckMaxDrawdown())
    {
        Print("Maximum drawdown threshold reached. Stopping trading.");
        return;
    }

    if (groupCompleted && TimeCurrent() - groupEndTime < GroupIdleMinutes * 60)
    {
        Print("Group completed. Idling for ", GroupIdleMinutes, " minutes.");
        return;
    }
    else if (groupCompleted && TimeCurrent() - groupEndTime >= GroupIdleMinutes * 60)
    {
        groupCompleted = false;
        Print("Idle time over. Re-analyzing market conditions.");
    }

    if (CalculateIndicators())
    {
        if (CheckTradeConditions() && CountOpenPositions() < MaxOpenPositions)
        {
            if (ShowEntrySignals)
            {
                DrawEntrySignal();
            }
            OpenTrade();
        }
    }
}

//+------------------------------------------------------------------+
//| Initialize Indicators                                            |
//+------------------------------------------------------------------+
bool InitializeIndicators()
{
    emaHandle1 = iMA(NULL, 0, EmaPeriod1, 0, MODE_EMA, PRICE_CLOSE);
    emaHandle2 = iMA(NULL, 0, EmaPeriod2, 0, MODE_EMA, PRICE_CLOSE);
    rsiHandle = iRSI(NULL, 0, RsiPeriod, PRICE_CLOSE);
    atrHandle = iATR(NULL, 0, AtrPeriod);
    adxHandle = iADX(NULL, 0, AdxPeriod);

    if (emaHandle1 == INVALID_HANDLE || emaHandle2 == INVALID_HANDLE || 
        rsiHandle == INVALID_HANDLE || atrHandle == INVALID_HANDLE || 
        adxHandle == INVALID_HANDLE)
    {
        return false;
    }
    return true;
}

//+------------------------------------------------------------------+
//| Release Indicators                                               |
//+------------------------------------------------------------------+
void ReleaseIndicators()
{
    IndicatorRelease(emaHandle1);
    IndicatorRelease(emaHandle2);
    IndicatorRelease(rsiHandle);
    IndicatorRelease(atrHandle);
    IndicatorRelease(adxHandle);
}

//+------------------------------------------------------------------+
//| Check Maximum Drawdown Threshold                                 |
//+------------------------------------------------------------------+
bool CheckMaxDrawdown()
{
    double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    double drawdownPercentage = ((accountEquityAtStart - currentEquity) / accountEquityAtStart) * 100;
    return drawdownPercentage >= MaxDrawdownPercentage;
}

//+------------------------------------------------------------------+
//| Calculate Indicators                                             |
//+------------------------------------------------------------------+
bool CalculateIndicators()
{
    double emaBuffer1[1], emaBuffer2[1], rsiBuffer[1], atrBuffer[1], adxBuffer[1];
    if (CopyBuffer(emaHandle1, 0, 0, 1, emaBuffer1) != 1 ||
        CopyBuffer(emaHandle2, 0, 0, 1, emaBuffer2) != 1 ||
        CopyBuffer(rsiHandle, 0, 0, 1, rsiBuffer) != 1 ||
        CopyBuffer(atrHandle, 0, 0, 1, atrBuffer) != 1 ||
        CopyBuffer(adxHandle, 0, 0, 1, adxBuffer) != 1)
    {
        Print("Failed to copy indicator buffers.");
        return false;
    }

    emaValue1 = emaBuffer1[0];
    emaValue2 = emaBuffer2[0];
    rsiValue = rsiBuffer[0];
    atrValue = atrBuffer[0];
    adxValue = adxBuffer[0];

    Print("EMA1 (50): ", emaValue1, " | EMA2 (200): ", emaValue2, 
          " | RSI: ", rsiValue, " | ATR: ", atrValue, " | ADX: ", adxValue);
    return true;
}

//+------------------------------------------------------------------+
//| Check Trade Conditions                                           |
//+------------------------------------------------------------------+
bool CheckTradeConditions()
{
    double currentPrice = iClose(NULL, 0, 0);
    bool buyCondition = (currentPrice > emaValue1 && currentPrice > emaValue2 && 
                         rsiValue < RsiOverbought && adxValue > AdxThreshold);
    bool sellCondition = ((currentPrice < emaValue1 || currentPrice < emaValue2) && 
                          rsiValue > RsiOversold && adxValue > AdxThreshold);

    // Skip trades near reversal areas
    if (IsNearReversalArea(currentPrice, buyCondition, sellCondition))
    {
        Print("Price is near reversal area. Skipping trade.");
        return false;
    }

    Print("Buy Condition: ", buyCondition, " | Sell Condition: ", sellCondition);
    return buyCondition || sellCondition;
}

//+------------------------------------------------------------------+
//| Check if Price is Near Reversal Area                             |
//+------------------------------------------------------------------+
bool IsNearReversalArea(double currentPrice, bool buyCondition, bool sellCondition)
{
    double supportLevel = iLow(NULL, 0, iLowest(NULL, 0, MODE_LOW, 14, 1));
    double resistanceLevel = iHigh(NULL, 0, iHighest(NULL, 0, MODE_HIGH, 14, 1));

    // Skip buy trades near resistance or sell trades near support
    if ((buyCondition && currentPrice >= resistanceLevel) || 
        (sellCondition && currentPrice <= supportLevel))
    {
        return true;
    }

    return false;
}

//+------------------------------------------------------------------+
//| Draw Entry Signal on Chart                                       |
//+------------------------------------------------------------------+
void DrawEntrySignal()
{
    static datetime lastSignalTime = 0;
    if (TimeCurrent() == lastSignalTime)
        return;

    lastSignalTime = TimeCurrent();

    string arrowName = "TradeSignal_" + TimeToString(TimeCurrent());
    int arrowCode = (rsiValue < RsiOverbought) ? 241 : 242; // 241 = buy, 242 = sell
    color arrowColor = (rsiValue < RsiOverbought) ? clrGreen : clrRed;

    if (ObjectFind(0, arrowName) == -1)
    {
        ObjectCreate(0, arrowName, OBJ_ARROW, 0, TimeCurrent(), iClose(NULL, 0, 0));
        ObjectSetInteger(0, arrowName, OBJPROP_COLOR, arrowColor);
        ObjectSetInteger(0, arrowName, OBJPROP_ARROWCODE, arrowCode);
        ObjectSetInteger(0, arrowName, OBJPROP_WIDTH, 2);
    }

    if (EnableLogging)
    {
        Print("Trade Signal: ", (rsiValue < RsiOverbought) ? "Buy" : "Sell", 
              " at ", TimeToString(TimeCurrent()));
    }
}

//+------------------------------------------------------------------+
//| Open Trade Function                                              |
//+------------------------------------------------------------------+
void OpenTrade()
{
    if (TimeCurrent() - lastTradeTime < TradeCooldownSeconds)
    {
        Print("Trade cooldown active. Skipping trade.");
        return;
    }

    double price, sl, tp;
    ENUM_ORDER_TYPE orderType;

    if (rsiValue < RsiOverbought)
    {
        price = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_ASK), _Digits);
        sl = UseEaDefinedStopLoss ? NormalizeDouble(price - (atrValue * 2), _Digits) : NormalizeDouble(price - StopLoss * _Point, _Digits);
        tp = NormalizeDouble(price + TakeProfit * _Point, _Digits);
        orderType = ORDER_TYPE_BUY;
    }
    else
    {
        price = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_BID), _Digits);
        sl = UseEaDefinedStopLoss ? NormalizeDouble(price + (atrValue * 2), _Digits) : NormalizeDouble(price + StopLoss * _Point, _Digits);
        tp = NormalizeDouble(price - TakeProfit * _Point, _Digits);
        orderType = ORDER_TYPE_SELL;
    }

    // Log the trade parameters for debugging
    Print("Opening Trade - Price: ", price, " | SL: ", sl, " | TP: ", tp);

    MqlTradeRequest request;
    MqlTradeResult result;
    ZeroMemory(request);
    ZeroMemory(result);

    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = CalculateLotSize();
    request.price = price;
    request.sl = sl;
    request.tp = tp;
    request.type = orderType;
    request.type_filling = ORDER_FILLING_FOK;
    request.magic = MagicNumber;

    if (!OrderSend(request, result))
    {
        Print("OrderSend failed, error code: ", GetLastError());
    }
    else if (result.retcode != TRADE_RETCODE_DONE)
    {
        Print("Trade request failed, retcode: ", result.retcode);
    }
    else
    {
        Print("Trade opened successfully, ticket: ", result.order);
        lastTradeTime = TimeCurrent();
    }
}

//+------------------------------------------------------------------+
//| Calculate Lot Size Based on Risk Percentage and User Input       |
//+------------------------------------------------------------------+
double CalculateLotSize()
{
    if (UserLotSize > 0)
    {
        return UserLotSize; // Use user-defined lot size
    }

    double accountEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    double riskAmount = accountEquity * (RiskPercentage / 100);
    double lotSize = riskAmount / (StopLoss * _Point);
    return MathMin(lotSize, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX));
}

//+------------------------------------------------------------------+
//| Count Open Positions for the Current Symbol                      |
//+------------------------------------------------------------------+
int CountOpenPositions()
{
    int count = 0;
    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if (PositionSelectByTicket(ticket) && 
            PositionGetString(POSITION_SYMBOL) == _Symbol && 
            PositionGetInteger(POSITION_MAGIC) == MagicNumber)
        {
            count++;
        }
    }
    return count;
}
