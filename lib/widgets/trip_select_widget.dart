import 'package:flutter/material.dart';
import 'package:detalhes/models/trip.dart';

/// Lista as corridas abertas do motorista (de qualquer cliente) para escolher
/// qual acompanhar.
class TripSelectWidget extends StatelessWidget {
  final List<Trip> trips;
  final ValueChanged<Trip> onSelected;
  final VoidCallback onBack;

  const TripSelectWidget({
    super.key,
    required this.trips,
    required this.onSelected,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 16),
        const Text(
          'Escolha a corrida',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final trip in trips)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.local_shipping),
                    title: Text('${trip.startingPointName} → ${trip.endingPointName}'),
                    subtitle: Text('${trip.tenantName} · ${trip.label} · ${trip.key}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => onSelected(trip),
                  ),
                ),
            ],
          ),
        ),
        TextButton(onPressed: onBack, child: const Text('Voltar')),
        const SizedBox(height: 16),
      ],
    );
  }
}
