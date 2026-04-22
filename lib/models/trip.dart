/// Modelo para representar uma Trip retornada pela API
class Trip {
  final int id;
  final String label;
  final String description;
  final String status;
  final int startingPointId;
  final int endingPointId;
  final String key;
  final int driverId;
  final String driverName;
  final String startingPointName;
  final String endingPointName;

  // Loading (ponto de partida) - coordenadas opcionais
  final double? loadingLatitude;
  final double? loadingLongitude;
  final String? loadingName;

  // Unloading (ponto de chegada) - coordenadas opcionais
  final double? unloadingLatitude;
  final double? unloadingLongitude;
  final String? unloadingName;

  Trip({
    required this.id,
    required this.label,
    required this.description,
    required this.status,
    required this.startingPointId,
    required this.endingPointId,
    required this.key,
    required this.driverId,
    required this.driverName,
    required this.startingPointName,
    required this.endingPointName,
    this.loadingLatitude,
    this.loadingLongitude,
    this.loadingName,
    this.unloadingLatitude,
    this.unloadingLongitude,
    this.unloadingName,
  });

  /// Verifica se as coordenadas do ponto de partida estão disponíveis
  bool get hasLoadingCoordinates =>
      loadingLatitude != null && loadingLongitude != null;

  /// Verifica se as coordenadas do ponto de chegada estão disponíveis
  bool get hasUnloadingCoordinates =>
      unloadingLatitude != null && unloadingLongitude != null;

  factory Trip.fromJson(Map<String, dynamic> json) {
    return Trip(
      id: json['id'] ?? 0,
      label: json['label'] ?? '',
      description: json['description'] ?? '',
      status: json['status'] ?? '',
      startingPointId: json['starting_point_id'] ?? 0,
      endingPointId: json['ending_point_id'] ?? 0,
      key: json['key'] ?? '',
      driverId: json['driver_id'] ?? 0,
      driverName: json['driver_name'] ?? '',
      startingPointName: json['starting_point_name'] ?? '',
      endingPointName: json['ending_point_name'] ?? '',
      // Loading coordinates (vêm como strings no nível raiz)
      loadingLatitude: _parseDouble(json['loadinglatitude']),
      loadingLongitude: _parseDouble(json['loadinglongitude']),
      loadingName: json['loadingname'] ?? json['starting_point_name'] ?? '',
      // Unloading coordinates (vêm como strings no nível raiz)
      unloadingLatitude: _parseDouble(json['unloadinglatitude']),
      unloadingLongitude: _parseDouble(json['unloadinglongitude']),
      unloadingName: json['unloadingname'] ?? json['ending_point_name'] ?? '',
    );
  }

  /// Helper para converter string ou número em double
  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}
