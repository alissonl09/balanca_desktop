import 'dart:async';
import 'dart:convert';
import 'dart:io';

class TestHeaders implements HttpHeaders {
  final values = <String, Object>{};
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestRequest implements HttpClientRequest {
  TestRequest(this.result);
  final Future<HttpClientResponse> Function() result;
  final bytes = <int>[];
  @override
  void add(List<int> data) => bytes.addAll(data);
  @override
  final TestHeaders headers = TestHeaders();
  @override
  bool followRedirects = true;
  @override
  Future<HttpClientResponse> close() => result();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestResponse extends Stream<List<int>> implements HttpClientResponse {
  TestResponse(this.statusCode, this.body);
  @override
  final int statusCode;
  final String body;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream.value(utf8.encode(body)).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestClient implements HttpClient {
  TestClient({
    int status = 200,
    String body = '[]',
    Future<HttpClientResponse> Function()? result,
  }) : request = TestRequest(
         result ?? (() async => TestResponse(status, body)),
       );
  final TestRequest request;
  Uri? uri;
  String? method;
  bool closed = false;
  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    method = 'GET';
    uri = url;
    return request;
  }

  @override
  Future<HttpClientRequest> postUrl(Uri url) async {
    method = 'POST';
    uri = url;
    return request;
  }

  @override
  void close({bool force = false}) {
    closed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const payload = '''[{"tipoDocumento":"NF-e","nota":["1","2"],
"emissor":"Cooperativa","motorista":"Motorista de teste",
"transportador":"Transportadora de teste","quantidadeTotal":1234.5,
"embalagem":"Granel","deposito":"JAPY","sequencia":7,
"tipoOperacao":"XFER","numeroTicketOrigem":80,
"codigoUnidadeOrigem":2,"pesoLiquidoOrigem":1200}]''';
