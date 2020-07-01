//+------------------------------------------------------------------+
//|                                            Ichimoku Chikou Cross |
//|                                  Copyright © 2016, EarnForex.com |
//|                                       https://www.earnforex.com/ |
//+------------------------------------------------------------------+
#property copyright "Copyright © 2016, EarnForex"
#property link      "https://www.earnforex.com/metatrader-expert-advisors/Ichimoku-Chikou-Cross/"
#property version   "1.01"

#property description "Trades using Ichimoku Kinko Hyo indicator."
#property description "Implements Chikou/Price cross strategy."
#property description "Chikou crossing price (close) from below is a bullish signal."
#property description "Chikou crossing price (close) from above is a bearish signal."
#property description "No SL/TP. Positions remain open from signal to signal."
#property description "Entry confirmed by current price above/below Kumo, latest Chikou outside Kumo."

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>

// Main input parameters
input int Tenkan = 9; // Tenkan line period. The fast "moving average".
input int Kijun = 26; // Kijun line period. The slow "moving average".
input int Senkou = 52; // Senkou period. Used for Kumo (Cloud) spans.

// Money management
input double Lots = 0.1; 		// Basic lot size.
input bool MM  = false;  	// MM - If true - ATR-based position sizing.
input int ATR_Period = 20;
input double ATR_Multiplier = 1;
input double Risk = 2; // Risk - Risk tolerance in percentage points.
input double FixedBalance = 0; // FixedBalance - If greater than 0, position size calculator will use it instead of actual account balance.
input double MoneyRisk = 0; // MoneyRisk - Risk tolerance in base currency.
input bool UseMoneyInsteadOfPercentage = false;
input bool UseEquityInsteadOfBalance = false;
input int LotDigits = 2; // LotDigits - How many digits after dot supported in lot size. For example, 2 for 0.01, 1 for 0.1, 3 for 0.001, etc.

// Miscellaneous
input string OrderComment = "Ichimoku-Chikou-Cross";
input int Slippage = 100; 	// Tolerated slippage in brokers' pips.

// Main trading objects
CTrade *Trade;
CPositionInfo PositionInfo;

// Global variables
// Common
ulong LastBars = 0;
bool HaveLongPosition;
bool HaveShortPosition;
double StopLoss; // Not actual stop-loss - just a potential loss of MM estimation.

// Indicator handles
int IchimokuHandle;
int ATRHandle;

// Entry signals
bool ChikouPriceBull = false;
bool ChikouPriceBear = false;
bool KumoBullConfirmation = false;
bool KumoBearConfirmation = false;
bool KumoChikouBullConfirmation = false;
bool KumoChikouBearConfirmation = false;

// Buffers
double SenkouSpanA[];
double SenkouSpanB[];
double ChikouSpan[];

//+------------------------------------------------------------------+
//| Expert Initialization Function                                   |
//+------------------------------------------------------------------+
void OnInit()
{
	// Initialize the Trade class object
	Trade = new CTrade;
	Trade.SetDeviationInPoints(Slippage);
	IchimokuHandle = iIchimoku(_Symbol, _Period, Tenkan, Kijun, Senkou);
   ATRHandle = iATR(NULL, 0, ATR_Period);
}

//+------------------------------------------------------------------+
//| Expert Deinitialization Function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
	delete Trade;
}

//+------------------------------------------------------------------+
//| Expert Every Tick Function                                       |
//+------------------------------------------------------------------+
void OnTick()
{
   if ((!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) || (!TerminalInfoInteger(TERMINAL_CONNECTED)) || (SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE) != SYMBOL_TRADE_MODE_FULL)) return;
	
	int bars = Bars(_Symbol, _Period);
	
	// Trade only if new bar has arrived
	if (LastBars != bars) LastBars = bars;
	else return;
	
	MqlRates rates[];
	int copied = CopyRates(NULL, 0, 1, Kijun + 2, rates); // Will need pre-last bar and a two bars under latest closed Chikou line.
   if (copied <= 0) Print("Error copying price data ", GetLastError());
   
   if (CopyBuffer(IchimokuHandle, 2, 1, Kijun + 1, SenkouSpanA) != Kijun + 1) return;
   if (CopyBuffer(IchimokuHandle, 3, 1, Kijun + 1, SenkouSpanB) != Kijun + 1) return;
	// Kijun + 1 because we are not interested in latest "unclosed" Chikou bar, only two latest closed bars.
   if (CopyBuffer(IchimokuHandle, 4, Kijun + 1, 2, ChikouSpan) != 2) return;
   
   // Getting the potential loss value based on current ATR.
   if (MM)
   {
      double ATR[1];
      if (CopyBuffer(ATRHandle, 0, 1, 1, ATR) != 1) return;
      StopLoss = ATR[0] * ATR_Multiplier;
   }
   
   // Chikou/Price Cross
   // Bullish entry condition
   if ((ChikouSpan[1] > rates[1].close) && (ChikouSpan[0] <= rates[0].close))
   {
      ChikouPriceBull = true;
      ChikouPriceBear = false;
   }
   // Bearish entry condition
   else if ((ChikouSpan[1] < rates[1].close) && (ChikouSpan[0] >= rates[0].close))
   {
      ChikouPriceBull = false;
      ChikouPriceBear = true;
   }
   else if (ChikouSpan[1] == rates[1].close) // Voiding entry conditions if cross is ongoing.
   {
      ChikouPriceBull = false;
      ChikouPriceBear = false;
   }
   
   // Kumo confirmation. When cross is happening current price (latest close) should be above/below both Senkou Spans, or price should close above/below both Senkou Spans after a cross.
   if ((rates[Kijun + 1].close > SenkouSpanA[Kijun]) && (rates[Kijun + 1].close > SenkouSpanB[Kijun])) KumoBullConfirmation = true;
   else KumoBullConfirmation = false;
   if ((rates[Kijun + 1].close < SenkouSpanA[Kijun]) && (rates[Kijun + 1].close < SenkouSpanB[Kijun])) KumoBearConfirmation = true;
   else KumoBearConfirmation = false;
   
   // Kumo/Chikou confirmation. When cross is happening Chikou at its latest close should be above/below both Senkou Spans at that time, or it should close above/below both Senkou Spans after a cross.
   if ((ChikouSpan[1] > SenkouSpanA[0]) && (ChikouSpan[1] > SenkouSpanB[0])) KumoChikouBullConfirmation = true;
   else KumoChikouBullConfirmation = false;
   if ((ChikouSpan[1] < SenkouSpanA[0]) && (ChikouSpan[1] < SenkouSpanB[0])) KumoChikouBearConfirmation = true;
   else KumoChikouBearConfirmation = false;

   GetPositionStates();
   
   if (ChikouPriceBull)
   {
      if (HaveShortPosition) ClosePrevious();
      if ((KumoBullConfirmation) && (KumoChikouBullConfirmation))
      {
         ChikouPriceBull = false;
         fBuy();
      }
   }
   else if (ChikouPriceBear)
   {
      if (HaveLongPosition) ClosePrevious();
      if ((KumoBearConfirmation) && (KumoChikouBearConfirmation))
      {
         fSell();
         ChikouPriceBear = false;
      }
   }
}

//+------------------------------------------------------------------+
//| Check what position is currently open										|
//+------------------------------------------------------------------+
void GetPositionStates()
{
	// Is there a position on this currency pair?
	if (PositionInfo.Select(_Symbol))
	{
		if (PositionInfo.PositionType() == POSITION_TYPE_BUY)
		{
			HaveLongPosition = true;
			HaveShortPosition = false;
		}
		else if (PositionInfo.PositionType() == POSITION_TYPE_SELL)
		{ 
			HaveLongPosition = false;
			HaveShortPosition = true;
		}
	}
	else 
	{
		HaveLongPosition = false;
		HaveShortPosition = false;
	}
}

//+------------------------------------------------------------------+
//| Buy                                                              |
//+------------------------------------------------------------------+
void fBuy()
{
	double Ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
	Trade.PositionOpen(_Symbol, ORDER_TYPE_BUY, LotsOptimized(), Ask, 0, 0, OrderComment);
}

//+------------------------------------------------------------------+
//| Sell                                                             |
//+------------------------------------------------------------------+
void fSell()
{
	double Bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
	Trade.PositionOpen(_Symbol, ORDER_TYPE_SELL, LotsOptimized(), Bid, 0, 0, OrderComment);
}

//+------------------------------------------------------------------+
//| Calculate position size depending on money management parameters.|
//+------------------------------------------------------------------+
double LotsOptimized()
{
	if (!MM) return (Lots);
	
   double Size, RiskMoney, PositionSize = 0;

   // If could not find account currency, probably not connected.
   if (AccountInfoString(ACCOUNT_CURRENCY) == "") return(-1);

   if (FixedBalance > 0)
   {
      Size = FixedBalance;
   }
   else if (UseEquityInsteadOfBalance)
   {
      Size = AccountInfoDouble(ACCOUNT_EQUITY);
   }
   else
   {
      Size = AccountInfoDouble(ACCOUNT_BALANCE);
   }
   
   if (!UseMoneyInsteadOfPercentage) RiskMoney = Size * Risk / 100;
   else RiskMoney = MoneyRisk;

   double UnitCost = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double TickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if ((StopLoss != 0) && (UnitCost != 0) && (TickSize != 0)) PositionSize = NormalizeDouble(RiskMoney / (StopLoss * UnitCost / TickSize), LotDigits);

   if (PositionSize < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) PositionSize = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   else if (PositionSize > SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX)) PositionSize = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   return(PositionSize);
} 

//+------------------------------------------------------------------+
//| Close open position																|
//+------------------------------------------------------------------+
void ClosePrevious()
{
	for (int i = 0; i < 10; i++)
	{
		Trade.PositionClose(_Symbol, Slippage);
		if ((Trade.ResultRetcode() != 10008) && (Trade.ResultRetcode() != 10009) && (Trade.ResultRetcode() != 10010))
			Print("Position Close Return Code: ", Trade.ResultRetcodeDescription());
		else return;
	}
}
//+------------------------------------------------------------------+
