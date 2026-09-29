import 'package:flutter_test/flutter_test.dart';
import 'package:detalhes/models/trip.dart';

void main() {
  // Item de `POST /auth/driver/login` -> { trips: [ <item>, ... ] }
  final item = {
    'tenant': {'id': 2, 'name': 'Beta Log'},
    'token': 'jwt-da-corrida',
    'trip': {
      'id': 90,
      'label': 'ABC1D23',
      'description': '',
      'status': 'PLANNED',
      'starting_point_id': 1,
      'ending_point_id': 2,
      'key': 'ROTA-001',
      'driver_id': 7,
      'driver_name': 'João',
      'starting_point_name': 'Origem',
      'ending_point_name': 'Destino',
    },
  };

  test('Trip.fromLogin junta corrida, tenant e token', () {
    final trip = Trip.fromLogin(item);
    expect(trip.id, 90);
    expect(trip.key, 'ROTA-001');
    expect(trip.label, 'ABC1D23');
    expect(trip.tenantName, 'Beta Log');
    expect(trip.token, 'jwt-da-corrida');
  });

  test('toJson/fromJson preserva token e tenant (persistência local)', () {
    final restored = Trip.fromJson(Trip.fromLogin(item).toJson());
    expect(restored.token, 'jwt-da-corrida');
    expect(restored.tenantName, 'Beta Log');
    expect(restored.key, 'ROTA-001');
    expect(restored.driverName, 'João');
  });

  test('Trip salva por versão antiga do app (sem token) não quebra', () {
    final old = Trip.fromJson({'id': 1, 'key': 'K'});
    expect(old.token, '');
    expect(old.tenantName, '');
  });
}
