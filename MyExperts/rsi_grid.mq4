//+------------------------------------------------------------------+
//|                                                     rsi_grid.mq4 |
//|                                                          DerJens |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "DerJens"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

#include <Arrays/ArrayInt.mqh>
#include <Arrays/ArrayObj.mqh>

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

class CCost : public CObject {
   private:
    int    m_ticket;  
    double m_commission;
    double m_swap;  
  public:
    CCost(void);
    CCost(int ticket, double commission, double swap);
    int GetTicket() { return m_ticket;};
    double GetSwap() { return m_swap;};
    double GetCommission() { return m_commission;};
    void   SetCommission(double commission) { m_commission = commission;};
    void   SetSwap(double swap) { m_swap = swap;};
    
      
};

input string label0 = "" ; //+--- admin ---+
input int    myMagic = 1;
input int    tracelevel = 2;
input bool   backtest = true; //display balance and equity in chart
input string chartLabel = "RSI grid";

input string label1 = "" ; //+--- entry signal ---+
input int    rsiPeriod = 6;
input double rsiDistance = 15.0; //RSI threshold in % from upper and lower end

input string label2 = ""; //+--- money management ---+
input double lots = 0.01;
input int    maxPositions = 6; //max number of positions
input double tpPoints = 400;
input double martingaleFactor = 2.5;
input double martingaleMinDistance = 100;
input double increaseSizeEvery = 1500.0;  //auto-scale (initial account size or 0.0 to disable)
input double emergencyExitRatio = 0.6; //emergency exit: balance/equity ratio (0.0 to disable)
input bool   pyramide = true; //new position size in profit
input bool   abortInEmergency = true;
double rsiLowThreshold = rsiDistance;
double rsiHighThreshold = 100 - rsiDistance;

static CArrayInt longTickets;
static CArrayInt shortTickets;
static CArrayObj *costsLong; 
static CArrayObj *costsShort;

bool aborted = false;

static double currentLots = lots;
static datetime lastTradeTime = NULL;
static double lastRsiPrev = -1.0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//---
   Comment(chartLabel);
   
   if (pyramide && tpPoints < martingaleMinDistance) {        
      PrintFormat("E0001 Cannot increase position size in profit");
      return (INIT_PARAMETERS_INCORRECT);    
   }
   
   longTickets.Clear();
   shortTickets.Clear();
   costsLong = new CArrayObj();
   costsLong.Clear();
   costsShort = new CArrayObj();
   costsShort.Clear();
   
   
   for (int i=OrdersTotal(); i>=0; i--) {
      if (OrderSelect(i, SELECT_BY_POS) && OrderMagicNumber() == myMagic) {
         if (StringCompare(OrderSymbol(), Symbol(),false)!=0) {
            PrintFormat("E0002 MagicNumber already in use!");          
            return INIT_FAILED;
         }
         if (OrderType() == OP_BUY) {
            longTickets.Add(OrderTicket());
            costsLong.Add(new CCost(OrderTicket(), OrderCommission(), OrderSwap()));
         } else if ( OrderType() == OP_SELL) {
            shortTickets.Add(OrderTicket());
            costsShort.Add(new CCost(OrderTicket(), OrderCommission(), OrderSwap()));
         }
         
         
      }
   }
   
   PrintFormat("I0001 Init: Point=%.5f",_Point);
   
//---
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
  
      int file = FileOpen("backtest.csv", FILE_WRITE | FILE_CSV, ";"); 
      for (int i=OrdersHistoryTotal();i>=0;i--) {
         if (OrderSelect(i,SELECT_BY_POS,MODE_HISTORY)) {
            string direction = "LONG";
            if (OrderType()==OP_SELL) direction = "SHORT";
         
            FileWrite(file, 
               OrderTicket(),
               OrderSymbol(),
               NormalizeDouble(OrderLots(),2),
               direction,
               NormalizeDouble(OrderOpenPrice(),5),
               TimeToStr(OrderOpenTime(),TIME_DATE | TIME_SECONDS),  
               NormalizeDouble(OrderClosePrice(),5),
               TimeToStr(OrderCloseTime(),TIME_DATE | TIME_SECONDS),  
               NormalizeDouble(OrderCommission(),2),
               NormalizeDouble(OrderSwap(),2),
               NormalizeDouble(OrderProfit(),2),
               NormalizeDouble(OrderStopLoss(),5),
               NormalizeDouble(OrderTakeProfit(),5),
               OrderComment()
             );
         }
      }
      FileFlush(file);
      FileClose(file);
      
      delete(costsLong);
      delete(costsShort);
      
      PrintFormat("I0002 deinit - file closed.");
     
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {

   if (emergencyExit() && abortInEmergency) return;
   
   double rsiPrev = iRSI(Symbol(),PERIOD_CURRENT,rsiPeriod,PRICE_CLOSE,1);
   if (lastRsiPrev == rsiPrev) return;
   lastRsiPrev = rsiPrev;
   //if (Time[0] == lastTradeTime) return;   
   //lastTradeTime = Time[0];   
   
   if (backtest) Comment("balance: ", AccountBalance(), ", equity: ", AccountEquity());
   
   considerCosts();
   
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
      && (martingaleMinDistance * filterInfo.currentCountOfOpenPositions) > MathAbs(filterInfo.martingaleDistance)) {
      if (tracelevel>=2) PrintFormat("I0021 not opening new short position: too close %.5f, minDistance=%.5f",
         MathAbs(filterInfo.martingaleDistance),
         martingaleMinDistance * filterInfo.currentCountOfOpenPositions);         
      return ticket;
   }
   
   //position sizing
   double size = currentLots;
   if (filterInfo.currentCountOfOpenPositions > 0 && filterInfo.currentCountOfOpenPositions <= maxPositions) {
      size = MathPow(martingaleFactor,filterInfo.currentCountOfOpenPositions)*currentLots;
   }
   
   //don't escalate position size in profit
   if (filterInfo.martingaleDistance < 0.0) {
      if (pyramide) size = currentLots; else size = 0.0;
   }
   if (size == 0) return ticket;
   
   double totalSize = filterInfo.currentSizeOfOpenPositions + size;
   
   double totalTarget = (filterInfo.pointsToRecover + tpPoints)* currentLots / totalSize;
   double tp = filterInfo.entry - (totalTarget * _Point);
      
   ticket = OrderSend(Symbol(),OP_SELL,size,filterInfo.entry,20,0,tp,"rsi-grid",myMagic,0,clrRed);      
   
   if (ticket>0 && OrderSelect(ticket,SELECT_BY_TICKET)) {
      costsShort.Add(new CCost(OrderTicket(),0.0, 0.0));
      for (int i=shortTickets.Total(); i>=0; i--) {
         if (OrderSelect(shortTickets.At(i),SELECT_BY_TICKET)) {
            if (StringCompare(OrderSymbol(), Symbol(),false)!=0) {
               string error = StringFormat("OrderSymbol=%s, Symbol=%",OrderSymbol(),Symbol());
               Comment("Error: " + error);
               PrintFormat("E0003: " + error);
               continue;
            }
            
            if (tp != OrderTakeProfit()) {
               if (!OrderModify(OrderTicket(),0,OrderStopLoss(),tp,0,clrGreen)) {
                  PrintFormat("E0004");
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
      && (martingaleMinDistance * filterInfo.currentCountOfOpenPositions) > MathAbs(filterInfo.martingaleDistance)) {
      if (tracelevel>=2) PrintFormat("I0022 not opening new long position: too close %.5f, minDistance=%.5f",
         MathAbs(filterInfo.martingaleDistance),
         martingaleMinDistance * filterInfo.currentCountOfOpenPositions);
      return ticket;
   }
   
     
   //postion sizing 
   double size = currentLots;
   if (filterInfo.currentCountOfOpenPositions>0) {
      size = MathPow(martingaleFactor, filterInfo.currentCountOfOpenPositions) * currentLots;
   }
   
   //don't escalate position size in profit
   if (filterInfo.martingaleDistance < 0.0) {
      if (pyramide) size = currentLots; else size = 0.0;
   }   
   
   if (size == 0.0) return ticket;
   
   double totalSize = filterInfo.currentSizeOfOpenPositions + size;
   double totalTarget = (filterInfo.pointsToRecover + tpPoints) * currentLots / totalSize;
   double tp = filterInfo.entry + (totalTarget * _Point);
    
   ticket = OrderSend(Symbol(),OP_BUY,size,filterInfo.entry,20,0,tp,"rsi-grid",myMagic,0,clrGreen);
   
   if (ticket>0 && OrderSelect(ticket,SELECT_BY_TICKET)) {
      costsLong.Add(new CCost(OrderTicket(), 0.0,0.0));
      
      for (int i=longTickets.Total(); i>=0; i--) {
         if (OrderSelect(longTickets.At(i),SELECT_BY_TICKET)) {
            if (StringCompare(OrderSymbol(), Symbol(),false)!=0) {
               string error = StringFormat("OrderSymbol=%s, Symbol=%",OrderSymbol(),Symbol());
               Comment("Error: " + error);
               PrintFormat("E0005: " + error);
               continue;
            }
            
            if (tp != OrderTakeProfit()) {
               if (!OrderModify(OrderTicket(),0,OrderStopLoss(),tp,0,clrGreen)) {
                  PrintFormat("E0006");
               }
            }   
         }
      }
   }
   
   if (tracelevel>=2) PrintFormat("buy() < exit %i", ticket);   
   
   return ticket;
}

bool emergencyExit() {
   
   if (!aborted || !abortInEmergency) {
      int largestTicket = -1;
      double largestSize = 0.0;
      if (AccountEquity() / AccountBalance() < emergencyExitRatio) { 
         Print("Emergency");
         for (int i=shortTickets.Total(); i>=0; i--) {
            if (OrderSelect(shortTickets.At(i),SELECT_BY_TICKET)) {
               if (OrderCloseTime()==0) {
                  if (!OrderClose(OrderTicket(),OrderLots(),Bid,1000,clrRed)) {
                     PrintFormat("E0007 - cannot close order ?!");
                  }
               }
            }
         }
         
         for (int i=longTickets.Total(); i>=0; i--) {
            if (OrderSelect(longTickets.At(i),SELECT_BY_TICKET)) {
               if (OrderCloseTime()==0) {
                  if (!OrderClose(OrderTicket(),OrderLots(),Ask,1000,clrRed)) {
                     PrintFormat("E0008 - cannot close order ?!");
                  }
               }
            }
         }
         aborted = true;
      }
   }
   return aborted;
}

void scale() {
   if (tracelevel>=2) PrintFormat("scale() > entry: increaseSizeEvery=%.2f, equity=%.2f",increaseSizeEvery,AccountEquity());
   if (increaseSizeEvery > 0.0) {
      int factor = (int)(AccountEquity() / increaseSizeEvery);
      if (factor<1) factor = 1;
      currentLots = NormalizeDouble(factor * lots,_Digits);
      if (currentLots<lots) currentLots = lots;
      
      double maxLots = MarketInfo(_Symbol,MODE_MAXLOT) / MathPow(martingaleFactor,maxPositions);
      if (currentLots > maxLots) currentLots = maxLots;
   }
   
   if (tracelevel>=2) PrintFormat("scale() < exit: lots=%.2f",currentLots);
}

ENTRYSIGNAL entrySignal() {
   if (tracelevel>=2) PrintFormat("entrySignal() > entry");
   ENTRYSIGNAL signal = ENTRY_NONE;
   
   double rsi = iRSI(Symbol(),PERIOD_CURRENT,rsiPeriod,PRICE_CLOSE,1);
   double rsiPrev = iRSI(Symbol(),PERIOD_CURRENT,rsiPeriod,PRICE_CLOSE,2);
   double rsiBefore = iRSI(Symbol(),PERIOD_CURRENT,rsiPeriod,PRICE_CLOSE,3);
   
   if (tracelevel>=2) PrintFormat("I0003 entrySignal 2: RSI[1]=%.2f, RSI[2]=%.2f, RSI[3]=%.2f",rsi,rsiPrev,rsiBefore);
   
   //TODO: working around timing issue by also considering t-2
   if ((rsiPrev > rsiHighThreshold || rsiBefore > rsiHighThreshold) && rsi < rsiHighThreshold) {
      signal = ENTRY_SHORT;
      if (tracelevel>=2) PrintFormat("I0020 entrySignal() < exit: signal=SHORT");
   }
   if ((rsiPrev < rsiLowThreshold || rsiBefore < rsiLowThreshold) && rsi > rsiLowThreshold){
      signal = ENTRY_LONG;
      if (tracelevel>=2) PrintFormat("I0020 entrySignal() < exit: signal=LONG");
   }
      
   
   
   if (tracelevel>=2) PrintFormat("entrySignal() < exit");
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
            PrintFormat("E0009: " + error);
            continue;
         }
         if (OrderCloseTime()!=0) {
            PrintFormat("I0019 deleting short ticket %i with OrderCloseTime %s",OrderTicket(),OrderCloseTime());
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
   
   if (filterInfo.highestEntry > 0.0 && filterInfo.highestEntry < filterInfo.entry) {
      filterInfo.martingaleDistance = (filterInfo.entry - filterInfo.highestEntry) / _Point; 
   }
   if (filterInfo.lowestEntry > 0.0 && filterInfo.lowestEntry > filterInfo.entry) {
      filterInfo.martingaleDistance = (filterInfo.entry - filterInfo.lowestEntry) / _Point;
   }
   
   if (tracelevel>=2) PrintFormat("I0004 assessShort() lowest=%.5f,highest=%.5f,entry=%.5f,dist=%.5f", filterInfo.lowestEntry, filterInfo.highestEntry, filterInfo.entry, filterInfo.martingaleDistance);
    
   
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
            PrintFormat("E0010: " + error);
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
   
   if (filterInfo.lowestEntry > 0.0 && filterInfo.lowestEntry > filterInfo.entry) {
      filterInfo.martingaleDistance = (filterInfo.lowestEntry - filterInfo.entry) / _Point;
   }
   if (filterInfo.highestEntry > 0.0 && filterInfo.highestEntry < filterInfo.entry) {
      filterInfo.martingaleDistance = (filterInfo.highestEntry - filterInfo.entry) / _Point; 
   }
   if (tracelevel>=2) PrintFormat("I0005 assessLong() lowest=%.5f,highest=%.5f,entry=%.5f,dist=%.5f", filterInfo.lowestEntry, filterInfo.highestEntry, filterInfo.entry, filterInfo.martingaleDistance);
   
   
   if (tracelevel>=2) PrintFormat("assessLong() < exit: dist=%.2f", filterInfo.martingaleDistance);
   return filterInfo;
}


void considerCosts() {
   double longLots = 0.0;
   double openLongCost = 0.0;
   double consideredCostLong = 0.0;
   double shortLots = 0.0;
   double openShortCost = 0.0;
   double consideredCostShort = 0.0;
   
   //collect actual costs short
   for (int i=shortTickets.Total(); i>=0; i--) {
      if (OrderSelect(shortTickets.At(i),SELECT_BY_TICKET)) {
         if (StringCompare(OrderSymbol(), Symbol(),false)!=0) {
            string error = StringFormat("OrderSymbol=%s, Symbol=%",OrderSymbol(),Symbol());
            Comment("Error: " + error);
            PrintFormat("E0011: " + error);
            continue;
         }
         if (OrderCloseTime()!=0) {
            shortTickets.Delete(i);
         }
         
         shortLots += OrderLots();
         openShortCost += OrderCommission(); 
         if (OrderSwap() > 0) {
            openShortCost -= OrderSwap(); //positive OrderSwap() is profit
         } else {
            openShortCost += OrderSwap(); //negative OrderSwap() is cost
         }
      }
   }
   
   //collect considered costs short
   for (int i=costsShort.Total()-1;i>=0;i--) {
      CCost *c = costsShort.At(i);
      if (tracelevel>=2) PrintFormat("I0006 i=%i, ticket=%i",i,c.GetTicket());
      if (OrderSelect(c.GetTicket(), SELECT_BY_TICKET)) {
         if (OrderCloseTime()!=0) {
            costsShort.Delete(i);
            continue;
         }
         if (c.GetCommission() != OrderCommission() && tracelevel>=2) {
            PrintFormat("I0007 OrderCommission not considered: %.2f (ticket: %i)",OrderCommission(),OrderTicket());
         }
         if (c.GetSwap() != (-1*OrderSwap()) && tracelevel>=2) {
            PrintFormat("I0008 Swap not considered: %.2f (ticket: %i)",OrderSwap(),OrderTicket());
         }
         consideredCostShort += c.GetCommission();
         if (c.GetSwap() > 0) {
            consideredCostShort -= c.GetSwap(); //positive OrderSwap() is profit
         } else {
            consideredCostShort += c.GetSwap(); //negative OrderSwap() is cost
         }
      } else {
         costsShort.Delete(i);
      }
   }
   
   if (tracelevel>=0) PrintFormat("I0009 short considered cost: %.2f, actual cost: %.2f",consideredCostShort, openShortCost);
   double toBeConsidered = consideredCostShort - openShortCost;
   
   if (toBeConsidered != 0) {
      double points = toBeConsidered /(MarketInfo(_Symbol,MODE_TICKVALUE) * shortLots / MarketInfo(_Symbol,MODE_TICKSIZE));
      if (tracelevel>=2) PrintFormat("I0010 SHORT to-be-considered: %.5f, consideration costs points: %.5f", toBeConsidered, points);
      
      if (MathAbs(points)>0.0001) {
         for (int i=shortTickets.Total(); i>=0; i--) {
            if (OrderSelect(shortTickets.At(i),SELECT_BY_TICKET)) {
               if (StringCompare(OrderSymbol(), Symbol(),false)!=0) {
                  string error = StringFormat("OrderSymbol=%s, Symbol=%",OrderSymbol(),Symbol());
                  Comment("Error: " + error);
                  PrintFormat("E0012: " + error);
                  continue;
               }
               
               double oldTP = OrderTakeProfit();
               if (!OrderModify(OrderTicket(),0,OrderStopLoss(),OrderTakeProfit()-points,0,clrGreen)) {
                  PrintFormat("E0012");
               } else {
                  PrintFormat("I0011 Short OrderModified to consider costs. Ticket: %i, old tp=%.5f, new tp=%.5f",OrderTicket(), oldTP,OrderTakeProfit());
               }
               
            }
         }
         
         for (int i=costsShort.Total()-1;i>=0;i--) {
            CCost *c = costsShort.At(i);
            if (OrderSelect(c.GetTicket(),SELECT_BY_TICKET)) {
               c.SetSwap(OrderSwap());
               c.SetCommission(OrderCommission());
               if (tracelevel>=2) PrintFormat("I0012 short cost tracking updated for ticket %i with swap %.2f and commission %.2f", c.GetTicket(),c.GetSwap(),c.GetCommission());
            }
         }
      }
   }
   
   
   //collect data long
   for (int i=longTickets.Total(); i>=0; i--) {
      if (OrderSelect(longTickets.At(i),SELECT_BY_TICKET)) {
         if (StringCompare(OrderSymbol(), Symbol(),false)!=0) {
            string error = StringFormat("OrderSymbol=%s, Symbol=%",OrderSymbol(),Symbol());
            Comment("Error: " + error);
            PrintFormat("E0013: " + error);
            continue;
         }
         if (OrderCloseTime()!=0) {
            longTickets.Delete(i);
         }
         
         longLots += OrderLots();
         openLongCost += OrderCommission();
         if ( OrderSwap() > 0) {   
            openLongCost -= OrderSwap(); //positive OrderSwap() is profit
         } else {
            openLongCost += OrderSwap(); //negative OrderSwap() is cost
         }
      }
   }
   
   //collect considered costs short
   for (int i=costsLong.Total()-1;i>=0;i--) {
      CCost *c = costsLong.At(i);
      if (OrderSelect(c.GetTicket(), SELECT_BY_TICKET)) {
         if (OrderCloseTime()!=0) {
            costsLong.Delete(i);
            continue;
          }
      
      
         if (c.GetCommission() != OrderCommission() && tracelevel>=2) {
            PrintFormat("I0013 OrderCommission not considered: %.2f (ticket: %i)",OrderCommission(),OrderTicket());
         }
         if (c.GetSwap() != (-1 * OrderSwap()) && tracelevel>=2) {
            PrintFormat("I0014 Swap not considered: %.2f (ticket: %i)",OrderSwap(),OrderTicket());
         }
         consideredCostLong += c.GetCommission();
         
         if (c.GetSwap() > 0.0) {
            consideredCostLong -= c.GetSwap(); //positive swap is profit
         } else {
            consideredCostLong += c.GetSwap(); //negative swap is cost
         }
      } else {
         costsShort.Delete(i);
      }
   }
   
   if (tracelevel>=0) PrintFormat("I0015 long considered cost: %.2f, actual cost: %.2f",consideredCostLong, openLongCost);
   toBeConsidered = consideredCostLong - openLongCost;
   
   if (toBeConsidered != 0) {
      double points = toBeConsidered /(MarketInfo(_Symbol,MODE_TICKVALUE) * longLots / MarketInfo(_Symbol,MODE_TICKSIZE));
      if (tracelevel>=2) PrintFormat("I0016 LONG:  to-be-considered: %.5f, points: %.5f", toBeConsidered, points);
      if (MathAbs(points)>0.0001) {
         for (int i=longTickets.Total(); i>=0; i--) {
            if (OrderSelect(longTickets.At(i),SELECT_BY_TICKET)) {
               if (StringCompare(OrderSymbol(), Symbol(),false)!=0) {
                  string error = StringFormat("OrderSymbol=%s, Symbol=%",OrderSymbol(),Symbol());
                  Comment("Error: " + error);
                  PrintFormat("E0014: " + error);
                  continue;
               }
               
               double oldTP = OrderTakeProfit();
               if (!OrderModify(OrderTicket(),0,OrderStopLoss(),OrderTakeProfit()+points,0,clrGreen)) {
                  PrintFormat("E0015");
               } else {
                  if (OrderSelect(OrderTicket(),SELECT_BY_TICKET)) {
                     PrintFormat("I0017 Long OrderModified to consider costs, ticket: %i, old tp=%.5f, new tp=%.5f", OrderTicket(), oldTP, OrderTakeProfit());
                  } else {
                     PrintFormat("I0019 Cannot re-select for trace.");
                  }
               }
               
            }
         }
         
         for (int i=costsLong.Total()-1;i>=0;i--) {
            CCost *c = costsLong.At(i);
            if (OrderSelect(c.GetTicket(),SELECT_BY_TICKET)) {
               c.SetSwap(OrderSwap());
               c.SetCommission(OrderCommission());
               if (tracelevel>=2) PrintFormat("I0018 long cost tracking updated for ticket %i with swap %.2f and commission %.2f", c.GetTicket(),c.GetSwap(),c.GetCommission());
            }
         }
      }
   }
      
   
}

CCost::CCost(void) {
   m_ticket = -1;
   m_swap = 0.0;
   m_commission = 0.0;
}

CCost::CCost(int ticket, double commission, double swap){
   m_ticket = ticket;
   m_commission = commission;
   if (swap < 0.0) {
      m_swap = (-1 * swap);
   } else {
      m_swap = 0.0;
   }
}

