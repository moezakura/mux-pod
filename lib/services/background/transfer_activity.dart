/// Actual SFTP work owns a lease, including cancellation cleanup. UI phases
/// (file pickers, confirmation dialogs, exporting) do not hold the device awake.
class TransferActivity {
  static final shared = TransferActivity();
  int _count = 0;
  bool get active => _count > 0;
  Future<void> Function()? onChanged;

  Future<T> run<T>(Future<T> Function() operation) async {
    _count++;
    try {
      await onChanged?.call();
      return await operation();
    } finally {
      _count--;
      await onChanged?.call();
    }
  }
}
