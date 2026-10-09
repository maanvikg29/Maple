// Leaf generator used to draw every leaf in the Maple Leaf Atlas.
// Input: one entry from species.json. Output: SVG markup in a -100..100 box,
// petiole pointing down. Port this to a SwiftUI Shape if Maple should draw
// leaves natively instead of using the exported SVGs.
const AUTUMN = {R:["#b3312b","crimson"],S:["#d2462a","scarlet"],O:["#d9782b","orange"],Y:["#d1a020","gold"],G:["#3f6d3b","stays green"]};
let season = "autumn";
/* ---------- leaf geometry ---------- */
function hash(s){let h=2166136261;for(const c of s){h^=c.charCodeAt(0);h=Math.imul(h,16777619)}return (h>>>0)/4294967295}
function summerGreen(id){const t=hash(id);const hue=95+t*30, l=30+hash(id+"l")*10;return `hsl(${hue} 42% ${l}%)`}
function pol(a,r){return [Math.sin(a)*r,-Math.cos(a)*r]}
function qpts(p0,c,p1,n){const out=[];for(let i=1;i<=n;i++){const t=i/n,u=1-t;out.push([u*u*p0[0]+2*u*t*c[0]+t*t*p1[0],u*u*p0[1]+2*u*t*c[1]+t*t*p1[1]])}return out}
function cpts(p0,c1,c2,p1,n){const out=[];for(let i=1;i<=n;i++){const t=i/n,u=1-t;out.push([u*u*u*p0[0]+3*u*u*t*c1[0]+3*u*t*t*c2[0]+t*t*t*p1[0],u*u*u*p0[1]+3*u*u*t*c1[1]+3*u*t*t*c2[1]+t*t*t*p1[1]])}return out}

/* add teeth to an edge (array of points), teeth face away from 'centre' */
function serrate(pts,cx,cy,amp,double,from){
  const out=[];
  pts.forEach((p,i)=>{
    const t=i/(pts.length-1);
    if(i%2===1 && t>from && t<0.97){
      const dx=p[0]-cx, dy=p[1]-cy, d=Math.hypot(dx,dy)||1;
      const a=amp*(double&&(i%4===1)?1.8:1);
      out.push([p[0]+dx/d*a,p[1]+dy/d*a]);
    } else out.push(p);
  });
  return out;
}
function toPath(pts){return "M"+pts.map(p=>p[0].toFixed(1)+" "+p[1].toFixed(1)).join("L")+"Z"}

/* one simple blade from base (bx,by) pointing at angle a, length L, half-width w */
function blade(bx,by,a,L,w,margin,seed){
  const tip=[bx+Math.sin(a)*L, by-Math.cos(a)*L];
  const nx=Math.cos(a), ny=Math.sin(a); // perpendicular
  const along=(f)=>[bx+Math.sin(a)*L*f, by-Math.cos(a)*L*f];
  const b0=along(0.02);
  const sideL=[...cpts(b0,[along(.15)[0]-nx*w*1.1,along(.15)[1]-ny*w*1.1],[along(.7)[0]-nx*w*.9,along(.7)[1]-ny*w*.9],tip,26)];
  const sideR=[...cpts(tip,[along(.7)[0]+nx*w*.9,along(.7)[1]+ny*w*.9],[along(.15)[0]+nx*w*1.1,along(.15)[1]+ny*w*1.1],b0,26)];
  let L1=sideL, R1=sideR;
  if(margin){const c=along(.45);L1=serrate(sideL,c[0],c[1],margin===2?2.2:1.4,margin===2,0.12);R1=serrate(sideR,c[0],c[1],margin===2?2.2:1.4,margin===2,0.03)}
  return {d:toPath([b0,...L1,...R1]), veins:[[b0,tip]]};
}

function leafShapes(sp){
  const shapes=[], veins=[];
  const jit=hash(sp.id);
  if(sp.form==="palmate"){
    const n=sp.lobes, R=72;
    const span={3:1.25,5:1.95,7:2.3,9:2.55,11:2.7}[n]||2;
    const angles=[...Array(n)].map((_,i)=>n===1?0:-span+2*span*i/(n-1));
    const lens=angles.map(a=>R*(0.62+0.38*Math.pow(Math.cos(a*0.55),2))*(n>=7?0.98:1));
    const pts=[];
    const baseR=6;
    const gap=(2*span)/(n-1);
    const sinusR=(i)=>Math.min(lens[i],lens[i+1])*(1-sp.depth)*0.92+4;
    const start=pol(Math.PI*0.999,baseR*0.4);
    // edge before first lobe: from petiole notch out to first tip
    const firstOuter=pol(angles[0]-gap*0.55,Math.max(lens[0]*(1-sp.depth)*0.75,14));
    pts.push(start);
    let prev=firstOuter; pts.push(...qpts(start,pol(angles[0]-gap*0.7,lens[0]*0.35),firstOuter,8));
    for(let i=0;i<n;i++){
      const a=angles[i], L=lens[i], tip=pol(a,L);
      const w=gap*(0.32-0.18*sp.depth);
      const shL=pol(a-w,(prev?Math.hypot(...prev):L*.5)+(L-Math.hypot(...prev))*0.62);
      let edge=qpts(prev,shL,tip,18);
      const nextS = i<n-1 ? pol((a+angles[i+1])/2, sinusR(i)) : pol(a+gap*0.55,Math.max(L*(1-sp.depth)*0.75,14));
      const shR=pol(a+w,Math.hypot(...nextS)+(L-Math.hypot(...nextS))*0.62);
      let edge2=qpts(tip,shR,nextS,18);
      if(sp.margin){
        const c=pol(a,L*0.35), amp=sp.margin===2?2.6:1.7;
        edge=serrate(edge,c[0],c[1],amp,sp.margin===2,0.25);
        edge2=serrate(edge2,c[0],c[1],amp,sp.margin===2,0.0).map((p,j,arr)=>j/(arr.length-1)>0.78?qpts(tip,shR,nextS,18)[j]:p);
      }
      pts.push(...edge,...edge2);
      veins.push([[0,0],tip]);
      prev=nextS;
    }
    const end=pol(-Math.PI*0.999,baseR*0.4);
    pts.push(...qpts(prev,pol(angles[n-1]+gap*0.7,lens[n-1]*0.35),end,8));
    shapes.push(toPath(pts));
    return {shapes,veins,petiole:[[0,0],[2,30]],y:-10};
  }
  if(sp.form==="unlobed"){
    const L=118, w=sp.evergreen?24:34+jit*6;
    const b=blade(0,48,0,L,w,sp.margin,sp.id);
    // side veins
    for(let i=1;i<=5;i++){const y=48-L*0.15*i;veins.push([[0,y],[-w*0.7,y-14]],[[0,y],[w*0.7,y-14]])}
    return {shapes:[b.d],veins:[...b.veins,...veins],petiole:[[0,48],[2,74]],y:-6};
  }
  if(sp.form==="trifoliate"){
    const base=[0,30];
    const parts=[[0,84,26],[-1.05,62,20],[1.05,62,20]];
    parts.forEach(([a,L,w])=>{const b=blade(base[0]+Math.sin(a)*6,base[1]-Math.cos(a)*6,a,L,w,sp.margin,sp.id);shapes.push(b.d);veins.push(...b.veins)});
    return {shapes,veins,petiole:[[0,30],[2,72]],y:-8};
  }
  if(sp.form==="palmcompound"){
    const base=[0,34];
    [-1.35,-0.68,0,0.68,1.35].forEach((a,i)=>{const L=i===2?88:(i%4===0?62:78);const b=blade(base[0],base[1],a,L,11,sp.margin,sp.id);shapes.push(b.d);veins.push(...b.veins)});
    return {shapes,veins,petiole:[[0,34],[2,74]],y:-8};
  }
  if(sp.form==="pinnate"){
    const top=-78, bottom=50;
    veins.push([[0,bottom],[0,top+36]]);
    const t=blade(0,top+38,0,46,15,sp.margin,sp.id);shapes.push(t.d);veins.push(...t.veins);
    [[-14,1.25],[24,1.3]].forEach(([y,a])=>{
      [-1,1].forEach(s=>{const b=blade(0,y,s*a,48,14,sp.margin,sp.id);shapes.push(b.d);veins.push(...b.veins)});
    });
    return {shapes,veins,petiole:[[0,bottom-8],[2,80]],y:-4};
  }
}

function leafSVG(sp,size){
  const g=leafShapes(sp);
  const fill = season==="autumn" ? AUTUMN[sp.autumn][0] : summerGreen(sp.id);
  const rot = (hash(sp.id+"r")-0.5)*16;
  const veinStroke = `color-mix(in srgb, ${fill} 55%, #000)`;
  const pet = g.petiole;
  return `<svg viewBox="-100 -100 200 200" role="img" aria-label="Leaf of ${sp.name}"><g class="fit">
    <g transform="rotate(${rot.toFixed(1)}) translate(0 ${g.y})">
      <path d="M${pet[0][0]} ${pet[0][1]} Q${pet[0][0]+3} ${(pet[0][1]+pet[1][1])/2} ${pet[1][0]} ${pet[1][1]}" stroke="${veinStroke}" stroke-width="2.4" fill="none" stroke-linecap="round"/>
      ${g.shapes.map(d=>`<path d="${d}" fill="${fill}" stroke="${veinStroke}" stroke-width="0.8" stroke-linejoin="round"/>`).join("")}
      ${g.veins.map(([a,b])=>`<path d="M${a[0].toFixed(1)} ${a[1].toFixed(1)}L${(a[0]+(b[0]-a[0])*.86).toFixed(1)} ${(a[1]+(b[1]-a[1])*.86).toFixed(1)}" stroke="${veinStroke}" stroke-width="0.9" opacity=".55" fill="none"/>`).join("")}
    </g></g></svg>`;
}

