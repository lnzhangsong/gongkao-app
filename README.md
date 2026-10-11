# 考公台历 · gongkao-app

小米平板 / 安卓手机用的**全屏常亮台历 + 考试倒计时**，右半屏轮播考公内容（行测常识 /
高频成语 / 时政热词）；点按可切到**番茄工作法**（25/5/15，时长可配）并播放**背景白噪音**；
另有**AI 规划**（登录主站账号，读你的做题数据，生成可勾选备考清单）。基于 **Flutter**，
打成安卓 apk 安装到设备。

选型取「性能 × 跨端」两项（用户裁定）：Flutter 是性能接近原生、又能全平台跨端的唯一
同时满足者。完整对比见方案文档 §二。

实现分两阶段（见方案 §十）：**Phase 1** 纯离线（台历 / 番茄钟 / 背景音）；
**Phase 2** 联网（登录主站 + AI 规划）。

> 状态：**方案阶段，尚未开工**。先看 [`docs/平板台历方案.md`](docs/平板台历方案.md)。

## 与主站的关系

本仓**独立**，与 [`gongkao`](../gongkao)（读本 READBOOK 主站）**无关**：

- 不接入主仓 pnpm workspace，不参与其构建 / 部署 / 门禁。
- 内容以**镜像**方式取自 `gongkao/data/` 下的三份 JSON，见方案文档 §三。
- 主站怎么改都不影响本工程，反之亦然。

## 版权与用途

内置的常识 / 成语 / 时政内容**版权归各自权利人**，随本仓仅供**个人学习自用**，
**不单独分发、不商用**。与主仓 `gongkao/LICENSE` 末尾《数据与内容版权说明》同口径。

## 快速开始

（工程尚未创建；下列步骤在动工后生效，详见方案文档 §六。）

```bash
flutter create --org com.gongkao --project-name gongkao_pad .
flutter pub add wakelock_plus lunar audioplayers
node scripts/sync_data.mjs        # 从 ../gongkao/data/ 镜像内容
flutter run                       # 调试
flutter build apk --release       # 出 apk
```

## 常用改动

- **改考试日期 / 轮播间隔 / 番茄时长 / 断点阈值**：`lib/config.dart`
- **刷新内容**：重跑 `node scripts/sync_data.mjs`
- **补背景音素材**：把无缝循环的白噪音放进 `assets/audio/`，并在 `lib/config.dart` 登记
