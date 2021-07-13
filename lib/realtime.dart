part of appwrite;

class RealtimeSubscription {
  final Stream stream;
  final Function close;

  RealtimeSubscription({required this.stream, required this.close});
}

class Realtime extends Service {
  WebSocketChannel? _websok;

  String? _lastUrl;
  late Map<String, List<StreamController>> channels;
  Map<String, dynamic>? lastMessage;

  Realtime(Client client) : super(client) {
    channels = {};
  }

  _closeConnection() {
    _websok?.sink.close(normalClosure);
  }

  createSocket() async {
    //close existing connection
    final endPoint = client.endPointRealtime;
    final project = client.headers!['X-Appwrite-Project'];
    if (endPoint == null) return;
    var uri = Uri.parse(endPoint);
    uri = Uri(
        host: uri.host,
        scheme: uri.scheme,
        port: uri.port,
        queryParameters: {
          "project": project,
          "channels[]": channels.keys,
        },
        path: uri.path + "/realtime");
    if (_lastUrl == uri.toString() && _websok?.closeCode == null) {
      return;
    }
    _closeConnection();
    _lastUrl = uri.toString();
    print('subscription: $_lastUrl');
    Map<String, String>? headers;
    if (!client.initialized) await client.init();
    if (!kIsWeb) {
      final cookies = await client.cookieJar.loadForRequest(uri);
      headers = {HttpHeaders.cookieHeader: CookieManager.getCookies(cookies)};
    }
    _websok = WebSocketChannel.connect(uri, headers: headers);
    _websok?.stream.listen((event) {
      final data = jsonDecode(event);
      lastMessage = data;
      if (data['channels'] != null) {
        List<String> received = List<String>.from(data['channels']);
        received.forEach((channel) {
          if (channels[channel] != null) {
            channels[channel]!.forEach((stream) {
              stream.sink.add(event);
            });
          }
        });
      }
    });
  }

  RealtimeSubscription subscribe(List<String> channels) {
    StreamController controller = StreamController();
    channels.forEach((channel) {
      if (!this.channels.containsKey(channel)) {
        this.channels[channel] = [];
      }
      this.channels[channel]!.add(controller);
    });
    Future.delayed(Duration.zero, () => this.createSocket());
    RealtimeSubscription subscription = RealtimeSubscription(
        stream: controller.stream,
        close: () {
          controller.close();
          channels.forEach((channel) {
            this.channels[channel]!.remove(controller);
            if (this.channels[channel]!.length < 1) {
              this.channels.remove(channel);
            }
          });
          Future.delayed(Duration.zero, () => this.createSocket());
        });
    return subscription;
  }
}