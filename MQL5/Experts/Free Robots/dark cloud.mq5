//+------------------------------------------------------------------+
//|                                 DarkCloud PiercingLine Stoch.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>

//--- Input parameters
input int InpAverBodyPeriod = 12;       // Period for calculating average candlestick size
input int InpStochK = 47;               // Stochastic %K period
input int InpStochD = 9;                // Stochastic %D period
input int InpStochSlow = 13;            // Stochastic smoothing period
input double InpLot = 0.1;              // Lot size
input uint InpSL = 200;                 // Stop Loss in points
input uint InpTP = 200;                 // Take Profit in points
input uint InpSlippage = 10;            // Slippage in points
input uint InpTrailingStop = 100;       // Trailing Stop in points
input long InpMagicNumber = 120800;     // Magic Number

//--- Global variables
int ExtIndicatorHandle;                 // Stochastic indicator handle
CTrade ExtTrade;                        // Trade object
CSymbolInfo ExtSymbolInfo;              // Symbol info object

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   // Initialize Stochastic indicator
   ExtIndicatorHandle = iStochastic(_Symbol, _Period, InpStochK, InpStochD, InpStochSlow, MODE_SMA, STO_LOWHIGH);
   if(ExtIndicatorHandle == INVALID_HANDLE)
     {
      Print("Error creating Stochastic indicator");
      return(INIT_FAILED);
     }

   // Set trade parameters
   ExtTrade.SetDeviationInPoints(InpSlippage);
   ExtTrade.SetExpertMagicNumber(InpMagicNumber);

   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   IndicatorRelease(ExtIndicatorHandle);
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   // Check for new bar
   static datetime lastBarTime = 0;
   if(lastBarTime == iTime(_Symbol, _Period, 0))
      return;
   lastBarTime = iTime(_Symbol, _Period, 0);

   // Check for trading signals
   int signal = CheckSignal();
   if(signal != 0)
     {
      if(signal == 1 && !PositionExist(POSITION_TYPE_BUY))
         OpenPosition(POSITION_TYPE_BUY);
      else if(signal == -1 && !PositionExist(POSITION_TYPE_SELL))
         OpenPosition(POSITION_TYPE_SELL);
     }

   // Update trailing stop
   UpdateTrailingStop();
  }
//+------------------------------------------------------------------+
//| Check for trading signals                                        |
//+------------------------------------------------------------------+
int CheckSignal()
  {
   // Check for Dark Cloud Cover (Sell signal)
   if(iClose(_Symbol, _Period, 2) > iOpen(_Symbol, _Period, 2) && // Long white candle
      iClose(_Symbol, _Period, 1) < iClose(_Symbol, _Period, 2) && // Close below previous close
      iClose(_Symbol, _Period, 1) > iOpen(_Symbol, _Period, 2) &&  // Close within previous body
      iOpen(_Symbol, _Period, 1) > iHigh(_Symbol, _Period, 2))     // Open above previous high
     {
      double stoch = GetStochasticSignal(1);
      if(stoch > 70)
         return -1; // Sell signal
     }

   // Check for Piercing Line (Buy signal)
   if(iOpen(_Symbol, _Period, 2) > iClose(_Symbol, _Period, 2) && // Long black candle
      iClose(_Symbol, _Period, 1) > iClose(_Symbol, _Period, 2) && // Close above previous close
      iClose(_Symbol, _Period, 1) < iOpen(_Symbol, _Period, 2) &&  // Close within previous body
      iOpen(_Symbol, _Period, 1) < iLow(_Symbol, _Period, 2))      // Open below previous low
     {
      double stoch = GetStochasticSignal(1);
      if(stoch < 30)
         return 1; // Buy signal
     }

   return 0; // No signal
  }
//+------------------------------------------------------------------+
//| Get Stochastic signal value                                      |
//+------------------------------------------------------------------+
double GetStochasticSignal(int index)
  {
   double stochValues[];
   if(CopyBuffer(ExtIndicatorHandle, 0, index, 1, stochValues) < 0)
     {
      Print("Error copying Stochastic data");
      return EMPTY_VALUE;
     }
   return stochValues[0];
  }
//+------------------------------------------------------------------+
//| Open a position                                                  |
//+------------------------------------------------------------------+
void OpenPosition(int positionType)
  {
   double price = (positionType == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = (positionType == POSITION_TYPE_BUY) ? price - InpSL * _Point : price + InpSL * _Point;
   double tp = (positionType == POSITION_TYPE_BUY) ? price + InpTP * _Point : price - InpTP * _Point;

   if(positionType == POSITION_TYPE_BUY)
      ExtTrade.Buy(InpLot, _Symbol, price, sl, tp);
   else
      ExtTrade.Sell(InpLot, _Symbol, price, sl, tp);
  }
//+------------------------------------------------------------------+
//| Check if a position exists                                       |
//+------------------------------------------------------------------+
bool PositionExist(int positionType)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
        {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber && PositionGetInteger(POSITION_TYPE) == positionType)
            return true;
        }
     }
   return false;
  }
//+------------------------------------------------------------------+
//| Update trailing stop for open positions                          |
//+------------------------------------------------------------------+
void UpdateTrailingStop()
  {
   int positions = PositionsTotal();
   for(int i = 0; i < positions; i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket != 0)
        {
         string symbol = PositionGetString(POSITION_SYMBOL);
         long magic = PositionGetInteger(POSITION_MAGIC);
         if(symbol == _Symbol && magic == InpMagicNumber)
           {
            double currentSL = PositionGetDouble(POSITION_SL);
            double newSL;

            if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
              {
               newSL = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_BID) - InpTrailingStop * _Point, _Digits);
               if (newSL > currentSL || currentSL == 0)
                 {
                  ExtTrade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
                  PrintFormat("Trailing Stop updated for Buy position #%d to SL: %G", ticket, newSL);
                 }
              }
            else if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
              {
               newSL = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_ASK) + InpTrailingStop * _Point, _Digits);
               if (newSL < currentSL || currentSL == 0)
                 {
                  ExtTrade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
                  PrintFormat("Trailing Stop updated for Sell position #%d to SL: %G", ticket, newSL);
                 }
              }
           }
        }
     }
  }
//+------------------------------------------------------------------+
