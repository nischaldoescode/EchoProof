// echo local cache source
// stores recent feed in hive so the app feels instant on cold start

import 'package:hive_flutter/hive_flutter.dart';
import '../../../../core/utils/logger.dart';

class EchoLocalSource {
  static const _cacheKey = 'feed_cache';
  static const _cacheTimestamp = 'feed_cache_ts';
  static const _maxAgeMinutes = 5;

  Box get _box => Hive.box('echo_cache');

  Future<List<Map<String, dynamic>>?> getCachedFeed() async {
    final timestamp = _box.get(_cacheTimestamp) as int?;
    if (timestamp == null) return null;

    final ageMinutes = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(timestamp))
        .inMinutes;

    if (ageMinutes > _maxAgeMinutes) {
      AppLogger.debug('cache: feed cache expired');
      return null;
    }

    final cached = _box.get(_cacheKey);
    if (cached == null) return null;

    AppLogger.debug('cache: serving feed from cache (${ageMinutes}m old)');
    return List<Map<String, dynamic>>.from(cached as List);
  }

  Future<void> cacheFeed(List<Map<String, dynamic>> feed) async {
    await _box.put(_cacheKey, feed);
    await _box.put(_cacheTimestamp, DateTime.now().millisecondsSinceEpoch);
    AppLogger.debug('cache: feed cached (${feed.length} echoes)');
  }

  Future<void> clearCache() async {
    await _box.delete(_cacheKey);
    await _box.delete(_cacheTimestamp);
  }
}
