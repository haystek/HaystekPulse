import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:googleapis_auth/auth_io.dart' as gauth;

/// The notification-only service account key, bundled with the app.
/// Create it in the Google Cloud console and save it at this path.
const String _assetPath = 'assets/fcm_sender.json';
const String _scope = 'https://www.googleapis.com/auth/firebase.messaging';

gauth.AutoRefreshingAuthClient? _client;
String? _projectId;

/// Sends one notification through Firebase Cloud Messaging, either to
/// everyone subscribed to [topic] or to one device [token].
Future<bool> sendPush({
  String? topic,
  String? token,
  required String title,
  required String body,
  Map<String, String>? data,
}) async {
  if (_client == null) {
    final raw = await rootBundle.loadString(_assetPath);
    final json = jsonDecode(raw) as Map<String, dynamic>;
    _projectId = json['project_id'] as String?;
    _client = await gauth.clientViaServiceAccount(
      gauth.ServiceAccountCredentials.fromJson(json),
      [_scope],
    );
  }

  final response = await _client!.post(
    Uri.parse(
      'https://fcm.googleapis.com/v1/projects/$_projectId/messages:send',
    ),
    headers: const {'Content-Type': 'application/json'},
    body: jsonEncode({
      'message': {
        if (topic != null) 'topic': topic,
        if (token != null) 'token': token,
        'notification': {'title': title, 'body': body},
        if (data != null && data.isNotEmpty) 'data': data,
        'android': {
          'priority': 'HIGH',
          'notification': {
            'channel_id': 'haystek_alerts',
            'icon': 'ic_notification',
            'color': '#1B4FD8',
            'sound': 'default',
            'default_sound': true,
            'default_vibrate_timings': true,
            'notification_priority': 'PRIORITY_HIGH',
          },
        },
        'apns': {
          'payload': {
            'aps': {'sound': 'default'},
          },
        },
      },
    }),
  );
  return response.statusCode == 200;
}
