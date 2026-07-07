// 全局变量初始化
var title = "";
var user = "";
var ipv6 = "";
var pins = [];
var apps = [];
var isEditing = false; // 编辑状态标记

// 1. 加载配置文件
(function loadConfig() {
    fetch('../index.json') 
        .then(function(r) { 
            if (!r.ok) throw new Error('Network response was not ok');
            return r.json(); 
        })
        .then(function(data) {
            title = data.title || "";
            user = data.user || "";
            ipv6 = data.ipv6 || "";
            pins = Array.isArray(data.pins) ? data.pins : [];
            apps = Array.isArray(data.apps) ? data.apps : [];

            initPage();
        })
        .catch(function(err) {
            console.warn("加载配置失败，使用默认空数据:", err);
            title = "导航";
            initPage();
        });
})();

// 2. 创建应用图标 (单链接动态切换法)
function createAppIcon(item) {
    var div = document.createElement('div');
    div.className = "app";

    var a = document.createElement('a');
    a.className = 'app-link';
    a.target = "_self";
    a.setAttribute('data-url', item.url || '#');
    a.setAttribute('data-purl', item.purl || item.url || '#');

    var span = document.createElement('span');
    var icon = document.createElement('div');
    icon.className = 'app-icon';
    icon.textContent = item.txt ? item.txt.charAt(0) : 'A';
    
    var strong = document.createElement('strong');
    strong.innerText = item.txt || "未命名";
    
    span.appendChild(icon);
    span.appendChild(strong);
    a.appendChild(span);

    a.onclick = function(e) {
        if (isEditing) {
            e.preventDefault();
            e.stopPropagation();
            var arrayType = apps.includes(item) ? 'apps' : 'pins';
            var index = (arrayType === 'apps' ? apps : pins).indexOf(item);
            showEditDialog(item, arrayType, index);
            return false;
        }

        if (e.altKey && item.purl) {
            e.preventDefault();
            if (e.ctrlKey) {
                window.open(item.purl);
            } else {
                window.location.href = item.purl;
            }
            return false;
        }
    };

    div.appendChild(a);
    return div;
}

// 3. 应用模式切换
function applyMode() {
    var isPrivate = window.location.hash === '#private';
    document.title = title + (isPrivate ? " (内网)" : " (外网)");
    
    var titleEl = document.querySelector("#main .topbar .title");
    if (titleEl) {
        titleEl.innerText = document.title;
        titleEl.style.cursor = "pointer";
    }

    if (isPrivate) {
        document.body.classList.add('private-mode');
    } else {
        document.body.classList.remove('private-mode');
    }

    var links = document.querySelectorAll('.app .app-link');
    links.forEach(function(a) {
        var url = a.getAttribute('data-url');
        var purl = a.getAttribute('data-purl');
        if (isPrivate) {
            a.href = purl; 
        } else {
            a.href = url;  
        }
    });
}

// 4. 初始化页面
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
        apps.forEach(function(app) { 
            grid.appendChild(createAppIcon(app)); 
        });
    }

    var pinGrid = document.querySelector("#main .footerbar .grid");
    if (pinGrid) {
        pinGrid.innerHTML = '';
        pins.slice(0, 4).forEach(function(pin) { 
            pinGrid.appendChild(createAppIcon(pin)); 
        });
    }

    var titleEl = document.querySelector("#main .topbar .title");
    if (titleEl) {
        titleEl.addEventListener('click', function() {
            if (window.location.hash === '#private') {
                window.location.hash = ''; 
            } else {
                window.location.hash = '#private'; 
            }
        });
    }

    var manageButton = document.getElementById('manage-button');
    if (manageButton) {
        manageButton.addEventListener('click', function() {
            isEditing = !isEditing;
            if (isEditing) {
                this.innerHTML = '<i class="fas fa-sign-out-alt"></i> 退出管理';
                body.classList.add('editing');
            } else {
                this.innerHTML = '<i class="fas fa-edit"></i> 管理网址';
                body.classList.remove('editing');
            }
        });
    }

    var addButton = document.getElementById('add-button');
    if (addButton) {
        addButton.addEventListener('click', function() {
            showAddDialog();
        });
    }

    applyMode();
    window.addEventListener('hashchange', applyMode);

    initModalEvents();
}

// 5. 模态框事件处理 (⭐ 修复了选择器，并增加了安全判空防止 JS 崩溃)
function initModalEvents() {
    var addModal = document.getElementById('add-modal');
    var editModal = document.getElementById('edit-modal');

    function closeModal(modal) {
        if (modal) modal.style.display = 'none';
    }

    // --- 添加模态框 ---
    if (addModal) {
        // ⭐ 修正选择器：.cancel-btn -> .btn-cancel
        var addCancelBtn = addModal.querySelector('.btn-cancel');
        if (addCancelBtn) {
            addCancelBtn.addEventListener('click', function(e) {
                e.preventDefault();
                closeModal(addModal);
            });
        }

        // ⭐ 修正选择器：.submit-btn -> .btn-submit
        var addSubmitBtn = addModal.querySelector('.btn-submit');
        if (addSubmitBtn) {
            addSubmitBtn.addEventListener('click', function(e) {
                e.preventDefault();
                
                var txt = document.getElementById('add-txt').value.trim();
                var url = document.getElementById('add-url').value.trim();
                var purl = document.getElementById('add-purl').value.trim();
                
                if (!txt || (!url && !purl)) {
                    alert('名称和至少一个URL不能为空');
                    return;
                }

                var formData = new FormData();
                formData.append('action', 'add');
                formData.append('arrayType', 'apps'); 
                formData.append('txt', txt);
                formData.append('url', url);
                formData.append('purl', purl);

                fetch('edit.php', { method: 'POST', body: formData })
                    .then(function(r) { return r.json(); })
                    .then(function(data) {
                        if (data.success) {
                            alert('添加成功');
                            location.reload();
                        } else {
                            alert('添加失败: ' + data.message);
                        }
                    })
                    .catch(function(err) { alert('请求失败: ' + err); });
            });
        }
        
        addModal.addEventListener('click', function(e) {
            if (e.target === addModal) closeModal(addModal);
        });
    }

    // --- 编辑模态框 ---
    if (editModal) {
        var editCancelBtn = editModal.querySelector('.btn-cancel');
        if (editCancelBtn) {
            editCancelBtn.addEventListener('click', function(e) {
                e.preventDefault();
                closeModal(editModal);
            });
        }

        var editSubmitBtn = editModal.querySelector('.btn-submit');
        if (editSubmitBtn) {
            editSubmitBtn.addEventListener('click', function(e) {
                e.preventDefault();
                if (!window.currentEditItem) return;
                
                var txt = document.getElementById('edit-txt').value.trim();
                var url = document.getElementById('edit-url').value.trim();
                var purl = document.getElementById('edit-purl').value.trim();
                
                if (!txt || (!url && !purl)) {
                    alert('名称和至少一个URL不能为空');
                    return;
                }

                var newData = { txt: txt, url: url, purl: purl };
                updateUrl(window.currentEditItem.arrayType, window.currentEditItem.index, newData);
            });
        }

        // ⭐ 修正选择器：.delete-btn -> .btn-delete
        var deleteBtn = editModal.querySelector('.btn-delete');
        if (deleteBtn) {
            deleteBtn.addEventListener('click', function(e) {
                e.preventDefault();
                if (window.currentEditItem && confirm('确定要删除这个网址吗？')) {
                    deleteUrl(window.currentEditItem.arrayType, window.currentEditItem.index);
                }
            });
        }

        editModal.addEventListener('click', function(e) {
            if (e.target === editModal) closeModal(editModal);
        });
    }
}

// 6. 辅助函数
function showAddDialog() {
    var addModal = document.getElementById('add-modal');
    if (addModal) {
        document.getElementById('add-txt').value = '';
        document.getElementById('add-url').value = '';
        document.getElementById('add-purl').value = '';
        addModal.style.display = 'flex';
    }
}

function showEditDialog(item, arrayType, index) {
    var editModal = document.getElementById('edit-modal');
    if (editModal) {
        window.currentEditItem = { arrayType: arrayType, index: index };
        document.getElementById('edit-txt').value = item.txt || '';
        document.getElementById('edit-url').value = item.url || '';
        document.getElementById('edit-purl').value = item.purl || '';
        editModal.style.display = 'flex';
    }
}

// 7. API 请求
function updateUrl(arrayType, index, newData) {
    var formData = new FormData();
    formData.append('action', 'update');
    formData.append('arrayType', arrayType);
    formData.append('index', index);
    formData.append('txt', newData.txt);
    formData.append('url', newData.url);
    formData.append('purl', newData.purl);

    fetch('edit.php', { method: 'POST', body: formData })
        .then(function(r) { return r.json(); })
        .then(function(data) {
            if (data.success) {
                alert('更新成功');
                location.reload();
            } else {
                alert('更新失败: ' + data.message);
            }
        })
        .catch(function(err) { alert('请求失败: ' + err); });
}

function deleteUrl(arrayType, index) {
    var formData = new FormData();
    formData.append('action', 'delete');
    formData.append('arrayType', arrayType);
    formData.append('index', index);

    fetch('edit.php', { method: 'POST', body: formData })
        .then(function(r) { return r.json(); })
        .then(function(data) {
            if (data.success) {
                alert('删除成功');
                location.reload();
            } else {
                alert('删除失败: ' + data.message);
            }
        })
        .catch(function(err) { alert('请求失败: ' + err); });
}
