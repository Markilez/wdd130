//+------------------------------------------------------------------+
//|                                                      MyExpert.mq5 |
//|                        Copyright 2025, MetaQuotes Software Corp. |
//|                                       https://www.mql5.com       |
//+------------------------------------------------------------------+
#property strict

input double TakeProfit = 50;        // Take Profit in points
input double StopLoss = 30;          // Stop Loss in points
input double TrailingStop = 20;      // Trailing Stop in points
input int MACD_Fast_EMA = 12;        // MACD Fast EMA
input int MACD_Slow_EMA = 26;        // MACD Slow EMA
input int MACD_Signal_SMA = 9;       // MACD Signal SMA
input double SAR_Acceleration = 0.02; // Parabolic SAR Acceleration
input double SAR_Maximum = 0.2;      // Parabolic SAR Maximum

// Global variables
double MACD_Main, MACD_Signal, SAR_Value;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // Initialization code
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // Cleanup code
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Calculate indicators
    if (CalculateIndicators())
    {
        // Check for trade conditions
        if (CheckTradeConditions())
        {
            OpenTrade();
        }
    }
    
    // Manage open trades
    ManageOpenTrades();
}

//+------------------------------------------------------------------+
//| Calculate indicators                                             |
//+------------------------------------------------------------------+
bool CalculateIndicators()
{
    // Get MACD values
    int macd_handle = iMACD(NULL, 0, MACD_Fast_EMA, MACD_Slow_EMA, MACD_Signal_SMA, PRICE_CLOSE);
    if (macd_handle == INVALID_HANDLE)
        return false;
    
    double macd_buffer[2];
    if (CopyBuffer(macd_handle, MAIN_LINE, 0, 2, macd_buffer) != 2)
        return false;
    MACD_Main = macd_buffer[1];
    MACD_Signal = macd_buffer[0];

    // Get Parabolic SAR value
    int sar_handle = iSAR(NULL, 0, SAR_Acceleration, SAR_Maximum);
    if (sar_handle == INVALID_HANDLE)
        return false;
    
    double sar_buffer[1];
    if (CopyBuffer(sar_handle, 0, 0, 1, sar_buffer) != 1)
        return false;
    SAR_Value = sar_buffer[0];
    
    return true;
}

//+------------------------------------------------------------------+
//| Check trade conditions                                           |
//+------------------------------------------------------------------+
bool CheckTradeConditions()
{
    // Get the latest close prices
    double close_prices[2];
    if (CopyClose(NULL, 0, 0, 2, close_prices) != 2)
        return false;

    // Buy condition: MACD crosses above signal and price is above SAR
    if (MACD_Main > MACD_Signal && close_prices[1] < SAR_Value && close_prices[0] > SAR_Value)
        return true;

    // Sell condition: MACD crosses below signal and price is below SAR
    if (MACD_Main < MACD_Signal && close_prices[1] > SAR_Value && close_prices[0] < SAR_Value)
        return true;

    return false;
}

//+------------------------------------------------------------------+
//| Open trade function                                              |
//+------------------------------------------------------------------+
void OpenTrade()
{
    double price = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_ASK), _Digits);
    double sl = NormalizeDouble(price - StopLoss * _Point, _Digits);
    double tp = NormalizeDouble(price + TakeProfit * _Point, _Digits);
    
    // Send buy order
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
    request.type = ORDER_TYPE_BUY;
    request.type_filling = ORDER_FILLING_FOK;
    request.deviation = 10;
    
    // Check the return value of OrderSend
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
        // Trade opened successfully
        Print("Trade opened successfully, ticket: ", result.order);
    }
}

//+------------------------------------------------------------------+
//| Manage open trades                                               |
//+------------------------------------------------------------------+
void ManageOpenTrades()
{
    // Implement trailing stop logic
    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if (PositionSelectByTicket(ticket))
        {
            if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
            {
                double new_sl = NormalizeDouble(PositionGetDouble(POSITION_PRICE_OPEN) + TrailingStop * _Point, _Digits);
                if (new_sl > PositionGetDouble(POSITION_SL))
                {
                    MqlTradeRequest request;
                    MqlTradeResult result;
                    ZeroMemory(request);
                    ZeroMemory(result);
                    
                    request.action = TRADE_ACTION_SLTP;
                    request.symbol = _Symbol;
                    request.sl = new_sl;
                    request.tp = PositionGetDouble(POSITION_TP);
                    request.position = ticket;
                    
                    // Check the return value of OrderSend
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
                double new_sl = NormalizeDouble(PositionGetDouble(POSITION_PRICE_OPEN) - TrailingStop * _Point, _Digits);
                if (new_sl < PositionGetDouble(POSITION_SL))
                {
                    MqlTradeRequest request;
                    MqlTradeResult result;
                    ZeroMemory(request);
                    ZeroMemory(result);
                    
                    request.action = TRADE_ACTION_SLTP;
                    request.symbol = _Symbol;
                    request.sl = new_sl;
                    request.tp = PositionGetDouble(POSITION_TP);
                    request.position = ticket;
                    
                    // Check the return value of OrderSend
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

//+------------------------------------------------------------------+
