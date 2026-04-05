import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/trip.dart';

/// Serviço para comunicação com a API
class ApiService {
  static const String baseUrl = 'https://onrota.nakafest.site';

  /// Valida uma key buscando informações da trip
  /// Retorna a Trip se sucesso, null se key inválida ou erro
  static Future<Trip?> validateKey(String key) async {
    try {
      final url = '$baseUrl/public/trip/key/$key';
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'x-api-key': '123',
      };
      final response = await http.get(Uri.parse(url), headers: headers);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return Trip.fromJson(data);
      }
      return null;
    } catch (e) {
      print('Erro ao validar key: $e');
      return null;
    }
  }
}
