import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class SupabaseService {
  static final SupabaseService _instance = SupabaseService._internal();
  late final SupabaseClient client;
  RealtimeChannel? _messagesChannel;

  factory SupabaseService() {
    return _instance;
  }

  SupabaseService._internal();

  Future<void> initialize() async {
    try {
      await Supabase.initialize(
        url: 'https://ubumkdjchrzlcifiqojf.supabase.co',
        anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVidW1rZGpjaHJ6bGNpZmlxb2pmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDMwNzYyNzAsImV4cCI6MjA1ODY1MjI3MH0.NQwK6CnEzaI520taRJwcQlPwbdiy1QTAwLvQU5hXWmg',
        debug: true,
      );
      client = Supabase.instance.client;
      print('Supabase initialized successfully');
      
      // Initialize realtime subscription if user is logged in
      if (currentUser != null) {
        _subscribeToMessages();
      }
    } catch (e) {
      print('Error initializing Supabase: $e');
      rethrow;
    }
  }

  // Authentication methods
  Future<AuthResponse> signUp(String email, String password) async {
    try {
      await Future.delayed(const Duration(seconds: 1));
      
      final response = await client.auth.signUp(
        email: email,
        password: password,
      );
      
      return response;
    } catch (e) {
      print('Sign up error: $e');
      if (e.toString().contains('429')) {
        throw Exception('Too many requests. Please try again later.');
      }
      rethrow;
    }
  }

  Future<AuthResponse> signIn(String email, String password) async {
    final response = await client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    
    // Initialize realtime subscription after successful login
    if (response.user != null) {
      _subscribeToMessages();
    }
    
    return response;
  }

  Future<void> signOut() async {
    _unsubscribeFromMessages();
    await client.auth.signOut();
  }

  // User methods
  User? get currentUser => client.auth.currentUser;

  // Chat methods
  Future<List<Map<String, dynamic>>> getUsers() async {
    try {
      final response = await client
          .from('profiles')
          .select()
          .neq('id', currentUser?.id ?? '');
      
      print('Fetched users: ${response.length}');
      return response;
    } catch (e) {
      print('Error fetching users: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getMessages(String otherUserId) async {
    final response = await client
        .from('messages')
        .select()
        .or('sender_id.eq.${currentUser!.id},receiver_id.eq.${currentUser!.id}')
        .or('sender_id.eq.$otherUserId,receiver_id.eq.$otherUserId')
        .order('created_at');
    
    // Mark messages as read
    await client
        .from('messages')
        .update({'read': true})
        .eq('sender_id', otherUserId)
        .eq('receiver_id', currentUser!.id)
        .eq('read', false);
    
    return response;
  }

  Future<Map<String, dynamic>> sendMessage(String receiverId, String content) async {
    // Insert message into database
    final response = await client.from('messages').insert({
      'sender_id': currentUser!.id,
      'receiver_id': receiverId,
      'content': content,
      'created_at': DateTime.now().toIso8601String(),
      'read': false,
    }).select().single();
    
    return response;
  }
  
  // DeepSeek AI chat method
  Future<String> chatWithAI(String message) async {
    try {
      final apiKey = "sk-141a848045c946ee845fb00be0b8cfb8";
      final url = Uri.parse('https://api.deepseek.com/v1/chat/completions');
      
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': 'deepseek-chat',
          'messages': [
            {'role': 'system', 'content': 'You are a helpful assistant.'},
            {'role': 'user', 'content': message}
          ],
          'temperature': 0.7,
        }),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['choices'][0]['message']['content'];
      } else {
        print('Error from DeepSeek API: ${response.statusCode} - ${response.body}');
        
        // If insufficient balance, use a fallback response
        if (response.statusCode == 402) {
          return _generateFallbackResponse(message);
        }
        
        return "Sorry, I couldn't process your request at the moment. Status: ${response.statusCode}";
      }
    } catch (e) {
      print('Error chatting with AI: $e');
      return "Sorry, there was an error connecting to the AI service: $e";
    }
  }
  
  // Fallback response generator when API is unavailable
  String _generateFallbackResponse(String message) {
    // Simple keyword-based responses
    message = message.toLowerCase();
    
    if (message.contains('hello') || message.contains('hi ') || message.contains('hey')) {
      return "Hello! How can I help you today?";
    } else if (message.contains('how are you')) {
      return "I'm doing well, thank you for asking! How can I assist you?";
    } else if (message.contains('thank')) {
      return "You're welcome! Feel free to ask if you need anything else.";
    } else if (message.contains('help')) {
      return "I'd be happy to help! Please let me know what you need assistance with.";
    } else if (message.contains('weather')) {
      return "I'm sorry, I don't have access to real-time weather data. You might want to check a weather app or website for that information.";
    } else if (message.contains('name')) {
      return "I'm DeepSeek AI, your virtual assistant.";
    } else if (message.contains('joke')) {
      return "Why don't scientists trust atoms? Because they make up everything!";
    } else if (message.contains('time')) {
      return "I don't have access to the current time. You can check your device's clock for that information.";
    } else {
      return "I understand you're asking about '${message.substring(0, message.length > 20 ? 20 : message.length)}...'. Currently, I'm operating in offline mode due to API limitations. Please try again later when the service is available.";
    }
  }
  
  void _subscribeToMessages() {
    // Unsubscribe from any existing channel
    _unsubscribeFromMessages();
    
    // Subscribe to messages table changes
    _messagesChannel = client
        .channel('public:messages')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'receiver_id',
            value: currentUser?.id ?? '',
          ),
          callback: (payload) {
            // Handle new message
            if (_messageListener != null) {
              final newMessage = payload.newRecord;
              _messageListener!(newMessage);
            }
          },
        )
        .subscribe();
    
    print('Subscribed to messages channel');
  }

  void _unsubscribeFromMessages() {
    _messagesChannel?.unsubscribe();
    _messagesChannel = null;
    print('Unsubscribed from messages channel');
  }

  // Message listener callback
  Function(Map<String, dynamic>)? _messageListener;

  void listenForMessages(Function(Map<String, dynamic>) onMessage) {
    _messageListener = onMessage;
  }

  Future<void> createProfile(String userId, String email, {String? username}) async {
    await client.from('profiles').insert({
      'id': userId,
      'email': email,
      'username': username ?? email.split('@')[0],
      'created_at': DateTime.now().toIso8601String(),
    });
  }
}