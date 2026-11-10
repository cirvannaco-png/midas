// Exported from StrategyTune; research-only, not MQL5 source.
// Script ID: yzt9i490pquc1ozwiugl9qyy
// Compiled version: 2

class MidasTouch2NoQuotaResearch {
  lastKey:string="";
  volumeRejects:number=0;
  fibRejects:number=0;
  lastEntryTime:number=0;
  entryTime:number=0;
  activeLotId:number=-1;
  tp1Done:boolean=false;
  tp2Done:boolean=false;
  runnerTrailArmed:boolean=false;
  tradeRisk:number=0;
  tradeStates:any[]=[];
  entryAttributionRecords:string[]=[];
  dayKey:number=-1;
  currentDayEligible:boolean=false;
  lastFinalizedDay:number=-1;
  entriesToday:number=0;
  daysObserved:number=0;
  daysMetMinimum:number=0;
  daysBelowMinimum:number=0;
  dailyEntrySum:number=0;
  dailyShortfallSum:number=0;
  maxEntriesInDay:number=0;
  totalEntriesPlaced:number=0;
  strictEntries:number=0;
  singleSwingEntries:number=0;
  continuationEntries:number=0;
  microMomentumEntries:number=0;
  lastClosedSignature:string="";
  positionTradeCount:number=0;
  positionWins:number=0;
  positionLosses:number=0;
  positionFlat:number=0;
  positionNetPnl:number=0;
  positionNetR:number=0;
  capturedClosedPnl:number=0;
  unmatchedCloseRecords:number=0;
  lastEngineClosedTrades:number=0;
  missedCloseEvents:number=0;
  positionAttributionValid:boolean=true;
  positionTP1Count:number=0;
  positionTP2Count:number=0;
  position2RCount:number=0;
  position3RCount:number=0;
  runnerNetPnl:number=0;
  tierPositionN:number[]=[];
  tierPositionW:number[]=[];
  tierPositionL:number[]=[];
  tierPositionPnl:number[]=[];
  // Entry-time feature snapshots and final outcomes; telemetry only.
  featureWinSums:number[]=[];
  featureLossSums:number[]=[];
  featureWinN:number=0;
  featureLossN:number=0;
  regimePositionN:number[]=[];
  regimePositionW:number[]=[];
  regimePositionL:number[]=[];

  blockedOpposite:number=0;
  blockedRiskCap:number=0;
  blockedConcurrency:number=0;
  blockedDailyMax:number=0;
  weekendFlattenCalls:number=0;
  weekendFlattenErrors:number=0;
  weekendLotsTargeted:number=0;
  weekendBlockedEntryBars:number=0;
  blockedSingleSwingRegime:number=0;
  blockedContinuationRegime:number=0;
  blockedStops:number=0;
  blockedSizing:number=0;
  tp1Count:number=0;
  tp2Count:number=0;

  onInit(ctx:InitContext):void {
    this.lastKey="";
    this.lastEntryTime=0;
    this.entryTime=0;
    this.activeLotId=-1;
    this.tp1Done=false;
    this.tp2Done=false;
    this.runnerTrailArmed=false;
    this.tradeRisk=0;
    this.tradeStates=[];
    this.entryAttributionRecords=[];
    this.dayKey=-1; this.currentDayEligible=false; this.lastFinalizedDay=-1; this.entriesToday=0;
    this.daysObserved=0; this.daysMetMinimum=0; this.daysBelowMinimum=0;
    this.dailyEntrySum=0; this.dailyShortfallSum=0; this.maxEntriesInDay=0;
    this.totalEntriesPlaced=0; this.strictEntries=0; this.singleSwingEntries=0; this.continuationEntries=0; this.microMomentumEntries=0;
    this.lastClosedSignature="";
    this.positionTradeCount=0; this.positionWins=0; this.positionLosses=0; this.positionFlat=0;
    this.positionNetPnl=0; this.positionNetR=0; this.capturedClosedPnl=0; this.unmatchedCloseRecords=0;
    this.lastEngineClosedTrades=0; this.missedCloseEvents=0; this.positionAttributionValid=true;
    this.positionTP1Count=0; this.positionTP2Count=0; this.position2RCount=0; this.position3RCount=0; this.runnerNetPnl=0;
    this.tierPositionN=[0,0,0,0,0]; this.tierPositionW=[0,0,0,0,0]; this.tierPositionL=[0,0,0,0,0]; this.tierPositionPnl=[0,0,0,0,0];
    this.featureWinSums=[0,0,0,0,0,0,0,0,0,0,0,0];
    this.featureLossSums=[0,0,0,0,0,0,0,0,0,0,0,0];
    this.featureWinN=0; this.featureLossN=0;
    this.regimePositionN=[0,0,0]; this.regimePositionW=[0,0,0]; this.regimePositionL=[0,0,0];
    this.blockedOpposite=0; this.blockedRiskCap=0; this.blockedConcurrency=0; this.blockedDailyMax=0;
    this.weekendFlattenCalls=0; this.weekendFlattenErrors=0;
    this.weekendLotsTargeted=0; this.weekendBlockedEntryBars=0;
    this.blockedSingleSwingRegime=0; this.blockedContinuationRegime=0;
    this.blockedStops=0; this.blockedSizing=0; this.tp1Count=0; this.tp2Count=0;
  }

  atr(ctx:Context, back:number):number {
    const n=ctx.inputs.atrLen;
    if(ctx.bars.count < back+n+2) return NaN;
    let sum=0;
    for(let i=back;i<back+n;i++){
      const h=ctx.bars.high(i), l=ctx.bars.low(i), pc=ctx.bars.close(i+1);
      sum += Math.max(h-l,Math.abs(h-pc),Math.abs(l-pc));
    }
    return sum/n;
  }

  // Research regime proxy: absolute 8-vs-21 bar mean separation / ATR.
  // 0=range-like, 1=transition, 2=trend-like. This is not the production EA classifier.
  trendSlopeProxyATR(ctx:Context):number {
    const a=this.atr(ctx,1);
    if(!(a>0)||ctx.bars.count<25)return NaN;
    let fast=0,slow=0;
    for(let k=1;k<=8;k++)fast+=ctx.bars.close(k);
    for(let k=1;k<=21;k++)slow+=ctx.bars.close(k);
    return Math.abs(fast/8-slow/21)/a;
  }

  bodyRatio(ctx:Context,i:number):number {
    const r=ctx.bars.high(i)-ctx.bars.low(i);
    return r>0 ? Math.abs(ctx.bars.close(i)-ctx.bars.open(i))/r : 0;
  }

  isSwingHigh(ctx:Context,i:number):boolean {
    const s=ctx.inputs.swingStrength;
    if(i < s+1 || i+s >= ctx.bars.count) return false;
    const x=ctx.bars.high(i);
    for(let d=1;d<=s;d++){
      if(x < ctx.bars.high(i-d) || x < ctx.bars.high(i+d)) return false;
    }
    return true;
  }

  isSwingLow(ctx:Context,i:number):boolean {
    const s=ctx.inputs.swingStrength;
    if(i < s+1 || i+s >= ctx.bars.count) return false;
    const x=ctx.bars.low(i);
    for(let d=1;d<=s;d++){
      if(x > ctx.bars.low(i-d) || x > ctx.bars.low(i+d)) return false;
    }
    return true;
  }

  inSession(ctx:Context):boolean {
    const h=new Date(ctx.time).getUTCHours();
    return h>=ctx.inputs.sessionStartUTC && h<ctx.inputs.sessionEndUTC;
  }

  // Research-only weekend guard. It blocks entries throughout Saturday and
  // Sunday, and from Friday's UTC cutoff onward. At the first eligible market
  // update it submits one account-wide flatten request instead of closing
  // lots one by one. Any multi-lot close-event collision invalidates the
  // internal attribution tracker; full-position results must then be rebuilt
  // from the saved session rows grouped by original opening fill.
  applyWeekendGuard(ctx:Context):boolean {
    if(!ctx.inputs.avoidWeekendExposure)return false;
    const date=new Date(ctx.time);
    const day=date.getUTCDay();
    const hour=date.getUTCHours();
    const weekend=day===6 || day===0 || (day===5 && hour>=ctx.inputs.fridayCutoffHourUTC);
    if(!weekend)return false;
    if(ctx.isNewBar)this.weekendBlockedEntryBars++;
    const lots=ctx.account.lots;
    if(lots.length>0){
      try {
        this.weekendFlattenCalls++;
        this.weekendLotsTargeted+=lots.length;
        ctx.orders.closePosition();
        this.captureLastClosed(ctx);
        if(ctx.account.lots.length>0)this.positionAttributionValid=false;
      } catch(e:any) {
        this.weekendFlattenErrors++;
      }
    }
    return true;
  }

  findLiquidity(ctx:Context,forBuy:boolean):any {
    const start=Math.max(ctx.inputs.swingStrength+1,3);
    const end=Math.min(ctx.inputs.lookbackBars,ctx.bars.count-ctx.inputs.swingStrength-1);
    let best:any=null;

    for(let a=start;a<=end;a++){
      if(forBuy ? !this.isSwingLow(ctx,a) : !this.isSwingHigh(ctx,a)) continue;
      const p=forBuy ? ctx.bars.low(a) : ctx.bars.high(a);
      const aa=this.atr(ctx,a);
      if(!(aa>0)) continue;

      for(let b=a+1;b<=end;b++){
        if(forBuy ? !this.isSwingLow(ctx,b) : !this.isSwingHigh(ctx,b)) continue;
        const q=forBuy ? ctx.bars.low(b) : ctx.bars.high(b);
        if(Math.abs(p-q)>ctx.inputs.equalTolATR*aa) continue;

        const pool=forBuy ? Math.min(p,q) : Math.max(p,q);
        const confirm=Math.min(a,b);
        const newestSweep=Math.max(1,confirm-1);
        const oldestSweep=Math.max(1,Math.min(end-1,confirm-ctx.inputs.maxSweepAgeBars));
        for(let sw=newestSweep;sw>=oldestSweep;sw--){
          if(forBuy){
            if(!(ctx.bars.low(sw)<pool && ctx.bars.close(sw)>pool)) continue;
            const atr=this.atr(ctx,sw);
            if(!(atr>0)) continue;
            const wick=pool-ctx.bars.low(sw);
            const reclaim=ctx.bars.close(sw)-pool;
            const ratio=wick>0?Math.max(0,Math.min(reclaim/wick,1)):0;
            if(ratio<ctx.inputs.minRejectionRatio) continue;
            const pen=wick/atr;
            const key="L:"+sw+":"+pool.toFixed(5);
            best={sw,pool,ratio,pen,key};
          } else {
            if(!(ctx.bars.high(sw)>pool && ctx.bars.close(sw)<pool)) continue;
            const atr=this.atr(ctx,sw);
            if(!(atr>0)) continue;
            const wick=ctx.bars.high(sw)-pool;
            const reclaim=pool-ctx.bars.close(sw);
            const ratio=wick>0?Math.max(0,Math.min(reclaim/wick,1)):0;
            if(ratio<ctx.inputs.minRejectionRatio) continue;
            const pen=wick/atr;
            const key="S:"+sw+":"+pool.toFixed(5);
            best={sw,pool,ratio,pen,key};
          }
          return best;
        }
      }
    }
    return null;
  }

  findStructure(ctx:Context,forBuy:boolean,sw:number):any {
    const start=Math.max(ctx.inputs.swingStrength+1,3);
    const maxPivot=Math.min(ctx.inputs.lookbackBars,ctx.bars.count-ctx.inputs.swingStrength-1);
    for(let pivot=sw+1;pivot<=maxPivot;pivot++){
      if(forBuy ? !this.isSwingHigh(ctx,pivot) : !this.isSwingLow(ctx,pivot)) continue;
      const level=forBuy?ctx.bars.high(pivot):ctx.bars.low(pivot);
      for(let bos=pivot-1;bos>=1;bos--){
        if(bos>ctx.inputs.maxStructureAgeBars) continue;
        const atr=this.atr(ctx,bos);
        if(!(atr>0)) continue;
        const crossed=forBuy ? ctx.bars.close(bos)>level+0.1*atr : ctx.bars.close(bos)<level-0.1*atr;
        if(!crossed) continue;
        const dist=forBuy ? (ctx.bars.close(bos)-level)/atr : (level-ctx.bars.close(bos))/atr;
        const br=this.bodyRatio(ctx,bos);
        const strength=Math.max(0,Math.min(1,0.6*Math.min(dist/1,1)+0.4*Math.min(br/0.75,1)));
        return {pivot,bos,level,strength};
      }
    }
    return null;
  }

  findDisplacement(ctx:Context,forBuy:boolean,sw:number,bos:number):any {
    const oldest=Math.min(sw-1,bos+ctx.inputs.maxSweepAgeBars);
    for(let i=bos;i<=oldest;i++){
      const atr=this.atr(ctx,i);
      if(!(atr>0)) continue;
      const range=ctx.bars.high(i)-ctx.bars.low(i);
      if(!(range>0)) continue;
      const directional=forBuy ? ctx.bars.close(i)>ctx.bars.open(i) : ctx.bars.close(i)<ctx.bars.open(i);
      const ra=range/atr;
      if(!directional || ra<ctx.inputs.minDisplacementATR) continue;
      const br=this.bodyRatio(ctx,i);
      if(br<ctx.inputs.minBodyRatio) continue;
      return {bar:i,atr,rangeATR:ra,bodyRatio:br};
    }
    return null;
  }

  findFVG(ctx:Context,forBuy:boolean,bos:number,disp:number,sw:number):any {
    const newest=Math.max(1,bos);
    const oldest=Math.min(ctx.bars.count-3,disp+ctx.inputs.maxStructureToFVG);
    let best:any=null;
    for(let mid=newest+1;mid<=oldest+1;mid++){
      const newer=mid-1, older=mid+1;
      if(newer<1 || older>=ctx.bars.count) continue;
      let top=0,bottom=0;
      if(forBuy){
        if(ctx.bars.low(newer)<=ctx.bars.high(older)) continue;
        top=ctx.bars.low(newer); bottom=ctx.bars.high(older);
      } else {
        if(ctx.bars.high(newer)>=ctx.bars.low(older)) continue;
        top=ctx.bars.low(older); bottom=ctx.bars.high(newer);
      }
      const atr=this.atr(ctx,mid);
      if(!(atr>0)) continue;
      const width=Math.abs(top-bottom);
      if(width<ctx.inputs.minFVGATR*atr) continue;
      const completion=newer;
      if(completion<bos || completion>disp) continue;
      if(completion>=sw) continue;
      const age=Math.max(0,completion-1);
      if(age>ctx.inputs.maxStructureAgeBars) continue;
      const price=ctx.bars.close(1);
      const midPrice=(top+bottom)/2;
      const dist=Math.abs(price-midPrice)/this.atr(ctx,1);
      if(dist>ctx.inputs.maxFVGDistanceATR) continue;
      best={top,bottom,widthATR:width/atr,completion,age};
      break;
    }
    return best;
  }

  locationOK(ctx:Context,forBuy:boolean,pivot:number,fvgMid:number):boolean {
    let hi=-Infinity,lo=Infinity;
    const limit=Math.min(ctx.inputs.lookbackBars,ctx.bars.count-ctx.inputs.swingStrength-1);
    const start=Math.max(pivot+1,ctx.inputs.swingStrength+1);
    for(let i=start;i<=limit;i++){
      if(this.isSwingHigh(ctx,i)) hi=Math.max(hi,ctx.bars.high(i));
      if(this.isSwingLow(ctx,i)) lo=Math.min(lo,ctx.bars.low(i));
    }
    if(!(hi>lo) || !isFinite(fvgMid)) return false;
    const mid=lo+0.5*(hi-lo);
    return forBuy ? fvgMid<=mid : fvgMid>=mid;
  }



  rvol(ctx:Context):number {
    const n=ctx.inputs.rvolLookback;
    if(ctx.bars.count<n+3) return 0;
    let sum=0;
    for(let i=2;i<=n+1;i++) sum+=ctx.bars.volume(i);
    const avg=sum/n;
    return avg>0 ? ctx.bars.volume(1)/avg : 0;
  }

  fibInZone(ctx:Context,forBuy:boolean):boolean {
    const limit=Math.min(ctx.inputs.lookbackBars,ctx.bars.count-ctx.inputs.swingStrength-1);
    let hi=-Infinity,lo=-Infinity,hiBar=-1,loBar=-1;
    for(let i=ctx.inputs.swingStrength+1;i<=limit;i++){
      if(forBuy && this.isSwingHigh(ctx,i)){hi=ctx.bars.high(i);hiBar=i;break;}
      if(!forBuy && this.isSwingLow(ctx,i)){lo=ctx.bars.low(i);loBar=i;break;}
    }
    if(forBuy && hiBar<0) return false;
    if(!forBuy && loBar<0) return false;
    let legLow=-Infinity,legHigh=-Infinity;
    if(forBuy){
      for(let i=hiBar+1;i<=limit;i++) if(this.isSwingLow(ctx,i)){legLow=ctx.bars.low(i);break;}
      if(!(legLow>-Infinity)||!(hi>legLow)) return false;
      const pct=(hi-ctx.bars.close(1))/(hi-legLow)*100;
      const a=Math.min(ctx.inputs.fibZoneMinPct,ctx.inputs.fibZoneMaxPct),b=Math.max(ctx.inputs.fibZoneMinPct,ctx.inputs.fibZoneMaxPct);
      return pct>=a&&pct<=b;
    } else {
      for(let i=loBar+1;i<=limit;i++) if(this.isSwingHigh(ctx,i)){legHigh=ctx.bars.high(i);break;}
      if(!(legHigh<Infinity)||!(legHigh>lo)) return false;
      const pct=(ctx.bars.close(1)-lo)/(legHigh-lo)*100;
      const a=Math.min(ctx.inputs.fibZoneMinPct,ctx.inputs.fibZoneMaxPct),b=Math.max(ctx.inputs.fibZoneMinPct,ctx.inputs.fibZoneMaxPct);
      return pct>=a&&pct<=b;
    }
  }
  optionalFiltersOK(ctx:Context,forBuy:boolean):boolean {
    if(ctx.inputs.requireVolumeConfirmation && this.rvol(ctx)<ctx.inputs.rvolThreshold){
      this.volumeRejects++;
      return false;
    }
    if(ctx.inputs.requireFibonacciZone && !this.fibInZone(ctx,forBuy)){
      this.fibRejects++;
      return false;
    }
    return true;
  }

  openRiskPercent(ctx:Context):number {
    const lots=ctx.account.lots;
    let riskMoney=0;
    for(let i=0;i<lots.length;i++){
      const lot=lots[i];
      const idx=this.stateIndex(lot.lotId);
      if(idx<0)return Infinity;
      const state=this.tradeStates[idx];
      if(!(state.initialQuantity>0)||!(state.riskMoney>0)||!(lot.quantity>0))return Infinity;
      if(lot.stopLossPrice===null && lot.trailPrice===null)return Infinity;
      const remaining=Math.min(1,Math.max(0,lot.quantity/state.initialQuantity));
      riskMoney+=state.riskMoney*remaining;
    }
    const balance=ctx.account.balance;
    return balance>0 ? 100*riskMoney/balance : Infinity;
  }

  chain(ctx:Context,forBuy:boolean):any {
    const liq=this.findLiquidity(ctx,forBuy);
    if(liq===null) return null;

    const st=this.findStructure(ctx,forBuy,liq.sw);
    if(st===null) return null;

    const disp=this.findDisplacement(ctx,forBuy,liq.sw,st.bos);
    if(disp===null) return null;

    const fvg=this.findFVG(ctx,forBuy,st.bos,disp.bar,liq.sw);
    if(fvg===null) return null;

    if(!this.locationOK(ctx,forBuy,st.pivot,(fvg.top+fvg.bottom)/2)) return null;

    const price=ctx.bars.close(1);
    const invalidation=forBuy?ctx.bars.low(liq.sw):ctx.bars.high(liq.sw);
    const atr=this.atr(ctx,1);
    if(!(atr>0)) return null;
    if(forBuy ? invalidation>=fvg.bottom : invalidation<=fvg.top) return null;

    const sweepQ=Math.max(0,Math.min(liq.ratio,1));
    const dispQ=Math.max(0,Math.min(disp.rangeATR/2.5,1));
    const structQ=Math.max(0,Math.min(st.strength,1));
    const fvgQ=Math.max(0,Math.min(fvg.widthATR,1));
    const freshQ=1;
    const locQ=1;
    const quality=forBuy
      ? 100*(0.20*sweepQ+0.20*dispQ+0.20*structQ+0.15*fvgQ+0.10*freshQ+0.15*locQ)
      : 100*(0.20*sweepQ+0.20*dispQ+0.20*structQ+0.15*fvgQ+0.10*freshQ+0.15*locQ);

    if(quality<ctx.inputs.minQuality) return null;
    if(ctx.inputs.rewardRisk<ctx.inputs.minRunnerRR)return null;
    if(!this.optionalFiltersOK(ctx,forBuy))return null;

    return {
      quality,
      sw:liq.sw,
      bos:st.bos,
      disp:disp.bar,
      fvg,
      invalidation,
      entryKey:(forBuy?"L":"S")+":"+st.bos+":"+fvg.completion,
      score:quality,
      rejectionRatio:liq.ratio
    };
  }


  finalizeDay(ctx:Context):void {
    if(this.dayKey<0||this.lastFinalizedDay===this.dayKey)return;
    if(this.currentDayEligible){
      this.daysObserved++;
      this.dailyEntrySum+=this.entriesToday;
      this.dailyShortfallSum+=Math.max(0,ctx.inputs.minDailyTrades-this.entriesToday);
      if(this.entriesToday>=ctx.inputs.minDailyTrades)this.daysMetMinimum++;
      else this.daysBelowMinimum++;
      if(this.entriesToday>this.maxEntriesInDay)this.maxEntriesInDay=this.entriesToday;
    }
    this.lastFinalizedDay=this.dayKey;
  }

  rollDay(ctx:Context):void {
    const key=Math.floor(ctx.time/86400000);
    const sessionNow=this.inSession(ctx);
    if(this.dayKey<0){
      this.dayKey=key;
      this.entriesToday=0;
      this.currentDayEligible=sessionNow;
      return;
    }
    if(key!==this.dayKey){
      this.finalizeDay(ctx);
      this.dayKey=key;
      this.entriesToday=0;
      this.currentDayEligible=sessionNow;
    }else if(sessionNow){
      this.currentDayEligible=true;
    }
  }

  tierIndex(tier:string):number {
    if(tier==="strict")return 0;
    if(tier==="singleSwing")return 1;
    if(tier==="continuation")return 2;
    if(tier==="microMomentum")return 3;
    return 4;
  }

  // Diagnostic only: lastClosedTrade exposes one latest close, so multiple closes on
  // one market update cannot be reconstructed here. Use saved session rows grouped by
  // openingFillId for authoritative whole-position and family/regime outcomes.
  captureLastClosed(ctx:Context):void {
    const engineClosedTrades=ctx.stats.trades;
    const newlyClosed=engineClosedTrades-this.lastEngineClosedTrades;
    if(newlyClosed>1){this.missedCloseEvents+=newlyClosed-1;this.positionAttributionValid=false;}
    this.lastEngineClosedTrades=engineClosedTrades;
    const t=ctx.account.lastClosedTrade;
    if(t===null)return;
    const sig=[t.openTime,t.closeTime,t.openPrice,t.closePrice,t.quantity,t.pnl,t.side].join(":");
    if(sig===this.lastClosedSignature)return;
    this.lastClosedSignature=sig;

    let state:any=null;
    for(let i=0;i<this.tradeStates.length;i++){
      const s=this.tradeStates[i];
      if(s.entryTime===t.openTime&&s.side===t.side&&Math.abs(s.entryPrice-t.openPrice)<0.05){
        state=s;break;
      }
    }
    if(state===null){this.unmatchedCloseRecords++;return;}
    state.closedPnl+=t.pnl;
    state.closedQty+=t.quantity;
    state.closedRows++;
    this.capturedClosedPnl+=t.pnl;
  }

  finalizePositionState(state:any,ctx:Context):void {
    if(state.finalized)return;
    state.finalized=true;
    if(state.closedRows<=0){
      this.unmatchedCloseRecords++;
      return;
    }
    this.positionTradeCount++;
    this.positionNetPnl+=state.closedPnl;
    const riskMoney=state.riskMoney>0?state.riskMoney:1;
    const netR=state.closedPnl/riskMoney;
    this.positionNetR+=netR;
    if(state.closedPnl>0)this.positionWins++;
    else if(state.closedPnl<0)this.positionLosses++;
    else this.positionFlat++;

    if(state.featuresKnown){
      const featureValues=[state.entryQuality,state.entryRVOL,state.spreadATR,state.rejectionRatio,
        state.fvgWidthATR,state.sweepAgeBars,state.bosAgeBars,state.displacementRangeATR,
        state.displacementBodyRatio,state.trendSlopeATR,state.maxFavorableR,state.maxAdverseR];
      if(state.closedPnl>0){
        this.featureWinN++;
        for(let k=0;k<featureValues.length;k++)this.featureWinSums[k]+=featureValues[k];
      }else if(state.closedPnl<0){
        this.featureLossN++;
        for(let k=0;k<featureValues.length;k++)this.featureLossSums[k]+=featureValues[k];
      }
      const regimeIndex=state.regimeProxy;
      if(regimeIndex>=0 && regimeIndex<3){
        this.regimePositionN[regimeIndex]++;
        if(state.closedPnl>0)this.regimePositionW[regimeIndex]++;
        else if(state.closedPnl<0)this.regimePositionL[regimeIndex]++;
      }
    }

    if(state.tp1Done)this.positionTP1Count++;
    if(state.tp2Done)this.positionTP2Count++;
    if(state.maxFavorableR>=2)this.position2RCount++;
    if(state.maxFavorableR>=3)this.position3RCount++;

    const idx=Math.max(0,Math.min(4,state.tierIndex));
    this.tierPositionN[idx]++;
    this.tierPositionPnl[idx]+=state.closedPnl;
    if(state.closedPnl>0)this.tierPositionW[idx]++;
    else if(state.closedPnl<0)this.tierPositionL[idx]++;

    if(state.tp2Done){
      const isSingleSwing=state.tierIndex===1;
      const isContinuation=state.tierIndex===2;
      const tp1RR=isSingleSwing?ctx.inputs.singleSwingTP1RR:(isContinuation?ctx.inputs.continuationTP1RR:ctx.inputs.tp1RR);
      const tp2RR=isSingleSwing?ctx.inputs.singleSwingTP2RR:(isContinuation?ctx.inputs.continuationTP2RR:ctx.inputs.tp2RR);
      const tp1Fraction=isSingleSwing?ctx.inputs.singleSwingTP1CloseFraction:(isContinuation?ctx.inputs.continuationTP1CloseFraction:ctx.inputs.tp1CloseFraction);
      const tp2Fraction=isSingleSwing?ctx.inputs.singleSwingTP2CloseFraction:(isContinuation?ctx.inputs.continuationTP2CloseFraction:ctx.inputs.tp2CloseFraction);
      const bookedR=(tp1Fraction*tp1RR)+(tp2Fraction*tp2RR);
      this.runnerNetPnl+=state.closedPnl-riskMoney*bookedR;
    }
  }

  stateIndex(lotId:number):number {
    for(let i=0;i<this.tradeStates.length;i++)if(this.tradeStates[i].lotId===lotId)return i;
    return -1;
  }

  registerLot(ctx:Context,lot:any,risk:number):any {
    let idx=this.stateIndex(lot.lotId);
    if(idx>=0)return this.tradeStates[idx];
    const r=risk>0?risk:Math.abs(lot.entryPrice-(lot.stopLossPrice===null?lot.entryPrice:lot.stopLossPrice));
    const q:any={
      lotId:lot.lotId,
      side:lot.side,
      entryPrice:lot.entryPrice,
      risk:r>0?r:this.atr(ctx,1)*1.5,
      riskMoney:ctx.account.balance*ctx.inputs.riskFraction/100,
      entryTime:lot.entryTime,
      initialQuantity:lot.quantity,
      closedQty:0,
      closedRows:0,
      closedPnl:0,
      tp1Done:false,
      tp2Done:false,
      runnerTrailArmed:false,
      forceClosed:false,
      finalized:false,
      missingSince:0,
      tierIndex:3,
      featuresKnown:false,
      entryQuality:0, entryRVOL:0, spreadATR:0, rejectionRatio:0, fvgWidthATR:0,
      sweepAgeBars:0, bosAgeBars:0, displacementAgeBars:0, displacementRangeATR:0,
      displacementBodyRatio:0, trendSlopeATR:0, regimeProxy:-1,
      maxFavorableR:0, maxAdverseR:0
    };
    this.tradeStates.push(q);
    return q;
  }

  manageLots(ctx:Context):void {
    this.captureLastClosed(ctx);
    const lots=ctx.account.lots;
    for(let i=0;i<lots.length;i++){
      const lot=lots[i];
      const st=this.registerLot(ctx,lot,0);
      if(!(st.risk>0)||st.forceClosed)continue;

      const isBuy=lot.side==="Long";
      const isSingleSwing=st.tierIndex===1;
      const isContinuation=st.tierIndex===2;
      const tp1RR=isSingleSwing?ctx.inputs.singleSwingTP1RR:(isContinuation?ctx.inputs.continuationTP1RR:ctx.inputs.tp1RR);
      const tp2RR=isSingleSwing?ctx.inputs.singleSwingTP2RR:(isContinuation?ctx.inputs.continuationTP2RR:ctx.inputs.tp2RR);
      const tp1CloseFraction=isSingleSwing?ctx.inputs.singleSwingTP1CloseFraction:(isContinuation?ctx.inputs.continuationTP1CloseFraction:ctx.inputs.tp1CloseFraction);
      const tp2CloseFraction=isSingleSwing?ctx.inputs.singleSwingTP2CloseFraction:(isContinuation?ctx.inputs.continuationTP2CloseFraction:ctx.inputs.tp2CloseFraction);
      const trailATR=isSingleSwing?ctx.inputs.singleSwingTrailATR:(isContinuation?ctx.inputs.continuationTrailATR:ctx.inputs.trailATR);
      const beOffsetR=isSingleSwing?ctx.inputs.singleSwingBEOffsetR:(isContinuation?ctx.inputs.continuationBEOffsetR:ctx.inputs.beOffsetR);
      const px=isBuy?ctx.bid:ctx.ask;
      const favorableR=isBuy?(px-st.entryPrice)/st.risk:(st.entryPrice-px)/st.risk;
      st.maxFavorableR=Math.max(st.maxFavorableR,favorableR);
      const adverseR=isBuy?(st.entryPrice-px)/st.risk:(px-st.entryPrice)/st.risk;
      st.maxAdverseR=Math.max(st.maxAdverseR,adverseR);
      const tp1=isBuy?st.entryPrice+st.risk*tp1RR:st.entryPrice-st.risk*tp1RR;
      const tp2=isBuy?st.entryPrice+st.risk*tp2RR:st.entryPrice-st.risk*tp2RR;
      const hit1=isBuy?px>=tp1:px<=tp1;
      const hit2=isBuy?px>=tp2:px<=tp2;

      if(!st.tp1Done&&hit1){
        const frac=Math.max(0,Math.min(tp1CloseFraction,0.95));
        if(frac>0)ctx.orders.closeLot(st.lotId,lot.quantity*frac);
        ctx.orders.setLotStops(st.lotId,{
          slPrice:isBuy?st.entryPrice+st.risk*beOffsetR:st.entryPrice-st.risk*beOffsetR,
          tpPrice:isBuy?st.entryPrice+st.risk*Math.max(ctx.inputs.rewardRisk,ctx.inputs.minRunnerRR):st.entryPrice-st.risk*Math.max(ctx.inputs.rewardRisk,ctx.inputs.minRunnerRR)
        });
        st.tp1Done=true;
        this.tp1Count++;
      }else if(st.tp1Done&&!st.tp2Done&&hit2){
        const remain=Math.max(0.0001,1-tp1CloseFraction);
        const frac=Math.max(0,Math.min(tp2CloseFraction/remain,1));
        const liveLots=ctx.account.lots;
        let qty=0;
        for(let j=0;j<liveLots.length;j++)if(liveLots[j].lotId===st.lotId)qty=liveLots[j].quantity;
        if(qty>0&&frac>0)ctx.orders.closeLot(st.lotId,qty*frac);
        ctx.orders.setLotStops(st.lotId,{tpPrice:null});
        const a=this.atr(ctx,1);
        if(a>0)ctx.orders.setLotTrail(st.lotId,a*trailATR);
        st.tp2Done=true;
        st.runnerTrailArmed=true;
        this.tp2Count++;
      }

      if(st.entryTime>0&&ctx.time-st.entryTime>=ctx.inputs.maxHoldBars*ctx.run.interval*60000){
        ctx.orders.closeLot(st.lotId);
        st.forceClosed=true;
      }
    }

    // A second capture catches synchronous closes issued by this manager on the same update.
    this.captureLastClosed(ctx);
    const live=ctx.account.lots;
    for(let j=this.tradeStates.length-1;j>=0;j--){
      const state=this.tradeStates[j];
      let found=false;
      for(let i=0;i<live.length;i++)if(live[i].lotId===state.lotId){found=true;break;}
      if(found)state.missingSince=0;
      else if(state.missingSince===0)state.missingSince=ctx.time;
      else{
        this.finalizePositionState(state,ctx);
        this.tradeStates.splice(j,1);
      }
    }
  }

  selectDirection(buy:any,sell:any,directionalAdvantage:number):any {
    const buyOK=buy!==null,sellOK=sell!==null;
    if(!buyOK&&!sellOK)return null;
    if(buyOK&&!sellOK)return{side:"Long",chosen:buy};
    if(sellOK&&!buyOK)return{side:"Short",chosen:sell};
    const delta=buy.score-sell.score;
    if(delta>=directionalAdvantage)return{side:"Long",chosen:buy};
    if(-delta>=directionalAdvantage)return{side:"Short",chosen:sell};
    return null;
  }

  singleSwingChain(ctx:Context,forBuy:boolean):any {
    const atr=this.atr(ctx,1);
    if(!(atr>0)||ctx.bars.count<60)return null;
    let fastMean=0,slowMean=0;
    for(let k=1;k<=8;k++)fastMean+=ctx.bars.close(k);
    for(let k=1;k<=21;k++)slowMean+=ctx.bars.close(k);
    const trendSlopeATR=Math.abs(fastMean/8-slowMean/21)/atr;
    // In adaptive mode, preserve range-like entries for PD validation,
    // reject the weak transition band, and require stronger trend slope elsewhere.
    if(ctx.inputs.adaptiveFallbackPD && trendSlopeATR>=ctx.inputs.fallbackPDTrendThreshold &&
       trendSlopeATR<ctx.inputs.minSingleSwingTrendSlopeATR)return null;
    const maxPivot=Math.min(ctx.inputs.lookbackBars,45);
    const maxAge=Math.min(ctx.inputs.fallbackMaxSweepBars,ctx.inputs.maxSweepAgeBars+2);
    let best:any=null;

    for(let pivot=ctx.inputs.swingStrength+2;pivot<=maxPivot;pivot++){
      if(forBuy?!this.isSwingLow(ctx,pivot):!this.isSwingHigh(ctx,pivot))continue;
      const level=forBuy?ctx.bars.low(pivot):ctx.bars.high(pivot);
      for(let sw=pivot-1;sw>=Math.max(2,pivot-maxAge);sw--){
        const swept=forBuy
          ?ctx.bars.low(sw)<level&&ctx.bars.close(sw)>level
          :ctx.bars.high(sw)>level&&ctx.bars.close(sw)<level;
        if(!swept)continue;

        const wick=forBuy?level-ctx.bars.low(sw):ctx.bars.high(sw)-level;
        const reclaim=forBuy?ctx.bars.close(sw)-level:level-ctx.bars.close(sw);
        if(!(wick>0))continue;
        const rejection=Math.max(0,Math.min(1,reclaim/wick));
        if(rejection<ctx.inputs.minRejectionRatio*0.65)continue;

        let micro=forBuy?-Infinity:Infinity;
        for(let k=2;k<sw;k++){
          if(forBuy)micro=Math.max(micro,ctx.bars.high(k));
          else micro=Math.min(micro,ctx.bars.low(k));
        }
        if(!isFinite(micro))continue;
        const close1=ctx.bars.close(1),close2=ctx.bars.close(2);
        const crossed=forBuy
          ?close1>micro&&close2<=micro&&close1>ctx.bars.open(1)
          :close1<micro&&close2>=micro&&close1<ctx.bars.open(1);
        if(!crossed)continue;

        const body=this.bodyRatio(ctx,1);
        const range=ctx.bars.high(1)-ctx.bars.low(1);
        const rangeATR=range/atr;
        const effectiveRangeCap=ctx.inputs.adaptiveFallbackPD
          ? (trendSlopeATR<ctx.inputs.fallbackPDTrendThreshold?ctx.inputs.maxSingleSwingRangeATR:ctx.inputs.trendSingleSwingRangeATR)
          : ctx.inputs.maxSingleSwingRangeATR;
        if(body<ctx.inputs.minBodyRatio*0.75||rangeATR<0.55||rangeATR>effectiveRangeCap)continue;
        const breakQ=Math.max(0,Math.min(1,Math.abs(close1-micro)/(0.25*atr)));
        const rejectQ=Math.max(0,Math.min(1,rejection/0.65));
        const bodyQ=Math.max(0,Math.min(1,body/0.65));
        const quality=100*(0.35*rejectQ+0.40*breakQ+0.25*bodyQ);
        if(quality<ctx.inputs.singleSwingMinQuality)continue;

        let applyFallbackPD=ctx.inputs.requireFallbackPD;
        if(ctx.inputs.adaptiveFallbackPD){
          applyFallbackPD=trendSlopeATR<ctx.inputs.fallbackPDTrendThreshold;
        }
        if(applyFallbackPD){
          let rangeHigh=-Infinity,rangeLow=Infinity;
          const rangeLimit=Math.min(40,ctx.bars.count-2);
          for(let k=2;k<=rangeLimit;k++){
            rangeHigh=Math.max(rangeHigh,ctx.bars.high(k));
            rangeLow=Math.min(rangeLow,ctx.bars.low(k));
          }
          if(!(rangeHigh>rangeLow))continue;
          const midpoint=(rangeHigh+rangeLow)/2;
          const price=ctx.bars.close(1);
          if(forBuy?price>midpoint:price<midpoint)continue;
        }

        const invalidation=forBuy?ctx.bars.low(sw):ctx.bars.high(sw);
        const key="SS:"+(forBuy?"L":"S")+":"+ctx.bars.time(pivot)+":"+ctx.bars.time(sw);
        if(ctx.inputs.rewardRisk<ctx.inputs.minRunnerRR)continue;
        if(!this.optionalFiltersOK(ctx,forBuy))continue;
        const cand={quality,score:quality,sw,bos:1,disp:1,invalidation,entryKey:key,rejectionRatio:rejection,mode:"singleSwing"};
        if(best===null||cand.score>best.score)best=cand;
      }
    }
    return best;
  }

  continuationChain(ctx:Context,forBuy:boolean):any {
    const atr=this.atr(ctx,1);
    if(!(atr>0)||ctx.bars.count<60)return null;
    let fast=0,slow=0;
    for(let i=1;i<=20;i++)fast+=ctx.bars.close(i);
    for(let i=1;i<=50;i++)slow+=ctx.bars.close(i);
    fast/=20; slow/=50;
    const close1=ctx.bars.close(1),close2=ctx.bars.close(2);
    if(forBuy?!(close1>fast&&fast>slow):!(close1<fast&&fast<slow))return null;

    const body=this.bodyRatio(ctx,1);
    const range=ctx.bars.high(1)-ctx.bars.low(1);
    if(body<0.40||range/atr<0.60)return null;

    let touched=false;
    for(let i=1;i<=5;i++){
      if(forBuy){
        if(ctx.bars.low(i)<=fast+0.20*atr&&ctx.bars.high(i)>=fast-0.20*atr)touched=true;
      }else{
        if(ctx.bars.high(i)>=fast-0.20*atr&&ctx.bars.low(i)<=fast+0.20*atr)touched=true;
      }
    }
    if(!touched)return null;

    let level=forBuy?-Infinity:Infinity;
    for(let i=2;i<=5;i++){
      if(forBuy)level=Math.max(level,ctx.bars.high(i));
      else level=Math.min(level,ctx.bars.low(i));
    }
    const crossed=forBuy?close1>level&&close2<=level:close1<level&&close2>=level;
    if(!crossed)return null;

    const strength=Math.max(0,Math.min(1,Math.abs(close1-level)/(0.25*atr)));
    const quality=100*(0.45*Math.min(body/0.7,1)+0.35*strength+0.20*Math.min(Math.abs(close1-fast)/atr,1));
    if(quality<ctx.inputs.fallbackQualityFloor)return null;
    if(ctx.inputs.rewardRisk<ctx.inputs.minRunnerRR)return null;
    if(!this.optionalFiltersOK(ctx,forBuy))return null;

    let invalidation=forBuy?ctx.bars.low(1):ctx.bars.high(1);
    for(let i=2;i<=5;i++)invalidation=forBuy?Math.min(invalidation,ctx.bars.low(i)):Math.max(invalidation,ctx.bars.high(i));
    const key="TC:"+(forBuy?"L":"S")+":"+ctx.bars.time(1)+":"+level.toFixed(2);
    return{quality,score:quality,sw:1,bos:1,disp:1,invalidation,entryKey:key,rejectionRatio:body,mode:"continuation"};
  }

  microMomentumChain(ctx:Context,forBuy:boolean):any {
    const atr=this.atr(ctx,1);
    if(!(atr>0)||ctx.bars.count<60)return null;

    let fast=0,slow=0;
    for(let i=1;i<=9;i++)fast+=ctx.bars.close(i);
    for(let i=1;i<=20;i++)slow+=ctx.bars.close(i);
    fast/=9; slow/=20;

    const close1=ctx.bars.close(1),close2=ctx.bars.close(2);
    if(forBuy?!(close1>fast&&fast>slow):!(close1<fast&&fast<slow))return null;

    const body=this.bodyRatio(ctx,1);
    const range=ctx.bars.high(1)-ctx.bars.low(1);
    if(body<0.30||range/atr<0.45)return null;

    let level=forBuy?-Infinity:Infinity;
    for(let i=2;i<=4;i++){
      if(forBuy)level=Math.max(level,ctx.bars.high(i));
      else level=Math.min(level,ctx.bars.low(i));
    }
    const crossed=forBuy?close1>level&&close2<=level:close1<level&&close2>=level;
    if(!crossed)return null;

    let pullback=false;
    for(let i=1;i<=6;i++){
      if(forBuy){
        if(ctx.bars.low(i)<=fast+0.35*atr&&ctx.bars.high(i)>=fast-0.35*atr)pullback=true;
      }else{
        if(ctx.bars.high(i)>=fast-0.35*atr&&ctx.bars.low(i)<=fast+0.35*atr)pullback=true;
      }
    }
    if(!pullback)return null;

    const bodyQ=Math.max(0,Math.min(1,body/0.65));
    const breakQ=Math.max(0,Math.min(1,Math.abs(close1-level)/(0.20*atr)));
    const trendQ=Math.max(0,Math.min(1,Math.abs(fast-slow)/(0.40*atr)));
    const quality=100*(0.35*bodyQ+0.45*breakQ+0.20*trendQ);
    if(quality<ctx.inputs.microMomentumMinQuality)return null;
    if(ctx.inputs.rewardRisk<ctx.inputs.minRunnerRR)return null;
    if(!this.optionalFiltersOK(ctx,forBuy))return null;

    let invalidation=forBuy?ctx.bars.low(1):ctx.bars.high(1);
    for(let i=2;i<=4;i++)invalidation=forBuy?Math.min(invalidation,ctx.bars.low(i)):Math.max(invalidation,ctx.bars.high(i));
    const key="MM:"+(forBuy?"L":"S")+":"+ctx.bars.time(1)+":"+level.toFixed(2);
    return{quality,score:quality,sw:1,bos:1,disp:1,invalidation,entryKey:key,rejectionRatio:body,mode:"microMomentum"};
  }

  onUpdate(ctx:Context):void {
    this.rollDay(ctx);
    if(this.applyWeekendGuard(ctx))return;
    if(ctx.bars.count<100)return;

    // Manage every open lot independently. Entries may be added in the same net direction,
    // so long runners do not block all new same-direction opportunities.
    this.manageLots(ctx);

    if(!ctx.isNewBar||!this.inSession(ctx))return;

    if(this.entriesToday>=ctx.inputs.maxDailyTrades)return;

    const atr=this.atr(ctx,1);
    if(!(atr>0))return;

    const currentDirection:TradeSide|null=ctx.account.position>0?"Long":(ctx.account.position<0?"Short":null);
    const buy=(!ctx.inputs.enableStrictFamily||currentDirection==="Short")?null:this.chain(ctx,true);
    const sell=(!ctx.inputs.enableStrictFamily||currentDirection==="Long")?null:this.chain(ctx,false);
    let selected=this.selectDirection(buy,sell,ctx.inputs.directionalAdvantage);
    let tier="strict";

    // Fallback families are considered only when strict setup selection fails.
    // minDailyTrades is diagnostics only; it never triggers or authorizes an entry.
    if(selected===null&&ctx.inputs.enableSingleSwingFallback){
      const sb=currentDirection==="Short"?null:this.singleSwingChain(ctx,true);
      const ss=currentDirection==="Long"?null:this.singleSwingChain(ctx,false);
      selected=this.selectDirection(sb,ss,ctx.inputs.directionalAdvantage);
      if(selected!==null)tier="singleSwing";
    }
    if(selected===null&&ctx.inputs.enableContinuationFallback){
      const cb=currentDirection==="Short"?null:this.continuationChain(ctx,true);
      const cs=currentDirection==="Long"?null:this.continuationChain(ctx,false);
      selected=this.selectDirection(cb,cs,ctx.inputs.directionalAdvantage);
      if(selected!==null)tier="continuation";
    }
    if(selected===null&&ctx.inputs.enableMicroMomentumFallback){
      const mb=currentDirection==="Short"?null:this.microMomentumChain(ctx,true);
      const ms=currentDirection==="Long"?null:this.microMomentumChain(ctx,false);
      selected=this.selectDirection(mb,ms,ctx.inputs.directionalAdvantage);
      if(selected!==null)tier="microMomentum";
    }
    if(selected===null)return;

    const side:TradeSide=selected.side;
    const chosen=selected.chosen;

    // Optional family-specific eligibility gate. The transition band is excluded
    // from both specialist lanes when these switches are enabled.
    const entryRegimeSlopeATR=this.trendSlopeProxyATR(ctx);
    if(tier==="singleSwing" && ctx.inputs.rangeOnlySingleSwing &&
       (!isFinite(entryRegimeSlopeATR)||entryRegimeSlopeATR>=ctx.inputs.rangeRegimeMaxSlopeATR)){
      this.blockedSingleSwingRegime++;
      return;
    }
    if(tier==="continuation" && ctx.inputs.trendOnlyContinuation &&
       (!isFinite(entryRegimeSlopeATR)||entryRegimeSlopeATR<ctx.inputs.trendRegimeMinSlopeATR)){
      this.blockedContinuationRegime++;
      return;
    }

    // Netting-account safety: only add in the existing net direction until it is flat.
    if(ctx.account.position>0&&side!=="Long"){this.blockedOpposite++;return;}
    if(ctx.account.position<0&&side!=="Short"){this.blockedOpposite++;return;}

    const liveLots=ctx.account.lots;
    if(liveLots.length>=ctx.inputs.maxConcurrentLots){this.blockedConcurrency++;return;}
    const riskPercent=tier==="strict"?ctx.inputs.riskFraction:ctx.inputs.opportunityRiskFraction;
    if(!(riskPercent>0))return;
    const currentOpenRisk=this.openRiskPercent(ctx);
    const projectedOpenRisk=currentOpenRisk+riskPercent;
    if(!isFinite(currentOpenRisk)||projectedOpenRisk>ctx.inputs.maxPortfolioRiskPercent){
      this.blockedRiskCap++;
      return;
    }

    if(chosen.entryKey===this.lastKey)return;
    if(this.lastEntryTime>0&&ctx.time-this.lastEntryTime<ctx.inputs.cooldownBars*ctx.run.interval*60000)return;

    // Validate the protective stop against the executable side of the current quote, not the prior closed bar.
    const entryReference=side==="Long"?ctx.ask:ctx.bid;
    const familyStopBufferATR=tier==="singleSwing"?ctx.inputs.singleSwingStopBufferATR:
      (tier==="continuation"?ctx.inputs.continuationStopBufferATR:ctx.inputs.stopBufferATR);
    const familyMaxStopATR=tier==="singleSwing"?ctx.inputs.singleSwingMaxStopATR:
      (tier==="continuation"?ctx.inputs.continuationMaxStopATR:4.0);
    const stopPrice=side==="Long"
      ?chosen.invalidation-familyStopBufferATR*atr
      :chosen.invalidation+familyStopBufferATR*atr;
    const slDist=side==="Long"?entryReference-stopPrice:stopPrice-entryReference;
    if(!(slDist>0)||slDist/atr>familyMaxStopATR){this.blockedStops++;return;}

    let fill:any;
    try {
      fill=ctx.orders.marketOrder({
        side,
        risk:{percent:riskPercent},
        slPrice:stopPrice
      });
    } catch (e:any) {
      // Research-only fail-safe: skip entries the engine rejects, including sizes below its minimum step.
      this.blockedSizing++;
      return;
    }
    if(fill.lotIds.length===0)return;

    this.lastKey=chosen.entryKey;
    this.lastEntryTime=ctx.time;
    this.entryTime=ctx.time;
    this.activeLotId=fill.lotIds[0];
    this.tradeRisk=slDist;

    // Capture only information available at the signal/entry bar. This block does not
    // participate in selection, sizing, order placement or exits.
    const featureATR=this.atr(ctx,1);
    const spreadATR=featureATR>0?Math.max(0,ctx.ask-ctx.bid)/featureATR:0;
    const entryRVOL=this.rvol(ctx);
    const sweepAgeBars=chosen.sw;
    const bosAgeBars=chosen.bos;
    const displacementAgeBars=chosen.disp;
    const displacementATR=this.atr(ctx,chosen.disp);
    const displacementRangeATR=displacementATR>0?(ctx.bars.high(chosen.disp)-ctx.bars.low(chosen.disp))/displacementATR:0;
    const displacementRange=ctx.bars.high(chosen.disp)-ctx.bars.low(chosen.disp);
    const displacementBodyRatio=displacementRange>0?Math.abs(ctx.bars.close(chosen.disp)-ctx.bars.open(chosen.disp))/displacementRange:0;
    let fastMean=0,slowMean=0;
    for(let k=1;k<=8;k++)fastMean+=ctx.bars.close(k);
    for(let k=1;k<=21;k++)slowMean+=ctx.bars.close(k);
    fastMean/=8; slowMean/=21;
    const trendSlopeATR=featureATR>0?Math.abs(fastMean-slowMean)/featureATR:0;
    // Research-only regime proxy: 0=range-like, 1=transition, 2=trend-like.
    // It is not claimed to reproduce the MT5 EA's trend/phase classifier.
    const regimeProxy=trendSlopeATR>=0.45?2:(trendSlopeATR<0.20?0:1);
    const entryFVGWidthATR=chosen.fvg!==undefined?chosen.fvg.widthATR:0;

    for(let i=0;i<fill.lotIds.length;i++){
      let initialQty=0;
      const openedLots=ctx.account.lots;
      for(let j=0;j<openedLots.length;j++)if(openedLots[j].lotId===fill.lotIds[i])initialQty=openedLots[j].quantity;
      this.tradeStates.push({
        lotId:fill.lotIds[i],
        side,
        entryPrice:fill.fillPrice,
        risk:slDist,
        riskMoney:ctx.account.balance*riskPercent/100,
        entryTime:ctx.time,
        initialQuantity:initialQty,
        closedQty:0,
        closedRows:0,
        closedPnl:0,
        tp1Done:false,
        tp2Done:false,
        runnerTrailArmed:false,
        forceClosed:false,
        finalized:false,
        missingSince:0,
        tierIndex:this.tierIndex(tier),
        featuresKnown:true,
        entryQuality:chosen.quality,
        entryRVOL,
        spreadATR,
        rejectionRatio:chosen.rejectionRatio,
        fvgWidthATR:entryFVGWidthATR,
        sweepAgeBars,
        bosAgeBars,
        displacementAgeBars,
        displacementRangeATR,
        displacementBodyRatio,
        trendSlopeATR,
        regimeProxy,
        maxFavorableR:0,
        maxAdverseR:0
      });
      // Persist entry-time lineage independently of the in-run close observer.
      // Saved session rows are joined later by timestamp, side and actual fill price.
      const entryRecord=[
        String(Math.round(ctx.time)),
        side==="Long"?"L":"S",
        fill.fillPrice.toFixed(8),
        String(this.tierIndex(tier)),
        String(regimeProxy),
        chosen.quality.toFixed(1),
        (ctx.account.balance*riskPercent/100).toFixed(4),
        spreadATR.toFixed(4),
        trendSlopeATR.toFixed(4)
      ].join("|");
      this.entryAttributionRecords.push(entryRecord);
    }

    this.entriesToday++;
    this.totalEntriesPlaced++;
    if(this.entriesToday>this.maxEntriesInDay)this.maxEntriesInDay=this.entriesToday;
    if(tier==="strict")this.strictEntries++;
    else if(tier==="singleSwing")this.singleSwingEntries++;
    else if(tier==="continuation")this.continuationEntries++;
    else if(tier==="microMomentum")this.microMomentumEntries++;
    else this.continuationEntries++;

  }

  onFinish(ctx:Context):void {
    this.captureLastClosed(ctx);
    this.finalizeDay(ctx);
    const liveAtFinish=ctx.account.lots;
    for(let i=0;i<this.tradeStates.length;i++){
      let isOpen=false;
      for(let j=0;j<liveAtFinish.length;j++)if(liveAtFinish[j].lotId===this.tradeStates[i].lotId)isOpen=true;
      if(!isOpen)this.finalizePositionState(this.tradeStates[i],ctx);
    }
    ctx.stats.custom.set("minDailyTradesTarget",ctx.inputs.minDailyTrades);
    ctx.stats.custom.set("maxDailyTradesLimit",ctx.inputs.maxDailyTrades);
    ctx.stats.custom.set("weekendGuardEnabled",ctx.inputs.avoidWeekendExposure);
    ctx.stats.custom.set("fridayCutoffHourUTC",ctx.inputs.fridayCutoffHourUTC);
    ctx.stats.custom.set("weekendFlattenCalls",this.weekendFlattenCalls);
    ctx.stats.custom.set("weekendFlattenErrors",this.weekendFlattenErrors);
    ctx.stats.custom.set("weekendLotsTargeted",this.weekendLotsTargeted);
    ctx.stats.custom.set("weekendBlockedEntryBars",this.weekendBlockedEntryBars);
    ctx.stats.custom.set("weekendLotsRemainingAtFinish",ctx.account.lots.length);
    ctx.stats.custom.set("rangeOnlySingleSwing",ctx.inputs.rangeOnlySingleSwing);
    ctx.stats.custom.set("trendOnlyContinuation",ctx.inputs.trendOnlyContinuation);
    ctx.stats.custom.set("blockedSingleSwingRegime",this.blockedSingleSwingRegime);
    ctx.stats.custom.set("blockedContinuationRegime",this.blockedContinuationRegime);
    ctx.stats.custom.set("singleSwingStopBufferATR",ctx.inputs.singleSwingStopBufferATR);
    ctx.stats.custom.set("continuationStopBufferATR",ctx.inputs.continuationStopBufferATR);
    ctx.stats.custom.set("totalEntriesPlaced",this.totalEntriesPlaced);
    ctx.stats.custom.set("entriesOpenAtEnd",ctx.account.lots.length);
    ctx.stats.custom.set("daysObserved",this.daysObserved);
    ctx.stats.custom.set("daysMetMinimum",this.daysMetMinimum);
    ctx.stats.custom.set("daysBelowMinimum",this.daysBelowMinimum);
    ctx.stats.custom.set("dailyComplianceRate",this.daysObserved>0?100*this.daysMetMinimum/this.daysObserved:0);
    ctx.stats.custom.set("averageEntriesPerDay",this.daysObserved>0?this.dailyEntrySum/this.daysObserved:0);
    ctx.stats.custom.set("averageDailyShortfall",this.daysObserved>0?this.dailyShortfallSum/this.daysObserved:0);
    ctx.stats.custom.set("maxEntriesInDay",this.maxEntriesInDay);
    ctx.stats.custom.set("entriesToday",this.entriesToday);
    ctx.stats.custom.set("strictEntries",this.strictEntries);
    ctx.stats.custom.set("singleSwingEntries",this.singleSwingEntries);
    ctx.stats.custom.set("continuationEntries",this.continuationEntries);
    ctx.stats.custom.set("microMomentumEntries",this.microMomentumEntries);
    ctx.stats.custom.set("dailyMinimumIsDiagnosticOnly",true);
    ctx.stats.custom.set("opportunityRiskFractionConfigured",ctx.inputs.opportunityRiskFraction);
    ctx.stats.custom.set("blockedOppositeDirection",this.blockedOpposite);
    ctx.stats.custom.set("blockedPortfolioRisk",this.blockedRiskCap);
    ctx.stats.custom.set("blockedConcurrency",this.blockedConcurrency);
    ctx.stats.custom.set("blockedDailyMax",this.blockedDailyMax);
    ctx.stats.custom.set("blockedStopDistance",this.blockedStops);
    ctx.stats.custom.set("blockedOrderPlacement",this.blockedSizing);
    ctx.stats.custom.set("tp1Events",this.tp1Count);
    ctx.stats.custom.set("tp2Events",this.tp2Count);
    ctx.stats.custom.set("capturedClosedPnl",this.capturedClosedPnl);
    const reconciliationDelta=ctx.stats.totalPnl-this.capturedClosedPnl;
    if(Math.abs(reconciliationDelta)>0.01)this.positionAttributionValid=false;
    ctx.stats.custom.set("unmatchedCloseRecords",this.unmatchedCloseRecords);
    ctx.stats.custom.set("missedCloseEvents",this.missedCloseEvents);
    ctx.stats.custom.set("positionAttributionValid",this.positionAttributionValid);
    ctx.stats.custom.set("positionAttributionPnlDelta",reconciliationDelta);
    ctx.stats.custom.set("engineClosedTradeRecords",ctx.stats.trades);
    ctx.stats.custom.set("volumeRejects",this.volumeRejects);
    ctx.stats.custom.set("fibRejects",this.fibRejects);

    // Export entry-time strategy/regime lineage in bounded chunks. StrategyTune allows
    // at most 100 custom keys and 256 characters per string. Overflow is explicit.
    const mapChunks:string[]=[];
    let mapChunk="";
    for(let i=0;i<this.entryAttributionRecords.length;i++){
      const record=this.entryAttributionRecords[i];
      const candidate=mapChunk.length>0?mapChunk+";"+record:record;
      if(candidate.length>240 && mapChunk.length>0){
        mapChunks.push(mapChunk);
        mapChunk=record;
      }else{
        mapChunk=candidate;
      }
    }
    if(mapChunk.length>0)mapChunks.push(mapChunk);
    const maxMapChunks=48;
    const exportedChunks=Math.min(mapChunks.length,maxMapChunks);
    for(let i=0;i<exportedChunks;i++){
      ctx.stats.custom.set("entryMap"+i,mapChunks[i]);
    }
    ctx.stats.custom.set("entryMapVersion",1);
    ctx.stats.custom.set("entryMapRecords",this.entryAttributionRecords.length);
    ctx.stats.custom.set("entryMapChunks",mapChunks.length);
    ctx.stats.custom.set("entryMapOverflow",mapChunks.length>maxMapChunks);
    ctx.stats.custom.set("sessionRowsAuthoritative",true);
  }
}
export default MidasTouch2NoQuotaResearch;
