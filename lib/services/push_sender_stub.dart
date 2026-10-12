/// Used on web, where sending is switched off: a key bundled into a
/// website can be read by anyone who opens it.
Future<bool> sendPush({
  String? topic,
  String? token,
  required String title,
  required String body,
  Map<String, String>? data,
}) async {
  return false;
}
