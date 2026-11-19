import 'ops_models.dart';

/// A problem after delivery: complaint (re-wash) or wrong delivery.
/// Stages (complaint): open → pickup → received → washing → ready → returned, then closed.
/// Wrong delivery: open with tasks (take back / hand over), closed when all tasks are done.
class Issue {
  Issue({
    required this.id,
    required this.number,
    required this.kind,
    required this.orderId,
    required this.customerId,
    required this.branchId,
    required this.openedAt,
    required this.openedBy,
    required this.dueAt,
    this.otherOrderId = '',
    this.subKind = '',
    this.pieces = const [],
    this.reason = '',
    this.note = '',
    this.fault = const [],
    this.compensation = 0,
    this.stage = 'open',
    this.closed = false,
    this.closedAt,
    this.reopenCount = 0,
    List<IssueTask>? tasks,
    List<StatusEvent>? history,
  })  : tasks = tasks ?? [],
        history = history ?? [];

  final String id;
  final int number;
  final String kind; // complaint | wrong
  String subKind; // wrong: swap | wrongaddr | missing
  final String orderId;
  String otherOrderId;
  final String customerId;
  final String branchId;
  List<String> pieces; // tag labels
  String reason;
  String note;
  List<String> fault; // staff ids (or 'none')
  double compensation;
  String stage;
  bool closed;
  DateTime openedAt;
  String openedBy;
  DateTime? closedAt;
  int reopenCount;
  DateTime dueAt;
  final List<IssueTask> tasks;
  final List<StatusEvent> history;

  String get code => 'ISS-${number.toString().padLeft(4, '0')}';
  bool get open => !closed;

  /// Hours from opening to closing (or to now while open).
  double get hoursOpen => ((closedAt ?? DateTime.now()).difference(openedAt).inMinutes / 60);

  Map<String, dynamic> toJson() => {
        'id': id,
        'number': number,
        'kind': kind,
        'subKind': subKind,
        'orderId': orderId,
        'otherOrderId': otherOrderId,
        'customerId': customerId,
        'branchId': branchId,
        'pieces': pieces,
        'reason': reason,
        'note': note,
        'fault': fault,
        'compensation': compensation,
        'stage': stage,
        'closed': closed,
        'openedAt': openedAt.toIso8601String(),
        'openedBy': openedBy,
        'closedAt': closedAt?.toIso8601String(),
        'reopenCount': reopenCount,
        'dueAt': dueAt.toIso8601String(),
        'tasks': tasks.map((e) => e.toJson()).toList(),
        'history': history.map((e) => e.toJson()).toList(),
      };

  factory Issue.fromJson(Map<String, dynamic> j) => Issue(
        id: j['id'] as String,
        number: (j['number'] as num?)?.toInt() ?? 0,
        kind: j['kind'] as String? ?? 'complaint',
        subKind: j['subKind'] as String? ?? '',
        orderId: j['orderId'] as String? ?? '',
        otherOrderId: j['otherOrderId'] as String? ?? '',
        customerId: j['customerId'] as String? ?? '',
        branchId: j['branchId'] as String? ?? '',
        pieces: ((j['pieces'] as List?) ?? []).map((e) => '$e').toList(),
        reason: j['reason'] as String? ?? '',
        note: j['note'] as String? ?? '',
        fault: ((j['fault'] as List?) ?? []).map((e) => '$e').toList(),
        compensation: (j['compensation'] as num?)?.toDouble() ?? 0,
        stage: j['stage'] as String? ?? 'open',
        closed: j['closed'] as bool? ?? false,
        openedAt: DateTime.tryParse(j['openedAt'] as String? ?? '') ?? DateTime.now(),
        openedBy: j['openedBy'] as String? ?? '',
        closedAt: DateTime.tryParse(j['closedAt'] as String? ?? ''),
        reopenCount: (j['reopenCount'] as num?)?.toInt() ?? 0,
        dueAt: DateTime.tryParse(j['dueAt'] as String? ?? '') ?? DateTime.now(),
        tasks: ((j['tasks'] as List?) ?? []).map((e) => IssueTask.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
        history: ((j['history'] as List?) ?? []).map((e) => StatusEvent.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      );
}

class IssueTask {
  IssueTask({required this.text, this.agent = '', this.customerId = '', this.done = false, this.doneAt, this.doneBy = ''});
  final String text;
  String agent;
  final String customerId; // whose address
  bool done;
  DateTime? doneAt;
  String doneBy;
  Map<String, dynamic> toJson() => {
        'text': text,
        'agent': agent,
        'customerId': customerId,
        'done': done,
        'doneAt': doneAt?.toIso8601String(),
        'doneBy': doneBy,
      };
  factory IssueTask.fromJson(Map<String, dynamic> j) => IssueTask(
        text: j['text'] as String? ?? '',
        agent: j['agent'] as String? ?? '',
        customerId: j['customerId'] as String? ?? '',
        done: j['done'] as bool? ?? false,
        doneAt: DateTime.tryParse(j['doneAt'] as String? ?? ''),
        doneBy: j['doneBy'] as String? ?? '',
      );
}

const complaintReasons = ['Stain left', 'Not ironed well', 'Colour faded', 'Torn / damaged', 'Smell', 'Other'];
const issueStages = ['open', 'pickup', 'received', 'washing', 'ready', 'returned'];

/// Money paid to / taken from staff: advance, salary payment, manual bonus or deduction.
class Payout {
  Payout({
    required this.id,
    required this.staffId,
    required this.month,
    required this.kind,
    required this.amount,
    required this.at,
    this.mode = 'cash',
    this.note = '',
  });
  final String id;
  final String staffId;
  final String month; // yyyy-mm
  final String kind; // advance | paid | bonus | deduction
  final double amount;
  final DateTime at;
  final String mode;
  final String note;
  Map<String, dynamic> toJson() => {
        'id': id,
        'staffId': staffId,
        'month': month,
        'kind': kind,
        'amount': amount,
        'at': at.toIso8601String(),
        'mode': mode,
        'note': note,
      };
  factory Payout.fromJson(Map<String, dynamic> j) => Payout(
        id: j['id'] as String,
        staffId: j['staffId'] as String? ?? '',
        month: j['month'] as String? ?? '',
        kind: j['kind'] as String? ?? 'advance',
        amount: (j['amount'] as num?)?.toDouble() ?? 0,
        at: DateTime.tryParse(j['at'] as String? ?? '') ?? DateTime.now(),
        mode: j['mode'] as String? ?? 'cash',
        note: j['note'] as String? ?? '',
      );
}

String monthKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';
