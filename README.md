# socat IPv4/IPv6 转发脚本

支持：
- IPv6 → IPv4 (v6to4)
- IPv4 → IPv6 (v4to6)
- TCP / UDP / TCP+UDP
- systemd 自动守护、自动重启、开机自启

## 使用方法

### 安装规则
```
bash setup-socat-proxy.sh install
```

### 删除规则
```
bash setup-socat-proxy.sh remove
```

### 列出规则
```
bash setup-socat-proxy.sh list
```

### 重启规则
```
bash setup-socat-proxy.sh restart
```

## 示例：IPv4 → IPv6 SSH 中转

```
方向: 2
协议: 1
本地监听端口: 36022
远端 IPv6: 2a0f:7802:e2c1:33::a
远端端口: 22
```

客户端即可：
```
ssh -p 36022 root@<VPS_B IPv4>
```
