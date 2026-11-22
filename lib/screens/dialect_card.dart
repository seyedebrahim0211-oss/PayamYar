import 'dart:async';
import '../sms_bridge.dart';
import '../message_search.dart';
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
  return uri != null && uri.scheme == 'https' &&
      uri.host == 'honarmardomi.ir' && uri.userInfo.isEmpty;
}

/// Preserve phrases and distinct meanings, including entries without recordings.
List<List<String>> dialectEntries(String body) {
  final entries = <List<String>>[];
  final seen = <String>{};
  for (final card in html.parse(body).querySelectorAll('article[data-kind="word"]')) {
    final word = card.querySelector('h3')?.text.trim() ?? '';
    final meaning = card.querySelector('.gy-mean')?.text.trim() ?? '';
    final url = card.querySelector('[data-au]')?.attributes['data-au'] ?? '';
    if (word.isNotEmpty && seen.add(jsonEncode([word, meaning, _officialAudio(url) ? url : '']))) {
      final audio = _officialAudio(url) ? url : '';
      entries.add([word, meaning, audio]);
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
  String _query = '';
  AudioPlayer? _player;
  StreamSubscription<void>? _completion;
  Timer? _midnight;
  List<List<String>> _entries = const [];
  bool _playing = false;
  int? _playingIndex;
  int _generation = 0;
  int? _day;

  int get _today {
    final now = DateTime.now();
    return DateTime.utc(now.year, now.month, now.day)
        .millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;
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
    final day = _today;

    _day = day;
    final now = DateTime.now();
    _midnight?.cancel();
    _midnight = Timer(DateTime(now.year, now.month, now.day + 1).difference(now), _refresh);
    if (_playing) await _stop();

    void display(List<List<String>> entries) {
      if (!mounted || generation != _generation || entries.isEmpty) return;
      setState(() => _entries = entries);
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('dialect.dictionary.v2.entries');
      final raw = saved ?? await rootBundle.loadString('assets/dialect.json');
      final decoded = jsonDecode(raw) as List;
      final entries = decoded.map((v) => List<String>.from(v as List))
          .where((v) => v.length >= 3 && v[0].isNotEmpty).toList();
      display(entries);
      if (!mounted || generation != _generation ||
          prefs.getInt('dialect.dictionary.v2.day') == day) {
        return;
      }
      final response = await _client.get(Uri.parse(_source))
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return;
      final current = await compute(dialectEntries, utf8.decode(response.bodyBytes));
      if (!mounted || generation != _generation || current.isEmpty) return;
      await prefs.setString('dialect.dictionary.v2.entries', jsonEncode(current));
      await prefs.setInt('dialect.dictionary.v2.day', day);
      display(current);
    } catch (_) {
      // Previously validated cached words stay available offline.
    }
  }

  Future<void> _stop() async {
    if (mounted) setState(() => _playing = false);
    await _player?.stop();
  }

  Future<void> _listen(int index) async {
    if (index < 0 || index >= _entries.length) return;
    try {
      if (_playing) {
        await _stop();
        if (_playingIndex == index) return;
      }
      final address = _entries[index][2];
      if (!_officialAudio(address)) return;
      final player = _player ??= AudioPlayer();
      _completion ??= player.onPlayerComplete.listen((_) {
        if (mounted) {
          setState(() => _playing = false);
        }
      });
      setState(() { _playing = true; _playingIndex = index; });
      await player.play(UrlSource(address)).timeout(const Duration(seconds: 15));
    } catch (_) {
      if (!mounted) return;
      setState(() => _playing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('پخش تلفظ ممکن نشد. اتصال اینترنت را بررسی کنید.')));
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
    final results = [for (var i = 0; i < _entries.length; i++)
      if (_query.isEmpty || MessageSearch.normalize('${_entries[i][0]} ${_entries[i][1]}').contains(_query)) i];
    return Scaffold(
      appBar: AppBar(title: const Text('واژه‌نامه بشرویه')),
      body: SafeArea(child: Column(children: [
        Padding(padding: const EdgeInsets.all(12), child: TextField(
          onChanged: (v) => setState(() => _query = MessageSearch.normalize(v.trim())),
          decoration: const InputDecoration(labelText: 'جست‌وجوی واژه یا معنی', prefixIcon: Icon(Icons.search)))),
        if (results.isEmpty) Padding(padding: const EdgeInsets.all(18),
          child: Text(_entries.isEmpty ? 'در حال دریافت واژه‌ها…' : 'واژه‌ای پیدا نشد.')),
        Expanded(child: ListView.builder(keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          itemCount: results.length, itemBuilder: (context, row) {
            final index = results[row];
            final entry = _entries[index];
            return ListTile(title: Text(entry[0]), subtitle: Text(entry[1]),
              leading: !_officialAudio(entry[2]) ? null : IconButton(
                tooltip: 'پخش یا توقف تلفظ', onPressed: () => _listen(index),
                icon: Icon(_playing && _playingIndex == index ? Icons.stop : Icons.volume_up_outlined)),
              trailing: IconButton(tooltip: 'اشتراک‌گذاری واژه', icon: const Icon(Icons.share_outlined),
                onPressed: () => SmsBridge.shareText([entry[0], entry[1], if (_officialAudio(entry[2])) entry[2], _source].join('\n'),
                  subject: 'واژه‌نامه بشرویه')));
          })),
      ])),
    );
  }
}
