var title = "", user = "", ipv6 = "", pins = [], apps = [];

(function loadConfig() {
    fetch('index.json')
        .then(function(r) { return r.json(); })
        .then(function(data) {
            title = data.title || "";
            user = data.user || "";
            ipv6 = data.ipv6 || "";
            pins = data.pins || [];
            apps = data.apps || [];

            var hostname = window.location.hostname;
            function fixUrl(s) {
                if (!s) return "";
                try { var u = new URL(s); u.hostname = hostname; return u.toString(); }
                catch(e) { return s; }
            }
            apps.forEach(function(a) { a.url = fixUrl(a.url); a.purl = fixUrl(a.purl); });
            pins.forEach(function(p) { p.url = fixUrl(p.url); p.purl = fixUrl(p.purl); });

            initPage();
        })
        .catch(function() { initPage(); });
})();

function createAppIcon(item) {
    var div = document.createElement('div');
    div.className = "app";

    var span = document.createElement('span');
    var icon = document.createElement('div');
    icon.className = 'app-icon';
    icon.textContent = item.txt ? item.txt.charAt(0) : 'A';
    var strong = document.createElement('strong');
    strong.innerText = item.txt || "未命名";
    span.appendChild(icon);
    span.appendChild(strong);

    // 外网链接 (url) - 默认显示
    var aPublic = document.createElement('a');
    aPublic.className = 'link-public';
    aPublic.href = item.url || "about:blank";
    aPublic.target = "_self";
    aPublic.appendChild(span.cloneNode(true));

    // 内网链接 (purl) - 仅 #private 时显示
    var aPrivate = document.createElement('a');
    aPrivate.className = 'link-private';
    aPrivate.href = item.purl || item.url || "about:blank";
    aPrivate.target = "_self";
    aPrivate.appendChild(span.cloneNode(true));

    // Alt+Click 强制内网兜底
    [aPublic, aPrivate].forEach(function(a) {
        a.onclick = function(e) {
            if (e.altKey && item.purl) {
                e.preventDefault();
                e.ctrlKey ? window.open(item.purl) : (window.location.href = item.purl);
                return false;
            }
        };
    });

    div.appendChild(aPublic);
    div.appendChild(aPrivate);
    return div;
}

function applyMode() {
    var isPrivate = window.location.hash === '#private';
    document.title = title + (isPrivate ? "(内网)" : "(外网)");
    
    // 修正选择器：.title -> .left (匹配 css.txt 结构)
    var titleEl = document.querySelector("#main .topbar .left");
    if (titleEl) {
        titleEl.innerText = document.title;
        titleEl.style.cursor = "pointer";
    }

    if (isPrivate) {
        document.body.classList.add('private-mode');
    } else {
        document.body.classList.remove('private-mode');
    }
}

function initPage() {
    var body = document.querySelector("body");
    function resize() {
        if (body) {
            body.style.height = window.innerHeight + "px";
            body.style.width = window.innerWidth + "px";
        }
    }
    window.addEventListener('resize', resize);
    resize();

    var grid = document.querySelector("#main .content .grid");
    if (grid) {
        grid.innerHTML = '';
        apps.forEach(function(app) { grid.appendChild(createAppIcon(app)); });
    }

    var pinGrid = document.querySelector("#main .footerbar .grid");
    if (pinGrid) {
        pinGrid.innerHTML = '';
        pins.slice(0, 4).forEach(function(pin) { pinGrid.appendChild(createAppIcon(pin)); });
    }

    // ✅ 注入 CSS（核心切换逻辑）
    var styleId = 'nav-switch-style';
    if (!document.getElementById(styleId)) {
        var style = document.createElement('style');
        style.id = styleId;
        style.textContent = 
            '.app { position: relative; display: inline-block; }' +
            '.app .link-private { display: none !important; }' +
            '.app .link-public { display: inline-block !important; }' +
            'body.private-mode .app .link-private { display: inline-block !important; }' +
            'body.private-mode .app .link-public { display: none !important; }';
        document.head.appendChild(style);
    }

    // ✅ 修正选择器并绑定事件：.title -> .left
    var titleEl = document.querySelector("#main .topbar .left");
    if (titleEl) {
        titleEl.addEventListener('click', function() {
            if (window.location.hash === '#private') {
                window.location.hash = '';
            } else {
                window.location.hash = '#private';
            }
        });
    }

    // ✅ 修正模态框按钮选择器：.btn-cancel -> .btn (匹配 css.txt 结构)
    var modals = document.querySelectorAll('.modal');
    modals.forEach(function(modal) {
        var closeBtns = modal.querySelectorAll('.btn'); // 使用通用 .btn 类
        closeBtns.forEach(function(btn) {
            btn.addEventListener('click', function() {
                modal.style.display = 'none';
            });
        });
    });

    applyMode();
    window.addEventListener('hashchange', applyMode);
}
