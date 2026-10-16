import 'dart:async';
import 'dart:ui' show Size;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// 一次抬头事件记录。
class HeadUpEvent {
  const HeadUpEvent({required this.index, required this.at, this.gapMillis});

  /// 第几次（从 1 计）。
  final int index;

  /// 发生时刻。
  final DateTime at;

  /// 与上一次抬头的间隔；第一次为 null。
  final int? gapMillis;
}

/// 抬头检测与计次。
/// 前置摄像头低分辨率取流，按固定间隔抽帧给 ML Kit，取人脸俯仰角 pitch。
/// 以「校准基准角 + 阈值」判定抬头，仅在上穿阈值时计一次（带回滞防抖）。
/// 帧只在内存中分析，不落盘、不外传。
class FacePitchMonitor {
  FacePitchMonitor();

  FaceDetector? _detector;
  CameraController? _cam;

  /// 抽帧间隔：约 350ms 一帧，兼顾响应与发热。
  static const Duration _sampleEvery = Duration(milliseconds: 350);
  DateTime _lastSample = DateTime.fromMillisecondsSinceEpoch(0);
  bool _busy = false;

  /// 连续未检出人脸的帧数；单帧丢失不立即退出抬头态，避免抖动误判。
  int _missStreak = 0;
  static const int _missToClear = 3;

  /// 正在启动中（相机初始化是异步的，期间 running 仍为 false），
  /// 用于避免重复并发启动。
  bool _starting = false;

  bool get running => _cam?.value.isInitialized ?? false;

  /// 是否已启动或正在启动。
  bool get active => _starting || running;

  /// 最近一帧是否检出人脸。
  final ValueNotifier<bool> faceFound = ValueNotifier<bool>(false);

  /// 最近一帧俯仰角（度）；null 表示未检出。
  final ValueNotifier<double?> pitch = ValueNotifier<double?>(null);

  /// 低头基准角（校准得到）。null 表示尚未校准。
  final ValueNotifier<double?> baseline = ValueNotifier<double?>(null);

  /// 抬头判定阈值：相对基准角的抬升量（度）。可调。
  final ValueNotifier<double> thresholdDelta = ValueNotifier<double>(2);

  /// 回滞：低于「阈值 - 滞回」才认为回到非抬头，避免抖动重复计数。
  /// 需小于动作幅度，否则无法回落到非抬头态。
  static const double _hysteresis = 1;

  /// 当前是否处于抬头状态。
  final ValueNotifier<bool> headUp = ValueNotifier<bool>(false);

  /// 抬头次数（本次会话累计）。
  final ValueNotifier<int> count = ValueNotifier<int>(0);

  /// 抬头事件列表（最新在前）。
  final ValueNotifier<List<HeadUpEvent>> events =
      ValueNotifier<List<HeadUpEvent>>(<HeadUpEvent>[]);

  DateTime? _lastEventAt;

  /// 首次上穿阈值的时刻；需连续保持抬头到 [holdDuration] 才计次。
  DateTime? _risingSince;

  /// 需连续保持抬头多久才计一次（去抖，避免瞬时抖动误计）。由设置注入。
  Duration holdDuration = const Duration(seconds: 2);

  /// 每次抬头计数的回调（用于外部持久化）。参数为时刻与与上次的间隔。
  void Function(DateTime at, int? gapMillis)? onHeadUp;

  Future<bool> start() async {
    if (_starting) return false;
    if (running) return true;
    _starting = true;
    try {
      final List<CameraDescription> cameras = await availableCameras();
      if (cameras.isEmpty) return false;
      final CameraDescription front = cameras.firstWhere(
        (CameraDescription c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      final CameraController cam = CameraController(
        front,
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );
      await cam.initialize();
      _cam = cam;

      _detector = FaceDetector(
        options: FaceDetectorOptions(
          performanceMode: FaceDetectorMode.fast,
          enableTracking: false,
        ),
      );

      cam.startImageStream(_onFrame);
      return true;
    } catch (_) {
      return false;
    } finally {
      _starting = false;
    }
  }

  Future<void> stop() async {
    final CameraController? cam = _cam;
    _cam = null;
    if (cam != null) {
      try {
        if (cam.value.isStreamingImages) await cam.stopImageStream();
      } catch (_) {}
      await cam.dispose();
    }
    await _detector?.close();
    _detector = null;
    faceFound.value = false;
    pitch.value = null;
    headUp.value = false;
    _risingSince = null;
  }

  /// 独立采样：临时开相机，采集约 [duration] 内的多帧人脸俯仰角并取平均。
  /// 若相机本就未运行，采样结束后自动关闭；返回值 null 表示未采到人脸。
  Future<double?> sampleAvg({
    Duration duration = const Duration(milliseconds: 1200),
  }) async {
    final bool startedHere = !active;
    if (startedHere) {
      final bool ok = await start();
      if (!ok) return null;
    }
    final List<double> samples = <double>[];
    final DateTime end = DateTime.now().add(duration);
    while (DateTime.now().isBefore(end)) {
      final double? p = pitch.value;
      if (p != null) samples.add(p);
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    if (startedHere) await stop();
    if (samples.isEmpty) return null;
    final double sum = samples.fold(0, (double a, double b) => a + b);
    return sum / samples.length;
  }

  void resetCount() {
    count.value = 0;
    events.value = <HeadUpEvent>[];
    headUp.value = false;
    _lastEventAt = null;
    _risingSince = null;
  }

  Future<void> _onFrame(CameraImage image) async {
    final CameraController? cam = _cam;
    final FaceDetector? det = _detector;
    if (cam == null || det == null) return;
    final DateTime now = DateTime.now();
    if (now.difference(_lastSample) < _sampleEvery) return;
    if (_busy) return;
    _lastSample = now;
    _busy = true;
    try {
      final InputImage? input = _toInputImage(image, cam.description);
      if (input == null) return;
      final List<Face> faces = await det.processImage(input);
      if (faces.isEmpty) {
        _missStreak++;
        faceFound.value = false;
        pitch.value = null;
        // 连续多帧检不到才退出抬头态，单帧丢失忽略。
        if (_missStreak >= _missToClear) headUp.value = false;
        return;
      }
      _missStreak = 0;
      faceFound.value = true;
      final double? p = faces.first.headEulerAngleX;
      pitch.value = p;
      if (p != null) _evaluate(p);
    } catch (_) {
      // 单帧失败忽略，不影响后续抽帧。
    } finally {
      _busy = false;
    }
  }

  /// 依据基准角与阈值判定抬头；需连续保持抬头达 [holdDuration] 才计一次。
  void _evaluate(double p) {
    final double? base = baseline.value;
    if (base == null) return; // 未校准不计。
    final double delta = thresholdDelta.value;
    final double upLine = base + delta;
    final double downLine = base + delta - _hysteresis;
    final DateTime now = DateTime.now();
    if (p >= upLine) {
      // 进入/保持抬头态：从首次上穿起计时，满 holdDuration 才计。
      _risingSince ??= now;
      if (!headUp.value &&
          now.difference(_risingSince!) >= holdDuration) {
        headUp.value = true;
        _record();
      }
    } else if (p <= downLine) {
      // 掉回低头：作废本次，重新等待。
      if (headUp.value) headUp.value = false;
      _risingSince = null;
    }
    // 中间区（回滞带内）保持现状，避免抖动。
  }

  void _record() {
    final DateTime now = DateTime.now();
    final int idx = count.value + 1;
    count.value = idx;
    final int? gap =
        _lastEventAt == null ? null : now.difference(_lastEventAt!).inMilliseconds;
    _lastEventAt = now;
    events.value = <HeadUpEvent>[
      HeadUpEvent(index: idx, at: now, gapMillis: gap),
      ...events.value,
    ];
    onHeadUp?.call(now, gap);
  }

  /// 把 nv21 的 CameraImage 转成 ML Kit 的 InputImage。
  InputImage? _toInputImage(CameraImage image, CameraDescription desc) {
    final Uint8List bytes;
    if (image.planes.length == 1) {
      bytes = image.planes[0].bytes;
    } else if (image.planes.length >= 3) {
      final Uint8List y = image.planes[0].bytes;
      final Uint8List u = image.planes[1].bytes;
      final Uint8List v = image.planes[2].bytes;
      final Uint8List nv21 = Uint8List(y.length + u.length + v.length);
      nv21.setRange(0, y.length, y);
      // nv21 要求 VU 交错；camera 插件给的 planes[1]=U, planes[2]=V。
      int idx = y.length;
      for (int i = 0; i < u.length; i++) {
        nv21[idx++] = v[i];
        nv21[idx++] = u[i];
      }
      bytes = nv21;
    } else {
      return null;
    }

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: _rotation(desc.sensorOrientation),
        format: InputImageFormat.nv21,
        bytesPerRow: image.planes[0].bytesPerRow,
      ),
    );
  }

  InputImageRotation _rotation(int sensorOrientation) {
    switch (sensorOrientation) {
      case 90:
        return InputImageRotation.rotation90deg;
      case 180:
        return InputImageRotation.rotation180deg;
      case 270:
        return InputImageRotation.rotation270deg;
      default:
        return InputImageRotation.rotation0deg;
    }
  }

  void dispose() {
    unawaited(stop());
    faceFound.dispose();
    pitch.dispose();
    baseline.dispose();
    thresholdDelta.dispose();
    headUp.dispose();
    count.dispose();
    events.dispose();
  }
}
