<?php
// edit.php
header('Content-Type: application/json');

// 配置文件的路径
$configFile = dirname(__FILE__) . '/index.json';

// 读取配置文件内容
function readConfig() {
    global $configFile;
    if (!file_exists($configFile)) {
        return ['apps' => [], 'pins' => [], 'title' => '', 'user' => '', 'ipv6' => ''];
    }
    $json = file_get_contents($configFile);
    return json_decode($json, true);
}

// 保存配置文件
function saveConfig($data) {
    global $configFile;
    $json = json_encode($data, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE);
    file_put_contents($configFile, $json);
}

// 处理请求
$response = ['success' => false, 'message' => '未知错误'];
$action = $_POST['action'] ?? '';

try {
    $config = readConfig();

    switch ($action) {
        case 'update':
            // 更新操作
            $arrayType = $_POST['arrayType'] ?? '';
            $index = $_POST['index'] ?? -1;
            $txt = $_POST['txt'] ?? '';
            $url = $_POST['url'] ?? '';
            $purl = $_POST['purl'] ?? '';

            if (!in_array($arrayType, ['apps', 'pins'])) {
                throw new Exception('无效的数组类型');
            }

            if (!isset($config[$arrayType][$index])) {
                throw new Exception('索引不存在');
            }

            if (empty($txt) || empty($url) && empty($purl)) {
                throw new Exception('名称和外网或内网URL不能为空');
            }

            // 更新数据
            $config[$arrayType][$index] = [
                'txt' => $txt,
                'url' => $url,
                'purl' => $purl
            ];

            saveConfig($config);
            $response = ['success' => true, 'message' => '更新成功'];
            break;

        case 'delete':
            // 删除操作
            $arrayType = $_POST['arrayType'] ?? '';
            $index = $_POST['index'] ?? -1;

            if (!in_array($arrayType, ['apps', 'pins'])) {
                throw new Exception('无效的数组类型');
            }

            if (!isset($config[$arrayType][$index])) {
                throw new Exception('索引不存在');
            }

            // 删除指定元素
            array_splice($config[$arrayType], $index, 1);
            
            saveConfig($config);
            $response = ['success' => true, 'message' => '删除成功'];
            break;

        case 'add':
            // 添加新网址
            $txt = $_POST['txt'] ?? '';
            $url = $_POST['url'] ?? '';
            $purl = $_POST['purl'] ?? '';
            $type = $_POST['type'] ?? 'apps'; // 默认为apps

            if (!in_array($type, ['apps', 'pins'])) {
                throw new Exception('无效的数组类型');
            }

            if (empty($txt) || empty($url) && empty($purl)) {
                throw new Exception('名称和外网或内网URL不能为空');
            }

            // 添加新元素
            $config[$type][] = [
                'txt' => $txt,
                'url' => $url,
                'purl' => $purl
            ];

            saveConfig($config);
            $response = ['success' => true, 'message' => '添加成功'];
            break;

        default:
            $response = ['success' => false, 'message' => '无效的操作'];
    }
} catch (Exception $e) {
    $response = ['success' => false, 'message' => $e->getMessage()];
}

echo json_encode($response);
?>