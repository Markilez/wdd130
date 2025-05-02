//+------------------------------------------------------------------+
//|                                                      MyExpert.mq5 |
//|                        Copyright 2025, MetaQuotes Software Corp. |
//|                                       https://www.mql5.com       |
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window

// Input parameters
input double TakeProfit = 500;            // Take Profit in points
input double StopLoss = 300;              // Stop Loss in points
input int MACD_Fast_EMA = 12;             // MACD Fast EMA
input int MACD_Slow_EMA = 26;             // MACD Slow EMA
input int MACD_Signal_SMA = 9;            // MACD Signal SMA
input int EMA_Period1 = 144;              // First EMA Period
input int EMA_Period2 = 50;               // Second EMA Period
input int EMA_Period3 = 200;              // Third EMA Period (200 EMA)
input int RSI_Period = 14;                // RSI Period
input double RSI_Overbought = 70;         // RSI Overbought level
input double RSI_Oversold = 30;           // RSI Oversold level
input double RiskPercentage = 1.0;        // Risk percentage of account balance
input double UserLotSize = 0.0;           // User-defined lot size (set to 0 to use default 0.001)
input int MagicNumber = 1135710;          // Unique Magic Number for this EA
input bool ShowEntrySignals = true;       // Show buy/sell signals on chart
input bool EnableLogging = true;           // Enable logging of trade signals
input int MaxOpenPositions = 50;           // Maximum number of open positions
input double ProfitTarget = 5;              // Profit target in dollars
input int ReversalCandles = 3;             // Number of reversal candles to consider
input double TrendThreshold = 0.5;         // Trend strength threshold
input double LockInProfitThreshold = 20;   // Lock-in profit threshold in dollars
input int TrailingStopDelaySeconds = 300;  // Delay in seconds before trailing stop is activated
input int TrailingStopDelayTicks = 10;     // Delay in ticks before trailing stop is activated
input int TrendFilterPeriod = 200;         // Period for trend filter
input bool EnableAlerts = true;            // Enable alerts for trade signals
input double TrailingStop = 20;            // Trailing Stop in points

// Global variables
double MACD_Main, MACD_Signal, EMA_Value1, EMA_Value2, EMA_Value3, RSI_Value;
int macd_handle, ema_handle1, ema_handle2, ema_handle3, rsi_handle;

// Struct to store trade details
struct TradeInfo
{
    datetime openTime; // Time when the trade was opened
    double openPrice;  // Price at which the trade was opened
    double takeProfit; // Take Profit level for the trade
};

// Map to store trade details
ulong tradeTickets[]; // Array to store trade tickets
TradeInfo tradeDetails[]; // Array to store trade details

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // Initialize indicators
    macd_handle = iMACD(NULL, 0, MACD_Fast_EMA, MACD_Slow_EMA, MACD_Signal_SMA, PRICE_CLOSE);
    ema_handle1 = iMA(NULL, 0, EMA_Period1, 0, MODE_EMA, PRICE_CLOSE);
    ema_handle2 = iMA(NULL, 0, EMA_Period2, 0, MODE_EMA, PRICE_CLOSE);
    ema_handle3 = iMA(NULL, 0, EMA_Period3, 0, MODE_EMA, PRICE_CLOSE);
    rsi_handle = iRSI(NULL, 0, RSI_Period, PRICE_CLOSE);

    if (macd_handle == INVALID_HANDLE || ema_handle1 == INVALID_HANDLE || 
        ema_handle2 == INVALID_HANDLE || ema_handle3 == INVALID_HANDLE || 
        rsi_handle == INVALID_HANDLE)
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
    IndicatorRelease(ema_handle1);
    IndicatorRelease(ema_handle2);
    IndicatorRelease(ema_handle3);
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
        if (CheckSwingTradeConditions() && PositionsTotal() < MaxOpenPositions)
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
    double macd_buffer[3], ema_buffer1[1], ema_buffer2[1], ema_buffer3[1], rsi_buffer[1];
    if (CopyBuffer(macd_handle, 0, 0, 3, macd_buffer) != 3 ||
        CopyBuffer(ema_handle1, 0, 0, 1, ema_buffer1) != 1 ||
        CopyBuffer(ema_handle2, 0, 0, 1, ema_buffer2) != 1 ||
        CopyBuffer(ema_handle3, 0, 0, 1, ema_buffer3) != 1 ||
        CopyBuffer(rsi_handle, 0, 0, 1, rsi_buffer) != 1)
    {
        Print("Failed to copy indicator buffers.");
        return false;
    }

    MACD_Main = macd_buffer[0];
    MACD_Signal = macd_buffer[1];
    EMA_Value1 = ema_buffer1[0];
    EMA_Value2 = ema_buffer2[0];
    EMA_Value3 = ema_buffer3[0];
    RSI_Value = rsi_buffer[0];

    Print("MACD Main: ", MACD_Main, " | MACD Signal: ", MACD_Signal, 
          " | EMA1: ", EMA_Value1, " | EMA2: ", EMA_Value2, 
          " | EMA3: ", EMA_Value3, " | RSI: ", RSI_Value);
    return true;
}

//+------------------------------------------------------------------+
//| Check swing trade conditions                                     |
//+------------------------------------------------------------------+
bool CheckSwingTradeConditions()
{
    double currentPrice = iClose(NULL, 0, 0);
    bool buyCondition = (currentPrice > EMA_Value1 && currentPrice > EMA_Value2 && 
                         currentPrice > EMA_Value3 && RSI_Value < RSI_Overbought && 
                         MACD_Main > MACD_Signal);
    bool sellCondition = (currentPrice < EMA_Value1 && currentPrice < EMA_Value2 && 
                          currentPrice < EMA_Value3 && RSI_Value > RSI_Oversold && 
                          MACD_Main < MACD_Signal);

    return buyCondition || sellCondition; // Return true if either condition is met
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

    string arrowName = "SwingSignal_" + TimeToString(TimeCurrent());
    int arrowCode = (MACD_Main > MACD_Signal) ? 241 : 242; // 241 = buy, 242 = sell
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
        Print("Swing Trade Signal: ", (MACD_Main > MACD_Signal) ? "Buy" : "Sell", 
              " at ", TimeToString(TimeCurrent()));
    }
}

//+------------------------------------------------------------------+
//| Open trade function                                              |
//+------------------------------------------------------------------+
void OpenTrade()
{
    double price, sl, tp;
    ENUM_ORDER_TYPE orderType;

    if (MACD_Main > MACD_Signal)
    {
        price = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_ASK), _Digits);
        sl = NormalizeDouble(price - StopLoss * _Point, _Digits);
        tp = NormalizeDouble(price + TakeProfit * _Point, _Digits);
        orderType = ORDER_TYPE_BUY;
    }
    else
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
    request.volume = ValidateLotSize(UserLotSize > 0 ? UserLotSize : 0.001); // Use user-defined lot size or default 0.001
    request.price = price;
    request.sl = sl;
    request.tp = tp;
    request.type = orderType;
    request.type_filling = ORDER_FILLING_FOK;

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
        // Store trade details
        StoreTradeDetails(result.order, price, tp);
    }
}

//+------------------------------------------------------------------+
//| Validate lot size against broker limits                          |
//+------------------------------------------------------------------+
double ValidateLotSize(double lotSize)
{
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    return MathMax(lotSize, minLot); // Ensure lot size is not below the minimum allowed
}

//+------------------------------------------------------------------+
//| Store trade details                                             |
//+------------------------------------------------------------------+
void StoreTradeDetails(ulong ticket, double price, double tp)
{
    int size = ArraySize(tradeTickets);
    ArrayResize(tradeTickets, size + 1);
    ArrayResize(tradeDetails, size + 1);
    tradeTickets[size] = ticket;
    tradeDetails[size].openTime = TimeCurrent();
    tradeDetails[size].openPrice = price;
    tradeDetails[size].takeProfit = tp;
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

            // Handle trailing stop if applicable
            HandleTrailingStop(ticket, currentPrice);
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
void HandleTrailingStop(ulong ticket, double currentPrice)
{
    double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
    double newStopLoss;

    if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
    {
        newStopLoss = NormalizeDouble(currentPrice - (TrailingStop * _Point), _Digits);
        if (newStopLoss > PositionGetDouble(POSITION_SL))
        {
            ModifyTrade(ticket, newStopLoss);
        }
    }
    else
    {
        newStopLoss = NormalizeDouble(currentPrice + (TrailingStop * _Point), _Digits);
        if (newStopLoss < PositionGetDouble(POSITION_SL))
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
    else
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
//| Array Search Function                                            |
//+------------------------------------------------------------------+
int ArraySearch(const ulong &array[], ulong value)
{
    for (int i = 0; i < ArraySize(array); i++)
    {
        if (array[i] == value)
        {
            return i;
        }
    }
    return -1;
}
