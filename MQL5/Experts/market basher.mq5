//+------------------------------------------------------------------+
//|                                                      Scalper.mq5 |
//|                        Copyright 2025, Markilez.                  |
//|                                       https://www.mql5.com       |
//+------------------------------------------------------------------+
#property strict

// Input parameters
input double TakeProfit = 1000;            // Take Profit in points (tight for scalping)
input double StopLoss = 5000;               // Stop Loss in points (tight for scalping)
input double TrailingStop = 10;           // Trailing Stop in points (tight for scalping)
input int EMA_Period = 50;                // EMA Period (shorter for scalping)
input int RSI_Period = 10;                // RSI Period (shorter for scalping)
input double RSI_Overbought = 70;         // RSI Overbought level
input double RSI_Oversold = 30;           // RSI Oversold level
input int ATR_Period = 14;                // ATR Period
input double LotSize = 0.1;               // Fixed lot size for scalping
input int MaxPositions = 5;               // Maximum open positions
input int PauseAfterProfit = 60;          // Pause duration in seconds after a profitable trade
input int MagicNumber = 674534;           // Unique Magic Number for this EA

// Global variables
double EMA_Value, RSI_Value, ATR_Value;
datetime LastProfitableTradeTime = 0;     // Timestamp of the last profitable trade
bool ConfirmationReceived = false;         // Flag to track if confirmation is received

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
    // Check if the EA is in a pause state after a profitable trade
    if (LastProfitableTradeTime > 0 && TimeCurrent() - LastProfitableTradeTime < PauseAfterProfit)
    {
        Print("EA is paused after a profitable trade.");
        return;
    }

    Print("OnTick() called at: ", TimeCurrent());

    if (CalculateIndicators())
    {
        Print("Indicators calculated successfully.");
        bool conditionsMet = CheckTradeConditions();
        if (conditionsMet)
        {
            if (!ConfirmationReceived)
            {
                Print("Trade conditions met. Waiting for confirmation...");
                ConfirmationReceived = true; // Set confirmation to true
            }
            else
            {
                Print("Confirmation received. Opening trade...");
                OpenTrade();
                ConfirmationReceived = false; // Reset confirmation flag
            }
        }
        else
        {
            Print("Trade conditions not met. Managing open trades...");
            ManageOpenTrades();
        }
    }
    else
    {
        Print("Failed to calculate indicators.");
    }
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
    double current_price = iClose(_Symbol, 0, 0);

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
    // Check if the maximum number of positions has been reached
    if (PositionsTotal() >= MaxPositions)
    {
        Print("Maximum number of positions reached. Cannot open a new trade.");
        return;
    }

    // Open the trade
    double price = 0;
    double sl = 0;
    double tp = 0;
    ENUM_ORDER_TYPE orderType = ORDER_TYPE_BUY;

    if (iClose(_Symbol, 0, 0) > EMA_Value)
    {
        price = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_ASK), _Digits);
        sl = NormalizeDouble(price - StopLoss * _Point, _Digits);
        tp = NormalizeDouble(price + TakeProfit * _Point, _Digits);
        orderType = ORDER_TYPE_BUY;
    }
    else if (iClose(_Symbol, 0, 0) < EMA_Value)
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
    request.volume = LotSize; // Fixed lot size for scalping
    request.price = price;
    request.sl = sl;
    request.tp = tp;
    request.type = orderType;
    request.type_filling = ORDER_FILLING_FOK;
    request.deviation = 10;
    request.magic = MagicNumber; // Assign the Magic Number
    request.comment = "Scalper V2"; // Add the comment here

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
            // Filter trades by Magic Number
            if (PositionGetInteger(POSITION_MAGIC) != MagicNumber)
            {
                continue; // Skip trades not opened by this EA
            }

            double currentProfit = PositionGetDouble(POSITION_PROFIT);
            double tp = PositionGetDouble(POSITION_TP);
            double sl = PositionGetDouble(POSITION_SL);
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);

            // Adjust trailing stop
            AdjustTrailingStop(ticket, sl, tp, openPrice, currentPrice);

            // Check if the position is closed and profitable
            if (currentProfit > 0)
            {
                LastProfitableTradeTime = TimeCurrent(); // Update the timestamp of the last profitable trade
                Print("Profitable trade active. Current profit: ", currentProfit);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Adjust trailing stop function                                     |
//+------------------------------------------------------------------+
void AdjustTrailingStop(ulong ticket, double sl, double tp, double openPrice, double currentPrice)
{
    if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
    {
        double new_sl = NormalizeDouble(currentPrice - TrailingStop * _Point, _Digits);
        if (new_sl > sl && new_sl > openPrice) // Ensure the new SL is in profit
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
        if (new_sl < sl && new_sl < openPrice) // Ensure the new SL is in profit
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

//+------------------------------------------------------------------+
