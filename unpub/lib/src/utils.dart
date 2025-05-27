import 'dart:convert';

import 'package:unpub/src/models.dart';
import 'package:yaml/yaml.dart';
import 'package:mongo_dart/mongo_dart.dart' as mongo;
import 'package:postgres/postgres.dart';

convertYaml(dynamic value) {
  if (value is YamlMap) {
    return value
        .cast<String, dynamic>()
        .map((k, v) => MapEntry(k, convertYaml(v)));
  }
  if (value is YamlList) {
    return value.map((e) => convertYaml(e)).toList();
  }
  return value;
}

Map<String, dynamic>? loadYamlAsMap(dynamic value) {
  var yamlMap = loadYaml(value) as YamlMap?;
  return convertYaml(yamlMap).cast<String, dynamic>();
}

List<String> getPackageTags(Map<String, dynamic> pubspec) {
  // TODO: web and other tags
  if (pubspec['flutter'] != null) {
    return ['flutter'];
  } else {
    return ['flutter', 'web', 'other'];
  }
}


Future<void> migrateFromMongoToPostgre({
  required mongo.Db mongoConnection,
  required PostgreSQLConnection postgresConnection,
}) async {
  final mongoPackages = mongoConnection.collection('packages');
  final mongoStats = mongoConnection.collection('stats');
  try {
    final packages = await mongoPackages.find().toList();
    for (final pkg in packages) {
      final package = UnpubPackage.fromJson(pkg);
      print('Migrating ${package.name}');

      // Insert package (sans uploaders)
      await postgresConnection.query(
        '''
        INSERT INTO packages (name, private, created_at, updated_at, download)
        VALUES (@name, @private, @createdAt, @updatedAt, @download)
        ON CONFLICT (name) DO NOTHING
        ''',
        substitutionValues: {
          'name': package.name,
          'private': package.private,
          'createdAt': package.createdAt.toIso8601String(),
          'updatedAt': package.updatedAt.toIso8601String(),
          'download': package.download ?? 0,
        },
      );

      // Get package_id
      final result = await postgresConnection.query(
        'SELECT id FROM packages WHERE name = @name',
        substitutionValues: {'name': package.name},
      );

      if (result.isEmpty) {
        print('❌ Package ID not found for ${package.name}, skipping');
        continue;
      }

      final packageId = result.first[0] as int;

      // Insert uploaders (dans la table dédiée)
      if (package.uploaders != null) {
        for (final email in package.uploaders!) {
          await postgresConnection.query(
            '''
            INSERT INTO uploaders (package_id, email)
            VALUES (@packageId, @email)
            ON CONFLICT DO NOTHING
            ''',
            substitutionValues: {
              'packageId': packageId,
              'email': email,
            },
          );
        }
      }

      // Insert versions (en reliant à package_id)
      for (final version in package.versions) {
        await postgresConnection.query(
          '''
          INSERT INTO versions (
            package_id, version, pubspec, pubspec_yaml, uploader, readme, changelog, created_at
          )
          VALUES (
            @packageId, @version, @pubspec, @yaml, @uploader, @readme, @changelog, @createdAt
          )
          ON CONFLICT (package_id, version) DO NOTHING
          ''',
          substitutionValues: {
            'packageId': packageId,
            'version': version.version,
            'pubspec': jsonEncode(version.pubspec),
            'yaml': version.pubspecYaml,
            'uploader': version.uploader,
            'readme': version.readme,
            'changelog': version.changelog,
            'createdAt': version.createdAt.toIso8601String(),
          },
        );
      }

      // Insert downloads from stats
      final stats = await mongoStats.findOne({'name': package.name});
      if (stats != null) {
        for (final entry in stats.entries) {
          if (entry.key.startsWith('d')) {
            final dateStr = entry.key.substring(1); // ex: "20240511"
            final count = entry.value as int;

            await postgresConnection.query(
              '''
              INSERT INTO downloads (package_id, date, count)
              VALUES (@id, @date, @count)
              ON CONFLICT (package_id, date) DO UPDATE SET count = EXCLUDED.count
              ''',
              substitutionValues: {
                'id': packageId,
                'date': dateStr,
                'count': count,
              },
            );
          }
        }
      }

      print('✅ Migrated package: ${package.name}');
    }
  } on Exception catch (e) {
    print(e);
  } on Error catch (e) {
    print(e);
  }
}
