import 'package:flutter/material.dart';

/// Widget responsável por gerenciar a entrada do CPF
class CpfInputWidget extends StatefulWidget {
  final String? currentCpf;
  final ValueChanged<String> onCpfSubmitted;

  const CpfInputWidget({
    super.key,
    this.currentCpf,
    required this.onCpfSubmitted,
  });

  @override
  State<CpfInputWidget> createState() => _CpfInputWidgetState();
}

class _CpfInputWidgetState extends State<CpfInputWidget> {
  final TextEditingController _controller = TextEditingController();
  String _formattedCpf = '';

  @override
  void initState() {
    super.initState();
    if (widget.currentCpf != null && widget.currentCpf!.isNotEmpty) {
      _controller.text = _formatCpf(widget.currentCpf!);
    }
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    final text = _controller.text.replaceAll(RegExp(r'\D'), '');
    setState(() {
      _formattedCpf = _formatCpf(text);
    });
    _controller.value = TextEditingValue(
      text: _formattedCpf,
      selection: TextSelection.collapsed(offset: _formattedCpf.length),
    );
  }

  String _formatCpf(String cpf) {
    final digits = cpf.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 11) return digits.substring(0, 11);
    
    if (digits.length <= 3) return digits;
    if (digits.length <= 6) return '${digits.substring(0, 3)}.${digits.substring(3)}';
    if (digits.length <= 9) return '${digits.substring(0, 3)}.${digits.substring(3, 6)}.${digits.substring(6)}';
    return '${digits.substring(0, 3)}.${digits.substring(3, 6)}.${digits.substring(6, 9)}-${digits.substring(9)}';
  }

  bool _isValidCpf(String cpf) {
    final digits = cpf.replaceAll(RegExp(r'\D'), '');
    return digits.length == 11;
  }

  void _submit() {
    final cpf = _controller.text.replaceAll(RegExp(r'\D'), '');
    
    if (!_isValidCpf(cpf)) {
      _showErrorAlert('Digite um CPF válido (11 dígitos)');
      return;
    }

    widget.onCpfSubmitted(cpf);
  }

  void _showErrorAlert(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Erro'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.person_outline,
              size: 64,
              color: Colors.blue,
            ),
            const SizedBox(height: 24),
            const Text(
              'Bem-vindo!',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Digite seu CPF para continuar',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _controller,
              keyboardType: TextInputType.number,
              maxLength: 14,
              decoration: const InputDecoration(
                labelText: 'CPF',
                hintText: '000.000.000-00',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.badge),
                counterText: '',
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submit,
                child: const Text('Continuar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
