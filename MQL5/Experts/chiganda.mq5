//+------------------------------------------------------------------+
//|                                                      ScalperEA.mq5|
//|                        Copyright 2025, MetaQuotes Software Corp. |
//|                                       https://www.mql5.com       |
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window

// Input Parameters
input double TakeProfit = 1000;              // Take Profit in points for scalping
input double StopLoss = 1000;                 // Stop Loss in points for scalping
input int EmaPeriod1 = 50;                    // Fast EMA Period
input int EmaPeriod2 = 200;                   // Slow EMA Period
input int RsiPeriod = 14;                     // RSI Period for scalping
input double RsiOverbought = 80.0;            // RSI Overbought level
input double RsiOversold = 20.0;              // RSI Oversold level
input int MacdFastEMAPeriod = 12;             // Fast EMA period for MACD
input int MacdSlowEMAPeriod = 26;             // Slow EMA period for MACD
input int MacdSignalPeriod = 9;               // Signal period for MACD
input double RiskPercentage = 1.0;            // Risk percentage of account balance
input double UserLotSize = 0.10;              // User-defined lot size
input int MagicNumber = 9076;                // Unique Magic Number for this EA
input bool ShowEntrySignals = true;           // Show buy/sell signals on chart
input bool EnableLogging = true;              // Enable logging of trade signals
input int MaxOpenPositions = 5;               // Maximum number of open positions
input int TradeCooldownSeconds = 60;          // Cooldown period between trades in seconds
input double LockInProfitThreshold = 20;      // Lock-in profit threshold in dollars
input double TrailingStop = 20;                // Trailing Stop in points
input bool EnableTrailingStop = true;          // Enable or disable trailing stop feature
input double MaxLossThreshold = 100;           // Maximum loss threshold in dollars
input double MaxDrawdownPercentage = 10;       // Maximum drawdown percentage

// Global Variables
double emaValue1, emaValue2, rsiValue, macdMain, macdSignal;
int emaHandle1, emaHandle2, rsiHandle, macdHandle;
long chartId; // Store the chart ID
datetime lastTradeTime = 0; // Time of the last trade

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

    Print("Scalper EA initialized successfully on chart ID: ", chartId);
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert Deinitialization Function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    ReleaseIndicators();
    Print("Scalper EA deinitialized with reason: ", reason);
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

    if (CalculateIndicators())
    {
        // Check trade conditions and the number of open positions
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
    macdHandle = iMACD(NULL, 0, MacdFastEMAPeriod, MacdSlowEMAPeriod, MacdSignalPeriod, PRICE_CLOSE);

    if (emaHandle1 == INVALID_HANDLE || emaHandle2 == INVALID_HANDLE || 
        rsiHandle == INVALID_HANDLE || macdHandle == INVALID_HANDLE)
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
    IndicatorRelease(macdHandle);
}

//+------------------------------------------------------------------+
//| Calculate Indicators                                             |
//+------------------------------------------------------------------+
bool CalculateIndicators()
{
    double emaBuffer1[1], emaBuffer2[1], rsiBuffer[1], macdBuffer[2];

    if (CopyBuffer(emaHandle1, 0, 0, 1, emaBuffer1) != 1 ||
        CopyBuffer(emaHandle2, 0, 0, 1, emaBuffer2) != 1 ||
        CopyBuffer(rsiHandle, 0, 0, 1, rsiBuffer) != 1 ||
        CopyBuffer(macdHandle, 0, 0, 2, macdBuffer) != 2)
    {
        Print("Failed to copy indicator buffers.");
        return false;
    }

    emaValue1 = emaBuffer1[0];
    emaValue2 = emaBuffer2[0];
    rsiValue = rsiBuffer[0];
    macdMain = macdBuffer[0];  // MACD value
    macdSignal = macdBuffer[1]; // Signal line value

    Print("EMA1: ", emaValue1, " | EMA2: ", emaValue2, " | RSI: ", rsiValue, " | MACD: ", macdMain, " | MACD Signal: ", macdSignal);
    return true;
}

//+------------------------------------------------------------------+
//| Check Trade Conditions                                           |
//+------------------------------------------------------------------+
bool CheckTradeConditions()
{
    double currentPrice = iClose(NULL, 0, 0);
    bool buyCondition = (currentPrice > emaValue1 && currentPrice > emaValue2 &&
                         rsiValue < RsiOverbought && macdMain > macdSignal &&
                         CheckCandlestickPattern(true));

    bool sellCondition = (currentPrice < emaValue1 && currentPrice < emaValue2 &&
                          rsiValue > RsiOversold && macdMain < macdSignal &&
                          CheckCandlestickPattern(false));

    Print("Buy Condition: ", buyCondition, " | Sell Condition: ", sellCondition);
    return buyCondition || sellCondition;
}

//+------------------------------------------------------------------+
//| Check for Bullish/Bearish Engulfing Pattern                     |
//+------------------------------------------------------------------+
bool CheckCandlestickPattern(bool isBuySignal)
{
    double openCurrent = iOpen(NULL, 0, 0);
    double closeCurrent = iClose(NULL, 0, 0);
    double openPrev = iOpen(NULL, 0, 1);
    double closePrev = iClose(NULL, 0, 1);

    if (isBuySignal)
    {
        return (closePrev < openPrev && closeCurrent > openCurrent && 
                closeCurrent > openPrev && openCurrent < closePrev);
    }
    else // Sell Signal
    {
        return (closePrev > openPrev && closeCurrent < openCurrent && 
                closeCurrent < openPrev && openCurrent > closePrev);
    }
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
    int arrowCode = (rsiValue < RsiOverbought) ? 241 : 242;
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
        Print("Trade Signal: ", (rsiValue < RsiOverbought) ? "Buy" : "Sell", " at ", TimeToString(TimeCurrent()));
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

    // Check buy condition
    if (rsiValue < RsiOverbought && emaValue1 > emaValue2 && macdMain > macdSignal && CheckCandlestickPattern(true)) // Buy condition
    {
        price = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_ASK), _Digits);
        sl = NormalizeDouble(price - StopLoss * _Point, _Digits);
        tp = NormalizeDouble(price + TakeProfit * _Point, _Digits);
        orderType = ORDER_TYPE_BUY;
    }
    // Check sell condition
    else if (rsiValue > RsiOversold && emaValue1 < emaValue2 && macdMain < macdSignal && CheckCandlestickPattern(false)) // Sell condition
    {
        price = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_BID), _Digits);
        sl = NormalizeDouble(price + StopLoss * _Point, _Digits);
        tp = NormalizeDouble(price - TakeProfit * _Point, _Digits);
        orderType = ORDER_TYPE_SELL;
    }
    else
    {
        Print("No valid trade condition met. Skipping trade.");
        return;
    }

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
//| Calculate Lot Size Based on Risk Percentage and User Input      |
//+------------------------------------------------------------------+
double CalculateLotSize()
{
    if (UserLotSize > 0)
    {
        return UserLotSize;
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
//+------------------------------------------------------------------+