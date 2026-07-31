import 'package:detalhes/models/trip.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Trip serializes and deserializes expected fields', () {
    final trip = Trip(
      id: 7,
      label: 'Rota teste',
      description: 'Descrição',
      status: 'PLANNED',
      startingPointId: 1,
      endingPointId: 2,
      key: 'ROTA-001',
      driverId: 99,
      driverName: 'Motorista Teste',
      startingPointName: 'Origem',
      endingPointName: 'Destino',
      loadingLatitude: -23.1,
      loadingLongitude: -46.2,
      loadingName: 'Carga',
      unloadingLatitude: -23.3,
      unloadingLongitude: -46.4,
      unloadingName: 'Descarga',
    );

    final json = trip.toJson();
    final restored = Trip.fromJson(json);

    expect(restored.key, trip.key);
    expect(restored.driverName, trip.driverName);
    expect(restored.loadingLatitude, trip.loadingLatitude);
    expect(restored.unloadingName, trip.unloadingName);
  });
}
