//+------------------------------------------------------------------+
//|                                                     rsi_grid.mq4 |
//|                                                          DerJens |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "DerJens"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

#include "../../Include/Arrays/ArrayInt.mqh";

enum ENTRYSIGNAL { ENTRY_LONG, ENTRY_SHORT, ENTRY_NONE };

struct FilterInfo {
   double entry;
   double ask;
   double bid;
   int    currentCountOfOpenPositions;
   double currentSizeOfOpenPositions;
   double pointsToRecover;
   double highestEntry;
   double lowestEntry;
   double martingaleDistance;

};

input string label0 = "" ; //+--- admin ---+
input int myMagic = 1;
input int tracelevel = 2;
input string chartLabel = "RSI grid";

input string label1 = "" ; //+--- entry signal ---+
input int rsiPeriod = 6;
input double rsiLowThreshold = 15;
input double rsiHighThreshold = 85;

input string label2 = ""; //+--- money management ---+
input double lots = 0.01;
input double maxLots = 3.00;
input double tpPoints = 400;
input double martingaleFactor = 3.0;
input double martingaleMinDistance = 100;
input double increaseSizeEvery = 1500.0;  //auto-scale (initial account size or 0.0 to disable)
input double emergencyExitRatio = 0.6; //emergency exit: balance/equity ratio (0.0 to disable)
input bool   pyramide = true; //new position size in profit

CArrayInt longTickets;
CArrayInt shortTickets;

static double currentLots = lots;
static double currentMaxLots = maxLots;
static datetime lastTradeTime = NULL;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//---
   Comment(chartLabel);
   
   longTickets.Clear();
   shortTickets.Clear();
   for (int i=OrdersTotal(); i>=0; i--) {
      if (OrderSelect(i, SELECT_BY_POS) && OrderMagicNumber() == myMagic) {
         if (StringCompare(OrderSymbol(), Symbol(),false)!=0) {
            PrintFormat("MagicNumber already in use!");          
            return INIT_FAILED;
         }
         if (OrderType() == OP_BUY) {
            longTickets.Add(OrderTicket());
         } else if ( OrderType() == OP_SELL) {
            shortTickets.Add(OrderTicket());
         }
      }
   }
   
   PrintFormat("Init: Point=%.5f",_Point);
   
   
//---
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//---
   
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
//---
   if (Time[0] == lastTradeTime) return;
   
   lastTradeTime = Time[0];
   
   if (emergencyExit()) return;
   scale();
   ENTRYSIGNAL entry = entrySignal();
   
   if (ENTRY_SHORT == entry) {
      int ticket = sell();
      if (ticket > -1) 
         shortTickets.Add(ticket);
   }
   
   if (ENTRY_LONG == entry) {
      int ticket = buy();
      if (ticket > -1) 
         longTickets.Add(ticket);
   }
   
  }
//+------------------------------------------------------------------+


int sell() {
   if (tracelevel>=2) PrintFormat("sell() > entry");
   
   FilterInfo filterInfo = assessShort();
   int ticket = -1;
   
   //exit if too close to current positions
   if (filterInfo.currentCountOfOpenPositions > 0 
      && martingaleMinDistance > MathAbs(filterInfo.martingaleDistance)) return ticket;
   
   //position sizing
   double size = currentLots;
   if (filterInfo.currentCountOfOpenPositions > 0) {
      size = MathPow(martingaleFactor,filterInfo.currentCountOfOpenPositions)*currentLots;
   }
   
   //don't escalate position size in profit
   if (filterInfo.martingaleDistance < 0.0) {
      if (pyramide) size = currentLots; else size = 0.0;
   }

   //limit max size      
   double totalSize = filterInfo.currentSizeOfOpenPositions + size;
   if (totalSize > currentMaxLots) {
      size = currentMaxLots - filterInfo.currentSizeOfOpenPositions;
      totalSize = currentMaxLots;
   }
   double totalTarget = (filterInfo.pointsToRecover + tpPoints)* currentLots / totalSize;
   double tp = filterInfo.entry - (totalTarget * _Point);
     
   if (size > 0)
      ticket = OrderSend(Symbol(),OP_SELL,size,filterInfo.entry,1000,0,tp,"rsi-grid",myMagic,0,clrRed);
   if (ticket>0) {
      for (int i=shortTickets.Total(); i>=0; i--) {
         if (OrderSelect(shortTickets.At(i),SELECT_BY_TICKET)) {
            if (StringCompare(OrderSymbol(), Symbol(),false)!=0) {
               string error = StringFormat("OrderSymbol=%s, Symbol=%",OrderSymbol(),Symbol());
               Comment("Error: " + error);
               PrintFormat("Error: " + error);
               continue;
            }
            if (ticket>0) {
               
               if (!OrderModify(OrderTicket(),0,0,tp,0,clrGreen)) {
                  PrintFormat("ERROR!");
               }
            }
         }
      }
   }
    if (tracelevel>=2) PrintFormat("sell() < exit %i", ticket);
   
   return ticket;
}

int buy() {
   if (tracelevel>=2) PrintFormat("buy() > entry");
    
   FilterInfo filterInfo = assessLong();
   int ticket = -1;
   
   //exit if too close to current positions
   if (filterInfo.currentCountOfOpenPositions> 0 
      && martingaleMinDistance > MathAbs(filterInfo.martingaleDistance)) return ticket;
   
     
   //postion sizing 
   double size = currentLots;
   if (filterInfo.currentCountOfOpenPositions>0) {
      size = MathPow(martingaleFactor, filterInfo.currentCountOfOpenPositions) * currentLots;
   }
   
   //don't escalate position size in profit
   if (filterInfo.martingaleDistance < 0.0) {
      if (pyramide) size = currentLots; else size = 0.0;
   }   
   
   //limit max size 
   double totalSize = filterInfo.currentSizeOfOpenPositions + size;
   if (totalSize > currentMaxLots) {
      size = currentMaxLots - filterInfo.currentSizeOfOpenPositions;
      totalSize = currentMaxLots;
   }
   double totalTarget = (filterInfo.pointsToRecover + tpPoints) * currentLots / totalSize;
   double tp = filterInfo.entry + (totalTarget * _Point);
   
   if (size > 0.0)
      ticket = OrderSend(Symbol(),OP_BUY,size,filterInfo.entry,1000,0,tp,"rsi-grid",myMagic,0,clrGreen);
   
   if (ticket>0) {
      for (int i=longTickets.Total(); i>=0; i--) {
         if (OrderSelect(longTickets.At(i),SELECT_BY_TICKET)) {
            if (StringCompare(OrderSymbol(), Symbol(),false)!=0) {
               Comment("Two Chart Windows run RSI-Grid EA with the same Magic Number!");
               PrintFormat("Two Chart Windows run RSI-Grid EA with the same Magic Number!");
               continue;
            }
            if (ticket>0) {
               if (!OrderModify(OrderTicket(),0,0,tp,0,clrGreen)) {
                  PrintFormat("ERROR!");
               }
            }
         }
      }
   } 
   
   if (tracelevel>=2) PrintFormat("buy() < exit %i", ticket);   
   
   return ticket;
}

bool emergencyExit() {
   if (AccountEquity() / AccountBalance() < emergencyExitRatio) { 
      Print("Emergency");
      for (int i=shortTickets.Total(); i>=0; i--) {
         if (OrderSelect(shortTickets.At(i),SELECT_BY_TICKET)) {
            OrderClose(OrderTicket(),OrderLots(),Bid,1000,clrRed);
         }
      }
      for (int i=longTickets.Total(); i>=0; i--) {
         if (OrderSelect(longTickets.At(i),SELECT_BY_TICKET)) {
            OrderClose(OrderTicket(),OrderLots(),Ask,1000,clrRed);
         }
      }
      return true;
   }
   return false;
}

void scale() {
   if (tracelevel>=2) PrintFormat("scale() > entry: increaseSizeEvery=%.2f, equity=%.2f",increaseSizeEvery,AccountEquity());
   if (increaseSizeEvery > 0.0) {
      currentLots = NormalizeDouble(AccountEquity() / increaseSizeEvery * lots,_Digits);
      if (currentLots<lots) currentLots = lots;
      currentMaxLots = NormalizeDouble(AccountEquity() / increaseSizeEvery * maxLots,_Digits);
      if (currentMaxLots < maxLots) currentMaxLots = maxLots;
   }
   
   if (tracelevel>=2) PrintFormat("scale() < exit: lots=%.2f, maxlots=%.2f",currentLots,currentMaxLots);
}

ENTRYSIGNAL entrySignal() {
   if (tracelevel>=2) PrintFormat("entrySignal() > entry");
   ENTRYSIGNAL signal = ENTRY_NONE;
   
   double rsi = iRSI(Symbol(),PERIOD_CURRENT,rsiPeriod,PRICE_CLOSE,1);
   double rsiPrev = iRSI(Symbol(),PERIOD_CURRENT,rsiPeriod,PRICE_CLOSE,2);
   
   if (tracelevel>=2) PrintFormat("entrySignal 2: RSI[1]=%.2f, RSI[2]=%.2f",rsi,rsiPrev);
   
   if (rsiPrev > rsiHighThreshold && rsi < rsiHighThreshold) signal = ENTRY_SHORT;
   if (rsiPrev < rsiLowThreshold && rsi > rsiLowThreshold)   signal = ENTRY_LONG;
   
   
   if (tracelevel>=2) PrintFormat("entrySignal() < exit: signal=",signal);
   return signal;
}

FilterInfo assessShort() {
   if (tracelevel>=2) PrintFormat("assessShort() > entry"); 
 
   FilterInfo filterInfo = {};
   filterInfo.ask = NormalizeDouble(Ask, _Digits);
   filterInfo.bid = NormalizeDouble(Bid, _Digits);;
   filterInfo.entry = NormalizeDouble(Bid, _Digits);;
   filterInfo.currentSizeOfOpenPositions = 0.0;
   filterInfo.currentCountOfOpenPositions = 0;
   filterInfo.pointsToRecover = 0.0;
   filterInfo.highestEntry = -1.0;
   filterInfo.lowestEntry = -1.0;
   
   for (int i=shortTickets.Total(); i>=0; i--) {
      if (OrderSelect(shortTickets.At(i),SELECT_BY_TICKET)) {
         if (StringCompare(OrderSymbol(), Symbol(),false)!=0) {
            string error = StringFormat("OrderSymbol=%s, Symbol=%",OrderSymbol(),Symbol());
            Comment("Error: " + error);
            PrintFormat("Error: " + error);
            continue;
         }
         if (OrderCloseTime()!=0) {
            shortTickets.Delete(i);
         } else {
            filterInfo.currentCountOfOpenPositions++;
            filterInfo.currentSizeOfOpenPositions+=OrderLots();
            filterInfo.pointsToRecover += ((filterInfo.ask-OrderOpenPrice())*(OrderLots()/currentLots))/_Point;
         }
         if (filterInfo.highestEntry < 0 || filterInfo.highestEntry < OrderOpenPrice()) {
            filterInfo.highestEntry = OrderOpenPrice();
         }
         if (filterInfo.lowestEntry < 0 || filterInfo.lowestEntry > OrderOpenPrice()) {
            filterInfo.lowestEntry = OrderOpenPrice();
         }
      }
   }
   
   if (filterInfo.highestEntry > 0.0) {
      filterInfo.martingaleDistance = (filterInfo.entry - filterInfo.highestEntry) / _Point;
      if (filterInfo.entry < filterInfo.lowestEntry) {
         filterInfo.martingaleDistance = (filterInfo.entry - filterInfo.lowestEntry) / _Point; 
      }
   } 
   
   if (tracelevel>=2) PrintFormat("assessShort() < exit: count=%i", filterInfo.currentCountOfOpenPositions);
   return filterInfo;
}

FilterInfo assessLong() {
   if (tracelevel>=2) PrintFormat("assessLong() > entry"); 
 
   FilterInfo filterInfo = {};
   filterInfo.ask = NormalizeDouble(Ask, _Digits);
   filterInfo.bid = NormalizeDouble(Bid, _Digits);   
   filterInfo.entry = NormalizeDouble(Ask, _Digits);;
   filterInfo.currentSizeOfOpenPositions = 0.0;
   filterInfo.currentCountOfOpenPositions = 0;
   filterInfo.pointsToRecover = 0.0;
   filterInfo.highestEntry = -1.0;
   filterInfo.lowestEntry = -1.0;
   filterInfo.martingaleDistance = 0.0;
   
   for (int i=longTickets.Total(); i>=0; i--) {
      if (OrderSelect(longTickets.At(i),SELECT_BY_TICKET)) {
         if (StringCompare(OrderSymbol(), Symbol(),false)!=0) {
            string error = StringFormat("OrderSymbol=%s, Symbol=%",OrderSymbol(),Symbol());
            Comment("Error: " + error);
            PrintFormat("Error: " + error);
            continue;
         }
         if (OrderCloseTime()!=0) {
            longTickets.Delete(i);
         } else {
            filterInfo.currentCountOfOpenPositions++;
            filterInfo.currentSizeOfOpenPositions+=OrderLots();
            filterInfo.pointsToRecover += ((OrderOpenPrice()-filterInfo.bid)*(OrderLots()/currentLots))/_Point;
               
            if (filterInfo.lowestEntry < 0 || filterInfo.lowestEntry > OrderOpenPrice()) {
               filterInfo.lowestEntry = OrderOpenPrice();
            }
            if (filterInfo.highestEntry < 0 || filterInfo.highestEntry < OrderOpenPrice()) {
               filterInfo.highestEntry = OrderOpenPrice();
            }      
         }
      }
   }  
   
   if (filterInfo.lowestEntry > 0.0) {
      filterInfo.martingaleDistance = (filterInfo.lowestEntry - filterInfo.entry) / _Point;
      if (filterInfo.entry > filterInfo.highestEntry) {
         filterInfo.martingaleDistance = (filterInfo.highestEntry - filterInfo.entry) / _Point; 
      }
   } 
   PrintFormat("JENS: lowest=%.2f, highest=%.2f, entry=%.2f, dist=%.2f",filterInfo.lowestEntry, filterInfo.highestEntry, filterInfo.entry, filterInfo.martingaleDistance);
   
   if (tracelevel>=2) PrintFormat("assessLong() < exit: dist=%.2f", filterInfo.martingaleDistance);
   return filterInfo;
}