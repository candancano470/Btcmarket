import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';
import 'background_service.dart';

final FlutterLocalNotificationsPlugin _notifPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> _initNotifications() async {
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = InitializationSettings(android: androidInit);
  await _notifPlugin.initialize(initSettings);
  final android = _notifPlugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  await android?.requestNotificationsPermission();
}

Future<void> _showNotification(String title, String body) async {
  const androidDetails = AndroidNotificationDetails(
    'btcmarketpro_channel',
    'BTCMarketPro Bildirimleri',
    channelDescription: 'Yeni içerik bildirimleri',
    importance: Importance.high,
    priority: Priority.high,
    icon: '@mipmap/ic_launcher',
  );
  const details = NotificationDetails(android: androidDetails);
  await _notifPlugin.show(
    DateTime.now().millisecondsSinceEpoch ~/ 1000,
    title,
    body,
    details,
  );
}

bool _isExternalUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  if (uri.scheme == 'tg' || uri.host == 't.me') return true;
  const internalHost = 'btcmorning.com';
  if (!uri.host.contains(internalHost)) return true;
  return false;
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initNotifications();
  await initWorkManager();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Color(0xFF071330),
      statusBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const BTCMarketProApp());
}

class BTCMarketProApp extends StatelessWidget {
  const BTCMarketProApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BTCMarketPro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A6FFF),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF071330),
        useMaterial3: true,
      ),
      home: const AppRoot(),
    );
  }
}

class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  InAppWebViewController? _controller;
  bool _showSplash = true;
  bool _hasError = false;
  bool _hasInternet = true;
  late StreamSubscription<List<ConnectivityResult>> _connectivitySub;

  Timer? _notifTimer;
  int _lastChecked = 0;

  static const String _homeUrl = 'https://www.btcmorning.com/btcmarketpro/';
  static const String _notifyUrl =
      'https://www.btcmorning.com/wp-content/plugins/btcmarketpro/notify_check.php';

  @override
  void initState() {
    super.initState();
    _lastChecked = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 300;

    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final hasNet =
          results.isNotEmpty && results.first != ConnectivityResult.none;
      if (!mounted) return;
      setState(() => _hasInternet = hasNet);
    });

    Future.delayed(const Duration(seconds: 8), () {
      if (mounted && _showSplash) setState(() => _showSplash = false);
    });

    _startForegroundPolling();
  }

  void _startForegroundPolling() {
    _notifTimer = Timer.periodic(const Duration(minutes: 2), (_) async {
      await _checkForNotifications();
    });
    Future.delayed(const Duration(seconds: 30), _checkForNotifications);
  }

  Future<void> _checkForNotifications() async {
    if (!_hasInternet) return;
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      final uri = Uri.parse('$_notifyUrl?since=$_lastChecked');
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
      if (title.isNotEmpty) await _showNotification(label, title);

      _lastChecked = json['checked_at'] as int? ??
          DateTime.now().millisecondsSinceEpoch ~/ 1000;
    } catch (_) {}
  }

  Future<void> _reloadPage() async {
    setState(() {
      _hasError = false;
      _showSplash = true;
    });
    await _controller?.reload();
  }

  Future<bool> _onWillPop() async {
    if (_controller != null && await _controller!.canGoBack()) {
      await _controller!.goBack();
      return false;
    }
    return _showExitDialog();
  }

  Future<bool> _showExitDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0D1F3C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Exit App',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text(
          'Are you sure you want to exit BTCMarketPro?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('No', style: TextStyle(color: Color(0xFF1A6FFF))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A6FFF),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Yes', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  void dispose() {
    _connectivitySub.cancel();
    _notifTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && mounted) SystemNavigator.pop();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF071330),
        body: SafeArea(
          child: Stack(
            children: [
              if (!_hasInternet)
                _NoInternetWidget(onRetry: _reloadPage)
              else if (_hasError)
                _ErrorWidget(onRetry: _reloadPage)
              else
                InAppWebView(
                  initialUrlRequest: URLRequest(url: WebUri(_homeUrl)),
                  initialSettings: InAppWebViewSettings(
                    javaScriptEnabled: true,
                    mediaPlaybackRequiresUserGesture: false,
                    allowFileAccessFromFileURLs: true,
                    allowUniversalAccessFromFileURLs: true,
                    useHybridComposition: true,
                    // hardwareAccelerated kaldırıldı
                    allowsInlineMediaPlayback: true,
                    userAgent:
                        'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
                  ),
                  onWebViewCreated: (controller) => _controller = controller,
                  shouldOverrideUrlLoading:
                      (controller, navigationAction) async {
                    final url =
                        navigationAction.request.url?.toString() ?? '';
                    if (url.isEmpty) return NavigationActionPolicy.ALLOW;
                    if (_isExternalUrl(url)) {
                      final uri = Uri.parse(url);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri,
                            mode: LaunchMode.externalApplication);
                      }
                      return NavigationActionPolicy.CANCEL;
                    }
                    return NavigationActionPolicy.ALLOW;
                  },
                  onLoadStop: (controller, url) async {
                    if (!mounted) return;
                    setState(() {
                      _showSplash = false;
                      _hasError = false;
                    });
                  },
                  onReceivedError: (controller, request, error) {
                    if (!mounted) return;
                    if (request.isForMainFrame ?? false) {
                      setState(() {
                        _showSplash = false;
                        _hasError = true;
                      });
                    }
                  },
                ),
              if (_showSplash) const SplashScreen(),
            ],
          ),
        ),
      ),
    );
  }
}

// ── SplashScreen ──────────────────────────────────────────────────────────────

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF071330),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/logo.png',
              width: 120,
              height: 120,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.currency_bitcoin,
                size: 80,
                color: Color(0xFF1A6FFF),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'BTCMarketPro',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 32),
            const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                color: Color(0xFF1A6FFF),
                strokeWidth: 3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── _NoInternetWidget ─────────────────────────────────────────────────────────

class _NoInternetWidget extends StatelessWidget {
  final VoidCallback onRetry;
  const _NoInternetWidget({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF071330),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_rounded,
                  size: 72, color: Colors.white38),
              const SizedBox(height: 20),
              const Text(
                'İnternet Bağlantısı Yok',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Lütfen bağlantınızı kontrol edip tekrar deneyin.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 14),
              ),
              const SizedBox(height: 28),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Tekrar Dene'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A6FFF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 28, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── _ErrorWidget ──────────────────────────────────────────────────────────────

class _ErrorWidget extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorWidget({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF071330),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded,
                  size: 72, color: Colors.redAccent),
              const SizedBox(height: 20),
              const Text(
                'Sayfa Yüklenemedi',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Bir hata oluştu. Lütfen tekrar deneyin.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 14),
              ),
              const SizedBox(height: 28),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Tekrar Dene'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A6FFF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 28, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}