#!/usr/bin/env python3
"""Flatten the modular MQL5 EA into one deterministic .mq5 source file."""
import argparse, json, re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
SOURCE_ROOT=(ROOT/"development"/"EA").resolve()
MANIFEST=ROOT/"SOURCE_MANIFEST.json"
OUTPUT=ROOT/"MidasTouch2.mq5"
INCLUDE=re.compile(r'^(?P<indent>\s*)#include\s*(?P<quote>[<"])(?P<path>[^">]+)[">](?P<tail>.*)$')
GUARD=re.compile(r'^\s*#ifndef\s+([A-Za-z_]\w*)\s*[\r\n]+\s*#define\s+\1\b',re.MULTILINE)
def build(entry,commit):
    expanded=set(); guards={}; stack=[]; conditional=[]
    def expand(path):
        path=path.resolve()
        if path in stack: raise ValueError("include cycle: "+" -> ".join(str(p) for p in stack+[path]))
        stack.append(path); lines=path.read_text(encoding="utf-8-sig").splitlines(); out=[]; depth=0
        for number,line in enumerate(lines,1):
            stripped=line.strip()
            if re.match(r"^#\s*(if|ifdef|ifndef)\b",stripped): depth+=1
            match=INCLUDE.match(line)
            if not match: out.append(line)
            elif match.group("quote")=="<": out.append(line)
            else:
                if depth>(1 if path.suffix.lower()==".mqh" else 0): conditional.append(f"{path}:{number}")
                target=(path.parent/match.group("path").replace("\\","/")).resolve()
                try: target.relative_to(SOURCE_ROOT)
                except ValueError as exc: raise ValueError(f"include escapes source tree: {target}") from exc
                if not target.is_file(): raise FileNotFoundError(f"missing include: {path}:{number}: {match.group('path')}")
                rel=target.relative_to(SOURCE_ROOT)
                if target in expanded: out.append(f"{match.group('indent')}// already inlined once under include guard: {rel}")
                else:
                    guard=GUARD.search(target.read_text(encoding="utf-8-sig"))
                    if not guard: raise ValueError(f"header has no include guard: {target}")
                    macro=guard.group(1)
                    if macro in guards and guards[macro]!=target: raise ValueError(f"duplicate include guard: {macro}")
                    guards[macro]=target; expanded.add(target)
                    out.append(f"{match.group('indent')}// BEGIN INLINED MODULE: {rel}")
                    out.append(expand(target))
                    out.append(f"{match.group('indent')}// END INLINED MODULE: {rel}")
            if re.match(r"^#\s*endif\b",stripped): depth=max(0,depth-1)
        stack.pop(); return "\n".join(out)
    prefix=("// MidasTouch2 single-file production build\n"
            "// Package version: 1.0.0-rc.1\n"
            f"// Generated from cirvannaco-png/Midas-touch2-@{commit}\n"
            "// Modular source is preserved under development/EA/.\n"
            "// Regenerate with: python scripts/build_single_file.py\n"
            "// Do not hand-edit this generated file.\n\n")
    result=prefix+expand(entry)+"\n"
    if conditional: raise ValueError("conditional local includes found: "+", ".join(conditional))
    if re.search(r'^\s*#include\s*"',result,re.MULTILINE): raise ValueError("quoted custom includes remain")
    return result
def main():
    parser=argparse.ArgumentParser(); parser.add_argument("--check",action="store_true"); parser.add_argument("--output",type=Path,default=OUTPUT); args=parser.parse_args()
    data=json.loads(MANIFEST.read_text(encoding="utf-8"))
    entry=SOURCE_ROOT/Path(data["entrypoint"]).relative_to("EA")
    generated=build(entry,data["source_commit"])
    if args.check:
        actual=args.output.read_text(encoding="utf-8-sig") if args.output.exists() else None
        if actual!=generated: raise SystemExit("FAIL: generated EA differs from modular sources; regenerate it")
        print(f"PASS: source matches modular implementation ({len(generated):,} characters)")
    else:
        args.output.parent.mkdir(parents=True,exist_ok=True); args.output.write_text(generated,encoding="utf-8",newline="\n")
        print(f"Wrote {args.output} ({len(generated):,} characters)")
if __name__=="__main__": main()
