// lib/settings_service.dart
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static const String serverHostKey = 'server_host';
  static const String serverPortKey = 'server_port';

  // Default values
  static const String defaultHost = '0.0.0.0';
  static const int defaultPort = 8080;

  Future<String> getServerHost() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(serverHostKey) ?? defaultHost;
  }

  Future<void> setServerHost(String host) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(serverHostKey, host);
  }

  Future<int> getServerPort() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(serverPortKey) ?? defaultPort;
  }

  Future<void> setServerPort(int port) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(serverPortKey, port);
  }
}
