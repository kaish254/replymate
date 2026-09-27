import 'package:flutter/material.dart';

import '../services/daraja_payment_service.dart';
import '../services/free_usage_service.dart';

class PremiumPaymentSheet extends StatefulWidget {
  const PremiumPaymentSheet({super.key});

  @override
  State<PremiumPaymentSheet> createState() => _PremiumPaymentSheetState();
}

class _PremiumPaymentSheetState extends State<PremiumPaymentSheet> {
  final _phoneController = TextEditingController();
  final _paymentService = DarajaPaymentService();
  PaymentRequest? _paymentRequest;
  String? _message;
  String? _receipt;
  bool _busy = false;
  bool _paid = false;

  @override
  void initState() {
    super.initState();
    _restorePendingPayment();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _paymentService.close();
    super.dispose();
  }

  Future<void> _restorePendingPayment() async {
    final request = await _paymentService.restorePendingPayment();
    if (mounted && request != null) {
      setState(() {
        _paymentRequest = request;
        _message = request.customerMessage;
      });
    }
  }

  Future<void> _startPayment() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final request = await _paymentService.startPayment(
        _phoneController.text.trim(),
      );
      await _paymentService.savePendingPayment(request);
      if (!mounted) return;
      setState(() {
        _paymentRequest = request;
        _message = request.customerMessage;
      });
    } on Object catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkPayment() async {
    final request = _paymentRequest;
    if (request == null) return;
    setState(() {
      _busy = true;
      _message = 'Checking with M-Pesa...';
    });
    try {
      final status = await _paymentService.checkStatus(request);
      if (!mounted) return;
      if (status.status == 'paid' && status.expiresAt != null) {
        await FreeUsageService().activatePremium(status.expiresAt!);
        await _paymentService.clearPendingPayment();
        if (!mounted) return;
        setState(() {
          _paid = true;
          _receipt = status.receipt;
          _message =
              'Premium is active until ${_dateLabel(status.expiresAt!)}.';
        });
      } else if (status.status == 'failed') {
        await _paymentService.clearPendingPayment();
        if (!mounted) return;
        setState(() {
          _paymentRequest = null;
          _message =
              status.message ?? 'Payment was not completed. You can try again.';
        });
      } else {
        setState(
          () => _message = 'Still waiting for M-Pesa confirmation. Approve the prompt, then check again.',
        );
      }
    } on Object catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, 10, 24, 24 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'CrushReply Premium',
              style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'KSh 100 / month',
              style: TextStyle(
                fontSize: 18,
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Unlimited replies, no ads, and every tone. Renew each month by paying again; this MVP does not auto-charge.',
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _phoneController,
              enabled: _paymentRequest == null && !_paid,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Safaricom M-Pesa number',
                hintText: '0712 345 678',
                prefixIcon: Icon(Icons.phone_android),
              ),
            ),
            if (_message != null) ...[
              const SizedBox(height: 12),
              Text(
                _message!,
                style: TextStyle(
                  color: _paid
                      ? Colors.green.shade700
                      : theme.colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
            ],
            if (_receipt != null) ...[
              const SizedBox(height: 5),
              Text(
                'M-Pesa receipt: $_receipt',
                style: const TextStyle(fontSize: 12),
              ),
            ],
            const SizedBox(height: 16),
            if (_paymentRequest == null && !_paid)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _startPayment,
                  icon: _busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.lock_outline),
                  label: const Text('Pay KSh 100 with M-Pesa'),
                ),
              )
            else if (!_paid)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _checkPayment,
                  icon: _busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  label: const Text('I have paid · Check status'),
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
              ),
            const SizedBox(height: 10),
            const Text(
              'Your phone will receive an M-Pesa prompt. Never share your M-Pesa PIN with anyone.',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  String _dateLabel(DateTime date) => '${date.day}/${date.month}/${date.year}';
}
