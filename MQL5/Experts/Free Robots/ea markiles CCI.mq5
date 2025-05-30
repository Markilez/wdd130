//+------------------------------------------------------------------+
//|  Copyright (c) 2025 - Kinetic Vision - All rights reserved       |
//+------------------------------------------------------------------+
#property copyright "2025 - Kinetic Vision"
#property link      "https://www.kineticvision.com"
#property version   "1.00"

// Input parameters
input bool        AutoTrading = true;
input int         MagicNumber = 1000;
input ENUM_TIMEFRAMES TimeFrame = PERIOD_M1;
input int         CCI_Period1 = 14;
input int         CCI_Period2 = 14;
input int         CCI_Period3 = 14;
input double      CCI_Overbought1 = 150;
input double      CCI_Oversold1 = 0;
input int         FastMA_Period1 = 13;
input int         SlowMA_Period1 = 50;
input int         RSI_Period1 = 14;
input double      RSI_Overbought1 = 80;
input double      RSI_Oversold1 = 25;
input string      SymbolList = "GBPUSD"; // Example synthetic index

// Trading parameters
input double      LotSize = 0.01;
input double      RiskReward = 3;
input int         MaxTrades = 2;
input int         TrailingStopPips = 5;

// Strategy selection
input string      Strategy = "CCI_BOOM";

// Global variables
string Symbols[];
int cci_handle1[], cci_handle2[], cci_handle3[];
int ma_fast_handle[], ma_slow_handle[];
int rsi_handle[];

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // Split symbol list into array
    StringSplit(SymbolList, ',', Symbols);
    
    // Check if symbols are loaded correctly
    if(ArraySize(Symbols) == 0)
    {
        Print("Error: No symbols found in SymbolList.");
        return(INIT_FAILED);
    }
    
    // Resize indicator handle arrays
    ArrayResize(cci_handle1, ArraySize(Symbols));
    ArrayResize(cci_handle2, ArraySize(Symbols));
    ArrayResize(cci_handle3, ArraySize(Symbols));
    ArrayResize(ma_fast_handle, ArraySize(Symbols));
    ArrayResize(ma_slow_handle, ArraySize(Symbols));
    ArrayResize(rsi_handle, ArraySize(Symbols));
    
    // Create indicator handles for each symbol
    for(int i=0; i<ArraySize(Symbols); i++)
    {
        cci_handle1[i] = iCCI(Symbols[i], PERIOD_H1, CCI_Period1, PRICE_CLOSE);
        if(cci_handle1[i] == INVALID_HANDLE)
        {
            Print("Failed to create CCI handle for ", Symbols[i], ". Error: ", GetLastError());
            return(INIT_FAILED);
        }
        
        cci_handle2[i] = iCCI(Symbols[i], PERIOD_H4, CCI_Period2, PRICE_CLOSE);
        if(cci_handle2[i] == INVALID_HANDLE)
        {
            Print("Failed to create CCI handle for ", Symbols[i], ". Error: ", GetLastError());
            return(INIT_FAILED);
        }
        
        cci_handle3[i] = iCCI(Symbols[i], PERIOD_D1, CCI_Period3, PRICE_CLOSE);
        if(cci_handle3[i] == INVALID_HANDLE)
        {
            Print("Failed to create CCI handle for ", Symbols[i], ". Error: ", GetLastError());
            return(INIT_FAILED);
        }
        
        ma_fast_handle[i] = iMA(Symbols[i], TimeFrame, FastMA_Period1, 0, MODE_SMA, PRICE_CLOSE);
        if(ma_fast_handle[i] == INVALID_HANDLE)
        {
            Print("Failed to create MA handle for ", Symbols[i], ". Error: ", GetLastError());
            return(INIT_FAILED);
        }
        
        ma_slow_handle[i] = iMA(Symbols[i], TimeFrame, SlowMA_Period1, 0, MODE_SMA, PRICE_CLOSE);
        if(ma_slow_handle[i] == INVALID_HANDLE)
        {
            Print("Failed to create MA handle for ", Symbols[i], ". Error: ", GetLastError());
            return(INIT_FAILED);
        }
        
        rsi_handle[i] = iRSI(Symbols[i], TimeFrame, RSI_Period1, PRICE_CLOSE);
        if(rsi_handle[i] == INVALID_HANDLE)
        {
            Print("Failed to create RSI handle for ", Symbols[i], ". Error: ", GetLastError());
            return(INIT_FAILED);
        }
    }
    
    Print("EA initialized successfully.");
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Iterate through all symbols in the list
    for(int i=0; i<ArraySize(Symbols); i++)
    {
        string current_symbol = Symbols[i];
        
        // Check if maximum trades are reached
        if(CountOpenPositions() >= MaxTrades)
        {
            Print("Maximum trades reached. No new trades will be opened.");
            return;
        }
        
        // Handle trailing stops
        TrailingStop(current_symbol);
        
        // Execute strategy
        if(Strategy == "CCI_BOOM")
        {
            HandleBoomStrategy(current_symbol, LotSize, i);
        }
        else if(Strategy == "MA_CROSS")
        {
            HandleMAStrategy(current_symbol, LotSize, i);
        }
        else if(Strategy == "RSI_BREAKOUT")
        {
            HandleRSIStrategy(current_symbol, LotSize, i);
        }
    }
}

//+------------------------------------------------------------------+
//| Handle CCI Boom Strategy with Confirmation                       |
//+------------------------------------------------------------------+
void HandleBoomStrategy(string symbol, double lot, int index)
{
    double cciValue[1], fastMA[1], slowMA[1], rsiValue[1];
    
    // Get CCI value
    if(CopyBuffer(cci_handle1[index], 0, 0, 1, cciValue) != 1)
    {
        Print("Failed to copy CCI buffer for ", symbol);
        return;
    }
    
    // Get MA values
    if(CopyBuffer(ma_fast_handle[index], 0, 0, 1, fastMA) != 1 || 
       CopyBuffer(ma_slow_handle[index], 0, 0, 1, slowMA) != 1)
    {
        Print("Failed to copy MA buffer for ", symbol);
        return;
    }
    
    // Get RSI value
    if(CopyBuffer(rsi_handle[index], 0, 0, 1, rsiValue) != 1)
    {
        Print("Failed to copy RSI buffer for ", symbol);
        return;
    }
    
    // Check for multiple indicator confirmations
    bool buySignal = cciValue[0] > CCI_Overbought1 && 
                     fastMA[0] > slowMA[0] && 
                     rsiValue[0] > RSI_Oversold1;
    
    bool sellSignal = cciValue[0] < CCI_Oversold1 && 
                     fastMA[0] < slowMA[0] && 
                     rsiValue[0] < RSI_Overbought1;
    
    // Execute trade only if all indicators confirm the signal
    if(buySignal)
    {
        ExecuteTrade(symbol, ORDER_TYPE_BUY, lot);
    }
    else if(sellSignal)
    {
        ExecuteTrade(symbol, ORDER_TYPE_SELL, lot);
    }
}

//+------------------------------------------------------------------+
//| Handle MA Cross Strategy with Confirmation                       |
//+------------------------------------------------------------------+
void HandleMAStrategy(string symbol, double lot, int index)
{
    double fastMA[1], slowMA[1], cciValue[1], rsiValue[1];
    
    // Get MA values
    if(CopyBuffer(ma_fast_handle[index], 0, 0, 1, fastMA) != 1 || 
       CopyBuffer(ma_slow_handle[index], 0, 0, 1, slowMA) != 1)
    {
        Print("Failed to copy MA buffer for ", symbol);
        return;
    }
    
    // Get CCI value
    if(CopyBuffer(cci_handle1[index], 0, 0, 1, cciValue) != 1)
    {
        Print("Failed to copy CCI buffer for ", symbol);
        return;
    }
    
    // Get RSI value
    if(CopyBuffer(rsi_handle[index], 0, 0, 1, rsiValue) != 1)
    {
        Print("Failed to copy RSI buffer for ", symbol);
        return;
    }
    
    // Check for multiple indicator confirmations
    bool buySignal = fastMA[0] > slowMA[0] && 
                     cciValue[0] > CCI_Oversold1 && 
                     rsiValue[0] > RSI_Oversold1;
    
    bool sellSignal = fastMA[0] < slowMA[0] && 
                      cciValue[0] < CCI_Overbought1 && 
                      rsiValue[0] < RSI_Overbought1;
    
    // Execute trade only if all indicators confirm the signal
    if(buySignal)
    {
        ExecuteTrade(symbol, ORDER_TYPE_BUY, lot);
    }
    else if(sellSignal)
    {
        ExecuteTrade(symbol, ORDER_TYPE_SELL, lot);
    }
}

//+------------------------------------------------------------------+
//| Handle RSI Breakout Strategy with Confirmation                   |
//+------------------------------------------------------------------+
void HandleRSIStrategy(string symbol, double lot, int index)
{
    double rsiValue[1], cciValue[1], fastMA[1], slowMA[1];
    
    // Get RSI value
    if(CopyBuffer(rsi_handle[index], 0, 0, 1, rsiValue) != 1)
    {
        Print("Failed to copy RSI buffer for ", symbol);
        return;
    }
    
    // Get CCI value
    if(CopyBuffer(cci_handle1[index], 0, 0, 1, cciValue) != 1)
    {
        Print("Failed to copy CCI buffer for ", symbol);
        return;
    }
    
    // Get MA values
    if(CopyBuffer(ma_fast_handle[index], 0, 0, 1, fastMA) != 1 || 
       CopyBuffer(ma_slow_handle[index], 0, 0, 1, slowMA) != 1)
    {
        Print("Failed to copy MA buffer for ", symbol);
        return;
    }
    
    // Check for multiple indicator confirmations
    bool buySignal = rsiValue[0] < RSI_Oversold1 && 
                     cciValue[0] > CCI_Oversold1 && 
                     fastMA[0] > slowMA[0];
    
    bool sellSignal = rsiValue[0] > RSI_Overbought1 && 
                      cciValue[0] < CCI_Overbought1 && 
                      fastMA[0] < slowMA[0];
    
    // Execute trade only if all indicators confirm the signal
    if(buySignal)
    {
        ExecuteTrade(symbol, ORDER_TYPE_BUY, lot);
    }
    else if(sellSignal)
    {
        ExecuteTrade(symbol, ORDER_TYPE_SELL, lot);
    }
}

//+------------------------------------------------------------------+
//| Execute Trade (MQL5 version)                                     |
//+------------------------------------------------------------------+
void ExecuteTrade(string symbol, ENUM_ORDER_TYPE orderType, double lot)
{
    MqlTradeRequest request = {};
    MqlTradeResult result = {};
    
    request.action = TRADE_ACTION_DEAL;
    request.symbol = symbol;
    request.volume = lot;
    request.type = orderType;
    request.price = (orderType == ORDER_TYPE_BUY) ? SymbolInfoDouble(symbol, SYMBOL_ASK) 
                                                 : SymbolInfoDouble(symbol, SYMBOL_BID);
    request.deviation = 5;
    request.magic = MagicNumber;
    
    // Calculate stop loss and take profit
    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    if(orderType == ORDER_TYPE_BUY)
    {
        request.sl = request.price - 100 * point;
        request.tp = request.price + 100 * point * RiskReward;
    }
    else
    {
        request.sl = request.price + 100 * point;
        request.tp = request.price - 100 * point * RiskReward;
    }
    
    if(!OrderSend(request, result))
    {
        Print("OrderSend failed: ", GetLastError());
    }
    else
    {
        Print("Order placed successfully, ticket: ", result.order);
    }
}

//+------------------------------------------------------------------+
//| Trailing Stop Function                                           |
//+------------------------------------------------------------------+
void TrailingStop(string symbol)
{
    for(int i=PositionsTotal()-1; i>=0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket > 0 && PositionGetInteger(POSITION_MAGIC) == MagicNumber && PositionGetString(POSITION_SYMBOL) == symbol)
        {
            double currentSL = PositionGetDouble(POSITION_SL);
            double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
            double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
            {
                double newSL = currentPrice - TrailingStopPips * point;
                if(newSL > currentSL || currentSL == 0.0)
                {
                    ModifySL(ticket, newSL);
                }
            }
            else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
            {
                double newSL = currentPrice + TrailingStopPips * point;
                if(newSL < currentSL || currentSL == 0.0)
                {
                    ModifySL(ticket, newSL);
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Modify Stop Loss                                                 |
//+------------------------------------------------------------------+
void ModifySL(ulong ticket, double newSL)
{
    MqlTradeRequest request = {};
    MqlTradeResult result = {};
    request.action = TRADE_ACTION_SLTP;
    request.position = ticket;
    request.sl = newSL;
    request.magic = MagicNumber;
    if(!OrderSend(request, result))
    {
        Print("Trailing stop failed: ", GetLastError());
    }
}

//+------------------------------------------------------------------+
//| Count Open Positions                                             |
//+------------------------------------------------------------------+
int CountOpenPositions()
{
    int count = 0;
    for(int i=PositionsTotal()-1; i>=0; i--)
    {
        if(PositionGetInteger(POSITION_MAGIC) == MagicNumber)
        {
            count++;
        }
    }
    return count;
}
