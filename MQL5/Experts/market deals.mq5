//+------------------------------------------------------------------+
//|                                                      MyExpert.mq5 |
//|                        Copyright 2025, MetaQuotes Software Corp. |
//|                                       https://www.mql5.com       |
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window

// Input parameters
input double TakeProfit = 500;            // Take Profit in points
input double StopLoss = 500;              // Stop Loss in points
input int EMA_Period1 = 50;               // 50 EMA Period
input int EMA_Period2 = 200;              // Corrected 200 EMA Period (was previously EMA_Per极iod2)
input int RSI_Period = 14;                // RSI Period
input double RSI_Overbought = 70;         // RSI Overbought level
input double RSI_Oversold = 30;           // RSI Oversold level
input int ATR_Period = 14;                // ATR Period
input int ADX_Period = 14;                // ADX Period
input double ADX_Threshold = 25;          // ADX threshold for trend strength
input double RiskPercentage = 1.0;        // Risk percentage of account balance
input double UserLotSize = 0.0;           // User-defined lot size (set to 0 to use default 0.001)

// Updated MagicNumber to a valid range for int
input int MagicNumber = 1456;           // Unique Magic Number for this EA
input bool ShowEntrySignals = true;       // Show buy/sell signals on chart
input bool EnableLogging = true;          // Enable logging of trade signals
input bool UseEADefinedStopLoss = false;    // Enable/disable EA-defined stop loss
input int MaxOpenPositions = 5;           // Maximum number of open positions
input double ProfitTarget = 5;            // Profit target in dollars
input double LockInProfitThreshold = 20;  // Lock-in profit threshold in dollars
input int TrailingStopDelaySeconds = 300; // Delay in seconds before trailing stop is activated
input double TrailingStop = 20;           // Trailing Stop in points
input bool EnableTrailingStop = false;     // Enable or disable trailing stop feature
input int TradeCooldownSeconds = 150;     // Cooldown period between trades in seconds

// Global variables
double EMA_Value1, EMA_Value2, RSI_Value, ATR_Value, ADX_Value;
int ema_handle1, ema_handle2, rsi_handle, atr_handle, adx_handle;
long chartID; // Store the chart ID
datetime lastTradeTime = 0; // Time of the last trade

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
    // Store the chart ID
    chartID = ChartID();

    // Initialize indicators
    ema_handle1 = iMA(NULL, 0, EMA_Period1, 0, MODE_EMA, PRICE_CLOSE);
    ema_handle2 = iMA(NULL, 0, EMA_Period2, 0, MODE_EMA, PRICE_CLOSE);
    rsi_handle = iRSI(NULL, 0, RSI_Period, PRICE_CLOSE);
    atr_handle = iATR(NULL, 0, ATR_Period);
    adx_handle = iADX(NULL, 0, ADX_Period);

    if (ema_handle1 == INVALID_HANDLE || ema_handle2 == INVALID_HANDLE || 
        rsi_handle == INVALID_HANDLE || atr_handle == INVALID_HANDLE || 
        adx_handle == INVALID_HANDLE)
    {
        Print("Failed to create indicator handles.");
        return INIT_FAILED;
    }

    Print("EA initialized successfully on chart ID: ", chartID);
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    IndicatorRelease(ema_handle1);
    IndicatorRelease(ema_handle2);
    IndicatorRelease(rsi_handle);
    IndicatorRelease(atr_handle);
    IndicatorRelease(adx_handle);
    Print("EA deinitialized with reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Ensure the EA only runs on the chart it was attached to
    if (ChartID() != chartID)
    {
        Print("EA is running on a different chart. Exiting OnTick().");
        return;
    }

    // Check trading conditions
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
        ManageOpenTrades();
    }
}

//+------------------------------------------------------------------+
//| Calculate indicators                                             |
//+------------------------------------------------------------------+
bool CalculateIndicators()
{
    double ema_buffer1[1], ema_buffer2[1], rsi_buffer[1], atr_buffer[1], adx_buffer[1];
    if (CopyBuffer(ema_handle1, 0, 0, 1, ema_buffer1) != 1 ||
        CopyBuffer(ema_handle2, 0, 0, 1, ema_buffer2) != 1 ||
        CopyBuffer(rsi_handle, 0, 0, 1, rsi_buffer) != 1 ||
        CopyBuffer(atr_handle, 0, 0, 1, atr_buffer) != 1 ||
        CopyBuffer(adx_handle, 0, 0, 1, adx_buffer) != 1)
    {
        Print("Failed to copy indicator buffers.");
        return false;
    }

    EMA_Value1 = ema_buffer1[0];
    EMA_Value2 = ema_buffer2[0];
    RSI_Value = rsi_buffer[0];
    ATR_Value = atr_buffer[0];
    ADX_Value = adx_buffer[0];

    Print("EMA1 (50): ", EMA_Value1, " | EMA2 (200): ", EMA_Value2, 
          " | RSI: ", RSI_Value, " | ATR: ", ATR_Value, " | ADX: ", ADX_Value);
    return true;
}

//+------------------------------------------------------------------+
//| Check trade conditions                                           |
//+------------------------------------------------------------------+
bool CheckTradeConditions()
{
    double currentPrice = iClose(NULL, 0, 0);
    bool buyCondition = (currentPrice > EMA_Value1 && currentPrice > EMA_Value2 && 
                         RSI_Value < RSI_Overbought && ADX_Value > ADX_Threshold);
    bool sellCondition = (currentPrice < EMA_Value1 && currentPrice < EMA_Value2 && 
                          RSI_Value > RSI_Oversold && ADX_Value > ADX_Threshold);

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

    string arrowName = "TradeSignal_" + TimeToString(TimeCurrent());
    int arrowCode = (RSI_Value < RSI_Overbought) ? 241 : 242; // 241 = buy, 242 = sell
    color arrowColor = (RSI_Value < RSI_Overbought) ? clrGreen : clrRed;

    if (ObjectFind(0, arrowName) == -1)
    {
        ObjectCreate(0, arrowName, OBJ_ARROW, 0, TimeCurrent(), iClose(NULL, 0, 0));
        ObjectSetInteger(0, arrowName, OBJPROP_COLOR, arrowColor);
        ObjectSetInteger(0, arrowName, OBJPROP_ARROWCODE, arrowCode);
        ObjectSetInteger(0, arrowName, OBJPROP_WIDTH, 2);
    }

    if (EnableLogging)
    {
        Print("Trade Signal: ", (RSI_Value < RSI_Overbought) ? "Buy" : "Sell", 
              " at ", TimeToString(TimeCurrent()));
    }
}

//+------------------------------------------------------------------+
//| Open trade function                                              |
//+------------------------------------------------------------------+
void OpenTrade()
{
    // Check if the cooldown period has passed
    if (TimeCurrent() - lastTradeTime < TradeCooldownSeconds)
    {
        Print("Trade cooldown active. Skipping trade.");
        return;
    }

    double price, sl, tp;
    ENUM_ORDER_TYPE orderType;

    if (RSI_Value < RSI_Overbought)
    {
        price = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_ASK), _Digits);
        // Use EA-defined stop loss if enabled, otherwise use user-defined stop loss
        sl = UseEADefinedStopLoss ? NormalizeDouble(price - (ATR_Value * 2), _Digits) : NormalizeDouble(price - StopLoss * _Point, _Digits);
        tp = NormalizeDouble(price + TakeProfit * _Point, _Digits);
        orderType = ORDER_TYPE_BUY;
    }
    else
    {
        price = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_BID), _Digits);
        // Use EA-defined stop loss if enabled, otherwise use user-defined stop loss
        sl = UseEADefinedStopLoss ? NormalizeDouble(price + (ATR_Value * 2), _Digits) : NormalizeDouble(price + StopLoss * _Point, _Digits);
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
    request.magic = MagicNumber; // Use the unique Magic Number for this EA

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
        lastTradeTime = TimeCurrent(); // Update the last trade time
        StoreTradeDetails(result.order, price, tp);
        PrintMarketDeals(); // Print market deals after every trade
    }
}

//+------------------------------------------------------------------+
//| Print market deals                                               |
//+------------------------------------------------------------------+
void PrintMarketDeals()
{
    HistorySelect(0, TimeCurrent());
    int totalDeals = HistoryDealsTotal();
    for (int i = 0; i < totalDeals; i++)
    {
        ulong dealTicket = HistoryDealGetTicket(i);
        if (HistoryDealGetInteger(dealTicket, DEAL_MAGIC) == MagicNumber)
        {
            Print("Deal Ticket: ", dealTicket, 
                  " | Symbol: ", HistoryDealGetString(dealTicket, DEAL_SYMBOL), 
                  " | Type: ", (HistoryDealGetInteger(dealTicket, DEAL_TYPE) == DEAL_TYPE_BUY) ? "Buy" : "Sell", 
                  " | Volume: ", HistoryDealGetDouble(dealTicket, DEAL_VOLUME), 
                  " | Price: ", HistoryDealGetDouble(dealTicket, DEAL_PRICE), 
                  " | Profit: ", HistoryDealGetDouble(dealTicket, DEAL_PROFIT));
        }
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
//| Count open positions for the current symbol                      |
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
//| Manage open trades                                               |
//+------------------------------------------------------------------+
void ManageOpenTrades()
{
    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if (PositionSelectByTicket(ticket) && 
            PositionGetString(POSITION_SYMBOL) == _Symbol && 
            PositionGetInteger(POSITION_MAGIC) == MagicNumber)
        {
            double currentProfit = PositionGetDouble(POSITION_PROFIT);
            double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);

            // Close profitable trades based on profit target
            if (currentProfit >= ProfitTarget)
            {
                CloseTrade(ticket);
            }

            // Handle trailing stop if applicable
            if (EnableTrailingStop)
            {
                HandleTrailingStop(ticket, currentPrice);
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