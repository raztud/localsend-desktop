// lib/config.dart

class AppConfig {
  // Server settings for when THIS app instance acts as a server
  static const String defaultServerHost = '0.0.0.0'; // Listen on all available network interfaces
  static const int defaultServerPort = 8080;

  // You could also add default client target IP/Port here if desired
  // static const String defaultClientTargetIp = '192.168.1.100';
  // static const int defaultClientTargetPort = 8080;
}
