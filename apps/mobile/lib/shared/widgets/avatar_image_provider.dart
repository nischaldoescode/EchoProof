// avatar image provider
// @params none

import 'package:flutter/widgets.dart';

const echoProofLogoAsset = 'assets/images/logo.png';

bool isEchoProofOfficialLogoUrl(String? value) {
  final url = value?.trim();
  if (url == null || url.isEmpty) return false;
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  return uri.scheme == 'https' &&
      uri.host.toLowerCase() == 'echoproof.online' &&
      uri.path == '/logo.png';
}

ImageProvider<Object>? avatarImageProvider(String? value) {
  final url = value?.trim();
  if (url == null || url.isEmpty) return null;
  if (isEchoProofOfficialLogoUrl(url)) {
    return const AssetImage(echoProofLogoAsset);
  }

  final uri = Uri.tryParse(url);
  if (uri == null) return null;
  if (uri.scheme == 'https' || uri.scheme == 'http') {
    return NetworkImage(url);
  }
  return null;
}
