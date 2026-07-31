import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/trip.dart';

enum TripLookupStatus {
  success,
  missingApiKey,
  invalidApiKey,
  notFound,
  networkError,
  serverError,
}

class TripLookupResult {
  final Trip? trip;
  final TripLookupStatus status;
  final String? message;

  const TripLookupResult({
    required this.trip,
    required this.status,
    this.message,
  });

  bool get isSuccess => status == TripLookupStatus.success;
}

/// Serviço para comunicação com a API
class ApiService {
  static const String baseUrl = 'https://onrota.nakafest.site';

  static Map<String, String> _headers(String apiKey) {
    return <String, String>{
      'Content-Type': 'application/json',
      'x-api-key': apiKey.trim(),
    };
  }

  /// Valida uma key buscando informações da trip
  /// Retorna o resultado da consulta e o status específico de falha
  static Future<TripLookupResult> validateKey(
    String key, {
    required String apiKey,
  }) async {
    final normalizedApiKey = apiKey.trim();
    if (normalizedApiKey.isEmpty) {
      return const TripLookupResult(
        trip: null,
        status: TripLookupStatus.missingApiKey,
        message: 'Configure a API key do cliente antes de validar a key.',
      );
    }

    try {
      final url = '$baseUrl/public/trip/key/$key';
      final response = await http.get(
        Uri.parse(url),
        headers: _headers(normalizedApiKey),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return TripLookupResult(
          trip: Trip.fromJson(data),
          status: TripLookupStatus.success,
        );
      }

      if (response.statusCode == 403) {
        return const TripLookupResult(
          trip: null,
          status: TripLookupStatus.invalidApiKey,
          message: 'A API key do cliente está inválida ou foi revogada.',
        );
      }

      if (response.statusCode == 404) {
        return const TripLookupResult(
          trip: null,
          status: TripLookupStatus.notFound,
          message: 'Trip não encontrada para este cliente.',
        );
      }

      return TripLookupResult(
        trip: null,
        status: TripLookupStatus.serverError,
        message: 'Erro ${response.statusCode}: ${response.body}',
      );
    } catch (e) {
      return TripLookupResult(
        trip: null,
        status: TripLookupStatus.networkError,
        message: 'Erro ao validar key: $e',
      );
    }
  }
}
