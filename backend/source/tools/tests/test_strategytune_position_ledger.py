from tools.strategytune_position_ledger import LedgerError, build_report
import pytest


def ent(ts=1000, side="L", price=4000.0, family=1, regime=2):
    return f"{ts}|{side}|{price:.8f}|{family}|{regime}|90.0|10.0|0.01|0.5"


def cls(oid, cid, side, op, pnl, qty=1.0):
    return {"status":"Closed","openingFillId":oid,"closingFillId":cid,"side":side,
            "openTimestamp":1000,"openPrice":op,"closeTimestamp":1100,"closePrice":op+1,
            "quantity":qty,"pnl":pnl,"exitReason":"market"}


def bundle(rows, maps, pnl, trades=None, has_more=False):
    custom={"entryMapVersion":1,"entryMapRecords":len(maps),"entryMapChunks":1 if maps else 0,
            "entryMapOverflow":False,"sessionRowsAuthoritative":True}
    if maps: custom["entryMap0"]=";".join(maps)
    return {"session":{"ticker":"Gold","currency":"USD","trades":rows,"returned":len(rows),
        "total":len(rows),"totalUnfiltered":len(rows),"hasMore":has_more},
        "run":{"accountCurrency":"USD","record":{"startingBalance":10000},
        "stats":{"stats":{"totalPnl":pnl,"trades":trades if trades is not None else len(rows)},
        "customStats":custom}}}


def test_partial_closes_grouped_and_engine_pnl_reconciles():
    rows=[cls(1,11,"Long",4000,8,0.4),cls(1,12,"Long",4000,6,0.6),
          cls(2,13,"Short",4010,-4)]
    report=build_report(bundle(rows,[ent(),ent(side="S",price=4010,family=2,regime=1)],10,3))
    assert report["ledger_valid"]
    assert report["positions"]["completed_positions"]==2
    assert report["positions"]["partial_exit_positions"]==1
    assert report["by_family"]["singleSwing"]["net_pnl"]==14


def test_open_remainder_is_not_a_completed_position():
    rows=[cls(1,11,"Long",4000,4,0.4),
          {"status":"Open","openingFillId":1,"side":"Long","openTimestamp":1000,
           "openPrice":4000,"quantity":0.6,"pnl":1.5}]
    report=build_report(bundle(rows,[ent()],4,1))
    assert report["ledger_valid"]
    assert report["positions"]["completed_positions"]==0
    assert report["positions"]["open_positions"]==1
    assert report["positions"]["unrealized_pnl_open_positions"]==1.5


def test_pnl_mismatch_fails_ledger():
    report=build_report(bundle([cls(1,11,"Long",4000,5)],[ent()],5.5,1))
    assert not report["ledger_valid"]
    assert not report["pnl_reconciled"]


def test_incomplete_pagination_and_overflow_fail_closed():
    rows=[cls(1,11,"Long",4000,5)]
    p=bundle(rows,[ent()],5,1,True)
    with pytest.raises(LedgerError,match="pagination"):
        build_report(p)
    p=bundle(rows,[ent()],5,1)
    p["run"]["stats"]["customStats"]["entryMapOverflow"]=True
    with pytest.raises(LedgerError,match="overflow"):
        build_report(p)


def test_same_timestamp_two_sides_join_independently():
    rows=[cls(1,11,"Long",4000,5),cls(2,12,"Short",4010,6)]
    report=build_report(bundle(rows,[ent(),ent(side="S",price=4010)],11,2))
    assert report["ledger_valid"]
    assert report["entry_map_matched"]==2


def test_duplicate_entry_identity_is_rejected():
    p=bundle([cls(1,11,"Long",4000,5)],[ent(),ent()],5,1)
    p["run"]["stats"]["customStats"]["entryMapRecords"]=2
    p["run"]["stats"]["customStats"]["entryMap0"] += ";" + ent()
    with pytest.raises(LedgerError,match="duplicate"):
        build_report(p)
