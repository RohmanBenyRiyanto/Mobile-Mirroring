/* Finds downloadable versions from two places in the repository:
   1. GitHub Releases that have a .dmg attached (preferred)
   2. .dmg files in the folder set in config.js
   and reads CHANGELOG.md for notes and dates. Nothing here is hard-coded per version.
   © 2026 Rohman Beny Riyanto */
(function () {
  'use strict';
  var C = window.BENZ_CONFIG;
  var API = 'https://api.github.com/repos/' + C.owner + '/' + C.repo;
  var RAW = 'https://raw.githubusercontent.com/' + C.owner + '/' + C.repo + '/';
  var WEB = 'https://github.com/' + C.owner + '/' + C.repo;
  var CACHE = 'bm.releases.v1', TTL = 5 * 60 * 1000;

  /* 404 means "this source is empty"; anything else means "could not check". */
  function get(url, as) {
    return fetch(url, as === 'json' ? { headers: { Accept: 'application/vnd.github+json' } } : undefined)
      .then(function (r) {
        if (r.status === 404) return null;
        if (!r.ok) throw new Error('HTTP ' + r.status);
        return as === 'json' ? r.json() : r.text();
      });
  }

  function safeUrl(u) { return typeof u === 'string' && /^https:\/\//.test(u) ? u : null; }
  function sha(s) { var m = /\b[a-f0-9]{64}\b/i.exec(s || ''); return m ? m[0].toLowerCase() : null; }

  function compare(a, b) {
    function parts(v) {
      var m = /^(\d+(?:\.\d+)*)(?:-(.+))?$/.exec(v);
      return m ? { n: m[1].split('.').map(Number), pre: m[2] || '' } : { n: [-1], pre: v };
    }
    var x = parts(a), y = parts(b);
    for (var i = 0; i < Math.max(x.n.length, y.n.length); i++) {
      var d = (x.n[i] || 0) - (y.n[i] || 0);
      if (d) return d;
    }
    if (!x.pre !== !y.pre) return x.pre ? -1 : 1;
    return x.pre.localeCompare(y.pre, undefined, { numeric: true });
  }

  function fromReleases(list) {
    return (list || []).filter(function (r) { return !r.draft; }).map(function (r) {
      var dmgs = (r.assets || []).filter(function (a) { return /\.dmg$/i.test(a.name); });
      var a = dmgs.filter(function (d) { return d.name === C.assetName; })[0] || dmgs[0];
      if (!a || !safeUrl(a.browser_download_url)) return null;
      return {
        version: String(r.tag_name || '').replace(/^v/i, ''), file: a.name, size: a.size,
        url: a.browser_download_url, sha256: /^sha256:/.test(a.digest || '') ? sha(a.digest) : null,
        date: (r.published_at || '').slice(0, 10), notes: r.body || '', pre: !!r.prerelease,
        page: safeUrl(r.html_url), source: 'release'
      };
    }).filter(Boolean);
  }

  function fromFolder(list) {
    if (!Array.isArray(list)) return Promise.resolve([]);
    var byName = {};
    list.forEach(function (f) { byName[f.name] = f; });
    return Promise.all(list.map(function (f) {
      var m = /(\d+\.\d+(?:\.\d+)?(?:-[0-9A-Za-z.]+)?)\.dmg$/i.exec(f.name);
      if (f.type !== 'file' || !m || !safeUrl(f.download_url)) return null;
      var item = {
        version: m[1], file: f.name, size: f.size, url: f.download_url, sha256: null,
        date: '', notes: '', pre: m[1].indexOf('-') > -1, page: null, source: 'folder'
      };
      var side = byName[f.name + '.sha256'];
      if (!side || !safeUrl(side.download_url)) return item;
      return get(side.download_url, 'text').then(function (t) { item.sha256 = sha(t); return item; })
        .catch(function () { return item; });
    })).then(function (all) { return all.filter(Boolean); });
  }

  /* "## [0.2.0] - 2026-12-01", "## 0.2.0", "## v0.2.0 (2026-12-01)" */
  function parseChangelog(text) {
    var out = [], cur = null;
    String(text || '').replace(/<!--[\s\S]*?-->/g, '').split(/\r?\n/).forEach(function (line) {
      var h = /^##\s+\[?v?([0-9][^\]\s(]*|Unreleased)\]?(.*)$/i.exec(line);
      if (h) {
        var d = /\d{4}-\d{2}-\d{2}/.exec(h[2]);
        cur = { version: h[1], date: d ? d[0] : '', body: [] };
        out.push(cur);
      } else if (/^##?\s/.test(line)) { cur = null; }
      else if (cur) cur.body.push(line);
    });
    out.forEach(function (e) { e.body = e.body.join('\n').trim(); });
    return out;
  }

  function load() {
    try {
      var hit = JSON.parse(sessionStorage.getItem(CACHE) || 'null');
      if (hit && Date.now() - hit.at < TTL) return Promise.resolve(hit.data);
    } catch (e) { /* storage may be unavailable */ }

    var failed = 0;
    function soft(p) { return p.catch(function () { failed++; return null; }); }

    return Promise.all([
      soft(get(API + '/releases?per_page=20', 'json')),
      soft(get(API + '/contents/' + C.folder.path + '?ref=' + encodeURIComponent(C.folder.branch), 'json')),
      get(RAW + 'refs/heads/' + C.changelog.branch + '/' + C.changelog.path, 'text').catch(function () { return null; })
    ]).then(function (res) {
      return fromFolder(res[1]).then(function (folder) {
        var seen = {}, versions = [];
        fromReleases(res[0]).concat(folder).forEach(function (v) {
          if (!seen[v.version]) { seen[v.version] = true; versions.push(v); }
        });
        versions.sort(function (a, b) { return compare(b.version, a.version); });
        var log = parseChangelog(res[2]);
        versions.forEach(function (v) {
          var e = log.filter(function (x) { return x.version === v.version; })[0];
          if (e) { v.date = v.date || e.date; v.notes = v.notes.trim() || e.body; }
        });
        var latest = versions.filter(function (v) { return !v.pre; })[0] || versions[0] || null;
        /* "empty" may only be claimed when both sources really answered. */
        var state = latest ? 'ready' : failed ? 'error' : 'empty';
        var data = { state: state, latest: latest, versions: versions, changelog: log };
        if (!failed) { try { sessionStorage.setItem(CACHE, JSON.stringify({ at: Date.now(), data: data })); } catch (e) {} }
        return data;
      });
    });
  }

  window.BenzReleases = { load: load, compare: compare, parseChangelog: parseChangelog, web: WEB };
})();
