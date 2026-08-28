import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/download/batch_destination_picker.dart';

/// 一括ダウンロードの保存先ピッカー（[BatchDestinationPicker]）を提供する provider。
///
/// テストでは本 provider をモック実装で override して使用する
/// （プラットフォーム依存のフォルダ選択を回避するため）。
/// 非 autoDispose（画面をまたいでも差し替えられないよう保持）。
final batchDestinationPickerProvider = Provider<BatchDestinationPicker>(
  (ref) => const PlatformBatchDestinationPicker(),
);
