fetch('ipv6.json')
    .then(response => {
        if (!response.ok) throw new Error(`HTTP ${response.status}`);
        return response.json();
    })
    .then(data => {
        const list = document.getElementById('ipv6-list');
        list.innerHTML = '';

        if (!Array.isArray(data.ipv6)) {
            list.innerHTML = '<li style="color: red;">JSON 数据格式错误</li>';
            return;
        }

        data.ipv6.forEach(item => {
            const li = document.createElement('li');
            const a = document.createElement('a');
            a.textContent = item.txt || '未命名地址';

            if (item.url && item.url.trim() !== '') {
                a.href = item.url;
                a.target = '_blank';
            } else {
                a.classList.add('empty-url');
                a.textContent += ' （未配置链接）';
            }

            li.appendChild(a);
            list.appendChild(li);
        });
    })
    .catch(error => {
        document.getElementById('ipv6-list').innerHTML = `<li style="color: red;">加载失败：${error.message}</li>`;
    });
