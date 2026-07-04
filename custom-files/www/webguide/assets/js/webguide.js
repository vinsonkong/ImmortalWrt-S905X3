
    
        // 全局变量初始化
        var title = "";
        var user = "";
        var ipv6 = "";
        var pins = [];
        var apps = [];
        var isEditing = false; // 编辑状态标记
        
        // 加载index.json文件
        (function loadConfig() {
            fetch('index.json')
                .then(response => response.json())
                .then(data => {
                    title = data.title || "";
                    user = data.user || "";
                    ipv6 = data.ipv6 || "";
                    pins = data.pins || [];
                    apps = data.apps || [];
                    




            
            const container = document.getElementById('link-container');            
            const link = document.createElement('a');
                link.href = `${data.ipv6}`;
                link.textContent = 'ipv6';
                container.appendChild(link);
            
            
                    
                    console.log("配置文件加载成功");
                    initPage();
                })
                .catch(error => {
                    console.log("配置文件加载失败，使用默认配置", error);
                    initPage();
                });
        })();


        
        // 创建应用图标
        function createAppIcon(item, arrayType, index) {
            const div = document.createElement('div');
            const span = document.createElement('span');
            const a = document.createElement('a');
            const strong = document.createElement('strong');

            div.className = "app";
            
            // 创建图标元素
            const icon = document.createElement('div');
            icon.className = 'app-icon';
            icon.textContent = item.txt ? item.txt.charAt(0) : 'A';
            
            a.innerHTML = '';
            a.public_url = item.url || "about:blank";
            a.private_url = item.purl;
            a.target = "_self";
            a.setAttribute('data-txt', item.txt || "未命名");
            a.setAttribute('data-array-type', arrayType);
            a.setAttribute('data-index', index);
            
            a.onclick = function(e) {
                // 如果处于编辑状态，显示编辑模态框
                if (isEditing) {
                    e.preventDefault();
                    showEditDialog(item, arrayType, index);
                    return false;
                }
                
                if (a.attributes["href"].value[0] === '#') {
                    window.location.hash = a.attributes["href"].value;
                    window.location.reload();
                    return false;
                }

                let url = (e.altKey ? item.purl || a.href : a.href) || "about:blank";

                if (e.ctrlKey) {
                    window.open(url);
                    return false;
                }
                
                // 直接跳转，不显示动画
                window.location.href = url;
                return false;
            };
            
            strong.innerText = item.txt || "未命名";

            span.appendChild(icon);
            span.appendChild(strong);
            a.appendChild(span);
            div.appendChild(a);
            
            return div;
        }

        // 初始化页面
        function initPage() {
            const $ = selector => document.querySelector(selector);
            const body = $("body");
            
            function resize() {
                body.style.height = window.innerHeight + "px";
                body.style.width = window.innerWidth + "px";
            };
            
            window.onresize = resize;
            window.ontouchend = resize;
            resize();



            document.title = title;
            if (window.location.hash === '#private') {
                document.title += `(内网)`;
            } else {
                document.title += `(外网)`;
            }
            $("#main .topbar .title").innerText = document.title;
            
  

            const grid = $("#main .content .grid");
            grid.innerHTML = '';
            for (let i = 0; i < apps.length; i++) {
                const app = createAppIcon(apps[i], 'apps', i);
                grid.appendChild(app);
            }

            const pin = $("#main .footerbar .grid");
            pin.innerHTML = '';
            for (let i = 0; i < Math.min(pins.length, 4); i++) {
                const app = createAppIcon(pins[i], 'pins', i);
                pin.appendChild(app);
            }

            // 初始化管理按钮
            const manageButton = document.getElementById('manage-button');
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
            
            // 初始化添加按钮
            const addButton = document.getElementById('add-button');
            addButton.addEventListener('click', function() {
                showAddDialog();
            });

            // 初始化编辑模态框事件
            const editModal = document.getElementById('edit-modal');
            editModal.querySelector('.cancel-btn').addEventListener('click', function() {
                editModal.style.display = 'none';
            });
            
            // 初始化添加模态框事件
            const addModal = document.getElementById('add-modal');
            addModal.querySelector('.cancel-btn').addEventListener('click', function() {
                addModal.style.display = 'none';
            });
            
            // 添加模态框的提交事件
            addModal.querySelector('.submit-btn').addEventListener('click', function() {
                const txt = document.getElementById('add-txt').value;
                const url = document.getElementById('add-url').value;
                const purl = document.getElementById('add-purl').value;
                
                if (!txt.trim() || !url.trim() && !purl.trim()) {
                    alert('名称和外网或内网URL不能为空');
                    return;
                }
                
                const formData = new FormData();
                formData.append('action', 'add');
                formData.append('arrayType', 'apps');
                formData.append('txt', txt);
                formData.append('url', url);
                formData.append('purl', purl);
                
                fetch('edit.php', {
                    method: 'POST',
                    body: formData
                })
                .then(response => response.json())
                .then(data => {
                    if (data.success) {
                        alert('添加成功');
                        location.reload();
                    } else {
                        alert('添加失败: ' + data.message);
                    }
                })
                .catch(error => {
                    alert('请求失败: ' + error);
                });
            });
            
            // 初始化ping检测
            function ping(ip, timeout, success) {
                if (window.location.hash === '#private') {
                    success && success();
                    return;
                }
                if (ip[0] === '#') {
                    return;
                }
                var img = new Image()
                var start = new Date().getTime()
                img.src = /^(http)/.test(ip) ? ip + "?t=" + start : "http://" + ip + "?t=" + start
                img.onload = function () {
                    success && success();
                }
                img.onerror = function () {
                    success && success();
                }
                var timer = setTimeout(() => success = null, timeout)
            }

            document.querySelectorAll(".app a").forEach(a => {
                a.href = a.public_url;
                const purl = a.private_url;
                if (purl) {
                    ping(purl, 1000, () => a.href = purl);
                }
            });
        }
        
        // 显示添加对话框
        function showAddDialog() {
            const addModal = document.getElementById('add-modal');
            document.getElementById('add-txt').value = '';
            document.getElementById('add-url').value = '';
            document.getElementById('add-purl').value = '';
            addModal.style.display = 'flex';
        }
        
        // 显示编辑对话框
        function showEditDialog(item, arrayType, index) {
            const editModal = document.getElementById('edit-modal');
            const txtInput = document.getElementById('edit-txt');
            const urlInput = document.getElementById('edit-url');
            const purlInput = document.getElementById('edit-purl');
            
            // 填充数据
            txtInput.value = item.txt || '';
            urlInput.value = item.url || '';
            purlInput.value = item.purl || '';
            
            // 显示模态框
            editModal.style.display = 'flex';
            
            // 删除按钮事件
            editModal.querySelector('.delete-btn').onclick = function() {
                if (confirm('确定要删除这个网址吗？')) {
                    deleteUrl(arrayType, index);
                }
            };
            
            // 提交按钮事件
            editModal.querySelector('.submit-btn').onclick = function() {
                const newData = {
                    txt: txtInput.value,
                    url: urlInput.value,
                    purl: purlInput.value
                };
                
                if (!newData.txt.trim() || !newData.url.trim() && !newData.purl.trim()) {
                    alert('名称和外网或内网URL不能为空');
                    return;
                }
                
                updateUrl(arrayType, index, newData);
            };
        }
        
        // 更新URL数据
        function updateUrl(arrayType, index, newData) {
            const formData = new FormData();
            formData.append('action', 'update');
            formData.append('arrayType', arrayType);
            formData.append('index', index);
            formData.append('txt', newData.txt);
            formData.append('url', newData.url);
            formData.append('purl', newData.purl);
            
            fetch('edit.php', {
                method: 'POST',
                body: formData
            })
            .then(response => response.json())
            .then(data => {
                if (data.success) {
                    alert('更新成功');
                    location.reload();
                } else {
                    alert('更新失败: ' + data.message);
                }
            })
            .catch(error => {
                alert('请求失败: ' + error);
            });
        }
        
        // 删除URL数据
        function deleteUrl(arrayType, index) {
            const formData = new FormData();
            formData.append('action', 'delete');
            formData.append('arrayType', arrayType);
            formData.append('index', index);
            
            fetch('edit.php', {
                method: 'POST',
                body: formData
            })
            .then(response => response.json())
            .then(data => {
                if (data.success) {
                    alert('删除成功');
                    location.reload();
                } else {
                    alert('删除失败: ' + data.message);
                }
            })
            .catch(error => {
                alert('请求失败: ' + error);
            });
        }
    
