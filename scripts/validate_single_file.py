#!/usr/bin/env python3
"""Static structural checks for flattened MQL5 source; not a compiler."""
import collections, json, re, sys
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
        "exact execution_ledger readiness token":r'readinessToken\s*=\s*CharToString\(34\)\s*\+\s*"execution_ledger"\s*\+\s*CharToString\(34\)\s*\+\s*":"\s*\+\s*CharToString\(34\)\s*\+\s*"ready"\s*\+\s*CharToString\(34\)',
        "Strategy Tester WebRequest guard":r'bool\s+CheckHealth\s*\(\s*\)\s*\{[\s\S]{0,700}MQLInfoInteger\(MQL_TESTER\)',
        "recovery requires health and reconciliation":r'if\s*\(!\(bool\)MQLInfoInteger\(MQL_TESTER\)[\s\S]{0,700}g_executionLedgerHealthy\s*=\s*g_executionLedger\.CheckHealth\(\)\s*&&\s*ReconcileBrokerStateSnapshot\(\)',
        "retry time persisted before retry":r'g_lastLedgerReconcileAttempt\s*=\s*localNow\s*;',
        "three qualified winning trades target":r'input\s+int\s+InpMinimumQualifiedTradesPerDay\s*=\s*3\s*;',
        "minimum qualifying result threshold":r'input\s+double\s+InpMinimumQualifiedTradeR\s*=\s*0\.25\s*;'
    }
    for name,pattern in bridge_checks.items():
        if not re.search(pattern,raw): fail.append("bridge/control regression: "+name)
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
    print("Source:",manifest["source_repository"]+"@"+manifest["source_commit"])
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
