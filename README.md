# 桌面地图 DesktopMap

![release](https://img.shields.io/github/v/release/tianZhen926/desktopmap?label=release&color=0b7285)
![platform](https://img.shields.io/badge/macOS-13.0%2B-000000?logo=apple&logoColor=white)
![arch](https://img.shields.io/badge/arch-arm64%20%2B%20x86__64-informational)
![stack](https://img.shields.io/badge/stack-Swift%20%C2%B7%20SwiftUI%20%C2%B7%20AppKit-F05138?logo=swift&logoColor=white)
![network](https://img.shields.io/badge/network%20requests-0-brightgreen)
![license](https://img.shields.io/badge/license-MIT-green)

**把「哪个目录占地方、里面是什么、能不能删」做成一张贴在你桌面壁纸层、抬眼就能看到的地图。**

点一条就在访达里跳过去；想知道占多少，它自己去测；标了灰的就提醒你别手抖。
全局快捷键 ⌃⌥⌘M 可以随时拉出一屏启动台式的卡片浮层，收起来什么都没发生过。

## 三条硬约束

这三条不是特性，是设计边界。任何 PR 违反其中一条都会被拒。

1. **只跳转，不删除。**
   清单里的任何目录，程序只会用访达打开它——不写入、不移动、不删除、不改权限。
   代码里确实存在删除动作，但 `removeItem` 的全部 5 处目标都是它自己的数据文件（清单本体、日志截断、备份轮换），
   `trashItem` 零命中。对用户而言唯一带破坏性的动作是把某条从清单里移除，
   文件仍在原位，而且顶栏可以一步放回。
2. **零网络。**
   没有 URLSession、没有埋点、没有更新检查、没有崩溃上报，整个工程的 import 只有
   AppKit / SwiftUI / Combine / Foundation / Carbon / ServiceManagement / UniformTypeIdentifiers。
   上面那枚 `network requests 0` 的徽标不是装饰：源码里搜不到一处 http。
3. **改动可回溯。**
   每次保存前自动留一份清单快照（最多 15 份），跳转、编辑、撤卡片都写进行为日志。

## 快速开始

去 [Releases](https://github.com/tianZhen926/desktopmap/releases) 下载 `DesktopMap-<版本>.dmg`（推荐）或 `.zip`。
通用二进制，Apple Silicon 与 Intel 都支持，需要 macOS 13 及以上。

1. 打开 dmg，把 DesktopMap 拖进「应用程序」。
2. **第一次打开会被 Gatekeeper 拦。** 这个包只做 ad-hoc 自签，没有 Apple 开发者证书，也没有公证——
   纯本机工具换取零成本的代价。绕过方式二选一：右键 App → 打开 → 再点一次「打开」，或者：

   ```bash
   xattr -cr /Applications/DesktopMap.app
   ```

3. 下载后可以核对校验和（数值同时写在 Release 正文与 `SHA256SUMS.txt`）：

   ```bash
   shasum -a 256 ~/Downloads/DesktopMap-*.dmg
   ```

上手只要三步：装完在面板里点「添加文件夹」选一个你常有东西的目录 → 看它测出来的大小 →
双击卡片跳到访达。之后按自己的习惯分组、加备注。

## 界面

四个入口，职责互不重叠。

| 入口 | 定位 | 关键行为 |
| --- | --- | --- |
| **桌面面板** | 常驻看板 | 贴在壁纸/图标层，不抢焦点；可置顶或退回桌面层；可指定显示在哪块屏 |
| **控制台** | 管理后台 | 条目增删改、分组改名与并入、扫描大目录、导入子文件夹、层级与刷新设置、开机自启、备份恢复 |
| **状态栏** | 临时入口 | 菜单 + 磁盘剩余空间读数；卡片模式开着时左键直接开合浮层，右键出菜单 |
| **卡片浮层** | 全屏概览 | ⌃⌥⌘M 唤起，按分组成网格、带启动台式进出动画；搜索、只看可删、只看 1G 以上、拖入添加、ⓘ 详情条、✕ 撤卡片 |

浮层跟随鼠标所在的屏幕——在外接屏上干活时不用回头去够状态栏图标。

## 工作原理

- **大小测量**：`/usr/bin/du -sk`，最多 4 路并发，跳过已测过的路径，单目录有超时保护
  （防止卡在未挂载的软链目标或网络盘上）。系统禁止第三方统计的目录（废纸篓、部分沙盒容器）
  显示 `?`，这是系统限制，不是缺陷。
- **桌面层**：窗口层级取 `CGWindowLevelForKey(.desktopIconWindow)`。用普通 `.desktopWindow`
  会被 Finder 的壁纸/图标窗口盖住并吃掉所有点击；同时 hosting view 要放开 `acceptsFirstMouse`，
  否则第一次点击只激活 App、按钮不响应。
- **全局快捷键**：Carbon `RegisterEventHotKey`，不需要辅助功能权限，不会弹授权框。
- **浮层与系统面板的层级冲突**：浮层层级高于 `NSOpenPanel` 与 `NSMenu`，所以选文件夹必须先收浮层、
  选完再展开；浮层内不能用下拉菜单，要用平铺按钮。
- **清单结构**：一条 = 路径 + 名称 + 分组 + 备注 + 风险标记（可删 / 看清再动 / 别动）。
  分组是自由文本，可以直接敲一个新名字建立。

## 数据与隐私

```
~/Library/Application Support/DesktopMap/list.json      # 清单本体
~/Library/Application Support/DesktopMap/actions.log    # 行为日志
~/Library/Application Support/DesktopMap/backups/       # 每次保存前自动留，最多 15 份
```

偏好写在 `dev.fengtianzeng.desktopmap` 域（窗口位置、层级、卡片模式开关等）。
所有数据只落在你自己机器上。卸载 = 删掉 App + 上面这个目录，没有别处。

「恢复出厂清单」和「恢复到最近一份备份」都是先自动留一份当前快照、再二次确认才执行。

## 从源码构建

只需要 Command Line Tools（`xcrun --sdk macosx --show-sdk-path`），**没有 Xcode 工程**。

```bash
git clone https://github.com/tianZhen926/desktopmap.git
cd desktopmap
./build.sh                    # 本机架构，约 40 秒，产物 ~/Applications/DesktopMap.app
./release.sh                  # 发布用：通用二进制 + dmg + zip + 校验和 + 上线前隐私自检
```

`build.sh` 的三个开关：

| 变量 | 作用 |
| --- | --- |
| `DM_OUT` | 产物位置（默认 `~/Applications/DesktopMap.app`） |
| `DM_UNIVERSAL=1` | 同时编 arm64 与 x86_64 并合成通用二进制 |
| `DM_SEED=public` | 强制使用仓库里的通用示例种子清单 |

产物必须落在 iCloud 同步范围之外：`~/Documents` 里的 bundle 会被持续贴扩展属性，
codesign 报 `detritus not allowed`。构建采用「暂存目录里编译 + 签名，全部成功才替换线上那份」，
所以编译失败不会让你手上没程序。

**出厂种子**：仓库里的 `Resources/default_list.json` 是 18 条通用示例。
想让「恢复出厂清单」恢复成你自己整理的一份，放一个 `Resources/default_list.local.json` 即可——
`build.sh` 会优先用它，该文件已在 `.gitignore` 里，不会被提交。
对外发布只走 `release.sh`，它会强制 `DM_SEED=public`，并在打包前后各扫一遍私人路径，扫到就中止。

## 已知边界

- 需要 macOS 13 及以上。
- Intel 支持来自交叉编译 + 通用二进制。作者的机器是 Apple Silicon，x86_64 切片只在 Rosetta 下
  冒烟测过，没有在真 Intel 机器上跑完整 UI——遇到不对请开 issue。
- 没有沙盒、没有 App Store 版本、没有自动更新，升级要自己重新下载。
- 卡片浮层展开时会盖住整条菜单栏，此时状态栏图标点不到（用 ⌃⌥⌘M 或 Esc 收起来）。

## 许可

MIT，见 [LICENSE](LICENSE)。可商用、可闭源二次分发，保留版权声明即可。

## 打赏

如果它帮你省下了找文件的时间，可以自愿打赏。这不影响项目本身：
不提供、也不承诺任何付费支持或售后，所有功能都已是完整形态，没有付费解锁。

<!-- 收款码：把你自己的真实码截图存成 docs/sponsor-wechat.png，再放开下面这行。
     注意码必须能扫到你自己的收款页，别用任何来路不明的图。 -->
<!-- ![微信收款码](docs/sponsor-wechat.png) -->

## English

**DesktopMap** puts a directory map on your macOS desktop wallpaper layer: each entry is a path,
its measured size, and a deletability marker. Clicking jumps to it in Finder — the app never deletes
anything, and it makes zero network requests. A Launchpad-style full-screen card overlay
(<kbd>⌃</kbd><kbd>⌥</kbd><kbd>⌘</kbd><kbd>M</kbd>) gives you the whole picture at a glance, with search,
filters, drag-to-add, and per-card detail. Native SwiftUI + AppKit, built with `swiftc` only — no Xcode
project required. Universal binary, macOS 13+. Distributed as an ad-hoc signed `.dmg` / `.zip`.

## Contributing

Issue 和 PR 都欢迎。改动前后各跑一次 `./build.sh` 与 `--probe` 自检；
UI 相关改动请在说明里写清你在几块屏、什么 macOS 版本上验过。
本项目不接受任何会删除用户文件的改动。
