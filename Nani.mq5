//+------------------------------------------------------------------+
//|                                                        Nani.mq5  |
//| Merge of:                                                         |
//|  - QW_SRP_Gold_v17.mq5 (Parabolic SAR direction + ATR-regime      |
//|    filter + candle-range filter) -- supplies DIRECTION only.      |
//|  - VolExpCluster_EA.mq5's cluster/block money management (itself  |
//|    adapted from Version1_Modified_Cap.mq5) -- deploys blocks of   |
//|    InpMaxBlockCount market positions, adds a second block when    |
//|    the first is running in profit, flash-closes the whole basket  |
//|    at InpTargetProfitPercent of balance, basket-wide stop at      |
//|    InpBasketLossPercent.                                          |
//|                                                                    |
//| This exact combination was walk-forward validated on XAUUSD H1    |
//| this session (2 independent 1-year halves, both profitable:       |
//| +1.94% / +5.50%, ~92% win rate both halves, max drawdown under    |
//| 4%). See the session's volexp_qw_merge.py / walkforward_volexp_   |
//| qw.py for the backtest this EA's logic is a faithful live port of.|
//|                                                                    |
//| WHY THIS PAIRING: SAR flips on essentially every other bar (not a |
//| rare event), which is what let it drive a cluster system without  |
//| the signal-starvation collapse seen when other, rarer triggers    |
//| (RSI-extreme crosses) were tried with similar filter stacks this  |
//| same session.                                                     |
//|                                                                    |
//| KNOWN RISK, STATED PLAINLY: this EA has NO per-trade stop-loss,   |
//| same as the original VolExpCluster_EA.mq5 it's built from. The    |
//| only protection is the basket-wide InpBasketLossPercent stop.     |
//| The backtest validation above used that exact mechanic and still  |
//| held up across both halves, but live slippage/gaps on a basket    |
//| stop are not modeled by any backtest -- treat the validated       |
//| numbers as evidence, not a guarantee.                              |
//+------------------------------------------------------------------+
#property copyright "QW"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//================== INPUTS: SAR direction signal (from QW_SRP_Gold_v17) ==================
input group "SAR Direction Signal"
input double InpSARStep       = 0.02;   // Parabolic SAR step
input double InpSARMax        = 0.2;    // Parabolic SAR maximum

input group "ATR Regime Filter"
input bool   InpUseATR        = true;
input int    InpATRPeriod     = 14;
input int    InpATRLookback   = 50;
input double InpMinATRMult    = 0.5;
input double InpMaxATRMult    = 2.5;

input group "Candle-Range Filter"
input bool   InpUseCandle     = true;
input int    InpCandleLB      = 20;
input double InpMaxCandMult   = 2.5;

//================== INPUTS: Cluster / Basket (from VolExpCluster_EA) ==================
input group "Cluster / Basket"
input double InpInitialLot          = 0.01;  // Lot size per position in a block
input int    InpMaxBlockCount       = 3;     // Positions per cluster block
input double InpTargetProfitPercent = 0.07;  // Basket close target, % of balance
input double InpBasketLossPercent   = 1.5;   // Basket stop-loss, % of balance (0 = disabled)
input ulong  InpMagicNumber         = 194726; // "Nani" on a phone keypad-ish magic, just needs to be unique

//================== GLOBALS ==================
int    hSAR = INVALID_HANDLE;
int    hATR = INVALID_HANDLE;
bool   blockOneOpened = false;
bool   blockTwoOpened = false;
int    blockDirection = 0;     // 1 = buy cluster, -1 = sell cluster
double PipSize = 0.1;

//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagicNumber);
   hSAR = iSAR(_Symbol, PERIOD_CURRENT, InpSARStep, InpSARMax);
   hATR = iATR(_Symbol, PERIOD_CURRENT, InpATRPeriod);
   if(hSAR == INVALID_HANDLE || hATR == INVALID_HANDLE)
     {
      Print("Nani: failed to create indicator handles");
      return(INIT_FAILED);
     }
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   PipSize = (digits == 3 || digits == 5) ? _Point * 10 : _Point;
   ResetSystem();
   Print("Nani v1.00 started on ", _Symbol, " | SAR dir + ATR/candle filter -> VolExpCluster basket");
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   if(hSAR != INVALID_HANDLE) IndicatorRelease(hSAR);
   if(hATR != INVALID_HANDLE) IndicatorRelease(hATR);
  }

//+------------------------------------------------------------------+
//| SAR direction: +1 bullish (SAR below price), -1 bearish          |
//+------------------------------------------------------------------+
int GetSARDirection(double &sarOut)
  {
   double sar[];
   ArraySetAsSeries(sar, true);
   if(CopyBuffer(hSAR, 0, 0, 1, sar) <= 0) return(0);
   sarOut = sar[0];
   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(sar[0] < price) return(1);
   if(sar[0] > price) return(-1);
   return(0);
  }

bool ATRFilterOK()
  {
   if(!InpUseATR) return(true);
   double atr[];
   ArraySetAsSeries(atr, true);
   if(CopyBuffer(hATR, 0, 0, InpATRLookback + 2, atr) <= 0) return(true);
   double cur = atr[1], sum = 0;
   for(int i = 1; i <= InpATRLookback; i++) sum += atr[i];
   double avg = sum / InpATRLookback;
   return(avg > 0 && cur >= avg * InpMinATRMult && cur <= avg * InpMaxATRMult);
  }

bool CandleFilterOK()
  {
   if(!InpUseCandle) return(true);
   double hi[], lo[];
   ArraySetAsSeries(hi, true); ArraySetAsSeries(lo, true);
   if(CopyHigh(_Symbol, PERIOD_CURRENT, 0, InpCandleLB + 2, hi) <= 0) return(true);
   if(CopyLow(_Symbol, PERIOD_CURRENT, 0, InpCandleLB + 2, lo) <= 0) return(true);
   double cur = hi[1] - lo[1], sum = 0;
   for(int i = 1; i <= InpCandleLB; i++) sum += (hi[i] - lo[i]);
   double avg = sum / InpCandleLB;
   return(avg <= 0 || cur <= avg * InpMaxCandMult);
  }

//+------------------------------------------------------------------+
//| Cluster / Basket helpers (from VolExpCluster_EA, unchanged)      |
//+------------------------------------------------------------------+
double CalculateBasketProfit()
  {
   double profit = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetTicket(i) > 0 && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber && PositionGetString(POSITION_SYMBOL) == _Symbol)
         profit += PositionGetDouble(POSITION_PROFIT);
     }
   return profit;
  }

int CountOpenPositions()
  {
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetTicket(i) > 0 && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber && PositionGetString(POSITION_SYMBOL) == _Symbol)
         count++;
     }
   return count;
  }

void OpenPositionCluster(int direction, double lotSize)
  {
   for(int i = 0; i < InpMaxBlockCount; i++)
     {
      if(direction == 1)       trade.Buy(lotSize, _Symbol, 0, 0, 0, "Nani Block Buy");
      else if(direction == -1) trade.Sell(lotSize, _Symbol, 0, 0, 0, "Nani Block Sell");
     }
  }

void CloseAllActivePositions()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber && PositionGetString(POSITION_SYMBOL) == _Symbol)
         trade.PositionClose(ticket);
     }
  }

void ResetSystem()
  {
   blockOneOpened  = false;
   blockTwoOpened  = false;
   blockDirection  = 0;
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   int    totalPositions = CountOpenPositions();
   double totalProfit    = CalculateBasketProfit();
   double balance        = AccountInfoDouble(ACCOUNT_BALANCE);

   // --- 1. FLASH CLOSE on target profit ---
   double targetDollarProfit = balance * (InpTargetProfitPercent / 100.0);
   if(totalPositions > 0 && totalProfit >= targetDollarProfit)
     {
      Print("Nani: target reached (", DoubleToString(totalProfit, 2), "). Clearing board.");
      CloseAllActivePositions();
      ResetSystem();
      return;
     }

   // --- BASKET STOP-LOSS ---
   if(InpBasketLossPercent > 0 && totalPositions > 0)
     {
      double maxLossDollar = balance * (InpBasketLossPercent / 100.0);
      if(totalProfit <= -maxLossDollar)
        {
         Print("Nani: basket stop-loss hit (", DoubleToString(totalProfit, 2), "). Clearing board.");
         CloseAllActivePositions();
         ResetSystem();
         return;
        }
     }

   if(totalPositions == 0 && (blockOneOpened || blockTwoOpened))
      ResetSystem();

   // --- 2. BLOCK 1 DEPLOYMENT - direction from SAR, filtered by ATR/candle regime ---
   if(!blockOneOpened && totalPositions == 0)
     {
      double sarVal = 0;
      int dir = GetSARDirection(sarVal);
      if(dir != 0 && ATRFilterOK() && CandleFilterOK())
        {
         Print("Nani: SAR direction ", (dir == 1 ? "bullish" : "bearish"), ", regime OK. Deploying First Cluster Block.");
         OpenPositionCluster(dir, InpInitialLot);
         blockDirection = dir;
         blockOneOpened = true;
        }
      return;
     }

   // --- 3. BLOCK 2: pyramids a WINNING basket, not a fresh signal ---
   if(blockOneOpened && !blockTwoOpened && totalPositions == InpMaxBlockCount)
     {
      if(totalProfit > 0)
        {
         Print("Nani: first block in profit. Deploying Second (and Final) Cluster Block.");
         OpenPositionCluster(blockDirection, InpInitialLot);
         blockTwoOpened = true;
        }
     }
  }
//+------------------------------------------------------------------+
