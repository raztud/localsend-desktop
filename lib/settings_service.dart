import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static const String serverHostKey = 'server_host';
  static const String serverPortKey = 'server_port';

  // Default values
  static const String defaultHost = '0.0.0.0';
  // static const int defaultPort = 8080;
  final Random _random = Random();

  int generateRandomPortInRange() {
    const minPort = 49152;
    const maxPort = 65535;
    return minPort + _random.nextInt(maxPort - minPort + 1);
  }


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
    return prefs.getInt(serverPortKey) ?? 0; // Default to 0 for random
  }

  Future<void> setServerPort(int port) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(serverPortKey, port);
  }

  Future<void> setServerPortToRandom() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(serverPortKey, 0); // Storing 0 means "use random"
  }

}
