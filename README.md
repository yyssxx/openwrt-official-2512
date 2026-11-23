# OpenWrt 25.12 — 小米 AX3000T 自编固件

基于**官方 OpenWrt 25.12**（`openwrt/openwrt` 的 `openwrt-25.12` 分支）为小米路由器 AX3000T（RD03，联发科 MT7981B / mediatek-filogic）定制的固件，GitHub Actions 云编译。

**当前状态**：2026-11-16 的 Release 已刷入实机日常运行，编译暂时暂停——没有「封版」一说，哪天想动随时重开。

## 当前版本

| 项目 | 内容 |
| --- | --- |
| Release | `xiaomi_mi-router-ax3000t-2026.11.16-0642` |
| 系统 | OpenWrt 25.12-SNAPSHOT r33380-60c494ad06 |
| 内核 | 6.12.116 |
| 默认 LAN | 192.168.31.1 |
| sysupgrade 包 | 37,468,455 B（35.73 MiB） |
| sysupgrade sha256 | `a161802c035e740e7ff7c50e586813bb6495afacfa4dfb07b1b53fbe32dbe70a` |

## 主要软件包

- **代理**：SSR Plus 198-r4（中文界面）+ Xray-core 26.11.9（coolsnowwolf/packages 覆盖版，开启 `CONFIG_XRAY_CORE_NAIVE`，XRay 型节点支持 naive 出站）、dns2tcp、ipt2socks
- **网络**：SmartDNS 46.1、DDNS 2.8.4、TurboACC 1.4、UPnP、nlbwmon 流量统计
- **远程访问**：frpc 0.66.0 + LuCI 面板、cloudflared 2026.10.6（Cloudflare Tunnel）
- **其它**：定时重启（luci-app-autoreboot）、vlmcsd 1113-r5、IPTV（luci-app-iptv + udpxy）、文件传输、网络唤醒

完整清单见 Release 里的 `.manifest` 文件。

## 仓库文件与编译

- `config-official.seed` — 编译种子配置
- `diy-part1.sh` / `diy-part2.sh` — 定制脚本（feeds 增补、LAN IP 等）
- `build-openwrt.yml` — Actions 工作流副本（实际工作流位于 `.github/workflows/`）
- **触发方式**：Actions 页面手动 Run workflow，可选开启 SSH 调试
- **Feeds**：官方 packages / luci / routing / telephony / video + helloworld + Openwrt-Passwall + coolsnowwolf/packages（详见 Release 的 `feeds.buildinfo`）

## 刷机路线

### 已在官方/OpenWrt 系统上（正常重刷）

LuCI 或 SSH 直接 sysupgrade Release 的 `squashfs-sysupgrade.bin`，可保留配置。

### 从原厂 MiWiFi 重刷

1. 全程**有线**连接，WiFi 关闭；用 XMiR 工具开 SSH（菜单 2），先做全备份（菜单 4）
2. 菜单 7 刷**官方 25.12.6 的 `factory.ubi`** 作跳板，进入临时系统（192.168.1.1）
3. sysupgrade 本仓库 Release 的 sysupgrade 包（不保留配置）

> ⚠️ **绝不能用本仓库自编的 `initramfs-factory.ubi`（35.62 MiB）当菜单 7 跳板**——它超过 34 MiB 的 `ubi_kernel` 分区，刷入变砖。跳板只能用官方 factory.ubi。
>
> 刷前红线：sysupgrade 包内 root ≤ 78 MiB（81,788,928 B）、kernel ≤ 34 MiB；哈希核对无误再刷。

## 备注

- 本机型与 lede 布局不兼容、ImmortalWrt 没有 SSR Plus，官方 25.12 是唯一走得通的自编路线。
- 救砖：小米官方修复工具 + 原厂固件 `miwifi_rd03_firmware_14680_1.0.64.bin`。
- 24.10 自编线已于 2026-11-16 弃用（仓库 `openwrt-official` 保留未删）。
