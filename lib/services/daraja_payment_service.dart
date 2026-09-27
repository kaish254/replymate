import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class DarajaPaymentService {
  DarajaPaymentService({http.Client? client, String? apiBaseUrl})
    : _client = client ?? http.Client(),
      _apiBaseUrl =
          apiBaseUrl ?? const String.fromEnvironment('PAYMENT_API_BASE_URL');

  final String _apiBaseUrl;
  final http.Client _client;

  void close() => _client.close();

  Future<PaymentRequest> startPayment(String phone) async {
    final response = await _client
        .post(
          _uri('/api/payments/stk'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({'phone': phone}),
        )
        .timeout(const Duration(seconds: 30));
    final data = _decode(response);
    return PaymentRequest(
      checkoutRequestId: data['checkoutRequestId'] as String,
      statusToken: data['statusToken'] as String,
      customerMessage:
          data['customerMessage'] as String? ??
          'Approve the M-Pesa prompt on your phone.',
      amountKes: data['amountKes'] as int? ?? 100,
    );
  }

  Future<PaymentStatus> checkStatus(PaymentRequest request) async {
    final response = await _client
        .get(
          _uri(
            '/api/payments/${Uri.encodeComponent(request.checkoutRequestId)}',
          ),
          headers: {'Authorization': 'Bearer ${request.statusToken}'},
        )
        .timeout(const Duration(seconds: 15));
    final data = _decode(response);
    return PaymentStatus(
      status: data['status'] as String,
      receipt: data['receipt'] as String?,
      expiresAt: data['expiresAt'] == null
          ? null
          : DateTime.parse(data['expiresAt'] as String),
      message: data['message'] as String?,
    );
  }

  Future<void> savePendingPayment(PaymentRequest request) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      'pending_checkout_id',
      request.checkoutRequestId,
    );
    await preferences.setString('pending_checkout_token', request.statusToken);
  }

  Future<PaymentRequest?> restorePendingPayment() async {
    final preferences = await SharedPreferences.getInstance();
    final checkoutId = preferences.getString('pending_checkout_id');
    final token = preferences.getString('pending_checkout_token');
    if (checkoutId == null || token == null) return null;
    return PaymentRequest(
      checkoutRequestId: checkoutId,
      statusToken: token,
      customerMessage: 'A payment prompt is awaiting confirmation.',
      amountKes: 100,
    );
  }

  Future<void> clearPendingPayment() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove('pending_checkout_id');
    await preferences.remove('pending_checkout_token');
  }

  Uri _uri(String path) {
    if (_apiBaseUrl.isEmpty) {
      throw const PaymentServiceException(
        'Payment service is not configured. Set PAYMENT_API_BASE_URL to your deployed API URL.',
      );
    }
    return Uri.parse('$_apiBaseUrl$path');
  }

  Map<String, dynamic> _decode(http.Response response) {
    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic>) {
      throw const PaymentServiceException(
        'The payment server returned an invalid response.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw PaymentServiceException(
        body['error'] as String? ?? 'Payment request failed.',
      );
    }
    return body;
  }
}

class PaymentRequest {
  const PaymentRequest({
    required this.checkoutRequestId,
    required this.statusToken,
    required this.customerMessage,
    required this.amountKes,
  });

  final String checkoutRequestId;
  final String statusToken;
  final String customerMessage;
  final int amountKes;
}

class PaymentStatus {
  const PaymentStatus({
    required this.status,
    required this.receipt,
    required this.expiresAt,
    required this.message,
  });

  final String status;
  final String? receipt;
  final DateTime? expiresAt;
  final String? message;
}

class PaymentServiceException implements Exception {
  const PaymentServiceException(this.message);
  final String message;

  @override
  String toString() => message;
}
