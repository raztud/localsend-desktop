import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static const String serverHostKey = 'server_host';
  static const String serverPortKey = 'server_port';

  // Default values
  static const String defaultHost = '0.0.0.0';
  // static const int defaultPort = 8080;
  final Random _random = Random();

  int _getRandomPort() {
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

  Future<int> getServerPort({bool preferRandom = false}) async {
    final prefs = await SharedPreferences.getInstance();
    int? storedPort = prefs.getInt(serverPortKey);

    if (preferRandom || storedPort == null || storedPort == 0) {
      // If preferRandom is true, or no port is stored, or stored port is 0 (our convention for random)
      int randomPort = _getRandomPort();
      // Optionally, you might want to save this randomly chosen port
      // await prefs.setInt(serverPortKey, randomPort); // Uncomment to save the chosen random port
      print("ℹ️ Using random port: $randomPort");
      return randomPort;
    }
    return storedPort;
  }

  Future<void> setServerPort(int port) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(serverPortKey, port);
  }

  Future<void> setServerPortToRandom() async {
    final prefs = await SharedPreferences.getInstance();
    // Storing 0 can be a convention to mean "use random on next start"
    await prefs.setInt(serverPortKey, 0);
    print("ℹ️ Server port set to pick random on next start.");
  }

}
