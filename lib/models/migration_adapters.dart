import 'dart:typed_data';

import 'package:finamp/services/queue_service.dart';
import 'package:hive_ce/hive.dart';

import 'finamp_models.dart';
import 'jellyfin_models.dart';

/// This class exists to be extended by FinampStorableQueueInfo.  It allows the migration
/// adapter to be registered with hive using a separate type ID without conflict
/// while still returning a FinampStorableQueueInfo.
class FinampStorableQueueInfoLegacy {
  const FinampStorableQueueInfoLegacy();
}

class FinampStorableQueueInfoMigrationAdapter extends TypeAdapter<FinampStorableQueueInfoLegacy> {
  @override
  final typeId = 61;

  @override
  FinampStorableQueueInfoLegacy read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read()};
    final currentTrack = fields[1] as BaseItemId?;
    return FinampStorableQueueInfo(
      packedPreviousTracks: FinampStorableQueueInfo.packIds((fields[0] as List).cast<BaseItemId>()),
      packedCurrentTrack: currentTrack == null ? Uint8List(0) : FinampStorableQueueInfo.packIds([currentTrack]),
      currentTrackSeek: (fields[2] as num?)?.toInt(),
      packedNextUp: FinampStorableQueueInfo.packIds((fields[3] as List).cast<BaseItemId>()),
      packedQueue: FinampStorableQueueInfo.packIds((fields[4] as List).cast<BaseItemId>()),
      creation: (fields[5] as num).toInt(),
      sourceIndex: 0,
      sourceList: [fields[6] as QueueItemSource? ?? QueueService.savedQueueSource],
      trackSourceIndexes: Uint8List(0),
      packedShuffleOrder: null,
    );
  }

  @override
  void write(BinaryWriter writer, FinampStorableQueueInfoLegacy obj) {
    throw Exception("Attempted to write hive entry using migration adapter.");
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FinampStorableQueueInfoMigrationAdapter && runtimeType == other.runtimeType && typeId == other.typeId;
}
