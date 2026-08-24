# 修改 DEB 的普通信息

这份教程只修改 DEB 中 `DEBIAN/control` 的普通元数据，例如名称、版本、作者、维护者、分类、图标和描述。它不会把原本不兼容 RootHide 的插件变成 RootHide 版本，也不负责修改插件功能或设置页面 UI。

以下步骤按当前环境编写：

- DEB 在 Windows：`D:\Claude\My project\repo\debs`；
- NAS 工作目录：`/vol1/1000/Docker/Repo-Deb`；
- NAS 已安装 Docker，并能运行 `debian:bookworm-slim`；
- Windows 已能通过 `admin@My-Nas` 连接 NAS。

## 一、哪些字段通常可以修改

`DEBIAN/control` 中常见字段的含义：

| 字段 | 用途 | 建议 |
| --- | --- | --- |
| `Name` | Sileo 中显示的软件名称 | 可以改成中文名称 |
| `Version` | 软件版本和升级判断依据 | 内容变化后必须提高版本 |
| `Maintainer` | 软件包维护者 | 可以写自己的名称，但不要冒充原作者 |
| `Author` | 原作者 | 应当保留真实作者信息 |
| `Sponsor` | 赞助者或来源展示 | 可删除或按实际情况填写 |
| `Section` | 软件分类 | 本仓库建议通过上传 BAT 分类，不必为此修改原包 |
| `Icon` | 软件包详情图标 URL | 可以换成长期有效的 HTTPS 图片地址 |
| `Description` | 软件包说明 | 可以补充中文说明和兼容信息 |

以下字段不要为了“看起来像 RootHide”而随便改：

| 字段 | 风险 |
| --- | --- |
| `Package` | 软件包唯一 ID；修改后会变成另一个包，并可能破坏升级、冲突和依赖关系 |
| `Architecture` | 改文字不会转换二进制架构；Rootless 包不能靠这里改成 RootHide |
| `Depends` / `Pre-Depends` | 修改错误会造成缺少依赖、无法安装或卸载异常 |
| `Conflicts` / `Replaces` / `Provides` | 会影响其他包的安装和替换关系 |
| 安装脚本 | `preinst`、`postinst`、`prerm`、`postrm` 能以高权限执行，除非完全理解，否则不要动 |

如果只是在 Sileo 里改变显示名称，应修改 `Name`，不要修改 `Package`。

如果只是想改变软件源里的分类，不需要解包。双击 `一键推送插件.bat`，选择 `依赖插件`、`美化插件` 或 `功能插件`；Actions 会在生成在线索引时覆盖 `Section`，原始 DEB 保持不变。

## 二、先保留原始文件

不要直接覆盖唯一的原包。原文件保留不动，新包使用新的版本号和文件名。

例如原文件：

```text
zhuti.example.mask_1.0_iphoneos-arm64e.deb
```

修改后输出：

```text
zhuti.example.mask_1.0+repo1_iphoneos-arm64e.deb
```

`+repo1` 表示在上游 `1.0` 的基础上做了第 1 次仓库元数据调整。下一次可以使用 `+repo2`。也可以沿用你已经使用的形式，例如 `1.5.37-Beta4-roothide`，但同一个包的版本格式最好始终一致。

## 三、把原包传到 NAS

如果文件还只在 Windows 上，打开 PowerShell，执行下面命令。把文件名替换成自己的实际文件名：

```powershell
& 'C:\Program Files\Git\usr\bin\scp.exe' `
    -i 'D:\Claude\My project\.ssh-nas-repo\id_ed25519' `
    -o IdentitiesOnly=yes `
    'D:\Claude\My project\repo\debs\zhuti.example.mask_1.0_iphoneos-arm64e.deb' `
    'admin@My-Nas:/vol1/1000/Docker/Repo-Deb/'
```

如果普通的 `scp` 已经能够直接连接 NAS，也可以简化为：

```powershell
scp 'D:\Claude\My project\repo\debs\zhuti.example.mask_1.0_iphoneos-arm64e.deb' `
    'admin@My-Nas:/vol1/1000/Docker/Repo-Deb/'
```

不要公开、复制或发送私钥文件的内容。

## 四、连接 NAS 并确认文件

在 PowerShell 中连接：

```powershell
ssh admin@My-Nas
```

进入工作目录：

```bash
cd /vol1/1000/Docker/Repo-Deb
ls -lh *.deb
```

先查看原包的基本信息：

```bash
docker run --rm \
  --user "$(id -u):$(id -g)" \
  -v "$PWD:/work" \
  -w /work \
  debian:bookworm-slim \
  dpkg-deb --info zhuti.example.mask_1.0_iphoneos-arm64e.deb
```

确认 `Package`、`Version`、`Architecture` 和依赖信息与预期一致。

## 五、解包

给每次操作使用一个全新的目录名，例如：

```bash
PKG_FILE='zhuti.example.mask_1.0_iphoneos-arm64e.deb'
EDIT_DIR='edit-zhuti-example-mask-repo1'
```

先确认目标目录不存在：

```bash
test ! -e "$EDIT_DIR" && echo '编辑目录可用' || echo '目录已存在，请换一个新的 EDIT_DIR'
```

只有看到“编辑目录可用”时才继续。不要提前执行 `mkdir "$EDIT_DIR"`，因为 `dpkg-deb -R` 会自己创建目录；提前创建或重复使用一个已经含有 `DEBIAN` 的目录，会出现：

```text
unexpected pre-existing pathname .../DEBIAN: File exists
```

执行解包：

```bash
docker run --rm \
  --user "$(id -u):$(id -g)" \
  -v "$PWD:/work" \
  -w /work \
  debian:bookworm-slim \
  dpkg-deb -R "$PKG_FILE" "$EDIT_DIR"
```

查看解包后的控制文件：

```bash
sed -n '1,200p' "$EDIT_DIR/DEBIAN/control"
```

同时检查有没有安装脚本：

```bash
find "$EDIT_DIR/DEBIAN" -maxdepth 1 -type f -printf '%f\n'
```

如果除了 `control`、`md5sums` 之外还有 `preinst`、`postinst`、`prerm` 或 `postrm`，说明这个包带有安装脚本。不要在不理解脚本内容的情况下继续重新发布。

## 六、修改 control

可以在 NAS 上用 `vi`：

```bash
vi "$EDIT_DIR/DEBIAN/control"
```

也可以通过 NAS 文件管理器打开该文件。保存编码必须是 **UTF-8 无 BOM**，不要使用会把中文保存成 ANSI/GBK 的编辑器。

一个简单示例：

```text
Package: zhuti.example.mask
Version: 1.0+repo1
Architecture: iphoneos-arm64e
Name: 示例立体遮罩
Section: 主题美化
Maintainer: 无言以对
Author: 原作者名称
Depends: com.spark.snowboard, com.spark.snowboard.masks
Icon: https://你的稳定地址/icon.png
Description: 适用于 RootHide 的 SnowBoard 遮罩主题。
```

修改时注意：

- 每一行格式都是 `字段名: 值`，冒号后要有空格；
- 不要在行尾添加无意义空格；
- `Version` 不能含空格；
- `Icon` 应是可以公开访问的 HTTPS 图片直链；
- `Author` 应保留原作者，`Maintainer` 才是当前维护或打包者；
- 不要删除原本必需的依赖；
- 如果只是改说明，也应提高版本号，避免缓存旧包。

多行 `Description` 的后续每一行必须以一个空格开头，空行要写成“一个空格加一个点”：

```text
Description: 第一行是简短说明
 这是第二行。
 .
 这是空行后的下一段。
```

## 七、重新打包

设定新包文件名：

```bash
OUTPUT_FILE='zhuti.example.mask_1.0+repo1_iphoneos-arm64e.deb'
```

确认这个输出文件还不存在，避免覆盖：

```bash
test ! -e "$OUTPUT_FILE" && echo '输出文件名可用' || echo '输出文件已存在，请换名或提高版本'
```

只有确认文件名可用后，再重新打包：

```bash
docker run --rm \
  --user "$(id -u):$(id -g)" \
  -v "$PWD:/work" \
  -w /work \
  debian:bookworm-slim \
  dpkg-deb --root-owner-group --build "$EDIT_DIR" "$OUTPUT_FILE"
```

`--root-owner-group` 会让归档内文件使用标准的 root 所有权，不要求以 NAS 的 root 用户进行打包。

## 八、验证新包

查看元数据：

```bash
docker run --rm \
  -v "$PWD:/work:ro" \
  -w /work \
  debian:bookworm-slim \
  dpkg-deb --info "$OUTPUT_FILE"
```

查看文件清单：

```bash
docker run --rm \
  -v "$PWD:/work:ro" \
  -w /work \
  debian:bookworm-slim \
  dpkg-deb --contents "$OUTPUT_FILE"
```

至少逐项核对：

- `Package` 没有被意外改掉；
- `Version` 是新的版本；
- `Architecture` 仍然正确；
- `Depends`、`Pre-Depends` 没有丢失；
- 中文 `Name` 和 `Description` 显示正常；
- 包内文件路径与原包一致；
- 新包能在测试设备上正常安装、启用和卸载。

还可以记录校验值：

```bash
sha256sum "$OUTPUT_FILE"
```

## 九、把新包下载回 Windows

退出 NAS：

```bash
exit
```

在 Windows PowerShell 执行：

```powershell
& 'C:\Program Files\Git\usr\bin\scp.exe' `
    -i 'D:\Claude\My project\.ssh-nas-repo\id_ed25519' `
    -o IdentitiesOnly=yes `
    'admin@My-Nas:/vol1/1000/Docker/Repo-Deb/zhuti.example.mask_1.0+repo1_iphoneos-arm64e.deb' `
    'D:\Claude\My project\repo\debs\'
```

确认文件已经回来：

```powershell
Get-Item 'D:\Claude\My project\repo\debs\zhuti.example.mask_1.0+repo1_iphoneos-arm64e.deb'
Get-FileHash 'D:\Claude\My project\repo\debs\zhuti.example.mask_1.0+repo1_iphoneos-arm64e.deb' -Algorithm SHA256
```

接下来按照 [01-推送软件包教程.md](01-推送软件包教程.md) 提交和推送。

## 十、关于 plist、设置页标题和中文问号

`DEBIAN/control` 只控制软件源里显示的包信息。插件设置页面里的标题、按钮或 `label` 通常位于 payload 中的 `.plist`、`.strings` 或二进制文件里，不属于普通包信息。

如果把 plist 中的中文改完后在手机上显示成 `????`，常见原因包括：

- 原文件是二进制 plist，却被普通文本编辑器直接保存；
- 保存成了 ANSI/GBK，而不是 UTF-8；
- plist 语法被破坏；
- UI 实际读取的是另一个本地化文件，而不是改过的那个文件。

因此不要把二进制 plist 当普通文本编辑。修改 UI 文件前，应先判断它是 XML plist、二进制 plist还是本地化字符串文件，再使用对应工具转换、修改和校验。这类修改应单独测试，不要和一次普通 `control` 信息调整混在一起。

## 最后检查清单

- [ ] 原始 DEB 仍然保留；
- [ ] 新包使用了新的 `Version` 和文件名；
- [ ] 没有冒充原作者或删除来源信息；
- [ ] 没有随意改 `Package`、架构、依赖和安装脚本；
- [ ] `control` 是 UTF-8，无中文乱码；
- [ ] `dpkg-deb --info` 和 `dpkg-deb --contents` 均成功；
- [ ] 已在测试设备验证安装、使用和卸载；
- [ ] 已确认拥有公开再分发权限。
