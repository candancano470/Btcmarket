import 'dart:convert';
import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';

const String kBgTaskName = 'btcNotifyCheck';
const String kBgTaskUniqueName = 'btcNotifyCheckPeriodic';
const String _notifyUrl =
    'https://www.btcmorning.com/wp-content/plugins/btcmarketpro/notify_check.php';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName != kBgTaskName) return Future.value(true);
    try {
      final since = inputData?['since'] as int? ??
          (DateTime.now().millisecondsSinceEpoch ~/ 1000 - 900);
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      final uri = Uri.parse('$_notifyUrl?since=$since');
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode != 200) return Future.value(true);
      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      if (json['success'] != true) return Future.value(true);
      if ((json['new_count'] as int? ?? 0) == 0) return Future.value(true);
      final items = json['items'] as List<dynamic>? ?? [];
      if (items.isEmpty) return Future.value(true);
      final item = items.first as Map<String, dynamic>;
      final label = item['label'] as String? ?? '🔔 BTCMarketPro';
      final title = item['title'] as String? ?? '';
      if (title.isNotEmpty) await _showBgNotification(label, title);
    } catch (_) {}
    return Future.value(true);
  });
}

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

Future<void> initWorkManager() async {
  await Workmanager().initialize(
    callbackDispatcher,
    isInDebugMode: false,
  );
  await Workmanager().registerPeriodicTask(
    kBgTaskUniqueName,
    kBgTaskName,
    frequency: const Duration(minutes: 15),
    constraints: Constraints(
      networkType: NetworkType.connected,
    ),
    existingWorkPolicy: ExistingWorkPolicy.keep,
    backoffPolicy: BackoffPolicy.linear,
    backoffPolicyDelay: const Duration(minutes: 5),
  );
}