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
  final String email;
  final String name;
  final String phone;
  final List<EmergencyContact> emergencyContacts;
  final bool biometricsEnabled;
  final bool hasPin;
  final bool isAnonymous;

  const UserModel({
    required this.id,
    required this.email,
    required this.name,
    required this.phone,
    this.emergencyContacts = const [],
    this.biometricsEnabled = false,
    this.hasPin = false,
    this.isAnonymous = false,
  });

  UserModel copyWith({
    String? id,
    String? email,
    String? name,
    String? phone,
    List<EmergencyContact>? emergencyContacts,
    bool? biometricsEnabled,
    bool? hasPin,
    bool? isAnonymous,
  }) {
    return UserModel(
      id: id ?? this.id,
      email: email ?? this.email,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      emergencyContacts: emergencyContacts ?? this.emergencyContacts,
      biometricsEnabled: biometricsEnabled ?? this.biometricsEnabled,
      hasPin: hasPin ?? this.hasPin,
      isAnonymous: isAnonymous ?? this.isAnonymous,
    );
  }
}
