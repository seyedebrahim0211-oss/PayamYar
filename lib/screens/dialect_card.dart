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
  return uri != null && uri.scheme == 'https' &&
      uri.host == 'honarmardomi.ir' && uri.userInfo.isEmpty;
}

/// Only public entries with a meaning and first-party pronunciation are shown.
List<List<String>> dialectEntries(String body) {
  final entries = <List<String>>[];
  final seen = <String>{};
  for (final card in html.parse(body).querySelectorAll('article[data-kind="word"]')) {
    final word = card.querySelector('h3')?.text.trim() ?? '';
    final meaning = card.querySelector('.gy-mean')?.text.trim() ?? '';
    final url = card.querySelector('[data-au]')?.attributes['data-au'] ?? '';
    if (word.isNotEmpty && !word.contains(RegExp(r'\s')) &&
        meaning.isNotEmpty && _officialAudio(url) && seen.add(word)) {
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
  final _pages = PageController(viewportFraction: .93);
  AudioPlayer? _player;
  StreamSubscription<void>? _completion;
  Timer? _midnight;
  List<List<String>> _entries = const [];
  bool _playing = false;
  int _index = 0;
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
    final newDay = _day != day;
    _day = day;
    final now = DateTime.now();
    _midnight?.cancel();
    _midnight = Timer(DateTime(now.year, now.month, now.day + 1).difference(now), _refresh);
    if (_playing) await _stop();

    void display(List<List<String>> entries) {
      if (!mounted || generation != _generation || entries.isEmpty) return;
      final index = newDay || _entries.isEmpty
          ? day % entries.length
          : _index.clamp(0, entries.length - 1);
      setState(() {
        _entries = entries;
        _index = index;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && generation == _generation && _pages.hasClients) {
          _pages.jumpToPage(index);
        }
      });
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('dialect.public.entries');
      final raw = saved ?? await rootBundle.loadString('assets/dialect.json');
      final decoded = jsonDecode(raw) as List;
      final entries = decoded.map((v) => List<String>.from(v as List))
          .where((v) => v.length >= 3 && _officialAudio(v[2])).toList();
      display(entries);
      if (!mounted || generation != _generation ||
          prefs.getInt('dialect.public.day') == day) {
        return;
      }
      final response = await _client.get(Uri.parse(_source))
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return;
      final current = await compute(dialectEntries, utf8.decode(response.bodyBytes));
      if (!mounted || generation != _generation || current.isEmpty) return;
      await prefs.setString('dialect.public.entries', jsonEncode(current));
      await prefs.setInt('dialect.public.day', day);
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
        return;
      }
      final address = _entries[index][2];
      if (!_officialAudio(address)) return;
      final player = _player ??= AudioPlayer();
      _completion ??= player.onPlayerComplete.listen((_) {
        if (mounted) {
          setState(() => _playing = false);
        }
      });
      setState(() => _playing = true);
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
    _pages.dispose();
    _client.close();
    _completion?.cancel();
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_entries.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    const gold = Color(0xFFBA9562);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(18, 5, 18, 2),
        child: Row(children: [
          Icon(Icons.auto_stories_outlined, size: 18, color: scheme.primary),
          const SizedBox(width: 7),
          Expanded(child: Text('واژه امروز بشرویه · هنر مردمی',
            style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800))),
          Text('${_index + 1} / ${_entries.length}',
            textDirection: TextDirection.ltr,
            style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
        ]),
      ),
      SizedBox(
        height: 118,
        child: PageView.builder(
          key: const ValueKey('dialect-word-carousel'),
          controller: _pages,
          itemCount: _entries.length,
          onPageChanged: (index) {
            if (_playing) unawaited(_stop());
            setState(() => _index = index);
          },
          itemBuilder: (context, index) {
            final entry = _entries[index];
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(19),
                  border: Border.all(color: gold.withValues(alpha: .55)),
                  gradient: LinearGradient(
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                    colors: [scheme.surface, scheme.secondaryContainer.withValues(alpha: .70)],
                  ),
                  boxShadow: [BoxShadow(color: scheme.shadow.withValues(alpha: .06),
                    blurRadius: 10, offset: const Offset(0, 3))],
                ),
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 9),
                  child: Row(children: [
                    Container(
                      width: 42,
                      height: 64,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: .09),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: gold.withValues(alpha: .35)),
                      ),
                      child: const Text('۞', style: TextStyle(color: Color(0xFF087A77), fontSize: 27)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(entry[0], maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                        Text(entry[1], maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                        const SizedBox(height: 2),
                        Text('برای واژه بعدی به چپ یا راست بکشید',
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(color: scheme.primary)),
                      ],
                    )),
                    const SizedBox(width: 4),
                    IconButton.filledTonal(
                      key: ValueKey('dialect-audio-$index'),
                      tooltip: _playing && _index == index ? 'توقف تلفظ' : 'شنیدن تلفظ محلی',
                      icon: Icon(_playing && _index == index
                          ? Icons.stop_rounded : Icons.volume_up_rounded),
                      onPressed: () => _listen(index),
                    ),
                  ]),
                ),
              ),
            );
          },
        ),
      ),
    ]);
  }
}
