//+------------------------------------------------------------------+
//|                                                      MyExpert.mq5 |
//|                        Copyright 2025, Markilez. |
//|                                       https://www.mql5.com       |
//+------------------------------------------------------------------+
#property strict

// Input parameters
input double TakeProfit = 500;        // Take Profit in points
input double StopLoss = 300;          // Stop Loss in points
input double TrailingStop = 20;      // Trailing Stop in points
input int EMA_Period = 144;           // EMA Period
input int RSI_Period = 14;            // RSI Period
input double RSI_Overbought = 70;    // RSI Overbought level
input double RSI_Oversold = 30;      // RSI Oversold level
input int ATR_Period = 14;           // ATR Period

// Global variables
double EMA_Value, RSI_Value, ATR_Value;

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
    // Calculate EMA
    int ema_handle = iMA(NULL, 0, EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
    if (ema_handle == INVALID_HANDLE)
    {
        Print("Failed to create EMA handle.");
        return false;
    }
    double ema_buffer[1];
    if (CopyBuffer(ema_handle, 0, 0, 1, ema_buffer) != 1)
    {
        Print("Failed to copy EMA buffer.");
        return false;
    }
    EMA_Value = ema_buffer[0];

    // Calculate RSI
    int rsi_handle = iRSI(NULL, 0, RSI_Period, PRICE_CLOSE);
    if (rsi_handle == INVALID_HANDLE)
    {
        Print("Failed to create RSI handle.");
        return false;
    }
    double rsi_buffer[1];
    if (CopyBuffer(rsi_handle, 0, 0, 1, rsi_buffer) != 1)
    {
        Print("Failed to copy RSI buffer.");
        return false;
    }
    RSI_Value = rsi_buffer[0];

    // Calculate ATR
    int atr_handle = iATR(NULL, 0, ATR_Period);
    if (atr_handle == INVALID_HANDLE)
    {
        Print("Failed to create ATR handle.");
        return false;
    }
    double atr_buffer[1];
    if (CopyBuffer(atr_handle, 0, 0, 1, atr_buffer) != 1)
    {
        Print("Failed to copy ATR buffer.");
        return false;
    }
    ATR_Value = atr_buffer[0];

    Print("EMA: ", EMA_Value, " | RSI: ", RSI_Value, " | ATR: ", ATR_Value);
    
    return true;
}

//+------------------------------------------------------------------+
//| Check trade conditions                                           |
//+------------------------------------------------------------------+
bool CheckTradeConditions()
{
    double current_price = iClose(NULL, 0, 0);

    // Buy condition: Price crosses above EMA and RSI is not overbought
    bool buyCondition = (current_price > EMA_Value && RSI_Value < RSI_Overbought);

    // Sell condition: Price crosses below EMA and RSI is not oversold
    bool sellCondition = (current_price < EMA_Value && RSI_Value > RSI_Oversold);

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

    if (iClose(NULL, 0, 0) > EMA_Value)
    {
        price = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_ASK), _Digits);
        sl = NormalizeDouble(price - ATR_Value, _Digits); // Use ATR for dynamic SL
        tp = NormalizeDouble(price + TakeProfit * _Point, _Digits);
        orderType = ORDER_TYPE_BUY;
    }
    else if (iClose(NULL, 0, 0) < EMA_Value)
    {
        price = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_BID), _Digits);
        sl = NormalizeDouble(price + ATR_Value, _Digits); // Use ATR for dynamic SL
        tp = NormalizeDouble(price - TakeProfit * _Point, _Digits);
        orderType = ORDER_TYPE_SELL;
    }

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
