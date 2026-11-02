import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const KaraokeApp());

class KaraokeApp extends StatelessWidget {
  const KaraokeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Karaoke Mic',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.deepPurple, useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.deepPurple,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const MethodChannel _ch = MethodChannel('karaoke/engine');

  bool running = false;
  bool muted = false;
  double gain = 0; // dB
  double echo = 25; // %
  double echoTime = 0.25; // seconds
  double reverb = 30; // %
  double level = 0;
  String route = '';
  String? error;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _send(String method, [Object? arg]) async {
    try {
      await _ch.invokeMethod(method, arg);
    } on PlatformException catch (e) {
      if (mounted) setState(() => error = e.message);
    } on MissingPluginException {
      if (mounted) setState(() => error = 'រកមិនឃើញ native engine');
    }
  }

  Future<void> _applyAll() async {
    await _send('setMicGain', gain);
    await _send('setEcho', echo);
    await _send('setEchoTime', echoTime);
    await _send('setReverb', reverb);
    await _send('setMute', muted);
  }

  Future<void> _toggle() async {
    if (running) {
      _timer?.cancel();
      await _send('stop');
      setState(() {
        running = false;
        level = 0;
      });
      return;
    }
    setState(() => error = null);
    await _applyAll();
    await _send('start');
    if (error != null) return;

    String r = '';
    try {
      r = (await _ch.invokeMethod<String>('getRoute')) ?? '';
    } catch (_) {}
    setState(() {
      running = true;
      route = r;
    });
    _timer = Timer.periodic(const Duration(milliseconds: 80), (_) async {
      try {
        final v = await _ch.invokeMethod<double>('getLevel');
        if (mounted && v != null) setState(() => level = v.clamp(0.0, 1.0));
      } catch (_) {}
    });
  }

  Widget _slider({
    required String title,
    required double value,
    required double min,
    required double max,
    required String unit,
    required String method,
    required ValueChanged<double> onChanged,
    int decimals = 0,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title),
            Text('${value.toStringAsFixed(decimals)}$unit',
                style: TextStyle(color: Theme.of(context).hintColor)),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          onChanged: (v) {
            onChanged(v);
            _send(method, v);
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('🎤 Karaoke Mic')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                backgroundColor: running ? Colors.red : null,
              ),
              onPressed: _toggle,
              child: Text(running ? 'បញ្ឈប់' : 'ចាប់ផ្តើមច្រៀង',
                  style: const TextStyle(fontSize: 18)),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('បិទសំឡេងមីកបណ្ដោះអាសន្ន'),
              value: muted,
              onChanged: running
                  ? (v) {
                      setState(() => muted = v);
                      _send('setMute', v);
                    }
                  : null,
            ),
            LinearProgressIndicator(value: level, minHeight: 8),
            if (route.isNotEmpty && running)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Output: $route',
                    style: TextStyle(color: Theme.of(context).hintColor)),
              ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(error!, style: TextStyle(color: cs.error)),
              ),
            const Divider(height: 32),
            _slider(
              title: 'កម្រិតមីក',
              value: gain,
              min: 0,
              max: 20,
              unit: ' dB',
              method: 'setMicGain',
              onChanged: (v) => setState(() => gain = v),
            ),
            _slider(
              title: 'Echo',
              value: echo,
              min: 0,
              max: 100,
              unit: '%',
              method: 'setEcho',
              onChanged: (v) => setState(() => echo = v),
            ),
            _slider(
              title: 'រយៈពេល Echo',
              value: echoTime,
              min: 0.05,
              max: 0.6,
              unit: ' s',
              decimals: 2,
              method: 'setEchoTime',
              onChanged: (v) => setState(() => echoTime = v),
            ),
            _slider(
              title: 'Reverb',
              value: reverb,
              min: 0,
              max: 100,
              unit: '%',
              method: 'setReverb',
              onChanged: (v) => setState(() => reverb = v),
            ),
            const SizedBox(height: 16),
            Text(
              'ចុចចាប់ផ្តើម រួចប្តូរទៅ YouTube ដើម្បីមើលអក្សរ និងចាក់ភ្លេង។ '
              'ប្រើកាស ឬដាក់ speaker ឲ្យឆ្ងាយពីទូរស័ព្ទ ដើម្បីកុំឲ្យមានសំឡេងហួច។ '
              'Bluetooth មាន latency 100–300ms ប្រើខ្សែទើបទាន់បំផុត។',
              style: TextStyle(color: Theme.of(context).hintColor, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
