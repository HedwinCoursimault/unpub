import 'package:flutter/material.dart';
import '../services/app_service.dart';
import '../widgets/app_scaffold.dart';

class PackageDetailPage extends StatelessWidget {
  final String packageName;

  const PackageDetailPage({super.key, required this.packageName});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: AppService().getPackageDetail(packageName),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const AppScaffold(
            title: 'Chargement...',
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return AppScaffold(
            title: 'Erreur',
            body: Center(child: Text('Erreur : ${snapshot.error}')),
          );
        }
        return AppScaffold(
          title: 'Détail de $packageName',
          body: Text(snapshot.data ?? 'Pas de détails.'),
        );
      },
    );
  }
}
