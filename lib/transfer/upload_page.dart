import 'dart:convert';

/// Texts of the upload page, in the app's language.
typedef UploadPageText = ({
  String title,
  String drop,
  String choose,
  String done,
  String failed,
  String notAudio,
});

/// The page the computer's browser shows: drop files (or pick them), each is
/// sent with PUT to `./upload?name=…`, with progress. Self-contained: no
/// external scripts or fonts (works without internet).
String uploadPage(UploadPageText t) {
  String esc(String s) => const HtmlEscape().convert(s);
  final texts = jsonEncode({'done': t.done, 'failed': t.failed, 'notAudio': t.notAudio});
  return '''<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${esc(t.title)}</title>
<style>
:root{--bg:#f5f5f7;--card:#fff;--ink:#1c1c1e;--muted:#6e6e73;--line:#e5e5ea;--ok:#00805a;--bad:#d70015}
@media (prefers-color-scheme:dark){:root{--bg:#0b0b0d;--card:#1a1a1d;--ink:#f5f5f7;--muted:#98989f;--line:#2c2c30;--ok:#4cd9a0;--bad:#ff6961}}
*{box-sizing:border-box}body{margin:0;font:16px/1.4 system-ui,-apple-system,Segoe UI,Roboto,sans-serif;background:var(--bg);color:var(--ink)}
main{max-width:640px;margin:0 auto;padding:32px 16px}h1{font-size:28px;margin:0 0 20px}
#drop{border:2px dashed var(--line);border-radius:20px;background:var(--card);padding:48px 16px;text-align:center;cursor:pointer}
#drop.over{border-color:var(--ink)}#drop p{margin:0 0 12px;color:var(--muted)}
button{font:inherit;font-weight:700;border:0;border-radius:999px;padding:10px 20px;background:var(--ink);color:var(--bg);cursor:pointer}
ul{list-style:none;padding:0;margin:20px 0 0}li{background:var(--card);border-radius:14px;padding:12px 14px;margin-bottom:8px}
.name{font-weight:600;overflow-wrap:anywhere}.state{font-size:14px;color:var(--muted)}.ok{color:var(--ok)}.bad{color:var(--bad)}
progress{width:100%;height:6px;margin-top:6px;accent-color:var(--ink)}
</style></head><body><main>
<h1>${esc(t.title)}</h1>
<div id="drop" tabindex="0" role="button"><p>${esc(t.drop)}</p><button type="button">${esc(t.choose)}</button>
<input id="pick" type="file" multiple hidden></div>
<ul id="list"></ul>
</main><script>
const T=$texts;const drop=document.getElementById('drop'),pick=document.getElementById('pick'),list=document.getElementById('list');
const audio=/\\.(mp3|m4a|m4b|aac|flac|wav|ogg|oga|opus|aif|aiff|aifc|wma|ape|wv|tta|mka|dsf|dff|alac|mp2|ac3|amr|weba|lrc|cue)\$/i;
let queue=Promise.resolve();
drop.onclick=()=>pick.click();drop.onkeydown=e=>{if(e.key==='Enter'||e.key===' ')pick.click()};
pick.onchange=()=>{add(pick.files);pick.value=''};
drop.ondragover=e=>{e.preventDefault();drop.classList.add('over')};drop.ondragleave=()=>drop.classList.remove('over');
drop.ondrop=e=>{e.preventDefault();drop.classList.remove('over');add(e.dataTransfer.files)};
function add(files){for(const f of files){const li=document.createElement('li');
li.innerHTML='<div class="name"></div><div class="state"></div><progress max="1" value="0"></progress>';
li.querySelector('.name').textContent=f.name;list.prepend(li);
if(!audio.test(f.name)){done(li,false,T.notAudio);continue}
queue=queue.then(()=>send(f,li))}}
function done(li,ok,text){li.querySelector('progress').remove();const s=li.querySelector('.state');s.textContent=text;s.className='state '+(ok?'ok':'bad')}
function send(f,li){return new Promise(res=>{const x=new XMLHttpRequest();x.open('PUT','upload?name='+encodeURIComponent(f.name));
x.upload.onprogress=e=>{if(e.lengthComputable)li.querySelector('progress').value=e.loaded/e.total};
x.onload=()=>{done(li,x.status===200,x.status===200?T.done:T.failed);res()};x.onerror=()=>{done(li,false,T.failed);res()};x.send(f)})}
</script></body></html>''';
}
