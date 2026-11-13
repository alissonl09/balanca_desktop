import 'dart:io';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stdout.writeln('Informe uma URL HTTPS sem credenciais ou segredos.');
    exitCode = 64;
    return;
  }
  final uri = Uri.tryParse(arguments.single);
  if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty) {
    stdout.writeln('URL HTTPS inválida.');
    exitCode = 64;
    return;
  }
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final response = await (() async {
      final request = await client.getUrl(uri);
      request.followRedirects = false;
      return request.close();
    })().timeout(const Duration(seconds: 15));
    stdout.writeln(
      'HTTP=${response.statusCode}; TLS=validado pelo Dart; credencial enviada=não',
    );
  } on HandshakeException {
    stdout.writeln('TLS=falha de handshake/certificado; HTTP=indisponível');
  } catch (e) {
    stdout.writeln('Falha=${e.runtimeType}; HTTP=indisponível');
  } finally {
    client.close(force: true);
  }
}
