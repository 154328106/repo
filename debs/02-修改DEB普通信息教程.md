# 在 NAS 上修改 DEB 信息

前提：你已经把 DEB 直接放进 NAS 的：

```text
/vol1/1000/Docker/Repo-Deb
```

下面不再包含上传和下载步骤。SSH 使用 root 或 admin 都可以。

## 1. 进入目录

SSH 登录后执行：

```bash
cd /vol1/1000/Docker/Repo-Deb
ls -lh *.deb
```

## 2. 填写原包、新版本和编辑目录

以下面这个原包为例：

```text
example.plugin_1.0_iphoneos-arm64e.deb
```

复制下面三行，并换成自己的文件名：

```bash
PKG_FILE='example.plugin_1.0_iphoneos-arm64e.deb'
EDIT_DIR='edit-example-plugin-01'
OUTPUT_FILE='example.plugin_1.0+repo1_iphoneos-arm64e.deb'
```

- `PKG_FILE`：原包文件名；
- `EDIT_DIR`：随便起一个从未使用过的新目录名；
- `OUTPUT_FILE`：修改后生成的新包，文件名里使用新版本。

确认原包存在：

```bash
ls -lh "$PKG_FILE"
```

## 3. 解包

不要提前创建 `EDIT_DIR`，直接执行：

```bash
docker run --rm \
  --user "$(id -u):$(id -g)" \
  -v "$PWD:/work" -w /work \
  debian:bookworm-slim \
  dpkg-deb -R "$PKG_FILE" "$EDIT_DIR"
```

如果提示 `DEBIAN: File exists`，说明这个编辑目录以前用过。重新设置一个新名字，再解包：

```bash
EDIT_DIR='edit-example-plugin-02'
```

## 4. 修改 control

打开包信息：

```bash
vi "$EDIT_DIR/DEBIAN/control"
```

vi 操作：按 `i` 开始编辑；完成后按 `Esc`，输入 `:wq`，再按回车保存。

通常只修改这些字段：

```text
Version: 1.0+repo1
Name: 插件显示名称
Maintainer: 无言以对
Author: 原作者名称
Icon: https://图片直链/icon.png
Description: 这里填写中文介绍和兼容信息。
```

注意：

- 内容改过后必须提高 `Version`；
- `Author` 保留真实原作者；
- 文件必须保存为 UTF-8；
- 不要随便修改 `Package`、`Architecture`、`Depends`、`Pre-Depends`；
- 不用修改 `Section`，推送时 BAT 会让你选择分类。

保存后看一遍：

```bash
sed -n '1,200p' "$EDIT_DIR/DEBIAN/control"
```

## 5. 重新打包

执行：

```bash
docker run --rm \
  --user "$(id -u):$(id -g)" \
  -v "$PWD:/work" -w /work \
  debian:bookworm-slim \
  dpkg-deb --root-owner-group --build "$EDIT_DIR" "$OUTPUT_FILE"
```

不要让 `OUTPUT_FILE` 与原包同名，也不要覆盖已经发布的同版本包。

## 6. 检查新包

```bash
docker run --rm \
  -v "$PWD:/work:ro" -w /work \
  debian:bookworm-slim \
  dpkg-deb --info "$OUTPUT_FILE"
```

重点检查：

- `Package` 没变；
- `Version` 是新版本；
- `Architecture` 和依赖没有丢失；
- 中文名称和描述没有乱码。

确认文件已经生成：

```bash
ls -lh "$OUTPUT_FILE"
```

## 7. 推送

先在手机上测试新包能否正常安装、使用和卸载。

确认正常后，在 Windows 双击 `一键推送插件.bat`，输入或拖入 NAS 共享文件夹，然后：

1. 选择刚生成的新 DEB；
2. 选择“依赖插件 / 美化插件 / 功能插件”；
3. 确认提交；
4. 等待 Actions 显示成功。

整个流程就是：

```text
DEB 已放入 NAS
→ SSH 进入 Repo-Deb
→ 解包
→ 修改 DEBIAN/control
→ 重新打包
→ 检查
→ 双击 BAT 推送并分类
```
