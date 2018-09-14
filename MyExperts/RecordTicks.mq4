//+------------------------------------------------------------------+
//|                                                  RecordTicks.mq4 |
//|                                                     Record Ticks |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Record Ticks"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

int file = -1;
int flushCount = 0;
int hour = -1;


//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   // Open the file for writing
   openFile();  
 
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   closeFile();   
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
  
  if (TimeHour(TimeCurrent()) != hour) {
   closeFile();
   openFile();
  }
  
   FileWrite(file, 
             TimeToStr(TimeCurrent(),
                       TIME_DATE | TIME_SECONDS),  
             Bid, 
             Ask);
 
   flushCount++;
   
   // Flush file buffer each 1024 ticks to enhance performance
   //    when writing huge files
   if (flushCount == 1024) {
     flushFile();
   }
   
  }
  
string getFileName() {
   
   datetime now = TimeCurrent();
   string fileName = StringFormat("%s %4i-%02i-%02i %02i.csv", Symbol(), TimeYear(now),TimeMonth(now),TimeDay(now),TimeHour(now));
   hour = TimeHour(now);
   return fileName;
}

void openFile() {
   file = FileOpen(getFileName(), FILE_WRITE | FILE_CSV, ";"); 
}

void closeFile() {
   flushFile();
   FileClose(file); 
}

void flushFile() {
   FileFlush(file);
   flushCount = 0;
}