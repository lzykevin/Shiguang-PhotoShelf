# 拾光 PhotoShelf

一款 Swift 原生的 macOS 本地照片管理应用。让个人照片值得回看、容易整理、随时找得到。

**拾光 1.0 正式版** · macOS 14+ · Apple Silicon 与 Intel

## 功能

- 关联多个本地文件夹、增量扫描、离线缩略图浏览；原片留在原位置。
- 多种照片布局，日期／月份分组，沉浸式全屏、滚轮缩放、自动播放和多张照片对比。
- 0–5 星评分、爱心收藏、相册、标签、备注；批量整理及撤销／重做。
- 搜索文件名、标签、备注和相册；日期与标签高级筛选、一步多星级筛选、智能相册。
- 拍摄日期、添加日期、文件名及星级双向排序。
- 导出原片副本、系统分享、整理数据备份与恢复。
- Sparkle 应用内更新：菜单“检查更新…”，设置中可开启自动检查。

静态照片格式由 macOS ImageIO 解码，包括常见 JPEG、HEIC、PNG、TIFF 及系统支持的 RAW。暂不管理视频和 Live Photo 动态部分；云同步、AI 搜图及人物整理尚未实现。

## 内置示例图库

首次打开可点击“先用示例照片体验”，离线载入 11 张风景照片、旅行精选相册、风景／天空标签，以及现有示例评分和收藏。示例复制到应用自己的数据目录，载入不覆盖已有照片或相册；重复载入不重置整理信息。移除示例来源后可再次载入，恢复原有整理。

照片来源与授权见 [示例素材说明](Sources/PhotoShelf/Resources/Samples/CREDITS.md)。不包含本机路径、文件夹授权、浏览记录或测试备注。

## 安装与更新

从 [GitHub Releases](https://github.com/lzykevin/PhotoShelf/releases/latest) 下载 `PhotoShelf-1.0.0.zip`，解压后将应用拖入“应用程序”。

在“拾光 → 检查更新…”查看新版本，也可以在设置中开启自动检查。更新检查不上传照片或整理数据。

## 构建与测试

需要完整 Xcode、Python 3、macOS 14+。首次构建需联网下载 Sparkle 2.10.1（固定版本及校验和由 Swift Package Manager 验证）。

```sh
swift test
./scripts/build.sh
```

应用生成于 `build/Build/Products/Release/PhotoShelf.app`。工程由 Python 脚本生成，不需额外安装 XcodeGen。Swift Package 用于测试，不是可分发的沙箱应用包。

```sh
./scripts/package-release.sh
```

生成发布 ZIP；维护者的打包、签名和更新发布步骤见 [发布说明](docs/publishing.md)。

## 本地数据

整理信息独立存储，默认目录：

```
~/Library/Containers/com.photoshelf.local/Data/Library/Application Support/PhotoShelf/
```

应用不自动移动、删除或覆盖原片。**用户明确触发的文件夹重命名会同步修改本地目录**。从相册移除照片不删除文件。整理数据备份不包含原片；恢复前会自动备份当前整理数据，恢复后可能需要重新授权照片来源。

## 常用快捷键

| 操作 | 快捷键 |
|---|---|
| 评分／清除评分 | 1–5／0 |
| 收藏 | F |
| 对比所选照片 | D |
| 看图／退出大图 | 空格／Esc |
| 大图前后切换 | ←／→ |
| 多选／连续选择 | ⌘点击／⇧点击 |
| 搜索 | ⌘F |
| 撤销／重做 | ⌘Z／⇧⌘Z |

文字输入期间不会误触照片快捷键。

## 参与及许可

欢迎通过 Issues 反馈问题。请去除截图和日志中的私人照片与路径。开发指南见 [CONTRIBUTING.md](CONTRIBUTING.md)。

代码使用 [MIT 许可证](LICENSE)，依赖与素材说明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。个人照片、数据库、缓存及本地验收记录不包含在仓库中。

### 移除来源与恢复关联

移除来源只隐藏该来源并停止扫描，完整保留照片记录、评分、标签、备注、收藏、浏览记录及相册关联。重新添加同一路径会复用原来源；路径改变时，可在图库设置中对“已移除”来源使用“重新关联”。移除前仍自动备份，备份失败不会移除。旧版本已经删除的整理记录需从当时备份恢复。
