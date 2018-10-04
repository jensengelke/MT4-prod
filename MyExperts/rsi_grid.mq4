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

input string label0 = "" ; //+--- admin ---+
input int myMagic = 20180819;
input int tracelevel = 2;
input string chartLabel = "RSI grid";

input string label1 = "" ; //+--- entry signal ---+
input int rsiPeriod = 12;
input double rsiLowThreshold = 25;
input double rsiHighThreshold = 85;

input string label2 = ""; //+--- money management ---+
input double lots = 0.01;
input double maxLots = 3.00;
input double tpPoints = 400;
input double martingaleFactor = 3.0;
input double martingaleMinDistance = 100;
input double increaseSizeEvery = 1500.0;
input double emergencyExit = 0.6;

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
   
   if (AccountEquity() / AccountBalance() < emergencyExit) { 
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
      
   }
   
   currentLots = NormalizeDouble(AccountEquity() / increaseSizeEvery * lots,_Digits);
   if (currentLots<lots) currentLots = lots;
   currentMaxLots = NormalizeDouble(AccountEquity() / increaseSizeEvery * maxLots,_Digits);
   if (currentMaxLots < maxLots) currentMaxLots = maxLots;
   
   if (tracelevel>=2) PrintFormat("lots=%.2f,maxlots=%.2f",currentLots,currentMaxLots);
   
   double rsi = iRSI(Symbol(),PERIOD_CURRENT,rsiPeriod,PRICE_CLOSE,1);
   double rsiPrev = iRSI(Symbol(),PERIOD_CURRENT,rsiPeriod,PRICE_CLOSE,2);
   
   if (tracelevel>=2) {
      PrintFormat("RSI[1]=%.2f, RSI[2]=%.2f",rsi,rsiPrev);
   }
   
   if (rsiPrev > rsiHighThreshold && rsi < rsiHighThreshold) {
      //short signal
      int ticket = sell();
      if (ticket > -1) 
         shortTickets.Add(ticket);
      
   }
   
   if (rsiPrev < rsiLowThreshold && rsi > rsiLowThreshold) {
      //long signal
      int ticket = buy();
      if (ticket > -1) 
         longTickets.Add(ticket);
   }
   
  }
//+------------------------------------------------------------------+


int sell() {
   if (tracelevel>=2) {
      PrintFormat("ENTRY sell()");
   }
   double entry = NormalizeDouble(Bid, _Digits);
   double ask = NormalizeDouble(Ask, _Digits);
   int ticket = -1;
   
   double currentSizeOfOpenPositions = 0.0;
   int currentCountOfOpenPositions = 0;
   
   double pointsToRecover = 0.0;
   double highestEntry = -1.0;
   
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
            currentCountOfOpenPositions++;
            currentSizeOfOpenPositions+=OrderLots();
            pointsToRecover += ((ask-OrderOpenPrice())*(OrderLots()/currentLots))/_Point;
            pointsToRecover += OrderSwap()/MarketInfo(OrderSymbol(),MODE_TICKVALUE);
            pointsToRecover += OrderCommission()/MarketInfo(OrderSymbol(),MODE_TICKVALUE);
            if (tracelevel >= 2) {
               PrintFormat("SELL: thisEntry=%.5f, orderEntry=%.5f, orderSize=%.2f, currentLots=%.2f, pointsToRecover=%.5f",
                  entry,
                  OrderOpenPrice(),
                  OrderLots(),
                  currentLots,
                  pointsToRecover);
            }
         }
         if (highestEntry < 0 || highestEntry < OrderOpenPrice()) {
            highestEntry = OrderOpenPrice();
         }
      }
   }
   
   if (highestEntry > 0.0) {
      double martingaleDistance = (entry -highestEntry)/_Point;
      if (martingaleDistance < martingaleMinDistance) {
         if (tracelevel>=1) {
            PrintFormat("SKIPPING SELL signal: current price is %.2f (less than martingaleMinDistance: %.2f) points away from highest entry", martingaleDistance, martingaleMinDistance);
         }
         return ticket;
      }
   }
   
   double size = currentLots;
   if (currentCountOfOpenPositions > 0) {
      size = MathPow(martingaleFactor,currentCountOfOpenPositions)*currentLots;
   }
   
   
   double totalSize = currentSizeOfOpenPositions + size;
   if (totalSize > currentMaxLots) {
      size = currentMaxLots - currentSizeOfOpenPositions;
      totalSize = currentMaxLots;
   }
   double totalTarget = (pointsToRecover + tpPoints)*currentLots/totalSize;
   double tp = entry - (totalTarget*_Point);
     
   if (size > 0)
      ticket = OrderSend(Symbol(),OP_SELL,size,entry,1000,0,tp,"rsi-grid",myMagic,0,clrRed);
   if (ticket>0) {
      for (int i=shortTickets.Total(); i>=0; i--) {
         
         if (OrderSelect(shortTickets.At(i),SELECT_BY_TICKET)) {
            if (StringCompare(OrderSymbol(), Symbol(),false)!=0) {
               string error = StringFormat("OrderSymbol=%s, Symbol=%",OrderSymbol(),Symbol());
               Comment("Error: " + error);
               PrintFormat("Error: " + error);
               continue;
            }
            if (!OrderModify(OrderTicket(),0,0,tp,0,clrGreen)) {
               PrintFormat("ERROR!");
            }
         }
      }
   }
   return ticket;
}

int buy() {
   if (tracelevel>=2) {
      PrintFormat("ENTRY buy()");
   }
   double entry = NormalizeDouble(Ask, _Digits);
   double bid = NormalizeDouble(Bid, _Digits);
   int ticket = -1;
   
   double currentSizeOfOpenPositions = 0.0;
   int currentCountOfOpenPositions = 0;
   double pointsToRecover = 0.0;
   double lowestEntry = -1.0;
   
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
            currentCountOfOpenPositions++;
            currentSizeOfOpenPositions+=OrderLots();
            pointsToRecover += ((OrderOpenPrice()-bid)*(OrderLots()/currentLots))/_Point;
            pointsToRecover += OrderSwap()/MarketInfo(OrderSymbol(),MODE_TICKVALUE);
            pointsToRecover += OrderCommission()/MarketInfo(OrderSymbol(),MODE_TICKVALUE);
            if (tracelevel >=2) {
               PrintFormat("BUY: thisEntry=%.5f, orderEntry=%.5f, orderSize=%.2f, currentLots=%.2f, pointsToRecover=%.5f",
                  entry,
                  OrderOpenPrice(),
                  OrderLots(),
                  currentLots,
                  pointsToRecover);
            }
               
            if (lowestEntry < 0 || lowestEntry > OrderOpenPrice()) {
            lowestEntry = OrderOpenPrice();
         }      
         }
      }
   }
   
   if (lowestEntry > 0.0) {
      double martingaleDistance = (lowestEntry - entry)/_Point;
      if (martingaleDistance < martingaleMinDistance) {
         if (tracelevel>=1) {
            PrintFormat("SKIPPING BUY signal: current price is %.2f (less than martingaleMinDistance: %.2f) points away from highest entry", martingaleDistance, martingaleMinDistance);
         }
         return ticket;
      }
   }
      
   double size = currentLots;
   if (currentCountOfOpenPositions>0) {
      size = MathPow(martingaleFactor,currentCountOfOpenPositions)*currentLots;
   }
   
   
   double totalSize = currentSizeOfOpenPositions + size;
   if (totalSize > currentMaxLots) {
      size = currentMaxLots - currentSizeOfOpenPositions;
      totalSize = currentMaxLots;
   }
   double totalTarget = (pointsToRecover + tpPoints)*currentLots/totalSize;
   double tp = entry + (totalTarget*_Point);
   
   if (size > 0.0)
      ticket = OrderSend(Symbol(),OP_BUY,size,entry,1000,0,tp,"rsi-grid",myMagic,0,clrGreen);
   
   if (ticket>0) {
      for (int i=longTickets.Total(); i>=0; i--) {
         if (OrderSelect(longTickets.At(i),SELECT_BY_TICKET)) {
            if (StringCompare(OrderSymbol(), Symbol(),false)!=0) {
               Comment("Two Chart Windows run RSI-Grid EA with the same Magic Number!");
               PrintFormat("Two Chart Windows run RSI-Grid EA with the same Magic Number!");
               continue;
            }
         if (!OrderModify(OrderTicket(),0,0,tp,0,clrGreen)) {
               PrintFormat("ERROR!");
            }
         }
      }
   }
   
   
   return ticket;
}