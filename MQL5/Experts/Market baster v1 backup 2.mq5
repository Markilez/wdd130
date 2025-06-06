//+------------------------------------------------------------------+
//|                                                     MyExpert.mq5 |
//|                        Copyright 2025, MetaQuotes Software Corp. |
//|                                       https://www.mql5.com       |
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window

// Input parameters
input double TakeProfit = 500;            // Take Profit in points
input double StopLoss = 300;              // Stop Loss in points
input double TrailingStop = 20;           // Trailing Stop in points
input int MACD_Fast_EMA = 12;             // MACD Fast EMA
input int MACD_Slow_EMA = 26;             // MACD Slow EMA
input int MACD_Signal_SMA = 9;            // MACD Signal SMA
input int EMA_Period = 144;               // EMA Period
input int RSI_Period = 14;                // RSI Period
input double RSI_Overbought = 70;         // RSI Overbought level
input double RSI_Oversold = 30;           // RSI Oversold level
input double RiskPercentage = 1.0;        // Risk percentage of account balance
input double UserLotSize = 0.001;         // User-defined lot size
input int MagicNumber = 113010;           // Unique Magic Number for this EA
input bool ShowEntrySignals = true;       // Show buy/sell signals on chart
input bool EnableLogging = true;          // Enable logging of trade signals
input int MaxOpenPositions = 20;          // Maximum number of open positions
input double ProfitTarget = 50;            // Profit target in dollars
input int ReversalCandles = 3;            // Number of reversal candles to consider
input double TrendThreshold = 0.5;         // Trend strength threshold
input double LockInProfitThreshold = 20;   // Lock-in profit threshold in dollars

// Global variables
double MACD_Main, MACD_Signal, EMA_Value, RSI_Value;
int macd_handle, ema_handle, rsi_handle;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // Initialize indicators
    macd_handle = iMACD(NULL, 0, MACD_Fast_EMA, MACD_Slow_EMA, MACD_Signal_SMA, PRICE_CLOSE);
    ema_handle = iMA(NULL, 0, EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
    rsi_handle = iRSI(NULL, 0, RSI_Period, PRICE_CLOSE);

    if (macd_handle == INVALID_HANDLE || ema_handle == INVALID_HANDLE || rsi_handle == INVALID_HANDLE)
    {
        Print("Failed to create indicator handles.");
        return INIT_FAILED;
    }

    Print("EA initialized successfully.");
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    IndicatorRelease(macd_handle);
    IndicatorRelease(ema_handle);
    IndicatorRelease(rsi_handle);
    Print("EA deinitialized with reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Check trading conditions
    if (CalculateIndicators())
    {
        if (CheckTradeConditions() && PositionsTotal() < MaxOpenPositions)
        {
            if (ShowEntrySignals)
            {
                DrawEntrySignal();
            }
            OpenTrade();
        }
        ManageOpenTrades();
    }
}

//+------------------------------------------------------------------+
//| Calculate indicators                                             |
//+------------------------------------------------------------------+
bool CalculateIndicators()
{
    double macd_buffer[3], ema_buffer[1], rsi_buffer[1];
    if (CopyBuffer(macd_handle, 0, 0, 3, macd_buffer) != 3 ||
        CopyBuffer(ema_handle, 0, 0, 1, ema_buffer) != 1 ||
        CopyBuffer(rsi_handle, 0, 0, 1, rsi_buffer) != 1)
    {
        Print("Failed to copy indicator buffers.");
        return false;
    }

    MACD_Main = macd_buffer[0];
    MACD_Signal = macd_buffer[1];
    EMA_Value = ema_buffer[0];
    RSI_Value = rsi_buffer[0];

    Print("MACD Main: ", MACD_Main, " | MACD Signal: ", MACD_Signal, " | EMA: ", EMA_Value, " | RSI: ", RSI_Value);
    return true;
}

//+------------------------------------------------------------------+
//| Check trade conditions                                           |
//+------------------------------------------------------------------+
bool CheckTradeConditions()
{
    double current_price = iClose(NULL, 0, 0);

    // Buy condition: Price above EMA, RSI not overbought, MACD crossover
    bool buyCondition = (current_price > EMA_Value && RSI_Value < RSI_Overbought && MACD_Main > MACD_Signal);

    // Sell condition: Price below EMA, RSI not oversold, MACD crossunder
    bool sellCondition = (current_price < EMA_Value && RSI_Value > RSI_Oversold && MACD_Main < MACD_Signal);

    return buyCondition || sellCondition;
}

//+------------------------------------------------------------------+
//| Draw entry signal on chart                                       |
//+------------------------------------------------------------------+
void DrawEntrySignal()
{
    static datetime lastSignalTime = 0;
    if (TimeCurrent() == lastSignalTime)
        return;

    lastSignalTime = TimeCurrent();

    string arrowName = "EntrySignal_" + TimeToString(TimeCurrent());
    int arrowCode = (MACD_Main > MACD_Signal) ? 233 : 234; // 233 = buy, 234 = sell
    color arrowColor = (MACD_Main > MACD_Signal) ? clrGreen : clrRed;

    if (ObjectFind(0, arrowName) == -1)
    {
        ObjectCreate(0, arrowName, OBJ_ARROW, 0, TimeCurrent(), iClose(NULL, 0, 0));
        ObjectSetInteger(0, arrowName, OBJPROP_COLOR, arrowColor);
        ObjectSetInteger(0, arrowName, OBJPROP_ARROWCODE, arrowCode);
        ObjectSetInteger(0, arrowName, OBJPROP_WIDTH, 2);
    }

    if (EnableLogging)
    {
        Print("Trade Signal: ", (MACD_Main > MACD_Signal) ? "Buy" : "Sell", " at ", TimeToString(TimeCurrent()));
    }
}

//+------------------------------------------------------------------+
//| Open trade function                                              |
//+------------------------------------------------------------------+
void OpenTrade()
{
    double price = 0, sl = 0, tp = 0;
    ENUM_ORDER_TYPE orderType = ORDER_TYPE_BUY;

    if (MACD_Main > MACD_Signal)
    {
        price = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_ASK), _Digits);
        sl = NormalizeDouble(price - StopLoss * _Point, _Digits);
        tp = NormalizeDouble(price + TakeProfit * _Point, _Digits);
        orderType = ORDER_TYPE_BUY;
    }
    else if (MACD_Main < MACD_Signal)
    {
        price = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_BID), _Digits);
        sl = NormalizeDouble(price + StopLoss * _Point, _Digits);
        tp = NormalizeDouble(price - TakeProfit * _Point, _Digits);
        orderType = ORDER_TYPE_SELL;
    }

    MqlTradeRequest request;
    MqlTradeResult result;
    ZeroMemory(request);
    ZeroMemory(result);

    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = ValidateLotSize(UserLotSize); // Validate the lot size
    request.price = price;
    request.sl = sl;
    request.tp = tp;
    request.type = orderType;
    request.type_filling = ORDER_FILLING_FOK;
    request.deviation = 10;
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
    }
}

//+------------------------------------------------------------------+
//| Validate lot size against broker limits                          |
//+------------------------------------------------------------------+
double ValidateLotSize(double lotSize)
{
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    lotSize = MathMin(MathMax(lotSize, minLot), maxLot);

    return NormalizeDouble(lotSize, 2);
}

//+------------------------------------------------------------------+
//| Manage open trades                                               |
//+------------------------------------------------------------------+
void ManageOpenTrades()
{
    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if (PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
        {
            double currentProfit = PositionGetDouble(POSITION_PROFIT);
            double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);

            // Close profitable trades based on profit target
            if (currentProfit >= ProfitTarget)
            {
                CloseTrade(ticket);
            }
            // Check for trailing stop
            else if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
            {
                HandleTrailingStop(ticket, currentPrice, StopLoss);
            }
            else if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
            {
                HandleTrailingStop(ticket, currentPrice, StopLoss, true);
            }

            // Lock in profits if conditions are met
            if (currentProfit >= LockInProfitThreshold)
            {
                LockInProfit(ticket);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Handle Trailing Stops                                            |
//+------------------------------------------------------------------+
void HandleTrailingStop(ulong ticket, double currentPrice, double stopLoss, bool isSell = false)
{
    double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
    double newStopLoss;

    if (isSell)
    {
        // For sell orders, the stop loss must be above the open price
        newStopLoss = NormalizeDouble(currentPrice + (TrailingStop * _Point), _Digits);
        if (newStopLoss < PositionGetDouble(POSITION_SL))
        {
            ModifyTrade(ticket, newStopLoss);
        }
    }
    else
    {
        // For buy orders, the stop loss must be below the open price
        newStopLoss = NormalizeDouble(currentPrice - (TrailingStop * _Point), _Digits);
        if (newStopLoss > PositionGetDouble(POSITION_SL))
        {
            ModifyTrade(ticket, newStopLoss);
        }
    }
}

//+------------------------------------------------------------------+
//| Lock in profits                                                  |
//+------------------------------------------------------------------+
void LockInProfit(ulong ticket)
{
    double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
    double newStopLoss;

    if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
    {
        newStopLoss = NormalizeDouble(currentPrice - (TrailingStop * _Point), _Digits);
        if (newStopLoss > PositionGetDouble(POSITION_SL))
        {
            ModifyTrade(ticket, newStopLoss);
            Print("Locked in profit for buy trade, ticket: ", ticket);
        }
    }
    else if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
    {
        newStopLoss = NormalizeDouble(currentPrice + (TrailingStop * _Point), _Digits);
        if (newStopLoss < PositionGetDouble(POSITION_SL))
        {
            ModifyTrade(ticket, newStopLoss);
            Print("Locked in profit for sell trade, ticket: ", ticket);
        }
    }
}

//+------------------------------------------------------------------+
//| Close trade function                                             |
//+------------------------------------------------------------------+
void CloseTrade(ulong ticket)
{
    MqlTradeRequest request;
    MqlTradeResult result;
    ZeroMemory(request);
    ZeroMemory(result);

    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = PositionGetDouble(POSITION_VOLUME);
    request.position = ticket;
    request.type = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
    request.type_filling = ORDER_FILLING_FOK;
    request.deviation = 10;

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
        Print("Trade closed successfully, ticket: ", result.order);
    }
}

//+------------------------------------------------------------------+
//| Modify Trade Function                                            |
//+------------------------------------------------------------------+
void ModifyTrade(ulong ticket, double newStopLoss)
{
    MqlTradeRequest request;
    MqlTradeResult result;
    ZeroMemory(request);
    ZeroMemory(result);

    request.action = TRADE_ACTION_SLTP;
    request.symbol = _Symbol;
    request.position = ticket;
    request.sl = newStopLoss;

    if (!OrderSend(request, result))
    {
        Print("ModifyTrade failed, error code: ", GetLastError());
    }
    else if (result.retcode != TRADE_RETCODE_DONE)
    {
        Print("Trade modification request failed, retcode: ", result.retcode);
    }
}

//+------------------------------------------------------------------+
//| Check market conditions for closing trades                       |
//+------------------------------------------------------------------+
bool CheckMarketConditions()
{
    // Improved check for reversal candles
    bool isReversal = false;
    for (int i = 1; i <= ReversalCandles; i++)
    {
        if (iClose(NULL, 0, i) > iOpen(NULL, 0, i) && iClose(NULL, 0, i + 1) < iOpen(NULL, 0, i + 1))
        {
            isReversal = true;
            break;
        }
    }

    // Check trend strength
    double trendStrength = MathAbs(MACD_Main - MACD_Signal);
    bool isWeakTrend = (trendStrength < TrendThreshold);

    return isReversal || isWeakTrend;
}

//+------------------------------------------------------------------+
