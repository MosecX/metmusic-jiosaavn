import 'dart:convert';

class AccountUser {
  final int id;
  final String username;
  final String email;
  final String role;
  final String status;
  final String? createdAt;

  const AccountUser({
    required this.id,
    required this.username,
    required this.email,
    required this.role,
    required this.status,
    this.createdAt,
  });

  factory AccountUser.fromJson(Map<String, dynamic> json) {
    return AccountUser(
      id: json['id'] is int
          ? json['id']
          : int.tryParse(json['id']?.toString() ?? '') ?? 0,
      username: json['username']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      role: json['role']?.toString() ?? 'user',
      status: json['status']?.toString() ?? 'pending',
      createdAt: json['created_at']?.toString(),
    );
  }

  bool get isApproved => status == 'approved';
  bool get isPending => status == 'pending';
  bool get isRejected => status == 'rejected';
}

class FavoriteRow {
  final int id;
  final String itemType;
  final String itemId;
  final Map<String, dynamic> data;
  final String? createdAt;

  FavoriteRow({
    required this.id,
    required this.itemType,
    required this.itemId,
    required this.data,
    this.createdAt,
  });

  factory FavoriteRow.fromJson(Map<String, dynamic> json) {
    return FavoriteRow(
      id: json['id'] is int
          ? json['id']
          : int.tryParse(json['id']?.toString() ?? '') ?? 0,
      itemType: json['item_type']?.toString() ?? 'track',
      itemId: json['item_id']?.toString() ?? '',
      data: _parseData(json['data']),
      createdAt: json['created_at']?.toString(),
    );
  }

  static Map<String, dynamic> _parseData(dynamic raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return {};
  }
}

class UserPlaylist {
  final int id;
  final String name;
  final String description;
  final String? createdAt;

  UserPlaylist({
    required this.id,
    required this.name,
    required this.description,
    this.createdAt,
  });

  factory UserPlaylist.fromJson(Map<String, dynamic> json) {
    return UserPlaylist(
      id: json['id'] is int
          ? json['id']
          : int.tryParse(json['id']?.toString() ?? '') ?? 0,
      name: json['name']?.toString() ?? 'Playlist',
      description: json['description']?.toString() ?? '',
      createdAt: json['created_at']?.toString(),
    );
  }
}

class PlaylistTrackRow {
  final int id;
  final String trackId;
  final Map<String, dynamic> data;

  PlaylistTrackRow({
    required this.id,
    required this.trackId,
    required this.data,
  });

  factory PlaylistTrackRow.fromJson(Map<String, dynamic> json) {
    return PlaylistTrackRow(
      id: json['id'] is int
          ? json['id']
          : int.tryParse(json['id']?.toString() ?? '') ?? 0,
      trackId: json['track_id']?.toString() ?? '',
      data: FavoriteRow._parseData(json['data']),
    );
  }
}