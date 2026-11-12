import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'contacts_data.dart';

/// A PayamYar contact group (kept on the phone, independent of Google/Samsung accounts).
class ContactGroup {
  final String id;
  final String name;
  final int color;
  const ContactGroup(this.id, this.name, this.color);
  Map<String, Object> toJson() => {'id': id, 'name': name, 'color': color};
  static ContactGroup? fromJson(Object? r) => r is Map && r['id'] != null
      ? ContactGroup(r['id'].toString(), r['name']?.toString() ?? '', (r['color'] as num?)?.toInt() ?? 0xFF087F81)
      : null;
}

const defaultGroups = [
  ContactGroup('family', 'خانواده', 0xFFB4537A),
  ContactGroup('friends', 'دوستان', 0xFF3A7CA5),
  ContactGroup('work', 'کار', 0xFFA17A37),
  ContactGroup('other', 'سایر', 0xFF47765F),
];

const groupColors = [0xFFB4537A, 0xFF3A7CA5, 0xFFA17A37, 0xFF47765F, 0xFF75539A, 0xFFC0583B, 0xFF087F81, 0xFF305F91];

/// Phone book state for the Contacts tab: list, search, groups, duplicates and photo cache.
class ContactStore extends ChangeNotifier {
  static const _prefsKey = 'contact_groups_v1';

  List<PhoneContact> contacts = [];
  List<ContactGroup> groups = List.of(defaultGroups);
  /// Contact key → group ids.
  Map<String, Set<String>> members = {};
  bool loading = false;
  bool canRead = false;
  bool canWrite = false;
  String? error;
  final Map<int, Future<dynamic>> _photos = {};
  bool _loadedGroups = false;

  Future<void> load({bool ask = false}) async {
    if (!ContactsBridge.supported) {
      contacts = _sample;
      canRead = true;
      notifyListeners();
      return;
    }
    if (!_loadedGroups) await _loadGroups();
    loading = true;
    error = null;
    notifyListeners();
    try {
      var p = await ContactsBridge.permissions();
      if (p['read'] != true && ask) {
        await ContactsBridge.requestPermissions();
        p = await ContactsBridge.permissions();
      }
      canRead = p['read'] == true;
      canWrite = p['write'] == true;
      if (canRead) {
        contacts = await ContactsBridge.list();
        _photos.clear();
      }
    } catch (e) {
      error = 'خواندن مخاطبین انجام نشد.';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Asks for write access when needed; false when the user refused.
  Future<bool> ensureWrite() async {
    if (canWrite) return true;
    if (!ContactsBridge.supported) return false;
    await ContactsBridge.requestPermissions();
    final p = await ContactsBridge.permissions();
    canRead = p['read'] == true;
    canWrite = p['write'] == true;
    notifyListeners();
    return canWrite;
  }

  Future<dynamic> photo(PhoneContact c) =>
      !c.hasPhoto ? Future.value(null) : _photos.putIfAbsent(c.id, () => ContactsBridge.photo(c.id));

  void forgetPhoto(int id) => _photos.remove(id);

  PhoneContact? byId(int id) {
    for (final c in contacts) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Contact whose number matches [number] (normalised), for linking SMS conversations.
  PhoneContact? byPhone(String number) {
    final k = phoneKey(number);
    if (k.length < 5) return null;
    final tail = k.length > 10 ? k.substring(k.length - 10) : k;
    for (final c in contacts) {
      for (final p in c.phones) {
        final pk = phoneKey(p.value);
        if (pk == k || (pk.length >= 10 && pk.endsWith(tail))) return c;
      }
    }
    return null;
  }

  // ───────────── search & filters ─────────────

  static String _fold(String s) => s.replaceAll('ي', 'ی').replaceAll('ك', 'ک').replaceAll('‌', ' ').toLowerCase();

  List<PhoneContact> search(String query, {String? groupId, bool favorites = false}) {
    final q = _fold(query.trim());
    final qDigits = phoneKey(query);
    return contacts.where((c) {
      if (favorites && !c.starred) return false;
      if (groupId != null && !(members[c.key]?.contains(groupId) ?? false)) return false;
      if (q.isEmpty) return true;
      if (_fold(c.name).contains(q) || _fold(c.org).contains(q)) return true;
      if (c.emails.any((e) => e.value.toLowerCase().contains(q))) return true;
      return qDigits.length >= 3 && c.phones.any((p) => phoneKey(p.value).contains(qDigits));
    }).toList();
  }

  int get favoritesCount => contacts.where((c) => c.starred).length;

  // Derived lists are cached per loaded contact list (they are shown on every rebuild).
  List<PhoneContact>? _cacheFor;
  final Map<String, Object> _cache = {};

  T _cached<T extends Object>(String key, T Function() build) {
    if (!identical(_cacheFor, contacts)) {
      _cache.clear();
      _cacheFor = contacts;
    }
    return _cache.putIfAbsent(key, build) as T;
  }

  /// Contacts that share a number or the exact same name; each list is one cluster to review.
  List<List<PhoneContact>> get duplicates => _cached('dup', _duplicates);

  List<List<PhoneContact>> _duplicates() {
    final parent = <int, int>{};
    int find(int x) {
      while (parent[x] != null && parent[x] != x) {
        x = parent[x]!;
      }
      return x;
    }

    void union(int a, int b) {
      final ra = find(a), rb = find(b);
      if (ra != rb) parent[ra] = rb;
    }

    final byKey = <String, int>{};
    for (final c in contacts) {
      parent.putIfAbsent(c.id, () => c.id);
      final keys = <String>[
        for (final p in c.phones)
          if (phoneKey(p.value).length >= 7) 'p:${phoneKey(p.value)}',
        if (c.name.trim().length >= 3) 'n:${_fold(c.name.trim())}',
      ];
      for (final k in keys) {
        final other = byKey[k];
        if (other == null) {
          byKey[k] = c.id;
        } else {
          union(c.id, other);
        }
      }
    }
    final clusters = <int, List<PhoneContact>>{};
    for (final c in contacts) {
      (clusters[find(c.id)] ??= []).add(c);
    }
    return clusters.values.where((l) => l.length > 1).toList();
  }

  /// Without a real name, without any number/e-mail, or with an invalid number.
  List<PhoneContact> get incomplete => _cached('incomplete', () => contacts.where((c) =>
      c.name.trim().isEmpty ||
      RegExp(r'^[\d\s+()-]+$').hasMatch(c.name.trim()) ||
      (c.phones.isEmpty && c.emails.isEmpty) ||
      c.phones.any((p) => !isValidPhone(p.value))).toList());

  /// Numbers written with Persian digits, spaces or +98 that can be tidied to 09xxxxxxxxx.
  List<PhoneContact> get untidy => _cached('untidy', () => contacts.where((c) => c.phones.any((p) => isUntidy(p.value))).toList());

  int get duplicateCount => duplicates.fold(0, (n, l) => n + l.length);

  // ───────────── groups ─────────────

  Future<void> _loadGroups() async {
    _loadedGroups = true;
    final p = await SharedPreferences.getInstance();
    try {
      final raw = jsonDecode(p.getString(_prefsKey) ?? '{}');
      if (raw is Map) {
        final g = (raw['groups'] is List ? raw['groups'] as List : const []).map(ContactGroup.fromJson).whereType<ContactGroup>().toList();
        if (g.isNotEmpty) groups = g;
        final m = raw['members'];
        if (m is Map) {
          members = {for (final e in m.entries) e.key.toString(): {for (final x in (e.value as List? ?? const [])) x.toString()}};
        }
      }
    } catch (_) {
      // Corrupt data: keep the default groups.
    }
  }

  Future<void> _saveGroups() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_prefsKey, jsonEncode({
      'groups': [for (final g in groups) g.toJson()],
      'members': {for (final e in members.entries) if (e.value.isNotEmpty) e.key: e.value.toList()},
    }));
    notifyListeners();
  }

  ContactGroup? group(String id) {
    for (final g in groups) {
      if (g.id == id) return g;
    }
    return null;
  }

  List<ContactGroup> groupsOf(PhoneContact c) =>
      [for (final id in members[c.key] ?? const <String>{}) if (group(id) != null) group(id)!];

  Map<String, List<String>> get groupNamesByKey => {
        for (final e in members.entries) e.key: [for (final id in e.value) if (group(id) != null) group(id)!.name],
      };

  int countIn(String groupId) => contacts.where((c) => members[c.key]?.contains(groupId) ?? false).length;

  Future<void> setGroups(PhoneContact c, Set<String> ids) async {
    members[c.key] = ids;
    await _saveGroups();
  }

  Future<void> addToGroup(Iterable<PhoneContact> list, String groupId) async {
    for (final c in list) {
      (members[c.key] ??= <String>{}).add(groupId);
    }
    await _saveGroups();
  }

  Future<void> removeFromGroup(Iterable<PhoneContact> list, String groupId) async {
    for (final c in list) {
      members[c.key]?.remove(groupId);
    }
    await _saveGroups();
  }

  Future<ContactGroup> createGroup(String name, int color) async {
    final g = ContactGroup('g${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}', name.trim(), color);
    groups = [...groups, g];
    await _saveGroups();
    return g;
  }

  Future<void> renameGroup(String id, String name, int color) async {
    groups = [for (final g in groups) g.id == id ? ContactGroup(id, name.trim(), color) : g];
    await _saveGroups();
  }

  Future<void> deleteGroup(String id) async {
    groups = groups.where((g) => g.id != id).toList();
    for (final s in members.values) {
      s.remove(id);
    }
    await _saveGroups();
  }

  /// Group id by name (case/spacing-insensitive), creating it when [create] is true.
  Future<String?> groupIdByName(String name, {bool create = true}) async {
    final n = _fold(name.trim());
    if (n.isEmpty) return null;
    for (final g in groups) {
      if (_fold(g.name) == n) return g.id;
    }
    if (!create) return null;
    return (await createGroup(name, groupColors[groups.length % groupColors.length])).id;
  }

  // ───────────── writes ─────────────

  Future<void> toggleStar(PhoneContact c) async {
    if (!await ensureWrite()) return;
    await ContactsBridge.star(c.id, !c.starred);
    await load();
  }

  Future<int> remove(List<PhoneContact> list) async {
    if (!await ensureWrite()) return 0;
    final n = await ContactsBridge.delete([for (final c in list) c.id]);
    for (final c in list) {
      members.remove(c.key);
    }
    await _saveGroups();
    await load();
    return n;
  }

  Future<bool> merge(List<PhoneContact> list) async {
    if (!await ensureWrite()) return false;
    final keep = list.first;
    final union = <String>{for (final c in list) ...?members[c.key]};
    final ok = await ContactsBridge.join([for (final c in list) c.id]);
    await load();
    // The merged person keeps the first contact's id when possible; carry the groups over.
    final merged = byId(keep.id) ?? (contacts.isEmpty ? null : byPhone(keep.primaryPhone));
    if (merged != null && union.isNotEmpty) await setGroups(merged, union);
    return ok;
  }

  /// Rewrites every untidy number of [c] as 09xxxxxxxxx (other fields untouched).
  Future<void> tidy(PhoneContact c) async {
    if (!await ensureWrite()) return;
    await ContactsBridge.save(
      id: c.id,
      name: c.name,
      phones: [for (final p in c.phones) isUntidy(p.value) ? LabeledValue(phoneKey(p.value), type: p.type, label: p.label) : p],
      emails: c.emails,
      org: c.org,
      title: c.title,
      note: c.note,
      birthday: c.birthday,
    );
  }

  static const _sample = <PhoneContact>[
    PhoneContact(id: 1, name: 'علی رضایی', starred: true, phones: [LabeledValue('09121234567')],
        emails: [LabeledValue('ali@example.com', type: 1)], org: 'هنر مردمی', birthday: '1990-05-12'),
    PhoneContact(id: 2, name: 'مریم احمدی', phones: [LabeledValue('+989359876543')]),
    PhoneContact(id: 3, name: 'مریم احمدی', phones: [LabeledValue('09359876543')]),
    PhoneContact(id: 4, name: '', phones: [LabeledValue('۰۹۱۰ ۱۱۱ ۲۲۳۳')]),
  ];

  static Color colorOf(ContactGroup g) => Color(g.color);
}
