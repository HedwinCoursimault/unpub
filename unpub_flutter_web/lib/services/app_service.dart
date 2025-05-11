import 'dart:convert';
import 'package:http/http.dart' as http;

class AppService {
  final String baseUrl = ''; // vide = même domaine

  Future<List<String>> getPackageList() async {
    final uri = Uri.parse('$baseUrl/api/packages');
    final response = await http.get(uri);
    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      final list = json as List;
      return list.map((e) => e['name'].toString()).toList();
    } else {
      throw Exception('Échec du chargement des packages');
    }
  }

  Future<String> getPackageDetail(String name) async {
    final uri = Uri.parse('$baseUrl/api/packages/$name');
    final response = await http.get(uri);
    if (response.statusCode == 200) {
      return response.body;
    } else {
      throw Exception('Package $name introuvable');
    }
  }
}
