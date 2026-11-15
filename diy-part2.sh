#!/bin/bash
#
# diy-part2.sh（官方 OpenWrt 25.12 树专用，probe5）：feeds install 之后、defconfig 之前执行
# probe1（2026-11-15）实证——golang 的包链接因上游改版式而悬空、静默失效；
# probe2 把链接目标修对（lang/golang/golang）后仍死在 xray-core：包选对了
# （csw golang 1.27.3 确实编了），但 xray-core 的 Makefile 写死了引用官方源的
# golang-package.mk（见 1e 段），工具链由那份 .mk 按官方默认版本 1.24.13 选，
# 与包覆盖是两条线。probe3 在 probe2 基础上加 1e 段改写该引用，其余不变。
# probe4 = probe3 + 种子补传（种子此前漏传，三炉白跑）：构建一路走到
# package/compile 深处，只剩 vlmcsd 在 apk 打包步被拒（见 1f 段）。
# probe5 在 probe3 基础上加 1f 段给 vlmcsd 覆写 apk 版本号，其余不变。

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

# 1e) xray-core 的工具链引用改写（probe2 实证新增）：csw 的 xray-core Makefile
#     写死 include $(TOPDIR)/feeds/packages/lang/golang/golang-package.mk——
#     这行是按 lede 写的（在 lede 里 feeds/packages 就是 csw 本人，无碍）；
#     在官方树里 feeds/packages 是官方源，它那份新版 .mk 会把 PATH 指到官方
#     默认版本的工具链目录（25.12 默认 go 1.24.13），xray 的 go.mod 要
#     >=1.27，当场编死——包覆盖选对 csw golang 也没用，.mk 是另一条线。
#     改指 csw 自己的 golang-package.mk，恢复 lede 里的同款搭配
#     （csw xray + csw .mk + csw golang 1.27.3，D2 那边天天在编）。
XRAY_MK="feeds/cswpackages/net/xray-core/Makefile"
sed -i 's|$(TOPDIR)/feeds/packages/lang/golang/golang-package.mk|$(TOPDIR)/feeds/cswpackages/lang/golang/golang-package.mk|' "$XRAY_MK"
grep -qF 'feeds/cswpackages/lang/golang/golang-package.mk' "$XRAY_MK" || { echo "ERROR: xray-core 的 golang-package.mk 引用改写失败"; exit 1; }

# 1f) vlmcsd 的 apk 版本号覆写（probe4 实证新增）：csw 的 vlmcsd
#     PKG_VERSION:=svn1113（opkg 时代无碍），25.12 的 apk 对版本号校验
#     严于 opkg——必须数字开头，"svn1113-r5" 在 apk mkpkg 步被当场拒
#     （ERROR: info field 'version' has invalid value）。PKG_VERSION 本身
#     还兼作源码 tag（下载地址 tar.gz/svn1113），不能直接改；改走包定义
#     里的 VERSION 覆写（include/package-defaults.mk 的默认
#     VERSION:=$(PKG_VERSION)-r$(PKG_RELEASE) 可被包自己的 define 覆盖，
#     package-pack.mk 的 mkpkg --info version:$(VERSION) 吃的就是它），
#     源码抓取与构建目录一律不动，只让最终包版本变成 1113-r5。
VLMCSD_MK="feeds/cswpackages/net/vlmcsd/Makefile"
sed -i 's|^define Package/vlmcsd$|define Package/vlmcsd\n\tVERSION:=1113-r$(PKG_RELEASE)|' "$VLMCSD_MK"
grep -qF 'VERSION:=1113-r$(PKG_RELEASE)' "$VLMCSD_MK" || { echo "ERROR: vlmcsd 的 VERSION 覆写失败"; exit 1; }

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
