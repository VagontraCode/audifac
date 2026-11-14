import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// A song guests can find, as the page shows it.
typedef GuestSong = ({int id, String title, String artist});

/// A guest's request.
class GuestRequest {
  GuestRequest({required this.songId, required this.from, required this.at});

  final int songId;

  /// Names guests typed (one request per song, names gathered).
  final List<String> from;
  final DateTime at;
}

/// Soirée guest requests: guests on the same Wi-Fi open a page (QR code on
/// the host's phone), search the library and ask for songs. The host
/// accepts or declines each one.
///
/// Like Wi-Fi transfer, the address carries a random token, and the server
/// runs only while the host has requests switched on.
class GuestServer {
  GuestServer({required this.search, required this.page});

  /// Up to ~25 songs matching a query.
  final List<GuestSong> Function(String query) search;
  final String page;

  HttpServer? _server;
  late String token;
  final _requests = StreamController<GuestRequest>.broadcast();

  /// Per guest name, in a short window: a guest can't flood the host.
  final _recent = <String, List<DateTime>>{};
  static const perGuestPerMinute = 5;

  Stream<GuestRequest> get requests => _requests.stream;
  int? get port => _server?.port;

  Future<void> start({int port = 0, InternetAddress? address}) async {
    if (_server != null) return;
    final random = Random.secure();
    const alphabet = 'abcdefghijkmnpqrstuvwxyz23456789';
    token = List.generate(6, (_) => alphabet[random.nextInt(alphabet.length)]).join();
    _server = await HttpServer.bind(address ?? InternetAddress.anyIPv4, port);
    _server!.listen(_handle, onError: (_) {});
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> dispose() async {
    await stop();
    await _requests.close();
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      final segments = request.uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segments.isEmpty || segments.first != token) {
        response.statusCode = HttpStatus.notFound;
        return await response.close();
      }
      final action = segments.length > 1 ? segments[1] : '';
      if (request.method == 'GET' && action.isEmpty) {
        response.headers.contentType = ContentType.html;
        response.headers.set('Cache-Control', 'no-store');
        response.write(page);
      } else if (request.method == 'GET' && action == 'search') {
        final q = (request.uri.queryParameters['q'] ?? '').trim();
        final found = q.length < 2 ? const <GuestSong>[] : search(q).take(25);
        response.headers.contentType = ContentType.json;
        response.write(jsonEncode([for (final s in found) {'id': s.id, 'title': s.title, 'artist': s.artist}]));
      } else if (request.method == 'POST' && action == 'request') {
        // A request is a few bytes; anything big or unannounced is refused.
        if (request.contentLength < 0 || request.contentLength > 2000) throw const FormatException('size');
        final body = await utf8.decoder.bind(request).join().timeout(const Duration(seconds: 5));
        final j = jsonDecode(body) as Map<String, dynamic>;
        final id = (j['id'] as num).toInt();
        var from = (j['from'] as String? ?? '').trim();
        if (from.length > 40) from = from.substring(0, 40);
        if (!_allow(from)) {
          response.statusCode = HttpStatus.tooManyRequests;
        } else {
          _requests.add(GuestRequest(songId: id, from: [if (from.isNotEmpty) from], at: DateTime.now()));
          response.headers.contentType = ContentType.json;
          response.write('{"ok":true}');
        }
      } else {
        response.statusCode = HttpStatus.notFound;
      }
      await response.close();
    } catch (_) {
      try {
        response.statusCode = HttpStatus.badRequest;
        await response.close();
      } catch (_) {}
    }
  }

  bool _allow(String from) {
    final now = DateTime.now();
    final times = (_recent[from] ??= [])..removeWhere((t) => now.difference(t) > const Duration(minutes: 1));
    if (times.length >= perGuestPerMinute) return false;
    times.add(now);
    return true;
  }
}

/// Texts of the guest page, in the host's language.
typedef GuestPageText = ({
  String title,
  String name,
  String search,
  String request,
  String sent,
  String tooMany,
  String failed,
  String nothing,
});

/// The page guests see: their name (remembered), a search box, results with
/// a "Request" button. Self-contained (no internet needed).
String guestPage(GuestPageText t) {
  String esc(String s) => const HtmlEscape().convert(s);
  final texts = jsonEncode({'request': t.request, 'sent': t.sent, 'tooMany': t.tooMany, 'failed': t.failed, 'nothing': t.nothing});
  return '''<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${esc(t.title)}</title>
<style>
:root{--bg:#f5f5f7;--card:#fff;--ink:#1c1c1e;--muted:#6e6e73;--line:#e5e5ea;--ok:#00805a}
@media (prefers-color-scheme:dark){:root{--bg:#0b0b0d;--card:#1a1a1d;--ink:#f5f5f7;--muted:#98989f;--line:#2c2c30;--ok:#4cd9a0}}
*{box-sizing:border-box}body{margin:0;font:16px/1.4 system-ui,-apple-system,Segoe UI,Roboto,sans-serif;background:var(--bg);color:var(--ink)}
main{max-width:560px;margin:0 auto;padding:24px 16px}h1{font-size:26px;margin:0 0 16px}
input{width:100%;font:inherit;padding:12px 14px;border-radius:14px;border:1px solid var(--line);background:var(--card);color:var(--ink);margin-bottom:10px}
ul{list-style:none;padding:0;margin:8px 0 0}li{display:flex;align-items:center;gap:12px;background:var(--card);border-radius:14px;padding:10px 12px;margin-bottom:8px}
.t{flex:1;min-width:0}.t b,.t span{display:block;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.t span{color:var(--muted);font-size:14px}
button{font:inherit;font-weight:700;border:0;border-radius:999px;padding:8px 16px;background:var(--ink);color:var(--bg);cursor:pointer;flex:none}
button:disabled{background:transparent;color:var(--ok)}p.m{color:var(--muted)}
</style></head><body><main>
<h1>${esc(t.title)}</h1>
<input id="name" maxlength="40" placeholder="${esc(t.name)}" autocomplete="nickname">
<input id="q" type="search" placeholder="${esc(t.search)}" autocomplete="off">
<ul id="list"></ul>
</main><script>
const T=$texts,name=document.getElementById('name'),q=document.getElementById('q'),list=document.getElementById('list');
try{name.value=localStorage.getItem('name')||''}catch(e){}
name.oninput=()=>{try{localStorage.setItem('name',name.value)}catch(e){}};
let timer;q.oninput=()=>{clearTimeout(timer);timer=setTimeout(find,250)};
async function find(){const v=q.value.trim();if(v.length<2){list.innerHTML='';return}
try{const r=await fetch('search?q='+encodeURIComponent(v));show(await r.json())}catch(e){list.innerHTML='<p class="m">'+T.failed+'</p>'}}
function show(songs){list.innerHTML='';if(!songs.length){list.innerHTML='<p class="m">'+T.nothing+'</p>';return}
for(const s of songs){const li=document.createElement('li');li.innerHTML='<div class="t"><b></b><span></span></div><button type="button"></button>';
li.querySelector('b').textContent=s.title;li.querySelector('span').textContent=s.artist;const b=li.querySelector('button');b.textContent=T.request;
b.onclick=async()=>{b.disabled=true;try{const r=await fetch('request',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({id:s.id,from:name.value})});
b.textContent=r.ok?T.sent:(r.status===429?T.tooMany:T.failed);if(!r.ok)setTimeout(()=>{b.disabled=false;b.textContent=T.request},3000)}catch(e){b.textContent=T.failed;b.disabled=false}};list.append(li)}}
</script></body></html>''';
}
