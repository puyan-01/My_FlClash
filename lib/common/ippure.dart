import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/models/models.dart';

import 'constant.dart';

class IpPurity {
  const IpPurity({
    required this.ip,
    required this.score,
    required this.countryCode,
    required this.residential,
    required this.broadcast,
  });

  static const lowRiskMax = 40;
  static const mediumRiskMax = 70;

  final String ip;

  /// IPPure 的风险系数，0 到 100，越低越干净。
  final int score;

  final String countryCode;
  final bool residential;
  final bool broadcast;

  bool get trusted => score <= lowRiskMax;
}

Future<IpPurity?> fetchIpPurity(
  CoreController core, {
  required String proxyName,
}) async {
  try {
    final response = await core.outboundIp(
      OutboundIpParams(
        proxyName: proxyName,
        urls: const ['https://my.ippure.com/v1/info'],
        timeout: probeTimeoutDuration.inMilliseconds,
      ),
    );
    if (response.error != null) {
      return null;
    }
    final json = jsonDecode(response.body);
    if (json is! Map<String, dynamic>) {
      return null;
    }
    final score = json['fraudScore'];
    final ip = json['ip'];
    if (score is! num ||
        score < 0 ||
        score > 100 ||
        score % 1 != 0 ||
        ip is! String ||
        InternetAddress.tryParse(ip)?.type != InternetAddressType.IPv4) {
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
