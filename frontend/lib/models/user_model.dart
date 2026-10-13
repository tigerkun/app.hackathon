import 'package:flutter/foundation.dart';

@immutable
class EmergencyContact {
  final String name;
  final String phone;
  final String relationship;

  const EmergencyContact({
    required this.name,
    required this.phone,
    this.relationship = 'Family',
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'phone': phone,
    'relationship': relationship,
  };

  factory EmergencyContact.fromJson(Map<String, dynamic> json) => EmergencyContact(
    name: json['name'] as String? ?? '',
    phone: json['phone'] as String? ?? '',
    relationship: json['relationship'] as String? ?? 'Family',
  );
}

@immutable
class UserModel {
  final String id;
  final String name;
  final String email;
  final String phone;
  final String? emergencyContactPhone;
  final String? emergencyContactName;
  final List<EmergencyContact> emergencyContacts;
  final bool isGuest;
  final bool hasPin;
  final bool biometricsEnabled;
  final DateTime createdAt;

  const UserModel({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    this.emergencyContactPhone,
    this.emergencyContactName,
    this.emergencyContacts = const [],
    this.isGuest = false,
    this.hasPin = false,
    this.biometricsEnabled = false,
    required this.createdAt,
  });

  bool get isAnonymous => isGuest;

  factory UserModel.guest() => UserModel(
    id: 'guest_user',
    name: 'Guest Citizen',
    email: '',
    phone: '',
    isGuest: true,
    hasPin: false,
    biometricsEnabled: false,
    createdAt: DateTime.now(),
  );

  factory UserModel.fromJson(Map<String, dynamic> json) {
    List<EmergencyContact> contacts = [];
    if (json['emergencyContacts'] is List) {
      contacts = (json['emergencyContacts'] as List)
          .whereType<Map<String, dynamic>>()
          .map((c) => EmergencyContact.fromJson(c))
          .toList();
    } else if (json['emergencyContact'] is Map<String, dynamic>) {
      contacts = [EmergencyContact.fromJson(json['emergencyContact'] as Map<String, dynamic>)];
    }

    final contactPhone = json['emergencyContactPhone'] as String? ??
        json['emergency_contact_phone'] as String? ??
        (contacts.isNotEmpty ? contacts.first.phone : null);

    final contactName = json['emergencyContactName'] as String? ??
        json['emergency_contact_name'] as String? ??
        (contacts.isNotEmpty ? contacts.first.name : null);

    return UserModel(
      id: json['id'] as String? ?? json['_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      emergencyContactPhone: contactPhone,
      emergencyContactName: contactName,
      emergencyContacts: contacts,
      isGuest: json['isGuest'] as bool? ?? false,
      hasPin: json['hasPin'] as bool? ?? (json['pin'] != null),
      biometricsEnabled: json['biometricsEnabled'] as bool? ?? false,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'email': email,
    'phone': phone,
    'emergencyContactPhone': emergencyContactPhone,
    'emergencyContactName': emergencyContactName,
    'emergencyContacts': emergencyContacts.map((c) => c.toJson()).toList(),
    'isGuest': isGuest,
    'hasPin': hasPin,
    'biometricsEnabled': biometricsEnabled,
    'createdAt': createdAt.toIso8601String(),
  };

  UserModel copyWith({
    String? id,
    String? name,
    String? email,
    String? phone,
    String? emergencyContactPhone,
    String? emergencyContactName,
    List<EmergencyContact>? emergencyContacts,
    bool? isGuest,
    bool? hasPin,
    bool? biometricsEnabled,
    DateTime? createdAt,
    bool? isAnonymous,
  }) {
    return UserModel(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      emergencyContactPhone: emergencyContactPhone ?? this.emergencyContactPhone,
      emergencyContactName: emergencyContactName ?? this.emergencyContactName,
      emergencyContacts: emergencyContacts ?? this.emergencyContacts,
      isGuest: isGuest ?? (isAnonymous ?? this.isGuest),
      hasPin: hasPin ?? this.hasPin,
      biometricsEnabled: biometricsEnabled ?? this.biometricsEnabled,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
