import 'dart:async';
import '../sms_bridge.dart';
import '../message_search.dart';
import '../jalali.dart';
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
  Timer? _searchDebounce;
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
    _searchDebounce?.cancel();

    _client.close();
    _completion?.cancel();
    _player?.dispose();
    super.dispose();
  }

  void _search(String value) {
    _searchDebounce?.cancel();
    final normalized = MessageSearch.normalize(value.trim());
    _searchDebounce = Timer(const Duration(milliseconds: 140), () {
      if (mounted) setState(() => _query = normalized);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final results = <int>[
      for (var i = 0; i < _entries.length; i++)
        if (_query.isEmpty ||
            MessageSearch.normalize('${_entries[i][0]} ${_entries[i][1]}').contains(_query)) i,
    ];
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('واژه‌نامه بشرویه',
          style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: SafeArea(child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: LinearGradient(colors: [
                scheme.primaryContainer.withValues(alpha: .85),
                scheme.tertiaryContainer.withValues(alpha: .55),
              ]),
              border: Border.all(color: scheme.primary.withValues(alpha: .2)),
            ),
            child: Row(children: [
              Container(
                width: 46, height: 46,
                decoration: BoxDecoration(
                  color: scheme.surface.withValues(alpha: .65),
                  borderRadius: BorderRadius.circular(14)),
                child: Icon(Icons.auto_stories_rounded, size: 27, color: scheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('گنجینه گویش بشرویگی',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900, color: scheme.onSurface)),
                  Text('${Jalali.digits(_entries.length)} واژه و عبارت · هنر مردمی',
                    style: Theme.of(context).textTheme.bodySmall),
                ],
              )),
              Icon(Icons.diamond_outlined, color: scheme.primary.withValues(alpha: .5)),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
          child: TextField(
            onChanged: _search,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              labelText: 'جست‌وجوی واژه یا معنی',
              hintText: 'مثلاً نام یک واژه بشرویگی',
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              fillColor: scheme.surfaceContainerLow,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: scheme.outlineVariant)),
            ),
          ),
        ),
        if (results.isEmpty)
          Padding(padding: const EdgeInsets.all(20),
            child: Text(_entries.isEmpty
              ? 'در حال دریافت واژه‌ها…' : 'واژه‌ای پیدا نشد.',
              textAlign: TextAlign.center)),
        Expanded(
          child: ListView.builder(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 28),
            itemCount: results.length,
            itemBuilder: (context, row) {
              final index = results[row];
              final entry = _entries[index];
              final hasAudio = _officialAudio(entry[2]);
              final playing = _playing && _playingIndex == index;
              final card = RepaintBoundary(child: Container(
                margin: const EdgeInsets.only(bottom: 9),
                decoration: BoxDecoration(
                  color: playing
                    ? scheme.primaryContainer.withValues(alpha: .6)
                    : scheme.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: playing ? scheme.primary.withValues(alpha: .55)
                      : scheme.outlineVariant.withValues(alpha: .7)),
                ),
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(12, 12, 9, 12),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                    Container(
                      width: 38, height: 38,
                      decoration: BoxDecoration(
                        color: scheme.secondaryContainer.withValues(alpha: .6),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: Icon(Icons.menu_book_rounded, color: scheme.primary,
                        size: 21),
                    ),
                    const SizedBox(width: 11),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(entry[0], textAlign: TextAlign.start,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900, color: scheme.primary)),
                        const SizedBox(height: 3),
                        Text(entry[1], textAlign: TextAlign.start,
                          style: Theme.of(context).textTheme.bodyMedium),
                      ],
                    )),
                    if (hasAudio)
                      IconButton(
                        tooltip: playing ? 'توقف تلفظ' : 'پخش تلفظ واژه',
                        onPressed: () => _listen(index),
                        icon: Icon(playing
                          ? Icons.stop_circle_rounded
                          : Icons.play_circle_outline_rounded,
                          color: scheme.primary),
                      ),
                    IconButton(
                      tooltip: 'اشتراک‌گذاری واژه',
                      icon: Icon(Icons.ios_share_rounded,
                        color: scheme.onSurfaceVariant, size: 21),
                      onPressed: () => SmsBridge.shareText(
                        [entry[0], entry[1], if (hasAudio) entry[2], _source].join('\\n'),
                        subject: 'واژه‌نامه بشرویه'),
                    ),
                  ]),
                ),
              ));
              if (reduceMotion) return card;
              return TweenAnimationBuilder<double>(
                key: ValueKey('word-$index'),
                tween: Tween(begin: .975, end: 1),
                duration: const Duration(milliseconds: 170),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) =>
                  Transform.scale(scale: value, child: child),
                child: card,
              );
            },
          ),
        ),
      ])),
    );
  }

}
