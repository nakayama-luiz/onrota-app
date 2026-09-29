import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/trip.dart';

/// Serviço para comunicação com a API
class ApiService {
  static const String baseUrl = 'https://onrota.nakafest.site';

  /// Headers das rotas do motorista: o token da corrida substitui a api key.
  static Map<String, String> headers(String token) => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

  /// Login do motorista (CPF + placa). Devolve as corridas abertas dele em
  /// todos os clientes. Lança [Exception] com a mensagem para o usuário.
  static Future<List<Trip>> login(String cpf, String placa) async {
    final http.Response response;
    try {
      response = await http.post(
        Uri.parse('$baseUrl/auth/driver/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'cpf': cpf, 'placa': placa}),
      );
    } catch (e) {
      debugPrint('Erro no login: $e');
      throw Exception('Sem conexão com o servidor. Verifique sua internet.');
    }

    if (response.statusCode == 200) {
      final items = (jsonDecode(response.body)['trips'] as List).cast<Map<String, dynamic>>();
      return items.map(Trip.fromLogin).toList();
    }

    String message = 'Erro ${response.statusCode} ao entrar.';
    try {
      message = jsonDecode(response.body)['error'] ?? message;
    } catch (_) {}
    throw Exception(message);
  }
}
