/* Shared studio engine for all channel templates.
   A channel page calls Studio.mount(config) where config = {
     channel, title, sub, accent, note, sample,
     controls: [{key, label, options:[[value,label],...]}],   // top-level data fields with a dropdown
     hooks:    [{q, q_hi?, options?}],                          // comment-question bank
     guide:    [[field, boldText, rest], ...],
     posts(d): [{id, label, slides:[{name, html, size:"post"|"story"}], caption}]
   } */
(function(){
const esc=s=>String(s??"").replace(/[&<>"]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"}[c]));
const hl=s=>esc(s).replace(/\*(.+?)\*/g,"<em>$1</em>");
const pad=(n,w=2)=>String(n).padStart(w,"0");
const initials=n=>String(n||"?").split(/\s+/).filter(Boolean).map(w=>w[0]).join("").slice(0,2).toUpperCase();
const clean=s=>String(s??"").replace(/\*/g,"");

const ICON={
  comment:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"><path d="M20.5 11.5a8.5 8.5 0 0 1-12.4 7.6L3.5 20.5l1.4-4.4A8.5 8.5 0 1 1 20.5 11.5z"/></svg>',
  follow:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><circle cx="9.5" cy="8" r="4"/><path d="M2.5 20.5a7 7 0 0 1 14 0"/><path d="M19 8v6M16 11h6"/></svg>',
  save:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"><path d="M6 3.5h12v17l-6-4.5-6 4.5z"/></svg>',
  send:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"><path d="M21 3 10 14"/><path d="M21 3l-7 18-4-7-7-4z"/></svg>',
  heart:'<svg viewBox="0 0 24 24"><path fill="currentColor" d="M12 21s-7.5-4.6-9.6-9.2C.9 8.4 3 4.5 6.8 4.5c2.1 0 3.6 1.2 5.2 3.1 1.6-1.9 3.1-3.1 5.2-3.1 3.8 0 5.9 3.9 4.4 7.3C19.5 16.4 12 21 12 21z"/></svg>',
  play:'<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="11" fill="currentColor" opacity=".18"/><path fill="currentColor" d="M9.5 7.5v9l7-4.5z"/></svg>'
};

/* Comment & Follow slide. o = {question, question_hi, options, followLine, chip, placeholder, size, cls} */
function ctaSlide(d,o){
  const story=o.size==="story";
  const opts=(o.options||[]).slice(0,5);
  return `<section class="art cta-slide ${o.cls||""}${story?" story":""}">
    <div class="cta-top"><span>${esc(d.handle)}</span><span class="cta-chip">${esc(o.chip||"Your turn")}</span></div>
    <div class="cta-ic">${ICON.comment}</div>
    <h2 class="cta-q fit" data-max="${story?110:96}" data-min="48"><span>${hl(o.question||"What do you think?")}${o.question_hi?`<small lang="hi">${hl(o.question_hi)}</small>`:""}</span></h2>
    ${opts.length?`<div class="cta-opts">${opts.map((x,i)=>`<span><b>${o.numbered?pad(i+1):String.fromCharCode(65+i)}</b>${esc(x)}</span>`).join("")}</div>`:""}
    <div class="cta-box"><i></i><span>${esc(o.placeholder||"Drop your answer in the comments…")}</span><em>Post</em></div>
    <div class="cta-follow"><div class="cta-btn">Follow</div><p>${esc(o.followLine||"Follow "+d.handle+" so you don't miss the next one")}</p></div>
    <div class="cta-row"><span>${ICON.follow} Follow</span><span>${ICON.save} Save</span><span>${ICON.send} Share</span></div>
  </section>`;
}

function fit(root){
  root.querySelectorAll(".fit").forEach(el=>{
    const max=+el.dataset.max||60,min=+el.dataset.min||20,w=el.dataset.axis==="w";
    let s=max; el.style.fontSize=s+"px";
    const over=()=>w?el.scrollWidth>el.clientWidth+1:el.scrollHeight>el.clientHeight+1;
    while(over()&&s>min){s-=2;el.style.fontSize=s+"px";}
  });
}

let cfg, current, posts=[], capIdx=0, els={};
function scale(){document.querySelectorAll(".frame").forEach(f=>{const a=f.firstElementChild;if(a)a.style.setProperty("--k",f.clientWidth/1080);});}

async function render(d){
  current=d; posts=cfg.posts(d)||[];
  els.posts.innerHTML=posts.map((p,pi)=>`<div class="st-post">
    <header class="chrome"><b>${esc(p.label||("Post "+(pi+1)))}</b><button data-cap="${pi}">Show caption</button></header>
    <div class="st-row">${p.slides.map((s,si)=>`<div class="st-cell"><span class="chrome">${pad(si+1)} · ${esc(s.name)}</span>
      <div class="frame" data-size="${s.size||"post"}" data-file="${esc((p.id||pad(pi+1))+"-"+pad(si+1)+"-"+s.name)}">${s.html}</div></div>`).join("")}</div>
  </div>`).join("");
  scale();
  try{await document.fonts.ready;}catch(e){}
  fit(els.posts);
  showCap(Math.min(capIdx,Math.max(0,posts.length-1)));
}
function showCap(i){capIdx=i;const p=posts[i];els.cap.textContent=p?p.caption:"";els.capT.textContent="Caption · "+(p?(p.label||"Post "+(i+1)):"");}

function setData(d){els.ta.value=JSON.stringify(d,null,2);syncControls(d);render(d);}
function syncControls(d){(cfg.controls||[]).forEach(c=>{const s=document.getElementById("ctl-"+c.key);if(s&&d[c.key]!=null)s.value=d[c.key];});}
function edit(fn){try{const d=JSON.parse(els.ta.value);fn(d);setData(d);}catch(e){}}

function mount(c){
  cfg=c;
  if(c.accent)document.documentElement.style.setProperty("--accent",c.accent);
  const app=document.getElementById("app");
  app.innerHTML=`<div class="st-wrap">
    <div class="st-top chrome"><div><h1><small>${esc(c.channel)}</small>${esc(c.title)}</h1><p class="st-sub">${esc(c.sub||"")}</p></div>
      <div class="st-controls">${(c.controls||[]).map(k=>`<label class="st-ctl" for="ctl-${k.key}">${esc(k.label)}<select id="ctl-${k.key}">${k.options.map(o=>`<option value="${esc(o[0])}">${esc(o[1])}</option>`).join("")}</select></label>`).join("")}
      <button id="st-hook" class="primary" type="button">New comment hook</button></div></div>
    <div class="st-main">
      <div class="st-panel chrome"><h2 class="st-h">Post data</h2><p class="st-note">${esc(c.note||"")}</p>
        <textarea id="st-json" spellcheck="false" aria-label="Post data as JSON"></textarea><div id="st-status" class="st-status" role="status">Valid JSON</div></div>
      <div class="st-panel"><h2 class="st-h chrome">Preview</h2><div id="st-posts" class="st-posts"></div></div>
    </div>
    <div class="st-panel chrome"><div style="display:flex;justify-content:space-between;gap:12px;flex-wrap:wrap;align-items:center"><h2 class="st-h" id="st-capT">Caption</h2><button id="st-copy" class="primary" type="button">Copy caption</button></div><pre id="st-cap" class="st-caption"></pre></div>
    <div class="st-panel chrome"><h2 class="st-h">Comment hooks · click one to use it on every post</h2><div id="st-hooks" class="st-hooks"></div></div>
    <div class="st-panel chrome"><h2 class="st-h">Field guide</h2><ul class="st-guide">${(c.guide||[]).map(g=>`<li><code>${esc(g[0])}</code> <b>${esc(g[1])}</b> ${esc(g[2]||"")}</li>`).join("")}</ul></div>
  </div>`;
  els={ta:document.getElementById("st-json"),st:document.getElementById("st-status"),posts:document.getElementById("st-posts"),cap:document.getElementById("st-cap"),capT:document.getElementById("st-capT")};
  document.getElementById("st-hooks").innerHTML=(c.hooks||[]).map((h,i)=>`<button type="button" data-hook="${i}">${esc(clean(h.q))}</button>`).join("");
  let t;
  els.ta.addEventListener("input",()=>{clearTimeout(t);t=setTimeout(()=>{try{const d=JSON.parse(els.ta.value);syncControls(d);render(d);els.st.textContent="Valid JSON";els.st.className="st-status";}catch(e){els.st.textContent="The JSON has an error: "+e.message+". The preview shows the last valid version.";els.st.className="st-status bad";}},250);});
  (c.controls||[]).forEach(k=>document.getElementById("ctl-"+k.key).addEventListener("change",e=>edit(d=>{d[k.key]=e.target.value;(d[c.itemsKey]||[]).forEach(x=>{if(k.perItem)delete x[k.key];});})));
  const useHook=h=>edit(d=>{d.hook={q:h.q};if(h.q_hi)d.hook.q_hi=h.q_hi;if(h.options)d.hook.options=h.options;(d[c.itemsKey]||[]).forEach(x=>delete x.hook);});
  document.getElementById("st-hook").addEventListener("click",()=>{const hs=c.hooks||[];if(hs.length)useHook(hs[Math.floor(Math.random()*hs.length)]);});
  document.getElementById("st-hooks").addEventListener("click",e=>{const b=e.target.closest("[data-hook]");if(b)useHook(c.hooks[+b.dataset.hook]);});
  els.posts.addEventListener("click",e=>{const b=e.target.closest("[data-cap]");if(b)showCap(+b.dataset.cap);});
  document.getElementById("st-copy").addEventListener("click",e=>{const b=e.currentTarget;navigator.clipboard.writeText(els.cap.textContent).then(()=>{b.textContent="Copied";setTimeout(()=>b.textContent="Copy caption",1500);}).catch(()=>{const r=document.createRange();r.selectNodeContents(els.cap);const s=getSelection();s.removeAllRanges();s.addRange(r);b.textContent="Press Ctrl/Cmd+C";});});
  new ResizeObserver(scale).observe(els.posts);
  setData(c.sample);
}

/* Hook text for a post: item.hook overrides data.hook overrides channel default */
function hookOf(d,item,fallback){return (item&&item.hook)||d.hook||fallback||{q:"What do you think?"};}
/* Caption ending shared by every channel: the comment question, its options, and a
   plain "comment below" call (skipped when the question already says comment). */
function captionHook(h){
  const ask=/comment/i.test(clean(h.q)+" "+clean(h.q_hi||""))?"":"\n👇 Drop your answer in the comments";
  return `💬 ${clean(h.q)}${h.q_hi?"\n💬 "+clean(h.q_hi):""}${h.options&&h.options.length?"\n"+h.options.map((o,i)=>`${h.numbered?pad(i+1):String.fromCharCode(65+i)}) ${o}`).join("   "):""}${ask}`;
}

window.Studio={mount,render:d=>render(d),captions:()=>posts.map(p=>({id:p.id,text:p.caption})),ctaSlide,hookOf,captionHook,esc,hl,pad,initials,clean,ICON,get data(){return current;}};
})();
