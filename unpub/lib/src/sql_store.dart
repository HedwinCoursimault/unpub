import 'package:postgres/postgres.dart';
import 'meta_store.dart';
import 'models.dart';

class SqlStore extends MetaStore {
  final PostgreSQLConnection connection;

  SqlStore(this.connection);

  Future<void> initDb() async {
  final res = await connection.query("SELECT to_regclass('public.packages')");
  final exists = res.first.first != null;

  if (exists) {
    print('🟢 DB already initialized.');
    return;
  }

  print('⚙️ Initializing PostgreSQL schema...');

  await connection.transaction((ctx) async {
    await ctx.execute('''
      CREATE TABLE packages (
        id SERIAL PRIMARY KEY,
        name TEXT UNIQUE NOT NULL,
        private BOOLEAN NOT NULL DEFAULT TRUE,
        created_at TIMESTAMP NOT NULL,
        updated_at TIMESTAMP NOT NULL,
        download INT NOT NULL DEFAULT 0
      );
    ''');

    await ctx.execute('''
      CREATE TABLE versions (
        id SERIAL PRIMARY KEY,
        package_id INTEGER NOT NULL REFERENCES packages(id) ON DELETE CASCADE,
        version TEXT NOT NULL,
        pubspec JSONB NOT NULL,
        pubspec_yaml TEXT,
        uploader TEXT,
        readme TEXT,
        changelog TEXT,
        created_at TIMESTAMP NOT NULL,
        UNIQUE(package_id, version)
      );
    ''');

    await ctx.execute('''
      CREATE TABLE uploaders (
        package_id INTEGER NOT NULL REFERENCES packages(id) ON DELETE CASCADE,
        email TEXT NOT NULL,
        UNIQUE(package_id, email)
      );
    ''');

    await ctx.execute('''
      CREATE TABLE downloads (
        package_id INTEGER NOT NULL REFERENCES packages(id) ON DELETE CASCADE,
        date TEXT NOT NULL,
        count INT NOT NULL DEFAULT 0,
        PRIMARY KEY (package_id, date)
      );
    ''');

    print('✅ Schema initialized.');
  });
}


  @override
  Future<UnpubPackage?> queryPackage(String name) async {
    final result = await connection.query(
      '''SELECT id, name, private, created_at, updated_at, download FROM packages WHERE name = @name''',
      substitutionValues: {'name': name},
    );

    if (result.isEmpty) return null;

    final row = result.first;
    final packageId = row[0];

    final versionsRes = await connection.query(
      '''SELECT version, pubspec, pubspec_yaml, uploader, readme, changelog, created_at FROM versions WHERE package_id = @id''',
      substitutionValues: {'id': packageId},
    );

    final uploadersRes = await connection.query(
      '''SELECT email FROM uploaders WHERE package_id = @id''',
      substitutionValues: {'id': packageId},
    );

    final versions = versionsRes.map((v) => UnpubVersion(
      v[0], v[1], v[2], v[3], v[4], v[5], v[6]
    )).toList();

    return UnpubPackage(
      row[1], // name
      versions,
      row[2], // private
      uploadersRes.map((u) => u[0] as String).toList(),
      row[3], // created_at
      row[4], // updated_at
      row[5], // download
    );
  }

  @override
  Future<void> addVersion(String name, UnpubVersion version) async {
    await connection.transaction((ctx) async {
      final pkg = await ctx.query(
        '''SELECT id FROM packages WHERE name = @name''',
        substitutionValues: {'name': name},
      );

      int pkgId;
      if (pkg.isEmpty) {
        final insert = await ctx.query(
          '''INSERT INTO packages (name, created_at, updated_at) VALUES (@name, @created, @updated) RETURNING id''',
          substitutionValues: {
            'name': name,
            'created': version.createdAt,
            'updated': version.createdAt,
          },
        );
        pkgId = insert.first[0];
      } else {
        pkgId = pkg.first[0];
        await ctx.execute(
          '''UPDATE packages SET updated_at = @updated WHERE id = @id''',
          substitutionValues: {
            'updated': version.createdAt,
            'id': pkgId,
          },
        );
      }

      await ctx.query(
        '''INSERT INTO versions (package_id, version, pubspec, pubspec_yaml, uploader, readme, changelog, created_at)
           VALUES (@pkgId, @version, @pubspec, @yaml, @uploader, @readme, @changelog, @created)''',
        substitutionValues: {
          'pkgId': pkgId,
          'version': version.version,
          'pubspec': version.pubspec,
          'yaml': version.pubspecYaml,
          'uploader': version.uploader,
          'readme': version.readme,
          'changelog': version.changelog,
          'created': version.createdAt,
        },
      );

      if (version.uploader != null) {
        await ctx.execute(
          '''INSERT INTO uploaders (package_id, email)
             VALUES (@pkgId, @uploader)
             ON CONFLICT DO NOTHING''',
          substitutionValues: {
            'pkgId': pkgId,
            'uploader': version.uploader,
          },
        );
      }
    });
  }
@override
Future<void> addUploader(String name, String email) async {
  final res = await connection.query(
    'SELECT id FROM packages WHERE name = @name',
    substitutionValues: {'name': name},
  );
  if (res.isEmpty) return;

  final pkgId = res.first[0];
  await connection.query(
    '''
    INSERT INTO uploaders (package_id, email)
    VALUES (@pkgId, @mail)
    ON CONFLICT DO NOTHING
    ''',
    substitutionValues: {'pkgId': pkgId, 'mail': email},
  );
}

@override
Future<void> removeUploader(String name, String email) async {
  final res = await connection.query(
    'SELECT id FROM packages WHERE name = @name',
    substitutionValues: {'name': name},
  );
  if (res.isEmpty) return;

  final pkgId = res.first[0];
  await connection.query(
    '''
    DELETE FROM uploaders
    WHERE package_id = @pkgId AND email = @mail
    ''',
    substitutionValues: {'pkgId': pkgId, 'mail': email},
  );
}

@override
void increaseDownloads(String name, String version) async {
  final res = await connection.query(
    'SELECT id FROM packages WHERE name = @name',
    substitutionValues: {'name': name},
  );
  if (res.isEmpty) return;
  final pkgId = res.first[0];
  final today = DateTime.now();
  final dayKey = "${today.year}${today.month.toString().padLeft(2, '0')}${today.day.toString().padLeft(2, '0')}";

  await connection.query('''
    INSERT INTO downloads (package_id, date, count)
    VALUES (@pkgId, @date, 1)
    ON CONFLICT (package_id, date) DO UPDATE
    SET count = downloads.count + 1
  ''', substitutionValues: {'pkgId': pkgId, 'date': dayKey});

  await connection.query('''
    UPDATE packages SET download = download + 1
    WHERE id = @pkgId
  ''', substitutionValues: {'pkgId': pkgId});
}

@override
Future<UnpubQueryResult> queryPackages({
  required int size,
  required int page,
  required String sort,
  String? keyword,
  String? uploader,
  String? dependency,
}) async {
  final offset = page * size;
  final whereClauses = <String>[];
  final params = <String, dynamic>{};

  if (keyword != null) {
    whereClauses.add("name ILIKE @keyword");
    params['keyword'] = '%$keyword%';
  }

  // TODO: uploader / dependency non gérés pour l’instant
  final where = whereClauses.isEmpty ? '' : 'WHERE ' + whereClauses.join(' AND ');

  final result = await connection.query(
    '''
    SELECT id, name, private, created_at, updated_at, download
    FROM packages
    $where
    ORDER BY $sort DESC
    LIMIT @size OFFSET @offset
    ''',
    substitutionValues: {
      ...params,
      'size': size,
      'offset': offset,
    },
  );

  final packages = <UnpubPackage>[];
  for (final row in result) {
    final pkgId = row[0];
    final versionsRes = await connection.query(
      '''SELECT version, pubspec, pubspec_yaml, uploader, readme, changelog, created_at
         FROM versions WHERE package_id = @id''',
      substitutionValues: {'id': pkgId},
    );

    final uploadersRes = await connection.query(
      '''SELECT email FROM uploaders WHERE package_id = @id''',
      substitutionValues: {'id': pkgId},
    );

    final versions = versionsRes.map((v) => UnpubVersion(
      v[0], v[1], v[2], v[3], v[4], v[5], v[6]
    )).toList();

    packages.add(UnpubPackage(
      row[1], // name
      versions,
      row[2], // private
      uploadersRes.map((u) => u[0] as String).toList(),
      row[3], // created_at
      row[4], // updated_at
      row[5], // download
    ));
  }

  final countRes = await connection.query(
    'SELECT COUNT(*) FROM packages $where',
    substitutionValues: params,
  );
  final count = countRes.first[0] as int;

  return UnpubQueryResult(count, packages);
}

}
