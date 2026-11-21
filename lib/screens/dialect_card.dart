import 'dart:async';
import 'dart:convert';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const _source = 'https://honarmardomi.ir/gooyesh-boshruyeh/';

bool _officialAudio(String address) {
  final uri = Uri.tryParse(address);
  return uri != null && uri.scheme == 'https' && uri.host == 'honarmardomi.ir' && uri.userInfo.isEmpty;
}

/// فقط مدخل‌های عمومیِ دارای معنی و صدای منبع در نوار روزانه جای دارند.
List<List<String>> dialectEntries(String body) {
  final entries = <List<String>>[];
  for (final card in html.parse(body).querySelectorAll('article[data-kind="word"]')) {
    final word = card.querySelector('h3')?.text.trim() ?? '';
    final meaning = card.querySelector('.gy-mean')?.text.trim() ?? '';
    final url = card.querySelector('[data-au]')?.attributes['data-au'] ?? '';
    if (word.isNotEmpty && meaning.isNotEmpty && _officialAudio(url)) {
      entries.add([word, meaning, url]);
    }
  }
  return entries;
}

class DialectCard extends StatefulWidget {
  const DialectCard({super.key});
  @override
  State<DialectCard> createState() => _DialectCardState();
}

class _DialectCardState extends State<DialectCard> with WidgetsBindingObserver {
  final _client = http.Client();
  AudioPlayer? _player;
  StreamSubscription<void>? _completion;
  Timer? _midnight;
  List<String>? _word;
  bool _playing = false;
  int _generation = 0;
  int? _day;

  int get _today {
    final now = DateTime.now();
    return DateTime.utc(now.year, now.month, now.day).millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _day != _today) _refresh();
    if (state == AppLifecycleState.paused && _playing) _stop();
  }

  Future<void> _refresh() async {
    final generation = ++_generation;
    final day = _day = _today;
    final now = DateTime.now();
    _midnight?.cancel();
    _midnight = Timer(DateTime(now.year, now.month, now.day + 1).difference(now), _refresh);
    if (_playing) await _stop();
    void display(List<List<String>> entries) {
      if (!mounted || generation != _generation || entries.isEmpty) return;
      setState(() => _word = entries[day % entries.length]);
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('dialect.public.entries');
      final raw = saved ?? await rootBundle.loadString('assets/dialect.json');
      final entries = (jsonDecode(raw) as List).map((v) => List<String>.from(v as List)).toList();
      display(entries);
      if (!mounted || generation != _generation || prefs.getInt('dialect.public.day') == day) return;
      final response = await _client.get(Uri.parse(_source)).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return;
      final current = await compute(dialectEntries, utf8.decode(response.bodyBytes));
      if (!mounted || generation != _generation || current.isEmpty) return;
      await prefs.setString('dialect.public.entries', jsonEncode(current));
      await prefs.setInt('dialect.public.day', day);
      display(current);
    } catch (_) {
      // The bundled dictionary and the last successful update also work offline.
    }
  }

  Future<void> _stop() async {
    if (mounted) setState(() => _playing = false);
    await _player?.stop();
  }

  Future<void> _listen() async {
    try {
      if (_playing) { await _stop(); return; }
      final address = _word?.last;
      if (address == null || !_officialAudio(address)) return;
      final player = _player ??= AudioPlayer();
      _completion ??= player.onPlayerComplete.listen((_) {
        if (mounted) setState(() => _playing = false);
      });
      setState(() => _playing = true);
      await player.play(UrlSource(address)).timeout(const Duration(seconds: 15));
    } catch (_) {
      if (!mounted) return;
      setState(() => _playing = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('پخش تلفظ ممکن نشد. اتصال اینترنت را بررسی کنید.')));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _midnight?.cancel();
    _client.close();
    _completion?.cancel();
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final word = _word;
    if (word == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: theme.colorScheme.secondaryContainer,
      child: ListTile(
        dense: true,
        title: Text('واژهٔ امروز بشرویه · هنر مردمی', style: theme.textTheme.labelMedium),
        subtitle: Text('${word[0]}  ·  ${word[1]}', style: theme.textTheme.bodyMedium),
        trailing: IconButton.filledTonal(
          tooltip: _playing ? 'توقف تلفظ' : 'شنیدن تلفظ محلی',
          icon: Icon(_playing ? Icons.stop_rounded : Icons.volume_up_rounded),
          onPressed: _listen,
        ),
      ),
    );
  }
}
