# Tonic

Tonic 是一个专注于即时使用的 iPhone 调音器和节拍器，使用 SwiftUI 与 AVFoundation 构建。

## 功能

- 实时音高检测与音分偏差显示
- A4 = 432 / 440 / 442 Hz 参考音高
- 40-240 BPM 节拍器
- 2/4、3/4、4/4、6/8 拍号
- 音频中断、路由变化和麦克风权限恢复
- 简体中文与 English 本地化
- Dynamic Type、VoiceOver、Reduce Motion 和高对比度支持

## 开发

使用 Xcode 27 或更高版本打开 `ToneTuner.xcodeproj`。项目最低支持 iOS 17。

运行测试：

```sh
xcodebuild test \\
  -project ToneTuner.xcodeproj \\
  -scheme 'Tone Tuner' \\
  -destination 'generic/platform=iOS Simulator' \\
  CODE_SIGNING_ALLOWED=NO
```

真机使用调音器时，需要在系统设置中允许麦克风访问。

## 许可证

[MIT](LICENSE)
