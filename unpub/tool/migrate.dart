import 'package:mongo_dart/mongo_dart.dart' as mongo;
import 'package:postgres/postgres.dart';
import 'package:unpub/unpub.dart';

Future<void> main() async {
  // Connexion MongoDB
  final mongoDb = await mongo.Db.create('mongodb://localhost:27017/unpub');
  await mongoDb.open();

  // Connexion PostgreSQL (compatible postgres ^2.6.4)
  final postgres = PostgreSQLConnection(
    'localhost',
    5432,
    'unpub',
    username: 'postgres',
    password: '****',
  );
  await postgres.open();

  migrateFromMongoToPostgre(mongoConnection: mongoDb, postgresConnection: postgres);

  await postgres.close();
  await mongoDb.close();
}
