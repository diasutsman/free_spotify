import 'package:envied/envied.dart';

part 'env.g.dart';

@envied
abstract class Env {
  @EnviedField(varName: 'CLIENT_ID', obfuscate: true)
  static String clientId = _Env.clientId;

  @EnviedField(varName: 'CLIENT_SECRET', obfuscate: true)
  static String clientSecret = _Env.clientSecret;
}
