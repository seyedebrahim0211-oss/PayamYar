/// Validates the SIM explicitly chosen for a broadcast against currently active
/// subscription IDs. Never accept the Android default-SIM sentinel.
class GroupSimChoice {
  static int? active(int? selected, List<Map<dynamic, dynamic>> subscriptions) {
    if (selected == null || selected < 0) return null;
    return subscriptions.any((sim) => sim['id'] == selected) ? selected : null;
  }

  /// A one-SIM handset is unambiguous. Multiple active subscriptions require
  /// an explicit physical SIM; Android's implicit default is never accepted.
  static int? privateSend(int? chosen, List<Map<dynamic, dynamic>> subscriptions) {
    final valid = subscriptions.where((sim) =>
        sim['id'] is int && (sim['id'] as int) >= 0).toList();
    if (valid.isEmpty) return null;
    if (valid.length == 1) return valid.single['id'] as int;
    return active(chosen, valid);
  }
}
