import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// ─── Bildirim plugin instance ───────────────────────────────────────────────
final FlutterLocalNotificationsPlugin _notifPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Sistem UI — edge-to-edge
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
  ));

  await _initNotifications();
  runApp(const BTCMarketProApp());
}

Future<void> _initNotifications() async {
  const android = AndroidInitializationSettings('@mipmap/ic_launcher');
  await _notifPlugin.initialize(
    const InitializationSettings(android: android),
  );
}

// ─── App root ───────────────────────────────────────────────────────────────
class BTCMarketProApp extends StatelessWidget {
  const BTCMarketProApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BTCMarketPro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF071330),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const WebViewScreen(),
    );
  }
}

// ─── WebView ekranı ─────────────────────────────────────────────────────────
class WebViewScreen extends StatefulWidget {
  const WebViewScreen({super.key});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  static const _platform =
      MethodChannel('com.btcmorning.btcmarketpro/permissions');

  InAppWebViewController? _webView;
  bool _loading = true;
  bool _hasConnection = true;
  StreamSubscription? _connectSub;

  // Sadece bu domain WebView'da kalır, geri kalanı dış tarayıcı
  static const String _siteDomain = 'btcmorning.com';
  static const String _homeUrl = 'https://btcmorning.com';

  @override
  void initState() {
    super.initState();
    _checkConnection();
    _connectSub = Connectivity().onConnectivityChanged.listen(_onConnectChange);

    // Bildirim iznini 4 saniye sonra contextual sor
    Future.delayed(const Duration(seconds: 4), _maybeAskNotifPermission);
  }

  @override
  void dispose() {
    _connectSub?.cancel();
    super.dispose();
  }

  // ── Bağlantı ──────────────────────────────────────────────────────────────
  Future<void> _checkConnection() async {
    final result = await Connectivity().checkConnectivity();
    _setConnection(result);
  }

  void _onConnectChange(List<ConnectivityResult> results) {
    _setConnection(results);
    if (_hasConnection) _webView?.reload();
  }

  void _setConnection(List<ConnectivityResult> results) {
    setState(() {
      _hasConnection = results.any((r) => r != ConnectivityResult.none);
    });
  }

  // ── Bildirim izni ─────────────────────────────────────────────────────────
  Future<void> _maybeAskNotifPermission() async {
    if (!mounted) return;
    final plugin = _notifPlugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (plugin == null) return;

    final enabled = await plugin.areNotificationsEnabled() ?? false;
    if (!enabled && mounted) _showNotifDialog();
  }

  void _showNotifDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0D1B3E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Text('🔔 ', style: TextStyle(fontSize: 22)),
          Text('Bildirimler', style: TextStyle(color: Colors.white)),
        ]),
        content: const Text(
          'Haberler, Airdrops, Launchpad ve Testnet güncellemelerini anında alın.',
          style: TextStyle(color: Colors.white70, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Daha Sonra',
                style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF7931A),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await _requestNotifPermission();
            },
            child: const Text('İzin Ver',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _requestNotifPermission() async {
    try {
      await _platform.invokeMethod('requestNotificationPermission');
    } catch (_) {
      // Native izin isteği — hata olursa sessiz geç
    }
  }

  // ── URL yönlendirme ───────────────────────────────────────────────────────
  /// Site kendi domain'i → WebView | Başka domain & özel şema → Dış tarayıcı
  bool _isInternal(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    return uri.host.contains(_siteDomain);
  }

  Future<NavigationActionPolicy> _handleNavigation(
      InAppWebViewController ctrl,
      NavigationAction action) async {
    final url = action.request.url?.toString() ?? '';

    // Özel şemalar: tel, mailto, intent vb.
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      await _launchExternal(url);
      return NavigationActionPolicy.CANCEL;
    }

    // Dış domain → dış tarayıcı
    if (!_isInternal(url)) {
      await _launchExternal(url);
      return NavigationActionPolicy.CANCEL;
    }

    return NavigationActionPolicy.ALLOW;
  }

  Future<void> _launchExternal(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF071330),
      body: _hasConnection ? _buildWebView() : _buildNoConnection(),
    );
  }

  Widget _buildWebView() {
    return Stack(
      children: [
        InAppWebView(
          initialUrlRequest: URLRequest(url: WebUri(_homeUrl)),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            domStorageEnabled: true,
            databaseEnabled: true,
            useShouldOverrideUrlLoading: true,
            mediaPlaybackRequiresUserGesture: false,
            allowsInlineMediaPlayback: true,
            mixedContentMode: MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
            supportZoom: false,
            builtInZoomControls: false,
            displayZoomControls: false,
            useHybridComposition: true,
            cacheMode: CacheMode.LOAD_DEFAULT,
          ),
          onWebViewCreated: (ctrl) {
            _webView = ctrl;

            // Web sayfası JS tarafından bildirim izni isteyebilir:
            // window.flutter_inappwebview.callHandler('requestNotifPermission')
            ctrl.addJavaScriptHandler(
              handlerName: 'requestNotifPermission',
              callback: (_) async {
                await _requestNotifPermission();
                return 'ok';
              },
            );
          },
          shouldOverrideUrlLoading: _handleNavigation,
          onLoadStart: (_, __) => setState(() => _loading = true),
          onLoadStop: (_, __) => setState(() => _loading = false),
          onReceivedError: (_, __, ___) => setState(() => _loading = false),
        ),

        // Yükleniyor göstergesi
        if (_loading)
          const Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(Color(0xFFF7931A)),
            ),
          ),
      ],
    );
  }

  Widget _buildNoConnection() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off_rounded, color: Colors.white38, size: 72),
            const SizedBox(height: 20),
            const Text('İnternet bağlantısı yok',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            const Text('Lütfen bağlantınızı kontrol edin',
                style: TextStyle(color: Colors.white54)),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF7931A),
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _checkConnection,
              icon: const Icon(Icons.refresh, color: Colors.white),
              label: const Text('Tekrar Dene',
                  style: TextStyle(color: Colors.white, fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }
}