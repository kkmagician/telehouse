import 'dart:convert' show jsonDecode, jsonEncode, utf8;
import 'dart:io' show File, stdin, stderr, exitCode;
import 'package:http/http.dart' as http;
import 'package:args/args.dart';

class Metric {
  String name;
  int timestamp;
  Map<String, dynamic> tags;
  Map<String, dynamic> fields;

  Metric({this.name, this.timestamp, this.tags, this.fields});

  factory Metric.fromJson(Map<String, dynamic> parsedJson) {
    return Metric(
        name: parsedJson['name'],
        timestamp: parsedJson.containsKey('timestamp') ? parsedJson['timestamp'] : 0,
        tags: parsedJson.containsKey('tags') ? parsedJson['tags'] : {},
        fields: parsedJson['fields']
    );
  }

  String toValue(bool checkQuotes) {
    var tagsString = jsonEncode(tags);
    var fieldsString = jsonEncode(fields);

    if (checkQuotes) {
      tagsString = tagsString.replaceAll("'", "''");
      fieldsString = fieldsString.replaceAll("'", "''");
    }

    return "('$name',$timestamp,'$tagsString','$fieldsString')";
  }
}

class Metrics {
  List<Metric> events;
  Metrics({this.events});

  factory Metrics.fromJson(Map<String, dynamic> parsedJson) {
    return Metrics(
      events: List<Map<String, dynamic>>
        .from(parsedJson['metrics'])
        .map((e) => Metric.fromJson(e))
        .toList()
    );
  }
}

List<Metric> parseMetrics(String jsonString) {
  final json = jsonDecode(jsonString);
  try {
    return Metrics.fromJson(json).events;
  } catch (e) {
    return [Metric.fromJson(json)];
  }
}

Future<String> sendData({
  String table,
  List<Metric> metrics,
  String host,
  String user,
  String pass,
  bool checkQuotes
}) {
  final values = metrics.map((e) => e.toValue(checkQuotes)).join(',');
  final request = 'INSERT INTO $table (name, timestamp, tags, fields) VALUES ' + values;
  final url = host + '/?user=$user&password=$pass';

  return http.post(url, body: request).then((value) => value.body);
}

Future<String> readStdinDataString() =>
    stdin.asyncMap((event) => utf8.decode(event)).join();

void showError(String message, {int code = 1}) {
  exitCode = code;
  stderr.writeln(message);
}

void main(List<String> arguments) async {
  exitCode = 0;

  final argParser = ArgParser()
    ..addOption('table', abbr: 't', defaultsTo: 'default.telehouse')
    ..addOption('user', abbr: 'u', defaultsTo: 'default')
    ..addOption('pass', abbr: 'p', defaultsTo: '')
    ..addOption('host', abbr: 'h', defaultsTo: 'http://localhost:8123')
    ..addOption('passFile', abbr: 'f', defaultsTo: '')
    ..addFlag('checkQuotes', abbr: 'q', defaultsTo: false);

  final args = argParser.parse(arguments);

  final table = args['table'];
  final host = args['host'];
  final user = args['user'];
  final bool checkQuotes = args['checkQuotes'];
  var pass = args['pass'];

  if (pass == '' && args['passFile'] != '') {
    try {
      pass = File(args['passFile']).readAsStringSync();
    } catch (e) {
      showError("Could not open the password file with $e");
      return;
    }
  }

  await stdin.asyncMap((event) => utf8.decode(event))
        .join()
        .then((value) =>
          parseMetrics(value),
          onError: (_) => showError('Could not parse JSON metrics from the given data'))
        .then((metrics) =>
          sendData(table: table, metrics: metrics, host: host, user: user, pass: pass, checkQuotes: checkQuotes),
          onError: (_) => showError('Could not perform the HTTP insert')
        ).then((response) =>
          response != '' ? showError('Insert has failed with the error: $response') : '');
}
