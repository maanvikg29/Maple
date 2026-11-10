# Research pacing model (2026-10-11): modelled usage profiles behind the focus spec's ladder and tiers; not used at build time.
import random, statistics as st, json, math
from pacing_sim import P, pois, wchoice
HOURS=[1,2,3,5,7,10,13,16,20,24,28,32,36,40,45,50]+list(range(55,101,5))+[110,120,130,140,150,160,168,180,190,200]+[210,220,230,240,250]+list(range(265,401,15))+list(range(420,721,20))+[740,760,780,800]+list(range(825,1501,25))+list(range(1530,1801,30))+[1840,1880,1920,1960,2000]
LAD={'streak':[3,7,14,30,50,75,100,150,250,365],
     'sessions':[1,10,25,50,100,250,500,1000],
     'mornings':[1,7,25,50,100,200,365],
     'bedtime':[1,7,25,50,100,200,365],
     'sleep':[3,14,30,60,100,175,250,365]}
assert len(HOURS)==114 and 1+114+sum(map(len,LAD.values()))==155
CAP=360
def run(prof,days=1095,cap=CAP,health=True):
    p=P[prof]; mins=0; sess=0; s=0; best=0; misses=0; morn=0; bed=0; sleep=0; capped=0
    rows=[]; unlock_days=[0]  # first leaf at onboarding day 0
    have=set(['first'])
    for d in range(days):
        if d%7==0:
            away=random.random()<0.05 and d>14
            paused=away and random.random()<0.5
            misses=0
        wk=(d%7) in (5,6)
        mult=(1.15 if d<14 else 1.0)*(0.15 if away else 1)
        pf=(p['fwe'] if wk else p['fwd'])*mult
        dm=0; fin=0
        n=0
        if d==0: n=1 if random.random()<min(1,pf+.1) else 0
        elif random.random()<min(pf,.99): n=max(1,pois(p['sess']))
        for _ in range(n):
            m=wchoice(p['mins'])
            if random.random()<p['brk']: dm+=m*random.uniform(.2,.9)
            else: dm+=m; fin+=1
        if d>0:
            mm,mp=p['mon']
            if random.random()<min(mp*mult,.98): dm+=mm; morn+=1
            elif random.random()<.3: dm+=mm*random.uniform(.1,.6)
        wm,wp=p['wd']
        if random.random()<min(wp*mult,.98): dm+=wm; bed+=1
        elif random.random()<.3: dm+=wm*random.uniform(.1,.6)
        if health and d>0 and random.random()<p['sleep']*(1 if not away else .5): sleep+=1
        if dm>cap: capped+=1; dm=cap
        mins+=dm; sess+=fin
        # streak: calendar days, up to 2 rest days per calendar week, Away pauses (no add, no break)
        if paused and not fin: pass
        elif fin: s+=1
        else:
            misses+=1
            if d==0: pass
            elif misses>2: s=0
            else: s+=1 if s>0 else 0
        best=max(best,s)
        h=mins/60
        c={'hours':sum(t<=h for t in HOURS),'streak':sum(t<=best for t in LAD['streak']),'sessions':sum(t<=sess for t in LAD['sessions']),
           'mornings':sum(t<=morn for t in LAD['mornings']),'bedtime':sum(t<=bed for t in LAD['bedtime']),'sleep':sum(t<=sleep for t in LAD['sleep'])}
        c['total']=1+sum(c.values()); c['h']=h; c['best']=best
        rows.append(c)
    return rows,capped
if __name__=='__main__':
    random.seed(7)
    R=400; out={}
    for prof in P:
        runs=[run(prof) for _ in range(R)]
        O={}
        for d in (1,3,7,14,30,90,180,365,730,1095):
            tot=sorted(r[d-1]['total'] for r,_ in runs)
            q=lambda a,x:a[int(x*(len(a)-1))]
            O[d]={'med':st.median(tot),'p10':q(tot,.1),'p90':q(tot,.9),
                  'hours_leaves':st.median(r[d-1]['hours'] for r,_ in runs),
                  'sec':{k:st.median(r[d-1][k] for r,_ in runs) for k in LAD},
                  'h':round(st.median(r[d-1]['h'] for r,_ in runs)),'best':st.median(r[d-1]['best'] for r,_ in runs)}
        O['capped_days_y1']=st.median(c for _,c in runs)
        # cadence: mean days between leaves in windows
        cad={}
        for a,b in ((0,7),(7,30),(30,90),(90,365),(365,730),(730,1095)):
            g=[(b-a)/max(1e-9,(r[b-1]['total']-(r[a-1]['total'] if a>0 else 0))) for r,_ in runs]
            cad[f'{a}-{b}']=round(st.median(g),1)
        O['days_per_leaf']=cad
        def fd(r,f):
            for i,x in enumerate(r):
                if f(x): return i+1
        for lab,f in (('500h',lambda x:x['h']>=500),('1000h',lambda x:x['h']>=1000),('2000h',lambda x:x['h']>=2000),('all155',lambda x:x['total']>=155),('streak100',lambda x:x['best']>=100),('streak365',lambda x:x['best']>=365)):
            v=[fd(r,f) for r,_ in runs]; got=[x for x in v if x]
            O[lab]={'share_by_3y':round(len(got)/R,2),'median_day':st.median(got) if got else None}
        out[prof]=O
    json.dump(out,open('out2.json','w'),indent=1)
    for prof,O in out.items():
        print('==',prof,'capped',O['capped_days_y1'],'days/leaf',O['days_per_leaf'])
        for d in (1,3,7,14,30,90,180,365,730,1095):
            x=O[d]; print(f"d{d}: {x['med']} ({x['p10']}-{x['p90']}) hours {x['hours_leaves']} h={x['h']} best={x['best']} sec={x['sec']}")
        for lab in ('500h','1000h','2000h','all155','streak100','streak365'): print(' ',lab,O[lab])
