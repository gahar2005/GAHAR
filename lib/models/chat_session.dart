// ─── Chat Session Model ───────────────────────────────────────────────────────
class SavedChatMessage {
  final String text;
  final bool isUser;
  final bool isAi;
  final String? assistantMode;

  SavedChatMessage({
    required this.text,
    required this.isUser,
    this.isAi = false,
    this.assistantMode,
  });

  Map<String, dynamic> toJson() => {
        'text': text,
        'isUser': isUser,
        'isAi': isAi,
        'assistantMode': assistantMode,
      };

  factory SavedChatMessage.fromJson(Map<String, dynamic> json) =>
      SavedChatMessage(
        text: json['text'] as String,
        isUser: json['isUser'] as bool,
        isAi: json['isAi'] as bool? ?? false,
        assistantMode: json['assistantMode'] as String?,
      );
}

class ChatSession {
  final String id;
  final String title;
  final List<SavedChatMessage> messages;
  final DateTime createdAt;

  ChatSession({
    required this.id,
    required this.title,
    required this.messages,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'messages': messages.map((m) => m.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
      };

  factory ChatSession.fromJson(Map<String, dynamic> json) => ChatSession(
        id: json['id'] as String,
        title: json['title'] as String,
        messages: (json['messages'] as List? ?? [])
            .map((m) => SavedChatMessage.fromJson(m as Map<String, dynamic>))
            .toList(),
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}
