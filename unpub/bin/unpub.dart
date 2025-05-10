import 'dart:io';
import 'package:args/args.dart';
import 'package:path/path.dart' as path;
import 'package:postgres/postgres.dart';
import 'package:unpub/unpub.dart' as unpub;
import 'package:unpub/src/sql_store.dart'; 

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('host', abbr: 'h', defaultsTo: '0.0.0.0')
    ..addOption('port', abbr: 'p', defaultsTo: '4000')
    ..addOption(
      'database',
      abbr: 'd',
      defaultsTo: 'postgres://user:password@localhost:5432/unpub',
      help: 'PostgreSQL URI for the metadata store',
    )
    ..addOption('proxy-origin', abbr: 'o', defaultsTo: '');

  final results = parser.parse(args);

  if (results.rest.isNotEmpty) {
    print('Got unexpected arguments: "${results.rest.join(' ')}".\n\nUsage:\n');
    print(parser.usage);
    exit(1);
  }

  final host = results['host'] as String;
  final port = int.parse(results['port'] as String);
  final dbUri = results['database'] as String;
  final proxyOriginRaw = results['proxy-origin'] as String;
  final proxyOrigin =
      proxyOriginRaw.trim().isEmpty ? null : Uri.parse(proxyOriginRaw);

  final uri = Uri.parse(dbUri);
  if (uri.scheme != 'postgres') {
    stderr.writeln('Only postgres:// URI is supported for --database');
    exit(2);
  }

  final db = PostgreSQLConnection(
    uri.host,
    uri.port,
    uri.pathSegments.first,
    username: uri.userInfo.split(":").first,
    password:
        uri.userInfo.contains(":") ? uri.userInfo.split(":")[1] : null,
  );

  SqlStore store;

  try {
    await db.open();
    store = SqlStore(db);
    await store.initDb();
  } catch (e) {
    stderr.writeln('Failed to connect to PostgreSQL: $e');
    exit(2);
  }

  final baseDir = path.absolute('unpub-packages');

  final app = unpub.App(
    metaStore: store,
    packageStore: unpub.FileStore(baseDir),
    proxy_origin: proxyOrigin,
    overrideUploaderEmail: 'dev@localhost',
  );

  final server = await app.serve(host, port);
  print('✅ Unpub PostgreSQL server ready at http://${server.address.host}:${server.port}');
}
