#!/bin/bash

#天光云影app云同步备份文件远程助手
#适用于飞牛OS系统X86
# 定义变量（以下变量须自行修改）
USERNAME="admin"                # 账号
PASSWORD="admin"               # 密码
CONFIG_DIR="/vol2/1000/www"    # 配置目录（存放天光云影备份文件的目录）
PORT_MAPPING="5000:5000"       # 端口映射（默认就行）
PROJECT_DIR="/vol1/1000/docker/tgyy-web"  # 项目目录变量

# 创建项目目录（如果不存在）
mkdir -p "$PROJECT_DIR" || { echo "无法创建项目目录"; exit 1; }

# 进入项目目录
cd "$PROJECT_DIR" || { echo "无法进入项目目录"; exit 1; }

# 停止并删除旧容器和镜像
docker stop tgyy-web 2>/dev/null
docker rm -f tgyy-web 2>/dev/null
docker rmi -f tgyy-web-config 2>/dev/null

# 清理旧文件
rm -rf app.py Dockerfile templates requirements.txt
mkdir -p templates "$CONFIG_DIR" || { echo "无法创建目录"; exit 1; }

# 创建requirements.txt
cat > requirements.txt << 'EOF'
flask==2.0.1
werkzeug==2.0.2
EOF

# 创建app.py（使用变量配置账号）
cat > app.py << EOF
from flask import Flask, render_template, request, redirect, send_from_directory
import json
import os
import logging
from werkzeug.security import generate_password_hash, check_password_hash
from flask import request, Response

# 配置日志
logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler("/app/config/app.log"),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

app = Flask(__name__)
CONFIG_PATH = "/app/config/all_configs.json"
CONFIG_DIR = os.path.dirname(CONFIG_PATH)

# 确保配置目录存在
try:
    os.makedirs(CONFIG_DIR, exist_ok=True)
    logger.info(f"配置目录已准备: {CONFIG_DIR}")
except Exception as e:
    logger.error(f"创建配置目录失败: {str(e)}")

# 账号密码配置（使用变量）
USER_CREDENTIALS = {
    '$USERNAME': generate_password_hash('$PASSWORD')  # 用户名: $USERNAME, 密码: $PASSWORD
}

# 密码保护装饰器
def login_required(f):
    def decorated(*args, **kwargs):
        try:
            # 尝试获取Authorization头
            auth_header = request.headers.get('Authorization')
            if not auth_header or not auth_header.startswith('Basic '):
                logger.warning("未提供有效的Authorization头")
                return Response(
                    'Authentication required', 401,
                    {'WWW-Authenticate': 'Basic realm="Config Management"'})
            
            # 验证账号密码
            from base64 import b64decode
            auth_info = b64decode(auth_header[6:]).decode('utf-8')
            if ':' in auth_info:
                username, password = auth_info.split(':', 1)
            else:
                username = '$USERNAME'
                password = auth_info
            
            # 检查用户名是否存在且密码正确
            if username not in USER_CREDENTIALS or not check_password_hash(USER_CREDENTIALS[username], password):
                logger.warning(f"账号 {username} 验证失败")
                return Response(
                    'Invalid username or password', 401,
                    {'WWW-Authenticate': 'Basic realm="Config Management"'})
            
            return f(*args, **kwargs)
        except Exception as e:
            logger.error(f"验证过程出错: {str(e)}", exc_info=True)
            return "Server error", 500
    return decorated

def load_config():
    try:
        if not os.path.exists(CONFIG_PATH):
            logger.info("创建默认配置文件")
            default_config = {
                "configs": {
                    "iptvSourceCurrent": {"name": "IPTV", "url": "", "isLocal": False, "transformJs": None},
                    "iptvSourceList": {"value": [{"name": "IPTV", "url": "", "isLocal": False, "transformJs": None}]},
                    "epgSourceCurrent": {"name": "默认节目单 综合", "url": ""},
                    "videoPlayerUserAgent": ""
                }
            }
            save_config(default_config)
            return default_config
            
        with open(CONFIG_PATH, 'r', encoding='utf-8') as f:
            return json.load(f)
    except Exception as e:
        logger.error(f"读取配置出错: {str(e)}")
        return {"configs": {}}

def save_config(data):
    try:
        with open(CONFIG_PATH, 'w', encoding='utf-8') as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
        logger.info("配置已保存")
    except Exception as e:
        logger.error(f"保存配置出错: {str(e)}")

@app.route('/', methods=['GET', 'POST'])
@login_required
def index():
    try:
        config = load_config()
        logger.debug(f"加载配置: {config}")
        
        if request.method == 'POST':
            new_current_url = request.form.get('iptv_current_url', '').strip()
            if new_current_url:
                config['configs']['iptvSourceCurrent']['url'] = new_current_url
            
            new_list_url = request.form.get('iptv_list_url', '').strip()
            if new_list_url:
                if 'value' not in config['configs']['iptvSourceList']:
                    config['configs']['iptvSourceList']['value'] = []
                if len(config['configs']['iptvSourceList']['value']) == 0:
                    config['configs']['iptvSourceList']['value'].append({
                        "name": "IPTV", "url": "", "isLocal": False, "transformJs": None
                    })
                config['configs']['iptvSourceList']['value'][0]['url'] = new_list_url
            
            new_epg_url = request.form.get('epg_url', '').strip()
            if new_epg_url:
                config['configs']['epgSourceCurrent']['url'] = new_epg_url
            
            new_ua = request.form.get('user_agent', '').strip()
            if new_ua:
                config['configs']['videoPlayerUserAgent'] = new_ua
            
            save_config(config)
            return redirect('/')
        
        template_path = os.path.join(app.root_path, 'templates', 'index.html')
        if not os.path.exists(template_path):
            logger.error(f"模板文件不存在: {template_path}")
            return "Template missing", 500
            
        return render_template('index.html', config=config)
    except Exception as e:
        logger.error(f"根路由处理出错: {str(e)}", exc_info=True)
        return "Server error", 500

@app.route('/all_configs.json')
def serve_config():
    try:
        if os.path.exists(CONFIG_PATH):
            return send_from_directory(CONFIG_DIR, 'all_configs.json', mimetype='application/json')
        return "Config file not found", 404
    except Exception as e:
        logger.error(f"配置文件访问出错: {str(e)}")
        return "Server error", 500

@app.route('/health')
def health_check():
    return "OK", 200

if __name__ == '__main__':
    try:
        logger.info("应用启动中...")
        app.run(host='0.0.0.0', port=5000, debug=False, use_reloader=False)
    except Exception as e:
        logger.critical(f"应用启动失败: {str(e)}", exc_info=True)
EOF

# 创建前端页面
cat > templates/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>天光云影云同步配置管理</title>
    <style>
        body { font-family: Arial, sans-serif; max-width: 1200px; margin: 0 auto; padding: 20px; }
        .form-group { margin: 20px 0; padding: 15px; border: 1px solid #eee; border-radius: 6px; }
        label { display: block; margin-bottom: 8px; font-weight: bold; color: #333; }
        input { width: 100%; padding: 10px; border: 1px solid #ddd; border-radius: 4px; box-sizing: border-box; }
        button { padding: 12px 24px; background: #4285f4; color: white; border: none; border-radius: 4px; cursor: pointer; }
        button:hover { background: #3367d6; }
        h1 { color: #202124; border-bottom: 1px solid #eee; padding-bottom: 10px; }
        .link-section { margin: 20px 0; padding: 15px; background-color: #f5f5f5; border-radius: 6px; }
        .link-section a { color: #1a73e8; text-decoration: none; }
        .link-section a:hover { text-decoration: underline; }
    </style>
</head>
<body>
    <h1>天光云影云同步配置管理</h1>
    
    <div class="link-section">
        <p><strong>配置文件直接访问:</strong> <a href="/all_configs.json" target="_blank">/all_configs.json</a></p>
    </div>
    
    <form method="POST">
        <div class="form-group">
            <label>iptvSourceCurrent 链接:</label>
            <input type="text" name="iptv_current_url" value="{{ config['configs']['iptvSourceCurrent']['url'] if config.get('configs') else '' }}" size="150">
        </div>
        
        <div class="form-group">
            <label>iptvSourceList 链接:</label>
            <input type="text" name="iptv_list_url" value="{{ config['configs']['iptvSourceList']['value'][0]['url'] if config.get('configs') and config['configs'].get('iptvSourceList') and config['configs']['iptvSourceList'].get('value') else '' }}" size="150">
        </div>
        
        <div class="form-group">
            <label>EPG 链接:</label>
            <input type="text" name="epg_url" value="{{ config['configs']['epgSourceCurrent']['url'] if config.get('configs') else '' }}" size="150">
        </div>
        
        <div class="form-group">
            <label>用户代理 (UA):</label>
            <input type="text" name="user_agent" value="{{ config['configs']['videoPlayerUserAgent'] if config.get('configs') else '' }}" size="100">
        </div>
        
        <button type="submit">保存修改</button>
    </form>
</body>
</html>
EOF

# 创建Dockerfile
cat > Dockerfile << 'EOF'
FROM python:3.9-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --default-timeout=1000 \
    --retries 5 \
    -i https://pypi.tuna.tsinghua.edu.cn/simple \
    --no-cache-dir -r requirements.txt

COPY app.py .
COPY templates ./templates

# 创建配置目录并设置权限
RUN mkdir -p /app/config && chmod -R 777 /app/config

EXPOSE 5000

CMD ["python", "app.py"]
EOF

# 创建all_configs.json并放入宿主机的配置目录
cat > "$CONFIG_DIR/all_configs.json" << 'EOF'
{
  "version": "3.3.10",
  "syncAt": 1757992495076,
  "syncFrom": "秦的HONOR 30 Pro",
  "description": null,
  "configs": {
    "appBootLaunch": false,
    "appPipEnable": false,
    "appLastLatestVersion": "1.3.0.172",
    "appAgreementAgreed": true,
    "appStartupScreen": "Live",
    "debugDeveloperMode": true,
    "debugShowFps": false,
    "debugShowVideoPlayerMetadata": false,
    "debugShowLayoutGrids": false,
    "iptvSourceCacheTime": 3600000,
    "iptvSourceCurrent": {
      "name": "IPTV",
      "url": "https://sub.ottiptv.cc/douyuyqk.m3u",
      "isLocal": false,
      "transformJs": null
    },
    "iptvSourceList": {
      "value": [
        {
          "name": "IPTV",
          "url": "https://sub.ottiptv.cc/douyuyqk.m3u",
          "isLocal": false,
          "transformJs": null
        }
      ]
    },
    "iptvChannelGroupHiddenList": [],
    "iptvHybridMode": "IPTV_FIRST",
    "iptvSimilarChannelMerge": true,
    "iptvChannelLogoProvider": "https://gitee.com/mytv-android/myTVlogo/raw/main/img/{name|uppercase}.png",
    "iptvChannelLogoOverride": true,
    "iptvChannelFavoriteEnable": true,
    "iptvChannelFavoriteListVisible": false,
    "iptvChannelFavoriteList": {
      "value": []
    },
    "iptvChannelLastPlay": null,
    "iptvChannelLinePlayableHostList": null,
    "iptvChannelLinePlayableUrlList": null,
    "iptvChannelChangeFlip": false,
    "iptvChannelNoSelectEnable": true,
    "iptvChannelChangeListLoop": true,
    "epgEnable": true,
    "epgSourceCurrent": {
      "name": "默认节目单 综合",
      "url": "https://gitee.com/mytv-android/myepg/raw/master/output/epg.gz"
    },
    "epgSourceList": {
      "value": []
    },
    "epgRefreshTimeThreshold": 2,
    "epgSourceFollowIptv": false,
    "epgChannelReserveList": {
      "value": []
    },
    "uiShowEpgProgrammeProgress": true,
    "uiShowEpgProgrammePermanentProgress": false,
    "uiShowChannelLogo": true,
    "uiShowChannelPreview": true,
    "uiUseClassicPanelScreen": true,
    "uiDensityScaleRatio": 0.0,
    "uiFontScaleRatio": 1.0,
    "uiTimeShowMode": "EVERY_HOUR",
    "uiFocusOptimize": false,
    "uiScreenAutoCloseDelay": 15000,
    "updateForceRemind": true,
    "updateChannel": "stable",
    "videoPlayerCore": "MEDIA3",
    "videoPlayerRenderMode": "SURFACE_VIEW",
    "videoPlayerUserAgent": "okHttp/Mod-1.4.0.0",
    "videoPlayerHeaders": "",
    "videoPlayerLoadTimeout": 15000,
    "videoPlayerDisplayMode": "SIXTEEN_NINE",
    "videoPlayerForceAudioSoftDecode": false,
    "videoPlayerStopPreviousMediaItem": false,
    "videoPlayerSkipMultipleFramesOnSameVSync": true,
    "themeAppCurrent": null,
    "cloudSyncAutoPull": null,
    "cloudSyncProvider": null,
    "cloudSyncGithubGistId": null,
    "cloudSyncGithubGistToken": null,
    "cloudSyncGiteeGistId": null,
    "cloudSyncGiteeGistToken": null,
    "cloudSyncNetworkUrl": null,
    "cloudSyncLocalFilePath": null,
    "cloudSyncWebDavUrl": null,
    "cloudSyncWebDavUsername": null,
    "cloudSyncWebDavPassword": null,
    "feiyangAllInOneFilePath": ""
  },
  "extraLocalIptvSourceList": {},
  "extraChannelNameAlias": ""
}
EOF

# 构建并启动
docker build --network=host -t tgyy-web-config . || { echo "构建失败"; exit 1; }
docker run -d \
  --name tgyy-web \
  -p "$PORT_MAPPING" \
  -v "$CONFIG_DIR:/app/config" \
  --restart always \
  tgyy-web-config || { echo "启动失败"; exit 1; }

# 设置目录权限
chmod -R 777 "$CONFIG_DIR" || { echo "设置目录权限失败"; exit 1; }

# 部署完成后显示明文信息
echo "部署完成！"
echo "访问地址: http://localhost:5000/"
echo "用户名: admin"
echo "密码: admin"
echo "配置文件已初始化到 /vol2/1000/www/all_configs.json"
echo "查看日志: docker logs -f tgyy-web"