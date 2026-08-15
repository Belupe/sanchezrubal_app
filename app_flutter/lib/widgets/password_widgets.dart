import 'package:flutter/material.dart';

import '../utils/password_policy.dart';

class PasswordField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String? helper;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  const PasswordField({
    super.key,
    required this.controller,
    required this.label,
    this.helper,
    this.autofillHints,
    this.onChanged,
    this.onSubmitted,
  });

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      obscureText: !_visible,
      autofillHints: widget.autofillHints,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      decoration: InputDecoration(
        labelText: widget.label,
        helperText: widget.helper,
        helperMaxLines: 2,
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          icon: Icon(_visible ? Icons.visibility_off : Icons.visibility),
          tooltip: _visible ? 'Ocultar contraseña' : 'Ver contraseña',
          onPressed: () => setState(() => _visible = !_visible),
        ),
      ),
    );
  }
}

class PasswordChecklist extends StatelessWidget {
  final String password;
  final String? confirm;

  const PasswordChecklist({super.key, required this.password, this.confirm});

  @override
  Widget build(BuildContext context) {
    final filas = [
      ...PasswordPolicy.requisitos(password),
      if (confirm != null)
        ('Las contraseñas coinciden', password.isNotEmpty && password == confirm),
    ];
    final hint = Theme.of(context).hintColor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: filas.map((r) {
        final ok = r.$2;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Icon(ok ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 18, color: ok ? Colors.green : hint),
            const SizedBox(width: 8),
            Expanded(
              child: Text(r.$1,
                  style: TextStyle(
                    color: ok ? null : hint,
                    decoration: ok ? TextDecoration.none : null,
                  )),
            ),
          ]),
        );
      }).toList(),
    );
  }
}
