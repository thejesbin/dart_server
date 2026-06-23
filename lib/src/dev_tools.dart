import 'dart:convert';
import 'dart:io';

import 'middleware.dart';
import 'response.dart';

/// Supplies the currently-registered routes to the dashboard.
typedef RoutesProvider = List<({String method, String pattern})> Function();

/// A single recorded HTTP exchange, shown in the dev dashboard.
class RequestRecord {
  /// Monotonic id for this request within the current process.
  final int id;

  /// When the request was received.
  final DateTime time;

  /// HTTP method, e.g. `GET`.
  final String method;

  /// Request path (no query string).
  final String path;

  /// Parsed query parameters.
  final Map<String, String> query;

  /// Request headers (lower-cased).
  final Map<String, String> requestHeaders;

  /// Captured request body (text, possibly truncated), or `null`.
  final String? requestBody;

  /// Response status code, or `null` if the request errored before one was set.
  int? statusCode;

  /// Wall-clock time to produce the response, in milliseconds.
  double? durationMs;

  /// Response body size in bytes.
  int? responseSize;

  /// Response `Content-Type` MIME, e.g. `application/json`.
  String? responseType;

  /// Captured response body (text, possibly truncated), or `null`.
  String? responseBody;

  /// String form of an error thrown while handling the request, or `null`.
  String? error;

  RequestRecord({
    required this.id,
    required this.time,
    required this.method,
    required this.path,
    required this.query,
    required this.requestHeaders,
    this.requestBody,
  });

  /// JSON form consumed by the dashboard front-end.
  Map<String, dynamic> toJson() => {
        'id': id,
        'time': time.toIso8601String(),
        'method': method,
        'path': path,
        'query': query,
        'status': statusCode,
        'durationMs': durationMs,
        'responseSize': responseSize,
        'responseType': responseType,
        'requestHeaders': requestHeaders,
        'requestBody': requestBody,
        'responseBody': responseBody,
        'error': error,
      };
}

/// In-memory collector behind the development dashboard.
///
/// Records the most recent requests (a bounded ring buffer), aggregate stats,
/// the route table and basic server info, and serves a self-contained HTML
/// dashboard plus a JSON snapshot. Created and wired up by
/// [DartServer.useDevTools]; you rarely construct this directly.
class DevTools {
  DevTools({
    required this.dashboardPath,
    this.maxRequests = 100,
    this.captureBodies = true,
    this.maxBodyCapture = 16 * 1024,
    RoutesProvider? routesProvider,
    int? Function()? portProvider,
  })  : _routesProvider = routesProvider,
        _portProvider = portProvider,
        startTime = DateTime.now();

  /// Base path the dashboard is mounted at (e.g. `/__dev`).
  final String dashboardPath;

  /// Maximum number of requests kept in the ring buffer.
  final int maxRequests;

  /// Whether request/response bodies are captured (text only, truncated).
  final bool captureBodies;

  /// Maximum captured body length in characters before truncation.
  final int maxBodyCapture;

  /// When the collector (≈ the server) started.
  final DateTime startTime;

  final RoutesProvider? _routesProvider;
  final int? Function()? _portProvider;

  final List<RequestRecord> _records = [];
  int _nextId = 1;
  int _total = 0;
  final Map<String, int> _byMethod = {};
  final Map<String, int> _byStatusClass = {
    '2xx': 0,
    '3xx': 0,
    '4xx': 0,
    '5xx': 0,
    'other': 0,
  };

  /// Middleware that records each request. Mounted outermost so it observes the
  /// final response (after all other middleware). Its own dashboard traffic is
  /// skipped to avoid noise.
  Middleware get middleware => (req, next) async {
        if (_isDashboardPath(req.path)) return next();

        final record = RequestRecord(
          id: _nextId++,
          time: DateTime.now(),
          method: req.method,
          path: req.path,
          query: Map.of(req.query),
          requestHeaders: Map.of(req.headers),
          requestBody: captureBodies ? _capture(req.body) : null,
        );
        final stopwatch = Stopwatch()..start();
        try {
          final res = await next();
          stopwatch.stop();
          _finish(record, stopwatch, res, null);
          return res;
        } catch (error) {
          stopwatch.stop();
          _finish(record, stopwatch, null, error);
          rethrow;
        }
      };

  /// Serves the HTML dashboard.
  Handler get dashboardHandler => (req) => Response.html(_renderHtml());

  /// Serves a JSON [snapshot].
  Handler get apiHandler => (req) => Response.json(snapshot());

  /// Clears recorded requests and aggregate counters.
  Handler get clearHandler => (req) {
        clear();
        return Response.json({'cleared': true});
      };

  bool _isDashboardPath(String path) =>
      path == dashboardPath || path.startsWith('$dashboardPath/');

  void _finish(
    RequestRecord record,
    Stopwatch stopwatch,
    Response? res,
    Object? error,
  ) {
    record.durationMs = stopwatch.elapsedMicroseconds / 1000.0;
    if (res != null) {
      record.statusCode = res.statusCode;
      record.responseSize = res.bodyBytes.length;
      record.responseType = res.contentType?.mimeType;
      if (captureBodies && _isTextual(res.contentType?.mimeType)) {
        record.responseBody =
            _capture(utf8.decode(res.bodyBytes, allowMalformed: true));
      }
    }
    if (error != null) record.error = error.toString();
    _add(record);
  }

  void _add(RequestRecord record) {
    _total++;
    _byMethod.update(record.method, (v) => v + 1, ifAbsent: () => 1);
    _byStatusClass.update(_statusClass(record.statusCode), (v) => v + 1,
        ifAbsent: () => 1);
    _records.add(record);
    while (_records.length > maxRequests) {
      _records.removeAt(0);
    }
  }

  /// Resets the buffer and counters.
  void clear() {
    _records.clear();
    _total = 0;
    _nextId = 1;
    _byMethod.clear();
    _byStatusClass.updateAll((_, __) => 0);
  }

  /// A point-in-time snapshot of everything the dashboard renders.
  Map<String, dynamic> snapshot() {
    final durations = _records
        .where((r) => r.durationMs != null)
        .map((r) => r.durationMs!)
        .toList()
      ..sort();
    double? avg, min, max, p95;
    if (durations.isNotEmpty) {
      min = durations.first;
      max = durations.last;
      avg = durations.reduce((a, b) => a + b) / durations.length;
      p95 = durations[((durations.length - 1) * 0.95).floor()];
    }

    final routes = (_routesProvider?.call() ?? [])
        .where((r) => !r.pattern.startsWith(dashboardPath))
        .map((r) => {'method': r.method, 'pattern': r.pattern})
        .toList();

    return {
      'server': {
        'status': 'running',
        'port': _portProvider?.call(),
        'pid': pid,
        'dartVersion': Platform.version,
        'startedAt': startTime.toIso8601String(),
        'uptimeSeconds': DateTime.now().difference(startTime).inSeconds,
      },
      'stats': {
        'total': _total,
        'byMethod': _byMethod,
        'byStatusClass': _byStatusClass,
        'timingMs': {'avg': avg, 'min': min, 'max': max, 'p95': p95},
        'inBuffer': _records.length,
        'capacity': maxRequests,
      },
      'routes': routes,
      // Newest first.
      'requests': _records.reversed.map((r) => r.toJson()).toList(),
    };
  }

  String? _capture(String text) {
    if (text.isEmpty) return null;
    if (text.length <= maxBodyCapture) return text;
    return '${text.substring(0, maxBodyCapture)}'
        '… (truncated, ${text.length} chars)';
  }

  static bool _isTextual(String? mime) {
    if (mime == null) return false;
    return mime.contains('json') ||
        mime.startsWith('text/') ||
        mime.contains('xml') ||
        mime.contains('javascript') ||
        mime.contains('urlencoded');
  }

  static String _statusClass(int? status) {
    if (status == null) return 'other';
    if (status >= 500) return '5xx';
    if (status >= 400) return '4xx';
    if (status >= 300) return '3xx';
    if (status >= 200) return '2xx';
    return 'other';
  }

  String _renderHtml() => _dashboardTemplate.replaceAll('__DEV_PATH__', dashboardPath);
}

/// Self-contained dashboard page. `__DEV_PATH__` is replaced with the mount
/// path at render time. Kept as a raw string so the embedded JS `${}`/`$` and
/// backticks pass through untouched.
const String _dashboardTemplate = r'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>dart_server · dev tools</title>
<style>
  :root{--bg:#0e1116;--panel:#161b22;--line:#262d36;--muted:#8b949e;--fg:#e6edf3;
    --s2:#2ea043;--s3:#1f6feb;--s4:#d29922;--s5:#f85149;--accent:#7c3aed}
  *{box-sizing:border-box}
  body{margin:0;font:13px/1.5 -apple-system,Segoe UI,Roboto,sans-serif;background:var(--bg);color:var(--fg)}
  header{display:flex;align-items:center;gap:16px;padding:12px 18px;border-bottom:1px solid var(--line);position:sticky;top:0;background:var(--bg);z-index:5}
  .brand{font-weight:700;font-size:15px;letter-spacing:.3px}
  .badge{background:var(--accent);color:#fff;font-size:10px;padding:2px 7px;border-radius:10px;margin-left:6px;vertical-align:middle;letter-spacing:1px}
  .meta{color:var(--muted);font-size:12px}
  .controls{margin-left:auto;display:flex;align-items:center;gap:10px}
  button{background:var(--panel);color:var(--fg);border:1px solid var(--line);border-radius:6px;padding:5px 11px;cursor:pointer;font-size:12px}
  button:hover{border-color:var(--accent)}
  label{color:var(--muted);font-size:12px;user-select:none}
  .cards{display:flex;flex-wrap:wrap;gap:10px;padding:14px 18px}
  .card{background:var(--panel);border:1px solid var(--line);border-radius:8px;padding:10px 14px;min-width:88px}
  .card .val{font-size:20px;font-weight:700}
  .card .lbl{color:var(--muted);font-size:11px;text-transform:uppercase;letter-spacing:.5px}
  .card.s2 .val{color:var(--s2)} .card.s4 .val{color:var(--s4)} .card.s5 .val{color:var(--s5)}
  main{display:grid;grid-template-columns:1fr 300px;gap:14px;padding:0 18px 24px}
  @media(max-width:880px){main{grid-template-columns:1fr}}
  .panel{background:var(--panel);border:1px solid var(--line);border-radius:8px;overflow:hidden}
  .panel h2{font-size:12px;text-transform:uppercase;letter-spacing:.5px;color:var(--muted);margin:0;padding:12px 14px;border-bottom:1px solid var(--line)}
  table{width:100%;border-collapse:collapse}
  th,td{text-align:left;padding:8px 12px;border-bottom:1px solid var(--line);white-space:nowrap}
  th{color:var(--muted);font-weight:600;font-size:11px;text-transform:uppercase}
  tbody tr{cursor:pointer} tbody tr:hover{background:#1c2230}
  td.path{white-space:normal;word-break:break-all;font-family:ui-monospace,Menlo,monospace}
  .m{font-weight:700;font-size:11px;padding:1px 6px;border-radius:4px;background:#21262d}
  .m-GET{color:#3fb950}.m-POST{color:#58a6ff}.m-PUT{color:#d29922}.m-DELETE{color:#f85149}.m-PATCH{color:#a371f7}
  .pill{font-weight:700;padding:1px 7px;border-radius:10px;font-size:11px;background:#21262d}
  .pill.s2{color:var(--s2)}.pill.s3{color:var(--s3)}.pill.s4{color:var(--s4)}.pill.s5{color:var(--s5)}.pill.err{color:var(--s5)}
  aside h2:not(:first-child){margin-top:0}
  #routes{list-style:none;margin:0;padding:8px 0;max-height:240px;overflow:auto}
  #routes li{padding:5px 14px;font-family:ui-monospace,Menlo,monospace;font-size:12px}
  dl{margin:0;padding:8px 14px;display:grid;grid-template-columns:auto 1fr;gap:4px 12px}
  dt{color:var(--muted)} dd{margin:0;text-align:right;font-family:ui-monospace,Menlo,monospace}
  .empty{padding:26px;text-align:center;color:var(--muted)}
  .detail{position:fixed;inset:0;background:rgba(0,0,0,.55);display:flex;justify-content:flex-end;z-index:20}
  .detail.hidden{display:none}
  .detail-card{background:var(--panel);width:min(560px,100%);height:100%;overflow:auto;padding:18px;border-left:1px solid var(--line)}
  .detail-card h3{margin:0 0 12px;font-size:14px;word-break:break-all}
  .detail-card h4{margin:16px 0 6px;font-size:11px;text-transform:uppercase;color:var(--muted)}
  .close{position:sticky;top:0;float:right;background:transparent;border:none;font-size:22px;color:var(--muted)}
  .kv div{display:flex;justify-content:space-between;gap:14px;padding:3px 0;border-bottom:1px solid var(--line);font-family:ui-monospace,Menlo,monospace;font-size:12px}
  .kv .k{color:var(--muted)} .kv .v{word-break:break-all;text-align:right}
  pre{background:#0b0e13;border:1px solid var(--line);border-radius:6px;padding:10px;overflow:auto;font-size:12px;white-space:pre-wrap;word-break:break-word}
  .err-box{background:rgba(248,81,73,.12);border:1px solid var(--s5);color:#ffb3ae;border-radius:6px;padding:10px;font-family:ui-monospace,Menlo,monospace;font-size:12px}
</style>
</head>
<body>
<header>
  <div class="brand">dart_server<span class="badge">DEV</span></div>
  <div class="meta" id="serverMeta"></div>
  <div class="controls">
    <label><input type="checkbox" id="autoRefresh" checked> auto-refresh</label>
    <button id="refreshBtn">Refresh</button>
    <button id="clearBtn">Clear</button>
  </div>
</header>
<section class="cards" id="cards"></section>
<main>
  <div class="panel">
    <h2>Requests</h2>
    <table>
      <thead><tr><th>#</th><th>Time</th><th>Method</th><th>Path</th><th>Status</th><th>Took</th><th>Size</th></tr></thead>
      <tbody id="reqBody"></tbody>
    </table>
    <div class="empty" id="reqEmpty" style="display:none">No requests yet — hit one of your routes.</div>
  </div>
  <aside class="panel">
    <h2>Routes</h2>
    <ul id="routes"></ul>
    <h2>Server</h2>
    <dl id="serverInfo"></dl>
  </aside>
</main>
<div id="detail" class="detail hidden"></div>
<script>
const API='__DEV_PATH__/api';
const $=s=>document.querySelector(s);
const esc=s=>String(s==null?'':s).replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
let data=null;
const sClass=s=>s==null?'err':s>=500?'s5':s>=400?'s4':s>=300?'s3':s>=200?'s2':'';
const fmtMs=v=>v==null?'–':(v<10?v.toFixed(1):Math.round(v))+'ms';
const fmtBytes=b=>b==null?'–':b<1024?b+'B':(b/1024).toFixed(1)+'KB';
const card=(l,v,c)=>`<div class="card ${c||''}"><div class="val">${esc(v)}</div><div class="lbl">${esc(l)}</div></div>`;
const tag=m=>`<span class="m m-${esc(m)}">${esc(m)}</span>`;
async function load(){try{const r=await fetch(API);data=await r.json();render();}catch(e){$('#serverMeta').textContent='server offline';}}
function render(){
  const st=data.stats,sv=data.server;
  $('#cards').innerHTML=[
    card('requests',st.total),
    card('in view',st.inBuffer+'/'+st.capacity),
    card('avg',fmtMs(st.timingMs.avg)),
    card('p95',fmtMs(st.timingMs.p95)),
    card('2xx',st.byStatusClass['2xx'],'s2'),
    card('4xx',st.byStatusClass['4xx'],'s4'),
    card('5xx',st.byStatusClass['5xx'],'s5'),
    card('uptime',sv.uptimeSeconds+'s')
  ].join('');
  $('#serverMeta').textContent='port '+(sv.port??'–')+' · pid '+sv.pid;
  const rows=data.requests;
  $('#reqEmpty').style.display=rows.length?'none':'block';
  $('#reqBody').innerHTML=rows.map(r=>`<tr data-id="${r.id}">
    <td>${r.id}</td><td>${new Date(r.time).toLocaleTimeString()}</td><td>${tag(r.method)}</td>
    <td class="path">${esc(r.path)}</td>
    <td><span class="pill ${sClass(r.status)}">${r.status??'ERR'}</span></td>
    <td>${fmtMs(r.durationMs)}</td><td>${fmtBytes(r.responseSize)}</td></tr>`).join('');
  document.querySelectorAll('#reqBody tr').forEach(tr=>tr.onclick=()=>detail(tr.dataset.id));
  $('#routes').innerHTML=data.routes.length?data.routes.map(r=>`<li>${tag(r.method)} ${esc(r.pattern)}</li>`).join(''):'<li class="empty">none</li>';
  $('#serverInfo').innerHTML=[['Status',sv.status],['Port',sv.port??'–'],['PID',sv.pid],
    ['Dart',(sv.dartVersion||'').split(' ')[0]],['Started',new Date(sv.startedAt).toLocaleTimeString()]]
    .map(([k,v])=>`<dt>${k}</dt><dd>${esc(v)}</dd>`).join('');
}
function detail(id){
  const r=data.requests.find(x=>String(x.id)===String(id));if(!r)return;
  const kv=o=>{const e=Object.entries(o||{});return e.length?e.map(([k,v])=>`<div><span class="k">${esc(k)}</span><span class="v">${esc(v)}</span></div>`).join(''):'<em>none</em>';};
  $('#detail').innerHTML=`<div class="detail-card">
    <button class="close" onclick="document.getElementById('detail').classList.add('hidden')">×</button>
    <h3>${tag(r.method)} ${esc(r.path)} <span class="pill ${sClass(r.status)}">${r.status??'ERR'}</span> <span style="color:var(--muted);font-weight:400">${fmtMs(r.durationMs)}</span></h3>
    ${r.error?`<div class="err-box">${esc(r.error)}</div>`:''}
    <h4>Query</h4><div class="kv">${kv(r.query)}</div>
    <h4>Request headers</h4><div class="kv">${kv(r.requestHeaders)}</div>
    ${r.requestBody?`<h4>Request body</h4><pre>${esc(r.requestBody)}</pre>`:''}
    ${r.responseBody?`<h4>Response body</h4><pre>${esc(r.responseBody)}</pre>`:''}
  </div>`;
  $('#detail').classList.remove('hidden');
}
$('#refreshBtn').onclick=load;
$('#clearBtn').onclick=async()=>{await fetch(API+'/clear',{method:'POST'});load();};
$('#detail').onclick=e=>{if(e.target.id==='detail')e.target.classList.add('hidden');};
setInterval(()=>{if($('#autoRefresh').checked)load();},2000);
load();
</script>
</body>
</html>''';
