import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediagrab/core/utils/permission_utils.dart';

void main() {
  group('PermissionUtils', () {
    test('isFolderWritable returns true for valid temporary directory', () async {
      final tempDir = await Directory.systemTemp.createTemp('mediagrab_perm_test_');
      final isWritable = await PermissionUtils.isFolderWritable(tempDir.path);
      expect(isWritable, isTrue);
      await tempDir.delete(recursive: true);
    });

    test('isFolderWritable returns false for empty path', () async {
      final isWritable = await PermissionUtils.isFolderWritable('');
      expect(isWritable, isFalse);
    });

    test('isFolderWritable returns false for non-writable root or invalid system path', () async {
      final isWritable = await PermissionUtils.isFolderWritable('/system_non_writable_test_123/sub');
      expect(isWritable, isFalse);
    });
  });
}
