// ─── Hospital Profile Model ───────────────────────────────────────────────────
class HospitalProfile {
  final String name;
  final String type; // Public, Private, Teaching, Specialized
  final String capacity; // e.g. "250 beds"
  final List<String> departments;
  final String owner;
  final bool isTeaching;
  final bool isSpecialized;

  const HospitalProfile({
    required this.name,
    required this.type,
    required this.capacity,
    required this.departments,
    required this.owner,
    this.isTeaching = false,
    this.isSpecialized = false,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type,
        'capacity': capacity,
        'departments': departments,
        'owner': owner,
        'isTeaching': isTeaching,
        'isSpecialized': isSpecialized,
      };

  factory HospitalProfile.fromJson(Map<String, dynamic> json) =>
      HospitalProfile(
        name: json['name'] as String? ?? '',
        type: json['type'] as String? ?? 'General',
        capacity: json['capacity'] as String? ?? '',
        departments:
            List<String>.from(json['departments'] as List? ?? []),
        owner: json['owner'] as String? ?? '',
        isTeaching: json['isTeaching'] as bool? ?? false,
        isSpecialized: json['isSpecialized'] as bool? ?? false,
      );

  static HospitalProfile get placeholder => const HospitalProfile(
        name: '[Healthcare Facility Name]',
        type: 'General Hospital',
        capacity: '',
        departments: [],
        owner: '',
      );

  String get displayHeader =>
      '$name${isTeaching ? ' – Teaching Hospital' : ''}${isSpecialized ? ' – Specialized' : ''}';
}
