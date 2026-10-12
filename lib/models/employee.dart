import 'package:cloud_firestore/cloud_firestore.dart';

/// One document in the `employees` collection.
/// The document ID is the Firebase Authentication UID of that person.
class Employee {
  const Employee({
    required this.uid,
    required this.employeeId,
    required this.name,
    required this.type,
    required this.mustChangePassword,
    required this.active,
  });

  final String uid;
  final String employeeId;
  final String name;

  /// 'e' = employee, 'm' = management.
  final String type;
  final bool mustChangePassword;
  final bool active;

  bool get isManagement => type == 'm';

  factory Employee.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return Employee(
      uid: doc.id,
      employeeId: (data['employeeId'] ?? '') as String,
      name: (data['name'] ?? '') as String,
      type: (data['type'] ?? 'e') as String,
      mustChangePassword: (data['mustChangePassword'] ?? true) as bool,
      active: (data['active'] ?? true) as bool,
    );
  }
}
