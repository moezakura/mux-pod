import 'dart:async';

import '../../ssh/ssh_client.dart';
import '../agent_types.dart';
import 'chat_event.dart';
import 'chat_event_parser.dart';
import 'headless_command_builder.dart';

/// A chat conversation with one AI CLI agent running headlessly over SSH.
///
/// Each user prompt spawns a new remote process via [SshClient.execStream]
/// (agents have no persistent headless stdin protocol in the modes used
/// here); follow-up prompts pass the captured [sessionId] through the
/// agent's resume flag (`--resume` for Claude, `exec resume` for Codex,
/// `--session-id` for Droid) so conversation context is preserved.
///
/// Usage:
/// ```dart
/// final session = HeadlessAgentSession(ssh: ssh, kind: AgentKind.claudeCode);
/// final sub = session.events.listen((event) { ... });
/// await session.start('Summarize this repo');
/// // ... after RunCompleted:
/// await session.send('Now list the risky parts');
/// ```
///
/// Listen to [events] before calling [start]: the stream is broadcast and
/// events emitted without a listener are lost. Runs are serialized —
/// calling [start]/[send] while a run is active throws a [StateError].
class HeadlessAgentSession {
  HeadlessAgentSession({
    required SshClient ssh,
    required AgentKind kind,
    String? model,
    UnifiedIntelligence? intelligence,
    UnifiedPermission? permission,
    bool planMode = false,
    String? workingDirectory,
    String? resumeSessionId,
  })  : _ssh = ssh,
        _kind = kind,
        _model = model,
        _intelligence = intelligence,
        _permission = permission,
        _planMode = planMode,
        _workingDirectory = workingDirectory,
        _sessionId = resumeSessionId;

  final SshClient _ssh;
  final AgentKind _kind;
  final String? _model;
  final UnifiedIntelligence? _intelligence;
  final UnifiedPermission? _permission;
  final bool _planMode;
  final String? _workingDirectory;

  final _eventsController = StreamController<ChatEvent>.broadcast();

  StreamSubscription<ChatEvent>? _activeRun;
  Completer<void>? _activeDone;
  String? _sessionId;
  bool _disposed = false;

  /// Parsed chat events from the current and past runs.
  Stream<ChatEvent> get events => _eventsController.stream;

  /// The agent's session id, captured from its output. Null until the
  /// agent announces it (or never, if the agent does not report one).
  String? get sessionId => _sessionId;

  /// Whether a run is currently streaming.
  bool get isRunning => _activeRun != null;

  /// Starts a fresh conversation with [prompt].
  ///
  /// The returned future completes when the run ends: a terminal event
  /// ([RunCompleted]/[RunFailed]), the output stream closing, or
  /// [cancel]. Progress events are delivered through [events], which
  /// should be listened to before calling this method. Throws
  /// [StateError] if a run is already active.
  Future<void> start(String prompt) => _run(prompt, resume: false);

  /// Sends a follow-up [prompt], resuming the stored [sessionId].
  ///
  /// Throws [StateError] if a run is active or no session id has been
  /// captured yet (without one, context cannot be resumed).
  Future<void> send(String prompt) {
    final id = _sessionId;
    if (id == null) {
      throw StateError(
        'Cannot send a follow-up: no session id captured yet. '
        'Use start() to begin a new conversation.',
      );
    }
    return _run(prompt, resume: true);
  }

  Future<void> _run(String prompt, {required bool resume}) {
    if (_disposed) {
      throw StateError('HeadlessAgentSession is disposed');
    }
    if (_activeRun != null) {
      throw StateError('A run is already in progress');
    }

    final command = buildHeadlessCommand(
      kind: _kind,
      prompt: prompt,
      model: _model,
      intelligence: _intelligence,
      permission: _permission,
      planMode: _planMode,
      resumeSessionId: resume ? _sessionId : null,
      workingDirectory: _workingDirectory,
    );

    // execStream throws synchronously when the SSH connection is down;
    // let that propagate to the caller of start()/send().
    final output = _ssh.execStream(command);

    var terminalEmitted = false;
    final done = Completer<void>();
    _activeDone = done;
    _activeRun = parseAgentEventStream(_kind, output).listen(
      (event) {
        if (event is SessionStarted) {
          _sessionId = event.sessionId;
        }
        if (event is RunCompleted || event is RunFailed) {
          terminalEmitted = true;
        }
        _eventsController.add(event);
      },
      onError: (Object error) {
        // Non-zero exit or SSH disconnect mid-run. When the parser
        // already emitted a terminal event (agents print an error result
        // line and then exit non-zero), do not emit a duplicate.
        if (!terminalEmitted) {
          _eventsController.add(RunFailed(error.toString()));
        }
        if (!done.isCompleted) done.complete();
      },
      onDone: () {
        // The process exited cleanly without a parseable terminal event;
        // synthesize completion so listeners never wait forever.
        if (!terminalEmitted) {
          _eventsController.add(const RunCompleted());
        }
        if (!done.isCompleted) done.complete();
      },
      cancelOnError: true,
    );

    return done.future.whenComplete(() {
      _activeRun = null;
      _activeDone = null;
    });
  }

  /// Cancels the active run, killing the remote process by closing its
  /// SSH exec channel. Does nothing when no run is active.
  Future<void> cancel() async {
    final run = _activeRun;
    final done = _activeDone;
    _activeRun = null;
    _activeDone = null;
    // Cancelling the subscription closes the exec channel (see
    // SshClient.execStream onCancel), which kills the remote process.
    await run?.cancel();
    // Unblock callers awaiting start()/send(); the subscription is already
    // cancelled so done would never complete otherwise.
    if (done != null && !done.isCompleted) done.complete();
  }

  /// Cancels any active run and closes the event stream.
  Future<void> dispose() async {
    _disposed = true;
    await cancel();
    await _eventsController.close();
  }
}
