//+------------------------------------------------------------------+
//|                EnhancedPriceActionScalperPro.mq5               |
//|                        Copyright 2025                            |
//|                                       https://www.mql5.com       |
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window

// Input Parameters
input group "==== Risk Management ===="
input double RiskRewardRatio = 3.0;          // Risk-Reward Ratio (1:3)
input double StopLoss = 300;                  // Stop Loss in points
input double RiskPercentage = 1.0;            // Risk percentage of account balance
input double UserLotSize = 0.20;              // User-defined lot size
input int MagicNumber = 11586;                // Unique Magic Number
input int MaxOpenPositions = 5;               // Maximum open positions
input double LockInProfitThreshold = 2110;       // Lock-in profit threshold ($)
input double MaxLossThreshold = 100;           // Maximum loss threshold ($)
input double MaxDrawdownPercentage = 10;       // Maximum drawdown percentage

input group "==== Trading Rules ===="
input ENUM_TIMEFRAMES TimeFrame = PERIOD_H1; // Trading timeframe
input int TradeCooldownSeconds = 60;          // Cooldown period between trades
input int SupportResistanceLookback = 50;     // Bars for S/R levels
input double PinBarThreshold = 0.6;           // Pin bar ratio threshold
input int InsideBarLookback = 3;              // Bars for inside bars
input double VolumeSpikeMultiplier = 1.5;     // Volume spike multiplier
input bool RequireCloseConfirmation = true;   // Require candle close confirmation

input group "==== CCI Filter ===="
input int CCIPeriod = 14;                     // CCI period
input double CCITrendThreshold = 100;         // CCI threshold
input bool UseCCIFilter = true;               // Enable CCI filter

input group "==== Visual & Alert Settings ===="
input bool ShowEntrySignals = true;           // Show buy/sell signals
input bool EnableAlerts = true;               // Enable trade alerts
input bool EnableLogging = true;              // Enable trade logging
input color BuySignalColor = clrDodgerBlue;   // Buy signal color
input color SellSignalColor = clrRed;         // Sell signal color
input int ArrowSize = 2;                      // Signal arrow size

// Global Variables
long chartId;
datetime lastTradeTime = 0;
bool isProfitsLocked = false;
double supportLevel = 0;
double resistanceLevel = 0;
int cciHandle;
double dailyEquityHigh;
double dailyEquityLow;

// Dynamic Variables for Trade Calculations
double TakeProfit;  // Made as a regular variable now instead of an input

//+------------------------------------------------------------------+
//| Expert Initialization Function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    chartId = ChartID();
    dailyEquityHigh = AccountInfoDouble(ACCOUNT_EQUITY);
    dailyEquityLow = dailyEquityHigh;

    // Calculate TakeProfit based on RiskRewardRatio
    TakeProfit = StopLoss * RiskRewardRatio;

    // Initialize CCI indicator
    cciHandle = iCCI(NULL, TimeFrame, CCIPeriod, PRICE_TYPICAL);
    
    if (cciHandle == INVALID_HANDLE)
    {
        Print("Failed to initialize CCI indicator. Error: ", GetLastError());
        return INIT_FAILED;
    }
    
    Print("EA initialized successfully. Risk-Reward set to 1:", RiskRewardRatio);
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert Tick Function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Update indicators and levels for new bars
    if (IsNewBar())
    {
        CalculateSupportResistance();
    }

    // Check trade conditions with full indicator confirmation
    if (CheckTradeConditions() && 
        CountOpenPositions() < MaxOpenPositions &&
        CheckTradingAllowed())
    {
        if (ShowEntrySignals)
        {
            DrawEntrySignal();
        }
        OpenTrade();
    }

    // Manage open positions
    ManageOpenTrades();
}

//+------------------------------------------------------------------+
//| Enhanced Trade Condition Check with CCI Filter                  |
//+------------------------------------------------------------------+
bool CheckTradeConditions()
{
    // Price Action Signals
    bool priceActionBuySignal = (CheckPinBar(true) || CheckInsideBarBreakout(true)) && 
                                 iClose(NULL, TimeFrame, 0) > supportLevel;
    bool priceActionSellSignal = (CheckPinBar(false) || CheckInsideBarBreakout(false)) && 
                                  iClose(NULL, TimeFrame, 0) < resistanceLevel;

    // Volume Filter
    double currentVolume = iVolume(NULL, TimeFrame, 0);
    double avgVolume = iMA(NULL, TimeFrame, 20, 0, MODE_SMA, VOLUME_TICK);
    bool volumeFilter = currentVolume > avgVolume * VolumeSpikeMultiplier;

    // CCI Filter
    bool cciFilter = true;
    if (UseCCIFilter)
    {
        double cci[];
        if (CopyBuffer(cciHandle, 0, 0, 2, cci) < 0)
        {
            Print("Failed to copy CCI buffer. Error: ", GetLastError());
            return false; // Exit if there's an error
        }

        ArraySetAsSeries(cci, true);
        cciFilter = (priceActionBuySignal && cci[0] > -CCITrendThreshold && cci[0] > cci[1]) ||
                    (priceActionSellSignal && cci[0] < CCITrendThreshold && cci[0] < cci[1]);
    }

    // Confirmation Filter
    bool confirmationFilter = RequireCloseConfirmation ? 
                              (priceActionBuySignal ? ConfirmBuySignal() : ConfirmSellSignal()) : 
                              true;

    // Combined Conditions
    bool buyCondition = priceActionBuySignal && volumeFilter && confirmationFilter && cciFilter;
    bool sellCondition = priceActionSellSignal && volumeFilter && confirmationFilter && cciFilter;

    if (EnableLogging)
    {
        Print("Buy Conditions - PA: ", priceActionBuySignal, 
              " Vol: ", volumeFilter, 
              " CCI: ", cciFilter, 
              " Conf: ", confirmationFilter);
        Print("Sell Conditions - PA: ", priceActionSellSignal, 
              " Vol: ", volumeFilter, 
              " CCI: ", cciFilter, 
              " Conf: ", confirmationFilter);
    }

    return buyCondition || sellCondition;
}

//+------------------------------------------------------------------+
//| Enhanced Trade Execution with Full Confirmation                 |
//+------------------------------------------------------------------+
void OpenTrade()
{
    if (TimeCurrent() - lastTradeTime < TradeCooldownSeconds)
    {
        Print("Trade cooldown active. Skipping trade.");
        return;
    }

    bool isBuySignal = CheckPinBar(true) || CheckInsideBarBreakout(true);
    if (CountOpenPositionsInDirection(isBuySignal) > 0)
    {
        Print("Existing position in same direction. Skipping trade.");
        return;
    }

    double price, sl, tp;
    ENUM_ORDER_TYPE orderType;

    if (isBuySignal)
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

    MqlTradeRequest request = {};
    MqlTradeResult result = {};
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
        Print("Trade opened: Type: ", EnumToString(orderType),
              " Price: ", price,
              " SL: ", sl,
              " TP: ", tp,
              " RR: 1:", RiskRewardRatio);
        lastTradeTime = TimeCurrent();
        isProfitsLocked = false;

        if (EnableAlerts)
        {
            Alert("New trade: ", EnumToString(orderType), " at ", price);
        }
    }
}

//+------------------------------------------------------------------+
//| Enhanced Position Management with Trailing Stops                |
//+------------------------------------------------------------------+
void ManageOpenTrades()
{
    for (int i = 0; i < PositionsTotal(); i++)
    {
        ulong ticket = PositionGetTicket(i);
        if (!PositionSelectByTicket(ticket) || 
            PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;

        double currentPrice = PositionGetInteger(POSITION_TYPE) == ORDER_TYPE_BUY ? 
                              SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
                              SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        double positionProfit = PositionGetDouble(POSITION_PROFIT);

        // Check for max loss threshold
        if (-positionProfit >= MaxLossThreshold)
        {
            ClosePosition(ticket);
            continue;
        }

        // Lock in profits if threshold reached
        if (!isProfitsLocked && positionProfit >= LockInProfitThreshold)
        {
            double newSL = PositionGetInteger(POSITION_TYPE) == ORDER_TYPE_BUY ?
                           currentPrice - (StopLoss * _Point) :
                           currentPrice + (StopLoss * _Point);

            MqlTradeRequest modifyRequest = {};
            MqlTradeResult modifyResult = {};
            modifyRequest.action = TRADE_ACTION_SLTP;
            modifyRequest.position = ticket;
            modifyRequest.sl = newSL;

            if (!OrderSend(modifyRequest, modifyResult))
            {
                Print("Failed to modify SL, error code: ", GetLastError());
            }
            else
            {
                isProfitsLocked = true;
                Print("Profits locked for ticket: ", ticket);
            }
        }

        // Apply trailing stop
        double trailPrice = PositionGetInteger(POSITION_TYPE) == ORDER_TYPE_BUY ?
                            currentPrice - (StopLoss * 0.5 * _Point) : // Trail at 50% of original SL
                            currentPrice + (StopLoss * 0.5 * _Point);

        if ((PositionGetInteger(POSITION_TYPE) == ORDER_TYPE_BUY && trailPrice > PositionGetDouble(POSITION_SL)) ||
            (PositionGetInteger(POSITION_TYPE) == ORDER_TYPE_SELL && trailPrice < PositionGetDouble(POSITION_SL)))
        {
            MqlTradeRequest modifyRequest = {};
            MqlTradeResult modifyResult = {};
            modifyRequest.action = TRADE_ACTION_SLTP;
            modifyRequest.position = ticket;
            modifyRequest.sl = trailPrice;

            if (!OrderSend(modifyRequest, modifyResult))
            {
                Print("Failed to modify trailing stop, error code: ", GetLastError());
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Helper Functions                                                 |
//+------------------------------------------------------------------+
bool IsNewBar()
{
    static datetime lastBarTime = 0;
    datetime currentBarTime = iTime(NULL, TimeFrame, 0);
    
    if (lastBarTime != currentBarTime)
    {
        lastBarTime = currentBarTime;
        return true;
    }
    return false;
}

void CalculateSupportResistance()
{
    double highs[], lows[];
    ArraySetAsSeries(highs, true);
    ArraySetAsSeries(lows, true);
    
    CopyHigh(NULL, TimeFrame, 0, SupportResistanceLookback, highs);
    CopyLow(NULL, TimeFrame, 0, SupportResistanceLookback, lows);
    
    resistanceLevel = highs[ArrayMaximum(highs)];
    supportLevel = lows[ArrayMinimum(lows)];

    if (EnableLogging)
    {
        Print("Updated S/R Levels - Support: ", supportLevel, " Resistance: ", resistanceLevel);
    }
}

bool CheckPinBar(bool isBuySignal)
{
    double open = iOpen(NULL, TimeFrame, 0);
    double high = iHigh(NULL, TimeFrame, 0);
    double low = iLow(NULL, TimeFrame, 0);
    double close = iClose(NULL, TimeFrame, 0);
    
    double bodySize = MathAbs(close - open);
    double upperWick = high - MathMax(open, close);
    double lowerWick = MathMin(open, close) - low;

    if (isBuySignal) 
        return (close > open) && (lowerWick >= bodySize * PinBarThreshold) && (upperWick < bodySize * 0.5);
    
    return (close < open) && (upperWick >= bodySize * PinBarThreshold) && (lowerWick < bodySize * 0.5);
}

bool CheckInsideBarBreakout(bool isBuySignal)
{
    double motherHigh = iHigh(NULL, TimeFrame, 1);
    double motherLow = iLow(NULL, TimeFrame, 1);
    
    bool isInsideBar = true;
    for (int i = 2; i <= InsideBarLookback; i++)
    {
        if (iHigh(NULL, TimeFrame, i) > motherHigh || iLow(NULL, TimeFrame, i) < motherLow)
        {
            isInsideBar = false;
            break;
        }
    }

    if (!isInsideBar) return false;
    
    return isBuySignal ? (iHigh(NULL, TimeFrame, 0) > motherHigh) : (iLow(NULL, TimeFrame, 0) < motherLow);
}

bool ConfirmBuySignal() { return iClose(NULL, TimeFrame, 0) > iClose(NULL, TimeFrame, 1); }
bool ConfirmSellSignal() { return iClose(NULL, TimeFrame, 0) < iClose(NULL, TimeFrame, 1); }

void DrawEntrySignal()
{
    static datetime lastSignalTime = 0;
    if (TimeCurrent() == lastSignalTime) return;

    lastSignalTime = TimeCurrent();
    string arrowName = "TradeSignal_" + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES);
    
    bool isBuySignal = CheckPinBar(true) || CheckInsideBarBreakout(true);
    int arrowCode = isBuySignal ? 241 : 242;
    color arrowColor = isBuySignal ? BuySignalColor : SellSignalColor;

    if (ObjectFind(0, arrowName) == -1)
    {
        ObjectCreate(0, arrowName, OBJ_ARROW, 0, TimeCurrent(), iClose(NULL, TimeFrame, 0));
        ObjectSetInteger(0, arrowName, OBJPROP_COLOR, arrowColor);
        ObjectSetInteger(0, arrowName, OBJPROP_ARROWCODE, arrowCode);
        ObjectSetInteger(0, arrowName, OBJPROP_WIDTH, ArrowSize);
    }
}

int CountOpenPositionsInDirection(bool isBuySignal)
{
    int count = 0; 
    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if (PositionSelectByTicket(ticket) && 
            PositionGetString(POSITION_SYMBOL) == _Symbol && 
            PositionGetInteger(POSITION_MAGIC) == MagicNumber)
        {
            if ((isBuySignal && PositionGetInteger(POSITION_TYPE) == ORDER_TYPE_BUY) ||
                (!isBuySignal && PositionGetInteger(POSITION_TYPE) == ORDER_TYPE_SELL))
            {
                count++;
            }
        }
    }
    return count;
}

double CalculateLotSize()
{
    if (UserLotSize > 0) return UserLotSize;

    double accountEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    double riskAmount = accountEquity * (RiskPercentage / 100);
    double lotSize = riskAmount / (StopLoss * _Point);
    
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    
    lotSize = MathRound(lotSize / lotStep) * lotStep;
    return MathMin(MathMax(lotSize, minLot), maxLot);
}

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

bool CheckTradingAllowed()
{
    // Check daily drawdown limit
    double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    if (currentEquity < dailyEquityHigh * (1 - MaxDrawdownPercentage / 100))
    {
        Print("Max drawdown limit reached. Trading suspended.");
        return false;
    }
    return true;
}

void ClosePosition(ulong ticket)
{
    MqlTradeRequest request = {};
    MqlTradeResult result = {};
    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = PositionGetDouble(POSITION_VOLUME);
    request.type = (PositionGetInteger(POSITION_TYPE) == ORDER_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
    request.position = ticket;
    
    if (!OrderSend(request, result))
    {
        Print("Failed to close position, error code: ", GetLastError());
    }
}
//+------------------------------------------------------------------+