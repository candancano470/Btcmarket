import 'dart:convert';
import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

const String _notifyUrl =
    'https://www.btcmorning.com/wp-content/plugins/btcmarketpro/notify_check.php';

Future<void> _showBgNotification(String title, String body) async {
  final plugin = FlutterLocalNotificationsPlugin();
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  await plugin.initialize(const InitializationSettings(android: androidInit));
  const androidDetails = AndroidNotificationDetails(
    'btcmarketpro_channel',
    'BTCMarketPro Bildirimleri',
    channelDescription: 'Yeni içerik bildirimleri',
    importance: Importance.high,
    priority: Priority.high,
    icon: '@mipmap/ic_launcher',
  );
  await plugin.show(
    DateTime.now().millisecondsSinceEpoch ~/ 1000,
    title,
    body,
    const NotificationDetails(android: androidDetails),
  );
}

Future<void> checkNotifications(int since) async {
  try {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);
    final uri = Uri.parse('$_notifyUrl?since=$since');
    final request = await client.getUrl(uri);
    final response = await request.close();
    if (response.statusCode != 200) return;
    final body = await response.transform(utf8.decoder).join();
    final json = jsonDecode(body) as Map<String, dynamic>;
    if (json['success'] != true) return;
    if ((json['new_count'] as int? ?? 0) == 0) return;
    final items = json['items'] as List<dynamic>? ?? [];
    if (items.isEmpty) return;
    final item = items.first as Map<String, dynamic>;
    final label = item['label'] as String? ?? '🔔 BTCMarketPro';
    final title = item['title'] as String? ?? '';
    if (title.isNotEmpty) await _showBgNotification(label, title);
  } catch (_) {}
}

Future<void> initWorkManager() async {
  // workmanager kaldırıldı, bildirimler foreground polling ile çalışıyor
}