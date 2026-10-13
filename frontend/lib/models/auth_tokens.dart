class AuthTokens {
  final String accessToken;
  final String refreshToken;
  final int expiresIn;

  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
  });

  factory AuthTokens.fromJson(Map<String, dynamic> json) => AuthTokens(
    accessToken: json['accessToken'] as String? ??
        json['token'] as String? ??
        json['access_token'] as String? ??
        '',
    refreshToken: json['refreshToken'] as String? ??
        json['refresh_token'] as String? ??
        '',
    expiresIn: json['expiresIn'] is int
        ? json['expiresIn'] as int
        : int.tryParse(json['expiresIn']?.toString() ?? '3600') ?? 3600,
  );

  Map<String, dynamic> toJson() => {
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'expiresIn': expiresIn,
  };
}
