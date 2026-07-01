# NoSleep 安装指引

## 可以直接分享给别人安装吗？

可以，但当前这个版本是本地构建的未签名 app，不是经过 Apple Developer ID 签名和公证的正式发行包。

这意味着别人拿到 `NoSleep.app` 后可以安装使用，但第一次打开时 macOS 可能会提示“无法验证开发者”或阻止打开。按下面步骤允许一次即可。

## 安装步骤

1. 打开 `NoSleep.dmg`。
2. 把 `NoSleep.app` 拖到右侧的“Applications / 应用程序”文件夹。
3. 在“应用程序”里打开 `NoSleep.app`。
4. 第一次打开时，如果 macOS 阻止运行：
   - 打开“系统设置”
   - 进入“隐私与安全性”
   - 找到 NoSleep 被拦截的提示
   - 点击“仍要打开”
5. 重新打开 `NoSleep.app`。
6. 菜单栏会出现 NoSleep 图标。
7. 第一次打开会弹出“NoSleep 初始设置”。
8. 点击“开始授权”，输入一次管理员密码。

完成后，NoSleep 就可以免密切换“合盖后继续工作”。

## 如果提示“文件已损坏”

这通常不是文件真的损坏，而是 macOS 对未公证 app 的 Gatekeeper 拦截。

临时解决方式：

1. 先把 `NoSleep.app` 拖到“应用程序”文件夹。
2. 打开“终端”。
3. 执行：

```sh
xattr -cr /Applications/NoSleep.app
```

4. 再打开 `NoSleep.app`。

如果仍然打不开，再到“系统设置 > 隐私与安全性”里点击“仍要打开”。

## 菜单栏状态

- 正常休眠
- 保持清醒
- 合盖继续工作

## 使用建议

- 合盖后继续工作时，建议连接电源。
- 不要把正在运行的 MacBook 放进包里或密闭空间。
- 退出 NoSleep 时，会恢复 app 启动前的休眠状态。

## 更正式的分发方式

当前已经提供 DMG 拖拽安装包。如果要进一步减少 macOS 安全提示，后续最好做：

- Apple Developer ID 签名
- notarization 公证
- DMG 签名

那样 macOS 安全提示会少很多，更适合公开分享。
