#!/usr/bin/env python3
"""Static structural checks for flattened MQL5 source; not a compiler."""
import collections, hashlib, json, re, sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]; EA=ROOT/"MidasTouch2.mq5"; MANIFEST=ROOT/"SOURCE_MANIFEST.json"
def mask(text):
    out=[]; i=0; state="normal"; quote=""
    while i<len(text):
        c=text[i]; n=text[i+1] if i+1<len(text) else ""
        if state=="normal":
            if c=="/" and n=="/": out.extend("  "); i+=2; state="line"; continue
            if c=="/" and n=="*": out.extend("  "); i+=2; state="block"; continue
            if c in ('"',"'"): quote=c; out.append(" "); i+=1; state="string"; continue
            out.append(c); i+=1; continue
        if state=="line":
            if c=="\n": out.append("\n"); state="normal"
            else: out.append(" ")
            i+=1; continue
        if state=="block":
            if c=="*" and n=="/": out.extend("  "); i+=2; state="normal"
            else: out.append("\n" if c=="\n" else " "); i+=1
            continue
        if state=="string":
            if c=="\\": out.extend("  "); i+=2; continue
            if c==quote: out.append(" "); i+=1; state="normal"; continue
            out.append("\n" if c=="\n" else " "); i+=1
    return "".join(out)
def ranges_for_classes(code):
    ranges=[]; rx=re.compile(r'\b(?:class|struct)\s+[A-Za-z_]\w*\s*(?:final\s*)?(?:\:\s*[^{}]+)?\{')
    for match in rx.finditer(code):
        depth=1; i=match.end()
        while i<len(code) and depth:
            if code[i]=="{": depth+=1
            elif code[i]=="}": depth-=1
            i+=1
        if depth==0: ranges.append((match.start(),i))
    return ranges
def main():
    if not EA.is_file(): raise SystemExit("FAIL: MidasTouch2.mq5 missing")
    raw=EA.read_text(encoding="utf-8-sig")
    code=mask(raw); fail=[]
    bridge_checks={
        "authenticated execution-ledger health request":r'WebRequest\s*\(\s*"GET"\s*,\s*m_baseUrl\s*\+\s*"/execution-ledger/health"',
        "exact execution_ledger readiness token":r'readinessToken\s*=\s*quote\s*\+\s*"execution_ledger"\s*\+\s*quote\s*\+\s*":"\s*\+\s*quote\s*\+\s*"ready"\s*\+\s*quote',
        "exact ledger_schema readiness token":r'schemaToken\s*=\s*quote\s*\+\s*"ledger_schema"\s*\+\s*quote\s*\+\s*":"\s*\+\s*quote\s*\+\s*"ready"\s*\+\s*quote',
        "Strategy Tester WebRequest guard":r'bool\s+CheckHealth\s*\(\s*\)\s*\{[\s\S]{0,700}MQLInfoInteger\(MQL_TESTER\)',
        "health success does not directly open admission":r'm_healthVerified\s*=\s*true\s*;[\s\S]{0,180}m_admissionHealthy\s*=\s*false\s*;',
        "entry admission requires health and reconciliation":r'bool\s+AdmissionReady\s*\(\)\s*const\s*\{\s*return\s*\(m_ready\s*&&\s*m_healthVerified\s*&&\s*m_admissionHealthy\)\s*;\s*\}',
        "reconciliation alone reopens an authenticated healthy ledger":r'void\s+MarkReconciled\s*\(\)\s*\{\s*m_admissionHealthy\s*=\s*\(m_ready\s*&&\s*m_healthVerified\)\s*;\s*\}',
        "transport failure invalidates health and admission":r'm_healthVerified\s*=\s*false\s*;\s*m_admissionHealthy\s*=\s*false\s*;\s*PrintFormat\("Midas execution ledger: POST',
        "startup probes configured ledger before testing admission":r'if\s*\(InpEnableExecution\s*&&\s*g_executionLedger\.Ready\(\)\s*\)[\s\S]{0,450}g_executionLedgerHealthy\s*=\s*g_executionLedger\.CheckHealth\(\)\s*&&\s*ReconcileBrokerStateSnapshot\(\)[\s\S]{0,150}g_executionLedger\.MarkReconciled\(\)',
        "recovery requires health and reconciliation":r'if\s*\(!\(bool\)MQLInfoInteger\(MQL_TESTER\)[\s\S]{0,700}g_executionLedgerHealthy\s*=\s*g_executionLedger\.CheckHealth\(\)\s*&&\s*ReconcileBrokerStateSnapshot\(\)',
        "retry time persisted before retry":r'g_lastLedgerReconcileAttempt\s*=\s*localNow\s*;',
        "three qualified winning trades target":r'input\s+int\s+InpMinimumQualifiedTradesPerDay\s*=\s*3\s*;',
        "minimum qualifying result threshold":r'input\s+double\s+InpMinimumQualifiedTradeR\s*=\s*0\.25\s*;',
        "daily counter accepts only fully closed positive qualifying R on weekdays":r'void\s+OnQualifiedClose\(datetime\s+at,double\s+realizedR,ulong\s+positionId\)\s*\{[\s\S]{0,320}realizedR\s*<=\s*0\.0[\s\S]{0,100}realizedR\s*\+\s*1e-9\s*<\s*m_minQualifiedR[\s\S]{0,100}!IsWeekday\(at\)',
        "daily counter called only after complete qualified position finalization":r'if\s*\(tracked\s*&&\s*!stillOpen\s*&&\s*g_tracker\.LastFinalizedQualified\(\)\)\s*g_dailyTradeTarget\.OnQualifiedClose',
        "daily target reports no forced entries":r'continuing normal setup search, no entries forced',
        "daily objective does not gate setup evaluation":r'g_dailyTradeTarget\.LogSearchProgress\(\);[\s\S]{0,350}TradeSetup\s+buySetup\s*=\s*g_decision\.GenerateBuySetup\(\)',
        "KES Gold stop-risk input defaults to 7.50":r'input\s+double\s+InpSmallGoldMaxStopRiskKES\s*=\s*7\.50\s*;',
        "Strategy Tester FX conversion requires explicit input":r'if\s*\(\(bool\)MQLInfoInteger\(MQL_TESTER\)\)[\s\S]{0,350}InpAccountCurrencyPerKES\s*<=\s*0\.0[\s\S]{0,180}return\s+false',
        "live FX conversion scans direct and inverse KES pairs":r'for\s*\(int\s+direction\s*=\s*0\s*;\s*direction\s*<\s*2[\s\S]{0,1500}bool\s+direct\s*=\s*\(baseCurrency\s*==\s*"KES"[\s\S]{0,250}bool\s+inverse\s*=\s*\(baseCurrency\s*==\s*accountCurrency[\s\S]{0,500}SymbolInfoTick\(candidate,tick\)',
        "live conversion quotes must be fresh":r'age\s*=\s*\(long\)now\s*-\s*\(long\)tick\.time\s*;[\s\S]{0,100}age\s*>\s*maxAge',
        "Gold risk percent is capped by KES-derived account money":r'ResolveRiskPercentWithCashCap\(equity,g_activeRiskLimits\.riskPercentPerTrade[\s\S]{0,160}goldCashCapMoney,true,effectiveRiskPercent',
        "Gold exception is isolated from other symbols":r'!IsGoldRiskLimitedSymbol\(_Symbol\)',
        "automated sizing uses capped risk percent":r'CalculateLotSize\(_Symbol,effectiveRiskPercent\*fraction',
        "automated Gold sizing uses worst permitted adverse entry":r'riskEntry\s*=\s*\(decision\.setup\.type\s*==\s*ORDER_TYPE_BUY\s*\?\s*entry\s*\+\s*maxDeviation\s*:\s*entry\s*-\s*maxDeviation\)',
        "automated stop risk is measured at worst permitted fill":r'CalculateLotSize\(_Symbol,effectiveRiskPercent\*fraction,riskEntry[\s\S]{0,250}RiskAmountForLots\(_Symbol,legLots\[leg\],riskEntry',
        "automated multi-leg risk is capped as one signal":r'GoldStopRiskWithinCashCap\(totalProposedRisk,goldCashCapMoney\)',
        "manual sizing uses capped risk percent":r'CalculateLotSize\(_Symbol,effectiveRiskPercent,riskEntry,setup\.stop_loss',
        "manual Gold sizing uses worst permitted adverse entry":r'riskEntry\s*=\s*\(isBuy\s*\?\s*entry\s*\+\s*maxDeviation\s*:\s*entry\s*-\s*maxDeviation\)',
        "manual stop risk is measured at worst permitted fill":r'RiskAmountForLots\(_Symbol,lots,riskEntry,setup\.stop_loss\)',
        "manual Gold cash risk is capped":r'GoldStopRiskWithinCashCap\(proposedRisk,goldCashCapMoney\)',
        "Gold cap exception does not bypass zero-risk rejection":r'bool\s+SmallAccountRiskFloorSatisfied[\s\S]{0,280}plannedRiskPercent\s*<=\s*0\.0[\s\S]{0,100}if\s*\(goldCashCapApplies\)',
    }
    policy_test_path=ROOT/"development"/"EA"/"tests"/"AccountRiskProfilePolicy.mq5"
    policy_test=policy_test_path.read_text(encoding="utf-8-sig") if policy_test_path.is_file() else ""
    policy_test_checks={
        "Gold policy tests cover KES cap overflow":r'GoldStopRiskWithinCashCap\(7\.51,7\.50\)',
        "Gold policy tests retain non-Gold risk":r'ResolveRiskPercentWithCashCap\(1500\.0,20\.0,7\.50,false',
        "Gold policy tests cover cash-cap conversion":r'ResolveRiskPercentWithCashCap\(1500\.0,20\.0,7\.50,true'
    }
    for name,pattern in bridge_checks.items():
        if not re.search(pattern,raw): fail.append("bridge/control regression: "+name)
    for name,pattern in policy_test_checks.items():
        if not re.search(pattern,policy_test):
            fail.append("Gold risk policy test missing: "+name)
    if re.search(r'^\s*#include\s*"',code,re.MULTILINE): fail.append("custom quoted include remains")
    system=re.findall(r'^\s*#include\s*<([^>]+)>',code,re.MULTILINE)
    if not system: fail.append("standard MQL5 library include missing")
    if any(x.replace("/", "\\").lower()!="trade\\trade.mqh" for x in system): fail.append(f"unexpected system includes: {system}")
    type_matches=list(re.finditer(r'\b(class|struct|enum)\s+([A-Za-z_]\w*)\s*(?:final\s*)?(?:\:\s*[^{};]+)?\{',code))
    type_names=[m.group(2) for m in type_matches]
    dup_types=sorted(k for k,v in collections.Counter(type_names).items() if v>1)
    if dup_types: fail.append(f"duplicate type definitions: {dup_types}")
    inputs=re.findall(r'^\s*input\s+(?!group\b)[^;\r\n=]*?\b([A-Za-z_]\w*)\s*=',code,re.MULTILINE)
    dup_inputs=sorted(k for k,v in collections.Counter(inputs).items() if v>1)
    if dup_inputs: fail.append(f"duplicate input names: {dup_inputs}")
    class_ranges=ranges_for_classes(code)
    events=("OnInit","OnDeinit","OnTick","OnTimer","OnTradeTransaction","OnChartEvent"); counts={}
    for event in events:
        rx=re.compile(r'^\s*(?:void|int|bool)\s+'+event+r'\s*\([^;]*?\)\s*\{',re.MULTILINE)
        found=[m for m in rx.finditer(code) if not any(a<m.start()<b for a,b in class_ranges)]
        counts[event]=len(found)
        if counts[event]!=1: fail.append(f"{event}: expected one global handler, found {counts[event]}")
    safeties={
        "dynamic stop":r'\binput\s+bool\s+InpEnableDynamicStop\s*=\s*true\b',
        "execution ledger":r'\binput\s+bool\s+InpRequireExecutionLedger\s*=\s*true\b',
        "opposing-position policy":r'\binput\s+bool\s+InpAllowConcurrentOpposingPositions\s*=\s*true\b'}
    for name,pattern in safeties.items():
        if not re.search(pattern,code): fail.append("required safety default missing: "+name)
    manifest=json.loads(MANIFEST.read_text(encoding="utf-8"))
    snapshot=manifest.get("current_source_snapshot",{})
    snapshot_files=snapshot.get("files",[])
    source_root=ROOT/"development"/"EA"
    if not snapshot_files:
        fail.append("current staged EA source snapshot missing from SOURCE_MANIFEST.json")
    else:
        expected={item["path"]:item for item in snapshot_files}
        actual={p.relative_to(ROOT).as_posix():p for p in source_root.rglob("*") if p.is_file()}
        missing=sorted(set(expected)-set(actual))
        extra=sorted(set(actual)-set(expected))
        if missing: fail.append("staged source files missing from manifest: "+", ".join(missing))
        if extra: fail.append("unmanifested staged source files: "+", ".join(extra))
        for rel,item in expected.items():
            path=actual.get(rel)
            if path is None: continue
            data=path.read_bytes()
            blob=hashlib.sha1(b"blob "+str(len(data)).encode("ascii")+b"\0"+data).hexdigest()
            if blob!=item.get("git_blob_sha"):
                fail.append("staged source hash mismatch: "+rel)
            if len(data)!=item.get("size_bytes"):
                fail.append("staged source size mismatch: "+rel)
    print("Upstream baseline:",manifest["source_repository"]+"@"+manifest["source_commit"])
    print("Staged source snapshot:",snapshot.get("repository","")+"@"+snapshot.get("commit",""))
    print("Staged source files:",len(snapshot_files),"expected;",len(actual) if 'actual' in locals() else 0,"found")
    print("Named type definitions:",len(type_names),"; duplicates:",len(dup_types))
    print("Input declarations:",len(inputs),"; duplicate names:",len(dup_inputs))
    print("Standard includes:",system)
    print("Global event handlers:",counts)
    if fail:
        for message in fail: print("FAIL:",message,file=sys.stderr)
        return 1
    print("PASS: static structure and safety-default checks")
    print("NOTICE: not a MetaEditor compile, Strategy Tester run, or demo execution")
    return 0
if __name__=="__main__": sys.exit(main())
