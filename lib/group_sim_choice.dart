/// Validates the SIM explicitly chosen for a broadcast against currently active
/// Android subscriptions. Never substitutes the phone's default subscription.
class GroupSimChoice {
  static int? active(int? selected, List<Map<dynamic, dynamic>> subscriptions) {
    if (selected == null || selected < 0) return null;
    return subscriptions.any((sim) => sim['id'] == selected) ? selected : null;
  }
}
