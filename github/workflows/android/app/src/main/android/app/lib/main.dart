import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:sensors_plus/sensors_plus.dart';

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    cameras = await availableCameras();
  } catch (e) {
    debugPrint("Kamera başlatılamadı: $e");
  }
  runApp(const LightMeterApp());
}

class LightMeterApp extends StatelessWidget {
  const LightMeterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Pozometre',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
      ),
      home: const CameraMeterScreen(),
    );
  }
}

class CameraMeterScreen extends StatefulWidget {
  const CameraMeterScreen({super.key});

  @override
  State<CameraMeterScreen> createState() => _CameraMeterScreenState();
}

class _CameraMeterScreenState extends State<CameraMeterScreen> {
  CameraController? _controller;
  bool _isCameraReady = false;

  // Pozometre Ayarları
  double _targetAperture = 2.8;
  int _targetIso = 100;
  double _calculatedEV = 12.0;
  String _calculatedShutter = "1/125";

  // Kompozisyon & Eğim (Ufuk Çizgisi)
  double _rollAngle = 0.0;
  bool _showRuleOfThirds = true;

  @override
  void initState() {
    super.initState();
    _initCamera();
    _initSensors();
  }

  Future<void> _initCamera() async {
    if (cameras.isEmpty) return;
    _controller = CameraController(
      cameras[0],
      ResolutionPreset.medium,
      enableAudio: false,
    );

    try {
      await _controller!.initialize();
      if (!mounted) return;
      setState(() => _isCameraReady = true);

      // Simüle edilen parlaklık taraması (Canlı ışık ölçümü)
      _startExposureMonitoring();
    } catch (e) {
      debugPrint("Kamera hatası: $e");
    }
  }

  void _initSensors() {
    accelerometerEventStream().listen((AccelerometerEvent event) {
      if (!mounted) return;
      // Yatay eğim açısını (Roll) hesapla
      double angle = math.atan2(event.x, event.y) * (180 / math.pi);
      setState(() {
        _rollAngle = angle - 90; // Telefon dik/yatay dengesi
      });
    });
  }

  void _startExposureMonitoring() {
    // 1 saniyede bir pozlamayı güncelle
    Stream.periodic(const Duration(seconds: 1)).listen((_) {
      if (!mounted || !_isCameraReady) return;
      _recalculateExposure();
    });
  }

  void _recalculateExposure() {
    // EV Formülü: EV = log2(N^2 / t)
    // t (Enstantane) = N^2 / 2^(EV)
    double ev = 10.0 + (math.Random().nextDouble() * 4.0); // Örnek EV aralığı (10-14 EV)
    double shutterSeconds = math.pow(_targetAperture, 2) / math.pow(2, ev);
    
    // ISO Dengeleme
    shutterSeconds = shutterSeconds * (100 / _targetIso);

    String shutterDisplay;
    if (shutterSeconds >= 1) {
      shutterDisplay = "${shutterSeconds.toStringAsFixed(1)}s";
    } else {
      int denominator = (1 / shutterSeconds).round();
      shutterDisplay = "1/$denominator";
    }

    setState(() {
      _calculatedEV = double.parse(ev.toStringAsFixed(1));
      _calculatedShutter = shutterDisplay;
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isCameraReady || _controller == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Colors.amber)),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          // 1. Canlı Kamera Akışı
          Center(
            child: CameraPreview(_controller!),
          ),

          // 2. 1/3 Kuralı Izgarası (Kompozisyon Kılavuzu)
          if (_showRuleOfThirds)
            CustomPaint(
              size: Size.infinite,
              painter: RuleOfThirdsPainter(),
            ),

          // 3. Canlı Ufuk Çizgisi Göstergesi
          Center(
            child: Transform.rotate(
              angle: -_rollAngle * (math.pi / 180),
              child: Container(
                width: 140,
                height: 2,
                color: (_rollAngle.abs() < 1.5) ? Colors.greenAccent : Colors.redAccent.withOpacity(0.7),
              ),
            ),
          ),

          // 4. Pozometre Bilgi Paneli (Üst Katman)
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.75),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildMetric("EV", _calculatedEV.toString()),
                    _buildMetric("DİYAFRAM", "f/${_targetAperture.toString()}"),
                    _buildMetric("ENSTANTANE", _calculatedShutter),
                    _buildMetric("ISO", "$_targetIso"),
                  ],
                ),
              ),
            ),
          ),

          // 5. Kompozisyon AI Durum & Ayar Çubuğu (Alt Katman)
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              padding: const EdgeInsets.all(16),
              color: Colors.black.withOpacity(0.8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _rollAngle.abs() < 1.5 ? "Denge: Mükemmel (0°)" : "Ufuk Eğik: ${_rollAngle.toStringAsFixed(1)}°",
                        style: TextStyle(
                          color: _rollAngle.abs() < 1.5 ? Colors.greenAccent : Colors.orangeAccent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          _showRuleOfThirds ? Icons.grid_on : Icons.grid_off,
                          color: Colors.white,
                        ),
                        onPressed: () {
                          setState(() => _showRuleOfThirds = !_showRuleOfThirds);
                        },
                      )
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text("f/ Değeri: ", style: TextStyle(color: Colors.white70)),
                      Expanded(
                        child: Slider(
                          value: _targetAperture,
                          min: 1.4,
                          max: 16.0,
                          divisions: 10,
                          activeColor: Colors.amber,
                          label: "f/$_targetAperture",
                          onChanged: (val) {
                            setState(() => _targetAperture = double.parse(val.toStringAsFixed(1)));
                            _recalculateExposure();
                          },
                        ),
                      ),
                    ],
                  )
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetric(String title, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(color: Colors.amber, fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

// 1/3 Kuralı Çizim Katmanı
class RuleOfThirdsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.25)
      ..strokeWidth = 1.0;

    // Dikey Çizgiler
    canvas.drawLine(Offset(size.width / 3, 0), Offset(size.width / 3, size.height), paint);
    canvas.drawLine(Offset(2 * size.width / 3, 0), Offset(2 * size.width / 3, size.height), paint);

    // Yatay Çizgiler
    canvas.drawLine(Offset(0, size.height / 3), Offset(size.width, size.height / 3), paint);
    canvas.drawLine(Offset(0, 2 * size.height / 3), Offset(size.width, 2 * size.height / 3), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
