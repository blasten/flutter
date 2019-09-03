// Copyright 2016 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'base/io.dart';
import 'device.dart';
import 'globals.dart';

/// Discovers a specific service protocol on a device, and forwards the service
/// protocol device port to the host.
class ProtocolDiscovery {
  ProtocolDiscovery._(
    this.logReader,
    this.serviceName, {
    this.portForwarder,
    this.hostPort,
    this.ipv6,
  }) : assert(logReader != null);

  factory ProtocolDiscovery.observatory(
    DeviceLogReader logReader, {
    DevicePortForwarder portForwarder,
    int hostPort,
    bool ipv6 = false,
  }) {
    const String kObservatoryService = 'Observatory';
    return ProtocolDiscovery._(
      logReader,
      kObservatoryService,
      portForwarder: portForwarder,
      hostPort: hostPort,
      ipv6: ipv6,
    );
  }

  final DeviceLogReader logReader;
  final String serviceName;
  final DevicePortForwarder portForwarder;
  final int hostPort;
  final bool ipv6;

  /// The stream with the discovered service URIs.
  ///
  /// The service may not be active on a given URI since the service can disconnect
  /// at any time and re-issue a new URI.
  ///
  /// Therefore, if the connection to the service is lost, clients can try to re-connect
  /// to a new URI.
  Stream<Uri> get uris async* {
    final RegExp serviceUriRegEx = RegExp('${RegExp.escape(serviceName)} listening on '
        '((http|\/\/)[a-zA-Z0-9:/=_\\-\.\\[\\]]+)');
    await for (String line in logReader.logLines) {
      final Match match = serviceUriRegEx.firstMatch(line);
      if (match == null) {
        continue;
      }
      Uri uri;
      try {
        uri = Uri.parse(match[1]);
      } catch (error) {
        printError('Failed to parse URI in line: $line');
        continue;
      }
      yield await _forwardPort(uri);
    }
  }

  Future<Uri> _forwardPort(Uri deviceUri) async {
    printTrace('$serviceName URL on device: $deviceUri');
    Uri hostUri = deviceUri;

    if (portForwarder != null) {
      final int actualDevicePort = deviceUri.port;
      final int actualHostPort = await portForwarder.forward(actualDevicePort, hostPort: hostPort);
      printTrace('Forwarded host port $actualHostPort to device port $actualDevicePort for $serviceName');
      hostUri = deviceUri.replace(port: actualHostPort);
    }
    assert(InternetAddress(hostUri.host).isLoopback);
    if (ipv6) {
      hostUri = hostUri.replace(host: InternetAddress.loopbackIPv6.host);
    }
    return hostUri;
  }
}
