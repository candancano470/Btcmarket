import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:file_picker/file_picker.dart';
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

  void _setupFileUploadHandler(InAppWebViewController controller) {
    controller.addJavaScriptHandler(
      handlerName: 'flutterFileUpload',
      callback: (args) async {
        try {
          final result = await FilePicker.platform.pickFiles(
            type: FileType.image,
            allowMultiple: false,
            withData: true,
          );
          if (result == null || result.files.isEmpty) {
            await controller.evaluateJavascript(
                source: 'window._flutterFileCallback(null, null, null)');
            return;
          }
          final file = result.files.first;
          List<int>? bytes = file.bytes;
          if ((bytes == null || bytes.isEmpty) && file.path != null) {
            bytes = await File(file.path!).readAsBytes();
          }
          if (bytes == null || bytes.isEmpty) {
            await controller.evaluateJavascript(
                source: 'window._flutterFileCallback(null, null, null)');
            return;
          }
          final base64Data = base64Encode(bytes);
          final ext = (file.extension ?? 'jpeg').toLowerCase();
          final mimeType = ext == 'png' ? 'image/png' : 'image/jpeg';
          final fileName = file.name;
          await controller.evaluateJavascript(
              source:
                  "window._flutterFileCallback('$base64Data', '$fileName', '$mimeType')");
        } catch (e) {
          await controller.evaluateJavascript(
              source: 'window._flutterFileCallback(null, null, null)');
        }
      },
    );
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
                    hardwareAcceleration: true,
                    allowsInlineMediaPlayback: true,
                    userAgent:
                        'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
                  ),
                  onWebViewCreated: (controller) {
                    _controller = controller;
                    _setupFileUploadHandler(controller);
                  },
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
                    await controller.evaluateJavascript(source: '''
                      (function() {
                        if (window._btcFileHandlerReady) return;
                        window._btcFileHandlerReady = true;
                        window._activeFileInput = null;
                        window._flutterFileCallback = function(base64Data, fileName, mimeType) {
                          if (!base64Data || !window._activeFileInput) return;
                          try {
                            var byteStr = atob(base64Data);
                            var ab = new ArrayBuffer(byteStr.length);
                            var ia = new Uint8Array(ab);
                            for (var i = 0; i < byteStr.length; i++) {
                              ia[i] = byteStr.charCodeAt(i);
                            }
                            var blob = new Blob([ab], { type: mimeType || 'image/jpeg' });
                            var file = new File([blob], fileName || 'photo.jpg', { type: mimeType || 'image/jpeg' });
                            var dt = new DataTransfer();
                            dt.items.add(file);
                            window._activeFileInput.files = dt.files;
                            window._activeFileInput.dispatchEvent(new Event('change', { bubbles: true }));
                            window._activeFileInput.dispatchEvent(new Event('input', { bubbles: true }));
                            window._activeFileInput = null;
                          } catch(e) {
                            console.error('File inject error:', e);
                          }
                        };
                        document.addEventListener('click', function(e) {
                          var el = e.target;
                          while (el) {
                            if (el.tagName === 'INPUT' && el.type === 'file') {
                              e.preventDefault();
                              e.stopPropagation();
                              window._activeFileInput = el;
                              window.flutter_inappwebview.callHandler('flutterFileUpload');
                              return false;
                            }
                            el = el.parentElement;
                          }
                        }, true);
                      })();
                    ''');
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

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _boltController;
  late AnimationController _textController;
  late AnimationController _glowController;
  late Animation<double> _boltScale;
  late Animation<double> _boltOpacity;
  late Animation<double> _textOpacity;
  late Animation<double> _glow;

  @override
  void initState() {
    super.initState();
    _boltController =
        AnimationController(duration: const Duration(milliseconds: 900), vsync: this);
    _textController =
        AnimationController(duration: const Duration(milliseconds: 700), vsync: this);
    _glowController =
        AnimationController(duration: const Duration(milliseconds: 1200), vsync: this)
          ..repeat(reverse: true);
    _boltScale = Tween<double>(begin: 0.3, end: 1.0).animate(
        CurvedAnimation(parent: _boltController, curve: Curves.elasticOut));
    _boltOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
            parent: _boltController,
            curve: const Interval(0.0, 0.4, curve: Curves.easeIn)));
    _textOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _textController, curve: Curves.easeIn));
    _glow = Tween<double>(begin: 15.0, end: 35.0).animate(
        CurvedAnimation(parent: _glowController, curve: Curves.easeInOut));
    _boltController.forward();
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _textController.forward();
    });
  }

  @override
  void dispose() {
    _boltController.dispose();
    _textController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF071330),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedBuilder(
              animation: Listenable.merge([_boltController, _glowController]),
              builder: (context, child) {
                return Opacity(
                  opacity: _boltOpacity.value,
                  child: Transform.scale(
                    scale: _boltScale.value,
                    child: Container(
                      width: 110,
                      height: 110,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const RadialGradient(
                          colors: [Color(0xFF1A6FFF), Color(0xFF071330)],
                          radius: 0.8,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF1A6FFF).withOpacity(0.7),
                            blurRadius: _glow.value,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.bolt, color: Colors.white, size: 72),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 36),
            FadeTransition(
              opacity: _textOpacity,
              child: const Text('BTCMarketPro',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 34,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5)),
            ),
            const SizedBox(height: 10),
            FadeTransition(
              opacity: _textOpacity,
              child: const Text('Advanced Crypto Platform',
                  style: TextStyle(
                      color: Color(0xFF00bcd4),
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 0.8)),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoInternetWidget extends StatelessWidget {
  final VoidCallback onRetry;
  const _NoInternetWidget({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off_rounded, color: Color(0xFF1A6FFF), size: 80),
            const SizedBox(height: 24),
            const Text('No Internet Connection',
                style: TextStyle(
                    color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            const Text(
              'Please check your internet connection\nto access BTCMarketPro.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 15),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A6FFF),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorWidget extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorWidget({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/logo.png',
                width: 100,
                height: 100,
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.bolt, color: Color(0xFF1A6FFF), size: 80)),
            const SizedBox(height: 24),
            const Text('Page Could Not Load',
                style: TextStyle(
                    color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            const Text(
              'An error occurred while connecting\nto the server. Please try again.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 15),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Refresh'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A6FFF),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}