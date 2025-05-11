import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/app_service.dart';
import '../widgets/app_scaffold.dart';

class PackageListPage extends StatefulWidget {
  const PackageListPage({super.key});

  @override
  State<PackageListPage> createState() => _PackageListPageState();
}

class _PackageListPageState extends State<PackageListPage> {
  List<String> _packages = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPackages();
  }

  Future<void> _loadPackages() async {
    final packages = await AppService().getPackageList();
    setState(() {
      _packages = packages;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Liste des packages',
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _packages.length,
              itemBuilder: (context, index) {
                final name = _packages[index];
                return ListTile(
                  title: Text(name),
                  onTap: () => context.go('/packages/$name'),
                );
              },
            ),
    );
  }
}
