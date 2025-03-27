class UserModel {
  final String id;
  final String email;
  final String? username;
  final String? avatarUrl;
  final int unreadCount;

  UserModel({
    required this.id,
    required this.email,
    this.username,
    this.avatarUrl,
    this.unreadCount = 0,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] ?? '',
      email: json['email'] ?? '',
      username: json['username'],
      avatarUrl: json['avatar_url'],
      unreadCount: json['unread_count'] ?? 0,
    );
  }

  @override
  String toString() {
    return 'UserModel(id: $id, email: $email, username: $username)';
  }
}