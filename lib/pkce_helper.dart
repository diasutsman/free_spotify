import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

class PKCEHelper {
  static String generateCodeVerifier([int length = 128]) {
    final random = Random.secure();
    final values = List<int>.generate(length, (_) => random.nextInt(256));
    return base64UrlEncode(values).replaceAll('=', '');
  }

  static String generateCodeChallenge(String codeVerifier) {
    final bytes = utf8.encode(codeVerifier);
    final digest = sha256.convert(bytes);
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }
}
