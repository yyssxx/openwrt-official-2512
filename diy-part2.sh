#!/bin/bash
#
# diy-part2.sh（官方 OpenWrt 25.12 树专用，probe2）：feeds install 之后、defconfig 之前执行
# 与 24.10 run7 版的唯一实质差别在第 1 段的 golang 链接目标（见该段注释）：
# probe1（2026-11-15）实证——手工符号链接覆盖在 apk 时代照样是构建期的选包
# 机制（xray-core 覆盖生效），但 golang 的链接因上游改版式而悬空、静默失效，
# 整炉死在 xray-core 编译（go.mod 要 go>=1.27，实际用了官方 go 1.24.13）。

# 1) 把 golang + xray-core 换成 coolsnowwolf/packages 的版本。
#    教训（2026-11-10）：./scripts/feeds install -f -p 在本流程里实测无效——首跑
#    run 42725891719 的日志显示实际编译的是 feeds/packages 的官方 xray-core，
#    WSL 本地同样复现（-f 无声无息不换链接）。改用手动符号链接：先摘掉官方源的
#    同名链接，再把 csw 的链进 package/feeds/cswpackages/，与 feeds install 生成
#    的链接完全一致（WSL 已验证：defconfig 后 CONFIG_XRAY_CORE_NAIVE=y）。
#    验收标准不变：config.buildinfo 里 CONFIG_XRAY_CORE_NAIVE=y 必须在，
#    且 manifest 里 xray-core 应为 26.11.9、cloudflared 应为 2026.10.6、frpc 应为 0.66.0。
rm -f package/feeds/packages/xray-core package/feeds/packages/golang
mkdir -p package/feeds/cswpackages
ln -sf ../../../feeds/cswpackages/net/xray-core package/feeds/cswpackages/xray-core
# golang 的链接目标比 24.10 时代深一层（probe1 实证）：coolsnowwolf/packages 在
# 2026-11-13 的同步里把 golang 改成了官方同款的嵌套版式——本体 Makefile 在
# lang/golang/golang/，lang/golang/ 本层只剩共享 .mk 文件。24.10 的链接指向
# lang/golang 本层，没有 Makefile，链接悬空被元数据扫描无声忽略，官方
# golang（25.12 是 1.24.13）胜出，xray-core（go.mod 要 go>=1.27）当场编死。
# 本体在 lang/golang/golang，版本 1.27.3，PKG_NAME=golang，2026-11-15 已验。
ln -sf ../../../feeds/cswpackages/lang/golang/golang package/feeds/cswpackages/golang
# 1b) cswpackages 里还有两个包同样进不了 install -a 的账本（run 42780589138 的
#     buildinfo 里双双缺席），一并手动链接——种子里都选了：
#     vlmcsd（KMS 本体）、luci-app-iptv（藏在 pon/ 目录下，依赖 luci-base +
#     firewall4 + kmod-nft-bridge，官方树全有）。
ln -sf ../../../feeds/cswpackages/net/vlmcsd package/feeds/cswpackages/vlmcsd
ln -sf ../../../feeds/cswpackages/pon/luci-app-iptv package/feeds/cswpackages/luci-app-iptv

# 硬校验（probe1 教训新增）：上面四条手工链接任何一条悬空都要当场判死，
# 不许再静默滑过去——diy 脚本没有 set -e，ln -sf 对不存在的目标不报错，
# 悬空链接会被元数据扫描无声忽略、官方同名包胜出，probe1 就死在这里。
for p in xray-core golang vlmcsd luci-app-iptv; do
  test -f "package/feeds/cswpackages/$p/Makefile" || { echo "ERROR: cswpackages/$p 覆盖链接失效（目标 Makefile 不存在）"; exit 1; }
done

# 1c) lede 独有的 LuCI 小应用（run 7 起只剩三个）已改走 diy-part1 登记的
#     ledeapps 本地源（src-link），feeds install 会把它们链进
#     package/feeds/ledeapps/，这里不再做任何拷贝——v2/v3 在此处 cp -r 的
#     两次失败教训见 diy-part1 里 ledeapps 段的注释（相对引用 ../../luci.mk
#     与物理路径的问题）。

# 1d) luci-app-turboacc（run 7 新增）：chenmozhijin 为官方树适配的版本，
#     不在现有任何源里，整仓克隆后只取应用目录。它与 1c 那批应用正好相反：
#     Makefile 用绝对引用 include $(TOPDIR)/feeds/luci/luci.mk，物理路径
#     无所谓，cp -r 进已登记的 cswpackages 目录是安全的。种子侧必须钉关
#     INCLUDE_NFT_FULLCONE（依赖的 kmod-nft-fullcone 各源都没有），见种子注释。
git clone --depth 1 https://github.com/chenmozhijin/turboacc.git /tmp/turboacc
cp -r /tmp/turboacc/luci-app-turboacc package/feeds/cswpackages/luci-app-turboacc
test -f package/feeds/cswpackages/luci-app-turboacc/Makefile || { echo "ERROR: luci-app-turboacc 拷贝失败"; exit 1; }

# 2) 修改默认管理 IP：192.168.1.1 -> 192.168.31.1（AX3000T 既定地址，与 run 20/22 一致）
sed -i 's/192.168.1.1/192.168.31.1/g' package/base-files/files/bin/config_generate

# 3) 注意：lede 版 diy-part2 里给 filogic.mk 打的 factory.ubi 补丁不要带过来——
#    官方树的设备定义自带 ARTIFACTS/initramfs-factory.ubi，构建会原生出 factory.ubi。

