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
    );
  }
}
