/// Modelo para representar uma Trip retornada pela API
class Trip {
  final int id;
  final String label; // placa
  final String description;
  final String status;
  final int startingPointId;
  final int endingPointId;
  final String key;
  final int driverId;
  final String driverName;
  final String startingPointName;
  final String endingPointName;

  /// Cliente (tenant) dono da corrida — o mesmo motorista pode ter corridas
  /// em clientes diferentes.
  final String tenantName;

  /// Token da corrida emitido no login. Vai no header `Authorization` de
  /// `/log` e `/public/trip/key/:key` e só vale para esta corrida.
  final String token;

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
    this.tenantName = '',
    this.token = '',
  });

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
      tenantName: json['tenant_name'] ?? '',
      token: json['token'] ?? '',
    );
  }

  /// Item de `POST /auth/driver/login`: `{ tenant, trip, token }`.
  factory Trip.fromLogin(Map<String, dynamic> item) {
    return Trip.fromJson({
      ...Map<String, dynamic>.from(item['trip'] as Map),
      'tenant_name': (item['tenant'] as Map?)?['name'] ?? '',
      'token': item['token'] ?? '',
    });
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'description': description,
        'status': status,
        'starting_point_id': startingPointId,
        'ending_point_id': endingPointId,
        'key': key,
        'driver_id': driverId,
        'driver_name': driverName,
        'starting_point_name': startingPointName,
        'ending_point_name': endingPointName,
        'tenant_name': tenantName,
        'token': token,
      };
}
