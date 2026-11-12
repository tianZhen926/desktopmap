# 桌面地图 DesktopMap

把「哪些目录占地方、里面是什么、能不能删」这件事，做成本机上一张随手可看的地图。

macOS 原生小程序：SwiftUI + AppKit，一个窗口贴在桌面壁纸那一层，列你自己的目录；
想看全局时用 ⌃⌥⌘M 唤起全屏卡片浮层。**不联网、不上传、不删除任何文件。**

<!-- 截图自己补：把图放进 docs/ 后加一行 ![](docs/screenshot-cards.png)。没有图就先别加，README 会显示裂图。 -->

## 它解决什么

系统设置里那个「储存空间」只告诉你每一大类占了多少，然后就没有了。
你想知道的其实是：

- 哪个目录真的占地方；
- 这目录是缓存（能删）还是数据（别碰）；
- 点一下能不能直接跳过去看。

桌面地图把这三件事拼在一起：一条 = 一个目录 + 一句备注 + 一个风险标记 + 实时大小。

## 三条硬约束

1. **只跳转，不删除。** 所有按钮只有一种破坏性：从清单里移除这条可视化——文件还在原位，而且能一步撤回。删文件请自己去访达。
2. **不联网。** 没有网络请求，没有埋点，没有更新检查。`NSHumanReadableCopyright` 里就写着这句。
3. **改动有记录。** 每次增删改、跳转、撤卡片都会写进行为日志，出问题能回溯。

## 三个入口

| 入口 | 干什么 |
| --- | --- |
| 桌面面板 | 贴在壁纸/图标层，不抢焦点，平时当背景看板用；可置顶或退回桌面层 |
| 控制台 | 管条目、管分组（改名、并入）、看设置、开备份文件夹、恢复 |
| 状态栏 | 菜单 + 磁盘剩余空间；卡片模式开着时左键直接开合浮层，右键出菜单 |
| 卡片模式 | 全屏浮层，按分组成网格，带 Launchpad 式进出动画；支持拖入、搜索、筛选、详情条 |

## 用法

```bash
git clone https://github.com/tianZhen926/desktopmap.git
cd desktopmap
./build.sh
open ~/Applications/DesktopMap.app
```

需要 Command Line Tools（`xcode-select --install`），**不需要 Xcode 工程**。
产物固定落在 `~/Applications/DesktopMap.app`——不要放进 `~/Documents`，iCloud 同步会持续给 bundle
贴扩展属性，codesign 会报 `detritus not allowed`。

自检：

```bash
~/Applications/DesktopMap.app/Contents/MacOS/DesktopMap --dump    # 条目/屏幕/层级/菜单
~/Applications/DesktopMap.app/Contents/MacOS/DesktopMap --probe   # 窗口与控件数量
```

首次打开被 Gatekeeper 拦住（这是 ad-hoc 自签，没有开发者证书）：

```bash
xattr -cr ~/Applications/DesktopMap.app
```

### 把自己的一份清单当出厂种子（可选）

仓库里的 `Resources/default_list.json` 是通用示例。如果你想让「恢复出厂清单」恢复成
自己整理的那份，放一个 `Resources/default_list.local.json` 就行——`build.sh` 会优先用它，
这个文件已在 `.gitignore` 里，不会被提交出去。

## 你的数据存在哪

```
~/Library/Application Support/DesktopMap/list.json    # 清单本体
~/Library/Application Support/DesktopMap/actions.log  # 行为日志
~/Library/Application Support/DesktopMap/backups/     # 每次保存前自动留一份，最多 15 份
```

偏好写在 `dev.fengtianzeng.desktopmap` 域里（窗口位置、是否贴桌面、卡片模式开关等）。
「恢复出厂清单」会先把当前清单备份成 `-beforeFactory` 再覆盖，且必须二次确认。

## 大小是怎么统计的

`/usr/bin/du -sk`，最多 4 路并发，跳过已经测过的路径，单目录超时会被掐掉（防止卡在挂载点/网络盘）。
系统禁止访问的目录（废纸篓、部分沙盒容器）显示 `?`——这是系统限制，不是 bug。

## 已知边界

- 需要 macOS 13+。
- 全局快捷键走 Carbon `RegisterEventHotKey`，不需要辅助功能权限。
- 卡片浮层的层级高于系统面板，所以文件选择器/菜单必须等浮层收起后才能弹出来（代码里为此做了 hide→picker→reopen）。
- 没有沙盒、没有 App Store 版本，纯本机自用工具。

## 许可

MIT，见 [LICENSE](LICENSE)。你可以商用、闭源二次分发，保留版权声明即可。

## 打赏

如果这东西帮你省了找文件的时间，可以自愿打赏——完全不影响项目本身：
不提供、也不承诺任何付费支持或售后，所有功能现在都是完整的，没有付费解锁。

<!-- 收款码：把你自己的真实码截图存成 docs/sponsor-wechat.png，再放开下面这行。
     注意码要能扫出你自己的收款页，别用任何来路不明的图。 -->
<!-- ![微信收款码](docs/sponsor-wechat.png) -->

不想放图的话，用 GitHub Sponsors 或爱发电的链接也一样，写在上面这段之后即可。

## Contributing

Issue 和 PR 都欢迎。改代码前请先跑一遍 `./build.sh` 和 `--probe`，
UI 相关的改动请说明你在几块屏、什么 macOS 版本上验过。
