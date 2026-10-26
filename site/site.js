// Optional: the site works without it. Opens the contents beside wide pages, lets the keyboard reach boxes that
// scroll, and searches page titles and headings on the docs index.
(function () {
  var toc = document.querySelector('details.toc');
  if (toc && window.matchMedia('(min-width: 75rem)').matches) toc.open = true;
  document.querySelectorAll('.table-wrap, pre').forEach(function (box) {
    if (box.scrollWidth > box.clientWidth + 1) {
      box.tabIndex = 0;
      box.setAttribute('role', 'region');
      box.setAttribute('aria-label', box.tagName === 'PRE' ? 'Code, scrolls sideways' : 'Table, scrolls sideways');
    }
  });
  var form = document.querySelector('form.search');
  if (!form || !window.fetch) return;
  var input = form.querySelector('input'), list = document.getElementById('search-results');
  var root = document.querySelector('[data-root]').getAttribute('data-root'), entries = null, loading = null;
  form.hidden = false;
  form.addEventListener('submit', function (e) { e.preventDefault(); });
  function show() {
    var words = input.value.toLowerCase().split(/\s+/).filter(Boolean);
    list.textContent = '';
    if (!words.length || !entries) return;
    var shown = 0;
    for (var i = 0; i < entries.length && shown < 40; i++) {
      var e = entries[i], text = (e[0] + ' ' + e[2]).toLowerCase();
      if (!words.every(function (w) { return text.indexOf(w) >= 0; })) continue;
      var li = document.createElement('li'), a = document.createElement('a');
      a.href = root + e[1];
      a.textContent = e[0];
      li.appendChild(a);
      if (e[2]) { var s = document.createElement('span'); s.textContent = ' in ' + e[2]; li.appendChild(s); }
      list.appendChild(li);
      shown++;
    }
    if (!shown) { var none = document.createElement('li'); none.textContent = 'Nothing found.'; list.appendChild(none); }
  }
  input.addEventListener('input', function () {
    if (entries) return show();
    if (loading) return;
    loading = fetch(root + 'static/search-index.json').then(function (r) { return r.json(); }).then(function (d) { entries = d; show(); });
  });
})();
