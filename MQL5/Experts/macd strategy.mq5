//+------------------------------------------------------------------+
//|                                                      MyExpert.mq5 |
//|                        Copyright 2025, MetaQuotes Software Corp. |
//|                                       https://www.mql5.com       |
//+------------------------------------------------------------------+
#property strict

// Input parameters
input double TakeProfit = 500;        // Take Profit in points
input double StopLoss = 300;          // Stop Loss in points
input double TrailingStop = 20;      // Trailing Stop in points
input int MACD_Fast_EMA = 12;          // MACD Fast EMA
input int MACD_Slow_EMA = 26;          // MACD Slow EMA
input int MACD_Signal_SMA = 9;         // MACD Signal SMA
input int MagicNumber = 1139;           // Unique Magic Number for this EA

// Global variables
double MACD_Main, MACD_Signal;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    Print("EA initialized successfully.");
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    Print("EA deinitialized with reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    Print("OnTick() called at: ", TimeCurrent());

    if (CalculateIndicators())
    {
        Print("Indicators calculated successfully.");
        if (CheckTradeConditions())
        {
            Print("Trade conditions met. Opening trade...");
            OpenTrade();
        }
        else
        {
            Print("Trade conditions not met.");
        }
    }
    else
    {
        Print("Failed to calculate indicators.");
    }
    
    ManageOpenTrades();
}

//+------------------------------------------------------------------+
//| Calculate indicators                                             |
//+------------------------------------------------------------------+
bool CalculateIndicators()
{
    int macd_handle = iMACD(NULL, 0, MACD_Fast_EMA, MACD_Slow_EMA, MACD_Signal_SMA, PRICE_CLOSE);
    if (macd_handle == INVALID_HANDLE)
    {
        Print("Failed to create MACD handle.");
        return false;
    }
    
    double macd_buffer[3]; // Adjusted to hold all necessary values
    if (CopyBuffer(macd_handle, 0, 0, 3, macd_buffer) != 3) // Copying 3 values
    {
        Print("Failed to copy MACD buffer.");
        return false;
    }
    MACD_Main = macd_buffer[0];
    MACD_Signal = macd_buffer[1];

    Print("MACD Main: ", MACD_Main, " | MACD Signal: ", MACD_Signal);
    
    return true;
}

//+------------------------------------------------------------------+
//| Check trade conditions                                           |
//+------------------------------------------------------------------+
bool CheckTradeConditions()
{
    static double prev_MACD_Main = 0;
    static double prev_MACD_Signal = 0;

    bool buyCondition = (prev_MACD_Main <= prev_MACD_Signal && MACD_Main > MACD_Signal);
    bool sellCondition = (prev_MACD_Main >= prev_MACD_Signal && MACD_Main < MACD_Signal);

    prev_MACD_Main = MACD_Main;
    prev_MACD_Signal = MACD_Signal;

    return buyCondition || sellCondition;
}

//+------------------------------------------------------------------+
//| Open trade function                                              |
//+------------------------------------------------------------------+
void OpenTrade()
{
    double price = 0;
    double sl = 0;
    double tp = 0;
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

    // Debugging logs
    Print("Opening trade - Price: ", price, " | SL: ", sl, " | TP: ", tp, " | Order Type: ", EnumToString(orderType));

    MqlTradeRequest request;
    MqlTradeResult result;
    ZeroMemory(request);
    ZeroMemory(result);
    
    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = 0.1;
    request.price = price;
    request.sl = sl;
    request.tp = tp;
    request.type = orderType;
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
        Print("Trade opened successfully, ticket: ", result.order);
    }
}

//+------------------------------------------------------------------+
//| Manage open trades                                               |
//+------------------------------------------------------------------+
void ManageOpenTrades()
{
    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if (PositionSelectByTicket(ticket))
        {
            double currentProfit = PositionGetDouble(POSITION_PROFIT);
            double tp = PositionGetDouble(POSITION_TP);
            double sl = PositionGetDouble(POSITION_SL);
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);

            // Check if profit is 50% closer to TP
            if (currentProfit >= (tp - openPrice) * 0.5)
            {
                if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
                {
                    double new_sl = NormalizeDouble(currentPrice - TrailingStop * _Point, _Digits);
                    if (new_sl > sl)
                    {
                        MqlTradeRequest request;
                        MqlTradeResult result;
                        ZeroMemory(request);
                        ZeroMemory(result);
                        
                        request.action = TRADE_ACTION_SLTP;
                        request.symbol = _Symbol;
                        request.sl = new_sl;
                        request.tp = tp;
                        request.position = ticket;
                        
                        if (!OrderSend(request, result))
                        {
                            Print("OrderSend failed, error code: ", GetLastError());
                        }
                        else if (result.retcode != TRADE_RETCODE_DONE)
                        {
                            Print("Trade request failed, retcode: ", result.retcode);
                        }
                    }
                }
                else if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
                {
                    double new_sl = NormalizeDouble(currentPrice + TrailingStop * _Point, _Digits);
                    if (new_sl < sl)
                    {
                        MqlTradeRequest request;
                        MqlTradeResult result;
                        ZeroMemory(request);
                        ZeroMemory(result);
                        
                        request.action = TRADE_ACTION_SLTP;
                        request.symbol = _Symbol;
                        request.sl = new_sl;
                        request.tp = tp;
                        request.position = ticket;
                        
                        if (!OrderSend(request, result))
                        {
                            Print("OrderSend failed, error code: ", GetLastError());
                        }
                        else if (result.retcode != TRADE_RETCODE_DONE)
                        {
                            Print("Trade request failed, retcode: ", result.retcode);
                        }
                    }
                }
            }
        }
    }
}

//+------------------------------------------------------------------+

