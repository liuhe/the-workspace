# Release process

tasker 走 **GitHub Actions + git tag** 的方式发版；tag 推上去 CI 自动 build、打包、发 Release。

## 一次发版

1. 本地验证一遍：`cd app/tasker && swift build && swift run taskerCheck`
2. 打 tag 并推：

   ```bash
   git tag v0.1.0
   git push origin v0.1.0
   ```

3. GitHub → Actions 页看 "Release" workflow 跑完（约 5 分钟）
4. Releases 页面出现 `v0.1.0`，附件 `tasker-0.1.0.zip`

要试 workflow 不发正式版：Actions 页面手动触发 `Release` workflow，填个 version 号，产物走 artifact 而不是 Release。

## Workflow 干了什么

`.github/workflows/release.yml` 步骤：

1. 用 `macos-14` runner（自带 Xcode + Swift）
2. `swift build -c release --arch arm64 --arch x86_64` → 一份 **universal binary**（同时含 arm64 + x86_64 slice）
3. `lipo -verify_arch` 校验两个架构都在
4. `scripts/make-icon.sh` → 用 `iconGen` target 渲染 10 张尺寸 PNG → `iconutil` 打成 `AppIcon.icns`
5. `scripts/make-app-bundle.sh <ver>` → 打成 `dist/tasker.app`（Contents/{MacOS/tasker, Info.plist, Resources/AppIcon.icns}）
6. `zip -yr` 打包（保 symlink），上传到 Release

## 用户装法（README 会引用）

1. 从 Releases 下 `tasker-<ver>.zip`
2. 解压得到 `tasker.app`，拖进 `/Applications`
3. **首次打开**：右键点 app → **打开** → 弹窗确认
   - 因为没做 Apple 代码签名，Gatekeeper 会拦。这一步只做一次。
   - 或跑一次 `xattr -d com.apple.quarantine /Applications/tasker.app` 后双击。

## 已知限制

- **没签名 / 没公证**：需 Apple Developer 账号（$99/年）+ `codesign` + `notarytool`。目前免费方案就是让用户走 Gatekeeper bypass。
- **数据目录**默认 `~/Documents/tasker/`，可在 app Settings 里改。首次运行会自动创建。
- **最低系统**：macOS 14（Package.swift 里 `.macOS(.v14)`）。改老系统会跟 SwiftUI/AppKit 用的新 API 冲突，得下调 API 用法才能降 target。

## 图标

- 图标绘制在 `Sources/TaskerIcon/AppIcon.swift`，运行时（dock 图标）和发版打包（Finder 里的 app 图标）用同一份代码。
- 改颜色/形状后，本地跑 `bash scripts/make-icon.sh` 可预览生成 `AppIcon.icns`。
- 想彻底换设计，改 `AppIcon.generate(size:)` 即可，两处会同步。
