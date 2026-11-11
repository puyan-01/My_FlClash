import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

class IpPurity {
  const IpPurity({
    required this.ip,
    required this.score,
    required this.countryCode,
    required this.residential,
    required this.broadcast,
  });

  final String ip;

  /// IPPure 的风险系数，0 到 100，越低越干净。
  final int score;

  final String countryCode;
  final bool residential;
  final bool broadcast;

  bool get trusted => score <= 40;
}

/// IPPure 只返回调用方自己的出口 IP，所以查询必须经过目标节点。
Future<IpPurity?> fetchIpPurity(
  Dio dio, {
  CancelToken? cancelToken,
  Duration timeout = const Duration(seconds: 10),
}) async {
  try {
    final response = await dio
        .get<String>(
          'https://my.ippure.com/v1/info',
          cancelToken: cancelToken,
          options: Options(
            responseType: ResponseType.plain,
            validateStatus: (_) => true,
          ),
        )
        .timeout(timeout);
    if (response.statusCode != 200) {
      return null;
    }
    final json = jsonDecode(response.data ?? '');
    if (json is! Map<String, dynamic>) {
      return null;
    }
    final score = json['fraudScore'];
    final ip = json['ip'];
    if (score is! num || ip is! String) {
      return null;
    }
    return IpPurity(
      ip: ip,
      score: score.toInt(),
      countryCode: '${json['countryCode'] ?? ''}',
      residential: json['isResidential'] == true,
      broadcast: json['isBroadcast'] == true,
    );
  } catch (_) {
    return null;
  }
}
