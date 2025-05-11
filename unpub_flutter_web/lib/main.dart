import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'pages/home_page.dart';
import 'pages/package_list_page.dart';
import 'pages/package_details_page.dart';

void main() {
  runApp(const UnpubApp());
}

class UnpubApp extends StatelessWidget {
  const UnpubApp({super.key});

  @override
  Widget build(BuildContext context) {
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (context, state) => const PackageListPage()),
        GoRoute(path: '/packages', builder: (context, state) => const PackageListPage()),
        GoRoute(
          path: '/packages/:name',
          builder: (context, state) {
            final name = state.pathParameters['name']!;
            return PackageDetailPage(packageName: name);
          },
        ),
      ],
    );

    return MaterialApp.router(
      title: 'Unpub Flutter Web',
      theme: ThemeData(primarySwatch: Colors.blue),
      routerConfig: router,
    );
  }
}
