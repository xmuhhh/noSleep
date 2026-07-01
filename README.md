# NoSleep

一个让 Mac 保持清醒的菜单栏小工具。

## 功能

- 保持 Mac 清醒，避免闲置后自动休眠。
- 开启合盖后继续工作，让 Codex 等后台任务在 MacBook 合盖后继续运行。
- 退出 NoSleep 时，恢复应用启动前的休眠状态。
- 菜单栏只显示状态图标。
- 下拉菜单采用三态选择：正常休眠、保持清醒、合盖继续工作。
- 第一次打开时引导安装免密授权，之后修改合盖设置不再重复输入管理员密码。

## 构建

```sh
swift build
```

## 生成应用

```sh
./scripts/package-app.sh
```

应用会生成到：

```text
build/NoSleep.app
```

## 生成 DMG 安装包

```sh
./scripts/package-dmg.sh
```

安装包会生成到：

```text
dist/NoSleep.dmg
```

## 说明

合盖模式会修改系统电源设置。第一次打开 NoSleep 时，应用会引导用户安装免密授权，并写入一条受限的 sudoers 规则，只允许当前用户免密执行以下两个命令：

```text
/usr/bin/pmset -a disablesleep 0
/usr/bin/pmset -a disablesleep 1
```

安装后，开启、关闭和退出时恢复合盖设置都不需要再输入管理员密码。

建议插电使用，并保持 Mac 散热良好。

## 给别人安装

见 [INSTALL.md](INSTALL.md)。

如果别人打开时提示“文件已损坏”，这通常是未公证 app 被 Gatekeeper 拦截。处理方式也写在 [INSTALL.md](INSTALL.md) 里。
