//+------------------------------------------------------------------+
//|  Copyright (c) 2023  - Your Name  - All rights reserved           |
//+------------------------------------------------------------------+
#property copyright "2023 - Your Name"
#property link      "https://www.yourwebsite.com"
#property version   "1.00"

// Input parameters
input bool        AutoTrading = true;
input int         MagicNumber = 1000;
input int         SymbolSelect = 0;
input ENUM_TIMEFRAMES TimeFrame = PERIOD_M1;
input int         CCI_Period1 = 14;
input int         CCI_Period2 = 14;
input int         CCI_Period3 = 14;

input double      CCI_Overbought1 = 150;
input double      CCI_Oversold1 = 0;
input int         FastMA_Period1 = 21;
input int         SlowMA_Period1 = 50;
input int         RSI_Period1 = 14;
input double      RSI_Overbought1 = 70;
input double      RSI_Oversold1 = 30;
input string      SymbolList = "EURUSD,GBPUSD,USDJPY,V75";

// Bollinger Bands parameters
input int         BB_Period = 20;
input double      BB_Deviation = 2.0;

// Trading parameters
input double      LotSize = 0.01;
input double      RiskReward = 3;
input int         MaxTrades = 5;
input int         StopLossPips = 100;       // Stop loss in points
input int         TrailingStopPips = 50;    // Trailing stop distance

// Strategy selection
input string      Strategy = "CCI_BOOM";

// Global variables
string Symbols[];
int cci_handle1, cci_handle2, cci_handle3;
int ma_fast_handle, ma_slow_handle;
int rsi_handle;
int bb_handle;

//+------------------------------------------------------------------+
//|  Forward Declarations                                            |
//+------------------------------------------------------------------+
void HandleBoomStrategy(string symbol, double lotSize);
void HandleMAStrategy(string symbol, double lotSize);
void HandleRSIStrategy(string symbol, double lotSize);
void HandleBBStrategy(string symbol, double lotSize);

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // Split symbol list into array
    StringSplit(SymbolList, ',', Symbols);

    // Create indicator handles
    if(ArraySize(Symbols) > 0)
    {
        cci_handle1 = iCCI(Symbols[SymbolSelect], PERIOD_H1, CCI_Period1, PRICE_CLOSE);
        cci_handle2 = iCCI(Symbols[SymbolSelect], PERIOD_H4, CCI_Period2, PRICE_CLOSE);
        cci_handle3 = iCCI(Symbols[SymbolSelect], PERIOD_D1, CCI_Period3, PRICE_CLOSE);

        ma_fast_handle = iMA(Symbols[SymbolSelect], TimeFrame, FastMA_Period1, 0, MODE_SMA, PRICE_CLOSE);
        ma_slow_handle = iMA(Symbols[SymbolSelect], TimeFrame, SlowMA_Period1, 0, MODE_SMA, PRICE_CLOSE);

        rsi_handle = iRSI(Symbols[SymbolSelect], TimeFrame, RSI_Period1, PRICE_CLOSE);

        bb_handle = iBands(Symbols[SymbolSelect], TimeFrame, BB_Period, 0, BB_Deviation, PRICE_CLOSE);
    }
    else
    {
        Print("Error: SymbolList is empty.");
        return(INIT_FAILED);
    }

    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    if(!AutoTrading) return;

    if(CountOpenPositions() >= MaxTrades) return;

    string current_symbol = Symbols[SymbolSelect];

    // Handle trailing stops
    TrailingStop(current_symbol);

    if(Strategy == "CCI_BOOM")
    {
        HandleBoomStrategy(current_symbol, CalculateLotSize(current_symbol));
    }
    else if(Strategy == "MA_CROSS")
    {
        HandleMAStrategy(current_symbol, CalculateLotSize(current_symbol));
    }
    else if(Strategy == "RSI_BREAKOUT")
    {
        HandleRSIStrategy(current_symbol, CalculateLotSize(current_symbol));
    }
    else if(Strategy == "BOLLINGER_BANDS")
    {
        HandleBBStrategy(current_symbol, CalculateLotSize(current_symbol));
    }
}

//+------------------------------------------------------------------+
//| Calculate proper lot size for V75 and other symbols              |
//+------------------------------------------------------------------+
double CalculateLotSize(string symbol)
{
    double min_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
    double lot = LotSize;

    if(lot < min_lot) lot = min_lot;
    if(lot > SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX))
        lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);

    return NormalizeDouble(lot, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS));
}

//+------------------------------------------------------------------+
//| Trailing Stop Management                                         |
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
                if(newSL > currentSL  || currentSL == 0.0)
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

//+------------------------------------------------------------------+
//| Execute Trade with V75 compatibility                             |
//+------------------------------------------------------------------+
void ExecuteTrade(string symbol, ENUM_ORDER_TYPE orderType, double lot)
{
    MqlTradeRequest request = {};
    MqlTradeResult result = {};

    double price = (orderType == ORDER_TYPE_BUY) ? SymbolInfoDouble(symbol, SYMBOL_ASK)
                                                : SymbolInfoDouble(symbol, SYMBOL_BID);
    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    double sl_points = StopLossPips * point;
    double tp_points = sl_points * RiskReward;

    request.action = TRADE_ACTION_DEAL;
    request.symbol = symbol;
    request.volume = lot;
    request.type = orderType;
    request.price = price;
    request.deviation = 5;
    request.magic = MagicNumber;

    if(orderType == ORDER_TYPE_BUY)
    {
        request.sl = price - sl_points;
        request.tp = price + tp_points;
    }
    else
    {
        request.sl = price + sl_points;
        request.tp = price - tp_points;
    }

    if(!OrderSend(request, result))
    {
        Print("OrderSend failed: ", GetLastError());
    }
}

//+------------------------------------------------------------------+
//| Handle CCI Boom Strategy                                         |
//+------------------------------------------------------------------+
void HandleBoomStrategy(string symbol, double lotSize)
{
    double cciValue = iCCI(symbol, PERIOD_H1, CCI_Period1, PRICE_CLOSE, 0);

    if(cciValue == 0)
    {
        Print("Failed to get CCI value for ", symbol);
        return;
    }

    bool buySignal = cciValue > CCI_Overbought1;
    bool sellSignal = cciValue < CCI_Oversold1;

    if(buySignal)
    {
        ExecuteTrade(symbol, ORDER_TYPE_BUY, lotSize);
    }
    else if(sellSignal)
    {
        ExecuteTrade(symbol, ORDER_TYPE_SELL, lotSize);
    }
}

//+------------------------------------------------------------------+
//| Handle MA Cross Strategy                                         |
//+------------------------------------------------------------------+
void HandleMAStrategy(string symbol, double lotSize)
{
    double fastMA = iMA(symbol, TimeFrame, FastMA_Period1, 0, MODE_SMA, PRICE_CLOSE, 0);
    double slowMA = iMA(symbol, TimeFrame, SlowMA_Period1, 0, MODE_SMA, PRICE_CLOSE, 0);

    bool buySignal = fastMA > slowMA;
    bool sellSignal = fastMA < slowMA;

    if(buySignal)
    {
        ExecuteTrade(symbol, ORDER_TYPE_BUY, lotSize);
    }
    else if(sellSignal)
    {
        ExecuteTrade(symbol, ORDER_TYPE_SELL, lotSize);
    }
}

//+------------------------------------------------------------------+
//| Handle RSI Breakout Strategy                                     |
//+------------------------------------------------------------------+
void HandleRSIStrategy(string symbol, double lotSize)
{
    double rsiValue = iRSI(symbol, TimeFrame, RSI_Period1, PRICE_CLOSE, 0);

    bool buySignal = rsiValue < RSI_Oversold1;
    bool sellSignal = rsiValue > RSI_Overbought1;

    if(buySignal)
    {
        ExecuteTrade(symbol, ORDER_TYPE_BUY, lotSize);
    }
    else if(sellSignal)
    {
        ExecuteTrade(symbol, ORDER_TYPE_SELL, lotSize);
    }
}

//+------------------------------------------------------------------+
//| Handle Bollinger Bands Strategy                                  |
//+------------------------------------------------------------------+
void HandleBBStrategy(string symbol, double lotSize)
{
    double upperBand[], lowerBand[], close[];
    CopyBuffer(bb_handle, 1, 0, 1, upperBand);
    CopyBuffer(bb_handle, 2, 0, 1, lowerBand);
    CopyClose(symbol, TimeFrame, 0, 1, close);

    bool buySignal = close[0] < lowerBand[0];
    bool sellSignal = close[0] > upperBand[0];

    if(buySignal)
    {
        ExecuteTrade(symbol, ORDER_TYPE_BUY, lotSize);
    }
    else if(sellSignal)
    {
        ExecuteTrade(symbol, ORDER_TYPE_SELL, lotSize);
    }
}
