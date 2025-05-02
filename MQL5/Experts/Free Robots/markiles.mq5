//+------------------------------------------------------------------+
//| Expert Advisor: Enhanced Trendline Breakout Strategy             |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.51"

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\PositionInfo.mqh>

// Define signal constants
#define SIGNAL_BUY    1
#define SIGNAL_SELL   -1
#define SIGNAL_NONE   0

// Input parameters
input int InpTrendlinePeriod = 20;     // Period for trendline calculation
input int InpMAPeriod = 5;             // Trend MA period
input int InpPeriodCCI = 37;           // CCI period
input ENUM_APPLIED_PRICE InpPrice = PRICE_CLOSE; // Price type

// Trade parameters
input uint InpDuration = 10;           // Position holding time in bars
input double InpSL = 200.0;            // Stop Loss in points
input double InpTP = 200.0;            // Take Profit in points
input double InpTrailingStop = 100;    // Trailing stop in points
input uint InpSlippage = 10;           // Slippage in points
input double InpLot = 0.1;             // Lot size
input double InpRiskPercentage = 1.0;  // Risk percentage for dynamic lot sizing

// Indicator parameters
input int InpRSIPeriod = 14;           // RSI period
input int InpFastEMA = 12;             // Fast EMA period for MACD
input int InpSlowEMA = 26;             // Slow EMA period for MACD
input int InpSignalSMA = 9;            // Signal SMA period for MACD
input int InpBBPeriod = 20;            // Bollinger Bands period
input double InpBBDeviation = 2.0;     // Bollinger Bands deviation

// Expert ID
input long InpMagicNumber = 120500;    // Magic Number

// Global variables
int ExtSignalOpen = SIGNAL_NONE;
double TrendlineSlope = 0.0;
double TrendlineIntercept = 0.0;

// Service objects
CTrade ExtTrade;
CSymbolInfo ExtSymbolInfo;
CAccountInfo ExtAccountInfo;

//+------------------------------------------------------------------+
//| Expert initialization function                                  |
//+------------------------------------------------------------------+
int OnInit()
{
  // Initialize symbol info
  if(!ExtSymbolInfo.Name(_Symbol))
  {
    Print("Error initializing symbol info");
    return INIT_FAILED;
  }
  
  // Set trade parameters
  ExtTrade.SetExpertMagicNumber(InpMagicNumber);
  ExtTrade.SetMarginMode();
  ExtTrade.SetTypeFillingBySymbol(_Symbol);
  
  // Verify indicator handles
  if(InpMAPeriod <= 0 || InpRSIPeriod <= 0)
  {
    Print("Invalid indicator parameters");
    return INIT_FAILED;
  }
  
  return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert tick function                                            |
//+------------------------------------------------------------------+
void OnTick()
{
  if(!ExtSymbolInfo.RefreshRates())
  {
    Print("Error refreshing rates");
    return;
  }
  
  if(CheckPattern())
  {
    if(ExtSignalOpen != SIGNAL_NONE)
    {
      PositionOpen();
    }
  }
  
  ManageTrailingStop();
}

//+------------------------------------------------------------------+
//| Calculate trendline using linear regression                     |
//+------------------------------------------------------------------+
bool CalculateTrendline(int period)
{
  double closePrices[];
  ArraySetAsSeries(closePrices, true);
  
  if(CopyClose(_Symbol, _Period, 0, period, closePrices) != period)
  {
    Print("Error copying close prices");
    return false;
  }
  
  double sumX = 0.0, sumY = 0.0, sumXY = 0.0, sumX2 = 0.0;
  
  for(int i = 0; i < period; i++)
  {
    sumX += i;
    sumY += closePrices[i];
    sumXY += i * closePrices[i];
    sumX2 += i * i;
  }
  
  double denominator = period * sumX2 - sumX * sumX;
  if(denominator == 0)
  {
    Print("Error: Division by zero in trendline calculation");
    return false;
  }
  
  TrendlineSlope = (period * sumXY - sumX * sumY) / denominator;
  TrendlineIntercept = (sumY - TrendlineSlope * sumX) / period;
  return true;
}

//+------------------------------------------------------------------+
//| Calculate dynamic lot size                                      |
//+------------------------------------------------------------------+
double CalculateLotSize(double riskPercentage)
{
  double balance = ExtAccountInfo.Balance();
  if(balance <= 0)
  {
    Print("Invalid account balance");
    return InpLot;
  }
  
  double riskAmount = balance * riskPercentage / 100;
  double pointValue = ExtSymbolInfo.Point();
  double lotSize = riskAmount / (InpSL * pointValue);
  return NormalizeDouble(lotSize, 2);
}

//+------------------------------------------------------------------+
//| Open position with proper risk management                       |
//+------------------------------------------------------------------+
bool PositionOpen()
{
  double price, stoploss, takeprofit;
  double point = ExtSymbolInfo.Point();
  int digits = ExtSymbolInfo.Digits();
  double lotSize = CalculateLotSize(InpRiskPercentage);
  
  if(ExtSignalOpen == SIGNAL_BUY)
  {
    price = ExtSymbolInfo.Ask();
    stoploss = price - InpSL * point;
    takeprofit = price + InpTP * point;
    
    if(!ExtTrade.Buy(lotSize, _Symbol, price, stoploss, takeprofit))
    {
      Print("Buy order failed: ", GetLastError());
      return false;
    }
  }
  else if(ExtSignalOpen == SIGNAL_SELL)
  {
    price = ExtSymbolInfo.Bid();
    stoploss = price + InpSL * point;
    takeprofit = price - InpTP * point;
    
    if(!ExtTrade.Sell(lotSize, _Symbol, price, stoploss, takeprofit))
    {
      Print("Sell order failed: ", GetLastError());
      return false;
    }
  }
  
  return true;
}

//+------------------------------------------------------------------+
//| Manage trailing stops                                           |
//+------------------------------------------------------------------+
void ManageTrailingStop()
{
  if(InpTrailingStop <= 0) return;
  
  for(int i = PositionsTotal()-1; i >= 0; i--)
  {
    ulong ticket = PositionGetTicket(i);
    if(ticket <= 0) continue;
    
    ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
    double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
    double currentStop = PositionGetDouble(POSITION_SL);
    double currentPrice = (type == POSITION_TYPE_BUY) ? ExtSymbolInfo.Bid() : ExtSymbolInfo.Ask();
    double newStop = currentPrice - InpTrailingStop * ExtSymbolInfo.Point() * (type == POSITION_TYPE_BUY ? -1 : 1);
    
    if((type == POSITION_TYPE_BUY && newStop > currentStop) ||
       (type == POSITION_TYPE_SELL && newStop < currentStop))
    {
      ExtTrade.PositionModify(ticket, newStop, PositionGetDouble(POSITION_TP));
    }
  }
}

//+------------------------------------------------------------------+
//| Pattern detection logic                                         |
//+------------------------------------------------------------------+
bool CheckPattern()
{
  if(!CalculateTrendline(InpTrendlinePeriod))
    return false;
  
  // Add your actual pattern detection logic here
  // This is a placeholder for demonstration
  ExtSignalOpen = SIGNAL_BUY;
  return true;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
  // Cleanup code here
}
//+------------------------------------------------------------------+