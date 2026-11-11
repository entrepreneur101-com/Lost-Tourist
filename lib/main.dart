import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_mlkit_language_id/google_mlkit_language_id.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

const backendUrl = 'https://YOUR-WORKER.workers.dev'; // see server/worker.js
const navy = Color(0xFF12263A), yellow = Color(0xFFFFC93C), paper = Color(0xFFF4F7FB);

void main() => runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: Home()));

// ---------- Access: 3 free looks a day, or a 14-day pass ----------
class Access {
  static const freePerDay = 3;
  /// 'ok' | 'limit' | 'expired' (expired is shown once after a pass ends)
  static Future<String> status() async {
    final p = await SharedPreferences.getInstance();
    final until = p.getInt('passUntil') ?? 0;
    if (until > DateTime.now().millisecondsSinceEpoch) return 'ok';
    final today = DateTime.now().toIso8601String().substring(0, 10);
    if (p.getString('day') != today) {
      await p.setString('day', today);
      await p.setInt('n', 0);
    }
    if (until > 0 && !(p.getBool('expiredShown') ?? false)) {
      await p.setBool('expiredShown', true);
      return 'expired';
    }
    return (p.getInt('n') ?? 0) < freePerDay ? 'ok' : 'limit';
  }

  static Future<void> countScan() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('n', (p.getInt('n') ?? 0) + 1);
  }

  // TODO: replace with RevenueCat purchase; grant the pass only after it succeeds.
  static Future<void> buyPass() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('passUntil', DateTime.now().add(const Duration(days: 14)).millisecondsSinceEpoch);
    await p.setBool('expiredShown', false);
  }
}

// ---------- Scan: GPS + on-device OCR -> server -> translate ----------
class Place {
  final String name, address, story, sign;
  final double lat, lng;
  Place(this.name, this.address, this.story, this.sign, this.lat, this.lng);
}

Future<Place> scan(File photo) async {
  final pos = await Geolocator.getCurrentPosition();
  final rec = TextRecognizer();
  final text = (await rec.processImage(InputImage.fromFile(photo))).text.trim();
  await rec.close();
  final res = await http.post(Uri.parse('$backendUrl/locate'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'lat': pos.latitude, 'lng': pos.longitude, 'text': text.split('\n').take(3).join(' ')}));
  if (res.statusCode != 200) throw Exception('not found');
  final j = jsonDecode(res.body);
  final sign = text.isEmpty ? '' : await _translate(text);
  return Place(j['name'], j['address'] ?? '', j['story'] ?? '', sign, (j['lat'] as num).toDouble(), (j['lng'] as num).toDouble());
}

Future<String> _translate(String text) async {
  try {
    final lid = LanguageIdentifier(confidenceThreshold: 0.5);
    final code = await lid.identifyLanguage(text);
    await lid.close();
    final src = BCP47Code.fromRawValue(code);
    if (src == null || src == TranslateLanguage.english) return '';
    final tr = OnDeviceTranslator(sourceLanguage: src, targetLanguage: TranslateLanguage.english); // TODO: user's language
    final out = await tr.translateText(text);
    await tr.close();
    return out;
  } catch (_) {
    return '';
  }
}

// ---------- UI helpers ----------
class Big extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool outline;
  const Big(this.label, this.onTap, {super.key, this.outline = false});
  @override
  Widget build(BuildContext c) => SizedBox(
      width: double.infinity,
      height: outline ? 72 : 88,
      child: TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
              backgroundColor: outline ? Colors.transparent : yellow,
              foregroundColor: navy,
              shape: StadiumBorder(side: outline ? const BorderSide(color: navy, width: 3) : BorderSide.none)),
          child: Text(label, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700))));
}

void go(BuildContext c, Widget w, {bool replace = false}) {
  final r = MaterialPageRoute(builder: (_) => w);
  replace ? Navigator.pushReplacement(c, r) : Navigator.push(c, r);
}

// ---------- 1. Home ----------
class Home extends StatelessWidget {
  const Home({super.key});
  Future<void> _start(BuildContext c) async {
    final s = await Access.status();
    if (!c.mounted) return;
    if (s != 'ok') return go(c, Paywall(expired: s == 'expired'));
    final shot = await ImagePicker().pickImage(source: ImageSource.camera);
    if (shot == null || !c.mounted) return;
    go(c, Scanning(File(shot.path)));
  }

  @override
  Widget build(BuildContext c) => Scaffold(
      backgroundColor: const Color(0xFF2E3F52),
      body: SafeArea(
          child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(children: [
                const Spacer(),
                const Text('Lost?', style: TextStyle(color: Colors.white, fontSize: 44, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                const Text('Take a photo of where you are.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 24)),
                const Spacer(),
                Big('Where am I?', () => _start(c)),
              ]))));
}

// ---------- 2. Scanning ----------
class Scanning extends StatefulWidget {
  final File photo;
  const Scanning(this.photo, {super.key});
  @override
  State<Scanning> createState() => _ScanningState();
}

class _ScanningState extends State<Scanning> {
  bool failed = false;
  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      final p = await scan(widget.photo);
      await Access.countScan();
      if (mounted) go(context, Result(p), replace: true);
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
  }

  @override
  Widget build(BuildContext c) => Scaffold(
      backgroundColor: navy,
      body: Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
              child: failed
                  ? Column(mainAxisSize: MainAxisSize.min, children: [
                      const Text('Not sure yet.\nTry pointing at a sign or a building front.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 28)),
                      const SizedBox(height: 32),
                      Big('Try again', () => Navigator.pop(c)),
                    ])
                  : const Column(mainAxisSize: MainAxisSize.min, children: [
                      CircularProgressIndicator(color: yellow, strokeWidth: 8),
                      SizedBox(height: 32),
                      Text('Looking… hold still', style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w700)),
                    ]))));
}

// ---------- 3. Result ----------
class Result extends StatelessWidget {
  final Place p;
  const Result(this.p, {super.key});
  @override
  Widget build(BuildContext c) => Scaffold(
      backgroundColor: paper,
      body: SafeArea(
          child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('You are here', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: Color(0xFF3C4E60))),
                Text(p.name, style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800, height: 1.1, color: navy)),
                const SizedBox(height: 8),
                Text(p.address, style: const TextStyle(fontSize: 22, color: Color(0xFF3C4E60))),
                if (p.sign.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                      child: Text('Sign says: ${p.sign}', style: const TextStyle(fontSize: 20, color: navy))),
                ],
                const Spacer(),
                Big('Tell me', () => go(c, Narrator(p))),
                const SizedBox(height: 12),
                Big('Try again', () => Navigator.popUntil(c, (r) => r.isFirst), outline: true),
                TextButton(
                    onPressed: () => launchUrl(Uri.parse('https://www.google.com/maps/search/?api=1&query=${p.lat},${p.lng}'), mode: LaunchMode.externalApplication),
                    child: const Center(child: Text("Help, I'm really lost: open Maps", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: navy)))),
              ]))));
}

// ---------- 4. Narrator (on-device text-to-speech) ----------
class Narrator extends StatefulWidget {
  final Place p;
  const Narrator(this.p, {super.key});
  @override
  State<Narrator> createState() => _NarratorState();
}

class _NarratorState extends State<Narrator> {
  final tts = FlutterTts();
  bool slow = false;
  String get story => widget.p.story.isNotEmpty ? widget.p.story : 'You are at ${widget.p.name}. ${widget.p.address}.';
  @override
  void initState() {
    super.initState();
    _speak();
  }

  Future<void> _speak() async {
    await tts.stop();
    await tts.setSpeechRate(slow ? 0.3 : 0.5);
    await tts.speak(story);
  }

  @override
  void dispose() {
    tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => Scaffold(
      backgroundColor: paper,
      appBar: AppBar(backgroundColor: paper, elevation: 0, foregroundColor: navy),
      body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.p.name, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: navy)),
            const SizedBox(height: 20),
            Expanded(child: SingleChildScrollView(child: Text(story, style: const TextStyle(fontSize: 24, height: 1.45, color: navy)))),
            SwitchListTile(
                title: const Text('Slow speech', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
                value: slow,
                activeColor: navy,
                onChanged: (v) {
                  setState(() => slow = v);
                  _speak();
                }),
            Row(children: [
              Expanded(child: Big('Stop', () => tts.stop())),
              const SizedBox(width: 16),
              Expanded(child: Big('Replay', _speak, outline: true)),
            ]),
          ])));
}

// ---------- 5. Paywall / pass expired ----------
class Paywall extends StatelessWidget {
  final bool expired;
  const Paywall({super.key, this.expired = false});
  @override
  Widget build(BuildContext c) => Scaffold(
      backgroundColor: paper,
      body: SafeArea(
          child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(children: [
                const Spacer(),
                Text(expired ? 'Your 14-day pass has ended.' : "You've used your 3 free looks today.",
                    textAlign: TextAlign.center, style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w800, color: navy)),
                const SizedBox(height: 16),
                Text(expired ? 'Hope you had a great trip! Get another pass for unlimited looks.' : 'Unlimited looks, the narrator and all languages for 14 days.',
                    textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, color: Color(0xFF3C4E60))),
                const Spacer(),
                Big(expired ? r'Get another 14 days, $2.99' : r'Get 14-day pass, $2.99', () async {
                  await Access.buyPass();
                  if (c.mounted) Navigator.pop(c);
                }),
                const SizedBox(height: 12),
                Big(expired ? 'Not now' : 'Come back tomorrow', () => Navigator.pop(c), outline: true),
                const SizedBox(height: 12),
                const Text(r'Or unlock forever for $12.99', style: TextStyle(fontSize: 18, color: Color(0xFF3C4E60))),
              ]))));
}