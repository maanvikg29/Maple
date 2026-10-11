# Research pacing model, shared helpers (2026-10-11): usage profiles and sampling used by pacing-model.py; not used at build time.
import random, statistics as st, json, sys
HOURS=[1,2,3,5,7,10,13,16,20,24,28,32,36,40,45,50]+list(range(55,101,5))+[110,120,130,140,150,160,168,180,190,200]+[210,220,230,240,250]+list(range(265,401,15))+list(range(420,721,20))+[740,760,780,800]+list(range(825,1501,25))+list(range(1530,1801,30))+[1840,1880,1920,1960,2000]
assert len(HOURS)==114 and len(set(HOURS))==114 and HOURS==sorted(HOURS), (len(HOURS))
LAD={
 'streak':[3,7,14,21,30,50,75,100,200,365],
 'sessions':[1,5,10,25,50,100,250,500],
 'mornings':[1,3,7,21,50,100,200],
 'bedtime':[1,3,7,21,50,100,200],
 'sleep':[1,5,14,30,60,100,180,300],
}
assert 1+114+sum(len(v) for v in LAD.values())==155, sum(len(v) for v in LAD.values())
P={
 'light':  dict(fwd=.35,fwe=.20,sess=1.1,mins=[(20,.3),(25,.5),(30,.2)],brk=.18,mon=(20,.35),wd=(30,.35),sleep=.45),
 'typical':dict(fwd=.85,fwe=.60,sess=1.6,mins=[(25,.35),(45,.3),(50,.2),(60,.15)],brk=.12,mon=(45,.65),wd=(45,.65),sleep=.60),
 'heavy':  dict(fwd=.92,fwe=.80,sess=3.5,mins=[(25,.15),(45,.25),(50,.3),(60,.2),(90,.1)],brk=.08,mon=(60,.80),wd=(60,.80),sleep=.70),
}
CAP=360
def pois(lam):
    import math
    L=math.exp(-lam);k=0;p=1
    while True:
        p*=random.random()
        if p<L: return k
        k+=1
def wchoice(pairs):
    r=random.random();a=0
    for v,w in pairs:
        a+=w
        if r<=a: return v
    return pairs[-1][0]
def run(prof, days=730, streak_rule='rest', seed=None, cap=CAP):
    p=P[prof]
    mins=0; sess=0; streak=0; best=0; bank=1; counted_since=0
    morn=0; bed=0; sleep=0
    out={}
    away=False; paused=False
    capped_days=0
    for d in range(days):
        if d%7==0:
            away = random.random()<0.05 and d>14
            paused = away and random.random()<0.5
        wk = (d%7) in (5,6)
        mult = 1.15 if d<14 else 1.0
        if away: mult*=0.15
        pf = (p['fwe'] if wk else p['fwd'])*mult
        dm=0; finished=0
        nsess=0
        if d==0:
            nsess = 1 if random.random()<min(1,pf+0.1) else 0
        elif random.random()<min(pf,0.99):
            nsess=max(1,pois(p['sess']))
        for _ in range(nsess):
            m=wchoice(p['mins'])
            if random.random()<p['brk']:
                dm+=m*random.uniform(.2,.9)
            else:
                dm+=m; 
                if m>=10: finished+=1
        # morning (not on install day)
        if d>0:
            mm,mp=p['mon']
            if random.random()<min(mp*mult,0.98):
                dm+=mm; morn+=1
            elif random.random()<0.3: dm+=mm*random.uniform(.1,.6)
        wm,wp=p['wd']
        if random.random()<min(wp*mult,0.98):
            dm+=wm; bed+=1
            # sleep counted next morning; treat same day
        elif random.random()<0.3: dm+=wm*random.uniform(.1,.6)
        if random.random()<p['sleep']*(1 if not away else .5): sleep+=1
        if dm>cap: capped_days+=1; dm=cap
        mins+=dm; sess+=finished
        # streak
        if finished>0:
            streak+=1; counted_since+=1
            if streak_rule=='rest' and counted_since>=7:
                bank=min(2,bank+1); counted_since=0
        else:
            if streak_rule=='rest' and paused:
                pass
            elif streak_rule=='rest' and bank>0 and d>0:
                bank-=1
            elif d==0: pass
            else:
                streak=0; counted_since=0
                if streak_rule=='rest': bank=max(bank,1) if False else bank
        best=max(best,streak)
        h=mins/60
        cnt={'first':1,
             'hours':sum(1 for t in HOURS if h>=t),
             'streak':sum(1 for t in LAD['streak'] if best>=t),
             'sessions':sum(1 for t in LAD['sessions'] if sess>=t),
             'mornings':sum(1 for t in LAD['mornings'] if morn>=t),
             'bedtime':sum(1 for t in LAD['bedtime'] if bed>=t),
             'sleep':sum(1 for t in LAD['sleep'] if sleep>=t)}
        out[d+1]=dict(cnt, hours_saved=h, best=best, sess=sess, capped=capped_days)
    return out
if __name__=='__main__':
    R=300
    days_of_interest=[1,7,30,90,180,365,730]
    res={}
    for prof in P:
        runs=[run(prof) for _ in range(R)]
        res[prof]={}
        for d in days_of_interest:
            tot=[sum(v for k,v in r[d].items() if k in ('first','hours','streak','sessions','mornings','bedtime','sleep')) for r in runs]
            tot_nosleep=[t-r[d]['sleep'] for t,r in zip(tot,runs)]
            hrs=[r[d]['hours'] for r in runs]
            hs=[r[d]['hours_saved'] for r in runs]
            sec=[sum(r[d][k] for k in ('streak','sessions','mornings','bedtime','sleep')) for r in runs]
            best=[r[d]['best'] for r in runs]
            q=lambda a,pct: sorted(a)[int(pct*(len(a)-1))]
            res[prof][d]=dict(total_med=st.median(tot),total_p10=q(tot,.1),total_p90=q(tot,.9),nosleep_med=st.median(tot_nosleep),
                hours_leaves_med=st.median(hrs),sec_med=st.median(sec),hours_saved_med=round(st.median(hs),1),best_streak_med=st.median(best),best_p90=q(best,.9),
                by={k:st.median([r[d][k] for r in runs]) for k in ('streak','sessions','mornings','bedtime','sleep')})
        res[prof]['capped_days_y1']=st.median([r[365]['capped'] for r in runs])
        # top rung days
        def first_day(r,cond):
            for dd in range(1,731):
                if cond(r[dd]): return dd
            return None
        for label,cond in [('100h',lambda x:x['hours_saved']>=100),('500h',lambda x:x['hours_saved']>=500),('1000h',lambda x:x['hours_saved']>=1000),('2000h',lambda x:x['hours_saved']>=2000),('streak100',lambda x:x['best']>=100),('streak365',lambda x:x['best']>=365),('streak30',lambda x:x['best']>=30)]:
            fd=[first_day(r,cond) for r in runs]
            reached=[f for f in fd if f]
            res[prof][label]=dict(share_by_730=round(len(reached)/R,2), median_day=(st.median(reached) if reached else None))
    print(json.dumps(res,indent=1))
