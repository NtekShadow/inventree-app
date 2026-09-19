import "dart:async";
import "dart:convert";
import "dart:io";
import "package:flutter/material.dart";
import "package:flutter_tabler_icons/flutter_tabler_icons.dart";
import "package:url_launcher/url_launcher.dart";
import "package:webview_flutter/webview_flutter.dart";
import "package:webview_windows/webview_windows.dart" as win_wv;

import "package:inventree/api.dart";
import "package:inventree/app_colors.dart";
import "package:inventree/helpers.dart";
import "package:inventree/l10.dart";
import "package:inventree/user_profile.dart";
import "package:inventree/inventree/sentry.dart";

class InvenTreeSSOLoginWidget extends StatefulWidget {
  const InvenTreeSSOLoginWidget(this.profile, {super.key});

  final UserProfile profile;

  @override
  State<InvenTreeSSOLoginWidget> createState() =>
      _InvenTreeSSOLoginWidgetState();
}

class _InvenTreeSSOLoginWidgetState extends State<InvenTreeSSOLoginWidget> {
  // Windows Desktop controller
  final win_wv.WebviewController _windowsController =
      win_wv.WebviewController();
  final List<StreamSubscription<dynamic>> _windowsSubscriptions = [];
  String _currentWindowsUrl = "";

  // Mobile / macOS controller
  late final WebViewController _mobileController;

  bool _isInitialized = false;
  String? _initializationError;
  double _loadingProgress = 0.0;
  bool _isExtractingToken = false;
  bool _tokenReceived = false;
  String _statusMessage = "";

  String get _loginUrl {
    String server = widget.profile.server.trim();
    if (!server.endsWith("/")) {
      server += "/";
    }
    return "${server}accounts/login/";
  }

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows) {
      _initWindowsWebView();
    } else {
      _initMobileWebView();
    }
  }

  @override
  void dispose() {
    for (final s in _windowsSubscriptions) {
      s.cancel();
    }
    if (Platform.isWindows) {
      _windowsController.dispose();
    }
    super.dispose();
  }

  /*
   * Initialize WebView2 on Windows desktop
   */
  Future<void> _initWindowsWebView() async {
    try {
      await _windowsController.initialize();

      _windowsSubscriptions.add(
        _windowsController.url.listen((url) {
          _currentWindowsUrl = url;
          _checkLoginStatus(url);
        }),
      );

      _windowsSubscriptions.add(
        _windowsController.loadingState.listen((state) {
          if (mounted) {
            setState(() {
              _loadingProgress =
                  state == win_wv.LoadingState.loading ? 0.5 : 1.0;
            });
          }
          if (state == win_wv.LoadingState.navigationCompleted) {
            _checkLoginStatus(_currentWindowsUrl);
          }
        }),
      );

      _windowsSubscriptions.add(
        _windowsController.webMessage.listen((dynamic message) {
          _handleTokenPayload(message);
        }),
      );

      await _windowsController.setBackgroundColor(Colors.transparent);
      await _windowsController.setPopupWindowPolicy(
        win_wv.WebviewPopupWindowPolicy.sameWindow,
      );
      await _windowsController.loadUrl(_loginUrl);

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      debug("Windows WebView init error: $e");
      if (mounted) {
        setState(() {
          _initializationError = e.toString();
        });
      }
    }
  }

  /*
   * Initialize webview_flutter on Android, iOS and macOS
   */
  void _initMobileWebView() {
    try {
      _mobileController = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..addJavaScriptChannel(
          "InvenTreeChannel",
          onMessageReceived: (JavaScriptMessage message) {
            _handleTokenPayload(message.message);
          },
        )
        ..setNavigationDelegate(
          NavigationDelegate(
            onProgress: (int progress) {
              if (mounted) {
                setState(() {
                  _loadingProgress = progress / 100.0;
                });
              }
            },
            onPageStarted: (String url) {
              _checkLoginStatus(url);
            },
            onPageFinished: (String url) {
              if (mounted) {
                setState(() {
                  _loadingProgress = 1.0;
                });
              }
              _checkLoginStatus(url);
            },
            onWebResourceError: (WebResourceError error) {
              debug(
                "SSO WebView error: ${error.description} (code: ${error.errorCode})",
              );
            },
          ),
        )
        ..loadRequest(Uri.parse(_loginUrl));

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      debug("Mobile WebView init error: $e");
      if (mounted) {
        setState(() {
          _initializationError = e.toString();
        });
      }
    }
  }

  /*
   * Check whether current page indicates the user might now be authenticated.
   * Runs whenever page changes or finishes loading on the InvenTree host.
   */
  Future<void> _checkLoginStatus(String url) async {
    if (_isExtractingToken || _tokenReceived) return;

    final serverUri = Uri.tryParse(widget.profile.server);
    final currentUri = Uri.tryParse(url);

    if (serverUri == null || currentUri == null) return;

    // Only inspect when navigating within the InvenTree domain
    if (serverUri.host.toLowerCase() != currentUri.host.toLowerCase()) {
      return;
    }

    // Still displaying the bare login form (and not a callback)
    if (currentUri.path.contains("accounts/login") && !url.contains("code=")) {
      return;
    }

    await _extractToken();
  }

  /*
   * Execute JavaScript in the authenticated web session to query the API token
   */
  Future<void> _extractToken() async {
    if (_isExtractingToken || _tokenReceived) return;

    _isExtractingToken = true;

    String platformName = "inventree-app";
    try {
      final deviceInfo = await getDeviceInfo();
      if (Platform.isAndroid) {
        platformName += "-android";
      } else if (Platform.isIOS) {
        platformName += "-ios";
      } else if (Platform.isWindows) {
        platformName += "-windows";
      } else if (Platform.isMacOS) {
        platformName += "-macos";
      } else if (Platform.isLinux) {
        platformName += "-linux";
      }

      if (deviceInfo.containsKey("name")) {
        platformName += "-${deviceInfo['name']}";
      }
    } catch (_) {}

    // JavaScript to request the user's API token within the authenticated session
    final jsCode = """
      (async function() {
        function sendResult(obj) {
          let str = JSON.stringify(obj);
          try {
            if (window.InvenTreeChannel && window.InvenTreeChannel.postMessage) {
              window.InvenTreeChannel.postMessage(str);
            }
          } catch(e) {}
          try {
            if (window.chrome && window.chrome.webview && window.chrome.webview.postMessage) {
              window.chrome.webview.postMessage(str);
            }
          } catch(e) {}
          return str;
        }

        try {
          // Check if session is logged in
          let meRes = await fetch('/api/user/me/', {
            headers: {'X-Requested-With': 'XMLHttpRequest'},
            credentials: 'include'
          });
          if (meRes.status !== 200) {
            return sendResult({status: 'unauthenticated', code: meRes.status});
          }

          // Request API token from modern endpoint
          let tokenRes = await fetch('/api/user/me/token/?name=${platformName}', {
            headers: {'X-Requested-With': 'XMLHttpRequest'},
            credentials: 'include'
          });
          if (tokenRes.status === 200) {
            let data = await tokenRes.json();
            if (data && data.token) {
              return sendResult({status: 'ok', token: data.token});
            }
          }

          // Fallback to legacy token endpoint
          let oldTokenRes = await fetch('/api/user/token/?name=${platformName}', {
            headers: {'X-Requested-With': 'XMLHttpRequest'},
            credentials: 'include'
          });
          if (oldTokenRes.status === 200) {
            let data = await oldTokenRes.json();
            if (data && data.token) {
              return sendResult({status: 'ok', token: data.token});
            }
          }

          return sendResult({status: 'no_token', meStatus: meRes.status});
        } catch(e) {
          return sendResult({status: 'error', error: e.toString()});
        }
      })();
    """;

    try {
      if (Platform.isWindows) {
        final res = await _windowsController.executeScript(jsCode);
        if (res != null) {
          _handleTokenPayload(res);
        }
      } else {
        final rawResult =
            await _mobileController.runJavaScriptReturningResult(jsCode);
        _handleTokenPayload(rawResult);
      }
    } catch (e) {
      debug("SSO token check exception: $e");
    } finally {
      _isExtractingToken = false;
    }
  }

  /*
   * Handle incoming token payload from message channels or script execution
   */
  void _handleTokenPayload(dynamic raw) {
    if (_tokenReceived || !mounted) return;
    if (raw == null) return;

    try {
      dynamic data = raw;
      if (data is String) {
        // Strip extra outer quotes if wrapped
        if (data.startsWith('"') && data.endsWith('"') && data.length > 1) {
          try {
            data = jsonDecode(data);
          } catch (_) {}
        }
        if (data is String) {
          data = jsonDecode(data);
        }
      }

      if (data is Map<String, dynamic>) {
        if (data["status"] == "ok" &&
            data["token"] != null &&
            (data["token"] as String).isNotEmpty) {
          _onTokenReceived(data["token"] as String);
        }
      }
    } catch (e) {
      debug("Error parsing SSO token payload: $e");
    }
  }

  /*
   * Complete SSO authentication once API token is retrieved
   */
  Future<void> _onTokenReceived(String token) async {
    if (_tokenReceived) return;
    _tokenReceived = true;

    debug(
      "SSO Login successful, received token: ${token.substring(0, token.length > 8 ? 8 : token.length)}...",
    );

    if (mounted) {
      setState(() {
        _statusMessage = L10().serverConnecting;
      });
    }

    widget.profile.token = token;
    await UserProfileDBManager().updateProfile(widget.profile);
    await InvenTreeAPI().connectToServer(widget.profile);

    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  Widget _buildWebView() {
    if (_initializationError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(TablerIcons.alert_triangle, size: 64, color: COLOR_DANGER),
              const SizedBox(height: 16),
              Text(
                "SSO WebView konnte nicht initialisiert werden",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _initializationError!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                icon: Icon(TablerIcons.world),
                label: Text("Im Standard-Browser öffnen"),
                onPressed: () {
                  launchUrl(
                    Uri.parse(_loginUrl),
                    mode: LaunchMode.externalApplication,
                  );
                },
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                icon: Icon(TablerIcons.refresh),
                label: Text(L10().refresh),
                onPressed: () {
                  setState(() {
                    _initializationError = null;
                    _isInitialized = false;
                  });
                  if (Platform.isWindows) {
                    _initWindowsWebView();
                  } else {
                    _initMobileWebView();
                  }
                },
              ),
            ],
          ),
        ),
      );
    }

    if (!_isInitialized) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: COLOR_PROGRESS),
            const SizedBox(height: 16),
            Text(L10().serverConnecting),
          ],
        ),
      );
    }

    if (Platform.isWindows) {
      return win_wv.Webview(_windowsController);
    } else {
      return WebViewWidget(controller: _mobileController);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(L10().ssoLogin),
            Text(
              widget.profile.server,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(TablerIcons.refresh),
            tooltip: L10().refresh,
            onPressed: () {
              if (_isInitialized) {
                if (Platform.isWindows) {
                  _windowsController.reload();
                } else {
                  _mobileController.reload();
                }
              }
              _extractToken();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (_loadingProgress < 1.0 || _isExtractingToken)
            LinearProgressIndicator(
              value: _isExtractingToken ? null : _loadingProgress,
              color: COLOR_PROGRESS,
            ),
          if (_statusMessage.isNotEmpty)
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              color: COLOR_PROGRESS.withValues(alpha: 0.15),
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: COLOR_PROGRESS,
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _statusMessage,
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(child: _buildWebView()),
        ],
      ),
    );
  }
}
