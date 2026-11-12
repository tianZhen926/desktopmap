<h1 align="center">🗺️ 桌面地图 DesktopMap</h1>

<p align="center">
  <b>把「哪个目录占地方、里面是什么、能不能删」做成一张贴在你桌面壁纸层、抬眼就能看到的地图。</b>
</p>

<p align="center">
  <a href="https://github.com/tianZhen926/desktopmap/releases"><img src="https://img.shields.io/github/v/release/tianZhen926/desktopmap?label=release&color=0b7285" alt="release"></a>
  <img src="https://img.shields.io/badge/macOS-13.0%2B-000000?logo=apple&logoColor=white" alt="macOS 13+">
  <img src="https://img.shields.io/badge/arch-arm64%20%2B%20x86__64-informational" alt="universal">
  <img src="https://img.shields.io/badge/stack-Swift%20%C2%B7%20SwiftUI%20%C2%B7%20AppKit-F05138?logo=swift&logoColor=white" alt="stack">
  <img src="https://img.shields.io/badge/network%20requests-0-brightgreen" alt="no network">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green" alt="MIT"></a>
</p>

<p align="center">
  ⚡ 点一条就在访达跳过去 &nbsp;·&nbsp; 📏 大小自己去测 &nbsp;·&nbsp; ⌨️ <b>⌃⌥⌘M</b> 拉出一屏卡片
</p>

---

## 🚩 三条硬约束

不是特性，是设计边界。违反其中任何一条的 PR 会被拒。

- 🚫 **只跳转，不删除。** 清单里的目录只会被访达打开，不写入、不移动、不改权限。
  代码里确有 `removeItem`，但 5 处目标全是自己的数据文件（清单 / 日志截断 / 备份轮换），`trashItem` 零命中。
  移除某条只是撤掉可视化，文件在原位，顶栏可一步放回。
- 🔌 **零网络。** 没有 URLSession、埋点、更新检查、崩溃上报；整个工程只 import 7 个本地框架，
  源码搜不到一处 `http`。上面那枚徽标不是装饰。
- 🧾 **改动可回溯。** 每次保存前自动留清单快照（最多 15 份），跳转、编辑、撤卡片都写进行为日志。

## 📥 快速开始

```bash
# 1. 下载（推荐 dmg）  https://github.com/tianZhen926/desktopmap/releases
# 2. 打开 dmg，把 DesktopMap 拖进「应用程序」
# 3. 第一次打开会被 Gatekeeper 拦——ad-hoc 自签、无证书无公证，二选一绕过：
xattr -cr /Applications/DesktopMap.app    # 或右键 App → 打开 → 再点一次「打开」
```

通用二进制，Apple Silicon 与 Intel 都支持，需要 macOS 13+。核对校验和：

```bash
shasum -a 256 ~/Downloads/DesktopMap-*.dmg   # 数值见 Release 正文 / SHA256SUMS.txt
```

上手只要三步：**添加文件夹** → 看测出来的大小 → 双击跳到访达。

## 🖥️ 四个入口

| 入口 | 用来干什么 |
| --- | --- |
| **桌面面板** | 常驻看板。贴在壁纸/图标层，不抢焦点，可置顶、可指定显示在哪块屏 |
| **控制台** | 管理后台。条目增删改、分组改名与并入、扫描大目录、层级与刷新设置、开机自启、备份恢复 |
| **状态栏** | 临时入口。菜单 + 磁盘剩余读数；卡片模式开着时左键开合浮层、右键出菜单 |
| **卡片浮层** | 全屏概览。<kbd>⌃</kbd><kbd>⌥</kbd><kbd>⌘</kbd><kbd>M</kbd> 唤起，启动台式进出动画、搜索、只看可删、只看 1G 以上、拖入添加、ⓘ 详情、✕ 撤卡片 |

浮层跟随鼠标所在屏幕——在外接屏干活时不用回头去够状态栏图标。

<details>
<summary>🔬 工作原理（点开看）</summary>

- **大小测量** — `/usr/bin/du -sk`，最多 4 路并发，跳过已测路径，单目录有超时保护（防卡在未挂载软链或网络盘）。系统禁止第三方统计的目录显示 `?`。
- **桌面层** — 层级取 `CGWindowLevelForKey(.desktopIconWindow)`；用普通 `.desktopWindow` 会被 Finder 壁纸窗口盖住并吃掉点击。hosting view 要放开 `acceptsFirstMouse`，否则首次点击只激活 App。
- **全局快捷键** — Carbon `RegisterEventHotKey`，不需要辅助功能权限，不弹授权框。
- **层级冲突** — 浮层层级高于 `NSOpenPanel` 与 `NSMenu`，所以选文件夹必须先收浮层、选完再展开；浮层内不能用下拉菜单，只能平铺按钮。
- **清单结构** — 一条 = 路径 + 名称 + 分组 + 备注 + 风险标记（🟢 可删 / 🟠 看清再动 / ⚪ 别动）。分组是自由文本，敲个新名字就建立。

</details>

## 📁 你的数据

```
~/Library/Application Support/DesktopMap/
├── list.json       清单本体
├── actions.log     行为日志
└── backups/        每次保存前自动留，最多 15 份
```

偏好写在 `dev.fengtianzeng.desktopmap` 域。数据只落在你自己机器上；卸载 = 删 App + 删这个目录。
「恢复出厂清单」「恢复到最近备份」都是先留当前快照、再二次确认才执行。

## 🛠️ 从源码构建

只需要 Command Line Tools，**没有 Xcode 工程**。

```bash
git clone https://github.com/tianZhen926/desktopmap.git && cd desktopmap
./build.sh      # 本机架构，约 40 秒 → ~/Applications/DesktopMap.app
./release.sh    # 发布用：通用二进制 + dmg + zip + 校验和 + 上线前隐私自检
```

| 开关 | 作用 |
| --- | --- |
| `DM_OUT` | 产物位置（默认 `~/Applications/DesktopMap.app`） |
| `DM_UNIVERSAL=1` | arm64 与 x86_64 各编一份再合成通用二进制 |
| `DM_SEED=public` | 强制使用仓库里的通用示例种子清单 |

> 🌱 **出厂种子**：仓库里的 `default_list.json` 是 18 条通用示例。想恢复成自己整理的一份，
> 放 `Resources/default_list.local.json` 即可（`build.sh` 优先用它，已在 `.gitignore` 里）。
> 对外发布只走 `release.sh`——它强制公开种子，并在打包前后各扫一遍私人路径，扫到就中止。

> ☁️ 产物别放 `~/Documents`：iCloud 会持续给 bundle 贴扩展属性，codesign 报 `detritus not allowed`。
> 构建采用「暂存目录里编译 + 签名，全部成功才替换线上那份」，编译失败不会让你手上没程序。

## ⚠️ 已知边界

- 🚮 没有沙盒、没有 App Store 版本、**没有自动更新**，升级要自己重新下载。
- 🖥️ Intel 支持来自交叉编译 + 通用二进制。作者机器是 Apple Silicon，x86_64 切片只在 Rosetta 下冒烟测过，没在真 Intel 机上跑完整 UI——遇到不对请开 issue。
- 🕶️ 卡片浮层展开时盖住整条菜单栏，此时状态栏图标点不到（<kbd>⌃⌥⌘M</kbd> 或 <kbd>Esc</kbd> 收起）。

## 💛 打赏

如果它帮你省下了找文件的时间，可以自愿打赏。不影响项目本身：不提供也不承诺任何付费支持或售后，
所有功能都已是完整形态，没有付费解锁。

<!-- 收款码：把你自己的真实码截图存成 docs/sponsor-wechat.png，再放开下面这行。
     码必须能扫到你自己的收款页，别用任何来路不明的图。 -->
<!-- <p align="center"><img src="docs/sponsor-wechat.png" width="220" alt="微信收款码"></p> -->

<details>
<summary>🌐 English</summary>

**DesktopMap** puts a directory map on your macOS wallpaper layer: each entry is a path, its measured
size, and a deletability marker. Clicking jumps to it in Finder — the app never deletes your files and
makes zero network requests. A Launchpad-style full-screen overlay (<kbd>⌃⌥⌘M</kbd>) gives you the whole
picture at a glance, with search, filters, drag-to-add and per-card detail. Native SwiftUI + AppKit,
built with `swiftc` only. Universal binary, macOS 13+, distributed as an ad-hoc signed `.dmg` / `.zip`.

</details>

<p align="center">
  发布于 <a href="https://github.com/tianZhen926/desktopmap/releases">Releases</a> ·
  <a href="LICENSE">MIT License</a> ·
  🤝 PR 欢迎，但不接受任何会删除用户文件的改动
</p>
