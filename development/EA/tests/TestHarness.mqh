#ifndef MIDAS_TEST_HARNESS_MQH
#define MIDAS_TEST_HARNESS_MQH

// Shared one-shot result writer for deterministic MT5 policy scripts.
// CI launches each script with /config; TerminalClose then propagates the
// assertion result as the terminal process exit code. Manual launches stay open.
void MidasTestFinish(const string resultFile,const int failureCount)
  {
   int resultHandle=FileOpen(resultFile,FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(resultHandle==INVALID_HANDLE)
     {
      PrintFormat("FAIL: could not write test result %s (error=%d)",resultFile,GetLastError());
      if(MQLInfoInteger(MQL_STARTED_FROM_CONFIG))
         TerminalClose(2);
      return;
     }

   FileWrite(resultHandle,StringFormat("failures=%d",failureCount));
   FileClose(resultHandle);

   if(MQLInfoInteger(MQL_STARTED_FROM_CONFIG))
      TerminalClose(failureCount==0 ? 0 : 1);
  }

#endif
