//+------------------------------------------------------------------+
//|                                   DarkCloud PiercingLine CCI.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.01"

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>

#define SIGNAL_BUY    1             // Buy signal
#define SIGNAL_NOT    0             // no trading signal
#define SIGNAL_SELL  -1             // Sell signal

#define CLOSE_LONG    2             // signal to close Long
#define CLOSE_SHORT  -2             // signal to close Short

//--- Input parameters
input int InpAverBodyPeriod=12;     // period for calculating average candlestick size
input int InpMAPeriod = 5;          // Trend MA period
input int InpPeriodCCI = 37;        // CCI period
input ENUM_APPLIED_PRICE InpPrice=PRICE_CLOSE; // price type

//--- trade parameters
input uint InpDuration=10;           // position holding time in bars
input double InpSL=200.0;            // Stop Loss in points
input double InpTP=200.0;            // Take Profit in points
input double InpTrailingStop=100;    // Trailing stop in points
input uint InpSlippage=10;           // slippage in points
//--- money management parameters
input double InpLot=0.1;             // lot
//--- Expert ID
input long InpMagicNumber=120500;     // Magic Number

//--- RSI parameters
input int InpRSIPeriod=14;           // RSI period
input double InpRSIOverbought=70;    // RSI overbought level
input double InpRSIOversold=30;      // RSI oversold level

//--- MACD parameters
input int InpFastEMA=12;             // Fast EMA period for MACD
input int InpSlowEMA=26;              // Slow EMA period for MACD
input int InpSignalSMA=9;            // Signal SMA period for MACD

//--- Bollinger Bands parameters
input int InpBBPeriod=20;            // Bollinger Bands period
input double InpBBDeviation=2.0;     // Bollinger Bands deviation

//--- global variables
int ExtAvgBodyPeriod; 
int ExtSignalOpen=0; 
int ExtSignalClose=0; 
string ExtPatternInfo="";
string ExtDirection="";
bool ExtPatternDetected=false; 
bool ExtConfirmed=false; 
bool ExtCloseByTime=true; 
bool ExtCheckPassed=true; 
//---  indicator handles
int ExtIndicatorHandle=INVALID_HANDLE;
int ExtTrendMAHandle=INVALID_HANDLE;
int ExtRSIHandle=INVALID_HANDLE;
int ExtMACDHandle=INVALID_HANDLE;
int ExtBollingerBandsHandle=INVALID_HANDLE;

//--- service objects
CTrade ExtTrade;
CSymbolInfo ExtSymbolInfo;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("InpSL=", InpSL);
   Print("InpTP=", InpTP);
   //--- set parameters for trading operations
   ExtTrade.SetDeviationInPoints(InpSlippage);    // slippage
   ExtTrade.SetExpertMagicNumber(InpMagicNumber); // Expert Advisor ID
   ExtTrade.LogLevel(LOG_LEVEL_ERRORS);           // logging level

   ExtAvgBodyPeriod = InpAverBodyPeriod;

   //--- indicator initialization
   ExtIndicatorHandle = iCCI(_Symbol, _Period, InpPeriodCCI, InpPrice);
   if(ExtIndicatorHandle == INVALID_HANDLE)
   {
      Print("Error creating CCI indicator");
      return(INIT_FAILED);
   }

   //--- trend moving average     
   ExtTrendMAHandle = iMA(_Symbol, _Period, InpMAPeriod, 0, MODE_SMA, PRICE_CLOSE);
   if(ExtTrendMAHandle == INVALID_HANDLE)
   {
      Print("Error creating Moving Average indicator");
      return(INIT_FAILED);
   }

   //--- RSI
   ExtRSIHandle = iRSI(_Symbol, _Period, InpRSIPeriod, INPPrice);
   if(ExtRSIHandle == INVALID_HANDLE)
   {
      Print("Error creating RSI indicator");
      return(INIT_FAILED);
   }

   //--- MACD
   ExtMACDHandle = iMACD(_Symbol, _Period, InpFastEMA, InpSlowEMA, InpSignalSMA);
   if(ExtMACDHandle == INVALID_HANDLE)
   {
      Print("Error creating MACD indicator");
      return(INIT_FAILED);
   }

   //--- Bollinger Bands
   ExtBollingerBandsHandle = iBands(_Symbol, _Period, InpBBPeriod, InpBBDeviation, 0, InpPrice);
   if(ExtBollingerBandsHandle == INVALID_HANDLE)
   {
      Print("Error creating Bollinger Bands indicator");
      return(INIT_FAILED);
   }

   //--- OK
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    //--- release indicator handles
   IndicatorRelease(ExtIndicatorHandle);
   IndicatorRelease(ExtTrendMAHandle);
   IndicatorRelease(ExtRSIHandle);
   IndicatorRelease(ExtMACDHandle);
   IndicatorRelease(ExtBollingerBandsHandle);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    //--- save the next bar start time; all checks at bar opening only
   static datetime next_bar_open=0;
   //--- Phase 1 - check the emergence of a new bar
   if(TimeCurrent() >= next_bar_open)
   {
      //--- get the current state of environment on the new bar
      if(CheckState())
      {
         //--- set the new bar opening time
         next_bar_open = TimeCurrent();
         next_bar_open -= next_bar_open % PeriodSeconds(_Period);
         next_bar_open += PeriodSeconds(_Period);
         //--- report the emergence of a new bar only once within a bar
         if(ExtPatternDetected && ExtConfirmed)
            Print(ExtPatternInfo);
      }
      else
      {
         //--- error getting the status, retry on the next tick
         return;
      }
   }

   //--- Phase 2 - if there is a signal and no position in this direction
   if(ExtSignalOpen && !PositionExist(ExtSignalOpen))
   {
      Print("\r\nSignal to open position ", ExtDirection);
      PositionOpen();
      if(PositionExist(ExtSignalOpen))
         ExtSignalOpen = SIGNAL_NOT;
   }

   //--- Phase 3 - close if there is a signal to close
   if(ExtSignalClose && PositionExist(ExtSignalClose))
   {
      Print("\r\nSignal to close position ", ExtDirection);
      CloseBySignal(ExtSignalClose);
      if(!PositionExist(ExtSignalClose))
         ExtSignalClose = SIGNAL_NOT;
   }

   //--- Phase 4 - implement the trailing stop based on profit
   ManageTrailingStop();
}

//+------------------------------------------------------------------+
//| Get the current environment and check for a pattern             |
//+------------------------------------------------------------------+
bool CheckState()
{
   //--- check if there is a pattern
   if(!CheckPattern())
   {
      Print("Error, failed to check pattern");
      return(false);
   }

   //--- check for confirmation
   if(!CheckConfirmation())
   {
      Print("Error, failed to check pattern confirmation");
      return(false);
   }

   //--- if there is no confirmation, cancel the signal
   if(!ExtConfirmed)
      ExtSignalOpen = SIGNAL_NOT;

   //--- check if there is a signal to close a position
   if(!CheckCloseSignal())
   {
      Print("Error, failed to check the closing signal");
      return(false);
   }

   //--- if positions are to be closed after certain holding time in bars
   if(InpDuration)
      ExtCloseByTime = true; // set flag to close upon expiration

   //--- all checks done
   return(true);
}

//+------------------------------------------------------------------+
//| Open a position in the direction of the signal                   |
//+------------------------------------------------------------------+
bool PositionOpen()
{
   ExtSymbolInfo.Refresh();
   ExtSymbolInfo.RefreshRates();

   double price=0;
   //--- Stop Loss and Take Profit are not set by default
   double stoploss=0.0;
   double takeprofit=0.0;

   int    digits=ExtSymbolInfo.Digits();
   double point=ExtSymbolInfo.Point();
   double spread=ExtSymbolInfo.Ask()-ExtSymbolInfo.Bid();

   //--- uptrend
   if(ExtSignalOpen==SIGNAL_BUY)
   {
      price=NormalizeDouble(ExtSymbolInfo.Ask(), digits);
      //--- if Stop Loss is set
      if(InpSL>0)
      {
         stoploss = NormalizeDouble(price - InpSL * point, digits);
      }
      //--- if Take Profit is set
      if(InpTP>0)
      {
         takeprofit = NormalizeDouble(price + InpTP * point, digits);
      }

      if(!ExtTrade.Buy(InpLot, Symbol(), price, stoploss, takeprofit))
      {
         PrintFormat("Failed to buy %G at %G (sl=%G tp=%G) failed. Ask=%G error=%d",
                     InpLot, price, stoploss, takeprofit, ExtSymbolInfo.Ask(), GetLastError());
         return(false);
      }
   }

   //--- downtrend
   if(ExtSignalOpen==SIGNAL_SELL)
   {
      price=NormalizeDouble(ExtSymbolInfo.Bid(), digits);
      //--- if Stop Loss is set
      if(InpSL>0)
      {
         stoploss = NormalizeDouble(price + InpSL * point, digits);
      }
      //--- if Take Profit is set
      if(InpTP>0)
      {
         takeprofit = NormalizeDouble(price - InpTP * point, digits);
      }

      if(!ExtTrade.Sell(InpLot, Symbol(), price, stoploss, takeprofit))
      {
         PrintFormat("Failed to sell at %G (sl=%G tp=%G) failed. Bid=%G error=%d",
                     price, stoploss, takeprofit, ExtSymbolInfo.Bid(), GetLastError());
         return(false);
      }
   }

   return(true);
}

//+------------------------------------------------------------------+
//| Close a position based on the specified signal                  |
//+------------------------------------------------------------------+
void CloseBySignal(int type_close)
{
   //--- if there is no signal to close, return successful completion
   if(type_close==SIGNAL_NOT)
      return;
   //--- if there are no positions opened by our EA
   if(PositionExist(ExtSignalClose)==0)
      return;

   //--- closing direction
   long type;
   switch(type_close)
   {
      case CLOSE_SHORT:
         type=POSITION_TYPE_SELL;
         break;
      case CLOSE_LONG:
         type=POSITION_TYPE_BUY;
         break;
      default:
         Print("Error! Signal to close not detected");
         return;
   }

   //--- check all positions and close ours based on the signal
   int positions=PositionsTotal();
   for(int i=positions-1; i>=0; i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket!=0)
      {
         //--- get the name of the symbol and the position id (magic)
         string symbol=PositionGetString(POSITION_SYMBOL);
         long magic =PositionGetInteger(POSITION_MAGIC);
         //--- if they correspond to our values
         if(symbol==Symbol() && magic==InpMagicNumber)
         {
            if(PositionGetInteger(POSITION_TYPE)==type)
            {
               ExtTrade.PositionClose(ticket, InpSlippage);
               ExtTrade.PrintResult();
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Manage Trailing Stop based on acquired profit                   |
//+------------------------------------------------------------------+
void ManageTrailingStop()
{
   // Check for open positions
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket != 0)
      {
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double profit = PositionGetDouble(POSITION_PROFIT);
         double stoploss = PositionGetDouble(POSITION_SL);
         double newStopLoss;

         // Check if the position is profitably open
         if (profit > 0)
         {
            // Check if we need to adjust the stoploss to breach the trailing stop logic
            if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
            {
               newStopLoss = openPrice + InpTrailingStop * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
               if (stoploss < newStopLoss)
               {
                  if (!ExtTrade.PositionModify(ticket, newStopLoss, POSITION_TP))
                  {
                     Print("Error adjusting SL for buy position. Error: ", GetLastError());
                  } 
               }
            }
            else if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
            {
               newStopLoss = openPrice - InpTrailingStop * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
               if (stoploss > newStopLoss)
               {
                  if (!ExtTrade.PositionModify(ticket, newStopLoss, POSITION_TP))
                  {
                     Print("Error adjusting SL for sell position. Error: ", GetLastError());
                  } 
               }
            }
         }
      }
   }
}

// Implement further methods CheckPattern, CheckConfirmation and CheckCloseSignal
// Remaining logic remains similar to your existing implementations, 
// for example CheckPattern() to recognize trading signals 
// and CheckConfirmation() to validate these signals.
